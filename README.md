# BiS Gamba

A shared high/low gold gambling table for raid nights, in the BiS UI theme.
World of Warcraft TBC Classic Anniversary (Interface 20506).

`/gamba` opens the window. `/gamba help` lists every command.

## A round

1. Type the roll range in the box (100, 200, 310, whatever) and hit **start**.
   The addon posts the game, the range and the stakes in raid (or party / say),
   spare and one idea per dot:
   *"BiS Gamba · HIGH / LOW · /roll 100 · low pays high the gap, up to 99g · 1 to
   join, -1 to leave."* On a flat table (`/gamba flat`) that reads *"low pays high
   100g flat"*.
2. People join by typing `1` (or `-1` to back out) in chat - no addon needed.
   Addon users can use the **join** button instead. They appear at the table as
   portraits: their class icon (2D) or a race/sex stand-in (3D) when out of
   range, the real character when close.
3. **last call** posts a ten-second warning and counts down on the host's own
   portrait; when it runs out the rolls start by themselves. **start now** skips
   the wait. Either way the addon posts *"BiS Gamba · rolls open · HIGH / LOW
   /roll 100 now · 2 in"*.
4. **The table shuts the moment rolls are called.** Nobody joins after seeing a
   roll land, nobody walks out of a round they are losing, and anybody who was
   called to roll and doesn't forfeits. **roll** rolls the right range for you -
   it only lights up once rolls are called, and only the first roll counts.
5. When everyone has rolled the round settles after a three-second grace;
   **end** settles now with whoever rolled. Highest wins, lowest pays the
   difference. Ties re-roll among the tied; if *everyone* rolls the same number
   there is nothing to pay, so the whole table rerolls.
6. The winner cheers, the loser cries, everyone in between kneels, shrugs or
   flexes by how close they came to paying.

## One window for everyone

Host and player see the same buttons in the same places - what you may not do is
greyed out, never hidden or moved. A player has **join**/**roll** live and the
wager box, **start**, **last call** and **end** greyed beside them; the host has
them all. The host can **leave** the table and still run the game. Once a round
is finished anyone can hit **start** to host the next one - hosting, and the
crown above the portrait, move to them.

Two views, **2d** class portraits and **3d** models, share one fixed grid, so
switching never moves or resizes anything (`/gamba view`). The window hides
itself when you enter combat and comes back when you leave (`/gamba combat`).
The footer switches: **never open anything** (nothing appears on its own -
no window when a game starts, none back after combat, no pop-ups from other
people), **sound**, and **open when a game starts**.

## Who owes who

Every result goes to a ledger that survives logout and nets debts between the
same two people. Under each portrait: *owes 160g / to Gnomer*, *gets 95g*.
**debts** opens the full list with a **paid** button per line.

**pay** (which shows what you owe) opens a trade with the next person you owe and
waits a beat in case they open it first. Once they accept, a panel appears beside
the trade window with the amount in a copy box - already selected, so it is
Ctrl+C then Ctrl+V into the gold field - and whispers them the balance if they
are not running the addon. No addon can fill that gold box directly on this
client: Blizzard blocks the money call, tainting the edit boxes throws, and
PickupPlayerMoney is protected, which is why Gargul can't do it either. When the
trade completes the ledger settles itself - both directions, partial payments
included - and only the person who was owed announces it, so nobody can clear a
debt they owe by fibbing.

## Leaderboard

**leaderboard** shows the biggest all-time winners and losers with win-loss
records. At the table the all-time winner wears a gold aura, the biggest loser
burns, and the host wears a crown.

The board is built from a shared ledger of settled rounds, each stamped with a
host id, so two people who saw different rounds trade ids and fill each other's
gaps - by itself when the window opens, or on **sync**. A brand-new guildie can
take somebody's whole ledger with the **sync** button that appears beside
whoever holds the most (`/gamba adopt`); it is a restore, not a merge, and
nothing of yours is touched until their whole ledger has arrived.

Each round is stamped with the guild it was played in, and the board shows guild
rounds only by default, so a guildie's bad night in a pug can't drag the guild's
board down. The button at the top of the panel switches guild-only / everyone
(`/gamba scope`). **reset all** wipes the board for the whole group - each
person confirms on their own machine, and debts are kept.

## Sound

Short motifs mark last call, your turn to roll, a tie, winning, losing and
payouts. They are built from the Un'Goro Simon-game tones, with sound-kit IDs as
a fallback that always plays. The last-call countdown only beeps at three and
two - the portrait still counts every second, but the sound stays out of the way
of the other cues, and the roller hears only their own "your turn" at zero, not
the group's "go" on top of it. Never the raid-warning sound. On the effects
channel by default. `/gamba sound` toggles; `sound test` plays every cue,
`sound probe` shows what each settled on, `sound kit <id>` auditions any kit
ID, `sound master` moves them up if they get lost.

**Voices.** If [FojjiCore](https://www.curseforge.com/wow/addons/fojjicore) is
installed, the cues are spoken instead, out of its voice packs - Arabella by
default, or whatever FojjiCore lists first if that pack isn't in the build you
have (their lineup shifts between updates, so `auto` never leans on one name).
Nothing is copied: the lines play straight from that addon's folder, and any cue
a pack has no line for (or any pack that isn't there) falls back to its motif.
The vocabulary is raid callouts, so a table opening is *"table"*, last call is
*"stack up"*, the countdown is counted, a win is *"safe"* and a loss is *"doom on
you"*. `/gamba voice list` shows the packs, `/gamba voice stacy` (any piece of
the name) picks one, `voice off` goes back to the tones, `voice auto` back to the
default.

## Fair play and safety

Addon messages are only heard from people in your group, never whispers from
strangers. A result is only believed for a round this client actually watched,
with both rolls seen and an amount that follows from them - a crafted result is
refused. Only the creditor can mark a debt paid. Unsolicited, future-dated or
oversized rounds are refused, so the ledger can't be poisoned or flooded. A
disconnected host's table is released so the next person can deal.

## Settings

Everything below is a `/gamba` command, but there is also a window for it:
**options** in the header (click again to close it), or `/gamba config`. A flat panel with a left rail -
**Table** (roll range, stakes, timers, joining), **Ledger** (board scope,
whisper, wipes), **Sound** (cues, channel, voice pack), **Display** (view,
scale, zoom, minimap, combat, pop-up behaviour) - in BiS violet.

## Commands

```
/gamba              toggle the table
/gamba start [N]    open a table for /roll N (default 100)
/gamba call [secs]  last call: a countdown, then the rolls start themselves
/gamba go           stop taking joins, start rolling now
/gamba join         join / leave somebody else's table (types 1 / -1)
/gamba roll         roll the right range
/gamba view [2d|3d]  switch between 2D and 3D portraits
/gamba end          settle with the rolls in / close the table
/gamba nudge        name the people still to roll, in chat
/gamba remind N     seconds before the straggler reminder (0 = off)
/gamba pay [name]   trade the gold to the next person you owe
/gamba config       the settings window (options | settings)
/gamba debts        print who owes who
/gamba board        the leaderboard, biggest winners first
/gamba sync         swap missing rounds with the group so the board agrees
/gamba adopt [who]  throw your ledger away and take theirs whole
/gamba rounds       the round ledger the leaderboard is built from
/gamba rebuild      recompute the leaderboard from the ledger
/gamba history      the last ten rounds
/gamba scope [guild|all]   whether pug rounds count on the board
/gamba wipestats yes       throw away your ledger
/gamba wipestats all       ask everyone with the addon to wipe theirs too
/gamba paid A B     mark A's debt to B paid
/gamba clear        wipe every debt
/gamba flat         toggle: loser pays the difference (default) or the full wager
/gamba autojoin     toggle seating anyone who /rolls the range (default off)
/gamba quiet        toggle chat announcements
/gamba popup        toggle: open the window when a host starts a game
/gamba combat       toggle hiding the window while you're in combat
/gamba neveropen    toggle: nothing ever appears on its own
/gamba sound        toggle the cues (sound test | probe | kit <id> | sfx|master)
/gamba voice        speak the cues with a FojjiCore voice pack (voice list | <name> | off | auto)
/gamba whisper      toggle whispering the balance to people without the addon
/gamba users        who else you have seen running BiS Gamba
/gamba autocopy     toggle selecting the amount for you when a trade opens
/gamba scale X | zoom X | npc Race 2|3 id | minimap | fixtrade | tradedebug | reset
```

Minimap button: left opens the table, right rolls.

## Development

`lua5.1 dev/harness.lua` from the addon folder runs 311 headless checks over
rounds, ties, forfeits, the countdown, sync, the ledger, guild scoping, the
trade payout and every slash command. `luacheck BiSGamba.lua` is clean. The
`dev/` folder is not shipped in the release zip.
