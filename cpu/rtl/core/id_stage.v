`include "riscv_defines.h"
`include "riscv_inst_defines.h"

module id_stage (
    // 时钟/复位
    input  wire                 clk              ,  // 系统时钟
    input  wire                 reset            ,  // 异步复位（高有效）
    // 流水线控制
    input  wire                 es_allowin       ,  // 执行阶段就绪信号
    output wire                 id_allowin       ,  // 译码阶段就绪信号
    output wire                 id_to_es_valid   ,  // 译码到执行的有效信号
    output wire [`ID_TO_ES_BUS_WD-1:0] id_to_es_bus,  // 译码到执行的总线
    // 来自取指阶段
    input  wire                 if_to_id_valid   ,  // 取指到译码的有效信号
    input  wire [`IF_TO_ID_BUS_WD-1:0] if_to_id_bus,  // 取指到译码的总线
    // 通用寄存器堆接口
    output wire [4:0]           rf_raddr1        ,  // 读寄存器1地址
    output wire [4:0]           rf_raddr2        ,  // 读寄存器2地址
    input  wire [31:0]          rf_rdata1        ,  // 读寄存器1数据
    input  wire [31:0]          rf_rdata2        ,  // 读寄存器2数据
    // 数据前递（来自执行/存储阶段）
    input  wire [`MS_TO_DS_FORWARD_BUS-1:0] ms_to_ds_forward_bus, // 存储到译码前递
    input  wire                 ms_to_ds_valid   ,  // 存储前递有效
    input  wire [`ES_TO_DS_FORWARD_BUS-1:0] es_to_ds_forward_bus, // 执行到译码前递
    input  wire                 es_to_ds_valid   ,  // 执行前递有效
    // 分支预测反馈
    output wire [31:0]          id_pc            ,  // 当前PC（给分支预测器）
    output wire                 id_branch_inst   ,  // 分支指令标记
    output wire [31:0]          id_branch_target ,  // 分支目标地址
    // 异常/冲刷信号
    input  wire                 excp_flush       ,  // 异常冲刷
    input  wire                 branch_flush     ,  // 分支预测错误冲刷
    // 暂停信号
    output wire                 id_stall         ,  // 译码阶段暂停
    input  wire                 core_stall       ,  // 全局核心暂停
    // CSR接口（基础支持）
    input  wire [31:0]          csr_rdata        ,  // CSR读数据
    output wire [11:0]          csr_addr         ,  // CSR地址
    output wire                 csr_we           ,  // CSR写使能
    input  wire                 csr_stall        ,  // CSR访问暂停
    // 分支预测器接口
    input  wire                 bp_taken         ,  // 分支预测跳转
    input  wire [31:0]          bp_target_pc     ,  // 分支预测目标PC
    // 测试接口（仅核心信号）
    output wire [31:0]          id_test_data1    ,  // 测试用寄存器1数据
    output wire [31:0]          id_test_data2    ,  // 测试用寄存器2数据
    output wire [4:0]           id_test_rd       ,  // 测试用目标寄存器
    output wire                 id_test_valid    ,  // 测试有效标记
    // 核心输出（供调试/验证）
    output wire [31:0]          id_inst          ,  // 当前译码指令
    output wire [31:0]          id_imm           ,  // 扩展后的立即数
    output wire                 id_illegal_inst  ,  // 非法指令标记
    output wire                 id_excp          ,  // 异常标记
    output wire [9:0]           id_excp_num      ,  // 异常号
    output wire                 id_load_inst     ,  // 加载指令标记
    output wire                 id_store_inst    ,  // 存储指令标记
    output wire                 id_br_inst       ,  // 分支指令标记
    output wire                 id_gr_we         ,  // 通用寄存器写使能
    output wire [4:0]           id_dest          // 目标寄存器地址
);

// ====================== 内部寄存器/连线定义 ======================
reg         id_valid;                  // 译码阶段有效标记
wire        id_ready_go;               // 译码阶段就绪（可发送到执行阶段）
wire        flush_sign;                // 流水线冲刷总信号

// 取指阶段传入数据拆解
reg [31:0]  if_pc_r;                   // 锁存的PC
reg [31:0]  if_inst_r;                 // 锁存的指令
reg         if_inst_valid_r;           // 锁存的指令有效标记

// 指令字段拆解
wire [6:0]  opcode;                    // 操作码 [6:0]
wire [2:0]  funct3;                    // 功能码3 [14:12]
wire [6:0]  funct7;                    // 功能码7 [31:25]
wire [4:0]  rs1;                       // 源寄存器1 [19:15]
wire [4:0]  rs2;                       // 源寄存器2 [24:20]
wire [4:0]  rd;                        // 目标寄存器 [11:7]

// 立即数扩展
wire [31:0] imm_i;                     // I类型立即数
wire [31:0] imm_s;                     // S类型立即数
wire [31:0] imm_b;                     // B类型立即数
wire [31:0] imm_u;                     // U类型立即数
wire [31:0] imm_j;                     // J类型立即数
reg [31:0]  imm;                       // 最终扩展后的立即数

// 指令类型标记
reg         rtype_inst;                // R类型指令
reg         itype_inst;                // I类型指令
reg         stype_inst;                // S类型指令
reg         btype_inst;                // B类型指令
reg         utype_inst;                // U类型指令
reg         jtype_inst;                // J类型指令
reg         csr_inst;                  // CSR指令

// 控制信号
reg         gr_we;                     // 通用寄存器写使能
reg         alu_src1;                  // ALU源1选择：0=rs1，1=PC
reg         alu_src2;                  // ALU源2选择：0=rs2，1=立即数
reg [4:0]   alu_op;                    // ALU操作类型
reg         load_inst;                 // 加载指令标记
reg         store_inst;                // 存储指令标记
reg [1:0]   mem_size;                  // 内存访问大小
reg         mem_sign_ext;              // 加载符号扩展
reg         branch_inst;               // 分支指令标记
reg         jump_inst;                 // 跳转指令标记
reg         csr_we_reg;                // CSR写使能（寄存器版）
reg [11:0]  csr_addr_reg;              // CSR地址（寄存器版）
reg         illegal_inst;              // 非法指令标记
reg [9:0]   excp_num;                  // 异常号
reg         excp;                      // 异常标记

// 数据前递处理
wire [31:0] rs1_data;                  // 源寄存器1最终数据（前递+寄存器堆）
wire [31:0] rs2_data;                  // 源寄存器2最终数据（前递+寄存器堆）
wire        rs1_forward_ms;            // rs1从存储阶段前递
wire        rs1_forward_es;            // rs1从执行阶段前递
wire        rs2_forward_ms;            // rs2从存储阶段前递
wire        rs2_forward_es;            // rs2从执行阶段前递

// 分支预测
reg         branch_taken;              // 分支是否跳转（预测）
reg [31:0]  branch_target_pc;          // 分支目标PC

// ====================== 核心逻辑 ======================
// 1. 冲刷信号整合（仅保留核心冲刷）
assign flush_sign = excp_flush | branch_flush;

// 2. 取指阶段数据锁存
always @(posedge clk or posedge reset) begin
    if (reset) begin
        if_pc_r         <= 32'h80000000;
        if_inst_r       <= 32'b0;
        if_inst_valid_r <= 1'b0;
    end else if (id_allowin) begin
        // 拆解取指阶段总线（仅保留核心字段）
        {if_pc_r, if_inst_r, if_inst_valid_r} = if_to_id_bus;
    end
end

// 3. 流水线握手逻辑（核心）
assign id_ready_go    = !core_stall & !csr_stall;
assign id_allowin     = !id_valid | (id_ready_go & es_allowin);
assign id_to_es_valid = id_valid & id_ready_go;

// 译码阶段有效标记更新
always @(posedge clk or posedge reset) begin
    if (reset) begin
        id_valid <= 1'b0;
    end else if (flush_sign) begin
        id_valid <= 1'b0;
    end else if (id_allowin) begin
        id_valid <= if_to_id_valid;
    end
end

// 4. 指令字段拆解（RV32I标准）
assign opcode = if_inst_r[6:0];
assign funct3 = if_inst_r[14:12];
assign funct7 = if_inst_r[31:25];
assign rs1    = if_inst_r[19:15];
assign rs2    = if_inst_r[24:20];
assign rd     = if_inst_r[11:7];

// 5. 立即数扩展（仅保留核心类型）
assign imm_i  = {{20{if_inst_r[31]}}, if_inst_r[31:20]};        // I类型
assign imm_s  = {{20{if_inst_r[31]}}, if_inst_r[31:25], if_inst_r[11:7]}; // S类型
assign imm_b  = {{19{if_inst_r[31]}}, if_inst_r[31], if_inst_r[7], if_inst_r[30:25], if_inst_r[11:8], 1'b0}; // B类型
assign imm_u  = {if_inst_r[31:12], 12'b0};                     // U类型
assign imm_j  = {{11{if_inst_r[31]}}, if_inst_r[31], if_inst_r[19:12], if_inst_r[20], if_inst_r[30:21], 1'b0}; // J类型

// 6. 指令译码核心逻辑（仅保留RV32I基础指令）
always @(*) begin
    // 默认值（防止综合器生成锁存器）
    rtype_inst   = 1'b0;
    itype_inst   = 1'b0;
    stype_inst   = 1'b0;
    btype_inst   = 1'b0;
    utype_inst   = 1'b0;
    jtype_inst   = 1'b0;
    csr_inst     = 1'b0;
    gr_we        = 1'b0;
    alu_src1     = 1'b0;
    alu_src2     = 1'b0;
    alu_op       = 5'b0;
    load_inst    = 1'b0;
    store_inst   = 1'b0;
    mem_size     = 2'b0;
    mem_sign_ext = 1'b0;
    branch_inst  = 1'b0;
    jump_inst    = 1'b0;
    csr_we_reg   = 1'b0;
    csr_addr_reg = 12'b0;
    illegal_inst = 1'b0;
    excp_num     = 10'b0;
    excp         = 1'b0;
    imm          = 32'b0;
    branch_taken = 1'b0;
    branch_target_pc = 32'b0;

    case (opcode)
        // R类型指令（算术逻辑运算）
        `OPCODE_OP: begin
            rtype_inst = 1'b1;
            alu_src1   = 1'b0; // 源1=rs1
            alu_src2   = 1'b0; // 源2=rs2
            gr_we      = 1'b1; // 写通用寄存器
            case (funct3)
                `FUNCT3_ADD_SUB: alu_op = (funct7 == `FUNCT7_SUB) ? `ALU_OP_SUB : `ALU_OP_ADD;
                `FUNCT3_SLL:     alu_op = `ALU_OP_SLL;
                `FUNCT3_SLT:     alu_op = `ALU_OP_SLT;
                `FUNCT3_SLTU:    alu_op = `ALU_OP_SLTU;
                `FUNCT3_XOR:     alu_op = `ALU_OP_XOR;
                `FUNCT3_SRL_SRA: alu_op = (funct7 == `FUNCT7_SRA) ? `ALU_OP_SRA : `ALU_OP_SRL;
                `FUNCT3_OR:      alu_op = `ALU_OP_OR;
                `FUNCT3_AND:     alu_op = `ALU_OP_AND;
                default: begin
                    illegal_inst = 1'b1;
                    excp_num     = `EXCP_ILLEGAL_INST;
                    excp         = 1'b1;
                end
            endcase
        end

        // I类型指令（立即数运算）
        `OPCODE_OP_IMM: begin
            itype_inst = 1'b1;
            alu_src1   = 1'b0; // 源1=rs1
            alu_src2   = 1'b1; // 源2=立即数
            gr_we      = 1'b1; // 写通用寄存器
            imm        = imm_i;
            case (funct3)
                `FUNCT3_ADD_SUB:     alu_op = `ALU_OP_ADD;
                `FUNCT3_SLL:     alu_op = `ALU_OP_SLL;
                `FUNCT3_SLT:     alu_op = `ALU_OP_SLT;
                `FUNCT3_SLTU:    alu_op = `ALU_OP_SLTU;
                `FUNCT3_XOR:     alu_op = `ALU_OP_XOR;
                `FUNCT3_SRL_SRA: alu_op = (funct7 == `FUNCT7_SRA) ? `ALU_OP_SRA : `ALU_OP_SRL;
                `FUNCT3_OR:      alu_op = `ALU_OP_OR;
                `FUNCT3_AND:     alu_op = `ALU_OP_AND;
                default: begin
                    illegal_inst = 1'b1;
                    excp_num     = `EXCP_ILLEGAL_INST;
                    excp         = 1'b1;
                end
            endcase
        end

        // 加载指令（I类型）
        `OPCODE_LOAD: begin
            itype_inst   = 1'b1;
            load_inst    = 1'b1;
            alu_src1     = 1'b0; // 源1=rs1
            alu_src2     = 1'b1; // 源2=立即数
            gr_we        = 1'b1; // 写通用寄存器
            imm          = imm_i;
            alu_op       = `ALU_OP_ADD; // 地址计算：rs1 + imm
            case (funct3)
                `FUNCT3_LB:  begin mem_size=2'b01; mem_sign_ext=1'b1; end
                `FUNCT3_LH:  begin mem_size=2'b10; mem_sign_ext=1'b1; end
                `FUNCT3_LW:  begin mem_size=2'b00; mem_sign_ext=1'b0; end
                `FUNCT3_LBU: begin mem_size=2'b01; mem_sign_ext=1'b0; end
                `FUNCT3_LHU: begin mem_size=2'b10; mem_sign_ext=1'b0; end
                default: begin
                    illegal_inst = 1'b1;
                    excp_num     = `EXCP_ILLEGAL_INST;
                    excp         = 1'b1;
                end
            endcase
        end

        // 存储指令（S类型）
        `OPCODE_STORE: begin
            stype_inst  = 1'b1;
            store_inst  = 1'b1;
            alu_src1    = 1'b0; // 源1=rs1
            alu_src2    = 1'b1; // 源2=立即数
            gr_we       = 1'b0; // 不写通用寄存器
            imm         = imm_s;
            alu_op      = `ALU_OP_ADD; // 地址计算：rs1 + imm
            case (funct3)
                `FUNCT3_SB: mem_size=2'b01;
                `FUNCT3_SH: mem_size=2'b10;
                `FUNCT3_SW: mem_size=2'b00;
                default: begin
                    illegal_inst = 1'b1;
                    excp_num     = `EXCP_ILLEGAL_INST;
                    excp         = 1'b1;
                end
            endcase
        end

        // 分支指令（B类型）
        `OPCODE_BRANCH: begin
            btype_inst   = 1'b1;
            branch_inst  = 1'b1;
            alu_src1     = 1'b0; // 源1=rs1
            alu_src2     = 1'b0; // 源2=rs2
            gr_we        = 1'b0; // 不写通用寄存器
            imm          = imm_b;
            alu_op       = `ALU_OP_BRANCH; // 分支比较
            // 分支预测
            branch_taken = bp_taken;
            branch_target_pc = bp_target_pc;
            // 仅保留合法分支指令
            if (funct3 != `FUNCT3_BEQ  && funct3 != `FUNCT3_BNE  && 
                funct3 != `FUNCT3_BLT  && funct3 != `FUNCT3_BGE  && 
                funct3 != `FUNCT3_BLTU && funct3 != `FUNCT3_BGEU) begin
                illegal_inst = 1'b1;
                excp_num     = `EXCP_ILLEGAL_INST;
                excp         = 1'b1;
            end
        end

        // 跳转指令（JAL，J类型）
        `OPCODE_JAL: begin
            jtype_inst   = 1'b1;
            jump_inst    = 1'b1;
            alu_src1     = 1'b1; // 源1=PC
            alu_src2     = 1'b1; // 源2=立即数
            gr_we        = 1'b1; // 写通用寄存器（返回地址）
            imm          = imm_j;
            alu_op       = `ALU_OP_ADD; // 目标地址：PC + imm
            branch_taken = 1'b1;
            branch_target_pc = if_pc_r + imm_j;
        end

        // 跳转指令（JALR，I类型）
        `OPCODE_JALR: begin
            itype_inst   = 1'b1;
            jump_inst    = 1'b1;
            alu_src1     = 1'b0; // 源1=rs1
            alu_src2     = 1'b1; // 源2=立即数
            gr_we        = 1'b1; // 写通用寄存器（返回地址）
            imm          = imm_i;
            alu_op       = `ALU_OP_ADD; // 目标地址：rs1 + imm
            branch_taken = 1'b1;
            branch_target_pc = (rs1 == 5'b0 ? 32'b0 : rf_rdata1) + imm_i;
        end

        // U类型指令（LUI）
        `OPCODE_LUI: begin
            utype_inst = 1'b1;
            alu_src1   = 1'b0; // 源1=0
            alu_src2   = 1'b1; // 源2=立即数
            gr_we      = 1'b1; // 写通用寄存器
            imm        = imm_u;
            alu_op     = `ALU_OP_OR; // 直接赋值：0 | imm_u
        end

        // U类型指令（AUIPC）
        `OPCODE_AUIPC: begin
            utype_inst = 1'b1;
            alu_src1   = 1'b1; // 源1=PC
            alu_src2   = 1'b1; // 源2=立即数
            gr_we      = 1'b1; // 写通用寄存器
            imm        = imm_u;
            alu_op     = `ALU_OP_ADD; // PC + imm_u
        end

        // CSR指令（基础支持）
        `OPCODE_SYSTEM: begin
            csr_inst  = 1'b1;
            gr_we     = 1'b1;
            imm       = imm_i;
            csr_addr_reg  = if_inst_r[31:20];
            csr_we_reg    = (funct3 != `FUNCT3_CSRRS);
            // 仅保留合法CSR指令
            if (funct3 != `FUNCT3_CSRRW && funct3 != `FUNCT3_CSRRS && funct3 != `FUNCT3_CSRRC) begin
                illegal_inst = 1'b1;
                excp_num     = `EXCP_ILLEGAL_INST;
                excp         = 1'b1;
            end
        end

        // 非法指令
        default: begin
            illegal_inst = 1'b1;
            excp_num     = `EXCP_ILLEGAL_INST;
            excp         = 1'b1;
        end
    endcase
end

// 7. 数据前递处理（核心，解决流水线冒险）
assign rs1_forward_ms = (rs1 != 5'b0) && ms_to_ds_valid && (rs1 == ms_to_ds_forward_bus[36:32]) && ms_to_ds_forward_bus[37];
assign rs1_forward_es = (rs1 != 5'b0) && es_to_ds_valid && (rs1 == es_to_ds_forward_bus[36:32]) && es_to_ds_forward_bus[37];
assign rs2_forward_ms = (rs2 != 5'b0) && ms_to_ds_valid && (rs2 == ms_to_ds_forward_bus[36:32]) && ms_to_ds_forward_bus[37];
assign rs2_forward_es = (rs2 != 5'b0) && es_to_ds_valid && (rs2 == es_to_ds_forward_bus[36:32]) && es_to_ds_forward_bus[37];

// 源寄存器数据选择（前递优先级：存储阶段 > 执行阶段 > 寄存器堆）
assign rs1_data = rs1_forward_ms ? ms_to_ds_forward_bus[31:0] :
                  rs1_forward_es ? es_to_ds_forward_bus[31:0] :
                  (rs1 == 5'b0) ? 32'b0 : rf_rdata1;

assign rs2_data = rs2_forward_ms ? ms_to_ds_forward_bus[31:0] :
                  rs2_forward_es ? es_to_ds_forward_bus[31:0] :
                  (rs2 == 5'b0) ? 32'b0 : rf_rdata2;

// 8. 通用寄存器堆读地址赋值
assign rf_raddr1 = rs1;
assign rf_raddr2 = rs2;

// 9. CSR接口赋值
assign csr_addr = csr_addr_reg;
assign csr_we   = csr_we_reg;

// 10. 译码到执行阶段的总线赋值（精简版）
assign id_to_es_bus = {
    // 基础信息
    if_pc_r,              // PC (32)
    if_inst_r,            // 原始指令 (32)
    // 控制信号
    gr_we,                // 通用寄存器写使能 (1)
    rd,                   // 目标寄存器地址 (5)
    alu_op,               // ALU操作类型 (5)
    alu_src1,             // ALU源1选择 (1)
    alu_src2,             // ALU源2选择 (1)
    // 数据
    rs1_data,             // 源寄存器1数据 (32)
    rs2_data,             // 源寄存器2数据 (32)
    imm,                  // 立即数 (32)
    // 内存访问
    load_inst,            // 加载指令标记 (1)
    store_inst,           // 存储指令标记 (1)
    mem_size,             // 内存访问大小 (2)
    mem_sign_ext,         // 加载符号扩展 (1)
    // 分支/跳转
    branch_inst,          // 分支指令标记 (1)
    jump_inst,            // 跳转指令标记 (1)
    branch_taken,         // 分支预测跳转 (1)
    branch_target_pc,     // 分支目标PC (32)
    // 异常
    illegal_inst,         // 非法指令标记 (1)
    excp_num,             // 异常号 (10)
    excp,                 // 异常标记 (1)
    // CSR
    csr_inst,             // CSR指令标记 (1)
    csr_we_reg,           // CSR写使能 (1)
    csr_addr_reg,         // CSR地址 (12)
    csr_rdata             // CSR读数据 (32)
};

// 11. 核心输出赋值
assign id_inst         = if_inst_r;
assign id_pc           = if_pc_r;
assign id_branch_inst  = branch_inst;
assign id_branch_target= branch_target_pc;
assign id_stall        = core_stall | csr_stall;
assign id_imm          = imm;
assign id_illegal_inst = illegal_inst;
assign id_excp         = excp;
assign id_excp_num     = excp_num;
assign id_load_inst    = load_inst;
assign id_store_inst   = store_inst;
assign id_br_inst      = branch_inst;
assign id_gr_we        = gr_we;
assign id_dest         = rd;

// 测试接口（仅核心信号）
assign id_test_data1   = rs1_data;
assign id_test_data2   = rs2_data;
assign id_test_rd      = rd;
assign id_test_valid   = id_valid;

endmodule