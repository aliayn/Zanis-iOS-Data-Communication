import logging
import time
import json
import struct
import subprocess
import os
import socket
import re

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def get_device_udid():
    """Get the UDID of the connected device."""
    try:
        result = subprocess.run(["idevice_id", "-l"], capture_output=True, text=True)
        if result.returncode != 0:
            logger.error(f"Failed to get device list: {result.stderr}")
            return None

        # Get the first device ID
        device_id = result.stdout.strip().split("\n")[0]
        if not device_id:
            return None

        logger.info(f"Found device: {device_id}")
        return device_id
    except Exception as e:
        logger.error(f"Failed to get device: {e}")
        return None


def start_port_forwarding(device_id, local_port, device_port):
    """Start port forwarding for the device."""
    try:
        # Kill any existing iproxy processes
        subprocess.run(["pkill", "-f", "iproxy"], capture_output=True)
        time.sleep(1)  # Wait for processes to be killed

        # Start iproxy to forward local port to device's localhost port
        logger.info(
            f"Starting port forwarding from local port {local_port} to device port {device_port}..."
        )
        process = subprocess.Popen(
            ["iproxy", f"{local_port}:{device_port}"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )

        # Give it a moment to start
        time.sleep(2)

        # Check if it's still running
        if process.poll() is not None:
            stderr = process.stderr.read().decode("utf-8")
            logger.error(f"Port forwarding failed to start: {stderr}")
            return None

        # Try to check if the port is actually being listened to
        try:
            result = subprocess.run(
                ["lsof", "-i", f":{local_port}"], capture_output=True, text=True
            )
            logger.info(f"Port {local_port} status:\n{result.stdout}")
            if "LISTEN" not in result.stdout:
                logger.error("Port is not in LISTEN state")
                process.terminate()
                return None
        except Exception as e:
            logger.warning(f"Could not check port status: {e}")

        logger.info("Port forwarding started successfully")
        return process
    except Exception as e:
        logger.error(f"Failed to start port forwarding: {e}")
        return None


def check_ios_port_status(device_id, port):
    """Check if a port on the iOS device is available."""
    try:
        # First, check if the port is already being forwarded
        result = subprocess.run(
            ["lsof", "-i", f":{port}"], capture_output=True, text=True
        )
        if result.stdout and "LISTEN" in result.stdout:
            logger.info(f"Port {port} is already in use on the host machine")
            return False

        # Try to start a temporary iproxy to check if the port is available on the device
        temp_process = subprocess.Popen(
            ["iproxy", f"{port}:{port}"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )

        # Give it a moment to start
        time.sleep(1)

        # Check if the process is still running
        if temp_process.poll() is not None:
            stderr = temp_process.stderr.read().decode("utf-8")
            logger.info(f"Port {port} is not available on the device: {stderr}")
            return False

        # Try to connect to the port
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(1)
        try:
            sock.connect(("127.0.0.1", port))
            logger.info(f"Port {port} is available on the device")
            available = True
        except:
            logger.info(f"Port {port} is not accessible on the device")
            available = False
        finally:
            sock.close()
            temp_process.terminate()

        return available
    except Exception as e:
        logger.error(f"Error checking port status: {e}")
        return False


def present_as_network_entity(device_id, port):
    """Present the Python script as a network entity to the iOS app."""
    try:
        # Create a socket to listen for incoming connections
        server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        server_socket.bind(("127.0.0.1", 0))  # Use a random available port
        server_socket.listen(1)

        # Get the local port we're listening on
        local_port = server_socket.getsockname()[1]
        logger.info(f"Listening for connections on port {local_port}")

        # Start port forwarding from our local port to the device port
        proxy_process = start_port_forwarding(device_id, local_port, port)
        if not proxy_process:
            logger.error("Failed to start port forwarding")
            server_socket.close()
            return None, None

        # Accept a connection from the iOS app
        logger.info("Waiting for connection from iOS app...")
        client_socket, addr = server_socket.accept()
        logger.info(f"Connected to iOS app at {addr}")

        # Set TCP_NODELAY to ensure immediate transmission
        client_socket.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)

        return client_socket, proxy_process
    except Exception as e:
        logger.error(f"Error presenting as network entity: {e}")
        if "server_socket" in locals():
            server_socket.close()
        if "proxy_process" in locals():
            proxy_process.terminate()
        return None, None


def connect_to_peertalk():
    """Connect to the PeerTalk service."""
    try:
        # Get the device ID
        device_id = get_device_udid()
        if not device_id:
            logger.error("No device found")
            return None, None

        # Use port 2350 which we've confirmed is available
        local_port = 2350
        device_port = 2350

        # Start port forwarding
        proxy_process = start_port_forwarding(device_id, local_port, device_port)
        if not proxy_process:
            logger.error("Failed to start port forwarding")
            return None, None

        # Create a socket
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(5)  # 5 second timeout

        # Connect to the iOS app
        logger.info(f"Attempting to connect to localhost:{local_port}...")
        sock.connect(("127.0.0.1", local_port))
        logger.info("TCP connection established successfully")

        # Set TCP_NODELAY to ensure immediate transmission
        sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        logger.info("TCP_NODELAY set successfully")

        # Send initial handshake with device info
        vid, pid = get_device_info()
        handshake_data = {
            "type": "deviceInfo",
            "vid": vid if vid else "0x05AC",
            "pid": pid if pid else "0x12A8",
            "interface": "en0",
            "timestamp": int(time.time()),
        }

        handshake_frame = pack_frame(handshake_data)
        if handshake_frame:
            logger.info(f"Sending handshake with device info: {handshake_data}")
            sock.sendall(handshake_frame)
            sock.flush()

            # Wait for response
            try:
                logger.info("Waiting for response from iOS app...")
                response = unpack_frame(sock)
                if response:
                    logger.info(f"Received response from iOS app: {response}")
                    return sock, proxy_process
                else:
                    logger.warning("No response received from iOS app")
            except socket.timeout:
                logger.warning("Timeout waiting for iOS app response")
        else:
            logger.error("Failed to create handshake frame")

        return sock, proxy_process
    except Exception as e:
        logger.error(f"Failed to connect: {e}")
        if "proxy_process" in locals():
            proxy_process.terminate()
        if "sock" in locals():
            sock.close()
        return None, None


def pack_frame(data):
    """Pack data into a PeerTalk frame."""
    try:
        # Convert data to bytes if it's not already
        if isinstance(data, str):
            payload = data.encode("utf-8")
        elif isinstance(data, dict):
            payload = json.dumps(data).encode("utf-8")
        elif isinstance(data, bytes):
            payload = data
        else:
            payload = str(data).encode("utf-8")

        # PeerTalk frame format matching iOS implementation
        frame_type = 101  # Match the iOS app's frame type for data transmission
        tag = 0  # PTFrameNoTag in iOS
        payload_size = len(payload)
        total_length = payload_size + 16  # Header size is 16 bytes

        # Pack header (matching iOS implementation)
        # Format: total_length (4 bytes) + frame_type (4 bytes) + tag (4 bytes) + payload_size (4 bytes)
        header = struct.pack(">IIII", total_length, frame_type, tag, payload_size)
        frame = header + payload

        # Log the frame details
        logger.info(f"Frame details:")
        logger.info(f"  Total length: {total_length}")
        logger.info(f"  Frame type: {frame_type}")
        logger.info(f"  Tag: {tag}")
        logger.info(f"  Payload size: {payload_size}")
        logger.info(f"  Header (hex): {header.hex()}")
        logger.info(f"  Payload (hex): {payload.hex()}")
        logger.info(f"  Payload: {payload.decode('utf-8', errors='ignore')}")

        return frame
    except Exception as e:
        logger.error(f"Error packing frame: {e}")
        return None


def unpack_frame(sock):
    """Unpack a PeerTalk frame from the socket."""
    try:
        # Read header (16 bytes)
        header = sock.recv(16)
        if not header:
            return None

        # Unpack header (matching iOS implementation)
        total_length, frame_type, tag, payload_size = struct.unpack(">IIII", header)

        # Log the frame details
        logger.info("Received frame:")
        logger.info(f"  Total length: {total_length}")
        logger.info(f"  Frame type: {frame_type}")
        logger.info(f"  Tag: {tag}")
        logger.info(f"  Payload size: {payload_size}")
        logger.info(f"  Header (hex): {header.hex()}")

        # Read payload
        if payload_size > 0:
            payload = sock.recv(payload_size)
            if payload:
                logger.info(f"  Payload (hex): {payload.hex()}")
                try:
                    return payload.decode("utf-8")
                except UnicodeDecodeError:
                    return payload

        return None
    except Exception as e:
        logger.error(f"Error unpacking frame: {e}")
        return None


def send_handshake(sock):
    """Send a handshake frame to establish the connection."""
    try:
        # Send a simple handshake message
        handshake = {
            "type": "deviceInfo",  # Match iOS app's expected type
            "vid": "0x05AC",  # Apple's vendor ID
            "pid": "0x12A8",  # Common iPhone PID
            "interface": "en0",  # Default interface name
            "timestamp": int(time.time()),
        }

        frame = pack_frame(handshake)
        if frame:
            logger.info("Sending handshake...")
            sock.sendall(frame)
            sock.flush() if hasattr(sock, "flush") else None  # Ensure data is sent
            logger.info("Handshake sent")
            return True

        return False
    except Exception as e:
        logger.error(f"Error during handshake: {e}")
        return False


def detect_cdc_ecm():
    """Detect CDC-ECM device connection."""
    try:
        # Check for network interfaces that might be CDC-ECM
        result = subprocess.run(["ifconfig"], capture_output=True, text=True)
        if result.returncode != 0:
            logger.error(f"Failed to get network interfaces: {result.stderr}")
            return None

        # Look for ECM interface (usually starts with en or eth)
        interfaces = result.stdout.split("\n\n")
        for interface in interfaces:
            # Check if this is an ECM interface
            if "ECM" in interface or (
                "en" in interface and "status: active" in interface
            ):
                # Extract interface name
                match = re.match(r"^([^\s:]+)", interface)
                if match:
                    interface_name = match.group(1)
                    logger.info(f"Found CDC-ECM interface: {interface_name}")
                    return interface_name

        return None
    except Exception as e:
        logger.error(f"Failed to detect CDC-ECM: {e}")
        return None


def get_device_info():
    """Get device information including VID and PID."""
    try:
        # Get device info using system_profiler
        result = subprocess.run(
            ["system_profiler", "SPUSBDataType"], capture_output=True, text=True
        )

        if result.returncode != 0:
            logger.error(f"Failed to get USB device info: {result.stderr}")
            return None, None

        # Look for iPhone/iPad in the output
        output = result.stdout
        vid = None
        pid = None

        # Find VID and PID
        vid_match = re.search(r"Vendor ID: (0x[0-9A-Fa-f]+)", output)
        pid_match = re.search(r"Product ID: (0x[0-9A-Fa-f]+)", output)

        if vid_match:
            vid = vid_match.group(1)
        if pid_match:
            pid = pid_match.group(1)

        if vid and pid:
            logger.info(f"Found device VID: {vid}, PID: {pid}")
            return vid, pid

        return None, None
    except Exception as e:
        logger.error(f"Failed to get device info: {e}")
        return None, None


def send_device_info(sock):
    """Send device information to the iOS app."""
    try:
        # Get device VID/PID
        vid, pid = get_device_info()
        if not vid or not pid:
            logger.warning("Could not get device VID/PID")
            vid = "unknown"
            pid = "unknown"

        # Get CDC-ECM interface
        interface = detect_cdc_ecm()

        # Prepare device info message
        device_info = {
            "type": "deviceInfo",
            "vid": vid,
            "pid": pid,
            "interface": interface if interface else "unknown",
            "timestamp": int(time.time()),
        }

        frame = pack_frame(device_info)
        if frame:
            logger.info("Sending device info...")
            sock.sendall(frame)
            logger.info("Device info sent")
            return True

        return False
    except Exception as e:
        logger.error(f"Error sending device info: {e}")
        return False


def main():
    """Main function to run the PeerTalk client."""
    logger.info("Starting PeerTalk client...")

    # Clean up any existing iproxy processes
    subprocess.run(["pkill", "-f", "iproxy"], capture_output=True)
    time.sleep(1)

    while True:
        try:
            # Connect to PeerTalk
            sock, proxy_process = connect_to_peertalk()
            if not sock:
                logger.error("Failed to establish connection")
                time.sleep(1)
                continue

            try:
                # Send handshake
                if not send_handshake(sock):
                    logger.error("Handshake failed")
                    continue

                # Send device info
                if not send_device_info(sock):
                    logger.error("Failed to send device info")
                    continue

                # Keep checking for CDC-ECM connection
                last_interface = None
                while True:
                    try:
                        # Check for CDC-ECM interface
                        current_interface = detect_cdc_ecm()

                        # If interface changed, send update
                        if current_interface != last_interface:
                            last_interface = current_interface
                            status = {
                                "type": "status",
                                "connected": current_interface is not None,
                                "interface": current_interface
                                if current_interface
                                else "none",
                                "timestamp": int(time.time()),
                            }
                            frame = pack_frame(status)
                            if frame:
                                sock.sendall(frame)
                                logger.info(
                                    f"Sent connection status: {'connected' if current_interface else 'disconnected'}"
                                )

                        # Handle any incoming messages
                        try:
                            response = unpack_frame(sock)
                            if response:
                                logger.info(f"Received message: {response}")
                        except socket.timeout:
                            pass

                    except Exception as e:
                        logger.error(f"Error in connection check loop: {e}")
                        break

                    time.sleep(1)

            except Exception as e:
                logger.error(f"Error during communication: {e}")
            finally:
                sock.close()
                if proxy_process:
                    proxy_process.terminate()

        except Exception as e:
            logger.error(f"Error in main loop: {e}")
            time.sleep(1)
            if "sock" in locals():
                sock.close()
            if "proxy_process" in locals():
                proxy_process.terminate()


if __name__ == "__main__":
    main()
