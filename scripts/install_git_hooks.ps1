<#
.SYNOPSIS
    Point this clone's git hooks at the tracked hooks/git/ directory, so the
    territory pre-commit backstop (hooks/pre-commit-territory.js) runs.
.DESCRIPTION
    One-time per machine/clone: core.hooksPath is a repo-config setting, so
    it applies to the main checkout AND every `git worktree add` sibling
    automatically — run this once from the main checkout, not once per
    worktree.
#>
$ErrorActionPreference = "Stop"
$RepoRoot = (git rev-parse --show-toplevel).Trim()
Set-Location $RepoRoot
git config core.hooksPath hooks/git
Write-Host "[install_git_hooks] core.hooksPath -> hooks/git (repo-wide, all worktrees)." -ForegroundColor Green
