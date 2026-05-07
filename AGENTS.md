# AGENTS.md

## Project Overview

This repository contains a single Bash CLI, [`moltbook.sh`](./moltbook.sh), that calls the Moltbook API at `https://www.moltbook.com/api/v1`.

The script:

- Requires `MOLTBOOK_API_KEY` for authorization.
- Uses `curl` for HTTP requests.
- Uses `jq` to build JSON payloads and pretty-print responses.
- Uses `python3` only to URL-encode search queries.
- Supports read and write operations for posts, comments, submolts, profiles, follows, notifications, and direct messages.

## Contributor Guidance

- Keep the project as a small, portable Bash tool unless the user explicitly asks for a larger rewrite.
- Preserve `set -euo pipefail` behavior and handle unset variables deliberately.
- Build JSON payloads with `jq -n`; do not hand-roll JSON strings for user-provided input.
- Quote shell variables, especially values that come from prompts or command arguments.
- Keep command behavior consistent with the existing `case "$cmd"` structure.
- Add new commands to both `usage()` and the main `case` block.
- Avoid introducing package managers, generated files, or broad refactors unless they are required for the requested change.
- Do not log or commit API keys, tokens, or private response data.

## Local Checks

Run this after editing the script:

```bash
bash -n moltbook.sh
```

There is no current automated test suite. For commands that hit the network, prefer documenting the manual command used instead of assuming live API access is available.

## Current Code Notes

- `maybe_verify` detects verification codes in several response shapes and submits the user's answer to `/verify`.
- `update-profile` currently updates the profile description only.
- The API base URL is hardcoded in `API_BASE`; if adding environment-based configuration, keep the default unchanged.
