import os
from http.server import HTTPServer, BaseHTTPRequestHandler

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        env = os.environ.get("ENV_NAME", "unknown")
        version = os.environ.get("APP_VERSION", "v0.0.0")
        sha = os.environ.get("GIT_SHA", "local")

        html = f"""<!DOCTYPE html>
<html>
<head>
    <title>Mock App - {env.upper()}</title>
    <style>
        body {{ font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; padding: 3rem; background: #f8fafc; color: #1e293b; }}
        .card {{ background: white; border-radius: 8px; padding: 2rem; box-shadow: 0 4px 6px -1px rgb(0 0 0 / 0.1); max-width: 500px; margin: auto; }}
        h1 {{ margin-top: 0; color: #0284c7; }}
        .badge {{ display: inline-block; padding: 0.25rem 0.75rem; border-radius: 9999px; font-weight: bold; font-size: 0.875rem; background: #e0f2fe; color: #0369a1; }}
        .field {{ margin: 1rem 0; font-size: 1.1rem; }}
        .label {{ font-weight: 600; color: #64748b; font-size: 0.875rem; text-transform: uppercase; }}
        .val {{ font-family: monospace; font-size: 1.1rem; background: #f1f5f9; padding: 0.2rem 0.4rem; border-radius: 4px; }}
    </style>
</head>
<body>
    <div class="card">
        <span class="badge">{env.upper()} ENVIRONMENT</span>
        <h1>Mock Application</h1>
        <div class="field">
            <div class="label">App Version</div>
            <div class="val">{version}</div>
        </div>
        <div class="field">
            <div class="label">Git Commit SHA</div>
            <div class="val">{sha}</div>
        </div>
    </div>
</body>
</html>"""
        
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(html.encode("utf-8"))))
        self.end_headers()
        self.wfile.write(html.encode("utf-8"))

if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8080))
    server = HTTPServer(("0.0.0.0", port), Handler)
    print(f"Mock server running on port {port}")
    server.serve_forever()


#app change 888