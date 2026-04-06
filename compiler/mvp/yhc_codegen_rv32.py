#!/usr/bin/env python3
"""RV32 assembly codegen for YHC IR."""

from __future__ import annotations

import re
from typing import Dict


class CodegenError(Exception):
    pass


def load_syscall_table(syscall_header: str) -> Dict[str, int]:
    table: Dict[str, int] = {}
    pattern = re.compile(r"^\s*#define\s+(SYS_[A-Za-z0-9_]+)\s+([0-9]+)\s*$")

    with open(syscall_header, "r", encoding="utf-8") as f:
        for line in f:
            m = pattern.match(line)
            if not m:
                continue
            table[m.group(1)] = int(m.group(2))

    required = ["SYS_write", "SYS_pause", "SYS_exit"]
    missing = [name for name in required if name not in table]
    if missing:
        raise CodegenError(f"missing syscall numbers in header: {', '.join(missing)}")

    return table


def _bytes_directive(text: str) -> str:
    values = list(text.encode("utf-8")) + [0]
    return ".byte " + ", ".join(str(v) for v in values)


def generate_asm(ir: dict, syscall_table: Dict[str, int], program_name: str) -> str:
    lines: list[str] = []

    lines.append(".section .text")
    lines.append(".globl main")
    lines.append("main:")
    lines.append("  addi sp, sp, -16")
    lines.append("  sw ra, 12(sp)")

    constants = {c["id"]: c for c in ir.get("constants", [])}

    for ins in ir.get("instructions", []):
        op = ins["op"]
        if op == "sys_write":
            cid = ins["const"]
            if cid not in constants:
                raise CodegenError(f"unknown constant id {cid}")
            lines.append("  # sys_write(fd=1, buf, len)")
            lines.append(f"  li a0, {int(ins['fd'])}")
            lines.append(f"  la a1, .L_{cid}")
            lines.append(f"  li a2, {int(ins['size'])}")
            lines.append(f"  li a7, {syscall_table['SYS_write']}")
            lines.append("  ecall")
            continue

        if op == "sys_pause":
            lines.append("  # sys_pause(ticks)")
            lines.append(f"  li a0, {int(ins['ticks'])}")
            lines.append(f"  li a7, {syscall_table['SYS_pause']}")
            lines.append("  ecall")
            continue

        if op == "sys_exit":
            lines.append("  # sys_exit(code)")
            lines.append(f"  li a0, {int(ins['code'])}")
            lines.append(f"  li a7, {syscall_table['SYS_exit']}")
            lines.append("  ecall")
            lines.append("  j .L_halt")
            continue

        raise CodegenError(f"unsupported IR op {op}")

    lines.append(".L_halt:")
    lines.append("  j .L_halt")

    if constants:
        lines.append("")
        lines.append(".section .rodata")
        lines.append(f".globl yhc_prog_name_{program_name}")
        lines.append(f"yhc_prog_name_{program_name}:")
        lines.append(_bytes_directive(program_name))
        for cid, c in constants.items():
            lines.append(f".L_{cid}:")
            lines.append("  " + _bytes_directive(c["text"]))

    lines.append("")
    return "\n".join(lines)
