# CurseForge page

## Summary (short description field)

Shares every level-up and death of your guild with on-screen banners, and can post them on your guild's Discord with screenshots, duels and a PvP ranking.

## Description

# Wall of Shame Forever

**Every level-up and every death of your guild, on everyone's screen.** And, if your guild wants it, on your Discord too, screenshot included.

Made for **WoW Forever**. Everyone in the guild installs the addon.

## Getting started

**1. Install the addon.** With the CurseForge app, or unzip it into `World of Warcraft\_forever_\Interface\AddOns` (you should end up with a `WallOfShameForever` folder there). Restart the game, then type `/wos test` to see the banners.

**In a guild, that's all: no code, no bot, nothing to set up.** Banners, guild map and roster work as soon as your guildmates have the addon too.

**2. No guild yet?** Make up a code together: `swf1.` followed by letters, digits, `-` or `_`, for example `swf1.MyGroup-2026`. Everyone types `/wos code swf1.MyGroup-2026` once and you share banners, duels and the map until the guild exists. No bot needed.

**3. Discord (optional, needs a Discord bot).** Only if your guild runs a Discord bot that receives the events (see Connection code below): your deaths, level-ups, duels and killing blows are posted on your Discord with screenshots.

1. **Once per guild, an officer** (a rank allowed to edit the guild information) **pastes the bot's code into the guild information** (Guild > Guild Info, the "Guild Information" text). The code comes from whoever runs the bot: the bot can print it (ours: `/shamewall code`), or they build it from the bot's address and key. Blizzard does not let addons write the guild information, so it has to be pasted by hand; the rest of the text can stay. Every member's addon reads the code from there.
2. **Each player** adds their Battle.net battletag where the bot asks for it (so it knows who you are on Discord), downloads the companion program (links below) and starts it next to the game. It finds WoW by itself.
3. Play in **windowed** or **windowed fullscreen** mode (an exclusive fullscreen screenshot can be black), and type `/reload` once: the companion gets the code from the addon at that moment.

Your next death or level-up shows up on Discord with a screenshot. `/wos discord` stops sending your events at any time.

## In game

- **Level-ups**: a golden banner with its own sound, a chat line, for every level of every guildmate. Your own level-ups are posted in guild chat too.
- **Deaths**: a bloody red banner with a skull, its own sound, and a chat line with the level, the zone and **who killed them** (with its level; falls, drowning and lava count too).
- **Duels lost against a guildmate**: an iron banner with broken swords and its own sound, on everyone's screen. In French, a random sentence ("X a terrassé Y", "Y s'est fait hagar par X"...), the same for the whole guild.
- **Guild map**: guildmates with the addon appear on the world map in their class color, other continents included (Azeroth view), with level, zone and the age of the position on hover. Updated every 15 seconds, shared only with your guild. Don't want to be seen? Untick it in `/wos options`.
- **Guild roster** (`/wos`): name, level, zone, last seen and number of deaths of every member.
- **No guild yet?** Make up a code (`swf1.` followed by anything, see Getting started): `/wos code <code>` shares everything (banners, duels, map) with everyone who pasted the same one, until the guild exists.

Deaths are only shared inside your own guild.

**English and French**: the addon follows your game client's language. Prefer the other one? `/wos lang en` or `/wos lang fr`, or the Language setting in `/wos options`.

## On Discord (optional)

With your guild's Discord bot and the companion program (Windows and macOS):

- your **deaths** and **level-ups** are posted with a screenshot of your screen at that moment
- **duels won against guildmates** are posted with the winner's screenshot, both players mentioned
- **killing blows** on players of the other faction are posted with the killer's screenshot, and the victim's name when the game shows it (English and French clients)
- a **ranking**: duels won against guildmates and killing blows on players of the other faction
- your **level per class** for the bot's member directory

Officers set it up once by pasting the bot's code into the guild information (see Getting started). Players have nothing to configure. The code is kept by all your characters, even a new one not yet in the guild.

Privacy: only **your own** events are sent, to **your guild's** bot, with your character name, level, class, zone and Battle.net battletag (so the bot can find your Discord account). Nothing is sent without the companion program and a code from your guild.

**Download the companion program** (only for the optional Discord part, the addon itself is the one on this page):

- [Windows (.exe)](https://github.com/Alencruser/wall-of-shame-forever/releases/download/companion-v0.4.0/WallOfShameCompanion.exe)
- [macOS Apple Silicon, M1 and later (.dmg)](https://github.com/Alencruser/wall-of-shame-forever/releases/download/companion-v0.4.0/WallOfShameCompanion.dmg)
- [macOS Intel (.dmg)](https://github.com/Alencruser/wall-of-shame-forever/releases/download/companion-v0.4.0/WallOfShameCompanion-Intel.dmg)

Not signed: Windows shows "Windows protected your PC" (More info > Run anyway); macOS asks to confirm in System Settings > Privacy & Security (Open Anyway). Release page and source code: [companion v0.4.0 on GitHub](https://github.com/Alencruser/wall-of-shame-forever/releases/tag/companion-v0.4.0).

## Connection code (Discord bot only)

Only for the Discord part, for whoever runs the guild's bot. Players and guilds without a bot never need this. The code tells the companion where the bot is and which key it accepts:

```
swf1.<base64url of {"url":"<https address of the bot>","key":"<your guild's key>"}, without the = padding>
```

For example `{"url":"https://bot.example.com/shamewall/deaths","key":"MyGuildKey"}` gives `swf1.eyJ1cmwiOiJodHRwczovL2JvdC5leGFtcGxlLmNvbS9zaGFtZXdhbGwvZGVhdGhzIiwia2V5IjoiTXlHdWlsZEtleSJ9`.

- **Build one**: in a terminal, `python -c "import base64,json; print('swf1.' + base64.urlsafe_b64encode(json.dumps({'url': 'https://bot.example.com/shamewall/deaths', 'key': 'MyGuildKey'}, separators=(',', ':')).encode()).decode().rstrip('='))"`, or any base64url tool.
- **The bot**: the address must be `https`. The companion sends your events to it as described in the [bot API](https://github.com/Alencruser/wall-of-shame-forever/blob/main/docs/bot-api.md), with the key in the `Authorization: Bearer` header; any bot that follows it works.
- A made-up code without a bot address (like `swf1.MyGroup-2026`) works in game only: the companion ignores it.
- The guild information holds 500 characters: a bot code takes about 140, so keep the bot address short.

## Commands

| Command | |
|---|---|
| `/wos` | open the guild roster |
| `/wos options` | open the options: all banners or only your own, sound and its volume, language, test button (also in the game menu > Options > AddOns) |
| `/wos log` | last 20 level-ups and deaths |
| `/wos guild` | toggle your level-ups in guild chat |
| `/wos popup` | toggle all banners (and their sound) |
| `/wos self` | toggle banners for your own level-ups, deaths and lost duels |
| `/wos sound` | toggle sound |
| `/wos map` | show/hide yourself on the guild's world map |
| `/wos volume 20\|40\|60\|80\|100` | volume of the banner sounds |
| `/wos strip <position>` | where the companion's strip shows: `topleft` (default), `top`, `topright`, `left`, `right`, `bottomleft`, `bottom`, `bottomright` (also in `/wos options`) |
| `/wos lang auto\|en\|fr` | addon language: auto follows the game client (default), or force English or French |
| `/wos test` | preview the banners |
| `/wos code <code>` | without a guild: your own Discord code (in a guild, paste it into the guild information instead) |
| `/wos discord` | toggle sending your events to Discord |
| `/wos flush` | reload the UI so the companion gets pending events |
| `/wos help` | all commands |

## Credits

Based on **Memento Forever** by **alexauer** (MIT license), translated to English and extended. The banner font is Lilita One by Juan Montoreano (SIL Open Font License 1.1). Released under the MIT license.
