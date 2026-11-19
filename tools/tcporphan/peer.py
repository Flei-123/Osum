import socket
import sys
import threading
import time

mode = sys.argv[1]
port = int(sys.argv[2])
server = socket.socket()
server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
server.bind(("0.0.0.0", port))
server.listen(64)
held = []


def serve(conn):
    if mode == "closing":
        conn.close()
        return
    held.append(conn)
    time.sleep(3600)


while True:
    conn, _ = server.accept()
    threading.Thread(target=serve, args=(conn,), daemon=True).start()
