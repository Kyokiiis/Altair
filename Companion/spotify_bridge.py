"""Local Spotify companion: per-user OAuth PKCE, refresh, and unlink.

Account tokens stay on this computer. No client secret or hosted relay required.
"""
from __future__ import annotations

import argparse
import asyncio
import base64
import hmac
import hashlib
import json
import logging
import math
import os
from pathlib import Path
import secrets
import re
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit, parse_qs, urlencode
from urllib.request import Request, urlopen
from urllib.error import HTTPError, URLError
import webbrowser

LOG = logging.getLogger("altair.spotify")
MAX_BODY = 4096


def artwork_url(item):
    """Use Spotify's smallest cover of at least 64px; expose only its public CDN URL."""
    images=((item.get("album") or {}).get("images") or item.get("images") or [])
    choices=[]
    for image in images:
        url=image.get("url","")
        if not isinstance(url,str) or not re.fullmatch(r"https://i\.scdn\.co/image/[A-Za-z0-9]+",url): continue
        width=image.get("width") or 0
        if isinstance(width,(int,float)) and width>=64: choices.append((width,url))
    return min(choices)[1] if choices else ""


def protected_bytes(data, decrypt=False):
    """Protect account tokens for the current Windows user; restrictive file mode elsewhere."""
    if os.name != "nt": return data
    import ctypes
    from ctypes import wintypes
    class Blob(ctypes.Structure):
        _fields_ = [("size", wintypes.DWORD), ("data", ctypes.POINTER(ctypes.c_ubyte))]
    buffer = ctypes.create_string_buffer(data)
    source = Blob(len(data), ctypes.cast(buffer, ctypes.POINTER(ctypes.c_ubyte)))
    output = Blob()
    ctypes.windll.kernel32.LocalFree.argtypes = [ctypes.c_void_p]
    ctypes.windll.kernel32.LocalFree.restype = ctypes.c_void_p
    operation = ctypes.windll.crypt32.CryptUnprotectData if decrypt else ctypes.windll.crypt32.CryptProtectData
    if not operation(ctypes.byref(source), None, None, None, None, 1, ctypes.byref(output)):
        raise OSError("Windows could not protect the Spotify account tokens")
    try: return ctypes.string_at(output.data, output.size)
    finally: ctypes.windll.kernel32.LocalFree(output.data)


class TokenStore:
    def __init__(self, path): self.path = Path(path)

    def load(self):
        if not self.path.exists(): return None
        return json.loads(protected_bytes(self.path.read_bytes(), decrypt=True))

    def save(self, data):
        self.path.parent.mkdir(parents=True, exist_ok=True)
        temporary = self.path.with_suffix(".tmp")
        with open(temporary, "wb") as stream:
            os.chmod(temporary, 0o600)
            stream.write(protected_bytes(json.dumps(data).encode()))
        os.replace(temporary, self.path)

    def clear(self): self.path.unlink(missing_ok=True)


class WebSpotify:
    """Per-user PKCE OAuth. Only this companion ever receives account tokens."""
    def __init__(self, store, port):
        self.store, self.port = store, port
        self.lock = threading.RLock()
        self.tokens = None
        try: self.tokens = store.load()
        except (OSError, ValueError): LOG.warning("Stored Spotify link is unavailable; link again")
        self.pending = None
        self.stopping = False
        self.cooldown = 0
        self.state = {"connected": False, "linked": bool(self.tokens), "message": "Link Spotify in Altair Settings"}
        self.sampled_at = time.monotonic()

    @property
    def redirect(self): return f"http://127.0.0.1:{self.port}/callback"

    def begin_link(self, client_id):
        if not isinstance(client_id, str) or not re.fullmatch(r"[a-fA-F0-9]{32}", client_id):
            raise ValueError("Enter your Spotify developer app's 32-character Client ID in Settings")
        verifier, state = secrets.token_urlsafe(64), secrets.token_urlsafe(32)
        challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).rstrip(b"=").decode()
        with self.lock:
            self.pending = {"client_id": client_id, "verifier": verifier, "state": state, "expires": time.monotonic()+600}
        query = urlencode({"client_id": client_id, "response_type": "code", "redirect_uri": self.redirect,
                           "scope": "user-read-playback-state user-read-currently-playing user-modify-playback-state",
                           "state": state, "code_challenge_method": "S256", "code_challenge": challenge,
                           "show_dialog": "true"})
        url = "https://accounts.spotify.com/authorize?"+query
        webbrowser.open(url)
        return {"ok": True, "url": url, "message": "Finish linking in your browser"}

    def finish_link(self, query):
        with self.lock:
            pending = self.pending
            state = query.get("state", [""])[0]
            if not pending or pending["expires"] < time.monotonic() or not hmac.compare_digest(state, pending["state"]):
                raise ValueError("The Spotify link expired or its state did not match. Start Link Spotify again.")
            self.pending = None  # A callback is single-use, including a denied callback.
            if query.get("error"): raise ValueError("Spotify linking was cancelled")
            code = query.get("code", [""])[0]
            if not code: raise ValueError("Spotify returned no authorization code")
            tokens = self.exchange({"grant_type": "authorization_code", "code": code, "redirect_uri": self.redirect,
                                    "client_id": pending["client_id"], "code_verifier": pending["verifier"]})
            tokens.update(client_id=pending["client_id"], expires_at=time.time()+tokens.get("expires_in",3600))
            self.store.save(tokens); self.tokens = tokens
            self.state = {"connected": False, "linked": True, "message": "Linked. Start playback in Spotify."}

    @staticmethod
    def exchange(data):
        request = Request("https://accounts.spotify.com/api/token", data=urlencode(data).encode(),
                          headers={"Content-Type": "application/x-www-form-urlencoded"})
        try:
            with urlopen(request, timeout=8) as response: return json.load(response)
        except HTTPError:
            raise ValueError("Spotify rejected the authorization. Check Client ID and redirect URI, then link again.") from None

    def unlink(self):
        with self.lock:
            self.store.clear()
            self.tokens, self.pending = None, None
            self.state = {"connected": False, "linked": False, "message": "Spotify unlinked"}
        return {"ok": True}

    def access_token(self):
        if not self.tokens: raise ValueError("Link Spotify in Settings first")
        if self.tokens.get("expires_at",0) < time.time()+60:
            if not self.tokens.get("refresh_token"): raise ValueError("Link Spotify again to renew access")
            fresh = self.exchange({"grant_type":"refresh_token", "refresh_token":self.tokens["refresh_token"],
                                   "client_id":self.tokens["client_id"]})
            fresh["refresh_token"] = fresh.get("refresh_token",self.tokens["refresh_token"])
            self.tokens.update(fresh, expires_at=time.time()+fresh.get("expires_in",3600))
            self.store.save(self.tokens)
        return self.tokens["access_token"]

    def api(self, method, path, data=None):
        if time.monotonic() < self.cooldown: raise ValueError("Spotify is rate limiting requests; retry shortly")
        for attempt in range(2):
            request = Request("https://api.spotify.com/v1/"+path, method=method,
                              data=json.dumps(data).encode() if data is not None else None,
                              headers={"Authorization":"Bearer "+self.access_token(), "Content-Type":"application/json"})
            try:
                with urlopen(request, timeout=5) as response:
                    if response.status == 204: return None
                    body=response.read().strip()
                    # Playback endpoints may acknowledge with an empty or plain-text
                    # success body. Only data requests require a JSON response.
                    return json.loads(body) if method=="GET" and body else None
            except HTTPError as exc:
                if exc.code == 401 and attempt == 0:
                    self.tokens["expires_at"] = 0; continue
                if exc.code == 429:
                    self.cooldown=time.monotonic()+max(2,min(300,int(exc.headers.get("Retry-After","10"))))
                    raise ValueError("Spotify is rate limiting requests; retry shortly") from None
                if exc.code == 403: raise ValueError("Spotify denied access. Check Premium, app access, and authorization scopes.") from None
                if exc.code == 404: raise ValueError("Start Spotify playback on a device first") from None
                raise ValueError("Spotify request failed; try again shortly") from None

    def refresh_state(self):
        with self.lock:
            if not self.tokens or time.monotonic()<self.cooldown: return
            try:
                data=self.api("GET","me/player")
                item=(data or {}).get("item") or {}
                artist=", ".join(a.get("name","") for a in (item.get("artists") or []))
                device=(data or {}).get("device") or {}
                disallows=((data or {}).get("actions") or {}).get("disallows") or {}
                self.state={"connected":True,"linked":True,"title":item.get("name","Nothing playing"),"artist":artist,
                            "artwork":artwork_url(item),
                            "duration":(item.get("duration_ms") or 0)/1000,"progress":((data or {}).get("progress_ms") or 0)/1000,
                            "playing":(data or {}).get("is_playing",False),
                            "volume":(device.get("volume_percent") or 0)/100,
                            "controls":{"toggle":bool(device) and not disallows.get("pausing" if (data or {}).get("is_playing") else "resuming",False),
                                        "next":bool(device) and not disallows.get("skipping_next",False),
                                        "previous":bool(device) and not disallows.get("skipping_prev",False),
                                        "seek":bool(item) and not disallows.get("seeking",False),
                                        "volume":bool(device) and device.get("supports_volume",True) and not device.get("is_restricted",False)}}
                self.sampled_at=time.monotonic()
            except (ValueError, URLError, TimeoutError) as exc:
                self.state={"connected":False,"linked":bool(self.tokens),"message":str(exc)[:180]}
                self.cooldown=max(self.cooldown,time.monotonic()+5)

    def snapshot(self):
        with self.lock:
            state=dict(self.state)
            if state.get("playing"):
                state["progress"]=min(state["duration"],state["progress"]+max(0,time.monotonic()-self.sampled_at))
            return state

    def dispatch(self, action, value):
        with self.lock:
            started=time.monotonic()
            position = self.snapshot().get("progress",0)
            if action == "seek": value = number(value,0,self.state.get("duration",0))
            if action == "volume": value = number(value,0,1)
            if action=="toggle": self.api("PUT","me/player/"+("pause" if self.state.get("playing") else "play"))
            elif action in {"next","previous"}: self.api("POST","me/player/"+action)
            elif action=="seek": self.api("PUT","me/player/seek?position_ms="+str(int(number(value,0,self.state.get("duration",0))*1000)))
            elif action=="volume": self.api("PUT","me/player/volume?volume_percent="+str(round(number(value,0,1)*100)))
            else: raise ValueError("Unsupported playback control")
            # Invalidate optimistically without a second API GET for every command.
            if action=="toggle":
                self.state["progress"]=position
                self.state["playing"]=not self.state.get("playing",False)
            if action=="seek": self.state["progress"]=value
            if action=="volume": self.state["volume"]=value
            if action=="volume":
                self.state["progress"]=min(self.state.get("duration",0),position+(time.monotonic()-started if self.state.get("playing") else 0))
            self.sampled_at=time.monotonic()

    async def run(self):
        while not self.stopping:
            await asyncio.to_thread(self.refresh_state)
            await asyncio.sleep(2)


def number(value, low, high):
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
        raise ValueError("Expected a finite number")
    return max(low, min(high, value))


class Server(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True

    def __init__(self, port, media, key):
        self.media, self.key = media, key
        super().__init__(("127.0.0.1", port), Handler)


class Handler(BaseHTTPRequestHandler):
    server_version = "AltairSpotify/1"

    def log_message(self, *_):
        pass  # Never log auth headers, metadata, or URLs.

    def respond(self, status, data):
        body = json.dumps(data, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        self.wfile.write(body)

    def authorized(self):
        port = self.server.server_address[1]
        if self.headers.get("Host") not in {f"127.0.0.1:{port}", f"localhost:{port}"}:
            self.respond(403, {"error": "Invalid loopback host"}); return False
        # Browser origins are unnecessary for executor requests and are rejected.
        if self.headers.get("Origin") or self.headers.get("Sec-Fetch-Site"):
            self.respond(403, {"error": "Browser requests are not supported"}); return False
        supplied = self.headers.get("Authorization", "")
        if not hmac.compare_digest(supplied, "Bearer " + self.server.key):
            self.respond(401, {"error": "Paste the bridge key into Altair Settings"}); return False
        return True

    def do_GET(self):
        if urlsplit(self.path).path == "/callback":
            if self.headers.get("Host") != f"127.0.0.1:{self.server.server_address[1]}":
                self.respond(403, {"error":"Invalid callback host"}); return
            try:
                self.server.media.finish_link(parse_qs(urlsplit(self.path).query))
                self.respond(200,{"connected":True,"message":"Spotify linked. Return to Altair; you can close this tab."})
            except (ValueError, AttributeError) as exc: self.respond(400,{"error":str(exc)})
            except Exception: self.respond(503,{"error":"Could not complete Spotify linking. Start Link Spotify again."})
            return
        if not self.authorized(): return
        path = urlsplit(self.path).path
        if path == "/v1/state": self.respond(200, self.server.media.snapshot())
        elif path == "/v1/health": self.respond(200, {"ok": True, "version": 1})
        else: self.respond(404, {"error": "Not found"})

    def do_POST(self):
        if not self.authorized(): return
        if self.path not in {"/v1/control","/v1/link","/v1/unlink"}: self.respond(404, {"error": "Not found"}); return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            if not 0 < length <= MAX_BODY:
                raise ValueError("Invalid request size")
            self.connection.settimeout(3)
            raw = self.rfile.read(length)
            if len(raw) != length: raise ValueError("Incomplete request")
            data = json.loads(raw)
            if not isinstance(data,dict): raise ValueError("Expected a JSON object")
            if self.path == "/v1/link": self.respond(200,self.server.media.begin_link(data.get("clientId")));return
            if self.path == "/v1/unlink": self.respond(200,self.server.media.unlink());return
            if not isinstance(data, dict) or data.get("action") not in {"toggle", "next", "previous", "seek", "volume"}:
                raise ValueError("Unsupported playback control")
            self.server.media.dispatch(data["action"], data.get("value"))
            self.respond(200, {"ok": True})
        except (ValueError, TypeError, TimeoutError, json.JSONDecodeError) as exc:
            self.respond(400, {"error": str(exc)[:160]})
        except Exception:
            LOG.warning("Spotify operation failed; retry or check the connection")
            self.respond(503, {"error": "Spotify could not complete the control"})


def load_key(path):
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        key = path.read_text(encoding="ascii").strip()
        if len(key) >= 32: return key
    key = secrets.token_urlsafe(32)
    path.write_text(key, encoding="ascii")
    return key


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=43827)
    args = parser.parse_args()
    if not 1024 <= args.port <= 65535: parser.error("Port must be between 1024 and 65535")
    path = Path(os.environ.get("LOCALAPPDATA", Path.home())) / "Altair" / "Spotify" / "bridge.key"
    key = load_key(path)
    media = WebSpotify(TokenStore(path.with_name("account.tokens")),args.port)
    server = Server(args.port, media, key)
    logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
    print(f"Altair Spotify companion: http://127.0.0.1:{args.port}\n"
          f"In Altair Settings, enter your developer app's Client ID and enable Spotify Connection.\n"
          f"Register redirect URI http://127.0.0.1:{args.port}/callback, then click Link Spotify.\n"
          f"Paste this bridge key into Spotify Bridge Key:\n{key}\n"
          f"Keep this window running. Ctrl+C disconnects. Key file: {path}", flush=True)
    thread = threading.Thread(target=server.serve_forever, name="AltairSpotifyHTTP", daemon=True)
    thread.start()
    try:
        asyncio.run(media.run())
    except KeyboardInterrupt:
        pass
    finally:
        media.stopping = True
        server.shutdown(); server.server_close()


if __name__ == "__main__":
    main()
