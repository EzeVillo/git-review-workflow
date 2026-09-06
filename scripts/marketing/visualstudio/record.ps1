param([string]$WindowTitle, [string]$Ffmpeg, [int]$DurationSeconds = 900)
$ErrorActionPreference = 'Stop'
$captureOutput = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../demo/marketing/visualstudio'))
if (-not $WindowTitle -or -not (Test-Path -LiteralPath $Ffmpeg)) { throw 'Pass the observed IDE window title and the FFmpeg executable.' }
if ($DurationSeconds -lt 1) { throw 'DurationSeconds must be positive.' }
[IO.File]::WriteAllText((Join-Path $captureOutput 'chapters.json'), '[]')
[IO.File]::WriteAllText((Join-Path $captureOutput 'recording-start.txt'), [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds().ToString())
# Capture the IDE window only. The editorial crop excludes the localized host
# menus and status bars; the English extension and real C# editor stay intact.
& $Ffmpeg -y -loglevel warning -f gdigrab -framerate 30 -i "title=$WindowTitle" -t $DurationSeconds -vf 'crop=1440:798:3:66,pad=1440:900:0:30:color=0x1e1e1e' -c:v libx264 -preset ultrafast -crf 18 -pix_fmt yuv420p (Join-Path $captureOutput 'raw.mp4')
if ($LASTEXITCODE -ne 0) { throw 'Recording failed.' }
