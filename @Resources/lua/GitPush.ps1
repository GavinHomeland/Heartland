# =========================
# GitPush.ps1 — commit+push only if there are changes
# Adds AI-friendly repo navigation artifacts to repo root before push
# =========================
param(
  [Parameter(Mandatory=$true)][string]$RepoPath,
  [string]$Message = ""
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Write-Line([string]$s) { Write-Output $s }

# =========================
# HELPERS — FILE WRITES
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

# =========================
# HELPERS — GIT
# =========================
function Invoke-Git {
  param(
    [Parameter(Mandatory=$true)][string]$RepoRoot,
    [Parameter(Mandatory=$true)][string[]]$Args
  )
  $out = & git -C $RepoRoot @Args 2>&1
  $code = $LASTEXITCODE
  return [pscustomobject]@{ Out = ($out -join "`r`n"); Code = $code }
}

function Get-GitDefaultBranch {
  param([Parameter(Mandatory=$true)][string]$RepoRoot)

  $r = Invoke-Git -RepoRoot $RepoRoot -Args @("remote","show","origin")
  if ($r.Code -eq 0 -and $r.Out) {
    $m = ($r.Out -split "`r?`n") | Where-Object { $_ -match 'HEAD branch:\s*' } | Select-Object -First 1
    if ($m) {
      return ($m -replace '.*HEAD branch:\s*','').Trim()
    }
  }

  # Fallback: try origin/HEAD symbolic ref
  $r2 = Invoke-Git -RepoRoot $RepoRoot -Args @("symbolic-ref","--short","refs/remotes/origin/HEAD")
  if ($r2.Code -eq 0 -and $r2.Out -match '^origin\/') {
    return ($r2.Out -replace '^origin\/','').Trim()
  }

  # Last resort: current branch
  $r3 = Invoke-Git -RepoRoot $RepoRoot -Args @("rev-parse","--abbrev-ref","HEAD")
  if ($r3.Code -eq 0) { return $r3.Out.Trim() }

  return ""
}

function Get-GithubOwnerRepoFromRemote {
  param([string]$RemoteUrl)

  if ([string]::IsNullOrWhiteSpace($RemoteUrl)) { return "" }

  $u = $RemoteUrl.Trim()

  if ($u -match '^git@github\.com:(.+?)(\.git)?$') { return $Matches[1] }
  if ($u -match '^https:\/\/github\.com\/(.+?)(\.git)?$') { return $Matches[1] }
  if ($u -match '^ssh:\/\/git@github\.com\/(.+?)(\.git)?$') { return $Matches[1] }

  return ""
}

function Get-GithubHttpsBaseFromOwnerRepo {
  param([string]$OwnerRepo)
  if ([string]::IsNullOrWhiteSpace($OwnerRepo)) { return "" }
  return "https://github.com/$OwnerRepo"
}

function Get-GithubRawBaseFromOwnerRepo {
  param([string]$OwnerRepo)
  if ([string]::IsNullOrWhiteSpace($OwnerRepo)) { return "" }
  return "https://raw.githubusercontent.com/$OwnerRepo"
}

function UrlEncode-RepoPath {
  param([Parameter(Mandatory=$true)][string]$RelPath)

  $p = $RelPath.Replace('\','/').TrimStart('/')
  $segs = $p -split '/'
  $enc  = $segs | ForEach-Object { [System.Uri]::EscapeDataString($_) }
  return ($enc -join '/')
}

function Sanitize-RemoteUrl {
  param([string]$RemoteUrl)
  if ([string]::IsNullOrWhiteSpace($RemoteUrl)) { return "" }

  # Strip embedded credentials if present: https://user:token@github.com/...
  return ($RemoteUrl -replace 'https:\/\/[^@\/]+@','https://').Trim()
}

# =========================
# HELPERS — INVENTORY
# =========================
function Write-FileInventory {
  param(
    [Parameter(Mandatory=$true)][string]$RepoRoot
  )

  # NOTE: We intentionally do NOT include timestamps in the manifest to avoid diff churn.

  $manifestCsvPath = Join-Path $RepoRoot "heartland_tree.csv"
  $refsTxtPath     = Join-Path $RepoRoot "heartland_refs.txt"
  $navMdPath       = Join-Path $RepoRoot "heartland_repo_nav.md"

  # 1) Build CSV content in-memory (stable ordering, forward slashes)
  $items = Get-ChildItem -Path $RepoRoot -Recurse -File -Force |
    Where-Object {
      $_.FullName -notmatch '\\\.git\\' -and
      $_.Name -notmatch '^(heartland_tree\.csv|heartland_refs\.txt|heartland_repo_nav\.md)$'
    } |
    Select-Object `
      @{n='Path';e={$_.FullName.Substring($RepoRoot.Length + 1).Replace('\','/')}}, `
      Length |
    Sort-Object Path

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
# HELPERS — AI REPO NAV REPORT
# =========================
function Write-RepoNavReport {
  param(
    [Parameter(Mandatory=$true)][string]$RepoRoot
  )

  $navPath = Join-Path $RepoRoot "heartland_repo_nav.md"

  $originUrl = (Invoke-Git -RepoRoot $RepoRoot -Args @("remote","get-url","origin")).Out.Trim()
  $originUrlSafe = Sanitize-RemoteUrl $originUrl

  $ownerRepo = Get-GithubOwnerRepoFromRemote $originUrlSafe
  $ghBase    = Get-GithubHttpsBaseFromOwnerRepo $ownerRepo
  $rawBase   = Get-GithubRawBaseFromOwnerRepo $ownerRepo

  $curBranch = (Invoke-Git -RepoRoot $RepoRoot -Args @("rev-parse","--abbrev-ref","HEAD")).Out.Trim()
  $defBranch = Get-GitDefaultBranch -RepoRoot $RepoRoot
  if ([string]::IsNullOrWhiteSpace($defBranch)) { $defBranch = $curBranch }

  $headSha   = (Invoke-Git -RepoRoot $RepoRoot -Args @("rev-parse","HEAD")).Out.Trim()
  $recentLog = (Invoke-Git -RepoRoot $RepoRoot -Args @("log","-n","8","--oneline")).Out.Trim()

  $topTree   = (Invoke-Git -RepoRoot $RepoRoot -Args @("ls-tree","--name-only","HEAD")).Out.Trim()

  $remoteShow = (Invoke-Git -RepoRoot $RepoRoot -Args @("remote","show","origin")).Out.Trim()
  $branchesVV = (Invoke-Git -RepoRoot $RepoRoot -Args @("branch","-vv")).Out.Trim()

  # Detect key “authoritative” files by name (adjust list if you want)
  $keyNames = @(
    "Heartland Weather.ini",
    "Heartland.ini",
    "README.md"
  )

  $foundKeyFiles = @()
  foreach ($nm in $keyNames) {
    $f = Get-ChildItem -Path $RepoRoot -Recurse -File -Force |
      Where-Object { $_.FullName -notmatch '\\\.git\\' -and $_.Name -eq $nm } |
      Select-Object -First 1
    if ($f) {
      $rel = $f.FullName.Substring($RepoRoot.Length + 1).Replace('\','/')
      $foundKeyFiles += [pscustomobject]@{ Name = $nm; RelPath = $rel; FullPath = $f.FullName }
    }
  }

  # Identify tracked files with spaces (these often confuse URL navigation)
  $spacePaths = @()
  $ls = Invoke-Git -RepoRoot $RepoRoot -Args @("ls-files")
  if ($ls.Code -eq 0 -and $ls.Out) {
    $spacePaths = ($ls.Out -split "`r?`n") | Where-Object { $_ -match '\s' } | Sort-Object
  }

  # Try to pull version-ish line from Heartland Weather.ini (first 140 lines only)
  $hwVersion = ""
  $hw = $foundKeyFiles | Where-Object { $_.Name -eq "Heartland Weather.ini" } | Select-Object -First 1
  if ($hw) {
    try {
      $headLines = Get-Content -LiteralPath $hw.FullPath -TotalCount 140 -ErrorAction Stop
      $v = $headLines | Where-Object { $_ -match '(?i)\bversion\b' } | Select-Object -First 1
      if ($v) { $hwVersion = $v.Trim() }
    } catch { }
  }

  $nl = "`r`n"
  $sb = New-Object System.Text.StringBuilder

  [void]$sb.Append("# Heartland Repo Navigation Map$nl$nl")
  [void]$sb.Append("This file is generated by `GitPush.ps1` before a push. It exists to help automated readers (and humans) navigate the public GitHub repo without guessing.$nl$nl")

  [void]$sb.Append("## Identity$nl$nl")
  [void]$sb.Append("- Local repo root: `$RepoPath` (this machine)$nl")
  [void]$sb.Append("- Origin: `$originUrlSafe`$nl")
  if ($ghBase) { [void]$sb.Append("- GitHub base: $ghBase$nl") }
  [void]$sb.Append("- Current branch: `$curBranch`$nl")
  [void]$sb.Append("- Default branch (origin HEAD): `$defBranch`$nl")
  [void]$sb.Append("- HEAD commit: `$headSha`$nl$nl")

  [void]$sb.Append("## Key Files (authoritative targets)$nl$nl")
  if (-not $foundKeyFiles) {
    [void]$sb.Append("_No key files matched by name search._$nl$nl")
  } else {
    foreach ($kf in $foundKeyFiles) {
      $enc = UrlEncode-RepoPath $kf.RelPath
      if ($ghBase) {
        $blob = "$ghBase/blob/$defBranch/$enc"
        $raw  = ""
        if ($rawBase) { $raw = "$rawBase/$defBranch/$enc" }

        [void]$sb.Append("- **$($kf.Name)** — `$($kf.RelPath)`$nl")
        [void]$sb.Append("  - View (blob): $blob$nl")
        if ($raw) { [void]$sb.Append("  - Raw: $raw$nl") }
      } else {
        [void]$sb.Append("- **$($kf.Name)** — `$($kf.RelPath)`$nl")
      }
    }
    [void]$sb.Append($nl)
  }

  if ($hwVersion) {
    [void]$sb.Append("### Detected version hint (Heartland Weather.ini)$nl$nl")
    [void]$sb.Append("`$hwVersion`$nl$nl")
  }

  [void]$sb.Append("## Top-level tree (HEAD)$nl$nl")
  [void]$sb.Append("```text$nl")
  if ($topTree) { [void]$sb.Append($topTree + $nl) }
  [void]$sb.Append("```$nl$nl")

  if ($spacePaths -and $spacePaths.Count -gt 0) {
    $take = $spacePaths | Select-Object -First 30
    [void]$sb.Append("## Paths containing spaces (URL-encoding hazard)$nl$nl")
    [void]$sb.Append("GitHub URLs require encoding spaces as `%20` (or per-segment encoding). Examples:$nl$nl")
    [void]$sb.Append("```text$nl")
    foreach ($p in $take) { [void]$sb.Append($p + $nl) }
    if ($spacePaths.Count -gt 30) { [void]$sb.Append("... ($($spacePaths.Count - 30) more)$nl") }
    [void]$sb.Append("```$nl$nl")
  }

  [void]$sb.Append("## Recent commits$nl$nl")
  [void]$sb.Append("```text$nl")
  if ($recentLog) { [void]$sb.Append($recentLog + $nl) }
  [void]$sb.Append("```$nl$nl")

  [void]$sb.Append("## Remote summary$nl$nl")
  [void]$sb.Append("```text$nl")
  if ($remoteShow) { [void]$sb.Append($remoteShow + $nl) }
  [void]$sb.Append("```$nl$nl")

  [void]$sb.Append("## Branches (-vv)$nl$nl")
  [void]$sb.Append("```text$nl")
  if ($branchesVV) { [void]$sb.Append($branchesVV + $nl) }
  [void]$sb.Append("```$nl$nl")

  [void]$sb.Append("## Other generated navigation artifacts$nl$nl")
  [void]$sb.Append("- `heartland_tree.csv` — stable file manifest (path + size)$nl")
  [void]$sb.Append("- `heartland_refs.txt` — INI scan for ScriptFile/@Include/#@#/@Resources/Plugin/Measure refs$nl")

  $content = $sb.ToString()
  return (Write-TextIfChanged -Path $navPath -Content $content)
}

# =========================
# MAIN
# =========================

# Ensure RepoPath exists
if (-not (Test-Path $RepoPath)) {
  Write-Line "ERR $(Get-Date -Format s) RepoPath not found: $RepoPath"
  exit 2
}

$repoRoot = (Resolve-Path -LiteralPath $RepoPath).Path

# Optional: avoid "dubious ownership" edge cases if Rainmeter runs weirdly
& git -C $repoRoot config --local --get core.repositoryformatversion *> $null
if ($LASTEXITCODE -ne 0) {
  Write-Line "ERR $(Get-Date -Format s) Not a git repo: $RepoPath"
  exit 3
}

# -------------------------
# PRE-PUSH NAV ARTIFACTS
# -------------------------
try {
  $invChanged = Write-FileInventory -RepoRoot $repoRoot
  $navChanged = Write-RepoNavReport -RepoRoot $repoRoot

  if ($invChanged -or $navChanged) {
    Write-Line "OK  $(Get-Date -Format s) Nav artifacts updated (tree/refs/repo_nav)"
  } else {
    Write-Line "OK  $(Get-Date -Format s) Nav artifacts unchanged"
  }
} catch {
  Write-Line "ERR $(Get-Date -Format s) Nav artifact step failed: $($_.Exception.Message)"
  exit 8
}

# Check for any changes (tracked/untracked) respecting .gitignore
$st = & git -C $repoRoot status --porcelain
if ($LASTEXITCODE -ne 0) {
  Write-Line "ERR $(Get-Date -Format s) git status failed"
  exit 4
}

# Ignore generated nav artifacts when deciding whether to push
$generated = @("heartland_tree.csv","heartland_refs.txt","heartland_repo_nav.md")
$stLines = @()
if (-not [string]::IsNullOrWhiteSpace($st)) {
  $stLines = ($st -split "`r?`n") | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
}

$nonGenerated = foreach ($line in $stLines) {
  if ($line.Length -lt 4) { continue }
  $path = $line.Substring(3).Trim()

  # Handle rename format: old -> new (take new)
  if ($path -match '\s->\s') {
    $path = ($path -split '\s->\s')[-1].Trim()
  }

  $path = $path.Trim('"')
  if ($generated -notcontains $path) { $line }
}

if (-not $nonGenerated -or $nonGenerated.Count -eq 0) {
  Write-Line "OK $(Get-Date -Format s) No changes (excluding generated nav artifacts)"
  exit 0
}

# Stage everything (respects .gitignore)
& git -C $repoRoot add -A
if ($LASTEXITCODE -ne 0) {
  Write-Line "ERR $(Get-Date -Format s) git add failed"
  exit 5
}

# Build message
if ([string]::IsNullOrWhiteSpace($Message)) {
  $Message = "Update " + (Get-Date -Format "yyyy-MM-dd HH:mm")
}

# Commit
& git -C $repoRoot commit -m $Message
if ($LASTEXITCODE -ne 0) {
  $st2 = & git -C $repoRoot status --porcelain
  if ([string]::IsNullOrWhiteSpace($st2)) {
    Write-Line "OK $(Get-Date -Format s) Nothing to commit after add (ignored-only)"
    exit 0
  }
  Write-Line "ERR $(Get-Date -Format s) git commit failed"
  exit 6
}

# Push
& git -C $repoRoot push
if ($LASTEXITCODE -ne 0) {
  Write-Line "ERR $(Get-Date -Format s) git push failed"
  exit 7
}

Write-Line "OK $(Get-Date -Format s) Pushed"
exit 0
