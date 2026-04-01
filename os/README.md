# xv6-rv32

This repository is an independent port of MIT xv6 to **RISC-V 32-bit (RV32GC)**.

It is intended for learning and experimentation around:
- 32-bit address-space behavior
- memory-management differences from RV64 xv6
- kernel and user-space compatibility on RV32

## Upstream References

This project is based on MIT xv6-riscv:
- Main repository: https://github.com/mit-pdos/xv6-riscv
- Upstream README: https://github.com/mit-pdos/xv6-riscv/blob/riscv/README
- Course resources: https://pdos.csail.mit.edu/6.1810/

## What Is Different In This Repo

Compared with upstream xv6-riscv, this repo contains RV32-focused changes.
You can use this section as a changelog summary for your own updates.

Current highlights:
- Ported kernel and userland build/boot flow to RV32GC.
- Updated memory-related paths for RV32 behavior and validation.
- Added/adjusted logic to pass lazy allocation related tests in this branch.

## Build And Run

Requirements:
- RISC-V GCC/newlib toolchain
- QEMU user emulation for RISC-V 32-bit (the `qemu-system-riscv32` binary)

Then run:

```sh
make qemu
```

## Test

Run user tests in QEMU shell:

```sh
usertests
```

If reporting a bug, include:
- toolchain version
- qemu version
- full log
- minimal reproduction steps

## Notes

- This is **not** an official MIT xv6 upstream branch.
- Behavior may intentionally diverge from RV64 xv6 where RV32 constraints require it.

## License And Credits

Please follow upstream xv6 license terms (see `LICENSE`).
All original xv6 design and most baseline code belong to the MIT xv6 contributors.