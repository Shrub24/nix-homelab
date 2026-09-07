# windows-dj-setup/setup.ps1 - run as Administrator from S:\
# Target shell: Windows PowerShell 5.1. Keep this file ASCII only: 5.1 reads
# BOM-less UTF-8 as the legacy codepage and mangles non-ASCII string literal
# terminators.
$ErrorActionPreference = "Stop"

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  Write-Error "Run as Administrator."
  exit 1
}

$here = $PSScriptRoot

# 1. WinFsp (required for VirtIO-FS)
$winfspInstalled = (Test-Path "C:\Program Files\WinFsp\bin\winfsp-x64.dll") -or (Test-Path "C:\Program Files (x86)\WinFsp\bin\winfsp-x64.dll")
if (-not $winfspInstalled) {
  Write-Host "Installing WinFsp..."
  Start-Process msiexec -Wait -ArgumentList "/i `"$here\winfsp.msi`" /qn /norestart"
} else { Write-Host "WinFsp already installed." }

# 2. VirtIO-FS services: one service per mount tag. M: is the whole music
# storage root (Engine Library is a real directory on it) and S: is this
# read-only setup share.
# ponytail: one service per tag; virtiofs.exe handles a single mount per process
$virtiofs = "C:\Program Files\Virtio-Win\viofs\virtiofs.exe"
if (-not (Test-Path $virtiofs)) { Write-Error "virtiofs.exe not found at $virtiofs - install virtio-win-guest-tools first."; exit 1 }

# The cmdlet-based service removal is PowerShell 6+ only; sc.exe works on 5.1.
function Remove-DjService([string]$Name) {
  $service = Get-Service -Name $Name -ErrorAction SilentlyContinue
  if (-not $service) { return }

  if ($service.Status -ne "Stopped") {
    Stop-Service -Name $Name -Force
    $service.WaitForStatus("Stopped", [TimeSpan]::FromSeconds(15))
  }
  sc.exe delete $Name | Out-Null

  # The SCM removes services asynchronously; do not race New-Service.
  for ($attempt = 0; $attempt -lt 20; $attempt++) {
    if (-not (Get-Service -Name $Name -ErrorAction SilentlyContinue)) { return }
    Start-Sleep -Milliseconds 250
  }
  throw "Service $Name is still pending deletion. Reboot and run setup.ps1 again."
}

# The Engine library used to ride a separate L: share behind an M:\Engine
# Library junction; it is now a real directory on M:. Remove the dead share
# services. Deleting a service never touches the library files themselves.
Remove-DjService "VirtioFS-Library"
Remove-DjService "VirtioFS-EngineLibrary"

foreach ($svc in @(
  @{ Name="VirtioFS-Media"; Tag="media"; Letter="M:" },
  @{ Name="VirtioFS-Setup"; Tag="setup"; Letter="S:" }
)) {
  Remove-DjService $svc.Name
  $bin = "`"$virtiofs`" -t $($svc.Tag) -m $($svc.Letter)"
  New-Service -Name $svc.Name -BinaryPathName $bin -DisplayName "VirtIO-FS $($svc.Tag)" -StartupType Automatic | Out-Null
  Start-Service $svc.Name
  Write-Host "Started $($svc.Name) -> $($svc.Letter)"
}

# Remove only the obsolete M:\Engine Library -> L:\ junction. Never remove a
# real Engine Library directory.
$engineLibrary = Get-Item -LiteralPath "M:\Engine Library" -Force -ErrorAction SilentlyContinue
if ($engineLibrary -and (($engineLibrary.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)) {
  cmd /c rmdir "M:\Engine Library" | Out-Null
  Write-Host "Removed legacy M:\Engine Library junction."
}

# 3. Sleep/hibernate - VM must stay awake for Remote Library
powercfg /hibernate off
powercfg /change standby-timeout-ac 0
powercfg /change monitor-timeout-ac 0
Write-Host "Sleep/hibernate disabled."

# 4. Engine library location
# Engine DJ opens its library from the user's Music known-folder
# (%USERPROFILE%\Music\Engine Library). The operator points the Music
# known-folder directly at M:, so M:\Engine Library (a real directory on the
# music share) is what Engine sees. This script deliberately creates no
# junction, symlink, or profile link and never moves library files.
Write-Host "Engine library: point the Windows Music known-folder directly at M: (not a subfolder) so Engine resolves M:\Engine Library."
Write-Host "VERIFY: in Explorer, M:\Engine Library exists on the music share and the Music folder resolves to M:\."

# 5. Mesa OpenGL fallback - fixes "Failed to initialize graphics backend for OpenGL" on virtio-gpu
# opengl32.dll needs libgallium_wgl.dll beside it
$engineExe = Get-ChildItem -Path "C:\Program Files","C:\Program Files (x86)" -Filter "Engine DJ.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
if ($engineExe) {
  foreach ($f in @("opengl32sw.dll","libgallium_wgl.dll","libEGL.dll")) {
    $src = Join-Path $here $f
    $dst = Join-Path $engineExe.DirectoryName $f
    # opengl32.dll hard-override helps if Qt ignores sw fallback
    if ($f -eq "opengl32sw.dll" -and -not (Test-Path $dst)) {
      Copy-Item $src $dst -Force
      Copy-Item $src (Join-Path $engineExe.DirectoryName "opengl32.dll") -Force
      Write-Host "Installed Mesa fallback to $dst + opengl32.dll"
    } elseif ((Test-Path $src) -and -not (Test-Path $dst)) {
      Copy-Item $src $dst -Force
      Write-Host "Installed $f to $dst"
    }
  }
} else { Write-Host "Engine DJ not found - copy $here\opengl32sw.dll + libgallium_wgl.dll to the Engine install dir after installing Engine." }

Write-Host "Done. Reboot recommended, then verify M:\ and S:\ in Explorer."
