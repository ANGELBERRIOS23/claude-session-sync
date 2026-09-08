# Claude Session Sync - Windows
# Syncs Claude Code session indexes between Claude and Claude-3p (Bedrock) desktop apps.
# Run: powershell -ExecutionPolicy Bypass -File claude-session-sync.ps1

param(
    [switch]$SyncAll,
    [switch]$List,
    [switch]$Help
)

$ErrorActionPreference = "Stop"

$ClaudeBase = Join-Path $env:APPDATA "Claude\claude-code-sessions"
$Claude3pBase = Join-Path $env:APPDATA "Claude-3p\claude-code-sessions"

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
        Write-Host "3. Restart Claude (Personal)"
        Write-Host "4. Restart Claude-3p (Bedrock)"
        Write-Host "5. Quit"
        $choice = Read-Host "Choose"

        switch ($choice) {
            "1" { Show-Sessions }
            "2" { Sync-AllSessions }
            "3" { Restart-Claude "Claude" }
            "4" { Restart-Claude "Claude-3p" }
            "5" { return }
            default { Write-Host "Invalid option" -ForegroundColor Red }
        }
    }
}

if ($Help) {
    Write-Host "Claude Session Sync - Windows"
    Write-Host "Usage:"
    Write-Host "  .\claude-session-sync.ps1           Interactive menu"
    Write-Host "  .\claude-session-sync.ps1 -List      List all sessions"
    Write-Host "  .\claude-session-sync.ps1 -SyncAll   Sync all sessions"
    exit 0
}

if ($List) { Show-Sessions; exit 0 }
if ($SyncAll) { Sync-AllSessions; exit 0 }

Show-Menu
