# Spotify connection

Each user links their own account. Altair controls Spotify on an existing Spotify device; it does not stream audio into Roblox. Start a song in Spotify first.

## First setup

1. Install Python 3.10 or newer. On Windows run `StartSpotify.cmd` in this folder. The companion stays running in the background when you close the setup window. macOS/Linux: run `python3 spotify_bridge.py` and leave it running.
2. Open the [Spotify developer dashboard](https://developer.spotify.com/dashboard) yourself and create an app using the Web API. Register exactly `http://127.0.0.1:43827/callback` as its redirect URI.
3. Copy its **Client ID**. Do not copy its client secret: this app uses authorization code with PKCE and needs no secret.
4. Open Altair **Settings → Capsules & Spotify**. Paste the Client ID into **Spotify Client ID**, and the local key printed by the companion into **Spotify Bridge Key**. Enable **Spotify Connection**.
5. Click **Link Spotify**. The companion opens Spotify approval in your default browser. Approve it yourself, then return to Altair. Start playback on a Spotify device.

The music capsule supports play/pause, next, previous, seeking and device volume, subject to Spotify's permissions and device capabilities. Authentication refreshes automatically while the companion runs. If the port is occupied, launch `python spotify_bridge.py --port 43828`, change **Spotify Bridge Port**, and register the matching redirect URI.

## Unlink and repeat the process

Rerunning or unloading Altair keeps the saved link. Altair restores connection settings before polling and carries playback metadata across UI rebuilds. The companion refreshes authorization automatically and reloads saved credentials when restarted; it needs to be started again after rebooting the computer.

Click **Unlink Spotify** in Altair Settings, then confirm **Disconnect**. Cancel, Escape, clicking outside the dialog, or rerunning Altair dismisses an unanswered confirmation without unlinking. Confirming removes saved account tokens and pending browser authorization. Click **Link Spotify** to approve again. Turning **Spotify Connection** off also asks for confirmation; this only pauses polling and preserves the account link.

Unlink removes this computer's credentials. To revoke the app's permission at Spotify too, remove it from [Spotify account apps](https://www.spotify.com/account/apps/) yourself. Closing the companion stops the local connection. No account was linked as part of development tests.

## Requirements for other users

Spotify imposes app and account restrictions. Development mode requires Premium for the app owner and currently supports up to five allowlisted users. Playback control also requires Premium. Users of their own personal developer app enter their own Client ID. A broadly distributed app using one shared Client ID needs Spotify extended quota approval; distributing this repository does not grant that approval. Consult [quota modes](https://developer.spotify.com/documentation/web-api/concepts/quota-modes) for current rules.

The Roblox environment needs an HTTP request implementation that permits loopback connections. Ordinary published Roblox LocalScripts cannot call this local companion. Timer, stopwatch and notification UI do not depend on Spotify or the companion.

## Storage and privacy

The bridge listens only on `127.0.0.1`. Requests require a randomly generated local bridge key; browser-origin API requests are rejected. OAuth callbacks validate a short-lived, single-use state and PKCE verifier. Account access/refresh tokens never enter Roblox, GitHub or Altair settings. Windows encrypts them for the current Windows user with DPAPI. On other systems the token file uses owner-only permissions. Keep the local bridge key private; it permits playback commands and account linking/unlinking on this computer.

Files live in `%LOCALAPPDATA%/Altair/Spotify` on Windows, or `~/Altair/Spotify` otherwise. The default OAuth mode needs no third-party Python packages.


## Troubleshooting

- **Companion unavailable:** run `StartSpotify.cmd` again, check the matching key/port, and confirm your executor allows loopback requests. A temporary connection failure retries automatically and does not delete the saved link.
- **Redirect mismatch:** use the exact numeric loopback redirect above, including port and `/callback`.
- **Access denied:** check Premium, the developer app's allowlist and granted permissions. Re-link after changing app access.
- **Nothing playing:** start playback using Spotify itself. Altair does not automatically choose a playback device.
- **Rate limited:** the companion honors Spotify's retry delay; leave it running and wait.

Tests: `python -m unittest discover -s Companion/tests -v` from the repository root. Tests simulate authorization and playback responses and never connect an actual Spotify account.

Manual development checks also used a real linked account and Volt's HTTP and
local asset implementation. The state response includes a public Spotify cover
URL; Altair loads it directly from `i.scdn.co` without sending account tokens or
the companion key. Cover rendering requires executor local image-asset support.
