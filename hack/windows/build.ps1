# Set error handling
$ErrorActionPreference = "Stop"
$DebugPreference = "Continue"
$VerbosePreference = "Continue"
Set-PSDebug -Trace 1   # 显示每一行执行

$ROOT_DIR = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent | Split-Path -Parent | Split-Path -Parent -Resolve

# Include the common functions
. "$ROOT_DIR/hack/lib/windows/init.ps1"

function Build {
    $distDir = Join-Path -Path $ROOT_DIR -ChildPath "dist/gpustackhelper"
    Remove-Item -Path $distDir -Recurse -Force -ErrorAction SilentlyContinue

    $env:GIT_VERSION = $GIT_VERSION; poetry run pyinstaller helper.spec -y
    if ($LASTEXITCODE -ne 0) {
        GPUStack.Log.Fatal "failed to run pyinstaller."
    }
}

function Install-Dependency {
    & "$ROOT_DIR\hack\windows\install.ps1"
}

function Build-I18n {
    $tsPath = Join-Path $ROOT_DIR "translations/zh_CN.ts"
    $qmPath = Join-Path $ROOT_DIR "translations/zh_CN.qm"
    # 1. do release only
    poetry run pyside6-lrelease $tsPath -qm $qmPath

    # Compile English translations
    $enTsPath = Join-Path $ROOT_DIR "translations/en_US.ts"
    $enQmPath = Join-Path $ROOT_DIR "translations/en_US.qm"
    poetry run pyside6-lrelease $enTsPath -qm $enQmPath
}

#
# main
#

GPUStack.Log.Info "+++ BUILD +++"
try {
    Install-Dependency
    Build-I18n
    Build
}
catch {
    GPUStack.Log.Fatal "failed to build: $($_.Exception.Message)"
}
GPUStack.Log.Info "--- BUILD ---"
