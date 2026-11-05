"""Local Spotify companion: per-user OAuth PKCE, refresh, and unlink.

Account tokens stay on this computer. No client secret or hosted relay required.
"""
from __future__ import annotations

import argparse
import asyncio
import base64
import hmac
import io
import colorsys
import hashlib
import json
import logging
import math
import os
from pathlib import Path
import secrets
import shutil
import subprocess
import sys
import re
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit, parse_qs, urlencode
from urllib.request import Request, urlopen
from urllib.error import HTTPError
import webbrowser
from datetime import datetime, timezone

sys.path.insert(0,str(Path(os.environ.get("LOCALAPPDATA",Path.home()))/"Altair/Spotify/dependencies"))

LOG = logging.getLogger("altair.spotify")
MAX_BODY = 4096
MAX_ARTWORK_BYTES = 1_048_576
MAX_ARTWORK_PIXELS = 16_000_000
ARTWORK_URL = re.compile(r"https://i\.scdn\.co/image/[A-Za-z0-9]+")
CONTROL_ACTIONS = frozenset({"toggle", "next", "previous", "seek", "volume"})


def artwork_palette(data):
    """Sample a tiny cover once per track; decoding stays out of Roblox's frame loop."""
    if not data or len(data)>MAX_ARTWORK_BYTES:
        return None
    try:
        from PIL import Image
    except ImportError:
        return None
    try:
        with Image.open(io.BytesIO(data)) as image:
            if image.width*image.height>MAX_ARTWORK_PIXELS:
                return None
            image.draft("RGB",(32,32))
            image.thumbnail((32,32))
            image=image.convert("RGB").quantize(colors=8).convert("RGB")
            samples=image.getcolors(1024) or []
        def score(sample):
            count,rgb=sample
            _,s,v=colorsys.rgb_to_hsv(*(x/255 for x in rgb))
            return count*(.3+.7*s) if .12<v<.98 else count*.08
        samples.sort(key=score,reverse=True)
        if not samples:
            return None
        first=samples[0][1]
        second=next((rgb for _,rgb in samples[1:] if sum((a-b)**2 for a,b in zip(first,rgb))>2400),first)
        return [list(first),list(second)]
    except (OSError,ValueError,Image.DecompressionBombError):
        return None


def artwork_url(item):
    """Use Spotify's smallest cover of at least 64px; expose only its public CDN URL."""
    images=((item.get("album") or {}).get("images") or item.get("images") or [])
    choices=[]
    for image in images:
        url=image.get("url","")
        if not isinstance(url,str) or not ARTWORK_URL.fullmatch(url): continue
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


class AuthorizationRequired(ValueError):
    pass



class DesktopSpotify:
    """Local Windows Spotify session. Never enumerates other apps' media metadata."""
    def __init__(self):
        self.manager=None;self.session=None;self.state=None;self.identity=None;self.artwork_id="";self.artwork_bytes=b"";self.palette=None

    def audio_sessions(self):
        # Per-application mixer only; never write the device/master volume.
        now=time.monotonic()
        if now>=getattr(self,"audio_refresh",0):
            from pycaw.pycaw import AudioUtilities
            matches=[]
            for session in AudioUtilities.GetAllSessions():
                try:
                    if session.Process and session.Process.name().lower()=="spotify.exe":
                        matches.append(session.SimpleAudioVolume)
                except Exception:
                    continue
            self.audio_volumes=matches;self.audio_refresh=now+2
        return getattr(self,"audio_volumes",[])

    def read_volume(self):
        try:
            sessions=self.audio_sessions()
            return max((0.0 if x.GetMute() else float(x.GetMasterVolume()) for x in sessions),default=None)
        except Exception:
            self.audio_refresh=0
            return None

    def set_volume(self,value):
        value=number(value,0,1)
        try:
            sessions=self.audio_sessions()
            if not sessions: raise ValueError("Start Spotify playback to create its audio session")
            for session in sessions:
                session.SetMasterVolume(value,None)
                if value>0: session.SetMute(0,None)
        except Exception:
            self.audio_refresh=0
            raise
        return True

    async def read(self):
        if not getattr(self,"apartment_initialized",False):
            # Background asyncio has no GUI message loop. Use a multithreaded
            # apartment so Windows delivers session/track changes without one.
            from winrt.runtime import init_apartment,ApartmentType
            sys.coinit_flags=0
            init_apartment(ApartmentType.MULTI_THREADED)
            self.apartment_initialized=True
        from winrt.windows.media.control import GlobalSystemMediaTransportControlsSessionManager
        if self.manager is None or time.monotonic()-getattr(self,"manager_refreshed",0)>15:
            self.manager=await GlobalSystemMediaTransportControlsSessionManager.request_async()
            self.manager_refreshed=time.monotonic()
        self.session=next((x for x in self.manager.get_sessions() if "spotify" in x.source_app_user_model_id.lower()),None)
        if self.session is None: self.state=None;return None
        properties=await self.session.try_get_media_properties_async()
        playback=self.session.get_playback_info();timeline=self.session.get_timeline_properties();controls=playback.controls
        identity=(properties.title,properties.artist,properties.album_title)
        if identity!=self.identity:
            self.identity=identity;self.artwork_id="";self.artwork_bytes=b"";self.palette=None
            if properties.thumbnail:
                try:
                    from winrt.windows.storage.streams import DataReader
                    stream=await properties.thumbnail.open_read_async()
                    try:
                        if 0<stream.size<=MAX_ARTWORK_BYTES:
                            reader=DataReader(stream)
                            try:
                                await reader.load_async(stream.size);data=bytearray(stream.size);reader.read_bytes(data)
                                if data[:2]==b"\xff\xd8"or data[:8]==b"\x89PNG\r\n\x1a\n":
                                    self.artwork_bytes=bytes(data);self.artwork_id=hashlib.sha256(data).hexdigest()
                                    self.palette=artwork_palette(self.artwork_bytes)
                            finally: reader.detach_stream();reader.close()
                    finally: stream.close()
                except Exception: LOG.warning("Local Spotify cover unavailable; playback remains connected")
        playing=int(playback.playback_status)==4
        duration=max(0,timeline.end_time.total_seconds()-timeline.start_time.total_seconds())
        position=max(0,timeline.position.total_seconds()-timeline.start_time.total_seconds())
        if playing:
            try: position+=max(0,(datetime.now(timezone.utc)-timeline.last_updated_time).total_seconds())
            except (TypeError,AttributeError): pass
        volume=self.read_volume()
        self.state={"connected":True,"linked":True,"available":True,"status":"ready","source":"desktop","volume":volume if volume is not None else 0,
                    "title":properties.title,"artist":properties.artist,"duration":duration,"progress":min(duration,position),
                    "playing":playing,"artwork":"altair-desktop:"+self.artwork_id if self.artwork_id else "",
                    "palette":self.palette,
                    "controls":{"toggle":bool(controls.is_play_pause_toggle_enabled),"next":bool(controls.is_next_enabled),
                                "previous":bool(controls.is_previous_enabled),"seek":bool(controls.is_playback_position_enabled),"volume":volume is not None}}
        return dict(self.state)

    async def control(self,action,value=None):
        if action=="volume": return self.set_volume(value)
        if self.session is None: raise ValueError("Open Spotify on this computer first")
        if action=="toggle": result=await self.session.try_toggle_play_pause_async()
        elif action=="next": result=await self.session.try_skip_next_async()
        elif action=="previous": result=await self.session.try_skip_previous_async()
        elif action=="seek": result=await self.session.try_change_playback_position_async(round(number(value,0,(self.state or{}).get("duration",0))*10000000))
        else: raise ValueError("This control is unavailable for desktop playback")
        if not result: raise ValueError("Spotify could not apply that playback control")


class WebSpotify:
    """Per-user PKCE OAuth. Only this companion ever receives account tokens."""
    def __init__(self, store, port):
        self.store, self.port = store, port
        self.lock = threading.RLock()
        self.state_lock = threading.RLock()
        self.needs_save = False
        self.desktop=DesktopSpotify();self.loop=None;self.web_available=False;self.last_client_seen=time.monotonic()
        self.tokens = None
        try: self.tokens = store.load()
        except (OSError, ValueError): LOG.warning("Stored Spotify link is unavailable; link again")
        self.pending = None
        self.stopping = False
        self.cooldown = 0
        self.reauth_required = False
        self.state = {"connected": bool(self.tokens), "linked": bool(self.tokens), "available": False, "status": "reconnecting" if self.tokens else "unlinked", "message": "Restoring saved Spotify link" if self.tokens else "Connect Spotify in Altair Settings"}
        self.sampled_at = time.monotonic()

    def publish(self, state, sampled_at=None):
        with self.state_lock:
            # Progress and its clock are one sample, including cached retries.
            self.state = dict(state)
            self.sampled_at = time.monotonic() if sampled_at is None else sampled_at

    def cover_palette(self, url):
        if not isinstance(url,str) or not ARTWORK_URL.fullmatch(url):
            return None
        cache=getattr(self,"palette_cache",None)
        if cache is None:
            self.palette_cache=cache={}
        if url not in cache:
            if len(cache)>=8:
                cache.pop(next(iter(cache)))
            try:
                # Public cover request: never forward Spotify account credentials.
                with urlopen(Request(url,headers={"Accept":"image/*"}),timeout=2) as response:
                    cache[url]=artwork_palette(response.read(MAX_ARTWORK_BYTES+1))
            except (OSError,ValueError):
                cache[url]=None
        return cache[url]

    def resume_or_link(self, client_id):
        with self.lock:
            self.last_client_seen=time.monotonic()
            client_id = client_id.strip() if isinstance(client_id, str) else client_id
            if client_id and (not self.tokens or self.tokens.get("mode")=="desktop"
                              or client_id != self.tokens.get("client_id") or self.reauth_required):
                return self.begin_link(client_id)
            if not self.tokens and not client_id and (self.desktop.state or os.name=="nt"):
                tokens={"mode":"desktop"};self.store.save(tokens);self.tokens=tokens
                self.publish(dict(self.desktop.state)if self.desktop.state else {"connected":True,"linked":True,"available":False,"source":"desktop","playing":False,"status":"waiting_for_spotify","message":"Open Spotify desktop and start playback; the connection is saved"})
            if self.tokens and not self.reauth_required:
                return {"ok": True, "linked": True, "message": "Saved Spotify link restored"}
            return self.begin_link(client_id or (self.tokens or {}).get("client_id"))

    @property
    def redirect(self): return f"http://127.0.0.1:{self.port}/callback"

    def begin_link(self, client_id):
        if not isinstance(client_id, str) or not re.fullmatch(r"[a-fA-F0-9]{32}", client_id):
            raise ValueError("Enter your Spotify developer app's 32-character Client ID in Settings")
        with self.lock:
            if (self.pending and self.pending["client_id"] == client_id
                    and self.pending["expires"] > time.monotonic() and self.pending.get("url")):
                # Reopen a closed browser without invalidating its approval.
                if time.monotonic() - self.pending.get("opened_at", 0) >= 5:
                    webbrowser.open(self.pending["url"])
                    self.pending["opened_at"] = time.monotonic()
                return {"ok": True, "url": self.pending["url"], "message": "Finish linking in your browser"}
            verifier, state = secrets.token_urlsafe(64), secrets.token_urlsafe(32)
            challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).rstrip(b"=").decode()
            query = urlencode({"client_id": client_id, "response_type": "code", "redirect_uri": self.redirect,
                               "scope": "user-read-playback-state user-read-currently-playing user-modify-playback-state",
                               "state": state, "code_challenge_method": "S256", "code_challenge": challenge,
                               "show_dialog": "true"})
            url = "https://accounts.spotify.com/authorize?"+query
            self.pending = {"client_id": client_id, "verifier": verifier, "state": state,
                            "expires": time.monotonic()+600, "url": url, "opened_at": time.monotonic()}
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
            if getattr(self,"bridge_key",None):
                try: publish_executor_connection(self.port,self.bridge_key,tokens["client_id"])
                except OSError: pass
            self.cooldown=0
            self.reauth_required=False
            self.publish({"connected": True, "linked": True, "available": False, "status": "reconnecting", "message": "Linked. Start playback in Spotify."})

    @staticmethod
    def exchange(data):
        request = Request("https://accounts.spotify.com/api/token", data=urlencode(data).encode(),
                          headers={"Content-Type": "application/x-www-form-urlencoded"})
        try:
            with urlopen(request, timeout=8) as response: return json.load(response)
        except HTTPError as exc:
            try: code=json.loads(exc.read(MAX_BODY)).get("error")
            except (ValueError, OSError): code=None
            if code in {"invalid_grant", "invalid_client"}:
                raise AuthorizationRequired("Spotify requires browser approval again") from None
            raise ValueError("Spotify authorization is temporarily unavailable; retry shortly") from None

    def unlink(self):
        with self.lock:
            self.store.clear()
            self.tokens, self.pending = None, None
            self.reauth_required=False
            self.publish({"connected": False, "linked": False, "available": False, "status": "unlinked", "message": "Spotify unlinked"})
        return {"ok": True}

    def access_token(self):
        if not self.tokens: raise ValueError("Link Spotify in Settings first")
        if self.tokens.get("expires_at",0) < time.time()+60:
            if not self.tokens.get("refresh_token"): raise AuthorizationRequired("Spotify requires browser approval again")
            fresh = self.exchange({"grant_type":"refresh_token", "refresh_token":self.tokens["refresh_token"],
                                   "client_id":self.tokens["client_id"]})
            fresh["refresh_token"] = fresh.get("refresh_token",self.tokens["refresh_token"])
            self.tokens.update(fresh, expires_at=time.time()+fresh.get("expires_in",3600))
            try: self.store.save(self.tokens); self.needs_save=False
            except OSError: self.needs_save=True; LOG.warning("Saving refreshed Spotify access will be retried")
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
                if exc.code == 401: raise AuthorizationRequired("Spotify requires browser approval again") from None
                if exc.code == 429:
                    try: delay=max(2,int(exc.headers.get("Retry-After","30")))
                    except (TypeError,ValueError): delay=30
                    self.cooldown=time.monotonic()+delay
                    raise ValueError("Spotify is rate limiting requests; retry shortly") from None
                if exc.code == 403: raise ValueError("Spotify denied access. Check Premium, app access, and authorization scopes.") from None
                if exc.code == 404: raise ValueError("Start Spotify playback on a device first") from None
                raise ValueError("Spotify request failed; try again shortly") from None

    def refresh_state(self):
        with self.lock:
            if not self.tokens or self.tokens.get("mode")=="desktop"or time.monotonic()<self.cooldown or self.reauth_required: return
            try:
                if self.needs_save:
                    try: self.store.save(self.tokens); self.needs_save=False
                    except OSError: pass
                playback=self.api("GET","me/player") or {}
                sampled_at=time.monotonic()
                item=playback.get("item") or {}
                artist=", ".join(a.get("name","") for a in (item.get("artists") or []))
                device=playback.get("device") or {}
                disallows=(playback.get("actions") or {}).get("disallows") or {}
                state={"connected":True,"linked":True,"available":True,"status":"ready","title":item.get("name","Nothing playing"),"artist":artist,
                            "artwork":artwork_url(item),
                            "duration":(item.get("duration_ms") or 0)/1000,"progress":(playback.get("progress_ms") or 0)/1000,
                            "playing":playback.get("is_playing",False),
                            "volume":(device.get("volume_percent") or 0)/100,
                            "controls":{"toggle":bool(device) and not disallows.get("pausing" if playback.get("is_playing") else "resuming",False),
                                        "next":bool(device) and not disallows.get("skipping_next",False),
                                        "previous":bool(device) and not disallows.get("skipping_prev",False),
                                        "seek":bool(item) and not disallows.get("seeking",False),
                                        "volume":bool(device) and device.get("supports_volume",True) and not device.get("is_restricted",False)}}
                state["source"]="web"
                state["palette"]=self.cover_palette(state["artwork"])
                with self.state_lock:
                    # Matching titles do not identify Spotify's active device.
                    # Commit Web authority with its sample, not before/after it.
                    self.web_available=True
                    self.publish(state,sampled_at)
            except (ValueError, OSError) as exc:
                with self.state_lock:
                    self.web_available=False
                    state=self.snapshot()
                    reauth=isinstance(exc,AuthorizationRequired)
                    self.reauth_required=reauth
                    if state.get("source")=="desktop" and self.desktop.state:
                        self.cooldown=max(self.cooldown,time.monotonic()+5);return
                    state.update(connected=bool(self.tokens) and not reauth,linked=bool(self.tokens),available=False,
                                 status="authorization_required" if reauth else "reconnecting",reauth_required=reauth,
                                 stale=True,message=str(exc)[:180])
                    self.publish(state)
                    self.cooldown=max(self.cooldown,time.monotonic()+5)
            except Exception:
                # A malformed response/artwork decoding failure is not proof of
                # expired approval. Still stop presenting old Web data as fresh.
                # The existing main lock keeps this failure on the same link.
                with self.state_lock:
                    self.web_available=False
                    self.cooldown=max(self.cooldown,time.monotonic()+5)
                    if self.tokens and self.tokens.get("mode")!="desktop":
                        state=self.snapshot()
                        if not (state.get("source")=="desktop" and self.desktop.state):
                            state.update(connected=not self.reauth_required,linked=True,available=False,
                                         stale=True,status="reconnecting",
                                         message="Spotify playback is reconnecting; the saved link is retained")
                            self.publish(state)
                raise  # The background loop logs only its fixed, redacted warning.

    def snapshot(self):
        # Never wait for upstream network I/O to serve the local status endpoint.
        with self.state_lock:
            state=dict(self.state)
            state["retry_after"]=max(0,round(self.cooldown-time.monotonic(),1))
            if state.get("source")=="desktop":
                state["web_retry_after"]=state["retry_after"];state["retry_after"]=0
            state["web_reauth_required"]=self.reauth_required
            if state.get("playing"):
                state["progress"]=min(state["duration"],state["progress"]+max(0,time.monotonic()-self.sampled_at))
            return state

    def _control_desktop(self, action, value):
        asyncio.run_coroutine_threadsafe(self.desktop.control(action,value),self.loop).result(timeout=4)

    def _publish_control(self, action, value, selected_state):
        with self.state_lock:
            # A command can finish after a new Web/desktop sample or unlink.
            # Never decorate that newer observation with the old command.
            if self.state is not selected_state: return
            state=self.snapshot()
            if action=="toggle": state["playing"]=not state.get("playing",False)
            elif action=="volume": state["volume"]=number(value,0,1)
            elif action=="seek": state["progress"]=number(value,0,state.get("duration",0))
            self.publish(state)

    def dispatch(self, action, value):
        with self.state_lock:
            snapshot=self.snapshot();selected_state=self.state
        if snapshot.get("source")=="desktop" and self.loop:
            # Do not queue local media keys behind a slow OAuth/network state poll.
            self._control_desktop(action,value)
            self.last_control_at=time.monotonic()
            self._publish_control(action,value,selected_state)
            return
        with self.lock:
            with self.state_lock:
                snapshot=self.snapshot();selected_state=self.state
            if snapshot.get("source")=="desktop"and self.loop:
                self._control_desktop(action,value)
                self.last_control_at=time.monotonic()
                self._publish_control(action,value,selected_state)
                return
            if action == "seek": value = number(value,0,snapshot.get("duration",0))
            if action == "volume": value = number(value,0,1)
            if action=="toggle": self.api("PUT","me/player/"+("pause" if snapshot.get("playing") else "play"))
            elif action in {"next","previous"}: self.api("POST","me/player/"+action)
            elif action=="seek": self.api("PUT","me/player/seek?position_ms="+str(int(value*1000)))
            elif action=="volume": self.api("PUT","me/player/volume?volume_percent="+str(round(number(value,0,1)*100)))
            else: raise ValueError("Unsupported playback control")
            # Invalidate optimistically without a second API GET for every command.
            self._publish_control(action,value,selected_state)

    async def run(self):
        self.loop=asyncio.get_running_loop()
        async def web_updates():
            while not self.stopping:
                if time.monotonic()-self.last_client_seen<20:
                    try: await asyncio.to_thread(self.refresh_state)
                    except Exception:
                        LOG.warning("Spotify update failed; the saved link is retained")
                        # refresh_state commits its failure/backoff before it
                        # releases the link lock. Do not delay a newer link here.
                await asyncio.sleep(max(3,min(60,self.cooldown-time.monotonic())))
        web=asyncio.create_task(web_updates())
        try:
            while not self.stopping:
                if os.name=="nt"and time.monotonic()-self.last_client_seen<20:
                    try:
                        state=await asyncio.wait_for(self.desktop.read(),timeout=5)
                        with self.state_lock:
                            # Re-evaluate after the await; Web may have recovered
                            # while Windows was reading an old local session.
                            prefer_local=self.tokens and (self.tokens.get("mode")=="desktop" or not self.web_available)
                            if state and prefer_local:
                                self.publish(state)
                            elif not state and prefer_local and self.state.get("source")=="desktop":
                                self.publish({"connected":True,"linked":True,"available":False,"playing":False,"status":"waiting_for_spotify","source":"desktop","message":"Open Spotify on this computer; the account remains linked"})
                    except Exception:
                        # A dead Windows session/thumbnail must not freeze cached playback forever.
                        self.desktop.manager=None;self.desktop.session=None;self.desktop.state=None
                        self.desktop.audio_refresh=0
                        with self.state_lock:
                            if self.tokens and (self.tokens.get("mode")=="desktop" or not self.web_available):
                                state=self.snapshot()
                                state.update(linked=True,connected=True,available=False,stale=True,status="reconnecting",message="Desktop playback is reconnecting; the saved link is retained")
                                self.publish(state)
                await asyncio.sleep(.2 if time.monotonic()-getattr(self,"last_control_at",0)<2 else 1)
        finally:
            web.cancel()
            try: await web
            except asyncio.CancelledError: pass


def number(value, low, high):
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
        raise ValueError("Expected a finite number")
    return max(low, min(high, value))


class Server(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True

    def __init__(self, port, media, key):
        self.media, self.key = media, key
        media.bridge_key=key
        super().__init__(("127.0.0.1", port), Handler)


class Handler(BaseHTTPRequestHandler):
    server_version = "AltairSpotify/1"

    def log_message(self, *_):
        pass  # Never log auth headers, metadata, or URLs.

    def _respond_bytes(self, status: int, body: bytes, content_type: str, *, nosniff: bool = False) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        if nosniff: self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        self.wfile.write(body)

    def respond(self, status, data):
        body = json.dumps(data, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        self._respond_bytes(status, body, "application/json; charset=utf-8", nosniff=True)

    def authorized(self):
        port = self.server.server_address[1]
        if self.headers.get("Host") not in {f"127.0.0.1:{port}", f"localhost:{port}"}:
            self.respond(403, {"error": "Invalid loopback host"}); return False
        # Browser origins are unnecessary for executor requests and are rejected.
        if self.headers.get("Origin") or self.headers.get("Sec-Fetch-Site"):
            self.respond(403, {"error": "Browser requests are not supported"}); return False
        supplied = self.headers.get("Authorization", "")
        if not isinstance(supplied, str) or not supplied.isascii() or not hmac.compare_digest(supplied, "Bearer " + self.server.key):
            self.respond(401, {"error": "Paste the bridge key into Altair Settings"}); return False
        return True

    def _request_url(self):
        try:
            return urlsplit(self.path)
        except (TypeError, ValueError):
            self.respond(400, {"error": "Malformed request target"})
            return None

    def do_GET(self):
        url = self._request_url()
        if url is None: return
        if url.path == "/callback":
            if self.headers.get("Host") != f"127.0.0.1:{self.server.server_address[1]}":
                self.respond(403, {"error":"Invalid callback host"}); return
            try:
                self.server.media.finish_link(parse_qs(url.query))
                self.respond(200,{"connected":True,"message":"Spotify linked. Return to Altair; you can close this tab."})
            except (ValueError, AttributeError) as exc: self.respond(400,{"error":str(exc)})
            except Exception: self.respond(503,{"error":"Could not complete Spotify linking. Start Link Spotify again."})
            return
        if not self.authorized(): return
        path = url.path
        if path == "/v1/state":
            self.server.media.last_client_seen=time.monotonic()
            self.respond(200, self.server.media.snapshot())
        elif path.startswith("/v1/artwork/"):
            desktop=self.server.media.desktop
            if not desktop.artwork_id or path.rsplit("/",1)[-1]!=desktop.artwork_id: self.respond(404,{"error":"Cover changed"});return
            data=desktop.artwork_bytes
            self._respond_bytes(200,data,"image/png"if data[:8]==b"\x89PNG\r\n\x1a\n"else"image/jpeg")
        elif path == "/v1/health": self.respond(200, {"ok": True, "version": 1})
        else: self.respond(404, {"error": "Not found"})

    def do_POST(self):
        if not self.authorized(): return
        if self._request_url() is None: return
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
            if self.path == "/v1/link": self.respond(200,self.server.media.resume_or_link(data.get("clientId")));return
            if self.path == "/v1/unlink": self.respond(200,self.server.media.unlink());return
            if data.get("action") not in CONTROL_ACTIONS:
                raise ValueError("Unsupported playback control")
            self.server.media.dispatch(data["action"], data.get("value"))
            self.respond(200, {"ok": True})
        except (ValueError, TypeError, TimeoutError) as exc:
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


def publish_executor_connection(port, key, client_id="", workspace=None):
    root=Path(workspace) if workspace else Path(os.environ.get("LOCALAPPDATA",Path.home()))/"Volt/workspace"
    if workspace is None and not root.exists(): return False
    target=root/"Altair/Spotify.connection.json"
    target.parent.mkdir(parents=True,exist_ok=True)
    data={"version":1,"port":port,"bridgeKey":key,"clientId":client_id}
    temporary=target.with_suffix(".tmp")
    temporary.write_text(json.dumps(data),encoding="utf-8")
    os.chmod(temporary,0o600);os.replace(temporary,target)
    return True


def install_startup(port=43827):
    """Start the local companion at sign-in; no account credentials in the launcher."""
    if not isinstance(port, int) or isinstance(port, bool) or not 1024 <= port <= 65535:
        raise ValueError("Port must be between 1024 and 65535")
    if os.name != "nt":
        raise ValueError("Automatic sign-in startup is available on Windows")
    startup = Path(os.environ["APPDATA"]) / "Microsoft/Windows/Start Menu/Programs/Startup"
    startup.mkdir(parents=True, exist_ok=True)
    pythonw = Path(getattr(sys,"_base_executable",sys.executable)).with_name("pythonw.exe")
    if not pythonw.exists():
        raise ValueError("pythonw.exe is required for background startup")
    source=Path(__file__).resolve()
    installed=Path(os.environ.get("LOCALAPPDATA",Path.home()))/"Altair/Spotify/spotify_bridge.py"
    installed.parent.mkdir(parents=True,exist_ok=True)
    if source!=installed: shutil.copy2(source,installed)
    script=installed
    # Use a native Startup shortcut: it does not require the deprecated VBScript engine.
    shortcut = startup / "Altair Spotify.lnk"
    launcher = Path(os.environ.get("SystemRoot", "C:/Windows")) / "System32/WindowsPowerShell/v1.0/powershell.exe"
    environment = os.environ.copy()
    environment.update(ALTAIR_STARTUP_PYTHON=str(pythonw), ALTAIR_STARTUP_SCRIPT=str(script),
                       ALTAIR_STARTUP_LINK=str(shortcut), ALTAIR_STARTUP_PORT=str(port))
    command = ("$ErrorActionPreference='Stop'; "
               "$shell=New-Object -ComObject WScript.Shell; "
               "$link=$shell.CreateShortcut($env:ALTAIR_STARTUP_LINK); "
               "$link.TargetPath=$env:ALTAIR_STARTUP_PYTHON; "
               "$link.Arguments='\"'+$env:ALTAIR_STARTUP_SCRIPT+'\" --port '+$env:ALTAIR_STARTUP_PORT; "
               "$link.WorkingDirectory=Split-Path -LiteralPath $env:ALTAIR_STARTUP_SCRIPT; "
               "$link.WindowStyle=7; $link.Description='Altair Spotify companion'; $link.Save()")
    subprocess.run([str(launcher), "-NoProfile", "-NonInteractive", "-Command", command],
                   env=environment, check=True, capture_output=True,
                   creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
    if not shortcut.is_file():
        raise OSError("The Spotify startup shortcut was not created")
    legacy = startup / "Altair Spotify.vbs"
    if legacy.exists():
        legacy.unlink()



def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=43827)
    parser.add_argument("--install-startup", action="store_true", help="Enable background startup at Windows sign-in")
    args = parser.parse_args()
    if not 1024 <= args.port <= 65535: parser.error("Port must be between 1024 and 65535")
    if args.install_startup:
        install_startup(args.port)
        return
    path = Path(os.environ.get("LOCALAPPDATA", Path.home())) / "Altair" / "Spotify" / "bridge.key"
    key = load_key(path)
    media = WebSpotify(TokenStore(path.with_name("account.tokens")),args.port)
    server = Server(args.port, media, key)
    try: publish_executor_connection(args.port,key,(media.tokens or {}).get("client_id",""))
    except OSError: LOG.warning("Automatic local pairing is unavailable; use the bridge key file")
    logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
    print(f"Altair Spotify companion: http://127.0.0.1:{args.port}\n"
          f"Open Spotify desktop and play something, then choose Connect Spotify in Altair.\n"
          f"Volt pairing is automatic. Desktop playback needs no developer app or Client ID.\n"
          f"For other devices only: enter a Spotify developer Client ID and register\n"
          f"http://127.0.0.1:{args.port}/callback, then choose Connect Spotify.\n"
          f"The saved account survives restarts. Key file for other executors: {path}", flush=True)
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
