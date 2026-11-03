#!/usr/bin/env python3
"""
Bluetooth Messenger - Linux PC side script for communicating with Android app
Supports bidirectional communication with Android device via Bluetooth RFCOMM
"""

try:
    import bluetooth
except ImportError:
    bluetooth = None
import sys
import time
import threading
import argparse
import queue
from collections import deque

SERVICE_UUID = "00001101-0000-1000-8000-00805F9B34FB"  
SERVICE_NAME = "Bluetooth Messenger"

class AndroidBluetoothMessenger:
    """Handles Bluetooth communication with Android device"""
    
    def __init__(self):
        self.client_sock = None
        self.server_sock = None
        self.running = False
        self.receive_thread = None
        self.serial_port = None
        self.receive_buffer = bytearray()
        self.pending_messages = deque()

    def open_serial(self, port):
        """Use a Windows incoming Bluetooth SPP COM port (not a USB cable)."""
        try:
            import serial
            self.serial_port = serial.Serial(port, 115200, timeout=0.2, write_timeout=5)
            print(f"Bluetooth COM port {port} opened. Waiting for Android messages...", flush=True)
            print("An open COM port does not yet prove a Bluetooth connection.", flush=True)
            return True
        except (ImportError, OSError) as exc:
            print(f"Cannot open {port}: {exc}")
            return False
        
    def start_server(self, port=1):
        """Start Bluetooth RFCOMM server and wait for Android connection"""
        try:
            self.server_sock = bluetooth.BluetoothSocket(bluetooth.RFCOMM)
            self.server_sock.bind(("", port))
            self.server_sock.listen(1)
            
            try:
                bluetooth.advertise_service(
                    self.server_sock,
                    SERVICE_NAME,
                    service_id=SERVICE_UUID,
                    service_classes=[SERVICE_UUID, bluetooth.SERIAL_PORT_CLASS],
                    profiles=[bluetooth.SERIAL_PORT_PROFILE]
                )
                print("SDP service advertisement registered")
            except Exception as sdp_err:
                print(f"SDP advertisement failed: {sdp_err}")
                print("UUID connection requires SDP. Check the Bluetooth service setup.")
            
            print(f"\nBluetooth server started on RFCOMM channel {port}")
            print(f"Service UUID: {SERVICE_UUID}")
            print("Waiting for Android device to connect...")
            print("\nMake sure Bluetooth is enabled on both devices and they are paired!")
            print("")
            
            self.client_sock, client_info = self.server_sock.accept()
            print(f"Connected to: {client_info}")
            
            return True
            
        except Exception as e:
            print(f"Error starting Bluetooth server: {e}")
            return False
    
    def connect_to_device(self, device_address, port=1):
        """Connect to Android device as client (alternative method)"""
        try:
            print(f"Connecting to {device_address} on port {port}...")
            self.client_sock = bluetooth.BluetoothSocket(bluetooth.RFCOMM)
            self.client_sock.connect((device_address, port))
            print(f"Connected to: {device_address}")
            return True
        except Exception as e:
            print(f"Error connecting to device: {e}")
            return False
    
    def send_message(self, message):
        """Send a message to the Android device"""
        if self.client_sock is None and self.serial_port is None:
            print("Not connected to device")
            return False
        
        try:
            data = (message + "\n").encode('utf-8')
            if self.serial_port is not None:
                if self.serial_port.write(data) != len(data):
                    raise OSError("Incomplete serial write")
            else:
                self.client_sock.sendall(data)
            print(f"[PC]: {message}", flush=True)
            return True
        except Exception as e:
            print(f"Error sending message: {e}")
            return False
    
    def receive_message(self):
        """Receive a message from the Android device"""
        if self.client_sock is None and self.serial_port is None:
            return None
        
        try:
            if self.pending_messages:
                return self.pending_messages.popleft()
            if self.serial_port is not None:
                data = self.serial_port.read(max(1, min(self.serial_port.in_waiting, 4096)))
                if not data:
                    return None  # Serial timeout is not a disconnection.
            else:
                data = self.client_sock.recv(1024)
            if data:
                self.receive_buffer.extend(data)
                while b'\n' in self.receive_buffer:
                    line, _, remainder = self.receive_buffer.partition(b'\n')
                    self.receive_buffer = bytearray(remainder)
                    self.pending_messages.append(line.rstrip(b'\r').decode('utf-8'))
                if self.pending_messages:
                    return self.pending_messages.popleft()
            else:
                
                raise ConnectionError("Connection closed by remote device")
        except Exception as e:
            if "timed out" not in str(e).lower():
                raise
        return None
    
    def start_receive_loop(self):
        """Start background thread to receive messages"""
        self.running = True
        self.receive_thread = threading.Thread(target=self._receive_loop, daemon=True)
        self.receive_thread.start()
    
    def _receive_loop(self):
        """Background thread loop for receiving messages"""
        print("Listening for messages from Android device...")
        print("")
        disconnected_shown = False
        
        
        if self.client_sock:
            self.client_sock.settimeout(1.0)
        
        while self.running:
            try:
                message = self.receive_message()
                if message:
                    print(f"\n[Android]: {message}")
                    print(">>> ", end='', flush=True)
                    disconnected_shown = False
            except ConnectionError as e:
                if not disconnected_shown:
                    print(f"\n✗ Device disconnected: {e}")
                    print("\nThis usually means:")
                    print("  1. The Android app (Bluetooth Messenger) was closed")
                    print("  2. Bluetooth was turned off on the device")
                    print("  3. The device moved out of range")
                    print("")
                    disconnected_shown = True
                self.running = False
                break
            except Exception as e:
                if not disconnected_shown:
                    print(f"\n✗ Error in receive loop: {e}")
                    disconnected_shown = True
                self.running = False
                break
    
    def stop(self):
        """Stop receiving and disconnect"""
        self.running = False
        if self.receive_thread:
            self.receive_thread.join(timeout=2)
        
        if self.client_sock:
            try:
                self.client_sock.close()
            except:
                pass
            self.client_sock = None
        
        if self.server_sock:
            try:
                self.server_sock.close()
            except:
                pass
            self.server_sock = None

        if self.serial_port is not None:
            self.serial_port.close()
            self.serial_port = None
        
        print("Disconnected")
    
    def interactive_mode(self):
        """Run in interactive mode with continuous communication"""
        print("\n=== Bluetooth Messenger Interactive Mode ===")
        print("Type messages and press Enter to send")
        print("Press Ctrl+C to exit\n")
        
        self.start_receive_loop()
        lines = queue.Queue()

        def read_input():
            while True:
                try:
                    line = input()
                except EOFError:
                    lines.put(None)
                    return
                lines.put(line)
        threading.Thread(target=read_input, daemon=True).start()
        
        try:
            while self.running:
                
                try:
                    message = lines.get(timeout=0.1)
                except queue.Empty:
                    continue
                if message is None:
                    break
                if message.strip() and not self.send_message(message):
                    print("Failed to send message")
                    break
        except KeyboardInterrupt:
            print("\nExiting...")
        finally:
            self.stop()

def scan_devices():
    """Scan for nearby Bluetooth devices"""
    print("Scanning for Bluetooth devices...")
    print("(This may take 10-15 seconds)\n")
    
    try:
        nearby_devices = bluetooth.discover_devices(duration=10, lookup_names=True)
        
        if not nearby_devices:
            print("No devices found.")
            return
        
        print(f"Found {len(nearby_devices)} device(s):\n")
        for addr, name in nearby_devices:
            print(f"  {name}")
            print(f"    Address: {addr}\n")
    except Exception as e:
        print(f"Error scanning for devices: {e}")

def main():
    parser = argparse.ArgumentParser(
        description='Bluetooth Messenger - Android / PC text messages over Bluetooth',
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    
    parser.add_argument('--scan', action='store_true', help='Scan for nearby Bluetooth devices')
    parser.add_argument('--connect', '-c', type=str, metavar='ADDRESS', help='Connect to device at specified MAC address (client mode)')
    parser.add_argument('--send', '-s', type=str, help='Send a message to the Android device')
    parser.add_argument('--port', '-p', type=int, default=1, help='RFCOMM port number (default: 1)')
    parser.add_argument('--interactive', '-i', action='store_true', help='Interactive mode (default if no args)')
    parser.add_argument('--serial', metavar='COM', help='Windows incoming Bluetooth COM port, e.g. COM3')
    parser.add_argument('--list-ports', action='store_true', help='List Windows serial ports')
    
    args = parser.parse_args()

    if args.list_ports:
        from serial.tools import list_ports
        for port in list_ports.comports():
            print(f"{port.device}: {port.description} [{port.hwid}]")
        return
    if args.serial and (args.connect or args.scan):
        parser.error('--serial cannot be combined with --connect or --scan')
    if not args.serial and bluetooth is None:
        parser.error('PyBluez is unavailable. On Windows use --serial COM3 with an incoming Bluetooth port.')
    
    if args.scan:
        scan_devices()
        return
    
    messenger = AndroidBluetoothMessenger()
    
    try:
        if args.serial:
            if not messenger.open_serial(args.serial):
                sys.exit(1)
        elif args.connect:
            
            if not messenger.connect_to_device(args.connect, args.port):
                sys.exit(1)
        else:
            
            if not messenger.start_server(args.port):
                sys.exit(1)
        
        if not args.send:
            args.interactive = True
        
        if args.interactive:
            messenger.interactive_mode()
        else:
            if args.send:
                print(f"Sending: {args.send}")
                if messenger.send_message(args.send):
                    print("Message sent successfully")
                    
                    time.sleep(2)
                else:
                    print("Failed to send message")
                    sys.exit(1)
                
    except KeyboardInterrupt:
        print("\nInterrupted by user")
    finally:
        messenger.stop()

if __name__ == "__main__":
    main()
