# 0002. AES-256-GCM vault for private files in a public repo

Date: 2026-11-26 (records the existing design). Status: accepted.

## Context
Launch notes, signing steps and contact details belong with the code but the repo is public.

## Decision
`scripts/vault.mjs` encrypts each file in `private/` (gitignored) into `private.enc` (committed) with
AES-256-GCM from Node's built-in crypto. The key is `.vault-key` (gitignored, mode 600) or
`MWVAULT_KEY`. Each file's relative path is the GCM additional data, so swapped files fail to decrypt.
`encrypt` refuses to overwrite ciphertext that the current key cannot open, unless `--force`.
`check` runs in the pre-commit hook and in `scripts/check.sh`.

## Consequences
- No dependency. Losing the key loses the data; it is backed up outside the repo.
- Ciphertext stays public forever. A leaked key exposes every past version: rotate with `--force`.
- Agents never print, log or commit the key or plaintext.
