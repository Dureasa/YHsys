"""Utility helpers shared by backend/frontend."""

from __future__ import annotations


def align_up(value: int, alignment: int) -> int:
    if alignment <= 0:
        raise ValueError("alignment must be positive")
    return (value + alignment - 1) & ~(alignment - 1)


def bytes_directive(text: str, nul_terminated: bool = True) -> str:
    data = list(text.encode("utf-8"))
    if nul_terminated:
        data.append(0)
    return ".byte " + ", ".join(str(v) for v in data)
