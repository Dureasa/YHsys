`ifndef __RISCV_CSR_DEFINES_H__
`define __RISCV_CSR_DEFINES_H__

    // ------------------------------
    // CSR 地址定义 (RV32 M-mode)
    // ------------------------------
`define CSR_MSTATUS 768 // 12'h300
`define CSR_MISA 769 // 12'h301
`define CSR_MIE 772 // 12'h304
`define CSR_MTVEC 773 // 12'h305
`define CSR_MSCRATCH 832 // 12'h340
`define CSR_MEPC 833 // 12'h341
`define CSR_MCAUSE 834 // 12'h342
`define CSR_MTVAL 835 // 12'h343
`define CSR_MIP 836 // 12'h344

    // ------------------------------
    // mstatus 位定义
    // ------------------------------
`define MSTATUS_MIE_BIT 3
`define MSTATUS_MPIE_BIT 7
`define MSTATUS_MPP_BIT 11
    /*
    `define MSTATUS_MIE(1 << 3) //(1 << `MSTATUS_MIE_BIT)
    `define MSTATUS_MPIE(1 << 7) //(1 << `MSTATUS_MPIE_BIT)
    `define MSTATUS_MPP(3 << 11) //(3 << `MSTATUS_MPP_BIT) // M-mode Prio
    */
    // ------------------------------
    // mie / mip 中断位
    // ------------------------------
`define MIE_SSIE_BIT 1
`define MIE_MSIE_BIT 3
`define MIE_STIE_BIT 5
`define MIE_MTIE_BIT 7
`define MIE_SEIE_BIT 9
`define MIE_MEIE_BIT 11
    /*
    `define MIE_MSIE(1 << `MIE_MSIE_BIT) // M-mode 软件中断
    `define MIE_MTIE(1 << `MIE_MTIE_BIT) // M-mode 定时器中断
    `define MIE_MEIE(1 << `MIE_MEIE_BIT) // M-mode 外部中断
    */
    // ------------------------------
    // mcause 编码 (与异常单元一致)
    // ------------------------------
`define MCAUSE_INT_BIT 31 // 最高位=1表示中断

    // 异常原因 (mcause[30:0])
`define EXC_INST_ADDR_MISALIGN 5'd0
`define EXC_INST_ACCESS_FAULT 5'd1
`define EXC_ILLEGAL_INST 5'd2
`define EXC_BREAKPOINT 5'd3
`define EXC_LOAD_ADDR_MISALIGN 5'd4
`define EXC_LOAD_ACCESS_FAULT 5'd5
`define EXC_STORE_ADDR_MISALIGN 5'd6
`define EXC_STORE_ACCESS_FAULT 5'd7
`define EXC_ECALL_U 5'd8
`define EXC_ECALL_M 5'd11

    // 中断原因 (mcause[30:0])
`define INT_SSIP 5'd1
`define INT_MSIP 5'd3
`define INT_STIP 5'd5
`define INT_MTIP 5'd7
`define INT_SEIP 5'd9
`define INT_MEIP 5'd11

    // ------------------------------
    // CSR 操作类型 (与ID阶段匹配)
    // ------------------------------
`define CSR_OP_READ 3'b000
`define CSR_OP_WRITE 3'b001
`define CSR_OP_SET 3'b010
`define CSR_OP_CLEAR 3'b011

`endif