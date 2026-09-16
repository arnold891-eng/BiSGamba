# BiS Gamba

High/low gold gambling for raid nights: a shared table, a debt ledger, one-click trade payouts and a leaderboard. The target client is WoW TBC Anniversary (`## Interface: 20506`, Lua 5.1). The author is Kumlust, the license is MIT, and the CurseForge project is 1682133.

## Layout

- `BiSGamba.toc`: the load order. The version lives here (`## Version`) and is the single source of truth, read by the release script, the harness and LibBiSComm.
- `BiSGamba.lua`: the entire addon, about 3.9k lines. Its sections are marked by `----` banners: theme fallback, sounds, DB defaults and migrations (`dbver`, currently 6), guild, roll parsing, `Ledger`, `Comm` (the `BiSGamba` addon-message prefix), `Game` (the state machine `IDLE → JOIN → ROLL → DONE`), round-ledger adoption, `Trade`, `UI` (2d/3d seat grid), Options (`Own` owners), and slash commands (`/gamba`, `/bisgamba`, `/gamble`).
- `Libs/`: **embedded copies; never edit them here.** Their canonical sources are one folder up:
  - `Libs/LibBiSComm-1.0/` ← `../_bisdev/LibBiSComm-1.0/` (shared `BiS` channel, currently minor 5)
  - `Libs/RezComm-1.0/` ← `../_bisdev/RezComm-1.0/`
  - `Libs/BiSTheme/Console.lua` and `Options.lua` ← `../BiSTheme/` (options kit minor 2)

  To change a lib, edit the canonical copy, then run `../_bisdev/sync.ps1`. The harness and `release.ps1` both fail if the bytes differ.
- `dev/tests.lua`: the headless harness (see below). `dev/harness.lua` is only a shim that `dofile`s it.
- `dev/release.ps1`: zips the addon (without `dev/` or the dotfiles) into `Downloads` and uploads it to CurseForge. It sends the top `CHANGELOG.md` entry as the changelog.
- `.github/workflows/check.yml`: CI calls the reusable workflow in `arnold891-eng/bisdev`, which runs `_bisdev/check.sh BiSGamba`.

## Running the tests

Run the harness from this folder, because it opens `BiSGamba.toc` and the libs by relative path:

```bash
lua5.1 dev/tests.lua
```

It prints `N checks, M failed` and exits with code 1 if anything is red. Failures print as `FAIL: <what>`. On Windows with Lua for Windows, the binary is `lua` rather than `lua5.1`; make sure it really is 5.1.

For the full house check (every `dev/*.lua` suite plus `bislint` over the TOC's Lua), run this from `Interface/AddOns`:

```bash
_bisdev/check.sh BiSGamba
```

## How the harness works (keep it true)

- **The TOC is the loader** (debt 13). The harness `loadfile`s every `.lua` line of `BiSGamba.toc` in order, just as the client does, and asserts that `BiSGamba.lua` is the last line. A file missing from the TOC is therefore also missing under test.
- It stubs the WoW API itself: frames record points, text, size and scripts. `C_Timer.After` queues into `timers`, which `runTimers(maxDelay)` drains. `SendChatMessage` goes to `said` (whispers go to `whispers`), `RandomRoll` goes to `rolled`, and addon messages go to `addon`. The trade money edit boxes throw "forbidden object" if the addon writes to them.
- The addon must expose `BiSGamba` as a global table (`G`) and its event frame as `G._ev`. Tests drive it through `fire(event, ...)`, `from(sender, ...)` for addon messages, `SlashCmdList.BISGAMBA(...)`, and `G.UI.*Btn.scripts.OnClick()`.
- It starts from a pre-`dbver` save, so every migration must keep running. When you add a migration, bump `defaults.dbver` and update the `dbver == 6` assert.
- It asserts that none of the addon's internals leak into `_G` (`Stat`, `Trade`, `Game`, `UI`, ...). Keep new locals local and hang anything the tests need off `G`.
- Fences worth knowing:
  - The lib minors: `LibBiSComm.MINOR == 5` and `BiSTheme.OPTIONS_MINOR == 2`.
  - The addon registers with the TOC version rather than a literal (the stub returns `9.9.9-toc`).
  - No feature toggle may gate the shared channel.
  - Embedded libs must be byte-identical to their canonical copies. This is skipped with a note when the siblings aren't present.
- To add a test, write a new `---- banner` section before `slash + misc`, using `check(cond, "plain-English what")`. Include the actual value in the message when it helps diagnose a failure.

## Conventions

- Settings: each setting has one owner function in `Own`, called by both the options window and the slash handler, so the two never drift. The window reports the change in its `BiS>` prompt, and the slash handler adds the chat line.
- Theme: use `BiSTheme` when it's loaded, otherwise the inline palette at the top of `BiSGamba.lua`. That fallback fills in missing fields and never overwrites existing ones.
- Trust: a result is believed only for a round this client actually watched. Crafted messages are refused (there are tests for this).
- Nothing touches combat actions. The window just hides during combat.
- Line endings are LF (`.gitattributes`), except `*.ps1`, which uses CRLF.

## Releasing

1. Bump `## Version` in the TOC.
2. Add a `## x.y.z` entry at the top of `CHANGELOG.md`.
3. Get the harness green.
4. Run `dev/release.ps1`. It defaults to alpha; use `-Type release`, or `-ZipOnly` to skip the upload.

The token is read from `%USERPROFILE%\Downloads\curseforge-token.txt`. Commits that don't ship anything say "version unchanged, no release" in the message.
