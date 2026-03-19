`include "riscv_inst_defines.h"

module alu (
    input  wire [4:0]   alu_op,
    input  wire [31:0]  src1,
    input  wire [31:0]  src2,
    output reg  [31:0]  result,
    output wire         branch_taken
);

wire [31:0]  sub_result;
wire         eq, ne, lt, ltu;

assign sub_result = src1 - src2;
assign eq  = (src1 == src2);
assign ne  = ~eq;
assign lt  = ((src1[31] != src2[31]) && (src1[31] == 1)) || ((src1[31] == src2[31]) && (sub_result[31] == 1));
assign ltu = src1 < src2;

reg branch_real_taken;
assign branch_taken = branch_real_taken;

always @(*) begin
    branch_real_taken = 1'b0;
    result = 32'b0;
    case (alu_op)
        `ALU_OP_ADD:  result = src1 + src2;
        `ALU_OP_SUB:  result = sub_result;
        `ALU_OP_SLL:  result = src1 << src2[4:0];
        `ALU_OP_SLT:  result = {31'b0, lt};
        `ALU_OP_SLTU: result = {31'b0, ltu};
        `ALU_OP_XOR:  result = src1 ^ src2;
        `ALU_OP_SRL:  result = src1 >> src2[4:0];
        `ALU_OP_SRA:  result = $signed(src1) >>> src2[4:0];
        `ALU_OP_OR:   result = src1 | src2;
        `ALU_OP_AND:  result = src1 & src2;

        `ALU_OP_BRANCH: begin
            case (src2[2:0]) // funct3
                3'b000: branch_real_taken = eq;  // BEQ
                3'b001: branch_real_taken = ne;  // BNE
                3'b100: branch_real_taken = lt;  // BLT
                3'b101: branch_real_taken = ~lt; // BGE
                3'b110: branch_real_taken = ltu; // BLTU
                3'b111: branch_real_taken = ~ltu;// BGEU
                default: branch_real_taken = 1'b0;
            endcase
        end

        default: begin
            result = 32'b0;
            branch_real_taken = 1'b0;
        end
    endcase
end

endmodule