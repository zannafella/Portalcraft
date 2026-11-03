<#
Plays Portalcraft: real Minecraft inside Portal 2.

  1. puts ReShade (with the Portalcraft add-on) into Portal 2's folder for this session,
  2. waits for Minecraft: start the "Portalcraft" installation in the Minecraft Launcher and press Play
     (the launcher opens by itself if Minecraft isn't running yet),
  3. starts Portal 2 through Steam (VAC off with -insecure; single player only),
  4. when Portal 2 closes, Minecraft saves and quits, and ReShade is taken out of Portal 2's folder again.

  .\Play-Portalcraft.ps1 [-Map sp_a1_intro3] [-Windowed] [-Vulkan]

Portal 2 with -vulkan in its Steam launch options (or -Vulkan here) runs on Vulkan: ReShade then goes in front of
Portal 2's own DXVK for the session instead of in front of Windows' Direct3D 9.
#>
param(
	[switch] $Pause,
	[string] $Map = '',
	[switch] $Windowed,
	[switch] $Vulkan
)
$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot
$Tool = Join-Path $Root 'tools\portalcraft.ps1'
Add-Type -AssemblyName System.Core

function Open-Link {
	try { return [System.IO.MemoryMappedFiles.MemoryMappedFile]::OpenExisting('Local\PortalcraftLink') } catch { return $null }
}

function Get-MinecraftBeat($link) {
	$view = $link.CreateViewAccessor(0, 64)
	try { return $view.ReadInt64(24) } finally { $view.Dispose() }
}

function Wait-Minecraft([double] $minutes) {
	$deadline = (Get-Date).AddMinutes($minutes)
	$first = $null
	while ((Get-Date) -lt $deadline) {
		$link = Open-Link
		if ($link) {
			$beat = Get-MinecraftBeat $link
			$link.Dispose()
			if ($null -ne $first -and $beat -ne $first) { return $true }
			$first = $beat
		}
		Start-Sleep -Milliseconds 700
	}
	return $false
}

# Windows 11's Smart App Control: 0 off, 1 on (blocks unsigned DLLs Windows doesn't know, like ReShade's and the
# add-on), 2 evaluation (only watches)
function Get-SmartAppControl {
	try { return [int](Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy' -ErrorAction Stop).VerifiedAndReputablePolicyState }
	catch { return 0 }
}
$SmartAppControlText = ("Windows' Smart App Control is on. It blocks files that aren't signed and that Windows doesn't know, and " +
	"ReShade's DLL and Portalcraft's add-on are both unsigned, so Portal 2 can't load them (Windows may have shown " +
	"'Part of this app has been blocked'). Portalcraft can't run while it is on. It is in Windows Security > App & " +
	"browser control > Smart App Control settings; note that Windows doesn't let you turn it back on afterwards " +
	"without reinstalling Windows, so that is your call.")

function Get-LinkHostPid {
	$link = Open-Link
	if (-not $link) { return 0 }
	try {
		$view = $link.CreateViewAccessor(0, 128)
		try { return $view.ReadUInt32(8) } finally { $view.Dispose() }
	} finally { $link.Dispose() }
}

# Things on this PC that keep Portal 2 from loading ReShade (and so Portalcraft), checked before starting. Returns
# whether Portal 2 will run on Vulkan (-vulkan in its Steam launch options, which Steam adds to every launch).
function Test-Portal2Setup([string] $p2dir) {
	$opts = (& $Tool launch-options | Out-String).Trim()
	Write-Host "Portal 2: $p2dir (launch options in Steam: $(if ($opts) { $opts } else { 'none' }))"
	$vulkan = $opts -match '(^|\s)-vulkan(\s|$)'
	if ($vulkan) { Write-Host "Portal 2 runs on Vulkan (-vulkan): ReShade goes in front of its DXVK for this session." }
	# a d3d9.dll next to portal2.exe (another ReShade, DXVK...) is loaded instead of Portalcraft's ReShade in bin\
	elseif (Test-Path (Join-Path $p2dir 'd3d9.dll')) {
		throw ("Portal 2's folder has a d3d9.dll next to portal2.exe (another mod: ReShade, DXVK or similar). Portal 2 loads " +
			"that one instead of Portalcraft's. Move it out of $p2dir while you play Portalcraft (put it back afterwards for that mod).")
	}
	if ((Get-SmartAppControl) -eq 1) { Write-Warning $SmartAppControlText }
	$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
		[Security.Principal.WindowsBuiltInRole]::Administrator)
	if ($admin) { Write-Warning 'This window runs as administrator. Run Play-Portalcraft.bat, the Modrinth App and Steam normally (all with the same rights).' }
	return [bool]$vulkan
}

# Portal 2 is running but Portalcraft's add-on never joined the link: say why, as far as this PC can tell.
function Show-AddonDiagnosis([string] $p2dir, [datetime] $since, [bool] $vulkan) {
	$log = Join-Path $Root 'runtime\ReShade.log'
	# where ReShade sits this session: in front of Windows' Direct3D 9, or of Portal 2's DXVK (-vulkan)
	$dll = if ($vulkan) { 'bin\dxvk_d3d9.dll' } else { 'bin\d3d9.dll' }
	Write-Host ''
	Write-Host "Portalcraft didn't come on in Portal 2 (its add-on never connected to Minecraft)." -ForegroundColor Yellow
	if ((Get-SmartAppControl) -eq 1) { Write-Host "  $SmartAppControlText" -ForegroundColor Yellow }
	elseif (-not (Test-Path (Join-Path $p2dir $dll))) {
		Write-Host ("  Portal 2's $dll (ReShade, put there by Portalcraft) is gone: an antivirus most likely removed it. " +
			"Restore it from the antivirus' quarantine and allow it, then play again.") -ForegroundColor Yellow
	}
	elseif (-not (Test-Path $log) -or (Get-Item $log).LastWriteTime -lt $since) {
		Write-Host ("  ReShade didn't load in Portal 2 (when it does, a ReShade line shows at the top of the screen as Portal 2 " +
			"starts, and runtime\ReShade.log is written). Most likely an antivirus blocks $dll (allow it), or " +
			"Portal 2 was started by something other than this window.") -ForegroundColor Yellow
	}
	else {
		Write-Host "  ReShade loaded; what it says about Portalcraft (runtime\ReShade.log):" -ForegroundColor Yellow
		Select-String -Path $log -Pattern 'add-on|Portalcraft|ERROR' | Select-Object -Last 15 |
			ForEach-Object { Write-Host "    $($_.Line)" -ForegroundColor Yellow }
	}
	Write-Host "  Please send logs\play.log and runtime\ReShade.log from this folder with your report." -ForegroundColor Yellow
}

function Send-Minecraft([string] $json) {
	$link = Open-Link
	if (-not $link) { return }
	$view = $link.CreateViewAccessor(0, 0x200000)
	try {
		$ring = 0x1000; $slots = 1024; $slotSize = 512
		$head = $view.ReadUInt32($ring)
		$slot = $ring + 64 + ($head % $slots) * $slotSize
		$bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
		$view.Write($slot, [uint32]0)
		$view.Write($slot + 4, [uint32]$bytes.Length)
		$view.WriteArray($slot + 8, $bytes, 0, $bytes.Length)
		$view.Write($slot, [uint32]($head + 1))
		$view.Write($ring, [uint32]($head + 1))
	} finally { $view.Dispose(); $link.Dispose() }
}

# Everything below runs inside Main, so that any error is shown (and logged) instead of the window just closing.
$LogDir = Join-Path $PSScriptRoot 'logs'
New-Item -ItemType Directory -Force $LogDir | Out-Null
$Log = Join-Path $LogDir 'play.log'

function Main {
	if (Get-Process portal2 -ErrorAction SilentlyContinue) { throw 'Portal 2 is already running: close it first.' }

	$p2dir = (& $Tool find | Out-String).Trim()
	$vulkan = (Test-Portal2Setup $p2dir) -or $Vulkan
	& $Tool install -Vulkan:$vulkan
	# takes ReShade out again when Portal 2 closes, even if this window is closed first
	# (Windows PowerShell joins -ArgumentList with spaces as is: the path, which has spaces, needs its own quotes)
	Start-Process powershell -WindowStyle Hidden -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f (Join-Path $Root 'tools\cleanup-watch.ps1'))
	try {
		Write-Host ''
		if (-not (Wait-Minecraft 0.05)) {
			# the Modrinth App when there is a Portalcraft instance (Install-Portalcraft-Modrinth), else the Minecraft Launcher
			$modrinthMods = Join-Path $env:APPDATA 'ModrinthApp\profiles\Portalcraft\mods'
			$modrinthExe = Join-Path $env:LOCALAPPDATA 'Modrinth App\Modrinth App.exe'
			if ((Test-Path $modrinthExe) -and (Get-ChildItem $modrinthMods -Filter 'portalcraft-*.jar' -ErrorAction SilentlyContinue)) {
				Write-Host 'Waiting for Minecraft: in the Modrinth App press Play on the "Portalcraft" instance.'
				if (-not (Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -eq 'Modrinth App' })) { Start-Process $modrinthExe }
			}
			else {
				Write-Host 'Waiting for Minecraft: in the Minecraft Launcher pick "Portalcraft" and press Play.'
				if (-not (Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -in @('Minecraft', 'MinecraftLauncher') })) {
					# the Microsoft Store / Xbox app launcher, else the classic one
					try { Start-Process 'shell:AppsFolder\Microsoft.4297127D64EC6_8wekyb3d8bbwe!Minecraft' } catch {
						$classic = "${env:ProgramFiles(x86)}\Minecraft Launcher\MinecraftLauncher.exe"
						if (Test-Path $classic) { Start-Process $classic }
					}
				}
			}
			Write-Host '(This window keeps waiting: you can start Minecraft from any launcher with the Portalcraft mod.)'
			if (-not (Wait-Minecraft 15)) { throw 'Minecraft with Portalcraft did not start within 15 minutes.' }
		}
		Write-Host 'Minecraft is ready. Starting Portal 2...'

		# (named: splatting an array would pass '-Windowed' along as plain text)
		$portalArgs = @{}
		if ($Map) { $portalArgs.Map = $Map }
		if ($Windowed) { $portalArgs.Windowed = $true }
		if ($vulkan) { $portalArgs.Vulkan = $true }
		$started = Get-Date
		& $Tool portal2 @portalArgs
		$p2 = $null
		for ($i = 0; $i -lt 180 -and -not $p2; $i++) { Start-Sleep -Seconds 1; $p2 = Get-Process portal2 -ErrorAction SilentlyContinue | Select-Object -First 1 }
		if (-not $p2) { throw 'Portal 2 did not start (is Steam running and signed in?)' }
		Write-Host 'Portal 2 is running. Waiting for Portalcraft to come on it...'
		# the add-on joins the link (writes Portal 2's pid into it) within seconds of Portal 2's window appearing
		$on = $false
		for ($i = 0; $i -lt 120 -and -not $on -and -not $p2.HasExited; $i++) {
			Start-Sleep -Seconds 1
			$on = (Get-LinkHostPid) -eq $p2.Id
		}
		if ($on) { Write-Host 'Portalcraft is on in Portal 2. See ya (this window tidies up when Portal 2 closes)' }
		elseif (-not $p2.HasExited) { Show-AddonDiagnosis $p2dir $started $vulkan }
		$p2.WaitForExit()
		Write-Host 'Portal 2 closed: Minecraft saves and quits.'
		Send-Minecraft '{"t":"quit"}'
	}
	finally {
		Start-Sleep -Seconds 2
		& $Tool remove
	}
}

try {
	Start-Transcript -Path $Log -Force | Out-Null
	Main
}
catch {
	Write-Host ''
	Write-Host "Portalcraft: $($_.Exception.Message)" -ForegroundColor Red
	Write-Host "(full log: $Log)" -ForegroundColor DarkGray
	$_ | Format-List * -Force | Out-String | Write-Verbose
	$script:Failed = $true
}
finally {
	try { Stop-Transcript | Out-Null } catch {}
}
if ($script:Failed -or $Pause) { [void](Read-Host 'Press Enter to close') }
