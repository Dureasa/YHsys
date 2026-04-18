.section .text
.globl main
main:
  addi sp, sp, -16
  sw s0, 8(sp)
  sw ra, 12(sp)
  mv s0, sp
  li t0, 0
  sw t0, 0(s0)
.L_user_while_cond_1:
  lw t0, 0(s0)
  addi sp, sp, -4
  sw t0, 0(sp)
  li t0, 5
  mv t1, t0
  lw t0, 0(sp)
  addi sp, sp, 4
  slt t0, t0, t1
  bne t0, zero, .L_user_while_body_2
  j .L_user_while_end_3
.L_user_while_body_2:
  lw t0, 0(s0)
  mv a0, t0
  jal ra, .L_print_int
  lw t0, 0(s0)
  addi sp, sp, -4
  sw t0, 0(sp)
  li t0, 1
  mv t1, t0
  lw t0, 0(sp)
  addi sp, sp, 4
  add t0, t0, t1
  sw t0, 0(s0)
  j .L_user_while_cond_1
.L_user_while_end_3:
  lw t0, 0(s0)
  addi sp, sp, -4
  sw t0, 0(sp)
  li t0, 5
  mv t1, t0
  lw t0, 0(sp)
  addi sp, sp, 4
  xor t0, t0, t1
  seqz t0, t0
  bne t0, zero, .L_user_if_then_4
  j .L_user_if_else_5
.L_user_if_then_4:
  # sys_write(fd, buf, len)
  li a0, 1
  la a1, .L_str_str0
  li a2, 5
  li a7, 16
  ecall
  j .L_user_if_end_6
.L_user_if_else_5:
  # sys_write(fd, buf, len)
  li a0, 1
  la a1, .L_str_str1
  li a2, 11
  li a7, 16
  ecall
.L_user_if_end_6:
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
.globl yhc_prog_name_yhc_b2
yhc_prog_name_yhc_b2:
.byte 121, 104, 99, 95, 98, 50, 0
.L_str_str0:
  .byte 100, 111, 110, 101, 10, 0
.L_str_str1:
  .byte 117, 110, 101, 120, 112, 101, 99, 116, 101, 100, 10, 0
