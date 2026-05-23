const state = {
  timer: null,
  lastData: null
};

const $ = (id) => document.getElementById(id);

function pct(value) {
  return `${Math.round((value || 0) * 100)}%`;
}

function kdaColor(champ) {
  if (champ.winrate >= 0.62 || champ.kda >= 4) return "great";
  if (champ.winrate >= 0.54 || champ.kda >= 3) return "good";
  if (champ.winrate >= 0.48 || champ.kda >= 2) return "warn";
  return "bad";
}

function setText(id, value) {
  $(id).textContent = value;
}

function championImage(champ) {
  return champ.image || "https://ddragon.leagueoflegends.com/cdn/16.10.1/img/champion/Annie.png";
}

function rankEmblem(rank) {
  const tier = rank?.tier?.toUpperCase();
  if (tier === "CHALLENGER") {
    return "league_of_legends_challenger_rank_vector_by_masnera_dee9njr-fullview-Photoroom.png";
  }

  return "";
}

function render(data) {
  state.lastData = data;
  const profile = data.profile;
  const rank = data.rankedSolo || data.rankFallback;

  setText("gameName", profile.gameName);
  setText("tagLine", profile.tagLine);
  $("profileIcon").src = profile.profileIconUrl;

  const liveDot = $("liveDot");
  liveDot.className = `dot ${data.liveGame?.isLive ? "live" : "offline"}`;
  setText("liveStatus", data.liveGame?.isLive ? `In game: ${data.liveGame.mode || "League"} for ${data.liveGame.durationText}` : "Not currently in a live match");

  setText("rankLine", rank ? `${rank.tier} ${rank.rank} - ${rank.leaguePoints} LP` : "Unranked");
  setText("rankMeta", rank ? `${rank.wins}W ${rank.losses}L - ${pct(rank.winrate)} WR` : "No ranked solo queue data yet");
  setText("tierText", rank ? `${rank.tier} ${rank.rank}` : "Unranked");
  setText("lpText", rank ? `${rank.leaguePoints} LP` : "Queue up and make it official");
  const emblem = $("rankEmblem");
  const emblemUrl = rankEmblem(rank);
  if (emblemUrl) {
    emblem.src = emblemUrl;
  } else {
    emblem.removeAttribute("src");
  }
  emblem.alt = rank ? `${rank.tier} emblem` : "Unranked emblem";
  emblem.hidden = !emblemUrl;
  setText("winsText", rank?.wins || 0);
  setText("lossesText", rank?.losses || 0);
  setText("rankWinrateText", pct(rank?.winrate || 0));
  $("winrateMeter").style.width = pct(rank?.winrate || 0);
  setText("queueBadge", rank?.queueType?.replace("RANKED_", "").replace("_", " ") || "Ranked");

  setText("sampleSize", `${data.matches.length} match sample`);
  $("championGrid").innerHTML = data.champions.map((champ) => `
    <div class="champion-card ${kdaColor(champ)}">
      <img src="${championImage(champ)}" alt="${champ.name}">
      <div>
        <div class="card-title">${champ.name}</div>
        <div class="card-meta">${champ.games} games - ${pct(champ.winrate)} WR</div>
        <div class="card-meta">${champ.kda.toFixed(2)} KDA - ${champ.avgCs} CS avg</div>
      </div>
    </div>
  `).join("");

  setText("gameBadge", data.liveGame?.isLive ? "Live now" : "Offline");
  $("currentGame").innerHTML = data.liveGame?.isLive
    ? `
      <div class="game-line">
        <img src="${championImage(data.liveGame.champion)}" alt="${data.liveGame.champion.name}">
        <div>
          <div class="card-title">${data.liveGame.champion.name}</div>
          <div class="card-meta">${data.liveGame.queue || "Current game"} - ${data.liveGame.durationText}</div>
        </div>
      </div>
      <div class="card-meta">${data.liveGame.participantsText}</div>
    `
    : `<div class="card-meta">The dashboard will flip this panel as soon as Riot's spectator endpoint reports an active match.</div>`;

  $("matchList").innerHTML = data.matches.map((match) => `
    <div class="match-item ${match.win ? "win" : "loss"}">
      <img src="${championImage(match.champion)}" alt="${match.champion.name}">
      <div>
        <div class="card-title">${match.champion.name} - ${match.win ? "Victory" : "Defeat"}</div>
        <div class="card-meta">${match.queue} - ${match.age}</div>
      </div>
      <div class="match-spacer">
        <div class="card-title">${match.kills}/${match.deaths}/${match.assists}</div>
        <div class="card-meta">${match.kda.toFixed(2)} KDA</div>
      </div>
    </div>
  `).join("");

  $("notice").hidden = !data.notice;
  $("notice").textContent = data.notice || "";
  $("lastUpdated").textContent = `Synced ${new Date().toLocaleTimeString()}`;
}

function parseRiotId(value) {
  const [gameName, tagLine] = value.split("#");
  return {
    gameName: (gameName || "SkyTec").trim(),
    tagLine: (tagLine || "NA1").trim()
  };
}

async function refresh() {
  const button = $("refreshButton");
  button.disabled = true;
  button.textContent = "Syncing...";
  const riotId = parseRiotId($("riotIdInput").value);
  try {
    const url = `/api/dashboard?gameName=${encodeURIComponent(riotId.gameName)}&tagLine=${encodeURIComponent(riotId.tagLine)}&platform=na1&region=americas&matches=16`;
    const response = await fetch(url);
    if (!response.ok) throw new Error(await response.text());
    render(await response.json());
  } catch (error) {
    $("notice").hidden = false;
    $("notice").textContent = `Could not sync live Riot data: ${error.message}`;
  } finally {
    button.disabled = false;
    button.textContent = "Refresh now";
  }
}

function schedule() {
  clearInterval(state.timer);
  state.timer = setInterval(refresh, Number($("pollSelect").value));
}

$("refreshButton").addEventListener("click", refresh);
$("pollSelect").addEventListener("change", schedule);
$("riotIdInput").addEventListener("change", refresh);

schedule();
refresh();
