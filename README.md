# Simple Harness

Simple Harness is a project-scoped Claude Code plugin and marketplace for running a small development harness around medium- and high-complexity coding tasks.

The repository currently provides:

- one skill: `/simple-harness:run`
- three plugin subagents: `simple-harness:plan`, `simple-harness:gen`, `simple-harness:eval`
- three hooks: `UserPromptSubmit`, `PreCompact`, `Stop`
- one runtime directory: `.simple/`

The pipeline is intentionally file-based. Planning, implementation, evaluation, compaction recovery, and cross-session gotchas are all passed through files in `.simple/`.

## Install

This repository is both a marketplace root and a plugin.

The marketplace name is `simple-harness`, and the plugin name is also `simple-harness`, so the install target is `simple-harness@simple-harness`.

From a local checkout, run from the repository root:

```bash
claude plugin marketplace add . --scope project
claude plugin install simple-harness@simple-harness --scope project
```

From GitHub:

```bash
claude plugin marketplace add bzantium/simple-harness --scope project
claude plugin install simple-harness@simple-harness --scope project
```

Validate the manifests locally:

```bash
claude plugin validate .
```

The examples above use project scope, which matches how this plugin is designed to be used.

## Usage

### Automatic

The `UserPromptSubmit` hook classifies each prompt and either:

- does nothing for simple requests
- injects a reminder to run `simple-harness:run fast`
- injects a reminder to run `simple-harness:run full`

The classifier is intentionally conservative. A missed trigger is cheaper than a false positive, so pass-through is the default.

### Manual

Invoke the skill directly:

```text
/simple-harness:run add support for OAuth
/simple-harness:run fast add support for OAuth
/simple-harness:run full refactor the auth module
```

If you omit the first argument, the skill defaults to `full`.

## Classification Rules

The prompt classifier in `hooks/classify.sh` uses simple pattern matching.

It forces the full pipeline when the prompt mentions `/simple-harness:run`, a standalone `/run`, or `.simple/spec.md`.

It passes through when the prompt looks like:

- a short question without implementation verbs
- a short single-file edit request with a line number
- a git operation such as `commit`, `push`, `rebase`, `status`, or `/commit`
- a very short `rename`, `delete`, `remove`, `move`, `copy`, `format`, or `lint` request

It routes to the full pipeline when it sees signals such as:

- multi-step phrasing like `and then`, `after that`, `first ... then`, `1.`, `2.`
- architecture verbs like `refactor`, `redesign`, `migrate`, `architect`, `restructure`
- broad scope words like `across all`, `every file`, `throughout`, `entire`, `all files`
- long implementation-heavy prompts

It routes to the fast pipeline when it sees focused feature work or explicit quality requirements such as:

- `add support for`
- `build a`
- `create a ... system`
- `develop a`
- `with tests`
- `ensure`
- `verify that`
- `make sure`
- `test coverage`

## Pipeline

### Modes

- `fast`: `gen -> eval`
- `full`: `plan -> gen -> eval`

### Flow

1. The skill ensures `.simple/` exists.
2. If `.gitignore` already exists and does not contain `.simple/`, the skill appends it.
3. If `.simple/notepad.md` exists, the skill reads it and asks whether to resume the previous pipeline or start fresh.
4. If `.simple/gotchas.md` exists, the planner receives it as learning context.
5. In `full` mode, `simple-harness:plan` explores the repo and writes `.simple/spec.md`.
6. If the planner leaves open questions, the user answers them before implementation continues.
7. In `full` mode, implementation waits for user approval of the spec summary.
8. In `fast` mode, the skill writes a minimal `.simple/spec.md` directly from the user request.
9. `simple-harness:gen` records a git checkpoint in `.simple/checkpoint`, implements the changes, runs tests, and writes `.simple/changes.md`.
10. `simple-harness:eval` verifies the result against the spec, runs verification commands, and writes `.simple/evaluation.md`.
11. If evaluation fails, the generator rolls back to the checkpoint and retries from scratch with the evaluator feedback.
12. The retry loop stops after 2 failed iterations and asks the user how to proceed.
13. On pass, the pipeline removes `.simple/checkpoint`, clears `.simple/notepad.md`, and archives the latest `changes.md` and `evaluation.md`.

## Subagents

These subagents are registered through `.claude-plugin/plugin.json` and are intended to be invoked by the `run` skill, not replaced with generic agents.

| Subagent | Model | Tools | Role |
|----------|-------|-------|------|
| `simple-harness:plan` | `opus` | `Read`, `Grep`, `Glob`, `Write` | Explores the codebase and writes `.simple/spec.md` |
| `simple-harness:gen` | `sonnet` | `Read`, `Grep`, `Glob`, `Edit`, `Write`, `Bash` | Implements the spec, runs tests, writes `.simple/changes.md` |
| `simple-harness:eval` | `sonnet` | `Read`, `Grep`, `Glob`, `Bash`, `Write` | Verifies the implementation and writes `.simple/evaluation.md` |

The planner and evaluator do not modify project source files. Their write targets are their `.simple/` artifacts.

## Hooks

| Event | Type | Implementation | Behavior |
|-------|------|----------------|----------|
| `UserPromptSubmit` | command | `hooks/classify.sh` | Classifies the prompt and injects pipeline instructions when needed |
| `PreCompact` | command | `hooks/save-notepad.sh` | Writes `.simple/notepad.md` with a timestamp, current spec, latest evaluation, and known gotchas |
| `Stop` | agent | defined inline in `hooks/hooks.json` | Reviews the transcript and `.simple/` state for new harness-level gotchas, blocks once to have Claude append them, then allows stopping |

### Stop Hook Behavior

The stop hook is not trying to edit files itself.

Instead, it:

1. inspects the stop-hook input and transcript
2. checks `.simple/gotchas.md` for duplicates
3. returns `{"ok": true}` when there is nothing new to record
4. returns `{"ok": false, "reason": ...}` once when there is a new gotcha to append
5. returns `{"ok": true}` when `stop_hook_active` is already true, which prevents infinite stop loops

The categories it uses are:

- `user-correction`
- `repeated-instruction`
- `pipeline-failure`
- `classification-error`
- `compaction-gap`

## Runtime Files

All runtime state lives in `.simple/`, which is gitignored in this repository.

| File | Producer | Purpose |
|------|----------|---------|
| `.simple/spec.md` | planner or fast-mode pipeline setup | Contract for implementation and evaluation |
| `.simple/changes.md` | generator | Implementation summary |
| `.simple/evaluation.md` | evaluator | PASS or FAIL verdict plus actionable feedback |
| `.simple/checkpoint` | generator | Git commit hash used for rollback |
| `.simple/notepad.md` | `PreCompact` hook | Compaction snapshot with timestamp, spec, evaluation, and gotchas |
| `.simple/gotchas.md` | stop-hook workflow | Append-only cross-session harness issues |
| `.simple/changes-YYYY-MM-DD.md` | cleanup on PASS | Archived implementation summary |
| `.simple/evaluation-YYYY-MM-DD.md` | cleanup on PASS | Archived evaluation |

### File Lifecycle

- `spec.md` is kept after a successful run for future reference.
- `gotchas.md` accumulates across sessions.
- `notepad.md` is transient and is cleared on successful completion.
- `changes.md` and `evaluation.md` are archived on pass.

## Current Constraints

- The generator assumes the project is in a git repository. Checkpoint and rollback depend on `git rev-parse HEAD` and `git checkout $(cat .simple/checkpoint) -- .`.
- The pipeline is single-threaded by design. Generator and evaluator are not meant to run in parallel.
- The classifier is heuristic, not semantic. It will miss some tasks and that is intentional.
- Full mode depends on explicit user approval after planning.
- After 2 failed retries, the harness stops and asks the user how to continue.
- The stop hook records harness and process issues, not ordinary implementation bugs.

## Repository Layout

```text
.claude-plugin/            marketplace and plugin manifests
agents/                    plugin subagents: plan, gen, eval
hooks/                     hook configuration and shell scripts
skills/run/                run skill and handoff reference
```

## License

MIT
