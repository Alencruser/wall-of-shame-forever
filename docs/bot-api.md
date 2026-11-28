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
- `status` `received` (addon 0.6.7, companion 0.7.8): the **buyer** confirms a done order reached
  them; the bot applies it only if the order is done and not received yet, and the sender is the buyer
  (same character, or the buyer's account by battletag or character link); otherwise `200`, ignored
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

Guild bank log event, from SavedVariables only (no strip, no screenshot): the guild bank's money log
("Journal des richesses"), read by the addon each time the player opens the guild bank (no click on
the tab needed). Queued only when the log changed since the last reading of that guild. A new `id`
for every reading; the game keeps only the latest transactions and gives each one an age, so the bot
merges the readings of every guildmate:

```json
{ "type": "banklog", "id": "Grumbar-Forever:B:1793702383", "name": "Grumbar", "realm": "Forever",
  "guild": "Bagarre", "level": 30, "class": "WARRIOR", "time": 1793702383, "battletag": "Pierre#1234",
  "money": 16302,
  "lines": [
    { "type": "deposit", "who": "Lwi Zi", "copper": 202, "years": 0, "months": 0, "days": 13, "hours": 8 },
    { "type": "withdraw", "who": "Chamy Chan", "copper": 10000, "years": 0, "months": 0, "days": 0, "hours": 0 } ],
  "test": false, "source": "savedvariables" }
```

- `money`: the bank's balance in copper at the reading, `null` if unknown
- `lines`: in the game's order, oldest first. `type` as the game gives it (`deposit`, `withdraw`,
  `repair`, `withdrawForTab`, `buyTab`…); `who`: the name the log shows (no realm for the reader's
  realm); the age (`years`…`hours`) is relative to `time` and rounded down to the hour
- the bot estimates each transaction's date (`time` minus the age) and keeps a line once: same type,
  character, amount and a date within 3 hours of a known transaction (two identical lines of one
  reading stay two transactions)

Guild bank items event (addon 0.9.4, companion 0.8.5), from SavedVariables only: the item tabs' logs, read
right after the money log, one tab after the other (tabs the player can't see give nothing). Same rules as
`banklog`: queued only when changed, a new `id` per reading, merged by the bot. Deposits and withdrawals
only (moves left out), with Auctionator's price when the player has it:

```json
{ "type": "bankitems", "id": "Grumbar-Forever:I:1793702383", "name": "Grumbar", "realm": "Forever",
  "guild": "Bagarre", "level": 30, "class": "WARRIOR", "time": 1793702383, "battletag": "Pierre#1234",
  "lines": [
    { "type": "deposit", "who": "Lwi Zi", "item": 2589, "count": 20, "years": 0, "months": 0, "days": 3,
      "hours": 4, "price": 45, "age": 2, "tab": 1 } ],
  "test": false, "source": "savedvariables" }
```

- `price`: Auctionator's price of one, in copper (`null` without Auctionator or never seen); `age`: days
  since Auctionator saw it (`null` if unknown or older than 21 days)
- the bot keeps a line once (same type, item, count, character, date within 3 hours) and, per item, the
  price of the most recent sighting; the guild score counts a deposit (+) or a withdrawal (−) for 70 % of it

Follow event, on the strip and in SavedVariables, never with a screenshot: the time the player has
spent auto-following (`/follow`) a member of their guild. A strip every 5 minutes during the follow
and one at the end; the end is also queued in SavedVariables (only the latest update of a session
waits there). A new `id` per update:

```json
{ "type": "follow", "id": "Grumbar-Forever:F:1795199555:300", "name": "Grumbar", "realm": "Forever",
  "guild": "Bagarre", "level": 30, "class": "WARRIOR", "time": 1795199855, "battletag": "Pierre#1234",
  "target": "Johnny Teitelbaum", "start": 1795199555, "seconds": 300, "done": false,
  "test": false, "source": "realtime" }
```

- `target`: the followed guild member, as the game shows the name (followers of someone outside the
  guild send nothing); `start`: when the follow began, the same for every update of the session;
  `seconds`: time followed so far; `done`: `true` for the session's last update (follow ended, new
  target, /reload or logout)
- keep the highest `seconds` per follower (`name`, `realm`) and `start`: an update received twice, or
  after a later one, changes nothing. A game crash loses at most the minutes since the last strip

Armory event (addon v0.9.0, companion 0.8.3), from SavedVariables only (no strip, no screenshot): the
character's gear, stats and talents for the site's « Armurerie ». Read a moment after login, when gear or
talents change, on a level-up and at logout; queued only when the gear, the talents or the level changed
(stats alone move with buffs). Only the latest reading of a character waits in the outbox; a new `id` for
every reading:

```json
{ "type": "armory", "id": "Grumbar-Forever:G:1795800000", "name": "Grumbar", "realm": "Forever",
  "guild": "Bagarre", "level": 50, "class": "WARRIOR", "time": 1795800000, "battletag": "Pierre#1234",
  "race": "Humain", "off": false,
  "gear": [ { "slot": 5, "item": 7939, "enchant": 1891, "suffix": 0, "ilvl": 49, "quality": 3 } ],
  "stats": { "str": 168, "strB": 61, "armor": 3420, "ap": 446, "crit": 9.4 },
  "talents": [ { "name": "Armes", "points": 31, "talents": [
    { "spell": 12294, "tier": 7, "column": 2, "rank": 1, "max": 1, "name": "Frappe mortelle" } ] } ],
  "test": false, "source": "savedvariables" }
```

- `gear`: inventory slots 1 (head) to 19 (tabard) that hold something; `enchant` and `suffix` (« de l'ours »)
  as in the item link, 0 if none; a negative `suffix` (addon v0.9.2) is the item's first bonus ID (WoW Forever
  gives random suffixes as bonuses: Wowhead `bonus=`); `ilvl` 0 and `quality` `null` when the client did not give them
- `stats`: what the game's character sheet shows (buffs included); a stat the client does not give is left
  out. `str`…`spi` and their item bonus `strB`…`spiB`, `armor`, `hp`, `power`, `powerType`, melee `ap`
  `dmgMin` `dmgMax` `speed` `hit` `crit`, ranged `rap` `rdmgMin` `rdmgMax` `rspeed` `rcrit`, spells `sp`
  (best school) `sp2`…`sp7` (holy, fire, nature, frost, shadow, arcane) `heal` `scrit` `shit` `mp5` `mp5c`,
  defense `def` `dodge` `parry` `block` and resistances `res2`…`res6` (fire, nature, frost, shadow, arcane)
- `talents`: one entry per tree, left to right as in game; `spell`: the talent's spell, `null` if the client
  did not give it. On WoW Forever (addon v0.9.1) the trees come from the trait tree and have no name: the bot
  names them by class and order. From v0.9.2 the `name` field holds the links between talents instead:
  `"@2.2>4.2 4.3>5.3"` (from tier.column to tier.column)
- `off`: `true` when the player turned off « Montrer mon équipement et mes talents sur le site »: `gear`,
  `stats` and `talents` are empty, remove the character from the armory
- keep the latest reading per character (`time`); an older one arriving late changes nothing

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
    "note": "I bring the bars", "reply": "Ready on Friday",
    "reagents": [ { "itemId": 2841, "name": "Bronze Bar", "qty": 8 },
                  { "itemId": 2880, "name": "Weak Flux", "qty": 4 } ],
    "createdAt": 1793702383 } ] }
```

- `id`: 8 hex characters, unique in the guild; `artisan`: the character the order is for
- `buyer.class` (WoW class token) and `buyer.level` are `null` when the bot does not know the
  buyer's character (name typed by hand); `buyer.realm` is then the artisan's realm
- `itemId`: the crafted item (`null` for a recipe that makes no item, e.g. an enchantment);
  `itemName`: in French, as shown on Discord
- `qty`: 1 to 99; `note`: the buyer's note, `""` if none (200 characters at most);
  `createdAt`: Unix timestamp of the order
- `reply`: the artisan's answer to the buyer (set on the orders website), `""` if none
- `reagents`: the materials of the **whole** order (one craft's materials × the number of crafts;
  a recipe that makes several items per craft counts once per craft), `name` in French; `[]` when
  the bot does not know the recipe. Older bots send neither `reply` nor `reagents`
- poll every 2 minutes or so; the bot only logs a request when its answer changes

The same answer also lists the player's **own** orders as a buyer (the addon's "My orders" tab),
`placed`: the orders placed by the Discord member of that battletag, or by one of the `chars`,
still pending or done / refused in the last 7 days (cancelled ones never), oldest first. Older bots
send no `placed`; companions before 0.7.2 ignore it.

```json
{ "orders": [ ... ],
  "placed": [
  { "id": "7b1e0c42", "artisan": "Grumbar-Forever", "artisanClass": "WARRIOR",
    "buyer": "Thrall-Forever", "status": "done", "reason": "", "itemId": 2848,
    "itemName": "Bronze Shortsword", "qty": 2, "note": "", "reply": "Ready on Friday",
    "reagents": [ { "itemId": 2841, "name": "Bronze Bar", "qty": 8 } ],
    "createdAt": 1793702383, "updatedAt": 1793788783, "receivedAt": 0 } ] }
```

- `status`: `pending`, `done` or `refused`; `reason`: the artisan's reason for a refusal
- `artisanClass`: the artisan's class token when the bot knows it, else `null`
- `reagents`: as above (the addon only adds up those of pending orders); `updatedAt`: last change
- `hub.requests` (bot 2026-11-27, companion 0.8.0, addon 0.8.0): the guild's open item requests, newest
  first, 12 at most: [{ id, item, qty, reward, note, by, byClass, at, takers (names, comma separated), mine
  (asked by this player), taking (this player takes care of it) }]. The actions come from the addon as
  `request` events: `2|R|id|name|realm|guild|level|class|time|battletag|action|request|item|qty|reward|note`,
  action `new` (item, qty 1 to 999, reward and note optional), `take`, `drop` (someone else) or `close` (the
  asker only); the bot ignores (200) an unknown request, a close by someone else, a take by the asker
- gifts on a request (companion 0.8.2, addon 0.8.3): each request also has `received`, `waiting`, `waitMail`,
  `waitHand` (quantities received, announced and not confirmed yet, by mail or in person) and `gifts`
  (« id;name;qty;mode;status », status `p` pending, `r` received, `x` not received; pending first, 12 at
  most). Actions: `give` (someone else: qty given, cut to what is still needed; reward = mode `mail` or
  `hand`; note = the gift's id), `got` / `notgot` (the asker confirms a gift; note = its id). A gift pending
  for 14 days is received automatically. Closed requests keep their gifts (history)
- `hub.activities` (addon 0.8.0): each activity also has `id` (its Discord card), `type`, `size`, `levelMin`,
  `group` (« name;role;level » per member), `free` ({ tank, heal, dps } places left, dungeon only), `joined`
  and `myRole` (this player). Sign-ups come as `activity` events:
  `2|A|id|name|realm|guild|level|class|time|battletag|action|activity|role`, action `join` (role tank, heal
  or dps for a dungeon, empty otherwise) or `leave`; same rules as the card's button (full, role free and
  allowed for the class, required level), else ignored (200). An `order` event with status `cancelled`
  (addon 0.8.0) cancels a pending order when the sender is its buyer
- `hub` (bot 2026-11-27, companion 0.7.9, addon 0.7.0): the tabs of the addon's « Bagarre club » window
  for the player (its Discord account, from the battletag or a linked character), already worded by the
  bot: `titles` { bank, follow, craft }, `trophies`, `trophiesTotal`, `next` [{ name, desc, progress,
  share }], `rank`, `rankOf`, `rankMove`, `bank` { goal, moneyText, targetText, share, milestones
  [{ percent, reached }], mine, record }, `challenges` [{ title, progress, share, starts, ends,
  upcoming, reward }], `activities` [{ label, title, at, by, members, level }]. `null` when the bot does
  not know the player. The companion writes it as `hub` in the addon's file, within limits (depth 4,
  12 items per list, 200 characters per text)
- `hub.latest` (bot 2026-11-27, addon 0.9.3): { addon, companion } the latest versions published
  (CurseForge, GitHub), `null` when unknown. The companion 0.8.4 also writes its own version at the root of
  the addon's file (`companion`); the addon tells the player in chat when either is out of date (no
  `companion` there: a companion older than 0.8.4)
- `receivedAt` (bot 2026-11-24): for a done order, `0` while the hand-over is not confirmed (the
  addon shows a Received button), else when it was (unix seconds). A done order stays listed until
  received, then 7 days; the bot marks it received by itself 14 days after it was done

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
