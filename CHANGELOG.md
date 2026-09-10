# BiS Gamba - Changelog

## 1.1.0

First public release. A shared high/low gold gambling table for raid nights, in
the BiS theme.

- **The table.** Type a roll range, hit start, and the game is posted in raid.
  People join by typing `1` in chat - no addon needed - or with the button.
  Class-portrait (2D) or 3D views, one fixed grid so switching never moves
  anything. Last call counts down and the rolls start themselves; highest wins,
  lowest pays the difference. Winner cheers, loser cries.
- **One window for everyone.** Host and player see the same buttons in the same
  places; what you can't do is greyed, never hidden. Anyone can host the next
  round and the crown moves to them. Hides itself in combat.
- **Who owes who.** Every result nets to a debt ledger that survives logout.
  **pay** opens the trade and hands you the gold in a copy box to paste (no addon
  can fill it for you on this client), then settles the ledger itself - only the
  person owed announces it, so nobody clears a debt by fibbing.
- **Leaderboard** built from a shared round ledger, each round stamped with the
  guild it was played in, so a guildie's bad night in a pug can't drag the guild
  board down. A new guildie can adopt the most complete ledger with one button.
- **Sound and voices.** Short motifs mark last call, your turn, wins and losses;
  with FojjiCore installed they're spoken by one of its voice packs. Never the
  raid-warning sound.
- **A settings window** - `/gamba config`, or the options button - in a clean
  flat panel: table, ledger, sound and display, all in BiS violet.
- **A BiS> header** that cycles the game's state - whose table, the stakes, who
  still owes a roll - instead of cluttering your chat.
- **Plays well with the rest of BiS.** Carries the shared BiS channel, so just
  having Gamba installed helps summoners see where you are; and a healer's rez
  cast is announced to a BiS Innervate raid even if you don't run Innervate.

`/gamba` opens the table, `/gamba help` lists every command.

## 1.1.0-rc9

- FojjiCore's latest build dropped the "Brittney" voice pack we defaulted to.
  Nothing broke - `auto` just fell silent to the motifs - but it stopped
  speaking out of the box. `auto` now speaks in **whatever voice you picked in
  FojjiCore itself**; failing that it prefers **Arabella**, and failing that
  takes whatever pack FojjiCore lists first - so a future rename can't mute it
  again. Picking a pack by name (`/gamba voice stacy`) was unaffected - it
  already matched their new prefixed names.

## 1.1.0-rc8

- Chat lines pared back, Apple-spare: one idea per `·`, the rules stated once at
  the open and not repeated on every line. Open is
  *"BiS Gamba · HIGH / LOW · /roll 100 · low pays high the gap, up to 99g · 1 to
  join"*, last call *"· last call · 10s · /roll 100 · 1 to join"*, the go
  *"· rolls open · HIGH / LOW /roll 100 now · 2 in"*, the result
  *"· Kum 90 over Gnomer 10 · Gnomer owes Kum 80g"*. Same for the tie, forfeit,
  reroll and straggler lines.

## 1.1.0-rc7

- Countdown beep trimmed to just **3 and 2** (was 5..2). Screen still counts
  every second.
- At zero, a roller no longer hears both "go" and "your turn" - the "go" cue is
  skipped for anyone who's about to roll, so they get only "your turn"; watchers
  still hear "go".

## 1.1.0-rc6

- Last call still counts a full ten, but only beeps the final **5, 4, 3, 2** -
  the 10..6 ticks were drowning other cues, and the 1 stacked on top of the
  "go" that fires at zero. The portrait still counts every second on screen.

## 1.1.0-rc5

- The **options** header button now toggles the settings window - click to open,
  click again to close.

## 1.1.0-rc4

- A proper settings window (`/gamba config`, or the **options** button in the
  header): a flat panel with a left rail of tabs - Table, Ledger, Sound,
  Display - in the FojjiCore mould but BiS violet, wiring every toggle, slider
  and picker to the same options the slash commands set. Hand-built widgets,
  layered shades, no Blizzard skin.

## 1.1.0-rc3

- Spoken cues. With FojjiCore installed the sound cues are said by one of its
  voice packs (Brittney by default) - "table", "stack up", a counted last call,
  "safe", "doom on you". Played straight from FojjiCore's folder, nothing
  bundled; a cue without a line, or no FojjiCore at all, keeps the motif.
  `/gamba voice list | <name> | off | auto`.

## 1.1.0-rc2

- Fix: the payer's own debt did not clear after a trade (the person who was owed
  saw it clear, the one who paid did not). The money frames read zero the instant
  a trade closes, so settlement now uses the most gold seen on the table during
  the trade, and a zero read at the accept no longer wins over it.

## 1.1.0-rc1

First public release candidate. A shared high/low gold gambling table for raid
nights, in the BiS UI theme.

**Playing a round.** Whoever hits **start** hosts a table and it posts the game,
the roll range and the stakes in chat -
*"BiS Gamba: HIGH vs LOW - /roll 100, lowest pays the highest the difference -
up to 99g. Type 1 to join, -1 to leave."* People join by typing `1` in chat (no
addon needed). **last call** gives a ten-second countdown - counted down on the
host's own portrait - before the rolls start themselves; **start now** skips it.
Highest wins, lowest pays the difference (`/gamba flat` for the full wager).
Ties re-roll among the tied; if everyone lands on the same number the whole
table rerolls. The table shuts the instant rolls are called: nobody can join
after seeing a roll land, nobody can duck out of a round they are losing, and a
seated player who never rolls forfeits.

**One window for everyone.** Host and player see the same buttons in the same
places - what you may not do is greyed, never moved. Anyone can open the next
table once a round is finished; hosting and the crown pass to them. Two views,
2D class portraits and 3D models, share one fixed grid so switching never
resizes anything. The window hides itself in combat and comes back after;
**never open anything** stops it appearing on its own at all.

**Who owes who.** Every result goes to a debt ledger that survives logout and
nets debts between the same two people. **pay** opens a trade with the next
person you owe and, once they accept, shows the amount in a copy box to Ctrl+C
into the gold field (no addon can fill it directly on this client - Blizzard
blocks every route, which is why Gargul can't either). It whispers the balance
only to people without the addon. Completed trades settle the ledger by
themselves, both directions, partial payments included.

**Leaderboard.** Biggest all-time winners and losers, with win-loss records,
built from a shared ledger of settled rounds. Each round carries a host-stamped
id, so players who saw different rounds trade ids and fill each other's gaps -
automatically, or with **sync**. A brand-new guildie can take somebody's whole
ledger (**adopt**), a restore rather than a merge. Rounds are stamped with the
guild they were played in, and the board shows guild rounds only by default, so
a bad night in a pug never lands on the guild's board. **reset all** wipes the
board for everyone, each person confirming on their own machine; debts are kept.

**Sound.** Short motifs built from the Un'Goro Simon-game tones (with sound-kit
fallbacks that always play) mark last call, your turn to roll, winning, losing
and payouts. Never the raid-warning sound. On the effects channel by default;
`/gamba sound` to toggle, `probe`/`test`/`kit <id>` to tune.

**Safety.** Addon messages are only heard from people in your group. A result is
only believed for a round this client actually watched, with an amount that
follows from the rolls; only the person owed can mark a debt paid; unsolicited
rounds and future-dated or oversized rounds are refused. A disconnected host's
table is released.
