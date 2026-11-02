# Altair UI

Build.lua contains all interface construction and embedded assets. Altair.lua loads and binds it. No uploaded Roblox UI is required.

General contains colour, opacity and sizing controls. Experimental contains Styles (Altair/Roblox) and optional Avoid Game UI. Styles have visual previews and reset. HUD avoidance uses bounded native hit tests only during dragging; hidden widgets and large full-screen backgrounds are excluded. Newly appearing widgets and very fast movement may precede the bounds cache.

Notifications: Altair.notification(title, description). Notify and QueueNotification are compatibility aliases. UI size defaults to 110%.

Spotify instructions: ../Companion/README.md. Licences: ../THIRD_PARTY_NOTICES.md. Modified component source is embedded in Build.lua.

Tests and developer implementations are excluded from the public tree. The Developer tab appears only if Volt workspace contains Altair/Developer/AltairDevTools.lua. No inline source override is accepted.
