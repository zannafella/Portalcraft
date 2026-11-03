<#
Adds a "Portalcraft" installation to the official Minecraft Launcher (the way Fabric's own installer does), so you
start Minecraft signed in with your own account:

  - Fabric Loader 0.19.5 for Minecraft 26.3 as a launcher version (versions\fabric-loader-0.19.5-26.3),
  - a game folder of its own (default %APPDATA%\.portalcraft) with the Portalcraft mod and Fabric API in mods\,
  - an entry in launcher_profiles.json (backed up first; every existing installation is kept).

  .\Install-Portalcraft.ps1              install / update
  .\Install-Portalcraft.ps1 -Uninstall   remove the installation and the Fabric version (the game folder and its
                                         world stay unless you add -RemoveGameDir)

Close the Minecraft Launcher before running it (it rewrites launcher_profiles.json when it closes).
#>
param(
	[switch] $Pause,
	[string] $GameDir = (Join-Path $env:APPDATA '.portalcraft'),
	[string] $MinecraftDir = (Join-Path $env:APPDATA '.minecraft'),
	[switch] $Uninstall,
	[switch] $RemoveGameDir
)
$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot
$Mc = '26.3'
$Loader = '0.19.5'
$FabricApi = '0.161.0+26.3'
$VersionId = "fabric-loader-$Loader-$Mc"
$ProfileKey = 'portalcraft'
$Profiles = Join-Path $MinecraftDir 'launcher_profiles.json'

function Assert-LauncherClosed {
	$running = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -in @('Minecraft', 'MinecraftLauncher') }
	if ($running) { throw 'The Minecraft Launcher is open. Close it (File > Exit, or the X), then run this again. It rewrites its list of installations when it closes, so it must be closed while Portalcraft adds its installation.' }
}

function Get-Sha1([string] $path) { (Get-FileHash $path -Algorithm SHA1).Hash.ToLower() }

function Get-Text([string] $url) {
	$content = (Invoke-WebRequest -UseBasicParsing $url).Content
	if ($content -is [byte[]]) { $content = [System.Text.Encoding]::ASCII.GetString($content) }
	return $content.Trim()
}

function Save-Download([string] $url, [string] $out, [string] $sha1) {
	Write-Host "downloading $url"
	Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $out
	if ($sha1 -and (Get-Sha1 $out) -ne $sha1.ToLower()) { Remove-Item $out; throw "checksum mismatch for $url" }
}

function Read-Profiles {
	if (-not (Test-Path $Profiles)) { throw "$Profiles not found: start the Minecraft Launcher once, sign in, then close it" }
	return (Get-Content $Profiles -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function Write-Profiles($data, [string[]] $mustKeep) {
	$json = $data | ConvertTo-Json -Depth 32
	$check = $json | ConvertFrom-Json
	foreach ($k in $mustKeep) {
		if (-not ($check.profiles.PSObject.Properties.Name -contains $k)) { throw "refusing to write: installation $k would be lost" }
	}
	[System.IO.File]::WriteAllText($Profiles, $json, (New-Object System.Text.UTF8Encoding($false)))
}

# Everything below runs inside Main, so that any error is shown (and logged) instead of the window just closing.
$LogDir = Join-Path $PSScriptRoot 'logs'
New-Item -ItemType Directory -Force $LogDir | Out-Null
$Log = Join-Path $LogDir 'install.log'

function Main {
	if ($Uninstall) {
		Assert-LauncherClosed
		$data = Read-Profiles
		$keep = @($data.profiles.PSObject.Properties.Name | Where-Object { $_ -ne $ProfileKey })
		Copy-Item $Profiles "$Profiles.portalcraft-backup-$(Get-Date -Format yyyyMMdd-HHmmss)"
		$data.profiles.PSObject.Properties.Remove($ProfileKey)
		Write-Profiles $data $keep
		$vdir = Join-Path $MinecraftDir "versions\$VersionId"
		if (Test-Path $vdir) { Remove-Item $vdir -Recurse -Force }
		if ($RemoveGameDir -and (Test-Path $GameDir)) { Remove-Item $GameDir -Recurse -Force }
		Write-Host 'Portalcraft installation removed.'
		return
	}

	Assert-LauncherClosed

	# 1. the mod
	# (a playtest package has the jar in mods\; a source checkout builds it into mc\build\libs)
	$modJar = Get-ChildItem (Join-Path $Root 'mods') -Filter 'portalcraft-*.jar' -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
	if (-not $modJar) { $modJar = Join-Path $Root 'mc\build\libs\portalcraft-0.1.0.jar' }
	if (-not (Test-Path $modJar)) { throw "build the mod first: $modJar is missing (cd mc; .\gradlew build)" }

	# 2. Fabric Loader's launcher version, from Fabric's meta server; the loader jar itself gets its sha1/size filled in
	#    (Fabric's profile leaves them out, so the launcher would fetch it unchecked)
	$vdir = Join-Path $MinecraftDir "versions\$VersionId"
	New-Item -ItemType Directory -Force $vdir | Out-Null
	$profileJson = Invoke-RestMethod -UseBasicParsing "https://meta.fabricmc.net/v2/versions/loader/$Mc/$Loader/profile/json"
	$loaderUrl = "https://maven.fabricmc.net/net/fabricmc/fabric-loader/$Loader/fabric-loader-$Loader.jar"
	$loaderSha1 = Get-Text "$loaderUrl.sha1"
	$loaderSize = [long](Invoke-WebRequest -UseBasicParsing -Method Head $loaderUrl).Headers['Content-Length']
	foreach ($lib in $profileJson.libraries) {
		if ($lib.name -eq "net.fabricmc:fabric-loader:$Loader") {
			$lib | Add-Member -Force -NotePropertyName sha1 -NotePropertyValue $loaderSha1
			$lib | Add-Member -Force -NotePropertyName size -NotePropertyValue $loaderSize
		}
	}
	[System.IO.File]::WriteAllText((Join-Path $vdir "$VersionId.json"), ($profileJson | ConvertTo-Json -Depth 32), (New-Object System.Text.UTF8Encoding($false)))
	$emptyJar = Join-Path $vdir "$VersionId.jar"
	if (-not (Test-Path $emptyJar)) { [System.IO.File]::WriteAllBytes($emptyJar, [byte[]]@()) }

	# 3. the game folder: Portalcraft + Fabric API
	$mods = Join-Path $GameDir 'mods'
	New-Item -ItemType Directory -Force $mods | Out-Null
	Get-ChildItem $mods -Filter 'portalcraft-*.jar' | Remove-Item -Force
	Copy-Item $modJar $mods -Force
	$apiName = "fabric-api-$FabricApi.jar"
	$apiOut = Join-Path $mods $apiName
	if (-not (Test-Path $apiOut)) {
		Get-ChildItem $mods -Filter 'fabric-api-*.jar' | Remove-Item -Force
		$apiUrl = "https://maven.fabricmc.net/net/fabricmc/fabric-api/fabric-api/$($FabricApi.Replace('+', '%2B'))/$($apiName.Replace('+', '%2B'))"
		$apiSha1 = Get-Text "$apiUrl.sha1"
		$cached = Get-ChildItem (Join-Path $env:USERPROFILE ".gradle\caches\modules-2\files-2.1\net.fabricmc.fabric-api\fabric-api\$FabricApi") -Recurse -Filter $apiName -ErrorAction SilentlyContinue | Select-Object -First 1
		if ($cached -and (Get-Sha1 $cached.FullName) -eq $apiSha1.ToLower()) { Copy-Item $cached.FullName $apiOut }
		else { Save-Download $apiUrl $apiOut $apiSha1 }
	}

	# 4. the launcher installation
	$data = Read-Profiles
	$keep = @($data.profiles.PSObject.Properties.Name | Where-Object { $_ -ne $ProfileKey })
	Copy-Item $Profiles "$Profiles.portalcraft-backup-$(Get-Date -Format yyyyMMdd-HHmmss)"
	$now = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
	# the launcher splits these at spaces: keep each option space-free
	$javaArgs = '-Xms2G -Xmx4G -XX:+UseZGC --enable-native-access=ALL-UNNAMED'
	# Fabric's mods folder spelled out: in the first test the launcher started the game in the game folder but Fabric
	# found no mods there (cause unknown). Only when the path has no spaces.
	$modsPath = Join-Path $GameDir 'mods'
	if ($modsPath -notmatch ' ') { $javaArgs += " -Dfabric.modsFolder=$modsPath" }
	$entry = [ordered]@{
		created = $now
		gameDir = $GameDir
		icon = 'Crafting_Table'
		javaArgs = $javaArgs
		lastUsed = $now
		lastVersionId = $VersionId
		name = 'Portalcraft'
		type = 'custom'
	}
	$data.profiles | Add-Member -Force -NotePropertyName $ProfileKey -NotePropertyValue ([PSCustomObject]$entry)
	Write-Profiles $data $keep
	# Portal 2's saves, once, before Portalcraft ever runs (tools\portalcraft.ps1 backup-saves; Play does it too)
	try { & (Join-Path $Root 'tools\portalcraft.ps1') backup-saves } catch { Write-Warning "Portal 2's saves weren't backed up: $($_.Exception.Message)" }

	Write-Host ''
	Write-Host "Installed: 'Portalcraft' in the Minecraft Launcher (Fabric $Loader for $Mc), game folder $GameDir"
	Write-Host 'Next: run Play-Portalcraft.ps1 (or Play-Portalcraft.bat).'
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
