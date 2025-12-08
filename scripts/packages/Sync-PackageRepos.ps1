[CmdletBinding()]
param(
  [ValidateSet('ensure','remove','sync-tags')]
  [string]$Action = 'ensure',
  [string[]]$Table,
  [string]$TableJson,
  [string]$MapPath,
  [string]$PackagesDir,
  [string]$GithubOrg = 'blackcatdatabase',
  [ValidateSet('private','public','internal')]
  [string]$GithubVisibility = 'public',
  [switch]$CreateRemote,
  [switch]$DeleteRemote,
  [switch]$Force,
  [switch]$LocalOnly,
  [switch]$DisableLocalFallback,
  [string]$TagName,
  [switch]$PushTags
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptsRoot = Split-Path -Parent $PSScriptRoot
$RepoRoot    = Split-Path -Parent $ScriptsRoot
Set-Location -LiteralPath $RepoRoot

if (-not $MapPath) {
  $MapPath = Join-Path $PSScriptRoot '..\schema\schema-map-postgres.yaml'
}
if (-not $PackagesDir) {
  $PackagesDir = Join-Path $PSScriptRoot '..\..\packages'
}

$script:PackageRepoStandard = @{
  DescriptionTemplate = 'Schema package for table {0} (managed via blackcat-database).'
  HomepageUrl         = 'https://github.com/blackcatacademy/blackcat-database'
  Topics              = @('blackcat-database','schema','table-package','automation')
  RepoSettings        = @{
    HasIssues           = $true
    HasProjects         = $false
    HasWiki             = $false
    AllowMergeCommit    = $false
    AllowSquashMerge    = $true
    AllowRebaseMerge    = $false
    AllowAutoMerge      = $true
    DeleteBranchOnMerge = $true
  }
  Labels = @(
    @{ Name = 'type:bug';          Color = 'd73a4a'; Description = 'Defect or regression affecting this table package.' },
    @{ Name = 'type:enhancement';  Color = 'a2eeef'; Description = 'Feature or improvement request for this table package.' },
    @{ Name = 'type:docs';         Color = '5319e7'; Description = 'Documentation-only updates.' },
    @{ Name = 'status:triage';     Color = 'fbca04'; Description = 'Needs triage or grooming.' },
    @{ Name = 'status:blocked';    Color = 'b60205'; Description = 'Work blocked by dependencies.' }
  )
  BranchProtection = @{
    Branch                       = 'main'
    RequireLinearHistory         = $true
    RequireConversationResolution = $true
    EnforceAdmins                = $true
    AllowForcePushes             = $false
    AllowDeletions               = $false
    RequiredApprovingReviewCount = 1
    DismissStaleReviews          = $true
    RequireCodeOwnerReviews      = $false
    RequiredStatusChecks         = @()
    StatusCheckStrict            = $true
  }
}

function Write-Info([string]$Message) { Write-Host $Message -ForegroundColor Cyan }
function Write-Warn([string]$Message) { Write-Warning $Message }

function Convert-CommandOutputToText {
  param($Output)
  if ($null -eq $Output) { return '' }
  if ($Output -is [System.Array]) {
    $text = ($Output | Out-String).Trim()
    if (-not [string]::IsNullOrWhiteSpace($text)) { return $text }
    return ($Output -join [Environment]::NewLine)
  }
  $asString = [string]$Output
  return $asString.Trim()
}

function Test-TransientRemoteError {
  param([string]$Message)
  if ([string]::IsNullOrWhiteSpace($Message)) { return $false }
  $patterns = @(
    'HTTP\s+5\d\d',
    'The requested URL returned error:\s*5\d\d',
    'Internal Server Error',
    'Service Unavailable',
    'Gateway Timeout',
    'timed out',
    'timeout awaiting response',
    'connection.*reset',
    'fatal:\s+expected flush after ref listing',
    'fatal:\s+unable to access .+ 5\d\d',
    'curl 22'
  )
  foreach ($pattern in $patterns) {
    if ($Message -match $pattern) { return $true }
  }
  return $false
}

function Invoke-CommandWithRetry {
  param(
    [Parameter(Mandatory)][scriptblock]$Command,
    [string]$OperationDescription = 'command',
    [int]$MaxAttempts = 3,
    [int]$InitialDelaySeconds = 2
  )
  $attempt = 0
  $delay = [Math]::Max(1,$InitialDelaySeconds)
  $lastOutput = $null
  $lastExitCode = 0
  while ($attempt -lt $MaxAttempts) {
    $attempt++
    $lastOutput = & $Command
    $lastExitCode = $LASTEXITCODE
    if ($lastExitCode -eq 0) {
      return [pscustomobject]@{
        Success  = $true
        Output   = $lastOutput
        ExitCode = 0
        Message  = ''
      }
    }
    $message = Convert-CommandOutputToText -Output $lastOutput
    if ([string]::IsNullOrWhiteSpace($message)) {
      $message = "Exit code $lastExitCode"
    }
    if ((-not (Test-TransientRemoteError -Message $message)) -or $attempt -ge $MaxAttempts) {
      return [pscustomobject]@{
        Success  = $false
        Output   = $lastOutput
        ExitCode = $lastExitCode
        Message  = $message
      }
    }
    Write-Warn ("Transient failure during {0} (attempt {1}/{2}): {3}. Retrying in {4} seconds..." -f `
      $OperationDescription,$attempt,$MaxAttempts,$message,$delay)
    Start-Sleep -Seconds $delay
    $delay = [Math]::Min($delay * 2, 30)
  }
  return [pscustomobject]@{
    Success  = $false
    Output   = $lastOutput
    ExitCode = $lastExitCode
    Message  = Convert-CommandOutputToText -Output $lastOutput
  }
}

function Get-PackageSlug([string]$TableName) {
  return ($TableName -replace '_','-')
}

function Test-GhCliAvailable {
  if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    throw "GitHub CLI (gh) is required for this operation."
  }
}

function Test-GhRepoExists {
  param([string]$RepoFullName)
  if (-not $script:GhReady) { return $false }
  $endpoint = "repos/{0}" -f $RepoFullName
  try {
    $operation = "gh api $endpoint"
    $result = Invoke-CommandWithRetry -Command { & gh api $endpoint -X GET -H 'Accept: application/vnd.github+json' 1>$null 2>$null } `
      -OperationDescription $operation -MaxAttempts 4 -InitialDelaySeconds 2
    return $result.Success
  } catch {
    return $false
  }
}

function Get-StandardRepoDescription {
  param(
    [Parameter(Mandatory)][string]$Table,
    [Parameter(Mandatory)][string]$Slug
  )
  $template = $script:PackageRepoStandard.DescriptionTemplate
  if ([string]::IsNullOrWhiteSpace($template)) {
    return ("Schema package for table {0}." -f $Table)
  }
  return ($template -f $Table)
}

function Get-StandardRepoSettings {
  param(
    [Parameter(Mandatory)][string]$Table,
    [Parameter(Mandatory)][string]$Slug
  )
  $settings = @{}
  $description = Get-StandardRepoDescription -Table $Table -Slug $Slug
  if ($description) { $settings.description = $description }
  if ($script:PackageRepoStandard.HomepageUrl) {
    $settings.homepage = $script:PackageRepoStandard.HomepageUrl
  }
  $settings.default_branch = 'main'
  switch ($GithubVisibility) {
    'public'   { $settings.private = $false }
    'private'  { $settings.private = $true }
    'internal' { $settings.visibility = 'internal' }
  }
  if ($script:PackageRepoStandard.RepoSettings) {
    $repoSettings = $script:PackageRepoStandard.RepoSettings
    if ($repoSettings.ContainsKey('HasIssues'))           { $settings.has_issues            = [bool]$repoSettings.HasIssues }
    if ($repoSettings.ContainsKey('HasProjects'))         { $settings.has_projects          = [bool]$repoSettings.HasProjects }
    if ($repoSettings.ContainsKey('HasWiki'))             { $settings.has_wiki              = [bool]$repoSettings.HasWiki }
    if ($repoSettings.ContainsKey('AllowMergeCommit'))    { $settings.allow_merge_commit    = [bool]$repoSettings.AllowMergeCommit }
    if ($repoSettings.ContainsKey('AllowSquashMerge'))    { $settings.allow_squash_merge    = [bool]$repoSettings.AllowSquashMerge }
    if ($repoSettings.ContainsKey('AllowRebaseMerge'))    { $settings.allow_rebase_merge    = [bool]$repoSettings.AllowRebaseMerge }
    if ($repoSettings.ContainsKey('AllowAutoMerge'))      { $settings.allow_auto_merge      = [bool]$repoSettings.AllowAutoMerge }
    if ($repoSettings.ContainsKey('DeleteBranchOnMerge')) { $settings.delete_branch_on_merge = [bool]$repoSettings.DeleteBranchOnMerge }
  }
  return $settings
}

function Invoke-GhApiRequest {
  param(
    [Parameter(Mandatory)][string]$Path,
    [ValidateSet('GET','POST','PUT','PATCH','DELETE')]
    [string]$Method = 'GET',
    [hashtable]$Body,
    [string[]]$Headers,
    [switch]$ExpectJson
  )
  Test-GhCliAvailable
  $ghArgs = @('api',$Path,'-X',$Method,'-H','Accept: application/vnd.github+json')
  if ($Headers) {
    foreach ($hdr in $Headers) {
      if (-not [string]::IsNullOrWhiteSpace($hdr)) {
        $ghArgs += @('-H',$hdr)
      }
    }
  }
  $tempFile = $null
  if ($Body) {
    $json = $Body | ConvertTo-Json -Depth 10
    $tempFile = [System.IO.Path]::GetTempFileName()
    Set-Content -LiteralPath $tempFile -Value $json -Encoding UTF8
    $ghArgs += @('--input',$tempFile)
  }
  $operation = "gh api $Path"
  try {
    $result = Invoke-CommandWithRetry -Command { & gh @ghArgs } -OperationDescription $operation -MaxAttempts 4 -InitialDelaySeconds 2
  } finally {
    if ($tempFile -and (Test-Path -LiteralPath $tempFile)) {
      Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
    }
  }
  if (-not $result.Success) {
    $message = if ($result.Message) { $result.Message } else { 'GitHub CLI returned an error.' }
    throw "gh api call failed ($Path): $message"
  }
  $output = $result.Output
  if (-not $ExpectJson) {
    return $output
  }
  if (-not $output) { return $null }
  $raw = if ($output -is [System.Array]) { ($output -join [Environment]::NewLine) } else { [string]$output }
  if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
  return $raw | ConvertFrom-Json -Depth 10
}

function Set-GitHubRepoSettings {
  param(
    [Parameter(Mandatory)][string]$RepoFullName,
    [Parameter(Mandatory)][hashtable]$Settings
  )
  if (-not $Settings.Count) { return }
  Invoke-GhApiRequest -Path ("repos/{0}" -f $RepoFullName) -Method PATCH -Body $Settings | Out-Null
}

function Set-GitHubRepoTopics {
  param(
    [Parameter(Mandatory)][string]$RepoFullName,
    [string[]]$Topics
  )
  if (-not $Topics -or $Topics.Count -eq 0) { return }
  $body = @{ names = $Topics }
  Invoke-GhApiRequest -Path ("repos/{0}/topics" -f $RepoFullName) -Method PUT -Body $body -Headers @('Accept: application/vnd.github.mercy-preview+json') | Out-Null
}

function Set-GitHubRepoLabels {
  param(
    [Parameter(Mandatory)][string]$RepoFullName,
    [object[]]$LabelSpecs
  )
  if (-not $LabelSpecs -or $LabelSpecs.Count -eq 0) { return }
  $existing = Invoke-GhApiRequest -Path ("repos/{0}/labels?per_page=100" -f $RepoFullName) -ExpectJson
  if (-not $existing) { $existing = @() }
  elseif (-not ($existing -is [System.Collections.IEnumerable])) { $existing = @($existing) }
  $lookup = @{}
  foreach ($label in $existing) {
    if ($label.name) {
      $lookup[$label.name.ToLowerInvariant()] = $label
    }
  }
  foreach ($spec in $LabelSpecs) {
    $name = [string]$spec.Name
    if ([string]::IsNullOrWhiteSpace($name)) { continue }
    $color = if ($spec.Color) { ($spec.Color -replace '#','').ToLowerInvariant() } else { 'cccccc' }
    $description = [string]$spec.Description
    $key = $name.ToLowerInvariant()
    if ($lookup.ContainsKey($key)) {
      $current = $lookup[$key]
      $currentColor = [string]$current.color
      $currentDescription = if ($current.description) { [string]$current.description } else { '' }
      if ($currentColor.ToLowerInvariant() -ne $color -or $currentDescription -ne $description) {
        Invoke-GhApiRequest -Path ("repos/{0}/labels/{1}" -f $RepoFullName,[uri]::EscapeDataString($current.name)) -Method PATCH -Body @{
          name        = $name
          color       = $color
          description = $description
        } | Out-Null
        Write-Info "Updated label '$name' for $RepoFullName."
      }
    } else {
      Invoke-GhApiRequest -Path ("repos/{0}/labels" -f $RepoFullName) -Method POST -Body @{
        name        = $name
        color       = $color
        description = $description
      } | Out-Null
      Write-Info "Created label '$name' for $RepoFullName."
    }
  }
}

function Set-GitHubRepoBranchProtection {
  param(
    [Parameter(Mandatory)][string]$RepoFullName,
    [Parameter(Mandatory)][hashtable]$Config
  )
  if (-not $Config) { return }
  $branch = if ($Config.Branch) { $Config.Branch } else { 'main' }
  $statusChecks = $null
  if ($Config.ContainsKey('RequiredStatusChecks') -and $Config.RequiredStatusChecks) {
    $statusChecks = @{
      strict   = [bool]$Config.StatusCheckStrict
      contexts = @($Config.RequiredStatusChecks)
    }
  } elseif ($Config.ContainsKey('RequiredStatusChecks') -and -not $Config.RequiredStatusChecks) {
    $statusChecks = $null
  }
  $reviews = $null
  $needsReviewBlock = (
    ($Config.ContainsKey('RequiredApprovingReviewCount') -and [int]$Config.RequiredApprovingReviewCount -gt 0) -or
    $Config.RequireCodeOwnerReviews -or
    $Config.DismissStaleReviews
  )
  if ($needsReviewBlock) {
    $reviews = @{
      dismiss_stale_reviews          = [bool]$Config.DismissStaleReviews
      require_code_owner_reviews     = [bool]$Config.RequireCodeOwnerReviews
      required_approving_review_count = [int]$Config.RequiredApprovingReviewCount
      bypass_pull_request_allowances = @{
        users = @()
        teams = @()
        apps  = @()
      }
    }
  }
  $body = @{
    required_status_checks        = $statusChecks
    enforce_admins                = [bool]$Config.EnforceAdmins
    required_pull_request_reviews = $reviews
    restrictions                  = $null
    allow_force_pushes            = [bool]$Config.AllowForcePushes
    allow_deletions               = [bool]$Config.AllowDeletions
    required_linear_history       = [bool]$Config.RequireLinearHistory
    required_conversation_resolution = [bool]$Config.RequireConversationResolution
  }
  Invoke-GhApiRequest -Path ("repos/{0}/branches/{1}/protection" -f $RepoFullName,$branch) -Method PUT -Body $body | Out-Null
}

function Set-PackageRepoMetadata {
  param(
    [Parameter(Mandatory)][string]$RepoFullName,
    [Parameter(Mandatory)][string]$Table,
    [Parameter(Mandatory)][string]$Slug
  )
  if ($LocalOnly) { return }
  if (-not $script:GhReady) { return }
  try {
    $settings = Get-StandardRepoSettings -Table $Table -Slug $Slug
    Set-GitHubRepoSettings -RepoFullName $RepoFullName -Settings $settings
  } catch {
    Write-Warn "Failed to apply repository settings for ${RepoFullName}: $($_.Exception.Message)"
  }
  try {
    Set-GitHubRepoTopics -RepoFullName $RepoFullName -Topics $script:PackageRepoStandard.Topics
  } catch {
    Write-Warn "Failed to sync topics for ${RepoFullName}: $($_.Exception.Message)"
  }
  try {
    Set-GitHubRepoLabels -RepoFullName $RepoFullName -LabelSpecs $script:PackageRepoStandard.Labels
  } catch {
    Write-Warn "Failed to sync labels for ${RepoFullName}: $($_.Exception.Message)"
  }
  if ($script:PackageRepoStandard.BranchProtection) {
    try {
      Set-GitHubRepoBranchProtection -RepoFullName $RepoFullName -Config $script:PackageRepoStandard.BranchProtection
    } catch {
      Write-Warn "Failed to apply branch protection for ${RepoFullName}: $($_.Exception.Message)"
    }
  }
}

function New-RemotePackageRepo {
  param(
    [Parameter(Mandatory)][string]$RepoName,
    [Parameter(Mandatory)][string]$Description,
    [Parameter(Mandatory)][string]$Table
  )
  Test-GhCliAvailable
  $temp = Join-Path ([System.IO.Path]::GetTempPath()) ("bc_pkg_" + [System.Guid]::NewGuid().ToString('N'))
  try {
    New-Item -ItemType Directory -Path $temp | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $temp 'schema') | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $temp 'docs') | Out-Null
    Set-Gitattributes -RepoPath $temp
    $readme = @"
# $RepoName

$Description

> Generated automatically from blackcat-database for table `$Table`.

## What's included?
- \`schema/\`: canonical SQL migrations for the table.
- \`docs/\`: README, changelog, and definition exports.

This repository is managed by automation. Please keep changes in sync with the umbrella repo.
"@
    $readme | Set-Content -LiteralPath (Join-Path $temp 'README.md') -Encoding UTF8
    git -C $temp init -b main | Out-Null
    git -C $temp add . | Out-Null
    git -C $temp commit -m "chore: bootstrap $RepoName" | Out-Null
    $visibilitySwitch = "--$GithubVisibility"
    $nameArg = if ($GithubOrg) { "$GithubOrg/$RepoName" } else { $RepoName }
    $operation = "gh repo create $nameArg"
    $ghResult = Invoke-CommandWithRetry -Command { & gh repo create $nameArg $visibilitySwitch --source $temp --remote origin --push --description "$Description" 2>&1 } `
      -OperationDescription $operation -MaxAttempts 4
    if (-not $ghResult.Success) {
      $details = if ($ghResult.Message) { $ghResult.Message } else { "gh repo create returned exit code $($ghResult.ExitCode)" }
      throw "GitHub CLI failed to create repository '$RepoName': $details"
    }
  } finally {
    if (Test-Path -LiteralPath $temp) {
      Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
    }
  }
}

function Add-Submodule {
  param([string]$RepoUrl,[string]$Slug)
  $targetPath = Get-SubmoduleTargetPath -Slug $Slug
  $operation = "git submodule add $Slug"
  $result = Invoke-CommandWithRetry -Command { & git submodule add --depth 1 -b main $RepoUrl $targetPath 2>&1 } `
    -OperationDescription $operation -MaxAttempts 4 -InitialDelaySeconds 2
  if (-not $result.Success) {
    $details = if ($result.Message) { $result.Message } else { "git submodule add returned exit code $($result.ExitCode)" }
    throw ("git submodule add failed for {0}: {1}" -f $Slug,$details)
  }
  $configKey = "submodule.{0}.shallow" -f $targetPath
  & git config -f .gitmodules $configKey true | Out-Null
}

function Remove-Submodule {
  param([string]$Slug,[switch]$Force)
  $path = Get-SubmoduleTargetPath -Slug $Slug
  $localPath = Get-PackageFullPath -Slug $Slug
  if (Test-IsLocalPackageStub -Slug $Slug) {
    Remove-LocalPackageStub -Slug $Slug
    return
  }
  if (-not (Test-Path -LiteralPath $localPath)) {
    Write-Warn "Submodule '$Slug' not found."
    return
  }
  & git submodule deinit -f $path | Out-Null
  & git rm -f $path | Out-Null
  $modulesPath = Join-Path $RepoRoot (".git/modules/$path")
  if (Test-Path $modulesPath) { Remove-Item -LiteralPath $modulesPath -Recurse -Force }
}

function Test-GitPathTracked {
  param([Parameter(Mandatory)][string]$GitRelativePath)
  try {
    $output = & git ls-files --stage -- $GitRelativePath 2>$null
    if ($LASTEXITCODE -ne 0) { return $false }
    $text = if ($output -is [System.Array]) { ($output | Out-String).Trim() } else { [string]$output }
    return -not [string]::IsNullOrWhiteSpace($text)
  } catch {
    return $false
  }
}

function Get-PackageFullPath {
  param([Parameter(Mandatory)][string]$Slug)
  return (Join-Path $script:PackagesDirResolved $Slug)
}

function Get-SubmoduleTargetPath {
  param([Parameter(Mandatory)][string]$Slug)
  $base = if ($script:PackagesRelativePath) { $script:PackagesRelativePath } else { 'packages' }
  $combined = Join-Path $base $Slug
  return ($combined -replace '\\','/')
}

function Test-IsLocalPackageStub {
  param([Parameter(Mandatory)][string]$Slug)
  $marker = Join-Path (Get-PackageFullPath -Slug $Slug) '.bc-local-stub'
  return (Test-Path -LiteralPath $marker)
}

function Remove-LocalPackageStub {
  param([Parameter(Mandatory)][string]$Slug)
  $path = Get-PackageFullPath -Slug $Slug
  if (Test-Path -LiteralPath $path) {
    Write-Info "Removing local stub for '$Slug'."
    Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue
  }
}

function New-DirectoryIfMissing {
  param([Parameter(Mandatory)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
  }
}

function Get-StandardGitattributesContent {
  @(
    '*.php    text eol=lf'
    '*.phpt   text eol=lf'
    '*.md     text eol=lf'
    '*.sql    text eol=lf'
    '*.ps1    text eol=lf'
    '*.psm1   text eol=lf'
    '*.psd1   text eol=lf'
    '*.yml    text eol=lf'
    '*.yaml   text eol=lf'
    '*.json   text eol=lf'
    '*.sh     text eol=lf'
  ) -join "`n"
}

function Set-Gitattributes {
  param([Parameter(Mandatory)][string]$RepoPath)
  $target = Join-Path $RepoPath '.gitattributes'
  $desired = Get-StandardGitattributesContent
  $current = $null
  if (Test-Path -LiteralPath $target) {
    $current = (Get-Content -LiteralPath $target -Raw -ErrorAction SilentlyContinue)
  }
  if ($current -ne $desired) {
    Set-Content -LiteralPath $target -Value $desired -Encoding UTF8
  }
}

function New-LocalPackageStub {
  param([Parameter(Mandatory)][string]$Slug,[Parameter(Mandatory)][string]$Table)
  $path = Get-PackageFullPath -Slug $Slug
  if (-not (Test-Path -LiteralPath $path)) {
    Write-Info "Scaffolding local stub for '$Slug' at $path (no GitHub access)."
    New-Item -ItemType Directory -Path $path -Force | Out-Null
  } else {
    Write-Info "Refreshing local stub for '$Slug'."
  }
  foreach ($folder in @('schema','docs')) {
    New-DirectoryIfMissing -Path (Join-Path $path $folder)
  }
  $readme = @"
# Local package stub: $Slug

This directory was generated locally because the remote submodule for table '$Table'
is not available. Files here are ignored by Git and should not be committed.
When you gain access to the official package repository, rerun Sync-PackageRepos
without local fallback to replace this stub with the real submodule.
"@
  $readme | Set-Content -LiteralPath (Join-Path $path 'README.local.md') -Encoding UTF8
  $ignoreContent = @(
    '# Local stub – ignore everything in this package directory.',
    '*'
  ) -join [Environment]::NewLine
  $ignoreContent | Set-Content -LiteralPath (Join-Path $path '.gitignore') -Encoding UTF8
  $markerPath = Join-Path $path '.bc-local-stub'
  ("stub-created {0:O}" -f (Get-Date)) | Set-Content -LiteralPath $markerPath -Encoding UTF8
  return $path
}

$allowLocalFallback = -not $DisableLocalFallback
if (-not (Test-Path -LiteralPath $PackagesDir)) { throw "Packages directory not found: $PackagesDir" }
$PackagesDirInfo = Resolve-Path -LiteralPath $PackagesDir
$script:PackagesDirResolved = $PackagesDirInfo.ProviderPath
$script:PackagesRelativePath = $null
try {
  $relativeCandidate = Resolve-Path -LiteralPath $PackagesDir -Relative
  if ($relativeCandidate) {
    $script:PackagesRelativePath = $relativeCandidate.TrimStart('.','\\','/')
  }
} catch {
  try {
    $script:PackagesRelativePath = [System.IO.Path]::GetRelativePath($RepoRoot,$script:PackagesDirResolved)
  } catch {
    $script:PackagesRelativePath = $null
  }
}
if (-not $script:PackagesRelativePath -or $script:PackagesRelativePath -eq '.') {
  $script:PackagesRelativePath = 'packages'
}
if ((-not $Table -or $Table.Count -eq 0) -and $TableJson) {
  try {
    if (Get-Command ConvertFrom-Json -ParameterName Depth -ErrorAction SilentlyContinue) {
      $parsedJson = $TableJson | ConvertFrom-Json -Depth 10
    } else {
      $parsedJson = $TableJson | ConvertFrom-Json
    }
  } catch {
    throw "Failed to parse -TableJson: $($_.Exception.Message)"
  }
  if ($null -eq $parsedJson) {
    $Table = @()
  } elseif ($parsedJson -is [System.Collections.IEnumerable]) {
    $Table = @($parsedJson)
  } else {
    $Table = @($parsedJson)
  }
}

if (-not $Table -or $Table.Count -eq 0) {
  if (-not (Test-Path -LiteralPath $MapPath)) { throw "Map file not found: $MapPath" }
  $map = Import-PowerShellDataFile -Path $MapPath
  $Table = @($map.Tables.Keys)
}
if ($Table) {
  $Table = @(
    $Table |
      Where-Object { $_ -and -not [string]::IsNullOrWhiteSpace($_) } |
      ForEach-Object { $_.ToString().Trim() }
  )
}

$stats = [pscustomobject]@{
  RemotesCreated   = 0
  SubmodulesAdded  = 0
  LocalStubs       = 0
  AlreadyPresent   = 0
}

$script:GhReady = $false
$script:GhIdentity = $null
$script:GhStatusMessage = $null
try {
  if (Get-Command gh -ErrorAction SilentlyContinue) {
    $authResult = Invoke-CommandWithRetry -Command { & gh auth status 2>&1 } `
      -OperationDescription 'gh auth status' -MaxAttempts 3 -InitialDelaySeconds 1
    if ($authResult.Success) {
      $script:GhReady = $true
      $joined = Convert-CommandOutputToText -Output $authResult.Output
      if ($joined -match 'Logged in to .* as (\S+)') { $script:GhIdentity = $matches[1] }
    } else {
      $script:GhStatusMessage = if ($authResult.Message) { $authResult.Message } else { 'gh auth status failed.' }
    }
  }
} catch {
  $script:GhStatusMessage = $_.Exception.Message
}

if ($LocalOnly) {
  $allowLocalFallback = $true
} elseif ($script:GhReady) {
  if ($allowLocalFallback) {
    $allowLocalFallback = $false
    if ($script:GhIdentity) {
      Write-Info "GitHub CLI authenticated as $($script:GhIdentity); disabling local stub fallback."
    } else {
      Write-Info "GitHub CLI authenticated; disabling local stub fallback."
    }
  }
} elseif (-not $allowLocalFallback) {
  $msg = if ($script:GhStatusMessage) { $script:GhStatusMessage } else { 'GitHub CLI not logged in. Run `gh auth login`.' }
  throw "Local fallback disabled but GitHub CLI is not ready: $msg"
} else {
  if ($script:GhStatusMessage) {
    Write-Warn "GitHub CLI not ready (using local stubs): $($script:GhStatusMessage)"
  } else {
    Write-Warn 'GitHub CLI not installed or not authenticated; falling back to local stubs.'
  }
}

switch ($Action) {
  'ensure' {
    foreach ($tbl in $Table) {
      $slug = Get-PackageSlug $tbl
      $localPath = Get-PackageFullPath -Slug $slug
      $localExists = Test-Path -LiteralPath $localPath
      $isStub = Test-IsLocalPackageStub -Slug $slug
      $repoName = "table-$slug"
      $repoUrl  = "https://github.com/$GithubOrg/$repoName"
      $repoFullName = "$GithubOrg/$repoName"
      if ($LocalOnly) {
        if ($localExists -and -not $isStub) {
          Write-Info "Package '$slug' already exists (local-only mode)."
          $stats.AlreadyPresent++
        } else {
          New-LocalPackageStub -Slug $slug -Table $tbl | Out-Null
          $stats.LocalStubs++
        }
        continue
      }
      $repoExists = Test-GhRepoExists $repoFullName
      if ($repoExists) {
        $lsDesc = "git ls-remote $repoFullName"
        $remoteCheck = Invoke-CommandWithRetry -Command { & git ls-remote "https://github.com/$repoFullName" 2>&1 } `
          -OperationDescription $lsDesc -MaxAttempts 4 -InitialDelaySeconds 2
        if (-not $remoteCheck.Success) {
          $details = if ($remoteCheck.Message) { $remoteCheck.Message } else { 'git ls-remote returned no output' }
          Write-Warn "Repo '$repoFullName' reported as existing but git ls-remote failed ($details). Will treat as missing."
          $repoExists = $false
        }
      }
      $repoStatus = if ($repoExists) { 'exists' } else { 'missing' }
      Write-Info ("Remote repo check {0}: {1}" -f $repoFullName,$repoStatus)
      if ($CreateRemote -and -not $repoExists) {
        Write-Info "Creating remote repository $repoName via GitHub CLI..."
        try {
          $description = Get-StandardRepoDescription -Table $tbl -Slug $slug
          New-RemotePackageRepo -RepoName $repoName -Description $description -Table $tbl
          Write-Info "Remote $repoName created successfully."
          $stats.RemotesCreated++
          $repoExists = $true
        } catch {
          $errorMessage = $_.Exception.Message
          if ($errorMessage -match 'Name already exists') {
            Write-Warn "Remote repository $repoName already existed (gh create reported 'name already exists'); continuing with existing repo."
            $repoExists = $true
          } else {
            Write-Warn "Failed to create remote repository for $tbl ($slug): $errorMessage"
            if ($allowLocalFallback) {
              New-LocalPackageStub -Slug $slug -Table $tbl | Out-Null
              $stats.LocalStubs++
              continue
            } else {
              throw
            }
          }
        }
      }
      if ($repoExists) {
        Set-PackageRepoMetadata -RepoFullName $repoFullName -Table $tbl -Slug $slug
      }
  if ($localExists -and -not $isStub) {
    Set-Gitattributes -RepoPath $localPath
    Write-Info "Package '$slug' already exists."
    $stats.AlreadyPresent++
    continue
  }
      $targetPath = Get-SubmoduleTargetPath -Slug $slug
      $pathTracked = Test-GitPathTracked -GitRelativePath $targetPath
      if ($pathTracked) {
        if (-not $localExists) {
          Write-Warn "Git already tracks '$targetPath' but it is missing from the working tree. Restore it (e.g. `git checkout -- $targetPath`) or remove it from the index before re-running."
        } else {
          Write-Warn "Git already tracks '$targetPath'; skipping submodule add. Run `git rm -r --cached $targetPath` if you need to replace it with a managed submodule."
        }
        $stats.AlreadyPresent++
        continue
      }
      if ($isStub) {
        Write-Info "Replacing local stub for '$slug' with a real submodule..."
        Remove-LocalPackageStub -Slug $slug
        $localExists = $false
      }
      if (-not $repoExists) {
        if ($allowLocalFallback) {
          Write-Warn "Remote repository $repoFullName unavailable; creating local stub for $slug."
          New-LocalPackageStub -Slug $slug -Table $tbl | Out-Null
          $stats.LocalStubs++
          continue
        } else {
          throw "Remote repository $repoFullName not found and creation was not requested."
        }
      }
      Write-Info "Adding submodule for $tbl ($slug) from $repoUrl..."
      try {
        Add-Submodule -RepoUrl $repoUrl -Slug $slug
        Write-Info "Submodule for $tbl ($slug) added successfully."
        $stats.SubmodulesAdded++
      } catch {
        Write-Warn "Failed to add submodule for $tbl ($slug): $($_.Exception.Message)"
        if ($allowLocalFallback) {
          New-LocalPackageStub -Slug $slug -Table $tbl | Out-Null
          $stats.LocalStubs++
          continue
        }
        throw
      }
    }
    Write-Info ("Ensure Packages summary -> submodules added: {0}; remotes created: {1}; local stubs: {2}; already present: {3}." -f `
      $stats.SubmodulesAdded,$stats.RemotesCreated,$stats.LocalStubs,$stats.AlreadyPresent)
    if ($stats.LocalStubs -gt 0 -and -not $script:GhReady) {
      Write-Warn "Local stub fallback was used because GitHub CLI isn't authenticated."
    }
  }
  'remove' {
    if (-not $Table) { throw "Specify -Table for remove action." }
    foreach ($tbl in $Table) {
      $slug = Get-PackageSlug $tbl
      Write-Info "Removing submodule $slug..."
      Remove-Submodule -Slug $slug -Force:$Force
      if ($DeleteRemote) {
        Test-GhCliAvailable
        Write-Info "Deleting remote repository table-$slug..."
        & gh repo delete "$GithubOrg/table-$slug" --yes | Out-Null
      }
    }
  }
  'sync-tags' {
    if (-not $TagName) { throw "-TagName is required for sync-tags." }
    foreach ($pkg in Get-ChildItem -LiteralPath $PackagesDir -Directory) {
      try {
        & git -C $pkg.FullName tag -f $TagName | Out-Null
        if ($PushTags) {
          & git -C $pkg.FullName push origin $TagName --force | Out-Null
        }
        Write-Info "Updated tag $TagName in $($pkg.Name)."
      } catch {
        Write-Warn "Tag sync failed for $($pkg.Name): $($_.Exception.Message)"
      }
    }
  }
}
