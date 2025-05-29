from PySide6.QtWidgets import QMenu
from PySide6.QtGui import QAction
def create_menu_action(name: str, menu: QMenu) -> QAction:
    """
    create a button under a menu 
    """
    action = QAction(name, menu)
    menu.addAction(action)
    return action
