[CmdletBinding()]
param([switch]$BootstrapOnly)

if ($PSVersionTable.PSVersion.Major -lt 7) {
  $link = 'https://aka.ms/powershell'
  $msg = "Dev-Workflow requires PowerShell 7+. Current version: $($PSVersionTable.PSVersion). Install from $link."
  Write-Error $msg
  throw $msg
}

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptsRoot = Split-Path -Parent $PSScriptRoot
$RepoRoot    = Split-Path -Parent $ScriptsRoot
Set-Location -LiteralPath $RepoRoot

if ($BootstrapOnly) {
  Write-Host "Bootstrap check complete. RepoRoot: $RepoRoot"
  return
}

$PackagesDir = Join-Path $RepoRoot 'packages'
$SchemaDir   = Join-Path $ScriptsRoot 'schema'   # input maps/defs
$SchemaOut   = Join-Path $RepoRoot   'schema'   # generated consolidated SQL
$SchemaTools = Join-Path $ScriptsRoot 'schema-tools'
$DocsDir     = Join-Path $ScriptsRoot 'docs'
$QualityDir  = Join-Path $ScriptsRoot 'quality'
$AssetsDir   = Join-Path $ScriptsRoot 'dev/assets'
[System.Management.Automation.Runspaces.Runspace]::DefaultRunspace = $Host.Runspace
$DevLogDir   = Join-Path $RepoRoot 'logs'   # keep logs in repo root for easy access
if (-not (Test-Path -LiteralPath $DevLogDir)) {
  New-Item -ItemType Directory -Path $DevLogDir -Force | Out-Null
}
$script:DocsLogPath = Join-Path $DevLogDir ("docs-menu-{0}.log" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
Set-Content -LiteralPath $script:DocsLogPath -Value ("[{0}] Docs diagnostics log initialized." -f (Get-Date -Format 'u')) -Encoding UTF8
$BackgroundImagePath = Join-Path $AssetsDir 'background-workflow.png'
if (-not (Test-Path -LiteralPath $BackgroundImagePath)) {
  $fallbackBackground = Join-Path $AssetsDir 'workflow-bg.png'
  if (Test-Path -LiteralPath $fallbackBackground) {
    $BackgroundImagePath = $fallbackBackground
  }
}
$script:BackgroundImage = $null

$SettingsDir = Join-Path $AssetsDir 'settings'
if (-not (Test-Path -LiteralPath $SettingsDir)) {
  New-Item -ItemType Directory -Path $SettingsDir -Force | Out-Null
}
$script:GitHubSettingsPath = Join-Path $SettingsDir 'github-commits.json'
$script:GitHubSettings = @{
  UmbrellaTitle = ''
  UmbrellaBody  = ''
  PackagesTitle = ''
  PackagesBody  = ''
}
if (Test-Path -LiteralPath $script:GitHubSettingsPath) {
  try {
    $rawSettings = Get-Content -LiteralPath $script:GitHubSettingsPath -Raw -Encoding UTF8
    if (-not [string]::IsNullOrWhiteSpace($rawSettings)) {
      $loadedSettings = $rawSettings | ConvertFrom-Json -ErrorAction Stop
      foreach ($key in $script:GitHubSettings.Keys) {
        if ($loadedSettings.PSObject.Properties[$key] -and $loadedSettings.$key) {
          $script:GitHubSettings[$key] = [string]$loadedSettings.$key
        }
      }
    }
  } catch {
    # Ignore malformed drafts; they'll be recreated on save.
  }
}
$script:UmbrellaTitleBox = $null
$script:UmbrellaBodyBox = $null
$script:PackagesTitleBox = $null
$script:PackagesBodyBox = $null

$MapPg   = Join-Path $SchemaDir 'schema-map-postgres.yaml'
$DefsPg  = Join-Path $SchemaDir 'schema-defs-postgres.yaml'

$Warnings = New-Object System.Collections.Generic.List[string]
$script:LogBox = $null
$script:PendingLog = New-Object System.Collections.Generic.List[string]
$script:LogEntryCount = 0
$script:LogCountLabel = $null
$script:LogPauseScrolling = $false
$script:LogHighlightAlerts = $true
$script:LayoutDiagnosticsLogged = $false
$script:NewPackagesCreated = $false
$script:ForceLicense = $false

$Theme = [pscustomobject]@{
  FormBack    = [System.Drawing.Color]::FromArgb(8,16,32)
  CardBack    = [System.Drawing.Color]::FromArgb(18,38,66)
  PanelBack   = [System.Drawing.Color]::FromArgb(12,28,50)
  ControlBack = [System.Drawing.Color]::FromArgb(6,18,38)
  Accent      = [System.Drawing.Color]::FromArgb(0,196,255)
  Text        = [System.Drawing.Color]::WhiteSmoke
}

if (-not ('DarkMenuRenderer' -as [type])) {
  $menuRendererCode = @"
using System.Drawing;
using System.Windows.Forms;
public class DarkMenuColorTable : ProfessionalColorTable
{
    public override Color MenuItemSelected => Color.FromArgb(32, 64, 96);
    public override Color MenuItemSelectedGradientBegin => Color.FromArgb(32, 64, 96);
    public override Color MenuItemSelectedGradientEnd => Color.FromArgb(32, 64, 96);
    public override Color MenuItemBorder => Color.FromArgb(0, 196, 255);
    public override Color ToolStripDropDownBackground => Color.FromArgb(12, 16, 28);
    public override Color ImageMarginGradientBegin => Color.FromArgb(12, 16, 28);
    public override Color ImageMarginGradientEnd => Color.FromArgb(12, 16, 28);
    public override Color ImageMarginGradientMiddle => Color.FromArgb(12, 16, 28);
}
public class DarkMenuRenderer : ToolStripProfessionalRenderer
{
    private static readonly Color DefaultBack = Color.FromArgb(10, 14, 25);
    private static readonly Color DropBack = Color.FromArgb(18, 28, 46);
    private static readonly Color ActiveBack = Color.FromArgb(32, 64, 96);
    private static readonly Color ActiveBorder = Color.FromArgb(0, 196, 255);

    public DarkMenuRenderer() : base(new DarkMenuColorTable()) { }

    protected override void OnRenderMenuItemBackground(ToolStripItemRenderEventArgs e)
    {
        Rectangle rect = new Rectangle(Point.Empty, e.Item.Size);
        bool isTopLevel = e.Item.Owner is MenuStrip;
        bool active = e.Item.Selected || (e.Item as ToolStripMenuItem)?.DropDown.Visible == true;
        Color back = active ? ActiveBack : (isTopLevel ? DefaultBack : DropBack);
        using (SolidBrush brush = new SolidBrush(back))
        {
            e.Graphics.FillRectangle(brush, rect);
        }
        if (active)
        {
            using (Pen pen = new Pen(ActiveBorder))
            {
                Rectangle borderRect = new Rectangle(rect.X, rect.Y, rect.Width - 1, rect.Height - 1);
                e.Graphics.DrawRectangle(pen, borderRect);
            }
        }
    }

    protected override void OnRenderItemText(ToolStripItemTextRenderEventArgs e)
    {
        bool active = e.Item.Selected || (e.Item as ToolStripMenuItem)?.DropDown.Visible == true;
        Color textColor = active ? Color.White : Color.WhiteSmoke;
        using (SolidBrush brush = new SolidBrush(textColor))
        {
            StringFormat format = new StringFormat();
            format.Alignment = StringAlignment.Near;
            format.LineAlignment = StringAlignment.Center;
            e.Graphics.DrawString(e.Text, e.TextFont, brush, e.TextRectangle, format);
            format.Dispose();
        }
    }
}
"@
  Add-Type -TypeDefinition $menuRendererCode -ReferencedAssemblies System.Windows.Forms,System.Drawing,System.Drawing.Primitives,System.ComponentModel.Primitives,System.Drawing.Common
}

function Test-ConsoleIntroDisplay {
  if ($env:DEVWORKFLOW_SKIP_INTRO -eq '1') { return $false }
  if (-not $host -or -not $host.UI -or -not $host.UI.RawUI) { return $false }
  $name = if ($host.Name) { $host.Name } else { '' }
  if ($name -notlike '*ConsoleHost*') { return $false }
  try {
    $null = $host.UI.RawUI.CursorPosition
    return $true
  } catch {
    return $false
  }
}

function Show-DynamicEpicCatIntro {
  $durationSeconds = 5
  $fps = 24
  $frameDelay = [math]::Max([math]::Floor(1000 / $fps), 15)
  $baseFrameCount = [math]::Max([int]([math]::Round($durationSeconds * $fps)), 80)
  $lapFrames = [math]::Max([int]([math]::Floor($baseFrameCount * 0.4)), 30)
  $remaining = $baseFrameCount - ($lapFrames * 2)
  if ($remaining -lt 10) { $remaining = 10 }
  $totalFrames = ($lapFrames * 2) + $remaining
  $finalFrames = $remaining

  $frameWidth = 72
  $frameHeight = 0

  $catArt = @(
    ' /\___/\ ',
    '(= ^.^ =)>',
    ' /  w  \   ',
    '/|  |  |\  ',
    '\_/___\_/  ',
    '  "" ""    '
  )
  $mouseArt = @(
    '  __  ',
    ' (o )>',
    ' / /~ '
  )
  $mouseCaughtArt = @(
    '  __  ',
    ' (x_x)',
    ' / /~ '
  )

  $frameHeight = [math]::Max($catArt.Count, $mouseArt.Count + 2)
  $frameHeight = [math]::Max($frameHeight, $mouseCaughtArt.Count + 2)

  $catWidth = (($catArt | ForEach-Object { $_.Length }) | Measure-Object -Maximum).Maximum
  $mouseWidth = (($mouseArt | ForEach-Object { $_.Length }) | Measure-Object -Maximum).Maximum
  $travelWidth = [math]::Max($frameWidth - $catWidth - 4, 20)
  $mouseLeadBase = 12

  $rawUI = $null
  $cursorOrigin = $null
  $canResetCursor = $false
  try {
    if ($host.UI -and $host.UI.RawUI) {
      $rawUI = $host.UI.RawUI
      $cursorOrigin = $rawUI.CursorPosition
      $canResetCursor = $true
    }
  } catch {
    $canResetCursor = $false
  }

  $placeArt = {
    param([object[]]$Canvas,[string[]]$Art,[int]$X,[int]$Y,[int]$Width)
    if (-not $Canvas -or -not $Art) { return }
    for ($row = 0; $row -lt $Art.Count; $row++) {
      $targetRow = $Y + $row
      if ($targetRow -lt 0 -or $targetRow -ge $Canvas.Length) { continue }
      $lineChars = $Canvas[$targetRow]
      if (-not $lineChars) { continue }
      $lineText = $Art[$row]
      for ($col = 0; $col -lt $lineText.Length; $col++) {
        $char = $lineText[$col]
        if ($char -eq ' ') { continue }
        $targetCol = $X + $col
        if ($targetCol -lt 0 -or $targetCol -ge $Width) { continue }
        $lineChars[$targetCol] = $char
      }
      $Canvas[$targetRow] = $lineChars
    }
  }

  for ($frame = 0; $frame -lt $totalFrames; $frame++) {
    $stage = 'Lap'
    $lapIndex = 0
    if ($frame -ge $lapFrames -and $frame -lt ($lapFrames * 2)) {
      $lapIndex = 1
    } elseif ($frame -ge ($lapFrames * 2)) {
      $stage = 'Final'
    }

    $catPos = 0
    $mousePos = 0
    $mouseArtForFrame = $mouseArt
    $caught = $false

    if ($stage -eq 'Lap') {
      $lapStart = $lapIndex * $lapFrames
      $lapProgress = ($frame - $lapStart) / [math]::Max($lapFrames - 1, 1)
      $catPos = [int]([math]::Round($lapProgress * $travelWidth))
      $mouseLead = $mouseLeadBase + ($lapIndex * 4)
      $mousePos = [math]::Min($catPos + $mouseLead, $frameWidth - $mouseWidth - 2)
    } else {
      $finalProgress = ($frame - ($lapFrames * 2)) / [math]::Max($finalFrames - 1, 1)
      $catPos = [int]([math]::Round($finalProgress * $travelWidth))
      $mousePos = [math]::Max($catPos + 4, $frameWidth - $mouseWidth - 3 - [int]([math]::Round($finalProgress * ($travelWidth * 0.8))))
      if ($mousePos -lt 0) { $mousePos = 0 }
      if ($mousePos -gt ($frameWidth - $mouseWidth - 1)) {
        $mousePos = $frameWidth - $mouseWidth - 1
      }
      if ($finalProgress -ge 0.6) {
        $mousePos = [math]::Max($catPos + 2, $mousePos - 1)
      }
      $caught = (($catPos + $catWidth - 2) -ge $mousePos -or $finalProgress -ge 0.9)
      if ($caught) {
        $mouseArtForFrame = $mouseCaughtArt
        $mousePos = [math]::Min($catPos + $catWidth - 6, $frameWidth - $mouseWidth - 1)
      }
    }

    if ($frame -eq 0 -or -not $canResetCursor) {
      Clear-Host
    } else {
      try {
        $rawUI.CursorPosition = New-Object System.Management.Automation.Host.Coordinates 0 $cursorOrigin.Y
      } catch {
        Clear-Host
      }
    }

    $canvas = @()
    for ($row = 0; $row -lt $frameHeight; $row++) {
      $canvas += ,((' ' * $frameWidth).ToCharArray())
    }

    $catTopRow = [math]::Max($frameHeight - $catArt.Count, 0)
    $mouseTopRow = [math]::Min($catTopRow + 2, [math]::Max($frameHeight - $mouseArtForFrame.Count, 0))
    & $placeArt $canvas $catArt $catPos $catTopRow $frameWidth
    & $placeArt $canvas $mouseArtForFrame $mousePos $mouseTopRow $frameWidth

    $canvasStrings = $canvas | ForEach-Object { (-join $_) }

    $lineCount = 0
    $writeLine = {
      param([string]$Text,[string]$Color = 'Gray',[ref]$Counter)
      $Counter.Value++
      $content = if ($null -eq $Text) { '' } else { $Text }
      if ($content.Length -gt $frameWidth) {
        $content = $content.Substring(0, $frameWidth)
      } elseif ($content.Length -lt $frameWidth) {
        $content = $content.PadRight($frameWidth)
      }
      Write-Host $content -ForegroundColor $Color
    }

    foreach ($rowText in $canvasStrings) {
      & $writeLine $rowText 'Gray' ([ref]$lineCount)
    }

    while ($lineCount -lt $frameHeight) {
      & $writeLine '' 'Gray' ([ref]$lineCount)
    }

    Start-Sleep -Milliseconds $frameDelay
  }
}


if (Test-ConsoleIntroDisplay) {
  Show-DynamicEpicCatIntro
  Write-Host "01001101 01100101 01101111 01110111" -ForegroundColor Cyan
  Write-Host "[INFO] Cat initialized successfully" -ForegroundColor Green
  Write-Host "[DEBUG] Nap sequence started" -ForegroundColor DarkCyan
  Write-Host "[ERROR] Human interrupted nap" -ForegroundColor Red
  Start-Sleep -Milliseconds 400
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing; Add-Type -AssemblyName System.Drawing.Common
if (Test-Path -LiteralPath $BackgroundImagePath) {
  try {
    $script:BackgroundImage = [System.Drawing.Image]::FromFile($BackgroundImagePath)
  } catch {
    $script:BackgroundImage = $null
  }
}

function Set-CardTheme {
  param([System.Windows.Forms.Control]$Control)
  if (-not $Control) { return }
  $Control.BackColor = $Theme.CardBack
  $Control.ForeColor = $Theme.Text
}

function Set-TextBoxStyle {
  param([System.Windows.Forms.TextBoxBase]$TextBox)
  if (-not $TextBox) { return }
  $TextBox.BackColor = $Theme.ControlBack
  $TextBox.ForeColor = $Theme.Text
  $TextBox.BorderStyle = 'FixedSingle'
}

function Invoke-UiThread {
  param(
    [Parameter(Mandatory)][scriptblock]$Action,
    [object[]]$Arguments = @()
  )
  if ($form -and -not $form.IsDisposed) {
    $form.BeginInvoke($Action, $Arguments) | Out-Null
  } else {
    & $Action @Arguments
  }
}

function Set-ButtonVisualState {
  param([System.Windows.Forms.Button]$Button)
  if (-not $Button) { return }
  $applyTag = $null
  $applyStyle = $false
  if ($Button.Tag -is [psobject] -and $Button.Tag.Style -eq 'applyRecommendationButton') {
    $applyStyle = $true
    $applyTag = $Button.Tag
  }
  if ($Button.Enabled) {
    $Button.BackColor = $Theme.CardBack
    $Button.ForeColor = $Theme.Text
    $Button.FlatAppearance.BorderColor = $Theme.Accent
    $Button.Cursor = [System.Windows.Forms.Cursors]::Hand
    if ($applyStyle -and $applyTag -and $Button.Text -ne $applyTag.Label) {
      $Button.Text = $applyTag.Label
    }
  } else {
    $Button.BackColor = [System.Drawing.Color]::FromArgb(60,$Theme.CardBack.R,$Theme.CardBack.G,$Theme.CardBack.B)
    if ($applyStyle) {
      $Button.BackColor = [System.Drawing.Color]::FromArgb(40,$Theme.CardBack.R + [math]::Min(15,255-$Theme.CardBack.R),$Theme.CardBack.G + [math]::Min(15,255-$Theme.CardBack.G),$Theme.CardBack.B + [math]::Min(15,255-$Theme.CardBack.B))
      $Button.ForeColor = [System.Drawing.Color]::FromArgb(160,$Theme.Text.R,$Theme.Text.G,$Theme.Text.B)
      if ($Button.Text -ne ' ') { $Button.Text = ' ' }
    } else {
      $Button.ForeColor = [System.Drawing.Color]::FromArgb(130,$Theme.Text.R,$Theme.Text.G,$Theme.Text.B)
    }
    if ($applyStyle) {
      $Button.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(40,$Theme.CardBack.R,$Theme.CardBack.G,$Theme.CardBack.B)
    } else {
      $Button.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(90,$Theme.Accent.R,$Theme.Accent.G,$Theme.Accent.B)
    }
    $Button.Cursor = [System.Windows.Forms.Cursors]::Default
  }
}

function Set-ButtonStyle {
  param([System.Windows.Forms.Button]$Button)
  if (-not $Button) { return }
  $Button.FlatStyle = 'Flat'
  $Button.FlatAppearance.BorderSize = 1
  $Button.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(80,$Theme.Accent.R,$Theme.Accent.G,$Theme.Accent.B)
  $Button.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(110,$Theme.Accent.R,$Theme.Accent.G,$Theme.Accent.B)
  $Button.UseVisualStyleBackColor = $false
  Set-ButtonVisualState -Button $Button
  $updateState = ({ param($control,$evtArgs) Set-ButtonVisualState -Button $control }).GetNewClosure()
  $Button.Add_EnabledChanged($updateState)
}

function Set-LeftCardDock {
  param([System.Windows.Forms.GroupBox]$GroupBox)
  if (-not $GroupBox) { return }
  $GroupBox.Dock = 'Top'
  $GroupBox.AutoSize = $true
  $GroupBox.AutoSizeMode = 'GrowAndShrink'
  $GroupBox.Margin = New-Object System.Windows.Forms.Padding 5
  $GroupBox.MaximumSize = New-Object System.Drawing.Size(360,0)
  $GroupBox.MinimumSize = New-Object System.Drawing.Size(360,0)
  $GroupBox.Width = 360
}

function New-DocMenuItem {
  param([string]$Text,[string]$Path)
  $item = New-Object System.Windows.Forms.ToolStripMenuItem($Text)
  $item.Tag = $Path
  $item.Add_Click({
    param($evtSender,$evtArgs)
    $target = $evtSender.Tag
    if ($target -and (Test-Path -LiteralPath $target)) {
      Start-Process $target
    }
  })
  return $item
}

function Format-DocTitle {
  param([string]$FileName)
  if ([string]::IsNullOrWhiteSpace($FileName)) { return 'Document' }
  $lower = $FileName.ToLowerInvariant()
  switch ($lower) {
    'readme.md'        { return 'Overview' }
    'changelog.md'     { return 'Changelog' }
    'change-log.md'    { return 'Changelog' }
    'legal.md'         { return 'Legal' }
    'notice.md'        { return 'Notice' }
    'security.md'      { return 'Security Policy' }
    'support.md'       { return 'Support' }
    'code_of_conduct.md' { return 'Code of Conduct' }
    'contributing.md'  { return 'Contributing' }
    'scripts-guide.md' { return 'Scripts Guide' }
    'definition.md'    { return 'Definition' }
    'usage.md'         { return 'Usage' }
    default {
      $base = [System.IO.Path]::GetFileNameWithoutExtension($FileName)
      $friendly = ($base -replace '[_\-]+',' ') -replace '\s+',' '
      $friendly = $friendly.Trim()
      if (-not $friendly) { $friendly = $FileName }
      $textInfo = [System.Globalization.CultureInfo]::InvariantCulture.TextInfo
      return $textInfo.ToTitleCase($friendly.ToLowerInvariant())
    }
  }
}

function Format-SlugName {
  param([string]$Slug)
  if ([string]::IsNullOrWhiteSpace($Slug)) { return 'Unknown' }
  $friendly = ($Slug -replace '[_\-]+',' ') -replace '\s+',' '
  $friendly = $friendly.Trim()
  $textInfo = [System.Globalization.CultureInfo]::InvariantCulture.TextInfo
  return $textInfo.ToTitleCase($friendly.ToLowerInvariant())
}

function Format-DocDisplay {
  param(
    [string]$Display,
    [string]$FullPath,
    [string]$BaseRoot = $RepoRoot
  )
  if ([string]::IsNullOrWhiteSpace($Display) -or [string]::IsNullOrWhiteSpace($FullPath) -or [string]::IsNullOrWhiteSpace($BaseRoot)) {
    return $Display
  }
  try {
    $relative = [System.IO.Path]::GetRelativePath($BaseRoot,$FullPath)
  } catch {
    return $Display
  }
  if ([string]::IsNullOrWhiteSpace($relative)) { return $Display }
  $dir = [System.IO.Path]::GetDirectoryName($relative)
  if ([string]::IsNullOrWhiteSpace($dir) -or $dir -eq '.' ) { return $Display }
  $segments = $dir -split '[/\\]+'
  $friendlyParts = @()
  foreach ($segment in $segments) {
    if ([string]::IsNullOrWhiteSpace($segment)) { continue }
    $friendlyParts += (Format-SlugName $segment)
  }
  if ($friendlyParts.Count -eq 0) { return $Display }
  return ("{0} * {1}" -f ($friendlyParts -join ' / '), $Display)
}

function Add-DocRecord {
  param(
    [System.Collections.IList]$List,
    [string]$Display,
    [string]$Path,
    [int]$Priority = 50,
    [string]$BaseRoot = $RepoRoot
  )
  if ($null -eq $List -or [string]::IsNullOrWhiteSpace($Path)) { return }
  foreach ($existing in $List) {
    if ($existing.Path -and $existing.Path.Equals($Path, [System.StringComparison]::OrdinalIgnoreCase)) {
      return
    }
  }
  $finalDisplay = Format-DocDisplay -Display $Display -FullPath $Path -BaseRoot $BaseRoot
  $List.Add([pscustomobject]@{
    Display  = $finalDisplay
    Path     = $Path
    Priority = $Priority
  }) | Out-Null
}

function Write-DocsLog {
  param([string]$Message)
  if (-not $script:DocsLogPath) { return }
  $line = "[{0}] {1}" -f (Get-Date -Format 'u'), $Message
  try {
    Add-Content -LiteralPath $script:DocsLogPath -Value $line -Encoding UTF8
  } catch {
    # swallow logging issues
  }
}

function Add-DocListToMenu {
  param(
    [System.Windows.Forms.ToolStripMenuItem]$Menu,
    [System.Collections.IEnumerable]$Items
  )
  if (-not $Menu -or -not $Items) { return }
  $sorted = $Items | Sort-Object Priority,Display
  foreach ($entry in $sorted) {
    $menuItem = New-DocMenuItem -Text $entry.Display -Path $entry.Path
    $Menu.DropDownItems.Add($menuItem) | Out-Null
  }
}

function Get-MarkdownFiles {
  param(
    [Parameter(Mandatory)][string]$Path,
    [switch]$Recurse
  )
  if (-not (Test-Path -LiteralPath $Path)) {
    Write-DocsLog ("Path missing for markdown scan: {0}" -f $Path)
    return @()
  }
  $gciParams = @{
    LiteralPath = $Path
    Filter      = '*.md'
    File        = $true
    ErrorAction = 'Stop'
  }
  if ($Recurse) { $gciParams.Recurse = $true }
  try {
    $files = @(Get-ChildItem @gciParams)
  } catch {
    Add-Warning("Docs scan failed under '$Path': $($_.Exception.Message)")
    Write-DocsLog ("EnumerateFiles failed under {0}: {1}" -f $Path,$_.Exception.Message)
    return @()
  }
  Write-DocsLog ("Found {0} markdown files under {1} (Recurse={2})." -f $files.Count,$Path,$Recurse.IsPresent)
  return @($files)
}

function Get-GuideCategoryName {
  param([string]$Segment)
  if ([string]::IsNullOrWhiteSpace($Segment)) { return 'General' }
  switch ($Segment.ToLowerInvariant()) {
    {$_ -in @('howto','how-to')} { return 'How-to Guides' }
    'bench'         { return 'Benchmarks' }
    'benchmarks'    { return 'Benchmarks' }
    'howto-old'     { return 'Legacy Guides' }
    'usage'         { return 'Usage' }
    'overview'      { return 'Overview' }
    'scripts'       { return 'Scripts' }
    'security'      { return 'Security Notes' }
    'admin'         { return 'Admin' }
    default         { return (Format-SlugName $Segment) }
  }
}

function Add-DocsFlatSection {
  param(
    [System.Windows.Forms.ToolStripMenuItem]$RootMenu,
    [string]$Title,
    [System.Collections.IList]$Items
  )
  if (-not $RootMenu -or -not $Items -or $Items.Count -eq 0) { return $false }
  $sectionMenu = New-Object System.Windows.Forms.ToolStripMenuItem($Title)
  Add-DocListToMenu -Menu $sectionMenu -Items $Items
  if ($sectionMenu.DropDownItems.Count -eq 0) { return $false }
  $RootMenu.DropDownItems.Add($sectionMenu) | Out-Null
  return $true
}

function Add-DocsGroupedSection {
  param(
    [System.Windows.Forms.ToolStripMenuItem]$RootMenu,
    [string]$Title,
    [hashtable]$Groups
  )
  if (-not $RootMenu -or -not $Groups -or $Groups.Count -eq 0) { return $false }
  $sectionMenu = New-Object System.Windows.Forms.ToolStripMenuItem($Title)
  $groupKeys = $Groups.Keys | Sort-Object
  foreach ($groupKey in $groupKeys) {
    $items = $Groups[$groupKey]
    if (-not $items -or $items.Count -eq 0) { continue }
    $subMenu = New-Object System.Windows.Forms.ToolStripMenuItem($groupKey)
    Add-DocListToMenu -Menu $subMenu -Items $items
    if ($subMenu.DropDownItems.Count -gt 0) {
      $sectionMenu.DropDownItems.Add($subMenu) | Out-Null
    }
  }
  if ($sectionMenu.DropDownItems.Count -eq 0) { return $false }
  $RootMenu.DropDownItems.Add($sectionMenu) | Out-Null
  return $true
}

function Add-DocRecordIfExists {
  param(
    [System.Collections.IList]$List,
    [string]$Title,
    [string]$Path,
    [int]$Priority = 50,
    [string]$BaseRoot = $RepoRoot
  )
  if (-not $List -or [string]::IsNullOrWhiteSpace($Title) -or [string]::IsNullOrWhiteSpace($Path)) { return }
  if (Test-Path -LiteralPath $Path) {
    Add-DocRecord -List $List -Display $Title -Path $Path -Priority $Priority -BaseRoot $BaseRoot
    Write-DocsLog ("Added doc entry '{0}' from {1}" -f $Title,$Path)
  } else {
    Write-DocsLog ("Doc entry missing '{0}' at {1}" -f $Title,$Path)
  }
}

function Update-LogCountLabel {
  if ($script:LogCountLabel -and -not $script:LogCountLabel.IsDisposed) {
    $script:LogCountLabel.Text = "Entries: $($script:LogEntryCount)"
  }
}


function Clear-LogOutput {
  if ($script:LogBox -and -not $script:LogBox.IsDisposed) {
    $script:LogBox.Clear()
  }
  $script:LogEntryCount = 0
  Update-LogCountLabel
}

function Copy-LogOutput {
  if ($script:LogBox -and -not $script:LogBox.IsDisposed -and $script:LogBox.TextLength -gt 0) {
    [System.Windows.Forms.Clipboard]::SetText($script:LogBox.Text)
  }
}

function Save-LogOutput {
  if (-not ($script:LogBox -and -not $script:LogBox.IsDisposed)) { return }
  $dialog = New-Object System.Windows.Forms.SaveFileDialog
  $dialog.Filter = 'Text Files (*.txt)|*.txt|All Files (*.*)|*.*'
  $dialog.FileName = 'dev-workflow-log.txt'
  if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
    try {
      [System.IO.File]::WriteAllText($dialog.FileName,$script:LogBox.Text)
    } catch {
      Add-Warning("Failed to save log: $($_.Exception.Message)")
    }
  }
  $dialog.Dispose()
}

function New-LogToolbarButton {
  param(
    [string]$Text,
    [scriptblock]$OnClick
  )
  $btn = New-Object System.Windows.Forms.Button
  $btn.Text = $Text
  $btn.AutoSize = $false
  $btn.Height = 22
  $btn.FlatStyle = 'Flat'
  $btn.FlatAppearance.BorderSize = 0
  $btn.BackColor = [System.Drawing.Color]::FromArgb(28,46,72)
  $btn.ForeColor = [System.Drawing.Color]::Gainsboro
  $btn.Margin = New-Object System.Windows.Forms.Padding(4,0,0,1)
  $btn.Padding = New-Object System.Windows.Forms.Padding(6,0,6,0)
  $btn.MinimumSize = New-Object System.Drawing.Size(64,0)
  $btn.Width = [System.Math]::Max($btn.MinimumSize.Width,[System.Windows.Forms.TextRenderer]::MeasureText($Text,$btn.Font).Width + 20)
  $btn.TextAlign = 'MiddleCenter'
  if ($OnClick) { $btn.Add_Click($OnClick) }
  return $btn
}

function New-LogToggleButton {
  param(
    [string]$Text,
    [bool]$InitialValue,
    [scriptblock]$OnToggle
  )
  $toggle = New-Object System.Windows.Forms.CheckBox
  $toggle.Text = $Text
  $toggle.Appearance = 'Button'
  $toggle.AutoSize = $false
  $toggle.Height = 22
  $toggle.Checked = $InitialValue
  $toggle.FlatStyle = 'Flat'
  $toggle.FlatAppearance.BorderSize = 0
  $toggle.BackColor = [System.Drawing.Color]::FromArgb(34,52,80)
  $toggle.ForeColor = [System.Drawing.Color]::Gainsboro
  $toggle.Margin = New-Object System.Windows.Forms.Padding(4,0,0,1)
  $toggle.Padding = New-Object System.Windows.Forms.Padding(6,0,6,0)
  $toggle.MinimumSize = New-Object System.Drawing.Size(60,0)
  $toggle.Width = [System.Math]::Max($toggle.MinimumSize.Width,[System.Windows.Forms.TextRenderer]::MeasureText($Text,$toggle.Font).Width + 20)
  $toggle.TextAlign = 'MiddleCenter'
  $toggle.UseVisualStyleBackColor = $false
  if ($OnToggle) {
    $toggle.Tag = $OnToggle.GetNewClosure()
  } else {
    $toggle.Tag = $null
  }
  $toggle.Add_CheckedChanged({
    param($evtSender,$evtArgs)
    $callback = $evtSender.Tag
    if ($callback) {
      & $callback $evtSender.Checked
    }
  })
  return $toggle
}

function Set-CornerMarkerPosition {
  param([System.Windows.Forms.Control]$HostControl)
  if (-not $HostControl) { return }
  $markers = @()
  foreach ($child in @($HostControl.Controls)) {
    if ($child.Tag -and $child.Tag -is [System.Collections.IDictionary]) {
      if ($child.Tag.Contains('Type') -and $child.Tag.Type -eq 'CornerMarker') {
        $markers += $child
      }
    }
  }
  if ($markers.Count -eq 0) { return }
  foreach ($marker in $markers) {
    $meta = $marker.Tag
    $target = if ($meta.Contains('Target') -and $meta.Target) { $meta.Target } else { $HostControl }
    if (-not $target -or $target.IsDisposed) { continue }
    $rectOnScreen = $target.RectangleToScreen($target.ClientRectangle)
    $relativeRect = $HostControl.RectangleToClient($rectOnScreen)
    $corner = $meta.Corner
    $inset = if ($meta.Contains('Inset')) { [int]$meta.Inset } else { 0 }
    $width = $marker.Width
    $height = $marker.Height
    $x = 0
    $y = 0
    switch ($corner) {
      'TopLeft' {
        $x = $relativeRect.Left + $inset
        $y = $relativeRect.Top + $inset
      }
      'TopRight' {
        $x = $relativeRect.Right - $width - $inset
        $y = $relativeRect.Top + $inset
      }
      'BottomLeft' {
        $x = $relativeRect.Left + $inset
        $y = $relativeRect.Bottom - $height - $inset
      }
      'BottomRight' {
        $x = $relativeRect.Right - $width - $inset
        $y = $relativeRect.Bottom - $height - $inset
      }
    }
    $marker.Location = New-Object System.Drawing.Point(
      [System.Math]::Max(0,$x),
      [System.Math]::Max(0,$y)
    )
    $marker.BringToFront()
  }
}

function Add-CornerMarkers {
  param(
    [Parameter(Mandatory)][System.Windows.Forms.Control]$TargetControl,
    [string]$MarkerPrefix = 'Region',
    [System.Windows.Forms.Control]$HostControl,
    [hashtable]$CornerColors,
    [hashtable]$CornerLabels,
    [int]$Inset = 0,
    [int]$Size = 12
  )
  if (-not $TargetControl) { return }
  if (-not $HostControl) { $HostControl = $TargetControl }
  $existing = @(
    $HostControl.Controls |
      Where-Object {
        $_.Tag -and $_.Tag -is [System.Collections.IDictionary] -and
        $_.Tag.Contains('Type') -and $_.Tag.Type -eq 'CornerMarker' -and
        $_.Tag.Contains('Prefix') -and $_.Tag.Prefix -eq $MarkerPrefix
      }
  )
  if ($existing.Count -gt 0) { return }
  $defaultColors = @{
    TopLeft     = [System.Drawing.Color]::Tomato
    TopRight    = [System.Drawing.Color]::LimeGreen
    BottomLeft  = [System.Drawing.Color]::DodgerBlue
    BottomRight = [System.Drawing.Color]::Gold
  }
  $defaultLabels = @{
    TopLeft     = '1'
    TopRight    = '2'
    BottomLeft  = '3'
    BottomRight = '4'
  }
  $corners = 'TopLeft','TopRight','BottomLeft','BottomRight'
  foreach ($corner in $corners) {
    $color = if ($CornerColors -and $CornerColors.ContainsKey($corner)) {
      $CornerColors[$corner]
    } else {
      $defaultColors[$corner]
    }
    $labelText = if ($CornerLabels -and $CornerLabels.ContainsKey($corner)) {
      $CornerLabels[$corner]
    } else {
      $defaultLabels[$corner]
    }
    $foreColor = if ($color.GetBrightness() -lt 0.5) {
      [System.Drawing.Color]::White
    } else {
      [System.Drawing.Color]::Black
    }
    $marker = New-Object System.Windows.Forms.Label
    $marker.Size = New-Object System.Drawing.Size($Size,$Size)
    $marker.AutoSize = $false
    $marker.Text = $labelText
    $marker.TextAlign = 'MiddleCenter'
    $marker.BackColor = $color
    $marker.ForeColor = $foreColor
    $marker.Font = New-Object System.Drawing.Font('Segoe UI',6,[System.Drawing.FontStyle]::Bold)
    $marker.BorderStyle = 'FixedSingle'
    $marker.Margin = New-Object System.Windows.Forms.Padding(0)
    $marker.Tag = @{
      Type   = 'CornerMarker'
      Prefix = $MarkerPrefix
      Corner = $corner
      Inset  = $Inset
      Target = $TargetControl
    }
    $HostControl.Controls.Add($marker)
    $marker.BringToFront()
  }
  $hostRef = $HostControl
  $updateBlock = ({ param($evtSender,$evtArgs) Set-CornerMarkerPosition -HostControl $hostRef }).GetNewClosure()
  $HostControl.Add_SizeChanged($updateBlock)
  $HostControl.Add_Layout($updateBlock)
  if ($TargetControl -ne $HostControl) {
    $TargetControl.Add_SizeChanged($updateBlock)
    $TargetControl.Add_LocationChanged($updateBlock)
    $TargetControl.Add_Layout($updateBlock)
  }
  Set-CornerMarkerPosition -HostControl $HostControl
}

function Get-CornerMarkerControls {
  param([System.Windows.Forms.Control]$Control)
  if (-not $Control) { return @() }
  $markers = @()
  foreach ($child in $Control.Controls) {
    if ($child.Tag -and $child.Tag -is [System.Collections.IDictionary] -and $child.Tag.Contains('Type') -and $child.Tag.Type -eq 'CornerMarker') {
      $markers += $child
    }
    if ($child.HasChildren) {
      $markers += Get-CornerMarkerControls -Control $child
    }
  }
  return $markers
}

function Write-LayoutDiagnostics {
  param(
    [string]$Name,
    [System.Windows.Forms.Control]$Header,
    [System.Windows.Forms.Control]$Subtitle,
    [System.Windows.Forms.Control]$Toolbar,
    [System.Windows.Forms.Control]$MarkerRoot
  )
  if (-not $Header) { return }
  $headerSize = "{0}x{1}" -f $Header.Width,$Header.Height
  $subtitleInfo = if ($Subtitle) {
    "{0} ({1}x{2})" -f ($(if ($Subtitle.Visible) { 'visible' } else { 'hidden' }), $Subtitle.Width, $Subtitle.Height)
  } else {
    'n/a'
  }
  $toolbarInfo = if ($Toolbar) {
    "{0} controls, {1}x{2}" -f $Toolbar.Controls.Count,$Toolbar.Width,$Toolbar.Height
  } else {
    'n/a'
  }
  Write-UiLog("Catwatch: {0} whiskers aligned (header {1}, subtitle {2}, toolbar {3})." -f $Name,$headerSize,$subtitleInfo,$toolbarInfo)
  Write-UiLog("Cat status {0}: I'm ready to misbehave if anything squeaks." -f $Name)
  if ($MarkerRoot) {
    foreach ($marker in Get-CornerMarkerControls -Control $MarkerRoot) {
      $meta = $marker.Tag
      $prefix = if ($meta.Contains('Prefix')) { $meta.Prefix } else { '?' }
      $corner = if ($meta.Contains('Corner')) { $meta.Corner } else { '?' }
      Write-UiLog("Catwatch marker {0}-{1}: paws at ({2},{3}) size {4}x{5} - I'm ready to misbehave." -f $prefix,$corner,$marker.Left,$marker.Top,$marker.Width,$marker.Height)
    }
  }
}

$script:IsWindowsHost = $false
try {
  $script:IsWindowsHost = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Windows)
} catch {
  if ($env:OS -eq 'Windows_NT') { $script:IsWindowsHost = $true }
}
$script:PwshExecutablePath = $null
$script:ToolPathsInitialized = $false
$script:EnvironmentStatusLogged = $false
$script:EnvironmentChecked = $false
function Add-PathEntryIfNeeded {
  param([string]$PathEntry)
  if ([string]::IsNullOrWhiteSpace($PathEntry)) { return }
  $normalized = $PathEntry.Trim()
  $tryPaths = @($normalized)
  if ($normalized -notmatch '^[A-Za-z]:\\') {
    try {
      $resolved = Resolve-Path -LiteralPath $normalized -ErrorAction Stop
      if ($resolved) {
        $tryPaths = @($resolved.ProviderPath)
      }
    } catch {
      return
    }
  } elseif (-not (Test-Path -LiteralPath $normalized)) {
    return
  }
  $separator = [System.IO.Path]::PathSeparator
  $current = $env:PATH
  if (-not $current) {
    $env:PATH = $tryPaths[0]
    return
  }
  $existing = ($current -split [System.IO.Path]::PathSeparator) | Where-Object { $_ }
  foreach ($entry in $existing) {
    foreach ($candidate in $tryPaths) {
      if ($entry.Trim().Equals($candidate.Trim(),[System.StringComparison]::OrdinalIgnoreCase)) { return }
    }
  }
  $newPath = "$($tryPaths[0])$separator$current"
  $env:PATH = $newPath
  try {
    [System.Environment]::SetEnvironmentVariable('PATH',$newPath,[System.EnvironmentVariableTarget]::Process)
  } catch {
    # ignore failures; best effort
  }
  $script:ToolPathsInitialized = $false
}
function Initialize-ExternalToolsOnPath {
  if ($script:ToolPathsInitialized -or -not $script:IsWindowsHost) { return }
  $absoluteCandidates = @(
    'C:\Program Files\Git\cmd',
    'C:\Program Files\Git\bin',
    'C:\Program Files\GitHub CLI'
  )
  if ($env:LOCALAPPDATA) {
    $absoluteCandidates += (Join-Path $env:LOCALAPPDATA 'Programs\GitHub CLI')
  }
  foreach ($candidate in $absoluteCandidates) {
    Add-PathEntryIfNeeded $candidate
  }
  $script:ToolPathsInitialized = $true
}
function Resolve-PwshExecutablePath {
  if ($script:PwshExecutablePath) { return $script:PwshExecutablePath }
  try {
    $currentPath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    if ($currentPath -and (Test-Path -LiteralPath $currentPath)) {
      $script:PwshExecutablePath = $currentPath
      return $script:PwshExecutablePath
    }
  } catch {
    # ignore lookup failure
  }
  try {
    $pwshCmd = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($pwshCmd -and $pwshCmd.Source) {
      $script:PwshExecutablePath = $pwshCmd.Source
      return $script:PwshExecutablePath
    }
  } catch {
    # ignore lookup failure
  }
  if ($script:IsWindowsHost) {
    $candidateRoots = @(
      $env:ProgramFiles,
      $env:ProgramW6432,
      ${env:ProgramFiles(x86)}
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique
    $relativePaths = @(
      'PowerShell\7\pwsh.exe',
      'PowerShell\7-preview\pwsh.exe',
      'PowerShell\6\pwsh.exe'
    )
    foreach ($root in $candidateRoots) {
      foreach ($rel in $relativePaths) {
        try {
          $candidate = Join-Path $root $rel
          if (Test-Path -LiteralPath $candidate) {
            $script:PwshExecutablePath = $candidate
            return $script:PwshExecutablePath
          }
        } catch {
          # ignore invalid path
        }
      }
    }
    foreach ($fallback in @('C:\Program Files\PowerShell\7\pwsh.exe','C:\Program Files\PowerShell\7-preview\pwsh.exe','C:\Program Files\PowerShell\6\pwsh.exe', (Join-Path $PSHOME 'pwsh.exe'))) {
      if (Test-Path -LiteralPath $fallback) {
        $script:PwshExecutablePath = $fallback
        return $script:PwshExecutablePath
      }
    }
  }
  return $null
}
$script:EnvironmentMetadata = @{
  HostType = if ($script:IsWindowsHost) { 'Windows' } else { 'Unix' }
  PwshPath = ''
}
function Update-EnvironmentMetadata {
  $script:EnvironmentMetadata.PwshPath = if ($script:PwshExecutablePath) { $script:PwshExecutablePath } else { 'unresolved' }
}

function Invoke-PwshScript {
  param(
    [Parameter(Mandatory)][string]$ScriptPath,
    [string[]]$ScriptArguments = @(),
    [string]$DisplayName
  )
  if (-not (Test-Path -LiteralPath $ScriptPath)) {
    Add-Warning("Script not found: $ScriptPath")
    return
  }
  $pwshPath = Resolve-PwshExecutablePath
  if (-not $pwshPath) {
    Add-Warning("PowerShell 7 (pwsh) could not be located; install from https://aka.ms/powershell7 or ensure it is on PATH. Skipping $ScriptPath.")
    return
  }
  $name = if ($DisplayName) { $DisplayName } else { "pwsh $([System.IO.Path]::GetFileName($ScriptPath))" }
  $logPath = Join-Path $DevLogDir ("pwsh-{0}.log" -f (Get-Date -Format 'yyyyMMdd_HHmmssfff'))
  $pwshArgs = @('-NoLogo','-NoProfile')
  if ($script:IsWindowsHost) {
    $pwshArgs += @('-ExecutionPolicy','Bypass')
  }
  $pwshArgs += @('-File',$ScriptPath)
  if ($ScriptArguments -and $ScriptArguments.Count -gt 0) {
    $pwshArgs += $ScriptArguments
  }
  if ($pwshArgs -notcontains '-Verbose') {
    $pwshArgs += '-Verbose'
  }
  try {
    $output = & $pwshPath @pwshArgs 2>&1 | Tee-Object -FilePath $logPath -Encoding UTF8
    foreach ($line in $output) { if ($line) { Write-UiLog $line } }
    if ($LASTEXITCODE -ne 0) {
      throw "Command '$name' failed with exit code $LASTEXITCODE. See $logPath for details."
    }
  } catch {
    if (Test-Path -LiteralPath $logPath) {
      Write-UiLog("----- Begin log tail ($logPath) -----")
      try { foreach ($line in Get-Content -LiteralPath $logPath -Tail 200) { Write-UiLog $line } }
      catch { Write-UiLog("[WARN] Failed to read log tail: $($_.Exception.Message)") }
      Write-UiLog("----- End log tail -----")
    }
    throw
  } finally {
    if (Test-Path -LiteralPath $logPath) {
      Write-UiLog("Command output saved to $logPath")
    }
  }
}

function Get-ProjectDocPriority {
  param([string]$FileName)
  switch ($FileName.ToLowerInvariant()) {
    'readme.md'          { return 1 }
    'packages.md'        { return 5 }
    'code_of_conduct.md' { return 10 }
    'contributing.md'    { return 12 }
    'security.md'        { return 15 }
    'support.md'         { return 18 }
    'legal.md'           { return 25 }
    'notice'             { return 30 }
    default              { return 60 }
  }
}

function Get-PackageDocPriority {
  param([string]$FileName)
  switch ($FileName.ToLowerInvariant()) {
    'readme.md'     { return 5 }
    'definition.md' { return 15 }
    'legal.md'      { return 80 }
    'notice'        { return 82 }
    'changelog.md'  { return 90 }
    default         { return 55 }
  }
}

function Build-DocsMenu {
  param([System.Windows.Forms.ToolStripMenuItem]$DocsMenu)
  if (-not $DocsMenu) { return [pscustomobject]@{ Success = $false; ProjectDocs = 0; GuideCategories = 0; InfrastructureGroups = 0; ToolGroups = 0; PackageGroups = 0 } }

  Write-DocsLog ("Starting docs menu build. RepoRoot={0} ScriptsRoot={1}" -f $RepoRoot,$ScriptsRoot)
  $sectionsAdded = $false
  $diagnostics = [pscustomobject]@{
    Success              = $false
    ProjectDocs          = 0
    GuideCategories      = 0
    InfrastructureGroups = 0
    ToolGroups           = 0
    PackageGroups        = 0
  }

  # Project docs (root-level)
  $projectDocs = New-Object System.Collections.Generic.List[pscustomobject]
  foreach ($file in Get-MarkdownFiles -Path $RepoRoot) {
    Add-DocRecord -List $projectDocs -Display (Format-DocTitle $file.Name) -Path $file.FullName -Priority (Get-ProjectDocPriority $file.Name) -BaseRoot $RepoRoot
  }
  Add-DocRecordIfExists -List $projectDocs -Title 'Overview'          -Path (Join-Path $RepoRoot 'README.md')          -Priority 1  -BaseRoot $RepoRoot
  Add-DocRecordIfExists -List $projectDocs -Title 'Packages Summary'  -Path (Join-Path $RepoRoot 'PACKAGES.md')        -Priority 5  -BaseRoot $RepoRoot
  Add-DocRecordIfExists -List $projectDocs -Title 'Support'           -Path (Join-Path $RepoRoot 'SUPPORT.md')         -Priority 18 -BaseRoot $RepoRoot
  Add-DocRecordIfExists -List $projectDocs -Title 'Security Policy'   -Path (Join-Path $RepoRoot 'SECURITY.md')        -Priority 15 -BaseRoot $RepoRoot
  Add-DocRecordIfExists -List $projectDocs -Title 'Contributing'      -Path (Join-Path $RepoRoot 'CONTRIBUTING.md')    -Priority 12 -BaseRoot $RepoRoot
  Add-DocRecordIfExists -List $projectDocs -Title 'Code of Conduct'   -Path (Join-Path $RepoRoot 'CODE_OF_CONDUCT.md') -Priority 10 -BaseRoot $RepoRoot
  Add-DocRecordIfExists -List $projectDocs -Title 'Legal'             -Path (Join-Path $RepoRoot 'LEGAL.md')           -Priority 25 -BaseRoot $RepoRoot
  Add-DocRecordIfExists -List $projectDocs -Title 'Notice'            -Path (Join-Path $RepoRoot 'NOTICE')             -Priority 30 -BaseRoot $RepoRoot
  $diagnostics.ProjectDocs = $projectDocs.Count
  Write-DocsLog ("Project docs discovered: {0}" -f $diagnostics.ProjectDocs)
  if (Add-DocsFlatSection -RootMenu $DocsMenu -Title 'Project' -Items $projectDocs) { $sectionsAdded = $true }

  # Guides & Reference (docs/)
  $docsRoot = Join-Path $RepoRoot 'docs'
  $guideGroups = [ordered]@{}
  if (Test-Path -LiteralPath $docsRoot) {
    foreach ($entry in Get-ChildItem -LiteralPath $docsRoot -Directory -ErrorAction SilentlyContinue) {
      $category = Get-GuideCategoryName $entry.Name
      $guideGroups[$category] = New-Object System.Collections.Generic.List[pscustomobject]
      foreach ($file in Get-MarkdownFiles -Path $entry.FullName -Recurse) {
        Add-DocRecord -List $guideGroups[$category] -Display (Format-DocTitle $file.Name) -Path $file.FullName -Priority 40 -BaseRoot $entry.FullName
      }
      if ($guideGroups[$category].Count -eq 0) { $guideGroups.Remove($category) }
    }
    foreach ($file in Get-MarkdownFiles -Path $docsRoot) {
      $general = 'General'
      if (-not $guideGroups.Contains($general)) {
        $guideGroups[$general] = New-Object System.Collections.Generic.List[pscustomobject]
      }
      Add-DocRecord -List $guideGroups[$general] -Display (Format-DocTitle $file.Name) -Path $file.FullName -Priority 30 -BaseRoot $docsRoot
    }
    if ($guideGroups.Contains('General')) {
      Add-DocRecordIfExists -List $guideGroups['General'] -Title 'Scripts Guide' -Path (Join-Path $docsRoot 'scripts-guide.md') -Priority 8  -BaseRoot $docsRoot
      Add-DocRecordIfExists -List $guideGroups['General'] -Title 'Usage'         -Path (Join-Path $docsRoot 'usage.md')         -Priority 12 -BaseRoot $docsRoot
      Add-DocRecordIfExists -List $guideGroups['General'] -Title 'Overview'      -Path (Join-Path $docsRoot 'overview.md')      -Priority 10 -BaseRoot $docsRoot
    }
  } else {
    Write-DocsLog ("Docs directory not found: {0}" -f $docsRoot)
  }
  $diagnostics.GuideCategories = $guideGroups.Keys.Count
  Write-DocsLog ("Guide categories discovered: {0}" -f $diagnostics.GuideCategories)
  if (Add-DocsGroupedSection -RootMenu $DocsMenu -Title 'Guides & Reference' -Groups $guideGroups) { $sectionsAdded = $true }

  # Infrastructure
  $infraGroups = [ordered]@{}
  foreach ($infra in @('infra','k8s','provisioning','monitoring')) {
    $path = Join-Path $RepoRoot $infra
    if (-not (Test-Path -LiteralPath $path)) { continue }
    $list = New-Object System.Collections.Generic.List[pscustomobject]
    foreach ($file in Get-MarkdownFiles -Path $path -Recurse) {
      Add-DocRecord -List $list -Display (Format-DocTitle $file.Name) -Path $file.FullName -Priority 35 -BaseRoot $path
    }
    if ($list.Count -gt 0) {
      $infraGroups[(Format-SlugName $infra)] = $list
    }
  }
  $diagnostics.InfrastructureGroups = $infraGroups.Keys.Count
  Write-DocsLog ("Infrastructure groups discovered: {0}" -f $diagnostics.InfrastructureGroups)
  if (Add-DocsGroupedSection -RootMenu $DocsMenu -Title 'Infrastructure' -Groups $infraGroups) { $sectionsAdded = $true }

  # Tooling & Examples
  $toolGroups = [ordered]@{}
  foreach ($tool in @('tools','examples','bin')) {
    $path = Join-Path $RepoRoot $tool
    if (-not (Test-Path -LiteralPath $path)) { continue }
    $list = New-Object System.Collections.Generic.List[pscustomobject]
    foreach ($file in Get-MarkdownFiles -Path $path -Recurse) {
      Add-DocRecord -List $list -Display (Format-DocTitle $file.Name) -Path $file.FullName -Priority 45 -BaseRoot $path
    }
    if ($list.Count -gt 0) {
      $toolGroups[(Format-SlugName $tool)] = $list
    }
  }
  $diagnostics.ToolGroups = $toolGroups.Keys.Count
  Write-DocsLog ("Tooling groups discovered: {0}" -f $diagnostics.ToolGroups)
  if (Add-DocsGroupedSection -RootMenu $DocsMenu -Title 'Tooling & Examples' -Groups $toolGroups) { $sectionsAdded = $true }

  # Packages
  $packageGroups = [ordered]@{}
  if (Test-Path -LiteralPath $PackagesDir) {
    foreach ($pkg in Get-ChildItem -LiteralPath $PackagesDir -Directory -ErrorAction SilentlyContinue) {
      $pkgList = New-Object System.Collections.Generic.List[pscustomobject]
      foreach ($file in Get-MarkdownFiles -Path $pkg.FullName) {
        Add-DocRecord -List $pkgList -Display (Format-DocTitle $file.Name) -Path $file.FullName -Priority (Get-PackageDocPriority $file.Name) -BaseRoot $pkg.FullName
      }
      $pkgDocsDir = Join-Path $pkg.FullName 'docs'
      if (Test-Path -LiteralPath $pkgDocsDir) {
        foreach ($file in Get-MarkdownFiles -Path $pkgDocsDir -Recurse) {
          Add-DocRecord -List $pkgList -Display (Format-DocTitle $file.Name) -Path $file.FullName -Priority (Get-PackageDocPriority $file.Name) -BaseRoot $pkg.FullName
        }
      }
      Add-DocRecordIfExists -List $pkgList -Title 'Overview'   -Path (Join-Path $pkg.FullName 'README.md')         -Priority 5  -BaseRoot $pkg.FullName
      Add-DocRecordIfExists -List $pkgList -Title 'Definition' -Path (Join-Path $pkg.FullName 'docs/definition.md') -Priority 15 -BaseRoot $pkg.FullName
      Add-DocRecordIfExists -List $pkgList -Title 'Legal'      -Path (Join-Path $pkg.FullName 'LEGAL.md')          -Priority 80 -BaseRoot $pkg.FullName
      Add-DocRecordIfExists -List $pkgList -Title 'Changelog'  -Path (Join-Path $pkg.FullName 'CHANGELOG.md')      -Priority 90 -BaseRoot $pkg.FullName
      if ($pkgList.Count -gt 0) {
        $packageGroups[(Format-SlugName $pkg.Name)] = $pkgList
      }
    }
  }
  $diagnostics.PackageGroups = $packageGroups.Keys.Count
  Write-DocsLog ("Package groups discovered: {0}" -f $diagnostics.PackageGroups)
  if (Add-DocsGroupedSection -RootMenu $DocsMenu -Title 'Packages' -Groups $packageGroups) { $sectionsAdded = $true }

  $diagnostics.Success = $sectionsAdded
  Write-DocsLog ("Docs menu sections added: Project={0}, Guides={1}, Infra={2}, Tools={3}, Packages={4}" -f `
    $diagnostics.ProjectDocs,$diagnostics.GuideCategories,$diagnostics.InfrastructureGroups,$diagnostics.ToolGroups,$diagnostics.PackageGroups)
  return $diagnostics
}

function Test-IsPackageStub {
  param([string]$PackagePath)
  if (-not $PackagePath) { return $false }
  $marker = Join-Path $PackagePath '.bc-local-stub'
  return (Test-Path -LiteralPath $marker)
}

function Get-MissingPackageTables {
  if (-not (Test-Path -LiteralPath $MapPg)) { return @() }
  try {
    $map = Import-PowerShellDataFile -Path $MapPg
  } catch {
    return @()
  }
  if (-not $map -or -not $map.Tables) { return @() }
  $missing = @()
  foreach ($t in $map.Tables.Keys) {
    $slug = ($t -replace '_','-')
    $path = Join-Path $PackagesDir $slug
    if (-not (Test-Path -LiteralPath $path)) {
      $missing += $t
      continue
    }
    if (Test-IsPackageStub -PackagePath $path) {
      $missing += $t
    }
  }
  return $missing
}

$MissingPackageTables = @(Get-MissingPackageTables)

function Write-UiLog {
  param([string]$Message)
  $timestamp = (Get-Date).ToString('HH:mm:ss')
  $script:LogEntryCount++
  Update-LogCountLabel
  $text = "L{0:D4} | [{1}] {2}" -f $script:LogEntryCount,$timestamp,$Message
  if ($script:LogBox -and -not $script:LogBox.IsDisposed) {
    $color = [System.Drawing.Color]::WhiteSmoke
    if ($script:LogHighlightAlerts) {
      if ($Message -like '[ERROR]*') {
        $color = [System.Drawing.Color]::LightSalmon
      } elseif ($Message -like '[WARN]*') {
        $color = [System.Drawing.Color]::Khaki
      }
    }
    $script:LogBox.SelectionStart = $script:LogBox.TextLength
    $script:LogBox.SelectionLength = 0
    $script:LogBox.SelectionColor = $color
    $script:LogBox.AppendText($text + [Environment]::NewLine)
    if (-not $script:LogPauseScrolling) {
      $script:LogBox.SelectionStart = $script:LogBox.Text.Length
      $script:LogBox.ScrollToCaret()
    }
    [System.Windows.Forms.Application]::DoEvents()
  } else {
    $script:PendingLog.Add($text) | Out-Null
  }
}

function Write-EnvironmentStatusLog {
  if ($script:EnvironmentStatusLogged) { return }
  if (-not $script:PwshExecutablePath) {
    $script:PwshExecutablePath = Resolve-PwshExecutablePath
  }
  Update-EnvironmentMetadata
  $hostLabel = $script:EnvironmentMetadata.HostType
  $pwshInfo = $script:EnvironmentMetadata.PwshPath
  Write-UiLog("Execution environment: host=$hostLabel; pwsh path=$pwshInfo.")
  if ($script:IsWindowsHost -and -not $script:PwshExecutablePath) {
    Write-UiLog("[WARN] PowerShell 7 not found on Windows host; install it from https://aka.ms/powershell or add it to PATH.")
  }
  $script:EnvironmentStatusLogged = $true
}
Write-EnvironmentStatusLog
function Test-DevEnvironment {
  if ($script:EnvironmentChecked) { return }
  $script:EnvironmentChecked = $true
  Initialize-ExternalToolsOnPath
  Write-UiLog "Checking developer tooling..."
  $gitCmd = Get-Command git -ErrorAction SilentlyContinue
  if ($gitCmd) {
    Write-UiLog ("- git available at {0}" -f $gitCmd.Source)
  } else {
    Write-UiLog "[WARN] git not found. Install via https://git-scm.com/download/win or 'winget install --id Git.Git'."
  }
  $ghCmd = Get-Command gh -ErrorAction SilentlyContinue
  if ($ghCmd) {
    Write-UiLog ("- gh available at {0}" -f $ghCmd.Source)
    try {
      $statusOutput = & gh auth status 2>&1
      if ($statusOutput) {
        foreach ($line in $statusOutput) { Write-UiLog "[gh] $line" }
      }
      if ($LASTEXITCODE -ne 0) {
        Write-UiLog "[WARN] gh auth status failed. Run 'gh auth login' in this shell."
      }
    } catch {
      Write-UiLog "[WARN] gh auth status failed: $($_.Exception.Message)"
    }
  } else {
    Write-UiLog "[WARN] GitHub CLI not found. Install via https://cli.github.com/ or 'winget install --id GitHub.cli'."
  }
}
Test-DevEnvironment

function Add-Warning {
  param([string]$Message)
  if (![string]::IsNullOrWhiteSpace($Message)) {
    $Warnings.Add($Message)
    Write-UiLog("[WARN] $Message")
  }
}

function Save-GitHubCommitSettings {
  if (-not $script:UmbrellaTitleBox -or -not $script:UmbrellaBodyBox -or -not $script:PackagesTitleBox -or -not $script:PackagesBodyBox) {
    return
  }
  try {
    if (-not (Test-Path -LiteralPath $SettingsDir)) {
      New-Item -ItemType Directory -Path $SettingsDir -Force | Out-Null
    }
    $payload = [ordered]@{
      UmbrellaTitle = $script:UmbrellaTitleBox.Text
      UmbrellaBody  = $script:UmbrellaBodyBox.Text
      PackagesTitle = $script:PackagesTitleBox.Text
      PackagesBody  = $script:PackagesBodyBox.Text
    }
    $json = $payload | ConvertTo-Json -Depth 3
    Set-Content -LiteralPath $script:GitHubSettingsPath -Value $json -Encoding UTF8
  } catch {
    Add-Warning("Failed to persist GitHub commit drafts: $($_.Exception.Message)")
  }
}

function Invoke-Executable {
  param(
    [Parameter(Mandatory)][string]$FilePath,
    [string[]]$Arguments = @(),
    [string]$WorkingDirectory = $RepoRoot,
    [string]$DisplayName,
    [string]$LogFilePath
  )
  if (-not $DisplayName) {
    $DisplayName = "$FilePath $($Arguments -join ' ')"
  }
  Write-UiLog "Executing: $DisplayName"
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $FilePath
  $psi.WorkingDirectory = $WorkingDirectory
  foreach ($arg in $Arguments) { [void]$psi.ArgumentList.Add($arg) }
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError  = $true
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true

  $process = New-Object System.Diagnostics.Process
  $process.StartInfo = $psi
  $stdoutHandlerId = "InvokeExecutable.Output." + ([guid]::NewGuid().ToString('N'))
  $stderrHandlerId = "InvokeExecutable.Error." + ([guid]::NewGuid().ToString('N'))
  $logWriter = $null
  $rawWriter = $null
  if ($LogFilePath) {
    try {
      $logDir = Split-Path -Parent $LogFilePath
      if ($logDir -and -not (Test-Path -LiteralPath $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
      }
      $logWriter = [System.IO.StreamWriter]::new($LogFilePath,$false,[System.Text.Encoding]::UTF8)
      $logWriter.AutoFlush = $true
      $rawWriter = [System.IO.FileStream]::new($LogFilePath + '.raw',[System.IO.FileMode]::Create,[System.IO.FileAccess]::Write,[System.IO.FileShare]::Read)
    } catch {
      $logWriter = $null
      $rawWriter = $null
    }
  }
  try {
    Register-ObjectEvent -InputObject $process -EventName 'OutputDataReceived' -SourceIdentifier $stdoutHandlerId -Action {
      param($eventSender,$outputArgs)
      if ([string]::IsNullOrEmpty($outputArgs.Data)) { return }
      Invoke-UiThread { param($line) Write-UiLog $line } @($outputArgs.Data)
      if ($logWriter) {
        try { $logWriter.WriteLine($outputArgs.Data) } catch { }
      }
      if ($rawWriter) {
        try {
          $bytes = [System.Text.Encoding]::UTF8.GetBytes($outputArgs.Data + [Environment]::NewLine)
          $rawWriter.Write($bytes,0,$bytes.Length)
        } catch { }
      }
    } | Out-Null
    Register-ObjectEvent -InputObject $process -EventName 'ErrorDataReceived' -SourceIdentifier $stderrHandlerId -Action {
      param($eventSender,$errorArgs)
      if ([string]::IsNullOrEmpty($errorArgs.Data)) { return }
      Invoke-UiThread { param($line) Write-UiLog $line } @($errorArgs.Data)
      if ($logWriter) {
        try { $logWriter.WriteLine($errorArgs.Data) } catch { }
      }
      if ($rawWriter) {
        try {
          $bytes = [System.Text.Encoding]::UTF8.GetBytes($errorArgs.Data + [Environment]::NewLine)
          $rawWriter.Write($bytes,0,$bytes.Length)
        } catch { }
      }
    } | Out-Null
    $null = $process.Start()
    $process.BeginOutputReadLine()
    $process.BeginErrorReadLine()
    $process.WaitForExit()
  } finally {
    foreach ($handlerId in @($stdoutHandlerId,$stderrHandlerId)) {
      if ([string]::IsNullOrEmpty($handlerId)) { continue }
      Unregister-Event -SourceIdentifier $handlerId -ErrorAction SilentlyContinue
      Remove-Job -Name $handlerId -Force -ErrorAction SilentlyContinue
    }
    if ($logWriter) { try { $logWriter.Dispose() } catch { } }
    if ($rawWriter) { try { $rawWriter.Dispose() } catch { } }
  }
  if ($process.ExitCode -ne 0) {
    throw "Command '$DisplayName' failed with exit code $($process.ExitCode)."
  }
}

$script:ComposerResolution = $null
function Invoke-ComposerCommand {
  param(
    [Parameter(Mandatory)][string[]]$Arguments,
    [string]$DisplayName
  )

  if (-not $DisplayName) {
    $DisplayName = "composer " + ($Arguments -join ' ')
  }

  if (-not $script:ComposerResolution) {
    $composerCmd = $null
    try {
      $composerCmd = Get-Command 'composer' -ErrorAction Stop
    } catch {
      $composerCmd = $null
    }

    if ($composerCmd -and $composerCmd.Source) {
      $script:ComposerResolution = @{ Mode = 'local'; Path = $composerCmd.Source }
      Write-UiLog ("Using composer binary at '{0}'." -f $composerCmd.Source)
    } else {
      $script:ComposerResolution = @{ Mode = 'docker' }
      Write-UiLog "Composer not found on host PATH; falling back to 'docker compose run --rm app composer'."
    }
  }

  if ($script:ComposerResolution.Mode -eq 'local') {
    Invoke-Executable -FilePath $script:ComposerResolution.Path -Arguments $Arguments -DisplayName $DisplayName
  } else {
    $escapedArgs = @()
    $single = [char]39
    $double = [char]34
    foreach ($arg in $Arguments) {
      $escaped = $arg -replace $single, ($single + $double + $single + $double + $single)
      $escapedArgs += $single + $escaped + $single
    }
    $composerCmd = 'composer'
    if ($escapedArgs.Count -gt 0) {
      $composerCmd += ' ' + ($escapedArgs -join ' ')
    }
    $innerCommand = "git config --global --add safe.directory /work && exec $composerCmd"
    $dockerArgs = @('compose','run','--rm','app','bash','-lc', $innerCommand)
    Invoke-Executable -FilePath 'docker' -Arguments $dockerArgs -DisplayName ("docker compose run --rm app composer " + ($Arguments -join ' '))
  }
}

function Invoke-TestMatrix {
  param(
    [string]$Label = 'composer test'
  )
  $matrix = @(
    @{ Name = 'mysql';    Service = 'app-mysql';    Env = @('BC_DB=mysql') },
    @{ Name = 'postgres'; Service = 'app-postgres'; Env = @('BC_DB=pg')     },
    @{ Name = 'mariadb';  Service = 'app-mariadb';  Env = @('BC_DB=mysql') }
  )

  # Ensure DB containers are running before tests
  try {
    Write-UiLog "[DB] ensuring mysql/postgres/mariadb are up..."
    Invoke-Executable -FilePath 'docker' -Arguments @('compose','up','-d','mysql','postgres','mariadb') -DisplayName 'docker compose up -d mysql postgres mariadb'
  } catch {
    Add-Warning("Failed to start database containers: $($_.Exception.Message)")
    return @("DB startup failed; skipping $Label")
  }

  # Reset databases to clean state
  Write-UiLog "[DB] resetting databases (drop/create schemas)..."
  try {
    Invoke-Executable -FilePath 'docker' -Arguments @('compose','exec','-T','mysql','mysql','-uroot','-proot','-e','DROP DATABASE IF EXISTS test; CREATE DATABASE test;') -DisplayName 'reset mysql test DB'
  } catch {
    Add-Warning("MySQL reset failed: $($_.Exception.Message)")
  }
  try {
    Invoke-Executable -FilePath 'docker' -Arguments @('compose','exec','-T','mariadb','mysql','-uroot','-proot','-e','DROP DATABASE IF EXISTS test; CREATE DATABASE test;') -DisplayName 'reset mariadb test DB'
  } catch {
    Add-Warning("MariaDB reset failed: $($_.Exception.Message)")
  }
  try {
    $pgReset = "DROP SCHEMA IF EXISTS public CASCADE; CREATE SCHEMA public; DROP SCHEMA IF EXISTS bc_compat CASCADE;"
    Invoke-Executable -FilePath 'docker' -Arguments @('compose','exec','-T','postgres','psql','-U','postgres','-d','test','-c',$pgReset) -DisplayName 'reset postgres test schema'
  } catch {
    Add-Warning("Postgres reset failed: $($_.Exception.Message)")
  }

  $results = @()
  foreach ($entry in $matrix) {
    $name = $entry.Name
    Write-UiLog ("[DB] {0}: starting {1}..." -f $name, $Label)
    $dockerArgs = @('compose','run','--rm')
    foreach ($envVar in $entry.Env) { $dockerArgs += @('-e',$envVar) }
    $dockerArgs += @($entry.Service,'composer','test')

    $output = @()
    $exit = 0
    try {
      $output = & docker @dockerArgs 2>&1
      $exit = $LASTEXITCODE
    } catch {
      $output = @($_.Exception.Message)
      $exit = 1
    }
    foreach ($line in $output) {
      if ($line) { Write-UiLog ("[{0}] {1}" -f $name,$line) }
    }

    $modulesCount = $null
    foreach ($line in $output) {
      if ($line -match 'ALL GREEN \((\d+)\s+modules\)') {
        $modulesCount = [int]$matches[1]
        break
      }
    }
    $failModules = @()
    foreach ($line in $output) {
      if ($line -match '^\[FAIL\]\[install\]\s+([^\:]+)') {
        $failModules += $matches[1].Trim()
      }
    }
    $failModules = @($failModules | Select-Object -Unique)

    $success = ($exit -eq 0)
    $summary = if ($success) {
      $suffix = if ($modulesCount) { " ($modulesCount modules)" } else { '' }
      ("{0} ✓ ALL GREEN{1}" -f $name,$suffix)
    } else {
      $failText = if ($failModules.Count -gt 0) { $failModules -join ', ' } else { 'test failures' }
      ("{0} ✖ {1}" -f $name,$failText)
    }
    Write-UiLog ("[DB] {0}" -f $summary)
    if (-not $success) {
      $Warnings.Add(("DB tests failed for {0}: {1}" -f $name, ($failModules -join ', '))) | Out-Null
    }
    $results += $summary
  }
  return ,$results
}

function Protect-SubmoduleWorkingTrees {
  param([string]$RepoRoot)

  $gitmodules = Join-Path $RepoRoot '.gitmodules'
  if (-not (Test-Path -LiteralPath $gitmodules)) { return @() }

  $lines = & git -C $RepoRoot config -f $gitmodules --get-regexp path 2>$null
  if (-not $lines) { return @() }

  $stashed = New-Object System.Collections.Generic.List[object]
  foreach ($line in $lines) {
    $parts = $line -split '\s+',2
    if ($parts.Count -lt 2) { continue }
    $rel = $parts[1].Trim()
    if (-not $rel) { continue }

    $full = Join-Path $RepoRoot $rel
    if (-not (Test-Path -LiteralPath $full)) { continue }
    $gitMarker = Join-Path $full '.git'
    if (Test-Path -LiteralPath $gitMarker) { continue }

    $tempDir = "{0}.pre-submodule.{1}" -f $full, ([guid]::NewGuid().ToString('N'))
    Write-UiLog ("Detected existing files at '{0}' without submodule metadata. Moving to '{1}' before cloning." -f $rel,(Split-Path -Leaf $tempDir))
    Move-Item -LiteralPath $full -Destination $tempDir
    $stashed.Add([pscustomobject]@{ RelativePath = $rel; TempPath = $tempDir })
  }

  ,$stashed.ToArray()
}

function Restore-SubmoduleWorkingTrees {
  param(
    [Parameter()][object[]]$ProtectedPaths,
    [Parameter(Mandatory)][string]$RepoRoot,
    [switch]$CopyBack
  )

  if (-not $ProtectedPaths) { return }

  foreach ($entry in $ProtectedPaths) {
    if (-not $entry) { continue }
    $dest = Join-Path $RepoRoot $entry.RelativePath
    $temp = $entry.TempPath
    if (-not (Test-Path -LiteralPath $temp)) { continue }

    if ($CopyBack) {
      Write-UiLog ("Restoring preserved files into submodule '{0}'." -f $entry.RelativePath)
      if (-not (Test-Path -LiteralPath $dest)) {
        Move-Item -LiteralPath $temp -Destination $dest -Force
        continue
      }
      Get-ChildItem -LiteralPath $temp -Force | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $dest -Recurse -Force
      }
      Remove-Item -LiteralPath $temp -Recurse -Force
    } else {
      Write-UiLog ("Submodule sync failed; restoring '{0}' from temporary stash." -f $entry.RelativePath)
      if (Test-Path -LiteralPath $dest) {
        Remove-Item -LiteralPath $dest -Recurse -Force -ErrorAction SilentlyContinue
      }
      Move-Item -LiteralPath $temp -Destination $dest -Force
    }
  }
}

function Invoke-Script {
  param(
    [Parameter(Mandatory)][scriptblock]$ScriptBlock,
    [string]$DisplayName
  )
  if ($DisplayName) { Write-UiLog "Running: $DisplayName" }
  & $ScriptBlock
}

function New-Step {
  param(
    [string]$Name,
    [string]$Description,
    [scriptblock]$Action,
    [scriptblock]$ShouldRun
  )
  if (-not $ShouldRun) { $ShouldRun = { $true } }
  [pscustomobject]@{
    Name        = $Name
    Description = $Description
    Action      = $Action
    ShouldRun   = $ShouldRun
    Item        = $null
  }
}

$form = New-Object System.Windows.Forms.Form
$form.Text = 'BlackCat Dev Workflow'
$form.StartPosition = 'CenterScreen'
$form.Size = New-Object System.Drawing.Size(1320, 880)
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.BackColor = $Theme.FormBack
$form.ForeColor = $Theme.Text
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Regular)
try {
  $iconPath = Join-Path $AssetsDir 'favicon.ico'
  if (Test-Path -LiteralPath $iconPath) {
    $form.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon($iconPath)
  }
} catch {
  # keep default icon if load fails
}
if ($script:BackgroundImage) {
  $form.BackgroundImage = $null
}
$screenArea = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$maxHeight = [int][Math]::Floor($screenArea.Height * 0.8)
if ($form.Height -gt $maxHeight) {
  $form.Height = $maxHeight
}

$menuStrip = New-Object System.Windows.Forms.MenuStrip
$menuStrip.BackColor = [System.Drawing.Color]::FromArgb(10,14,25)
$menuStrip.ForeColor = $Theme.Text
$menuStrip.RenderMode = 'Professional'
$menuStrip.Renderer = New-Object DarkMenuRenderer
$form.MainMenuStrip = $menuStrip
$form.Controls.Add($menuStrip)

$docsMenu = New-Object System.Windows.Forms.ToolStripMenuItem('Docs')
$docsReport = Build-DocsMenu -DocsMenu $docsMenu
$docsBuilt = $docsReport.Success
if (-not $docsBuilt) {
  Add-Warning(("Docs menu build failed (project docs={0}, guide categories={1}, infra groups={2}, tool groups={3}, packages={4})." -f `
    $docsReport.ProjectDocs,$docsReport.GuideCategories,$docsReport.InfrastructureGroups,$docsReport.ToolGroups,$docsReport.PackageGroups))
  Write-DocsLog "Docs menu build failed; see warning above."
}
if (-not $docsBuilt -or $docsMenu.DropDownItems.Count -eq 0) {
  $fallbackMessage = if (-not $docsBuilt) {
    ("Docs catalog unavailable - check {0} (project {1}/guides {2}/infra {3}/tools {4}/packages {5})." -f `
      $script:DocsLogPath,$docsReport.ProjectDocs,$docsReport.GuideCategories,$docsReport.InfrastructureGroups,$docsReport.ToolGroups,$docsReport.PackageGroups)
  } else {
    'No markdown documents were discovered in this repo.'
  }
  $placeholder = New-Object System.Windows.Forms.ToolStripMenuItem($fallbackMessage)
  $placeholder.Enabled = $false
  $docsMenu.DropDownItems.Add($placeholder) | Out-Null
}

$shortcutsMenu = New-Object System.Windows.Forms.ToolStripMenuItem('Automation')
$obsStatusItem = New-Object System.Windows.Forms.ToolStripMenuItem('Observability status (docker compose ps)')
$obsStatusItem.Add_Click({
  try {
    $composePath = Join-Path $ScriptsRoot 'dev/observability-compose.yml'
    Invoke-Executable -FilePath 'docker' -Arguments @('compose','-f',$composePath,'ps') -DisplayName 'docker compose ps (observability)'
  } catch {
    Add-Warning("Observability status failed: $($_.Exception.Message)")
  }
})
$shortcutsMenu.DropDownItems.Add($obsStatusItem) | Out-Null
$devObsItem = New-Object System.Windows.Forms.ToolStripMenuItem('Launch Dev Observability workflow')
$devObsItem.Add_Click({
  try {
    Invoke-PwshScript -ScriptPath (Join-Path $ScriptsRoot 'dev/Dev-Observability.ps1') -DisplayName 'Dev-Observability.ps1'
  } catch {
    Add-Warning("Dev observability script failed: $($_.Exception.Message)")
  }
})
$shortcutsMenu.DropDownItems.Add($devObsItem) | Out-Null
$envCheckItem = New-Object System.Windows.Forms.ToolStripMenuItem('Run Environment Check')
$envCheckItem.Add_Click({
  try {
    Test-DevEnvironment
    [System.Windows.Forms.MessageBox]::Show("Environment check results were written to the workflow log.","Dev Workflow")
  } catch {
    Add-Warning("Environment check failed: $($_.Exception.Message)")
  }
})
$shortcutsMenu.DropDownItems.Add($envCheckItem) | Out-Null

$opsMenu = New-Object System.Windows.Forms.ToolStripMenuItem('Ops')
$grafanaItem = New-Object System.Windows.Forms.ToolStripMenuItem('Open Grafana dashboard')
$grafanaItem.Add_Click({ Start-Process 'http://localhost:3000' })
$opsMenu.DropDownItems.Add($grafanaItem) | Out-Null

$startObsItem = New-Object System.Windows.Forms.ToolStripMenuItem('Start observability stack')
$startObsItem.Add_Click({
  try {
    $composePath = Join-Path $ScriptsRoot 'dev/observability-compose.yml'
    Invoke-Executable -FilePath 'docker' -Arguments @('compose','-f',$composePath,'up','-d') -DisplayName 'docker compose up (observability)'
  } catch {
    Add-Warning("Failed to start observability stack: $($_.Exception.Message)")
  }
})
$opsMenu.DropDownItems.Add($startObsItem) | Out-Null

$stopObsItem = New-Object System.Windows.Forms.ToolStripMenuItem('Stop observability stack')
$stopObsItem.Add_Click({
  try {
    $composePath = Join-Path $ScriptsRoot 'dev/observability-compose.yml'
    Invoke-Executable -FilePath 'docker' -Arguments @('compose','-f',$composePath,'down') -DisplayName 'docker compose down (observability)'
  } catch {
    Add-Warning("Failed to stop observability stack: $($_.Exception.Message)")
  }
})
$opsMenu.DropDownItems.Add($stopObsItem) | Out-Null

$schemaMenu = New-Object System.Windows.Forms.ToolStripMenuItem('Schema')
$schemaMkItem = New-Object System.Windows.Forms.ToolStripMenuItem('Regenerate master schema (mk-schema)')
$schemaMkItem.Add_Click({
  try {
    Invoke-PwshScript -ScriptPath (Join-Path $SchemaTools 'mk-schema.ps1') -DisplayName 'mk-schema.ps1'
  } catch {
    Add-Warning("mk-schema failed: $($_.Exception.Message)")
  }
})
$schemaMenu.DropDownItems.Add($schemaMkItem) | Out-Null

$schemaGenerateItem = New-Object System.Windows.Forms.ToolStripMenuItem('Generate package PHP (Generate-PhpFromSchema)')
$schemaGenerateItem.Add_Click({
  try {
    Invoke-PwshScript -ScriptPath (Join-Path $SchemaTools 'Generate-PhpFromSchema.ps1') -DisplayName 'Generate-PhpFromSchema.ps1'
  } catch {
    Add-Warning("Generate-PhpFromSchema failed: $($_.Exception.Message)")
  }
})
$schemaMenu.DropDownItems.Add($schemaGenerateItem) | Out-Null

$schemaSplitItem = New-Object System.Windows.Forms.ToolStripMenuItem('Split schema to packages')
$schemaSplitItem.Add_Click({
  try {
    Invoke-PwshScript -ScriptPath (Join-Path $SchemaTools 'Split-SchemaToPackages.ps1') -DisplayName 'Split-SchemaToPackages.ps1'
  } catch {
    Add-Warning("Split-SchemaToPackages failed: $($_.Exception.Message)")
  }
})
$schemaMenu.DropDownItems.Add($schemaSplitItem) | Out-Null

$schemaCleanupItem = New-Object System.Windows.Forms.ToolStripMenuItem('Cleanup generated schema folders')
$schemaCleanupItem.Add_Click({
  try {
    Invoke-PwshScript -ScriptPath (Join-Path $SchemaTools 'Cleanup-SchemaFolders.ps1') -DisplayName 'Cleanup-SchemaFolders.ps1'
  } catch {
    Add-Warning("Cleanup-SchemaFolders failed: $($_.Exception.Message)")
  }
})
$schemaMenu.DropDownItems.Add($schemaCleanupItem) | Out-Null

$qualityMenu = New-Object System.Windows.Forms.ToolStripMenuItem('Quality')

$qualitySchemaOutput = New-Object System.Windows.Forms.ToolStripMenuItem('Test schema output')
$qualitySchemaOutput.Add_Click({
  try {
    Invoke-PwshScript -ScriptPath (Join-Path $ScriptsRoot 'quality/Test-SchemaOutput.ps1') -DisplayName 'Test-SchemaOutput.ps1'
  } catch {
    Add-Warning("Test-SchemaOutput failed: $($_.Exception.Message)")
  }
})
$qualityMenu.DropDownItems.Add($qualitySchemaOutput) | Out-Null

$qualityPackagesSchema = New-Object System.Windows.Forms.ToolStripMenuItem('Test packages schema')
$qualityPackagesSchema.Add_Click({
  try {
    Invoke-PwshScript -ScriptPath (Join-Path $ScriptsRoot 'quality/Test-PackagesSchema.ps1') -DisplayName 'Test-PackagesSchema.ps1'
  } catch {
    Add-Warning("Test-PackagesSchema failed: $($_.Exception.Message)")
  }
})
$qualityMenu.DropDownItems.Add($qualityPackagesSchema) | Out-Null

$qualitySecrets = New-Object System.Windows.Forms.ToolStripMenuItem('Secrets scan (Check-Secrets)')
$qualitySecrets.Add_Click({
  try {
    Invoke-PwshScript -ScriptPath (Join-Path $ScriptsRoot 'quality/Check-Secrets.ps1') -DisplayName 'Check-Secrets.ps1'
  } catch {
    Add-Warning("Check-Secrets failed: $($_.Exception.Message)")
  }
})
$qualityMenu.DropDownItems.Add($qualitySecrets) | Out-Null

$qualityLicense = New-Object System.Windows.Forms.ToolStripMenuItem('Enforce LICENSE/NOTICE')
$qualityLicense.Add_Click({
  try {
    Invoke-PwshScript -ScriptPath (Join-Path $ScriptsRoot 'quality/enforce-license.ps1') -DisplayName 'enforce-license.ps1'
  } catch {
    Add-Warning("enforce-license failed: $($_.Exception.Message)")
  }
})
$qualityMenu.DropDownItems.Add($qualityLicense) | Out-Null

$workflowMenu = New-Object System.Windows.Forms.ToolStripMenuItem('Workflow')
$toggleWorkflowMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem('Toggle workflow panel')
$toggleWorkflowMenuItem.Enabled = $false
$workflowMenu.DropDownItems.Add($toggleWorkflowMenuItem) | Out-Null
$startWorkflowMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem('Start workflow run')
$startWorkflowMenuItem.Enabled = $false
$workflowMenu.DropDownItems.Add($startWorkflowMenuItem) | Out-Null
$applySuggestionMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem('Apply recommended flow')
$applySuggestionMenuItem.Enabled = $false
$workflowMenu.DropDownItems.Add($applySuggestionMenuItem) | Out-Null

$reposMenu = New-Object System.Windows.Forms.ToolStripMenuItem('Repos')
$openUmbrellaMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem('Open umbrella repo folder')
$openUmbrellaMenuItem.Add_Click({ Start-Process $RepoRoot })
$reposMenu.DropDownItems.Add($openUmbrellaMenuItem) | Out-Null
$openPackagesMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem('Open packages folder')
$openPackagesMenuItem.Add_Click({ if (Test-Path -LiteralPath $PackagesDir) { Start-Process $PackagesDir } })
$reposMenu.DropDownItems.Add($openPackagesMenuItem) | Out-Null
$gitStatusMenuItem = New-Object System.Windows.Forms.ToolStripMenuItem('Run git status (umbrella)')
$gitStatusMenuItem.Add_Click({
  try {
    Invoke-Executable -FilePath 'git' -Arguments @('status','-sb') -WorkingDirectory $RepoRoot -DisplayName 'git status (umbrella)'
  } catch {
    Add-Warning("git status failed: $($_.Exception.Message)")
  }
})
$reposMenu.DropDownItems.Add($gitStatusMenuItem) | Out-Null

$menuStrip.Items.AddRange(@($docsMenu,$shortcutsMenu,$opsMenu,$schemaMenu,$qualityMenu,$workflowMenu,$reposMenu))

$mainLayout = New-Object System.Windows.Forms.TableLayoutPanel
$mainLayout.Dock = 'Fill'
$mainLayout.BackColor = [System.Drawing.Color]::FromArgb(0,0,0,0)
$mainLayout.ColumnCount = 2
$mainLayout.RowCount = 1
$centerColumn = New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent,100)
$logColumn = New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute,380)
$mainLayout.ColumnStyles.Add($centerColumn) | Out-Null
$mainLayout.ColumnStyles.Add($logColumn) | Out-Null
$mainLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent,100)))

$dockContainer = New-Object System.Windows.Forms.Panel
$dockContainer.Dock = 'Fill'
$dockContainer.Padding = New-Object System.Windows.Forms.Padding(0, [int]$menuStrip.Height, 0, 0)
$dockContainer.BackColor = [System.Drawing.Color]::FromArgb(0,0,0,0)
$dockContainer.Controls.Add($mainLayout)
$form.Controls.Add($dockContainer)

$leftColumnPanel = New-Object System.Windows.Forms.Panel
$leftColumnPanel.Dock = 'Fill'
$leftColumnPanel.BackColor = $Theme.FormBack
$leftColumnPanel.Margin = New-Object System.Windows.Forms.Padding 0
if ($script:BackgroundImage) {
  $leftColumnPanel.BackgroundImage = $script:BackgroundImage
  $leftColumnPanel.BackgroundImageLayout = 'Zoom'
}
$mainLayout.Controls.Add($leftColumnPanel,0,0)

$leftColumnLayout = New-Object System.Windows.Forms.TableLayoutPanel
$leftColumnLayout.Dock = 'Fill'
$leftColumnLayout.ColumnCount = 2
$leftColumnLayout.RowCount = 1
$leftColumnLayout.BackColor = [System.Drawing.Color]::Transparent
$leftColumnLayout.Margin = New-Object System.Windows.Forms.Padding 0
$leftColumnLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute,324)))
$leftColumnLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent,100)))
$leftColumnLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent,100)))
$leftColumnPanel.Controls.Add($leftColumnLayout)

$leftPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$leftPanel.Dock = 'Fill'
$leftPanel.FlowDirection = 'TopDown'
$leftPanel.WrapContents = $false
$leftPanel.AutoScroll = $true
$leftPanel.Margin = New-Object System.Windows.Forms.Padding 0
$leftPanel.Padding = New-Object System.Windows.Forms.Padding 6,6,6,6
$leftPanel.AutoScrollMargin = New-Object System.Drawing.Size(0,20)
$leftPanel.BackColor = [System.Drawing.Color]::Transparent
$leftColumnLayout.Controls.Add($leftPanel,0,0)

$leftMarkerPlaceholder = New-Object System.Windows.Forms.Panel
$leftMarkerPlaceholder.BackColor = [System.Drawing.Color]::Transparent
$leftMarkerPlaceholder.Margin = New-Object System.Windows.Forms.Padding(0)
$leftMarkerPlaceholder.Padding = New-Object System.Windows.Forms.Padding(0)
$leftMarkerPlaceholder.Width = 250
$leftMarkerPlaceholder.Height = 460
$leftMarkerPlaceholder.MinimumSize = New-Object System.Drawing.Size(250,460)
$leftMarkerPlaceholder.MaximumSize = New-Object System.Drawing.Size(250,0)
$leftPanel.Controls.Add($leftMarkerPlaceholder)
Set-CardTheme $leftMarkerPlaceholder

$leftMarkerTextPanel = New-Object System.Windows.Forms.TableLayoutPanel
$leftMarkerTextPanel.Dock = 'Fill'
$leftMarkerTextPanel.ColumnCount = 1
$leftMarkerTextPanel.RowCount = 5
$leftMarkerTextPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent,100)))
$leftMarkerTextPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
$leftMarkerTextPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
$leftMarkerTextPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
$leftMarkerTextPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
$leftMarkerTextPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent,100)))
$leftMarkerTextPanel.Padding = New-Object System.Windows.Forms.Padding(6,6,6,6)
$leftMarkerPlaceholder.Controls.Add($leftMarkerTextPanel)

$leftMarkerTitle = New-Object System.Windows.Forms.Label
$leftMarkerTitle.Text = "Welcome, stealth cat hero!"
$leftMarkerTitle.AutoSize = $true
$leftMarkerTitle.Margin = New-Object System.Windows.Forms.Padding(0,0,0,6)
$leftMarkerTitle.ForeColor = $Theme.Text
$leftMarkerTitle.TextAlign = 'MiddleCenter'
$leftMarkerTitle.Dock = 'Top'
$leftMarkerTitle.Font = New-Object System.Drawing.Font($form.Font.FontFamily,10,[System.Drawing.FontStyle]::Bold)
$leftMarkerTextPanel.Controls.Add($leftMarkerTitle,0,0)

$leftMarkerMessage = New-Object System.Windows.Forms.Label
$leftMarkerMessage.Margin = New-Object System.Windows.Forms.Padding(0,0,0,10)
$leftMarkerMessage.TextAlign = 'TopLeft'
$leftMarkerMessage.ForeColor = $Theme.Text
$leftMarkerMessage.Dock = 'Top'
$leftMarkerMessage.AutoSize = $true
$leftMarkerMessage.MaximumSize = New-Object System.Drawing.Size(230,0)
$leftMarkerMessage.Font = New-Object System.Drawing.Font($form.Font.FontFamily,9,[System.Drawing.FontStyle]::Regular)
$leftMarkerMessage.Text = "Thank you for keeping Black Cat Academy s. r. o. running smoother than a well-fed tabby.`nThis console respects your senior wizardry; it just gives your wrists fewer excuses to overwork.`nShip boldly, then use the reclaimed minutes for naps, tea, or suspiciously long cat videos."
$leftMarkerTextPanel.Controls.Add($leftMarkerMessage,0,1)

$leftMarkerBlurb = New-Object System.Windows.Forms.Label
$leftMarkerBlurb.Dock = 'Top'
$leftMarkerBlurb.Margin = New-Object System.Windows.Forms.Padding(0,0,0,10)
$leftMarkerBlurb.ForeColor = [System.Drawing.Color]::FromArgb(190,$Theme.Text.R,$Theme.Text.G,$Theme.Text.B)
$leftMarkerBlurb.Font = New-Object System.Drawing.Font($form.Font.FontFamily,8,[System.Drawing.FontStyle]::Italic)
$leftMarkerBlurb.AutoSize = $true
$leftMarkerBlurb.MaximumSize = New-Object System.Drawing.Size(230,0)
$leftMarkerBlurb.Text = "Think of this pane as the cat tree placard: quick context about what to expect, where to click, and why the UI already sharpened its claws for you."
$leftMarkerTextPanel.Controls.Add($leftMarkerBlurb,0,2)

$leftMarkerQuick = New-Object System.Windows.Forms.Label
$leftMarkerQuick.Dock = 'Top'
$leftMarkerQuick.Margin = New-Object System.Windows.Forms.Padding(0,0,0,8)
$leftMarkerQuick.ForeColor = [System.Drawing.Color]::LightSteelBlue
$leftMarkerQuick.Font = New-Object System.Drawing.Font($form.Font.FontFamily,8,[System.Drawing.FontStyle]::Regular)
$leftMarkerQuick.AutoSize = $true
$leftMarkerQuick.MaximumSize = New-Object System.Drawing.Size(230,0)
$leftMarkerQuick.Text = "Quick start: check the steps you need, accept Catwatch's suggestion if it pops up, then hit Start Workflow. While it churns, stretch, hydrate, or practice your best laser-pointer dodge. If something misbehaves, toggle the panel, adjust, and pounce again-no claws required."
$leftMarkerTextPanel.Controls.Add($leftMarkerQuick,0,3)

$leftMarkerLaunchBtn = New-Object System.Windows.Forms.Button
$leftMarkerLaunchBtn.Text = "Let's begin!"
$leftMarkerLaunchBtn.AutoSize = $true
$leftMarkerLaunchBtn.Anchor = 'Top'
$leftMarkerLaunchBtn.Margin = New-Object System.Windows.Forms.Padding(0,0,0,12)
Set-ButtonStyle $leftMarkerLaunchBtn
$leftMarkerTextPanel.Controls.Add($leftMarkerLaunchBtn,0,4)
$script:LeftLaunchButton = $leftMarkerLaunchBtn

$leftMarkerFooter = New-Object System.Windows.Forms.Label
$leftMarkerFooter.Text = "(c) $(Get-Date -Format 'yyyy') Black Cat Academy s. r. o."
$leftMarkerFooter.Dock = 'Bottom'
$leftMarkerFooter.AutoSize = $false
$leftMarkerFooter.Margin = New-Object System.Windows.Forms.Padding(0,0,0,4)
$leftMarkerFooter.Padding = New-Object System.Windows.Forms.Padding(6,0,6,4)
$leftMarkerFooter.ForeColor = [System.Drawing.Color]::FromArgb(160,$Theme.Text.R,$Theme.Text.G,$Theme.Text.B)
$leftMarkerFooter.TextAlign = 'MiddleCenter'
$leftMarkerPlaceholder.Controls.Add($leftMarkerFooter)


$centerPanel = New-Object System.Windows.Forms.Panel
$centerPanel.Dock = 'Fill'
$centerPanel.BackColor = [System.Drawing.Color]::Transparent
$leftColumnLayout.Controls.Add($centerPanel,1,0)

$centerLayout = New-Object System.Windows.Forms.TableLayoutPanel
$centerLayout.Dock = 'Fill'
$centerLayout.ColumnCount = 1
$centerLayout.RowCount = 1
$centerLayout.BackColor = [System.Drawing.Color]::Transparent
$centerLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent,100)))
$centerLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent,100)))
$centerPanel.Controls.Add($centerLayout)

$centerMainHost = New-Object System.Windows.Forms.Panel
$centerMainHost.Dock = 'Fill'
$centerMainHost.Margin = New-Object System.Windows.Forms.Padding(10,10,10,10)
$centerMainHost.BackColor = [System.Drawing.Color]::Transparent
$centerLayout.Controls.Add($centerMainHost,0,0)

$stepsOverlayHost = New-Object System.Windows.Forms.Panel
$stepsOverlayHost.Dock = 'Fill'
$stepsOverlayHost.BackColor = [System.Drawing.Color]::Transparent
$centerMainHost.Controls.Add($stepsOverlayHost)

$logPanel = New-Object System.Windows.Forms.Panel
$logPanel.Dock = 'Fill'
$logPanel.Padding = New-Object System.Windows.Forms.Padding(10)
$logPanel.BackColor = $Theme.FormBack
$mainLayout.Controls.Add($logPanel,1,0)

$stepsOverlay = New-Object System.Windows.Forms.Panel
$stepsOverlay.Dock = 'Fill'
$stepsOverlay.Padding = New-Object System.Windows.Forms.Padding 10
$stepsOverlay.Visible = $false
$stepsOverlay.BackColor = $Theme.PanelBack
$stepsOverlay.AutoScroll = $true
$script:WorkflowOverlayBaseColor = $stepsOverlay.BackColor
if (-not $stepsOverlay.Visible) {
  $stepsOverlay.BackColor = [System.Drawing.Color]::Transparent
}
$stepsOverlayHost.Controls.Add($stepsOverlay)
$script:WorkflowSectionPanel = $stepsOverlay

$workflowRegionPanel = New-Object System.Windows.Forms.Panel
$workflowRegionPanel.Dock = 'Fill'
$workflowRegionPanel.BackColor = $Theme.PanelBack
$workflowRegionPanel.Padding = New-Object System.Windows.Forms.Padding 0
$workflowRegionPanel.Visible = $false
$script:WorkflowPanelBaseColor = $workflowRegionPanel.BackColor
$workflowRegionPanel.BackColor = [System.Drawing.Color]::Transparent
$stepsOverlay.Controls.Add($workflowRegionPanel)

$workflowRegionLayout = New-Object System.Windows.Forms.TableLayoutPanel
$workflowRegionLayout.Dock = 'Fill'
$workflowRegionLayout.ColumnCount = 1
$workflowRegionLayout.RowCount = 2
$workflowRegionLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
$workflowRegionLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent,100)))
$workflowRegionPanel.Controls.Add($workflowRegionLayout)

$workflowTopPanel = New-Object System.Windows.Forms.Panel
$workflowTopPanel.Dock = 'Top'
$workflowTopPanel.Height = 150
$workflowTopPanel.BackColor = [System.Drawing.Color]::FromArgb(18,32,52)
$workflowTopPanel.Padding = New-Object System.Windows.Forms.Padding(12,10,12,12)
$workflowRegionLayout.Controls.Add($workflowTopPanel,0,0)

$workflowTopLayout = New-Object System.Windows.Forms.TableLayoutPanel
$workflowTopLayout.Dock = 'Fill'
$workflowTopLayout.ColumnCount = 1
$workflowTopLayout.RowCount = 3
$workflowTopLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
$workflowTopLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
$workflowTopLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute,50)))
$workflowTopPanel.Controls.Add($workflowTopLayout)

$workflowHeroLabel = New-Object System.Windows.Forms.Label
$workflowHeroLabel.Dock = 'Top'
$workflowHeroLabel.ForeColor = [System.Drawing.Color]::WhiteSmoke
$workflowHeroLabel.Font = New-Object System.Drawing.Font($form.Font.FontFamily,12,[System.Drawing.FontStyle]::Bold)
$workflowHeroLabel.TextAlign = 'MiddleLeft'
$workflowHeroLabel.Padding = New-Object System.Windows.Forms.Padding(0,0,0,6)
$workflowHeroLabel.Text = "Workflow build - herding release cats into a tidy queue."
$workflowTopLayout.Controls.Add($workflowHeroLabel,0,0)

$workflowInsightsLayout = New-Object System.Windows.Forms.TableLayoutPanel
$workflowInsightsLayout.ColumnCount = 2
$workflowInsightsLayout.RowCount = 1
$workflowInsightsLayout.Dock = 'Fill'
$workflowInsightsLayout.AutoSize = $true
$workflowInsightsLayout.AutoSizeMode = 'GrowAndShrink'
$workflowInsightsLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent,100)))
$workflowInsightsLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::AutoSize)))
$workflowInsightsLayout.Margin = New-Object System.Windows.Forms.Padding(0,4,0,10)
$workflowTopLayout.Controls.Add($workflowInsightsLayout,0,1)

$stepsControlsPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$stepsControlsPanel.Dock = 'Fill'
$stepsControlsPanel.Padding = New-Object System.Windows.Forms.Padding 0
$stepsControlsPanel.BackColor = [System.Drawing.Color]::FromArgb(18,32,52)
$stepsControlsPanel.FlowDirection = 'LeftToRight'
$stepsControlsPanel.WrapContents = $false
$workflowTopLayout.Controls.Add($stepsControlsPanel,0,2)

$selectAllBtn = New-Object System.Windows.Forms.Button
$selectAllBtn.Text = 'Select all'
$selectAllBtn.Margin = New-Object System.Windows.Forms.Padding 0,5,10,5
$selectAllBtn.Add_Click({ foreach ($i in $StepsList.Items) { $i.Checked = $true } })
Set-ButtonStyle $selectAllBtn
$stepsControlsPanel.Controls.Add($selectAllBtn)

$clearBtn = New-Object System.Windows.Forms.Button
$clearBtn.Text = 'Clear'
$clearBtn.Margin = New-Object System.Windows.Forms.Padding 0,5,10,5
$clearBtn.Add_Click({ foreach ($i in $StepsList.Items) { $i.Checked = $false } })
Set-ButtonStyle $clearBtn
$stepsControlsPanel.Controls.Add($clearBtn)

$closeButton = New-Object System.Windows.Forms.Button
$closeButton.Text = 'Close'
$closeButton.Margin = New-Object System.Windows.Forms.Padding 0,5,10,5
$closeButton.Add_Click({ $form.Close() })
Set-ButtonStyle $closeButton
$stepsControlsPanel.Controls.Add($closeButton)

$startButton = New-Object System.Windows.Forms.Button
$startButton.Text = 'Start workflow'
$startButton.Margin = New-Object System.Windows.Forms.Padding 0,5,10,5
Set-ButtonStyle $startButton
$stepsControlsPanel.Controls.Add($startButton)
$startWorkflowMenuItem.Enabled = $true
$startWorkflowMenuItem.Add_Click({
  if (-not $startButton.Enabled) { return }
  $startButton.PerformClick()
})


$tabControl = New-Object System.Windows.Forms.TabControl
$tabControl.Dock = 'Fill'
$tabControl.Padding = New-Object System.Drawing.Point(0,0)
$workflowRegionLayout.Controls.Add($tabControl,0,1)
$script:WorkflowRegionPanel = $workflowRegionPanel

$pipelineTab = New-Object System.Windows.Forms.TabPage
$pipelineTab.Text = 'Pipeline'
$pipelineTab.BackColor = $Theme.PanelBack
$pipelineTab.ForeColor = [System.Drawing.Color]::WhiteSmoke
$pipelineTab.UseVisualStyleBackColor = $false
$pipelineTab.AutoScroll = $false
$pipelineTab.Padding = New-Object System.Windows.Forms.Padding(0)
$tabControl.TabPages.Add($pipelineTab)

$stepsListHost = New-Object System.Windows.Forms.Panel
$stepsListHost.Dock = 'Fill'
$stepsListHost.AutoScroll = $true
$stepsListHost.Padding = New-Object System.Windows.Forms.Padding(0)
$stepsListHost.BackColor = $Theme.PanelBack
$pipelineTab.Controls.Add($stepsListHost)

$stepsListSurface = New-Object System.Windows.Forms.Panel
$stepsListSurface.AutoSize = $false
$stepsListSurface.AutoSizeMode = 'GrowOnly'
$stepsListSurface.Dock = 'Fill'
$stepsListSurface.Width = 0
$stepsListSurface.Height = 0
$stepsListSurface.Margin = New-Object System.Windows.Forms.Padding(0)
$stepsListSurface.Padding = New-Object System.Windows.Forms.Padding(0)
$stepsListHost.Controls.Add($stepsListSurface)
$script:StepsListScrollHost = $stepsListHost

$toolboxTab = New-Object System.Windows.Forms.TabPage
$toolboxTab.Text = 'Toolbox'
$toolboxTab.BackColor = $Theme.PanelBack
$toolboxTab.ForeColor = [System.Drawing.Color]::WhiteSmoke
$toolboxTab.UseVisualStyleBackColor = $false
$tabControl.TabPages.Add($toolboxTab)

$githubTab = New-Object System.Windows.Forms.TabPage
$githubTab.Text = 'GitHub'
$githubTab.BackColor = $Theme.PanelBack
$githubTab.ForeColor = [System.Drawing.Color]::WhiteSmoke
$githubTab.UseVisualStyleBackColor = $false
$tabControl.TabPages.Add($githubTab)

$githubLayout = New-Object System.Windows.Forms.FlowLayoutPanel
$githubLayout.Dock = 'Fill'
$githubLayout.AutoScroll = $true
$githubLayout.FlowDirection = 'TopDown'
$githubLayout.WrapContents = $false
$githubLayout.Padding = New-Object System.Windows.Forms.Padding 10
$githubLayout.BackColor = $Theme.PanelBack
$githubLayout.ForeColor = $Theme.Text
$githubTab.Controls.Add($githubLayout)

$settingsTab = New-Object System.Windows.Forms.TabPage
$settingsTab.Text = 'Settings'
$settingsTab.BackColor = $Theme.PanelBack
$settingsTab.ForeColor = [System.Drawing.Color]::WhiteSmoke
$settingsTab.UseVisualStyleBackColor = $false
$tabControl.TabPages.Add($settingsTab)

$settingsLayout = New-Object System.Windows.Forms.FlowLayoutPanel
$settingsLayout.Dock = 'Fill'
$settingsLayout.AutoScroll = $true
$settingsLayout.FlowDirection = 'TopDown'
$settingsLayout.WrapContents = $false
$settingsLayout.Padding = New-Object System.Windows.Forms.Padding 10
$settingsLayout.BackColor = $Theme.PanelBack
$settingsLayout.ForeColor = $Theme.Text
$settingsTab.Controls.Add($settingsLayout)

$StepsList = New-Object System.Windows.Forms.ListView
$StepsList.Dock = 'None'
$StepsList.Anchor = 'Top,Left'
$StepsList.View = 'Details'
$StepsList.CheckBoxes = $true
$StepsList.FullRowSelect = $true
$StepsList.BorderStyle = 'None'
$StepsList.GridLines = $true
$StepsList.Columns.Add('Step',220) | Out-Null
$StepsList.Columns.Add('Description',730) | Out-Null
$StepsList.Columns.Add('Status',140) | Out-Null
$runColumn = $StepsList.Columns.Add('Run',72)
$runColumn.TextAlign = 'Center'
$StepsList.OwnerDraw = $true
$StepsList.BackColor = $Theme.ControlBack
$StepsList.ForeColor = [System.Drawing.Color]::Gainsboro
try {
  $glyphSize = [Math]::Max(1.0,[double]$StepsList.Font.Size + 2)
  $script:RunGlyphFont = New-Object System.Drawing.Font($StepsList.Font.Name,$glyphSize,[System.Drawing.FontStyle]::Bold,$StepsList.Font.Unit)
} catch {
  $primaryFontError = $_
  try {
    $script:RunGlyphFont = [System.Drawing.Font]::new($StepsList.Font,[System.Drawing.FontStyle]::Bold)
  } catch {
    $script:RunGlyphFont = $null
    $fallbackFontError = $_
    $primaryMessage = if ($primaryFontError) { $primaryFontError.Exception.Message } else { 'unknown error' }
    Add-Warning("Failed to create run glyph font (primary: $primaryMessage; fallback: $($fallbackFontError.Exception.Message))")
  }
}
$stepsListSurface.Controls.Add($StepsList)
$script:StepsListDefaultCursor = $StepsList.Cursor
$StepsList.Add_MouseUp({
  param($evtSender,$evtArgs)
  if ($evtArgs.Button -ne [System.Windows.Forms.MouseButtons]::Left) { return }
  if (-not ($StepsList -and -not $StepsList.IsDisposed)) { return }
  $hit = $StepsList.HitTest($evtArgs.X,$evtArgs.Y)
  if (-not $hit -or -not $hit.Item) { return }
  $subItem = $hit.SubItem
  $subIndex = if ($subItem) { $hit.Item.SubItems.IndexOf($subItem) } else { -1 }
  if ($subIndex -ne 3) { return }
  $step = $hit.Item.Tag
  Invoke-AdHocWorkflowStep -Step $step
})
$StepsList.Add_MouseMove({
  param($evtSender,$evtArgs)
  if (-not ($StepsList -and -not $StepsList.IsDisposed)) { return }
  $hit = $StepsList.HitTest($evtArgs.X,$evtArgs.Y)
  $subIndex = if ($hit -and $hit.Item -and $hit.SubItem) { $hit.Item.SubItems.IndexOf($hit.SubItem) } else { -1 }
  $isCheckboxArea = $hit -and ($hit.Location -band [System.Windows.Forms.ListViewHitTestLocations]::StateImage)
  $handColumns = @(3)
  $targetCursor = if ($isCheckboxArea -or $handColumns -contains $subIndex) { [System.Windows.Forms.Cursors]::Hand } else { $script:StepsListDefaultCursor }
  if ($StepsList.Cursor -ne $targetCursor) {
    $StepsList.Cursor = $targetCursor
  }
})
$StepsList.Add_MouseLeave({
  if ($StepsList -and -not $StepsList.IsDisposed) {
    $StepsList.Cursor = $script:StepsListDefaultCursor
  }
})
$StepsList.Add_MouseWheel({
  param($evtSender,$evtArgs)
  if (-not ($StepsList -and -not $StepsList.IsDisposed)) { return }
  $scrollHost = $script:StepsListScrollHost
  if (-not ($scrollHost -and -not $scrollHost.IsDisposed -and $scrollHost.AutoScroll)) { return }
  $current = $scrollHost.AutoScrollPosition
  $newY = -$current.Y - $evtArgs.Delta
  if ($newY -lt 0) { $newY = 0 }
  $scrollHost.AutoScrollPosition = New-Object System.Drawing.Point(0, $newY)
})
$StepsList.Add_DrawColumnHeader({
  param($evtSender,$evtArgs)
  $evtArgs.DrawDefault = $true
})
$StepsList.Add_DrawItem({
  param($evtSender,$evtArgs)
  $evtArgs.DrawDefault = $true
})
$StepsList.Add_DrawSubItem({
  param($evtSender,$evtArgs)
  if ($evtArgs.ColumnIndex -ne 3) {
    $evtArgs.DrawDefault = $true
    return
  }
  $evtArgs.DrawDefault = $false
  $font = New-Object System.Drawing.Font($StepsList.Font.FontFamily,$StepsList.Font.Size + 2,[System.Drawing.FontStyle]::Bold)
  $fmt = New-Object System.Drawing.StringFormat
  $fmt.Alignment = [System.Drawing.StringAlignment]::Center
  $fmt.LineAlignment = [System.Drawing.StringAlignment]::Center
  $isSelected = ($evtArgs.Item -and $evtArgs.Item.Selected)
  $bgColor = if ($isSelected) { [System.Drawing.SystemColors]::Highlight } else { $StepsList.BackColor }
  $fgColor = if ($isSelected) { [System.Drawing.SystemColors]::HighlightText } else { $StepsList.ForeColor }
  $bgBrush = New-Object System.Drawing.SolidBrush($bgColor)
  $textBrush = New-Object System.Drawing.SolidBrush($fgColor)
  $evtArgs.Graphics.FillRectangle($bgBrush,$evtArgs.Bounds)
  $evtArgs.Graphics.DrawString($evtArgs.SubItem.Text,$font,$textBrush,$evtArgs.Bounds,$fmt)
  $textBrush.Dispose()
  $bgBrush.Dispose()
  $fmt.Dispose()
  $font.Dispose()
})

$stepsListRightCap = New-Object System.Windows.Forms.Panel
$stepsListRightCap.BackColor = $Theme.PanelBack
$stepsListRightCap.Width = 0
$stepsListRightCap.Height = 0
$stepsListRightCap.Enabled = $false
$stepsListSurface.Controls.Add($stepsListRightCap)
$stepsListRightCap.BringToFront()

function Update-StepsListHeight {
  if (-not ($StepsList -and -not $StepsList.IsDisposed)) { return }
  if (-not ($stepsListHost -and -not $stepsListHost.IsDisposed)) { return }
  $rowHeight = Get-StepsListRowHeight
  $headerHeight = Get-StepsListHeaderHeight
  $rows = $StepsList.Items.Count
  $desired = if ($rows -gt 0) { ($rows * $rowHeight) + $headerHeight } else { $headerHeight }
  $StepsList.Height = $desired

  $visibleWidth = [System.Math]::Max(1,$stepsListHost.ClientSize.Width - $stepsListHost.Padding.Horizontal)
  $StepsList.Width = $visibleWidth
  $stepsListSurface.Width = $visibleWidth
  $stepsListSurface.Height = $StepsList.Height

  $hostHeight = [System.Math]::Max(0,$stepsListHost.ClientSize.Height - $stepsListHost.Padding.Vertical)
  $needsScroll = $desired -gt $hostHeight
  $autoWidth = [System.Math]::Max(0,[int]$visibleWidth)
  $autoHeight = [System.Math]::Max(0,[int]$desired)
  if ($needsScroll) {
    $stepsListHost.AutoScrollMinSize = [System.Drawing.Size]::new($autoWidth,$autoHeight)
  } else {
    $stepsListHost.AutoScrollMinSize = [System.Drawing.Size]::Empty
    $stepsListHost.AutoScrollPosition = New-Object System.Drawing.Point 0,0
  }
  Update-StepsListColumns
}
$stepsListHost.Add_SizeChanged({ Update-StepsListHeight })

function Get-StepsListRowHeight {
  if ($StepsList -and -not $StepsList.IsDisposed -and $StepsList.Items.Count -gt 0) {
    try {
      $rect = $StepsList.GetItemRect(0)
      if ($rect.Height -gt 0) { return $rect.Height }
    } catch {
    }
  }
  return [System.Windows.Forms.TextRenderer]::MeasureText("X",$StepsList.Font).Height + 6
}

function Get-StepsListHeaderHeight {
  if ($StepsList -and -not $StepsList.IsDisposed) {
    return [System.Math]::Max(24,$StepsList.Font.Height + 16)
  }
  return $StepsList.Font.Height + 24
}

function Update-StepsListColumns {
  if (-not ($StepsList -and -not $StepsList.IsDisposed)) { return }
  if ($StepsList.Columns.Count -lt 4) { return }
  $hostWidth = [System.Math]::Max(0,$StepsList.Width)
  if ($hostWidth -le 0 -and $stepsListHost -and -not $stepsListHost.IsDisposed) {
    $hostWidth = [System.Math]::Max(0,$stepsListHost.ClientSize.Width - $stepsListHost.Padding.Horizontal)
  }
  if ($hostWidth -le 0) { return }
  $measure = {
    param([string]$text)
    $value = if ([string]::IsNullOrWhiteSpace($text)) { ' ' } else { $text }
    return [System.Windows.Forms.TextRenderer]::MeasureText($value,$StepsList.Font).Width
  }
  $maxColumnWidth = {
    param([int]$columnIndex,[bool]$splitWords)
    $maxWidth = & $measure $StepsList.Columns[$columnIndex].Text
    foreach ($item in $StepsList.Items) {
      if (-not $item) { continue }
      if ($item.SubItems.Count -le $columnIndex) { continue }
      $text = $item.SubItems[$columnIndex].Text
      if ([string]::IsNullOrWhiteSpace($text)) { continue }
      if ($splitWords) {
        foreach ($word in ($text -split '\s+')) {
          if ([string]::IsNullOrWhiteSpace($word)) { continue }
          $wordWidth = & $measure $word
          if ($wordWidth -gt $maxWidth) { $maxWidth = $wordWidth }
        }
      } else {
        $width = & $measure $text
        if ($width -gt $maxWidth) { $maxWidth = $width }
      }
    }
    return $maxWidth
  }

  $maxStep = & $maxColumnWidth 0 $false
  $maxDesc = & $maxColumnWidth 1 $false
  $maxStatusWord = & $maxColumnWidth 2 $true

  $minStepWidth = 160
  $maxStepWidth = 360
  $minDescWidth = 180
  $baseMaxDescWidth = 860
  $minStatusWidth = 60
  $maxStatusWidth = 140
  $runMinWidth = 72

  $usableWidth = [System.Math]::Max($minStepWidth + $minDescWidth + $minStatusWidth, $hostWidth - $runMinWidth)
  if ($usableWidth -le 0) { return }
  $maxDescWidth = [System.Math]::Max($baseMaxDescWidth,$usableWidth - ($minStepWidth + $minStatusWidth))

  $stepDesired = [int]($maxStep + 18)
  $stepWidth = [System.Math]::Max($minStepWidth,[System.Math]::Min($stepDesired,$maxStepWidth))
  $stepWidth = [System.Math]::Min($stepWidth,$usableWidth - ($minDescWidth + $minStatusWidth))

  $descDesired = [int]($maxDesc + 24)
  $descriptionWidth = [System.Math]::Max($minDescWidth,[System.Math]::Min($descDesired,$maxDescWidth))
  $descriptionWidth = [System.Math]::Min($descriptionWidth,$usableWidth - ($stepWidth + $minStatusWidth))

  $statusDesired = [int]($maxStatusWord + 6)
  $statusWidth = [System.Math]::Max($minStatusWidth,[System.Math]::Min($statusDesired,$maxStatusWidth))
  $availableForStatus = $usableWidth - $stepWidth - $descriptionWidth
  if ($availableForStatus -lt $minStatusWidth) {
    $deficit = $minStatusWidth - $availableForStatus
    if ($descriptionWidth - $minDescWidth -gt 0) {
      $reduceDesc = [System.Math]::Min($descriptionWidth - $minDescWidth,$deficit)
      $descriptionWidth -= $reduceDesc
      $availableForStatus += $reduceDesc
    }
    if ($availableForStatus -lt $minStatusWidth -and $stepWidth -gt $minStepWidth) {
      $reduceStep = [System.Math]::Min($stepWidth - $minStepWidth,$minStatusWidth - $availableForStatus)
      $stepWidth -= $reduceStep
      $availableForStatus += $reduceStep
    }
  }
  $statusWidth = [System.Math]::Max($minStatusWidth,[System.Math]::Min($statusWidth,$usableWidth - $stepWidth - $descriptionWidth))

  $total = $stepWidth + $descriptionWidth + $statusWidth
  if ($total -lt $usableWidth) {
    $descriptionWidth += ($usableWidth - $total)
    $total = $stepWidth + $descriptionWidth + $statusWidth
  }

  $remaining = $hostWidth - $total
  if ($remaining -ge $runMinWidth) {
    $runWidth = $remaining
  } else {
    $runWidth = $runMinWidth
    $overflow = $runWidth - $remaining
    if ($overflow -gt 0 -and $descriptionWidth -gt $minDescWidth) {
      $reduceDesc = [System.Math]::Min($descriptionWidth - $minDescWidth,$overflow)
      $descriptionWidth -= $reduceDesc
      $overflow -= $reduceDesc
    }
    if ($overflow -gt 0 -and $stepWidth -gt $minStepWidth) {
      $reduceStep = [System.Math]::Min($stepWidth - $minStepWidth,$overflow)
      $stepWidth -= $reduceStep
      $overflow -= $reduceStep
    }
    if ($overflow -gt 0 -and $statusWidth -gt $minStatusWidth) {
      $reduceStatus = [System.Math]::Min($statusWidth - $minStatusWidth,$overflow)
      $statusWidth -= $reduceStatus
      $overflow -= $reduceStatus
    }
    if ($overflow -gt 0) {
      $runWidth = [System.Math]::Max($runMinWidth,$runWidth - $overflow)
    }
  }

  $StepsList.Columns[0].Width = $stepWidth
  $StepsList.Columns[1].Width = $descriptionWidth
  $StepsList.Columns[2].Width = $statusWidth
  $StepsList.Columns[3].Width = $runWidth

  $columnSum = 0
  foreach ($col in $StepsList.Columns) { $columnSum += $col.Width }
  $diff = $hostWidth - $columnSum
  if ($diff -ne 0) {
    if ($diff -gt 0) {
      $StepsList.Columns[3].Width += $diff
    } else {
      $reduce = [System.Math]::Min([System.Math]::Max(0,$StepsList.Columns[3].Width - $runMinWidth),-[int]$diff)
      $StepsList.Columns[3].Width -= $reduce
      $diff += $reduce
      if ($diff -lt 0 -and $StepsList.Columns[1].Width -gt $minDescWidth) {
        $reduceDesc = [System.Math]::Min($StepsList.Columns[1].Width - $minDescWidth,-$diff)
        $StepsList.Columns[1].Width -= $reduceDesc
        $diff += $reduceDesc
      }
      if ($diff -lt 0 -and $StepsList.Columns[0].Width -gt $minStepWidth) {
        $reduceStep = [System.Math]::Min($StepsList.Columns[0].Width - $minStepWidth,-$diff)
        $StepsList.Columns[0].Width -= $reduceStep
        $diff += $reduceStep
      }
      if ($diff -lt 0 -and $StepsList.Columns[2].Width -gt $minStatusWidth) {
        $reduceStatus = [System.Math]::Min($StepsList.Columns[2].Width - $minStatusWidth,-$diff)
        $StepsList.Columns[2].Width -= $reduceStatus
        $diff += $reduceStatus
      }
    }
  }
}

$toolboxPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$toolboxPanel.Dock = 'Fill'
$toolboxPanel.WrapContents = $true
$toolboxPanel.AutoScroll = $true
$toolboxPanel.BackColor = $Theme.PanelBack
$toolboxPanel.Padding = New-Object System.Windows.Forms.Padding 8
$toolboxTab.Controls.Add($toolboxPanel)

$logLayout = New-Object System.Windows.Forms.TableLayoutPanel
$logLayout.Dock = 'Fill'
$logLayout.ColumnCount = 1
$logLayout.RowCount = 3
$logLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent,100)))
$logLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent,30)))
$logLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute,2)))
$logLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent,70)))
$logPanel.Controls.Add($logLayout)

$logHeader = New-Object System.Windows.Forms.Panel
$logHeader.Dock = 'Fill'
$logHeader.AutoSize = $false
$logHeader.MinimumSize = New-Object System.Drawing.Size(0,0)
$logHeader.Padding = New-Object System.Windows.Forms.Padding(12,0,12,0)
$logHeader.BackColor = [System.Drawing.Color]::FromArgb(18,32,52)
$logLayout.Controls.Add($logHeader,0,0)

$logHeaderLayout = New-Object System.Windows.Forms.TableLayoutPanel
$logHeaderLayout.Dock = 'Fill'
$logHeaderLayout.ColumnCount = 2
$logHeaderLayout.RowCount = 3
$logHeaderLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent,50)))
$logHeaderLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent,50)))
$logHeaderLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
$logHeaderLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
$logHeaderLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
$logHeader.Controls.Add($logHeaderLayout)

$logTitleRow = New-Object System.Windows.Forms.FlowLayoutPanel
$logTitleRow.Dock = 'Fill'
$logTitleRow.AutoSize = $true
$logTitleRow.AutoSizeMode = 'GrowAndShrink'
$logTitleRow.WrapContents = $false
$logTitleRow.FlowDirection = 'LeftToRight'
$logTitleRow.Margin = New-Object System.Windows.Forms.Padding(0)
$logTitleRow.Padding = New-Object System.Windows.Forms.Padding(0)
$logHeaderLayout.Controls.Add($logTitleRow,0,0)
$logHeaderLayout.SetColumnSpan($logTitleRow,2)

$logLabel = New-Object System.Windows.Forms.Label
$logLabel.Text = 'Live log'
$logLabel.AutoSize = $true
$logLabel.ForeColor = [System.Drawing.Color]::White
$logLabel.Font = New-Object System.Drawing.Font($form.Font.FontFamily, 12,[System.Drawing.FontStyle]::Bold)
$logLabel.Margin = New-Object System.Windows.Forms.Padding(0,0,8,0)
$logLabel.TextAlign = 'MiddleLeft'
$logTitleRow.Controls.Add($logLabel)

$script:LogCountLabel = New-Object System.Windows.Forms.Label
$script:LogCountLabel.Text = 'Entries: 0'
$script:LogCountLabel.AutoSize = $true
$script:LogCountLabel.ForeColor = [System.Drawing.Color]::Gainsboro
$script:LogCountLabel.Margin = New-Object System.Windows.Forms.Padding(0,4,0,0)
$script:LogCountLabel.TextAlign = 'MiddleLeft'
$logTitleRow.Controls.Add($script:LogCountLabel)

$logSubtitle = New-Object System.Windows.Forms.Label
$logSubtitle.Text = ("Diagnostics auto-save into {0}.`nIf the log screams, believe it." -f $DevLogDir)
$logSubtitle.AutoSize = $true
$logSubtitle.ForeColor = [System.Drawing.Color]::LightGray
$logSubtitle.Margin = New-Object System.Windows.Forms.Padding(0,3,0,3)
$logSubtitle.Dock = 'Fill'
$logSubtitle.TextAlign = 'MiddleLeft'
$logSubtitle.Font = New-Object System.Drawing.Font($logSubtitle.Font, [System.Drawing.FontStyle]::Bold)
$logHeaderLayout.Controls.Add($logSubtitle,0,1)
$logHeaderLayout.SetColumnSpan($logSubtitle,2)

$logControlsStrip = New-Object System.Windows.Forms.FlowLayoutPanel
$logControlsStrip.AutoSize = $true
$logControlsStrip.AutoSizeMode = 'GrowAndShrink'
$logControlsStrip.WrapContents = $true
$logControlsStrip.FlowDirection = 'LeftToRight'
$logControlsStrip.Margin = New-Object System.Windows.Forms.Padding(0,0,0,0)
$logControlsStrip.Padding = New-Object System.Windows.Forms.Padding(0,0,0,0)
$logControlsStrip.Dock = 'Fill'
$logHeaderLayout.Controls.Add($logControlsStrip,0,2)
$logHeaderLayout.SetColumnSpan($logControlsStrip,2)

$clearLogBtn = New-LogToolbarButton -Text 'Clear' -OnClick { Clear-LogOutput }
$logControlsStrip.Controls.Add($clearLogBtn)

$copyLogBtn = New-LogToolbarButton -Text 'Copy' -OnClick { Copy-LogOutput }
$logControlsStrip.Controls.Add($copyLogBtn)

$saveLogBtn = New-LogToolbarButton -Text 'Save' -OnClick { Save-LogOutput }
$logControlsStrip.Controls.Add($saveLogBtn)
$logControlsStrip.SetFlowBreak($saveLogBtn,$true)

$openLogDirBtn = New-LogToolbarButton -Text 'Open folder' -OnClick {
  if (Test-Path -LiteralPath $DevLogDir) {
    Start-Process $DevLogDir
  } else {
    Add-Warning("Cannot locate log folder: $DevLogDir")
  }
}
$logControlsStrip.Controls.Add($openLogDirBtn)

$pauseLogToggle = New-LogToggleButton -Text 'Pause scroll' -InitialValue:$script:LogPauseScrolling -OnToggle {
  param($state)
  $script:LogPauseScrolling = $state
  if (-not $state -and $script:LogBox -and -not $script:LogBox.IsDisposed) {
    $script:LogBox.SelectionStart = $script:LogBox.TextLength
    $script:LogBox.ScrollToCaret()
  }
}
$logControlsStrip.Controls.Add($pauseLogToggle)

$highlightLogToggle = New-LogToggleButton -Text 'Highlight alerts' -InitialValue:$script:LogHighlightAlerts -OnToggle {
  param($state)
  $script:LogHighlightAlerts = $state
}
$logControlsStrip.Controls.Add($highlightLogToggle)

$layoutDiagHandler = ({
  if ($script:LayoutDiagnosticsLogged) { return }
  if (-not ($logHeader -and $logControlsStrip -and $logSubtitle)) { return }
  $script:LayoutDiagnosticsLogged = $true
  Write-LayoutDiagnostics -Name 'LogHeader' -Header $logHeader -Subtitle $logSubtitle -Toolbar $logControlsStrip -MarkerRoot $logPanel
}).GetNewClosure()
$logPanel.Add_Layout($layoutDiagHandler)
$logHeader.Add_Layout($layoutDiagHandler)

$logDivider = New-Object System.Windows.Forms.Panel
$logDivider.Dock = 'Fill'
$logDivider.Height = 2
$logDivider.BackColor = [System.Drawing.Color]::FromArgb(26,42,66)
$logLayout.Controls.Add($logDivider,0,1)

$logBodyContainer = New-Object System.Windows.Forms.Panel
$logBodyContainer.Dock = 'Fill'
$logBodyContainer.Padding = New-Object System.Windows.Forms.Padding(0)
$logBodyContainer.BackColor = [System.Drawing.Color]::FromArgb(10,16,24)
$logBodyContainer.BorderStyle = 'None'
$logLayout.Controls.Add($logBodyContainer,0,2)

$script:LogBox = New-Object System.Windows.Forms.RichTextBox
$script:LogBox.Multiline = $true
$script:LogBox.ScrollBars = 'Vertical'
$script:LogBox.ReadOnly = $true
$script:LogBox.BackColor = [System.Drawing.Color]::FromArgb(12,16,28)
$script:LogBox.ForeColor = [System.Drawing.Color]::WhiteSmoke
$script:LogBox.Font = New-Object System.Drawing.Font('Consolas',9)
$script:LogBox.BorderStyle = 'None'
$script:LogBox.Dock = 'Fill'
$script:LogBox.DetectUrls = $false
$script:LogBox.HideSelection = $false
$logBodyContainer.Controls.Add($script:LogBox)

$logContext = New-Object System.Windows.Forms.ContextMenuStrip
$copyItem = $logContext.Items.Add('Copy all')
$copyItem.Add_Click({ Copy-LogOutput })
$saveItem = $logContext.Items.Add('Save to file...')
$saveItem.Add_Click({ Save-LogOutput })
$clearItem = $logContext.Items.Add('Clear')
$clearItem.Add_Click({ Clear-LogOutput })
$script:LogBox.ContextMenuStrip = $logContext

foreach ($entry in $script:PendingLog) {
  $script:LogBox.AppendText($entry + [Environment]::NewLine)
}
$script:PendingLog.Clear()


$recommendLabel = New-Object System.Windows.Forms.Label
$recommendLabel.Text = 'Detecting local changes...'
$recommendLabel.Dock = 'Fill'
$recommendLabel.ForeColor = $Theme.Text
$recommendLabel.AutoSize = $true
$recommendLabel.MaximumSize = New-Object System.Drawing.Size(900,0)
$recommendLabel.Padding = New-Object System.Windows.Forms.Padding 4
$recommendLabel.TextAlign = 'TopLeft'
$workflowInsightsLayout.Controls.Add($recommendLabel,0,0)

$insightsButtonPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$insightsButtonPanel.FlowDirection = 'LeftToRight'
$insightsButtonPanel.AutoSize = $true
$insightsButtonPanel.WrapContents = $false
$insightsButtonPanel.Dock = 'Right'
$insightsButtonPanel.Padding = New-Object System.Windows.Forms.Padding(0)
$workflowInsightsLayout.Controls.Add($insightsButtonPanel,1,0)

$applyRecommendationBtn = New-Object System.Windows.Forms.Button
$applyRecommendationBtn.Text = 'Apply recommended flow'
$applyRecommendationBtn.Tag = [pscustomobject]@{ Style='applyRecommendationButton'; Label='Apply recommended flow' }
$applyRecommendationBtn.AutoSize = $false
$applyRecommendationBtn.Width = 190
$applyRecommendationBtn.Margin = New-Object System.Windows.Forms.Padding(12,0,0,0)
$applyRecommendationBtn.Enabled = $false
Set-ButtonStyle $applyRecommendationBtn
$applyRecommendationBtn.Add_Paint({
  param($paintSender,$paintArgs)
  if (-not $paintSender.Enabled -and $paintSender.Tag -and $paintSender.Tag.Style -eq 'applyRecommendationButton') {
    $label = $paintSender.Tag.Label
    if (-not $label) { $label = 'Apply recommended flow' }
    $rect = $paintSender.ClientRectangle
    $rect.Inflate(-6,-4)
    $flags = [System.Windows.Forms.TextFormatFlags]::HorizontalCenter -bor [System.Windows.Forms.TextFormatFlags]::VerticalCenter -bor [System.Windows.Forms.TextFormatFlags]::WordBreak
    [System.Windows.Forms.TextRenderer]::DrawText($paintArgs.Graphics,$label,$paintSender.Font,$rect,[System.Drawing.SystemColors]::GrayText,$flags)
  }
})
$insightsButtonPanel.Controls.Add($applyRecommendationBtn)
$applySuggestionMenuItem.Enabled = $true
$applySuggestionMenuItem.Add_Click({
  if (-not $applyRecommendationBtn.Enabled) {
    [System.Windows.Forms.MessageBox]::Show(
      'No alternative recommendation is available yet.',
      'Workflow insights',
      [System.Windows.Forms.MessageBoxButtons]::OK,
      [System.Windows.Forms.MessageBoxIcon]::Information
    ) | Out-Null
    return
  }
  $applyRecommendationBtn.PerformClick()
})

$stepsToggleBtn = New-Object System.Windows.Forms.Button
$stepsToggleBtn.Text = 'Show workflow'
$stepsToggleBtn.Width = 120
$stepsToggleBtn.Margin = New-Object System.Windows.Forms.Padding(0,5,10,5)
Set-ButtonStyle $stepsToggleBtn
$stepsControlsPanel.Controls.Add($stepsToggleBtn)

$workflowToggleSection = $workflowRegionPanel
$workflowToggleHandler = {
  param(
    [bool]$Visible
  )
  if ($null -eq $workflowToggleSection) { return }
  if ($Visible) {
    if ($script:WorkflowPanelBaseColor) {
      $workflowToggleSection.BackColor = $script:WorkflowPanelBaseColor
    }
    if ($stepsOverlay) {
      if ($script:WorkflowOverlayBaseColor) {
        $stepsOverlay.BackColor = $script:WorkflowOverlayBaseColor
      }
      $stepsOverlay.Visible = $true
    }
  } else {
    $workflowToggleSection.BackColor = [System.Drawing.Color]::Transparent
    if ($stepsOverlay) {
      $stepsOverlay.BackColor = [System.Drawing.Color]::Transparent
      $stepsOverlay.Visible = $false
    }
  }
  $workflowToggleSection.Visible = $Visible
  if ($workflowToggleSection.Visible) {
    if ($stepsToggleBtn) { $stepsToggleBtn.Text = 'Hide workflow' }
  } else {
    if ($stepsToggleBtn) { $stepsToggleBtn.Text = 'Show workflow' }
  }
}

$stepsToggleBtn.Add_Click({
  if ($workflowToggleSection) {
    & $workflowToggleHandler (-not $workflowToggleSection.Visible)
  }
})
$toggleWorkflowMenuItem.Enabled = $true
$toggleWorkflowMenuItem.Add_Click({
  if ($workflowToggleSection -and $workflowToggleHandler) {
    $visible = -not $workflowToggleSection.Visible
    & $workflowToggleHandler $visible
  }
})

if ($script:LeftLaunchButton) {
  $script:LeftLaunchButton.Add_Click({
    if ($workflowToggleSection -and $workflowToggleHandler) {
      & $workflowToggleHandler (-not $workflowToggleSection.Visible)
    }
  })
}

& $workflowToggleHandler $false

$modeRoleGroup = New-Object System.Windows.Forms.GroupBox
$modeRoleGroup.Text = 'Execution Profile'
$modeRoleGroup.ForeColor = $form.ForeColor
$modeRoleGroup.Padding = New-Object System.Windows.Forms.Padding 10
$modeRoleGroup.AutoSize = $true
$modeRoleGroup.AutoSizeMode = 'GrowAndShrink'
$modeRoleGroup.Margin = New-Object System.Windows.Forms.Padding(0,0,0,12)
Set-CardTheme $modeRoleGroup
$settingsLayout.Controls.Add($modeRoleGroup)

$modeRoleLayout = New-Object System.Windows.Forms.TableLayoutPanel
$modeRoleLayout.Dock = 'Fill'
$modeRoleLayout.ColumnCount = 2
$modeRoleLayout.RowCount = 1
$modeRoleLayout.AutoSize = $true
$modeRoleLayout.AutoSizeMode = 'GrowAndShrink'
$modeRoleLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent,50)))
$modeRoleLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent,50)))
$modeRoleLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
$modeRoleLayout.Padding = New-Object System.Windows.Forms.Padding 4
$modeRoleGroup.Controls.Add($modeRoleLayout)

$modeSection = New-Object System.Windows.Forms.FlowLayoutPanel
$modeSection.FlowDirection = 'TopDown'
$modeSection.WrapContents = $false
$modeSection.AutoSize = $true
$modeSection.AutoSizeMode = 'GrowAndShrink'
$modeSection.Dock = 'Fill'
$modeSection.Margin = New-Object System.Windows.Forms.Padding 4
$modeSection.Padding = New-Object System.Windows.Forms.Padding 2
$modeRoleLayout.Controls.Add($modeSection,0,0)

$modeLabel = New-Object System.Windows.Forms.Label
$modeLabel.Text = 'Mode'
$modeLabel.AutoSize = $true
$modeLabel.Margin = New-Object System.Windows.Forms.Padding(4,2,4,2)
$modeLabel.ForeColor = $Theme.Text
$modeSection.Controls.Add($modeLabel)

$modeOptions = New-Object System.Windows.Forms.FlowLayoutPanel
$modeOptions.FlowDirection = 'LeftToRight'
$modeOptions.WrapContents = $true
$modeOptions.AutoSize = $true
$modeOptions.AutoSizeMode = 'GrowAndShrink'
$modeOptions.Margin = New-Object System.Windows.Forms.Padding 0
$modeOptions.Padding = New-Object System.Windows.Forms.Padding 0
$modeSection.Controls.Add($modeOptions)

$radioAuto = New-Object System.Windows.Forms.RadioButton
$radioAuto.Text = 'Automatic'
$radioAuto.Checked = $true
$radioAuto.AutoSize = $true
$radioAuto.Margin = New-Object System.Windows.Forms.Padding(4,4,12,4)
$modeOptions.Controls.Add($radioAuto)

$radioSemi = New-Object System.Windows.Forms.RadioButton
$radioSemi.Text = 'Semi-auto'
$radioSemi.AutoSize = $true
$radioSemi.Margin = New-Object System.Windows.Forms.Padding(4,4,12,4)
$modeOptions.Controls.Add($radioSemi)

$radioManual = New-Object System.Windows.Forms.RadioButton
$radioManual.Text = 'Manual'
$radioManual.AutoSize = $true
$radioManual.Margin = New-Object System.Windows.Forms.Padding(4,4,4,4)
$modeOptions.Controls.Add($radioManual)

$githubDraftNote = New-Object System.Windows.Forms.Label
$githubDraftNote.Text = 'GitHub commit drafts save automatically to dev/assets/settings.'
$githubDraftNote.AutoSize = $true
$githubDraftNote.Margin = New-Object System.Windows.Forms.Padding(4,0,4,8)
$githubDraftNote.ForeColor = [System.Drawing.Color]::Gainsboro
$githubLayout.Controls.Add($githubDraftNote)

$packagesDraftGroup = New-Object System.Windows.Forms.GroupBox
$packagesDraftGroup.Text = 'Packages repository draft'
$packagesDraftGroup.ForeColor = $form.ForeColor
$packagesDraftGroup.AutoSize = $true
$packagesDraftGroup.AutoSizeMode = 'GrowAndShrink'
$packagesDraftGroup.Margin = New-Object System.Windows.Forms.Padding(0,0,0,12)
$packagesDraftGroup.Padding = New-Object System.Windows.Forms.Padding 10
Set-CardTheme $packagesDraftGroup
$githubLayout.Controls.Add($packagesDraftGroup)

$packagesDraftLayout = New-Object System.Windows.Forms.TableLayoutPanel
$packagesDraftLayout.Dock = 'Fill'
$packagesDraftLayout.AutoSize = $true
$packagesDraftLayout.AutoSizeMode = 'GrowAndShrink'
$packagesDraftLayout.ColumnCount = 1
$packagesDraftLayout.RowCount = 5
$packagesDraftLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent,100)))
$packagesDraftLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
$packagesDraftLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
$packagesDraftLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
$packagesDraftLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute,110)))
$packagesDraftLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
$packagesDraftGroup.Controls.Add($packagesDraftLayout)

$packagesSummaryLabel = New-Object System.Windows.Forms.Label
$packagesSummaryLabel.Text = 'Summary (single line)'
$packagesSummaryLabel.AutoSize = $true
$packagesSummaryLabel.Margin = New-Object System.Windows.Forms.Padding(4,0,4,2)
$packagesSummaryLabel.ForeColor = $Theme.Text
$packagesDraftLayout.Controls.Add($packagesSummaryLabel,0,0)

$packagesTitleBox = New-Object System.Windows.Forms.TextBox
Set-TextBoxStyle $packagesTitleBox
$packagesTitleBox.Dock = 'Top'
$packagesTitleBox.Margin = New-Object System.Windows.Forms.Padding(4,0,4,6)
$packagesTitleBox.Width = 300
$packagesDraftLayout.Controls.Add($packagesTitleBox,0,1)

$packagesBodyLabel = New-Object System.Windows.Forms.Label
$packagesBodyLabel.Text = 'Details (~5 lines)'
$packagesBodyLabel.AutoSize = $true
$packagesBodyLabel.Margin = New-Object System.Windows.Forms.Padding(4,0,4,2)
$packagesBodyLabel.ForeColor = $Theme.Text
$packagesDraftLayout.Controls.Add($packagesBodyLabel,0,2)

$packagesBodyBox = New-Object System.Windows.Forms.TextBox
Set-TextBoxStyle $packagesBodyBox
$packagesBodyBox.Multiline = $true
$packagesBodyBox.AcceptsReturn = $true
$packagesBodyBox.ScrollBars = 'Vertical'
$packagesBodyBox.Height = 110
$packagesBodyBox.MinimumSize = New-Object System.Drawing.Size(200,110)
$packagesBodyBox.Dock = 'Top'
$packagesBodyBox.Margin = New-Object System.Windows.Forms.Padding(4,0,4,6)
$packagesDraftLayout.Controls.Add($packagesBodyBox,0,3)

$packagesHintLabel = New-Object System.Windows.Forms.Label
$packagesHintLabel.Text = 'Tip: describe module-level impacts or schema deltas.'
$packagesHintLabel.AutoSize = $true
$packagesHintLabel.Margin = New-Object System.Windows.Forms.Padding(4,0,4,0)
$packagesHintLabel.ForeColor = [System.Drawing.Color]::LightGray
$packagesDraftLayout.Controls.Add($packagesHintLabel,0,4)

$umbrellaDraftGroup = New-Object System.Windows.Forms.GroupBox
$umbrellaDraftGroup.Text = 'Umbrella repository draft'
$umbrellaDraftGroup.ForeColor = $form.ForeColor
$umbrellaDraftGroup.AutoSize = $true
$umbrellaDraftGroup.AutoSizeMode = 'GrowAndShrink'
$umbrellaDraftGroup.Margin = New-Object System.Windows.Forms.Padding(0,0,0,12)
$umbrellaDraftGroup.Padding = New-Object System.Windows.Forms.Padding 10
Set-CardTheme $umbrellaDraftGroup
$githubLayout.Controls.Add($umbrellaDraftGroup)

$umbrellaDraftLayout = New-Object System.Windows.Forms.TableLayoutPanel
$umbrellaDraftLayout.Dock = 'Fill'
$umbrellaDraftLayout.AutoSize = $true
$umbrellaDraftLayout.AutoSizeMode = 'GrowAndShrink'
$umbrellaDraftLayout.ColumnCount = 1
$umbrellaDraftLayout.RowCount = 5
$umbrellaDraftLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent,100)))
$umbrellaDraftLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
$umbrellaDraftLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
$umbrellaDraftLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
$umbrellaDraftLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute,110)))
$umbrellaDraftLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
$umbrellaDraftGroup.Controls.Add($umbrellaDraftLayout)

$umbrellaSummaryLabel = New-Object System.Windows.Forms.Label
$umbrellaSummaryLabel.Text = 'Summary (single line)'
$umbrellaSummaryLabel.AutoSize = $true
$umbrellaSummaryLabel.Margin = New-Object System.Windows.Forms.Padding(4,0,4,2)
$umbrellaSummaryLabel.ForeColor = $Theme.Text
$umbrellaDraftLayout.Controls.Add($umbrellaSummaryLabel,0,0)

$umbrellaTitleBox = New-Object System.Windows.Forms.TextBox
Set-TextBoxStyle $umbrellaTitleBox
$umbrellaTitleBox.Dock = 'Top'
$umbrellaTitleBox.Margin = New-Object System.Windows.Forms.Padding(4,0,4,6)
$umbrellaTitleBox.Width = 300
$umbrellaDraftLayout.Controls.Add($umbrellaTitleBox,0,1)

$umbrellaBodyLabel = New-Object System.Windows.Forms.Label
$umbrellaBodyLabel.Text = 'Details (~5 lines)'
$umbrellaBodyLabel.AutoSize = $true
$umbrellaBodyLabel.Margin = New-Object System.Windows.Forms.Padding(4,0,4,2)
$umbrellaBodyLabel.ForeColor = $Theme.Text
$umbrellaDraftLayout.Controls.Add($umbrellaBodyLabel,0,2)

$umbrellaBodyBox = New-Object System.Windows.Forms.TextBox
Set-TextBoxStyle $umbrellaBodyBox
$umbrellaBodyBox.Multiline = $true
$umbrellaBodyBox.AcceptsReturn = $true
$umbrellaBodyBox.ScrollBars = 'Vertical'
$umbrellaBodyBox.Height = 110
$umbrellaBodyBox.MinimumSize = New-Object System.Drawing.Size(200,110)
$umbrellaBodyBox.Dock = 'Top'
$umbrellaBodyBox.Margin = New-Object System.Windows.Forms.Padding(4,0,4,6)
$umbrellaDraftLayout.Controls.Add($umbrellaBodyBox,0,3)

$umbrellaHintLabel = New-Object System.Windows.Forms.Label
$umbrellaHintLabel.Text = 'Tip: highlight platform-wide behavior changes.'
$umbrellaHintLabel.AutoSize = $true
$umbrellaHintLabel.Margin = New-Object System.Windows.Forms.Padding(4,0,4,0)
$umbrellaHintLabel.ForeColor = [System.Drawing.Color]::LightGray
$umbrellaDraftLayout.Controls.Add($umbrellaHintLabel,0,4)

$script:PackagesTitleBox = $packagesTitleBox
$script:PackagesBodyBox = $packagesBodyBox
$script:UmbrellaTitleBox = $umbrellaTitleBox
$script:UmbrellaBodyBox = $umbrellaBodyBox

$script:PackagesTitleBox.Text = $script:GitHubSettings.PackagesTitle
$script:PackagesBodyBox.Text = $script:GitHubSettings.PackagesBody
$script:UmbrellaTitleBox.Text = $script:GitHubSettings.UmbrellaTitle
$script:UmbrellaBodyBox.Text = $script:GitHubSettings.UmbrellaBody

$githubSaveHandler = {
  Save-GitHubCommitSettings
}
$script:PackagesTitleBox.Add_TextChanged($githubSaveHandler)
$script:PackagesBodyBox.Add_TextChanged($githubSaveHandler)
$script:UmbrellaTitleBox.Add_TextChanged($githubSaveHandler)
$script:UmbrellaBodyBox.Add_TextChanged($githubSaveHandler)

$roleSection = New-Object System.Windows.Forms.FlowLayoutPanel
$roleSection.FlowDirection = 'TopDown'
$roleSection.WrapContents = $false
$roleSection.AutoSize = $true
$roleSection.AutoSizeMode = 'GrowAndShrink'
$roleSection.Dock = 'Fill'
$roleSection.Margin = New-Object System.Windows.Forms.Padding 4
$roleSection.Padding = New-Object System.Windows.Forms.Padding 2
$modeRoleLayout.Controls.Add($roleSection,1,0)

$roleLabel = New-Object System.Windows.Forms.Label
$roleLabel.Text = 'Role'
$roleLabel.AutoSize = $true
$roleLabel.Margin = New-Object System.Windows.Forms.Padding(4,2,4,2)
$roleLabel.ForeColor = $Theme.Text
$roleSection.Controls.Add($roleLabel)

$roleOptions = New-Object System.Windows.Forms.FlowLayoutPanel
$roleOptions.FlowDirection = 'TopDown'
$roleOptions.WrapContents = $false
$roleOptions.AutoSize = $true
$roleOptions.AutoSizeMode = 'GrowAndShrink'
$roleOptions.Margin = New-Object System.Windows.Forms.Padding 0
$roleOptions.Padding = New-Object System.Windows.Forms.Padding 0
$roleSection.Controls.Add($roleOptions)

$radioDev = New-Object System.Windows.Forms.RadioButton
$radioDev.Text = 'Developer (no push)'
$radioDev.Checked = $true
$radioDev.AutoSize = $true
$radioDev.Margin = New-Object System.Windows.Forms.Padding(4,4,4,2)
$roleOptions.Controls.Add($radioDev)

$radioAdmin = New-Object System.Windows.Forms.RadioButton
$radioAdmin.Text = 'Super-admin (push)'
$radioAdmin.AutoSize = $true
$radioAdmin.Margin = New-Object System.Windows.Forms.Padding(4,4,4,2)
$roleOptions.Controls.Add($radioAdmin)

$pushCheck = New-Object System.Windows.Forms.CheckBox
$pushCheck.Text = 'Push after commits'
$pushCheck.Checked = $false
$pushCheck.Enabled = $false
$pushCheck.AutoSize = $true
$pushCheck.ForeColor = $Theme.Text
$pushCheck.Margin = New-Object System.Windows.Forms.Padding(4,6,4,2)
$roleOptions.Controls.Add($pushCheck)

$roleHandler = {
  if ($radioAdmin.Checked) {
    $pushCheck.Enabled = $true
    if (-not $pushCheck.Checked) { $pushCheck.Checked = $true }
  } else {
    $pushCheck.Checked = $false
    $pushCheck.Enabled = $false
  }
}
$radioDev.Add_CheckedChanged($roleHandler)
$radioAdmin.Add_CheckedChanged($roleHandler)

$versionGroup = New-Object System.Windows.Forms.GroupBox
$versionGroup.Text = 'Version bump'
$versionGroup.ForeColor = $form.ForeColor
$versionGroup.Padding = New-Object System.Windows.Forms.Padding 10
$versionGroup.AutoSize = $true
$versionGroup.AutoSizeMode = 'GrowAndShrink'
$versionGroup.Margin = New-Object System.Windows.Forms.Padding(0,0,0,12)
Set-CardTheme $versionGroup
$settingsLayout.Controls.Add($versionGroup)

$versionLayout = New-Object System.Windows.Forms.TableLayoutPanel
$versionLayout.Dock = 'Fill'
$versionLayout.ColumnCount = 2
$versionLayout.RowCount = 4
$versionLayout.AutoSize = $true
$versionLayout.AutoSizeMode = 'GrowAndShrink'
$versionLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute,95)))
$versionLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent,100)))
$versionLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
$versionLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
$versionLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
$versionLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
$versionGroup.Controls.Add($versionLayout)

$versionCheck = New-Object System.Windows.Forms.CheckBox
$versionCheck.Text = 'Run package version bump'
$versionCheck.AutoSize = $true
$versionCheck.Margin = New-Object System.Windows.Forms.Padding(4,4,4,4)
$versionLayout.Controls.Add($versionCheck,0,0)
$versionLayout.SetColumnSpan($versionCheck,2)

$versionLabel = New-Object System.Windows.Forms.Label
$versionLabel.Text = 'Version (use semantic format, e.g., 1.2.3)'
$versionLabel.AutoSize = $true
$versionLabel.Margin = New-Object System.Windows.Forms.Padding(4,6,4,4)
$versionLabel.Anchor = 'Left'
$versionLayout.Controls.Add($versionLabel,0,1)

$versionBox = New-Object System.Windows.Forms.TextBox
$versionBox.Enabled = $false
Set-TextBoxStyle $versionBox
$versionBox.Width = 100
$versionBox.Margin = New-Object System.Windows.Forms.Padding(4,4,4,4)
$versionLayout.Controls.Add($versionBox,1,1)

$versionHint = New-Object System.Windows.Forms.Label
$versionHint.Text = 'Pattern: MAJOR.MINOR.PATCH (no v prefix, always three numbers).'
$versionHint.AutoSize = $true
$versionHint.Margin = New-Object System.Windows.Forms.Padding(4,0,4,4)
$versionHint.ForeColor = [System.Drawing.Color]::LightGray
$versionLayout.Controls.Add($versionHint,0,2)
$versionLayout.SetColumnSpan($versionHint,2)

$versionTablesLabel = New-Object System.Windows.Forms.Label
$versionTablesLabel.Text = 'Tables (comma; blank=all)'
$versionTablesLabel.AutoSize = $true
$versionTablesLabel.Margin = New-Object System.Windows.Forms.Padding(4,6,4,4)
$versionTablesLabel.Anchor = 'Left'
$versionLayout.Controls.Add($versionTablesLabel,0,3)

$versionTablesBox = New-Object System.Windows.Forms.TextBox
$versionTablesBox.Enabled = $false
Set-TextBoxStyle $versionTablesBox
$versionTablesBox.Margin = New-Object System.Windows.Forms.Padding(4,4,4,4)
$versionTablesBox.Dock = 'Fill'
$versionLayout.Controls.Add($versionTablesBox,1,3)

$versionCheck.Add_CheckedChanged({
  $enabled = $versionCheck.Checked
  $versionBox.Enabled = $enabled
  $versionTablesBox.Enabled = $enabled
  $versionLabel.Enabled = $enabled
  $versionTablesLabel.Enabled = $enabled
})

$complianceGroup = New-Object System.Windows.Forms.GroupBox
$complianceGroup.Text = 'Compliance'
$complianceGroup.ForeColor = $form.ForeColor
$complianceGroup.Padding = New-Object System.Windows.Forms.Padding 10
$complianceGroup.AutoSize = $true
$complianceGroup.AutoSizeMode = 'GrowAndShrink'
$complianceGroup.Margin = New-Object System.Windows.Forms.Padding(0,0,0,12)
Set-CardTheme $complianceGroup
$settingsLayout.Controls.Add($complianceGroup)

$complianceLayout = New-Object System.Windows.Forms.FlowLayoutPanel
$complianceLayout.Dock = 'Fill'
$complianceLayout.FlowDirection = 'TopDown'
$complianceLayout.WrapContents = $false
$complianceLayout.AutoSize = $true
$complianceLayout.AutoSizeMode = 'GrowAndShrink'
$complianceLayout.Margin = New-Object System.Windows.Forms.Padding 0
$complianceLayout.Padding = New-Object System.Windows.Forms.Padding 4
$complianceGroup.Controls.Add($complianceLayout)

$licenseCheck = New-Object System.Windows.Forms.CheckBox
$licenseCheck.Text = 'Run LICENSE/NOTICE enforcement'
$licenseCheck.AutoSize = $true
$licenseCheck.ForeColor = $Theme.Text
$licenseCheck.Margin = New-Object System.Windows.Forms.Padding(4,4,4,4)
$complianceLayout.Controls.Add($licenseCheck)

if ($MissingPackageTables.Count -gt 0) {
  $script:ForceLicense = $true
  $licenseCheck.Checked = $true
  $licenseCheck.Enabled = $false
}

$observabilityCheck = New-Object System.Windows.Forms.CheckBox
$observabilityCheck.Text = 'Launch observability stack (Prometheus + Grafana + Loki)'
$observabilityCheck.AutoSize = $true

$grafanaLaunchCheck = New-Object System.Windows.Forms.CheckBox
$grafanaLaunchCheck.Text = 'Open Grafana dashboard after launch'
$grafanaLaunchCheck.AutoSize = $true
$grafanaLaunchCheck.Checked = $true
$grafanaLaunchCheck.Enabled = $false

$phpstanCheck = New-Object System.Windows.Forms.CheckBox
$phpstanCheck.Text = 'Run PHPStan (phpstan.neon)'
$phpstanCheck.AutoSize = $true

$dockerInfraCheck = New-Object System.Windows.Forms.CheckBox
$dockerInfraCheck.Text = 'Ensure docker databases are up (MySQL/Postgres/MariaDB)'
$dockerInfraCheck.AutoSize = $true
$dockerInfraCheck.Checked  = $true

$dockerTestsCheck = New-Object System.Windows.Forms.CheckBox
$dockerTestsCheck.Text = 'Run full test suite via docker compose'
$dockerTestsCheck.AutoSize = $true

$terraformCheck = New-Object System.Windows.Forms.CheckBox
$terraformCheck.Text = 'Terraform (observability stack)'
$terraformCheck.AutoSize = $true

$terraformMode = New-Object System.Windows.Forms.ComboBox
$terraformMode.Items.AddRange(@('Plan','Apply')) | Out-Null
$terraformMode.SelectedIndex = 0
$terraformMode.DropDownStyle = 'DropDownList'
$terraformMode.Enabled = $false
$terraformMode.Width = 110
$terraformMode.BackColor = $Theme.ControlBack
$terraformMode.ForeColor = $Theme.Text

$secretsScanCheck = New-Object System.Windows.Forms.CheckBox
$secretsScanCheck.Text = 'Run secrets scanner before commits'
$secretsScanCheck.AutoSize = $true

$observabilityCheck.Add_CheckedChanged({
  $grafanaLaunchCheck.Enabled = $observabilityCheck.Checked
  if (-not $observabilityCheck.Checked) {
    $grafanaLaunchCheck.Checked = $false
  } elseif (-not $grafanaLaunchCheck.Checked) {
    $grafanaLaunchCheck.Checked = $true
  }
})

$terraformCheck.Add_CheckedChanged({
  $terraformMode.Enabled = $terraformCheck.Checked
})

function New-ToolGroup {
  param([string]$Title)
  $group = New-Object System.Windows.Forms.GroupBox
  $group.Text = $Title
  $group.ForeColor = $Theme.Text
  $group.BackColor = $Theme.CardBack
  $group.Size = New-Object System.Drawing.Size(390,150)
  $group.Margin = New-Object System.Windows.Forms.Padding 10
  $group.Padding = New-Object System.Windows.Forms.Padding 12
  return $group
}

$observabilityGroup = New-ToolGroup 'Observability'
$observabilityCheck.Location = New-Object System.Drawing.Point(15,30)
$observabilityGroup.Controls.Add($observabilityCheck)
$grafanaLaunchCheck.Location = New-Object System.Drawing.Point(35,60)
$observabilityGroup.Controls.Add($grafanaLaunchCheck)
$grafanaLink = New-Object System.Windows.Forms.LinkLabel
$grafanaLink.Text = 'Open Grafana (http://localhost:3000)'
$grafanaLink.Location = New-Object System.Drawing.Point(35,90)
$grafanaLink.LinkColor = [System.Drawing.Color]::DeepSkyBlue
$grafanaLink.ActiveLinkColor = [System.Drawing.Color]::LightSkyBlue
$grafanaLink.AutoSize = $true
$grafanaLink.Add_LinkClicked({ Start-Process 'http://localhost:3000' })
$observabilityGroup.Controls.Add($grafanaLink)

$dockerGroup = New-ToolGroup 'Containers'
$dockerInfraCheck.Location = New-Object System.Drawing.Point(15,30)
$dockerGroup.Controls.Add($dockerInfraCheck)
$dockerTestsCheck.Location = New-Object System.Drawing.Point(15,60)
$dockerGroup.Controls.Add($dockerTestsCheck)
$composeLink = New-Object System.Windows.Forms.LinkLabel
$composeLink.Text = 'View docker-compose.yml'
$composeLink.Location = New-Object System.Drawing.Point(15,90)
$composeLink.LinkColor = [System.Drawing.Color]::DeepSkyBlue
$composeLink.AutoSize = $true
$composeLink.Add_LinkClicked({
  $composePath = Join-Path $RepoRoot 'docker-compose.yml'
  if (Test-Path -LiteralPath $composePath) { Start-Process $composePath }
})
$dockerGroup.Controls.Add($composeLink)

$qualityGroup = New-ToolGroup 'Quality'
$phpstanCheck.Location = New-Object System.Drawing.Point(15,30)
$qualityGroup.Controls.Add($phpstanCheck)
$secretsScanCheck.Location = New-Object System.Drawing.Point(15,60)
$qualityGroup.Controls.Add($secretsScanCheck)
$phpstanLink = New-Object System.Windows.Forms.LinkLabel
$phpstanLink.Text = 'Open phpstan.neon'
$phpstanLink.Location = New-Object System.Drawing.Point(15,90)
$phpstanLink.LinkColor = [System.Drawing.Color]::DeepSkyBlue
$phpstanLink.AutoSize = $true
$phpstanLink.Add_LinkClicked({
  $phpstanPath = Join-Path $RepoRoot 'phpstan.neon'
  if (Test-Path -LiteralPath $phpstanPath) { Start-Process $phpstanPath }
})
$qualityGroup.Controls.Add($phpstanLink)

$infraGroup = New-ToolGroup 'Infra'
$terraformCheck.Location = New-Object System.Drawing.Point(15,30)
$infraGroup.Controls.Add($terraformCheck)
$terraformModeLabel = New-Object System.Windows.Forms.Label
$terraformModeLabel.Text = 'Mode'
$terraformModeLabel.Location = New-Object System.Drawing.Point(35,65)
$terraformModeLabel.Size = New-Object System.Drawing.Size(40,20)
$infraGroup.Controls.Add($terraformModeLabel)
$terraformMode.Location = New-Object System.Drawing.Point(80,62)
$infraGroup.Controls.Add($terraformMode)
$terraformLink = New-Object System.Windows.Forms.LinkLabel
$terraformLink.Text = 'Infra README'
$terraformLink.Location = New-Object System.Drawing.Point(35,95)
$terraformLink.LinkColor = [System.Drawing.Color]::DeepSkyBlue
$terraformLink.AutoSize = $true
$terraformLink.Add_LinkClicked({
  $tfDoc = Join-Path $RepoRoot 'infra/terraform/README.md'
  if (Test-Path -LiteralPath $tfDoc) { Start-Process $tfDoc }
})
$infraGroup.Controls.Add($terraformLink)

$toolboxPanel.Controls.Add($observabilityGroup)
$toolboxPanel.Controls.Add($dockerGroup)
$toolboxPanel.Controls.Add($qualityGroup)
$toolboxPanel.Controls.Add($infraGroup)

$Steps = @(
  (New-Step "Sync Submodules" "git submodule sync && update" {
    $protected = Protect-SubmoduleWorkingTrees -RepoRoot $RepoRoot
    try {
      Invoke-Executable -FilePath 'git' -Arguments @('submodule','sync','--recursive')
      Invoke-Executable -FilePath 'git' -Arguments @('submodule','update','--init','--recursive')
      Restore-SubmoduleWorkingTrees -ProtectedPaths $protected -RepoRoot $RepoRoot -CopyBack
    } catch {
      Restore-SubmoduleWorkingTrees -ProtectedPaths $protected -RepoRoot $RepoRoot
      throw
    }
  }),
  (New-Step "Docker Databases Up" "Ensure docker compose databases are running" {
    Invoke-Executable -FilePath 'docker' -Arguments @('compose','up','-d','mysql','postgres','mariadb')
  } { $dockerInfraCheck.Checked }),
  (New-Step "Ensure Package Repos" "Create missing package repositories/submodules" {
    if ($MissingPackageTables.Count -eq 0) {
      Write-UiLog "No missing packages detected."
      return
    }
    $tableArgs = @()
    foreach ($t in $MissingPackageTables) { $tableArgs += $t }
    $scriptPath = Join-Path $ScriptsRoot 'packages/Sync-PackageRepos.ps1'
    Write-UiLog ("Ensuring packages: " + ($tableArgs -join ', '))
    $pkgArgs = @('-Action','ensure','-CreateRemote')
    if ($tableArgs.Count -gt 0) {
      $tableJson = $tableArgs | ConvertTo-Json -Compress
      $pkgArgs += '-TableJson'
      $pkgArgs += $tableJson
    }
    Invoke-PwshScript -ScriptPath $scriptPath -ScriptArguments $pkgArgs -DisplayName 'Sync-PackageRepos (ensure)'
    $script:NewPackagesCreated = $true
  } { $MissingPackageTables.Count -gt 0 }),
  (New-Step "Composer Install" "Install PHP dependencies" {
    Invoke-Executable -FilePath 'docker' -Arguments @('compose','run','--rm','app','composer','install','--no-interaction')
  }),
  (New-Step "Cleanup Schema Folders" "Remove stale generated schema folders" {
    $cleanupScript = Join-Path $SchemaTools 'Cleanup-SchemaFolders.ps1'
    foreach ($target in @('schema','src')) {
      Write-UiLog ("Cleanup target: {0}" -f $target)
      $cleanupArgs = @(
        '-PackagesDir', $PackagesDir,
        '-Targets', $target,
        '-AutoConfirm',
        '-Confirm:$false'
      )
      Invoke-PwshScript -ScriptPath $cleanupScript -ScriptArguments $cleanupArgs -DisplayName ("Cleanup-SchemaFolders ({0})" -f $target)
    }
  }),
  (New-Step "Refresh Schema" "Run mk-schema.ps1" {
    $mkSchemaScript = Join-Path $SchemaTools 'mk-schema.ps1'
    $mkArgs = @('-InDir', $SchemaDir, '-SeedInTransaction','-Force')
    Invoke-PwshScript -ScriptPath $mkSchemaScript -ScriptArguments $mkArgs -DisplayName 'mk-schema.ps1'
  }),
  (New-Step "Split Schemas" "Split monolith into packages (Postgres + MySQL)" {
    $splitScript = Join-Path $SchemaTools 'Split-SchemaToPackages.ps1'
    $splitArgs = @(
      '-InDir', $SchemaDir,
      '-PackagesDir', $PackagesDir,
      '-CleanupLegacy',
      '-Force'
    )
    Invoke-PwshScript -ScriptPath $splitScript -ScriptArguments $splitArgs -DisplayName 'Split-SchemaToPackages.ps1'
  }),
  (New-Step "Docs (Postgres)" "Readmes, defs, changelog" {
    $docTasks = @(
      @{
        Path = Join-Path $DocsDir 'New-PackageReadmes.ps1'
        Args = @('-MapPath',$MapPg,'-PackagesDir',$PackagesDir,'-Force')
        Label = 'New-PackageReadmes (pg)'
      },
      @{
        Path = Join-Path $SchemaTools 'Build-Definitions.ps1'
        Args = @('-MapPath',$MapPg,'-DefsPath',$DefsPg,'-PackagesDir',$PackagesDir,'-Force')
        Label = 'Build-Definitions (pg)'
      },
      @{
        Path = Join-Path $DocsDir 'New-PackageChangelogs.ps1'
        Args = @('-MapPath',$MapPg,'-PackagesDir',$PackagesDir,'-Force')
        Label = 'New-PackageChangelogs (pg)'
      }
    )
    foreach ($task in $docTasks) {
      Invoke-PwshScript -ScriptPath $task.Path -ScriptArguments $task.Args -DisplayName $task.Label
    }
  }),
  (New-Step "Update PACKAGES.md" "Regenerate docs index" {
    $scriptPath = Join-Path $DocsDir 'New-DocsIndex.ps1'
    $scriptArgs = @(
      '-MapPath', $MapPg,
      '-PackagesDir', $PackagesDir,
      '-OutPath', (Join-Path $RepoRoot 'PACKAGES.md'),
      '-Force'
    )
    Invoke-PwshScript -ScriptPath $scriptPath -ScriptArguments $scriptArgs -DisplayName 'New-DocsIndex'
  }),
  (New-Step "Package Version Bump" "Run scripts/packages/Set-PackageVersion.ps1" {
    $versionValue = $versionBox.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($versionValue)) {
      throw "Version string required."
    }
    $tablesInput = @($versionTablesBox.Text.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $scriptPath = Join-Path $ScriptsRoot 'packages/Set-PackageVersion.ps1'
    if ($tablesInput.Count -eq 0) {
      & $scriptPath -All -Version $versionValue -MapPath $MapPg -PackagesDir $PackagesDir -Push:$pushCheck.Checked
    } else {
      & $scriptPath -Table $tablesInput -Version $versionValue -MapPath $MapPg -PackagesDir $PackagesDir -Push:$pushCheck.Checked
    }
  } { $versionCheck.Checked }),
  (New-Step "Generate PHP" "Generate PHP scaffolding from schema" {
    $generateScript = Join-Path $SchemaTools 'Generate-PhpFromSchema.ps1'
    $generateArgs = @(
      '-SchemaDir', $SchemaDir,
      '-TemplatesRoot', (Join-Path $ScriptsRoot 'templates/php'),
      '-ModulesRoot', $PackagesDir,
      '-NameResolution', 'detect',
      '-Force'
    )
    Invoke-PwshScript -ScriptPath $generateScript -ScriptArguments $generateArgs -DisplayName 'Generate-PhpFromSchema.ps1'
  }),
  (New-Step "Composer Dump" "Optimize autoloader" {
    Invoke-ComposerCommand -Arguments @('dump-autoload','-o') -DisplayName 'composer dump-autoload -o'
  }),
  (New-Step "Composer Test" "Run tests/ci pipeline" {
    Write-UiLog "Running DB test matrix (mysql, postgres, mariadb)..."
    Invoke-TestMatrix | Out-Null
  }),
  (New-Step "Dockerized Test Suite" "docker compose run --rm app composer test" {
    Write-UiLog "Running DB test matrix (docker compose)..."
    Invoke-TestMatrix | Out-Null
  } { $dockerTestsCheck.Checked }),
  (New-Step "Test Packages Schema" "pwsh scripts/quality/Test-PackagesSchema.ps1" {
    & (Join-Path $QualityDir 'Test-PackagesSchema.ps1') -PackagesDir $PackagesDir
  }),
  (New-Step "Test Schema Output" "pwsh scripts/quality/Test-SchemaOutput.ps1" {
    & (Join-Path $QualityDir 'Test-SchemaOutput.ps1') -MapPath $MapPg -SchemaDir $SchemaOut
  }),
  (New-Step "SQL Lint" "bash scripts/quality/SqlLint-Diff.sh" {
    Invoke-Executable -FilePath 'bash' -Arguments @('./scripts/quality/SqlLint-Diff.sh')
  }),
  (New-Step "PHPStan" "composer exec phpstan analyse -c phpstan.neon" {
    Invoke-ComposerCommand -Arguments @('exec','phpstan','analyse','-c','phpstan.neon') -DisplayName 'composer exec phpstan analyse -c phpstan.neon'
  } { $phpstanCheck.Checked }),
  (New-Step "Secrets Scan" "pwsh scripts/quality/Check-Secrets.ps1" {
    $secretsScript = Join-Path $QualityDir 'Check-Secrets.ps1'
    & pwsh -NoLogo -NoProfile -File $secretsScript -Root $RepoRoot
  } { $secretsScanCheck.Checked }),
  (New-Step "Launch Observability Stack" "pwsh scripts/dev/Dev-Observability.ps1 -Action start" {
    $obsScript = Join-Path $ScriptsRoot 'dev/Dev-Observability.ps1'
    & pwsh -NoLogo -NoProfile -File $obsScript -Action start -NoBrowser:(!$grafanaLaunchCheck.Checked)
  } { $observabilityCheck.Checked }),
  (New-Step "Terraform Observability" "terraform plan/apply inside infra/terraform" {
    $tfDir = Join-Path $RepoRoot 'infra/terraform'
    $mode = if ($terraformMode.SelectedItem) { $terraformMode.SelectedItem.ToString() } else { 'Plan' }
    $tfArgs = if ($mode -eq 'Apply') { @('apply','-auto-approve') } else { @('plan') }
    Invoke-Executable -FilePath 'terraform' -Arguments $tfArgs -WorkingDirectory $tfDir -DisplayName ("terraform {0} (infra/terraform)" -f $mode)
  } { $terraformCheck.Checked }),
  (New-Step "Enforce LICENSE/NOTICE" "Run enforce-license.ps1 across packages" {
    & (Join-Path $QualityDir 'enforce-license.ps1') -Packages (Join-Path $RepoRoot 'packages') -Force -Push:$pushCheck.Checked
  } { $licenseCheck.Checked -or $script:NewPackagesCreated -or $script:ForceLicense })
)

foreach ($step in $Steps) {
  $hasName = -not [string]::IsNullOrWhiteSpace($step.Name)
  $hasDescription = -not [string]::IsNullOrWhiteSpace($step.Description)
  if (-not ($hasName -or $hasDescription)) {
    continue
  }
  $rowName = if ($hasName) { $step.Name } else { '' }
  $item = New-Object System.Windows.Forms.ListViewItem($rowName)
  $descValue = if ($hasDescription) { $step.Description } else { '' }
  $item.SubItems.Add($descValue) | Out-Null
  $item.SubItems.Add('Pending') | Out-Null
  $item.SubItems.Add('RUN') | Out-Null
  $item.UseItemStyleForSubItems = $false
  if ($script:RunGlyphFont) {
    $item.SubItems[3].Font = $script:RunGlyphFont
  }
  $item.Checked = $step.ShouldRun.Invoke()
  $item.Tag = $step
  $step.Item = $item
  $StepsList.Items.Add($item) | Out-Null
}
Update-StepsListHeight

function Update-StepStatus {
  param($Step,$Status)
  $Step.Item.SubItems[2].Text = $Status
  [System.Windows.Forms.Application]::DoEvents()
}

$script:AdHocStepRunning = $false
$script:AdHocActiveStep = $null
function Invoke-AdHocWorkflowStep {
  param($Step)
  if (-not $Step -or -not $Step.Action) { return }
  if ($script:AdHocStepRunning) {
    if ($Step -eq $script:AdHocActiveStep) { return }
    Add-Warning("Another step is currently running. Please wait for it to finish before launching '$($Step.Name)'.")
    return
  }
  $script:AdHocStepRunning = $true
  $script:AdHocActiveStep = $Step
  try {
    Write-UiLog "Ad-hoc: running step '$($Step.Name)'."
    Update-StepStatus $Step 'Running'
    Invoke-Script -ScriptBlock $Step.Action -DisplayName ("Ad-hoc {0}" -f $Step.Name)
    Update-StepStatus $Step 'Done'
    Write-UiLog "Ad-hoc: step '$($Step.Name)' completed."
  } catch {
    Update-StepStatus $Step 'Failed'
    Add-Warning("Ad-hoc step '$($Step.Name)' failed: $($_.Exception.Message)")
  } finally {
    $script:AdHocStepRunning = $false
    $script:AdHocActiveStep = $null
  }
}

function Invoke-ManualActionPrompt {
  param([string]$StepName,[string]$Description)
  $msg = "Manual mode: run '$StepName' (${Description}). Click Yes when done, No to skip, Cancel to abort."
  return [System.Windows.Forms.MessageBox]::Show($msg,'Manual Step','YesNoCancel','Information')
}

function Invoke-FailurePrompt {
  param([string]$stepName,[string]$errorText)
  $msg = "Step '$stepName' failed:`n$errorText`nRetry? (Yes=Retry, No=Skip, Cancel=Abort)"
  return [System.Windows.Forms.MessageBox]::Show($msg,'Step Failed','YesNoCancel','Warning')
}

function New-CommitDraftMessage {
  param(
    [string]$Title,
    [string]$Body
  )
  $trimmedTitle = if ($null -ne $Title) { $Title.Trim() } else { '' }
  $trimmedBody = if ($null -ne $Body) { $Body.Trim() } else { '' }
  if (-not $trimmedTitle) { return '' }
  if ($trimmedBody) {
    return ("{0}`n`n{1}" -f $trimmedTitle, $trimmedBody)
  }
  return $trimmedTitle
}

function Invoke-PackageCommit {
  param([string]$Message,[bool]$Push)
  if ([string]::IsNullOrWhiteSpace($Message)) { return }
  $warningsText = if ($Warnings.Count) { "`n`nWarnings:`n - " + ($Warnings -join "`n - ") } else { '' }
  $finalMessage = $Message + $warningsText
  $committed = 0
  $branchStamp = Get-Date -Format 'yyyyMMdd-HHmmss'
  $targetBranch = if ($env:BC_WORKFLOW_BRANCH -and -not [string]::IsNullOrWhiteSpace($env:BC_WORKFLOW_BRANCH)) { $env:BC_WORKFLOW_BRANCH } else { "regen-$branchStamp" }
  $prMergeMode = if ($env:BC_PR_MERGE_MODE -and $env:BC_PR_MERGE_MODE.Trim()) { $env:BC_PR_MERGE_MODE.Trim().ToLower() } else { 'squash' }
  $prReviewers = @()
  if ($env:BC_PR_REVIEWERS) {
    $prReviewers = @($env:BC_PR_REVIEWERS.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
  }
  foreach ($pkg in Get-ChildItem -LiteralPath $PackagesDir -Directory) {
    $schemaDir = Join-Path $pkg.FullName 'schema'
    if (-not (Test-Path -LiteralPath $schemaDir)) { continue }
    try {
      Invoke-Executable -FilePath 'git' -Arguments @('add','schema') -WorkingDirectory $pkg.FullName -DisplayName "git add schema ($($pkg.Name))"
    } catch {
      Add-Warning("Failed to stage schema for package '$($pkg.Name)': $($_.Exception.Message)")
      continue
    }
    $pending = (& git -C $pkg.FullName status --porcelain)
    if (-not $pending) { continue }
    try {
      $currentBranch = (& git -C $pkg.FullName rev-parse --abbrev-ref HEAD).Trim()
      Invoke-Executable -FilePath 'git' -Arguments @('commit','-m',$finalMessage) -WorkingDirectory $pkg.FullName -DisplayName "git commit ($($pkg.Name))"
      if ($Push) {
        $pushBranch = $targetBranch
        if ([string]::IsNullOrWhiteSpace($currentBranch) -or $currentBranch -eq 'HEAD' -or $currentBranch -eq 'main' -or $currentBranch -eq 'master') {
          Invoke-Executable -FilePath 'git' -Arguments @('checkout','-B',$pushBranch) -WorkingDirectory $pkg.FullName -DisplayName "git checkout -B $pushBranch ($($pkg.Name))"
        } else {
          $pushBranch = $currentBranch
        }
        try {
          Invoke-Executable -FilePath 'git' -Arguments @('push','-u','origin',$pushBranch) -WorkingDirectory $pkg.FullName -DisplayName "git push origin $pushBranch ($($pkg.Name))"
          $ghCli = Get-Command gh -ErrorAction SilentlyContinue
          if ($ghCli -and $pushBranch -ne 'main' -and $pushBranch -ne 'master') {
            try {
              $prArgs = @('pr','create','-B','main','-H',$pushBranch,'-t',$finalMessage,'-b',$finalMessage)
              if ($prReviewers.Count -gt 0) {
                $prArgs += @('--reviewer', ($prReviewers -join ','))
              }
              Invoke-Executable -FilePath 'gh' -Arguments $prArgs -WorkingDirectory $pkg.FullName -DisplayName "gh pr create ($($pkg.Name))" -IgnoreExitCodes @(1)
              if ($prMergeMode -in @('squash','merge','rebase')) {
                Invoke-Executable -FilePath 'gh' -Arguments @('pr','merge','--auto',"--$prMergeMode") -WorkingDirectory $pkg.FullName -DisplayName "gh pr merge ($($pkg.Name))" -IgnoreExitCodes @(1)
              }
            } catch {
              Add-Warning("Package '$($pkg.Name)' PR creation failed (branch '$pushBranch'): $($_.Exception.Message)")
            }
          }
        } catch {
          Add-Warning("Package '$($pkg.Name)' push failed (branch '$pushBranch'): $($_.Exception.Message)")
        } finally {
          if ($currentBranch -and $currentBranch -ne 'HEAD' -and $currentBranch -ne $pushBranch) {
            try { Invoke-Executable -FilePath 'git' -Arguments @('checkout',$currentBranch) -WorkingDirectory $pkg.FullName -DisplayName "git checkout $currentBranch ($($pkg.Name))" } catch { }
          }
        }
      }
      $committed++
    } catch {
      Add-Warning("Package '$($pkg.Name)' commit failed: $($_.Exception.Message)")
    }
  }
  Write-UiLog ("Package commits completed (changed modules: {0})." -f $committed)
}

function Invoke-UmbrellaCommit {
  param([string]$Message,[bool]$Push)
  if ([string]::IsNullOrWhiteSpace($Message)) { return }
  $status = (git status --porcelain)
  if (-not $status) {
    Write-UiLog "No umbrella changes to commit."
    return
  }
  $prMergeMode = if ($env:BC_PR_MERGE_MODE -and $env:BC_PR_MERGE_MODE.Trim()) { $env:BC_PR_MERGE_MODE.Trim().ToLower() } else { 'squash' }
  $prReviewers = @()
  if ($env:BC_PR_REVIEWERS) {
    $prReviewers = @($env:BC_PR_REVIEWERS.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
  }
  $warningsText = if ($Warnings.Count) { "`n`nWarnings:`n - " + ($Warnings -join "`n - ") } else { '' }
  $finalMessage = $Message + $warningsText
  try {
    Write-UiLog "Committing umbrella repo..."
    git add -A | Out-Null
    git commit -m $finalMessage | Out-Null
    if ($Push) {
      Write-UiLog "Pushing umbrella repo..."
      git push | Out-Null
      $currentBranch = (git rev-parse --abbrev-ref HEAD).Trim()
      $ghCli = Get-Command gh -ErrorAction SilentlyContinue
      if ($ghCli -and $currentBranch -and $currentBranch -ne 'main' -and $currentBranch -ne 'master') {
        try {
          $prArgs = @('pr','create','-B','main','-H',$currentBranch,'-t',$finalMessage,'-b',$finalMessage)
          if ($prReviewers.Count -gt 0) {
            $prArgs += @('--reviewer', ($prReviewers -join ','))
          }
          Invoke-Executable -FilePath 'gh' -Arguments $prArgs -WorkingDirectory $RepoRoot -DisplayName "gh pr create (umbrella)" -IgnoreExitCodes @(1)
          if ($prMergeMode -in @('squash','merge','rebase')) {
            Invoke-Executable -FilePath 'gh' -Arguments @('pr','merge','--auto',"--$prMergeMode") -WorkingDirectory $RepoRoot -DisplayName "gh pr merge (umbrella)" -IgnoreExitCodes @(1)
          }
        } catch {
          Add-Warning("Umbrella PR creation failed (branch '$currentBranch'): $($_.Exception.Message)")
        }
      }
    }
    Write-UiLog "Umbrella commit complete."
  } catch {
    Add-Warning("Umbrella commit failed: $($_.Exception.Message)")
  }
}

$startButton.Add_Click({
  $startButton.Enabled = $false
  $closeButton.Enabled = $false
  foreach ($step in $Steps) { Update-StepStatus $step 'Pending' }
  $Warnings.Clear()

  $mode = if ($radioAuto.Checked) { 'Auto' } elseif ($radioSemi.Checked) { 'Semi' } else { 'Manual' }
  Write-UiLog "Starting workflow in $mode mode."

  # If DB-dependent steps are selected, force-enable the DB startup step.
  $dbStep       = $Steps | Where-Object { $_.Name -eq 'Docker Databases Up' } | Select-Object -First 1
  $dbDependents = @('Composer Test','Dockerized Test Suite')
  $dbNeeded     = ($Steps | Where-Object { $dbDependents -contains $_.Name -and $_.Item.Checked }).Count -gt 0
  if ($dbNeeded -and $dbStep -and $dbStep.Item -and -not $dbStep.Item.Checked) {
    $dbStep.Item.Checked = $true
    $dockerInfraCheck.Checked = $true
    Write-UiLog "DB-dependent steps selected -> enabling 'Docker Databases Up'."
  }

  $abort = $false
  foreach ($step in $Steps) {
    if (-not $step.Item.Checked) {
      Update-StepStatus $step 'Skipped'
      Add-Warning("Step '$($step.Name)' skipped (unchecked).")
      continue
    }

    if (-not ($step.ShouldRun.Invoke())) {
      Update-StepStatus $step 'Not requested'
      continue
    }

    if ($mode -eq 'Manual') {
      $res = Invoke-ManualActionPrompt $step.Name $step.Description
      switch ($res) {
        'Yes' { Update-StepStatus $step 'Marked done'; continue }
        'No'  { Update-StepStatus $step 'Skipped'; Add-Warning("Manual skip: $($step.Name)"); continue }
        default {
          $abort = $true
          break
        }
      }
    } else {
      $retry = $true
      while ($retry) {
        try {
          Update-StepStatus $step 'Running'
          Invoke-Script -ScriptBlock $step.Action -DisplayName $step.Name
          Update-StepStatus $step 'Done'
          $retry = $false
        } catch {
          Update-StepStatus $step 'Failed'
          if ($mode -eq 'Auto') {
            Add-Warning("Step '$($step.Name)' failed: $($_.Exception.Message)")
            $abort = $true
            break
          } else {
            $choice = Invoke-FailurePrompt $step.Name $_.Exception.Message
            switch ($choice) {
              'Yes' { Write-UiLog "Retrying $($step.Name)..."; $retry = $true }
              'No'  { Add-Warning("Step '$($step.Name)' skipped after failure."); $retry = $false }
              default { $abort = $true; $retry = $false }
            }
          }
        }
      }
      if ($abort) { break }
    }
  }

  if (-not $abort) {
    $packageMessage = New-CommitDraftMessage $script:PackagesTitleBox.Text $script:PackagesBodyBox.Text
    $umbrellaMessage = New-CommitDraftMessage $script:UmbrellaTitleBox.Text $script:UmbrellaBodyBox.Text
    Invoke-PackageCommit -Message $packageMessage -Push:$pushCheck.Checked
    Invoke-UmbrellaCommit -Message $umbrellaMessage -Push:$pushCheck.Checked
    Write-UiLog "Workflow completed."
    Write-UiLog "Reminder: mention @codex in your pull request (or trigger the Codex check manually). When code-review control is enabled, Codex will suggest improvements automatically or acknowledge with ."
  } else {
    Write-UiLog "Workflow aborted."
  }

  $startButton.Enabled = $true
  $closeButton.Enabled = $true
})
$AllStepNames = @($Steps | ForEach-Object { $_.Name })
$DocStepNames = @('Sync Submodules','Docs (Postgres)','Update PACKAGES.md')
$LicenseStepNames = @('Sync Submodules','Enforce LICENSE/NOTICE')
$CodeStepNames = @('Sync Submodules','Composer Install','Composer Dump','Composer Test','Test Packages Schema','Test Schema Output','SQL Lint')

function Get-ChangedFiles {
  try {
    $status = git status --porcelain
  } catch {
    return @()
  }
  $files = @()
  foreach ($line in $status) {
    if ($line.Length -lt 4) { continue }
    $path = $line.Substring(3).Trim()
    if ($path -match ' -> ') { $path = ($path -split ' -> ')[-1].Trim() }
    if (-not [string]::IsNullOrWhiteSpace($path)) { $files += $path }
  }
  return $files
}

function Format-FileList {
  param([string[]]$Files,[int]$Max = 5)
  if (-not $Files -or $Files.Count -eq 0) { return 'no tracked files' }
  if ($Files.Count -le $Max) { return ($Files -join ', ') }
  $more = $Files.Count - $Max
  return (($Files[0..($Max-1)]) -join ', ') + " (+$more more)"
}

function Get-StepRecommendation {
  $files = Get-ChangedFiles
  if ($files.Count -eq 0) {
    return [pscustomobject]@{
      Scope  = 'All'
      Summary = 'No local changes detected - running full workflow.'
      Steps  = $AllStepNames
      Files  = $files
    }
  }
  $flags = @{
    Schema  = $false
    Docs    = $false
    License = $false
    Code    = $false
  }
  foreach ($f in $files) {
    if ($f -match '^(schema/|scripts/schema|scripts/schema-tools|packages/[^/]+/schema|templates/)') { $flags.Schema = $true; continue }
    if ($f -match '^(docs/|README|PACKAGES\.md|examples/|docs/)' ) { $flags.Docs = $true; continue }
    if ($f -match '^(LICENSE|NOTICE|LEGAL|scripts/quality/enforce-license)' ) { $flags.License = $true; continue }
    if ($f -match '^(src/|tests/|composer\.|bin/|tools/|scripts/)' ) { $flags.Code = $true; continue }
  }

  $scope = 'All'
  $steps = $AllStepNames
  $summary = "Mixed changes detected`n`tfull workflow is recommended."

  if ($flags.Schema -or ($flags.Docs -and $flags.Code) -or ($files.Count -gt 20)) {
    $scope = 'All'
    $steps = $AllStepNames
    $summary = "Schema or mixed-impact changes detected`n`tfull workflow selected."
  }
  elseif ($flags.Docs -and -not ($flags.Code -or $flags.License -or $flags.Schema)) {
    $scope = 'Docs'
    $steps = $DocStepNames
    $summary = "Docs-only changes detected: " + (Format-FileList $files) + " - you may limit the flow to doc refresh steps."
  }
  elseif ($flags.License -and -not ($flags.Schema -or $flags.Code)) {
    $scope = 'License'
    $steps = $LicenseStepNames
    $summary = "License/legal files changed: " + (Format-FileList $files) + " - consider running the license enforcement step only."
  }
  elseif ($flags.Code -and -not $flags.Schema) {
    $scope = 'Code'
    $steps = $CodeStepNames
    $summary = "App/test changes detected (no schema edits): " + (Format-FileList $files) + " - tests and linting are sufficient."
  }

  return [pscustomobject]@{
    Scope = $scope
    Summary = $summary
    Steps = $steps
    Files = $files
  }
}

function Invoke-Recommendation {
  param($Recommendation)
  if (-not $Recommendation -or -not $Recommendation.Steps) { return }
  $target = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)
  foreach ($name in $Recommendation.Steps) { $target.Add($name) | Out-Null }
  foreach ($item in $StepsList.Items) {
    $item.Checked = $target.Contains($item.Text)
  }
}

$Recommendation = Get-StepRecommendation
$recommendLabel.Text = $Recommendation.Summary
$applyRecommendationBtn.Enabled = ($Recommendation.Scope -ne 'All')
$applyRecommendationBtn.Add_Click({ Invoke-Recommendation $Recommendation })
if ($Recommendation.Scope -ne 'All') {
  $autoPrompt = [System.Windows.Forms.MessageBox]::Show(
    "Detected $($Recommendation.Scope.ToLower()) changes.`nApply the suggested flow?",
    'Change detector',
    [System.Windows.Forms.MessageBoxButtons]::YesNo,
    [System.Windows.Forms.MessageBoxIcon]::Information)
  if ($autoPrompt -eq [System.Windows.Forms.DialogResult]::Yes) {
    Invoke-Recommendation $Recommendation
  }
}

[System.Windows.Forms.Application]::EnableVisualStyles()
[void][System.Windows.Forms.Application]::Run($form)
