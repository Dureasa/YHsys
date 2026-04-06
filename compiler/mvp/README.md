YHC internals

- yhc_frontend.py: parse .yhc source into AST
- yhc_ir.py: lower AST into explicit syscall IR
- yhc_codegen_rv32.py: generate RV32 assembly using YHsys syscall numbers
- yhc_compile.py: driver (source -> IR + assembly)
