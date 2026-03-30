`include "riscv_defines.h"
`include "riscv_csr_defines.h"
`include "riscv_excp_defines.h"

module if_stage (
    // 时钟 & 复位
    input  wire                clk,
    input  wire                reset,

    // 全局流水线控制
    input  wire                core_stall,      // 流水线暂停
    input  wire                excp_flush,     // 异常/中断冲刷（来自中断单元）
    input  wire                pred_flush,     // 分支预测错误冲刷

    // 来自中断/异常控制器
    input  wire                int_trap_en,    // 进入中断陷阱
    input  wire [`PC_WIDTH-1:0] trap_pc,        // 中断入口地址

    // 来自执行阶段（分支/跳转）
    input  wire                branch_taken,   // 分支生效
    input  wire [`PC_WIDTH-1:0] branch_target,  // 分支目标地址

    input  wire                jump_taken,     // 跳转生效
    input  wire [`PC_WIDTH-1:0] jump_target,    // 跳转目标地址

    // 来自 mret 中断返回
    input  wire                mret_ready,
    input  wire [`PC_WIDTH-1:0] csr_mepc,        // 中断返回地址

    // ==================== 与 MMU 对接（取指地址转换） ====================
    output reg  [`PC_WIDTH-1:0] if_vaddr,       // 取指虚拟地址（给MMU）
    output wire                if_mem_access,  // 取指 = 执行访问(EXEC)
    input  wire                mmu_ready,      // MMU 转换完成
    input  wire                mmu_excp_en,    // MMU 取指异常
    input  wire [`PC_WIDTH-1:0] mmu_paddr,      // 转换后的物理地址

    // 与指令存储器/ICache对接
    output reg  [`PC_WIDTH-1:0] imem_addr,      // 物理地址
    input  wire [`INST_WIDTH-1:0] imem_inst,     // 读出指令

    // 输出到译码阶段（ID）
    output reg  [`PC_WIDTH-1:0] if_pc,
    output reg  [`INST_WIDTH-1:0] if_inst,
    output reg                   if_valid
);

localparam PC_INIT_VAL = 32'h80000000;  // 复位地址
assign if_mem_access = 2'b00;  // EXEC 执行访问

// ==================== PC 选择逻辑（最高优先级：异常 > 跳转 > 分支 +4） ====================
reg [`PC_WIDTH-1:0] next_pc;
always @(*) begin
    // 1. 最高优先级：中断/异常陷阱
    if (int_trap_en) begin
        next_pc = trap_pc;
    end
    // 2. 中断返回 mret
    else if (mret_ready) begin
        next_pc = csr_mepc;
    end
    // 3. 跳转指令 JAL/JALR
    else if (jump_taken) begin
        next_pc = jump_target;
    end
    // 4. 分支指令
    else if (branch_taken) begin
        next_pc = branch_target;
    end
    // 5. 正常 +4
    else begin
        next_pc = if_pc + 3'd4;
    end
end

// ==================== PC 时序更新 ====================
always @(posedge clk or posedge reset) begin
    if (reset) begin
        if_pc <= PC_INIT_VAL;
    end
    // 冲刷：复位PC
    else if (excp_flush || pred_flush) begin
        if_pc <= PC_INIT_VAL;
    end
    // 暂停：保持PC
    else if (core_stall || !mmu_ready) begin
        if_pc <= if_pc;
    end
    // 正常更新
    else begin
        if_pc <= next_pc;
    end
end

// ==================== 输出到 MMU：虚拟地址 = PC ====================
always @(*) begin
    if_vaddr = if_pc;
end

// ==================== 指令输出锁存 ====================
always @(posedge clk or posedge reset) begin
    if (reset) begin
        if_inst  <= 32'h00000013;  // nop (addi x0,x0,0)
        if_valid <= 1'b0;
        imem_addr <= PC_INIT_VAL;
    end
    else if (excp_flush || pred_flush || mmu_excp_en) begin
        if_inst  <= 32'h00000013;
        if_valid <= 1'b0;
        imem_addr <= PC_INIT_VAL;
    end
    else if (core_stall || !mmu_ready) begin
        if_inst  <= if_inst;
        if_valid <= 1'b0;
        imem_addr <= imem_addr;
    end
    else begin
        imem_addr <= mmu_paddr;       // 来自MMU的物理地址
        if_inst   <= imem_inst;
        if_valid  <= 1'b1;
    end
end

endmodule