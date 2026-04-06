# YHC Compiler MVP (YHsys)

This directory contains a minimal end-to-end compiler flow:

source (`.yhc`) -> IR (`.ir.json`) -> RV32 assembly (`.s`) -> user binary -> YHsys fs image

## Supported Language (YHC)

Statements must end with `;`:

- `print "text";`
- `write "text";` (alias of `print`)
- `pause N;`
- `exit N;`

Comments:

- `# comment`
- `// comment`

String escapes:

- `\n`, `\t`, `\r`, `\\`, `\"`

## Build + Integrate

From repository root:

```bash
bash compiler/scripts/build_yh_program.sh compiler/examples/hello.yhc hello
```

Outputs:

- IR: `compiler/build/yhc_hello.ir.json`
- ASM: `compiler/build/yhc_hello.s`
- OBJ: `compiler/build/yhc_hello.o`
- ELF user binary: `os/out/bin/user/_yhc_hello`
- Repacked image: `os/out/img/fs-system.img`

## Run In YHsys

```bash
python3 compiler/scripts/run_yh_program.py --program yhc_hello --os-dir os
```

Or boot manually:

```bash
cd os
make qemu
# in shell:
yhc_hello
```

## Clean Generated Compiler Outputs

```bash
bash compiler/scripts/clean_mvp.sh
```

This removes generated compiler outputs and `_yhc_*` binaries from `os/out/bin/user`, then repacks fs image.
