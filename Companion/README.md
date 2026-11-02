# Altair Spotify companion

## Windows + Spotify desktop (recommended)

1. Run `StartSpotify.cmd` once. It installs local media support, keeps the companion in the background, and enables Windows sign-in startup.
2. Open Spotify and play something.
3. In Altair Settings → Capsules & Spotify, choose **Connect Spotify**. Volt pairs automatically. A desktop connection needs no developer app, client secret, or manual bridge-key copying.

Your connection is saved for this Windows user. Altair reruns and companion restarts keep it. Pausing playback hides the capsule without unlinking the account. **Spotify Status** explains whether playback is ready or waiting. **Unlink Spotify** requires confirmation and removes the saved connection.

Desktop playback supports title, artist, actual cover art, progress, play/pause, next/previous, and seek when Windows/Spotify expose those controls. Volume is disabled for this fallback. Only the Spotify desktop session is inspected. Local status and artwork endpoints require the companion key and reject browser-origin requests.

## Spotify Web API / other devices

Enter your public Spotify developer app Client ID with redirect `http://127.0.0.1:43827/callback`, then choose Connect Spotify and approve in the browser. Use the configured Bridge Port in the redirect if you changed it. Never enter a client secret. Other executors can enter the local key from `%LOCALAPPDATA%/Altair/Spotify/bridge.key` manually.

Account access and refresh tokens remain encrypted with Windows DPAPI in `%LOCALAPPDATA%/Altair/Spotify/account.tokens`; they are never exported to Roblox. Refresh tokens are retained when Spotify omits a replacement. Network failures and rate limits preserve the saved link and retry with backoff. A local desktop session is used while the Web API is unavailable. Spotify's [authorization rules and expiration](https://developer.spotify.com/documentation/web-api/tutorials/refreshing-tokens) can require browser approval again for Web API access.

## Persistence and performance

The installed companion lives outside the Git checkout, using the base Python runtime and a local dependency folder. Moving the checkout does not remove the installed script. The local status endpoint never waits on Spotify network I/O. Playback polling sleeps when Altair stops requesting status; local artwork is cached by its hash and downloaded into Roblox only when it changes. Spotify Retry-After is respected without delaying local playback updates.

Tests: `python -m unittest discover -s Companion/tests -p 'test_*.py'`.

Desktop volume controls Spotify’s Windows app mixer session, leaving device and game volume unchanged. Run StartSpotify.cmd again after updating dependencies; restart an older running companion to load the new backend.
