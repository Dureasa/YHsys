#!/usr/bin/env python3
"""Compatibility wrapper for legacy MVP compiler entrypoint."""

from __future__ import annotations

from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from compiler.yhc_compile import main as _new_main  # noqa: E402

def main() -> int:
    return _new_main()


if __name__ == "__main__":
    raise SystemExit(main())
