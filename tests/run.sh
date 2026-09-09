#!/usr/bin/env bash
set -Eeuo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
bash "$ROOT/tests/test-common.sh"
bash "$ROOT/tests/test-platform.sh"
bash "$ROOT/tests/test-launcher.sh"
