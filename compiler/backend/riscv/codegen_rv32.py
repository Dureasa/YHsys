#!/usr/bin/env python3
"""RV32 assembly code generator for YHC IR."""

from __future__ import annotations

import re
from dataclasses import dataclass

from compiler.utils.errors import CodegenError
from compiler.utils.helpers import align_up, bytes_directive


@dataclass(frozen=True)
class SymbolLayout:
    offset: int
    words: int
    is_array: bool


@dataclass
class FrameLayout:
    symbols: dict[str, SymbolLayout]
    frame_size: int
    saved_s0_offset: int
    saved_ra_offset: int


@dataclass
class EmitState:
    internal_label_id: int = 0

    def fresh(self, prefix: str) -> str:
        self.internal_label_id += 1
        return f".L_{prefix}_{self.internal_label_id}"


def _const_label(cid: str) -> str:
    return f".L_str_{cid}"


def _user_label(name: str) -> str:
    return f".L_user_{name}"


def _normalize_symbols(ir: dict) -> list[dict]:
    symbols = ir.get("symbols")
    if isinstance(symbols, list):
        return symbols
    variables = ir.get("variables", [])
    return [{"name": v, "size": None} for v in variables]


def _build_frame_layout(ir: dict) -> FrameLayout:
    symbols: dict[str, SymbolLayout] = {}
    offset = 0
    for sym in _normalize_symbols(ir):
        name = str(sym["name"])
        size = sym.get("size")
        words = 1 if size is None else int(size)
        if words <= 0:
            raise CodegenError(f"invalid symbol size for '{name}'")
        if name in symbols:
            raise CodegenError(f"duplicate symbol '{name}'")
        symbols[name] = SymbolLayout(offset=offset, words=words, is_array=size is not None)
        offset += words * 4

    frame_size = align_up(max(16, offset + 8), 16)
    return FrameLayout(
        symbols=symbols,
        frame_size=frame_size,
        saved_s0_offset=frame_size - 8,
        saved_ra_offset=frame_size - 4,
    )


def _symbol_layout(layout: FrameLayout, name: str) -> SymbolLayout:
    item = layout.symbols.get(name)
    if item is None:
        raise CodegenError(f"use of undefined variable '{name}'")
    return item


def _emit_push_t0(lines: list[str]) -> None:
    lines.append("  addi sp, sp, -4")
    lines.append("  sw t0, 0(sp)")


def _emit_pop(lines: list[str], reg: str) -> None:
    lines.append(f"  lw {reg}, 0(sp)")
    lines.append("  addi sp, sp, 4")


def _emit_eval_expr(lines: list[str], expr: dict, layout: FrameLayout, state: EmitState, target: str = "t0") -> None:
    kind = expr.get("kind")

    if kind == "int":
        lines.append(f"  li t0, {int(expr['value'])}")
    elif kind == "var":
        slot = _symbol_layout(layout, str(expr["name"]))
        if slot.is_array:
            raise CodegenError(f"array variable requires index: {expr['name']}")
        lines.append(f"  lw t0, {slot.offset}(s0)")
    elif kind == "array":
        slot = _symbol_layout(layout, str(expr["name"]))
        if not slot.is_array:
            raise CodegenError(f"scalar variable cannot be indexed: {expr['name']}")
        _emit_eval_expr(lines, expr["index"], layout, state, "t0")
        lines.append("  slli t0, t0, 2")
        lines.append(f"  addi t1, s0, {slot.offset}")
        lines.append("  add t1, t1, t0")
        lines.append("  lw t0, 0(t1)")
    elif kind == "unary":
        op = expr["op"]
        _emit_eval_expr(lines, expr["operand"], layout, state, "t0")
        if op == "+":
            pass
        elif op == "-":
            lines.append("  sub t0, zero, t0")
        elif op == "!":
            lines.append("  seqz t0, t0")
        elif op == "~":
            lines.append("  xori t0, t0, -1")
        else:
            raise CodegenError(f"unsupported unary operator '{op}'")
    elif kind == "binop":
        op = str(expr["op"])
        if op == "&&":
            false_label = state.fresh("and_false")
            end_label = state.fresh("and_end")
            _emit_eval_expr(lines, expr["lhs"], layout, state, "t0")
            lines.append(f"  beq t0, zero, {false_label}")
            _emit_eval_expr(lines, expr["rhs"], layout, state, "t0")
            lines.append("  snez t0, t0")
            lines.append(f"  j {end_label}")
            lines.append(f"{false_label}:")
            lines.append("  li t0, 0")
            lines.append(f"{end_label}:")
        elif op == "||":
            true_label = state.fresh("or_true")
            end_label = state.fresh("or_end")
            _emit_eval_expr(lines, expr["lhs"], layout, state, "t0")
            lines.append(f"  bne t0, zero, {true_label}")
            _emit_eval_expr(lines, expr["rhs"], layout, state, "t0")
            lines.append("  snez t0, t0")
            lines.append(f"  j {end_label}")
            lines.append(f"{true_label}:")
            lines.append("  li t0, 1")
            lines.append(f"{end_label}:")
        else:
            _emit_eval_expr(lines, expr["lhs"], layout, state, "t0")
            _emit_push_t0(lines)
            _emit_eval_expr(lines, expr["rhs"], layout, state, "t0")
            lines.append("  mv t1, t0")
            _emit_pop(lines, "t0")

            if op == "+":
                lines.append("  add t0, t0, t1")
            elif op == "-":
                lines.append("  sub t0, t0, t1")
            elif op == "*":
                lines.append("  mul t0, t0, t1")
            elif op == "/":
                lines.append("  div t0, t0, t1")
            elif op == "%":
                lines.append("  rem t0, t0, t1")
            elif op == "<<":
                lines.append("  sll t0, t0, t1")
            elif op == ">>":
                lines.append("  sra t0, t0, t1")
            elif op == "&":
                lines.append("  and t0, t0, t1")
            elif op == "|":
                lines.append("  or t0, t0, t1")
            elif op == "^":
                lines.append("  xor t0, t0, t1")
            elif op == "==":
                lines.append("  xor t0, t0, t1")
                lines.append("  seqz t0, t0")
            elif op == "!=":
                lines.append("  xor t0, t0, t1")
                lines.append("  snez t0, t0")
            elif op == "<":
                lines.append("  slt t0, t0, t1")
            elif op == "<=":
                lines.append("  slt t0, t1, t0")
                lines.append("  xori t0, t0, 1")
            elif op == ">":
                lines.append("  slt t0, t1, t0")
            elif op == ">=":
                lines.append("  slt t0, t0, t1")
                lines.append("  xori t0, t0, 1")
            else:
                raise CodegenError(f"unsupported binary operator '{op}'")
    else:
        raise CodegenError(f"unsupported expression kind '{kind}'")

    if target != "t0":
        lines.append(f"  mv {target}, t0")


def _emit_store_lvalue(lines: list[str], target: dict, value_reg: str, layout: FrameLayout, state: EmitState) -> None:
    kind = target.get("kind")
    if kind == "var":
        slot = _symbol_layout(layout, str(target["name"]))
        if slot.is_array:
            raise CodegenError(f"array variable requires index: {target['name']}")
        lines.append(f"  sw {value_reg}, {slot.offset}(s0)")
        return
    if kind == "array":
        slot = _symbol_layout(layout, str(target["name"]))
        if not slot.is_array:
            raise CodegenError(f"scalar variable cannot be indexed: {target['name']}")
        if value_reg != "t0":
            lines.append(f"  mv t0, {value_reg}")
        _emit_push_t0(lines)
        _emit_eval_expr(lines, target["index"], layout, state, "t0")
        lines.append("  slli t0, t0, 2")
        lines.append(f"  addi t1, s0, {slot.offset}")
        lines.append("  add t1, t1, t0")
        _emit_pop(lines, "t2")
        lines.append("  sw t2, 0(t1)")
        return
    raise CodegenError("invalid assignment target")


def _emit_print_int_helper(lines: list[str], sys_write_no: int) -> None:
    lines.append("")
    lines.append(".L_print_int:")
    lines.append("  addi sp, sp, -64")
    lines.append("  sw ra, 60(sp)")
    lines.append("  sw s0, 56(sp)")
    lines.append("  mv s0, a0")
    lines.append("  addi t1, sp, 48")
    lines.append("  li t2, 0")
    lines.append("  bge s0, zero, .L_pi_abs_done")
    lines.append("  li t2, 1")
    lines.append("  sub s0, zero, s0")
    lines.append(".L_pi_abs_done:")
    lines.append("  mv t3, s0")
    lines.append("  bne t3, zero, .L_pi_digits")
    lines.append("  addi t1, t1, -1")
    lines.append("  li t4, 48")
    lines.append("  sb t4, 0(t1)")
    lines.append("  j .L_pi_sign")
    lines.append(".L_pi_digits:")
    lines.append("  li t5, 10")
    lines.append(".L_pi_loop:")
    lines.append("  remu t6, t3, t5")
    lines.append("  divu t3, t3, t5")
    lines.append("  addi t6, t6, 48")
    lines.append("  addi t1, t1, -1")
    lines.append("  sb t6, 0(t1)")
    lines.append("  bne t3, zero, .L_pi_loop")
    lines.append(".L_pi_sign:")
    lines.append("  beq t2, zero, .L_pi_newline")
    lines.append("  addi t1, t1, -1")
    lines.append("  li t6, 45")
    lines.append("  sb t6, 0(t1)")
    lines.append(".L_pi_newline:")
    lines.append("  li t6, 10")
    lines.append("  sb t6, 48(sp)")
    lines.append("  addi t3, sp, 49")
    lines.append("  sub a2, t3, t1")
    lines.append("  li a0, 1")
    lines.append("  mv a1, t1")
    lines.append(f"  li a7, {sys_write_no}")
    lines.append("  ecall")
    lines.append("  lw ra, 60(sp)")
    lines.append("  lw s0, 56(sp)")
    lines.append("  addi sp, sp, 64")
    lines.append("  ret")


def load_syscall_table(syscall_header: str) -> dict[str, int]:
    table: dict[str, int] = {}
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


def generate_asm(ir: dict, syscall_table: dict[str, int], program_name: str) -> str:
    layout = _build_frame_layout(ir)
    constants = {c["id"]: c for c in ir.get("constants", [])}
    instructions = ir.get("instructions", [])
    state = EmitState()
    lines: list[str] = []

    labels_defined = {ins["name"] for ins in instructions if ins.get("op") == "label"}
    for ins in instructions:
        if ins.get("op") in ("goto", "if_goto") and ins["label"] not in labels_defined:
            raise CodegenError(f"branch target label not defined: {ins['label']}")

    needs_print_int = any(ins.get("op") == "sys_write_expr" for ins in instructions)

    lines.append(".section .text")
    lines.append(".option norvc")
    lines.append(".globl main")
    lines.append("main:")
    lines.append(f"  addi sp, sp, -{layout.frame_size}")
    lines.append(f"  sw s0, {layout.saved_s0_offset}(sp)")
    lines.append(f"  sw ra, {layout.saved_ra_offset}(sp)")
    lines.append("  mv s0, sp")

    for ins in instructions:
        op = ins["op"]

        if op == "label":
            lines.append(f"{_user_label(ins['name'])}:")
            continue
        if op == "goto":
            lines.append(f"  j {_user_label(ins['label'])}")
            continue
        if op == "if_goto":
            _emit_eval_expr(lines, ins["cond"], layout, state, "t0")
            lines.append(f"  bne t0, zero, {_user_label(ins['label'])}")
            continue
        if op == "assign":
            _emit_eval_expr(lines, ins["expr"], layout, state, "t0")
            _emit_store_lvalue(lines, ins["target"], "t0", layout, state)
            continue
        if op == "array_zero":
            slot = _symbol_layout(layout, str(ins["name"]))
            if not slot.is_array:
                raise CodegenError(f"array_zero used on scalar symbol '{ins['name']}'")
            for i in range(int(ins["size"])):
                lines.append(f"  sw zero, {slot.offset + i * 4}(s0)")
            continue
        if op == "sys_write_const":
            cid = ins["const"]
            if cid not in constants:
                raise CodegenError(f"unknown constant id '{cid}'")
            lines.append("  # sys_write(fd, buf, len)")
            lines.append(f"  li a0, {int(ins['fd'])}")
            lines.append(f"  la a1, {_const_label(cid)}")
            lines.append(f"  li a2, {int(ins['size'])}")
            lines.append(f"  li a7, {syscall_table['SYS_write']}")
            lines.append("  ecall")
            continue
        if op == "sys_write_expr":
            _emit_eval_expr(lines, ins["expr"], layout, state, "a0")
            lines.append("  jal ra, .L_print_int")
            continue
        if op == "sys_pause_expr":
            _emit_eval_expr(lines, ins["expr"], layout, state, "a0")
            lines.append(f"  li a7, {syscall_table['SYS_pause']}")
            lines.append("  ecall")
            continue
        if op == "sys_exit_expr":
            _emit_eval_expr(lines, ins["expr"], layout, state, "a0")
            lines.append(f"  li a7, {syscall_table['SYS_exit']}")
            lines.append("  ecall")
            lines.append("  j .L_halt")
            continue

        raise CodegenError(f"unsupported IR op '{op}'")

    lines.append(".L_halt:")
    lines.append("  j .L_halt")

    if needs_print_int:
        _emit_print_int_helper(lines, syscall_table["SYS_write"])

    lines.append("")
    lines.append(".section .rodata")
    lines.append(f".globl yhc_prog_name_{program_name}")
    lines.append(f"yhc_prog_name_{program_name}:")
    lines.append(bytes_directive(program_name))
    for cid in sorted(constants.keys()):
        lines.append(f"{_const_label(cid)}:")
        lines.append("  " + bytes_directive(constants[cid]["text"]))

    lines.append("")
    return "\n".join(lines)
