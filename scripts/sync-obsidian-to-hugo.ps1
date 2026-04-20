param(
  [string]$ConfigPath = (Join-Path $PSScriptRoot "obsidian-sync.config.json"),
  [string]$SourceBlogDir,
  [string]$SiteRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path,
  [switch]$RunBuild
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Step([string]$Message) {
  Write-Host "[obsidian-sync] $Message" -ForegroundColor Cyan
}

function ConvertTo-TomlEscapedString([string]$Value) {
  return ($Value -replace '\\', '\\\\' -replace '"', '\"')
}

function Get-DefaultTitle([string]$Body, [string]$FileBaseName) {
  $heading = [regex]::Match($Body, '(?m)^\s*#\s+(.+?)\s*$')
  if ($heading.Success) {
    return $heading.Groups[1].Value.Trim()
  }

  $title = ($FileBaseName -replace '[-_]+', ' ').Trim()
  if ([string]::IsNullOrWhiteSpace($title)) {
    return "Untitled"
  }

  return $title
}

function Set-FrontMatterDefaults([string]$Content, [string]$FileBaseName, [datetime]$DefaultDate, [bool]$DefaultDraft = $true) {
  $dateText = $DefaultDate.ToString("yyyy-MM-ddTHH:mm:ssK")
  $draftTextToml = if ($DefaultDraft) { "true" } else { "false" }
  $draftTextYaml = if ($DefaultDraft) { "true" } else { "false" }
  $normalized = if ($null -eq $Content) { "" } else { $Content }

  $tomlMatch = [regex]::Match($normalized, '^\+\+\+\r?\n(?<fm>[\s\S]*?)\r?\n\+\+\+\r?\n?', [System.Text.RegularExpressions.RegexOptions]::Singleline)
  if ($tomlMatch.Success) {
    $fm = $tomlMatch.Groups["fm"].Value.Trim()
    $body = $normalized.Substring($tomlMatch.Length)
    $title = Get-DefaultTitle -Body $body -FileBaseName $FileBaseName
    $escapedTitle = ConvertTo-TomlEscapedString -Value $title

    if ($fm -notmatch '(?m)^title\s*=') { $fm += "`ntitle = `"$escapedTitle`"" }
    if ($fm -notmatch '(?m)^date\s*=') { $fm += "`ndate = $dateText" }
    if ($fm -match '(?m)^draft\s*=') {
      $fm = [regex]::Replace($fm, '(?m)^draft\s*=.*$', "draft = $draftTextToml")
    } else {
      $fm += "`ndraft = $draftTextToml"
    }
    if ($fm -notmatch '(?m)^tags\s*=') { $fm += "`ntags = []" }
    if ($fm -notmatch '(?m)^categories\s*=') { $fm += "`ncategories = []" }
    if ($fm -notmatch '(?m)^summary\s*=') { $fm += "`nsummary = `"`"" }

    $cleanBody = $body.TrimStart("`r", "`n")
    return "+++`n$($fm.Trim())`n+++`n`n$cleanBody"
  }

  $yamlMatch = [regex]::Match($normalized, '^---\r?\n(?<fm>[\s\S]*?)\r?\n---\r?\n?', [System.Text.RegularExpressions.RegexOptions]::Singleline)
  if ($yamlMatch.Success) {
    $fm = $yamlMatch.Groups["fm"].Value.Trim()
    $body = $normalized.Substring($yamlMatch.Length)
    $title = Get-DefaultTitle -Body $body -FileBaseName $FileBaseName

    if ($fm -notmatch '(?m)^title\s*:') { $fm += "`ntitle: `"$title`"" }
    if ($fm -notmatch '(?m)^date\s*:') { $fm += "`ndate: `"$dateText`"" }
    if ($fm -match '(?m)^draft\s*:') {
      $fm = [regex]::Replace($fm, '(?m)^draft\s*:.*$', "draft: $draftTextYaml")
    } else {
      $fm += "`ndraft: $draftTextYaml"
    }
    if ($fm -notmatch '(?m)^tags\s*:') { $fm += "`ntags: []" }
    if ($fm -notmatch '(?m)^categories\s*:') { $fm += "`ncategories: []" }
    if ($fm -notmatch '(?m)^summary\s*:') { $fm += "`nsummary: `"`"" }

    $cleanBody = $body.TrimStart("`r", "`n")
    return "---`n$($fm.Trim())`n---`n`n$cleanBody"
  }

  $defaultTitle = Get-DefaultTitle -Body $normalized -FileBaseName $FileBaseName
  $escapedDefaultTitle = ConvertTo-TomlEscapedString -Value $defaultTitle
  $frontMatter = @(
    "+++",
    "title = `"$escapedDefaultTitle`"",
    "date = $dateText",
    "draft = $draftTextToml",
    "tags = []",
    "categories = []",
    "summary = `"`"",
    "+++",
    ""
  ) -join "`n"

  return "$frontMatter$normalized"
}

$config = $null
if (Test-Path $ConfigPath) {
  $config = Get-Content -Path $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
}

if ([string]::IsNullOrWhiteSpace($SourceBlogDir) -and $null -ne $config -and $null -ne $config.sourceBlogDir) {
  $SourceBlogDir = [string]$config.sourceBlogDir
}

if ([string]::IsNullOrWhiteSpace($SourceBlogDir)) {
  throw "SourceBlogDir is required."
}

$managedSubdir = "obsidian"
if ($null -ne $config -and $null -ne $config.managedSubdir -and -not [string]::IsNullOrWhiteSpace([string]$config.managedSubdir)) {
  $managedSubdir = [string]$config.managedSubdir
}

$defaultDraft = $true
if ($null -ne $config -and $null -ne $config.defaultDraft) {
  try {
    $defaultDraft = [bool]$config.defaultDraft
  } catch {
    $defaultDraft = $true
  }
}

$postsFolders = @("`u6587`u7AE0", "`u535A`u5BA2", "`u6280`u672F", "`u5B66`u4E60", "posts", "post", "blog", "tech", "study")
$notesFolders = @("`u6742`u8BB0", "`u7B14`u8BB0", "`u751F`u6D3B", "`u65E5`u8BB0", "notes", "note", "life", "journal", "daily")
$projectFolders = @("`u9879`u76EE", "projects", "project")

if ($null -ne $config -and $null -ne $config.mapping) {
  if ($null -ne $config.mapping.posts) { $postsFolders = @($config.mapping.posts) }
  if ($null -ne $config.mapping.notes) { $notesFolders = @($config.mapping.notes) }
  if ($null -ne $config.mapping.projects) { $projectFolders = @($config.mapping.projects) }
}

$postsFolders = @($postsFolders | ForEach-Object { $_.ToString().ToLowerInvariant() })
$notesFolders = @($notesFolders | ForEach-Object { $_.ToString().ToLowerInvariant() })
$projectFolders = @($projectFolders | ForEach-Object { $_.ToString().ToLowerInvariant() })

function Resolve-Destination([string]$RelativePath) {
  $normalized = $RelativePath -replace '\\', '/'
  $parts = @($normalized.Split('/') | Where-Object { $_ -ne "" })

  $section = "posts"
  $consumeFirst = $false

  if ($parts.Count -gt 0) {
    $first = $parts[0].ToLowerInvariant()

    if ($projectFolders -contains $first) {
      $section = "projects"
      $consumeFirst = $true
    } elseif ($notesFolders -contains $first) {
      $section = "notes"
      $consumeFirst = $true
    } elseif ($postsFolders -contains $first) {
      $section = "posts"
      $consumeFirst = $true
    }
  }

  $subParts = @()
  if ($consumeFirst -and $parts.Count -gt 1) {
    $subParts = $parts[1..($parts.Count - 1)]
  } elseif ($consumeFirst) {
    $subParts = @([IO.Path]::GetFileName($normalized))
  } else {
    $subParts = $parts
  }

  if ($subParts.Count -eq 0) {
    $subParts = @([IO.Path]::GetFileName($normalized))
  }

  $subPath = ($subParts -join '/')
  return [PSCustomObject]@{
    Section = $section
    SubPath = $subPath
  }
}

$pythonFromVenv = Join-Path $SiteRoot ".venv\Scripts\python.exe"
$script:UsePyLauncher = $false
$script:PythonExe = $null

if (Test-Path $pythonFromVenv) {
  $script:PythonExe = $pythonFromVenv
} else {
  $pythonCmd = Get-Command python -ErrorAction SilentlyContinue
  if ($pythonCmd) {
    $script:PythonExe = $pythonCmd.Source
  } else {
    $pyCmd = Get-Command py -ErrorAction SilentlyContinue
    if ($pyCmd) {
      $script:UsePyLauncher = $true
    } else {
      throw "Python not found. Install Python 3.11+ or create .venv in this project."
    }
  }
}

function Invoke-Python([string[]]$Arguments) {
  if ($script:UsePyLauncher) {
    & py -3 @Arguments
  } else {
    & $script:PythonExe @Arguments
  }

  if ($LASTEXITCODE -ne 0) {
    throw "Python command failed: $($Arguments -join ' ')"
  }
}

if (-not (Test-Path $SourceBlogDir)) {
  throw "Source directory not found: $SourceBlogDir"
}

Write-Step "Checking obsidian-to-hugo package"
if ($script:UsePyLauncher) {
  & py -3 -c "import importlib.util,sys;sys.exit(0 if importlib.util.find_spec('obsidian_to_hugo') else 1)"
} else {
  & $script:PythonExe -c "import importlib.util,sys;sys.exit(0 if importlib.util.find_spec('obsidian_to_hugo') else 1)"
}

if ($LASTEXITCODE -ne 0) {
  Write-Step "Installing obsidian-to-hugo"
  Invoke-Python -Arguments @("-m", "pip", "install", "obsidian-to-hugo")
}

$contentRoot = Join-Path $SiteRoot "content"
$stagingDir = Join-Path $SiteRoot ".obsidian-export-staging"
$managedRoots = @(
  (Join-Path $contentRoot ("posts\" + $managedSubdir)),
  (Join-Path $contentRoot ("notes\" + $managedSubdir)),
  (Join-Path $contentRoot ("projects\" + $managedSubdir))
)

Write-Step "Cleaning staging and managed folders"
if (Test-Path $stagingDir) {
  Remove-Item -Path $stagingDir -Recurse -Force
}
foreach ($path in $managedRoots) {
  if (Test-Path $path) {
    Remove-Item -Path $path -Recurse -Force
  }
}
New-Item -ItemType Directory -Path $stagingDir -Force | Out-Null

Write-Step "Converting Obsidian notes"
Invoke-Python -Arguments @(
  "-m", "obsidian_to_hugo",
  "--obsidian-vault-dir", $SourceBlogDir,
  "--hugo-content-dir", $stagingDir
)

$files = Get-ChildItem -Path $stagingDir -Recurse -File
$markdownCount = 0
$assetCount = 0

foreach ($file in $files) {
  $relativePath = $file.FullName.Substring($stagingDir.Length).TrimStart("\", "/")
  $target = Resolve-Destination -RelativePath $relativePath
  $targetRoot = Join-Path (Join-Path $contentRoot $target.Section) $managedSubdir
  $targetPath = Join-Path $targetRoot ($target.SubPath -replace '/', '\\')
  $targetDir = Split-Path -Path $targetPath -Parent

  if (-not (Test-Path $targetDir)) {
    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
  }

  if ($file.Extension.ToLowerInvariant() -eq ".md") {
    $raw = Get-Content -Path $file.FullName -Raw -Encoding UTF8
    if ($null -eq $raw) { $raw = "" }
    $raw = [regex]::Replace($raw, '\{\{<\s*ref\s+"([^"]+)"\s*>\}\}', './$1')
    $fixed = Set-FrontMatterDefaults -Content $raw -FileBaseName ([IO.Path]::GetFileNameWithoutExtension($file.Name)) -DefaultDate $file.LastWriteTime -DefaultDraft $defaultDraft
    Set-Content -Path $targetPath -Value $fixed -Encoding UTF8
    $markdownCount += 1
  } else {
    Copy-Item -Path $file.FullName -Destination $targetPath -Force
    $assetCount += 1
  }
}

Write-Step "Synced $markdownCount markdown files and $assetCount assets"

if ($RunBuild) {
  Write-Step "Running Hugo build"
  Push-Location $SiteRoot
  try {
    hugo --minify
  } finally {
    Pop-Location
  }
}
