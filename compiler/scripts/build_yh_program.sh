#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
COMPILER_DIR="${ROOT_DIR}/compiler"
OS_DIR="${ROOT_DIR}/os"
BUILD_DIR="${COMPILER_DIR}/build"
DIRSIZ=14

normalize_cmd_name() {
  local raw="$1"
  local safe
  local hash
  local suffix
  local prefix_len

  safe="$(printf '%s' "${raw}" | sed 's/[^A-Za-z0-9_]/_/g')"
  if [[ -z "${safe}" ]]; then
    echo ""
    return
  fi

  if (( ${#safe} <= DIRSIZ )); then
    echo "${safe}"
    return
  fi

  hash="$(printf '%s' "${safe}" | cksum | awk '{print $1}')"
  suffix="$(printf '%04x' $((hash % 65536)))"
  prefix_len=$((DIRSIZ - 1 - ${#suffix}))
  echo "${safe:0:prefix_len}_${suffix}"
}

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <source.c> [program_name]"
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
CMD_NAME="$(normalize_cmd_name "${FINAL_NAME}")"

if [[ -z "${CMD_NAME}" ]]; then
  echo "error: empty command name after sanitize"
  exit 4
fi

if [[ "${CMD_NAME}" != "${FINAL_NAME}" ]]; then
  echo "[yhc-build] note: fs command name truncated to '${CMD_NAME}' (DIRSIZ=${DIRSIZ})"
fi

IR_PATH="${BUILD_DIR}/${FINAL_NAME}.ir.json"
ASM_PATH="${BUILD_DIR}/${FINAL_NAME}.s"
OBJ_PATH="${BUILD_DIR}/${FINAL_NAME}.o"
ELF_PATH="${BUILD_DIR}/${FINAL_NAME}.elf"

mkdir -p "${BUILD_DIR}"

python3 "${COMPILER_DIR}/yhc_compile.py" \
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

echo "[yhc-build] linking ${ELF_PATH}"
"${TOOLPREFIX}ld" -z max-page-size=4096 -m elf32lriscv \
  -T "${OS_DIR}/user/user.ld" \
  -o "${ELF_PATH}" \
  "${OBJ_PATH}" \
  "${OS_DIR}/out/obj/user/ulib.o" \
  "${OS_DIR}/out/obj/user/printf.o" \
  "${OS_DIR}/out/obj/user/umalloc.o" \
  "${OS_DIR}/out/obj/user/div64.o" \
  "${OS_DIR}/out/obj/user/usys.o"

echo "[yhc-build] injecting ELF into YHsys fs image"
bash "${COMPILER_DIR}/scripts/inject_user_binary.sh" "${ELF_PATH}" "${CMD_NAME}"

BIN_PATH="${OS_DIR}/out/bin/user/_${CMD_NAME}"

echo "[yhc-build] done"
echo "[yhc-build] IR      : ${IR_PATH}"
echo "[yhc-build] ASM     : ${ASM_PATH}"
echo "[yhc-build] OBJ     : ${OBJ_PATH}"
echo "[yhc-build] ELF     : ${ELF_PATH}"
echo "[yhc-build] USER BIN: ${BIN_PATH}"
echo "[yhc-build] shell cmd in YHsys: ${CMD_NAME}"
