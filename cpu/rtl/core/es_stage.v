`include "riscv_defines.h"
`include "riscv_inst_defines.h"
`include "riscv_csr_defines.h"
`include "riscv_excp_defines.h"

module es_stage (
    // 时钟 & 复位
    input  wire                    clk,
    input  wire                    reset,

    // 全局流水线控制
    input  wire                    core_stall,
    input  wire                    excp_flush,
    input  wire                    pred_flush,

    // 来自译码阶段 ID
    input  wire [`PC_WIDTH-1:0]     id_pc,
    input  wire [`REG_WIDTH-1:0]    id_rs1_data,
    input  wire [`REG_WIDTH-1:0]    id_rs2_data,
    input  wire [`REG_WIDTH-1:0]    id_imm,
    input  wire [4:0]               id_rs1,
    input  wire [4:0]               id_rs2,
    input  wire [4:0]               id_rd,
    input  wire [6:0]               id_opcode,
    input  wire [2:0]               id_funct3,
    input  wire [6:0]               id_funct7,

    // 控制信号
    input  wire                    id_reg_wen,
    input  wire                    id_alu_en,
    input  wire [3:0]               id_alu_op,
    input  wire                    id_mem_en,
    input  wire [1:0]               id_mem_op,
    input  wire                    id_branch_en,
    input  wire                    id_jump_en,

    // CSR 控制
    input  wire                    id_csr_en,
    input  wire [11:0]              id_csr_addr,
    input  wire [2:0]               id_csr_op,

    // 异常信号
    input  wire                    id_excp_en,
    input  wire [3:0]               id_excp_code,
    input  wire [`PC_WIDTH-1:0]     id_excp_pc,
    input  wire                    id_valid,

    // ==================== 数据前递输入（来自 MEM/WB 阶段） ====================
    input  wire [`REG_WIDTH-1:0]    ms_to_es_data,
    input  wire [`REG_WIDTH-1:0]    wb_to_es_data,
    input  wire [4:0]               ms_to_es_rd,
    input  wire [4:0]               wb_to_es_rd,
    input  wire                    ms_to_es_valid,
    input  wire                    wb_to_es_valid,

    // ==================== 输出到 MEM 阶段（适配 VIPT 并行架构） ====================
    output reg  [`PC_WIDTH-1:0]     ex_pc,
    output reg  [`REG_WIDTH-1:0]    ex_va,           // 虚拟地址 → 给 DCache 做 VIPT 索引
    output reg  [`REG_WIDTH-1:0]    ex_alu_result,   // ALU 结果
    output reg  [`REG_WIDTH-1:0]    ex_rs2_data,     // 存储数据
    output reg  [4:0]               ex_rd,
    output reg  [2:0]               ex_funct3,

    // 控制信号
    output reg                     ex_reg_wen,
    output reg                     ex_mem_en,
    output reg  [1:0]               ex_mem_op,
    output reg                     ex_csr_en,
    output reg  [11:0]              ex_csr_addr,
    output reg  [2:0]               ex_csr_op,
    output reg  [`REG_WIDTH-1:0]    ex_csr_wdata,

    // 分支/跳转结果
    output reg                     ex_branch_taken,
    output reg  [`PC_WIDTH-1:0]     ex_branch_target,
    output reg                     ex_jump_taken,
    output reg  [`PC_WIDTH-1:0]     ex_jump_target,

    // 异常输出
    output reg                     ex_excp_en,
    output reg  [3:0]               ex_excp_code,
    output reg  [`PC_WIDTH-1:0]     ex_excp_pc,
    output reg                     ex_valid
);

// ====================== ALU 操作定义 ======================
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

// ====================== 内部信号 ======================
reg [`REG_WIDTH-1:0] alu_a;
reg [`REG_WIDTH-1:0] alu_b;
reg [`REG_WIDTH-1:0] alu_out;
reg branch_cond;

reg [`REG_WIDTH-1:0] va_temp; // 访存虚拟地址

// 前递后的操作数
wire [`REG_WIDTH-1:0] fw_rs1_data;
wire [`REG_WIDTH-1:0] fw_rs2_data;

// ====================== 数据前递逻辑 ======================
assign fw_rs1_data = (id_rs1 != 5'd0 && ms_to_es_valid && id_rs1 == ms_to_es_rd) ? ms_to_es_data :
                    (id_rs1 != 5'd0 && wb_to_es_valid && id_rs1 == wb_to_es_rd) ? wb_to_es_data : id_rs1_data;

assign fw_rs2_data = (id_rs2 != 5'd0 && ms_to_es_valid && id_rs2 == ms_to_es_rd) ? ms_to_es_data :
                    (id_rs2 != 5'd0 && wb_to_es_valid && id_rs2 == wb_to_es_rd) ? wb_to_es_data : id_rs2_data;

// ====================== 访存指令：计算虚拟地址 VA（给 MEM 阶段 VIPT 使用） ======================
always @(*) begin
    va_temp = 32'b0;
    if (id_mem_en) begin
        va_temp = fw_rs1_data + id_imm;
    end
end

// ====================== ALU 操作数选择 ======================
always @(*) begin
    alu_a = 32'b0;
    alu_b = 32'b0;

    case (id_alu_op)
        ALU_OP_LUI: begin
            alu_a = 32'b0;
            alu_b = id_imm;
        end
        ALU_OP_AUIPC: begin
            alu_a = id_pc;
            alu_b = id_imm;
        end
        ALU_OP_JAL, ALU_OP_JALR: begin
            alu_a = id_pc;
            alu_b = 32'd4;
        end
        ALU_OP_PASS_RS1: begin
            alu_a = fw_rs1_data;
            alu_b = 32'b0;
        end
        ALU_OP_PASS_IMM: begin
            alu_a = id_imm;
            alu_b = 32'b0;
        end
        default: begin
            alu_a = fw_rs1_data;
            alu_b = (id_alu_op == ALU_OP_SUB) ? (~fw_rs2_data + 1'b1) : fw_rs2_data;
        end
    endcase
end

// ====================== ALU 运算核心 ======================
always @(*) begin
    alu_out = 32'b0;
    case (id_alu_op)
        ALU_OP_ADD, ALU_OP_SUB: alu_out = alu_a + alu_b;
        ALU_OP_SLL: alu_out = alu_a << alu_b[4:0];
        ALU_OP_SLT: alu_out = ($signed(alu_a) < $signed(alu_b)) ? 32'd1 : 32'd0;
        ALU_OP_SLTU: alu_out = (alu_a < alu_b) ? 32'd1 : 32'd0;
        ALU_OP_XOR: alu_out = alu_a ^ alu_b;
        ALU_OP_SRL: alu_out = alu_a >> alu_b[4:0];
        ALU_OP_SRA: alu_out = $signed(alu_a) >>> alu_b[4:0];
        ALU_OP_OR: alu_out = alu_a | alu_b;
        ALU_OP_AND: alu_out = alu_a & alu_b;
        ALU_OP_LUI: alu_out = alu_b;
        ALU_OP_AUIPC: alu_out = alu_a + alu_b;
        ALU_OP_JAL, ALU_OP_JALR: alu_out = alu_a + alu_b;
        ALU_OP_PASS_RS1: alu_out = alu_a;
        ALU_OP_PASS_IMM: alu_out = alu_a;
        default: alu_out = 32'b0;
    endcase
end

// ====================== 分支判断逻辑 ======================
always @(*) begin
    branch_cond = 1'b0;
    if (id_branch_en) begin
        case (id_funct3)
            3'b000: branch_cond = (fw_rs1_data == fw_rs2_data);
            3'b001: branch_cond = (fw_rs1_data != fw_rs2_data);
            3'b100: branch_cond = ($signed(fw_rs1_data) < $signed(fw_rs2_data));
            3'b101: branch_cond = ($signed(fw_rs1_data) >= $signed(fw_rs2_data));
            3'b110: branch_cond = (fw_rs1_data < fw_rs2_data);
            3'b111: branch_cond = (fw_rs1_data >= fw_rs2_data);
            default: branch_cond = 1'b0;
        endcase
    end
end

// ====================== 分支/跳转目标地址 ======================
always @(*) begin
    ex_branch_taken  = 1'b0;
    ex_branch_target = 32'b0;
    ex_jump_taken    = 1'b0;
    ex_jump_target   = 32'b0;

    if (id_branch_en && branch_cond) begin
        ex_branch_taken  = 1'b1;
        ex_branch_target = id_pc + id_imm;
    end

    if (id_jump_en) begin
        ex_jump_taken = 1'b1;
        if (id_alu_op == ALU_OP_JALR)
            ex_jump_target = (fw_rs1_data + id_imm) & ~32'b1;
        else
            ex_jump_target = id_pc + id_imm;
    end
end

// ====================== 输出到 MEM 阶段 ======================
always @(posedge clk or posedge reset) begin
    if (reset) begin
        ex_pc         <= 32'h80000000;
        ex_va         <= 32'b0;
        ex_alu_result <= 32'b0;
        ex_rs2_data   <= 32'b0;
        ex_rd         <= 5'b0;
        ex_funct3     <= 3'b0;

        ex_reg_wen    <= 1'b0;
        ex_mem_en     <= 1'b0;
        ex_mem_op     <= 2'b0;
        ex_csr_en     <= 1'b0;
        ex_csr_addr   <= 12'b0;
        ex_csr_op     <= 3'b0;
        ex_csr_wdata  <= 32'b0;

        ex_excp_en    <= 1'b0;
        ex_excp_code  <= 4'b0;
        ex_excp_pc    <= 32'b0;
        ex_valid      <= 1'b0;
    end
    else if (excp_flush || pred_flush) begin
        ex_pc         <= 32'h80000000;
        ex_va         <= 32'b0;
        ex_alu_result <= 32'b0;
        ex_rs2_data   <= 32'b0;
        ex_rd         <= 5'b0;
        ex_funct3     <= 3'b0;

        ex_reg_wen    <= 1'b0;
        ex_mem_en     <= 1'b0;
        ex_mem_op     <= 2'b0;
        ex_csr_en     <= 1'b0;
        ex_csr_addr   <= 12'b0;
        ex_csr_op     <= 3'b0;
        ex_csr_wdata  <= 32'b0;

        ex_excp_en    <= 1'b0;
        ex_excp_code  <= 4'b0;
        ex_excp_pc    <= 32'b0;
        ex_valid      <= 1'b0;
    end
    else if (core_stall) begin
        ex_pc         <= ex_pc;
        ex_va         <= ex_va;
        ex_alu_result <= ex_alu_result;
        ex_rs2_data   <= ex_rs2_data;
        ex_rd         <= ex_rd;
        ex_funct3     <= ex_funct3;

        ex_reg_wen    <= ex_reg_wen;
        ex_mem_en     <= ex_mem_en;
        ex_mem_op     <= ex_mem_op;
        ex_csr_en     <= ex_csr_en;
        ex_csr_addr   <= ex_csr_addr;
        ex_csr_op     <= ex_csr_op;
        ex_csr_wdata  <= ex_csr_wdata;

        ex_excp_en    <= ex_excp_en;
        ex_excp_code  <= ex_excp_code;
        ex_excp_pc    <= ex_excp_pc;
        ex_valid      <= ex_valid;
    end
    else begin
        // 正常流程：VA 交给 MEM 做 VIPT，ALU 结果正常传递
        ex_pc         <= id_pc;
        ex_va         <= va_temp;          // 虚拟地址 → MEM 阶段
        ex_alu_result <= alu_out;          // ALU 结果
        ex_rs2_data   <= fw_rs2_data;
        ex_rd         <= id_rd;
        ex_funct3     <= id_funct3;

        ex_reg_wen    <= id_reg_wen;
        ex_mem_en     <= id_mem_en;
        ex_mem_op     <= id_mem_op;
        ex_csr_en     <= id_csr_en;
        ex_csr_addr   <= id_csr_addr;
        ex_csr_op     <= id_csr_op;
        ex_csr_wdata  <= fw_rs1_data;

        // 异常仅来自 ID，MMU 已迁移到 MEM
        ex_excp_en    <= id_excp_en;
        ex_excp_code  <= id_excp_code;
        ex_excp_pc    <= id_excp_pc;
        ex_valid      <= id_valid;
    end
end

endmodule