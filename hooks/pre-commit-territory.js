#!/usr/bin/env node
/**
 * pre-commit-territory.js — git-level BACKSTOP for territorial isolation.
 *
 * WHY THIS EXISTS (distinct from territory-firewall.js)
 * ------------------------------------------------------
 * territory-firewall.js is a Claude Code PreToolUse hook: it only fires
 * inside a literal `claude` CLI session (S5/S5B), because only that CLI
 * reads .claude/settings.json's hooks wiring. GB (grok) and CX/CX9 (codex)
 * never see it — every Edit/Write they make is completely unchecked at
 * write time. This script is CLI-agnostic: it runs as a real git hook at
 * `git commit`, so it catches GB and CX/CX9 too, plus anything that slips
 * past the Claude-side hook (a genuine backstop, not a duplicate).
 *
 * Reuses hooks/lib.js's PLAN.md parsing and glob logic verbatim — the
 * Owned_Paths grammar must never diverge between the two enforcement
 * points, so there is exactly one parser and one glob matcher in this repo.
 *
 * FAIL POSTURE (matches territory-firewall.js's own documented split)
 * ---------------------------------------------------------------------
 *  - DEVTEAM_UNIT unset            -> allow (interactive/ORCH commit).
 *  - DEVTEAM_UNIT = ORCH           -> allow (structural authority).
 *  - DEVTEAM_UNIT set, unknown     -> BLOCK (fail-closed; same fix as the
 *                                     v4.7 firewall security fix — an
 *                                     unrecognized unit must never be
 *                                     silently treated as unrestricted).
 *  - Commit touches ONLY PLAN.md   -> allow unconditionally (this is
 *                                     plan_commit.sh's own commit, which
 *                                     runs from the MAIN checkout, not a
 *                                     worktree; block-level PLAN.md
 *                                     discipline stays with
 *                                     validate_plan.py + review, per the
 *                                     same split lib.js documents).
 *  - Known unit, staged files      -> BLOCK any file outside every one of
 *    outside Owned_Paths              that unit's active tasks' Owned_Paths.
 *  - Unexpected internal error     -> allow, with a loud stderr warning.
 *    (git/node failure, unreadable    A hook bug must never brick every
 *    PLAN.md, etc.)                   commit in the repo; the validator and
 *                                     human review remain the real backstop
 *                                     for that failure class, exactly as
 *                                     territory-firewall.js's own top-level
 *                                     catch already works.
 *
 * Exit codes per git's pre-commit contract: 0 = allow, non-zero = block.
 */
'use strict';

const { execSync } = require('child_process');
const path = require('path');
const fs = require('fs');
const lib = require('./lib.js');

function sh(cmd, cwd) {
  return execSync(cmd, { cwd, encoding: 'utf-8' }).trim();
}

function main() {
  const unit = lib.unit();
  if (unit === null) {
    process.stderr.write(
      `[pre-commit-territory] BLOCKED: DEVTEAM_UNIT='${process.env.DEVTEAM_UNIT}' is not a ` +
      `known unit (${lib.knownUnits().join('/')}) — refusing to treat an unrecognized unit as ` +
      `unrestricted. Fix DEVTEAM_UNIT or define the unit in autopilot.json's builders registry.\n`
    );
    return 1;
  }
  if (unit === 'ORCH') return 0;

  const cwd = process.cwd();
  const staged = sh('git diff --cached --name-only --diff-filter=ACMR', cwd)
    .split('\n')
    .map((s) => s.trim())
    .filter(Boolean);
  if (staged.length === 0) return 0; // nothing staged (e.g. an empty/amend commit)

  // plan_commit.sh's own commit: pathspec-scoped to PLAN.md alone, run from
  // the main checkout. Always allowed — block-level PLAN.md discipline is
  // validate_plan.py + review's job, not this hook's.
  if (staged.length === 1 && staged[0] === 'PLAN.md') return 0;

  let repoRoot = cwd;
  try {
    repoRoot = sh('git rev-parse --show-toplevel', cwd);
  } catch (_e) { /* keep cwd */ }

  let planText = '';
  try {
    planText = fs.readFileSync(path.join(repoRoot, 'PLAN.md'), 'utf-8');
  } catch (_e) {
    process.stderr.write(
      `[pre-commit-territory] WARNING: could not read PLAN.md at ${repoRoot} — allowing commit ` +
      `(cannot check territory without it; validator + review remain the backstop).\n`
    );
    return 0;
  }

  const tasks = lib.parsePlan(planText);
  const active = lib.activeTasksFor(tasks, unit);
  if (active.length === 0) {
    process.stderr.write(
      `[pre-commit-territory] WARNING: unit ${unit} has no claimed/in_progress/needs_review task ` +
      `in PLAN.md at ${repoRoot} — allowing commit (nothing to check territory against; this is ` +
      `unusual for a builder commit and worth a second look).\n`
    );
    return 0;
  }

  const owned = active.flatMap((t) => lib.ownedPathsOf(t));
  const violations = staged.filter(
    (f) => f !== 'PLAN.md' && !lib.pathInAnyGlob(f, owned)
  );

  if (violations.length > 0) {
    process.stderr.write(
      `[pre-commit-territory] BLOCKED: ${unit}'s commit touches file(s) outside its Owned_Paths ` +
      `(${active.map((t) => t.task_id).join(', ')}):\n` +
      violations.map((f) => `  - ${f}`).join('\n') + '\n' +
      `Owned_Paths for these task(s): ${owned.join(', ') || '(none declared)'}\n` +
      `If this file is genuinely needed, set the task to blocked (Blocked_Reason: ` +
      `OWNERSHIP_CONFLICT) with a Progress_Note explaining exactly why — do not commit outside ` +
      `territory to work around it.\n`
    );
    return 1;
  }

  return 0;
}

try {
  process.exit(main());
} catch (e) {
  process.stderr.write(
    `[pre-commit-territory] WARNING: hook crashed unexpectedly (${e && e.message}) — allowing ` +
    `commit. A hook bug must never brick every commit in the repo; validator + review remain the ` +
    `backstop.\n`
  );
  process.exit(0);
}
