# Preflights the sheets, generates the tables, builds the launcher and lays out dist/.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$dotnet = if ($env:DOTNET) { $env:DOTNET } else { 'dotnet' }
if (-not (Test-Path "$root\.tools\utmt-cli\UndertaleModCli.exe")) { throw 'UndertaleModTool CLI not found: put its 0.9.2.0 command-line build in .tools\utmt-cli (see README.md)' }
python -I "$root\tools\preflight_and_generate.py"
if ($LASTEXITCODE -ne 0) { throw 'preflight failed' }
& $dotnet build "$root\launcher\SonicTower.csproj" -c Release -v q --nologo -o "$root\.build\launcher"
if ($LASTEXITCODE -ne 0) { throw 'launcher build failed' }
$dist = "$root\dist"
if (Test-Path $dist) { Remove-Item -Recurse -Force $dist }
New-Item -ItemType Directory -Force "$dist\patch\gml" | Out-Null
Copy-Item "$root\.build\launcher\SonicTower.exe" $dist
Copy-Item "$root\patch\SonicTowerPatch.csx","$root\patch\hooks.json" "$dist\patch"
Copy-Item "$root\gml\st_main.gml","$root\gml\st_tables.gml" "$dist\patch\gml"
Copy-Item "$root\README.txt","$root\THIRD-PARTY.txt" $dist
# UndertaleModTool's command-line build, unchanged, beside the launcher: a separate GPL-3.0 program it runs.
robocopy "$root\.tools\utmt-cli" "$dist\utmt" /E /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) { throw 'robocopy failed' }
$global:LASTEXITCODE = 0
"dist size MB: " + [math]::Round((Get-ChildItem $dist -Recurse | Measure-Object Length -Sum).Sum/1MB,1)
