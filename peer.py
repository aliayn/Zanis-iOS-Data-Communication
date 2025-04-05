import socket
import struct
import json
import logging
import time
import plistlib
import os

# Configure logging
logging.basicConfig(level=logging.DEBUG)
logger = logging.getLogger(__name__)

# Constants matching PeerTalkManager.swift
PORT = 2345
FRAME_TYPE_DATA = 101
PTFrameNoTag = 0
USBMUXD_SOCKET_PATH = "/var/run/usbmuxd"


def send_usbmuxd_message(sock, message):
    """Send a message to usbmuxd and return the response"""
    try:
        # Send request
        msg = plistlib.dumps(message)
        length = len(msg)
        header = struct.pack("II", length + 16, 8)
        sock.send(header + msg)

        # Read response
        resp_header = sock.recv(16)
        if not resp_header or len(resp_header) != 16:
            raise Exception("Failed to read response header")

        resp_length, resp_type = struct.unpack("II", resp_header[:8])
        resp_data = sock.recv(resp_length - 16)
        if not resp_data or len(resp_data) != resp_length - 16:
            raise Exception("Failed to read response data")

        return plistlib.loads(resp_data)
    except Exception as e:
        logger.error(f"Error in usbmuxd communication: {e}")
        raise


def connect_to_peertalk():
    """Connect to the iOS device using usbmuxd directly"""
    try:
        # Check if usbmuxd socket exists
        if not os.path.exists(USBMUXD_SOCKET_PATH):
            logger.error(f"usbmuxd socket not found at {USBMUXD_SOCKET_PATH}")
            return None

        # Connect to usbmuxd
        usbmuxd = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        usbmuxd.settimeout(5.0)  # Set timeout for operations
        usbmuxd.connect(USBMUXD_SOCKET_PATH)
        logger.info("Connected to usbmuxd")

        # List devices
        list_devices_msg = {
            "MessageType": "ListDevices",
            "ClientVersionString": "peertalk-python",
            "ProgName": "peertalk-python",
            "kLibUSBMuxVersion": 3,
        }

        devices = send_usbmuxd_message(usbmuxd, list_devices_msg)

        if not devices.get("DeviceList"):
            logger.error("No devices found")
            return None

        device = devices["DeviceList"][0]
        device_id = device["DeviceID"]
        logger.info(f"Found device: {device.get('SerialNumber', device_id)}")

        # Connect to device
        connect_msg = {
            "MessageType": "Connect",
            "ClientVersionString": "peertalk-python",
            "ProgName": "peertalk-python",
            "DeviceID": device_id,
            "PortNumber": PORT,
        }

        result = send_usbmuxd_message(usbmuxd, connect_msg)

        if result.get("Number", 1) == 0:
            logger.info(f"Connected to device on port {PORT}")
            return usbmuxd
        else:
            logger.error(f"Failed to connect: {result}")
            return None

    except Exception as e:
        logger.error(f"Failed to connect to device: {e}")
        if "usbmuxd" in locals():
            usbmuxd.close()
        return None


def pack_frame(data):
    """Pack data into a PeerTalk frame matching iOS implementation"""
    frame_type = FRAME_TYPE_DATA
    tag = PTFrameNoTag
    length = len(data)

    # Match the frame format from PeerTalkManager.swift:
    # - 4 bytes: frame type (uint32)
    # - 4 bytes: tag (uint32)
    # - 4 bytes: payload length (uint32)
    # - N bytes: payload
    header = struct.pack(">III", frame_type, tag, length)
    return header + data


def unpack_frame(sock):
    """Unpack a PeerTalk frame from the socket"""
    try:
        # Read header (12 bytes: type + tag + length)
        header = sock.recv(12)
        if not header or len(header) != 12:
            return None

        frame_type, tag, length = struct.unpack(">III", header)
        logger.debug(f"Received frame: type={frame_type}, tag={tag}, length={length}")

        # Read payload
        payload = sock.recv(length)
        if not payload or len(payload) != length:
            return None

        return payload

    except Exception as e:
        logger.error(f"Error unpacking frame: {e}")
        return None


def main():
    logger.info("Starting PeerTalk client...")

    while True:
        try:
            # Connect to device
            sock = connect_to_peertalk()
            if not sock:
                logger.error("Failed to establish connection")
                time.sleep(1)  # Wait before retrying
                continue

            # Communication loop
            while True:
                try:
                    # Send a test message
                    test_message = json.dumps(
                        {"type": "test", "message": "Hello from Python!"}
                    ).encode()

                    frame = pack_frame(test_message)
                    sock.sendall(frame)
                    logger.info("Sent test message")

                    # Wait for response
                    response = unpack_frame(sock)
                    if response:
                        try:
                            decoded = response.decode()
                            logger.info(f"Received response: {decoded}")
                        except UnicodeDecodeError:
                            logger.info(
                                f"Received binary response of {len(response)} bytes"
                            )

                    time.sleep(1)  # Wait before sending next message

                except (socket.error, ConnectionError) as e:
                    logger.error(f"Connection error: {e}")
                    break

        except KeyboardInterrupt:
            logger.info("Stopping client...")
            break
        except Exception as e:
            logger.error(f"Error during communication: {e}")
            time.sleep(1)  # Wait before retrying
        finally:
            if "sock" in locals() and sock:
                sock.close()


if __name__ == "__main__":
    main()
