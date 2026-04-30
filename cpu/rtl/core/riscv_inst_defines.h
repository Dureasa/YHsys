`ifndef RISCV_INST_DEFINES_H
`define RISCV_INST_DEFINES_H

    // 操作码（opcode）
`define OPCODE_RTYPE 7'b0110011 // R类型
`define OPCODE_ITYPE 7'b0010011 // I类型（立即数）
`define OPCODE_LOAD 7'b0000011 // I类型（加载）
`define OPCODE_STORE 7'b0100011 // S类型（存储）
`define OPCODE_BRANCH 7'b1100011 // B类型（分支）
`define OPCODE_JAL 7'b1101111 // J类型（跳转）
`define OPCODE_JALR 7'b1100111 // I类型（跳转）
`define OPCODE_LUI 7'b0110111 // U类型（高位立即数）
`define OPCODE_AUIPC 7'b0010111 // U类型（PC相对高位立即数）
`define OPCODE_CSR 7'b1110011 // 系统指令（CSR）

    // 功能码3（funct3）
`define FUNCT3_ADD_SUB 3'b000
`define FUNCT3_SLL 3'b001
`define FUNCT3_SLT 3'b010
`define FUNCT3_SLTU 3'b011
`define FUNCT3_XOR 3'b100
`define FUNCT3_SRL_SRA 3'b101
`define FUNCT3_OR 3'b110
`define FUNCT3_AND 3'b111

`define FUNCT3_LB 3'b000
`define FUNCT3_LH 3'b001
`define FUNCT3_LW 3'b010
`define FUNCT3_LBU 3'b100
`define FUNCT3_LHU 3'b101

`define FUNCT3_SB 3'b000
`define FUNCT3_SH 3'b001
`define FUNCT3_SW 3'b010

`define FUNCT3_BEQ 3'b000
`define FUNCT3_BNE 3'b001
`define FUNCT3_BLT 3'b100
`define FUNCT3_BGE 3'b101
`define FUNCT3_BLTU 3'b110
`define FUNCT3_BGEU 3'b111

`define FUNCT3_CSRRW 3'b001
`define FUNCT3_CSRRS 3'b010
`define FUNCT3_CSRRC 3'b011
`define FUNCT3_CSRRWI 3'b101
`define FUNCT3_CSRRSI 3'b110
`define FUNCT3_CSRRCI 3'b111

    // 功能码7（funct7）
`define FUNCT7_SUB 7'b0100000
`define FUNCT7_SRA 7'b0100000

    // ALU操作类型
`define ALU_OP_ADD 5'b00000
`define ALU_OP_SUB 5'b00001
`define ALU_OP_SLL 5'b00010
`define ALU_OP_SLT 5'b00011
`define ALU_OP_SLTU 5'b00100
`define ALU_OP_XOR 5'b00101
`define ALU_OP_SRL 5'b00110
`define ALU_OP_SRA 5'b00111
`define ALU_OP_OR 5'b01000
`define ALU_OP_AND 5'b01001
`define ALU_OP_BRANCH 5'b01010

`endif