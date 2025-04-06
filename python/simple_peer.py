import socket
import subprocess
import time
import json
import struct
import logging

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

        logger.info("Port forwarding started successfully")
        return process
    except Exception as e:
        logger.error(f"Failed to start port forwarding: {e}")
        return None


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

        # PeerTalk frame format
        frame_type = 100  # Changed to 100 for control messages
        tag = 1  # Changed from 0 to 1
        payload_size = len(payload)
        total_length = payload_size + 16  # Header size is 16 bytes

        # Pack header
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


def main():
    """Main function to run the PeerTalk client."""
    logger.info("Starting simple PeerTalk client...")

    # Get the device ID
    device_id = get_device_udid()
    if not device_id:
        logger.error("No device found")
        return

    # Use port 2350 which we've confirmed is available
    local_port = 2350
    device_port = 2350

    while True:  # Main connection loop
        try:
            # Start port forwarding
            proxy_process = start_port_forwarding(device_id, local_port, device_port)
            if not proxy_process:
                logger.error("Failed to start port forwarding")
                time.sleep(2)
                continue

            try:
                # Create a socket
                sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                sock.settimeout(2)  # 2 second timeout

                # Connect to the iOS app
                logger.info(f"Attempting to connect to localhost:{local_port}...")
                try:
                    sock.connect(("127.0.0.1", local_port))
                    logger.info("TCP connection established successfully")
                except ConnectionRefusedError:
                    logger.error(
                        "Connection refused. Make sure the iOS app is running and listening on port 2350"
                    )
                    time.sleep(2)
                    continue
                except Exception as e:
                    logger.error(f"Connection failed: {e}")
                    time.sleep(2)
                    continue

                # Set TCP_NODELAY to ensure immediate transmission
                sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
                logger.info("TCP_NODELAY set successfully")

                # Send initial handshake
                handshake_data = {
                    "type": "deviceInfo",
                    "vid": "0x05AC",
                    "pid": "0x12A8",
                    "interface": "en0",
                    "timestamp": int(time.time()),
                }

                handshake_frame = pack_frame(handshake_data)
                if handshake_frame:
                    logger.info(f"Sending handshake with device info: {handshake_data}")
                    sock.sendall(handshake_frame)

                    # Wait for response
                    try:
                        logger.info("Waiting for response from iOS app...")
                        response = unpack_frame(sock)
                        if response:
                            logger.info(f"Received response from iOS app: {response}")
                        else:
                            logger.warning("No response received from iOS app")
                    except socket.timeout:
                        logger.warning("Timeout waiting for iOS app response")
                else:
                    logger.error("Failed to create handshake frame")

                # Keep the connection open and send periodic heartbeats
                logger.info(
                    "Connection established. Sending periodic heartbeats. Press Ctrl+C to exit."
                )
                last_heartbeat = 0
                while True:
                    current_time = time.time()

                    # Send heartbeat every 5 seconds
                    if current_time - last_heartbeat >= 5:
                        heartbeat_data = {
                            "type": "heartbeat",
                            "timestamp": int(current_time),
                        }
                        heartbeat_frame = pack_frame(heartbeat_data)
                        if heartbeat_frame:
                            logger.info("Sending heartbeat...")
                            sock.sendall(heartbeat_frame)
                            last_heartbeat = current_time

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
                break
            except Exception as e:
                logger.error(f"Error: {e}")
                time.sleep(2)  # Wait before retrying
            finally:
                if "sock" in locals():
                    sock.close()
                if proxy_process:
                    proxy_process.terminate()

        except KeyboardInterrupt:
            break


if __name__ == "__main__":
    main()
