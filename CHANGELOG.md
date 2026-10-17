# BiS Gamba - Changelog

## Unreleased

- **The team game.** Press **team** (or `/bisgamba team 100`) and the number is the wager for a team table. People join as usual; it needs an even number, 4 or more. When the rolls are called the sides are dealt at random and the wager is shared out: 100 between 5 a side is everyone `/roll 20`. If it doesn't split evenly the table calls an **audible** and moves the wager to the nearest even split (100 three ways is 99; exactly in between goes up). Each side's rolls are added up; a tie means both sides roll again; then **each loser pays one winner**, their share of the gap (or of the wager, with flat pay). Your side stands on the left, theirs on the right, every seat the same size, each side's total over it.
- **The table, redone.** You stand big, in 3D, on the left, with your buttons under you - join, roll, leave, pay - and only the next one to press is lit. Everyone else sits on the right. The window keeps the BiS 1.43:1 shape.
- **Short progress bars** when the table is working: a second when somebody joins ("Mare joins · 4 in · even, ready to deal"), while the sides are dealt, while they are added up.

- **Deathroll, as a duel.** You stand on the left in 3D, your opponent on the right, the rolls run down the middle. Pick them from your party or raid (a list you scroll), or type a guildmate's whole name. Type the gold: the rolls start there, so 500g is `/roll 500` - or tick "for fun" to roll without betting. They accept or decline. The challenger rolls first; the button says your exact roll (`/roll 450` after they rolled 450), and whoever rolls a 1 pays. The winner cheers, the loser cries. The gold goes in the same debts book as a high/low round, with the same "pay" and trade, and on the leaderboard. Button bottom left on the table, or `/bisgamba dr <name>`.

- **Your debts first.** The debts list shows what you owe and are owed at the top. Everybody else's fold into one line ("4 debts between others") that opens if you want to see them.
- **Debts nobody's addon can see paid clear themselves.** When neither player runs BiS Gamba, no addon ever sees their trade, so their debt used to sit there until someone clicked "paid". It now says "on their honour" and leaves the book the day after.
- **Paying someone without the addon counts.** When you pay through a trade and the person you paid doesn't run BiS Gamba, your own completed trade clears the debt for everyone with the addon, not just for you.

## 1.6.0

- **BiSGambaAPI** - other BiS addons can read the leaderboard, standings, debts and recent rounds, and open the window. It's read-only: nothing else can move gold, settle a debt or place a bet.
- The addon list shows **BiS>Gamba**, like its category.

## 1.5.0

- **Your guild can see you on BiS Tools' map.** Every BiS addon now shares your spot with guildmates while you move - every 15 seconds in a small guild, slower as it grows, never from inside an instance. On by default; `/biscomm share off` (or `on`) switches it for every BiS addon at once.
- The shared BiS channel no longer hooks the summon popup on Forever, where hooking Blizzard's code can break it until a restart.

## 1.4.0

- **Options window**: the BiS shape (1.43:1) with settings in even columns, a help strip at the bottom, and it no longer opens on top of another BiS window.

- **The command is `/bisgamba` now**, like the rest of the BiS family (`/bish`, `/bist`, `/bisg`). `/gamba` and `/gamble` still work.

- Res claims (RezComm minor 4) are never sent into the chat lockdown, and a claim the game asks to retry is sent once more.

- Shared messaging library updated (LibBiSComm minor 10): after a boss, when the game lifts its chat lockdown, BiS addons say hello again so group lists stay current; it respects a realm that blocks addon messages, picks the raid channel only when the game confirms you are in a raid, and ignores anyone flooding it.

- **Lighter in a raid.** Other addons' messages (DBM, BigWigs, ...) are dropped on one question
  instead of three. Shared libs: LibBiSComm minor 9 (one roster walk per roster change), BiS>
  prompt minor 5 (the window header no longer re-measures its text every frame).

- **Seat labels fit their seat.** A seat is 46 px: long names ("Kumsecrat.") and "owes 160g"
  ran past it. Names are cut at 7 letters, the money under a seat reads -160g / +160g (98.7k
  from five figures), and who owes whom is in the seat's tooltip.

## 1.3.5

- **No more errors from chat the game hides.** On WoW Forever the game can hide what is said in
  chat from addons for a while - most likely during boss fights. Gamba reads rolls, the "1"s typed
  to join and its own messages out of chat, and reading hidden text is an error. Now it skips
  anything hidden instead.
- **The table is told.** If that happens during a round, Gamba says once that rolls typed right
  now cannot be counted, so everyone knows to roll again once it lets up.
- **`/gamba hidden`** shows how often the game hid chat this session.

## 1.3.4

- LibBiSComm minor 6: summon API moved to C_SummonInfo on 2.5.6 — the phantom-summon filter works again.

## 1.3.3

- Shared console minor 4: the blinking cursor in the `BiS>` header is its own text now, so
  the words beside it no longer shift a hair every half second.

## 1.3.2

- Options window: Escape closes it (shared kit minor 2).
- Shared console minor 3: a header slot that toggles no longer hogs the rotation.
- Harness asserts the options kit minor, the TOC line for it, and the bytes of every embed.

## 1.3.1

- **Shared BiS channel updated to lib minor 5** - a phantom "summon by someone"
  no longer fires on bystanders when anyone else in the raid gets a summon (the
  2.5.x client wakes every summoner's addon, not just the one being pulled). No
  visible change to Gamba itself; it carries the fixed library for the raid.

## 1.3.0

- **Streaks over the head.** A seat on a run wears a badge from the shared round
  ledger - **W2**+ in gold for a win streak, **L2**+ in warn-pink for a lose
  streak, shown once you're two deep. Only a real result counts: a win is topping
  the roll, a loss is paying the gamble - everyone in the middle is neither, and
  never tracked. It follows your board scope, so a pug night doesn't touch the
  guild streaks.
- **The table reacts to the extremes.** Roll a **1** and you cry while the rest of
  the table laughs at you; roll the **max** and you flex while they cheer. An
  ordinary roll is still just your own little reaction - the whole table only
  moves for a 1 or a max.
- **Fix: debt text no longer bleeds onto the footer.** A long "owes 1g to
  <name>" under a seat wraps to a few lines; the seat now reserves room for all
  of them, so it stops overlapping the **sound** row along the bottom.

- **New options window.** The settings panel is now the shared BiS options window
  - one narrow flat panel with sections and simple controls (toggles, pickers,
    steppers), matching the rest of the BiS addons. Open it with the **options**
    button or `/gamba config`; it parks beside the table.
- **The table starts small and grows.** An empty table is a short strip; it
  expands as people join, up to thirteen to a row, so a full 25-man is two rows
  instead of a giant grid. The portraits are more compact - the 3D models fit
  more players on screen. The control buttons never move.
- **Voice leans to Illidan on TBC.** With FojjiCore installed, `auto` now speaks
  as Illidan when his pack is there, and otherwise follows whatever voice you set
  in FojjiCore - it never sticks to a pack name that a FojjiCore update might drop
  (which used to leave the cues silently on the tones).

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
