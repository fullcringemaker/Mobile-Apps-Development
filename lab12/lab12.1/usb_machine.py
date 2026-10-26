import os
import platform
import time
from dataclasses import dataclass, field
from enum import Enum
from typing import Optional
import codecs

import typer
from rich.console import Console
import usb.core
import usb.util
import usb.backend.libusb1
from usb.core import Device, Endpoint

if platform.system() == "Darwin" and "arm" in platform.platform():
    os.environ["DYLD_LIBRARY_PATH"] = "/opt/homebrew/lib"

class AppMode(Enum):
    Write = "write"
    Read = "read"

def find_backend():
    if platform.system() == "Windows":
        import libusb_package

        return libusb_package.get_libusb1_backend()
    return usb.backend.libusb1.get_backend()

def is_accessory(device):
    return device.idVendor == 0x18D1 and device.idProduct in (0x2D00, 0x2D01)


def is_phone(device):
    return is_accessory(device) or (
        device.idVendor == 0x22D9 and device.idProduct in (0x2765, 0x2769)
    )

@dataclass
class App:
    device: Optional[Device] = None
    console: Console = field(default_factory=Console)
    backend: object = field(default_factory=find_backend)

    def select_device(self):
        if self.backend is None:
            raise ValueError("libusb is unavailable. Install requirements.txt first.")
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
            raise ValueError(
                "More than one supported phone is connected. Leave only the phone "
                "used for this laboratory connected."
            )

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
        raise ValueError("Accessory not found. Check its driver and restart the command.")

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
            raise ValueError("Accessory bulk endpoint was not found")
        return endpoint

    def accept_data(self):
        ep_in = self.endpoint(usb.util.ENDPOINT_IN)
        self.console.print("[bold blue]Accepting data...")
        decoder = codecs.getincrementaldecoder("utf-8")()
        pending = ""
        while True:
            try:
                data = ep_in.read(size_or_buffer=16384, timeout=500)
            except usb.core.USBTimeoutError:
                if pending:
                    self.console.print(pending, markup=False, highlight=False)
                    pending = ""
                continue
            pending += decoder.decode(bytes(data))
            while "\n" in pending:
                message, pending = pending.split("\n", 1)
                self.console.print(message, markup=False, highlight=False)

    def write(self):
        ep_out = self.endpoint(usb.util.ENDPOINT_OUT)
        while True:
            message = self.console.input("[bold blue]Write: ")
            if not message:
                continue
            data = (message + "\n").encode("utf-8")
            if ep_out.write(data, timeout=5000) != len(data):
                raise ValueError("The message was only partially sent")

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
        app.console.print(
            "On Windows, check the selected phone/accessory interface in Zadig. "
            "After switching to accessory mode its USB ID changes."
        )
        if platform.system() == "Windows":
            if getattr(e, "errno", None) == 13:
                app.console.print(
                    "Close Android Studio and stop ADB (adb kill-server), "
                    "then retry before reinstalling any driver."
                )
            elif isinstance(e, NotImplementedError):
                app.console.print(
                    "Install WinUSB for Android Accessory Interface (Interface 0), "
                    "USB ID 18D1:2D00 or 18D1:2D01. Keep the ADB interface unchanged."
                )
        raise typer.Exit(code=1)
    finally:
        if app.device is not None:
            usb.util.dispose_resources(app.device)

if __name__ == "__main__":
    typer.run(main)


