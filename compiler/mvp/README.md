YHC MVP compatibility layer

- `yhc_compile.py`: legacy entrypoint wrapper, forwards to `compiler/yhc_compile.py`
- `yhc_frontend.py`: wrapper for new frontend parser API
- `yhc_ir.py`: wrapper for semantic + IR lowering API
- `yhc_codegen_rv32.py`: wrapper for new RV32 backend API

These files preserve old script imports while the real implementation lives in modular directories:

- `compiler/frontend/`
- `compiler/ir/`
- `compiler/backend/riscv/`
- `compiler/utils/`
