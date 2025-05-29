# gpustack-helper

## Introduction

gpustack-helper is a system tray tool for managing and controlling the GPUStack service on macOS. It supports starting, stopping, restarting, and monitoring the status of the service.

## Features

- One-click start/stop/restart of the GPUStack service
- Check service status and display it in the tray
- Open the web console
- Automatic configuration file synchronization

## Dependencies

- Python 3.10+
- PySide6

## Installation & Usage

1. Install dependencies:

   ```sh
   pip install poetry==1.8.3
   poetry install
   ```

2. Run the main program:

   ```sh
   python -m gpustackhelper.main
   ```

## Packaging

You can use PyInstaller for packaging. See `darwin.spec` and related scripts for details.

## License

Apache 2
