`ifndef __RISCV_DEFINES_H__
`define __RISCV_DEFINES_H__

    // 数据位宽
`define REG_WIDTH 32
`define PC_WIDTH 32
`define INST_WIDTH 32

    // 特权级
`define PRIV_U 2'b00
`define PRIV_S 2'b01
`define PRIV_M 2'b11

    // 存储器访问类型
`define MEM_NONE 2'b00
`define MEM_READ 2'b01
`define MEM_WRITE 2'b10
`define MEM_EXEC 2'b11

    // ALU 操作
`define ALU_OP_ADD 4'b0000
`define ALU_OP_SUB 4'b0001
`define ALU_OP_SLL 4'b0010
`define ALU_OP_SLT 4'b0011
`define ALU_OP_SLTU 4'b0100
`define ALU_OP_XOR 4'b0101
`define ALU_OP_SRL 4'b0110
`define ALU_OP_SRA 4'b0111
`define ALU_OP_OR 4'b1000
`define ALU_OP_AND 4'b1001
`define ALU_OP_LUI 4'b1010
`define ALU_OP_AUIPC 4'b1011
`define ALU_OP_JAL 4'b1100
`define ALU_OP_JALR 4'b1101
`define ALU_OP_PASS_RS1 4'b1110
`define ALU_OP_PASS_IMM 4'b1111

    // MEM 操作
`define MEM_OP_NONE 2'b00
`define MEM_OP_LB 2'b01
`define MEM_OP_LH 2'b10
`define MEM_OP_LW 2'b11
`define MEM_OP_SB 2'b01
`define MEM_OP_SH 2'b10
`define MEM_OP_SW 2'b11

`endif