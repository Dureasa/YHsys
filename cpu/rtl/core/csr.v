`include "riscv_defines.h"
`include "riscv_csr_defines.h"
`include "riscv_excp_defines.h"

module exception_unit (
    // 时钟 & 复位
    input  wire                         clk,
    input  wire                         reset,

    // 全局流水线控制
    output wire                         core_stall,
    output wire                         excp_flush,
    output wire                         if_excp_flush,

    // ==================== 来自各阶段的异常 ====================
    input  wire                         if_excp_en,
    input  wire [3:0]                   if_excp_code,
    input  wire [`PC_WIDTH-1:0]         if_excp_pc,

    input  wire                         id_excp_en,
    input  wire [3:0]                   id_excp_code,
    input  wire [`PC_WIDTH-1:0]         id_excp_pc,

    input  wire                         ex_excp_en,
    input  wire [3:0]                   ex_excp_code,
    input  wire [`PC_WIDTH-1:0]         ex_excp_pc,

    input  wire                         mem_excp_en,
    input  wire [3:0]                   mem_excp_code,
    input  wire [`PC_WIDTH-1:0]         mem_excp_pc,

    // ==================== 外部中断 ====================
    input  wire                         ext_irq,
    input  wire                         timer_irq,
    input  wire                         soft_irq,

    // ==================== CSR 状态 ====================
    input  wire [`REG_WIDTH-1:0]        csr_mstatus,
    input  wire [`REG_WIDTH-1:0]        csr_mepc,
    input  wire [`REG_WIDTH-1:0]        csr_mcause,
    input  wire [`REG_WIDTH-1:0]        csr_mtvec,
    input  wire [`REG_WIDTH-1:0]        csr_stvec,
    input  wire [`REG_WIDTH-1:0]        csr_medeleg,   // 异常委托 S-mode
    input  wire [`REG_WIDTH-1:0]        csr_mideleg,   // 中断委托 S-mode
    input  wire [`REG_WIDTH-1:0]        csr_mie,
    input  wire [`REG_WIDTH-1:0]        csr_mip,

    // ==================== CSR 写接口 ====================
    output reg                          csr_wr_en,
    output reg  [11:0]                  csr_wr_addr,
    output reg  [`REG_WIDTH-1:0]        csr_wr_data,

    // ==================== 特权级 ====================
    input  wire [1:0]                   cur_priv_level,  // M=11 S=01 U=00

    // ==================== PC 重定向 ====================
    output reg                          pc_redirect_en,
    output reg  [`PC_WIDTH-1:0]         pc_redirect_addr,

    // ==================== 输出 ====================
    output reg                          in_trap
);

// ==================== 特权级定义 ====================
localparam PRIV_U        = 2'b00;
localparam PRIV_S        = 2'b01;
localparam PRIV_M        = 2'b11;

// ==================== 中断/异常位 ====================
localparam MIE_BIT       = 3;
localparam SIE_BIT       = 1;

// ==================== 内部信号 ====================
reg                         trap_en;
reg [3:0]                   trap_code;
reg [`PC_WIDTH-1:0]         trap_pc;
reg                         is_irq;
reg                         trap_to_s;    // 1=进入S-mode 0=进入M-mode
reg                         is_ecall;

// ==================== 全局输出 ====================
assign core_stall   = trap_en;
assign excp_flush   = trap_en;
assign if_excp_flush= trap_en;

// ==================== 异常/中断 仲裁 & 委托选择 ====================
always @(*) begin
    trap_en     = 1'b0;
    trap_code   = 4'b0;
    trap_pc     = 32'b0;
    is_irq      = 1'b0;
    trap_to_s   = 1'b0;
    is_ecall    = 1'b0;

    // ---------------- 中断（遵循 mideleg 委托）----------------
    if ((cur_priv_level == PRIV_M && csr_mstatus[MIE_BIT]) ||
        (cur_priv_level == PRIV_S && csr_mstatus[SIE_BIT]) ||
        (cur_priv_level == PRIV_U)) begin

        if (ext_irq && csr_mie[11] && csr_mip[11]) begin
            trap_en     = 1'b1;
            trap_code   = `EXC_EXT_IRQ;
            is_irq      = 1'b1;
            trap_to_s   = csr_mideleg[11];
        end
        else if (timer_irq && csr_mie[7] && csr_mip[7]) begin
            trap_en     = 1'b1;
            trap_code   = `EXC_TIMER_IRQ;
            is_irq      = 1'b1;
            trap_to_s   = csr_mideleg[7];
        end
        else if (soft_irq && csr_mie[3] && csr_mip[3]) begin
            trap_en     = 1'b1;
            trap_code   = `EXC_SOFT_IRQ;
            is_irq      = 1'b1;
            trap_to_s   = csr_mideleg[3];
        end
    end

    // ---------------- 流水线异常（遵循 medeleg 委托）----------------
    if (mem_excp_en) begin
        trap_en     = 1'b1;
        trap_code   = mem_excp_code;
        trap_pc     = mem_excp_pc;
        is_irq      = 1'b0;
        trap_to_s   = csr_medeleg[trap_code];
        is_ecall    = (trap_code == `EXC_ECALL_U || trap_code == `EXC_ECALL_S || trap_code == `EXC_ECALL_M);
    end
    else if (ex_excp_en) begin
        trap_en     = 1'b1;
        trap_code   = ex_excp_code;
        trap_pc     = ex_excp_pc;
        is_irq      = 1'b0;
        trap_to_s   = csr_medeleg[trap_code];
        is_ecall    = (trap_code == `EXC_ECALL_U || trap_code == `EXC_ECALL_S || trap_code == `EXC_ECALL_M);
    end
    else if (id_excp_en) begin
        trap_en     = 1'b1;
        trap_code   = id_excp_code;
        trap_pc     = id_excp_pc;
        is_irq      = 1'b0;
        trap_to_s   = csr_medeleg[trap_code];
    end
    else if (if_excp_en) begin
        trap_en     = 1'b1;
        trap_code   = if_excp_code;
        trap_pc     = if_excp_pc;
        is_irq      = 1'b0;
        trap_to_s   = csr_medeleg[trap_code];
    end

    // ---------------- ecall 规则：U→S  S→M  M→M ----------------
    if (is_ecall) begin
        case (cur_priv_level)
            PRIV_U: trap_to_s = 1'b1;
            PRIV_S: trap_to_s = 1'b0;
            PRIV_M: trap_to_s = 1'b0;
            default: trap_to_s = 1'b0;
        endcase
    end
end

// ==================== Trap 处理 & CSR 写入 ====================
always @(posedge clk or posedge reset) begin
    if (reset) begin
        csr_wr_en        <= 1'b0;
        csr_wr_addr      <= 12'b0;
        csr_wr_data      <= 32'b0;
        pc_redirect_en   <= 1'b0;
        pc_redirect_addr <= 32'h80000000;
        in_trap          <= 1'b0;
    end
    else if (trap_en && !in_trap) begin
        in_trap          <= 1'b1;
        pc_redirect_en   <= 1'b1;

        // ---------------- 进入 S-mode ----------------
        if (trap_to_s) begin
            // sepc
            csr_wr_en        <= 1'b1;
            csr_wr_addr      <= `CSR_sepc;
            csr_wr_data      <= trap_pc;

            // scause
            csr_wr_en        <= 1'b1;
            csr_wr_addr      <= `CSR_scause;
            csr_wr_data      <= {27'b0, is_irq, 4'b0, trap_code};

            // sstatus
            csr_wr_en        <= 1'b1;
            csr_wr_addr      <= `CSR_sstatus;
            csr_wr_data      <= csr_mstatus;
            csr_wr_data[5]   <= csr_mstatus[1];  // SPIE = SIE
            csr_wr_data[1]   <= 1'b0;            // SIE = 0
            csr_wr_data[12:11] <= cur_priv_level;// SPP

            // 跳转到 stvec
            pc_redirect_addr <= csr_stvec;
        end

        // ---------------- 进入 M-mode ----------------
        else begin
            // mepc
            csr_wr_en        <= 1'b1;
            csr_wr_addr      <= `CSR_mepc;
            csr_wr_data      <= trap_pc;

            // mcause
            csr_wr_en        <= 1'b1;
            csr_wr_addr      <= `CSR_mcause;
            csr_wr_data      <= {27'b0, is_irq, 4'b0, trap_code};

            // mstatus
            csr_wr_en        <= 1'b1;
            csr_wr_addr      <= `CSR_mstatus;
            csr_wr_data      <= csr_mstatus;
            csr_wr_data[7]   <= csr_mstatus[3];  // MPIE = MIE
            csr_wr_data[3]   <= 1'b0;            // MIE = 0
            csr_wr_data[12:11]<= cur_priv_level;// MPP

            // 跳转到 mtvec
            pc_redirect_addr <= csr_mtvec;
        end
    end
    else begin
        csr_wr_en        <= 1'b0;
        csr_wr_addr      <= 12'b0;
        csr_wr_data      <= 32'b0;
        pc_redirect_en   <= 1'b0;
        in_trap          <= 1'b0;
    end
end

endmodule