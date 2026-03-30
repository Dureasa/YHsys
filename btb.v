`include "riscv_defines.h"
`include "riscv_inst_defines.h"

module btb(
    // 时钟/复位
    input  wire                 clk              ,  // 系统时钟
    input  wire                 reset            ,  // 异步复位（高有效）
    // 与取指阶段（IF）对接
    input  wire [`PC_WIDTH-1:0] if_pc            ,  // 取指当前PC（待预测分支指令地址）
    input  wire [`INST_WIDTH-1:0] if_inst        ,  // 取指当前指令（判断是否为分支指令）
    output reg                  pred_taken       ,  // 预测结果（1=预测跳转，0=预测不跳转）
    output wire [`PC_WIDTH-1:0]  pred_target_pc   ,  // 预测跳转目标地址
    output reg                  pred_valid       ,  // 预测有效（仅分支指令有效）
    // 与执行阶段（ES）对接（反馈实际跳转结果，修正预测器）
    input  wire [`PC_WIDTH-1:0] es_pc            ,  // 执行阶段分支指令PC（与if_pc对应）
    input  wire                 es_branch_en     ,  // 执行阶段标记：当前指令是分支指令
    input  wire                 es_branch_taken  ,  // 执行阶段实际跳转结果（1=实际跳转，0=实际不跳转）
    input  wire [`PC_WIDTH-1:0] es_branch_target ,  // 执行阶段实际跳转目标地址
    // 流水线冲刷控制（预测错误时触发）
    output reg                  pred_flush       ,  // 预测错误标记（触发流水线冲刷）
    output reg [`PC_WIDTH-1:0]  correct_pc       ,  // 预测错误时的正确PC
    // 全局控制信号
    input  wire                 core_stall       ,  // 核心暂停（暂停预测器更新）
    input  wire                 excp_flush       ,  // 异常冲刷（清空预测器状态）
    // 性能计数
    output reg                  pred_hit_cnt_en  ,  // 预测命中计数使能
    output reg                  pred_miss_cnt_en   // 预测缺失计数使能
);

// ====================== 内部参数/宏定义 ======================
// 2位饱和计数器状态定义（强跳转→弱跳转→弱不跳转→强不跳转）
localparam STRONG_TAKEN       = 2'b11;  // 强预测跳转
localparam WEAK_TAKEN         = 2'b10;  // 弱预测跳转
localparam WEAK_NOT_TAKEN     = 2'b01;  // 弱预测不跳转
localparam STRONG_NOT_TAKEN   = 2'b00;  // 强预测不跳转

// 预测表参数（根据流水线需求配置，适配32位PC）
localparam PRED_TABLE_DEPTH   = 256;    // 预测表深度（256项，对应PC[9:2]索引）
localparam PRED_TABLE_INDEX_WIDTH = 8;  // 预测表索引位宽

// 分支指令判断参数（funct3编码，对应RV32I分支指令）
localparam BEQ_FUNCT3         = 3'b000;
localparam BNE_FUNCT3         = 3'b001;
localparam BLT_FUNCT3         = 3'b100;
localparam BGE_FUNCT3         = 3'b101;
localparam BLTU_FUNCT3        = 3'b110;
localparam BGEU_FUNCT3        = 3'b111;

// ====================== 内部信号定义 ======================
// 预测表（2位饱和计数器，索引为PC[9:2]）
reg [1:0]                     pred_table[0:PRED_TABLE_DEPTH-1];

// 分支指令判断
wire                         is_branch_inst;  // 当前取指指令是分支指令
wire [2:0]                   branch_funct3;   // 分支指令funct3编码
wire [`PC_WIDTH-1:0]         branch_offset;   // 分支指令立即数偏移（符号扩展）

// 预测表索引（PC[9:2]，低2位为字节偏移，无意义）
wire [PRED_TABLE_INDEX_WIDTH-1:0] pred_index;
wire [PRED_TABLE_INDEX_WIDTH-1:0] update_index;

// 预测结果与实际结果对比
wire                         pred_correct;    // 预测正确标记
wire                         pred_wrong;      // 预测错误标记

// 锁存执行阶段分支信息（用于对齐预测表更新）
reg [`PC_WIDTH-1:0]          es_pc_reg;
reg                          es_branch_en_reg;
reg                          es_branch_taken_reg;

// ====================== 分支指令判断 ======================
// 判断当前取指指令是否为分支指令（opcode=1100011）
assign is_branch_inst = (if_inst[6:0] == `OPCODE_BRANCH);
// 提取分支指令funct3编码
assign branch_funct3 = if_inst[14:12];
// 分支指令立即数偏移（RV32I分支指令立即数格式：Imm[12|10:5|4:1|11]）
assign branch_offset = {{20{if_inst[31]}}, if_inst[7], if_inst[30:25], if_inst[11:8], 1'b0};
// 预测跳转目标地址（PC + 偏移）
assign pred_target_pc = if_pc + branch_offset;

// ====================== 预测表索引生成 ======================
// 取指阶段预测索引（当前PC[9:2]）
assign pred_index = if_pc[PRED_TABLE_INDEX_WIDTH+1:2];
// 执行阶段更新索引（执行阶段分支指令PC[9:2]，与预测时索引一致）
assign update_index = es_pc_reg[PRED_TABLE_INDEX_WIDTH+1:2];

// 锁存取指阶段预测结果（与执行阶段分支指令对齐）
reg pred_taken_reg;
always @(posedge clk or posedge reset) begin
    if (reset) begin
        pred_taken_reg <= 1'b0;
    end else if (!core_stall && is_branch_inst) begin
        pred_taken_reg <= pred_taken;
    end
end

// ====================== 预测结果判断与修正 ======================
// 预测正确/错误判断（仅分支指令有效）
assign pred_correct = es_branch_en_reg && (pred_taken_reg == es_branch_taken_reg);
assign pred_wrong = es_branch_en_reg && (pred_taken_reg != es_branch_taken_reg);

// 锁存执行阶段分支信息（对齐预测表更新时序）
always @(posedge clk or posedge reset) begin
    if (reset) begin
        es_pc_reg <= 32'b0;
        es_branch_en_reg <= 1'b0;
        es_branch_taken_reg <= 1'b0;
    end else if (!core_stall) begin
        es_pc_reg <= es_pc;
        es_branch_en_reg <= es_branch_en;
        es_branch_taken_reg <= es_branch_taken;
    end
end

// ====================== 预测表初始化与更新 ======================
integer i;
always @(posedge clk or posedge reset) begin
    if (reset) begin
        // 复位时，预测表初始化为「弱不跳转」（WEAK_NOT_TAKEN）
        for (i = 0; i < PRED_TABLE_DEPTH; i = i + 1) begin
            pred_table[i] <= WEAK_NOT_TAKEN;
        end
    end else if (excp_flush) begin
        // 异常冲刷时，重置预测表为初始状态
        for (i = 0; i < PRED_TABLE_DEPTH; i = i + 1) begin
            pred_table[i] <= WEAK_NOT_TAKEN;
        end
    end else if (!core_stall && es_branch_en_reg) begin
        // 执行阶段有分支指令，根据实际跳转结果更新预测表（2位饱和计数）
        case (pred_table[update_index])
            STRONG_TAKEN: begin
                pred_table[update_index] <= es_branch_taken_reg ? STRONG_TAKEN : WEAK_TAKEN;
            end
            WEAK_TAKEN: begin
                pred_table[update_index] <= es_branch_taken_reg ? STRONG_TAKEN : WEAK_NOT_TAKEN;
            end
            WEAK_NOT_TAKEN: begin
                pred_table[update_index] <= es_branch_taken_reg ? WEAK_TAKEN : STRONG_NOT_TAKEN;
            end
            STRONG_NOT_TAKEN: begin
                pred_table[update_index] <= es_branch_taken_reg ? WEAK_NOT_TAKEN : STRONG_NOT_TAKEN;
            end
            default: begin
                pred_table[update_index] <= WEAK_NOT_TAKEN;
            end
        endcase
    end
end

// ====================== 取指阶段预测逻辑 ======================
always @(posedge clk or posedge reset) begin
    if (reset) begin
        pred_taken <= 1'b0;
        pred_valid <= 1'b0;
    end else if (core_stall || excp_flush) begin
        // 核心暂停或异常冲刷，预测无效
        pred_taken <= 1'b0;
        pred_valid <= 1'b0;
    end else if (is_branch_inst) begin
        // 是分支指令，根据预测表状态输出预测结果
        pred_valid <= 1'b1;
        // 计数器为10/11时，预测跳转；00/01时，预测不跳转
        pred_taken <= (pred_table[pred_index] >= WEAK_TAKEN) ? 1'b1 : 1'b0;
    end else begin
        // 非分支指令，预测无效
        pred_taken <= 1'b0;
        pred_valid <= 1'b0;
    end
end

// ====================== 预测错误处理与流水线冲刷 ======================
always @(posedge clk or posedge reset) begin
    if (reset) begin
        pred_flush <= 1'b0;
        correct_pc <= 32'h80000000; // 复位正确PC，与流水线一致
        pred_hit_cnt_en <= 1'b0;
        pred_miss_cnt_en <= 1'b0;
    end else if (excp_flush) begin
        // 异常冲刷，清空预测错误标记和计数使能
        pred_flush <= 1'b0;
        pred_hit_cnt_en <= 1'b0;
        pred_miss_cnt_en <= 1'b0;
    end else if (pred_wrong) begin
        // 预测错误：触发流水线冲刷，设置正确PC
        pred_flush <= 1'b1;
        // 正确PC：实际跳转则为目标地址，实际不跳转则为PC+4
        correct_pc <= es_branch_taken_reg ? es_branch_target : (es_pc_reg + 4);
        // 预测缺失计数使能
        pred_miss_cnt_en <= 1'b1;
        pred_hit_cnt_en <= 1'b0;
    end else if (pred_correct && es_branch_en_reg) begin
        // 预测正确：计数使能，不冲刷
        pred_flush <= 1'b0;
        pred_hit_cnt_en <= 1'b1;
        pred_miss_cnt_en <= 1'b0;
    end else begin
        // 无分支指令或未完成判断，无动作
        pred_flush <= 1'b0;
        pred_hit_cnt_en <= 1'b0;
        pred_miss_cnt_en <= 1'b0;
    end
end

// 预测错误标记单拍清零（避免持续冲刷）
always @(posedge clk) begin
    if (pred_flush) begin
        pred_flush <= 1'b0;
    end
end

endmodule
