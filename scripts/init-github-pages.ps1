param(
  [string]$Owner = "jackycjrt",
  [string]$RepoName = "personal-blog-v2",
  [ValidateSet("public", "private")]
  [string]$Visibility = "public",
  [string]$Branch = "main"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Step([string]$Message) {
  Write-Host "[github-init] $Message" -ForegroundColor Cyan
}

$siteRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Push-Location $siteRoot
try {
  Write-Step "Ensuring local git repository"
  $isRepo = $false
  try {
    git rev-parse --is-inside-work-tree 1>$null 2>$null
    $isRepo = ($LASTEXITCODE -eq 0)
  } catch {
    $isRepo = $false
  }

  if (-not $isRepo) {
    git init -b $Branch
  }

  $currentBranch = git branch --show-current
  if ([string]::IsNullOrWhiteSpace($currentBranch)) {
    git checkout -b $Branch
  } elseif ($currentBranch -ne $Branch) {
    git checkout $Branch
  }

  $configuredName = git config user.name
  if ([string]::IsNullOrWhiteSpace($configuredName)) {
    git config user.name $Owner
  }

  $configuredEmail = git config user.email
  if ([string]::IsNullOrWhiteSpace($configuredEmail)) {
    git config user.email "$Owner@users.noreply.github.com"
  }

  Write-Step "Creating initial commit when needed"
  $hasCommit = $true
  try {
    git rev-parse --verify HEAD 1>$null 2>$null
    $hasCommit = ($LASTEXITCODE -eq 0)
  } catch {
    $hasCommit = $false
  }

  git add .
  if (-not $hasCommit) {
    git commit -m "chore: initialize blog workflow"
  } else {
    git diff --cached --quiet
    if ($LASTEXITCODE -ne 0) {
      git commit -m "chore: update blog workflow"
    }
  }

  Write-Step "Checking GitHub CLI authentication"
  gh auth status
  if ($LASTEXITCODE -ne 0) {
    throw "GitHub CLI is not authenticated. Run gh auth login and rerun this script."
  }

  $repo = "$Owner/$RepoName"
  Write-Step "Preparing remote repository $repo"

  $repoExists = $false
  try {
    gh repo view $repo 1>$null 2>$null
    $repoExists = ($LASTEXITCODE -eq 0)
  } catch {
    $repoExists = $false
  }

  $hasOrigin = $false
  try {
    git remote get-url origin 1>$null 2>$null
    $hasOrigin = ($LASTEXITCODE -eq 0)
  } catch {
    $hasOrigin = $false
  }

  if (-not $repoExists) {
    gh repo create $repo --$Visibility --source . --remote origin --push --description "Personal Hugo blog with Obsidian workflow"
  } else {
    if (-not $hasOrigin) {
      git remote add origin "https://github.com/$repo.git"
    }
    git push -u origin $Branch
  }

  Write-Step "Done"
} finally {
  Pop-Location
}
