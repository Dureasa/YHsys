#!/usr/bin/env python3
from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
COMPILER = ROOT / "compiler"
OS_DIR = ROOT / "os"
BUILD = COMPILER / "build"
BUILD_SCRIPT = COMPILER / "scripts" / "build_yh_program.sh"
RUN_SCRIPT = COMPILER / "scripts" / "run_yh_program.py"
SYS_HDR = OS_DIR / "kernel" / "syscall.h"

CASES = [
    {
        "src": COMPILER / "tests" / "cf01.c",
        "name": "cf01",
        "expect": "14\n13\n-6\n1",
        "ir_checks": [
            ("all_assign_int", None),
        ],
    },
    {
        "src": COMPILER / "tests" / "cf02.c",
        "name": "cf02",
        "expect": "16\n0",
        "ir_checks": [
            ("contains_folded_rhs", 6),
            ("contains_folded_zero", None),
        ],
    },
    {
        "src": COMPILER / "tests" / "dce01.c",
        "name": "dce01",
        "expect": "222",
        "ir_checks": [
            ("no_control_flow", None),
            ("contains_write_int", 222),
        ],
    },
    {
        "src": COMPILER / "tests" / "dce02.c",
        "name": "dce02",
        "expect": "333",
        "ir_checks": [
            ("no_control_flow", None),
            ("contains_write_int", 333),
        ],
    },
    {
        "src": COMPILER / "tests" / "dce03.c",
        "name": "dce03",
        "expect": "666",
        "ir_checks": [
            ("no_control_flow", None),
            ("contains_write_int", 666),
        ],
    },
    {
        "src": COMPILER / "tests" / "dce04.c",
        "name": "dce04",
        "expect": "1",
        "ir_checks": [
            ("no_dead_print_two", None),
        ],
    },
    {
        "src": COMPILER / "examples" / "hello.c",
        "name": "hello",
        "expect": "12\n27\n2\n13",
        "ir_checks": [],
    },
]


def run(cmd: list[str]) -> str:
    p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    if p.returncode != 0:
        print(p.stdout, end="")
        raise SystemExit(p.returncode)
    return p.stdout


def compile_case(src: Path, name: str) -> None:
    run([
        "bash",
        str(BUILD_SCRIPT),
        str(src),
        name,
    ])


def run_case(name: str) -> str:
    out = run([
        "python3",
        str(RUN_SCRIPT),
        "--program",
        f"yhc_{name}",
        "--os-dir",
        str(OS_DIR),
    ])
    return out.strip()


def load_ir(name: str) -> dict:
    return json.loads((BUILD / f"yhc_{name}.ir.json").read_text(encoding="utf-8"))


def check_ir(name: str, ir: dict, checks: list[tuple[str, int | None]]) -> None:
    for kind, value in checks:
        if kind == "all_assign_int":
            for ins in ir.get("instructions", []):
                if ins.get("op") == "assign":
                    expr = ins.get("expr", {})
                    if expr.get("kind") != "int":
                        raise AssertionError(f"{name}: assignment not folded to int: {ins}")
        elif kind == "contains_folded_rhs":
            found = False
            for ins in ir.get("instructions", []):
                if ins.get("op") == "assign":
                    expr = ins.get("expr", {})
                    if expr.get("kind") == "binop":
                        rhs = expr.get("rhs", {})
                        if rhs.get("kind") == "int" and int(rhs.get("value", -1)) == int(value):
                            found = True
            if not found:
                raise AssertionError(f"{name}: missing folded rhs {value}")
        elif kind == "contains_folded_zero":
            found = False
            for ins in ir.get("instructions", []):
                if ins.get("op") == "assign":
                    expr = ins.get("expr", {})
                    if expr.get("kind") == "int" and int(expr.get("value", -1)) == 0:
                        found = True
            if not found:
                raise AssertionError(f"{name}: missing folded zero")
        elif kind == "no_control_flow":
            ops = [ins.get("op") for ins in ir.get("instructions", [])]
            for op in ("if_goto", "goto", "label"):
                if op in ops:
                    raise AssertionError(f"{name}: unexpected control-flow op {op}: {ops}")
        elif kind == "contains_write_int":
            found = False
            for ins in ir.get("instructions", []):
                if ins.get("op") == "sys_write_expr":
                    expr = ins.get("expr", {})
                    if expr.get("kind") == "int" and int(expr.get("value", -999999)) == int(value):
                        found = True
            if not found:
                raise AssertionError(f"{name}: missing sys_write_expr {value}")
        elif kind == "no_dead_print_two":
            text = json.dumps(ir, ensure_ascii=True)
            if '"value": 2' in text:
                raise AssertionError(f"{name}: dead return-path code still present")
        else:
            raise AssertionError(f"unknown check {kind}")


def main() -> int:
    for case in CASES:
        compile_case(case["src"], case["name"])
        ir = load_ir(case["name"])
        check_ir(case["name"], ir, case["ir_checks"])
        out = run_case(case["name"])
        if out != case["expect"]:
            raise AssertionError(f"{case['name']}: expect {case['expect']!r}, got {out!r}")
        print(f"[ok] {case['name']}")
    print("all optimization tests passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
