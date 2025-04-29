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


def get_local_ip():
    """Get the local IP address of this machine."""
    try:
        # Create a socket to determine the local IP
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        # Doesn't need to be reachable, just to determine the interface
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception as e:
        logger.error(f"Error getting local IP: {e}")
        # Fallback to localhost
        return "127.0.0.1"


class EthernetServer:
    def __init__(self, host="127.0.0.1", port=2345):
        self.host = host
        self.port = port
        self.server_socket = None
        self.client_socket = None
        self.client_address = None
        self.is_running = False
        self.receive_thread = None
        self.heartbeat_thread = None

    def start(self):
        """Start the server and listen for connections."""
        try:
            self.server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            self.server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            logger.info(f"Binding to {self.host}:{self.port}...")
            self.server_socket.bind((self.host, self.port))
            self.server_socket.listen(1)
            self.is_running = True
            logger.info(f"Server started on {self.host}:{self.port}")

            # Accept client connections
            self._accept_connections()

        except Exception as e:
            logger.error(f"Server error: {e}")
            self.close()

    def _accept_connections(self):
        """Accept incoming connections."""
        logger.info("Waiting for connections...")
        while self.is_running:
            try:
                self.server_socket.settimeout(
                    1
                )  # Short timeout to allow checking is_running
                self.client_socket, self.client_address = self.server_socket.accept()
                logger.info(f"✅ Client connected: {self.client_address}")

            # Start receive and heartbeat threads
            self.receive_thread = threading.Thread(target=self._receive_loop)
            self.heartbeat_thread = threading.Thread(target=self._heartbeat_loop)
            self.receive_thread.daemon = True
            self.heartbeat_thread.daemon = True
            self.receive_thread.start()
            self.heartbeat_thread.start()

                # Wait for the client to disconnect before accepting another
                self.receive_thread.join()
                logger.info("Client disconnected, waiting for new connections")

            except socket.timeout:
                continue
        except Exception as e:
                if self.is_running:
                    logger.error(f"Accept error: {e}")
                    time.sleep(1)  # Prevent rapid retry on error

    def _receive_loop(self):
        """Continuously receive data from the connected client."""
        self.client_socket.settimeout(1)  # 1 second timeout
        while self.is_running and self.client_socket:
            try:
                data = self.client_socket.recv(1024)
                if not data:
                    logger.info("Client closed connection")
                    break
                logger.info(f"Received: {data.decode('utf-8')}")

                # Echo back the data
                response = f"Echo: {data.decode('utf-8')}"
                self.send(response)

            except socket.timeout:
                continue
            except Exception as e:
                logger.error(f"Receive error: {e}")
                break

        # Clean up client connection
        if self.client_socket:
            self.client_socket.close()
            self.client_socket = None
            self.client_address = None

    def _heartbeat_loop(self):
        """Send periodic heartbeat messages."""
        while self.is_running and self.client_socket:
            try:
                self.send("server_heartbeat")
                time.sleep(5)  # Send heartbeat every 5 seconds
            except Exception:
                break

    def send(self, message):
        """Send data to the connected client."""
        if not self.client_socket:
            logger.error("No client connected")
            return

        try:
            self.client_socket.sendall(message.encode("utf-8"))
            logger.info(f"Sent: {message}")
        except Exception as e:
            logger.error(f"Send error: {e}")
            # Don't close the server, just the client connection
            if self.client_socket:
                self.client_socket.close()
                self.client_socket = None
                self.client_address = None

    def close(self):
        """Close the server."""
        self.is_running = False

        if self.client_socket:
            self.client_socket.close()
            self.client_socket = None

        if self.server_socket:
            self.server_socket.close()
            self.server_socket = None

        logger.info("Server closed")


def main():
    if len(sys.argv) > 1:
        port = int(sys.argv[1])
    else:
        port = 2345

    server = EthernetServer(port=port)

    try:
        server.start()

        # Keep the main thread alive for user input
        while server.is_running:
            try:
                # Get user input
                message = input("Enter message to send to client (or 'quit' to exit): ")
                if message.lower() == "quit":
                    break

                if server.client_socket:
                    server.send(message)
                else:
                    logger.info("No client connected. Message not sent.")

            except KeyboardInterrupt:
                break
            except Exception as e:
                logger.error(f"Error: {e}")

    finally:
        server.close()


if __name__ == "__main__":
    main()
