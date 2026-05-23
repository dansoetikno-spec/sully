const cache = globalThis.__skytecCache || new Map();
globalThis.__skytecCache = cache;

function json(res, status, data) {
  res.statusCode = status;
  res.setHeader("Content-Type", "application/json; charset=utf-8");
  res.end(JSON.stringify(data));
}

async function getJson(url, headers = {}) {
  const response = await fetch(url, { headers });
  if (!response.ok) {
    const body = await response.text();
    const message = body || response.statusText;
    const error = new Error(`${response.status} ${message}`);
    error.status = response.status;
    throw error;
  }
  return response.json();
}

async function riot(host, path, query = {}) {
  const apiKey = process.env.RIOT_API_KEY;
  if (!apiKey) {
    throw new Error("RIOT_API_KEY is not set in Vercel Environment Variables.");
  }

  const params = new URLSearchParams(query);
  const suffix = params.toString() ? `?${params}` : "";
  return getJson(`https://${host}${path}${suffix}`, {
    "X-Riot-Token": apiKey
  });
}

async function dragon() {
  const cached = cache.get("dragon");
  if (cached && cached.expires > Date.now()) return cached.value;

  const versions = await getJson("https://ddragon.leagueoflegends.com/api/versions.json");
  const version = versions[0];
  const data = await getJson(`https://ddragon.leagueoflegends.com/cdn/${version}/data/en_US/champion.json`);
  const championsByKey = {};
  for (const champ of Object.values(data.data)) {
    championsByKey[Number(champ.key)] = {
      id: champ.id,
      name: champ.name,
      image: `https://ddragon.leagueoflegends.com/cdn/${version}/img/champion/${champ.image.full}`
    };
  }

  const value = { version, championsByKey };
  cache.set("dragon", { expires: Date.now() + 6 * 60 * 60 * 1000, value });
  return value;
}

function champion(dragonData, id) {
  return dragonData.championsByKey[Number(id)] || {
    id: "Unknown",
    name: `Champion ${id}`,
    image: `https://ddragon.leagueoflegends.com/cdn/${dragonData.version}/img/champion/Annie.png`
  };
}

function winrate(entry) {
  const total = Number(entry.wins || 0) + Number(entry.losses || 0);
  return total > 0 ? Number(entry.wins || 0) / total : 0;
}

function queueName(queueId) {
  if (queueId === 420) return "Ranked Solo";
  if (queueId === 440) return "Ranked Flex";
  return `Queue ${queueId}`;
}

function age(ms) {
  const minutes = Math.max(1, Math.floor((Date.now() - Number(ms)) / 60000));
  if (minutes >= 1440) return `${Math.floor(minutes / 1440)}d ago`;
  if (minutes >= 60) return `${Math.floor(minutes / 60)}h ago`;
  return `${minutes}m ago`;
}

function duration(seconds) {
  const total = Number(seconds || 0);
  const minutes = Math.floor(total / 60);
  return `${minutes}:${String(total % 60).padStart(2, "0")}`;
}

function demo(gameName, tagLine) {
  return {
    notice: "Demo mode: set RIOT_API_KEY in Vercel Environment Variables for real live data.",
    profile: {
      gameName,
      tagLine,
      profileIconUrl: "https://ddragon.leagueoflegends.com/cdn/16.10.1/img/profileicon/588.png"
    },
    rankedSolo: {
      queueType: "RANKED_SOLO_5x5",
      tier: "CHALLENGER",
      rank: "I",
      leaguePoints: 965,
      wins: 295,
      losses: 211,
      winrate: 0.583
    },
    rankFallback: null,
    liveGame: { isLive: false, durationText: "0:00" },
    champions: [
      { name: "Jhin", image: "https://ddragon.leagueoflegends.com/cdn/16.10.1/img/champion/Jhin.png", games: 7, wins: 5, winrate: .714, kda: 4.28, avgCs: 214 },
      { name: "Kai'Sa", image: "https://ddragon.leagueoflegends.com/cdn/16.10.1/img/champion/Kaisa.png", games: 5, wins: 3, winrate: .600, kda: 3.18, avgCs: 201 }
    ],
    matches: []
  };
}

async function dashboard(req) {
  const url = new URL(req.url, "http://localhost");
  const gameName = url.searchParams.get("gameName") || "SkyTec";
  const tagLine = url.searchParams.get("tagLine") || "NA1";
  const platform = url.searchParams.get("platform") || "na1";
  const region = url.searchParams.get("region") || "americas";
  const matchCount = Math.min(Number(url.searchParams.get("matches") || 16), 20);

  if (!process.env.RIOT_API_KEY) return demo(gameName, tagLine);

  const cacheKey = `dashboard:${gameName}#${tagLine}:${platform}:${region}:${matchCount}`;
  const cached = cache.get(cacheKey);
  if (cached && cached.expires > Date.now()) return cached.value;

  const dragonData = await dragon();
  const account = await riot(`${region}.api.riotgames.com`, `/riot/account/v1/accounts/by-riot-id/${encodeURIComponent(gameName)}/${encodeURIComponent(tagLine)}`);
  const summoner = await riot(`${platform}.api.riotgames.com`, `/lol/summoner/v4/summoners/by-puuid/${encodeURIComponent(account.puuid)}`);
  const entries = await riot(`${platform}.api.riotgames.com`, `/lol/league/v4/entries/by-puuid/${encodeURIComponent(account.puuid)}`);
  const enrichedEntries = entries.map((entry) => ({ ...entry, winrate: winrate(entry) }));
  const rankedSolo = enrichedEntries.find((entry) => entry.queueType === "RANKED_SOLO_5x5") || null;
  const rankFallback = enrichedEntries[0] || null;

  let liveGame = { isLive: false, durationText: "0:00" };
  try {
    const spectator = await riot(`${platform}.api.riotgames.com`, `/lol/spectator/v5/active-games/by-summoner/${encodeURIComponent(account.puuid)}`);
    const participant = spectator.participants.find((player) => player.puuid === account.puuid);
    liveGame = {
      isLive: true,
      mode: spectator.gameMode,
      queue: `Queue ${spectator.gameQueueConfigId}`,
      durationText: duration(spectator.gameLength),
      champion: champion(dragonData, participant?.championId),
      participantsText: `${spectator.participants.length} players currently loaded`
    };
  } catch (error) {
    liveGame = { isLive: false, durationText: "0:00" };
  }

  const matchIds = await riot(`${region}.api.riotgames.com`, `/lol/match/v5/matches/by-puuid/${encodeURIComponent(account.puuid)}/ids`, {
    start: 0,
    count: matchCount
  });

  const matches = [];
  const champStats = new Map();
  for (const matchId of matchIds) {
    try {
      const match = await riot(`${region}.api.riotgames.com`, `/lol/match/v5/matches/${encodeURIComponent(matchId)}`);
      const participant = match.info.participants.find((player) => player.puuid === account.puuid);
      if (!participant) continue;

      const champ = champion(dragonData, participant.championId);
      const deathsForKda = Math.max(1, Number(participant.deaths));
      const kda = (Number(participant.kills) + Number(participant.assists)) / deathsForKda;
      matches.push({
        champion: champ,
        win: Boolean(participant.win),
        queue: queueName(match.info.queueId),
        age: age(match.info.gameCreation),
        kills: Number(participant.kills),
        deaths: Number(participant.deaths),
        assists: Number(participant.assists),
        kda: Math.round(kda * 100) / 100
      });

      const key = String(participant.championId);
      if (!champStats.has(key)) {
        champStats.set(key, { champion: champ, games: 0, wins: 0, kills: 0, deaths: 0, assists: 0, cs: 0 });
      }
      const stat = champStats.get(key);
      stat.games += 1;
      if (participant.win) stat.wins += 1;
      stat.kills += Number(participant.kills);
      stat.deaths += Number(participant.deaths);
      stat.assists += Number(participant.assists);
      stat.cs += Number(participant.totalMinionsKilled) + Number(participant.neutralMinionsKilled);
    } catch (error) {
      // Skip individual match failures so one stale match cannot blank the dashboard.
    }
  }

  const champions = Array.from(champStats.values()).map((stat) => ({
    name: stat.champion.name,
    image: stat.champion.image,
    games: stat.games,
    wins: stat.wins,
    winrate: stat.games > 0 ? stat.wins / stat.games : 0,
    kda: Math.round(((stat.kills + stat.assists) / Math.max(1, stat.deaths)) * 100) / 100,
    avgCs: stat.games > 0 ? Math.round(stat.cs / stat.games) : 0
  })).sort((a, b) => b.games - a.games || b.winrate - a.winrate);

  const value = {
    notice: null,
    profile: {
      gameName: account.gameName,
      tagLine: account.tagLine,
      profileIconUrl: `https://ddragon.leagueoflegends.com/cdn/${dragonData.version}/img/profileicon/${summoner.profileIconId}.png`
    },
    rankedSolo,
    rankFallback,
    liveGame,
    champions,
    matches
  };

  cache.set(cacheKey, { expires: Date.now() + 45 * 1000, value });
  return value;
}

module.exports = async function handler(req, res) {
  try {
    json(res, 200, await dashboard(req));
  } catch (error) {
    json(res, error.status || 500, { error: error.message });
  }
};
