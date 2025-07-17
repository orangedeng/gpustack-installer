#!/usr/bin/env bash


function gpustack::util::sed() {
  if ! sed -i "$@" >/dev/null 2>&1; then
    # back off none GNU sed
    sed -i "" "$@"
  fi
}

function gpustack::util::get_os_name() {
  # Support overriding by BUILD_OS for cross-building
  local os_name="${BUILD_OS:-}"
  if [[ -n "$os_name" ]]; then
    echo "$os_name" | tr '[:upper:]' '[:lower:]'
  else
    uname -s | tr '[:upper:]' '[:lower:]'
  fi
}

function gpustack::util::is_darwin() {
  [[ "$(gpustack::util::get_os_name)" == "darwin" ]]
}

function gpustack::util::is_linux() {
  [[ "$(gpustack::util::get_os_name)" == "linux" ]]
}

function gpustack::util::check_python_version() {
  # check python is >=3.10 <=3.12
  if ! command -v python3 &> /dev/null; then
    gpustack::log::error "Python 3 is not installed. Please install Python 3.10 or later."
    exit 1
  fi
  PYTHON_VERSION=$(python3 --version | awk '{print $2}')
  if [[ ! "${PYTHON_VERSION}" =~ ^3\.(10|11|12)\. ]]; then
    gpustack::log::error "Python version ${PYTHON_VERSION} is not supported. Please use Python 3.10, 3.11, or 3.12."
    exit 1
  fi
}
