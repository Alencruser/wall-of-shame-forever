# Wall of Shame Forever

## v0.2.1 (2026-11-05)

- WoW Forever: characters have a first and a last name ("Chamy Chan"), which the game gave the
  addon as name and realm. The addon now recognizes its own player: no more second level-up
  banner, no own pin on the map, duels won are counted for the bot again, and the bot gets
  the real name and realm. The double lines in the roster window are merged

## v0.2.0 (2026-11-04)

- New banners for level-ups, deaths and duels; one level-up banner for every class
- Duel lost against a guildmate: the loser reports it, the whole guild gets a banner
  and a chat line (older versions ignore it)
- French translation of every in-game text. The addon follows the game client's language;
  `/wos lang auto|en|fr` or the options panel forces English or French
- French banners: "X est mort contre Y" with the killer, and a random sentence for duels
  ("X a terrassé Y", "X vient de bouler Y", "X a ragdoll Y", "X a plié en deux Y",
  "Y s'est fait hagar par X", "X a rincé Y", "X a fumé Y", "X a corrigé Y",
  "Y s'est fait sécher par X", "Y s'est fait rouler dessus par X"), drawn by the loser so the
  whole guild sees the same one; falls, drowning, lava and fire have sentences of their own
  ("X a testé la gravité", "X a oublié de respirer", "X a fini à point"...), drawn by the dead;
  long titles go on two lines instead of being cut
- Own sounds for the level-up, death and duel banners (media/sounds); the game's sounds
  are only used if the client refuses the file
- Options panel (`/wos options`, Options button in the roster, game menu > Options > AddOns):
  all banners or only your own, sound on/off and its volume (also `/wos volume`), language,
  and a button to test the banners. The slash commands still work
- Turning the banners off also silences their sounds: never a sound without its banner
- Guild map: guildmates with the addon on the world map (class color, tooltip with level,
  zone and age of the position), other continents included. Own position sent every 15 s
  when moving (every 2 min otherwise), only inside the guild; in a dungeon the last spot
  stays, faded. "Show me on the map" in the options or `/wos map` to hide yourself
- Without a guild: everyone with the same code sees every announcement. The game refuses addon
  messages on custom channels and lets an addon write on a channel only during a player action,
  so the messages go as hidden chat lines on the code channel, sent at the next key press
  (position every 30 s instead of 15). The channel name no longer depends on how the client
  formats hexadecimal numbers
- `/wos debug`: guild, code, code channel, players seen and the last messages received
- Duel banner: text lowered below the broken swords; a title on two lines goes down to size 14
  so the zone line still fits
- Guild map: pins drawn with the addon's own image (disc in the class colour, black ring), the
  client's party icon being missing on some clients
- Banner font: Lilita One (SIL Open Font License 1.1), replaces UnifrakturMaguntia

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
