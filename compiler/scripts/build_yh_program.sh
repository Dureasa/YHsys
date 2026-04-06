#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
COMPILER_DIR="${ROOT_DIR}/compiler"
OS_DIR="${ROOT_DIR}/os"
BUILD_DIR="${COMPILER_DIR}/build"

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <source.yhc> [program_name]"
  exit 1
fi

SRC_PATH="$1"
if [[ ! -f "${SRC_PATH}" ]]; then
  echo "error: source file not found: ${SRC_PATH}"
  exit 2
fi

if [[ $# -ge 2 ]]; then
  BASE_NAME="$2"
else
  BASE_NAME="$(basename "${SRC_PATH}")"
  BASE_NAME="${BASE_NAME%.*}"
fi

SAFE_NAME="$(printf '%s' "${BASE_NAME}" | sed 's/[^A-Za-z0-9_]/_/g')"
FINAL_NAME="yhc_${SAFE_NAME}"

IR_PATH="${BUILD_DIR}/${FINAL_NAME}.ir.json"
ASM_PATH="${BUILD_DIR}/${FINAL_NAME}.s"
OBJ_PATH="${BUILD_DIR}/${FINAL_NAME}.o"
BIN_PATH="${OS_DIR}/out/bin/user/_${FINAL_NAME}"

mkdir -p "${BUILD_DIR}"

python3 "${COMPILER_DIR}/mvp/yhc_compile.py" \
  --input "${SRC_PATH}" \
  --ir "${IR_PATH}" \
  --asm "${ASM_PATH}" \
  --syscall-header "${OS_DIR}/kernel/syscall.h" \
  --program-name "${FINAL_NAME}"

TOOLPREFIX=""
for prefix in \
  riscv64-unknown-elf- \
  riscv64-elf- \
  riscv64-linux-gnu- \
  riscv64-unknown-linux-gnu-
do
  if command -v "${prefix}gcc" >/dev/null 2>&1; then
    TOOLPREFIX="${prefix}"
    break
  fi
done

if [[ -z "${TOOLPREFIX}" ]]; then
  echo "error: cannot find riscv32-capable toolchain prefix"
  exit 3
fi

echo "[yhc-build] using toolchain prefix: ${TOOLPREFIX}"

echo "[yhc-build] preparing OS prerequisites"
make -C "${OS_DIR}" \
  out/bin/kernel/yhsys-kernel.elf \
  out/bin/host/mkfs \
  out/obj/user/ulib.o \
  out/obj/user/printf.o \
  out/obj/user/umalloc.o \
  out/obj/user/div64.o \
  out/obj/user/usys.o

echo "[yhc-build] assembling ${ASM_PATH}"
"${TOOLPREFIX}gcc" -march=rv32gc -mabi=ilp32 -fno-pie -no-pie -c -o "${OBJ_PATH}" "${ASM_PATH}"

echo "[yhc-build] linking ${BIN_PATH}"
"${TOOLPREFIX}ld" -z max-page-size=4096 -m elf32lriscv \
  -T "${OS_DIR}/user/user.ld" \
  -o "${BIN_PATH}" \
  "${OBJ_PATH}" \
  "${OS_DIR}/out/obj/user/ulib.o" \
  "${OS_DIR}/out/obj/user/printf.o" \
  "${OS_DIR}/out/obj/user/umalloc.o" \
  "${OS_DIR}/out/obj/user/div64.o" \
  "${OS_DIR}/out/obj/user/usys.o"

echo "[yhc-build] rebuilding fs image with new binary"
mapfile -t USER_BINS < <(find "${OS_DIR}/out/bin/user" -maxdepth 1 -type f -name "_*" | sort)
"${OS_DIR}/out/bin/host/mkfs" "${OS_DIR}/out/img/fs-system.img" "${OS_DIR}/README" "${USER_BINS[@]}"

echo "[yhc-build] done"
echo "[yhc-build] IR      : ${IR_PATH}"
echo "[yhc-build] ASM     : ${ASM_PATH}"
echo "[yhc-build] OBJ     : ${OBJ_PATH}"
echo "[yhc-build] USER BIN: ${BIN_PATH}"
echo "[yhc-build] shell cmd in YHsys: ${FINAL_NAME}"
