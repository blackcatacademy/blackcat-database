$errs=@()
$tokens=New-Object 'System.Collections.ObjectModel.Collection[System.Management.Automation.Language.Token]'
[System.Management.Automation.Language.Parser]::ParseFile('scripts/schema-tools/Build-Definitions.ps1',[ref]$tokens,[ref]$errs) | Out-Null
$errs | ForEach-Object { '{0} | Line {1} Col {2}' -f $_.Message, $_.Extent.StartLineNumber, $_.Extent.StartColumnNumber }
