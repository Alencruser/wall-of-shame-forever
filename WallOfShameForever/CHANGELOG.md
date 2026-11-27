# Wall of Shame Forever

## v0.9.2 (2026-11-27)

- Armurerie: the lines between talents (« this talent leads to that one ») are sent too, so the site draws
  them like the game
- Armurerie: items with a random suffix (« Cape de forestier de brigandage ») show with their suffix and its
  stats: WoW Forever gives it as a bonus of the item

## v0.9.1 (2026-11-27)

- Armurerie: talents read on WoW Forever, which has no Classic talent functions: the 3 trees, each talent's
  place, rank and spell come from the game's talent tree (the site's « Talents » tab was empty)

## v0.9.0 (2026-11-27)

- Armurerie: your gear (with enchants), the stats of the character sheet and your talents are sent to the
  site's new « Armurerie » page (guild members only), at login, when your gear or talents change, on a
  level-up and at logout. Needs the companion 0.8.3.
- New option « Montrer mon équipement et mes talents sur le site » (on by default, under « Carte et site »):
  off, your character is removed from the page

## v0.8.5 (2026-11-27)

- Orders: « À fabriquer (n) » and the window's « Commandes (n) » tab count the orders of the whole account;
  « Ce perso (n) » shows this character's, « Mes autres persos (n) » (was « Tous mes persos ») the other
  characters' only

## v0.8.4 (2026-11-27)

- Orders: an order to the character you play shows under « Ce perso » even when the realm differs (Forever
  changes it, or gives none): characters are matched by name only, like the bot
- The login line says for which character the orders are (« 1 commande en attente (pour Isa Lice) »)

## v0.8.3 (2026-11-27)

- Requests: gifts. On someone's request, « Je donne… » (replaces « Je m'en occupe ») announces how many you
  give (up to what is still needed) and how: by mail or in person. The line shows « Reçu 20/100 · 30 en
  attente (courrier 20, main propre 10) ».
- The asker is told in chat at login and confirms each gift (« À confirmer » → Reçu / Pas reçu); the received
  quantity goes up by itself. A gift not confirmed within 14 days counts as received. Needs the companion 0.8.2.
- Tooltip and loot line: the quantity still needed

## v0.8.2 (2026-11-27)

- Requests: dropping an item on the slot (or clicking the slot with an item in hand) puts it in the slot;
  the item stayed in hand before

## v0.8.1 (2026-11-27)

- Requests: Shift+click on an item in the bags puts it in the slot (and closes the stack split window
  the game opens), whatever the client uses for links

## v0.8.0 (2026-11-27)

- Item requests: a new « Demandes » tab in the « Bagarre club » window. Ask the guild for an item (drop it
  on the slot or Shift+click it: bags, quest log, a link), with a quantity, an optional reward and a note.
  The guild sees the open requests in the tab and in the item's tooltip (« Asked by … »), and a chat line
  when looting one; « I'm on it » tells the asker, who closes the request. Needs companion 0.8.0
- Activities: a click on an activity opens its window (date, organizer, levels, the group by role) where
  you sign up with the character you play (choose your role for a dungeon) or leave; the Discord card
  follows. Needs companion 0.8.0
- My orders: cancel an order still pending (« Cancel », with a confirmation)

## v0.7.2 (2026-11-27)

- Rogues: the lockpicking skill is sent with the professions (to the guild's bot and site, where the
  Grimoire ranks the rogues), and shown in a new Lockpicking column of the window's Guild tab

## v0.7.1 (2026-11-27)

- The guild's logo instead of the forge icon: minimap button, orders notification, empty orders list
  and the addon list

## v0.7.0 (2026-11-27)

- New look: one « Bagarre club » window in the guild site's style (red frame with a gold rim, titles
  on a red ribbon, gold buttons), with tabs: Guild (the roster), Orders, Achievements (your titles,
  achievements unlocked, the next ones, your bank ranking), Activities (the planned outings) and
  Goals (the guild bank goal and the guild challenges). The last three come from the guild's Discord
  bot through the companion (0.7.9 or later). The options window has the same look, and window
  animations can be turned off there

## v0.6.7 (2026-11-24)

- Craft orders, "My orders" tab: a done order now has a **Received** button. Click it once you have
  the item: the artisan and the guild's site see it was handed over (needs companion 0.7.8). Done
  orders stay in the tab until they are received; nobody confirms within 14 days: received anyway

## v0.6.6 (2026-11-21)

- Fix: when the game gives no realm name (it happened on WoW Forever on 2026-11-21), the addon used
  the last name as the realm ("Miss" on realm "Kin") and the bot refused deaths, levels and scores.
  The addon now remembers each character's realm and uses the last one seen, or keeps the full name

## v0.6.4 (2026-11-20)

- Guild bank: when you open the guild bank, the addon reads its money log (deposits and
  withdrawals, no click on the tab needed) and the bank's balance, and sends them to the guild's
  Discord bot (needs companion 0.7.3). Nothing shows in game; a reading is sent only when the log
  changed

## v0.6.3 (2026-11-18)

- Craft orders window: a new "My orders" tab for the orders you placed, grouped by artisan: pending,
  done (with who to pick it up from) and refused (with the reason) for 7 days, and the artisan's
  reply. On the right, your shopping list: the materials of your pending orders, for one artisan or
  in total, with how many you have and how many are missing. With the auction house open, click a
  material to search it there. The "To craft" tab is unchanged (needs companion 0.7.2)

## v0.6.2 (2026-11-18)

- Craft orders window twice as wide: your orders on the left, their materials on the right. Click a
  buyer's name for their materials, or Total for all your orders. Each material shows how many you
  have against how many are needed (bags and bank), green when you have enough, red when you are
  short, with the number of items still missing. The counts follow your bags as you loot or buy.
  Hover an order for its own materials and the reply you gave the buyer on the orders website
  (needs companion 0.7.1, which brings the materials)
- Professions: a profession level change made while Discord sharing was off is now sent once it is
  back on; a new connection code sends your professions again; unlearning every profession, or
  unlearning one and learning it again, no longer leaves old recipes behind

## v0.6.1 (2026-11-17)

- Profession levels without opening anything: fishing, gathering and the others are read at login,
  at logout and whenever a skill point is gained (a new reading only when a level changed). Recipes
  are still read when a profession window opens, and the ones already known are kept

## v0.6.0 (2026-11-16)

- Craft orders: guildmates order an item from your profession on the guild's Discord, and you see
  the orders in game. Click the new minimap button (a badge shows how many are waiting) or type
  `/wos commandes`: orders grouped by the character who asked, with the item, quantity and note.
  Mark one done, or refuse it with an optional reason; the buyer is told on Discord. Orders arrive
  at login or /reload (companion 0.7.0, which writes them for the addon). `/wos minimap` hides or
  shows the button
- A death was sometimes sent twice (hunters: a second report a few seconds later, without the
  killer). The addon now counts one death per life, and sends the bot a technical report when the
  game repeats a death, to find out why

## v0.5.0 (2026-11-13)

- Professions for the guild's Discord bot: when you open a profession window, the addon notes the
  recipes you know in it (with their color: orange, yellow, green, grey) and the level of all your
  professions, gathering included. The companion sends them on /reload or logout (companion 0.6.0).
  Nothing to do and nothing shown in game: open each profession once, then they stay up to date
  every time you open it

## v0.4.4 (2026-11-10)

- The Discord code is no longer removed when a character has no guild: the addon's settings are
  shared by every character of the account, so a reroll or an alt not yet in the guild used to remove
  the code for all of them. The code stays (a code in the guild information still replaces it), and
  a guildless character's events still go to the bot
- The level waiting for the companion is rewritten with the current guild (a reroll invited after
  its level was queued)
- `/wos striptest` is open to every player (the bot no longer keeps tests for its admins)

## v0.4.3 (2026-11-07)

- Fixed a Lua error in combat ("attempt to index local 'msg' (a secret string value)"): the game
  hides some chat text from addons during a fight, the addon now skips it

## v0.4.2 (2026-11-07)

- WoW Forever: the victim of a killing blow is named on Discord. With no dead enemy in
  view, the addon reads the game's Combat Log chat tab (refilled at the kill): your kill line
  ("You have slain X!" / "Vous tue X."), monsters left out, or else the last player you hit before
  the honor line. English and French clients; otherwise the victim stays on the screenshot
- In a guild, the companion code is pasted by hand into the guild information (WoW Forever does
  not let addons write there): see the CurseForge page

## v0.4.1 (2026-11-06)

- WoW Forever: monsters no longer posted as killing blows. On this client the game's statistic
  "World Killing Blows" counts monsters too, so a killing blow on a player now needs that
  statistic and the honorable kills to go up together. A player too low to give honor is not
  counted
- Nothing counted as a killing blow while dead, or in the 30 seconds after your own death

## v0.4.0 (2026-11-05)

- WoW Forever: killing blows on enemy players are counted again, from the game's own statistic
  "World Killing Blows" (the combat log is closed to addons). The victim is the dead enemy player
  in view when there is one
- Killing blows go out live on the strip: the bot posts them with a screenshot of the killer's
  screen in its killing blows channel (companion 0.4.0). `/wos striptest kill` to try it

## v0.3.1 (2026-11-05)

- WoW Forever: the killer is back on death banners and on Discord. Blizzard closes the combat
  log to addons on this client, so the addon now reads the game's death recap instead (the mob
  or player who landed the last hit, or a fall, drowning, lava...)
- Killing blows on enemy players cannot be counted on WoW Forever (combat log closed; back in
  v0.4.0)

## v0.3.0 (2026-11-05)

- Position of the companion's strip: top left (default), top center, top right, middle left,
  middle right, bottom left, bottom center or bottom right, never the middle of the screen.
  A small 3 x 3 screen in `/wos options` (the chosen box in gold, a golden preview on the game
  screen for 2 seconds), or `/wos strip <position>`. Outside the top left it needs companion
  0.3.0, which looks at every position by itself and keeps the strip out of the screenshot

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
