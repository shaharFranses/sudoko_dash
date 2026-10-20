import http.server,sys,functools
class H(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy","same-origin")
        self.send_header("Cross-Origin-Embedder-Policy","require-corp")
        self.send_header("Cache-Control","no-store")
        super().end_headers()
port=int(sys.argv[1]);d=sys.argv[2]
http.server.ThreadingHTTPServer(("127.0.0.1",port),functools.partial(H,directory=d)).serve_forever()
