`include "riscv_defines.h"
`include "riscv_inst_defines.h"

module wb_stage (
    // 时钟 & 复位
    input  wire                          clk                ,
    input  wire                          reset              ,

    // 流水线握手
    output wire                          wb_allowin         ,  // 允许前级进入

    // 来自访存阶段
    input  wire                          ms_to_wb_valid     ,
    input  wire [`MS_TO_WB_BUS_WD-1:0]    ms_to_wb_bus       ,

    // 通用寄存器堆写回接口
    output wire                          rf_we              ,
    output wire [4:0]                    rf_waddr           ,
    output wire [31:0]                   rf_wdata           ,

    // CSR 写回接口
    output wire                          csr_we             ,
    output wire [11:0]                   csr_waddr          ,
    output wire [31:0]                   csr_wdata          ,

    // 异常冲刷输出
    output wire                          wb_excp_flush
);

//==========================================================================
// 内部信号
//==========================================================================
reg                          wb_valid_r;

// 从 MS 阶段拆出的信号
reg  [31:0]                  wb_pc_r;
reg                          wb_gr_we_r;
reg  [4:0]                   wb_rd_r;
reg  [31:0]                  wb_final_data_r;
reg                          wb_illegal_r;
reg  [9:0]                   wb_excp_num_r;
reg                          wb_excp_r;
reg                          wb_csr_inst_r;
reg                          wb_csr_we_r;
reg  [11:0]                  wb_csr_addr_r;
reg  [31:0]                  wb_csr_rdata_r;

//==========================================================================
// 流水线握手
//==========================================================================
// 写回阶段无阻塞，always ready
assign wb_allowin = !wb_valid_r;

always @(posedge clk or posedge reset) begin
    if (reset) begin
        wb_valid_r <= 1'b0;
    end else if (wb_allowin) begin
        wb_valid_r <= ms_to_wb_valid;
    end
end

//==========================================================================
// 锁存访存阶段送来的总线
//==========================================================================
always @(posedge clk or posedge reset) begin
    if (reset) begin
        wb_pc_r          <= 32'b0;
        wb_gr_we_r       <= 1'b0;
        wb_rd_r          <= 5'b0;
        wb_final_data_r  <= 32'b0;
        wb_illegal_r     <= 1'b0;
        wb_excp_num_r    <= 10'b0;
        wb_excp_r        <= 1'b0;
        wb_csr_inst_r    <= 1'b0;
        wb_csr_we_r      <= 1'b0;
        wb_csr_addr_r    <= 12'b0;
        wb_csr_rdata_r   <= 32'b0;
    end else if (wb_allowin) begin
        {
            wb_pc_r,
            wb_gr_we_r,
            wb_rd_r,
            wb_final_data_r,
            wb_illegal_r,
            wb_excp_num_r,
            wb_excp_r,
            wb_csr_inst_r,
            wb_csr_we_r,
            wb_csr_addr_r,
            wb_csr_rdata_r
        } <= ms_to_wb_bus;
    end
end

//==========================================================================
// 通用寄存器堆写回控制
//==========================================================================
// 异常时不写回
assign rf_we    = wb_valid_r && wb_gr_we_r && !wb_excp_r;
assign rf_waddr = wb_rd_r;
assign rf_wdata = wb_final_data_r;

//==========================================================================
// CSR 写回控制
//==========================================================================
assign csr_we    = wb_valid_r && wb_csr_we_r && !wb_excp_r;
assign csr_waddr = wb_csr_addr_r;
assign csr_wdata = wb_final_data_r;

//==========================================================================
// 异常冲刷信号
//==========================================================================
assign wb_excp_flush = wb_valid_r && wb_excp_r;

endmodule