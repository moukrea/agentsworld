# AgentsWorld installer for Windows 10/11. Read it before running it.
#
#   irm https://moukrea.github.io/agentsworld/install.ps1 | iex                         the app (asks when it can)
#   & ([scriptblock]::Create((irm https://moukrea.github.io/agentsworld/install.ps1))) -ClientOnly
#   & ([scriptblock]::Create((irm https://moukrea.github.io/agentsworld/install.ps1))) -Host
#   & ([scriptblock]::Create((irm https://moukrea.github.io/agentsworld/install.ps1))) -Agent -Hub URL -Token TOKEN
#
# The same roles as install.sh. Everything goes into the user's profile, without administrator rights: the app
# through its per-user installer, the host and the agent under %LOCALAPPDATA%\agentsworld-cli (Node runtime, data,
# logs, the `agentsworld` command) and a scheduled task started at logon. Every download comes from a release of
# github.com/moukrea/agentsworld and is checked against that release's SHA256SUMS before anything is replaced.
# Running it again upgrades what is installed; `agentsworld update` does exactly that.
# (No typographic quotes in this file: PowerShell reads them as quotes.)
param(
  [switch]$App, [switch]$ClientOnly, [Alias('Host')][switch]$HostRole, [switch]$Agent,
  [string]$Hub = '', [string]$Token = '', [string]$Name = '',
  [int]$Port = 0, [int]$LinkPort = 0, [string]$Relay = '', [string]$Bind = '', [string]$Version = '',
  [switch]$NoService, [switch]$NoPair, [switch]$Yes
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
function Say($text) { Write-Host "`n  AgentsWorld - $text" }
function Info($text) { Write-Host "  $text" }
function Warn($text) { Write-Host "  ! $text" -ForegroundColor Yellow }
# Failures throw: `exit` would close the PowerShell window that ran `irm ... | iex`.
function Fail($text) { throw $text }
function Setting($name, $default) { $v = [Environment]::GetEnvironmentVariable($name); if ($v) { $v } else { $default } }
function Quiet([scriptblock]$command) {
  $previous = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  try { & $command 2>$null } catch { } finally { $ErrorActionPreference = $previous }
}
function WriteUtf8($path, $text) { [IO.File]::WriteAllText($path, $text, (New-Object Text.UTF8Encoding $false)) }

Say 'Installation'
if ([Environment]::OSVersion.Version.Build -lt 17763) { Fail 'Windows 10 version 1809 ou plus est necessaire.' }
$Local = Setting 'LOCALAPPDATA' (Join-Path $HOME 'AppData\Local')
$Roaming = Setting 'APPDATA' (Join-Path $HOME 'AppData\Roaming')
$Page = (Setting 'AGENTSWORLD_PAGE_URL' 'https://moukrea.github.io/agentsworld').TrimEnd('/')
$Repo = Setting 'AGENTSWORLD_REPO' 'moukrea/agentsworld'
$Dev = (Setting 'AGENTSWORLD_DEV_INSTALL' '0') -eq '1'
# Not %LOCALAPPDATA%\AgentsWorld: the app's own installer owns that directory (and its uninstaller removes it).
$Prefix = Setting 'AGENTSWORLD_PREFIX' (Join-Path $Local 'agentsworld-cli')
$Bin = Join-Path $Prefix 'bin'
$HostData = Setting 'AGENTSWORLD_HOST_DATA' (Join-Path $Prefix 'host')
$DesktopHome = Setting 'AGENTSWORLD_DESKTOP_HOME' (Join-Path $Roaming 'io.github.moukrea.agentsworld')
$Record = Join-Path $Prefix 'install.json'
$AgentEnv = Join-Path $Prefix 'agent.env'
$Runtime = Join-Path $Prefix 'runtime'
$Rt = Join-Path $Runtime 'current'
$Tasks = @{ host = 'AgentsWorld host'; agent = 'AgentsWorld agent' }
if ($Repo -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') { Fail 'Nom de depot invalide.' }
New-Item -ItemType Directory -Force -Path $Prefix, $Bin | Out-Null
$Tmp = Join-Path $Prefix (".install." + [Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $Tmp | Out-Null

try {
  $old = $null
  if (Test-Path $Record) { try { $old = Get-Content $Record -Raw | ConvertFrom-Json } catch { $old = $null } }
  $Installed = @(); if ($old -and $old.roles) { $Installed = @($old.roles) }
  if ($old -and $old.service -eq 'none' -and $Installed.Count) { $NoService = $true }
  if ((Setting 'AGENTSWORLD_NO_SERVICE' '0') -eq '1') { $NoService = $true }
  if ((Setting 'AGENTSWORLD_SKIP_PAIR' '0') -eq '1') { $NoPair = $true }

  # --- Role ---------------------------------------------------------------------------------------------------
  $chosen = @()
  if ($App) { $chosen += 'app' }; if ($ClientOnly) { $chosen += 'client-only' }
  if ($HostRole) { $chosen += 'host' }; if ($Agent) { $chosen += 'agent' }
  if ($chosen.Count -gt 1) { Fail "Un seul role a la fois ($($chosen -join ', '))." }
  $JauntDir = Join-Path $Local 'jaunt'
  $Jaunt = [bool](Get-Command jaunt -ErrorAction SilentlyContinue) -or (Test-Path $JauntDir)
  $Interactive = [Environment]::UserInteractive -and -not $Yes -and -not ([Environment]::GetCommandLineArgs() -match '^-NonInteractive$')
  if ($chosen.Count -eq 1) { $Roles = $chosen }
  elseif ($Installed.Count -and -not $Interactive) { $Roles = $Installed }
  elseif ($Interactive) {
    $recommended = if ($Installed.Count) { '0' } else { '1' }
    Write-Host "`n  Que faut-il installer sur cette machine ?`n"
    if ($Installed.Count) { Write-Host "  0) Mettre a jour ce qui est installe ($($Installed -join ' '))" }
    Write-Host '  1) L''application : au premier lancement, tu choisis d''heberger le monde ici ou de rejoindre un hote.'
    Write-Host '  2) Client seulement : l''application pour rejoindre un hote, sans hote sur cette machine.'
    Write-Host '  3) Hote sans ecran : le monde tourne en tache planifiee (machine toujours allumee), sans application.'
    Write-Host "  4) Agent : cette machine envoie ses sessions a un hote qui n'a pas Jaunt.`n"
    if ($Jaunt) {
      Write-Host '  Jaunt est installe ici. Avec Jaunt, UN SEUL hote, sur une de tes machines reliees a Jaunt, voit les'
      Write-Host '  sessions de toutes tes machines liees : les autres n''ont besoin que du client (2), ou de rien.'
      Write-Host '  L''agent (4) est inutile avec Jaunt.'
    } else {
      Write-Host '  Jaunt n''est pas installe ici. Sans Jaunt, chaque machine dont tu veux voir les sessions a besoin de'
      Write-Host '  l''agent (4), sauf l''hote lui-meme. Avec Jaunt (https://github.com/moukrea/jaunt), un seul hote suffit.'
    }
    $choice = (Read-Host "  Ton choix [$recommended]").Trim(); if (-not $choice) { $choice = $recommended }
    switch ($choice) {
      '0' { if (-not $Installed.Count) { Fail 'Rien n''est installe.' }; $Roles = $Installed }
      '1' { $Roles = @('app') } '2' { $Roles = @('client-only') } '3' { $Roles = @('host') } '4' { $Roles = @('agent') }
      default { Fail "Choix inconnu : $choice" }
    }
  } else { $Roles = @('app') }

  if ($Roles -contains 'agent') {
    $envOld = @{}
    if (Test-Path $AgentEnv) { foreach ($line in Get-Content $AgentEnv) { if ($line -match '^([A-Z_]+)=(.*)$') { $envOld[$Matches[1]] = $Matches[2] } } }
    if (-not $Hub) { $Hub = [string]$envOld['AGENTSWORLD_HUB'] }
    if (-not $Token) { $Token = [string]$envOld['AGENTSWORLD_TOKEN'] }
    if (-not $Name) { $Name = [string]$envOld['AGENTSWORLD_MACHINE_NAME'] }
    if (-not $Hub -and $Interactive) { $Hub = (Read-Host '  Adresse de l''hote (http://machine:4317)').Trim() }
    if (-not $Token -and $Interactive) {
      $secure = Read-Host '  Jeton de l''agent (agentsworld agent-token create sur l''hote)' -AsSecureString
      $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
      try { $Token = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr).Trim() } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
    }
    if (-not $Hub -or -not $Token) { Fail 'L''agent a besoin de -Hub URL et -Token JETON (agentsworld agent-token create <nom> sur l''hote les donne).' }
    if ($Token -cnotmatch '^[A-Za-z0-9_-]{16,200}$') { Fail 'Jeton invalide.' }
    if ($Hub -notmatch '^(https?|wss?)://[\]\[A-Za-z0-9._~:@%/?=&+-]+$') { Fail 'Adresse de l''hote invalide (http://machine:4317).' }
    if ($Name -and $Name -notmatch '^[^"`$\r\n]{1,64}$') { Fail 'Nom de machine invalide.' }
    if ($Jaunt) { Warn 'Jaunt est installe ici : un hote relie a Jaunt voit deja cette machine si elle est liee. L''agent sert aux machines sans Jaunt.' }
  }
  foreach ($p in $Port, $LinkPort) { if ($p -lt 0 -or $p -gt 65535) { Fail "Port invalide : $p" } }
  if ($Bind -and $Bind -notmatch '^([0-9]{1,3}(\.[0-9]{1,3}){3}|::|::1)$') { Fail "Adresse d'ecoute invalide : $Bind" }
  if ($Relay -and $Relay -notmatch '^wss://[A-Za-z0-9.-]+(:[0-9]+)?(/[A-Za-z0-9._~/-]*)?$' -and -not ($Dev -and $Relay -match '^ws://(127\.0\.0\.1|localhost)(:[0-9]+)?/?$')) {
    Fail 'Relais invalide : wss://machine[/chemin].'
  }

  # --- Release ------------------------------------------------------------------------------------------------
  function Fetch($url, $destination) {
    if ($url -notmatch '^https://' -and -not ($Dev -and $url -match '^http://(127\.0\.0\.1|localhost):')) { Fail "Telechargement refuse (HTTPS seulement) : $url" }
    Write-Host "  - $(Split-Path $url -Leaf)"
    Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $destination -Headers @{ 'User-Agent' = 'AgentsWorld-Installer/1' } -TimeoutSec 900
  }
  $Want = Setting 'AGENTSWORLD_VERSION' $Version
  if (-not $Want) {
    Fetch "$Page/config.json" (Join-Path $Tmp 'config.json')
    $config = [IO.File]::ReadAllText((Join-Path $Tmp 'config.json')) | ConvertFrom-Json
    if ($config.version -ne 1) { Fail 'config.json de la page : format inconnu.' }
    $Want = [string]$config.release
  }
  $Tag = if ($Want.StartsWith('v')) { $Want } else { "v$Want" }
  if ($Tag -notmatch '^v[0-9]+\.[0-9]+\.[0-9]+$') { Fail "Version invalide : $Tag" }
  $V = $Tag.Substring(1)
  $Base = (Setting 'AGENTSWORLD_RELEASE_BASE' "https://github.com/$Repo/releases/download/$Tag").TrimEnd('/')
  Say "Version $Tag ($($Roles -join ' '))"
  Fetch "$Base/SHA256SUMS" (Join-Path $Tmp 'SHA256SUMS')
  $Sums = @{}
  foreach ($line in [IO.File]::ReadAllLines((Join-Path $Tmp 'SHA256SUMS'))) {
    if ($line -match '^([0-9a-f]{64}) [ *](.+)$') { $Sums[$Matches[2]] = $Matches[1] }
  }
  # Download one release asset and check it against SHA256SUMS; nothing unverified is kept.
  function Asset($name) {
    $expected = $Sums[$name]
    if (-not $expected) { Fail "$name n'est pas dans SHA256SUMS de $Tag (cette version ne le publie pas)." }
    $file = Join-Path $Tmp $name
    Fetch "$Base/$name" $file
    $digest = (Get-FileHash -Algorithm SHA256 -Path $file).Hash.ToLowerInvariant()
    if ($digest -ne $expected) { Remove-Item -Force $file; Fail "Somme SHA-256 incorrecte pour $name : rien n'a ete installe." }
    Write-Host '    SHA-256 verifie'
    return $file
  }

  # --- Runtime, services -------------------------------------------------------------------------------------
  function Stop-Role($role) {
    Quiet { Stop-ScheduledTask -TaskName $Tasks[$role] -ErrorAction Stop } | Out-Null
    $script = if ($role -eq 'host') { 'agentsworld-server.mjs' } else { 'agentsworld-agent.mjs' }
    Get-CimInstance Win32_Process -Filter "Name = 'node.exe'" -ErrorAction SilentlyContinue |
      Where-Object { $_.CommandLine -and $_.CommandLine.Contains($Prefix) -and $_.CommandLine.Contains($script) } |
      ForEach-Object { Quiet { Stop-Process -Id $_.ProcessId -Force } }
  }
  function Install-Runtime {
    $current = Join-Path $Rt 'VERSION'
    if ((Test-Path $current) -and ((Get-Content $current -Raw).Trim() -eq $V) -and (Setting 'AGENTSWORLD_REINSTALL' '0') -ne '1') {
      Info "Moteur $V deja en place."; return
    }
    $zip = Asset "agentsworld-host_${V}_windows-x64.zip"
    $target = Join-Path $Runtime ("versions\$Tag-" + [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() + "-$PID")
    New-Item -ItemType Directory -Force -Path $target | Out-Null
    Expand-Archive -Path $zip -DestinationPath $target -Force
    $nodeVersion = Quiet { & (Join-Path $target 'bin\node.exe') --version }
    if (-not $nodeVersion -or -not (Test-Path (Join-Path $target 'server\agentsworld-server.mjs'))) {
      Remove-Item -Recurse -Force $target; Fail 'Le moteur ne demarre pas sur ce systeme.'
    }
    foreach ($role in 'host', 'agent') { if ($Installed -contains $role) { Stop-Role $role } }
    if (Test-Path $Rt) { cmd /c rmdir "$Rt" | Out-Null }
    New-Item -ItemType Junction -Path $Rt -Target $target | Out-Null
    # Keep the current runtime and one previous one.
    Get-ChildItem (Join-Path $Runtime 'versions') -Directory | Sort-Object LastWriteTime -Descending | Select-Object -Skip 2 |
      Where-Object { $_.FullName -ne $target } | ForEach-Object { Remove-Item -Recurse -Force $_.FullName -ErrorAction SilentlyContinue }
    Info "Moteur $V installe (Node $nodeVersion)."
  }
  # The script a role's scheduled task runs, hidden: Node with its output appended to <prefix>\<role>.log.
  function Write-RunScript($role) {
    $log = Join-Path $Prefix "$role.log"
    if ($role -eq 'host') {
      $envLines = "`$env:AGENTSWORLD_DATA = '$($HostData.Replace("'", "''"))'"
      $cmdline = "`"$Rt\bin\node.exe`" --preserve-symlinks-main `"$Rt\server\agentsworld-server.mjs`" --config `"$HostData\config.json`" >> `"$log`" 2>&1"
    } else {
      $envLines = "foreach (`$line in Get-Content '$($AgentEnv.Replace("'", "''"))') { if (`$line -match '^([A-Z_]+)=(.*)`$') { [Environment]::SetEnvironmentVariable(`$Matches[1], `$Matches[2], 'Process') } }"
      $cmdline = "`"$Rt\bin\node.exe`" --preserve-symlinks-main `"$Rt\agent\agentsworld-agent.mjs`" >> `"$log`" 2>&1"
    }
    $body = @"
# Written by install.ps1: runs the AgentsWorld $role hidden, its output appended to $log.
`$ErrorActionPreference = 'Continue'
$envLines
`$env:NODE_NO_WARNINGS = '1'
`$p = Start-Process -FilePath cmd.exe -ArgumentList '/d /c "$($cmdline.Replace("'", "''"))"' -WindowStyle Hidden -PassThru -Wait
exit `$p.ExitCode
"@
    $file = Join-Path $Prefix "$role-run.ps1"
    WriteUtf8 $file $body
    return $file
  }
  function Start-Role($role) {
    $run = Write-RunScript $role
    $arguments = "-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$run`""
    Stop-Role $role
    if (-not $NoService) {
      try {
        $user = "$env:USERDOMAIN\$env:USERNAME"
        $a = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $arguments -WorkingDirectory $Prefix
        $t = New-ScheduledTaskTrigger -AtLogOn -User $user
        $s = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable `
          -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -MultipleInstances IgnoreNew
        $pr = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
        Register-ScheduledTask -TaskName $Tasks[$role] -Action $a -Trigger $t -Settings $s -Principal $pr -Force | Out-Null
        Start-ScheduledTask -TaskName $Tasks[$role]
        $script:Service = 'task'
        return
      } catch {
        Warn "Pas de tache planifiee ($($_.Exception.Message)) : demarrage en arriere-plan."
      }
    }
    Start-Process -FilePath powershell.exe -ArgumentList $arguments -WindowStyle Hidden | Out-Null
    $script:Service = 'none'
    Info 'Demarre en arriere-plan (pas de tache planifiee : a relancer apres un redemarrage avec agentsworld start).'
  }
  function Wait-Host($port) {
    for ($i = 0; $i -lt 60; $i++) {
      try { Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$port/api/health" -TimeoutSec 2 | Out-Null; return $true } catch { Start-Sleep -Seconds 1 }
    }
    return $false
  }
  $script:Service = if ($NoService) { 'none' } else { 'task' }

  # The host's config.json, by the runtime's Node (the same script as install.sh): kept across updates, the options
  # given now replace its values, and both ports must be free when the host is not running yet.
  $HostConfigJs = @'
const fs = require("fs"), net = require("net");
const [file, port, linkPort, relay, running, bind, jaunt] = process.argv.slice(2);
let config = {};
try { config = JSON.parse(fs.readFileSync(file, "utf8")); } catch (error) { if (error.code !== "ENOENT") throw error; }
const fresh = Object.keys(config).length === 0;
config.link = {...(config.link ?? {})};
// With Jaunt, agents are useless: the world stays on this machine (devices use Link). Without, agents need HTTP.
if (fresh) { config.port = 4317; config.bind = jaunt === "1" ? "127.0.0.1" : "0.0.0.0"; config.link = {enabled: true, port: 4318, relays: []}; }
if (bind !== "-") config.bind = bind;
if (port !== "0") config.port = Number(port);
if (linkPort !== "0") config.link.port = Number(linkPort);
if (relay && relay !== "-") config.link.relays = [relay];
const free = (p) => new Promise((resolve) => {
  const s = net.createServer();
  s.once("error", () => resolve(false));
  s.listen(p, "0.0.0.0", () => s.close(() => resolve(true)));
});
(async () => {
  const http = config.port ?? 4317, link = config.link?.port ?? 4318;
  if (running !== "1") {
    if (!(await free(http))) { console.error(`Le port ${http} est deja pris sur cette machine. Choisis-en un autre : -Port N.`); process.exit(3); }
    if (!(await free(link))) { console.error(`Le port Link ${link} est deja pris sur cette machine. Choisis-en un autre : -LinkPort N.`); process.exit(3); }
  }
  if (fresh || port !== "0" || linkPort !== "0" || (relay && relay !== "-") || bind !== "-") {
    fs.writeFileSync(file + ".new", JSON.stringify(config, null, 2) + "\n");
    fs.renameSync(file + ".new", file);
  }
  console.log(`${http} ${link}`);
})();
'@

  $HostPort = if ($old) { [string]$old.hostPort } else { '' }
  $AppPath = if ($old) { [string]$old.appPath } else { '' }
  function Install-Host {
    Install-Runtime
    New-Item -ItemType Directory -Force -Path $HostData | Out-Null
    $running = '0'
    try { Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$(if ($HostPort) { $HostPort } else { 4317 })/api/health" -TimeoutSec 2 | Out-Null
      if ($Installed -contains 'host') { $running = '1' } } catch { }
    $js = Join-Path $Tmp 'host-config.js'; WriteUtf8 $js $HostConfigJs
    # Never an empty argument: Windows PowerShell drops them when it calls a program.
    $ports = & (Join-Path $Rt 'bin\node.exe') $js (Join-Path $HostData 'config.json') "$Port" "$LinkPort" $(if ($Relay) { $Relay } else { '-' }) $running $(if ($Bind) { $Bind } else { '-' }) $(if ($Jaunt) { '1' } else { '0' })
    if ($LASTEXITCODE) { Fail 'Rien n''a ete demarre.' }
    $http, $link = ([string]$ports).Trim() -split ' '
    Start-Role 'host'
    $script:HostPort = $http
    if (-not (Wait-Host $http)) {
      if ($script:Service -eq 'task') {
        # A task that cannot run now (no interactive logon, e.g. a CI runner) starts at the next logon: run it now.
        Warn 'La tache planifiee ne demarre pas maintenant : demarrage direct en arriere-plan (la tache prendra le relais a la prochaine ouverture de session).'
        Start-Process -FilePath powershell.exe -ArgumentList "-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$(Join-Path $Prefix 'host-run.ps1')`"" -WindowStyle Hidden | Out-Null
      }
      if (-not (Wait-Host $http)) { Fail "L'hote ne repond pas sur le port $http apres 60 s : agentsworld logs host." }
    }
    Info "Hote en marche : http://127.0.0.1:$http (appareils : port Link $link)."
  }
  function Install-Agent {
    Install-Runtime
    $lines = @("AGENTSWORLD_HUB=$Hub", "AGENTSWORLD_TOKEN=$Token")
    if ($Name) { $lines += "AGENTSWORLD_MACHINE_NAME=$Name" }
    WriteUtf8 $AgentEnv (($lines -join "`r`n") + "`r`n")
    Start-Role 'agent'
    Info "Agent en marche : il envoie les sessions de cette machine a $Hub."
  }
  function Install-App([bool]$clientOnlyMode) {
    $setup = Asset "AgentsWorld_${V}_x64-setup.exe"
    Info 'Installation de l''application (installateur par utilisateur, sans droits administrateur)...'
    $p = Start-Process -FilePath $setup -ArgumentList '/S' -PassThru -Wait
    if ($p.ExitCode) { Fail "L'installateur de l'application a echoue (code $($p.ExitCode))." }
    $script:AppPath = Join-Path $Local 'AgentsWorld\agentsworld.exe'
    New-Item -ItemType Directory -Force -Path $DesktopHome | Out-Null
    $desktopFile = Join-Path $DesktopHome 'desktop.json'
    if ($clientOnlyMode) { WriteUtf8 $desktopFile "{`n  `"mode`": `"join`",`n  `"clientOnly`": true`n}`n" }
    else {
      $mode = $null
      if (Test-Path $desktopFile) { try { $mode = ([IO.File]::ReadAllText($desktopFile) | ConvertFrom-Json).mode } catch { } }
      $value = if ($mode -eq 'host' -or $mode -eq 'join') { "`"$mode`"" } else { 'null' }
      WriteUtf8 $desktopFile "{`n  `"mode`": $value`n}`n"
    }
    if ($clientOnlyMode) { Info "Application installee en client seul : $($script:AppPath)" } else { Info "Application installee : $($script:AppPath)" }
  }

  # --- Install ------------------------------------------------------------------------------------------------
  $All = [Collections.ArrayList]@($Installed)
  foreach ($role in $Roles) {
    switch ($role) {
      'app' { Install-App $false; $All.Remove('client-only'); if (-not $All.Contains('app')) { [void]$All.Add('app') } }
      'client-only' { Install-App $true; $All.Remove('app'); if (-not $All.Contains('client-only')) { [void]$All.Add('client-only') } }
      'host' { Install-Host; if (-not $All.Contains('host')) { [void]$All.Add('host') } }
      'agent' { Install-Agent; if (-not $All.Contains('agent')) { [void]$All.Add('agent') } }
      default { Fail "Role inconnu dans install.json : $role" }
    }
  }
  $recordJson = [ordered]@{ roles = @($All); version = $Tag; page = $Page; repo = $Repo; service = $script:Service
    hostData = $HostData; hostPort = $script:HostPort; appPath = $script:AppPath; desktopHome = $DesktopHome; prefix = $Prefix } | ConvertTo-Json
  WriteUtf8 $Record $recordJson

  # --- The agentsworld command --------------------------------------------------------------------------------
  $cli = @'
# The agentsworld command, written by install.ps1. Run: agentsworld help
# No param block: options such as --rights or --purge reach $args as they are.
$Command = if ($args.Count) { [string]$args[0] } else { 'help' }
$Rest = @($args | Select-Object -Skip 1)
$ErrorActionPreference = 'Continue'
$Prefix = Split-Path -Parent $PSScriptRoot
$Record = Join-Path $Prefix 'install.json'
if (-not (Test-Path $Record)) { Write-Error "AgentsWorld n'est pas installe ici ($Record manquant)."; exit 1 }
$R = Get-Content $Record -Raw | ConvertFrom-Json
$Roles = @($R.roles)
$Rt = Join-Path $Prefix 'runtime\current'
$Tasks = @{ host = 'AgentsWorld host'; agent = 'AgentsWorld agent' }
function Has($role) { $Roles -contains $role }
function NodeCli {
  if (-not (Test-Path (Join-Path $Rt 'bin\node.exe'))) { Write-Host "Cette commande demande l'hote (agentsworld role add host)."; exit 1 }
  $env:AGENTSWORLD_DATA = $R.hostData; $env:AGENTSWORLD_CONFIG = Join-Path $R.hostData 'config.json'; $env:NODE_NO_WARNINGS = '1'
  # A statement, not a value: Node keeps the console (the QR code's colours), $LASTEXITCODE says how it went.
  & (Join-Path $Rt 'bin\node.exe') --preserve-symlinks-main (Join-Path $Rt 'cli\agentsworld.mjs') @args
}
function NeedHost { if (-not (Has 'host')) { Write-Host "Pas d'hote sans ecran ici. Dans l'application : Reglages > Appareil. Ou : agentsworld role add host"; exit 1 } }
function ServiceRoles($only) { if ($only) { @($only) } else { @('host', 'agent') | Where-Object { Has $_ } } }
function StopRole($role) {
  try { Stop-ScheduledTask -TaskName $Tasks[$role] -ErrorAction Stop } catch { }
  $script = if ($role -eq 'host') { 'agentsworld-server.mjs' } else { 'agentsworld-agent.mjs' }
  Get-CimInstance Win32_Process -Filter "Name = 'node.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -and $_.CommandLine.Contains($Prefix) -and $_.CommandLine.Contains($script) } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
}
function StartRole($role) {
  $run = Join-Path $Prefix "$role-run.ps1"
  if ($R.service -eq 'task') { try { Start-ScheduledTask -TaskName $Tasks[$role] -ErrorAction Stop; return } catch { } }
  Start-Process -FilePath powershell.exe -ArgumentList "-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$run`"" -WindowStyle Hidden | Out-Null
}
# Run install.ps1 with these parameters (a hashtable: a '-Host' string would not bind as a switch).
function Installer($splat) {
  $script = [Environment]::GetEnvironmentVariable('AGENTSWORLD_INSTALLER')
  if ($script) {
    $list = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $script)
    foreach ($key in $splat.Keys) { if ($splat[$key] -is [bool]) { $list += "-$key" } else { $list += @("-$key", [string]$splat[$key]) } }
    & powershell.exe @list
    return
  }
  & ([scriptblock]::Create((Invoke-RestMethod "$($R.page)/install.ps1"))) @splat
}
# --hub X --token Y ... (as install.sh takes them) into install.ps1 parameters.
function Options($words) {
  $map = @{ '--hub' = 'Hub'; '--token' = 'Token'; '--name' = 'Name'; '--port' = 'Port'; '--link-port' = 'LinkPort'; '--relay' = 'Relay'; '--bind' = 'Bind'; '--version' = 'Version' }
  $splat = @{ Yes = $true }
  for ($i = 0; $i -lt $words.Count; $i++) {
    $key = $map[$words[$i]]
    if ($key -and $i + 1 -lt $words.Count) { $splat[$key] = $words[$i + 1]; $i++ }
    elseif ($words[$i] -eq '--no-service') { $splat['NoService'] = $true }
    else { Write-Host "Option inconnue : $($words[$i])"; exit 2 }
  }
  return $splat
}
function RemoveRole($role, $purge) {
  if ($role -eq 'host' -or $role -eq 'agent') {
    StopRole $role
    try { Unregister-ScheduledTask -TaskName $Tasks[$role] -Confirm:$false -ErrorAction Stop } catch { }
    Remove-Item -Force -ErrorAction SilentlyContinue (Join-Path $Prefix "$role-run.ps1")
    if ($purge -and $role -eq 'agent') { Remove-Item -Force -ErrorAction SilentlyContinue (Join-Path $Prefix 'agent.env') }
    if ($purge -and $role -eq 'host' -and $R.hostData) { Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $R.hostData }
  } else {
    $uninstaller = Join-Path (Split-Path -Parent $R.appPath) 'uninstall.exe'
    if ($R.appPath -and (Test-Path $uninstaller)) { Start-Process -FilePath $uninstaller -ArgumentList '/S' -Wait }
    if ($purge -and $R.desktopHome) { Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $R.desktopHome }
  }
  $script:Roles = @($Roles | Where-Object { $_ -ne $role })
  $R.roles = $script:Roles
  [IO.File]::WriteAllText($Record, ($R | ConvertTo-Json), (New-Object Text.UTF8Encoding $false))
}
switch ($Command) {
  'status' {
    Write-Host "AgentsWorld $($R.version) - roles : $($Roles -join ' ')"
    if ((Has 'app') -or (Has 'client-only')) { Write-Host "Application : $($R.appPath)$(if (Has 'client-only') { ' (client seul)' })" }
    foreach ($role in ServiceRoles) {
      $task = Get-ScheduledTask -TaskName $Tasks[$role] -ErrorAction SilentlyContinue
      Write-Host "Service $role : $(if ($task) { $task.State } else { 'pas de tache planifiee' })"
    }
    if (Has 'host') { NodeCli status @Rest; exit $LASTEXITCODE }
  }
  { $_ -in 'pair', 'agent-token' } { NeedHost; NodeCli $Command @Rest; exit $LASTEXITCODE }
  'jaunt-enroll' {
    NeedHost; NodeCli 'jaunt-enroll' @Rest; $code = $LASTEXITCODE
    if (-not $code) { Write-Host "Redemarrage de l'hote..."; StopRole 'host'; StartRole 'host' }
    exit $code
  }
  'logs' {
    $role = if ($Rest.Count -and $Rest[0] -ne '-f') { $Rest[0] } elseif (Has 'host') { 'host' } elseif (Has 'agent') { 'agent' } else { 'app' }
    $file = if ($role -eq 'app') { Join-Path $R.desktopHome 'logs\desktop.log' } else { Join-Path $Prefix "$role.log" }
    if ($Rest -contains '-f') { Get-Content $file -Tail 200 -Wait } else { Get-Content $file -Tail 200 }
  }
  'start' { foreach ($role in ServiceRoles ($Rest | Select-Object -First 1)) { StartRole $role } }
  'stop' { foreach ($role in ServiceRoles ($Rest | Select-Object -First 1)) { StopRole $role } }
  'restart' { foreach ($role in ServiceRoles ($Rest | Select-Object -First 1)) { StopRole $role; StartRole $role } }
  'open' {
    if ($R.appPath -and (Test-Path $R.appPath)) { Start-Process $R.appPath }
    elseif (Has 'host') { Start-Process "http://127.0.0.1:$($R.hostPort)/" } else { Write-Host 'Rien a ouvrir.'; exit 1 }
  }
  'update' { Installer (Options $Rest) }
  'role' {
    if (-not $Rest.Count) { Write-Host ($Roles -join ' ') }
    elseif ($Rest[0] -eq 'add' -and $Rest.Count -ge 2) {
      $switch = @{ 'app' = 'App'; 'client-only' = 'ClientOnly'; 'host' = 'HostRole'; 'agent' = 'Agent' }[$Rest[1]]
      if (-not $switch) { Write-Host "Role inconnu : $($Rest[1])"; exit 2 }
      $splat = Options @($Rest | Select-Object -Skip 2)
      $splat[$switch] = $true
      Installer $splat
    } elseif ($Rest[0] -eq 'remove' -and $Rest.Count -ge 2 -and (Has $Rest[1])) { RemoveRole $Rest[1] $false; Write-Host "Role $($Rest[1]) retire (donnees gardees)." }
    else { Write-Host 'agentsworld role | role add <app|client-only|host|agent> [options] | role remove <role>'; exit 2 }
  }
  'uninstall' {
    $purge = $Rest -contains '--purge'
    foreach ($role in @($Roles)) { RemoveRole $role $purge }
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue (Join-Path $Prefix 'runtime')
    if ($purge) { Remove-Item -Force -ErrorAction SilentlyContinue (Join-Path $Prefix '*.log') }
    Remove-Item -Force -ErrorAction SilentlyContinue $Record
    $bin = Join-Path $Prefix 'bin'
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    [Environment]::SetEnvironmentVariable('Path', (($userPath -split ';') | Where-Object { $_ -and $_ -ne $bin }) -join ';', 'User')
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $bin
    Write-Host "AgentsWorld desinstalle.$(if (-not $purge) { " Le monde et les appairages sont gardes dans $($R.hostData) (--purge les supprime)." })"
  }
  { $_ -in 'version', '--version' } { Write-Host $R.version }
  default {
    Write-Host (@(
      'agentsworld status                      ce qui est installe et en marche',
      'agentsworld pair [--rights observe|answer|admin]   code d''appairage + QR code pour un appareil (hote)',
      'agentsworld jaunt-enroll                relie l''hote a Jaunt (a valider sur ton telephone)',
      'agentsworld agent-token create <nom>    jeton + commande d''installation d''un agent (machine sans Jaunt)',
      'agentsworld logs [host|agent|app] [-f]  journaux',
      'agentsworld start|stop|restart [host|agent]',
      'agentsworld open                        ouvre l''application (ou la page de l''hote)',
      'agentsworld update                      met a jour ce qui est installe',
      'agentsworld role                        roles installes ; role add <role> [options] ; role remove <role>',
      'agentsworld uninstall [--purge]         desinstalle (--purge : aussi le monde, les appairages et les reglages)'
    ) -join "`n")
  }
}
'@
  WriteUtf8 (Join-Path $Bin 'agentsworld.ps1') $cli
  # One line ending with `exit /b`: cmd parses the whole line first, so `agentsworld uninstall`, which deletes this
  # file, does not leave cmd looking for a next line in it (exit /b keeps PowerShell's exit code).
  WriteUtf8 (Join-Path $Bin 'agentsworld.cmd') "@powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"%~dp0agentsworld.ps1`" %* & exit /b`r`n"
  $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
  if (($userPath -split ';') -notcontains $Bin) { [Environment]::SetEnvironmentVariable('Path', (@($userPath, $Bin) | Where-Object { $_ }) -join ';', 'User') }
  $env:Path = "$Bin;$env:Path"

  # --- Next steps ---------------------------------------------------------------------------------------------
  Say "Pret ($Tag)"
  foreach ($role in $Roles) {
    switch ($role) {
      'app' {
        Info 'Ouvre AgentsWorld depuis le menu Demarrer (ou: agentsworld open).'
        Info 'Au premier lancement : Heberger ce monde sur cette machine, ou Rejoindre un hote avec le code d''appairage d''un hote.'
        if ($Jaunt) { Info 'Jaunt est ici : en hebergeant, Reglages > Appareil > Application > Relier a Jaunt montre toutes tes machines liees.' }
      }
      'client-only' {
        Info 'Ouvre AgentsWorld (agentsworld open), puis Rejoindre un hote : colle le code d''appairage de l''hote ou importe son QR code.'
        Info 'Sur l''hote : agentsworld pair, ou Reglages > Appareil > Appairer un appareil dans son application.'
      }
      'host' {
        if (-not $NoPair) { Say 'Appairer un appareil (telephone, autre ordinateur)'; & (Join-Path $Bin 'agentsworld.cmd') pair }
        else { Info 'Appairer un appareil : agentsworld pair' }
        if ($Jaunt -and -not (Test-Path (Join-Path $HostData 'jaunt-service.json'))) {
          Say 'Jaunt'
          Info 'Pour que cet hote voie les sessions de toutes tes machines reliees a Jaunt :'
          Info '  agentsworld jaunt-enroll      (une demande apparait sur ton telephone appaire a Jaunt : accepte-la)'
        } elseif (-not $Jaunt) {
          Info 'Sans Jaunt, pour voir les sessions d''une autre machine : agentsworld agent-token create <nom> ici donne sa commande d''installation.'
        }
      }
      'agent' { Info 'agentsworld status montre l''agent ; agentsworld logs agent ses journaux.' }
    }
  }
  Info "Commande : $Bin\agentsworld.cmd (ouvre un nouveau terminal pour l'avoir dans le PATH)"
} catch {
  Write-Host "`nagentsworld: echec : $_" -ForegroundColor Red
  # Run as a file (powershell -File, the update command): report the failure through the exit code.
  if ($MyInvocation.MyCommand.Path) { exit 1 }
} finally {
  Remove-Item -Recurse -Force $Tmp -ErrorAction SilentlyContinue
}
