# Bot API: death events

The companion sends **only the deaths of the player running it**. Guildmates see the death in
game through the addon and never report it.

## Connection code

The bot address is **not** in the public code. The bot gives a connection code to officers on
Discord (admin-only command, e.g. `/shamewall code`); one officer types `/wos code <code>` in
game, the addon stores it in the guild information, and every member's companion gets it from
there. Players configure nothing.

```
"swf1." + base64url(JSON {"url": "<https endpoint>", "key": "<guild key>"}), no padding
```

See `companion/connection.py` (`encode` builds one). The bot only serves its own guild:

- it accepts only the current guild key, and rejects everything else with `401`
- it checks that `guild` (and `realm`) in the event match the configured guild. Before the
  guild exists, players paste the code themselves and send `guild: ""`: accept those while
  no guild is configured on the bot side, and reject them once it is
- regenerating the key on Discord cuts off old codes (someone who left the guild)

## Request

`POST <url from the code>`, `multipart/form-data`

| Part | Content |
|---|---|
| header `Authorization` | `Bearer <guild key from the code>` |
| field `event` | JSON, see below |
| file `screenshot` | JPEG of the screen at the death or level-up, only when `source` is `realtime` |

Two event types: `death` (below) and `level`.

```json
{
  "type": "death",
  "id": "Grumbar-Forever:1793702383",
  "name": "Grumbar",
  "realm": "Forever",
  "guild": "Les Immortels",
  "level": 12,
  "class": "WARRIOR",
  "zone": "Elwynn Forest",
  "killer": "Hogger",
  "killerLevel": 11,
  "time": 1793702383,
  "battletag": "Pierre#1234",
  "test": false,
  "source": "realtime"
}
```

Leaderboard events, each reported only by the winner (kills from SavedVariables only):

```json
{ "type": "duel", "id": "Grumbar-Forever:W1793702383.1", "name": "Grumbar", "realm": "Forever",
  "guild": "", "level": 30, "class": "WARRIOR", "time": 1793702383, "battletag": "Pierre#1234",
  "opponent": "Thrall", "zone": "Durotar" }
{ "type": "kill", "id": "Grumbar-Forever:K1793702390.2", "name": "Grumbar", "realm": "Forever",
  "guild": "", "level": 30, "class": "WARRIOR", "time": 1793702390, "battletag": "Pierre#1234",
  "victim": "Garrosh", "victimLevel": 31, "victimClass": "WARRIOR", "zone": "The Barrens" }
```

- `duel`: duel won against a guildmate (before the guild: a player sharing the same code). Also
  on the strip, right away, with a screenshot of the winner's screen
- `kill`: killing blow on a hostile player (the other faction); `victimLevel` is `null` when the
  game did not show the victim

Level event, sent at login and on every level-up. A level-up also goes through the strip, right away, with a screenshot (`screenshot` file) like a death:

```json
{ "type": "level", "id": "Grumbar-Forever:L12", "name": "Grumbar", "realm": "Forever", "guild": "",
  "level": 12, "class": "WARRIOR", "time": 1793702383, "battletag": "Pierre#1234", "up": true, "zone": "Elwynn Forest",
  "test": false, "source": "savedvariables" }
```

- `up` (level only): `true` for a real level-up, which the bot posts; `false` for the level sent
  at login, only kept for the levels
- `battletag`: Battle.net battletag of the player (`BNGetInfo`), `""` if unknown. Lets the bot find
  the Discord member. The same level can arrive several times: keep the highest per battletag and
  class (a reroll of another class has its own level; a second character of the same class only
  counts once it is higher)

- `class`: WoW class token (`WARRIOR`, `PALADIN`, `HUNTER`, `ROGUE`, `PRIEST`, `SHAMAN`, `MAGE`,
  `WARLOCK`, `DRUID`)
- `killer`: mob or player name, or the environment (`Falling`, `Drowning`, `Fatigue`, `Fire`,
  `Lava`, `Slime`); `null` when unknown
- `killerLevel`: number, `-1` = skull level (show `??`), `null` when the game did not show the
  killer (not targeted, no nameplate)
- `time`: Unix timestamp of the death
- `test`: `true` for `/wos striptest`; post it only for the bot's admins (found by `battletag`),
  otherwise reply 200 without posting, so that players cannot flood the channels
- `source`: `realtime` (strip read on screen, with screenshot) or `savedvariables` (fallback after
  /reload or logout, no screenshot)

## Response

- `2xx`: received (also for an `id` already received: the companion retries after network
  errors, so the bot must **ignore an `id` it already has** and still answer 200)
- `401`/`403`: bad key or other guild; the companion tells the player to ask for the current
  code. Any other error: the companion retries with backoff (5 s up to 5 min)

## Suggested Discord embed

Title `Grumbar has fallen`, fields Level / Class / Zone / Killed by `Hogger (level 11)`, the
screenshot as the embed image, footer with the guild and the date from `time`.
