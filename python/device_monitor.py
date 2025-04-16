#!/usr/bin/env python3

import subprocess
import time
import json
from datetime import datetime
import re


def get_network_interfaces():
    """Get list of current network interfaces, excluding Apple interfaces"""
    try:
        result = subprocess.run(
            ["networksetup", "-listallhardwareports"], capture_output=True, text=True
        )
        interfaces = []
        current_interface = ""

        for line in result.stdout.split("\n"):
            if "Hardware Port:" in line:
                current_interface = line.split(": ")[1].strip()
            elif "Device:" in line and current_interface:
                device = line.split(": ")[1].strip()
                # Filter out Apple interfaces
                if not any(
                    apple in device.lower()
                    for apple in ["apple", "en0", "en1", "bridge", "p2p"]
                ):
                    interfaces.append(f"{current_interface}: {device}")

        return "\n".join(interfaces)
    except subprocess.CalledProcessError as e:
        print(f"Error getting network interfaces: {e}")
        return ""


def get_usb_devices():
    """Get list of all USB devices with their details"""
    try:
        result = subprocess.run(
            ["system_profiler", "SPUSBDataType"], capture_output=True, text=True
        )
        devices = []
        current_device = {}

        for line in result.stdout.split("\n"):
            line = line.strip()
            if not line:
                continue

            if ":" in line and not line.startswith("    "):
                # New device section
                if current_device:
                    devices.append(current_device)
                current_device = {"name": line.split(":")[0].strip()}
            elif line.startswith("    "):
                # Device details
                if ":" in line:
                    key, value = line.split(":", 1)
                    current_device[key.strip()] = value.strip()

        if current_device:
            devices.append(current_device)

        return devices
    except subprocess.CalledProcessError as e:
        print(f"Error getting USB devices: {e}")
        return []


def get_network_connections():
    """Get active network connections, excluding local and Apple services"""
    try:
        result = subprocess.run(["netstat", "-an"], capture_output=True, text=True)
        connections = []

        for line in result.stdout.split("\n"):
            if "ESTABLISHED" in line or "LISTEN" in line:
                # Filter out local and Apple services
                if not any(
                    addr in line for addr in ["127.0.0.1", "::1", "apple", "localhost"]
                ):
                    connections.append(line.strip())

        return "\n".join(connections)
    except subprocess.CalledProcessError as e:
        print(f"Error getting network connections: {e}")
        return ""


def get_detailed_usb_info():
    """Get detailed USB device information using multiple system commands"""
    try:
        # Get USB tree using ioreg
        ioreg_result = subprocess.run(
            ["ioreg", "-p", "IOUSB", "-l", "-w", "0"], capture_output=True, text=True
        )

        # Get disk information
        diskutil_result = subprocess.run(
            ["diskutil", "list"], capture_output=True, text=True
        )

        # Get system profiler USB info
        sysprof_result = subprocess.run(
            ["system_profiler", "SPUSBDataType"], capture_output=True, text=True
        )

        devices = []
        current_device = {}

        # Parse ioreg output
        for line in ioreg_result.stdout.split("\n"):
            line = line.strip()
            if '"USB Product Name"' in line:
                if current_device:
                    devices.append(current_device)
                current_device = {
                    "name": line.split("=")[1].strip().strip('"'),
                    "type": "USB Device",
                }
            elif '"USB Vendor Name"' in line and current_device:
                current_device["vendor"] = line.split("=")[1].strip().strip('"')
            elif '"USB Serial Number"' in line and current_device:
                current_device["serial"] = line.split("=")[1].strip().strip('"')
            elif '"idProduct"' in line and current_device:
                current_device["product_id"] = line.split("=")[1].strip()
            elif '"idVendor"' in line and current_device:
                current_device["vendor_id"] = line.split("=")[1].strip()
            elif '"USB Address"' in line and current_device:
                current_device["address"] = line.split("=")[1].strip()
            elif '"USB Speed"' in line and current_device:
                current_device["speed"] = line.split("=")[1].strip().strip('"')

        if current_device:
            devices.append(current_device)

        # Parse disk information
        disk_devices = []
        current_disk = {}
        for line in diskutil_result.stdout.split("\n"):
            if "/dev/disk" in line:
                if current_disk:
                    disk_devices.append(current_disk)
                parts = line.split()
                current_disk = {
                    "name": " ".join(parts[2:]) if len(parts) > 2 else "Unknown Disk",
                    "device": parts[0],
                    "size": parts[1] if len(parts) > 1 else "Unknown",
                    "type": "Storage Device",
                }
            elif "0:" in line and current_disk:
                current_disk["partitions"] = line.strip()

        if current_disk:
            disk_devices.append(current_disk)

        # Parse system profiler output
        for line in sysprof_result.stdout.split("\n"):
            if ":" in line and not line.startswith("    "):
                device_name = line.split(":")[0].strip()
                for device in devices:
                    if device["name"] == device_name:
                        device["details"] = line.strip()
                        break

        # Combine all device information
        all_devices = devices + disk_devices

        # Get additional network interface information for USB network devices
        network_result = subprocess.run(
            ["networksetup", "-listallhardwareports"], capture_output=True, text=True
        )

        for device in all_devices:
            if (
                "network" in device["name"].lower()
                or "ethernet" in device["name"].lower()
            ):
                device["network_info"] = network_result.stdout

        return all_devices

    except subprocess.CalledProcessError as e:
        print(f"Error getting device information: {e}")
        return []


def format_device_info(device):
    """Format device information for display"""
    info = []
    info.append(f"Device: {device.get('name', 'Unknown')}")
    info.append(f"Type: {device.get('type', 'Unknown')}")

    if "vendor" in device:
        info.append(f"Vendor: {device['vendor']}")
    if "serial" in device:
        info.append(f"Serial: {device['serial']}")
    if "product_id" in device:
        info.append(f"Product ID: {device['product_id']}")
    if "vendor_id" in device:
        info.append(f"Vendor ID: {device['vendor_id']}")
    if "address" in device:
        info.append(f"USB Address: {device['address']}")
    if "speed" in device:
        info.append(f"Speed: {device['speed']}")
    if "device" in device:
        info.append(f"Device Path: {device['device']}")
    if "size" in device:
        info.append(f"Size: {device['size']}")
    if "partitions" in device:
        info.append(f"Partitions: {device['partitions']}")
    if "details" in device:
        info.append(f"Details: {device['details']}")

    return "\n".join(info)


def monitor_usb_devices():
    print("Starting USB device monitoring...")
    print("Press Ctrl+C to stop")
    print("\nMonitoring for USB device changes...")

    # Initial state
    prev_devices = get_detailed_usb_info()

    try:
        while True:
            current_devices = get_detailed_usb_info()

            # Check for new devices
            new_devices = [d for d in current_devices if d not in prev_devices]
            if new_devices:
                print(f"\n[{datetime.now()}] New device(s) detected:")
                for device in new_devices:
                    print("\n" + format_device_info(device))
                    print("-" * 80)

            # Check for removed devices
            removed_devices = [d for d in prev_devices if d not in current_devices]
            if removed_devices:
                print(f"\n[{datetime.now()}] Device(s) removed:")
                for device in removed_devices:
                    print(f"\nDevice removed: {device.get('name', 'Unknown')}")
                    print(f"Type: {device.get('type', 'Unknown')}")
                    print("-" * 80)

            prev_devices = current_devices
            time.sleep(1)  # Check every second

    except KeyboardInterrupt:
        print("\nMonitoring stopped by user")


if __name__ == "__main__":
    monitor_usb_devices()
