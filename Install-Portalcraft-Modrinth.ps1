<#
Puts Portalcraft into a Modrinth App instance.

First, in the Modrinth App: Create an instance named "Portalcraft" with Minecraft 26.3 and the Fabric loader
(0.19.5 or newer). Then run this (Install-Portalcraft-Modrinth.bat): it copies the Portalcraft mod into the
instance's mods folder, and Fabric API too if the instance doesn't have it yet (from Fabric's official Maven,
checksum-verified).

  .\Install-Portalcraft-Modrinth.ps1 [-Instance Portalcraft]
#>
param(
	[switch] $Pause,
	[string] $Instance = 'Portalcraft'
)
$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot
$FabricApi = '0.161.0+26.3'

# Everything below runs inside Main, so that any error is shown (and logged) instead of the window just closing.
$LogDir = Join-Path $PSScriptRoot 'logs'
New-Item -ItemType Directory -Force $LogDir | Out-Null
$Log = Join-Path $LogDir 'install-modrinth.log'

function Get-Sha1([string] $path) { (Get-FileHash $path -Algorithm SHA1).Hash.ToLower() }

function Get-Text([string] $url) {
	$content = (Invoke-WebRequest -UseBasicParsing $url).Content
	if ($content -is [byte[]]) { $content = [System.Text.Encoding]::ASCII.GetString($content) }
	return $content.Trim()
}

function Main {
	$dir = Join-Path $env:APPDATA "ModrinthApp\profiles\$Instance"
	if (-not (Test-Path $dir)) {
		throw "No Modrinth instance named '$Instance' yet. In the Modrinth App: + (Create instance) -> name it $Instance, " +
			"Loader: Fabric, Game version: 26.3 -> Create. Then run this again."
	}
	# (a playtest package has the jar in mods\; a source checkout builds it into mc\build\libs)
	$modJar = Get-ChildItem (Join-Path $Root 'mods') -Filter 'portalcraft-*.jar' -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
	if (-not $modJar) { $modJar = Join-Path $Root 'mc\build\libs\portalcraft-0.1.0.jar' }
	if (-not (Test-Path $modJar)) { throw "build the mod first: $modJar is missing" }
	$mods = Join-Path $dir 'mods'
	New-Item -ItemType Directory -Force $mods | Out-Null
	Get-ChildItem $mods -Filter 'portalcraft-*.jar' | Remove-Item -Force
	Copy-Item $modJar $mods -Force
	Write-Host "copied $(Split-Path $modJar -Leaf) into $mods"

	if (Get-ChildItem $mods -Filter 'fabric-api-*.jar') {
		Write-Host 'Fabric API is already in the instance.'
	} else {
		$apiName = "fabric-api-$FabricApi.jar"
		$apiUrl = "https://maven.fabricmc.net/net/fabricmc/fabric-api/fabric-api/$($FabricApi.Replace('+', '%2B'))/$($apiName.Replace('+', '%2B'))"
		$apiSha1 = Get-Text "$apiUrl.sha1"
		$out = Join-Path $mods $apiName
		$cached = Get-ChildItem (Join-Path $env:USERPROFILE ".gradle\caches\modules-2\files-2.1\net.fabricmc.fabric-api\fabric-api\$FabricApi") -Recurse -Filter $apiName -ErrorAction SilentlyContinue | Select-Object -First 1
		if ($cached -and (Get-Sha1 $cached.FullName) -eq $apiSha1.ToLower()) { Copy-Item $cached.FullName $out }
		else {
			Write-Host "downloading $apiUrl"
			Invoke-WebRequest -UseBasicParsing -Uri $apiUrl -OutFile $out
			if ((Get-Sha1 $out) -ne $apiSha1.ToLower()) { Remove-Item $out; throw "checksum mismatch for $apiUrl" }
		}
		Write-Host "added $apiName"
	}
	# Portal 2's saves, once, before Portalcraft ever runs (tools\portalcraft.ps1 backup-saves; Play does it too)
	try { & (Join-Path $Root 'tools\portalcraft.ps1') backup-saves } catch { Write-Warning "Portal 2's saves weren't backed up: $($_.Exception.Message)" }
	Write-Host ''
	Write-Host "Done. Play with Play-Portalcraft.bat, and start the '$Instance' instance in the Modrinth App when it asks."
}

try {
	Start-Transcript -Path $Log -Force | Out-Null
	Main
}
catch {
	Write-Host ''
	Write-Host "Portalcraft: $($_.Exception.Message)" -ForegroundColor Red
	Write-Host "(full log: $Log)" -ForegroundColor DarkGray
	$script:Failed = $true
}
finally {
	try { Stop-Transcript | Out-Null } catch {}
}
if ($script:Failed -or $Pause) { [void](Read-Host 'Press Enter to close') }
