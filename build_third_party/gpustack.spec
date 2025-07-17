import os
import sys
import shutil
import re
import logging
import requests
from packaging.version import parse
from pathlib import Path
from typing import Dict, Tuple, Optional
from gpustack.worker.tools_manager import ToolsManager, BUILTIN_LLAMA_BOX_VERSION
from gpustack.utils.platform import system, arch, DeviceTypeEnum
from importlib.resources import files
from PyInstaller.utils.hooks import collect_all, collect_data_files

LLAMA_BOX = 'llama-box'
LLAMA_BOX_VERSION = os.getenv("LLAMA_BOX_VERSION", BUILTIN_LLAMA_BOX_VERSION)
LLAMA_BOX_DOWNLOAD_REPO = os.getenv("LLAMA_BOX_DOWNLOAD_REPO", f"gpustack/{LLAMA_BOX}")
PREFERRED_BASE_URL = os.getenv("PREFERRED_BASE_URL", None)
VERSION_URL_PREFIX = f"{LLAMA_BOX_DOWNLOAD_REPO}/releases/download/{LLAMA_BOX_VERSION}"
TARGET_PREFIX = f"dl-{LLAMA_BOX}-{system()}-{arch()}-"
TOOLKIT_NAME = os.getenv("TOOLKIT_NAME", None)
ALL_TOOLKIT_NAME = "__all__"  # Special value to indicate all toolkits

logger = logging.getLogger('tools')

def exe() -> str:
    return ".exe" if system() == "windows" else ""


def get_package_dir(package_name: str) -> str:
    paths = package_name.rsplit(".", 1)
    if len(paths) == 1:
        return str(files(package_name))
    package, subpackage = paths
    return str(files(package).joinpath(subpackage))


def get_toolkit_name(device: str) -> str:
    # Get the toolkit based on the device type.
    device_toolkit_mapper = {
        "cuda": DeviceTypeEnum.CUDA.value,
        "cann": DeviceTypeEnum.NPU.value,
        "metal": DeviceTypeEnum.MPS.value,
        "hip": DeviceTypeEnum.ROCM.value,
        "musa": DeviceTypeEnum.MUSA.value,
        "dtk": DeviceTypeEnum.DCU.value,
        "cpu": "",
    }

    if device in device_toolkit_mapper:
        return device_toolkit_mapper[device]
    else:
        return device


def split_filename(file_name: str) -> Tuple[str, str]:
    suffix = file_name.removeprefix(TARGET_PREFIX).split("-", 1)
    if len(suffix) < 2:
        device_name = suffix[0].removesuffix(".zip")
        version_suffix = ".zip"
    else:
        device_name, version_suffix = suffix[0], suffix[1]
    # e.g. get the toolkit name from mapping, metal -> mps, cuda -> cuda, etc.
    toolkit_name = get_toolkit_name(device_name)
    version_suffix = version_suffix.removesuffix(".zip")
    return toolkit_name, version_suffix


def verify_file_checksum(file_path: str, expected_checksum: str) -> bool:
    """Verify the checksum of a file against an expected value."""
    import hashlib

    sha256_hash = hashlib.sha256()
    with open(file_path, "rb") as f:
        for byte_block in iter(lambda: f.read(4096), b""):
            sha256_hash.update(byte_block)
    return sha256_hash.hexdigest() == expected_checksum


def split_checksum_line(line: str) -> Optional[Tuple[str, str, str]]:
    pair = re.split(r"\s+", line.strip(), 1)
    if len(pair) != 2:
        return None
    if not pair[1].startswith(TARGET_PREFIX):
        return None

    return pair[0], pair[1]


def download_checksum(manager: ToolsManager) -> Dict[str, Tuple[str, str, str]]:
    """
    return the directory for the llama-box files and their checksums.
    Will be filtered by version, os and arch.
    The key would be toolkit name and the value would be a tuple of
    (version_suffix, file_name, checksum).
    """
    checksum_filename = "sha256sum.txt"
    base_url = PREFERRED_BASE_URL or manager._download_base_url
    if base_url is None:
        manager._check_and_set_download_base_url()
        base_url = manager._download_base_url
    url_path = f"{base_url}/{VERSION_URL_PREFIX}/{checksum_filename}"
    # e.g. <device>: (<version>, <file_name>, <checksum>)
    files_checksum: Dict[str, Tuple[str, str, str]] = {}
    try:
        response = requests.get(url_path, timeout=10)
        if response.status_code != 200:
            raise RuntimeError(
                f"Failed to download checksum file from {url_path}. "
                f"Status code: {response.status_code}"
            )
        for line in response.text.splitlines():
            pair = split_checksum_line(line)
            if pair is None:
                continue
            toolkit, version_suffix = split_filename(pair[1])
            if toolkit in files_checksum:
                if version_suffix == "":
                    continue
                version, _, _ = files_checksum[toolkit]
                if parse(version_suffix) <= parse(version):
                    # Skip if the version is not newer than the existing one
                    continue
            # e.g. dl-llama-box-linux-amd64-cuda-12.4.zip
            files_checksum[toolkit] = (version_suffix, pair[1], pair[0])

    except Exception as e:
        raise RuntimeError(f"Failed to download checksum file: {e}")
    return files_checksum


def download_and_extract(
    manager: ToolsManager, file_path: Path, extract_dir: Path, checksum: str
) -> None:
    try:
        if not file_path.exists() or not verify_file_checksum(file_path, checksum):
            file_path.unlink(missing_ok=True)  # Remove if exists
            manager._download_file(
                f"{VERSION_URL_PREFIX}/{file_path.name}",
                file_path,
                base_url=PREFERRED_BASE_URL,
            )
        else:
            logger.info(f"Using cached file: {file_path.name}")
        if not verify_file_checksum(file_path, checksum):
            raise RuntimeError(f"Checksum verification failed for {file_path.name}")
        manager._extract_file(file_path, extract_dir)
    except Exception as e:
        raise RuntimeError(f"Failed to download or verify {file_path.name}: {e}")


def download_llama_box(manager: ToolsManager):
    if TOOLKIT_NAME is None:
        logger.info(
            "TOOLKIT_NAME environment variable is not set, skipping llama-box download."
        )
        return
    versioned_base = f"{LLAMA_BOX}-{LLAMA_BOX_VERSION}-{system()}-{arch()}"
    cache_dir = Path("./build/cache").resolve()
    os.makedirs(cache_dir, exist_ok=True)

    files_checksum = download_checksum(manager)
    if TOOLKIT_NAME != ALL_TOOLKIT_NAME and TOOLKIT_NAME not in files_checksum:
        raise ValueError(
            f"Required toolkit '{TOOLKIT_NAME}' not found in the checksum file."
        )
    for toolkit, (_, file_name, checksum) in files_checksum.items():
        if TOOLKIT_NAME != ALL_TOOLKIT_NAME and toolkit != TOOLKIT_NAME:
            continue

        versioned_dir = versioned_base + (f"-{toolkit}" if toolkit != "" else "")
        target_dir = manager.third_party_bin_path / LLAMA_BOX / versioned_dir
        if target_dir.exists():
            # only trust the downloaded file with verfied checksum
            logger.info(f"Removing existing directory: {target_dir}")
            shutil.rmtree(target_dir)
        os.makedirs(target_dir, exist_ok=True)

        file_path = cache_dir / file_name
        try:
            logger.info(f"Downloading {file_path.name} '{LLAMA_BOX_VERSION}'")
            download_and_extract(manager, file_path, target_dir, checksum)
            manager._update_versions_file(versioned_dir, LLAMA_BOX_VERSION)

        except Exception as e:
            raise RuntimeError(f"Failed to download or verify {file_name}: {e}")


def download():
    manager = ToolsManager()
    try:
        version_path = os.path.join(
            get_package_dir("gpustack.third_party.bin"), "versions.json"
        )
        if os.path.exists(version_path):
            os.remove(version_path)
        manager.download_fastfetch()
        manager.download_gguf_parser()
        download_llama_box(manager)
    except Exception as e:
        print(f"Error downloading tools: {e}")
        raise

paths_to_insert = [
    os.path.join(get_package_dir('vox_box'), 'third_party/CosyVoice'),
    os.path.join(get_package_dir('vox_box'), 'third_party/dia'),
    os.path.join(
        get_package_dir('vox_box'), 'third_party/CosyVoice/third_party/Matcha-TTS'
    ),
]

for path in paths_to_insert:
    sys.path.insert(0, path)


os.makedirs('./build/cache', exist_ok=True)

datas = [
    *collect_data_files('inflect', include_py_files=True),
    *collect_data_files('typeguard', include_py_files=True),
    *collect_data_files('tn', include_py_files=True),
    *collect_data_files('itn', include_py_files=True),
    *collect_data_files('audiotools'),
    (os.path.join(get_package_dir('whisper'), 'assets'), './whisper/assets'),
    (
        os.path.join(get_package_dir('vox_box.backends.tts'), 'cosyvoice_spk2info.pt'),
        './vox_box/backends/tts/',
    ),
    (get_package_dir('gpustack.migrations'), './gpustack/migrations'),
    (get_package_dir('gpustack.ui'), './gpustack/ui'),
    (get_package_dir('gpustack.assets'), './gpustack/assets'),
    (
        os.path.join(get_package_dir('gpustack'), 'third_party/bin/fastfetch'),
        './gpustack/third_party/bin/fastfetch',
    ),
    (
        os.path.join(get_package_dir('gpustack'), 'third_party/bin/gguf-parser'),
        './gpustack/third_party/bin/gguf-parser',
    ),
    (
        os.path.join(
            get_package_dir('gpustack'),
            f'third_party/bin/llama-box/llama-box-{BUILTIN_LLAMA_BOX_VERSION}-*',
        ),
        './gpustack/third_party/bin/llama-box',
    ),
    (
        os.path.join(
            get_package_dir('gpustack'),
            'third_party/bin/versions.json',
        ),
        './gpustack/third_party/bin',
    ),
    (
        os.path.join(get_package_dir('gpustack.detectors.fastfetch'), '*.jsonc'),
        './gpustack/detectors/fastfetch/',
    ),
]

download()
binaries = []
hiddenimports = []

for pkg in [
    'aiosqlite',
    'asyncmy',
    'asyncpg',
    'cosyvoice',
    'matcha',
    'dia',
    'dac',
    'transformers',
]:
    pkg_datas = collect_all(pkg)
    datas += pkg_datas[0]
    binaries += pkg_datas[1]
    hiddenimports += pkg_datas[2]


is_windows = sys.platform == 'win32'

if not is_windows:
    if os.getenv('INSTALL_PREFIX', None) is None:
        binaries += [
            (f'{os.getcwd()}/openfst/build/lib/*', './'),
        ]

    hiddenimports += [
        'tn', 'itn', '_pywrapfst'
    ]
    pkg_datas = collect_all('pynini')
    datas += pkg_datas[0]
    binaries += pkg_datas[1]
    hiddenimports += pkg_datas[2]

gpustack = Analysis(
    ['entrypoint.py'],
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
    name='gpustack',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    console=is_windows,
    disable_windowed_traceback=False,
    argv_emulation=not is_windows,
    target_arch=None,
    codesign_identity= os.getenv('CODESIGN_IDENTITY', None) if not is_windows else None,
    entitlements_file=None,
    icon=[os.path.abspath(os.path.join(os.getcwd(),'GPUStack.ico'))] if is_windows else None,
    contents_directory='third_party_internal',
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
    console=is_windows,
    disable_windowed_traceback=False,
    argv_emulation=not is_windows,
    target_arch=None,
    codesign_identity= os.getenv('CODESIGN_IDENTITY', None) if not is_windows else None,
    entitlements_file=None,
    icon=[os.path.abspath(os.path.join(os.getcwd(),'GPUStack.ico'))] if is_windows else None,
    contents_directory='third_party_internal',
)

coll = COLLECT(
    gpustack_exe,
    vox_box_exe,
    gpustack.binaries,
    gpustack.datas,
    strip=False,
    upx=True,
    upx_exclude=[],
    name='third_party',
)
