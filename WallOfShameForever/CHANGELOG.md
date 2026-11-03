# Wall of Shame Forever

## v0.1.0 (2026-11-03)

First release, based on Memento Forever v1.0.2 by alexauer (MIT), translated to English.

- Gothic banners, chat lines and sounds for every level-up and death of your guildmates
- Guild roster window (`/wos`): level, zone, last seen, deaths
- Death notices with the killer and its level (falls, drowning and lava too)
- Without a guild yet: `/wos code <code>` shares deaths with everyone who pasted the same code
- Optional Discord integration with your guild's bot and the companion program: deaths and
  level-ups with a screenshot, duels won against guildmates, killing blows on the other faction,
  levels for the bot's member directory. Officers set it up once with `/wos code <code>`
  (stored in the guild information); leaving the guild removes the code
- Test commands for bot admins: `/wos striptest`, `/wos striptest level`, `/wos striptest duel`
- Own addon network (`WALLOFSHAME`): independent from Memento Forever

## Memento Forever v1.0.2-en (2026-11-03)

- English translation of every in-game text, the roster window and the readme.
- Slash commands renamed: `gilde` -> `guild`, `selbst` -> `self`, `ton` -> `sound`.
- Network prefix and message format unchanged: compatible with the German v1.0.2.

## [v1.0.2](https://github.com/alexauer/memento-forever/tree/v1.0.2) (2026-11-01)

Original release by Alex, see https://github.com/alexauer/memento-forever/releases

- feat: use class banners with built-in emblems (#4)
- feat: show banners for own level-ups and deaths (#3), toggled with `/mf selbst`
