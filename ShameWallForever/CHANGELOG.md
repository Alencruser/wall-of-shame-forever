# Shame Wall Forever

## v0.1.0 (unreleased)

- Renamed to Shame Wall Forever: folder, SavedVariables `ShameWallForeverDB`, slash commands
  `/swf` and `/shamewall`.
- Own network (addon prefix `SHAMEWALL`): no longer talks to Memento Forever users.
- Death notices show the killer and its level (also sent to guildmates; older versions ignore it).
- Own deaths for the companion program (on-screen strip + SavedVariables outbox), on as soon as
  an officer sets the guild up with `/swf code <code>` (stored in the guild information).
  `/swf discord` turns it off.
- Without a guild, `/swf code <code>` shares deaths in game with everyone who pasted the same
  code (hidden private channel) and sends them to Discord.
- Leaving the guild removes its Discord code.
- Leaderboard events: duels won against guildmates, killing blows on players of the other faction.
- Level-ups posted on Discord right away (strip), `/swf striptest level` to try it.
- Levels sent to the guild's bot (at login and on level-up), with the Battle.net battletag so the
  bot can find the Discord member: highest level per class in the battletag directory and /activite.
- `/swf flush`, `/swf striptest`.

## Memento Forever v1.0.2-en (2026-11-03)

- English translation of every in-game text, the roster window and the readme.
- Slash commands renamed: `gilde` -> `guild`, `selbst` -> `self`, `ton` -> `sound`.
- Network prefix and message format unchanged: compatible with the German v1.0.2.

## [v1.0.2](https://github.com/alexauer/memento-forever/tree/v1.0.2) (2026-11-01)

Original release by Alex, see https://github.com/alexauer/memento-forever/releases

- feat: use class banners with built-in emblems (#4)
- feat: show banners for own level-ups and deaths (#3), toggled with `/mf selbst`
