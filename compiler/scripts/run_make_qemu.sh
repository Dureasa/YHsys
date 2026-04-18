#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
OS_DIR="${ROOT_DIR}/os"

echo "[run-qemu] executing make qemu in ${OS_DIR}"
cd "${OS_DIR}"
make qemu "$@"
