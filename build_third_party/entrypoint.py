import sys
import re
import os
import certifi
import multiprocessing

if __name__ == "__main__":
    if os.getenv("SSL_CERT_FILE", None) is None:
        os.environ["SSL_CERT_FILE"] = certifi.where()
    multiprocessing.freeze_support()
from gpustack.main import main as gpustack
from vox_box.main import main as vox_box

if __name__ == "__main__":
    sys.argv[0] = re.sub(r"(-script\.pyw|\.exe)?$", "", sys.argv[0])
    binary_name = os.path.basename(
        sys.argv[0]
    )  # Ensure the script name is set correctly
    if binary_name == "vox-box":
        sys.exit(vox_box())
    else:
        sys.exit(gpustack())
