#!/usr/bin/env bash
# install_git_hooks.sh — point this clone's git hooks at the tracked
# hooks/git/ directory, so the territory pre-commit backstop
# (hooks/pre-commit-territory.js) actually runs.
#
# One-time per machine/clone: `core.hooksPath` is a repo-config setting
# (not a worktree-config one unless extensions.worktreeConfig is set), so it
# applies to the main checkout AND every `git worktree add` sibling
# automatically — run this once from the main checkout, not once per
# worktree.
set -euo pipefail
REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"
chmod +x hooks/git/pre-commit
git config core.hooksPath hooks/git
echo "[install_git_hooks] core.hooksPath -> hooks/git (repo-wide, all worktrees)."
