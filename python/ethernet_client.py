import socket
import time
import logging
import sys
import threading

# Configure logging
logging.basicConfig(
    level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger(__name__)


class EthernetClient:
    def __init__(self, host="192.168.31.98", port=2355):
        self.host = host
        self.port = port
        self.socket = None
        self.is_connected = False
        self.receive_thread = None
        self.heartbeat_thread = None

    def connect(self):
        """Connect to the iOS device."""
        try:
            self.socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            self.socket.settimeout(5)  # 5 second timeout
            logger.info(f"Connecting to {self.host}:{self.port}...")
            self.socket.connect((self.host, self.port))
            self.is_connected = True
            logger.info("✅ Connected successfully")

            # Start receive and heartbeat threads
            self.receive_thread = threading.Thread(target=self._receive_loop)
            self.heartbeat_thread = threading.Thread(target=self._heartbeat_loop)
            self.receive_thread.daemon = True
            self.heartbeat_thread.daemon = True
            self.receive_thread.start()
            self.heartbeat_thread.start()

        except Exception as e:
            logger.error(f"Connection error: {e}")
            self.close()

    def _receive_loop(self):
        """Continuously receive data from the iOS device."""
        while self.is_connected:
            try:
                data = self.socket.recv(1024)
                if not data:
                    logger.info("Connection closed by server")
                    break
                logger.info(f"Received: {data.decode('utf-8')}")
            except socket.timeout:
                continue
            except Exception as e:
                logger.error(f"Receive error: {e}")
                break

    def _heartbeat_loop(self):
        """Send periodic heartbeat messages."""
        while self.is_connected:
            try:
                self.send("heartbeat")
                time.sleep(5)  # Send heartbeat every 5 seconds
            except Exception as e:
                logger.error(f"Heartbeat error: {e}")
                break

    def send(self, message):
        """Send data to the iOS device."""
        if not self.is_connected:
            logger.error("Not connected")
            return

        try:
            self.socket.sendall(message.encode("utf-8"))
            logger.info(f"Sent: {message}")
        except Exception as e:
            logger.error(f"Send error: {e}")
            self.close()

    def close(self):
        """Close the connection."""
        self.is_connected = False
        if self.socket:
            self.socket.close()
            self.socket = None
        logger.info("Connection closed")


def main():
    if len(sys.argv) > 1:
        host = sys.argv[1]
    else:
        host = "169.254.39.47"  # Default link-local address

    client = EthernetClient(host=host)

    try:
        client.connect()

        # Keep the main thread alive
        while client.is_connected:
            try:
                # Get user input
                message = input("Enter message to send (or 'quit' to exit): ")
                if message.lower() == "quit":
                    break
                client.send(message)
            except KeyboardInterrupt:
                break
            except Exception as e:
                logger.error(f"Error: {e}")
                break

    finally:
        client.close()


if __name__ == "__main__":
    main()
