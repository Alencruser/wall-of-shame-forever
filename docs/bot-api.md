# Bot API: death events

The companion sends **only the deaths of the player running it**. Guildmates see the death in
game through the addon and never report it.

## Connection code

The bot address is **not** in the public code. The bot gives a connection code to officers on
Discord (admin-only command, e.g. `/shamewall code`), or they build it by hand (format below);
one officer pastes it into the guild information (WoW Forever does not let addons write there),
and every member's addon and companion get it from there. Players configure nothing.

```
"swf1." + base64url(JSON {"url": "<https endpoint>", "key": "<guild key>"}), no padding
```

See `companion/connection.py` (`encode` builds one). The bot only serves its own guild:

- it accepts only the current guild key, and rejects everything else with `401`
- the key is the authority: it accepts events with an empty `guild` (before the guild exists,
  a reroll not invited yet, an alt: the code is saved for the whole WoW account). Events of
  another guild or another realm are ignored with `200`, never refused
- regenerating the key on Discord cuts off old codes (someone who left the guild keeps the code)

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

Professions event, from SavedVariables only (no strip, no screenshot). The addon reads it when the player opens a profession window in game (the game does not let an addon open one by itself): the known recipes of that profession and the level of every profession. A new `id` for every reading; keep the latest per character (`time`):

```json
{ "type": "professions", "id": "Grumbar-Forever:P:1793702383", "name": "Grumbar", "realm": "Forever",
  "guild": "", "level": 21, "class": "WARRIOR", "time": 1793702383, "battletag": "Pierre#1234",
  "professions": [
    { "skillLine": 165, "level": 146, "max": 225, "name": "Leatherworking",
      "recipes": [ { "id": 2152, "color": 3, "name": "Light Armor Kit" } ] },
    { "skillLine": 393, "level": 221, "max": 225, "name": "Skinning", "recipes": null } ],
  "test": false, "source": "savedvariables" }
```

- `skillLine`: the game's profession id (165 Leatherworking, 185 Cooking, 393 Skinning…); `name` in
  the language of the player's client
- `recipes`: the learned recipes (`id`: recipe id, the one of Wowhead's `spell=` pages), with their
  `color` against the player's skill: `0` orange, `1` yellow, `2` green, `3` grey (`null` unknown).
  `null` for a gathering profession, or one not opened in game since the addon has this feature

Order event, on the strip right away and in SavedVariables as a fallback, never with a screenshot:
the artisan marked a craft order (see [Craft orders](#craft-orders)) as done or refused in game.
One `id` per order and status:

```json
{ "type": "order", "id": "Grumbar-Forever:O:3f9a1c27:refused", "name": "Grumbar", "realm": "Forever",
  "guild": "", "level": 30, "class": "WARRIOR", "time": 1793702383, "battletag": "Pierre#1234",
  "order": "3f9a1c27", "status": "refused", "reason": "Out of bronze, sorry",
  "test": false, "source": "savedvariables" }
```

- `order`: the order `id` from the orders list; `status`: `done` or `refused`; `reason`: free text
  for a refusal, `""` if none (ignored for `done`)
- the bot applies it only if the order exists, is still pending and the sender (`name`, `realm`,
  case-insensitive) is its artisan; otherwise it answers `200` and ignores it (unknown order,
  already done/refused/cancelled by the buyer, another artisan), so the companion can drop it
- when the buyer has no pending order left with that artisan character, the bot sends them one
  Discord DM listing every order done or refused since the last DM (cancelled ones never)

Debug event, from SavedVariables only (no strip, no screenshot): a technical report from the addon,
never posted. The bot appends it as one JSON line to `debug.jsonl` and answers `200`:

```json
{ "type": "debug", "id": "Grumbar-Forever:X:1793702390:1", "name": "Grumbar", "realm": "Forever",
  "guild": "", "level": 30, "class": "HUNTER", "time": 1793702390, "battletag": "Pierre#1234",
  "topic": "mort-double", "details": "dtMs=2010;first=dead=1,ghost=0,...;zone=...;trace=-120 UNIT_PET ... / +0 PLAYER_DEAD ...",
  "test": false, "source": "savedvariables" }
```

- `topic`: what the report is about, letters, digits, `-` and `_` (40 at most). `mort-double`: the
  game sent `PLAYER_DEAD` again for a death already counted; the addon did not send it twice
- `details`: free text from the addon (4000 characters at most), `key=value` parts separated by `;`

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

## Craft orders

Guild members order items from an artisan on Discord (🛒 on an item card of the professions
directory). The companion fetches the pending orders of its player's characters and the addon
shows them in game; the artisan reports each one with an `order` event (above).

`GET <url from the code, last path segment replaced by "orders">`, e.g.
`https://bot.example/shamewall/deaths` → `https://bot.example/shamewall/orders`

| Part | Content |
|---|---|
| header `Authorization` | `Bearer <guild key from the code>` (`401` on a bad key, like the POST) |
| query `battletag` | the player's battletag (`BNGetInfo`), may be empty |
| query `chars` | the player's characters as `Name-Realm`, comma-separated (URL-encoded), may be empty |

Answer `200`, `application/json`: the **pending** orders whose artisan character belongs to that
battletag (as the bot knows it from professions and level events) **or** is in `chars`
(case-insensitive), oldest first. Done, refused and cancelled orders are never listed, so an order
disappears from the list once reported or cancelled.

```json
{ "orders": [
  { "id": "3f9a1c27", "artisan": "Grumbar-Forever",
    "buyer": { "name": "Thrall", "realm": "Forever", "class": "SHAMAN", "level": 42 },
    "itemId": 2848, "itemName": "Bronze Shortsword", "qty": 2,
    "note": "I bring the bars", "createdAt": 1793702383 } ] }
```

- `id`: 8 hex characters, unique in the guild; `artisan`: the character the order is for
- `buyer.class` (WoW class token) and `buyer.level` are `null` when the bot does not know the
  buyer's character (name typed by hand); `buyer.realm` is then the artisan's realm
- `itemId`: the crafted item (`null` for a recipe that makes no item, e.g. an enchantment);
  `itemName`: in French, as shown on Discord
- `qty`: 1 to 99; `note`: the buyer's note, `""` if none (200 characters at most);
  `createdAt`: Unix timestamp of the order
- poll every 2 minutes or so; the bot only logs a request when its answer changes

## Response

- `2xx`: received (also for an `id` already received: the companion retries after network
  errors, so the bot must **ignore an `id` it already has** and still answer 200)
- `401`: bad key; the companion tells the player to ask for the current code and retries
  in an hour or as soon as the code changes
- `403`: the bot refuses this one event; the companion drops it, the code is still fine.
  Any other error: the companion retries with backoff (5 s up to 5 min)

## Suggested Discord embed

Title `Grumbar has fallen`, fields Level / Class / Zone / Killed by `Hogger (level 11)`, the
screenshot as the embed image, footer with the guild and the date from `time`.
