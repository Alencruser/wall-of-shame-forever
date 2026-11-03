# TODO

## Done

- [x] Translate the addon to English (in-game texts, roster window, slash commands, readme)
- [x] Keep the network protocol compatible with the German original (prefix `MEMFOREVER`)

## P0 - Death shared with guildmates only

Already in the original addon: `OnOwnDeath()` sends a `D|level|zone|class|deaths` message on the
`GUILD` addon channel, and the server only delivers it to members of the same guild. Each guildmate
with the addon gets the death banner, sound, chat line and a log entry.

- [ ] Test in-game with 2 characters in the same guild (and 1 outside it, who must see nothing)
- [ ] Catch-up for missed deaths: each player keeps a history of their own deaths
      (timestamp, level, zone) and sends recent ones in reply to `H`, so a guildmate who was
      offline sees "X died while you were away" in `/wos log`
- [x] Cause of death (killer + level) in the chat line and `/wos log`
- [ ] Cause of death in the death banner too (check the text still fits the artwork)
- [ ] `/wos deaths` : list of the guild's recorded deaths (who, level, zone, date)

## P1 - Discord integration

addon -> death strip on screen (realtime) or SavedVariables (fallback) -> companion -> our bot
-> guild channel. Only the player who dies reports the death. Same model as DOINK
(https://github.com/ryan-flan/DOINK, MIT). Bot contract: `docs/bot-api.md`.

- [x] Addon: killer and killer level from the combat log (environment deaths too), shown in game
- [x] Addon: own deaths kept in `WallOfShameForeverDB.outbox` with a unique id, strip shown 3 s
      (`/wos discord` to enable, off by default; `/wos striptest`; `/wos flush`)
- [x] Companion (Python): reads the strip + takes the death screenshot, reads the outbox,
      dedups on the id, retries, dry run to `out/` without bot
- [x] Tests: Lua encoder -> rendered image -> Python decoder (gamma, noise, UTF-8, corruption)
- [ ] **Test in game**: `/wos discord`, `/wos striptest` with the companion in dry run, then a real
      death (killer level with and without target), different UI scales and resolutions
- [x] Connection code (bot address + guild key, nothing about the bot in the public repo):
      officers type `/wos code <code>`, stored in the guild information, read by every member's
      addon, picked up by the companion from SavedVariables. Players configure nothing
- [ ] Test in game: `CanEditGuildInfo` / `SetGuildInfoText` on Forever, guild info length limit
- [x] Before the guild exists: `/wos code <code>` per player, deaths shared in game through a
      hidden private channel derived from the code, Discord through the same code
- [x] Leaving the guild removes the code (addon remembers the last guild; companion forgets
      the code and drops waiting deaths)
- [ ] Test in game: leave / get kicked from the guild (online and offline), check the code is gone
- [x] Levels for the bot: level event at login and on level-up, with the battletag; the bot keeps
      the highest level per battletag and class (battletag directory, /activite sign-up)
- [x] Level-ups posted in their own channel (`/shamewall salon-niveaux`), right away through the strip
- [x] Local test: `npm run shamewall:local` in the bot, http allowed only for 127.0.0.1/localhost
- [x] Leaderboard: duels won against guildmates (system message) and killing blows on hostile
      players (PARTY_KILL), `/shamewall salon-classement` keeps one message up to date
- [x] Duel wins posted right away in their own channel (`/shamewall salon-duels`): winner's screenshot,
      both players mentioned (bot learns character -> battletag from every event)
- [ ] Test in game: duel message on a French client, killing blow on an enemy player
- [ ] Leaderboard: admin reset command (season), maybe a period (week, month)
- [ ] Test on WoW Classic Era (full chain on one PC), then on Forever
- [ ] Test in game: `BNGetInfo()` returns the battletag on Forever
- [ ] CurseForge page: say that the battletag is sent to the guild's bot (to find the Discord member)
- [ ] Test in game: addon messages on a custom channel (`SendAddonMessage` "CHANNEL") on Forever,
      channel hidden from the chat window, switch to the guild channel when joining a guild
- [x] Bot (bot-bagarre, `src/shamewall.js`): `/shamewall salon|guilde|code|nouvelle-cle|statut`,
      endpoint from `docs/bot-api.md`, tested end to end with the companion's sender
- [ ] Deploy the bot endpoint behind https (Caddy or Cloudflare tunnel), set SHAMEWALL_PORT and
      SHAMEWALL_PUBLIC_URL
- [x] Companion finds the WoW folder by itself (running WoW, registry, usual folders)
- [ ] Package the companion as an .exe (PyInstaller) for guildmates
- [ ] Distribution like DOINK: addon on CurseForge (no .exe in the package: CurseForge checks
      flag executables), companion zip on GitHub Releases, link from the CurseForge page
      (check CurseForge's rules on external download links first)
- [x] No code signing (no paid certificate): the readme explains the SmartScreen warning
- [ ] Check that `GetPhysicalScreenSize` exists on the Forever client (else no strip, fallback only)

## P2 - Later

- [ ] Localization table (EN/FR/DE) based on `GetLocale()` instead of hard-coded strings
- [ ] Settings panel in the game's interface options instead of slash commands only
- [ ] CurseForge page: credit alexauer and link the original project (MIT, required notice is in `LICENSE`)
