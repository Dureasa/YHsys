`include "riscv_defines.h"

module writeback_stage (
    // 时钟 & 复位
    input  wire                 clk,
    input  wire                 reset,

    // 来自 MEM 阶段
    input  wire [`PC_WIDTH-1:0]  mem_pc,
    input  wire [31:0]          mem_result,    // 来自 MEM：最终结果（load 已扩展）
    input  wire [4:0]           mem_rd,
    input  wire                 mem_reg_wen,
    input  wire                 mem_excp_en,
    input  wire [3:0]           mem_excp_code,

    // 全局控制
    input  wire                 core_stall,
    input  wire                 excp_flush,

    // 输出到寄存器文件
    output reg                  wb_reg_wen,
    output reg [4:0]            wb_rd,
    output reg [31:0]           wb_data,

    // 输出到 CPU 顶层（异常提交）
    output reg                  wb_excp_en,
    output reg [3:0]            wb_excp_code,
    output reg [`PC_WIDTH-1:0]  wb_pc
);

// ==============================
// 写回阶段：纯寄存 + 异常优先
// ==============================
always @(posedge clk or posedge reset) begin
    if (reset || excp_flush) begin
        wb_reg_wen   <= 1'b0;
        wb_rd        <= 5'b0;
        wb_data      <= 32'b0;
        wb_excp_en   <= 1'b0;
        wb_excp_code <= 4'b0;
        wb_pc        <= `PC_WIDTH'b0;
    end
    else if (!core_stall) begin
        // 异常优先：一旦 MEM 传来异常，写回阶段提交异常
        if (mem_excp_en) begin
            wb_reg_wen   <= 1'b0;          // 异常不写寄存器
            wb_rd        <= 5'b0;
            wb_data      <= 32'b0;
            wb_excp_en   <= 1'b1;
            wb_excp_code <= mem_excp_code;
            wb_pc        <= mem_pc;
        end
        else begin
            // 正常指令写回
            wb_reg_wen   <= mem_reg_wen;
            wb_rd        <= mem_rd;
            wb_data      <= mem_result;
            wb_excp_en   <= 1'b0;
            wb_excp_code <= 4'b0;
            wb_pc        <= mem_pc;
        end
    end
end

endmodule