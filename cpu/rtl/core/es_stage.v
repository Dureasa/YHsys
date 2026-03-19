`include "riscv_defines.h"
`include "riscv_inst_defines.h"

module es_stage (
    // 时钟 & 复位
    input  wire                          clk                ,
    input  wire                          reset              ,

    // 流水线握手
    input  wire                          ms_allowin         ,  // 访存阶段允许进入
    output wire                          es_allowin         ,  // 本阶段允许进入
    output wire                          es_to_ms_valid     ,  // 到访存阶段有效

    // 来自译码阶段
    input  wire                          id_to_es_valid     ,
    input  wire [`ID_TO_ES_BUS_WD-1:0]    id_to_es_bus       ,

    // 到访存阶段总线
    output wire [`ES_TO_MS_BUS_WD-1:0]    es_to_ms_bus       ,

    // 数据前递（发给译码阶段）
    output wire [`ES_TO_DS_FORWARD_BUS-1:0] es_to_ds_forward_bus,

    // 冲刷信号
    input  wire                          excp_flush         ,
    input  wire                          branch_flush
);

//==========================================================================
// 内部信号定义
//==========================================================================
reg                          es_valid_r;

// 从 ID 阶段拆出来的信号
reg  [31:0]                  es_pc_r;
reg  [31:0]                  es_inst_r;
reg                          es_gr_we_r;
reg  [4:0]                   es_rd_r;
reg  [4:0]                   es_alu_op_r;
reg                          es_alu_src1_r;
reg                          es_alu_src2_r;
reg  [31:0]                  es_rs1_data_r;
reg  [31:0]                  es_rs2_data_r;
reg  [31:0]                  es_imm_r;
reg                          es_load_r;
reg                          es_store_r;
reg  [1:0]                   es_mem_size_r;
reg                          es_mem_sign_ext_r;
reg                          es_branch_r;
reg                          es_jump_r;
reg                          es_branch_taken_r;
reg  [31:0]                  es_branch_target_r;
reg                          es_illegal_r;
reg  [9:0]                   es_excp_num_r;
reg                          es_excp_r;
reg                          es_csr_inst_r;
reg                          es_csr_we_r;
reg  [11:0]                  es_csr_addr_r;
reg  [31:0]                  es_csr_rdata_r;

// ALU 操作数
wire [31:0]                  alu_src1;
wire [31:0]                  alu_src2;

// ALU 输出
wire [31:0]                  alu_result;
wire                         alu_branch_taken; // 实际分支是否跳转

// 前递
assign es_to_ds_forward_bus = {es_gr_we_r, es_rd_r, alu_result};

//==========================================================================
// 流水线握手控制
//==========================================================================
wire es_ready_go = 1'b1; // 单周期 ALU，无阻塞

assign es_allowin     = !es_valid_r || (es_ready_go && ms_allowin);
assign es_to_ms_valid = es_valid_r  && es_ready_go;

always @(posedge clk or posedge reset) begin
    if (reset) begin
        es_valid_r <= 1'b0;
    end else if (excp_flush || branch_flush) begin
        es_valid_r <= 1'b0;
    end else if (es_allowin) begin
        es_valid_r <= id_to_es_valid;
    end
end

//==========================================================================
// 锁存 ID->ES 总线
//==========================================================================
always @(posedge clk or posedge reset) begin
    if (reset) begin
        es_pc_r           <= 32'b0;
        es_inst_r         <= 32'b0;
        es_gr_we_r        <= 1'b0;
        es_rd_r           <= 5'b0;
        es_alu_op_r       <= 5'b0;
        es_alu_src1_r     <= 1'b0;
        es_alu_src2_r     <= 1'b0;
        es_rs1_data_r     <= 32'b0;
        es_rs2_data_r     <= 32'b0;
        es_imm_r          <= 32'b0;
        es_load_r         <= 1'b0;
        es_store_r        <= 1'b0;
        es_mem_size_r     <= 2'b0;
        es_mem_sign_ext_r <= 1'b0;
        es_branch_r       <= 1'b0;
        es_jump_r         <= 1'b0;
        es_branch_taken_r <= 1'b0;
        es_branch_target_r<= 32'b0;
        es_illegal_r      <= 1'b0;
        es_excp_num_r     <= 10'b0;
        es_excp_r         <= 1'b0;
        es_csr_inst_r     <= 1'b0;
        es_csr_we_r       <= 1'b0;
        es_csr_addr_r     <= 12'b0;
        es_csr_rdata_r    <= 32'b0;
    end else if (es_allowin) begin
        {
            es_pc_r,
            es_inst_r,
            es_gr_we_r,
            es_rd_r,
            es_alu_op_r,
            es_alu_src1_r,
            es_alu_src2_r,
            es_rs1_data_r,
            es_rs2_data_r,
            es_imm_r,
            es_load_r,
            es_store_r,
            es_mem_size_r,
            es_mem_sign_ext_r,
            es_branch_r,
            es_jump_r,
            es_branch_taken_r,
            es_branch_target_r,
            es_illegal_r,
            es_excp_num_r,
            es_excp_r,
            es_csr_inst_r,
            es_csr_we_r,
            es_csr_addr_r,
            es_csr_rdata_r
        } <= id_to_es_bus;
    end
end

//==========================================================================
// ALU 操作数选择
//==========================================================================
assign alu_src1 = es_alu_src1_r ? es_pc_r : es_rs1_data_r;
assign alu_src2 = es_alu_src2_r ? es_imm_r : es_rs2_data_r;

//==========================================================================
// ALU 实例化
//==========================================================================
alu u_alu (
    .alu_op        (es_alu_op_r),
    .src1          (alu_src1),
    .src2          (alu_src2),
    .result        (alu_result),
    .branch_taken  (alu_branch_taken)
);

//==========================================================================
// 输出到 MS 阶段
//==========================================================================
assign es_to_ms_bus = {
    es_pc_r,
    es_gr_we_r,
    es_rd_r,
    alu_result,        // 访存地址 or 运算结果
    es_rs2_data_r,     // store 数据
    es_load_r,
    es_store_r,
    es_mem_size_r,
    es_mem_sign_ext_r,
    es_branch_r,
    alu_branch_taken,  // 实际跳转
    es_branch_target_r,
    es_jump_r,
    es_illegal_r,
    es_excp_num_r,
    es_excp_r,
    es_csr_inst_r,
    es_csr_we_r,
    es_csr_addr_r,
    es_csr_rdata_r
};

endmodule