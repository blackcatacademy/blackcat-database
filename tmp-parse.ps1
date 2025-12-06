$errs=@(); $tokens=@();
$null=[System.Management.Automation.Language.Parser]::ParseFile('scripts/schema-tools/Build-Definitions.ps1',[ref]$tokens,[ref]$errs);
if($errs){
  foreach($e in $errs){
    "$($e.Message) | Line $($e.Extent.StartLineNumber) Col $($e.Extent.StartColumnNumber)"
  }
}
