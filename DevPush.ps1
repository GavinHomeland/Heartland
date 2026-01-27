# ============================================
# DevPush.ps1 — Manual Git push for Heartland
# ============================================
# Usage examples:
#   .\DevPush.ps1
#   .\DevPush.ps1 -RepoPath "E:\Documents\Rainmeter\Skins\Heartland"
#   .\DevPush.ps1 -Message "Fix Mesonet gate"
#   .\DevPush.ps1 -ForcePushNoChanges
# ============================================

[CmdletBinding()]
param(
  [string]$RepoPath = (Get-Location).Path,
  [string]$Message  = "",
  [switch]$ForcePushNoChanges
)

$ErrorActionPreference = "Stop"

function Run-Git {
  param([Parameter(Mandatory=$true)][string[]]$Args)
  $cmd = "git " + ($Args -join " ")
  Write-Host ">> $cmd"
  $out = & git @Args 2>&1
  $code = $LASTEXITCODE
  if ($code -ne 0) {
    throw "Git failed ($code): $cmd`n$out"
  }
  return $out
}

# --- Move to repo
if (-not (Test-Path -LiteralPath $RepoPath)) {
  throw "RepoPath not found: $RepoPath"
}
Set-Location -LiteralPath $RepoPath

# --- Sanity: git present?
try { & git --version | Out-Null } catch { throw "git is not available in PATH." }

# --- Sanity: inside repo?
try {
  $inside = (Run-Git @("rev-parse","--is-inside-work-tree")).Trim()
  if ($inside -ne "true") { throw "Not inside a git work tree." }
} catch {
  throw "This folder is not a git repo: $RepoPath"
}

# --- If you ever hit 'dubious ownership', auto-trust this repo path
# (Safe: scoped to this exact path only)
try {
  Run-Git @("config","--global","--add","safe.directory",$RepoPath) | Out-Null
} catch {
  # ignore if it fails for some reason; it’s just a convenience
}

# --- Determine branch
$branch = (Run-Git @("rev-parse","--abbrev-ref","HEAD")).Trim()
if ([string]::IsNullOrWhiteSpace($branch) -or $branch -eq "HEAD") {
  throw "Could not determine current branch."
}

# --- Ensure origin exists
$remotes = Run-Git @("remote")
if ($remotes -notmatch "(?m)^origin$") {
  throw "Remote 'origin' not found. Add it first: git remote add origin <url>"
}

# --- Stage everything
Run-Git @("add","-A") | Out-Null

# --- Check if anything changed
$porcelain = Run-Git @("status","--porcelain")
$hasChanges = -not [string]::IsNullOrWhiteSpace($porcelain)

if ($hasChanges) {
  if ([string]::IsNullOrWhiteSpace($Message)) {
    $Message = "Dev push " + (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
