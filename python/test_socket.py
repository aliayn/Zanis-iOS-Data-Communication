import socket
import subprocess
import time
import logging
import sys
import threading

# Configure logging
logging.basicConfig(
    level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger(__name__)


def get_device_udid():
    """Get the UDID of the connected iOS device."""
    try:
        result = subprocess.run(["idevice_id", "-l"], capture_output=True, text=True)
        if result.stdout.strip():
            return result.stdout.strip()
        else:
            logging.error("No iOS device found")
            sys.exit(1)
    except Exception as e:
        logging.error(f"Error getting device UDID: {e}")
        sys.exit(1)


def start_port_forwarding(device_id, local_port, device_port):
    """Start port forwarding using iproxy."""
    try:
        # Kill any existing iproxy processes
        subprocess.run(["pkill", "-f", "iproxy"], capture_output=True)
        time.sleep(1)  # Wait for process to be killed

        # Start iproxy in the background
        cmd = ["iproxy", str(local_port), str(device_port)]
        process = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        time.sleep(2)  # Wait for port forwarding to start

        if process.poll() is None:
            logging.info("Port forwarding started successfully")
            return process
        else:
            logging.error("Failed to start port forwarding")
            sys.exit(1)
    except Exception as e:
        logging.error(f"Error starting port forwarding: {e}")
        sys.exit(1)


def receive_messages(sock):
    """Continuously receive messages from the socket."""
    while True:
        try:
            data = sock.recv(1024)
            if not data:
                logging.info("Connection closed by the server")
                break
            logging.info(f"📥 Received: {data.decode('utf-8')}")
        except socket.timeout:
            continue
        except Exception as e:
            logging.error(f"Error receiving data: {e}")
            break


def send_heartbeat(sock):
    """Send periodic heartbeat messages."""
    while True:
        try:
            message = f"Heartbeat {int(time.time())}"
            sock.sendall(message.encode("utf-8"))
            logging.info(f"📤 Sent: {message}")
            time.sleep(2)  # Send heartbeat every 2 seconds
        except Exception as e:
            logging.error(f"Error sending heartbeat: {e}")
            break


def main():
    if len(sys.argv) != 2:
        print("Usage: python test_socket.py <port>")
        sys.exit(1)

    port = int(sys.argv[1])

    # Get device UDID
    device_id = get_device_udid()
    logging.info(f"Found device: {device_id}")

    # Start port forwarding
    iproxy_process = start_port_forwarding(device_id, port, port)

    while True:  # Retry loop
        try:
            # Create socket
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.settimeout(0.5)  # Short timeout for non-blocking receive

            # Connect to the port
            logging.info(f"Attempting to connect to localhost:{port}...")
            sock.connect(("127.0.0.1", port))
            logging.info(f"✅ Successfully connected to port {port}")

            # Start threads for receiving and sending
            receive_thread = threading.Thread(target=receive_messages, args=(sock,))
            heartbeat_thread = threading.Thread(target=send_heartbeat, args=(sock,))
            receive_thread.daemon = True
            heartbeat_thread.daemon = True
            receive_thread.start()
            heartbeat_thread.start()

            # Keep the main thread alive and monitor connection
            while True:
                if not receive_thread.is_alive() or not heartbeat_thread.is_alive():
                    logging.info("Connection lost, attempting to reconnect...")
                    break
                time.sleep(1)

        except Exception as e:
            logging.error(f"Connection error: {e}")
            time.sleep(2)  # Wait before retrying

        finally:
            try:
                sock.close()
            except Exception as e:
                logging.error(f"Error closing socket: {e}")

    # Cleanup
    iproxy_process.terminate()
    logging.info("Connection closed and port forwarding stopped")


if __name__ == "__main__":
    main()
