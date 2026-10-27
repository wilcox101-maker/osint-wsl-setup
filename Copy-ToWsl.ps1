# Copy-ToWsl.ps1 — run from Windows PowerShell in this folder
# Copies installer + README into the default Ubuntu WSL home.
param(
  [string]$Distro = "Ubuntu",
  [string]$RemoteDir = "osint-src"
)
$ErrorActionPreference = "Stop"
wsl -d $Distro -- mkdir -p "`$HOME/$RemoteDir"
$files = @("install-osint-wsl.sh", "README.md", "Copy-ToWsl.ps1")
foreach ($f in $files) {
  if (-not (Test-Path $f)) { Write-Error "Missing $f in current directory"; exit 1 }
}
# Use wslpath-friendly approach via tar pipe (handles permissions + LF)
tar -cf - @("install-osint-wsl.sh", "README.md") | wsl -d $Distro -- bash -lc "cd ~/$RemoteDir && tar -xf - && chmod +x install-osint-wsl.sh"
Write-Host "Copied to \\wsl$\$Distro\home\<you>\$RemoteDir"
Write-Host "Next: wsl -d $Distro → cd ~/$RemoteDir && bash install-osint-wsl.sh"
