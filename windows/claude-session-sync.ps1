# Claude Session Sync - Windows
# Syncs Claude Code session indexes between Claude and Claude-3p (Bedrock) desktop apps.
# Run: powershell -ExecutionPolicy Bypass -File claude-session-sync.ps1

param(
    [switch]$SyncAll,
    [switch]$List,
    [switch]$Backup,
    [switch]$RestoreMissing,
    [switch]$InstallDaily,
    [switch]$RemoveDaily,
    [string]$VaultPath,
    [switch]$Help
)

$ErrorActionPreference = "Stop"

$ClaudeBase = Join-Path $env:APPDATA "Claude\claude-code-sessions"
$Claude3pBase = Join-Path $env:APPDATA "Claude-3p\claude-code-sessions"
$ProjectsRoot = Join-Path $env:USERPROFILE ".claude\projects"

# The vault lives outside every directory Claude manages, so Claude's own pruning can
# never reach it. Override with -VaultPath to keep it on an external or synced drive.
$VaultRoot = if ($VaultPath) { $VaultPath } else { Join-Path $env:LOCALAPPDATA "ClaudeSessionSync\Vault" }
$BlobsRoot = Join-Path $VaultRoot "blobs"
$ManifestPath = Join-Path $VaultRoot "manifest.json"
$RecoveredRoot = Join-Path $VaultRoot "recovered"

function Get-SessionDirs {
    param([string]$Base)
    $dirs = @()
    if (-not (Test-Path $Base)) { return $dirs }
    foreach ($acct in Get-ChildItem $Base -Directory) {
        foreach ($org in Get-ChildItem $acct.FullName -Directory) {
            $dirs += $org.FullName
        }
    }
    return $dirs
}

function Get-Sessions {
    param([string]$Dir)
    $sessions = @()
    $files = Get-ChildItem $Dir -Filter "local_*.json" -ErrorAction SilentlyContinue
    foreach ($f in $files) {
        try {
            $data = Get-Content $f.FullName -Raw | ConvertFrom-Json
            $sessions += [PSCustomObject]@{
                SessionId = $data.sessionId
                Title     = if ($data.title) { $data.title } else { "Untitled" }
                Model     = if ($data.model) { $data.model } else { "?" }
                File      = $f
                Dir       = $Dir
            }
        } catch {
            Write-Warning "Could not parse $($f.Name): $_"
        }
    }
    return $sessions
}

function Show-Sessions {
    $claudeDirs = Get-SessionDirs $ClaudeBase
    $claude3pDirs = Get-SessionDirs $Claude3pBase

    Write-Host "`n=== Claude (Personal) ===" -ForegroundColor Cyan
    foreach ($d in $claudeDirs) {
        $sessions = Get-Sessions $d
        foreach ($s in $sessions) {
            $synced = $false
            foreach ($td in $claude3pDirs) {
                if (Test-Path (Join-Path $td $s.File.Name)) { $synced = $true; break }
            }
            $status = if ($synced) { "[synced]" } else { "[not synced]" }
            $color = if ($synced) { "Green" } else { "Yellow" }
            Write-Host "  $status $($s.Title) ($($s.Model))" -ForegroundColor $color
        }
    }

    Write-Host "`n=== Claude-3p (Bedrock) ===" -ForegroundColor Magenta
    foreach ($d in $claude3pDirs) {
        $sessions = Get-Sessions $d
        foreach ($s in $sessions) {
            $synced = $false
            foreach ($td in $claudeDirs) {
                if (Test-Path (Join-Path $td $s.File.Name)) { $synced = $true; break }
            }
            $status = if ($synced) { "[synced]" } else { "[not synced]" }
            $color = if ($synced) { "Green" } else { "Yellow" }
            Write-Host "  $status $($s.Title) ($($s.Model))" -ForegroundColor $color
        }
    }
}

function Sync-AllSessions {
    $claudeDirs = Get-SessionDirs $ClaudeBase
    $claude3pDirs = Get-SessionDirs $Claude3pBase
    $copied = 0

    foreach ($srcDir in $claudeDirs) {
        $sessions = Get-Sessions $srcDir
        foreach ($s in $sessions) {
            foreach ($dstDir in $claude3pDirs) {
                $dest = Join-Path $dstDir $s.File.Name
                if (-not (Test-Path $dest)) {
                    Copy-Item $s.File.FullName $dest
                    Write-Host "  Copied to Bedrock: $($s.Title)" -ForegroundColor Green
                    $copied++
                }
            }
        }
    }

    foreach ($srcDir in $claude3pDirs) {
        $sessions = Get-Sessions $srcDir
        foreach ($s in $sessions) {
            foreach ($dstDir in $claudeDirs) {
                $dest = Join-Path $dstDir $s.File.Name
                if (-not (Test-Path $dest)) {
                    Copy-Item $s.File.FullName $dest
                    Write-Host "  Copied to Personal: $($s.Title)" -ForegroundColor Green
                    $copied++
                }
            }
        }
    }

    if ($copied -eq 0) {
        Write-Host "`nAll sessions already synced." -ForegroundColor Green
    } else {
        Write-Host "`n$copied session(s) synced." -ForegroundColor Cyan
    }
}

# ---------------------------------------------------------------------------
# Vault: daily backup and restore
# ---------------------------------------------------------------------------

function Get-Manifest {
    if (Test-Path $ManifestPath) {
        try { return Get-Content $ManifestPath -Raw | ConvertFrom-Json } catch { }
    }
    return [PSCustomObject]@{ version = 1; lastBackupAt = $null; entries = @() }
}

function Save-Manifest {
    param($Manifest)
    New-Item -ItemType Directory -Force -Path $VaultRoot | Out-Null
    $Manifest | ConvertTo-Json -Depth 10 | Set-Content $ManifestPath -Encoding UTF8
}

# Blobs are stored under their SHA-256, so a daily run over an unchanged transcript
# costs nothing beyond the first copy.
function Add-Blob {
    param([string]$Path)
    $hash = (Get-FileHash $Path -Algorithm SHA256).Hash.ToLower()
    $dir = Join-Path $BlobsRoot $hash.Substring(0, 2)
    $dest = Join-Path $dir $hash
    $wrote = $false
    if (-not (Test-Path $dest)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        Copy-Item $Path $dest
        $wrote = $true
    }
    return [PSCustomObject]@{ Digest = $hash; Wrote = $wrote; Bytes = (Get-Item $Path).Length }
}

function Get-BlobPath {
    param([string]$Digest)
    return Join-Path (Join-Path $BlobsRoot $Digest.Substring(0, 2)) $Digest
}

# Keeps recent revisions plus the largest ever seen. The largest is pinned because it is
# the copy recovery depends on; a run of truncated captures must not push it out.
function Add-Version {
    param($History, [string]$Digest, [long]$Bytes, [string]$Stamp)
    $list = @()
    if ($History) { $list = @($History) }
    if ($list | Where-Object { $_.digest -eq $Digest }) { return $list }
    $list += [PSCustomObject]@{ digest = $Digest; bytes = $Bytes; capturedAt = $Stamp }
    if ($list.Count -le 20) { return $list }
    $largest = $list | Sort-Object bytes -Descending | Select-Object -First 1
    $trimmed = @($list | Sort-Object capturedAt -Descending | Select-Object -First 20)
    if (-not ($trimmed | Where-Object { $_.digest -eq $largest.digest })) { $trimmed += $largest }
    return $trimmed
}

function Invoke-Backup {
    $stamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    $manifest = Get-Manifest
    $byKey = @{}
    foreach ($e in $manifest.entries) { $byKey[$e.key] = $e }

    $saved = 0; $bytes = 0

    # Half one: index rows, which carry title, cwd and model.
    foreach ($base in @(@{P = $ClaudeBase; N = "Claude" }, @{P = $Claude3pBase; N = "Claude-3p" })) {
        foreach ($dir in (Get-SessionDirs $base.P)) {
            foreach ($f in (Get-ChildItem $dir -Filter "local_*.json" -ErrorAction SilentlyContinue)) {
                try { $data = Get-Content $f.FullName -Raw | ConvertFrom-Json } catch { continue }
                $key = if ($data.cliSessionId) { $data.cliSessionId } else { $data.sessionId }
                if (-not $key) { continue }
                $blob = Add-Blob $f.FullName
                if ($blob.Wrote) { $saved++; $bytes += $blob.Bytes }

                $entry = $byKey[$key]
                if (-not $entry) {
                    $entry = [PSCustomObject]@{
                        key = $key; sessionId = $null; cliSessionId = $null; title = "Untitled"
                        cwd = "?"; model = "?"; projectSlug = $null; transcriptRelPath = $null
                        appName = $null; indexDir = $null; indexFileName = $null
                        indexBlob = $null; transcriptBlob = $null
                        indexBytes = 0; transcriptBytes = 0
                        indexHistory = @(); transcriptHistory = @()
                        firstSeenAt = $stamp; lastBackupAt = $stamp
                    }
                }
                $entry.sessionId = $data.sessionId
                $entry.cliSessionId = $data.cliSessionId
                if ($data.title) { $entry.title = $data.title }
                if ($data.cwd) { $entry.cwd = $data.cwd }
                if ($data.model) { $entry.model = $data.model }
                $entry.appName = $base.N
                $entry.indexDir = $dir
                $entry.indexFileName = $f.Name
                $entry.indexBlob = $blob.Digest
                $entry.indexBytes = $blob.Bytes
                $entry.indexHistory = Add-Version $entry.indexHistory $blob.Digest $blob.Bytes $stamp
                $entry.lastBackupAt = $stamp
                $byKey[$key] = $entry
            }
        }
    }

    # Half two: transcripts. Scanned recursively because subagent transcripts sit one level
    # deeper, at <slug>\<parentSessionId>\subagents\agent-*.jsonl, and a flat scan misses them.
    if (Test-Path $ProjectsRoot) {
        $prefix = (Resolve-Path $ProjectsRoot).Path.TrimEnd('\') + '\'
        foreach ($f in (Get-ChildItem $ProjectsRoot -Filter "*.jsonl" -Recurse -File -ErrorAction SilentlyContinue)) {
            $rel = $f.FullName.Substring($prefix.Length)
            $parts = $rel -split '\\'
            if ($parts.Count -lt 2) { continue }
            $isTopLevel = $parts.Count -eq 2
            $stem = [IO.Path]::GetFileNameWithoutExtension($f.Name)
            $key = if ($isTopLevel) { $stem } else { $rel }

            $blob = Add-Blob $f.FullName
            if ($blob.Wrote) { $saved++; $bytes += $blob.Bytes }

            $entry = $byKey[$key]
            if (-not $entry) {
                $entry = [PSCustomObject]@{
                    key = $key; sessionId = $null; cliSessionId = $null; title = $stem
                    cwd = "?"; model = "?"; projectSlug = $null; transcriptRelPath = $null
                    appName = $null; indexDir = $null; indexFileName = $null
                    indexBlob = $null; transcriptBlob = $null
                    indexBytes = 0; transcriptBytes = 0
                    indexHistory = @(); transcriptHistory = @()
                    firstSeenAt = $stamp; lastBackupAt = $stamp
                }
            }
            if ($isTopLevel) { $entry.cliSessionId = $stem }
            $entry.projectSlug = $parts[0]
            $entry.transcriptRelPath = $rel
            $entry.transcriptBlob = $blob.Digest
            $entry.transcriptBytes = $blob.Bytes
            $entry.transcriptHistory = Add-Version $entry.transcriptHistory $blob.Digest $blob.Bytes $stamp
            $entry.lastBackupAt = $stamp
            $byKey[$key] = $entry
        }
    }

    $manifest.entries = @($byKey.Values)
    $manifest.lastBackupAt = $stamp
    Save-Manifest $manifest

    $mb = [math]::Round($bytes / 1MB, 1)
    Write-Host "  Backed up $($manifest.entries.Count) session(s), $saved new file(s), $mb MB written" -ForegroundColor Green
    return $manifest
}

function Invoke-RestoreMissing {
    $manifest = Get-Manifest
    $restored = 0; $recovered = 0

    foreach ($e in $manifest.entries) {
        # Always recover the fullest copy ever captured, not the newest: the newest may be
        # a stub Claude wrote after wiping the file.
        $best = $null
        if ($e.transcriptHistory) { $best = $e.transcriptHistory | Sort-Object bytes -Descending | Select-Object -First 1 }
        elseif ($e.transcriptBlob) { $best = [PSCustomObject]@{ digest = $e.transcriptBlob; bytes = $e.transcriptBytes } }

        if ($best -and $e.transcriptRelPath) {
            $live = Join-Path $ProjectsRoot $e.transcriptRelPath
            $src = Get-BlobPath $best.digest
            if (Test-Path $src) {
                if (-not (Test-Path $live)) {
                    New-Item -ItemType Directory -Force -Path (Split-Path $live) | Out-Null
                    Copy-Item $src $live
                    Write-Host "  Restored: $($e.title)" -ForegroundColor Green
                    $restored++
                }
                elseif ((Get-Item $live).Length -lt $best.bytes) {
                    # Claude Code appends to an open handle; replacing the live file would
                    # strand everything written afterwards. The fuller copy goes beside the
                    # vault instead, out of Claude's directories.
                    $dir = Join-Path $RecoveredRoot $e.projectSlug
                    New-Item -ItemType Directory -Force -Path $dir | Out-Null
                    $stem = [IO.Path]::GetFileNameWithoutExtension($e.transcriptRelPath)
                    $name = "$stem-recovered-$((Get-Date).ToString('yyyyMMdd-HHmmss')).jsonl"
                    Copy-Item $src (Join-Path $dir $name)
                    Write-Host "  Truncated on disk, fuller copy saved: $($e.title)" -ForegroundColor Yellow
                    $recovered++
                }
            }
        }

        $bestIdx = $null
        if ($e.indexHistory) { $bestIdx = $e.indexHistory | Sort-Object bytes -Descending | Select-Object -First 1 }
        elseif ($e.indexBlob) { $bestIdx = [PSCustomObject]@{ digest = $e.indexBlob } }

        if ($bestIdx -and $e.indexDir -and $e.indexFileName) {
            $live = Join-Path $e.indexDir $e.indexFileName
            $src = Get-BlobPath $bestIdx.digest
            if ((Test-Path $src) -and -not (Test-Path $live)) {
                New-Item -ItemType Directory -Force -Path $e.indexDir | Out-Null
                Copy-Item $src $live
                $restored++
            }
        }
    }

    if ($restored -eq 0 -and $recovered -eq 0) {
        Write-Host "  Nothing to restore." -ForegroundColor Green
    } else {
        Write-Host "`n  $restored file(s) restored, $recovered fuller copy(ies) in the vault." -ForegroundColor Cyan
    }
}

function Install-DailyTask {
    $script = $MyInvocation.MyCommand.Path
    if (-not $script) { $script = $PSCommandPath }
    $args = "-ExecutionPolicy Bypass -File `"$script`" -Backup -RestoreMissing"
    if ($VaultPath) { $args += " -VaultPath `"$VaultPath`"" }
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $args
    $trigger = New-ScheduledTaskTrigger -Daily -At 12pm
    # StartWhenAvailable catches up after the machine was asleep, so a backup does not
    # silently lapse for the days the laptop stayed closed.
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    Register-ScheduledTask -TaskName "ClaudeSessionSyncBackup" -Action $action -Trigger $trigger `
        -Settings $settings -Description "Daily backup of Claude Code sessions" -Force | Out-Null
    Write-Host "  Daily backup scheduled at 12:00." -ForegroundColor Green
}

function Remove-DailyTask {
    Unregister-ScheduledTask -TaskName "ClaudeSessionSyncBackup" -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "  Daily backup removed." -ForegroundColor Yellow
}

function Show-VaultStatus {
    $manifest = Get-Manifest
    if (-not $manifest.entries -or $manifest.entries.Count -eq 0) {
        Write-Host "`n  Vault is empty. Run a backup first." -ForegroundColor Yellow
        return
    }
    $total = ($manifest.entries | Measure-Object -Property transcriptBytes -Sum).Sum
    $missing = 0
    foreach ($e in $manifest.entries) {
        if ($e.transcriptRelPath -and -not (Test-Path (Join-Path $ProjectsRoot $e.transcriptRelPath))) { $missing++ }
    }
    Write-Host "`n  Vault: $VaultRoot" -ForegroundColor Cyan
    Write-Host "  $($manifest.entries.Count) session(s), $([math]::Round($total / 1MB, 1)) MB"
    Write-Host "  Last backup: $($manifest.lastBackupAt)"
    $color = if ($missing -gt 0) { "Yellow" } else { "Green" }
    Write-Host "  Gone from disk, recoverable: $missing" -ForegroundColor $color
}

function Restart-Claude {
    param([string]$AppName)
    $proc = Get-Process -Name $AppName -ErrorAction SilentlyContinue
    if ($proc) {
        $exePath = $proc.Path
        Stop-Process -Name $AppName -Force
        Write-Host "  Stopped $AppName" -ForegroundColor Yellow
        Start-Sleep -Seconds 2
        if ($exePath) {
            Start-Process $exePath
            Write-Host "  Restarted $AppName" -ForegroundColor Green
        }
    } else {
        Write-Host "  $AppName is not running" -ForegroundColor Yellow
    }
}

# Interactive menu
function Show-Menu {
    while ($true) {
        Write-Host "`n--- Claude Session Sync ---" -ForegroundColor Blue
        Write-Host "1. List sessions"
        Write-Host "2. Sync all sessions"
        Write-Host "3. Back up now (vault)"
        Write-Host "4. Restore what Claude deleted"
        Write-Host "5. Vault status"
        Write-Host "6. Enable daily backup"
        Write-Host "7. Disable daily backup"
        Write-Host "8. Restart Claude (Personal)"
        Write-Host "9. Restart Claude-3p (Bedrock)"
        Write-Host "0. Quit"
        $choice = Read-Host "Choose"

        switch ($choice) {
            "1" { Show-Sessions }
            "2" { Sync-AllSessions }
            "3" { Invoke-Backup | Out-Null }
            "4" { Invoke-RestoreMissing }
            "5" { Show-VaultStatus }
            "6" { Install-DailyTask }
            "7" { Remove-DailyTask }
            "8" { Restart-Claude "Claude" }
            "9" { Restart-Claude "Claude-3p" }
            "0" { return }
            default { Write-Host "Invalid option" -ForegroundColor Red }
        }
    }
}

if ($Help) {
    Write-Host "Claude Session Sync - Windows"
    Write-Host "Usage:"
    Write-Host "  .\claude-session-sync.ps1                  Interactive menu"
    Write-Host "  .\claude-session-sync.ps1 -List            List all sessions"
    Write-Host "  .\claude-session-sync.ps1 -SyncAll         Sync all sessions"
    Write-Host "  .\claude-session-sync.ps1 -Backup          Back up sessions to the vault"
    Write-Host "  .\claude-session-sync.ps1 -RestoreMissing  Put back what Claude deleted"
    Write-Host "  .\claude-session-sync.ps1 -InstallDaily    Schedule a daily backup"
    Write-Host "  .\claude-session-sync.ps1 -RemoveDaily     Remove the scheduled backup"
    Write-Host "  -VaultPath <dir>   Keep the vault elsewhere (external or synced drive)"
    exit 0
}

if ($InstallDaily) { Install-DailyTask; exit 0 }
if ($RemoveDaily) { Remove-DailyTask; exit 0 }
if ($Backup) { Invoke-Backup | Out-Null }
if ($RestoreMissing) { Invoke-RestoreMissing }
if ($Backup -or $RestoreMissing) { exit 0 }
if ($List) { Show-Sessions; exit 0 }
if ($SyncAll) { Sync-AllSessions; exit 0 }

Show-Menu
