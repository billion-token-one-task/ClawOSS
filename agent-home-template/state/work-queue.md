# Work Queue

Human-readable. The `clawoss-skill` reads and writes the auto-managed sections below. **Manual entries** are preserved — add notes for yourself anywhere outside the auto-managed blocks.

---

<!-- IN-PROGRESS:START -->
## In Progress

_No cycle is currently working on anything. The Skill writes here when it enters step 3 (impl) and clears it when step 5 (commit state) finishes._

| Started (UTC) | Repo | Issue | Branch | Phase |
|---|---|---|---|---|
| — | — | — | — | — |

<!-- IN-PROGRESS:END -->

---

<!-- RECENTLY-DISCOVERED:START -->
## Recently Discovered

Last 10 candidates discovered in step 1, ranked by merge-probability heuristic (highest first). Evicted by `updated_at` when the list overflows.

| Score | Repo | Issue | Title | Labels | Updated (UTC) |
|---|---|---|---|---|---|
| — | — | — | — | — | — |

<!-- RECENTLY-DISCOVERED:END -->

---

## Pending (human-curated)

Add issues here that you want the agent to pick up next, regardless of discovery ranking. The Skill will pull from this list **before** running step 1 if it is non-empty.

Format: one line each, `owner/repo#N — short note`.

- (none yet)

---

## Notes

Free-form. The Skill never writes here. Use this for context the agent should not learn — e.g. "do not engage with maintainer @X again", "repo Y is mid-rewrite, hold off until Aug".
