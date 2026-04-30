`ifndef __RISCV_EXCP_DEFINES_H__
`define __RISCV_EXCP_DEFINES_H__

    // ------------------------------
    // 异常类型（mcause[3:0]）
    // ------------------------------
`define EXC_INSTR_ADDR_MIS 4'd0
`define EXC_INSTR_ACCESS_FAULT 4'd1
`define EXC_ILLEGAL_INST 4'd2
`define EXC_BREAKPOINT 4'd3
`define EXC_LOAD_ADDR_MIS 4'd4
`define EXC_LOAD_ACCESS_FAULT 4'd5
`define EXC_STORE_ADDR_MIS 4'd6
`define EXC_STORE_ACCESS_FAULT 4'd7

`define EXC_ECALL_U 4'd8
`define EXC_ECALL_S 4'd9
`define EXC_ECALL_M 4'd11

`define EXC_INSTR_PAGE_FAULT 4'd12
`define EXC_LOAD_PAGE_FAULT 4'd13
`define EXC_STORE_PAGE_FAULT 4'd15

    // ------------------------------
    // 中断类型
    // ------------------------------
`define EXC_SOFT_IRQ 4'd0
`define EXC_TIMER_IRQ 4'd1
`define EXC_EXT_IRQ 4'd2

`endif