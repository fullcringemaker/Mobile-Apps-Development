import base64
import json
import os
import platform
import re
import time
from dataclasses import dataclass, field
from enum import Enum
from pathlib import Path
from typing import Optional

import typer
import libusb_package
from rich.console import Console
import usb.core
import usb.util
from usb.core import Device, Endpoint

PHOTO_DIR = Path(__file__).resolve().parent / "received_photos"
CHUNK_SIZE = 16384

if platform.system() == "Darwin" and "arm" in platform.platform():
    os.environ["DYLD_LIBRARY_PATH"] = "/opt/homebrew/lib"

class AppMode(Enum):
    Write = "write"
    Read = "read"

def is_accessory(device):
    return device.idVendor == 0x18D1 and device.idProduct in (0x2D00, 0x2D01)

def is_phone(device):
    return is_accessory(device) or device.idVendor == 0x22D9

@dataclass
class App:
    device: Optional[Device] = None
    console: Console = field(default_factory=Console)
    backend: object = field(default_factory=libusb_package.get_libusb1_backend)

    def select_device(self):
        if self.backend is None:
            raise ValueError("USB backend unavailable")
        lst = list(
            usb.core.find(find_all=True, backend=self.backend, custom_match=is_phone)
        )
        if not lst:
            self.console.print("[bold blue]Waiting for phone...")
            while not lst:
                lst = list(
                    usb.core.find(
                        find_all=True, backend=self.backend, custom_match=is_phone
                    )
                )
                time.sleep(1)

        if len(lst) > 1:
            raise ValueError("USB device selection failed")

        self.device = lst[0]

    def prepare_device(self):
        if is_accessory(self.device):
            return
        for command_name, command in [
            ("Verifying protocol", self.set_protocol),
            ("Sending accessory parameters", self.send_accessory_parameters),
            ("Triggering accessory mode", self.set_accessory_mode),
        ]:
            self.console.print(f"{command_name}......... ", end="")
            try:
                command()
            except Exception:
                self.console.print("[bold red]FAIL")
                raise
            else:
                self.console.print("[bold green]OK")

    def set_protocol(self):
        ret = self.device.ctrl_transfer(0xC0, 51, 0, 0, 2, timeout=3000)
        protocol = int.from_bytes(bytes(ret), "little")
        if len(ret) != 2 or protocol < 1:
            raise ValueError("The selected device does not support Android Open Accessory")
        return

    def send_accessory_parameters(self):
        def send_string(str_id, str_val):
            data = str_val.encode("utf-8") + b"\0"
            ret = self.device.ctrl_transfer(0x40, 52, 0, str_id, data, timeout=3000)
            if ret != len(data):
                raise ValueError("Received non-valid response")
            return

        send_string(0, "dvpashkevich")
        send_string(1, "PyAndroidCompanion")
        send_string(2, "A Python based Android accessory companion")
        send_string(3, "0.1.0")
        send_string(4, "https://github.com/alien-agent/USB-Communicator-Script")
        send_string(5, "0000-0000-0000")
        return

    def set_accessory_mode(self):
        ret = self.device.ctrl_transfer(0x40, 53, 0, 0, None, timeout=3000)
        if ret:
            raise ValueError("Failed to trigger accessory mode")
        usb.util.dispose_resources(self.device)
        self.device = None
        deadline = time.monotonic() + 30
        while time.monotonic() < deadline:
            dev = usb.core.find(custom_match=is_accessory, backend=self.backend)
            if dev is not None:
                self.device = dev
                return
            time.sleep(0.5)
        raise ValueError("Accessory not found")

    def endpoint(self, direction):
        try:
            cfg = self.device.get_active_configuration()
        except usb.core.USBError:
            self.device.set_configuration()
            cfg = self.device.get_active_configuration()
        intf = cfg[(0, 0)]
        usb.util.claim_interface(self.device, intf.bInterfaceNumber)
        endpoint: Endpoint = usb.util.find_descriptor(
            intf,
            custom_match=lambda e: usb.util.endpoint_direction(e.bEndpointAddress)
            == direction
            and usb.util.endpoint_type(e.bmAttributes) == usb.util.ENDPOINT_TYPE_BULK,
        )
        if endpoint is None:
            raise ValueError("USB endpoint not found")
        return endpoint

    def receive_message(self, data):
        message = json.loads(data)
        if not isinstance(message, dict) or not isinstance(message.get("data"), str):
            raise ValueError("Invalid received data")
        if message.get("type") == "text":
            self.console.print(message["data"], markup=False, highlight=False)
        elif message.get("type") == "photo":
            photo = base64.b64decode(message["data"], validate=True)
            if not photo:
                raise ValueError("Invalid received data")
            name = str(message.get("name", "photo.jpg")).replace("\\", "/").rsplit("/", 1)[-1]
            name = re.sub(r'[<>:"/\\|?*\x00-\x1f]', "_", name)[:160].strip(" .")
            PHOTO_DIR.mkdir(parents=True, exist_ok=True)
            path = PHOTO_DIR / f"{time.time_ns()}_{name or 'photo.jpg'}"
            with path.open("xb") as file:
                file.write(photo)
            self.console.print(f"Photo saved: {path}", markup=False, highlight=False)
        else:
            raise ValueError("Invalid received data")

    def send_message(self, endpoint, message):
        data = json.dumps(message, ensure_ascii=False).encode("utf-8")
        for offset in range(0, len(data), CHUNK_SIZE):
            chunk = data[offset:offset + CHUNK_SIZE]
            if endpoint.write(chunk, timeout=5000) != len(chunk):
                raise ValueError("Data transfer failed")
        if endpoint.write(b"\n", timeout=5000) != 1:
            raise ValueError("Data transfer failed")

    def accept_data(self):
        ep_in = self.endpoint(usb.util.ENDPOINT_IN)
        self.console.print("[bold blue]Accepting data...")
        pending = bytearray()
        while True:
            try:
                data = ep_in.read(size_or_buffer=CHUNK_SIZE, timeout=500)
            except usb.core.USBTimeoutError:
                continue
            search_start = len(pending)
            pending.extend(data)
            while True:
                end = pending.find(b"\n", search_start)
                if end < 0:
                    break
                try:
                    self.receive_message(pending[:end])
                except (OSError, ValueError) as error:
                    self.console.print(f"Receive error: {error}", markup=False)
                del pending[:end + 1]
                search_start = 0

    def write(self):
        ep_out = self.endpoint(usb.util.ENDPOINT_OUT)
        self.console.print('Photo: "C:\\path\\photo.jpg"', markup=False)
        while True:
            message = self.console.input("[bold blue]Write: ")
            if not message:
                continue
            photo_command = message == "/photo" or message.startswith("/photo ")
            name = message[6:] if photo_command else message
            path = Path(name.strip().strip("\"'"))
            photo_file = path.suffix.lower() in (".jpg", ".jpeg", ".png", ".webp", ".gif", ".bmp")
            if photo_command or photo_file:
                try:
                    if not photo_file:
                        raise ValueError("Invalid photo file")
                    path = path.expanduser()
                    photo = path.read_bytes()
                    if not photo:
                        raise ValueError("Invalid photo file")
                except (OSError, ValueError) as error:
                    self.console.print(f"Photo error: {error}", markup=False)
                    continue
                self.send_message(ep_out, {
                    "type": "photo", "name": path.name,
                    "data": base64.b64encode(photo).decode("ascii"),
                })
                self.console.print(f"Photo sent: {path.name}", markup=False)
            else:
                self.send_message(ep_out, {"type": "text", "data": message})

def main(mode: AppMode = AppMode.Read):
    app = App()
    try:
        app.select_device()
        app.prepare_device()
        if mode == AppMode.Write:
            app.write()
        else:
            app.accept_data()
    except (KeyboardInterrupt, EOFError):
        app.console.print("\nDisconnected.")
    except (usb.core.USBError, ValueError, UnicodeError, NotImplementedError) as e:
        app.console.print(f"USB error: {e}", markup=False)
        raise typer.Exit(code=1)
    finally:
        if app.device is not None:
            usb.util.dispose_resources(app.device)

if __name__ == "__main__":
    typer.run(main)


