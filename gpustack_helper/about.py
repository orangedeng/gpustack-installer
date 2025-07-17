import logging
from PySide6.QtWidgets import QMessageBox, QApplication
from PySide6.QtCore import Qt

logger = logging.getLogger(__name__)


class About:
    gpustack_version: str
    gpustack_commit: str
    helper_version: str
    helper_commit: str
    prefix: str = "GPUStack\n"
    text: str
    msg: QMessageBox
    copy_button: QMessageBox.StandardButton

    def __init__(self):
        self.gpustack_commit = "unknown"
        self.gpustack_version = "unknown"
        self.helper_version = "unknown"
        self.helper_commit = "unknown"

        try:
            from gpustack_helper import (
                __version__,
                __commit__,
                __gpustack_commit__,
                __gpustack_version__,
            )

            self.helper_version = __version__
            self.helper_commit = __commit__
            self.gpustack_version = __gpustack_version__
            self.gpustack_commit = __gpustack_commit__

        except Exception as e:
            logger.error("Failed to get GPUStack version or commit", exc_info=e)
        gpustack_version = f"版本: {self.gpustack_version}({self.gpustack_commit})\n"
        helper_version = f"Helper: {self.helper_version}({self.helper_commit})"
        self.text = f"{gpustack_version}{helper_version}"

        self.msg = QMessageBox()
        self.msg.setWindowTitle("关于")
        self.msg.setIcon(QMessageBox.Icon.Information)
        self.msg.setText(f"{self.prefix}{self.text}")
        self.copy_button = self.msg.addButton("复制", QMessageBox.ButtonRole.AcceptRole)
        self.msg.addButton("确认", QMessageBox.ButtonRole.RejectRole)
        self.msg.setDefaultButton(self.copy_button)
        self.msg.setWindowFlags(
            self.msg.windowFlags() | Qt.WindowType.WindowStaysOnTopHint
        )

        def on_button_clicked(button):
            if button == self.copy_button:
                QApplication.clipboard().setText(self.text)

        self.msg.buttonClicked.connect(on_button_clicked)

    def show(self):
        self.msg.show()
        self.msg.raise_()
        self.msg.activateWindow()
