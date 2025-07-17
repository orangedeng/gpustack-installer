import os
import sys
import shutil
import zipfile
from io import BytesIO
from pathlib import Path
import requests
from pathlib import Path
from gpustack_helper.defaults import get_dac_filename, dac_download_link

NSSM_VERSION = "nssm-2.24-101-g897c7ad"
OFFICIAL_NSSM_DOWNLOAD_URL = f"https://nssm.cc/ci/{NSSM_VERSION}.zip"
NSSM_DOWNLOAD_URL = os.getenv("NSSM_DOWNLOAD_URL", OFFICIAL_NSSM_DOWNLOAD_URL)

version = os.getenv('GIT_VERSION', '0.99.0')
app_name = 'GPUStack'

def download_dac(base_path: str) -> str:
    filename = get_dac_filename()
    download_link = dac_download_link()
    if download_link is None:
        raise ValueError(
            f"Could not find model with filename {filename} in the DAC repository."
        )
    local_path = Path(base_path) / filename
    if not local_path.exists():
        response = requests.get(download_link)

        if response.status_code != 200:
            raise ValueError(
                f"Could not download model. Received response code {response.status_code}"
            )
        local_path.write_bytes(response.content)
    return str(local_path)


def download_nssm(target_dir: str) -> None:
    """Download and extract NSSM to the specified target directory."""
    shutil.rmtree(os.path.join(target_dir, NSSM_VERSION), ignore_errors=True)

    response = requests.get(NSSM_DOWNLOAD_URL)
    if response.status_code != 200:
        raise Exception(f"Failed to download NSSM from {NSSM_DOWNLOAD_URL}")

    with zipfile.ZipFile(BytesIO(response.content)) as z:
        z.extractall(target_dir)

    print(f"NSSM has been downloaded and extracted to {target_dir}")

dac_path = download_dac('./build/cache')
datas = [
    ('./tray_icon.png', './'),
    (dac_path, "./"),
    ("./translations/*.qm", "./translations"),
    ('./dist/third_party', 'third_party'),
]


is_windows = sys.platform == 'win32'

if is_windows:
    datas += [
    (f'./build/{NSSM_VERSION}/win64/nssm.exe', './'),
    ]
    build_dir = os.path.join(os.getcwd(), 'build')
    os.makedirs(build_dir, exist_ok=True)
    # download nssm to ${pwd}/build dir
    download_nssm(build_dir)

app_name = 'gpustackhelper'

helper = Analysis(
    [os.path.join('gpustack_helper','main.py')],
    pathex=[],
    binaries=[],
    datas=datas,
    hiddenimports=[],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
    optimize=0,
)

helper_pyz = PYZ(helper.pure)

helper_exe = EXE(
    helper_pyz,
    helper.scripts,
    [],
    exclude_binaries=True,
    name=app_name,
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    console=False,
    disable_windowed_traceback=False,
    argv_emulation=not is_windows,
    target_arch=None,
    codesign_identity=os.getenv('CODESIGN_IDENTITY', None) if not is_windows else None,
    entitlements_file=None,
    icon=['GPUStack.ico'],
    contents_directory=f'{app_name.lower()}_internal',
)

coll = COLLECT(
    helper_exe,
    helper.binaries,
    helper.datas,
    strip=False,
    upx=True,
    upx_exclude=[],
    name='gpustackhelper',
)

if not is_windows:
    # 创建 .app 包
    app = BUNDLE(
        coll,  # 将 coll 放入 BUNDLE 中
        name='GPUStack.app',
        icon='./GPUStack.icns',  # 图标文件路径
        bundle_identifier='ai.gpustack.gpustack',  # 应用标识符
        info_plist={
            'CFBundleName': 'GPUStack',
            'CFBundleDisplayName': 'GPUStack',
            'CFBundleVersion': version,
            'CFBundleShortVersionString': version,
            'NSHumanReadableCopyright': 'Copyright © 2025 Seal, Inc.',
            'LSMinimumSystemVersion': '14.0',  # 最低系统要求
            'NSPrincipalClass': 'NSApplication',
            'NSAppleScriptEnabled': False,
            'LSUIElement': True,
        },
    )
