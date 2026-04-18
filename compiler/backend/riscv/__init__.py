"""RISC-V backend package."""

from .codegen_rv32 import generate_asm, load_syscall_table

__all__ = ["generate_asm", "load_syscall_table"]
