`ifndef __RISCV_EXCP_DEFINES_H__
`define __RISCV_EXCP_DEFINES_H__

    // 异常 & 中断原因编码
    `define EXCP_INST_ADDR_MISALIGN = 4'b0000;
`define EXCP_INST_ACCESS_FAULT = 4'b0001;
`define EXCP_ILLEGAL_INST = 4'b0010;
`define EXCP_BREAKPOINT = 4'b0011;
`define EXCP_LOAD_ADDR_MISALIGN = 4'b0100;
`define EXCP_LOAD_ACCESS_FAULT = 4'b0101;
`define EXCP_STORE_ADDR_MISALIGN = 4'b0110;
`define EXCP_STORE_ACCESS_FAULT = 4'b0111;
`define EXCP_ECALL_U = 4'b1000;
`define EXCP_ECALL_M = 4'b1011;

// 中断编码
`define EXCP_SW_INT = 4'b1100;
`define EXCP_TIMER_INT = 4'b1101;
`define EXCP_EXT_INT = 4'b1110;

// MIE 中断掩码位
`define MIE_SW = 0;
`define MIE_TIMER = 1;
`define MIE_EXT = 2;

`endif