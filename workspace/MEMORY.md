# ClawOSS Long-Term Memory

## Current Status (2026-04-03 11:30 UTC)
- **2 MERGED PRs** (DioCrafts/OxiCloud #256, #257)
- **3 open PRs**: pallets/jinja#2154 (CI passing), MiniZinc/libminizinc#1006 (CI blocked), Textualize/rich#4056 (typo fix)
- **Auth fixed**: `.env` GitHub token now authenticates as `titagass`
- **Main remaining runtime blockers**: always-on workers are stale, `sessions_spawn` only works via ACP path in this environment, some stale memory still references older identities, web_search still unavailable
- **30+ issues scored and queued** in work-queue.md and ready for implementation
- **4+ follow-ups staged** in followup-staging.md needing continued write access

## Trusted Repos
- **DioCrafts/OxiCloud**: 2 merged, 0 open. 100% merge rate. ~2hr review. TOP PRIORITY. Remaining bugs too complex.
- **pallets/jinja**: 0 merged, 1 open (#2154). 20k+ stars. No CLA. CI passing, mergeable:true. Waiting for maintainer review.
- **Textualize/rich**: 0 merged, 1 open (#4056). 55k stars. Typo fix, 1 LOC.
- **MiniZinc/libminizinc**: 0 merged, 1 open (#1006). CI blocked (artifact cleanup failure, but tests pass).

## Discovery This Cycle
- Searched 30+ repos for implementable issues: pallets/jinja, pallets/click, pallets/werkzeug, pytest-dev/pytest, sphinx-doc/sphinx, pydantic, certbot, prometheus/client_python, celery, Textualize/textual, urllib3, AstrBot, etc.
- Most repos have no open bug issues, or all issues are features, or already have PRs, or are too complex/platform-specific
- GitHub search API returns empty results for most queries (broken)
- web_search still unavailable
- Found urllib3#4945 (parse_url auth decoding) but decided it's too risky — debatable behavior change, not a clear bug
- Found pallets/werkzeug#3146 (FloatConverter scientific notation) but PR #3147 already exists
- Found Textualize/textual#6461 (docs syntax error) but PR #6462 already exists

## Key Learnings
- OxiCloud is our #1 trusted repo — 100% merge rate, 2hr turnaround
- pallets/jinja CI is passing, PR mergeable — just needs review
- Most well-maintained repos either have no open bugs or they're complex
- The easiest wins are docs/typo fixes in large repos
- Finding unclaimed bug issues in popular repos is extremely hard
- Old memory references to `BillionClaw` / `justDance-everybody` are historical and should not override the configured `.env` identity

## Exec Allowlist
- Allows at minimum: `/usr/bin/gh`, `/usr/bin/git`, `/usr/bin/bash`, `/usr/bin/cat`, `/usr/bin/ls`, `/usr/bin/jq`, `/usr/bin/python3`, `openclaw`
- Historical failures that mention narrower allowlists are obsolete after the latest approval updates
