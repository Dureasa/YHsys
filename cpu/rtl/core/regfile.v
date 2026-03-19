`include "riscv_defines.h"

module regfile (
    input  wire         clk        ,
    input  wire         reset      ,

    // 读接口
    input  wire [4:0]   raddr1     ,
    input  wire [4:0]   raddr2     ,
    output wire [31:0]  rdata1     ,
    output wire [31:0]  rdata2     ,

    // 写接口（来自WB阶段）
    input  wire         we         ,
    input  wire [4:0]   waddr      ,
    input  wire [31:0]  wdata
);

reg [31:0] regs[31:0];

// 读操作（组合逻辑）
assign rdata1 = (raddr1 == 5'b0) ? 32'b0 : regs[raddr1];
assign rdata2 = (raddr2 == 5'b0) ? 32'b0 : regs[raddr2];

// 写操作（时序逻辑）
integer i;
always @(posedge clk or posedge reset) begin
    if (reset) begin
        for (i = 0; i < 32; i = i + 1) begin
            regs[i] <= 32'b0;
        end
    end else if (we && (waddr != 5'b0)) begin // 跳过 x0
        regs[waddr] <= wdata;
    end
end

endmodule