#!/usr/bin/env python3
"""IR lowering for YHC source AST."""

from __future__ import annotations

from dataclasses import dataclass

from yhc_frontend import AstNode


@dataclass
class ConstStr:
    cid: str
    text: str
    size: int


@dataclass
class IrInst:
    op: str
    args: dict


def lower_ast(nodes: list[AstNode]) -> dict:
    constants: list[ConstStr] = []
    instructions: list[IrInst] = []

    str_index = 0
    has_exit = False

    for node in nodes:
        if node.op == "print":
            data = str(node.value).encode("utf-8")
            cid = f"str{str_index}"
            str_index += 1
            constants.append(ConstStr(cid=cid, text=str(node.value), size=len(data)))
            instructions.append(IrInst(op="sys_write", args={"fd": 1, "const": cid, "size": len(data)}))
            continue

        if node.op == "pause":
            instructions.append(IrInst(op="sys_pause", args={"ticks": int(node.value)}))
            continue

        if node.op == "exit":
            instructions.append(IrInst(op="sys_exit", args={"code": int(node.value)}))
            has_exit = True
            continue

        raise ValueError(f"unsupported AST op: {node.op}")

    if not has_exit:
        instructions.append(IrInst(op="sys_exit", args={"code": 0}))

    return {
        "version": "0.1",
        "target": "rv32-yhsys",
        "constants": [{"id": c.cid, "text": c.text, "size": c.size} for c in constants],
        "instructions": [{"op": ins.op, **ins.args} for ins in instructions],
    }
