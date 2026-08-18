# Model discipline — decision record & rationale

`CLAUDE.md` carries the **table** (which model for which operation) because ORCH needs it in every session. This file carries the **reasoning**, because rationale is read once when you're deciding whether the rule still makes sense — not on every turn. See "Prefix hygiene" below for why that split matters.

---

## Decision, 2026-07-19: judgment rows moved off `claude-sonnet-5`

**Context.** The S5 builder unit (added in `c69cdda`) runs `claude-sonnet-5` headlessly. Before S5 existed, ORCH's judgment rows running on sonnet-5 posed no parity problem: GB is Grok, CX is Codex, so the reviewer was already a different model from both makers, with plausibly different blind spots.

**The problem S5 introduced.** When sonnet-5 reviews sonnet-5's work, the reviewer shares the maker's exact failure distribution — the same rationalizations read as plausible, the same edge cases don't come to mind, the same subtly-wrong pattern looks idiomatic. Role separation (interactive ORCH vs. headless builder, different briefings, the S5 identity override) addresses *incentives*, but it cannot change what a model is capable of *noticing*. Maker–checker discipline depends on the checker having an independent perspective, not just an independent instruction set.

**Second-order cost.** A missed review produces no rework finding. No rework finding means nothing for the Wave C distiller to mine. Same-model review doesn't just let bugs through — it starves the learning loop of the evidence it exists to consume, and does so invisibly.

**Why the cost is acceptable.** The three upgraded rows (decompose, review, triage) are the *lowest-frequency* operations in the system — a handful of invocations per wave, against builders burning tokens continuously. The premium lands precisely where errors are most expensive and volume is smallest. That's the correct shape for a tiered system; flat sonnet-5 across all judgment rows paid a uniform price for non-uniform stakes.

**Amendment, 2026-08-18: Fable retired — all judgment rows consolidated on `claude-opus-5`.** Fable is no longer an available model. Decompose (previously fable), review and triage (previously `claude-opus-4-8`) now all run on `claude-opus-5`, the highest Opus. The table in `CLAUDE.md`, the three `.claude/commands/devteam-*.md` guidance blocks, and `autopilot.json`'s `review_cmd`/`judgment_model` were updated together. What this preserves and what it gives up, stated plainly rather than glossed:

**Preserved — the primary parity boundary, maker vs checker.** Review still runs on a model the builders do not: GB is Grok, CX is Codex, and the (currently inactive) S5/S5B builders are sonnet-5. Opus-5 shares its failure distribution with none of them. This is the boundary the 2026-07-19 decision was actually built to protect (a checker must notice what the maker cannot), and it still holds.

**Given up — the planner/checker separation, deliberately.** Previously decompose (fable) and review (opus) were different models, so the reviewer shared a model with neither the builder *nor* the spec-author. With both on opus-5 that second separation is gone: the model that authors the decomposition is now the model that reviews work against it. This is a real reduction in independence at the spec-verification layer — a decomposition blind spot can now be mirrored by the same blind spot at review. It is accepted because the model lineup no longer offers a distinct high-capability planner, and Opus-5 at high effort is the strongest single judgment voice available; the mitigation is that review verifies against the *spec text quoted independently* (a subagent pulls the passages), not against the decomposition's own summary, which keeps some daylight between author and checker even on one model. Revisit if a second top-tier model returns.

**Why the distiller stays on sonnet-5.** It is not a gate. Its confidence math is code-owned (`instincts.py`), its output is data (INSTINCTS.md), and its amendment proposals are locked behind the constitutional gate requiring explicit `/approve`. The same-model concern applies to *checkers*; the distiller is neither maker nor checker. Unaffected by the Fable retirement.

**Effort is a depth knob, not a discount knob.** Running opus-5 at low effort to save budget defeats the purpose on decompose: territory carving and dependency sequencing are exactly where shallow reasoning misses interaction effects (two tasks that quietly share a file, a dependency chain that serialises what looked parallel). Medium is the floor; high for complex or many-task waves.

**Usage accounting.** Opus draws from the same Claude 5h/7d windows as sonnet-5, so the Wave I meters and `budget.py`'s S5 usage gating cover it with zero code changes — it simply consumes those windows faster per invocation. Acceptable at these rows' frequency; the standing rule is that Opus never creeps into the high-frequency mechanical rows.

---

## Prefix hygiene — why this file exists separately

Everything stable at the front of a session's prompt (tool definitions, system prompt, auto-loaded `CLAUDE.md`) is cached after the first turn, and a cached token costs a fraction of a fresh one. Two consequences shape how this project organises its docs:

**1. `CLAUDE.md` is a hot file — every ORCH turn and every S5 builder turn pays for it.** It auto-loads into context. So it should carry *rules and pointers*, not rationale. A rule is consulted constantly; the argument for a rule is consulted when someone questions it, which is rare and is exactly what `docs/` is for — files read on demand, free until the moment they're needed. When a decision needs recording, the table row goes in `CLAUDE.md`, the reasoning comes here. That's the same principle as `instincts.py inject --limit 5`: the store can grow without bound, but only the slice the current task needs enters the prefix.

**2. Model switching invalidates the cache.** Each model keeps its own cache, so a mid-session `/model` swap re-reads the whole prefix at full price. This does *not* mean abandoning model discipline — a wrong rework verdict costs far more than a re-read — but it does mean **batching**: group mechanical operations together on sonnet-4-6, then switch once for the judgment operation, rather than alternating turn by turn. Where a judgment op is self-contained, prefer running it as a separate headless invocation (`claude -p "/devteam-review" --model claude-opus-5 …`), which gets its own clean cache and leaves the interactive session's prefix untouched — this is already how the autopilot does every judgment call, and it's the better pattern for interactive use too.

**3. Nothing dynamic belongs above the stable content.** Timestamps, run IDs, and session junk in a prefix silently break caching on every turn. `dispatch.sh`/`.ps1` are clean on this today (composed builder prompts contain no timestamps — `RUN_TS` only names log files); keep it that way when editing prompt composition.
