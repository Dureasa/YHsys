.section .text
.globl main
main:
  addi sp, sp, -48
  sw s0, 40(sp)
  sw ra, 44(sp)
  mv s0, sp
  li t0, 0
  sw t0, 32(s0)
  li t0, 0
  sw t0, 36(s0)
  sw zero, 0(s0)
  sw zero, 4(s0)
  sw zero, 8(s0)
  sw zero, 12(s0)
  sw zero, 16(s0)
  sw zero, 20(s0)
  sw zero, 24(s0)
  sw zero, 28(s0)
.L_user_while_cond_1:
  lw t0, 32(s0)
  addi sp, sp, -4
  sw t0, 0(sp)
  li t0, 8
  mv t1, t0
  lw t0, 0(sp)
  addi sp, sp, 4
  slt t0, t0, t1
  bne t0, zero, .L_user_while_body_2
  j .L_user_while_end_3
.L_user_while_body_2:
  lw t0, 32(s0)
  addi sp, sp, -4
  sw t0, 0(sp)
  li t0, 3
  mv t1, t0
  lw t0, 0(sp)
  addi sp, sp, 4
  mul t0, t0, t1
  addi sp, sp, -4
  sw t0, 0(sp)
  li t0, 1
  mv t1, t0
  lw t0, 0(sp)
  addi sp, sp, 4
  add t0, t0, t1
  addi sp, sp, -4
  sw t0, 0(sp)
  lw t0, 32(s0)
  slli t0, t0, 2
  addi t1, s0, 0
  add t1, t1, t0
  lw t2, 0(sp)
  addi sp, sp, 4
  sw t2, 0(t1)
  lw t0, 32(s0)
  addi sp, sp, -4
  sw t0, 0(sp)
  li t0, 1
  mv t1, t0
  lw t0, 0(sp)
  addi sp, sp, 4
  add t0, t0, t1
  sw t0, 32(s0)
  j .L_user_while_cond_1
.L_user_while_end_3:
  li t0, 0
  sw t0, 32(s0)
.L_user_while_cond_4:
  lw t0, 32(s0)
  addi sp, sp, -4
  sw t0, 0(sp)
  li t0, 8
  mv t1, t0
  lw t0, 0(sp)
  addi sp, sp, 4
  slt t0, t0, t1
  bne t0, zero, .L_user_while_body_5
  j .L_user_while_end_6
.L_user_while_body_5:
  lw t0, 32(s0)
  slli t0, t0, 2
  addi t1, s0, 0
  add t1, t1, t0
  lw t0, 0(t1)
  addi sp, sp, -4
  sw t0, 0(sp)
  li t0, 1
  mv t1, t0
  lw t0, 0(sp)
  addi sp, sp, 4
  and t0, t0, t1
  addi sp, sp, -4
  sw t0, 0(sp)
  li t0, 1
  mv t1, t0
  lw t0, 0(sp)
  addi sp, sp, 4
  xor t0, t0, t1
  seqz t0, t0
  bne t0, zero, .L_user_if_then_7
  j .L_user_if_else_8
.L_user_if_then_7:
  lw t0, 36(s0)
  addi sp, sp, -4
  sw t0, 0(sp)
  lw t0, 32(s0)
  slli t0, t0, 2
  addi t1, s0, 0
  add t1, t1, t0
  lw t0, 0(t1)
  mv t1, t0
  lw t0, 0(sp)
  addi sp, sp, 4
  add t0, t0, t1
  sw t0, 36(s0)
  j .L_user_if_end_9
.L_user_if_else_8:
  lw t0, 32(s0)
  slli t0, t0, 2
  addi t1, s0, 0
  add t1, t1, t0
  lw t0, 0(t1)
  addi sp, sp, -4
  sw t0, 0(sp)
  li t0, 1
  mv t1, t0
  lw t0, 0(sp)
  addi sp, sp, 4
  sra t0, t0, t1
  addi sp, sp, -4
  sw t0, 0(sp)
  li t0, 2
  mv t1, t0
  lw t0, 0(sp)
  addi sp, sp, 4
  slt t0, t0, t1
  xori t0, t0, 1
  bne t0, zero, .L_user_if_then_10
  j .L_user_if_else_11
.L_user_if_then_10:
  lw t0, 36(s0)
  addi sp, sp, -4
  sw t0, 0(sp)
  lw t0, 32(s0)
  slli t0, t0, 2
  addi t1, s0, 0
  add t1, t1, t0
  lw t0, 0(t1)
  addi sp, sp, -4
  sw t0, 0(sp)
  li t0, 2
  mv t1, t0
  lw t0, 0(sp)
  addi sp, sp, 4
  div t0, t0, t1
  mv t1, t0
  lw t0, 0(sp)
  addi sp, sp, 4
  sub t0, t0, t1
  sw t0, 36(s0)
  j .L_user_if_end_12
.L_user_if_else_11:
  lw t0, 36(s0)
  addi sp, sp, -4
  sw t0, 0(sp)
  lw t0, 32(s0)
  slli t0, t0, 2
  addi t1, s0, 0
  add t1, t1, t0
  lw t0, 0(t1)
  mv t1, t0
  lw t0, 0(sp)
  addi sp, sp, 4
  xor t0, t0, t1
  sw t0, 36(s0)
.L_user_if_end_12:
.L_user_if_end_9:
  lw t0, 32(s0)
  addi sp, sp, -4
  sw t0, 0(sp)
  li t0, 1
  mv t1, t0
  lw t0, 0(sp)
  addi sp, sp, 4
  add t0, t0, t1
  sw t0, 32(s0)
  j .L_user_while_cond_4
.L_user_while_end_6:
  lw t0, 36(s0)
  mv a0, t0
  jal ra, .L_print_int
  lw t0, 36(s0)
  xori t0, t0, -1
  mv a0, t0
  jal ra, .L_print_int
  lw t0, 36(s0)
  addi sp, sp, -4
  sw t0, 0(sp)
  li t0, 1
  mv t1, t0
  lw t0, 0(sp)
  addi sp, sp, 4
  sll t0, t0, t1
  addi sp, sp, -4
  sw t0, 0(sp)
  li t0, 3
  mv t1, t0
  lw t0, 0(sp)
  addi sp, sp, 4
  or t0, t0, t1
  mv a0, t0
  jal ra, .L_print_int
  li t0, 0
  mv a0, t0
  li a7, 2
  ecall
  j .L_halt
.L_halt:
  j .L_halt

.L_print_int:
  addi sp, sp, -64
  sw ra, 60(sp)
  sw s0, 56(sp)
  mv s0, a0
  addi t1, sp, 48
  li t2, 0
  bge s0, zero, .L_pi_abs_done
  li t2, 1
  sub s0, zero, s0
.L_pi_abs_done:
  mv t3, s0
  bne t3, zero, .L_pi_digits
  addi t1, t1, -1
  li t4, 48
  sb t4, 0(t1)
  j .L_pi_sign
.L_pi_digits:
  li t5, 10
.L_pi_loop:
  remu t6, t3, t5
  divu t3, t3, t5
  addi t6, t6, 48
  addi t1, t1, -1
  sb t6, 0(t1)
  bne t3, zero, .L_pi_loop
.L_pi_sign:
  beq t2, zero, .L_pi_newline
  addi t1, t1, -1
  li t6, 45
  sb t6, 0(t1)
.L_pi_newline:
  li t6, 10
  sb t6, 48(sp)
  addi t3, sp, 49
  sub a2, t3, t1
  li a0, 1
  mv a1, t1
  li a7, 16
  ecall
  lw ra, 60(sp)
  lw s0, 56(sp)
  addi sp, sp, 64
  ret

.section .rodata
.globl yhc_prog_name_yhc_prog
yhc_prog_name_yhc_prog:
.byte 121, 104, 99, 95, 112, 114, 111, 103, 0
