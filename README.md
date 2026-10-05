# KartRace — Roblox kart racing MVP

## What's in this folder

| File / folder | What it is |
|---|---|
| `src/RaceServer.server.luau` | The server script: builds the track and lobby, runs races, saves wins. Shows up in Studio as **ServerScriptService > RaceServer**. |
| `src/RaceClient.client.luau` | The player script: kart driving, camera, on-screen UI. Shows up in Studio as **StarterPlayer > StarterPlayerScripts > RaceClient**. |
| `default.project.json` | A map for Rojo that says which file goes where in Studio. You normally never edit it. |
| `CLAUDE.md` | Notes Claude Code reads automatically when you run `claude` in this folder. |
| `KartRace.rbxlx` | A ready-made place file to open in Studio. |

The `.server.luau` / `.client.luau` endings tell Rojo whether a file becomes a Script or a LocalScript.

## One-time setup (Windows)

1. **Unzip this folder** somewhere easy, e.g. `C:\Users\<you>\Documents\KartRace`.
2. **Get Rojo:** download `rojo-7.7.0-windows-x86_64.zip` from
   https://github.com/rojo-rbx/rojo/releases, unzip it, and put `rojo.exe` inside this KartRace folder.
3. **Open a terminal in this folder:** open the folder in File Explorer, click the address bar, type `powershell`, press Enter.
4. **Install the Rojo plugin into Studio** (close Studio first):
   ```powershell
   .\rojo plugin install
   ```

## Every time you work on the game

1. Open `KartRace.rbxlx` in Roblox Studio.
2. In the PowerShell window in this folder, start the sync:
   ```powershell
   .\rojo serve
   ```
   Leave this window open.
3. In Studio, open the **Plugins** tab → **Rojo** → **Connect**.
4. Open a **second** PowerShell window in this folder and run `claude`. Ask for changes; they appear in Studio within a second or two.
5. Press **Play** in Studio to test. When something errors, copy the red text from **View → Output** and paste it to Claude.
6. When you're happy, **File → Save** (or Publish) in Studio so the place file has the latest code.

## Rules of thumb

- **Edit the `.luau` files, not the scripts inside Studio.** Rojo copies files → Studio, so changes made in Studio's script editor get overwritten.
- **Keep backups.** Copy the folder before big changes, or learn basic `git` (Claude Code can set it up for you).
- The leaderboard only works in a published game with **Game Settings → Security → Enable Studio Access to API Services** turned on.
