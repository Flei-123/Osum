#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
# tools/unterbau/tlssrv.py -- throw-away HTTPS server for the TLS stone probes (run.sh section 3d, STONES_NET=1).
#   tlssrv.py <port> <cert.pem> <key.pem> <docroot>
import functools, http.server, ssl, sys

port, cert, key, root = int(sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[4]
handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=root)
httpd = http.server.ThreadingHTTPServer(("127.0.0.1", port), handler)
ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
ctx.load_cert_chain(cert, key)
httpd.socket = ctx.wrap_socket(httpd.socket, server_side=True)
httpd.serve_forever()
