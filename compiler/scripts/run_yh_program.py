#!/usr/bin/env python3
"""Run a user command inside YHsys QEMU and print captured output."""

from __future__ import annotations

import argparse
import errno
import os
import pty
import re
import select
import signal
import time


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run a command inside YHsys shell")
    parser.add_argument("--program", required=True, help="program name in YHsys shell")
    parser.add_argument("--timeout", type=int, default=25, help="timeout seconds")
    parser.add_argument("--os-dir", default="os", help="path to os directory")
    return parser.parse_args()


def read_until(fd: int, pattern: str, timeout: float) -> str:
    deadline = time.time() + timeout
    out = bytearray()
    regex = re.compile(pattern)

    while time.time() < deadline:
        ready, _, _ = select.select([fd], [], [], 0.2)
        if not ready:
            continue
        try:
            data = os.read(fd, 4096)
        except OSError as e:
            if e.errno == errno.EIO:
                break
            raise
        if not data:
            break
        out.extend(data)
        text = out.decode("utf-8", "replace")
        if regex.search(text):
            return text

    return out.decode("utf-8", "replace")


def main() -> int:
    args = parse_args()
    os_dir = os.path.abspath(args.os_dir)

    qemu_cmd = [
        "qemu-system-riscv32",
        "-machine", "virt",
        "-bios", "none",
        "-kernel", os.path.join(os_dir, "out/bin/kernel/yhsys-kernel.elf"),
        "-m", "128M",
        "-smp", "1",
        "-nographic",
        "-global", "virtio-mmio.force-legacy=false",
        "-drive", f"file={os.path.join(os_dir, 'out/img/fs-system.img')},if=none,format=raw,id=x0",
        "-device", "virtio-blk-device,drive=x0,bus=virtio-mmio-bus.0",
    ]

    pid, fd = pty.fork()
    if pid == 0:
        os.chdir(os_dir)
        os.execvp(qemu_cmd[0], qemu_cmd)

    try:
        boot = read_until(fd, r"YHsys> ", args.timeout)
        if "YHsys> " not in boot:
            print("[run] failed to reach shell prompt")
            print(boot)
            return 2

        os.write(fd, (args.program + "\n").encode("utf-8"))
        out = read_until(fd, r"YHsys> ", args.timeout)

        # Print command output region only.
        marker = args.program + "\r\n"
        idx = out.find(marker)
        if idx >= 0:
            text = out[idx + len(marker):]
        else:
            text = out

        text = text.replace("YHsys> ", "")
        print(text.strip())
        return 0
    finally:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            os.waitpid(pid, 0)
        except ChildProcessError:
            pass


if __name__ == "__main__":
    raise SystemExit(main())
