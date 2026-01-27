# =========================
# GitPush.ps1 — commit+push only if there are changes
# =========================
param(
  [Parameter(Mandatory=$true)][string]$RepoPath,
  [string]$Message = ""
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Write-Line([string]$s) { Write-Output $s }

# Ensure RepoPath exists
if (-not (Test-Path $RepoPath)) {
  Write-Line "ERR $(Get-Date -Format s) RepoPath not found: $RepoPath"
  exit 2
}

# Use -C so we don't care what Rainmeter's working dir is
$git = "git"

# Optional: avoid "dubious ownership" edge cases if Rainmeter runs weirdly
& $git -C $RepoPath config --local --get core.repositoryformatversion *> $null
if ($LASTEXITCODE -ne 0) {
  Write-Line "ERR $(Get-Date -Format s) Not a git repo: $RepoPath"
  exit 3
}

# Check for any changes (tracked/untracked) respecting .gitignore
$st = & $git -C $RepoPath status --porcelain
if ($LASTEXITCODE -ne 0) {
  Write-Line "ERR $(Get-Date -Format s) git status failed"
  exit 4
}

if ([string]::IsNullOrWhiteSpace($st)) {
  Write-Line "OK $(Get-Date -Format s) No changes"
  exit 0
}

# Stage everything (respects .gitignore)
& $git -C $RepoPath add -A
if ($LASTEXITCODE -ne 0) {
  Write-Line "ERR $(Get-Date -Format s) git add failed"
  exit 5
}

# Build message
if ([string]::IsNullOrWhiteSpace($Message)) {
  $Message = "Update " + (Get-Date -Format "yyyy-MM-dd HH:mm")
}

# Commit (will still fail if add staged nothing, but status showed changes so unlikely)
& $git -C $RepoPath commit -m $Message
if ($LASTEXITCODE -ne 0) {
  # Fall back: maybe only ignored changes remained; treat as OK
  $st2 = & $git -C $RepoPath status --porcelain
  if ([string]::IsNullOrWhiteSpace($st2)) {
    Write-Line "OK $(Get-Date -Format s) Nothing to commit after add (ignored-only)"
    exit 0
  }
  Write-Line "ERR $(Get-Date -Format s) git commit failed"
  exit 6
}

# Push
& $git -C $RepoPath push
if ($LASTEXITCODE -ne 0) {
  Write-Line "ERR $(Get-Date -Format s) git push failed"
  exit 7
}

Write-Line "OK $(Get-Date -Format s) Pushed"
exit 0
