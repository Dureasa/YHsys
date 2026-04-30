"""Local IR optimization passes for YHC."""

from __future__ import annotations

from copy import deepcopy
from dataclasses import dataclass
from typing import Any


@dataclass
class OptimizationStats:
    instructions_before: int
    instructions_after: int

    @property
    def instructions_removed(self) -> int:
        return self.instructions_before - self.instructions_after

    def to_dict(self) -> dict[str, int]:
        return {
            "instructions_before": self.instructions_before,
            "instructions_after": self.instructions_after,
            "instructions_removed": self.instructions_removed,
        }


def _clone_expr(expr: dict[str, Any]) -> dict[str, Any]:
    return deepcopy(expr)


def _fold_unary(op: str, value: int) -> int:
    if op == "+":
        return value
    if op == "-":
        return -value
    if op == "!":
        return 0 if value else 1
    if op == "~":
        return ~value
    raise ValueError(f"unsupported unary operator '{op}'")


def _fold_binary(op: str, lhs: int, rhs: int) -> int:
    if op == "+":
        return lhs + rhs
    if op == "-":
        return lhs - rhs
    if op == "*":
        return lhs * rhs
    if op == "/":
        return int(lhs / rhs)
    if op == "%":
        return lhs % rhs
    if op == "<<":
        return lhs << rhs
    if op == ">>":
        return lhs >> rhs
    if op == "&":
        return lhs & rhs
    if op == "|":
        return lhs | rhs
    if op == "^":
        return lhs ^ rhs
    if op == "==":
        return 1 if lhs == rhs else 0
    if op == "!=":
        return 1 if lhs != rhs else 0
    if op == "<":
        return 1 if lhs < rhs else 0
    if op == "<=":
        return 1 if lhs <= rhs else 0
    if op == ">":
        return 1 if lhs > rhs else 0
    if op == ">=":
        return 1 if lhs >= rhs else 0
    if op == "&&":
        return 1 if (lhs != 0 and rhs != 0) else 0
    if op == "||":
        return 1 if (lhs != 0 or rhs != 0) else 0
    raise ValueError(f"unsupported binary operator '{op}'")


def _is_int(expr: dict[str, Any], value: int | None = None) -> bool:
    if expr.get("kind") != "int":
        return False
    if value is None:
        return True
    return int(expr.get("value")) == value


def _truthy_const(expr: dict[str, Any]) -> bool | None:
    if expr.get("kind") != "int":
        return None
    return int(expr["value"]) != 0


def _simplify_expr(expr: dict[str, Any], env: dict[str, int]) -> dict[str, Any]:
    kind = expr.get("kind")

    if kind == "int":
        return _clone_expr(expr)

    if kind == "var":
        name = str(expr["name"])
        if name in env:
            return {"kind": "int", "value": env[name]}
        return _clone_expr(expr)

    if kind == "array":
        new_expr = _clone_expr(expr)
        new_expr["index"] = _simplify_expr(expr["index"], env)
        return new_expr

    if kind == "unary":
        operand = _simplify_expr(expr["operand"], env)
        if _is_int(operand):
            return {"kind": "int", "value": _fold_unary(str(expr["op"]), int(operand["value"]))}
        return {"kind": "unary", "op": expr["op"], "operand": operand}

    if kind == "binop":
        op = str(expr["op"])
        lhs = _simplify_expr(expr["lhs"], env)
        rhs = _simplify_expr(expr["rhs"], env)

        if _is_int(lhs) and _is_int(rhs):
            if op in ("/", "%") and int(rhs["value"]) == 0:
                return {"kind": "binop", "op": op, "lhs": lhs, "rhs": rhs}
            return {"kind": "int", "value": _fold_binary(op, int(lhs["value"]), int(rhs["value"]))}

        if op == "+":
            if _is_int(lhs, 0):
                return rhs
            if _is_int(rhs, 0):
                return lhs
        elif op == "-":
            if _is_int(rhs, 0):
                return lhs
        elif op == "*":
            if _is_int(lhs, 0) or _is_int(rhs, 0):
                return {"kind": "int", "value": 0}
            if _is_int(lhs, 1):
                return rhs
            if _is_int(rhs, 1):
                return lhs
        elif op == "/":
            if _is_int(rhs, 1):
                return lhs
        elif op == "&&":
            lhs_truthy = _truthy_const(lhs)
            rhs_truthy = _truthy_const(rhs)
            if lhs_truthy is False or rhs_truthy is False:
                return {"kind": "int", "value": 0}
            if lhs_truthy is True:
                return {"kind": "unary", "op": "!", "operand": {"kind": "unary", "op": "!", "operand": rhs}}
            if rhs_truthy is True:
                return {"kind": "unary", "op": "!", "operand": {"kind": "unary", "op": "!", "operand": lhs}}
        elif op == "||":
            lhs_truthy = _truthy_const(lhs)
            rhs_truthy = _truthy_const(rhs)
            if lhs_truthy is True or rhs_truthy is True:
                return {"kind": "int", "value": 1}
            if lhs_truthy is False:
                return {"kind": "unary", "op": "!", "operand": {"kind": "unary", "op": "!", "operand": rhs}}
            if rhs_truthy is False:
                return {"kind": "unary", "op": "!", "operand": {"kind": "unary", "op": "!", "operand": lhs}}

        return {"kind": "binop", "op": op, "lhs": lhs, "rhs": rhs}

    raise ValueError(f"unsupported expression kind: {kind}")


def _simplify_fixed_point(expr: dict[str, Any], env: dict[str, int]) -> dict[str, Any]:
    current = _clone_expr(expr)
    while True:
        next_expr = _simplify_expr(current, env)
        if next_expr == current:
            return next_expr
        current = next_expr


def _assigned_var(target: dict[str, Any]) -> str | None:
    if target.get("kind") == "var":
        return str(target["name"])
    return None


def _invalidate_on_store(env: dict[str, int], target: dict[str, Any], symbols: list[dict[str, Any]]) -> None:
    if target.get("kind") == "var":
        env.pop(str(target["name"]), None)
        return
    if target.get("kind") == "array":
        env.pop(str(target["name"]), None)
        for sym in symbols:
            if sym.get("size") is not None:
                env.pop(str(sym["name"]), None)


def optimize_ir(module: dict[str, Any]) -> tuple[dict[str, Any], OptimizationStats]:
    optimized = deepcopy(module)
    before = len(optimized.get("instructions", []))

    while True:
        next_module = _optimize_once(optimized)
        if next_module == optimized:
            break
        optimized = next_module

    after = len(optimized.get("instructions", []))
    return optimized, OptimizationStats(instructions_before=before, instructions_after=after)


def _optimize_once(module: dict[str, Any]) -> dict[str, Any]:
    optimized = deepcopy(module)
    symbols = optimized.get("symbols", [])
    instructions = optimized.get("instructions", [])

    env: dict[str, int] = {}
    new_instructions: list[dict[str, Any]] = []

    idx = 0
    while idx < len(instructions):
        ins = deepcopy(instructions[idx])
        op = ins.get("op")

        if op == "label":
            env.clear()
            new_instructions.append(ins)
            idx += 1
            continue

        if op == "goto":
            env.clear()
            new_instructions.append(ins)
            idx += 1
            continue

        if op == "if_goto":
            cond = _simplify_fixed_point(ins["cond"], env)
            folded = _truthy_const(cond)
            if folded is True:
                new_instructions.append({"op": "goto", "label": ins["label"]})
            elif folded is False:
                pass
            else:
                ins["cond"] = cond
                new_instructions.append(ins)
            env.clear()
            idx += 1
            continue

        if op == "assign":
            target = deepcopy(ins["target"])
            expr = _simplify_fixed_point(ins["expr"], env)
            ins["target"] = target
            ins["expr"] = expr
            _invalidate_on_store(env, target, symbols)
            assigned = _assigned_var(target)
            if assigned is not None and _is_int(expr):
                env[assigned] = int(expr["value"])
            new_instructions.append(ins)
            idx += 1
            continue

        if op == "array_zero":
            env.pop(str(ins["name"]), None)
            new_instructions.append(ins)
            idx += 1
            continue

        if op in ("sys_write_expr", "sys_pause_expr", "sys_exit_expr"):
            ins["expr"] = _simplify_fixed_point(ins["expr"], env)
            new_instructions.append(ins)
            idx += 1
            continue

        new_instructions.append(ins)
        idx += 1

    new_instructions = _remove_dead_branches(new_instructions)
    new_instructions = _remove_unreachable_code(new_instructions)
    new_instructions = _remove_dead_stores(new_instructions)
    optimized["instructions"] = _cleanup_control_flow(new_instructions)
    return optimized


def _remove_dead_branches(instructions: list[dict[str, Any]]) -> list[dict[str, Any]]:
    pruned: list[dict[str, Any]] = []
    for ins in instructions:
        if ins.get("op") != "if_goto":
            pruned.append(ins)
            continue
        folded = _truthy_const(ins.get("cond", {}))
        if folded is True:
            pruned.append({"op": "goto", "label": ins["label"]})
        elif folded is False:
            continue
        else:
            pruned.append(ins)
    return pruned


def _remove_unreachable_code(instructions: list[dict[str, Any]]) -> list[dict[str, Any]]:
    if not instructions:
        return []

    label_to_index = {
        str(ins["name"]): idx
        for idx, ins in enumerate(instructions)
        if ins.get("op") == "label"
    }

    visited: set[int] = set()
    worklist = [0]

    while worklist:
        idx = worklist.pop()
        if idx < 0 or idx >= len(instructions) or idx in visited:
            continue
        visited.add(idx)

        ins = instructions[idx]
        op = ins.get("op")

        if op == "goto":
            target = label_to_index.get(str(ins["label"]))
            if target is not None:
                worklist.append(target)
            continue

        if op == "if_goto":
            target = label_to_index.get(str(ins["label"]))
            if target is not None:
                worklist.append(target)
            worklist.append(idx + 1)
            continue

        if op == "sys_exit_expr":
            continue

        worklist.append(idx + 1)

    return [ins for idx, ins in enumerate(instructions) if idx in visited]


def _expr_reads(expr: dict[str, Any]) -> set[str]:
    kind = expr.get("kind")
    if kind == "var":
        return {str(expr["name"])}
    if kind == "array":
        reads = {str(expr["name"])}
        reads |= _expr_reads(expr.get("index", {}))
        return reads
    if kind == "unary":
        return _expr_reads(expr.get("operand", {}))
    if kind == "binop":
        reads = _expr_reads(expr.get("lhs", {}))
        reads |= _expr_reads(expr.get("rhs", {}))
        return reads
    return set()


def _expr_is_side_effect_free(expr: dict[str, Any]) -> bool:
    kind = expr.get("kind")
    if kind in ("int", "var"):
        return True
    if kind == "array":
        return _expr_is_side_effect_free(expr.get("index", {}))
    if kind == "unary":
        return _expr_is_side_effect_free(expr.get("operand", {}))
    if kind == "binop":
        op = str(expr.get("op"))
        lhs = expr.get("lhs", {})
        rhs = expr.get("rhs", {})
        if op in ("/", "%"):
            if not _is_int(rhs) or int(rhs["value"]) == 0:
                return False
        return _expr_is_side_effect_free(lhs) and _expr_is_side_effect_free(rhs)
    return False


def _remove_dead_stores(instructions: list[dict[str, Any]]) -> list[dict[str, Any]]:
    if not instructions:
        return []

    n = len(instructions)
    label_to_index = {
        str(ins["name"]): idx
        for idx, ins in enumerate(instructions)
        if ins.get("op") == "label"
    }

    succs: list[set[int]] = [set() for _ in range(n)]
    uses: list[set[str]] = [set() for _ in range(n)]
    defs: list[set[str]] = [set() for _ in range(n)]

    for idx, ins in enumerate(instructions):
        op = ins.get("op")

        if op == "goto":
            target = label_to_index.get(str(ins["label"]))
            if target is not None:
                succs[idx].add(target)
        elif op == "if_goto":
            target = label_to_index.get(str(ins["label"]))
            if target is not None:
                succs[idx].add(target)
            if idx + 1 < n:
                succs[idx].add(idx + 1)
            uses[idx] |= _expr_reads(ins.get("cond", {}))
        elif op == "sys_exit_expr":
            uses[idx] |= _expr_reads(ins.get("expr", {}))
        else:
            if idx + 1 < n:
                succs[idx].add(idx + 1)
            if op == "assign":
                target = ins.get("target", {})
                uses[idx] |= _expr_reads(ins.get("expr", {}))
                if target.get("kind") == "array":
                    uses[idx] |= _expr_reads(target.get("index", {}))
                elif target.get("kind") == "var":
                    defs[idx].add(str(target["name"]))
            elif op in ("sys_write_expr", "sys_pause_expr"):
                uses[idx] |= _expr_reads(ins.get("expr", {}))

    live_in: list[set[str]] = [set() for _ in range(n)]
    live_out: list[set[str]] = [set() for _ in range(n)]

    changed = True
    while changed:
        changed = False
        for idx in range(n - 1, -1, -1):
            next_out: set[str] = set()
            for succ in succs[idx]:
                next_out |= live_in[succ]

            next_in = uses[idx] | (next_out - defs[idx])
            if next_out != live_out[idx] or next_in != live_in[idx]:
                live_out[idx] = next_out
                live_in[idx] = next_in
                changed = True

    pruned: list[dict[str, Any]] = []
    for idx, ins in enumerate(instructions):
        if ins.get("op") == "assign":
            target = ins.get("target", {})
            if target.get("kind") == "var":
                name = str(target["name"])
                if name not in live_out[idx] and _expr_is_side_effect_free(ins.get("expr", {})):
                    continue
        pruned.append(ins)
    return pruned


def _cleanup_control_flow(instructions: list[dict[str, Any]]) -> list[dict[str, Any]]:
    current = instructions
    while True:
        next_instructions: list[dict[str, Any]] = []
        changed = False

        for idx, ins in enumerate(current):
            if ins.get("op") == "goto" and idx + 1 < len(current):
                next_ins = current[idx + 1]
                if next_ins.get("op") == "label" and str(next_ins["name"]) == str(ins["label"]):
                    changed = True
                    continue
            next_instructions.append(ins)

        live_labels = {
            str(ins["label"])
            for ins in next_instructions
            if ins.get("op") in ("goto", "if_goto")
        }
        pruned: list[dict[str, Any]] = []
        for ins in next_instructions:
            if ins.get("op") == "label" and str(ins["name"]) not in live_labels:
                changed = True
                continue
            pruned.append(ins)

        if not changed:
            return pruned
        current = pruned
