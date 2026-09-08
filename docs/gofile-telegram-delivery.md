# Gofile + Telegram file delivery

Upload any file to a temporary public URL and post the link to a Telegram
chat via a bot. Useful for shipping build artefacts (e.g. a debug/release
APK for the two-phone field tests) without setting up CI artefact storage
or fighting a chat client's own upload size cap.

Script: `scripts/release_remote.py`. Run:

```
python scripts/release_remote.py [path-to-file]
```

Defaults to `build/app/outputs/flutter-apk/app-release.apk` if no path is
given.

## One-time setup

1. **Create a Telegram bot.** Message `@BotFather` → `/newbot` → save the
   token (looks like `1234567890:AAA...`).
2. **Get your chat ID.** Message `@userinfobot` — it replies with a numeric
   ID.
3. **Send your bot one message first** (any text). Until the user
   initiates, the bot can't DM them.
4. **Set the environment variables for your session** — never write these
   to a file in this repo, the secret-scan hook will (correctly) refuse it:
   ```powershell
   $env:TELEGRAM_BOT_TOKEN = "<token>"
   $env:TELEGRAM_CHAT_ID   = "<chat id>"
   ```

## The flow — three HTTP calls

1. **Pick a Gofile server** — `GET https://api.gofile.io/servers`, use
   `data.servers[0].name`.
2. **Upload the file** — `POST https://<server>.gofile.io/contents/uploadfile`,
   multipart, field `file` = the binary. No auth required. Free tier
   ~10-day expiry, no file-size limit.
3. **Post the link to Telegram** — `POST https://api.telegram.org/bot<TOKEN>/sendMessage`
   with `{chat_id, text, disable_web_page_preview: false}`.

## Pitfalls (lessons learned)

- **Don't set `parse_mode`.** Telegram legacy `Markdown` doesn't support
  backslash escapes, so any unmatched `_`/`*`/backtick in a commit message
  aborts the send with `"Can't find end of the entity"`. `MarkdownV2`
  requires escaping ~15 characters. Plain text is the reliable choice —
  Telegram auto-links URLs anyway.
- **Telegram `sendDocument` has a 50 MB cap.** That's why this goes through
  Gofile rather than attaching the file directly (this project's own debug
  APKs run 200MB+; even the smallest split-per-ABI release build is ~33MB,
  over this chat client's own 30MB attachment limit too).
- **Gofile links expire in ~10 days.** Not a release channel — use a real
  distribution track for anything long-lived.
- **Bot token is a secret.** If leaked, revoke via `@BotFather` → `/revoke`.
