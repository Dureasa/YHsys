#!/usr/bin/env python3
"""YHC compiler driver: source -> IR -> RV32 assembly."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from yhc_codegen_rv32 import generate_asm, load_syscall_table
from yhc_frontend import ParseError, parse_source
from yhc_ir import lower_ast


def parse_args() -> argparse.Namespace:
    root = Path(__file__).resolve().parents[2]
    parser = argparse.ArgumentParser(description="YHC compiler driver")
    parser.add_argument("--input", required=True, help="input source file (.yhc)")
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
        ast_nodes = parse_source(source)
    except ParseError as e:
        print(f"[yhc] parse error: {e}")
        return 2

    ir = lower_ast(ast_nodes)
    syscall_table = load_syscall_table(args.syscall_header)
    asm = generate_asm(ir, syscall_table, args.program_name)

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
