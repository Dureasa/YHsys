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
from compiler.utils.errors import CodegenError, LexError, ParserError, SemanticError


def parse_args() -> argparse.Namespace:
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description="YHC SysY-like compiler driver")
    parser.add_argument("--input", required=True, help="input source file (.c)")
    parser.add_argument("--ir", required=True, help="output IR json path")
    parser.add_argument("--asm", required=True, help="output assembly path")
    parser.add_argument(
        "--syscall-header",
        default=str(root / "os" / "kernel" / "syscall.h"),
        help="YHsys syscall header path",
    )
    parser.add_argument("--program-name", default="yhc_prog", help="logical program name")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    src_path = Path(args.input)
    ir_path = Path(args.ir)
    asm_path = Path(args.asm)

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

    ir = lower_program(program, symbols)

    try:
        syscall_table = load_syscall_table(args.syscall_header)
        asm = generate_asm(ir, syscall_table, args.program_name)
    except CodegenError as e:
        print(f"[yhc] codegen error: {e}")
        return 4

    ir_path.parent.mkdir(parents=True, exist_ok=True)
    asm_path.parent.mkdir(parents=True, exist_ok=True)
    ir_path.write_text(json.dumps(ir, ensure_ascii=True, indent=2) + "\n", encoding="utf-8")
    asm_path.write_text(asm, encoding="utf-8")

    print(f"[yhc] source : {src_path}")
    print(f"[yhc] ir     : {ir_path}")
    print(f"[yhc] asm    : {asm_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
