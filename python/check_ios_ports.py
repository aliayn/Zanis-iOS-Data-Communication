import subprocess
import time
import logging
import socket
import re

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


def check_port_on_device(device_id, port):
    """Check if a port on the iOS device is accessible."""
    try:
        # First, check if the port is already being forwarded on the host
        result = subprocess.run(
            ["lsof", "-i", f":{port}"], capture_output=True, text=True
        )
        if result.stdout and "LISTEN" in result.stdout:
            logger.info(f"Port {port} is already in use on the host machine")
            return False

        # Start iproxy to forward the port
        logger.info(f"Starting iproxy to check port {port} on device...")
        process = subprocess.Popen(
            ["iproxy", f"{port}:{port}"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )

        # Give it a moment to start
        time.sleep(1)

        # Check if the process is still running
        if process.poll() is not None:
            stderr = process.stderr.read().decode("utf-8")
            logger.error(f"Port {port} is not available on the device: {stderr}")
            process.terminate()
            return False

        # Try to connect to the port
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(1)
        try:
            sock.connect(("127.0.0.1", port))
            logger.info(f"✅ Port {port} is accessible on the device")
            available = True
        except Exception as e:
            logger.error(f"❌ Port {port} is not accessible on the device: {e}")
            available = False
        finally:
            sock.close()
            process.terminate()

        return available
    except Exception as e:
        logger.error(f"Error checking port {port}: {e}")
        return False


def scan_ports(device_id, start_port, end_port):
    """Scan a range of ports on the iOS device."""
    available_ports = []

    logger.info(f"Scanning ports {start_port} to {end_port} on device {device_id}...")

    for port in range(start_port, end_port + 1):
        logger.info(f"Checking port {port}...")
        if check_port_on_device(device_id, port):
            available_ports.append(port)
            logger.info(f"Port {port} is available")
        else:
            logger.info(f"Port {port} is not available")

    return available_ports


def check_peertalk_ports(device_id):
    """Check the specific ports used by PeerTalk."""
    # Check the base port and the next 10 ports (as used by the iOS app)
    base_port = 2347
    peertalk_ports = []

    logger.info(f"Checking PeerTalk ports starting from {base_port}...")

    for port in range(base_port, base_port + 11):
        logger.info(f"Checking PeerTalk port {port}...")
        if check_port_on_device(device_id, port):
            peertalk_ports.append(port)
            logger.info(f"✅ PeerTalk port {port} is available")
        else:
            logger.info(f"❌ PeerTalk port {port} is not available")

    return peertalk_ports


def main():
    """Main function to check iOS device ports."""
    logger.info("Starting iOS port checker...")

    # Get the device ID
    device_id = get_device_udid()
    if not device_id:
        logger.error("No device found. Please connect an iOS device and try again.")
        return

    # Check PeerTalk ports
    peertalk_ports = check_peertalk_ports(device_id)

    if peertalk_ports:
        logger.info(f"Available PeerTalk ports: {peertalk_ports}")
        logger.info("✅ You have access to the iOS device's localhost ports")
    else:
        logger.error("❌ No PeerTalk ports are accessible on the device")
        logger.info("This could be due to:")
        logger.info("1. The iOS app is not running")
        logger.info("2. The iOS app is not properly initializing the PeerTalk server")
        logger.info("3. You don't have proper access to the device's localhost")

    # Check port 2350 specifically
    logger.info("Checking port 2350 specifically...")
    if check_port_on_device(device_id, 2350):
        logger.info("✅ Port 2350 is accessible on the device")
    else:
        logger.error("❌ Port 2350 is not accessible on the device")


if __name__ == "__main__":
    main()
