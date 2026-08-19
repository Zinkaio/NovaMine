<#
    NovaMine setup (Windows) - run automatically by start.cmd.

    Makes the server ready to run, then gets out of the way:

      1. Installs PHP into bin\php if it isn't there (pmmp/PHP-Binaries, the build
         PocketMine-MP itself ships).
      2. Enables PHP's JIT compiler.

    Why step 2 exists: the prebuilt PHP ships an OPcache compiled WITHOUT JIT, so the
    opcache.jit settings do not exist and setting them by hand does nothing. This
    replaces that OPcache with the official PHP build of the SAME version and ABI,
    which does include JIT. Measured on a tick-loop-shaped benchmark: 3.0x on one
    thread, 1.9x across worker threads.

    Safe by construction:
      - A PHP extension must match the interpreter ABI exactly or the process crashes,
        so the ABI is compared byte for byte and anything else is refused.
      - Your original OPcache is kept as php_opcache.dll.nojit-backup.
      - Every step is idempotent, and a failure here never stops the server starting.

    Undo:  .\setup.ps1 -Revert
#>

[CmdletBinding()]
param(
    [string] $ServerRoot = $PSScriptRoot,
    [switch] $Revert,
    [switch] $Force      # re-check even if the completion marker is present
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }

function Info($m) { Write-Host "  $m" }
function Ok  ($m) { Write-Host "  $m" -ForegroundColor Green }
function Warn($m) { Write-Host "  $m" -ForegroundColor Yellow }

$phpDir  = Join-Path $ServerRoot 'bin\php'
$php     = Join-Path $phpDir 'php.exe'
$extDir  = Join-Path $phpDir 'ext'
$dll     = Join-Path $extDir 'php_opcache.dll'
$backup  = "$dll.nojit-backup"
$iniPath = Join-Path $phpDir 'php.ini'
$marker  = Join-Path $phpDir '.novamine-setup'

$PMMP_PHP = 'https://github.com/pmmp/PHP-Binaries/releases/download/pm5-latest/PHP-8.2-Windows-x64-PM5.zip'

# ------------------------------------------------------------------- revert
if ($Revert) {
    if (Test-Path $backup) { Copy-Item $backup $dll -Force; Ok 'Restored the original OPcache.' }
    else                   { Warn 'No OPcache backup found.' }
    if (Test-Path $iniPath) {
        Set-Content -Path $iniPath -Encoding ASCII -Value (
            Get-Content $iniPath | Where-Object { $_ -notmatch '^\s*opcache\.jit' -and $_ -notmatch '^\s*;\s*\[NovaMine\]' }
        )
        Ok 'Removed the JIT settings from php.ini.'
    }
    Remove-Item $marker -Force -ErrorAction SilentlyContinue
    Info 'Done. Start the server normally.'
    exit 0
}

# Fast path: nothing to do on every subsequent launch.
if ((Test-Path $marker) -and (Test-Path $php) -and -not $Force) { exit 0 }

# ------------------------------------------------------- 1. make sure PHP exists
if (-not (Test-Path $php)) {
    Write-Host "`nPHP not found - installing it into bin\php ..." -ForegroundColor Cyan
    $tmp = Join-Path ([IO.Path]::GetTempPath()) "novamine-php-$([guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    try {
        $zip = Join-Path $tmp 'php.zip'
        Invoke-WebRequest -Uri $PMMP_PHP -OutFile $zip -UseBasicParsing -TimeoutSec 600
        # The archive already contains bin\php\..., so it expands at the server root.
        Expand-Archive $zip $ServerRoot -Force
        if (-not (Test-Path $php)) { throw 'archive did not contain bin\php\php.exe' }
        Ok "installed PHP $((& $php -r 'echo PHP_VERSION;' 2>&1) -join '')"
    } catch {
        Warn "Could not install PHP automatically: $($_.Exception.Message)"
        Warn 'Download it manually from https://github.com/pmmp/PHP-Binaries/releases (pm5-latest)'
        Warn 'and unpack it so that bin\php\php.exe exists.'
        exit 1
    } finally {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# --------------------------------------------------------------- 2. enable JIT
# Never fatal: a server that runs slightly slower beats a server that will not start.
try {
    $jitPresent = (& $php -r "echo isset(opcache_get_status(false)['jit']) ? 'yes' : 'no';" 2>&1) -join ''

    if ($jitPresent -ne 'yes') {
        $phpInfo = & $php -i 2>&1
        $abiM = $phpInfo | Select-String '^Zend Extension Build\s*=>\s*(.+)$'
        $abi  = if ($abiM) { $abiM.Matches.Groups[1].Value.Trim() } else { '' }
        $ver  = (& $php -r 'echo PHP_VERSION;' 2>&1) -join ''
        $zts  = (& $php -r 'echo PHP_ZTS;'     2>&1) -join ''

        if (-not $abi) { throw 'could not read the PHP ABI' }
        $vs = if ($abi -match 'V[SC](\d+)') { "vs$($Matches[1])" } else { throw "could not parse the compiler from '$abi'" }
        $ntsPart = if ($zts -eq '1') { '' } else { 'nts-' }
        $zipName = "php-$ver-$ntsPart" + "Win32-$vs-x64.zip"

        Write-Host "`nEnabling PHP JIT ..." -ForegroundColor Cyan
        $tmp = Join-Path ([IO.Path]::GetTempPath()) "novamine-jit-$([guid]::NewGuid().ToString('N'))"
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        try {
            $zip = Join-Path $tmp $zipName
            $got = $false
            foreach ($base in @('https://windows.php.net/downloads/releases',
                                'https://windows.php.net/downloads/releases/archives')) {
                try { Invoke-WebRequest -Uri "$base/$zipName" -OutFile $zip -UseBasicParsing -TimeoutSec 300; $got = $true; break } catch { }
            }
            if (-not $got) { throw "could not download $zipName" }

            Expand-Archive $zip (Join-Path $tmp 'x') -Force
            $newDll = Join-Path $tmp 'x\ext\php_opcache.dll'
            if (-not (Test-Path $newDll)) { throw 'no php_opcache.dll in the archive' }

            # The check that matters: a mismatched extension crashes the interpreter.
            $refM = & (Join-Path $tmp 'x\php.exe') -i 2>&1 | Select-String '^Zend Extension Build\s*=>\s*(.+)$'
            $ref  = if ($refM) { $refM.Matches.Groups[1].Value.Trim() } else { '' }
            if ($ref -ne $abi) { throw "ABI mismatch (yours '$abi', download '$ref')" }
            if (-not ([Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($newDll))).Contains('zend_jit')) {
                throw 'the downloaded OPcache has no JIT either'
            }

            if (-not (Test-Path $backup)) { Copy-Item $dll $backup -Force }
            Copy-Item $newDll $dll -Force
            Ok "OPcache replaced with the JIT-capable build (ABI $abi)"
        } finally {
            Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    # ini settings (idempotent)
    if (-not (Test-Path $iniPath)) { New-Item -ItemType File -Path $iniPath -Force | Out-Null }
    if (-not (Get-Content $iniPath | Select-String '^\s*opcache\.jit\s*=')) {
        Add-Content -Path $iniPath -Encoding ASCII -Value @(
            '',
            '; [NovaMine] tracing JIT: profiles hot loops at runtime and compiles the paths that',
            '; [NovaMine] actually run - the right fit for a long-lived server process.',
            '; [NovaMine] Undo with:  .\setup.ps1 -Revert',
            'opcache.jit=tracing',
            'opcache.jit_buffer_size=128M'
        )
    }

    $state = (& $php -r "`$s=opcache_get_status(false); echo (`$s['jit']['on'] ?? false) ? 'on' : 'off';" 2>&1) -join ''
    if ($state -eq 'on') { Ok 'JIT enabled' } else { Warn "JIT could not be enabled (reports '$state') - the server will still run." }
} catch {
    Warn "Skipping JIT: $($_.Exception.Message)"
    Warn 'The server will still run normally, just without the speed-up.'
}

Set-Content -Path $marker -Encoding ASCII -Value @(
    "NovaMine setup completed $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
    'Delete this file (or run setup.ps1 -Force) to make the launcher re-check.'
)
exit 0
