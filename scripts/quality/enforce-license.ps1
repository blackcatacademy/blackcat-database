[CmdletBinding()]
param(
  [string]$Packages = 'packages',          # folder containing package submodules (relative to repo root by default)
  [switch]$Force,                          # overwrite existing files
  [switch]$DryRun,                         # only prints the actions
  [int]$Year = 2025,
  [string]$Owner = 'Black Cat Academy s. r. o.',
  [string]$Product = 'BlackCat Database',
  [string]$LicenseVersion = 'Version 1.0 – October 2025',
  [string]$Email = 'blackcatacademy@protonmail.com',
  [switch]$Push,                           # optional; defaults to false

  # Optional external templates (falls back to the embedded texts below)
  [string]$LicensePath,
  [string]$NoticePath,
  [string]$LegalPath
)

Set-StrictMode -Version Latest

# Resolve repo root (two levels above scripts/quality by default) and packages path
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..' '..') | Select-Object -ExpandProperty Path
$packagesPath = if ([IO.Path]::IsPathRooted($Packages)) { $Packages } else { Join-Path $repoRoot $Packages }

# ----------------- Helpers -----------------
function Set-FileContentSafe {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] [string]$Path,
    [Parameter(Mandatory)] [string]$Content,
    [switch]$Force
  )
  $parent = Split-Path -Parent $Path
  if ($parent -and -not (Test-Path -LiteralPath $parent)) {
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
  }
  if ((Test-Path -LiteralPath $Path) -and -not $Force) { return $false }
  Set-Content -Encoding UTF8 -LiteralPath $Path -Value $Content   # LiteralPath with default newline handling
  return $true
}

function Test-GitPendingChanges {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$RepoPath)
  $out = git -C $RepoPath status --porcelain
  return -not [string]::IsNullOrWhiteSpace($out)
}

function Expand-Placeholders {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Text,
    [Parameter(Mandatory)][hashtable]$Map
  )
  $t = $Text
  foreach ($k in $Map.Keys) {
    $t = $t.Replace("{$k}", [string]$Map[$k])
  }
  return $t
}

function Get-Body {
  [CmdletBinding()]
  param(
    [string]$Path,
    [string]$DefaultText,
    [hashtable]$Map
  )
  if ($Path -and (Test-Path $Path)) {
    $raw = Get-Content -Raw -Encoding UTF8 $Path
    return Expand-Placeholders -Text $raw -Map $Map
  } else {
    return Expand-Placeholders -Text $DefaultText -Map $Map
  }
}

# ----------------- Default texts (templated) -----------------
$ph = @{
  'YEAR'             = $Year
  'OWNER'            = $Owner
  'EMAIL'            = $Email
  'PRODUCT'          = $Product
  'LICENSE_VERSION'  = $LicenseVersion
}

$DefaultLicense = @'
{PRODUCT} Proprietary License
{LICENSE_VERSION}
© {YEAR} {OWNER}. All rights reserved.

This proprietary license is intended to protect the intellectual property, security, and integrity of the Software.

1. Ownership
This software and all associated components, libraries, documentation, and source code ("Software") are the exclusive property of {OWNER}. All rights, title, and interest are reserved.

2. Permitted Use
Subject to explicit written permission from the author, you may:
- Use the Software for personal or internal evaluation purposes only.
- Test or experiment with the Software in a non-commercial setting.
- Permission may be granted for educational or research purposes under separate terms.

3. Prohibited Use
Without prior written consent from {OWNER}, you may NOT:
- Redistribute, copy, or sublicense the Software.
- Modify, reverse engineer, decompile, or disassemble the Software.
- Use the Software for commercial purposes, including any form of paid service or product.
- Create or publish forks of the Software for commercial use. For the avoidance of doubt, creating a fork of the Software to be used, offered, sold, or otherwise exploited in any commercial context is strictly prohibited without a separate, explicit commercial license from {OWNER}.

4. Warranty Disclaimer
The Software is provided "as-is" and without any warranty, express or implied, including but not limited to fitness for a particular purpose, non-infringement, or merchantability. {OWNER} shall not be liable for any damages arising from the use or inability to use the Software.

5. Limitation of Liability
In no event shall {OWNER} be liable for any indirect, incidental, special, consequential, or punitive damages, including but not limited to loss of profits, data, or business opportunities, even if advised of the possibility of such damages.

6. Licensing Inquiries
Requests for commercial licensing, redistribution, or other permissions should be directed to:
{EMAIL}
{OWNER} will respond to licensing inquiries within a reasonable timeframe.

7. Governing Law
This License shall be governed by and construed in accordance with the laws of the Slovak Republic, without regard to conflict of law principles.

8. Enforcement
8.1 Remedies. Any unauthorized use, distribution, modification, or commercial exploitation of the Software (including creating or offering forks for commercial use) constitutes a material breach of this License and will entitle {OWNER} to pursue all available remedies under law and equity, including, but not limited to:
  - Immediate termination of any rights granted under this License.
  - Injunctive relief (temporary and permanent injunctions) to prevent continued unauthorized use or distribution.
  - Recovery of actual damages, statutory damages where applicable, and disgorgement of profits attributable to the breach.
  - Recovery of all costs and expenses, including reasonable attorneys' fees, incurred in enforcing this License.

8.2 Preservation and Destruction. Upon notice of termination for breach, the licensee must, within a reasonable time, cease all use of the Software and certify in writing that all copies, derivatives, builds, and forks (including any copies stored on servers, cloud storage, or distribution channels) have been returned or destroyed.

8.3 Criminal and Regulatory Referrals. {OWNER} reserves the right to refer matters of willful infringement or other unlawful conduct to appropriate law enforcement or regulatory authorities.

8.4 Enforcement Procedure. Complaints or reports of suspected violations should be sent to {EMAIL} and must include sufficient detail to identify the allegedly infringing material. {OWNER} will investigate reported violations and may take appropriate legal action where warranted.

8.5 No Waiver. Failure to enforce any provision of this License shall not constitute a waiver of future enforcement of that or any other provision.
'@

$DefaultNotice = @"
This repository is licensed under {PRODUCT} Proprietary License ({LICENSE_VERSION}).
© {YEAR} {OWNER}. All rights reserved.

If you redistribute this repository or its substantial parts, you must include this NOTICE and the LICENSE file.
"@

$DefaultLegal = @'
# Legal / Company Details

**Company name:** Black Cat Academy s. r. o.  
**Registry section:** Sro  
**Entry number:** 81922/L  

**Registered office:**  
Dolna ulica 1C  
Kunerad 013 13  

**Company ID (ICO):** 55 396 461  
**Date of registration:** 21 April 2023  
**Legal form:** Limited Liability Company  

**Shareholders:**  
- Vit Black — Contribution: 2 500 EUR (Paid: 2 500 EUR)  
- Jaine Black — Contribution: 2 500 EUR (Paid: 2 500 EUR)  

**Statutory directors:**  
- Vit Black  
- Jaine Black  
*Acting on behalf of the company:* Each director acts and signs independently.

**Registered capital:** 5 000 EUR (Paid-in amount: 5 000 EUR)

**Licensing contact:** blackcatacademy@protonmail.com
'@

# Build the texts (external file takes precedence)
$LicenseText = Get-Body -Path $LicensePath -DefaultText $DefaultLicense -Map $ph
$NoticeText  = Get-Body -Path $NoticePath  -DefaultText $DefaultNotice  -Map $ph
$LegalMd     = Get-Body -Path $LegalPath   -DefaultText $DefaultLegal   -Map $ph

# ----------------- Run -----------------
if (-not (Test-Path -LiteralPath $packagesPath)) {
  throw "Packages folder '$packagesPath' not found. Run from repo root or set -Packages explicitly."
}

$modules = @(Get-ChildItem -Directory $packagesPath | Sort-Object Name)
if (-not $modules -or $modules.Count -eq 0) { Write-Host "No modules found under '$packagesPath'." ; return }

$changed = @()
foreach ($m in $modules) {
  $repoPath = $m.FullName
  $name = $m.Name

  Write-Host "==> $name"

  $did1 = Set-FileContentSafe -Path (Join-Path $repoPath 'LICENSE') -Content $LicenseText -Force:$Force
  $did2 = Set-FileContentSafe -Path (Join-Path $repoPath 'NOTICE')  -Content $NoticeText  -Force:$Force
  $did3 = Set-FileContentSafe -Path (Join-Path $repoPath 'LEGAL.md') -Content $LegalMd    -Force:$Force

  if ($DryRun) {
    if ($did1 -or $did2 -or $did3) { Write-Host "DRY-RUN: changes would be committed in $name" }
    continue
  }

  if ($did1 -or $did2 -or $did3) {
    Write-Host "Updated LICENSE/NOTICE/LEGAL in $name (pending manual git add/commit/push)."
    $changed += $name
  } else {
    Write-Host "OK   (no change)"
  }
}

# --- umbrella (root) files ---
$umbrellaRoot = $repoRoot

# write files individually and capture the results
$u1 = Set-FileContentSafe -Path (Join-Path $umbrellaRoot 'LICENSE')  -Content $LicenseText -Force:$Force
$u2 = Set-FileContentSafe -Path (Join-Path $umbrellaRoot 'NOTICE')   -Content $NoticeText  -Force:$Force
$u3 = Set-FileContentSafe -Path (Join-Path $umbrellaRoot 'LEGAL.md') -Content $LegalMd     -Force:$Force

# brief log plus change aggregation
Write-Host "Umbrella writes → $umbrellaRoot  | LICENSE=$u1 NOTICE=$u2 LEGAL=$u3"

Write-Host "Done. Updated modules: $($changed -join ', ')"
