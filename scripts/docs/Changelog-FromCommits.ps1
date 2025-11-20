param([string] $From = "HEAD~50", [string] $To = "HEAD", [string] $OutPath = "./CHANGELOG_GENERATED.md")
$logs = git log --pretty=format:"%H|%s|%an|%ad" $From..$To
$sections = @{ feat=@(); fix=@(); perf=@(); docs=@(); chore=@(); refactor=@(); test=@(); other=@() }
foreach ($ln in $logs) {
  $p = $ln.Split('|',4)
  $type = 'other'
  if ($p[1] -match '^(feat|fix|perf|docs|chore|refactor|test)(\(.+\))?:') { $type = $matches[1] }
  $sections[$type] += "- " + $p[1]
}
$md = "# Release notes`n"
foreach ($k in @('feat','fix','perf','refactor','docs','test','chore','other')) {
  if ($sections[$k].Count -gt 0) {
    $md += "`n## " + $k.ToUpper() + "`n" + ($sections[$k] -join "`n") + "`n"
  }
}
$md | Out-File -FilePath $OutPath -NoNewline -Encoding UTF8
Write-Host "Wrote $OutPath"
