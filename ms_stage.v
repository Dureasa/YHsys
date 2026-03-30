`include "riscv_defines.h"
`include "riscv_inst_defines.h"

module ms_stage (
    // 时钟/复位
    input  wire                          clk                ,
    input  wire                          reset              ,

    // 流水线握手
    input  wire                          wb_allowin         ,  // 写回阶段允许接收
    output wire                          ms_allowin         ,  // 本阶段允许接收
    output wire                          ms_to_wb_valid     ,  // 到写回阶段有效

    // 来自执行阶段
    input  wire                          es_to_ms_valid     ,
    input  wire [`ES_TO_MS_BUS_WD-1:0]    es_to_ms_bus       ,

    // 到写回阶段总线
    output wire [`MS_TO_WB_BUS_WD-1:0]    ms_to_wb_bus       ,

    // 数据前递（发给译码阶段）
    output wire [`MS_TO_DS_FORWARD_BUS-1:0] ms_to_ds_forward_bus,

    // 数据缓存（DCache）接口
    output wire                          dcache_req         ,  // DCache 请求
    output wire                          dcache_we          ,  // DCache 写使能
    output wire [31:0]                   dcache_addr        ,  // DCache 地址
    output wire [31:0]                   dcache_wdata       ,  // DCache 写数据
    output wire [1:0]                    dcache_size        ,  // DCache 访问大小（00=字，01=字节，10=半字）
    output wire                          dcache_sign_ext    ,  // 加载符号扩展
    input  wire                          dcache_ack         ,  // DCache 响应
    input  wire [31:0]                   dcache_rdata       ,  // DCache 读数据
    input  wire                          dcache_miss        ,  // DCache 缺失

    // 冲刷信号
    input  wire                          excp_flush         ,
    input  wire                          branch_flush       ,

    // 分支预测反馈（分支错误冲刷）
    output wire                          branch_error       ,  // 分支预测错误
    output wire [31:0]                   branch_error_pc    ,  // 分支错误PC
    output wire [31:0]                   branch_correct_pc  ,  // 分支正确PC

    // 核心状态输出
    output wire                          ms_stall           ,  // 访存阶段暂停
    output wire                          ms_load_inst       ,  // 加载指令标记
    output wire                          ms_store_inst      // 存储指令标记
);

// ====================== 内部信号定义 ======================
reg                          ms_valid_r;               // 访存阶段有效标记
reg                          ms_ready_go_r;            // 访存就绪标记

// 从执行阶段拆解的信号
reg  [31:0]                  ms_pc_r;                  // 锁存的PC
reg                          ms_gr_we_r;               // 通用寄存器写使能
reg  [4:0]                   ms_rd_r;                  // 目标寄存器地址
reg  [31:0]                  ms_alu_result_r;          // ALU运算结果（访存地址/运算结果）
reg  [31:0]                  ms_rs2_data_r;            // 存储指令数据
reg                          ms_load_r;                // 加载指令标记
reg                          ms_store_r;               // 存储指令标记
reg  [1:0]                   ms_mem_size_r;            // 内存访问大小
reg                          ms_mem_sign_ext_r;        // 加载符号扩展
reg                          ms_branch_r;              // 分支指令标记
reg                          ms_branch_taken_r;        // 分支实际跳转
reg  [31:0]                  ms_branch_target_r;       // 分支目标PC
reg                          ms_jump_r;                // 跳转指令标记
reg                          ms_illegal_r;             // 非法指令标记
reg  [9:0]                   ms_excp_num_r;            // 异常号
reg                          ms_excp_r;                // 异常标记
reg                          ms_csr_inst_r;            // CSR指令标记
reg                          ms_csr_we_r;              // CSR写使能
reg  [11:0]                  ms_csr_addr_r;            // CSR地址
reg  [31:0]                  ms_csr_rdata_r;           // CSR读数据

// 加载数据处理
wire [31:0]                  load_data;                // 处理后的加载数据
reg  [31:0]                  load_data_r;              // 锁存的加载数据

// 分支错误判断
wire                         branch_mismatch;          // 分支预测与实际跳转不一致

// 流水线控制
wire                         ms_ready_go;              // 访存阶段就绪

// ====================== 流水线握手逻辑 ======================
// 访存就绪：非加载指令/加载指令已收到DCache响应/存储指令完成
assign ms_ready_go = (!ms_load_r || (ms_load_r && dcache_ack)) && 
                     (!ms_store_r || (ms_store_r && dcache_ack)) &&
                     !dcache_miss;

// 本阶段允许接收：无效 或 就绪且写回阶段允许接收
assign ms_allowin = !ms_valid_r || (ms_ready_go && wb_allowin);

// 到写回阶段有效：本阶段有效且就绪
assign ms_to_wb_valid = ms_valid_r && ms_ready_go;

// 访存阶段暂停标记
assign ms_stall = ms_valid_r && !ms_ready_go;

// ====================== 有效标记更新 ======================
always @(posedge clk or posedge reset) begin
    if (reset) begin
        ms_valid_r <= 1'b0;
    end else if (excp_flush || branch_flush) begin
        ms_valid_r <= 1'b0; // 冲刷时清空
    end else if (ms_allowin) begin
        ms_valid_r <= es_to_ms_valid; // 接收执行阶段数据
    end
end

// ====================== 执行阶段总线锁存 ======================
always @(posedge clk or posedge reset) begin
    if (reset) begin
        ms_pc_r           <= 32'b0;
        ms_gr_we_r        <= 1'b0;
        ms_rd_r           <= 5'b0;
        ms_alu_result_r   <= 32'b0;
        ms_rs2_data_r     <= 32'b0;
        ms_load_r         <= 1'b0;
        ms_store_r        <= 1'b0;
        ms_mem_size_r     <= 2'b0;
        ms_mem_sign_ext_r <= 1'b0;
        ms_branch_r       <= 1'b0;
        ms_branch_taken_r <= 1'b0;
        ms_branch_target_r<= 32'b0;
        ms_jump_r         <= 1'b0;
        ms_illegal_r      <= 1'b0;
        ms_excp_num_r     <= 10'b0;
        ms_excp_r         <= 1'b0;
        ms_csr_inst_r     <= 1'b0;
        ms_csr_we_r       <= 1'b0;
        ms_csr_addr_r     <= 12'b0;
        ms_csr_rdata_r    <= 32'b0;
    end else if (ms_allowin) begin
        // 拆解执行阶段总线（与es_to_ms_bus定义顺序一致）
        {
            ms_pc_r,
            ms_gr_we_r,
            ms_rd_r,
            ms_alu_result_r,
            ms_rs2_data_r,
            ms_load_r,
            ms_store_r,
            ms_mem_size_r,
            ms_mem_sign_ext_r,
            ms_branch_r,
            ms_branch_taken_r,
            ms_branch_target_r,
            ms_jump_r,
            ms_illegal_r,
            ms_excp_num_r,
            ms_excp_r,
            ms_csr_inst_r,
            ms_csr_we_r,
            ms_csr_addr_r,
            ms_csr_rdata_r
        } <= es_to_ms_bus;
    end
end

// ====================== DCache 接口控制 ======================
assign dcache_req    = ms_valid_r && (ms_load_r || ms_store_r) && !dcache_ack && !dcache_miss;
assign dcache_we     = ms_store_r;
assign dcache_addr   = ms_alu_result_r; // ALU结果 = 访存地址
assign dcache_size   = ms_mem_size_r;
assign dcache_sign_ext = ms_mem_sign_ext_r;

// 存储数据对齐（根据访问大小）
assign dcache_wdata = (ms_mem_size_r == 2'b01) ? {4{ms_rs2_data_r[7:0]}} :  // 字节
                      (ms_mem_size_r == 2'b10) ? {2{ms_rs2_data_r[15:0]}} : // 半字
                      ms_rs2_data_r;                                       // 字

// ====================== 加载数据处理 ======================
// 根据访问大小和符号扩展处理加载数据
assign load_data = (ms_mem_size_r == 2'b01) ? (ms_mem_sign_ext_r ? {{24{dcache_rdata[7]}},  dcache_rdata[7:0]}  : {24'b0, dcache_rdata[7:0]})  : // 字节
                   (ms_mem_size_r == 2'b10) ? (ms_mem_sign_ext_r ? {{16{dcache_rdata[15]}}, dcache_rdata[15:0]} : {16'b0, dcache_rdata[15:0]}) : // 半字
                   dcache_rdata;                                                                                                      // 字

// 锁存加载数据（防止DCache响应后数据变化）
always @(posedge clk or posedge reset) begin
    if (reset) begin
        load_data_r <= 32'b0;
    end else if (ms_load_r && dcache_ack) begin
        load_data_r <= load_data;
    end
end

// ====================== 分支错误判断 ======================
// 分支预测错误：分支指令且预测跳转 != 实际跳转
assign branch_mismatch = ms_branch_r && (ms_branch_taken_r != (ms_pc_r + 4 == ms_branch_target_r));
assign branch_error    = ms_valid_r && branch_mismatch;
assign branch_error_pc = ms_pc_r;
assign branch_correct_pc = ms_branch_taken_r ? ms_branch_target_r : (ms_pc_r + 4);

// ====================== 数据前递（发给译码阶段） ======================
// 前递总线：写使能(1) + 目标寄存器(5) + 数据(32)
assign ms_to_ds_forward_bus = {
    ms_gr_we_r,
    ms_rd_r,
    ms_load_r ? load_data_r : ms_alu_result_r // 加载指令用加载数据，其他用ALU结果
};

// ====================== 到写回阶段总线赋值 ======================
assign ms_to_wb_bus = {
    ms_pc_r,
    ms_gr_we_r,
    ms_rd_r,
    ms_load_r ? load_data_r : ms_alu_result_r, // 写回数据：加载/ALU/CSR
    ms_illegal_r,
    ms_excp_num_r,
    ms_excp_r,
    ms_csr_inst_r,
    ms_csr_we_r,
    ms_csr_addr_r,
    ms_csr_rdata_r
};

// ====================== 核心输出赋值 ======================
assign ms_load_inst  = ms_load_r;
assign ms_store_inst = ms_store_r;

endmodule