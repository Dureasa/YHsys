        # qemu -kernel loads the kernel at 0x80000000
        # and jumps to the boot CPU entry.
        # kernel.ld causes the following code to
        # be placed at 0x80000000.
.section .text
.global _entry
_entry:
        # set up a stack for C.
        # stack0 is declared in start.c,
        # with a single 4096-byte boot stack.
        # sp = stack0 + 4096
        la sp, stack0
        li a0, 1024*4
        add sp, sp, a0
        # jump to start() in start.c
        call start
spin:
        j spin
