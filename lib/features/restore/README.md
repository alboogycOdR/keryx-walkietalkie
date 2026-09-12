# Restore

12-word BIP-39 entry that reconstructs the Ed25519 identity (V2-FR-003).

- Per-word validation against the in-repo English wordlist, with prefix chips.
- Checksum failure is shown inline; a valid phrase calls `onRestored`.
- Callsign is a placeholder until the shell re-fetches `/v2/identity/me`.
