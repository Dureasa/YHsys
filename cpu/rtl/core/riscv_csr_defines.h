`ifndef __RISCV_CSR_DEFINES_H__
`define __RISCV_CSR_DEFINES_H__

    // ------------------------------
    // CSR 地址（RISC-V 标准）
    // ------------------------------

    // M-mode CSR
`define CSR_mstatus 12'h300
`define CSR_misa 12'h301
`define CSR_medeleg 12'h302
`define CSR_mideleg 12'h303
`define CSR_mie 12'h304
`define CSR_mtvec 12'h305
`define CSR_mscratch 12'h340
`define CSR_mepc 12'h341
`define CSR_mcause 12'h342
`define CSR_mip 12'h344

    // S-mode CSR
`define CSR_sstatus 12'h100
`define CSR_stvec 12'h105
`define CSR_sscratch 12'h140
`define CSR_sepc 12'h141
`define CSR_scause 12'h142
`define CSR_satp 12'h180

    // U-mode CSR
`define CSR_ustatus 12'h000
`define CSR_utvec 12'h005
`define CSR_uscratch 12'h040
`define CSR_uepc 12'h041
`define CSR_ucause 12'h042

    // ------------------------------
    // CSR 操作
    // ------------------------------
`define CSR_OP_READ 3'b000
`define CSR_OP_WRITE 3'b001
`define CSR_OP_SET 3'b010
`define CSR_OP_CLEAR 3'b011

    // ------------------------------
    // mstatus 位
    // ------------------------------
`define MIE_BIT 3
`define MPIE_BIT 7
`define MPP_H 12
`define MPP_L 11
`define SIE_BIT 1
`define SPIE_BIT 5
`define SPP_BIT 8

    // ------------------------------
    // mie / mip 位
    // ------------------------------
`define MSIE_BIT 3
`define MTIE_BIT 7
`define MEIE_BIT 11

`define SSIE_BIT 1
`define STIE_BIT 5
`define SEIE_BIT 9

`endif