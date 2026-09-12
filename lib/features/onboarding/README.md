# Onboarding (v2 first run)

Standalone callsign → recovery-phrase flow for TASK-093 to mount.

- `OnboardingScreen` injects the 12 words and an `onDone(callsign)` callback.
- Phrase grid is 3×4, Share Tech Mono, numbered, TalkBack-labelled per word.
- No copy affordance. Android `FLAG_SECURE` is requested through
  `za.co.basileia.keryx/screenshot_guard` (`setSecure`); native handling is
  outside this territory.
- The only forward exit is **I've written it down**.
