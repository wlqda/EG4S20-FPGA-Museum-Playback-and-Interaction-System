param([string]$OutputDirectory = "")
$ErrorActionPreference = 'Stop'
$project = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if (!$OutputDirectory) { $OutputDirectory = Join-Path $project 'build/narration/TF_CARD' }
[IO.Directory]::CreateDirectory($OutputDirectory) | Out-Null
$items = Get-Content (Join-Path (Split-Path $PSScriptRoot -Parent) 'narrations.json') -Raw -Encoding utf8 | ConvertFrom-Json
$speaker = New-Object -ComObject SAPI.SpVoice
$selected = $null
foreach ($token in $speaker.GetVoices()) { if ($token.GetDescription() -like '*Huihui*') { $selected = $token; break } }
if ($null -eq $selected) { throw 'Microsoft Huihui Desktop voice is required.' }
$speaker.Voice = $selected
$speaker.Rate = -1
$speaker.Volume = 100
foreach ($item in $items) {
    $destination = Join-Path $OutputDirectory $item.filename
    if (Test-Path -LiteralPath $destination) { throw "Refusing to overwrite existing audio: $destination" }
    $stream = New-Object -ComObject SAPI.SpFileStream
    $format = New-Object -ComObject SAPI.SpAudioFormat
    $format.Type = 38 # SAFT48kHz16BitMono
    $stream.Format = $format
    try {
        $stream.Open($destination, 3, $false)
        $speaker.AudioOutputStream = $stream
        $speaker.AllowAudioOutputFormatChangesOnNextSet = $false
        [void]$speaker.Speak($item.text, 0)
    } finally { $stream.Close() }
    Write-Output ("Generated " + $item.filename + " " + $item.title)
}
