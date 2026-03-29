# Simple Harness

Big harnesses are overwhelming. Going bare is not enough.
Simple Harness is a Claude Code plugin that implements [Anthropic's harness design philosophy](https://www.anthropic.com/engineering/harness-design-long-running-apps) with the smallest possible footprint.

> "Every component in a harness encodes an assumption about what the model can't do on its own."

## How It Works

```
User prompt
  |
  v
[classify hook] --- simple? -------> pass-through (no overhead)
  |                |
  |  medium        |  high
  |                |
  v                v
  |         Planner (opus)      writes spec.md (READ-ONLY)
  |                |
  +-------+-------+
          |
          v
   Generator (sonnet)   implements code + runs tests (git checkpoint)
          |
          v
   Evaluator (sonnet)   PASS/FAIL per criterion (READ-ONLY)
          |
          |-- PASS -> done
          +-- FAIL -> rollback -> re-run Generator (max 2x)
```

**Two modes:**
- **Fast** (medium complexity): Generator -> Evaluator. Skips the Planner for focused, single-scope changes.
- **Full** (high complexity): Planner -> Generator -> Evaluator. For architecture-level work, multi-step tasks, refactors.

**Core principles:**
- The Generator never judges its own code
- The Evaluator never modifies code
- On FAIL, git checkpoint rollback restores a clean state before retry
- All agent communication happens through files in `.simple/`

## Installation

```bash
claude plugin install simple-harness
```

Project-scoped plugin. Only active in the project where it's installed.

## Usage

### Automatic

The `UserPromptSubmit` hook classifies every request:

| Classification | Examples | Pipeline |
|---------------|----------|----------|
| **Simple** | `rename foo to bar`, `commit this`, `what does X do?` | pass-through |
| **Medium** | `build a REST API for user management`, `add support for OAuth` | fast (Generator + Evaluator) |
| **High** | `refactor the entire auth module`, `migrate database across all services` | full (Planner + Generator + Evaluator) |

The default is pass-through. A missed trigger is cheaper than a false one -- you can always invoke the pipeline manually.

### Manual

```
/simple-harness:pipeline implement user authentication with JWT
```

## Architecture

### Agents

| Agent | Model | Role | Access | Output |
|-------|-------|------|--------|--------|
| **Planner** | opus | Analyzes request, writes spec with testable success criteria | READ-ONLY | `.simple/spec.md` |
| **Generator** | sonnet | Implements the spec, runs tests | Full | `.simple/changes.md` |
| **Evaluator** | sonnet | Verifies each criterion, provides actionable feedback | READ-ONLY | `.simple/evaluation.md` |

### Hooks

| Event | Type | Purpose |
|-------|------|---------|
| `UserPromptSubmit` | command | 3-tier complexity classification (pattern matching, <100ms) |
| `PreCompact` | command | Saves pipeline state to `.simple/notepad.md` before compaction |
| `Stop` | prompt | Captures harness-level gotchas for cross-session learning |

### `.simple/` Directory

Runtime directory for agent handoff files and session state. Listed in `.gitignore`, so git rollback never touches it.

```
.simple/
├── spec.md              # Planner -> Generator contract
├── changes.md           # Generator -> Evaluator report
├── evaluation.md        # Evaluator -> Generator feedback
├── checkpoint           # git HEAD hash for rollback on FAIL
├── notepad.md           # State snapshot for compaction resilience
└── gotchas.md           # Cross-session failure learning
```

### Git Checkpoint & Rollback

The Generator creates a git checkpoint before modifying any code. If the Evaluator returns FAIL:

1. Code rolls back to the checkpoint (clean state restored)
2. Feedback in `.simple/evaluation.md` is preserved (`.simple/` is gitignored)
3. Generator re-implements from scratch with the feedback in mind

No patching on top of failed code. Keep the lessons, discard the attempt.

## Design Philosophy

### Assumption Registry

Every component encodes an assumption about model limitations. As models improve, assumptions go stale. Validate periodically and remove what's no longer load-bearing.

| Component | Assumption | Retirement Test |
|-----------|-----------|----------------|
| `classify.sh` | Model can't self-select workflow complexity | 20 prompts without hook. If it naturally plans for complex tasks, remove. |
| Planner | Can't produce testable spec + implementation in one pass | Generator-only on 10 tasks. If 80%+ pass first evaluation, remove. |
| Evaluator | Self-evaluation bias prevents reliable self-judgment | Self-eval vs external eval on 10 tasks. If within 10% agreement, remove. |
| PreCompact | Compaction loses critical pipeline state | 5 long sessions without notepad. If pipeline resumes correctly, remove. |
| Gotcha capture | No native cross-session learning | Keep until Claude Code adds session learning. (Most durable.) |

### Generator-Evaluator Separation

Same principle as separating Generator and Discriminator in a GAN. Self-evaluation bias is a structural property, not a model limitation -- this separation is the most durable component in the harness.

## Design Influences

- [Anthropic: Harness Design for Long-Running Apps](https://www.anthropic.com/engineering/harness-design-long-running-apps) -- core philosophy
- [oh-my-claudecode](https://github.com/yeachan-heo/oh-my-claudecode) -- hook system, compaction resilience, gotcha capture

## License

MIT
