# ClawOSS — Claude Code Instructions

## What This Is
ClawOSS is an autonomous OpenClaw agent configuration that discovers GitHub issues, implements bug fixes, and submits PRs. It does NOT modify OpenClaw itself — it uses OpenClaw as a platform.

## Architecture
- **Orchestrator**: Main agent session running HEARTBEAT.md loop (steps 0-7)
- **Implementation sub-agents**: Fresh context per task, clone → reproduce → fix → test → PR
- **Follow-up sub-agents**: 1 per PR, handle reviewer feedback via `gh` CLI, max 3 rounds
- **Sub-agents share a 5-slot pool** — follow-ups get priority over new implementations
- **Result files**: Sub-agents write to `workspace/memory/subagent-result-*.md`, orchestrator reads and processes

## Key Files
- `workspace/HEARTBEAT.md` — The autonomous loop, DO NOT break this
- `workspace/AGENTS.md` — Operating instructions and rules
- `workspace/skills/*/SKILL.md` — 10+ custom skills
- `config/openclaw.json` — Agent config (NO secrets here)
- `~/.openclaw/openclaw.json` — Live config WITH secrets
- `~/Library/LaunchAgents/ai.openclaw.gateway.plist` — Gateway service (MUST include KIMI_API_KEY)
- `workspace/memory/` — Runtime state (gitignored)
- `dashboard/` — Next.js 15 Vercel dashboard
- `scripts/restart.sh` — Full restart for headless operation

## Critical Rules
- NEVER put secrets in `config/openclaw.json` — that's committed to git
- ALWAYS update BOTH `~/.openclaw/openclaw.json` AND the gateway plist when changing API keys
- Workspace memory files are gitignored — they contain runtime state
- The agent targets merge-optimized contributions: bug fixes, docs fixes, typo fixes, test additions. No features, refactors, or architectural changes.
- Mix: 60% easy wins (docs, typos, tests) + 40% substantive bug fixes at responsive repos
- Prioritize issues < 3 days old, skip > 30 days old
- Only contribute to healthy repos: 200+ stars, active maintenance, responsive reviewers
- Sub-agents must deeply understand repo architecture before implementing fixes
- All GitHub communication via `gh` CLI
- Branch naming: `clawoss/{fix,docs,test,typo}/<description>`

## Team (clawoss-v7)
- **clawoss-architect**: Architecture & prompt design, deep knowledge of all files
- **clawoss-monitor**: Real-time agent monitoring & status reports
- **problem-finder**: Adversarial audit, finds bugs and edge cases
- **compatibility-ensurer**: Architecture extensibility review
- Teammates must NEVER be shut down unless user explicitly requests it
- Teammates actively cross-communicate via DMs

## Research — ALWAYS Use DeepWiki
When you have ANY question about OpenClaw internals (config, tools, APIs, hooks, sessions, heartbeat, compaction), use DeepWiki FIRST:
```
mcp__deepwiki__ask_question(repoName: "openclaw/openclaw", question: "your question")
```
Do NOT guess about OpenClaw behavior. Past incidents from guessing: wrong config keys, wrong tool names, broken gateway. DeepWiki has AI-summarized docs for the entire OpenClaw repo.

Also use DeepWiki for any open-source repo you're integrating with or contributing to.

## Prompts Are The Product
The quality of ClawOSS output is 100% determined by its prompts. When strategy changes:
- Update ALL prompt files immediately (openclaw.json heartbeat, HEARTBEAT.md, skills, templates)
- HEARTBEAT.md must stay under 20000 chars (OpenClaw truncates at this limit)
- AGENTS.md must stay under 20000 chars
- After prompt changes, the agent hot-reloads config — use `openclaw config set` for heartbeat prompt updates
- Review prompts regularly for cross-file consistency

## Model
- Default: `openai/gpt-5.5`
- Fallback: `openai/gpt-5.5`
- Override with `CLAWOSS_MODEL` and `CLAWOSS_FALLBACK_MODEL`
- API key env var for the default model: `OPENAI_API_KEY`

## Common Commands
```bash
# Restart agent
bash scripts/restart.sh

# Check agent status
openclaw logs 2>&1 | tail -20

# Wake agent manually
openclaw system event --text "resume heartbeat" --mode now

# Restart gateway (after config changes)
launchctl unload ~/Library/LaunchAgents/ai.openclaw.gateway.plist
launchctl load ~/Library/LaunchAgents/ai.openclaw.gateway.plist

# Check PRs
gh pr list --author BillionClaw --state open
```
