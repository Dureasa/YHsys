`include "riscv_defines.h"
`include "riscv_inst_defines.h"
`include "riscv_csr_defines.h"
`include "riscv_excp_defines.h"

module id_stage (
    // 时钟/复位
    input  wire                 clk              ,
    input  wire                 reset            ,

    // 与取指阶段（IF）对接
    input  wire [`PC_WIDTH-1:0]  if_pc            ,
    input  wire [`INST_WIDTH-1:0] if_inst        ,
    input  wire                 if_valid         ,

    // 全局流水线控制
    input  wire                 core_stall       ,
    input  wire                 excp_flush       ,
    input  wire                 pred_flush       ,

    // 与寄存器堆对接
    input  wire [`REG_WIDTH-1:0] regfile_rs1_data ,
    input  wire [`REG_WIDTH-1:0] regfile_rs2_data ,

    // 数据前递
    input  wire                  es_to_id_valid ,
    input  wire                  ms_to_id_valid ,
    input  wire [4:0]            es_to_id_rd    ,
    input  wire [4:0]            ms_to_id_rd    ,
    input  wire [`REG_WIDTH-1:0] es_to_id_data  ,
    input  wire [`REG_WIDTH-1:0] ms_to_id_data  ,

    // ==================== 输出到执行阶段 ====================
    output reg  [`PC_WIDTH-1:0]  id_pc            ,
    output reg  [`REG_WIDTH-1:0]  id_rs1_data      ,
    output reg  [`REG_WIDTH-1:0]  id_rs2_data      ,
    output reg  [`REG_WIDTH-1:0]  id_imm           ,
    output reg  [4:0]            id_rs1           ,
    output reg  [4:0]            id_rs2           ,
    output reg  [4:0]            id_rd            ,
    output reg  [6:0]            id_opcode        ,
    output reg  [2:0]            id_funct3        ,
    output reg  [6:0]            id_funct7        ,

    // 控制信号
    output reg                  id_reg_wen       ,
    output reg                  id_alu_en        ,
    output reg  [3:0]            id_alu_op        ,
    output reg                  id_mem_en        ,
    output reg  [1:0]            id_mem_op        ,
    output reg                  id_branch_en     ,
    output reg                  id_jump_en       ,

    // CSR 控制
    output reg                  id_csr_en        ,
    output reg  [11:0]           id_csr_addr      ,
    output reg  [2:0]            id_csr_op        ,

    // ==================== 输出异常到中断单元 ====================
    output reg                  id_excp_en       ,
    output reg  [3:0]            id_excp_code     ,
    output reg  [`PC_WIDTH-1:0]  id_excp_pc       ,

    // 输出有效
    output reg                  id_valid
);

// ====================== 内部参数定义 ======================
// ALU 操作
localparam ALU_OP_ADD      = 4'b0000;
localparam ALU_OP_SUB      = 4'b0001;
localparam ALU_OP_SLL      = 4'b0010;
localparam ALU_OP_SLT      = 4'b0011;
localparam ALU_OP_SLTU     = 4'b0100;
localparam ALU_OP_XOR      = 4'b0101;
localparam ALU_OP_SRL      = 4'b0110;
localparam ALU_OP_SRA      = 4'b0111;
localparam ALU_OP_OR       = 4'b1000;
localparam ALU_OP_AND      = 4'b1001;
localparam ALU_OP_LUI      = 4'b1010;
localparam ALU_OP_AUIPC    = 4'b1011;
localparam ALU_OP_JAL      = 4'b1100;
localparam ALU_OP_JALR     = 4'b1101;
localparam ALU_OP_PASS_RS1 = 4'b1110;
localparam ALU_OP_PASS_IMM = 4'b1111;

// 存储器操作
localparam MEM_OP_NONE     = 2'b00;
localparam MEM_OP_LOAD_B   = 2'b01;
localparam MEM_OP_LOAD_H   = 2'b10;
localparam MEM_OP_LOAD_W   = 2'b11;
localparam MEM_OP_STORE_B  = 2'b01;
localparam MEM_OP_STORE_H  = 2'b10;
localparam MEM_OP_STORE_W  = 2'b11;

// ====================== 内部信号 ======================
reg [`INST_WIDTH-1:0] id_inst;
reg                   illegal_inst;
reg [`REG_WIDTH-1:0]  imm_temp;

// 数据前递处理
wire [`REG_WIDTH-1:0] rs1_data;
wire [`REG_WIDTH-1:0] rs2_data;
wire        rs1_forward_ms;
wire        rs1_forward_es;
wire        rs2_forward_ms;
wire        rs2_forward_es;

assign rs1_forward_ms = (id_rs1 != 5'b0) && ms_to_id_valid && (id_rs1 == ms_to_id_rd);
assign rs1_forward_es = (id_rs1 != 5'b0) && es_to_id_valid && (id_rs1 == es_to_id_rd);
assign rs2_forward_ms = (id_rs2 != 5'b0) && ms_to_id_valid && (id_rs2 == ms_to_id_rd);
assign rs2_forward_es = (id_rs2 != 5'b0) && es_to_id_valid && (id_rs2 == es_to_id_rd);

assign rs1_data = rs1_forward_es ? es_to_id_data :
                  rs1_forward_ms ? ms_to_id_data :
                  (id_rs1 == 5'b0) ? 32'b0 : regfile_rs1_data;

assign rs2_data = rs2_forward_es ? es_to_id_data :
                  rs2_forward_ms ? ms_to_id_data :
                  (id_rs2 == 5'b0) ? 32'b0 : regfile_rs2_data;

// ====================== 指令锁存 ======================
always @(posedge clk or posedge reset) begin
    if (reset) begin
        id_pc        <= 32'h80000000;
        id_inst      <= 32'b0;
        id_valid     <= 1'b0;
        id_excp_en   <= 1'b0;
        id_excp_code <= 4'b0;
        id_excp_pc   <= 32'b0;
    end
    else if (excp_flush || pred_flush) begin
        id_pc        <= 32'h80000000;
        id_inst      <= 32'b0;
        id_valid     <= 1'b0;
        id_excp_en   <= 1'b0;
        id_excp_code <= 4'b0;
        id_excp_pc   <= 32'b0;
    end
    else if (core_stall) begin
        id_valid     <= 1'b0;
        id_excp_en   <= 1'b0;
    end
    else if (if_valid) begin
        id_pc        <= if_pc;
        id_inst      <= if_inst;
        id_valid     <= 1'b1;
        id_excp_pc   <= if_pc;
        id_excp_en   <= 1'b0;
    end
    else begin
        id_pc        <= 32'h80000000;
        id_inst      <= 32'b0;
        id_valid     <= 1'b0;
        id_excp_en   <= 1'b0;
    end
end

// ====================== 提取 rs1 / rs2 ======================
always @(*) begin
    id_rs1 = 5'b00000;
    id_rs2 = 5'b00000;
    case (id_inst[6:0])
        `OPCODE_RTYPE, `OPCODE_STORE, `OPCODE_BRANCH: begin
            id_rs1 = id_inst[19:15];
            id_rs2 = id_inst[24:20];
        end
        `OPCODE_ITYPE, `OPCODE_LOAD, `OPCODE_JALR, `OPCODE_CSR: begin
            id_rs1 = id_inst[19:15];
            id_rs2 = 5'b00000;
        end
        default: begin
            id_rs1 = 5'b00000;
            id_rs2 = 5'b00000;
        end
    endcase
end

// ====================== 提取 rd ======================
always @(*) begin
    id_rd = 5'b00000;
    case (id_inst[6:0])
        `OPCODE_RTYPE, `OPCODE_ITYPE, `OPCODE_LOAD,
        `OPCODE_LUI, `OPCODE_AUIPC, `OPCODE_JAL, `OPCODE_JALR:
            id_rd = id_inst[11:7];
        `OPCODE_CSR: begin
            if(id_inst[14:12] != 3'b000)
                id_rd = id_inst[11:7];
            else
                id_rd = 5'b00000;
        end
        default: id_rd = 5'b00000;
    endcase
end

// ====================== 立即数生成 ======================
always @(*) begin
    imm_temp = 32'b0;
    case (id_inst[6:0])
        `OPCODE_ITYPE, `OPCODE_LOAD, `OPCODE_JALR:
            imm_temp = {{20{id_inst[31]}}, id_inst[31:20]};
        `OPCODE_STORE:
            imm_temp = {{20{id_inst[31]}}, id_inst[31:25], id_inst[11:7]};
        `OPCODE_BRANCH:
            imm_temp = {{19{id_inst[31]}}, id_inst[31], id_inst[7], id_inst[30:25], id_inst[11:8], 1'b0};
        `OPCODE_LUI, `OPCODE_AUIPC:
            imm_temp = {id_inst[31:12], 12'b0};
        `OPCODE_JAL:
            imm_temp = {{11{id_inst[31]}}, id_inst[31], id_inst[19:12], id_inst[20], id_inst[30:21], 1'b0};
        `OPCODE_CSR:
            imm_temp = {20'b0, id_inst[31:20]};
        default:
            imm_temp = 32'b0;
    endcase
    id_imm = imm_temp;
end

// ====================== 指令译码 & 控制信号 ======================
always @(*) begin
    id_opcode    = 7'b0;
    id_funct3    = 3'b0;
    id_funct7    = 7'b0;
    id_reg_wen   = 1'b0;
    id_alu_en    = 1'b0;
    id_alu_op    = ALU_OP_ADD;
    id_mem_en    = 1'b0;
    id_mem_op    = MEM_OP_NONE;
    id_branch_en = 1'b0;
    id_jump_en   = 1'b0;
    id_csr_en    = 1'b0;
    id_csr_addr  = 12'b0;
    id_csr_op    = `CSR_OP_READ;
    illegal_inst = 1'b0;

    case (id_inst[6:0])
        // R 型
        `OPCODE_RTYPE: begin
            id_opcode  = `OPCODE_RTYPE;
            id_funct3  = id_inst[14:12];
            id_funct7  = id_inst[31:25];
            id_alu_en  = 1'b1;
            id_reg_wen = (id_rd != 5'b0);
            case (id_funct3)
                3'b000: id_alu_op = (id_funct7 == 7'b0100000) ? ALU_OP_SUB : ALU_OP_ADD;
                3'b001: id_alu_op = ALU_OP_SLL;
                3'b010: id_alu_op = ALU_OP_SLT;
                3'b011: id_alu_op = ALU_OP_SLTU;
                3'b100: id_alu_op = ALU_OP_XOR;
                3'b101: id_alu_op = (id_funct7 == 7'b0100000) ? ALU_OP_SRA : ALU_OP_SRL;
                3'b110: id_alu_op = ALU_OP_OR;
                3'b111: id_alu_op = ALU_OP_AND;
                default: illegal_inst = 1'b1;
            endcase
        end

        // I 型
        `OPCODE_ITYPE: begin
            id_opcode  = `OPCODE_ITYPE;
            id_funct3  = id_inst[14:12];
            id_alu_en  = 1'b1;
            id_reg_wen = (id_rd != 5'b0);
            case (id_funct3)
                3'b000: id_alu_op = ALU_OP_ADD;
                3'b001: id_alu_op = ALU_OP_SLL;
                3'b010: id_alu_op = ALU_OP_SLT;
                3'b011: id_alu_op = ALU_OP_SLTU;
                3'b100: id_alu_op = ALU_OP_XOR;
                3'b101: id_alu_op = (id_inst[31:25] == 7'b0100000) ? ALU_OP_SRA : ALU_OP_SRL;
                3'b110: id_alu_op = ALU_OP_OR;
                3'b111: id_alu_op = ALU_OP_AND;
                default: illegal_inst = 1'b1;
            endcase
        end

        // 加载
        `OPCODE_LOAD: begin
            id_opcode  = `OPCODE_LOAD;
            id_funct3  = id_inst[14:12];
            id_alu_en  = 1'b1;
            id_alu_op  = ALU_OP_ADD;
            id_mem_en  = 1'b1;
            id_reg_wen = (id_rd != 5'b0);
            case (id_funct3)
                3'b000, 3'b100: id_mem_op = MEM_OP_LOAD_B;
                3'b001, 3'b101: id_mem_op = MEM_OP_LOAD_H;
                3'b010: id_mem_op = MEM_OP_LOAD_W;
                default: illegal_inst = 1'b1;
            endcase
        end

        // 存储
        `OPCODE_STORE: begin
            id_opcode  = `OPCODE_STORE;
            id_funct3  = id_inst[14:12];
            id_alu_en  = 1'b1;
            id_alu_op  = ALU_OP_ADD;
            id_mem_en  = 1'b1;
            id_reg_wen = 1'b0;
            case (id_funct3)
                3'b000: id_mem_op = MEM_OP_STORE_B;
                3'b001: id_mem_op = MEM_OP_STORE_H;
                3'b010: id_mem_op = MEM_OP_STORE_W;
                default: illegal_inst = 1'b1;
            endcase
        end

        // 分支
        `OPCODE_BRANCH: begin
            id_opcode    = `OPCODE_BRANCH;
            id_funct3    = id_inst[14:12];
            id_alu_en    = 1'b1;
            id_alu_op    = ALU_OP_SUB;
            id_branch_en = 1'b1;
            id_reg_wen   = 1'b0;
        end

        // LUI
        `OPCODE_LUI: begin
            id_opcode  = `OPCODE_LUI;
            id_alu_en  = 1'b1;
            id_alu_op  = ALU_OP_LUI;
            id_reg_wen = (id_rd != 5'b0);
        end

        // AUIPC
        `OPCODE_AUIPC: begin
            id_opcode  = `OPCODE_AUIPC;
            id_alu_en  = 1'b1;
            id_alu_op  = ALU_OP_AUIPC;
            id_reg_wen = (id_rd != 5'b0);
        end

        // JAL
        `OPCODE_JAL: begin
            id_opcode  = `OPCODE_JAL;
            id_alu_en  = 1'b1;
            id_alu_op  = ALU_OP_JAL;
            id_jump_en = 1'b1;
            id_reg_wen = (id_rd != 5'b0);
        end

        // JALR
        `OPCODE_JALR: begin
            id_opcode  = `OPCODE_JALR;
            id_funct3  = 3'b000;
            id_alu_en  = 1'b1;
            id_alu_op  = ALU_OP_JALR;
            id_jump_en = 1'b1;
            id_reg_wen = (id_rd != 5'b0);
        end

        // CSR
        `OPCODE_CSR: begin
            id_opcode    = `OPCODE_CSR;
            id_funct3    = id_inst[14:12];
            id_csr_en    = 1'b1;
            id_csr_addr  = id_inst[31:20];
            id_reg_wen   = (id_rd != 5'b0);
            case (id_funct3)
                3'b001: id_csr_op = `CSR_OP_WRITE;
                3'b010: id_csr_op = `CSR_OP_SET;
                3'b011: id_csr_op = `CSR_OP_CLEAR;
                3'b101: id_csr_op = `CSR_OP_WRITE;
                3'b110: id_csr_op = `CSR_OP_SET;
                3'b111: id_csr_op = `CSR_OP_CLEAR;
                default: illegal_inst = 1'b1;
            endcase
        end

        default: illegal_inst = 1'b1;
    endcase

    // 异常生成
    if (id_valid && illegal_inst) begin
        id_excp_en   = 1'b1;
        id_excp_code = `EXC_ILLEGAL_INST;
    end
    else begin
        id_excp_en   = 1'b0;
        id_excp_code = 4'b0;
    end
end

// ====================== 输出数据 ======================
always @(posedge clk or posedge reset) begin
    if (reset) begin
        id_rs1_data <= 32'b0;
        id_rs2_data <= 32'b0;
    end
    else if (core_stall || excp_flush || pred_flush) begin
        id_rs1_data <= 32'b0;
        id_rs2_data <= 32'b0;
    end
    else if (id_valid) begin
        id_rs1_data <= (id_rs1 == 5'b0) ? 32'b0 : rs1_data;
        id_rs2_data <= (id_rs2 == 5'b0) ? 32'b0 : rs2_data;
    end
    else begin
        id_rs1_data <= 32'b0;
        id_rs2_data <= 32'b0;
    end
end

endmodule