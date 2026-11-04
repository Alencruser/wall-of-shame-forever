# Wall of Shame Forever companion

Small Windows program that sends **your own** deaths to the guild's Discord bot.

- **Realtime**: when you die, the addon shows a small strip of colored squares in the top-left
  corner for 3 seconds. The companion reads it from the screen (WoW must be the active window)
  and takes a screenshot of the death screen at the same moment.
- **Fallback**: every death is also kept in the addon's SavedVariables. WoW writes that file on
  `/reload`, logout or exit, and the companion sends what the strip missed (no screenshot).

A death is never sent twice (event id).

## Setup

Players have nothing to configure: install the addon, start the companion.

- **Officers, once per guild**: type `/wos code <code from the bot>` in game. The addon writes
  the code into the guild information (only ranks allowed to edit it can do this). Every
  member's addon reads it there, including members who join or log in later, and the
  companion picks it up from the addon's SavedVariables (written on `/reload` or logout).
  Until then, deaths wait in the companion and are sent as soon as the code shows up.
  The guild information stays free for real news: the addon adds one line
  `Code companion: swf1....` (about 140 of the 500 characters) and later only replaces the
  code inside it. Officers can edit the rest freely; if the line is deleted, members keep
  the last code they saw.
- **Before the guild exists** (server launch): each player types `/wos code <code from the
  bot>` once in game, then `/reload`. Everyone with the same code shares deaths in game
  through a hidden private channel (name and password derived from the code), and the
  companion gets the code from the SavedVariables as usual. Once in a guild, the addon
  switches back to the guild channel, and the officers' code replaces the personal one.
- **Leaving the guild** (or being kicked, even while offline) removes the code from the
  addon. The companion forgets it at the next `/reload` or logout and drops deaths still
  waiting, so nothing reaches the old guild's bot.
- **Players**: start the companion. The WoW folder is found automatically (see below).
  `/wos striptest` in game checks that the strip is read.
- `--dry-run` saves events and screenshots to `out/` instead of sending them;
  `config.example.toml` documents the optional settings.

To run from source:

```
python -m venv .venv
.venv\Scripts\pip install -r requirements.txt
.venv\Scripts\python wallofshame_companion.py
```

## Finding WoW

The companion can live anywhere. It looks for game folders (`_forever_`, `_classic_era_`...)
that contain `Interface\AddOns\WallOfShameForever`, in this order, and again every 30 s:

1. `wow_path` from `config.toml` (then nothing else)
2. the running WoW process (path of `Wow.exe`)
3. its own location, if it sits inside a game folder
4. the Blizzard registry key `InstallPath` (and the sibling game folders)
5. the usual install folders on every drive (`Program Files (x86)\World of Warcraft`, ...)

WoW must run in windowed or windowed fullscreen mode: an exclusive fullscreen capture can be black.

The companion is not code-signed: on first launch Windows may show "Windows protected your PC".
Click **More info**, then **Run anyway**.

## Test locally (e.g. on WoW Classic)

The addon runs on Classic Era too (same APIs). To try the whole chain on your PC:

1. Copy `WallOfShameForever` into `World of Warcraft\_classic_era_\Interface\AddOns\` and tick
   **Load out of date AddOns** in the AddOn list (or put the number from
   `/dump select(4, GetBuildInfo())` after `## Interface:` in the `.toc`).
2. Start the bot's local receiver (bot-bagarre): `npm run shamewall:local -- <deaths channel id>
   <level-ups channel id>`. It prints a connection code for `http://127.0.0.1:8787`: plain
   http is accepted only for this PC.
3. Start the companion (`.venv\Scripts\python wallofshame_companion.py`), WoW in windowed mode.
4. In game, on a character **without a guild**: `/wos code <code>`, then `/reload`.
5. `/wos striptest` and `/wos striptest level` post TEST cards (deleted after a minute); then
   die or level up for real.

## Connect your own bot

The companion is not tied to any bot: it sends to whatever the connection code points to.
To plug in your guild's own bot, you need three things.

### 1. An HTTPS endpoint

A public `https://` URL that accepts `POST` requests (`http://` is refused by the companion).
A Discord webhook URL cannot be used directly: your bot sits in between, checks the key and
posts to Discord itself.

### 2. A guild key

Any long random secret, kept on the bot side, for example:

```
python -c "import secrets; print(secrets.token_urlsafe(24))"
```

### 3. The connection code for your players

The code is `swf1.` followed by the base64url (no `=` padding) of
`{"url": "<your endpoint>", "key": "<your guild key>"}`. Your bot can build it, or from this
folder:

```
.venv\Scripts\python -c "import connection; print(connection.encode('https://your-bot.example/deaths', 'YOUR_GUILD_KEY'))"
```

Give it to your officers (admin-only bot command, private message...). One officer types
`/wos code <code>` in game and the whole guild gets it through the guild information.

### What the endpoint must do

For every request (full format in [`../docs/bot-api.md`](../docs/bot-api.md)):

| Check | Reply |
|---|---|
| `Authorization: Bearer <key>` is not your guild key | `401`, post nothing |
| `guild` / `realm` in the `event` field are not your guild | `403`, post nothing |
| `id` already received (the companion retries after network errors) | `200`, post nothing |
| `test` is `true` (`/wos striptest`) | `200`, post nothing or post to a test channel |
| otherwise | post the death to your Discord channel (`screenshot` file when present), `200` |

Any other error code makes the companion retry later (5 s, then up to 5 min).

### Changing the key

Someone left the guild with the code? Generate a new key, build the new code, and an officer
types `/wos code <new code>`: the guild information is updated, old codes get `401`, and
queued deaths are sent again with the new code.

## The .exe (background app)

`WallOfShameCompanion.exe` has no console window, only an icon in the notification area (Bagarre
Club logo), like the TrollDiscord client. Its menu shows the status (WoW folder found, bot,
last event sent) and has **Open log**, **Start with Windows** and **Quit**.

- **First launch** (from Downloads or anywhere): it copies itself to
  `%LOCALAPPDATA%\WallOfShameCompanion`, starts with Windows (quoted `HKCU\...\Run` entry), adds
  itself to **Settings > Apps > Installed apps** with an Uninstall button, and starts in the
  background. No admin rights. The downloaded file can be deleted.
- **Update**: launch a newer `.exe` the same way: it stops the running one and replaces it.
- **Uninstall**: from Windows Settings (or `WallOfShameCompanion.exe --uninstall`): stops it,
  removes the startup entry and the folder (settings, log, state).
- One instance at a time. `config.toml`, `state.json` and `log.txt` live in the install folder.

Build (`assets/icon.png` and `assets/icon.ico` come from the Bagarre Club logo):

```
.venv\Scripts\pip install -r requirements.txt -r requirements-dev.txt
.venv\Scripts\python build.py
```

From source, `python app.py` runs the tray app without installing anything, and
`python wallofshame_companion.py` the console version (`--dry-run` works with both).

## macOS

Same companion, strip and screenshots included: `WallOfShameCompanion.app`, an icon in the menu
bar (no Dock icon). Shared as `WallOfShameCompanion.dmg` for Apple Silicon Macs (M1 and later)
and `WallOfShameCompanion-Intel.dmg` for Intel Macs.

- **First launch**: open the `.dmg` (double click), then the app inside. It is not signed with an Apple certificate: macOS says
  it cannot check it. Open **System Settings > Privacy & Security**, click **Open Anyway** next to
  the message (older macOS: right-click the app > **Open**). The app then copies itself to
  `~/Applications`, opens at login (`~/Library/LaunchAgents/com.wallofshame.companion.plist`) and
  starts in the menu bar. The `.dmg` can then be ejected and deleted.
- **Screen Recording permission**: macOS asks for it on first launch. Allow the companion in
  **System Settings > Privacy & Security > Screen Recording**, then quit it from its menu and
  reopen it (`~/Applications/WallOfShameCompanion.app`). Without it, events still go to Discord on
  `/reload` or logout, but without screenshots; the menu shows **Allow screen recording…**. After
  an update, macOS may ask again.
- **Uninstall**: menu bar icon > **Uninstall…** (removes the app, the login item and
  `~/Library/Application Support/WallOfShameCompanion`).
- The WoW window must be the active one, windowed or fullscreen. The strip is searched near the
  window's corner (title bar included) and Retina screens are handled (2 pixels per point).

The `.app` can only be built on a Mac: the GitHub Actions workflow `companion` builds it (and the
Windows `.exe`) on GitHub's machines. For players, push a tag `companion-v0.2.0`: the `.exe` and
the `.dmg` are published as they are in a GitHub Release. Actions tab > **companion** > **Run
workflow** is for tests: GitHub zips the files of a run (unzip twice on a Mac). On a
Mac: `python3 -m venv .venv && .venv/bin/pip install -r requirements.txt -r requirements-dev.txt
&& .venv/bin/python build.py`.

Private builds with the guild's code built in (`build_private.py`) are Windows only for now: the
workflow must never get the code, since builds of a public repository can be downloaded. Mac players
use the public build and paste the code once in game (`/wos code <code>`, then `/reload`), until the
guild exists; then the officers' code arrives by itself.

The system-specific code is in `platform_win.py` and `platform_mac.py` (same functions, picked by
`osplat.py`); everything else is shared.

## Tests

```
.venv\Scripts\pip install -r requirements-dev.txt
.venv\Scripts\python -m unittest discover -s tests
```

The tests run the addon's real Lua encoder (via lupa) and decode the rendered strip.

The bot contract is in `../docs/bot-api.md`.
