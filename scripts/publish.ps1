param(
  [string]$CommitMessage = "chore: publish blog update",
  [string]$Branch = "main",
  [switch]$SkipSync
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Step([string]$Message) {
  Write-Host "[publish] $Message" -ForegroundColor Cyan
}

$siteRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Push-Location $siteRoot
try {
  if (-not $SkipSync) {
    Write-Step "Syncing Obsidian notes into Hugo content"
    & (Join-Path $PSScriptRoot "sync-obsidian-to-hugo.ps1") -RunBuild
  }

  Write-Step "Checking git repository"
  $isRepo = $false
  try {
    git rev-parse --is-inside-work-tree 1>$null 2>$null
    $isRepo = ($LASTEXITCODE -eq 0)
  } catch {
    $isRepo = $false
  }

  if (-not $isRepo) {
    throw "Current directory is not a Git repository. Run scripts/init-github-pages.ps1 first."
  }

  git add .
  git diff --cached --quiet
  if ($LASTEXITCODE -ne 0) {
    git commit -m $CommitMessage
    git push origin $Branch
    Write-Step "Published to $Branch"
  } else {
    Write-Step "No changes to publish"
  }
} finally {
  Pop-Location
}
