Shame Wall Forever - Level-ups, deaths and guild roster for WoW Forever
==================================================================
==================================================================
INSTALLATION
1. Copy the "ShameWallForever" folder into
   World of Warcraft\_forever_\Interface\AddOns\
   (the exact folder name for Forever may differ, e.g. _classic_era_).
   ShameWallForever.toc and ShameWallForever.lua must sit directly inside the folder.
2. Start the game, click "AddOns" at the bottom left of the character
   selection screen and enable Shame Wall Forever.
3. Everyone in the guild installs the addon - only then are there popups and deaths.
==================================================================
WHAT IT DOES
- When someone with the addon levels up, everyone sees a chat line and a
  gothic banner on EVERY level: golden thorn frame with pointed-arch crown and
  rosette, class medallion, Fraktur lettering, plus the level-up fanfare.
- On death: black iron banner with blood, skull and its own sound.
- Every own level-up is posted automatically in guild chat
  (visible to people without the addon too).
- When someone with the addon dies, all guildmates with the addon see a death
  notice with level and zone. Deaths are only shared inside your own guild.
- Level-ups of members WITHOUT the addon are detected as soon as the game
  refreshes the guild roster (chat line only; their deaths cannot be seen).
- /swf opens a list of all members: name, level, zone, last seen, deaths.
- Death notices show the killer and its level when the game knows them.
- Leaderboard on the guild's Discord: duels won against guildmates and killing blows
  on players of the other faction (sent by the companion on /reload or logout).
- Optional: with the companion program and /swf discord, your own deaths are posted
  to your guild's Discord (level, class, zone, killer, screenshot of the death screen).
==================================================================
COMMANDS
/swf         open/close the guild roster
/swf log     last 20 level-ups and deaths
/swf guild   toggle own level-ups in guild chat
/swf popup   toggle banners
/swf self    toggle banners for your own level-ups and deaths
/swf sound   toggle sound
/swf sync    request the current state from the guild
/swf test    preview banners and sound (only visible to you)
/swf discord toggle sending your own deaths to Discord (on by default)
/swf code <code>  officers: set the Discord bot's code for the whole guild.
                  Without a guild: your own code, deaths are shared in game
                  with everyone who pasted the same code.
                  Leaving your guild removes its code.
/swf flush   reload the UI so the companion gets pending deaths
/swf striptest         send a test death through the companion (bot admins only)
/swf striptest level   send a test level-up through the companion (bot admins only)
/swf striptest duel    send a test duel win through the companion (bot admins only)
==================================================================
IF THE ADDON IS MARKED AS "OUT OF DATE"
The addon targets interface 16001 (Forever). If a patch changes the number:
Type in chat:   /dump select(4, GetBuildInfo())
Put the number shown after "## Interface:" in ShameWallForever.toc.
Or tick "Load out of date AddOns" in the AddOn list.
==================================================================
CREDITS
Based on Memento Forever by alexauer (MIT license).
Shame Wall Forever uses its own network: it does not see Memento Forever users,
so everyone in the guild needs Shame Wall Forever.
==================================================================
FONT
The Fraktur font in the media folder is "UnifrakturMaguntia" under the
SIL Open Font License 1.1 (see media/Unifraktur-OFL.txt).
