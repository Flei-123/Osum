import socket
import sys
import time

path, command = sys.argv[1], sys.argv[2]
client = socket.socket(socket.AF_UNIX)
client.connect(path)
client.settimeout(2)
try:
    client.recv(4096)
except socket.timeout:
    pass
client.sendall((command + "\n").encode())
time.sleep(0.5)
client.close()
