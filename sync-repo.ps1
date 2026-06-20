param(
    [string]$Message = ""
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $repoRoot

if (-not (Test-Path .git)) {
    Write-Error "No git repository found in $repoRoot"
    exit 1
}

$branch = git rev-parse --abbrev-ref HEAD
if (-not $Message) {
    $Message = "Sync repository from local changes on branch $branch"
}

Write-Host "[sync-repo] Branch: $branch"
git status --short

Write-Host "[sync-repo] Staging changes..."
git add -A

$hasChanges = $LASTEXITCODE -eq 0

$diffIndex = git diff --cached --quiet
if ($LASTEXITCODE -ne 0) {
    Write-Host "[sync-repo] Committing changes: $Message"
    git commit -m "$Message"
} else {
    Write-Host "[sync-repo] No staged changes to commit."
}

Write-Host "[sync-repo] Pushing to origin/$branch..."
git push origin "$branch"
Write-Host "[sync-repo] Done."
