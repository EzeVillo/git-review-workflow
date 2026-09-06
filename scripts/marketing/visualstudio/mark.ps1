param([Parameter(Mandatory)][string]$Name)
$ErrorActionPreference = 'Stop'
$captureOutput = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../demo/marketing/visualstudio'))
$start = [long](Get-Content -LiteralPath (Join-Path $captureOutput 'recording-start.txt'))
$chapterFile = Join-Path $captureOutput 'chapters.json'
$chapters = @()
if (Test-Path -LiteralPath $chapterFile) { $chapters = @(Get-Content -LiteralPath $chapterFile -Raw | ConvertFrom-Json) }
$entry = @{ name = $Name; time = ([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() - $start) / 1000.0 }
$chapters += $entry
[IO.File]::WriteAllText($chapterFile, (ConvertTo-Json -InputObject $chapters), [Text.UTF8Encoding]::new($false))
$entry | ConvertTo-Json -Compress
