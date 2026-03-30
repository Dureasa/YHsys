`include "riscv_defines.h"
`include "riscv_csr_defines.h"
`include "riscv_excp_defines.h"
module csr(
    // 时钟 & 复位
    input  wire         clk,
    input  wire         reset,

    // 全局流水线控制
    input  wire         core_stall,      // 核心暂停
    output reg          excp_flush,     // 异常冲刷流水线
    output reg          int_trap_en,    // 进入中断/异常陷阱

    // 来自 CPU 各模块的异常请求
    input  wire         id_excp_en,     // 译码阶段异常
    input  wire [3:0]   id_excp_code,   // 译码异常代码
    input  wire [`PC_WIDTH-1:0] id_excp_pc,  // 异常PC

    input  wire         mmu_excp_en,    // MMU 异常
    input  wire [3:0]   mmu_excp_code,  // MMU 异常代码
    input  wire [`PC_WIDTH-1:0] mmu_excp_vaddr, // MMU 异常虚地址

    // 外部中断输入
    input  wire         ext_int_req,    // 外部中断
    input  wire         timer_int_req,  // 定时器中断
    input  wire         sw_int_req,     // 软件中断

    // 与 CSR 模块交互（RISC-V 标准）
    input  wire         csr_mstatus_mie,// 全局中断使能(MIE)
    input  wire         csr_mstatus_mpie,// 旧中断使能
    input  wire [3:0]   csr_mie,        // 中断掩码
    output reg          csr_mstatus_upd,// 更新 CSR
    output reg          csr_mepc_upd,   // 更新 MEPC
    output reg          csr_mcause_upd, // 更新 MCAUSE
    output reg          csr_mtvac_upd, // 更新 MTVAL
    output reg [`PC_WIDTH-1:0] csr_mepc_data,
    output reg [3:0]    csr_mcause_data,
    output reg [`PC_WIDTH-1:0] csr_mtvac_data,

    // 异常入口 & 返回地址
    input  wire [`PC_WIDTH-1:0] csr_mtvec,    // 异常入口基地址
    input  wire [`PC_WIDTH-1:0] csr_mepc,     // 中断返回PC
    output reg [`PC_WIDTH-1:0] trap_pc,      // 跳转到异常处理函数

    // 中断返回指令（mret）
    input  wire         mret_en,
    output reg          mret_ready
);

// ==============================
// 状态定义
// ==============================
localparam STATE_IDLE      = 3'b001;  // 正常运行
localparam STATE_TRAP      = 3'b010;  // 进入异常/中断
localparam STATE_MRET      = 3'b100;  // 中断返回

reg [2:0] curr_state;
reg [2:0] next_state;

// ==============================
// 中断优先级 & 仲裁
// ==============================
// 异常 > 定时器 > 外部 > 软件
wire excp_valid = id_excp_en || mmu_excp_en;

reg        int_selected;
reg [3:0]  trap_cause;
reg [`PC_WIDTH-1:0] trap_pc_val;
reg [`PC_WIDTH-1:0] trap_val;

always @(*) begin
    int_selected = 1'b0;
    trap_cause   = 4'b0000;
    trap_pc_val  = 32'b0;
    trap_val     = 32'b0;

    // 1. 异常（最高优先级）
    if (id_excp_en) begin
        int_selected = 1'b1;
        trap_cause   = id_excp_code;
        trap_pc_val  = id_excp_pc;
        trap_val     = 32'b0;
    end
    else if (mmu_excp_en) begin
        int_selected = 1'b1;
        trap_cause   = mmu_excp_code;
        trap_pc_val  = id_excp_pc;
        trap_val     = mmu_excp_vaddr;
    end
    // 2. 中断（全局使能 + 对应掩码）
    else if (csr_mstatus_mie && !excp_valid) begin
        if (timer_int_req && csr_mie[`MIE_TIMER]) begin
            int_selected = 1'b1;
            trap_cause   = `EXCP_TIMER_INT;
            trap_pc_val  = id_excp_pc;
        end
        else if (ext_int_req && csr_mie[`MIE_EXT]) begin
            int_selected = 1'b1;
            trap_cause   = `EXCP_EXT_INT;
            trap_pc_val  = id_excp_pc;
        end
        else if (sw_int_req && csr_mie[`MIE_SW]) begin
            int_selected = 1'b1;
            trap_cause   = `EXCP_SW_INT;
            trap_pc_val  = id_excp_pc;
        end
    end
end

// ==============================
// 状态机时序逻辑
// ==============================
always @(posedge clk or posedge reset) begin
    if (reset)
        curr_state <= STATE_IDLE;
    else if (!core_stall)
        curr_state <= next_state;
end

// ==============================
// 状态机组合逻辑
// ==============================
always @(*) begin
    next_state = curr_state;

    case (curr_state)
        STATE_IDLE: begin
            if ((int_selected || excp_valid) && !core_stall)
                next_state = STATE_TRAP;
            else if (mret_en)
                next_state = STATE_MRET;
        end

        STATE_TRAP: begin
            next_state = STATE_IDLE;
        end

        STATE_MRET: begin
            next_state = STATE_IDLE;
        end
    endcase
end

// ==============================
// 控制信号输出
// ==============================
always @(*) begin
    excp_flush   = 1'b0;
    int_trap_en  = 1'b0;
    trap_pc      = 32'b0;
    mret_ready   = 1'b0;

    csr_mstatus_upd = 1'b0;
    csr_mepc_upd    = 1'b0;
    csr_mcause_upd  = 1'b0;
    csr_mtvac_upd   = 1'b0;

    csr_mepc_data   = 32'b0;
    csr_mcause_data = 4'b0;
    csr_mtvac_data  = 32'b0;

    case (curr_state)
        STATE_IDLE: begin end

        // 进入异常/中断
        STATE_TRAP: begin
            excp_flush   = 1'b1;          // 冲刷流水线
            int_trap_en  = 1'b1;          // 通知流水线跳转
            trap_pc      = csr_mtvec;     // PC = 异常入口

            // 更新 CSR
            csr_mepc_upd    = 1'b1;
            csr_mcause_upd  = 1'b1;
            csr_mtvac_upd   = 1'b1;
            csr_mstatus_upd = 1'b1;

            csr_mepc_data   = trap_pc_val;
            csr_mcause_data = trap_cause;
            csr_mtvac_data  = trap_val;
        end

        // mret 返回
        STATE_MRET: begin
            mret_ready     = 1'b1;
            trap_pc        = csr_mepc;    // 返回断点
            csr_mstatus_upd= 1'b1;        // 恢复 mstatus
        end
    endcase
end

endmodule