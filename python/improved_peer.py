import socket
import subprocess
import time
import json
import struct
import logging
import sys

# Configure logging
logging.basicConfig(
    level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s"
)
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
            logger.error("No device found")
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

        logger.info("Port forwarding started successfully")
        return process
    except Exception as e:
        logger.error(f"Failed to start port forwarding: {e}")
        return None


def pack_frame(data, frame_type=101, tag=0):
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


def try_connect_to_port(device_id, port):
    """Try to connect to a specific port on the iOS device."""
    try:
        # Start port forwarding
        proxy_process = start_port_forwarding(device_id, port, port)
        if not proxy_process:
            logger.error(f"Failed to start port forwarding for port {port}")
            return None, None

        # Create a socket
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(2)  # 2 second timeout

        # Connect to the iOS app
        logger.info(f"Attempting to connect to localhost:{port}...")
        try:
            sock.connect(("127.0.0.1", port))
            logger.info(f"✅ TCP connection established successfully on port {port}")
        except ConnectionRefusedError:
            logger.error(f"Connection refused on port {port}")
            sock.close()
            proxy_process.terminate()
            return None, None
        except Exception as e:
            logger.error(f"Connection failed on port {port}: {e}")
            sock.close()
            proxy_process.terminate()
            return None, None

        # Set TCP_NODELAY to ensure immediate transmission
        sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        logger.info("TCP_NODELAY set successfully")

        return sock, proxy_process
    except Exception as e:
        logger.error(f"Error connecting to port {port}: {e}")
        if "sock" in locals():
            sock.close()
        if "proxy_process" in locals():
            proxy_process.terminate()
        return None, None


def main():
    """Main function to run the PeerTalk client."""
    logger.info("Starting improved PeerTalk client...")

    # Get the device ID
    device_id = get_device_udid()
    if not device_id:
        logger.error("No device found")
        return

    # Try ports in the range used by the iOS app
    base_port = 2347
    max_port = base_port + 10

    # If a specific port is provided as a command-line argument, try that first
    if len(sys.argv) > 1:
        try:
            specific_port = int(sys.argv[1])
            logger.info(f"Trying specific port {specific_port} first...")
            sock, proxy_process = try_connect_to_port(device_id, specific_port)
            if sock and proxy_process:
                logger.info(f"Successfully connected to port {specific_port}")
                # Continue with the connection...
                handle_connection(sock, proxy_process)
                return
        except ValueError:
            logger.error(f"Invalid port number: {sys.argv[1]}")

    # Try each port in the range
    for port in range(base_port, max_port + 1):
        logger.info(f"Trying port {port}...")
        sock, proxy_process = try_connect_to_port(device_id, port)
        if sock and proxy_process:
            logger.info(f"Successfully connected to port {port}")
            # Continue with the connection...
            handle_connection(sock, proxy_process)
            return

    logger.error("Failed to connect to any port in the range")


def handle_connection(sock, proxy_process):
    """Handle the established connection."""
    try:
        # Wait for initial status from iOS app after connection
        logger.info("Waiting for initial status from iOS app...")
        try:
            response = unpack_frame(sock)
            if response:
                logger.info(f"Received initial status: {response}")
            else:
                logger.warning("No initial status received")
        except socket.timeout:
            logger.warning("Timeout waiting for initial status")

        # Send device info
        handshake_data = {
            "type": "deviceInfo",
            "vid": "0x05AC",
            "pid": "0x12A8",
            "interface": "en0",
            "timestamp": int(time.time()),
        }

        handshake_frame = pack_frame(
            handshake_data, frame_type=102
        )  # Use deviceInfo frame type
        if handshake_frame:
            logger.info(f"Sending device info: {handshake_data}")
            sock.sendall(handshake_frame)

            # Wait for status response
            try:
                logger.info("Waiting for status response...")
                response = unpack_frame(sock)
                if response:
                    logger.info(f"Received status response: {response}")
                else:
                    logger.warning("No status response received")
            except socket.timeout:
                logger.warning("Timeout waiting for status response")
        else:
            logger.error("Failed to create device info frame")

        # Keep the connection open and send periodic status updates
        logger.info(
            "Connection established. Sending periodic status updates. Press Ctrl+C to exit."
        )
        last_status = 0
        while True:
            current_time = time.time()

            # Send status every 5 seconds
            if current_time - last_status >= 5:
                status_data = {
                    "type": "status",
                    "connected": True,
                    "timestamp": int(current_time),
                }
                status_frame = pack_frame(
                    status_data, frame_type=103
                )  # Use status frame type
                if status_frame:
                    logger.info("Sending status update...")
                    sock.sendall(status_frame)
                    last_status = current_time

                # Check for response
                try:
                    sock.settimeout(0.5)  # Short timeout for response
                    response = unpack_frame(sock)
                    if response:
                        logger.info(f"Received response: {response}")
                except socket.timeout:
                    pass
                except Exception as e:
                    logger.error(f"Error reading response: {e}")
                    raise  # Re-raise to trigger reconnection

            time.sleep(0.1)  # Small sleep to prevent CPU spinning

    except KeyboardInterrupt:
        logger.info("Exiting...")
    except Exception as e:
        logger.error(f"Error: {e}")
    finally:
        if "sock" in locals():
            sock.close()
        if proxy_process:
            proxy_process.terminate()


if __name__ == "__main__":
    main()
