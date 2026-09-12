# My code

Full-screen ID QR for TASK-093 to mount from the overflow menu.

- QR payload: `keryx://id?v=1&c=<callsign>&k=<base64url(publicKey)>`
- Share URL: `https://keryx.app/c/<callsign>-<code>?k=<base64url(publicKey)>`
- Display: `<CALLSIGN>·<CODE>`
- Brightness raised via `za.co.basileia.keryx/screen_brightness` while shown.
- `onShare` is injected; there is no `share_plus` dependency.
