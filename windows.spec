# -*- mode: python ; coding: utf-8 -*-
import os
from PyInstaller.utils.hooks import collect_all
from gpustack_helper.tools import download, get_package_dir
from gpustack_helper.download_nssm import download_nssm, NSSM_VERSION

app_name = 'GPUStack'

datas = [
  (get_package_dir('gpustack.migrations'), './gpustack/migrations'),
  (get_package_dir('gpustack.ui'),'./gpustack/ui'),
  (get_package_dir('gpustack.assets'),'./gpustack/assets'),
  (get_package_dir('gpustack.third_party'),'./gpustack/third_party'),
  (os.path.join(get_package_dir('gpustack.detectors.fastfetch'),'*.jsonc'), './gpustack/detectors/fastfetch/'),
  ('./tray_icon.png', './'),
  (f'./build/{NSSM_VERSION}/win64/nssm.exe', './'),
]

# download nssm to ${pwd}/build dir
download_nssm(os.path.join(os.getcwd(), 'build'))
download()

binaries = []
hiddenimports = []
tmp_ret = collect_all('aiosqlite')
datas += tmp_ret[0]; binaries += tmp_ret[1]; hiddenimports += tmp_ret[2]


helper = Analysis(
    ['gpustack_helper\\main.py'],
    pathex=[],
    binaries=binaries,
    datas=datas,
    hiddenimports=hiddenimports,
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
    name=f'{app_name}helper'.lower(),
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    console=True,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
    icon=['GPUStack.ico'],
)



gpustack = Analysis(
    ['gpustack_helper\\binary_entrypoint.py'],
    pathex=[],
    binaries=binaries,
    datas=datas,
    hiddenimports=hiddenimports,
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
    optimize=0,
)
gpustack_pyz = PYZ(gpustack.pure)

gpustack_exe = EXE(
    gpustack_pyz,
    gpustack.scripts,
    [],
    exclude_binaries=True,
    name=f'{app_name}'.lower(),
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    console=True,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
    icon=['GPUStack.ico'],
)

vox_box_exe = EXE(
    gpustack_pyz,
    gpustack.scripts,
    [],
    exclude_binaries=True,
    name='vox-box',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    console=True,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
    icon=['GPUStack.ico'],
)

coll = COLLECT(
    helper_exe,
    helper.binaries,
    helper.datas,
    gpustack_exe,
    vox_box_exe,
    gpustack.binaries,
    gpustack.datas,
    strip=False,
    upx=True,
    upx_exclude=[],
    name='main',
)
