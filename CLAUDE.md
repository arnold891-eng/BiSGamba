Read ../_bisdev/CLAUDE.md first.

## Layout (Gamba only)

- `BiSGamba.toc`: the load order, and the only place the version lives (`## Version`). `release.ps1`, the harness and LibBiSComm all read it from there.
- `BiSGamba.lua`: the whole addon, about 3.9k lines, split into sections by `----` banners:
  - theme fallback and sounds
  - DB defaults and migrations (`dbver`, currently 6)
  - guild and roll parsing
  - `Ledger`
  - `Comm` (the `BiSGamba` addon-message prefix)
  - `Game` (the state machine `IDLE → JOIN → ROLL → DONE`)
  - round-ledger adoption and `Trade`
  - `UI` (2d/3d seat grid)
  - Options (the `Own` owners)
  - slash commands (`/gamba`, `/bisgamba`, `/gamble`)
- `Libs/`: embedded copies of LibBiSComm-1.0, RezComm-1.0 and BiSTheme Console/Options. See the libs rules in `../_bisdev/CLAUDE.md`.
- `dev/tests.lua`: the headless harness. It loads every Lua file the TOC lists, in order, and needs the addon to expose `BiSGamba` (as `G`) and its event frame as `G._ev`. It fails if an internal leaks into `_G` or if the `dbver` migrations break. Use `runTimers(maxDelay)` for countdowns. `dev/harness.lua` is only a shim that `dofile`s it.
- `dev/release.ps1`: builds the zip (without `dev/` or the dotfiles) and uploads it to CurseForge project 1682133. It sends the top entry of `CHANGELOG.md` as the changelog.
- `.github/workflows/check.yml`: calls the reusable CI workflow in `bisdev`.
