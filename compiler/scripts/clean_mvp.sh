#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
COMPILER_DIR="${ROOT_DIR}/compiler"
OS_DIR="${ROOT_DIR}/os"

echo "[yhc-clean] removing compiler build outputs"
rm -f "${COMPILER_DIR}"/build/*.ir.json "${COMPILER_DIR}"/build/*.s "${COMPILER_DIR}"/build/*.o "${COMPILER_DIR}"/build/*.elf

echo "[yhc-clean] removing generated YHC user binaries"
rm -f "${OS_DIR}"/out/bin/user/_yhc_*

if [[ -x "${OS_DIR}/out/bin/host/mkfs" ]]; then
  echo "[yhc-clean] rebuilding fs image without generated YHC binaries"
  mapfile -t USER_BINS < <(find "${OS_DIR}/out/bin/user" -maxdepth 1 -type f -name "_*" | sort)
  "${OS_DIR}/out/bin/host/mkfs" "${OS_DIR}/out/img/fs-system.img" "${OS_DIR}/README" "${USER_BINS[@]}"
else
  echo "[yhc-clean] mkfs host tool not found; skip fs image rebuild"
fi

echo "[yhc-clean] done"
