.section .text
.globl main
main:
  addi sp, sp, -32
  sw s0, 24(sp)
  sw ra, 28(sp)
  mv s0, sp
  li t0, 6
  sw t0, 16(s0)
  li t0, 3
  sw t0, 20(s0)
  sw zero, 0(s0)
  sw zero, 4(s0)
  sw zero, 8(s0)
  sw zero, 12(s0)
  lw t0, 16(s0)
  addi sp, sp, -4
  sw t0, 0(sp)
  lw t0, 20(s0)
  addi sp, sp, -4
  sw t0, 0(sp)
  li t0, 2
  mv t1, t0
  lw t0, 0(sp)
  addi sp, sp, 4
  mul t0, t0, t1
  mv t1, t0
  lw t0, 0(sp)
  addi sp, sp, 4
  add t0, t0, t1
  addi sp, sp, -4
  sw t0, 0(sp)
  li t0, 0
  slli t0, t0, 2
  addi t1, s0, 0
  add t1, t1, t0
  lw t2, 0(sp)
  addi sp, sp, 4
  sw t2, 0(t1)
  lw t0, 16(s0)
  addi sp, sp, -4
  sw t0, 0(sp)
  lw t0, 20(s0)
  mv t1, t0
  lw t0, 0(sp)
  addi sp, sp, 4
  sub t0, t0, t1
  addi sp, sp, -4
  sw t0, 0(sp)
  lw t0, 16(s0)
  addi sp, sp, -4
  sw t0, 0(sp)
  lw t0, 20(s0)
  mv t1, t0
  lw t0, 0(sp)
  addi sp, sp, 4
  add t0, t0, t1
  mv t1, t0
  lw t0, 0(sp)
  addi sp, sp, 4
  mul t0, t0, t1
  addi sp, sp, -4
  sw t0, 0(sp)
  li t0, 1
  slli t0, t0, 2
  addi t1, s0, 0
  add t1, t1, t0
  lw t2, 0(sp)
  addi sp, sp, 4
  sw t2, 0(t1)
  li t0, 0
  slli t0, t0, 2
  addi t1, s0, 0
  add t1, t1, t0
  lw t0, 0(t1)
  addi sp, sp, -4
  sw t0, 0(sp)
  li t0, 5
  mv t1, t0
  lw t0, 0(sp)
  addi sp, sp, 4
  rem t0, t0, t1
  addi sp, sp, -4
  sw t0, 0(sp)
  li t0, 2
  slli t0, t0, 2
  addi t1, s0, 0
  add t1, t1, t0
  lw t2, 0(sp)
  addi sp, sp, 4
  sw t2, 0(t1)
  li t0, 2
  slli t0, t0, 2
  addi t1, s0, 0
  add t1, t1, t0
  lw t0, 0(t1)
  xori t0, t0, -1
  addi sp, sp, -4
  sw t0, 0(sp)
  li t0, 15
  mv t1, t0
  lw t0, 0(sp)
  addi sp, sp, 4
  and t0, t0, t1
  addi sp, sp, -4
  sw t0, 0(sp)
  li t0, 3
  slli t0, t0, 2
  addi t1, s0, 0
  add t1, t1, t0
  lw t2, 0(sp)
  addi sp, sp, 4
  sw t2, 0(t1)
  lw t0, 16(s0)
  addi sp, sp, -4
  sw t0, 0(sp)
  li t0, 10
  mv t1, t0
  lw t0, 0(sp)
  addi sp, sp, 4
  add t0, t0, t1
  sw t0, 16(s0)
  lw t0, 20(s0)
  addi sp, sp, -4
  sw t0, 0(sp)
  li t0, -1
  mv t1, t0
  lw t0, 0(sp)
  addi sp, sp, 4
  add t0, t0, t1
  sw t0, 20(s0)
  lw t0, 16(s0)
  addi sp, sp, -4
  sw t0, 0(sp)
  lw t0, 20(s0)
  mv t1, t0
  lw t0, 0(sp)
  addi sp, sp, 4
  slt t0, t1, t0
  beq t0, zero, .L_and_false_1
  li t0, 2
  slli t0, t0, 2
  addi t1, s0, 0
  add t1, t1, t0
  lw t0, 0(t1)
  addi sp, sp, -4
  sw t0, 0(sp)
  li t0, 0
  mv t1, t0
  lw t0, 0(sp)
  addi sp, sp, 4
  xor t0, t0, t1
  seqz t0, t0
  seqz t0, t0
  snez t0, t0
  j .L_and_end_2
.L_and_false_1:
  li t0, 0
.L_and_end_2:
  bne t0, zero, .L_user_if_then_1
  j .L_user_if_else_2
.L_user_if_then_1:
  li t0, 0
  slli t0, t0, 2
  addi t1, s0, 0
  add t1, t1, t0
  lw t0, 0(t1)
  mv a0, t0
  jal ra, .L_print_int
  li t0, 1
  slli t0, t0, 2
  addi t1, s0, 0
  add t1, t1, t0
  lw t0, 0(t1)
  mv a0, t0
  jal ra, .L_print_int
  li t0, 2
  slli t0, t0, 2
  addi t1, s0, 0
  add t1, t1, t0
  lw t0, 0(t1)
  mv a0, t0
  jal ra, .L_print_int
  li t0, 3
  slli t0, t0, 2
  addi t1, s0, 0
  add t1, t1, t0
  lw t0, 0(t1)
  mv a0, t0
  jal ra, .L_print_int
  j .L_user_if_end_3
.L_user_if_else_2:
  # sys_write(fd, buf, len)
  li a0, 1
  la a1, .L_str_str0
  li a2, 11
  li a7, 16
  ecall
.L_user_if_end_3:
  li t0, 1
  mv a0, t0
  li a7, 13
  ecall
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
.globl yhc_prog_name_yhc_h1
yhc_prog_name_yhc_h1:
.byte 121, 104, 99, 95, 104, 49, 0
.L_str_str0:
  .byte 117, 110, 101, 120, 112, 101, 99, 116, 101, 100, 10, 0
