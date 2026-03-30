
`ifndef RISCV_DEFINES_H
`define RISCV_DEFINES_H

    // 基础位宽定义
`define PC_WIDTH 32
`define INST_WIDTH 32
    //`define RESET_PC            32'h80000000

    // 总线位宽定义
`define IF_TO_ID_PC_WD 32
`define IF_TO_ID_INST_WD 32
`define IF_TO_ID_MISS_WD 1
`define IF_TO_ID_FLUSH_WD 1
`define IF_TO_ID_VALID_WD 1
`define IF_TO_ID_BUS_WD 67
    //(`IF_TO_ID_PC_WD + `IF_TO_ID_INST_WD + `IF_TO_ID_MISS_WD + `IF_TO_ID_FLUSH_WD + `IF_TO_ID_VALID_WD)

`define ID_TO_ES_BUS_WD 512 // 可根据实际需求调整

    // ES->MS 总线位宽
`define ES_TO_MS_BUS_WD 224

    // ES->DS forward bus: we(1) + rd(5) + data(32)
`define ES_TO_DS_FORWARD_BUS 38

    // MS->WB 总线位宽
`define MS_TO_WB_BUS_WD 144

    // MS->DS 前递总线：写使能(1) + 目标寄存器(5) + 数据(32)
`define MS_TO_DS_FORWARD_BUS 39

    // 异常号定义
    //`define EXCP_ILLEGAL_INST 10'b0000000001



`endif