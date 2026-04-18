"""IR datamodel used by backend code generators."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any


@dataclass(frozen=True)
class IRSymbol:
    name: str
    size: int | None


@dataclass(frozen=True)
class IRConstant:
    cid: str
    text: str
    size: int


@dataclass(frozen=True)
class IRInstruction:
    op: str
    args: dict[str, Any]


@dataclass
class IRModule:
    version: str = "1.0"
    target: str = "rv32-yhsys"
    symbols: list[IRSymbol] = field(default_factory=list)
    constants: list[IRConstant] = field(default_factory=list)
    instructions: list[IRInstruction] = field(default_factory=list)

    def to_dict(self) -> dict[str, Any]:
        return {
            "version": self.version,
            "target": self.target,
            "symbols": [{"name": s.name, "size": s.size} for s in self.symbols],
            "constants": [{"id": c.cid, "text": c.text, "size": c.size} for c in self.constants],
            "instructions": [{"op": ins.op, **ins.args} for ins in self.instructions],
        }
