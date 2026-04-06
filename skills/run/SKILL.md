---
name: run
description: "Run the development pipeline with automatic retry. Two modes: 'full' (Planner + Generator + Evaluator) for complex tasks, 'fast' (Generator + Evaluator, skip Planner) for focused changes. Triggers automatically via UserPromptSubmit hook, or manually via /simple-harness:run. Also triggers when .simple/spec.md exists and user wants to continue work."
---

# Development Pipeline

Reference `references/handoff-protocol.md` as the source of truth for the `.simple/` file contract, lifecycle, and archive naming.

Two modes based on complexity:

- **Full**: **Planner** (opus) -> **Generator** (sonnet) -> **Evaluator** (sonnet) — for architecture-level work, multi-step tasks, refactors
- **Fast**: **Generator** (sonnet) -> **Evaluator** (sonnet) — for focused features, single-scope changes with quality requirements

Each agent has a single responsibility. The Planner and Evaluator never modify code. The Generator never judges its own output. Communication happens exclusively through files in `.simple/`.

When delegating any phase, explicitly invoke the subagent from this plugin by its plugin-scoped name. Use `simple-harness:plan`, `simple-harness:gen`, and `simple-harness:eval`. Do NOT use a generic subagent for planner, generator, or evaluator work, because the plugin subagents carry the intended prompt, model, and tool restrictions.

## Mode Selection

The classify hook injects the mode as the first arg:
- `args: "full"` → run Phase 1 (Plan) + Phase 2 (Generate) + Phase 3 (Evaluate)
- `args: "fast"` → skip Phase 1, go directly to Phase 2 (Generate) + Phase 3 (Evaluate)
- No arg or manual `/run` invocation → default to `full`

In **fast mode**, the user's original request IS the spec. Write a minimal `.simple/spec.md` with the request as the Goal and derive 2-3 testable success criteria from it before spawning the Generator.

## Pre-flight

Before starting, ensure the `.simple/` directory exists:

```
mkdir -p .simple
```

If `.gitignore` exists and doesn't contain `.simple/`, add it:

```
echo ".simple/" >> .gitignore
```

If `.simple/notepad.md` exists (from a previous compaction), read it and present the saved context to the user. Ask if they want to resume the previous pipeline or start fresh.

If `.simple/gotchas.md` exists, it will be passed to the Planner as learning context.

## Phase 1: Plan

Invoke `simple-harness:plan` explicitly. Give it a task equivalent to:

```
USER REQUEST:
{user's original request}

GOTCHAS (learn from past sessions):
{contents of .simple/gotchas.md, or 'None'}

Create .simple/spec.md following your output format.
Explore the codebase thoroughly before writing the spec.
```

After the planner returns:

1. Read `.simple/spec.md`
2. If the spec has **Open Questions**: present them to the user. After answers, re-spawn the planner with the clarifications.
3. If the spec is clear: present a brief summary (Goal + Success Criteria) to the user and ask for approval.
4. On approval, proceed to Phase 2.

## Phase 2: Generate

Before spawning the generator, ensure git state is clean enough for checkpointing. The generator will create a checkpoint internally.

Invoke `simple-harness:gen` explicitly. Give it a task equivalent to:

```
Read `.simple/spec.md` and implement the changes described.
IMPORTANT: Create a git checkpoint BEFORE making any changes (see your Process step 1).
Write your summary to `.simple/changes.md`.
Follow the spec exactly. If you cannot, document why in Notes.
```

After the generator returns:

1. Read `.simple/changes.md`
2. Proceed to Phase 3.

## Phase 3: Evaluate

Invoke `simple-harness:eval` explicitly. Give it a task equivalent to:

```
Read `.simple/spec.md` for criteria and `.simple/changes.md` for what was done.
Verify each criterion. Run tests if applicable.
Write your evaluation to `.simple/evaluation.md`.
```

After the evaluator returns:

1. Read `.simple/evaluation.md`
2. If verdict is **PASS**: present summary to user. Proceed to Cleanup.
3. If verdict is **FAIL**: proceed to Retry Loop.

## Retry Loop

Maximum **2 retry iterations**. Each iteration re-runs Generator then Evaluator.

### On FAIL (iteration 1 or 2):

The generator will rollback to its checkpoint before re-implementing. This ensures each retry starts from a clean state rather than patching on top of failed code.

Re-spawn the generator with evaluator feedback:

```
Invoke `simple-harness:gen` explicitly with:

IMPORTANT: Rollback to your checkpoint FIRST (see "When Re-invoked with Evaluator Feedback" in your instructions), then re-implement from scratch with the feedback in mind.

EVALUATION FEEDBACK:
{contents of .simple/evaluation.md -- especially the 'Feedback for Generator' section}

ORIGINAL SPEC:
{contents of .simple/spec.md}

Fix the identified issues. Update `.simple/changes.md` with what you fixed.
```

Then re-spawn the evaluator (same prompt as Phase 3).

### After 2 failed iterations:

Stop the loop. Present to the user:
- The latest evaluation verdict and failures
- What was attempted across iterations
- Three options: (a) fix manually, (b) adjust the spec and re-plan, (c) continue with another iteration

## Cleanup (on PASS)

1. Remove the checkpoint file: `rm -f .simple/checkpoint`
2. Keep `.simple/spec.md` (reference for future changes)
3. Keep `.simple/gotchas.md` (persistent learning)
4. Archive completed artifacts:
   - Rename `.simple/changes.md` to `.simple/changes-{YYYY-MM-DD}.md`
   - Rename `.simple/evaluation.md` to `.simple/evaluation-{YYYY-MM-DD}.md`
5. Clear `.simple/notepad.md` if it exists

## Anti-Patterns

- In full mode, do NOT skip the Planner -- the spec is what makes evaluation possible
- In fast mode, still write a minimal spec.md before Generator runs
- Do NOT let the Generator self-evaluate -- that's the Evaluator's job
- Do NOT run more than 2 retry iterations without user intervention
- Do NOT modify `.simple/spec.md` during the Generate-Evaluate loop -- if the spec is wrong, go back to Phase 1
- Do NOT dispatch Generator and Evaluator in parallel -- they are sequential by design
