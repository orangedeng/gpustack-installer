# Set error handling
$ErrorActionPreference = "Stop"
$DebugPreference = "Continue"
$VerbosePreference = "Continue"
Set-PSDebug -Trace 1   # 显示每一行执行

$ROOT_DIR = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent | Split-Path -Parent | Split-Path -Parent -Resolve

# Include the common functions
. "$ROOT_DIR/hack/lib/windows/init.ps1"

$BUILD_ROOT= "$ROOT_DIR/build_third_party"

function Download-UI {
    $defaultTag = "latest"
    $gpustackDir = Get-ChildItem -Path "$BUILD_ROOT\.venv\lib" -Directory -Recurse -Filter gpustack | Select-Object -First 1
    $uiPath = Join-Path $gpustackDir.FullName "ui"
    $tmpUIPath = Join-Path $uiPath "tmp"
    $tag = if ($GPUSTACK_VERSION) { $GPUSTACK_VERSION } else { $defaultTag }

    # 仅当 uiPath 不存在或为空时才下载
    if (Test-Path $uiPath -PathType Container) {
        $files = Get-ChildItem $uiPath -Force -ErrorAction SilentlyContinue
        if ($files | Where-Object { -not $_.PSIsContainer } | Measure-Object | Select-Object -ExpandProperty Count) {
            GPUStack.Log.Info "UI assets already exist in $uiPath, skipping download."
            return
        }
    }


    Remove-Item -Recurse -Force $uiPath -ErrorAction Ignore
    $null = New-Item -ItemType Directory -Path (Join-Path $tmpUIPath "ui") -Force

    GPUStack.Log.Info "downloading '$tag' UI assets"
    $url = "https://gpustack-ui-1303613262.cos.accelerate.myqcloud.com/releases/$tag.tar.gz"
    $tmpFile = Join-Path $tmpUIPath "ui.tar.gz"
    $downloaded = $false
    try {
        DownloadWithRetries -url $url -outFile $tmpFile -maxRetries 3
        & "$env:WINDIR/System32/tar" -xzf $tmpFile -C (Join-Path $tmpUIPath "ui")
        $downloaded = $true
    } catch {
        GPUStack.Log.Warn "failed to download '$tag' ui archive, fallback to '$defaultTag' ui archive"
        $url = "https://gpustack-ui-1303613262.cos.accelerate.myqcloud.com/releases/$defaultTag.tar.gz"
        try {
            DownloadWithRetries -url $url -outFile $tmpFile -maxRetries 3
            & "$env:WINDIR/System32/tar" -xzf $tmpFile -C (Join-Path $tmpUIPath "ui")
            $downloaded = $true
        } catch {
            GPUStack.Log.Fatal "failed to download '$defaultTag' ui archive"
        }
    }
    if ($downloaded) {
        Copy-Item -Path (Join-Path $tmpUIPath "ui/dist/*") -Destination $uiPath -Recurse -Force
        Remove-Item -Recurse -Force (Join-Path $tmpUIPath "ui") -ErrorAction Ignore
        Remove-Item -Recurse -Force $tmpUIPath -ErrorAction Ignore
        Set-Content -Path (Join-Path $ROOT_DIR ".gpustack-ui-downloaded") -Value ""
    }
}

function DownloadWithRetries {
    param (
        [string]$url,
        [string]$outFile,
        [int]$maxRetries = 3
    )

    for ($i = 1; $i -le $maxRetries; $i++) {
        try {
            GPUStack.Log.Info "Attempting to download from $url (Attempt $i of $maxRetries)"
            Invoke-WebRequest -Uri $url -OutFile $outFile -ErrorAction Stop
            return
        }
        catch {
            GPUStack.Log.Warn "Download attempt $i failed: $($_.Exception.Message)"
            if ($i -eq $maxRetries) {
                throw $_
            }
        }
    }
}

function Cleanup-UI {
    $marker = Join-Path $ROOT_DIR ".gpustack-ui-downloaded"
    if (-not (Test-Path $marker)) {
        GPUStack.Log.Info "UI assets not downloaded, skipping cleanup."
        return
    }
    $poetryEnvPath = poetry env info --path | Select-Object -First 1
    $gpustackDir = Get-ChildItem -Path "$poetryEnvPath\lib" -Directory -Recurse -Filter gpustack | Select-Object -First 1
    $uiPath = Join-Path $gpustackDir.FullName "ui"
    if (Test-Path $uiPath -PathType Container) {
        Remove-Item -Recurse -Force $uiPath -ErrorAction Ignore
    }
    Remove-Item $marker -ErrorAction Ignore
}

function Build {
    $VIRTUAL_ENV_DIR = "$BUILD_ROOT\.venv"
    python -m venv $VIRTUAL_ENV_DIR
    & "$VIRTUAL_ENV_DIR/Scripts/Activate.ps1"
    GPUStack.Log.Info "Activated virtual environment at $VIRTUAL_ENV_DIR"
    pip install pyinstaller==6.14.2
    $transformersVersion = "4.51.3"
    if ($null -ne $GPUSTACK_VERSION -and '' -ne $GPUSTACK_VERSION) {
        $ver = $GPUSTACK_VERSION.TrimStart('v')
        pip install "transformers==$transformersVersion" "gpustack[audio]==$ver"
    } else {
        pip install "transformers==$transformersVersion" "git+$GPUSTACK_REPO@$GPUSTACK_BRANCH#egg=gpustack[audio]"
    }
    $version = if($GPUSTACK_VERSION) {$GPUSTACK_VERSION} else {'latest'}
    GPUStack.Log.Info "Installed gpustack version $version"
    Download-UI
    pyinstaller -y ${BUILD_ROOT}\gpustack.spec
    if ($LASTEXITCODE -ne 0) {
        GPUStack.Log.Fatal "PyInstaller failed with exit code $LASTEXITCODE"
    }
    Cleanup-UI
    GPUStack.Log.Info "gpustack built successfully."
    deactivate
}

#
# main
#

GPUStack.Log.Info "+++ BUILD GPUSTACK +++"
try {
    Build
}
catch {
    GPUStack.Log.Fatal "failed to build: $($_.Exception.Message)"
}
GPUStack.Log.Info "--- BUIL GPUSTACK ---"
