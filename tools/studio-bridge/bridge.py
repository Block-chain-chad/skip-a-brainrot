"""Studio <-> disk bridge (local only).

Run:  python tools/studio-bridge/bridge.py   (serves the folder it lives in on 127.0.0.1:8731)

GET  /<file>                serves a file from this folder (region scripts to splice).
POST /save?path=<abs path>  writes the request body (bytes, verbatim) to that path;
                            path must be under the repo's game-src mirror or this folder.

From an execute_luau chunk in Studio (Edit mode), flip HttpService.HttpEnabled on for the
call and restore it after -- the place ships with it OFF and must stay that way:

    local HS = game:GetService("HttpService")
    local was = HS.HttpEnabled; HS.HttpEnabled = true
    -- pull a region file into a splice:  HS:GetAsync("http://127.0.0.1:8731/<file>")
    -- push a live Source to its mirror:  HS:PostAsync("http://127.0.0.1:8731/save?path="
    --     .. HS:UrlEncode(absPath), inst.Source, Enum.HttpContentType.TextPlain, false)
    HS.HttpEnabled = was

Why: execute_luau results cap at ~100k characters and every byte returned goes through the
LLM context, so a 220 KB panel could only be mirrored in chunks. Pushing the Source from
Studio to disk is byte-exact and costs nothing; pulling region files avoids JSON-escaping
20 KB of Luau into a tool parameter. Whole-file rewrites over 200k chars still go through
ScriptEditorService:UpdateSourceAsync (execute_luau refuses a Source assignment that big).
"""
import os, sys, hashlib
from http.server import SimpleHTTPRequestHandler, HTTPServer
from urllib.parse import urlparse, parse_qs

HERE = os.path.abspath(os.path.dirname(os.path.abspath(__file__)))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
# writes land only under the repo's game-src mirror or the folder this script is served from
ALLOWED_ROOTS = [os.path.join(REPO, "game-src"), HERE]


class H(SimpleHTTPRequestHandler):
    def log_message(self, fmt, *args):
        sys.stderr.write("%s\n" % (fmt % args))

    def do_POST(self):
        u = urlparse(self.path)
        if u.path != "/save":
            self.send_response(404); self.end_headers(); return
        q = parse_qs(u.query)
        path = os.path.abspath(q.get("path", [""])[0])
        if not any(path.startswith(r + os.sep) for r in ALLOWED_ROOTS):
            self.send_response(403); self.end_headers(); self.wfile.write(b"path not allowed"); return
        n = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(n)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb") as f:
            f.write(body)
        digest = hashlib.sha1(body).hexdigest()
        out = ("saved %d bytes sha1=%s" % (len(body), digest)).encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(out)))
        self.end_headers()
        self.wfile.write(out)


if __name__ == "__main__":
    os.chdir(HERE)
    print("studio bridge on http://127.0.0.1:8731  (serving %s; writes under %s)" % (HERE, ", ".join(ALLOWED_ROOTS)))
    HTTPServer(("127.0.0.1", 8731), H).serve_forever()
