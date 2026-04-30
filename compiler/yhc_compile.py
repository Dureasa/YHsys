#!/usr/bin/env python3
"""YHC compiler driver: source -> IR -> RV32 assembly."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

if __package__ in (None, ""):
    _root = Path(__file__).resolve().parents[1]
    if str(_root) not in sys.path:
        sys.path.insert(0, str(_root))

from compiler.backend.riscv.codegen_rv32 import generate_asm, load_syscall_table
from compiler.frontend.lexer.tokenizer import tokenize
from compiler.frontend.parser.parser import Parser
from compiler.frontend.semantic.analyzer import SemanticAnalyzer
from compiler.ir.builder import lower_program
from compiler.ir.optimizer import OptimizationStats, optimize_ir
from compiler.utils.errors import CodegenError, LexError, ParserError, SemanticError


def parse_args() -> argparse.Namespace:
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description="YHC SysY-like compiler driver")
    parser.add_argument("--input", required=True, help="input source file (.c)")
    parser.add_argument("--ir", required=True, help="output IR json path")
    parser.add_argument("--asm", required=True, help="output assembly path")
    parser.add_argument("--ir-before", help="optional path for pre-optimization IR json")
    parser.add_argument("--ir-after", help="optional path for post-optimization IR json")
    parser.add_argument("--stats-json", help="optional path for optimization stats json")
    parser.add_argument(
        "--syscall-header",
        default=str(root / "os" / "kernel" / "syscall.h"),
        help="YHsys syscall header path",
    )
    parser.add_argument("--program-name", default="yhc_prog", help="logical program name")
    opt_group = parser.add_mutually_exclusive_group()
    opt_group.add_argument("--no-opt", action="store_true", help="disable IR optimization passes")
    opt_group.add_argument("--O1", action="store_true", help="enable local IR optimization passes")
    return parser.parse_args()


def _derive_ir_dump_path(base: Path, suffix: str) -> Path:
    name = base.name
    if name.endswith(".json"):
        return base.with_name(name[:-5] + f".{suffix}.json")
    return base.with_name(name + f".{suffix}.json")


def _write_json(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=True, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    args = parse_args()
    src_path = Path(args.input)
    ir_path = Path(args.ir)
    asm_path = Path(args.asm)
    ir_before_path = Path(args.ir_before) if args.ir_before else _derive_ir_dump_path(ir_path, "before")
    ir_after_path = Path(args.ir_after) if args.ir_after else _derive_ir_dump_path(ir_path, "after")
    stats_path = Path(args.stats_json) if args.stats_json else None
    opt_enabled = bool(args.O1 and not args.no_opt)

    source = src_path.read_text(encoding="utf-8")

    try:
        tokens = tokenize(source)
        program = Parser(tokens).parse_program()
    except (LexError, ParserError) as e:
        print(f"[yhc] parse error: {e}")
        return 2

    try:
        symbols = SemanticAnalyzer().analyze(program)
    except SemanticError as e:
        print(f"[yhc] semantic error: {e}")
        return 3

    ir_before = lower_program(program, symbols)
    if opt_enabled:
        ir_after, opt_stats = optimize_ir(ir_before)
    else:
        ir_after = json.loads(json.dumps(ir_before))
        opt_stats = OptimizationStats(
            instructions_before=len(ir_before.get("instructions", [])),
            instructions_after=len(ir_after.get("instructions", [])),
        )

    try:
        syscall_table = load_syscall_table(args.syscall_header)
        asm = generate_asm(ir_after, syscall_table, args.program_name)
    except CodegenError as e:
        print(f"[yhc] codegen error: {e}")
        return 4

    asm_path.parent.mkdir(parents=True, exist_ok=True)
    _write_json(ir_before_path, ir_before)
    _write_json(ir_after_path, ir_after)
    _write_json(ir_path, ir_after)
    asm_path.write_text(asm, encoding="utf-8")
    if stats_path is not None:
        _write_json(
            stats_path,
            {
                "opt_level": "O1" if opt_enabled else "no-opt",
                **opt_stats.to_dict(),
            },
        )

    print(f"[yhc] source : {src_path}")
    print(f"[yhc] ir     : {ir_path}")
    print(f"[yhc] ir pre : {ir_before_path}")
    print(f"[yhc] ir post: {ir_after_path}")
    print(f"[yhc] asm    : {asm_path}")
    print(
        "[yhc] ir stats: "
        f"before={opt_stats.instructions_before} "
        f"after={opt_stats.instructions_after} "
        f"removed={opt_stats.instructions_removed}"
    )
    if stats_path is not None:
        print(f"[yhc] stats  : {stats_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
