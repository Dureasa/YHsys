`include "riscv_defines.h"
`include "riscv_inst_defines.h"
`include "riscv_csr_defines.h"
`include "riscv_excp_defines.h"

module ms_stage (
    // 时钟 & 复位
    input  wire                    clk,
    input  wire                    reset,

    // 全局流水线控制
    input  wire                    core_stall,
    input  wire                    excp_flush,
    input  wire                    pred_flush,

    // ==================== 来自执行阶段 EX ====================
    input  wire [`PC_WIDTH-1:0]     ex_pc,
    input  wire [`REG_WIDTH-1:0]    ex_alu_result,   // ALU 结果
    input  wire [`REG_WIDTH-1:0]    ex_vaddr,        // 虚拟地址（来自ID，透传EX到MEM）
    input  wire [`REG_WIDTH-1:0]    ex_rs2_data,
    input  wire [4:0]               ex_rd,
    input  wire [2:0]               ex_funct3,

    // 控制信号
    input  wire                    ex_reg_wen,
    input  wire                    ex_mem_en,
    input  wire [1:0]               ex_mem_op,
    input  wire                    ex_csr_en,
    input  wire [11:0]              ex_csr_addr,
    input  wire [2:0]               ex_csr_op,
    input  wire [`REG_WIDTH-1:0]    ex_csr_wdata,

    // 异常（来自EX）
    input  wire                    ex_excp_en,
    input  wire [3:0]               ex_excp_code,
    input  wire [`PC_WIDTH-1:0]     ex_excp_pc,
    input  wire                    ex_valid,

    // ==================== MMU 地址翻译（在MEM阶段执行） ====================
    input  wire [`REG_WIDTH-1:0]    mmu_paddr,      // 物理地址
    input  wire                    mmu_ready,      // MMU 转换完成
    input  wire                    mmu_excp_en,    // MMU 异常
    input  wire [3:0]               mmu_excp_code,  // 异常码

    // ==================== 数据存储器 RAM ====================
    output reg                     dmem_we,
    output reg  [`REG_WIDTH-1:0]    dmem_addr,       // 物理地址
    output reg  [`REG_WIDTH-1:0]    dmem_wdata,
    input  wire [`REG_WIDTH-1:0]    dmem_rdata,

    // ==================== 输出到 WB ====================
    output reg  [`PC_WIDTH-1:0]     ms_pc,
    output reg  [`REG_WIDTH-1:0]    ms_result,
    output reg  [4:0]               ms_rd,
    output reg                     ms_reg_wen,
    output reg                     ms_csr_en,
    output reg  [11:0]              ms_csr_addr,
    output reg  [2:0]               ms_csr_op,
    output reg  [`REG_WIDTH-1:0]    ms_csr_wdata,

    // 异常输出
    output reg                     ms_excp_en,
    output reg  [3:0]               ms_excp_code,
    output reg  [`PC_WIDTH-1:0]     ms_excp_pc,
    output reg                     ms_valid
);

localparam  MEM_OP_LOAD     = 2'b01;
localparam  MEM_OP_STORE    = 2'b10;

// 加载指令位宽扩展
reg [`REG_WIDTH-1:0] load_data_final;
always @(*) begin
    load_data_final = 32'b0;
    if(ex_mem_en && ex_mem_op == MEM_OP_LOAD && !mmu_excp_en && mmu_ready) begin
        case(ex_funct3)
            3'b000: load_data_final = {{24{dmem_rdata[7]}}, dmem_rdata[7:0]};
            3'b001: load_data_final = {{16{dmem_rdata[15]}}, dmem_rdata[15:0]};
            3'b010: load_data_final = dmem_rdata;
            3'b100: load_data_final = {24'b0, dmem_rdata[7:0]};
            3'b101: load_data_final = {16'b0, dmem_rdata[15:0]};
            default: load_data_final = 32'b0;
        endcase
    end
end

// ==================== 访存控制 & MMU 地址使用 ====================
always @(*) begin
    dmem_we     = 1'b0;
    dmem_addr   = 32'b0;
    dmem_wdata  = 32'b0;

    // 只有 MMU 就绪 + 无异常 + 有效访存指令 才访问内存
    if(ex_valid && ex_mem_en && mmu_ready && !mmu_excp_en && !ex_excp_en) begin
        dmem_addr  = mmu_paddr;      // 使用 MMU 翻译后的物理地址
        dmem_wdata = ex_rs2_data;
        dmem_we    = (ex_mem_op == MEM_OP_STORE);
    end
end

// ==================== 输出到 WB 阶段 ====================
always @(posedge clk or posedge reset) begin
    if(reset) begin
        ms_pc        <= 32'h80000000;
        ms_result    <= 32'b0;
        ms_rd        <= 5'b0;
        ms_reg_wen   <= 1'b0;
        ms_csr_en    <= 1'b0;
        ms_excp_en   <= 1'b0;
        ms_valid     <= 1'b0;
    end
    else if(excp_flush || pred_flush) begin
        ms_pc        <= 32'h80000000;
        ms_result    <= 32'b0;
        ms_rd        <= 5'b0;
        ms_reg_wen   <= 1'b0;
        ms_csr_en    <= 1'b0;
        ms_excp_en   <= 1'b0;
        ms_valid     <= 1'b0;
    end
    else if(core_stall || !mmu_ready) begin  // MMU 未就绪 → 暂停
        // 保持不变
    end
    else begin
        // 正常传递
        ms_pc        <= ex_pc;
        ms_rd        <= ex_rd;
        ms_reg_wen   <= ex_reg_wen;
        ms_csr_en    <= ex_csr_en;
        ms_csr_addr  <= ex_csr_addr;
        ms_csr_op    <= ex_csr_op;
        ms_csr_wdata <= ex_csr_wdata;
        ms_valid     <= ex_valid;

        // 异常合并：EX异常 | MMU异常
        ms_excp_en   <= ex_excp_en || mmu_excp_en;
        ms_excp_code <= mmu_excp_en ? mmu_excp_code : ex_excp_code;
        ms_excp_pc   <= ex_excp_pc;

        // 结果选择
        if(ex_mem_en && ex_mem_op == MEM_OP_LOAD)
            ms_result <= load_data_final;
        else
            ms_result <= ex_alu_result;
    end
end

endmodule