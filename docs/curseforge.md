# CurseForge page

## Summary (short description field)

Shares every level-up and death of your guild with on-screen banners, and can post them on your guild's Discord with screenshots, duels and a PvP ranking.

## Description

# Wall of Shame Forever

**Every level-up and every death of your guild, on everyone's screen.** And, if your guild wants it, on your Discord too, screenshot included.

Made for **WoW Forever**. Everyone in the guild installs the addon.

## In game

- **Level-ups**: a golden banner with its own sound, a chat line, for every level of every guildmate. Your own level-ups are posted in guild chat too.
- **Deaths**: a bloody red banner with a skull, its own sound, and a chat line with the level, the zone and **who killed them** (with its level; falls, drowning and lava count too).
- **Duels lost against a guildmate**: an iron banner with broken swords and its own sound for the loser, on everyone's screen.
- **Guild map**: guildmates with the addon appear on the world map in their class color, other continents included (Azeroth view), with level, zone and the age of the position on hover. Updated every 15 seconds, shared only with your guild. Don't want to be seen? Untick it in `/wos options`.
- **Guild roster** (`/wos`): name, level, zone, last seen and number of deaths of every member.
- **No guild yet?** `/wos code <code>` shares deaths with everyone who pasted the same code, until the guild exists.

Deaths are only shared inside your own guild.

**English and French**: the addon follows your game client's language. Prefer the other one? `/wos lang en` or `/wos lang fr`, or the Language setting in `/wos options`.

## On Discord (optional)

With your guild's Discord bot and the companion program (Windows and macOS):

- your **deaths** and **level-ups** are posted with a screenshot of your screen at that moment
- **duels won against guildmates** are posted with the winner's screenshot, both players mentioned
- a **ranking**: duels won against guildmates and killing blows on players of the other faction
- your **level per class** for the bot's member directory

Officers set it up once in game: `/wos code <code from the bot>` (stored in the guild information). Players have nothing to configure. Leaving the guild removes the code.

Privacy: only **your own** events are sent, to **your guild's** bot, with your character name, level, class, zone and Battle.net battletag (so the bot can find your Discord account). Nothing is sent without the companion program and a code from your guild.

**Companion program:** source code and downloads on GitHub, [github.com/Alencruser/wall-of-shame-forever](https://github.com/Alencruser/wall-of-shame-forever). The repository opens on **launch day (November 4)**. It is **only for the optional Discord companion**: the addon itself is the one on this page, nothing else to download to play with it.

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
| `/wos lang auto\|en\|fr` | addon language: auto follows the game client (default), or force English or French |
| `/wos test` | preview the banners |
| `/wos code <code>` | officers: set the Discord code for the guild (without a guild: your own) |
| `/wos discord` | toggle sending your events to Discord |
| `/wos flush` | reload the UI so the companion gets pending events |
| `/wos help` | all commands |

## Credits

Based on **Memento Forever** by **alexauer** (MIT license), translated to English and extended. The banner font is Lilita One by Juan Montoreano (SIL Open Font License 1.1). Released under the MIT license.
