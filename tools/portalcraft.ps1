<#
Portalcraft tooling (Windows PowerShell 5.1+).

  .\portalcraft.ps1 deploy            build outputs -> runtime\ (ReShade config, preset, shaders, the add-on)
  .\portalcraft.ps1 install           put ReShade (bin\d3d9.dll) and the two-line ReShade.ini into Portal 2's folder
  .\portalcraft.ps1 remove            take exactly those two files out again
  .\portalcraft.ps1 status            show what is installed
  .\portalcraft.ps1 backup-saves      copy Portal 2's saves (portal2\SAVE) to Documents, once ever (install does it too)
  .\portalcraft.ps1 portal2 [-Map sp_a1_intro3 | -Load savename] [-Windowed]
                                      start Portal 2 through Steam (-insecure: VAC off) with the Portalcraft options
  .\portalcraft.ps1 find              print Portal 2's folder
  .\portalcraft.ps1 launch-options    print Portal 2's launch options in Steam (Steam adds them to every launch)

ReShade's own files never go anywhere but these two places; everything else lives in runtime\.
#>
param(
	[Parameter(Position = 0)] [ValidateSet('deploy', 'install', 'remove', 'status', 'portal2', 'backup-saves', 'find', 'launch-options')] [string] $Action = 'status',
	[string] $Map = '',
	[string] $Load = '',
	[switch] $Windowed,
	[switch] $Vulkan,           # install / portal2: Portal 2 with -vulkan (ReShade goes in front of Portal 2's DXVK)
	[string] $Portal2Dir = '',
	[string] $RuntimeDir = ''   # deploy: another runtime folder (tools\package.ps1 builds a playtest package with it)
)
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Runtime = if ($RuntimeDir) { $RuntimeDir } else { Join-Path $Root 'runtime' }
$ReShadeDll = Join-Path $Root 'third_party\runtime\ReShade32.dll'
# ReShade 6.8.0 add-on build, 32-bit (from ReShade_Setup_6.8.0_Addon.exe, sha256 afe4c8f1...)
$Marker = '; Portalcraft'
# Portal 2 with -vulkan draws through its own DXVK (bin\dxvk_d3d9.dll: Direct3D 9 on Vulkan) and never loads d3d9.dll.
# For a -vulkan session ReShade takes DXVK's file name and hands every Direct3D 9 call on ([PROXY] in
# runtime\ReShade.ini) to runtime\portalcraft_dxvk.dll, which quiets DXVK's log and passes them to DXVK, moved aside
# for the session: the add-on still sees Direct3D 9, the GPU still gets Vulkan. (The DXVK name is also in
# addon\dxvk\dxvk_shim.cpp.)
$DxvkFile = 'bin\dxvk_d3d9.dll'
$DxvkMoved = 'bin\dxvk_d3d9.portalcraft-original.dll'

function Find-Portal2 {
	if ($Portal2Dir) { return $Portal2Dir }
	$steam = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath
	if (-not $steam) { throw 'Steam not found' }
	$libs = @($steam.Replace('/', '\'))
	$vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
	if (Test-Path $vdf) {
		foreach ($m in [regex]::Matches((Get-Content $vdf -Raw), '"path"\s+"([^"]+)"')) { $libs += $m.Groups[1].Value.Replace('\\', '\') }
	}
	$libs = @($libs | Select-Object -Unique)
	# the library Steam installed it in has its manifest (an old copy left in another library doesn't count)
	foreach ($lib in $libs) {
		$acf = Join-Path $lib 'steamapps\appmanifest_620.acf'
		if (Test-Path $acf) {
			$dir = 'Portal 2'
			$m = [regex]::Match((Get-Content $acf -Raw), '"installdir"\s+"([^"]+)"')
			if ($m.Success) { $dir = $m.Groups[1].Value }
			$p = Join-Path $lib "steamapps\common\$dir"
			if (Test-Path (Join-Path $p 'portal2.exe')) { return $p }
		}
	}
	foreach ($lib in $libs) {
		$p = Join-Path $lib 'steamapps\common\Portal 2'
		if (Test-Path (Join-Path $p 'portal2.exe')) { return $p }
	}
	throw 'Portal 2 not found in any Steam library'
}

# Portal 2's launch options in Steam (Properties > Launch options) for the signed-in Steam account, or '' if unknown.
# Steam adds them to every launch, Portalcraft's too.
function Get-Portal2LaunchOptions {
	$steam = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath
	$user = (Get-ItemProperty 'HKCU:\Software\Valve\Steam\ActiveProcess' -ErrorAction SilentlyContinue).ActiveUser
	if (-not $steam -or -not $user) { return '' }
	$cfg = Join-Path $steam "userdata\$user\config\localconfig.vdf"
	if (-not (Test-Path $cfg)) { return '' }
	$text = Get-Content $cfg -Raw
	foreach ($m in [regex]::Matches($text, '"620"\s*\{')) {
		# this app's block, up to its closing brace
		$depth = 0
		for ($i = $m.Index + $m.Length - 1; $i -lt $text.Length; $i++) {
			if ($text[$i] -eq '{') { $depth++ }
			elseif ($text[$i] -eq '}') { $depth--; if ($depth -eq 0) { break } }
		}
		$block = $text.Substring($m.Index, $i - $m.Index)
		$o = [regex]::Match($block, '"LaunchOptions"\s+"((?:[^"\\]|\\.)*)"')
		if ($o.Success) { return $o.Groups[1].Value.Replace('\"', '"').Replace('\\', '\') }
	}
	return ''
}

function Deploy {
	New-Item -ItemType Directory -Force (Join-Path $Runtime 'shaders') | Out-Null
	New-Item -ItemType Directory -Force (Join-Path $Runtime 'cache') | Out-Null
	Copy-Item (Join-Path $Root 'addon\build\portalcraft.addon32') $Runtime -Force
	Copy-Item (Join-Path $Root 'addon\build\portalcraft_dxvk.dll') $Runtime -Force
	Copy-Item (Join-Path $Root 'addon\shaders\Portalcraft.fx') (Join-Path $Runtime 'shaders') -Force
	Copy-Item (Join-Path $Root 'addon\shaders\PortalcraftEarly.hlsl') (Join-Path $Runtime 'shaders') -Force
	Copy-Item (Join-Path $Root 'third_party\shaders\ReShade.fxh') (Join-Path $Runtime 'shaders') -Force
	Copy-Item (Join-Path $Root 'third_party\shaders\ReShadeUI.fxh') (Join-Path $Runtime 'shaders') -Force
	$ini = Join-Path $Runtime 'ReShade.ini'
	if (-not (Test-Path $ini)) {
		@"
[GENERAL]
EffectSearchPaths=.\shaders
TextureSearchPaths=.\shaders
PresetPath=.\PortalcraftPreset.ini
IntermediateCachePath=.\cache
PerformanceMode=0
NoReloadOnInit=0

[INPUT]
KeyOverlay=123,1,0,0
KeyEffects=0,0,0,0
KeyReload=0,0,0,0
KeyScreenshot=0,0,0,0
KeyNextPreset=0,0,0,0
KeyPreviousPreset=0,0,0,0
InputProcessing=2

[OVERLAY]
TutorialProgress=4
ShowClock=0
ShowFPS=0
ShowScreenshotMessage=0
ShowPresetTransitionMessage=0

[DEPTH]
DepthCopyBeforeClears=1
UseAspectRatioHeuristics=1

[ADDON]
AddonPath=.\

[SCREENSHOT]
SavePath=.\screenshots
"@ | Set-Content -Encoding ASCII $ini
	}
	$preset = Join-Path $Runtime 'PortalcraftPreset.ini'
	if (-not (Test-Path $preset)) {
		@"
Techniques=Portalcraft@Portalcraft.fx
TechniqueSorting=Portalcraft@Portalcraft.fx
"@ | Set-Content -Encoding ASCII $preset
	}
	Write-Host "deployed to $Runtime"
}

# Portal 2's saves, copied once (the first time Portalcraft is installed or played) to Documents, where removing
# Portalcraft or Portal 2 doesn't take them along. Never touched again: a backup folder already there means done.
function Backup-Saves {
	$p2 = Find-Portal2
	$save = Join-Path $p2 'portal2\SAVE'
	$dest = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Portal 2 saves (backup before Portalcraft)'
	if (Test-Path $dest) { return }
	$files = @(Get-ChildItem $save -Recurse -File -ErrorAction SilentlyContinue)
	if ($files.Count -eq 0) { Write-Host "Portal 2 has no saves yet: nothing to back up"; return }
	# (copied under another name first: a copy cut short isn't taken for a finished backup next time)
	$partial = "$dest (unfinished)"
	if (Test-Path $partial) { Remove-Item $partial -Recurse -Force }
	New-Item -ItemType Directory -Force $partial | Out-Null
	Copy-Item $save (Join-Path $partial 'SAVE') -Recurse -Force
	$copied = @(Get-ChildItem (Join-Path $partial 'SAVE') -Recurse -File).Count
	if ($copied -lt $files.Count) { throw "backing up Portal 2's saves: copied $copied of $($files.Count) files" }
	$when = Get-Date -Format 'yyyy-MM-dd HH:mm'
	@"
Portal 2's saves as they were on $when, before Portalcraft first ran (copied from $save).
Portalcraft makes this copy once and never changes it. Delete it whenever you like.

To put them back: quit Portal 2, then copy what is in the SAVE folder here into
$save
(the numbered folder is your Steam account; replace the files when asked). Steam Cloud may then ask which saves to
keep: pick the ones on this computer.
"@ | Set-Content -Encoding UTF8 (Join-Path $partial 'README.txt')
	Rename-Item $partial (Split-Path $dest -Leaf)
	Write-Host "backed up Portal 2's saves ($copied files) to $dest (once: it isn't done again)"
}

function Test-IsReShade([string] $path) {
	(Test-Path $path) -and ((Get-FileHash $path -Algorithm SHA256).Hash -eq (Get-FileHash $ReShadeDll -Algorithm SHA256).Hash)
}

# ReShade's [PROXY] section in runtime\ReShade.ini: with a path, ReShade passes Direct3D 9 on to that library (Portal
# 2's DXVK); without one, to Windows' own d3d9.dll as usual.
function Set-ProxyLibrary([string] $path) {
	$ini = Join-Path $Runtime 'ReShade.ini'
	if (-not (Test-Path $ini)) { return }
	$text = [System.IO.File]::ReadAllText($ini)
	$text = [regex]::Replace($text, '(?ms)^\[PROXY\]\r?\n.*?(?=^\[|\z)', '').TrimEnd()
	if ($path) { $text += "`r`n`r`n[PROXY]`r`nEnableProxyLibrary=1`r`nProxyLibrary=$path" }
	[System.IO.File]::WriteAllText($ini, $text + "`r`n", (New-Object System.Text.UTF8Encoding $false))
}

# -vulkan session: ReShade becomes bin\dxvk_d3d9.dll, Portal 2's DXVK waits next to it under another name
function Install-Dxvk([string] $p2) {
	$dx = Join-Path $p2 $DxvkFile
	$moved = Join-Path $p2 $DxvkMoved
	$shim = Join-Path $Runtime 'portalcraft_dxvk.dll'
	if (-not (Test-Path $shim)) { throw "$shim is missing (Portalcraft's go-between for -vulkan): unzip the whole package again" }
	try { Unblock-File $shim } catch {}
	if (-not (Test-Path $dx)) {
		throw "Portal 2's $DxvkFile (its Vulkan renderer) is missing: in Steam, Portal 2 > Properties > Installed Files > Verify integrity, then play again."
	}
	if (Test-IsReShade $dx) {
		if (-not (Test-Path $moved)) {
			throw "Portal 2's $DxvkFile is Portalcraft's ReShade and its own DXVK is gone: in Steam, Portal 2 > Properties > Installed Files > Verify integrity, then play again."
		}
	}
	else {
		# (a moved copy from an earlier session that Steam has since replaced is old: the one in place now wins)
		if (Test-Path $moved) { Remove-Item $moved -Force }
		Move-Item $dx $moved
		Copy-Item $ReShadeDll $dx
	}
	Set-ProxyLibrary $shim
}

# puts Portal 2's DXVK back after a -vulkan session (or one that ended badly)
function Restore-Dxvk([string] $p2) {
	$dx = Join-Path $p2 $DxvkFile
	$moved = Join-Path $p2 $DxvkMoved
	if (Test-Path $moved) {
		if ((Test-Path $dx) -and -not (Test-IsReShade $dx)) {
			# Steam already put DXVK back (an update or a file check): the moved copy is the old one
			Remove-Item $moved -Force
		}
		else {
			if (Test-Path $dx) { Remove-Item $dx -Force }
			Move-Item $moved $dx
			Write-Host "put Portal 2's $DxvkFile back"
		}
	}
	Set-ProxyLibrary ''
}

# Portalcraft's caption folder: one more DLC folder (Portal 2 mounts portal2_dlc1, 2, 3... while they are there, in
# order, each with its gameinfo.txt, and merges each one's resource\subtitles_<language>.dat over the game's). The add-on
# writes caption fixes into it as Portal 2 starts (no portal gun mode's sp_a1_intro7 line). Ours has portalcraft.txt.
function Get-CaptionDlc([string] $p2, [switch] $Create) {
	for ($n = 3; $n -lt 20; $n++) {
		$d = Join-Path $p2 "portal2_dlc$n"
		if (Test-Path (Join-Path $d 'portalcraft.txt')) {
			if ($Create) { Copy-SoundCaches $p2 $n }
			return $d
		}
		if (-not (Test-Path $d)) {
			if (-not $Create) { return $null }
			# (its gameinfo.txt: a copy of the game's own DLC's - without one the folder replaced the game's captions)
			$src = @('portal2_dlc2', 'portal2_dlc1') | ForEach-Object { Join-Path $p2 "$_\gameinfo.txt" } | Where-Object { Test-Path $_ } |
				Select-Object -First 1
			if (-not $src) { return $null }
			New-Item -ItemType Directory -Force (Join-Path $d 'resource') | Out-Null
			Copy-Item $src (Join-Path $d 'gameinfo.txt') -Force
			Copy-SoundCaches $p2 $n
			Set-Content (Join-Path $d 'portalcraft.txt') "Portalcraft's caption fixes (removed again when Portal 2 closes)" -Encoding ascii
			return $d
		}
	}
	return $null
}

# The caption folder's sound caches (maps\soundcache\_master*.cache), copied from the DLC folder before it. Without them
# Portal 2 rebuilds them as it starts and then never leaves the loading screen for the main menu (only a start
# straight into a map gets past it); the rebuilt ones are the same as the previous DLC's anyway.
function Copy-SoundCaches([string] $p2, [int] $n) {
	$to = Join-Path $p2 "portal2_dlc$n\maps\soundcache"
	if (Test-Path (Join-Path $to '_master.cache')) { return }
	for ($m = $n - 1; $m -ge 1; $m--) {
		$from = Join-Path $p2 "portal2_dlc$m\maps\soundcache"
		if (Test-Path (Join-Path $from '_master.cache')) {
			New-Item -ItemType Directory -Force $to | Out-Null
			Get-ChildItem $from -Filter '_master*.cache' | Copy-Item -Destination $to -Force
			return
		}
	}
	Write-Warning "no sound cache to copy into Portalcraft's caption folder: Portal 2 may hang on its loading screen"
}

function Install {
	$p2 = Find-Portal2
	# (a failed backup doesn't stop the install: it is tried again next time)
	try { Backup-Saves } catch { Write-Warning "Portal 2's saves weren't backed up: $($_.Exception.Message)" }
	$dll = Join-Path $p2 'bin\d3d9.dll'
	$ini = Join-Path $p2 'ReShade.ini'
	if ((Test-Path $dll) -and -not (Test-IsReShade $dll)) {
		throw "$dll exists and is not Portalcraft's ReShade: not touching it"
	}
	if ((Test-Path $ini) -and -not ((Get-Content $ini -Raw) -like "*$Marker*")) {
		throw "$ini exists and is not Portalcraft's: not touching it"
	}
	# files unzipped from a download carry Windows' "came from the internet" mark: take it off the two DLLs Portal 2
	# loads (ReShade, the add-on) so nothing blocks them for that
	foreach ($f in @($ReShadeDll, (Join-Path $Runtime 'portalcraft.addon32'))) {
		if (Test-Path $f) { try { Unblock-File $f } catch {} }
	}
	if ($Vulkan) {
		# only the DXVK slot: a second ReShade as d3d9.dll could be loaded by something else as well
		if (Test-Path $dll) { Remove-Item $dll -Force }
		Install-Dxvk $p2
	}
	else {
		Restore-Dxvk $p2
		# (already there: not copied again - Portal 2 holds it while running, and the rest still needs installing)
		if (-not (Test-Path $dll)) { Copy-Item $ReShadeDll $dll -Force }
	}
	# (UTF-8 without a BOM: ReShade reads its paths as UTF-8, and ASCII would mangle a user name with accents)
	[System.IO.File]::WriteAllText($ini, "$Marker (removed again when Portal 2 closes)`r`n[INSTALL]`r`nBasePath=$Runtime`r`n",
		(New-Object System.Text.UTF8Encoding $false))
	# Portalcraft's VScript half (run by the add-on with script_execute portalcraft/portalcraft)
	$vs = Join-Path $p2 'portal2\scripts\vscripts\portalcraft'
	New-Item -ItemType Directory -Force $vs | Out-Null
	Copy-Item (Join-Path $Root 'addon\vscripts\portalcraft.nut') $vs -Force
	# the map Minecraft's own world is played in (sp_mc_overworld, tools\make_overworld_map.py)
	$bsp = Join-Path $Root 'maps\sp_mc_overworld.bsp'
	if (Test-Path $bsp) { Copy-Item $bsp (Join-Path $p2 'portal2\maps\sp_mc_overworld.bsp') -Force }
	$cc = Get-CaptionDlc $p2 -Create
	if (-not $cc) { Write-Warning "no folder for Portalcraft's caption fixes (Portal 2's DLC folders are missing)" }
	$where = if ($Vulkan) { "$DxvkFile in front of Portal 2's DXVK, for -vulkan" } else { 'bin\d3d9.dll' }
	Write-Host "installed ReShade into $p2 ($where, ReShade.ini), portal2\scripts\vscripts\portalcraft\ and portal2\maps\sp_mc_overworld.bsp"
}

function Remove {
	$p2 = Find-Portal2
	$dll = Join-Path $p2 'bin\d3d9.dll'
	$ini = Join-Path $p2 'ReShade.ini'
	if (Test-IsReShade $dll) { Remove-Item $dll -Force; Write-Host "removed $dll" }
	Restore-Dxvk $p2
	if ((Test-Path $ini) -and ((Get-Content $ini -Raw) -like "*$Marker*")) { Remove-Item $ini -Force; Write-Host "removed $ini" }
	$vs = Join-Path $p2 'portal2\scripts\vscripts\portalcraft'
	if (Test-Path $vs) { Remove-Item $vs -Recurse -Force; Write-Host "removed $vs" }
	$map = Join-Path $p2 'portal2\maps\sp_mc_overworld.bsp'
	if (Test-Path $map) { Remove-Item $map -Force; Write-Host "removed $map" }
	$cc = Get-CaptionDlc $p2
	if ($cc) { Remove-Item $cc -Recurse -Force; Write-Host "removed $cc" }
}

function Status {
	$p2 = Find-Portal2
	Write-Host "Portal 2: $p2"
	foreach ($f in @('bin\d3d9.dll', 'ReShade.ini', 'portal2\scripts\vscripts\portalcraft')) {
		$path = Join-Path $p2 $f
		Write-Host ("  {0,-14} {1}" -f $f, $(if (Test-Path $path) { 'present' } else { 'absent' }))
	}
	$dxState = if (Test-Path (Join-Path $p2 $DxvkMoved)) { 'moved aside for a -vulkan session (ReShade in its place)' }
		elseif (Test-IsReShade (Join-Path $p2 $DxvkFile)) { 'ReShade, and Portal 2''s own is missing!' } else { "Portal 2's own" }
	Write-Host "  $DxvkFile $dxState"
	$cc = Get-CaptionDlc $p2
	Write-Host ("  caption fixes: {0}" -f $(if ($cc) { $cc } else { 'absent' }))
	Write-Host ("  portal2.exe running: {0}" -f [bool](Get-Process portal2 -ErrorAction SilentlyContinue))
	$backup = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Portal 2 saves (backup before Portalcraft)'
	Write-Host ("  save backup: {0}" -f $(if (Test-Path $backup) { $backup } else { 'none yet' }))
}

function Start-Portal2 {
	$steam = (Get-ItemProperty 'HKCU:\Software\Valve\Steam').SteamExe
	$launchArgs = @('-applaunch', '620', '-insecure', '-novid', '+sv_cheats', '1', '+con_logfile', 'portalcraft_console.log')
	if ($Vulkan) { $launchArgs += '-vulkan' }
	if ($Windowed) { $launchArgs += @('-windowed', '-noborder', '-w', '1920', '-h', '1080') }
	if ($Map) { $launchArgs += @('+map', $Map) }
	if ($Load) { $launchArgs += @('+load', $Load) }
	Write-Host "starting Portal 2: $steam $($launchArgs -join ' ')"
	Start-Process -FilePath $steam -ArgumentList $launchArgs
}

switch ($Action) {
	'deploy' { Deploy }
	'install' { Install }
	'remove' { Remove }
	'status' { Status }
	'portal2' { Start-Portal2 }
	'backup-saves' { Backup-Saves }
	'find' { Find-Portal2 }
	'launch-options' { Get-Portal2LaunchOptions }
}
