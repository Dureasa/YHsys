#!/usr/bin/env python3
"""Compatibility wrapper for legacy IR API."""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from compiler.frontend.semantic.analyzer import SemanticAnalyzer  # noqa: E402
from compiler.ir.builder import lower_program  # noqa: E402


def lower_ast(program):
    symbols = SemanticAnalyzer().analyze(program)
    return lower_program(program, symbols)


__all__ = ["lower_ast"]
