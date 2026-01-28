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

# =========================
# HELPERS — INVENTORY
# =========================
function Write-TextIfChanged {
  param(
    [Parameter(Mandatory=$true)][string]$Path,
    [Parameter(Mandatory=$true)][string]$Content,
    [string]$Encoding = "UTF8"
  )

  if (Test-Path $Path) {
    $old = Get-Content -Raw -LiteralPath $Path -ErrorAction SilentlyContinue
    if ($old -eq $Content) { return $false } # no change
  }

  Set-Content -LiteralPath $Path -Value $Content -Encoding $Encoding
  return $true
}

function Write-FileInventory {
  param(
    [Parameter(Mandatory=$true)][string]$RepoRoot
  )

  # NOTE: We intentionally do NOT include timestamps in the manifest to avoid diff churn.
  # If you ever WANT timestamps, add LastWriteTimeUtc back in.

  $manifestCsvPath = Join-Path $RepoRoot "heartland_tree.csv"
  $refsTxtPath     = Join-Path $RepoRoot "heartland_refs.txt"

  # 1) Build CSV content in-memory (stable ordering, forward slashes)
  $items = Get-ChildItem -Path $RepoRoot -Recurse -File -Force |
    Where-Object {
      $_.FullName -notmatch '\\\.git\\' -and
      $_.Name -notmatch '^(heartland_tree\.csv|heartland_refs\.txt)$'
    } |
    Select-Object `
      @{n='Path';e={$_.FullName.Substring($RepoRoot.Length + 1).Replace('\','/')}}, `
      Length |
    Sort-Object Path

  # Convert to CSV string with stable header order
  $csv = $items | ConvertTo-Csv -NoTypeInformation
  $csvText = ($csv -join "`r`n") + "`r`n"

  # 2) Build refs scan (only INI files)
  $iniFiles = Get-ChildItem -Path $RepoRoot -Recurse -File -Force -Filter "*.ini" |
    Where-Object { $_.FullName -notmatch '\\\.git\\' }

  $refMatches = foreach ($f in $iniFiles) {
    Select-String -LiteralPath $f.FullName -Pattern '^\s*ScriptFile\s*=|^\s*@Include\s*=|#@#|@Resources|^\s*Plugin\s*=|^\s*Measure\s*=' |
      ForEach-Object {
        "{0}:{1}: {2}" -f $f.FullName.Substring($RepoRoot.Length + 1).Replace('\','/'), $_.LineNumber, $_.Line.TrimEnd()
      }
  }

  $refsText = ""
  if ($refMatches) {
    $refsText = ($refMatches | Sort-Object) -join "`r`n"
    $refsText += "`r`n"
  }

  $changed = $false
  if (Write-TextIfChanged -Path $manifestCsvPath -Content $csvText) { $changed = $true }
  if (Write-TextIfChanged -Path $refsTxtPath     -Content $refsText) { $changed = $true }

  return $changed
}

# =========================
# MAIN
# =========================

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

# -------------------------
# PRE-PUSH INVENTORY
# -------------------------
try {
  $invChanged = Write-FileInventory -RepoRoot (Resolve-Path -LiteralPath $RepoPath).Path
  if ($invChanged) {
    Write-Line "OK  $(Get-Date -Format s) Inventory updated (heartland_tree.csv, heartland_refs.txt)"
  } else {
    Write-Line "OK  $(Get-Date -Format s) Inventory unchanged"
  }
} catch {
  Write-Line "ERR $(Get-Date -Format s) Inventory step failed: $($_.Exception.Message)"
  exit 8
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