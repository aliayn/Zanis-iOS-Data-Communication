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
    def __init__(self, host="127.0.0.1", port=2345):
        self.host = host
        self.port = port
        self.socket = None
        self.is_connected = False
        self.receive_thread = None
        self.heartbeat_thread = None
        self.reconnect_thread = None
        self.auto_reconnect = True
        self.reconnect_delay = 5  # seconds

    def connect(self, auto_reconnect=True):
        """Connect to the Ethernet server."""
        self.auto_reconnect = auto_reconnect
        try:
            if self.is_connected:
                logger.info("Already connected, disconnecting first...")
                self.disconnect()

            self.socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            self.socket.settimeout(10)  # 10 second timeout for connection
            logger.info(f"Connecting to {self.host}:{self.port}...")
            self.socket.connect((self.host, self.port))
            self.is_connected = True
            logger.info(f"✅ Connected successfully to {self.host}:{self.port}")

            # Start receive thread
            self.receive_thread = threading.Thread(target=self._receive_loop)
            self.receive_thread.daemon = True
            self.receive_thread.start()

            # Start heartbeat thread
            self.heartbeat_thread = threading.Thread(target=self._heartbeat_loop)
            self.heartbeat_thread.daemon = True
            self.heartbeat_thread.start()

            return True

        except Exception as e:
            logger.error(f"Connection error: {e}")
            self.is_connected = False

            if auto_reconnect and self.reconnect_thread is None:
                self._start_reconnect_thread()

            return False

    def _start_reconnect_thread(self):
        """Start a background thread to handle reconnection."""
        self.reconnect_thread = threading.Thread(target=self._reconnect_loop)
        self.reconnect_thread.daemon = True
        self.reconnect_thread.start()

    def _reconnect_loop(self):
        """Try to reconnect until successful or auto_reconnect is disabled."""
        while self.auto_reconnect and not self.is_connected:
            logger.info(f"Attempting to reconnect in {self.reconnect_delay} seconds...")
            time.sleep(self.reconnect_delay)
            if self.connect(auto_reconnect=False):
                break
        self.reconnect_thread = None

    def _receive_loop(self):
        """Continuously receive data from the server."""
        self.socket.settimeout(1)  # 1 second timeout for receives
        while self.is_connected:
            try:
                data = self.socket.recv(1024)
                if not data:
                    logger.info("Connection closed by server")
                    self.disconnect()
                    if self.auto_reconnect:
                        self._start_reconnect_thread()
                    break

                message = data.decode("utf-8")
                logger.info(f"Received: {message}")

                # Skip logging heartbeats to reduce noise
                if message != "server_heartbeat":
                    logger.info(f"Received: {message}")

            except socket.timeout:
                continue
            except ConnectionResetError:
                logger.error("Connection reset by server")
                self.disconnect()
                if self.auto_reconnect:
                    self._start_reconnect_thread()
                break
            except Exception as e:
                if self.is_connected:  # Only log if we haven't already disconnected
                    logger.error(f"Receive error: {e}")
                    self.disconnect()
                    if self.auto_reconnect:
                        self._start_reconnect_thread()
                break

    def _heartbeat_loop(self):
        """Send periodic heartbeat messages."""
        while self.is_connected:
            try:
                self.send("client_heartbeat")
                time.sleep(5)  # Send heartbeat every 5 seconds
            except Exception:
                break

    def send(self, message):
        """Send data to the server."""
        if not self.is_connected or not self.socket:
            logger.error("Not connected, cannot send message")
            return False

        try:
            self.socket.sendall(message.encode("utf-8"))
            # Skip logging heartbeats to reduce noise
            if message != "client_heartbeat":
                logger.info(f"Sent: {message}")
            return True
        except Exception as e:
            logger.error(f"Send error: {e}")
            self.disconnect()
            if self.auto_reconnect:
                self._start_reconnect_thread()
            return False

    def disconnect(self):
        """Disconnect from the server."""
        self.is_connected = False
        if self.socket:
            try:
                self.socket.close()
            except Exception:
                pass
            self.socket = None
        logger.info("Disconnected from server")

    def set_auto_reconnect(self, enabled, delay=5):
        """Enable or disable auto reconnection."""
        self.auto_reconnect = enabled
        self.reconnect_delay = delay
        logger.info(f"Auto reconnect {'enabled' if enabled else 'disabled'}")


def main():
    if len(sys.argv) > 1:
        host = sys.argv[1]
    else:
        host = "127.0.0.1"  # Default to localhost if not specified

    if len(sys.argv) > 2:
        port = int(sys.argv[2])
    else:
        port = 2345

    client = EthernetClient(host, port)

    try:
        client.connect()

        print("\nCommands:")
        print("  /quit - Exit the program")
        print("  /reconnect - Force reconnection")
        print("  /auto <on|off> - Toggle auto reconnection")
        print("  Any other text will be sent as a message\n")

        # Keep the main thread alive for user input
        while True:
            try:
                # Get user input
                message = input("> ")

                if message.lower() == "/quit":
                    break
                elif message.lower() == "/reconnect":
                    client.disconnect()
                    client.connect()
                elif message.lower().startswith("/auto"):
                    parts = message.split()
                    if len(parts) > 1 and parts[1].lower() == "off":
                        client.set_auto_reconnect(False)
                    else:
                        client.set_auto_reconnect(True)
                else:
                    if not client.send(message):
                        logger.warning("Failed to send message, reconnecting...")
                        client.connect()

            except KeyboardInterrupt:
                break
            except Exception as e:
                logger.error(f"Error: {e}")

    finally:
        client.auto_reconnect = False  # Disable auto reconnect on exit
        client.disconnect()
        logger.info("Client terminated")


if __name__ == "__main__":
    main()
