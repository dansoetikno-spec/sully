# SkyTec Live Rift Dashboard

A custom local League of Legends profile dashboard for `SkyTec#NA1`.

## Run it

```powershell
.\Start-Dashboard.ps1
```

Then open `http://localhost:5173/`.

The server reads your key from `.riot-api-key` automatically. If that file is missing, it falls back to `RIOT_API_KEY`. If neither is set, the dashboard runs in demo mode so you can still see the design.

Riot development keys deactivate every 24 hours. For a key you do not have to keep replacing, register the project in the Riot Developer Portal and use a personal key.

## Vercel

Do not commit `.riot-api-key`. For Vercel, add the key in the project settings instead:

1. Open the Vercel project.
2. Go to Settings -> Environment Variables.
3. Add `RIOT_API_KEY` with your Riot key.
4. Redeploy the project.

The deployed page calls `/api/dashboard`, which reads `process.env.RIOT_API_KEY` on Vercel.

## What It Shows

- Current Solo/Duo rank, LP, wins, losses, and winrate.
- Live game status from Riot's spectator endpoint.
- Recent match cards.
- Champion stats from recent matches, color-coded by winrate and KDA.

The page polls every 30 seconds by default and has a manual refresh button. The PowerShell server keeps your Riot key out of browser JavaScript.
