import http.server
import socketserver
import ssl
import sys

PAGE_ROWS = 400


def build_page():
    rows = "".join(
        "<div class='row'>row %d: %s</div>\n" % (i, "lorem ipsum dolor sit amet " * 6)
        for i in range(PAGE_ROWS)
    )
    return (
        "<!doctype html><html><head><meta charset='utf-8'><title>osum tls</title>"
        "<style>body{font:18px sans-serif;margin:8px}#banner{background:#0a0;color:#fff;padding:12px}"
        ".row{border-bottom:1px solid #ccc}</style></head><body>"
        "<div id='banner'>TLS-OK</div><canvas id='c' width='300' height='100'></canvas>"
        "<script>var c=document.getElementById('c').getContext('2d');c.fillStyle='#c00';c.fillRect(10,10,100,50);"
        "var s=0;for(var i=0;i<200000;i++){s=(s+i*i)%1000003}"
        "document.getElementById('banner').textContent='TLS-OK '+s;</script>"
        + rows
        + "</body></html>"
    ).encode()


HANDSHAKE_TIMEOUT_S = 60


class Handler(http.server.BaseHTTPRequestHandler):
    page = build_page()

    def setup(self):
        self.request.settimeout(HANDSHAKE_TIMEOUT_S)
        self.request.do_handshake()
        super().setup()

    def do_GET(self):
        body = self.page if self.path.split("?")[0] in ("/", "/index.html") else b"not found"
        self.send_response(200 if body is self.page else 404)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
        sys.stdout.write("GET %s %d\n" % (self.path, len(body)))
        sys.stdout.flush()

    def log_message(self, fmt, *args):
        pass


class Server(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    tls_context = None

    def get_request(self):
        raw, addr = self.socket.accept()
        return self.tls_context.wrap_socket(raw, server_side=True, do_handshake_on_connect=False), addr


def main():
    cert, key, port_file = sys.argv[1], sys.argv[2], sys.argv[3]
    srv = Server(("0.0.0.0", 0), Handler)
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.load_cert_chain(cert, key)
    srv.tls_context = ctx
    with open(port_file, "w") as f:
        f.write(str(srv.server_address[1]))
    srv.serve_forever()


main()
