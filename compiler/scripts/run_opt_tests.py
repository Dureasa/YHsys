#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
COMPILER = ROOT / "compiler"
OS_DIR = ROOT / "os"
BUILD = COMPILER / "build"
COMPILER_MAIN = COMPILER / "yhc_compile.py"
BUILD_SCRIPT = COMPILER / "scripts" / "build_yh_program.sh"
RUN_SCRIPT = COMPILER / "scripts" / "run_yh_program.py"
SYS_HDR = OS_DIR / "kernel" / "syscall.h"

CASES = [
    {
        "src": COMPILER / "tests" / "opt_constprop.c",
        "name": "opt_constprop",
        "run_tag": "cp",
        "expect": "7\n9",
        "ir_checks": ["constprop_assigns", "constprop_prints"],
        "expect_removed": False,
    },
    {
        "src": COMPILER / "tests" / "opt_algebraic.c",
        "name": "opt_algebraic",
        "run_tag": "ag",
        "expect": "5\n5\n0",
        "ir_checks": ["algebraic_assigns", "algebraic_prints"],
        "expect_removed": False,
    },
    {
        "src": COMPILER / "tests" / "opt_dead_branch.c",
        "name": "opt_dead_branch",
        "run_tag": "db",
        "expect": "11",
        "ir_checks": ["dead_branch_removed"],
        "expect_removed": True,
    },
    {
        "src": COMPILER / "tests" / "opt_combo.c",
        "name": "opt_combo",
        "run_tag": "cb",
        "expect": "3",
        "ir_checks": ["combo_folded"],
        "expect_removed": True,
    },
    {
        "src": COMPILER / "tests" / "dce05.c",
        "name": "dce05",
        "run_tag": "d5",
        "expect": "5",
        "ir_checks": ["unreachable_after_return"],
        "expect_removed": False,
    },
    {
        "src": COMPILER / "tests" / "dce06.c",
        "name": "dce06",
        "run_tag": "d6",
        "expect": "2",
        "ir_checks": ["dead_store_removed"],
        "expect_removed": True,
    },
    {
        "src": COMPILER / "tests" / "dce07.c",
        "name": "dce07",
        "run_tag": "d7",
        "expect": "8",
        "ir_checks": ["unreachable_after_goto"],
        "expect_removed": True,
    },
]


def run(cmd: list[str], env: dict[str, str] | None = None) -> str:
    p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, env=env)
    if p.returncode != 0:
        print(p.stdout, end="")
        raise SystemExit(p.returncode)
    return p.stdout


def compile_ir(src: Path, name: str, opt_flag: str) -> tuple[dict, dict, dict]:
    ir_path = BUILD / f"{name}.ir.json"
    ir_before_path = BUILD / f"{name}.before.ir.json"
    ir_after_path = BUILD / f"{name}.after.ir.json"
    asm_path = BUILD / f"{name}.s"
    stats_path = BUILD / f"{name}.optstats.json"

    run([
        "python3",
        str(COMPILER_MAIN),
        "--input",
        str(src),
        "--ir",
        str(ir_path),
        "--ir-before",
        str(ir_before_path),
        "--ir-after",
        str(ir_after_path),
        "--asm",
        str(asm_path),
        "--stats-json",
        str(stats_path),
        "--syscall-header",
        str(SYS_HDR),
        "--program-name",
        name,
        opt_flag,
    ])

    return (
        json.loads(ir_before_path.read_text(encoding="utf-8")),
        json.loads(ir_after_path.read_text(encoding="utf-8")),
        json.loads(stats_path.read_text(encoding="utf-8")),
    )


def build_case(src: Path, name: str, opt_flag: str) -> None:
    env = dict(os.environ)
    env["YHC_OPT_LEVEL"] = opt_flag
    run(["bash", str(BUILD_SCRIPT), str(src), name], env=env)


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


def assert_stats(name: str, before: dict, after: dict, stats: dict, expect_removed: bool) -> None:
    before_count = len(before.get("instructions", []))
    after_count = len(after.get("instructions", []))
    if stats.get("instructions_before") != before_count:
        raise AssertionError(f"{name}: bad before count in stats")
    if stats.get("instructions_after") != after_count:
        raise AssertionError(f"{name}: bad after count in stats")
    if stats.get("instructions_removed") != before_count - after_count:
        raise AssertionError(f"{name}: bad removed count in stats")
    if after_count > before_count:
        raise AssertionError(f"{name}: optimization increased instruction count")
    if expect_removed and after_count >= before_count:
        raise AssertionError(f"{name}: expected instruction removal")


def _assign_value(ir: dict, var_name: str) -> int | None:
    for ins in ir.get("instructions", []):
        if ins.get("op") != "assign":
            continue
        target = ins.get("target", {})
        expr = ins.get("expr", {})
        if target.get("kind") == "var" and target.get("name") == var_name and expr.get("kind") == "int":
            return int(expr["value"])
    return None


def _print_values(ir: dict) -> list[int]:
    values: list[int] = []
    for ins in ir.get("instructions", []):
        if ins.get("op") != "sys_write_expr":
            continue
        expr = ins.get("expr", {})
        if expr.get("kind") == "int":
            values.append(int(expr["value"]))
    return values


def _has_print_value(ir: dict, value: int) -> bool:
    return value in _print_values(ir)


def _assign_values(ir: dict, var_name: str) -> list[int]:
    values: list[int] = []
    for ins in ir.get("instructions", []):
        if ins.get("op") != "assign":
            continue
        target = ins.get("target", {})
        expr = ins.get("expr", {})
        if target.get("kind") == "var" and target.get("name") == var_name and expr.get("kind") == "int":
            values.append(int(expr["value"]))
    return values


def check_case(name: str, before: dict, after: dict, checks: list[str]) -> None:
    after_ops = [ins.get("op") for ins in after.get("instructions", [])]

    for check in checks:
        if check == "constprop_assigns":
            b_value = _assign_value(after, "b")
            if b_value not in (7, None):
                raise AssertionError(f"{name}: const propagation on assignment missing")
        elif check == "constprop_prints":
            if _print_values(after) != [7, 9]:
                raise AssertionError(f"{name}: const propagation on use missing")
        elif check == "algebraic_assigns":
            w_value = _assign_value(after, "w")
            if w_value not in (0, None):
                raise AssertionError(f"{name}: algebraic simplification missing")
            if any(ins.get("expr", {}).get("kind") == "binop" for ins in after.get("instructions", []) if ins.get("op") == "assign"):
                raise AssertionError(f"{name}: expected all arithmetic to simplify away")
        elif check == "algebraic_prints":
            if _print_values(after) != [5, 5, 0]:
                raise AssertionError(f"{name}: folded print values missing")
        elif check == "dead_branch_removed":
            if any(op in after_ops for op in ("if_goto", "goto", "label")):
                raise AssertionError(f"{name}: dead branch CFG not removed")
            if 22 in _print_values(after):
                raise AssertionError(f"{name}: dead else branch still present")
            if before == after:
                raise AssertionError(f"{name}: no optimization delta observed")
        elif check == "combo_folded":
            if any(op in after_ops for op in ("if_goto", "goto")):
                raise AssertionError(f"{name}: combined optimization did not remove branch")
            if _print_values(after) != [3]:
                raise AssertionError(f"{name}: dead then branch still present")
            y_value = _assign_value(after, "y")
            if y_value not in (3, None):
                raise AssertionError(f"{name}: combined folding result missing")
        elif check == "unreachable_after_return":
            if _has_print_value(after, 99):
                raise AssertionError(f"{name}: return-following unreachable code not removed")
            if _print_values(after) != [5]:
                raise AssertionError(f"{name}: wrong surviving print sequence")
        elif check == "dead_store_removed":
            if any(v == 42 for v in _assign_values(after, "b")):
                raise AssertionError(f"{name}: dead store to b survived")
            if any(v == 1 for v in _assign_values(after, "a")):
                raise AssertionError(f"{name}: overwritten store to a survived")
            if _print_values(after) != [2]:
                raise AssertionError(f"{name}: live store/use chain broken")
        elif check == "unreachable_after_goto":
            if _has_print_value(after, 77):
                raise AssertionError(f"{name}: goto-skipped code not removed")
            if _print_values(after) != [8]:
                raise AssertionError(f"{name}: reachable path changed")
        else:
            raise AssertionError(f"unknown check: {check}")


def main() -> int:
    for case in CASES:
        noopt_before, noopt_after, noopt_stats = compile_ir(case["src"], case["name"] + "_noopt", "--no-opt")
        o1_before, o1_after, o1_stats = compile_ir(case["src"], case["name"] + "_o1", "--O1")

        if noopt_before != noopt_after:
            raise AssertionError(f"{case['name']}: no-opt unexpectedly changed IR")
        assert_stats(case["name"] + "_noopt", noopt_before, noopt_after, noopt_stats, expect_removed=False)
        assert_stats(case["name"] + "_o1", o1_before, o1_after, o1_stats, expect_removed=case["expect_removed"])
        check_case(case["name"], o1_before, o1_after, case["ir_checks"])

        run_name_noopt = case["run_tag"] + "n"
        run_name_o1 = case["run_tag"] + "o"
        build_case(case["src"], run_name_noopt, "--no-opt")
        out_noopt = run_case(run_name_noopt)
        build_case(case["src"], run_name_o1, "--O1")
        out_o1 = run_case(run_name_o1)

        if out_noopt != case["expect"]:
            raise AssertionError(f"{case['name']}: no-opt expect {case['expect']!r}, got {out_noopt!r}")
        if out_o1 != case["expect"]:
            raise AssertionError(f"{case['name']}: O1 expect {case['expect']!r}, got {out_o1!r}")
        if out_noopt != out_o1:
            raise AssertionError(f"{case['name']}: no-opt and O1 outputs differ")
        print(f"[ok] {case['name']}")

    print("all optimization tests passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
