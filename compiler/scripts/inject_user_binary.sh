#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
OS_DIR="${ROOT_DIR}/os"
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
  echo "usage: $0 <binary_elf_path> [command_name]"
  exit 1
fi

SRC_BIN="$1"
if [[ ! -f "${SRC_BIN}" ]]; then
  echo "error: binary not found: ${SRC_BIN}"
  exit 2
fi

if [[ $# -ge 2 ]]; then
  CMD_NAME="$2"
else
  base="$(basename "${SRC_BIN}")"
  base="${base%.*}"
  CMD_NAME="${base}"
fi

SAFE_NAME="$(printf '%s' "${CMD_NAME}" | sed 's/[^A-Za-z0-9_]/_/g')"
SAFE_NAME="$(normalize_cmd_name "${CMD_NAME}")"
if [[ -z "${SAFE_NAME}" ]]; then
  echo "error: empty command name after sanitize"
  exit 3
fi

DEST_BIN="${OS_DIR}/out/bin/user/_${SAFE_NAME}"

echo "[inject] preparing mkfs and user bin directory"
make -C "${OS_DIR}" out/bin/host/mkfs out/bin/kernel/yhsys-kernel.elf >/dev/null
mkdir -p "${OS_DIR}/out/bin/user"

cp -f "${SRC_BIN}" "${DEST_BIN}"

echo "[inject] repacking fs image"
USER_BINS=()
while IFS= read -r path; do
  base="$(basename "${path}")"
  short="${base#_}"
  if (( ${#short} > DIRSIZ )); then
    echo "[inject] warning: skip overlong binary '${base}' (max ${DIRSIZ} chars in fs)"
    continue
  fi
  USER_BINS+=("${path}")
done < <(find "${OS_DIR}/out/bin/user" -maxdepth 1 -type f -name "_*" | sort)

if [[ ${#USER_BINS[@]} -eq 0 ]]; then
  echo "error: no valid user binaries to pack"
  exit 4
fi

"${OS_DIR}/out/bin/host/mkfs" "${OS_DIR}/out/img/fs-system.img" "${OS_DIR}/README" "${USER_BINS[@]}"

echo "[inject] done"
echo "[inject] installed: ${DEST_BIN}"
echo "[inject] shell command in YHsys: ${SAFE_NAME}"
