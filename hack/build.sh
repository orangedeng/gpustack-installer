#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "${ROOT_DIR}/hack/lib/init.sh"


function build() {
  GIT_VERSION=${GIT_VERSION} poetry run pyinstaller helper.spec -y
}

function prepare_dependencies() {
  POETRY_ONLY=true bash "${ROOT_DIR}/hack/install.sh"
}

function build_i18n() {
  # shellcheck disable=SC2086
  poetry run pyside6-lupdate ${ROOT_DIR}/gpustack_helper/*.py "${ROOT_DIR}/gpustack_helper/status.py" ${ROOT_DIR}/gpustack_helper/quickconfig/*.py ${ROOT_DIR}/gpustack_helper/services/*.py -ts "${ROOT_DIR}/translations/zh_CN.ts" -ts "${ROOT_DIR}/translations/en_US.ts" -no-obsolete -locations none
  # 检查未翻译条目
  if grep 'type="unfinished"' "${ROOT_DIR}/translations/zh_CN.ts" > /dev/null; then
    gpustack::log::error "zh_CN 存在未翻译的条目，请先完成翻译！"
    grep 'type="unfinished"' "${ROOT_DIR}/translations/zh_CN.ts"
    exit 1
  fi
  if grep 'type="unfinished"' "${ROOT_DIR}/translations/en_US.ts" > /dev/null; then
    gpustack::log::error "en_US 存在未翻译的条目，请先完成翻译！"
    grep 'type="unfinished"' "${ROOT_DIR}/translations/en_US.ts"
    exit 1
  fi
  # 检查 ts 文件是否有未提交的更改
  if [[ -n $(git status --porcelain --untracked-files=no translations/zh_CN.ts) ]]; then
    gpustack::log::error "translations/zh_CN.ts 有未提交的更改，请先提交后再生成 qm 文件！"
    git status --short "${ROOT_DIR}/translations/zh_CN.ts"
    exit 1
  fi
  poetry run pyside6-lrelease "${ROOT_DIR}/translations/zh_CN.ts" -qm "${ROOT_DIR}/translations/zh_CN.qm"
  poetry run pyside6-lrelease "${ROOT_DIR}/translations/en_US.ts" -qm "${ROOT_DIR}/translations/en_US.qm"
}

#
# main
#

gpustack::log::info "+++ BUILD +++"
prepare_dependencies
build_i18n
build
gpustack::log::info "--- BUILD ---"
