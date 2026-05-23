param(
  [int]$Port = 5173
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Cache = @{}

function Get-RiotApiKey() {
  if (-not [string]::IsNullOrWhiteSpace($env:RIOT_API_KEY)) {
    return $env:RIOT_API_KEY.Trim()
  }

  $keyPath = Join-Path $Root ".riot-api-key"
  if (Test-Path $keyPath -PathType Leaf) {
    return ((Get-Content $keyPath -Raw).Trim())
  }

  return $null
}

function Send-Text($Response, [int]$Status, [string]$Text, [string]$ContentType = "text/plain; charset=utf-8") {
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
  $Response.StatusCode = $Status
  $Response.ContentType = $ContentType
  $Response.ContentLength64 = $bytes.Length
  $Response.OutputStream.Write($bytes, 0, $bytes.Length)
  $Response.OutputStream.Close()
}

function Send-Json($Response, $Data, [int]$Status = 200) {
  Send-Text $Response $Status ($Data | ConvertTo-Json -Depth 24) "application/json; charset=utf-8"
}

function Get-JsonUrl([string]$Url, [hashtable]$Headers = @{}) {
  Invoke-RestMethod -Uri $Url -Headers $Headers -Method Get
}

function Get-Riot([string]$HostName, [string]$Path, [hashtable]$Query = @{}) {
  $apiKey = Get-RiotApiKey
  if ([string]::IsNullOrWhiteSpace($apiKey)) {
    throw "No Riot API key found. Add one to .riot-api-key or set RIOT_API_KEY."
  }

  $pairs = @()
  foreach ($key in $Query.Keys) {
    $pairs += ("{0}={1}" -f [uri]::EscapeDataString($key), [uri]::EscapeDataString([string]$Query[$key]))
  }
  $queryText = if ($pairs.Count -gt 0) { "?" + ($pairs -join "&") } else { "" }
  $url = "https://$HostName$Path$queryText"
  Invoke-RestMethod -Uri $url -Headers @{ "X-Riot-Token" = $apiKey } -Method Get
}

function Get-Dragon() {
  $cacheKey = "dragon"
  if ($Cache.ContainsKey($cacheKey) -and $Cache[$cacheKey].Expires -gt (Get-Date)) {
    return $Cache[$cacheKey].Value
  }

  $versions = Get-JsonUrl "https://ddragon.leagueoflegends.com/api/versions.json"
  $version = $versions[0]
  $championData = Get-JsonUrl "https://ddragon.leagueoflegends.com/cdn/$version/data/en_US/champion.json"
  $byKey = @{}
  foreach ($champ in $championData.data.PSObject.Properties.Value) {
    $byKey[[int]$champ.key] = @{
      id = $champ.id
      name = $champ.name
      image = "https://ddragon.leagueoflegends.com/cdn/$version/img/champion/$($champ.image.full)"
    }
  }
  $dragon = @{
    version = $version
    championsByKey = $byKey
  }
  $Cache[$cacheKey] = @{ Expires = (Get-Date).AddHours(6); Value = $dragon }
  $dragon
}

function Get-Champion($Dragon, [int]$ChampionId) {
  if ($Dragon.championsByKey.ContainsKey($ChampionId)) {
    return $Dragon.championsByKey[$ChampionId]
  }
  @{
    id = "Unknown"
    name = "Champion $ChampionId"
    image = "https://ddragon.leagueoflegends.com/cdn/$($Dragon.version)/img/champion/Annie.png"
  }
}

function Format-Age([datetime]$When) {
  $span = (Get-Date) - $When
  if ($span.TotalDays -ge 1) { return "$([math]::Floor($span.TotalDays))d ago" }
  if ($span.TotalHours -ge 1) { return "$([math]::Floor($span.TotalHours))h ago" }
  "$([math]::Max(1, [math]::Floor($span.TotalMinutes)))m ago"
}

function Format-Duration([int]$Seconds) {
  $minutes = [math]::Floor($Seconds / 60)
  $remaining = $Seconds % 60
  "{0}:{1:00}" -f $minutes, $remaining
}

function Get-MockDashboard([string]$GameName, [string]$TagLine) {
  @{
    notice = "Demo mode: add a valid Riot key to .riot-api-key or RIOT_API_KEY to use real live data."
    profile = @{
      gameName = $GameName
      tagLine = $TagLine
      profileIconUrl = "https://ddragon.leagueoflegends.com/cdn/16.10.1/img/profileicon/588.png"
    }
    rankedSolo = @{
      queueType = "RANKED_SOLO_5x5"; tier = "EMERALD"; rank = "II"; leaguePoints = 71; wins = 64; losses = 52; winrate = 0.552
    }
    rankFallback = $null
    liveGame = @{
      isLive = $false
      mode = $null
      durationText = "0:00"
    }
    champions = @(
      @{ name = "Jhin"; image = "https://ddragon.leagueoflegends.com/cdn/16.10.1/img/champion/Jhin.png"; games = 7; wins = 5; winrate = .714; kda = 4.28; avgCs = 214 },
      @{ name = "Kai'Sa"; image = "https://ddragon.leagueoflegends.com/cdn/16.10.1/img/champion/Kaisa.png"; games = 5; wins = 3; winrate = .600; kda = 3.18; avgCs = 201 },
      @{ name = "Ezreal"; image = "https://ddragon.leagueoflegends.com/cdn/16.10.1/img/champion/Ezreal.png"; games = 4; wins = 2; winrate = .500; kda = 2.44; avgCs = 188 },
      @{ name = "Lucian"; image = "https://ddragon.leagueoflegends.com/cdn/16.10.1/img/champion/Lucian.png"; games = 3; wins = 1; winrate = .333; kda = 1.76; avgCs = 174 }
    )
    matches = @(
      @{ champion = @{ name = "Jhin"; image = "https://ddragon.leagueoflegends.com/cdn/16.10.1/img/champion/Jhin.png" }; win = $true; queue = "Ranked Solo"; age = "18m ago"; kills = 10; deaths = 2; assists = 11; kda = 10.5 },
      @{ champion = @{ name = "Kai'Sa"; image = "https://ddragon.leagueoflegends.com/cdn/16.10.1/img/champion/Kaisa.png" }; win = $false; queue = "Ranked Solo"; age = "2h ago"; kills = 7; deaths = 6; assists = 4; kda = 1.83 },
      @{ champion = @{ name = "Ezreal"; image = "https://ddragon.leagueoflegends.com/cdn/16.10.1/img/champion/Ezreal.png" }; win = $true; queue = "Normal Draft"; age = "5h ago"; kills = 8; deaths = 3; assists = 9; kda = 5.67 }
    )
  }
}

function Get-Dashboard($Request) {
  $gameName = $Request.QueryString["gameName"]
  $tagLine = $Request.QueryString["tagLine"]
  $platform = $Request.QueryString["platform"]
  $region = $Request.QueryString["region"]
  $matchValue = $Request.QueryString["matches"]
  if ([string]::IsNullOrWhiteSpace($gameName)) { $gameName = "SkyTec" }
  if ([string]::IsNullOrWhiteSpace($tagLine)) { $tagLine = "NA1" }
  if ([string]::IsNullOrWhiteSpace($platform)) { $platform = "na1" }
  if ([string]::IsNullOrWhiteSpace($region)) { $region = "americas" }
  if ([string]::IsNullOrWhiteSpace($matchValue)) { $matchValue = "16" }
  $matchCount = [int]$matchValue

  if ([string]::IsNullOrWhiteSpace((Get-RiotApiKey))) {
    return Get-MockDashboard $gameName $tagLine
  }

  $cacheKey = "dashboard:$($gameName)#$($tagLine):$($platform):$($region):$($matchCount)"
  if ($Cache.ContainsKey($cacheKey) -and $Cache[$cacheKey].Expires -gt (Get-Date)) {
    return $Cache[$cacheKey].Value
  }

  $dragon = Get-Dragon
  $account = Get-Riot "$region.api.riotgames.com" "/riot/account/v1/accounts/by-riot-id/$([uri]::EscapeDataString($gameName))/$([uri]::EscapeDataString($tagLine))"
  $summoner = Get-Riot "$platform.api.riotgames.com" "/lol/summoner/v4/summoners/by-puuid/$([uri]::EscapeDataString($account.puuid))"
  $entries = Get-Riot "$platform.api.riotgames.com" "/lol/league/v4/entries/by-puuid/$([uri]::EscapeDataString($account.puuid))"
  $rankedSolo = $entries | Where-Object { $_.queueType -eq "RANKED_SOLO_5x5" } | Select-Object -First 1
  $rankFallback = $entries | Select-Object -First 1

  foreach ($entry in @($rankedSolo, $rankFallback)) {
    if ($null -ne $entry) {
      $total = [double]($entry.wins + $entry.losses)
      $rate = if ($total -gt 0) { $entry.wins / $total } else { 0 }
      $entry | Add-Member -NotePropertyName winrate -NotePropertyValue $rate -Force
    }
  }

  $liveGame = @{ isLive = $false; durationText = "0:00" }
  try {
    $spectator = Get-Riot "$platform.api.riotgames.com" "/lol/spectator/v5/active-games/by-summoner/$([uri]::EscapeDataString($account.puuid))"
    $participant = $spectator.participants | Where-Object { $_.puuid -eq $account.puuid } | Select-Object -First 1
    $liveChamp = Get-Champion $dragon ([int]$participant.championId)
    $liveGame = @{
      isLive = $true
      mode = $spectator.gameMode
      queue = "Queue $($spectator.gameQueueConfigId)"
      durationText = Format-Duration ([int]$spectator.gameLength)
      champion = $liveChamp
      participantsText = "$(($spectator.participants | Measure-Object).Count) players currently loaded"
    }
  } catch {
    $liveGame = @{ isLive = $false; durationText = "0:00" }
  }

  $matchIds = Get-Riot "$region.api.riotgames.com" "/lol/match/v5/matches/by-puuid/$([uri]::EscapeDataString($account.puuid))/ids" @{ start = 0; count = $matchCount }
  $matches = @()
  $champStats = @{}
  foreach ($matchId in $matchIds) {
    try {
      $match = Get-Riot "$region.api.riotgames.com" "/lol/match/v5/matches/$([uri]::EscapeDataString($matchId))"
      $participant = $match.info.participants | Where-Object { $_.puuid -eq $account.puuid } | Select-Object -First 1
      if ($null -eq $participant) { continue }
      $champion = Get-Champion $dragon ([int]$participant.championId)
      $deathsForKda = [math]::Max(1, [int]$participant.deaths)
      $kda = ([int]$participant.kills + [int]$participant.assists) / $deathsForKda
      $playedAt = [DateTimeOffset]::FromUnixTimeMilliseconds([int64]$match.info.gameCreation).LocalDateTime
      $queue = if ($match.info.queueId -eq 420) { "Ranked Solo" } elseif ($match.info.queueId -eq 440) { "Ranked Flex" } else { "Queue $($match.info.queueId)" }
      $matches += @{
        champion = $champion
        win = [bool]$participant.win
        queue = $queue
        age = Format-Age $playedAt
        kills = [int]$participant.kills
        deaths = [int]$participant.deaths
        assists = [int]$participant.assists
        kda = [math]::Round($kda, 2)
      }

      $champKey = [string]$participant.championId
      if (-not $champStats.ContainsKey($champKey)) {
        $champStats[$champKey] = @{
          champion = $champion; games = 0; wins = 0; kills = 0; deaths = 0; assists = 0; cs = 0
        }
      }
      $stat = $champStats[$champKey]
      $stat.games++
      if ($participant.win) { $stat.wins++ }
      $stat.kills += [int]$participant.kills
      $stat.deaths += [int]$participant.deaths
      $stat.assists += [int]$participant.assists
      $stat.cs += ([int]$participant.totalMinionsKilled + [int]$participant.neutralMinionsKilled)
    } catch {}
  }

  $champions = @(
    foreach ($stat in $champStats.Values) {
      $deathsForKda = [math]::Max(1, [int]$stat.deaths)
      @{
        name = $stat.champion.name
        image = $stat.champion.image
        games = $stat.games
        wins = $stat.wins
        winrate = if ($stat.games -gt 0) { $stat.wins / $stat.games } else { 0 }
        kda = [math]::Round((($stat.kills + $stat.assists) / $deathsForKda), 2)
        avgCs = if ($stat.games -gt 0) { [math]::Round($stat.cs / $stat.games) } else { 0 }
      }
    }
  ) | Sort-Object -Property games, winrate -Descending

  $dashboard = @{
    notice = $null
    profile = @{
      gameName = $account.gameName
      tagLine = $account.tagLine
      profileIconUrl = "https://ddragon.leagueoflegends.com/cdn/$($dragon.version)/img/profileicon/$($summoner.profileIconId).png"
    }
    rankedSolo = $rankedSolo
    rankFallback = $rankFallback
    liveGame = $liveGame
    champions = $champions
    matches = $matches
  }
  $Cache[$cacheKey] = @{ Expires = (Get-Date).AddSeconds(45); Value = $dashboard }
  $dashboard
}

function Serve-Static($Response, [string]$Path) {
  if ($Path -eq "/") { $Path = "/index.html" }
  $safePath = $Path.TrimStart("/") -replace "/", [IO.Path]::DirectorySeparatorChar
  $fullPath = [IO.Path]::GetFullPath((Join-Path $Root $safePath))
  if (-not $fullPath.StartsWith($Root, [StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path $fullPath -PathType Leaf)) {
    Send-Text $Response 404 "Not found"
    return
  }

  $ext = [IO.Path]::GetExtension($fullPath).ToLowerInvariant()
  $contentType = switch ($ext) {
    ".html" { "text/html; charset=utf-8" }
    ".css" { "text/css; charset=utf-8" }
    ".js" { "application/javascript; charset=utf-8" }
    default { "application/octet-stream" }
  }
  $bytes = [IO.File]::ReadAllBytes($fullPath)
  $Response.StatusCode = 200
  $Response.ContentType = $contentType
  $Response.ContentLength64 = $bytes.Length
  $Response.OutputStream.Write($bytes, 0, $bytes.Length)
  $Response.OutputStream.Close()
}

$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add("http://localhost:$Port/")
$listener.Start()
Write-Host "SkyTec dashboard running at http://localhost:$Port/"
Write-Host "Using RIOT_API_KEY or .riot-api-key for live data when available."

try {
  while ($listener.IsListening) {
    $context = $listener.GetContext()
    try {
      if ($context.Request.Url.AbsolutePath -eq "/api/dashboard") {
        Send-Json $context.Response (Get-Dashboard $context.Request)
      } else {
        Serve-Static $context.Response $context.Request.Url.AbsolutePath
      }
    } catch {
      Send-Json $context.Response @{ error = $_.Exception.Message } 500
    }
  }
} finally {
  $listener.Stop()
}
