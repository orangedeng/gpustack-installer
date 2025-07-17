# Define the function to get version variables
function Get-GPUStackVersionVar {
    # Get the build date
    $BUILD_DATE = Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ'

    # Initialize other variables
    $GIT_TREE_STATE = "unknown"
    $GIT_COMMIT = "unknown"
    $GIT_VERSION = "unknown"

    # Check if the source was exported through git archive
    if ('%$Format:%' -eq '%') {
        $GIT_TREE_STATE = "archive"
        $GIT_COMMIT = '$Format:%H$'

        # Parse the version from '$Format:%D$'
        if ('%$Format:%D$' -match 'tag:\s+(v[^ ,]+)') {
            $GIT_VERSION = $matches[1]
        }
        else {
            $GIT_VERSION = $GIT_COMMIT.Substring(0, 7)
        }

        # Respect specified version
        if ($env:VERSION) {
            $GIT_VERSION = $env:VERSION
        }
        return
    }

    # Return if git client is not found
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        $GIT_VERSION = if ($env:VERSION) { $env:VERSION } else { $GIT_VERSION }
        return
    }

    # Find git info via git client
    $GIT_COMMIT = git rev-parse "HEAD^{commit}" 2>$null
    if ($LASTEXITCODE -eq 0) {
        # Check if the tree is clean or dirty
        $gitStatus = (git status --porcelain 2>$null)
        if ($gitStatus) {
            $GIT_TREE_STATE = "dirty"
        }
        else {
            $GIT_TREE_STATE = "clean"
        }

        # Get the version from HEAD
        $GIT_VERSION = git rev-parse --abbrev-ref HEAD 2>$null
        if ($LASTEXITCODE -eq 0) {
            # Check if HEAD is tagged
            $gitTag = git tag -l --contains HEAD 2>$null | Select-Object -First 1
            if (-not [string]::IsNullOrEmpty($gitTag)) {
                $GIT_VERSION = $gitTag
            }
        }

        # Set version to 'v0.0.0' if the tree is dirty or version format does not match
        if ($GIT_TREE_STATE -eq "dirty" -or -not ($GIT_VERSION -match '^v([0-9]+)\.([0-9]+)\.([0-9]+)$')) {
            $GIT_VERSION = "v0.0.0"
        }

        # Respect specified version
        if ($env:VERSION) {
            $GIT_VERSION = $env:VERSION
        }
    }

    $global:BUILD_DATE = $BUILD_DATE
    $global:GIT_TREE_STATE = $GIT_TREE_STATE
    $global:GIT_COMMIT = $GIT_COMMIT
    $global:GIT_VERSION = $GIT_VERSION

    # If GIT_VERSION is v0.0.0, try to increment patch and append GITHUB_RUN_NUMBER
    if ($GIT_VERSION -eq "v0.0.0") {
        try {
            $LAST_TAG = git describe --tags --abbrev=0 HEAD^ 2>$null
        } catch {
            $LAST_TAG = "v0.0.0"
        }

        if (-not $LAST_TAG) {
            $LAST_TAG = "v0.0.0"
        }
        $GITHUB_RUN_NUMBER = $env:GITHUB_RUN_NUMBER
        if (-not $GITHUB_RUN_NUMBER) { $GITHUB_RUN_NUMBER = "99" }
        if ($LAST_TAG -match '^v([0-9]+)\.([0-9]+)\.([0-9]+)$') {
            $major = $matches[1]
            $minor = $matches[2]
            $patch_base = [int]$matches[3]
            $patch_mod = [int]$GITHUB_RUN_NUMBER % 100
            $new_patch = $patch_base + $patch_mod
            if ($new_patch -eq $patch_base) {
                $new_patch = $patch_base + 100
            }
            $GIT_VERSION = "v$major.$minor.$new_patch"
        } else {
            # If no tag, patch=1+mod
            $patch_mod = [int]$GITHUB_RUN_NUMBER % 100
            $patch = 1 + $patch_mod
            $GIT_VERSION = "v0.0.$patch"
        }
        $global:GIT_VERSION = $GIT_VERSION
        $global:LAST_TAG = $LAST_TAG
    }
}

function Get-GPUStackToolkitVersion{
    $GPUSTACK_REPO= "https://github.com/gpustack/gpustack.git"
    if ($env:GPUSTACK_REPO) {
        $GPUSTACK_REPO = $env:GPUSTACK_REPO
    }
    $GPUSTACK_BRANCH = 'main'
    if ($env:GPUSTACK_BRANCH) {
        $GPUSTACK_BRANCH = $env:GPUSTACK_BRANCH
    }
    $GPUSTACK_VERSION = $env:GPUSTACK_VERSION
    if ( $global:LAST_TAG -eq $null -and $GPUSTACK_VERSION -eq $null) {
        if ($global:GIT_VERSION -match '^v([0-9]+)\.([0-9]+)\.([0-9]+)$') {
            $major = $matches[1]
            $minor = $matches[2]
            $patch = $matches[3]
            if ($major -ne 0 -and $minor -ne 0 -and $patch.Length -ge 4) {
                $patch_head = $patch.Substring(0, $patch.Length - 3)
                $GPUSTACK_VERSION = "v$major.$minor.$patch_head"
            }
        } 
    }
    $global:GPUSTACK_REPO = $GPUSTACK_REPO
    $global:GPUSTACK_BRANCH = $GPUSTACK_BRANCH
    $global:GPUSTACK_VERSION = $GPUSTACK_VERSION
    
    $VOX_BOX_REPO="https://github.com/gpustack/vox-box.git"
    if ($env:VOX_BOX_REPO) {
        $VOX_BOX_REPO = $env:VOX_BOX_REPO
    }
    $global:VOX_BOX_REPO = $VOX_BOX_REPO
    $VOX_BOX_VERSION="v0.0.18"
    if ($env:VOX_BOX_VERSION) {
        $VOX_BOX_VERSION = $env:VOX_BOX_VERSION
    }
    $global:VOX_BOX_VERSION = $VOX_BOX_VERSION

    if ($GPUSTACK_VERSION -ne $null -and $GPUSTACK_VERSION -ne "") {
        $commit_line = git ls-remote $GPUSTACK_REPO $GPUSTACK_VERSION 2>$null | Select-Object -First 1
    } else{
        $commit_line = git ls-remote $GPUSTACK_REPO $GPUSTACK_BRANCH 2>$null | Select-Object -First 1
    }
    if ($commit_line) {
        $global:GPUSTACK_COMMIT = $commit_line.Split()[0].Substring(0,7)
    } else {
        $global:GPUSTACK_COMMIT = "unknown"
    }
}
