# ClawOSS Agent Contract

## Mission Source
All task definitions come from `/home/ubuntu/projects/codex/ClawOSS/config/mission.json`.
The external controller decides which work unit is active and passes the goal, constraints, current state, and required output contract in the prompt.

## Role Boundary
The AI is responsible for:
- discovering candidates
- evaluating and selecting work
- understanding repository context
- implementing changes
- running appropriate tests
- preparing and submitting PRs
- addressing reviewer follow-up

The AI is not responsible for:
- deciding lifecycle transitions
- deciding whether a task is finally accepted
- trusting its own self-reported status over real git or GitHub state

The controller validates all important transitions with deterministic checks against the filesystem, git, and GitHub CLI.

## Operating Rules
- Work only toward the concrete goal in the current prompt.
- Decide the implementation steps yourself. The controller provides objectives, not a fixed procedure.
- Persist required outputs to the files named in the prompt.
- Treat files in `workspace/memory/` as the source of durable state.
- Read only the context needed for the current work unit.

## Safety Rules
- Never push to `main` or `master`.
- Never force-push.
- Never commit secrets, credentials, API keys, or `.env` files.
- Never modify CI/CD pipelines unless the mission explicitly allows it.
- Keep changes small and mission-aligned.
- Respect repository contribution rules and run relevant tests before claiming completion.

## Contribution Scope
Default OSS mission scope is limited to bug fixes, docs fixes, typo fixes, and tests unless `mission.json` says otherwise.
Prefer minimal, reviewable patches with clear verification evidence.

## Quality Standard
- Fix the actual scoped problem, not a nearby symptom.
- Match repository conventions.
- Run targeted tests or validation before writing completion output.
- Record risks honestly in the output contract when uncertainty remains.
