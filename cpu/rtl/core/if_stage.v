`include "riscv_defines.h"  // 包含宏定义（如PC_WIDTH、INST_WIDTH等）

module if_stage(
    // 时钟/复位
    input  wire                 clk              ,  // 系统时钟
    input  wire                 reset            ,  // 异步复位（高有效）
    // 流水线控制
    input  wire                 id_allowin       ,  // 译码阶段就绪信号（允许接收新指令）
    output wire                 if_allowin       ,  // 取指阶段就绪信号（允许接收新PC）
    output wire                 if_to_id_valid   ,  // 取指到译码的有效信号
    output wire [`IF_TO_ID_BUS_WD-1:0] if_to_id_bus,  // 取指到译码的总线
    // 异常/冲刷信号
    input  wire                 excp_flush       ,  // 异常冲刷（清空流水线）
    input  wire                 branch_flush     ,  // 分支预测错误冲刷
    input  wire                 ertn_flush       ,  // 异常返回冲刷
    // 分支预测反馈（来自执行阶段）
    input  wire                 branch_taken     ,  // 分支实际是否跳转
    input  wire [`PC_WIDTH-1:0] branch_target_pc ,  // 分支实际目标PC
    // ICache接口
    input  wire                 icache_data_ok   ,  // ICache数据就绪
    input  wire [`INST_WIDTH-1:0] icache_rdata    ,  // ICache返回指令
    input  wire                 icache_miss      ,  // ICache缺失
    output wire                 icache_req       ,  // ICache读请求
    output wire [`PC_WIDTH-1:0] icache_addr      ,  // ICache访问地址
    // PC重定向（异常/中断/分支）
    input  wire                 pc_redirect_en   ,  // PC重定向使能
    input  wire [`PC_WIDTH-1:0] redirect_pc      ,  // 重定向目标PC
    // 性能计数
    output wire                 if_inst_valid    ,  // 取指有效（用于指令计数）
    // 空闲模式
    input  wire                 idle_flush       ,  // 空闲模式冲刷
    // 暂停信号（ICache缺失/流水线阻塞）
    output wire                 if_stall         ,  // 取指阶段暂停
    input  wire                 core_stall       ,  // 全局核心暂停
    // 分支预测器接口（可选，简化版可注释）
    input  wire                 bp_taken         ,  // 分支预测跳转
    input  wire [`PC_WIDTH-1:0] bp_target_pc     ,  // 分支预测目标PC
    output wire [`PC_WIDTH-1:0] if_pc_out        ,  // 当前PC输出（给分支预测器）
    input  wire                 icache_unbusy    ,  // ICache非忙
    input  wire                 tlb_excp_cancel_req // TLB异常取消请求
);

// ====================== 内部寄存器/连线定义 ======================
reg  [`PC_WIDTH-1:0]  pc_reg          ;  // PC寄存器（当前取指地址）
reg                   if_valid        ;  // 取指阶段有效标记
reg  [`INST_WIDTH-1:0] inst_buff       ;  // 指令缓存（解决ICache就绪但译码未就绪）
reg                   inst_buff_en    ;  // 指令缓存使能
reg                   icache_req_reg  ;  // ICache请求锁存

wire                  flush_sign      ;  // 流水线冲刷总信号
wire                  pc_update_en    ;  // PC更新使能
wire [`PC_WIDTH-1:0]  next_pc         ;  // 下一个PC值
wire [`PC_WIDTH-1:0]  predict_pc      ;  // 预测的下一个PC
wire                  if_ready_go     ;  // 取指阶段就绪（可发送到译码）
wire                  inst_valid      ;  // 指令有效（ICache返回/缓存命中）
wire [`INST_WIDTH-1:0] if_inst         ;  // 最终输出指令
wire                  icache_req_en   ;  // ICache请求使能

// ====================== 核心逻辑 ======================
// 1. 冲刷信号整合（异常/分支错误/ERTN/空闲）
assign flush_sign = excp_flush | branch_flush | ertn_flush | idle_flush | tlb_excp_cancel_req;

// 2. PC生成逻辑
// 2.1 预测PC（分支预测/正常+4）
assign predict_pc = bp_taken ? bp_target_pc : (pc_reg + 4'h4);
// 2.2 下一个PC（重定向优先 > 分支预测 > 正常+4）
assign next_pc = pc_redirect_en ? redirect_pc : predict_pc;
// 2.3 PC更新使能（无暂停+无冲刷+ICache非忙）
assign pc_update_en = if_allowin & !core_stall & !icache_miss & icache_unbusy;

// 3. PC寄存器更新（复位/冲刷/正常更新）
always @(posedge clk or posedge reset) begin
    if (reset) begin
        pc_reg <= 32'h80000000;  // 复位PC（如0x80000000）
    end else if (flush_sign) begin
        pc_reg <= redirect_pc;  // 冲刷时直接加载重定向PC
    end else if (pc_update_en) begin
        pc_reg <= next_pc;      // 正常更新PC
    end
end

// 4. ICache接口控制
assign icache_req_en = if_valid & !icache_miss & !flush_sign & !core_stall;
assign icache_req    = icache_req_en;
assign icache_addr   = pc_reg;  // ICache访问地址=当前PC

// 锁存ICache请求（防止跨周期丢失）
always @(posedge clk or posedge reset) begin
    if (reset) begin
        icache_req_reg <= 1'b0;
    end else begin
        icache_req_reg <= icache_req_en;
    end
end

// 5. 指令缓存（ICache就绪但译码未就绪时缓存指令）
always @(posedge clk or posedge reset) begin
    if (reset) begin
        inst_buff    <= `INST_WIDTH'b0;
        inst_buff_en <= 1'b0;
    end else if (flush_sign) begin
        inst_buff    <= `INST_WIDTH'b0;
        inst_buff_en <= 1'b0;
    end else if (icache_data_ok & !id_allowin & !core_stall) begin
        // ICache返回数据，但译码未就绪 → 缓存指令
        inst_buff    <= icache_rdata;
        inst_buff_en <= 1'b1;
    end else if (if_ready_go & id_allowin) begin
        // 指令已发送到译码 → 清空缓存
        inst_buff_en <= 1'b0;
    end
end

// 6. 指令有效判断（缓存命中/ICache返回）
assign inst_valid = inst_buff_en | icache_data_ok;
assign if_inst    = inst_buff_en ? inst_buff : icache_rdata;

// 7. 流水线握手逻辑
// 7.1 取指阶段就绪（指令有效 或 无ICache请求 或 冲刷）
assign if_ready_go = inst_valid | !icache_req_reg | flush_sign;
// 7.2 取指阶段允许接收新数据（译码就绪 且 自身就绪）
assign if_allowin  = !if_valid | (if_ready_go & id_allowin);
// 7.3 取指阶段有效标记（复位/冲刷清零，允许接收时更新）
always @(posedge clk or posedge reset) begin
    if (reset) begin
        if_valid <= 1'b0;
    end else if (flush_sign) begin
        if_valid <= 1'b0;
    end else if (if_allowin) begin
        if_valid <= 1'b1;  // 只要允许接收，就标记为有效
    end
end

// 7.4 取指到译码的有效信号
assign if_to_id_valid = if_valid & if_ready_go;

// 8. 取指到译码的总线（包含PC、指令、缓存缺失标记等）
assign if_to_id_bus = {
    pc_reg,              // 当前PC
    if_inst,             // 取到的指令
    icache_miss,         // ICache缺失标记
    flush_sign,          // 冲刷标记
    if_inst_valid        // 指令有效标记
};

// 9. 辅助信号
assign if_stall       = icache_miss | !icache_unbusy;  // 取指暂停
assign if_inst_valid  = if_valid & !flush_sign;       // 有效取指标记
assign if_pc_out      = pc_reg;                       // 当前PC输出（给分支预测器）


endmodule
