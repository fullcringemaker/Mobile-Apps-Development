import os
import platform
import time
from dataclasses import dataclass, field
from threading import Event, Thread
from typing import Optional

import typer
import libusb_package
from rich.console import Console
import usb.core
import usb.util
from usb.core import Device, Endpoint

CHUNK_SIZE = 16384

if platform.system() == "Darwin" and "arm" in platform.platform():
    os.environ["DYLD_LIBRARY_PATH"] = "/opt/homebrew/lib"

def is_accessory(device):
    return device.idVendor == 0x18D1 and device.idProduct in (0x2D00, 0x2D01)

def is_phone(device):
    return is_accessory(device) or device.idVendor == 0x22D9

@dataclass
class App:
    device: Optional[Device] = None
    console: Console = field(default_factory=Console)
    backend: object = field(default_factory=libusb_package.get_libusb1_backend)
    stopped: Event = field(default_factory=Event)

    def select_device(self):
        if self.backend is None:
            raise ValueError("Backend error")
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
            raise ValueError("Device error")

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
            raise ValueError("Protocol error")
        return

    def send_accessory_parameters(self):
        def send_string(str_id, str_val):
            data = str_val.encode("utf-8") + b"\0"
            ret = self.device.ctrl_transfer(0x40, 52, 0, str_id, data, timeout=3000)
            if ret != len(data):
                raise ValueError("USB error")
            return

        send_string(0, "dvpashkevich")
        send_string(1, "PyAndroidCompanionServer")
        send_string(2, "A Python based Android accessory companion")
        send_string(3, "0.1.0")
        send_string(4, "https://github.com/alien-agent/USB-Communicator-Script")
        send_string(5, "0000-0000-0000")
        return

    def set_accessory_mode(self):
        ret = self.device.ctrl_transfer(0x40, 53, 0, 0, None, timeout=3000)
        if ret:
            raise ValueError("Accessory error")
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
            raise ValueError("Endpoint error")
        return endpoint

    def accept_data(self, endpoint):
        pending = bytearray()
        try:
            while not self.stopped.is_set():
                try:
                    data = endpoint.read(size_or_buffer=CHUNK_SIZE, timeout=500)
                except usb.core.USBTimeoutError:
                    continue
                pending.extend(data)
                while b"\n" in pending:
                    message, _, pending = pending.partition(b"\n")
                    text = message.decode("utf-8")
                    self.console.print(f"\nRead: {text}\nWrite: ", end="", markup=False, highlight=False)
        except (OSError, ValueError):
            if not self.stopped.is_set():
                self.console.print("Read error")
            self.stopped.set()

    def send_text(self, endpoint, text):
        for data in (text.encode("utf-8"), b"\n"):
            offset = 0
            while offset < len(data) and not self.stopped.is_set():
                try:
                    count = endpoint.write(data[offset:offset + CHUNK_SIZE], timeout=500)
                except usb.core.USBTimeoutError:
                    continue
                if not count:
                    raise ValueError("Send error")
                offset += count

    def write(self, endpoint):
        while not self.stopped.is_set():
            text = self.console.input("[bold blue]Write: ")
            if text and not self.stopped.is_set():
                self.send_text(endpoint, text)

    def run(self):
        ep_in = self.endpoint(usb.util.ENDPOINT_IN)
        ep_out = self.endpoint(usb.util.ENDPOINT_OUT)
        self.console.print("[bold blue]Accepting data...")
        reader = Thread(target=self.accept_data, args=(ep_in,), daemon=True)
        reader.start()
        try:
            self.write(ep_out)
        finally:
            self.stopped.set()
            reader.join(timeout=1)

def main():
    app = App()
    try:
        app.select_device()
        app.prepare_device()
        app.run()
    except (KeyboardInterrupt, EOFError):
        app.console.print("\nDisconnected.")
    except (OSError, ValueError, NotImplementedError):
        app.console.print("USB error")
        raise typer.Exit(code=1)
    finally:
        if app.device is not None:
            usb.util.dispose_resources(app.device)

if __name__ == "__main__":
    typer.run(main)
