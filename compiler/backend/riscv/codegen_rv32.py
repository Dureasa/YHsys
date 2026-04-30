#!/usr/bin/env python3
"""RV32 assembly code generator for YHC IR."""

from __future__ import annotations

import re
from dataclasses import dataclass, field

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
    alloc: "RegisterAllocation | None" = None
    reg_valid: dict[str, bool] = field(default_factory=dict)
    reg_dirty: dict[str, bool] = field(default_factory=dict)
    stats: "CodegenStats" = field(default_factory=lambda: CodegenStats())

    def fresh(self, prefix: str) -> str:
        self.internal_label_id += 1
        return f".L_{prefix}_{self.internal_label_id}"


@dataclass(frozen=True)
class VarLocation:
    reg: str | None
    stack_offset: int
    spill: bool


@dataclass(frozen=True)
class RegisterAllocation:
    locations: dict[str, VarLocation]
    reg_to_var: dict[str, str]
    live_in: list[set[str]]
    live_out: list[set[str]]


@dataclass
class CodegenStats:
    load_count: int = 0
    store_count: int = 0
    temp_reg_uses: int = 0


ALLOCATABLE_REGS = ["t0", "t1", "t2", "t3", "t4", "t5", "t6", "a1", "a2", "a3"]


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


def _scalar_symbols(layout: FrameLayout) -> set[str]:
    return {name for name, slot in layout.symbols.items() if not slot.is_array}


def _expr_uses(expr: dict, layout: FrameLayout) -> set[str]:
    kind = expr.get("kind")
    if kind == "var":
        name = str(expr["name"])
        slot = _symbol_layout(layout, name)
        return {name} if not slot.is_array else set()
    if kind == "array":
        uses: set[str] = set()
        name = str(expr["name"])
        slot = _symbol_layout(layout, name)
        if not slot.is_array:
            raise CodegenError(f"scalar variable cannot be indexed: {name}")
        uses |= _expr_uses(expr["index"], layout)
        return uses
    if kind == "unary":
        return _expr_uses(expr["operand"], layout)
    if kind == "binop":
        return _expr_uses(expr["lhs"], layout) | _expr_uses(expr["rhs"], layout)
    if kind == "int":
        return set()
    raise CodegenError(f"unsupported expression kind '{kind}'")


def _instruction_uses_defs(ins: dict, layout: FrameLayout) -> tuple[set[str], set[str]]:
    op = ins.get("op")
    uses: set[str] = set()
    defs: set[str] = set()

    if op == "assign":
        target = ins["target"]
        uses |= _expr_uses(ins["expr"], layout)
        if target.get("kind") == "var":
            name = str(target["name"])
            slot = _symbol_layout(layout, name)
            if slot.is_array:
                raise CodegenError(f"array variable requires index: {name}")
            defs.add(name)
        elif target.get("kind") == "array":
            uses |= _expr_uses(target["index"], layout)
        else:
            raise CodegenError("invalid assignment target")
    elif op == "if_goto":
        uses |= _expr_uses(ins["cond"], layout)
    elif op in ("sys_write_expr", "sys_pause_expr", "sys_exit_expr"):
        uses |= _expr_uses(ins["expr"], layout)

    return uses, defs


def _analyze_liveness(instructions: list[dict], layout: FrameLayout) -> tuple[list[set[str]], list[set[str]]]:
    live_in: list[set[str]] = [set() for _ in instructions]
    live_out: list[set[str]] = [set() for _ in instructions]
    live: set[str] = set()

    for idx in range(len(instructions) - 1, -1, -1):
        uses, defs = _instruction_uses_defs(instructions[idx], layout)
        live_out[idx] = set(live)
        live = (live - defs) | uses
        live_in[idx] = set(live)

    return live_in, live_out


def _build_register_allocation(instructions: list[dict], layout: FrameLayout) -> RegisterAllocation:
    scalar_names = _scalar_symbols(layout)
    live_in, live_out = _analyze_liveness(instructions, layout)

    first_seen: dict[str, int] = {}
    last_seen: dict[str, int] = {}
    order: list[str] = []

    for idx, ins in enumerate(instructions):
        uses, defs = _instruction_uses_defs(ins, layout)
        for name in sorted((uses | defs) & scalar_names):
            if name not in first_seen:
                first_seen[name] = idx
                order.append(name)
            last_seen[name] = idx

    locations: dict[str, VarLocation] = {}
    reg_to_var: dict[str, str] = {}
    free_regs = list(ALLOCATABLE_REGS)
    active: list[tuple[str, int]] = []

    def expire(before: int) -> None:
        nonlocal active, free_regs
        still_active: list[tuple[str, int]] = []
        for var, end in active:
            if end < before:
                reg = locations[var].reg
                if reg is not None:
                    free_regs.append(reg)
            else:
                still_active.append((var, end))
        active = still_active

    for name in order:
        start = first_seen[name]
        end = last_seen[name]
        expire(start)
        if free_regs:
            reg = free_regs.pop(0)
            locations[name] = VarLocation(reg=reg, stack_offset=_symbol_layout(layout, name).offset, spill=False)
            reg_to_var[reg] = name
            active.append((name, end))
            active.sort(key=lambda x: x[1])
        else:
            locations[name] = VarLocation(reg=None, stack_offset=_symbol_layout(layout, name).offset, spill=True)

    for name in scalar_names:
        if name not in locations:
            locations[name] = VarLocation(reg=None, stack_offset=_symbol_layout(layout, name).offset, spill=True)

    return RegisterAllocation(locations=locations, reg_to_var=reg_to_var, live_in=live_in, live_out=live_out)


def _emit_lw(lines: list[str], state: EmitState, reg: str, offset: int, base: str = "s0") -> None:
    lines.append(f"  lw {reg}, {offset}({base})")
    state.stats.load_count += 1


def _emit_sw(lines: list[str], state: EmitState, reg: str, offset: int, base: str = "s0") -> None:
    lines.append(f"  sw {reg}, {offset}({base})")
    state.stats.store_count += 1


def _emit_push(lines: list[str], state: EmitState, reg: str) -> None:
    lines.append("  addi sp, sp, -4")
    _emit_sw(lines, state, reg, 0, "sp")


def _emit_pop(lines: list[str], state: EmitState, reg: str) -> None:
    _emit_lw(lines, state, reg, 0, "sp")
    lines.append("  addi sp, sp, 4")


def _prepare_reg_for_clobber(lines: list[str], layout: FrameLayout, state: EmitState, reg: str) -> None:
    if state.alloc is None:
        return
    owner = state.alloc.reg_to_var.get(reg)
    if owner is None:
        return
    if not state.reg_valid.get(owner, False):
        return
    if state.reg_dirty.get(owner, False):
        slot = _symbol_layout(layout, owner)
        _emit_sw(lines, state, reg, slot.offset, "s0")
    state.reg_valid[owner] = False
    state.reg_dirty[owner] = False


def _load_var_into_reg(lines: list[str], layout: FrameLayout, state: EmitState, name: str, reg: str) -> None:
    slot = _symbol_layout(layout, name)
    if slot.is_array:
        raise CodegenError(f"array variable requires index: {name}")

    if state.alloc is None:
        _prepare_reg_for_clobber(lines, layout, state, reg)
        _emit_lw(lines, state, reg, slot.offset, "s0")
        return

    loc = state.alloc.locations.get(name)
    if loc is None or loc.reg is None:
        _prepare_reg_for_clobber(lines, layout, state, reg)
        _emit_lw(lines, state, reg, slot.offset, "s0")
        return

    src = loc.reg
    if not state.reg_valid.get(name, False):
        _emit_lw(lines, state, src, slot.offset, "s0")
        state.reg_valid[name] = True
        state.reg_dirty[name] = False

    if reg != src:
        _prepare_reg_for_clobber(lines, layout, state, reg)
        lines.append(f"  mv {reg}, {src}")
    state.stats.temp_reg_uses += 1


def _store_scalar_from_reg(lines: list[str], layout: FrameLayout, state: EmitState, name: str, value_reg: str) -> None:
    slot = _symbol_layout(layout, name)
    if slot.is_array:
        raise CodegenError(f"array variable requires index: {name}")

    if state.alloc is None:
        _emit_sw(lines, state, value_reg, slot.offset, "s0")
        return

    loc = state.alloc.locations.get(name)
    if loc is None or loc.reg is None:
        _emit_sw(lines, state, value_reg, slot.offset, "s0")
        return

    dst = loc.reg
    if dst != value_reg:
        _prepare_reg_for_clobber(lines, layout, state, dst)
        lines.append(f"  mv {dst}, {value_reg}")
    state.reg_valid[name] = True
    state.reg_dirty[name] = True
    state.stats.temp_reg_uses += 1


def _spill_active_registers(lines: list[str], layout: FrameLayout, state: EmitState, active: set[str] | None = None) -> None:
    if state.alloc is None:
        return
    for name, loc in state.alloc.locations.items():
        if loc.reg is None:
            continue
        if active is not None and name not in active:
            continue
        if state.reg_valid.get(name, False) and state.reg_dirty.get(name, False):
            _emit_sw(lines, state, loc.reg, loc.stack_offset, "s0")
        state.reg_valid[name] = False
        state.reg_dirty[name] = False


def _emit_eval_expr(lines: list[str], expr: dict, layout: FrameLayout, state: EmitState, target: str = "t0") -> None:
    kind = expr.get("kind")

    if kind == "int":
        _prepare_reg_for_clobber(lines, layout, state, target)
        lines.append(f"  li {target}, {int(expr['value'])}")
        return

    if kind == "var":
        _load_var_into_reg(lines, layout, state, str(expr["name"]), target)
        return

    if kind == "array":
        slot = _symbol_layout(layout, str(expr["name"]))
        if not slot.is_array:
            raise CodegenError(f"scalar variable cannot be indexed: {expr['name']}")
        _emit_eval_expr(lines, expr["index"], layout, state, target)
        lines.append(f"  slli {target}, {target}, 2")
        lines.append(f"  addi a4, s0, {slot.offset}")
        lines.append(f"  add a4, a4, {target}")
        _emit_lw(lines, state, target, 0, "a4")
        return

    if kind == "unary":
        op = expr["op"]
        _emit_eval_expr(lines, expr["operand"], layout, state, target)
        if op == "+":
            return
        if op == "-":
            lines.append(f"  sub {target}, zero, {target}")
            return
        if op == "!":
            lines.append(f"  seqz {target}, {target}")
            return
        if op == "~":
            lines.append(f"  xori {target}, {target}, -1")
            return
        raise CodegenError(f"unsupported unary operator '{op}'")

    if kind == "binop":
        op = str(expr["op"])
        if op == "&&":
            false_label = state.fresh("and_false")
            end_label = state.fresh("and_end")
            _emit_eval_expr(lines, expr["lhs"], layout, state, target)
            lines.append(f"  beq {target}, zero, {false_label}")
            _emit_eval_expr(lines, expr["rhs"], layout, state, target)
            lines.append(f"  snez {target}, {target}")
            lines.append(f"  j {end_label}")
            lines.append(f"{false_label}:")
            lines.append(f"  li {target}, 0")
            lines.append(f"{end_label}:")
            return
        if op == "||":
            true_label = state.fresh("or_true")
            end_label = state.fresh("or_end")
            _emit_eval_expr(lines, expr["lhs"], layout, state, target)
            lines.append(f"  bne {target}, zero, {true_label}")
            _emit_eval_expr(lines, expr["rhs"], layout, state, target)
            lines.append(f"  snez {target}, {target}")
            lines.append(f"  j {end_label}")
            lines.append(f"{true_label}:")
            lines.append(f"  li {target}, 1")
            lines.append(f"{end_label}:")
            return

        _emit_eval_expr(lines, expr["lhs"], layout, state, target)
        _emit_push(lines, state, target)
        _emit_eval_expr(lines, expr["rhs"], layout, state, target)
        lines.append(f"  mv a4, {target}")
        _emit_pop(lines, state, target)

        if op == "+":
            lines.append(f"  add {target}, {target}, a4")
        elif op == "-":
            lines.append(f"  sub {target}, {target}, a4")
        elif op == "*":
            lines.append(f"  mul {target}, {target}, a4")
        elif op == "/":
            lines.append(f"  div {target}, {target}, a4")
        elif op == "%":
            lines.append(f"  rem {target}, {target}, a4")
        elif op == "<<":
            lines.append(f"  sll {target}, {target}, a4")
        elif op == ">>":
            lines.append(f"  sra {target}, {target}, a4")
        elif op == "&":
            lines.append(f"  and {target}, {target}, a4")
        elif op == "|":
            lines.append(f"  or {target}, {target}, a4")
        elif op == "^":
            lines.append(f"  xor {target}, {target}, a4")
        elif op == "==":
            lines.append(f"  xor {target}, {target}, a4")
            lines.append(f"  seqz {target}, {target}")
        elif op == "!=":
            lines.append(f"  xor {target}, {target}, a4")
            lines.append(f"  snez {target}, {target}")
        elif op == "<":
            lines.append(f"  slt {target}, {target}, a4")
        elif op == "<=":
            lines.append(f"  slt {target}, a4, {target}")
            lines.append(f"  xori {target}, {target}, 1")
        elif op == ">":
            lines.append(f"  slt {target}, a4, {target}")
        elif op == ">=":
            lines.append(f"  slt {target}, {target}, a4")
            lines.append(f"  xori {target}, {target}, 1")
        else:
            raise CodegenError(f"unsupported binary operator '{op}'")
        return

    raise CodegenError(f"unsupported expression kind '{kind}'")


def _emit_store_lvalue(lines: list[str], target: dict, value_reg: str, layout: FrameLayout, state: EmitState) -> None:
    kind = target.get("kind")
    if kind == "var":
        _store_scalar_from_reg(lines, layout, state, str(target["name"]), value_reg)
        return
    if kind == "array":
        slot = _symbol_layout(layout, str(target["name"]))
        if not slot.is_array:
            raise CodegenError(f"scalar variable cannot be indexed: {target['name']}")
        if value_reg != "a5":
            _prepare_reg_for_clobber(lines, layout, state, "a5")
            lines.append(f"  mv a5, {value_reg}")
        _emit_eval_expr(lines, target["index"], layout, state, "a4")
        lines.append("  slli a4, a4, 2")
        lines.append(f"  addi a6, s0, {slot.offset}")
        lines.append("  add a6, a6, a4")
        _emit_sw(lines, state, "a5", 0, "a6")
        return
    raise CodegenError("invalid assignment target")


def _emit_print_int_helper(lines: list[str], state: EmitState, sys_write_no: int) -> None:
    lines.append("")
    lines.append(".L_print_int:")
    lines.append("  addi sp, sp, -64")
    _emit_sw(lines, state, "ra", 60, "sp")
    _emit_sw(lines, state, "s0", 56, "sp")
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
    _emit_lw(lines, state, "ra", 60, "sp")
    _emit_lw(lines, state, "s0", 56, "sp")
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
    alloc = _build_register_allocation(instructions, layout)
    state = EmitState(alloc=alloc)
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
    _emit_sw(lines, state, "s0", layout.saved_s0_offset, "sp")
    _emit_sw(lines, state, "ra", layout.saved_ra_offset, "sp")
    lines.append("  mv s0, sp")

    for idx, ins in enumerate(instructions):
        op = ins["op"]

        if op == "label":
            _spill_active_registers(lines, layout, state)
            lines.append(f"{_user_label(ins['name'])}:")
            continue
        if op == "goto":
            _spill_active_registers(lines, layout, state, alloc.live_out[idx])
            lines.append(f"  j {_user_label(ins['label'])}")
            continue
        if op == "if_goto":
            _emit_eval_expr(lines, ins["cond"], layout, state, "t0")
            _spill_active_registers(lines, layout, state, alloc.live_out[idx])
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
            _spill_active_registers(lines, layout, state, alloc.live_out[idx])
            _prepare_reg_for_clobber(lines, layout, state, "a1")
            _prepare_reg_for_clobber(lines, layout, state, "a2")
            lines.append("  # sys_write(fd, buf, len)")
            lines.append(f"  li a0, {int(ins['fd'])}")
            lines.append(f"  la a1, {_const_label(cid)}")
            lines.append(f"  li a2, {int(ins['size'])}")
            lines.append(f"  li a7, {syscall_table['SYS_write']}")
            lines.append("  ecall")
            continue
        if op == "sys_write_expr":
            _emit_eval_expr(lines, ins["expr"], layout, state, "a0")
            _spill_active_registers(lines, layout, state, alloc.live_out[idx])
            lines.append("  jal ra, .L_print_int")
            continue
        if op == "sys_pause_expr":
            _emit_eval_expr(lines, ins["expr"], layout, state, "a0")
            _spill_active_registers(lines, layout, state, alloc.live_out[idx])
            lines.append(f"  li a7, {syscall_table['SYS_pause']}")
            lines.append("  ecall")
            continue
        if op == "sys_exit_expr":
            _emit_eval_expr(lines, ins["expr"], layout, state, "a0")
            _spill_active_registers(lines, layout, state, alloc.live_out[idx])
            lines.append(f"  li a7, {syscall_table['SYS_exit']}")
            lines.append("  ecall")
            lines.append("  j .L_halt")
            continue

        raise CodegenError(f"unsupported IR op '{op}'")

    lines.append(".L_halt:")
    lines.append("  j .L_halt")

    if needs_print_int:
        _emit_print_int_helper(lines, state, syscall_table["SYS_write"])

    lines.append("")
    lines.append(".section .rodata")
    lines.append(f".globl yhc_prog_name_{program_name}")
    lines.append(f"yhc_prog_name_{program_name}:")
    lines.append(bytes_directive(program_name))
    for cid in sorted(constants.keys()):
        lines.append(f"{_const_label(cid)}:")
        lines.append("  " + bytes_directive(constants[cid]["text"]))

    lines.append("")
    lines.append(
        f"# [codegen-stats] loads={state.stats.load_count} stores={state.stats.store_count} temp_reg_uses={state.stats.temp_reg_uses}"
    )
    lines.append("")
    return "\n".join(lines)
