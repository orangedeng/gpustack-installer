#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

DEBUG="${DEBUG:-}"
if [[ -n "${DEBUG}" ]]; then
  set -o xtrace
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "${ROOT_DIR}/hack/lib/init.sh"

PREFIX="${INSTALL_PREFIX:-${ROOT_DIR}/openfst/build}"
VOX_BOX_VERSION="${VOX_BOX_VERSION:-}"
BUILD_ROOT="${ROOT_DIR}/build_third_party"


function download_ui() {
  local default_tag="latest"
  local ui_path
  ui_path=$(find "${BUILD_ROOT}/.venv/lib" -type d -name gpustack | head -n 1)
  ui_path="${ui_path}/ui"
  local tmp_ui_path="${ui_path}/tmp"
  local tag="latest"

  # Only download if ui_path does not exist or is empty
  if [[ -d "${ui_path}" && $(ls -A "${ui_path}" 2>/dev/null) ]]; then
    gpustack::log::info "UI assets already exist in ${ui_path}, skipping download."
    return
  fi

  if [[ -n "${GPUSTACK_VERSION}" ]]; then
    tag="${GPUSTACK_VERSION}"
  fi

  rm -rf "${ui_path}"
  mkdir -p "${tmp_ui_path}/ui"

  gpustack::log::info "downloading '${tag}' UI assets"

  if ! curl --retry 3 --retry-connrefused --retry-delay 3 -sSfL "https://gpustack-ui-1303613262.cos.accelerate.myqcloud.com/releases/${tag}.tar.gz" 2>/dev/null |
    tar -xzf - --directory "${tmp_ui_path}/ui" 2>/dev/null; then

    gpustack::log::warn "failed to download '${tag}' ui archive, fallback to '${default_tag}' ui archive"
    if ! curl --retry 3 --retry-connrefused --retry-delay 3 -sSfL "https://gpustack-ui-1303613262.cos.accelerate.myqcloud.com/releases/${default_tag}.tar.gz" |
      tar -xzf - --directory "${tmp_ui_path}/ui" 2>/dev/null; then
      gpustack::log::fatal "failed to download '${default_tag}' ui archive"
    fi
  fi
  cp -a "${tmp_ui_path}/ui/dist/." "${ui_path}"

  rm -rf "${tmp_ui_path}"
  touch .gpustack-ui-downloaded
}

function cleanup_ui() {
  if [[ ! -f .gpustack-ui-downloaded ]]; then
    gpustack::log::info "UI assets not downloaded, skipping cleanup."
    return
  fi
  local ui_path
  ui_path=$(find "${BUILD_ROOT}/.venv/lib" -type d -name gpustack | head -n 1)
  ui_path="${ui_path}/ui"
  if [[ -d "${ui_path}" ]]; then
    rm -rf "${ui_path}"
  fi
  rm .gpustack-ui-downloaded
}

function build() {
  VIRTUAL_ENV_DIR="${BUILD_ROOT}/.venv"
  # creating virtual environment
  python -m venv "${VIRTUAL_ENV_DIR}"
  #shellcheck disable=SC1091
  source "${VIRTUAL_ENV_DIR}/bin/activate"
  gpustack::log::info "create virtual environment in .venv-vox-box"
  pip install pyinstaller==6.14.2
  fixed_transformers_version="${TRANSFORMERS_VERSION:-4.51.3}"
  if [ -z "${GPUSTACK_VERSION}" ]; then
    pip install transformers=="${fixed_transformers_version}" "git+${GPUSTACK_REPO}@${GPUSTACK_BRANCH:-main}#egg=gpustack[audio]"
  else
    pip install transformers=="${fixed_transformers_version}" "gpustack[audio]==${GPUSTACK_VERSION#v}"
  fi
  gpustack::log::info "installed gpustack version ${GPUSTACK_VERSION:-latest}"
  download_ui
  pyinstaller -y "${BUILD_ROOT}/gpustack.spec"
  cleanup_ui
  gpustack::log::info "gpustack built successfully"
  deactivate
}

gpustack::log::info "+++ BUILD GPUSTACK +++"
gpustack::util::check_python_version
source "${ROOT_DIR}/hack/build-openfst.sh"
export LIBRARY_PATH="${PREFIX}/lib:${LIBRARY_PATH:-}"
export CPLUS_INCLUDE_PATH="${PREFIX}/include:${CPLUS_INCLUDE_PATH:-}"
build
gpustack::log::info "--- BUILD GPUSTACK ---"
