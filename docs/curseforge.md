# CurseForge page

## Summary (short description field)

Every level-up and death of your guild, with gothic banners. Optional Discord wall of shame: deaths with a screenshot, level-ups, duels and a PvP ranking.

## Description

# Wall of Shame Forever

**Every level-up and every death of your guild, on everyone's screen.** And, if your guild wants it, on your Discord too, screenshot included.

Made for **WoW Forever**. Everyone in the guild installs the addon.

## In game

- **Level-ups**: a gothic banner with the class emblem, a chat line and the level-up fanfare, for every level of every guildmate. Your own level-ups are posted in guild chat too.
- **Deaths**: a black iron banner with blood and a skull, its own sound, and a chat line with the level, the zone and **who killed them** (with its level; falls, drowning and lava count too).
- **Guild roster** (`/wos`): name, level, zone, last seen and number of deaths of every member.
- **No guild yet?** `/wos code <code>` shares deaths with everyone who pasted the same code, until the guild exists.

Deaths are only shared inside your own guild.

## On Discord (optional)

With your guild's Discord bot and the Windows companion program:

- your **deaths** and **level-ups** are posted with a screenshot of your screen at that moment
- **duels won against guildmates** are posted with the winner's screenshot, both players mentioned
- a **ranking**: duels won against guildmates and killing blows on players of the other faction
- your **level per class** for the bot's member directory

Officers set it up once in game: `/wos code <code from the bot>` (stored in the guild information). Players have nothing to configure. Leaving the guild removes the code.

Privacy: only **your own** events are sent, to **your guild's** bot, with your character name, level, class, zone and Battle.net battletag (so the bot can find your Discord account). Nothing is sent without the companion program and a code from your guild.

## Commands

| Command | |
|---|---|
| `/wos` | open the guild roster |
| `/wos log` | last 20 level-ups and deaths |
| `/wos guild` | toggle your level-ups in guild chat |
| `/wos popup` | toggle banners |
| `/wos self` | toggle banners for your own level-ups and deaths |
| `/wos sound` | toggle sound |
| `/wos test` | preview the banners |
| `/wos code <code>` | officers: set the Discord code for the guild (without a guild: your own) |
| `/wos discord` | toggle sending your events to Discord |
| `/wos flush` | reload the UI so the companion gets pending events |
| `/wos help` | all commands |

## Credits

Based on **Memento Forever** by **alexauer** (MIT license), translated to English and extended. The Fraktur font is UnifrakturMaguntia (SIL Open Font License 1.1). Released under the MIT license.
