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

function Resolve-ExistingPath([string[]]$Candidates) {
  foreach ($candidate in $Candidates) {
    if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate)) {
      return (Resolve-Path -LiteralPath $candidate).Path
    }
  }

  return $null
}

function Find-VaultFileByName([string]$RootPath, [string]$FileName) {
  if ([string]::IsNullOrWhiteSpace($RootPath) -or [string]::IsNullOrWhiteSpace($FileName) -or -not (Test-Path -LiteralPath $RootPath)) {
    return $null
  }

  $match = Get-ChildItem -LiteralPath $RootPath -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -eq $FileName } |
    Select-Object -First 1

  if ($null -ne $match) {
    return $match.FullName
  }

  return $null
}

function Ensure-ParentDirectory([string]$Path) {
  $parent = Split-Path -Path $Path -Parent
  if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent)) {
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
  }
}

function Resolve-AssetSource([string]$AssetPath, [string]$CurrentSourceDir, [string]$SourceBlogDir, [string]$VaultDir) {
  $normalized = ($AssetPath -replace '\\', '/').Trim()
  $trimmed = $normalized.TrimStart('./')
  $fileName = [IO.Path]::GetFileName($trimmed)
  $currentDir = if ([string]::IsNullOrWhiteSpace($CurrentSourceDir)) { $SourceBlogDir } else { $CurrentSourceDir }

  $candidatePaths = @()
  if (-not [string]::IsNullOrWhiteSpace($currentDir)) {
    $candidatePaths += (Join-Path $currentDir ($trimmed -replace '/', '\'))
  }
  if (-not [string]::IsNullOrWhiteSpace($SourceBlogDir)) {
    $candidatePaths += (Join-Path $SourceBlogDir ($trimmed -replace '/', '\'))
  }
  if (-not [string]::IsNullOrWhiteSpace($VaultDir)) {
    $candidatePaths += (Join-Path $VaultDir ($trimmed -replace '/', '\'))
  }

  $resolved = Resolve-ExistingPath -Candidates $candidatePaths
  if ($null -ne $resolved) {
    return [PSCustomObject]@{
      SourcePath = $resolved
      OutputRelativePath = $trimmed
    }
  }

  if (-not [string]::IsNullOrWhiteSpace($fileName)) {
    $resolved = Find-VaultFileByName -RootPath $SourceBlogDir -FileName $fileName
    if ($null -eq $resolved) {
      $resolved = Find-VaultFileByName -RootPath $VaultDir -FileName $fileName
    }
    if ($null -ne $resolved) {
      return [PSCustomObject]@{
        SourcePath = $resolved
        OutputRelativePath = $fileName
      }
    }
  }

  return $null
}

function Resolve-ExcalidrawAsset([string]$AssetPath, [string]$CurrentSourceDir, [string]$SourceBlogDir, [string]$VaultDir) {
  $trimmed = ($AssetPath -replace '\\', '/').Trim().TrimStart('./')
  $withoutMd = if ($trimmed.EndsWith('.md')) { $trimmed.Substring(0, $trimmed.Length - 3) } else { $trimmed }
  $baseName = [IO.Path]::GetFileNameWithoutExtension($withoutMd)
  $relativeDir = Split-Path -Path ($withoutMd -replace '/', '\') -Parent

  $extensions = @('.svg', '.png', '.jpg', '.jpeg', '.webp')
  foreach ($extension in $extensions) {
    $relativeAsset = if ([string]::IsNullOrWhiteSpace($relativeDir)) {
      "$baseName$extension"
    } else {
      (($relativeDir -replace '\\', '/') + "/$baseName$extension")
    }

    $resolved = Resolve-AssetSource -AssetPath $relativeAsset -CurrentSourceDir $CurrentSourceDir -SourceBlogDir $SourceBlogDir -VaultDir $VaultDir
    if ($null -ne $resolved) {
      return $resolved
    }
  }

  return $null
}

function Sync-MarkdownAssets([string]$Content, [string]$CurrentSourceDir, [string]$TargetDir, [string]$SourceBlogDir, [string]$VaultDir) {
  $assetCount = 0
  $warnings = New-Object System.Collections.Generic.List[string]

  $rewritten = [regex]::Replace(
    $Content,
    '!\[(?<alt>[^\]]*)\]\((?<path>[^)]+)\)',
    {
      param($match)

      $alt = $match.Groups['alt'].Value
      $originalPath = $match.Groups['path'].Value.Trim()
      $asset = $null
      $outputPath = $null

      if ($originalPath -match '\.excalidraw(\.[^/\)]+)?\.md$') {
        $asset = Resolve-ExcalidrawAsset -AssetPath $originalPath -CurrentSourceDir $CurrentSourceDir -SourceBlogDir $SourceBlogDir -VaultDir $VaultDir
        if ($null -eq $asset) {
          $warnings.Add("Missing exported Excalidraw asset for '$originalPath'")
          return $match.Value
        }
      } else {
        $asset = Resolve-AssetSource -AssetPath $originalPath -CurrentSourceDir $CurrentSourceDir -SourceBlogDir $SourceBlogDir -VaultDir $VaultDir
        if ($null -eq $asset) {
          return $match.Value
        }
      }

      $outputPath = Join-Path $TargetDir ($asset.OutputRelativePath -replace '/', '\')
      Ensure-ParentDirectory -Path $outputPath
      Copy-Item -LiteralPath $asset.SourcePath -Destination $outputPath -Force
      $assetCount += 1

      # Hugo renders `content/foo.md` to `/foo/index.html`, so sibling assets
      # end up one level above the final page URL.
      $webPath = '../' + ($asset.OutputRelativePath -replace '\\', '/')
      if ($webPath -match '\s') {
        $webPath = '<' + $webPath + '>'
      }
      return '![' + $alt + '](' + $webPath + ')'
    }
  )

  return [PSCustomObject]@{
    Content = $rewritten
    AssetCount = $assetCount
    Warnings = $warnings
  }
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

$vaultDir = $null
if ($null -ne $config -and $null -ne $config.vaultDir -and -not [string]::IsNullOrWhiteSpace([string]$config.vaultDir)) {
  $vaultDir = [string]$config.vaultDir
}

if ([string]::IsNullOrWhiteSpace($vaultDir)) {
  $vaultDir = Split-Path -Path $SourceBlogDir -Parent
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
$warningMessages = New-Object System.Collections.Generic.List[string]

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
    $relativeParent = Split-Path -Path $relativePath -Parent
    $sourceParent = if ([string]::IsNullOrWhiteSpace($relativeParent)) { $SourceBlogDir } else { Join-Path $SourceBlogDir $relativeParent }
    $syncedAssets = Sync-MarkdownAssets -Content $raw -CurrentSourceDir $sourceParent -TargetDir $targetDir -SourceBlogDir $SourceBlogDir -VaultDir $vaultDir
    foreach ($warning in $syncedAssets.Warnings) {
      $warningMessages.Add(("{0}: {1}" -f $relativePath, $warning))
    }
    $assetCount += $syncedAssets.AssetCount
    $fixed = Set-FrontMatterDefaults -Content $syncedAssets.Content -FileBaseName ([IO.Path]::GetFileNameWithoutExtension($file.Name)) -DefaultDate $file.LastWriteTime -DefaultDraft $defaultDraft
    Set-Content -Path $targetPath -Value $fixed -Encoding UTF8
    $markdownCount += 1
  } else {
    Copy-Item -Path $file.FullName -Destination $targetPath -Force
    $assetCount += 1
  }
}

Write-Step "Synced $markdownCount markdown files and $assetCount assets"
foreach ($warning in $warningMessages) {
  Write-Warning $warning
}

if ($RunBuild) {
  Write-Step "Running Hugo build"
  Push-Location $SiteRoot
  try {
    hugo --minify
  } finally {
    Pop-Location
  }
}
