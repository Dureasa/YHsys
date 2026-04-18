#!/usr/bin/env python3
"""Compatibility wrapper for legacy codegen API."""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from compiler.backend.riscv.codegen_rv32 import generate_asm, load_syscall_table  # noqa: E402

__all__ = ["load_syscall_table", "generate_asm"]
