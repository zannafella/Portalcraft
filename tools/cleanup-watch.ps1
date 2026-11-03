<#
Started hidden by Play-Portalcraft.ps1 right after it puts ReShade into Portal 2's folder: waits for Portal 2 to start
and close again (or for 30 minutes without Portal 2), then takes ReShade out. Keeps working when the Play window is
closed early.
#>
$ErrorActionPreference = 'SilentlyContinue'
$tool = Join-Path $PSScriptRoot 'portalcraft.ps1'
$deadline = (Get-Date).AddMinutes(30)
$p2 = $null
while (-not $p2 -and (Get-Date) -lt $deadline) {
	Start-Sleep -Seconds 2
	$p2 = Get-Process portal2 | Select-Object -First 1
}
if ($p2) { $p2.WaitForExit() }
Start-Sleep -Seconds 3
if (-not (Get-Process portal2)) { & $tool remove | Out-Null }
