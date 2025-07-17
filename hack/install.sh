#!/usr/bin/env bash

# Set error handling
set -o errexit
set -o nounset
set -o pipefail

# Get the root directory and third_party directory
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

# Include the common functions
source "${ROOT_DIR}/hack/lib/init.sh"

function download_deps() {
  if [[ -z "$(command -v poetry)" ]]; then
    pip install poetry==1.8.3
  fi
  if ! poetry self show plugins -n | grep -q dynamic-versioning; then
    poetry self add poetry-dynamic-versioning
  fi
  poetry install
  if [[ "${POETRY_ONLY:-false}" == "false" ]]; then
    pip install pre-commit==4.2.0
    pre-commit install
  fi
}

gpustack::log::info "+++ DEPENDENCIES +++"
download_deps
source "${ROOT_DIR}/hack/export_version.sh"
gpustack::log::info "--- DEPENDENCIES ---"
