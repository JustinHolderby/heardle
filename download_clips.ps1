# Heardle Audio Clip Downloader (PowerShell)
# Place in project root next to music-library/
# Run with: .\download_clips.ps1

$MUSIC_LIB     = ".\music-library"
$CLIP_DURATION = 30
$CLIP_START    = 0      # default start offset (seconds) used when a track has no "start" field
$SKIP_EXISTING = $true

# Check dependencies
foreach ($cmd in @("yt-dlp", "ffmpeg", "jq")) {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
        Write-Host "ERROR: '$cmd' not found. Run: winget install $cmd"
        Read-Host "Press Enter to exit"
        exit 1
    }
}

Write-Host "Dependencies OK" -ForegroundColor Green

$total = 0; $skipped = 0; $failed = 0; $success = 0

$dictFiles = Get-ChildItem -Path $MUSIC_LIB -Recurse -Filter "dictionary.json"

foreach ($dictFile in $dictFiles) {
    $dict     = $dictFile.FullName
    $genreDir = $dictFile.DirectoryName
    $genre    = Split-Path $genreDir -Leaf
    $audioDir = Join-Path $genreDir "audio"

    New-Item -ItemType Directory -Force -Path $audioDir | Out-Null

    Write-Host ""
    Write-Host "Genre: $genre" -ForegroundColor Cyan

    # Pull id + optional per-track start time (defaults to 0 if "start" is missing)
    # @tsv avoids embedding double-quote chars in the jq program, which PowerShell
    # can mangle when passing args through to a native .exe on Windows.
    $jqFilter = '.[$genre][] | [.id, (.start // 0)] | @tsv'
    $entries = & jq -r --arg genre $genre $jqFilter "$dict" 2>$null

    if (-not $entries) {
        Write-Host "  No IDs found - skipping" -ForegroundColor Yellow
        continue
    }

    foreach ($entry in $entries) {
        $entry = $entry.Trim()
        if (-not $entry) { continue }

        $parts      = $entry -split '\t', 2
        $videoId    = $parts[0].Trim()
        $trackStart = if ($parts.Count -gt 1 -and $parts[1].Trim()) { [double]$parts[1].Trim() } else { $CLIP_START }

        if (-not $videoId) { continue }

        $total++
        $outFile = Join-Path $audioDir "${videoId}.mp3"
        $tmpFile = Join-Path $env:TEMP "heardle_${videoId}"

        if ($SKIP_EXISTING -and (Test-Path $outFile)) {
            Write-Host "  SKIP $videoId" -ForegroundColor Gray
            $skipped++
            continue
        }

        Write-Host "  DOWN $videoId (start ${trackStart}s) ..." -NoNewline

        & yt-dlp --quiet --no-warnings -x --audio-format mp3 --audio-quality 5 -o "${tmpFile}.%(ext)s" "https://www.youtube.com/watch?v=${videoId}" 2>$null

        if ($LASTEXITCODE -ne 0 -or -not (Test-Path "${tmpFile}.mp3")) {
            Write-Host " FAILED (unavailable)" -ForegroundColor Red
            $failed++
            continue
        }

        # -ss before -i seeks to the start point, -t sets the clip duration from there
        & ffmpeg -loglevel quiet -ss $trackStart -i "${tmpFile}.mp3" -t $CLIP_DURATION -q:a 5 "$outFile" 2>$null

        Remove-Item "${tmpFile}.mp3" -ErrorAction SilentlyContinue

        if (-not (Test-Path $outFile)) {
            Write-Host " FAILED (trim error)" -ForegroundColor Red
            $failed++
            continue
        }

        $size = "{0:N0} KB" -f ((Get-Item $outFile).Length / 1KB)
        Write-Host " OK ($size)" -ForegroundColor Green
        $success++
    }
}

Write-Host ""
Write-Host "════════════════" -ForegroundColor Cyan
Write-Host "Total:   $total"
Write-Host "Done:    $success" -ForegroundColor Green
Write-Host "Skipped: $skipped" -ForegroundColor Gray
Write-Host "Failed:  $failed" -ForegroundColor Red
Write-Host ""
Read-Host "Press Enter to exit"