--[[--------------------------------------------------------------------------
  BiS Gamba
  High / low gold gambling for raid nights, in one small window.

  Flow:  a host opens a table (posts to group chat, people type 1) -> last call
         or start the rolls -> everyone /rolls 1-N -> highest wins, lowest pays
         the difference -> a ledger remembers who owes who and a leaderboard of
         settled rounds -> pay opens the trade and hands you the gold to paste.

  Everyone at the table is a portrait: a class icon (2D) or a race/sex stand-in
  NPC (3D) out of range, the real character when close. The winner cheers, the
  loser cries, the rest emote by how near they came to paying. The all-time
  winner wears a gold aura, the loser burns, the host wears a crown.

  Results, debts and the round ledger sync between addon users over addon
  messages; a result is only believed for a round this client actually watched.

  Nothing here is secure against a determined host. Nothing here touches combat
  actions - the window just hides while you fight.
----------------------------------------------------------------------------]]

local ADDON = ...

-- BiS Theme: the shared palette when it's loaded, the same values inline
-- otherwise. The embedded Libs\BiSTheme\Console.lua loads first and, with the
-- BiSTheme addon absent, leaves a partial BiSTheme (rgb/rgba/text only for the
-- prompt). So fill in whatever a real BiSTheme would also carry - skin, classRGB
-- - without clobbering anything already there. With the real addon present this
-- whole block is a no-op.
local T = BiSTheme or {}
do
  local hex = { bg="121020", surface="1a1730", sunken="221d3c", line="2a2446", line2="3a3260",
    ink="ece8f6", ink2="c6bedd", muted="968ead", accent="b980ff", accentSoft="2c2148",
    good="4fd0cf", warn="f08cb0", gold="e5c04a", slate="8fb4d6", dim="8e86a6" }
  local cache = {}
  local function rgb(name)
    local h = hex[name] or hex.ink
    local c = cache[h]
    if not c then
      c = { tonumber(h:sub(1,2),16)/255, tonumber(h:sub(3,4),16)/255, tonumber(h:sub(5,6),16)/255 }
      cache[h] = c
    end
    return c[1], c[2], c[3]
  end
  T.hex = T.hex or hex
  T.rgb = T.rgb or rgb
  T.rgba = T.rgba or function(n, a) local r, g, b = T.rgb(n); return r, g, b, (a or 1) end
  T.text = T.text or function(n, s) return "|cff" .. (hex[n] or hex.ink) .. tostring(s) .. "|r" end
  T.classRGB = T.classRGB or function(tok)
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[tok]
    if c then return c.r, c.g, c.b end
    return rgb("ink")
  end
  T.skin = T.skin or function(f, border)
    if not f.SetBackdrop then return end
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    f:SetBackdropColor(rgb("surface")); f:SetBackdropBorderColor(rgb(border or "line2"))
  end
end

local G = {}
_G.BiSGamba = G
G.T = T

local function Print(msg) DEFAULT_CHAT_FRAME:AddMessage(T.text("accent", "Gamba") .. " " .. tostring(msg)) end
local function Warn(msg) DEFAULT_CHAT_FRAME:AddMessage(T.text("accent", "Gamba") .. " " .. T.text("warn", tostring(msg))) end
G.Print = Print

local function Now() return (GetServerTime and GetServerTime()) or time() end
local function After(secs, fn) if C_Timer and C_Timer.After then C_Timer.After(secs, fn) else fn() end end
local function Bare(name)
  if not name then return nil end
  name = tostring(name)
  if Ambiguate then name = Ambiguate(name, "none") end
  return (name:match("^[^-]+")) or name
end
local function Commas(n)
  local s = tostring(math.floor(tonumber(n) or 0))
  local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
  return (out:gsub("^,", ""))
end
local function Gold(n) return Commas(n) .. "g" end

----------------------------------------------------------------------------
-- constants
----------------------------------------------------------------------------
local HEAD_H   = 76                 -- title + controls + status
local PAD      = 8
local MAX_ROLL = 1000000

-- Textured stand-ins per race and sex for people out of range: city guards and
-- innkeepers render with baked skin where the base player bodies come out white.
-- Same table BiS Campfire uses; /gamba npc <Race> <2|3> <id> to override.
local NPC = {
  Human    = { [2] = 68,    [3] = 6740  },
  Orc      = { [2] = 3296,  [3] = 6929  },
  Dwarf    = { [2] = 5595,  [3] = 5111  },
  NightElf = { [2] = 3589,  [3] = 4262  },
  Scourge  = { [2] = 5624,  [3] = 5688  },
  Tauren   = { [2] = 3084,  [3] = 6746  },
  Gnome    = { [2] = 7406,  [3] = 7955  },
  Troll    = { [2] = 10540, [3] = 10540 },
  BloodElf = { [2] = 16222, [3] = 16542 },
  Draenei  = { [2] = 16733, [3] = 16739 },
}
local WISP = 10045

-- animation ids
local ANIM = {
  stand = 0, talk = 60, exclaim = 64, question = 65, bow = 66, wave = 67, cheer = 68,
  dance = 69, laugh = 70, kneel = 75, cry = 77, chicken = 78, beg = 79, applaud = 80,
  shout = 81, flex = 82, shy = 83, point = 84, salute = 113, roar = 74,
}
G.ANIM = ANIM   -- exposed so the harness can name the reactions
-- how the people in between feel, from "nearly paid" to "nearly won"
local MOOD = {
  { ANIM.kneel, ANIM.beg, ANIM.shy },          -- bottom third: sweating
  { ANIM.talk, ANIM.wave, ANIM.question },     -- middle: meh
  { ANIM.laugh, ANIM.applaud, ANIM.flex, ANIM.dance },  -- top third: smug
}

local db                            -- the saved variables, set up just below

----------------------------------------------------------------------------
-- Sound
--
-- Little motifs rather than beeps. The four Simon-game tones from the Un'Goro
-- toy are actual musical notes and have shipped with the client since vanilla,
-- so they are the closest thing to an instrument we have; the bells and the
-- gong fill in underneath. Nothing here uses the raid-warning sound - that
-- belongs to the raid leader, and a gambling table has no business borrowing it
-- mid-pull.
----------------------------------------------------------------------------
-- Each note is a list of candidates, tried in order until the client says one
-- will actually play. File names first, because the Simon-game tones are proper
-- notes and make a far better phrase - but this client keeps most sounds as .ogg
-- rather than .wav and an addon cannot ask which, so every path is tried both
-- ways. Sound kit numbers come last and are the safety net: they are resolved by
-- the client rather than by path, which is why WeakAuras offers "sound by kit
-- ID" - those always work. /gamba sound probe shows what each note settled on.
local SIMON = "Sound\\Spells\\SimonGame_"
local NOTE = {
  -- the four tones, low to high
  blue   = { SIMON .. "LargeBlueTree",   839 },
  red    = { SIMON .. "LargeRedTree",    840 },
  green  = { SIMON .. "LargeGreenTree",  841 },
  yellow = { SIMON .. "LargeYellowTree", 846 },
  -- punctuation
  start  = { SIMON .. "Visual_GameStart", "Sound\\Doodad\\G_GongTroll01", 850 },
  level  = { SIMON .. "Visual_LevelStart", "Sound\\Doodad\\BellTollAlliance", 856 },
  bad    = { SIMON .. "Visual_BadPress", "Sound\\Doodad\\PortcullisActive_Closed", 847 },
  bell   = { "Sound\\Doodad\\BellTollAlliance", "Sound\\Doodad\\BellTollNightElf", 878 },
  gong   = { "Sound\\Doodad\\G_GongTroll01", "Sound\\Doodad\\BellTollHorde", 854 },
  chest  = { "Sound\\Doodad\\Wooden_Chest_Open", "Sound\\Interface\\LootCoinLarge", 862 },
}

-- { note, when } - seconds from the top of the phrase
local MOTIF = {
  open  = { { "level", 0 }, { "blue", 0.18 } },                       -- a table is open
  call  = { { "bell", 0 }, { "green", 0.30 } },                       -- last call
  tick  = { { "blue", 0 } },                                          -- ...and its clock
  tick3 = { { "red", 0 } },                                           -- the last three seconds
  go    = { { "start", 0 }, { "green", 0.16 } },                      -- roll now
  you   = { { "blue", 0 }, { "yellow", 0.12 } },                      -- your turn
  tie   = { { "red", 0 }, { "red", 0.20 } },                          -- tied
  redo  = { { "red", 0 }, { "yellow", 0.18 } },                       -- everybody level, roll again
  win   = { { "green", 0 }, { "yellow", 0.16 }, { "blue", 0.32 }, { "bell", 0.52 } },
  lose  = { { "bad", 0 }, { "gong", 0.22 } },
  done  = { { "yellow", 0 } },                                        -- a round you were not in
  paid  = { { "chest", 0 }, { "green", 0.18 } },                      -- gold changed hands
}

-- A voice on top: FojjiCore (Fojji's WeakAuras companion) ships eighteen
-- spoken callout packs under Interface\AddOns\FojjiCore\voice\<pack>\. They
-- are never copied here - the lines are played straight out of that folder when
-- it exists, and a cue whose line is missing (or when FojjiCore is not
-- installed) falls back to its motif. Their vocabulary is raid mechanics, so
-- each cue borrows the nearest phrase; the countdown uses her numbers.
local VOICE_LINE = {
  open = "Table", call = "Stack Up", go = "Go Forward", you = "Fixate on You", tie = "Linked",
  redo = "Spread Out", win = "Safe", lose = "Doom on You", done = "Clear", paid = "Blessing",
}
local VOICE_PREFER = "Illidan"   -- TBC flavour: "auto" leans to the Betrayer when he is installed

-- FojjiCore groups its packs with a prefix ("Flavour - Illidan", "Community -
-- Fojji <Numen>", "Chinese - Stacy"). Strip that group prefix and any trailing
-- "<...>" tag down to the bare voice name, so we can prefer a pack by short name.
-- This is BiSInnervate's Sound:ShortPack, kept identical so the family agrees.
local function ShortPack(name)
  name = tostring(name or "")
  name = name:gsub("^%s*%a[%a]-%s*%-%s*", "")   -- drop "Flavour - " / "Community - " / "Chinese - " ...
  name = name:gsub("%s*<[^>]*>%s*$", "")         -- drop a trailing "<Numen>" / "<who>"
  return (name:gsub("^%s+", ""):gsub("%s+$", ""))
end
G.ShortPack = ShortPack

local Sound = { last = {}, quiet = false, picked = {}, voice = {} }
G.Sound = Sound

--- The pack in use. "auto" resolves, in order: the voice the player already
--- picked in FojjiCore itself; else the first installed pack whose name carries
--- our preferred flavour (Illidan) - matched by name, so a "Flavour - Illidan"
--- still hits; else whatever FojjiCore lists first. It NEVER returns a hardcoded
--- pack name that must exist - that was the Brittney/Arabella silent failure,
--- where a dropped pack left auto falling back to the tones with nobody the
--- wiser. Walk the installed list every time instead.
local function VoicePack()
  local v = db.voice
  if v == false or v == "off" then return nil end
  local fc = _G.FojjiCore
  if v == nil or v == "auto" then
    if not fc then return nil end
    local packs, order = fc.voicePacks, fc.voicePackOrder
    -- 1. follow the voice the player set in FojjiCore, when it has one
    local db2 = _G.FojjiCoreDB
    if db2 and db2.ttsVoiceType == "custom" and db2.ttsVoicePack
       and packs and packs[db2.ttsVoicePack] then return db2.ttsVoicePack end
    if order then
      -- 2. our preferred flavour, matched by SHORT name across FojjiCore's prefixes
      for _, n in ipairs(order) do if ShortPack(n):lower() == VOICE_PREFER:lower() then return n end end
      -- 3. failing that, whatever it lists first (a real pack, never a stale name)
      return order[1]
    end
    return nil
  end
  return v
end

--- Where a phrase lives. FojjiCore's own table is exact (folder names differ
--- from pack names for a few); without it the file name is rebuilt the way
--- FojjiCore does - lower case, runs of anything but a-z0-9 become one _.
local function VoicePath(pack, phrase)
  local fc = _G.FojjiCore
  if fc and fc.voicePacks and fc.voicePacks[pack] then return fc.voicePacks[pack][phrase] end
  local file = phrase:lower():gsub("[^a-z0-9]+", "_"):gsub("^_+", ""):gsub("_+$", "")
  return "Interface\\AddOns\\FojjiCore\\voice\\" .. pack .. "\\" .. file .. ".ogg"
end

--- Play something already resolved: an exact file path, or a sound kit number.
local function PlayResolved(what, channel)
  if type(what) == "number" then
    if not PlaySound then return false end
    local ok, willPlay = pcall(PlaySound, what, channel)
    return ok and willPlay ~= false
  end
  if not PlaySoundFile then return false end
  local ok, willPlay = pcall(PlaySoundFile, what, channel)
  return ok and willPlay ~= false
end

--- Try one candidate; hand back the exact thing that worked, or nil. A file
--- name is tried both ways round, since we cannot ask which the client keeps.
local function TryOne(candidate, channel)
  if type(candidate) == "number" then
    if PlayResolved(candidate, channel) then return candidate end
    return nil
  end
  for _, ext in ipairs({ ".ogg", ".wav" }) do
    local path = candidate .. ext
    if PlayResolved(path, channel) then return path end
  end
  return nil
end

--- Play a note, working out once and for all which candidate this client has.
local function PlayNote(name)
  local channel = db.soundChannel or "Master"
  local picked = Sound.picked[name]
  if picked ~= nil then
    if picked == false then return false end
    return PlayResolved(picked, channel)     -- already exact: never re-decorated
  end
  for _, candidate in ipairs(NOTE[name] or {}) do
    local resolved = TryOne(candidate, channel)
    if resolved then
      Sound.picked[name] = resolved
      return true
    end
  end
  Sound.picked[name] = false
  return false
end

--- What each note settled on, for when none of it makes a sound.
function Sound.Probe()
  Sound.picked = {}
  Sound.quiet = false
  local names = {}
  for name in pairs(NOTE) do names[#names + 1] = name end
  table.sort(names)
  for i, name in ipairs(names) do
    After((i - 1) * 0.35, function()
      local ok = PlayNote(name)
      Print(("  %-7s %s"):format(name, ok and T.text("good", tostring(Sound.picked[name])) or T.text("warn", "nothing played")))
    end)
  end
end

--- Say a cue in the chosen voice. True when a line came out; nil means play
--- the motif instead. A line that failed once is not tried again this session.
local function PlayVoice(name, n)
  local pack = VoicePack()
  if not pack then return nil end
  local phrase = VOICE_LINE[name]
  if name == "tick" or name == "tick3" then phrase = (n and n >= 1 and n <= 10) and tostring(n) or nil end
  if not phrase then return nil end
  local key = pack .. "/" .. phrase
  local picked = Sound.voice[key]
  if picked == false then return nil end
  local channel = db.soundChannel or "Master"
  if picked then return PlayResolved(picked, channel) or nil end
  local path = VoicePath(pack, phrase)
  if path and PlayResolved(path, channel) then Sound.voice[key] = path; return true end
  Sound.voice[key] = false
  return nil
end

--- Play one phrase. Repeats inside a fifth of a second are dropped, so a cue
--- that fires from two places at once is still heard once. `n` is the seconds
--- left on a tick, for the spoken countdown.
function Sound.Play(name, n)
  if db.sound == false or Sound.quiet then return end
  local motif = MOTIF[name]
  if not motif then return end
  local now = GetTime()
  if Sound.last[name] and now - Sound.last[name] < 0.2 then return end
  Sound.last[name] = now
  if PlayVoice(name, n) then return end
  for _, note in ipairs(motif) do
    local which, when = note[1], note[2]
    if when <= 0 then
      if PlayNote(which) == false and not Sound.warned then
        Sound.warned = true
        Print("no sound came out - try " .. T.text("ink", "/gamba sound probe") .. " to see what this client has")
      end
    else
      After(when, function() PlayNote(which) end)
    end
  end
end

----------------------------------------------------------------------------
-- saved variables
----------------------------------------------------------------------------
local defaults = {
  wager = 100, payDiff = true, autoJoin = false, announce = true, grace = 3, dbver = 6, boardScope = "guild",
  scale = 1, view = "2d", portrait = 0.75, zoom = 0, z = 0, minimapAngle = 200, minimap = true, autoOpen = true, remind = 30, whisper = true, autoCopy = true, lastCall = 10, sound = true, soundChannel = "SFX", voice = "auto", neverOpen = false,
  combat = true,       -- hide the window while you are in combat
  users = {},          -- [name] = when we last heard their addon
  tradeDelay = 1.2, npc = {}, wisp = WISP,
  debts = {},          -- list of { from=, to=, amount= (gold), at= }
  history = {},        -- last rounds: { at=, max=, high=, low=, amount=, rolls={name=roll} }
  stats = {},          -- derived from base + rounds; never edited directly
  base = {},           -- what was on the books before rounds were recorded
  rounds = {},         -- [id] = { at, max, winner, loser, amount, host }
  seq = 0,             -- our own round counter, for stamping ids
}

local Rebuild                       -- defined with the round bookkeeping below

local function InitDB()
  BiSGambaDB = BiSGambaDB or {}
  db = BiSGambaDB
  -- read the version BEFORE the defaults fill it in, or every migration is skipped.
  -- No dbver on a non-empty table means it was saved before versions existed.
  local ver = tonumber(db.dbver) or (next(db) and 1 or defaults.dbver)
  for k, v in pairs(defaults) do
    if db[k] == nil then db[k] = (type(v) == "table") and {} or v end
  end
  -- 1.0 seated anyone who rolled; rolls from people not at the table are ignored now
  if ver < 2 then db.autoJoin = false end
  if ver < 3 then db.view = "2d" end
  if db.view ~= "2d" and db.view ~= "3d" then db.view = "2d" end
  -- stats used to be a bare net figure; keep it, give it somewhere to grow
  if ver < 4 then
    for name, v in pairs(db.stats) do
      if type(v) == "number" then
        db.stats[name] = { net = v, wins = 0, losses = 0, games = 0, best = 0, worst = 0 }
      end
    end
  end
  -- Records used to be tallied as rounds went by, which is why two people who
  -- saw the same rounds could disagree for ever. From here they are derived from
  -- the rounds themselves; whatever was already on the books becomes the base.
  if ver < 5 then
    db.base = {}
    for name, v in pairs(db.stats) do
      if type(v) == "table" then
        db.base[name] = { net = v.net or 0, wins = v.wins or 0, losses = v.losses or 0,
                          games = v.games or 0, best = v.best or 0, worst = v.worst or 0 }
      end
    end
  end
  -- the cues started out on the master channel, which talks over everything;
  -- they belong with the rest of the game's effects
  if ver < 6 and db.soundChannel == "Master" then db.soundChannel = "SFX" end
  db.dbver = defaults.dbver
  Rebuild()
  G.db = db
end

----------------------------------------------------------------------------
-- group lookups
----------------------------------------------------------------------------
local function MyName() return Bare(UnitName("player")) end

--- Our guild, or nil. Rounds are stamped with the guild they were played in, so
--- a guildie's bad night in a pug never lands on the guild's board.
local function MyGuild()
  if not GetGuildInfo then return nil end
  local name = GetGuildInfo("player")
  if name == nil or name == "" then return nil end
  return name
end
G.MyGuild = MyGuild

local function GroupUnits()
  local units = {}
  if IsInRaid and IsInRaid() then
    for i = 1, 40 do units[#units + 1] = "raid" .. i end
  else
    units[1] = "player"
    for i = 1, 4 do units[#units + 1] = "party" .. i end
  end
  return units
end

local function UnitFor(name)
  if name == MyName() then return "player" end
  for _, u in ipairs(GroupUnits()) do
    if UnitExists(u) and Bare(UnitName(u)) == name then return u end
  end
  return nil
end

local function InGroup(name)
  return UnitFor(name) ~= nil
end

local function Channel()
  if IsInRaid and IsInRaid() then return "RAID" end
  if (GetNumGroupMembers and GetNumGroupMembers() or 0) > 0 then return "PARTY" end
  return nil          -- solo: SAY from a timer or event handler is blocked, so just print
end

local function Say(text)
  local ch = Channel()
  if not db.announce or not ch then Print(text) return end
  SendChatMessage(text, ch)
end

----------------------------------------------------------------------------
-- the roll line: RANDOM_ROLL_RESULT = "%s rolls %d (%d-%d)"
----------------------------------------------------------------------------
local ROLL_PATTERN
do
  local fmt = RANDOM_ROLL_RESULT or "%s rolls %d (%d-%d)"
  local p = fmt:gsub("[%(%)%.%+%-%*%?%[%]%^%$]", "%%%0")
  p = p:gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)")
  ROLL_PATTERN = "^" .. p .. "$"
end
G.ROLL_PATTERN = ROLL_PATTERN

local function ParseRoll(msg)
  local who, roll, lo, hi = msg:match(ROLL_PATTERN)
  if not who then return nil end
  return Bare(who), tonumber(roll), tonumber(lo), tonumber(hi)
end
G.ParseRoll = ParseRoll

----------------------------------------------------------------------------
-- ledger: who owes who. Debts between the same two people net out.
----------------------------------------------------------------------------
local Ledger = {}
G.Ledger = Ledger

--- Every settled round, keyed by an id the host stamps on it. The leaderboard is
--- derived from these, so two people who saw different rounds can fill each
--- other's gaps and end up agreeing.
local MAX_ROUNDS = 400

local function BlankRecord()
  return { net = 0, wins = 0, losses = 0, games = 0, best = 0, worst = 0 }
end

--- Recompute every record from the rounds on file, on top of whatever was
--- carried over from before rounds were recorded.
--- "guild" counts only rounds played among guildmates; "all" counts everything.
--- With no guild there is nothing to protect, so the scope falls back to all.
function G.Scope()
  if db.boardScope ~= "guild" then return "all" end
  return MyGuild() and "guild" or "all"
end

function Rebuild()
  local out = {}
  local guildOnly = G.Scope() == "guild"
  local myGuild = MyGuild()
  local function rec(name)
    local r = out[name]
    if not r then r = BlankRecord(); out[name] = r end
    return r
  end
  for name, r in pairs(db.base or {}) do
    local o = rec(name)
    o.net, o.wins, o.losses = r.net or 0, r.wins or 0, r.losses or 0
    o.games, o.best, o.worst = r.games or 0, r.best or 0, r.worst or 0
  end
  for _, rd in pairs(db.rounds or {}) do
    local amount = tonumber(rd.amount) or 0
    -- a round only counts toward the guild board if it was played among guildmates
    local counts = not guildOnly or (rd.g ~= nil and rd.g == myGuild)
    if counts and rd.winner and rd.loser and amount > 0 then
      local w, l = rec(rd.winner), rec(rd.loser)
      w.net = w.net + amount; w.wins = w.wins + 1; w.games = w.games + 1
      if amount > w.best then w.best = amount end
      l.net = l.net - amount; l.losses = l.losses + 1; l.games = l.games + 1
      if amount > l.worst then l.worst = amount end
    end
  end
  db.stats = out
end
G.Rebuild = Rebuild

--- Drop the oldest rounds so the table cannot grow without end.
local function TrimRounds()
  local list = {}
  for id, rd in pairs(db.rounds) do list[#list + 1] = { id = id, at = rd.at or 0 } end
  if #list <= MAX_ROUNDS then return end
  table.sort(list, function(a, b) return a.at > b.at end)
  for i = MAX_ROUNDS + 1, #list do db.rounds[list[i].id] = nil end
end

--- Record one round. Returns true when it was new, and "conflict" when we
--- already hold that id with different figures - which should never happen, so
--- it is worth saying out loud rather than quietly picking a side.
local function AddRound(id, rd, overwrite)
  if not id or id == "" then return false end
  if not rd.winner or not rd.loser or not rd.amount or rd.amount <= 0 then return false end
  -- a round from the future, or for more than a roll can be, is not a round
  if (tonumber(rd.at) or 0) > Now() + 600 or rd.amount > MAX_ROLL then return false end
  local have = db.rounds[id]
  if have and not overwrite then
    if have.winner ~= rd.winner or have.loser ~= rd.loser or have.amount ~= rd.amount then
      return false, "conflict"
    end
    return false
  end
  db.rounds[id] = rd
  TrimRounds()
  Rebuild()
  return true
end
G.AddRound = AddRound

--- Throw the ledger away and start everyone at zero. Debts are left alone -
--- what people owe each other is not a scoreboard.
function G.WipeStats()
  db.rounds, db.base, db.stats, db.history, db.seq = {}, {}, {}, {}, 0
  Rebuild()
end

--- The id a host stamps on the rounds it settles. The counter lives in the
--- saved variables, so ids stay unique for this character for ever.
local function NextRoundID()
  local me, id = MyName()
  -- step over anything already on file: a counter reset must never collide with
  -- a round we still hold, or the new round would be dropped as a conflict
  repeat
    db.seq = (tonumber(db.seq) or 0) + 1
    id = me .. ":" .. db.seq
  until not db.rounds[id]
  return id
end

--- everyone's running record. Reading one creates it, so callers never nil-check.
local function Stat(name)
  local r = db.stats[name]
  if type(r) ~= "table" then
    r = { net = tonumber(r) or 0, wins = 0, losses = 0, games = 0, best = 0, worst = 0 }
    db.stats[name] = r
  else
    -- a half-written record would blow up the arithmetic below
    r.net = r.net or 0; r.wins = r.wins or 0; r.losses = r.losses or 0
    r.games = r.games or 0; r.best = r.best or 0; r.worst = r.worst or 0
  end
  return r
end
G.Stat = Stat

--- everybody who has ever played, best net first
function G.Board()
  local list = {}
  for name, r in pairs(db.stats) do
    if type(r) == "table" and (r.games or 0) > 0 then list[#list + 1] = { name = name, r = r } end
  end
  table.sort(list, function(a, b)
    if a.r.net == b.r.net then return a.name < b.name end
    return a.r.net > b.r.net
  end)
  return list
end

-- A player's current run from the round ledger, the same source and scope the
-- board uses. Only a win (they had the top roll) or a loss (they paid) counts;
-- a round they were neither in - a middle roller - is skipped and never breaks
-- the run. Returns "win"/"lose"/nil and the length (0 when under a real streak).
function G.Streak(name)
  name = Bare(name)
  local guildOnly = G.Scope() == "guild"
  local myGuild = MyGuild()
  local seq = {}
  for _, rd in pairs(db.rounds) do
    local counts = (not guildOnly) or (rd.g ~= nil and rd.g == myGuild)
    if counts and rd.winner and rd.loser then
      local out = (Bare(rd.winner) == name and "win") or (Bare(rd.loser) == name and "lose") or nil
      if out then seq[#seq + 1] = { at = rd.at or 0, out = out } end
    end
  end
  if #seq == 0 then return nil, 0 end
  table.sort(seq, function(a, b) return a.at < b.at end)
  local last = seq[#seq].out
  local run = 0
  for i = #seq, 1, -1 do
    if seq[i].out == last then run = run + 1 else break end
  end
  return last, run
end

local function FindDebt(from, to)
  for i, d in ipairs(db.debts) do
    if d.from == from and d.to == to then return d, i end
  end
end

function Ledger.Add(from, to, amount)
  if not from or not to or from == to or amount <= 0 then return end
  local rev, ri = FindDebt(to, from)
  if rev then
    if rev.amount > amount then rev.amount = rev.amount - amount; rev.at = Now(); return end
    amount = amount - rev.amount
    table.remove(db.debts, ri)
    if amount <= 0 then return end
  end
  local d = FindDebt(from, to)
  if d then d.amount = d.amount + amount; d.at = Now()
  else table.insert(db.debts, { from = from, to = to, amount = amount, at = Now() }) end
end

--- money moved from `from` to `to` outside a round (a trade): settle what it covers
function Ledger.Pay(from, to, amount)
  local d, i = FindDebt(from, to)
  if not d then return 0 end
  local paid = math.min(d.amount, amount)
  d.amount = d.amount - paid
  if d.amount <= 0 then table.remove(db.debts, i) end
  return paid
end

function Ledger.Clear(from, to)
  local d, i = FindDebt(from, to)
  if d then table.remove(db.debts, i) return true end
  return false
end

function Ledger.ClearAll() db.debts = {} end

--- what one person owes and is owed, in total
function Ledger.Net(name)
  local owes, owed = 0, 0
  for _, d in ipairs(db.debts) do
    if d.from == name then owes = owes + d.amount end
    if d.to == name then owed = owed + d.amount end
  end
  return owes, owed
end

--- everything `name` owes, as a list of { to=, amount= }
function Ledger.Owes(name)
  local out = {}
  for _, d in ipairs(db.debts) do if d.from == name then out[#out + 1] = d end end
  table.sort(out, function(a, b) return a.amount > b.amount end)
  return out
end

function Ledger.OwedTo(name)
  local out = {}
  for _, d in ipairs(db.debts) do if d.to == name then out[#out + 1] = d end end
  table.sort(out, function(a, b) return a.amount > b.amount end)
  return out
end

----------------------------------------------------------------------------
-- comm: the host tells everyone with the addon what the table is doing.
-- One line per thing that happened, tab separated, drip-fed under the
-- client's addon-message throttle. Ledger events go both ways.
--
--   OPEN max            host opened a table       JOIN name / LEAVE name
--   GO                  rolling started           ROLL name value [T]   (T = tiebreak roll)
--   TIE kind n,n,n      re-roll among these       DONE winner loser amount high low
--   CLOSE               table closed              HI  -> host replays the table to the asker
--   PAID from to amount somebody settled a debt (trade or the paid button)
----------------------------------------------------------------------------
local Comm = { queue = {}, draining = false }
G.Comm = Comm
local PREFIX = "BiSGamba"
local Game                                  -- defined below

local function drain()
  if #Comm.queue == 0 then Comm.draining = false return end
  Comm.draining = true
  local item = table.remove(Comm.queue, 1)
  local ch, target = Channel(), nil
  if item.to then ch, target = "WHISPER", item.to end
  if ch then
    if C_ChatInfo and C_ChatInfo.SendAddonMessage then C_ChatInfo.SendAddonMessage(PREFIX, item.msg, ch, target)
    elseif SendAddonMessage then SendAddonMessage(PREFIX, item.msg, ch, target) end
  end
  After(0.15, drain)
end

local function pack(...)
  local parts = { ... }
  for i = 1, #parts do parts[i] = tostring(parts[i]) end
  local msg = table.concat(parts, "\t")
  if #msg > 250 then msg = msg:sub(1, 250) end
  return msg
end

function Comm.Send(...)
  Comm.queue[#Comm.queue + 1] = { msg = pack(...) }
  if not Comm.draining then drain() end
end

-- straight to one person (the host answering a HI)
function Comm.SendTo(who, ...)
  Comm.queue[#Comm.queue + 1] = { msg = pack(...), to = who }
  if not Comm.draining then drain() end
end

-- Anyone we have ever heard an addon message from is running it. Remembered
-- across sessions, so a trade knows without having to wait on a ping.
local USER_TTL = 14 * 24 * 60 * 60
function Comm.Seen(name)
  if not name or name == "" or name == MyName() then return end
  db.users = db.users or {}
  db.users[name] = Now()
end

function Comm.HasAddon(name)
  if not name then return false end
  if name == MyName() then return true end
  local at = db.users and db.users[name]
  return at ~= nil and (Now() - at) < USER_TTL
end

--- ask one person whether they are running it; they answer PONG
function Comm.Ping(who)
  if who and who ~= MyName() then Comm.SendTo(who, "PING") end
end

function Comm.Register()
  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
  elseif RegisterAddonMessagePrefix then RegisterAddonMessagePrefix(PREFIX) end
end

----------------------------------------------------------------------------
-- the game. One person hosts; everybody else with the addon mirrors it.
----------------------------------------------------------------------------
Game = { state = "IDLE", players = {}, order = {}, max = 100, host = nil }
G.Game = Game

--- What this table is called, for people reading chat rather than the window.
local function GameName() return "HIGH / LOW" end

--- What it costs to lose, in words. With the difference rule the damage depends
--- on the spread, so give the worst case rather than leaving people guessing.
local function Stakes()
  if db.payDiff then
    return ("low pays high the gap, up to %s"):format(Gold(Game.max - 1))
  end
  return ("low pays high %s flat"):format(Gold(Game.max))
end

local UI, Trade                             -- defined below

function Game.IsHost() return Game.host == MyName() end
function Game.Active() return Game.state == "JOIN" or Game.state == "ROLL" or Game.state == "TIE" end
-- a table somebody else is running right now
function Game.Remote() return Game.host ~= nil and not Game.IsHost() and Game.Active() end

-- states: IDLE, JOIN, ROLL, TIE, DONE
local function Player(name)
  local p = Game.players[name]
  if not p then
    p = { name = name }
    Game.players[name] = p
    Game.order[#Game.order + 1] = name
  end
  if not p.class then
    local u = UnitFor(name)
    if u then
      local _, class = UnitClass(u)
      local _, race = UnitRace(u)
      p.class, p.race, p.sex = class, race, UnitSex(u)
    end
  end
  return p
end

local function Drop(name)
  Game.players[name] = nil
  for i, n in ipairs(Game.order) do if n == name then table.remove(Game.order, i) break end end
end

local function Fresh(max)
  Game.max = max
  Game.players, Game.order = {}, {}
  Game.tied, Game.result, Game.highName, Game.tieKind = nil, nil, nil, nil
  Game.high, Game.low = nil, nil
  Game.countdownEnd = nil
end

-- host side -------------------------------------------------------------------
--- Seat somebody. Only while the table is open: once the rolls are called the
--- door is shut, or you could watch somebody roll a 3 and join knowing the low
--- was already taken.
function Game.Add(name, quiet)
  if not name or name == "" then return end
  if not Game.IsHost() and Game.Remote() then return end
  if Game.state == "IDLE" or Game.state == "DONE" then Game.Open() end
  if Game.state ~= "JOIN" then return end
  if Game.players[name] then return end
  Player(name)
  Comm.Send("JOIN", name)
  if not quiet then Print(T.text("ink2", name) .. " is in") end
  UI:Refresh()
end

--- Take somebody off the table. Also only while it is open: once you have been
--- called to roll you are in the round, win or lose.
function Game.Remove(name)
  if not Game.players[name] then return end
  if not Game.IsHost() then return end
  if Game.state ~= "JOIN" then return end
  Drop(name)
  Comm.Send("LEAVE", name)
  Print(T.text("ink2", name) .. " is out")
  UI:Refresh()
end

function Game.Open(max)
  if Game.Remote() then Warn(Game.host .. " is running the table") return end
  max = tonumber(max) or tonumber(db.wager) or 100
  max = math.max(2, math.min(MAX_ROLL, math.floor(max)))
  db.wager = max
  if Game.IsHost() and Game.Active() then Comm.Send("CLOSE") end   -- clients drop the old table first
  Game.host = MyName()
  Game.state = "JOIN"
  Fresh(max)
  Comm.Send("OPEN", max)
  Sound.Play("open")
  Game.Add(MyName(), true)
  Say(("BiS Gamba · %s · /roll %d · %s · 1 to join, -1 to leave"):format(GameName(), max, Stakes()))
  UI:Refresh()
end

local nudged = {}          -- who has already been told they rolled the wrong range
local latecomers = {}      -- who has already been told they missed this one

--- Seconds left on the last call, or nil when there is no countdown running.
function Game.Countdown()
  if not Game.countdownEnd then return nil end
  local left = Game.countdownEnd - GetTime()
  if left < 0 then left = 0 end
  return left
end

--- Ten seconds' warning in chat, and the host's own portrait counts it down.
function Game.LastCall(secs)
  if Game.state ~= "JOIN" or not Game.IsHost() then return end
  if Game.Countdown() then Warn("the countdown is already running") return end
  secs = tonumber(secs) or tonumber(db.lastCall) or 10
  secs = math.max(3, math.min(60, math.floor(secs)))
  Game.countdownEnd = GetTime() + secs
  Comm.Send("CALL", secs)
  Sound.Play("call")
  Say(("BiS Gamba · last call · %ds · %s /roll %d · 1 to join"):format(secs, GameName(), Game.max))
  UI:Refresh()
  local mine = Game.countdownEnd
  After(secs, function()
    if Game.countdownEnd == mine and Game.state == "JOIN" and Game.IsHost() then Game.StartRolls() end
  end)
end

function Game.StartRolls()
  if Game.state ~= "JOIN" or not Game.IsHost() then return end
  local n = #Game.order
  if n < 2 and not db.autoJoin then Warn("need at least two people at the table") return end
  Game.countdownEnd = nil
  Game.state = "ROLL"
  latecomers = {}
  Comm.Send("GO")
  -- if I'm a roller, the "you" cue fires when my button lights - don't double up
  if not Game.CanRoll() then Sound.Play("go") end
  Say(("BiS Gamba · rolls open · %s /roll %d now · %d in"):format(GameName(), Game.max, n))
  nudged = {}
  Game.Remind()
  UI:Refresh()
end

-- a while into the rolls, name the stragglers in chat (once per phase)
function Game.Remind(now)
  local secs = tonumber(db.remind) or 30
  if secs <= 0 and not now then return end
  local phase = Game.state .. ":" .. tostring(GetTime())
  Game.remindPhase = phase
  local function post()
    if not Game.IsHost() or not (Game.state == "ROLL" or Game.state == "TIE") then return end
    local miss = Game.Missing()
    if #miss == 0 then return end
    local names = {}
    for i = 1, math.min(8, #miss) do names[i] = miss[i] end
    if #miss > 8 then names[#names + 1] = "+" .. (#miss - 8) .. " more" end
    Say(("BiS Gamba · waiting on %s · /roll %d"):format(table.concat(names, ", "), Game.max))
  end
  if now then post() return end
  After(secs, function() if Game.remindPhase == phase then post() end end)
end

-- can I roll right now?
function Game.CanRoll()
  local me = MyName()
  local p = Game.players[me]
  if Game.state == "ROLL" then return p ~= nil and p.roll == nil end
  if Game.state == "TIE" then return Game.tied ~= nil and Game.tied[me] ~= nil and p ~= nil and p.tieRoll == nil end
  return false
end

--- Roll, and only roll. It never opens a table and never calls for rolls.
function Game.RollMe()
  if not Game.CanRoll() then
    local me = MyName()
    if Game.state == "JOIN" then Warn("rolls haven't been called yet")
    elseif Game.state == "TIE" then Warn("you're not in the tiebreak")
    elseif Game.players[me] and (Game.players[me].roll or Game.players[me].tieRoll) then Warn("you already rolled")
    elseif Game.state == "ROLL" then Warn("you're not at the table - join first")
    else Warn("no table open") end
    return
  end
  RandomRoll(1, Game.max)
end

-- client side: join / leave through raid chat, the way people without the addon do
function Game.Seated() return Game.players[MyName()] ~= nil end
--- Join or leave. The host runs the table either way: backing out only takes
--- them off the table, it does not hand the game to anybody else.
function Game.JoinMe()
  if Game.state ~= "JOIN" then
    Warn(Game.Active() and "the rolls are already out - catch the next one" or "no table open")
    return
  end
  local me = MyName()
  if Game.IsHost() then
    if Game.players[me] then Game.Remove(me) else Game.Add(me) end
    return
  end
  local ch = Channel()
  if not ch then Warn("not in a group") return end
  SendChatMessage(Game.Seated() and "-1" or "1", ch)
end

local function Missing()
  local out = {}
  for _, name in ipairs(Game.order) do
    local p = Game.players[name]
    if Game.state == "TIE" then
      if Game.tied[name] and not p.tieRoll then out[#out + 1] = name end
    elseif not p.roll then out[#out + 1] = name end
  end
  return out
end
Game.Missing = Missing

-- a roll line came in (host only reads chat; clients get ROLL from the host)
function Game.OnRoll(name, roll, lo, hi)
  if not Game.IsHost() then return end
  -- rolling while the table is still open is a way of saying "deal me in"
  if Game.state == "JOIN" and db.autoJoin and lo == 1 and hi == Game.max
     and not Game.players[name] and InGroup(name) then
    Game.Add(name)
    return
  end
  if lo ~= 1 or hi ~= Game.max then
    -- somebody at the table rolled the wrong range: tell them once, in chat, so no addon is needed
    if (Game.state == "ROLL" or Game.state == "TIE") and Game.players[name] and not nudged[name] then
      local p = Game.players[name]
      local waiting = (Game.state == "ROLL" and not p.roll) or (Game.state == "TIE" and Game.tied and Game.tied[name] and not p.tieRoll)
      if waiting then nudged[name] = true; Say(("BiS Gamba · %s rolled /roll %d · table is /roll %d"):format(name, hi, Game.max)) end
    end
    return
  end
  if Game.state == "ROLL" then
    -- no seating anybody now: rolling is not a way onto a closed table
    if not Game.players[name] then return end
    local p = Game.players[name]
    if p.roll then                            -- first roll counts; say so once
      if not p.rerolled then p.rerolled = true; Say(("BiS Gamba · %s already rolled %d · first roll counts"):format(name, p.roll)) end
      return
    end
    p.roll = roll
    Comm.Send("ROLL", name, roll)
    UI:OnRoll(name, roll)
    Game.Check()
  elseif Game.state == "TIE" then
    if not (Game.tied and Game.tied[name]) then return end
    local p = Game.players[name]
    if p.tieRoll then
      if not p.rerolledTie then p.rerolledTie = true; Say(("BiS Gamba · %s already rolled %d in the tiebreak · first roll counts"):format(name, p.tieRoll)) end
      return
    end
    p.tieRoll = roll
    Comm.Send("ROLL", name, roll, "T")
    UI:OnRoll(name, roll)
    Game.Check()
  end
end

local function Sorted(field)
  local list = {}
  for _, name in ipairs(Game.order) do
    local p = Game.players[name]
    if p[field] then list[#list + 1] = p end
  end
  table.sort(list, function(a, b)
    if a[field] == b[field] then return a.name < b.name end
    return a[field] > b[field]
  end)
  return list
end
Game.Sorted = Sorted

-- everybody rolled? then find high and low, or a tie to break
local settleAt = nil
function Game.Check(force)
  if not Game.IsHost() then return end
  local missing = Missing()
  if #missing > 0 and not force then UI:Refresh() return end
  if Game.state == "ROLL" then
    local list = Sorted("roll")
    if #list < 2 then
      if not force then UI:Refresh() return end     -- lone roller: wait for company
      Warn("not enough rolls to settle")
      Game.state = "DONE"; Comm.Send("CLOSE"); UI:Refresh(); return
    end
    -- everybody seated has rolled. Hold the door a moment for anyone still typing /roll.
    local grace = tonumber(db.grace) or 3
    if not force and grace > 0 then
      local mine = GetTime()
      settleAt = mine
      UI:Refresh()
      After(grace, function()
        if settleAt ~= mine or Game.state ~= "ROLL" then return end
        if #Missing() == 0 then Game.Check(true) else settleAt = nil; UI:Refresh() end
      end)
      return
    end
    settleAt = nil
    -- Forced settle with stragglers: whoever was called to roll and didn't
    -- forfeits and pays, rather than dropping out clean. (The grace path only
    -- gets here once everyone has rolled, so this is the manual `end` case.)
    local forfeiters = {}
    if #missing > 0 then
      for _, name in ipairs(missing) do
        local p = Game.players[name]
        if p then p.roll = 0; forfeiters[#forfeiters + 1] = name end   -- 0 sorts below any real roll
      end
      list = Sorted("roll")
    end
    if #list < 2 then Warn("not enough rolls to settle"); Game.state = "DONE"; Comm.Send("CLOSE"); UI:Refresh(); return end
    local high, low = list[1].roll, list[#list].roll
    local highs, lows = {}, {}
    for _, p in ipairs(list) do
      if p.roll == high then highs[#highs + 1] = p.name end
      if p.roll == low then lows[#lows + 1] = p.name end
    end
    if high == low then
      return Game.Redo(("everybody rolled %d"):format(high))
    end
    Game.high, Game.low = high, low
    -- a forfeit (roll 0) does not get a tiebreak - you already gave up your roll
    if low == 0 then
      table.sort(forfeiters)
      Game.highName = highs[1]
      if #highs > 1 then return Game.Tie("high", highs) end
      Say(("BiS Gamba · %s never rolled · forfeit"):format(forfeiters[1]))
      return Game.Settle(highs[1], forfeiters[1])
    end
    if #highs > 1 then return Game.Tie("high", highs) end
    Game.highName = highs[1]
    if #lows > 1 then return Game.Tie("low", lows) end
    return Game.Settle(highs[1], lows[1])
  elseif Game.state == "TIE" then
    -- a forced tiebreak: whoever was in it and didn't re-roll forfeits it
    if force then
      for name in pairs(Game.tied) do
        local p = Game.players[name]
        if p and not p.tieRoll then p.tieRoll = 0 end
      end
    end
    local list = {}
    for name in pairs(Game.tied) do
      local p = Game.players[name]
      if p and p.tieRoll then list[#list + 1] = p end
    end
    if #list < 2 then Warn("tiebreak needs two rolls"); Game.state = "DONE"; Comm.Send("CLOSE"); UI:Refresh(); return end
    table.sort(list, function(a, b) if a.tieRoll == b.tieRoll then return a.name < b.name end return a.tieRoll > b.tieRoll end)
    local want = (Game.tieKind == "high") and list[1] or list[#list]
    local same = {}
    for _, p in ipairs(list) do if p.tieRoll == want.tieRoll then same[#same + 1] = p.name end end
    if #same > 1 then return Game.Tie(Game.tieKind, same) end   -- tied again, go round once more
    if #same == #list and #list > 1 then return Game.Redo("the tiebreak tied too") end
    if Game.tieKind == "high" then
      Game.highName = want.name
      local lows = {}
      for _, name in ipairs(Game.order) do
        local p = Game.players[name]
        if p.roll == Game.low and name ~= want.name then lows[#lows + 1] = name end
      end
      if #lows > 1 then return Game.Tie("low", lows) end
      return Game.Settle(want.name, lows[1])
    else
      return Game.Settle(Game.highName or Sorted("roll")[1].name, want.name)
    end
  end
end

--- Wipe the rolls and ask for them again, with the round otherwise untouched.
function Game.Redo(why)
  if not Game.IsHost() then return end
  settleAt = nil
  for _, name in ipairs(Game.order) do
    local p = Game.players[name]
    p.roll, p.tieRoll, p.rerolled, p.rerolledTie = nil, nil, nil, nil
  end
  Game.state = "ROLL"
  Game.tied, Game.tieKind, Game.highName = nil, nil, nil
  Game.high, Game.low = nil, nil
  Comm.Send("REDO")
  Sound.Play("redo")
  Say(("BiS Gamba · %s · everyone reroll /roll %d"):format(why or "tie", Game.max))
  nudged = {}
  Game.Remind()
  UI:Refresh()
end

function Game.Tie(kind, names)
  Game.state = "TIE"
  Game.tieKind = kind
  Game.tied = {}
  for _, n in ipairs(names) do
    Game.tied[n] = true
    Game.players[n].tieRoll = nil
  end
  Comm.Send("TIE", kind)
  for _, n in ipairs(names) do Comm.Send("TIED", n) end
  if Game.tied[MyName()] then Sound.Play("tie") end
  nudged = {}
  Game.Remind()
  Say(("BiS Gamba · %s tie on %d · %s /roll %d to break it"):format(kind, kind == "high" and Game.high or Game.low,
    table.concat(names, ", "), Game.max))
  UI:Refresh()
end

-- book a result: the host does this when it settles, everyone else when DONE arrives
--- The guild a round belongs to: ours, but only when both people who settled it
--- are in it. Anything else is a pug round and stays off the guild board.
local function GuildFor(a, b)
  local g = MyGuild()
  if not g then return nil end
  local function inGuild(name)
    if name == MyName() then return true end
    local unit = UnitFor(name)
    if not unit or not UnitIsInMyGuild then return false end
    return UnitIsInMyGuild(unit) and true or false
  end
  if inGuild(a) and inGuild(b) then return g end
  return nil
end

local function Book(id, winner, loser, amount, guild)
  -- A round already on file under this id, with the same result, is a genuine
  -- duplicate - skip it. One with a DIFFERENT result is a poison entry somebody
  -- filed before the host's word arrived: fall through, overwrite it, and pay.
  if id then
    local have = db.rounds[id]
    if have and have.winner == winner and have.loser == loser and have.amount == amount then
      Game.result = { winner = winner, loser = loser, amount = amount }
      Game.state = "DONE"
      UI:Refresh()
      return
    end
  end
  Game.result = { winner = winner, loser = loser, amount = amount }
  Ledger.Add(loser, winner, amount)
  local rolls = {}
  for _, name in ipairs(Game.order) do rolls[name] = Game.players[name].roll end
  -- the host's word on its own round beats anything already filed under that id
  AddRound(id, { at = Now(), max = Game.max, winner = winner, loser = loser,
                 amount = amount, host = Game.host, g = guild }, true)
  table.insert(db.history, 1, { at = Now(), max = Game.max, high = winner, low = loser,
    amount = amount, rolls = rolls, host = Game.host, id = id })
  while #db.history > 50 do table.remove(db.history) end
  Game.state = "DONE"
  UI:OnResult(winner, loser)
end

function Game.Settle(winner, loser)
  if not winner or not loser then Game.state = "DONE"; Comm.Send("CLOSE"); UI:Refresh(); return end
  local amount = db.payDiff and (Game.high - Game.low) or Game.max
  local id = NextRoundID()
  local guild = GuildFor(winner, loser)
  Comm.Send("DONE", winner, loser, amount, Game.high, Game.low, id, guild or "-")
  Book(id, winner, loser, amount, guild)
  Say(("BiS Gamba · %s %d over %s %d · %s owes %s %s"):format(winner, Game.high, loser, Game.low, loser, winner, Gold(amount)))
  local me = MyName()
  if me == winner then UI:Event("you win " .. Gold(amount), "good")
  elseif me == loser then UI:Event("you pay " .. Gold(amount), "warn")
  else UI:Event(Bare(winner) .. " beat " .. Bare(loser), "ink2") end
  local owes = Ledger.Net(loser)
  if owes > amount then Print(("%s now owes %s total"):format(loser, Gold(owes))) end
end

function Game.End()
  if not Game.IsHost() then
    if Game.Remote() then Warn(Game.host .. " is running the table") end
    return
  end
  if Game.state == "ROLL" or Game.state == "TIE" then Game.Check(true)
  elseif Game.state == "JOIN" then Game.state = "IDLE"; Comm.Send("CLOSE"); Say("BiS Gamba · table closed"); UI:Refresh()
  else Game.state = "IDLE"; Game.players, Game.order = {}, {}; Comm.Send("CLOSE"); UI:Refresh() end
end

function Game.Reset()
  if Game.IsHost() and Game.Active() then Comm.Send("CLOSE") end
  Game.state = "IDLE"
  Game.host = nil
  Fresh(Game.max)
  UI:Refresh()
end

-- chat: 1 joins, -1 leaves (the host reads it; clients hear about it from the host)
function Game.OnChat(text, sender)
  if not Game.IsHost() then return end
  local name = Bare(sender)
  if not name then return end
  text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
  local joining = text == "1" or text == "+1" or text:lower() == "in"
  local leaving = text == "-1" or text:lower() == "out"
  if Game.state == "JOIN" then
    if joining then Game.Add(name) elseif leaving then Game.Remove(name) end
  elseif (Game.state == "ROLL" or Game.state == "TIE") and (joining or leaving) then
    -- too late either way, and worth saying so once so they know why
    if not Game.players[name] and not latecomers[name] then
      latecomers[name] = true
      Say(("BiS Gamba · sorry %s, the rolls are already out · next round"):format(name))
    end
  end
end

--- A wipe has to be agreed to on every machine, so nobody can clear the guild's
--- board by fat-fingering a slash command.
local function AskToWipe(who)
  local mine = who == nil
  if not mine and db.neverOpen then
    Print((who or "somebody") .. " is resetting the leaderboard - " .. T.text("ink", "/gamba wipestats yes") .. " to follow suit")
    return
  end
  local text = mine and "Wipe the BiS Gamba leaderboard for everyone? Debts are kept."
    or ((who or "somebody") .. " is resetting the BiS Gamba leaderboard.\nWipe yours too? Debts are kept.")
  if not StaticPopupDialogs or not StaticPopup_Show then
    -- no popup on this client: say what to type instead
    Warn(text)
    Print("type " .. T.text("ink", "/gamba wipestats yes") .. " to wipe yours")
    return
  end
  StaticPopupDialogs["BISGAMBA_WIPE"] = {
    text = text,
    button1 = mine and "Wipe everyone" or "Wipe mine",
    button2 = CANCEL or "Cancel",
    OnAccept = function()
      G.WipeStats()
      if mine then Comm.Send("WIPE") end
      Print(mine and "leaderboard wiped, and everyone running the addon was asked to do the same"
        or ("leaderboard wiped at " .. tostring(who) .. "'s request"))
      UI:Refresh()
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
  }
  StaticPopup_Show("BISGAMBA_WIPE")
end
G.AskToWipe = AskToWipe

----------------------------------------------------------------------------
-- Reconciling the leaderboard
--
-- Records are derived from rounds, and rounds carry a host-stamped id, so two
-- people only disagree when one of them never saw a round. Fix that by trading
-- id lists and posting the ones the other side is missing.
--
--   SYNC              "what rounds have you got?"
--   IDS  id id id     what I have (newest first, in chunks)
--   NEED id id id     send me these
--   ROUND id|at|max|winner|loser|amount|host
----------------------------------------------------------------------------
local SYNC_KEEP = 60          -- how far back we bother reconciling

--- A round's guild stamp is only believed from a guildmate; anybody else's
--- claim to have played a guild round is quietly dropped to "pug".
local function TrustedGuild(g, sender)
  if not g then return nil end
  if g ~= MyGuild() then return g end            -- some other guild's business, keep as told
  local unit = UnitFor(sender)
  if unit and UnitIsInMyGuild and UnitIsInMyGuild(unit) then return g end
  return nil
end

--- Rounds we have asked somebody for, and are prepared to accept from them.
local wanted = {}
local WANT_TTL = 120


--- our newest round ids, newest first
local function RecentIDs()
  local list = {}
  for id, rd in pairs(db.rounds) do list[#list + 1] = { id = id, at = rd.at or 0 } end
  table.sort(list, function(a, b) return a.at > b.at end)
  local out = {}
  for i = 1, math.min(SYNC_KEEP, #list) do out[i] = list[i].id end
  return out
end

--- send a list of ids as however many messages it takes to stay under the cap
local function SendIDs(op, ids, to)
  local chunk = {}
  local size = #op
  local function flush()
    if #chunk == 0 then return end
    if to then Comm.SendTo(to, op, unpack(chunk)) else Comm.Send(op, unpack(chunk)) end
    chunk, size = {}, #op
  end
  for _, id in ipairs(ids) do
    if size + #id + 1 > 230 or #chunk >= 20 then flush() end
    chunk[#chunk + 1] = id
    size = size + #id + 1
  end
  flush()
end

function Game.Sync()
  Comm.Send("SYNC")
end

--- somebody listed what they have: ask for anything we are missing
local function WantFrom(sender, parts)
  local want = {}
  for i = 2, #parts do
    local id = parts[i]
    if id and id ~= "" and not db.rounds[id] then
      want[#want + 1] = id
      wanted[id] = { from = sender, at = GetTime() }
    end
  end
  if #want > 0 then SendIDs("NEED", want, sender) end
end

local function RoundPayload(id, rd)
  return ("%s|%d|%d|%s|%s|%d|%s|%s"):format(id, rd.at or 0, rd.max or 0,
    rd.winner, rd.loser, rd.amount, rd.host or "?", rd.g or "-")
end

local function ParseRound(payload)
  local f = {}
  for piece in (tostring(payload) .. "|"):gmatch("(.-)|") do f[#f + 1] = piece end
  local id, amount = f[1], tonumber(f[6])
  local guild = f[8]
  if guild == "-" or guild == "" then guild = nil end
  if not id or id == "" or not f[4] or not f[5] or not amount then return nil end
  return id, { at = tonumber(f[2]) or 0, max = tonumber(f[3]) or 0, winner = f[4],
               loser = f[5], amount = amount, host = f[7], g = guild }
end

local function SendRounds(sender, parts)
  for i = 2, #parts do
    local rd = db.rounds[parts[i]]
    if rd then Comm.SendTo(sender, "ROUND", RoundPayload(parts[i], rd)) end
  end
end

--- How many rounds we hold, and who else is holding how many. Sizes are only
--- kept for the session - they are a hint for the adopt button, nothing more.
local function RoundCount()
  local n = 0
  for _ in pairs(db.rounds) do n = n + 1 end
  return n
end
G.RoundCount = RoundCount
Comm.sizes = {}

--- The person with a fuller ledger than ours, if there is one.
function G.BestLedger()
  local mine = RoundCount()
  local who, best = nil, mine
  local now = GetTime()
  for name, e in pairs(Comm.sizes) do
    if now - e.at < 600 and e.n > best then who, best = name, e.n end
  end
  return who, best
end

----------------------------------------------------------------------------
-- Adopting somebody else's ledger whole
--
-- A sync fills gaps both ways. Adopting is the other thing you sometimes want:
-- throw yours away and take theirs entire, the way you would restore a backup.
-- Nothing is thrown away until the whole ledger has arrived.
----------------------------------------------------------------------------
local Adopting = nil

local function SendWholeLedger(to)
  local list = {}
  for id, rd in pairs(db.rounds) do list[#list + 1] = { id = id, rd = rd } end
  table.sort(list, function(a, b) return (a.rd.at or 0) > (b.rd.at or 0) end)
  local chunk, size, count = {}, 4, 0
  local function flush()
    if #chunk == 0 then return end
    Comm.SendTo(to, "ALL", unpack(chunk))
    chunk, size = {}, 4
  end
  for i = 1, math.min(#list, 300) do
    local piece = RoundPayload(list[i].id, list[i].rd)
    if size + #piece + 1 > 225 or #chunk >= 5 then flush() end
    chunk[#chunk + 1] = piece
    size = size + #piece + 1
    count = count + 1
  end
  flush()
  Comm.SendTo(to, "ALLEND", count)
end

--- Ask one person for their whole ledger and take it in place of ours.
function G.Adopt(who)
  if not who or who == MyName() then return end
  local function go()
    Adopting = { who = who, rounds = {}, at = GetTime(), n = 0 }
    Comm.SendTo(who, "GIVEALL")
    Print(("asking %s for their ledger..."):format(who))
    After(45, function()
      if Adopting and Adopting.who == who and Adopting.at then
        Adopting = nil
        Warn(("%s never finished sending - your ledger is untouched"):format(who))
      end
    end)
  end
  local mine = RoundCount()
  local text = ("Replace your BiS Gamba ledger with %s's?\n\nYours (%d rounds) is thrown away and theirs is used instead. Debts are kept."):format(who, mine)
  if not StaticPopupDialogs or not StaticPopup_Show then Warn(text); go(); return end
  StaticPopupDialogs["BISGAMBA_ADOPT"] = {
    text = text, button1 = "Take theirs", button2 = CANCEL or "Cancel",
    OnAccept = go, timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
  }
  StaticPopup_Show("BISGAMBA_ADOPT")
end

local function AdoptChunk(sender, parts)
  if not Adopting or Adopting.who ~= sender then return end
  for i = 2, #parts do
    local id, rd = ParseRound(parts[i])
    if id then rd.g = TrustedGuild(rd.g, sender) end
    if id and not Adopting.rounds[id] and (tonumber(rd.at) or 0) <= Now() + 600 and rd.amount <= MAX_ROLL then
      Adopting.rounds[id] = rd
      Adopting.n = Adopting.n + 1
    end
  end
end

local function AdoptFinish(sender, count)
  if not Adopting or Adopting.who ~= sender then return end
  local got, want = Adopting.n, tonumber(count) or 0
  if got < want then
    Warn(("only %d of %s's %d rounds arrived - keeping yours"):format(got, sender, want))
    Adopting = nil
    return
  end
  db.rounds = Adopting.rounds
  db.base, db.stats, db.history, db.seq = {}, {}, {}, 0
  Adopting = nil
  Rebuild()
  Print(("adopted %s's ledger - %d rounds"):format(sender, got))
  UI:Refresh()
end

local function TakeRound(payload, sender)
  local id, rd = ParseRound(payload)
  if not id then return false end
  -- unsolicited rounds are not taken: we only file what we asked this person for
  local w = wanted[id]
  if not w or w.from ~= sender or GetTime() - w.at > WANT_TTL then return false end
  wanted[id] = nil
  rd.g = TrustedGuild(rd.g, sender)
  local added, why = AddRound(id, rd)
  if why == "conflict" then
    local mine = db.rounds[id]
    Warn(("%s has a different record for round %s (theirs: %s beat %s for %s; ours: %s beat %s for %s) - keeping ours"):format(
      tostring(sender), id, rd.winner, rd.loser, Gold(rd.amount), mine.winner, mine.loser, Gold(mine.amount)))
  end
  return added
end

-- the host replays the whole table to somebody who just asked
function Game.Replay(who)
  if not Game.IsHost() or not Game.Active() then return end
  local function send(...) Comm.SendTo(who, ...) end
  send("OPEN", Game.max)
  for _, name in ipairs(Game.order) do send("JOIN", name) end
  if Game.state == "ROLL" or Game.state == "TIE" then
    send("GO")
    for _, name in ipairs(Game.order) do
      local p = Game.players[name]
      if p.roll then send("ROLL", name, p.roll) end
    end
  end
  if Game.state == "TIE" then
    send("TIE", Game.tieKind)
    for n in pairs(Game.tied) do send("TIED", n) end
    for _, name in ipairs(Game.order) do
      local p = Game.players[name]
      if p.tieRoll then send("ROLL", name, p.tieRoll, "T") end
    end
  end
end

-- client side: something the host said
function Game.OnComm(msg, sender)
  sender = Bare(sender)
  if not sender or sender == MyName() then return end
  -- Whispers can come from anybody on the realm. Nothing in this protocol has
  -- any business arriving from outside the group, so nothing outside is heard.
  if not InGroup(sender) then return end
  local parts = {}
  for s in (msg .. "\t"):gmatch("(.-)\t") do parts[#parts + 1] = s end
  local op = parts[1]
  Comm.Seen(sender)
  if op == "PING" then
    Comm.SendTo(sender, "PONG")
    Trade.RethinkWhisper(sender)
    return
  elseif op == "PONG" then
    Trade.RethinkWhisper(sender)
    return
  end
  if op == "PAID" then
    local from, to, amount, how = parts[2], parts[3], tonumber(parts[4]), parts[5]
    -- only the person who is owed can say they have been paid; a debtor's word
    -- for it is not worth anything
    if not (from and to and amount) or sender ~= to then return end
    -- a payment we were a party to was booked on our own client when the trade
    -- completed, so the creditor's announcement of it is not applied twice here
    if how == "T" and (from == MyName() or to == MyName()) then return end
    local paid = Ledger.Pay(from, to, amount)
    if paid > 0 then
      Print(("%s paid %s %s"):format(from == MyName() and "you" or from, to == MyName() and "you" or to, Gold(paid)))
      UI:Refresh()
    end
    return
  end
  if op == "HI" then
    if Game.IsHost() then Game.Replay(sender) end
    return
  end
  if op == "WIPE" then
    AskToWipe(sender)
    return
  end
  if op == "SYNC" then
    SendIDs("IDS", RecentIDs(), sender)
    Comm.SendTo(sender, "SIZE", RoundCount())
    return
  elseif op == "SIZE" then
    Comm.sizes[sender] = { n = tonumber(parts[2]) or 0, at = GetTime() }
    UI:Refresh()
    return
  elseif op == "GIVEALL" then
    SendWholeLedger(sender)
    return
  elseif op == "ALL" then
    AdoptChunk(sender, parts)
    return
  elseif op == "ALLEND" then
    AdoptFinish(sender, parts[2])
    return
  elseif op == "IDS" then
    WantFrom(sender, parts)
    return
  elseif op == "NEED" then
    SendRounds(sender, parts)
    return
  elseif op == "ROUND" then
    local gained = 0
    for i = 2, #parts do if TakeRound(parts[i], sender) then gained = gained + 1 end end
    if gained > 0 then
      Print(("picked up %d round%s from %s - leaderboard updated"):format(gained, gained == 1 and "" or "s", sender))
      UI:Refresh()
    end
    return
  end
  if op == "OPEN" then
    if Game.IsHost() and Game.Active() then
      Warn(sender .. " also opened a table - ignoring theirs")
      return
    end
    local max = tonumber(parts[2]) or 100
    if Game.host == sender and Game.Active() and Game.max == max then return end   -- a replay, we're already synced
    if Game.Remote() and Game.host ~= sender then Warn(sender .. " opened a table too - staying with " .. Game.host) return end
    Game.host = sender
    Game.state = "JOIN"
    Fresh(max)
    local hint = (db.neverOpen or db.autoOpen == false) and "  (/gamba to open the table)" or ""
    Print(sender .. " opened a table: /roll " .. max .. hint)
    UI:Event(Bare(sender) .. " deals - /roll " .. max, "gold")
    Sound.Play("open")
    UI:AutoShow()
    UI:Refresh()
    return
  end
  if sender ~= Game.host then return end
  local name = parts[2]
  if op == "JOIN" then
    if name and name ~= "" and (Game.state == "JOIN" or Game.state == "ROLL") then Player(name); UI:Refresh() end
  elseif op == "LEAVE" then
    if name and name ~= "" then Drop(name); UI:Refresh() end
  elseif op == "CALL" then
    local secs = tonumber(parts[2])
    if secs and Game.state == "JOIN" then
      Game.countdownEnd = GetTime() + secs
      Sound.Play("call")
      UI:Refresh()
    end
  elseif op == "GO" then
    if Game.state == "JOIN" then Game.state = "ROLL"; Game.countdownEnd = nil; if not Game.CanRoll() then Sound.Play("go") end; UI:Refresh() end
  elseif op == "REDO" then
    for _, n in ipairs(Game.order) do
      local pl = Game.players[n]
      pl.roll, pl.tieRoll = nil, nil
    end
    Game.state = "ROLL"
    Game.tied, Game.tieKind, Game.result = nil, nil, nil
    Sound.Play("redo")
    UI:Refresh()
  elseif op == "ROLL" then
    local roll = tonumber(parts[3])
    if not name or name == "" or not roll then return end
    local p = Player(name)
    local field = (parts[4] == "T") and "tieRoll" or "roll"
    if p[field] == roll then return end            -- a replay of something we already have
    p[field] = roll
    UI:OnRoll(name, roll)
  elseif op == "TIE" then
    Game.state = "TIE"
    Game.tieKind = (name == "low") and "low" or "high"
    Game.tied = {}
    UI:Refresh()
  elseif op == "TIED" then
    if name and name ~= "" and Game.state == "TIE" and Game.tied then
      Game.tied[name] = true
      Player(name).tieRoll = nil
      UI:Refresh()
    end
  elseif op == "DONE" then
    local winner, loser, amount = parts[2], parts[3], tonumber(parts[4])
    local high, low = tonumber(parts[5]), tonumber(parts[6])
    -- A result is only believed for a round we were actually watching: the
    -- table has to be mid-roll, both names seated with the rolls the host
    -- claims, and the sum has to follow from those rolls. Anything else is
    -- somebody trying to write a debt onto the ledger by hand.
    local pw, pl = Game.players[winner or ""], Game.players[loser or ""]
    local expected = (high and low) and (db.payDiff and (high - low) or Game.max) or nil
    local ok = (Game.state == "ROLL" or Game.state == "TIE")
      and winner and loser and winner ~= loser and amount and high and low
      and pw and pl and pw.roll == high and pl.roll == low and high > low
      and amount == expected and amount <= MAX_ROLL
    if not ok then
      Warn(("ignored a result from %s that does not match the rolls we saw"):format(sender))
      return
    end
    Game.high, Game.low = high, low
    local guild = parts[8]
    if guild == "-" or guild == "" then guild = nil end
    Book(parts[7], winner, loser, amount, TrustedGuild(guild, sender))
  elseif op == "CLOSE" then
    if Game.Active() then Game.state = "IDLE"; Game.countdownEnd = nil; UI:Refresh() end
  end
end

-- everyone with the addon hears about a settled debt
--- Only the creditor's announcement is honoured by anybody else, so only the
--- creditor sends one. `how` = "T" marks a payment that came through a trade,
--- which both parties already booked for themselves.
function Ledger.Announce(from, to, amount, how)
  if not amount or amount <= 0 or to ~= MyName() then return end
  if how then Comm.Send("PAID", from, to, amount, how) else Comm.Send("PAID", from, to, amount) end
end

----------------------------------------------------------------------------
-- paying: open the trade, fill in the gold, settle when the trade completes
----------------------------------------------------------------------------
Trade = { pending = nil, live = false }
G.Trade = Trade

local function TradePartner()
  local name = UnitName("NPC")
  if (not name or name == "") and TradeFrameRecipientNameText then name = TradeFrameRecipientNameText:GetText() end
  if (not name or name == "") and UnitExists("target") and UnitIsPlayer("target") then name = UnitName("target") end
  if not name or name == "" then return nil end
  return Bare(name)
end

function Trade.Pay(to)
  local me = MyName()
  -- a trade is already open: this button means "put the gold in", nothing else
  if Trade.live then
    local who = TradePartner()
    if not who then Warn("can't tell who you're trading with - use the button on the trade window") return end
    if to and to ~= who then Warn("you're trading with " .. who .. ", not " .. to) return end
    local d = FindDebt(me, who)
    if not d then Print("you don't owe " .. who) return end
    Trade.pending = { to = who, amount = d.amount, at = GetTime() }
    Trade.Fill(true)
    return
  end
  if not to then
    local list = Ledger.Owes(me)
    for _, d in ipairs(list) do
      if UnitFor(d.to) then to = d.to break end
    end
    if not to and list[1] then Warn(list[1].to .. " isn't in your group; find them first") return end
    if not to then Print("you don't owe anybody") return end
  end
  local d = FindDebt(me, to)
  if not d then Print("you don't owe " .. to) return end
  local unit = UnitFor(to)
  if not unit then Warn(to .. " isn't in your group") return end
  Trade.pending = { to = to, amount = d.amount, at = GetTime() }
  -- give them a beat to open it first: both sides calling InitiateTrade wedges the client
  local delay = tonumber(db.tradeDelay) or 1.2
  local mine = Trade.pending
  Print(("asking %s to trade - %s goes in as soon as they accept"):format(to, Gold(d.amount)))
  After(delay, function()
    if Trade.pending ~= mine then return end
    if TradeFrame and TradeFrame:IsShown() then return end
    -- the raidN token may point at somebody else after a roster shuffle: re-find them
    local u = UnitFor(to)
    if not u then Warn(to .. " is gone") Trade.pending = nil return end
    if type(GetCursorInfo) == "function" and GetCursorInfo() and ClearCursor then ClearCursor() end
    InitiateTrade(u)
  end)
end

-- what I owe whoever is on the other side of the open trade window
local function OwedToPartner()
  local who = TradePartner()
  if not who then return nil end
  local d = FindDebt(MyName(), who)
  return who, d and d.amount or 0
end

-- What is actually in our side of the trade right now, or nil if this client
-- won't tell us.
local function TradeMoneyNow()
  local best = nil
  if MoneyInputFrame_GetCopper and TradePlayerInputMoneyFrame then
    local ok, v = pcall(MoneyInputFrame_GetCopper, TradePlayerInputMoneyFrame)
    if ok and type(v) == "number" then best = v end
  end
  if GetPlayerTradeMoney then
    local ok, v = pcall(GetPlayerTradeMoney)
    if ok and type(v) == "number" and (not best or v > best) then best = v end
  end
  return best
end

-- Every way of putting gold in a trade is shut on this client, which is why
-- Gargul's own setCopper is a stub that always reports failure:
--   MoneyInputFrame_SetCopper  - blocked by Blizzard ("security")
--   the frame's own edit boxes - forbidden, tainting them throws
--   PickupPlayerMoney          - protected, ADDON_ACTION_FORBIDDEN
-- SetTradeMoney is the one call that is not refused outright, so we try it and
-- then check; if it did nothing, the panel tells them the number to type.
local function PutMoney(copper)
  if SetTradeMoney then pcall(SetTradeMoney, copper) end
end

--- put the gold in. Works from the pay button (pending) or straight from the trade window.
function Trade.Fill(force)
  -- nothing goes in until they have actually accepted and the trade is live
  if not Trade.live then
    if force then
      local p = Trade.pending
      Print(("waiting for %s to accept - the gold goes in the moment the trade opens"):format(
        tostring((p and p.to) or TradePartner() or "them")))
    end
    return
  end
  local who, amount = OwedToPartner()
  local p = Trade.pending
  if p then
    -- the window we asked for; if the partner name isn't readable yet, trust the ask
    if who and who ~= p.to then Warn("trading with " .. who .. ", not " .. p.to) return end
    who, amount = p.to, p.amount
  end
  if not who or not amount or amount <= 0 then
    if force then Print("you don't owe " .. tostring(who or "them")) end
    return
  end
  local copper = math.floor(amount * 10000)
  local have = GetMoney and GetMoney() or copper
  if have < copper then
    Warn(("you have %s, owe %s: paying what you have"):format(Gold(math.floor(have / 10000)), Gold(amount)))
    copper = math.floor(have / 10000) * 10000
  end
  if copper <= 0 then return end
  local g = math.floor(copper / 10000)
  PutMoney(copper)
  -- Never claim it worked without looking. On this client it almost certainly
  -- did not: every way in is shut (see PutMoney), so the panel takes over.
  After(0.4, function()
    if TradeMoneyNow() == copper then
      Print(("put %s in the trade for %s - accept when they do"):format(Gold(g), who))
      if Trade.panel then Trade.panel:Hide() end
    else
      Print(("%s to pay %s - Ctrl+C the box beside the trade, Ctrl+V in the gold field"):format(T.text("gold", Commas(g)), who))
      Trade.ShowButton()
    end
  end)
end

-- A panel beside the trade window, the way Gargul does it: to the right of the
-- frame so nothing can clip it. It says what is owed either way, and carries the
-- fallback button for when the client refuses to fill the box for us.
function Trade.ShowButton()
  if not TradeFrame or not Trade.live then if Trade.panel then Trade.panel:Hide() end return end
  local f = Trade.panel
  if not f then
    f = CreateFrame("Frame", "BiSGambaTradePanel", TradeFrame, "BackdropTemplate")
    f:SetSize(214, 118)
    f:SetPoint("TOPLEFT", TradeFrame, "TOPRIGHT", 2, -8)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    T.skin(f, "accent")
    f:SetBackdropColor(T.rgba("bg", 1))

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.title:SetPoint("TOP", 0, -9)
    f.title:SetText(T.text("accent", "BiS Gamba"))

    local rule = f:CreateTexture(nil, "ARTWORK")
    rule:SetTexture("Interface\\Buttons\\WHITE8x8")
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", 10, -25)
    rule:SetPoint("TOPRIGHT", -10, -25)
    rule:SetVertexColor(T.rgba("line", 1))

    f.line = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.line:SetPoint("TOP", 0, -33)
    f.line:SetWidth(196)
    f.line:SetJustifyH("CENTER")

    -- The number, in a box you can copy out of. No addon may put gold in a trade,
    -- but the client will happily let you Ctrl+C out of an edit box and Ctrl+V
    -- into the gold field - which is the whole trick.
    local amount = CreateFrame("EditBox", "BiSGambaTradeAmount", f, "BackdropTemplate")
    amount:SetSize(122, 34)
    amount:SetPoint("TOP", 0, -52)
    amount:SetAutoFocus(false)
    amount:SetFontObject(GameFontNormalHuge)
    amount:SetJustifyH("CENTER")
    amount:SetTextInsets(4, 4, 0, 0)
    T.skin(amount, "line2")
    amount:SetBackdropColor(T.rgba("sunken", 1))
    amount:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    amount:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    -- it is a display, not an input: any edit snaps back
    amount:SetScript("OnEditFocusLost", function(self) self:SetText(self.value or "") end)
    amount:SetScript("OnMouseUp", function(self) self:SetFocus(); self:HighlightText() end)
    amount:SetScript("OnEnter", function(self)
      self:SetBackdropBorderColor(T.rgb("gold"))
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText("Ctrl+C to copy")
      GameTooltip:AddLine("then click the trade's gold box and Ctrl+V", T.rgb("muted"))
      GameTooltip:Show()
    end)
    amount:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(T.rgb("line2")); GameTooltip:Hide() end)
    f.amount = amount

    -- a coin, so the number reads as gold at a glance
    local coin = f:CreateTexture(nil, "OVERLAY")
    coin:SetTexture("Interface\\MoneyFrame\\UI-GoldIcon")
    coin:SetSize(16, 16)
    coin:SetPoint("LEFT", amount, "RIGHT", 5, 0)
    f.coin = coin

    f.hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.hint:SetPoint("BOTTOM", 0, 9)
    f.hint:SetWidth(198)
    f.hint:SetJustifyH("CENTER")
    Trade.panel = f
  end

  local who, amount = OwedToPartner()
  if who and who ~= Trade.told then Trade.told = who; Trade.MaybeWhisper(who) end
  -- the box holds the bare number: it has to paste cleanly into the gold field
  local function setAmount(v, hint)
    f.amount.value = tostring(math.floor(v))
    f.amount:SetText(f.amount.value)
    f.amount:SetTextColor(T.rgb("gold"))
    f.hint:SetText(T.text("muted", hint))
  end

  if who and amount > 0 then
    f.line:SetText(T.text("warn", "you owe " .. who))
    setAmount(amount, "click, Ctrl+C, paste in the gold box")
    f.amount:Show()
    f:Show()
    if db.autoCopy ~= false then f.amount:SetFocus(); f.amount:HighlightText() end
  else
    local d = who and FindDebt(who, MyName())
    if d then
      f.line:SetText(T.text("good", who .. " owes you"))
      setAmount(d.amount, "waiting on them")
      f.amount:Show()
      f:Show()
    else
      f:Hide()
    end
  end
end

--- Tell them the balance in a whisper - but only if they have no addon to show
--- them. Two BiS Gamba users already see the same numbers on both sides.
function Trade.MaybeWhisper(who)
  if db.whisper == false or not who or who == MyName() then return end
  if Comm.HasAddon(who) then return end
  Comm.Ping(who)                     -- they may have installed it since we last heard
  local mine = who
  After(1.5, function()
    if Trade.told ~= mine or not Trade.live then return end
    if Comm.HasAddon(mine) then return end          -- they answered: they can see it themselves
    if Trade.whispered == mine then return end
    local owe = FindDebt(MyName(), mine)
    local theirs = FindDebt(mine, MyName())
    local msg
    if owe then msg = "BiS Gamba: I owe you " .. Gold(owe.amount) .. ". Here you go."
    elseif theirs then msg = "BiS Gamba: you owe me " .. Gold(theirs.amount) .. ". Thanks!" end
    if msg then Trade.whispered = mine; SendChatMessage(msg, "WHISPER", nil, mine) end
  end)
end

--- a PONG landed while we were about to whisper them: don't
function Trade.RethinkWhisper(who)
  if Trade.told == who then Trade.whispered = who end
end

-- What was on the table when it closed. TRADE_MONEY_CHANGED cannot be trusted
-- here - Gargul polls for the same reason - so a ticker watches it while the
-- trade is live and keeps the highest figure either side put up.
local lastMine, lastTheirs, lastPartner = 0, 0, nil
local acceptedMine, acceptedTheirs = nil, nil   -- frozen when both went green
-- lastMine/lastTheirs hold the most gold each side had on the table at any point
-- during the trade (the peak). The money frames read 0 the instant the trade
-- closes, so a peak is what survives to settlement; the accepted amounts above
-- override it when we actually saw both sides accept.
local function Snapshot()
  lastPartner = TradePartner() or lastPartner
  if GetPlayerTradeMoney then
    local v = GetPlayerTradeMoney()
    if type(v) == "number" and v > lastMine then lastMine = v end
  end
  if GetTargetTradeMoney then
    local v = GetTargetTradeMoney()
    if type(v) == "number" and v > lastTheirs then lastTheirs = v end
  end
end
Trade.Snapshot = Snapshot

local ticker = CreateFrame("Frame")
ticker:Hide()
ticker:SetScript("OnUpdate", function(self, elapsed)
  self.t = (self.t or 0) + elapsed
  if self.t < 0.2 then return end
  self.t = 0
  Snapshot()
end)
Trade.ticker = ticker

function Trade.OnComplete()
  local me, who = MyName(), lastPartner
  if not who then return end
  -- Settle on what was on the table when both accepted; but a captured value of
  -- zero means we never got a clean read at the accept, so fall back to the most
  -- that was ever on the table (the ticker's peak), which survives the frames
  -- being zeroed at close. This is what makes the PAYER's own debt clear.
  local mine = (acceptedMine and acceptedMine > 0) and acceptedMine or (lastMine or 0)
  local theirs = (acceptedTheirs and acceptedTheirs > 0) and acceptedTheirs or (lastTheirs or 0)
  local gaveG, gotG = math.floor(mine / 10000), math.floor(theirs / 10000)
  if gaveG > 0 then
    local paid = Ledger.Pay(me, who, gaveG)
    if paid > 0 then
      local left = FindDebt(me, who)
      Print(("paid %s %s%s"):format(who, Gold(paid), left and (", " .. Gold(left.amount) .. " to go") or " - square"))
    end
  end
  if gotG > 0 then
    local paid = Ledger.Pay(who, me, gotG)
    if paid > 0 then
      Ledger.Announce(who, me, paid, "T")
      local left = FindDebt(who, me)
      Print(("%s paid you %s%s"):format(who, Gold(paid), left and (", they still owe " .. Gold(left.amount)) or " - square"))
      UI:Event(Bare(who) .. " paid " .. Gold(paid), "good")
    end
  end
  Trade.pending = nil
  if gaveG > 0 or gotG > 0 then Sound.Play("paid") end
  lastMine, lastTheirs, lastPartner = 0, 0, nil
  acceptedMine, acceptedTheirs = nil, nil
  UI:Refresh()
end

function Trade.OnEvent(event, a1, a2)
  if event == "TRADE_SHOW" then
    Trade.live = true
    Trade.bothAccepted = false
    lastMine, lastTheirs, lastPartner = 0, 0, TradePartner()
    acceptedMine, acceptedTheirs = nil, nil
    ticker.t = 0
    ticker:Show()
    After(0.3, function()
      lastPartner = TradePartner() or lastPartner
      Trade.ShowButton()
      if Trade.pending then Trade.Fill() end
      UI:Refresh()
    end)
  elseif event == "TRADE_MONEY_CHANGED" or event == "PLAYER_TRADE_MONEY" then
    Snapshot()
  elseif event == "TRADE_ACCEPT_UPDATE" then
    Snapshot()
    -- both sides green: freeze what is on the table right now. Un-accepting (an
    -- item dragged in, gold changed) drops the flag and the frozen amounts.
    if tonumber(a1) == 1 and tonumber(a2) == 1 then
      Trade.bothAccepted = true
      acceptedMine = (GetPlayerTradeMoney and GetPlayerTradeMoney()) or lastMine
      acceptedTheirs = (GetTargetTradeMoney and GetTargetTradeMoney()) or lastTheirs
    else
      Trade.bothAccepted = false
      acceptedMine, acceptedTheirs = nil, nil
    end
  elseif event == "TRADE_CLOSED" or event == "TRADE_REQUEST_CANCEL" then
    ticker:Hide()
    Trade.live, Trade.told, Trade.whispered = false, nil, nil
    if Trade.panel then Trade.panel:Hide() end
    -- TRADE_CLOSED comes before the "trade complete" message, and on this client
    -- that message may never come at all. Both sides accepted is enough.
    local accepted = Trade.bothAccepted
    Trade.bothAccepted = false
    After(0.3, function()
      if accepted then Trade.OnComplete() end
      UI:Refresh()
    end)
    -- TRADE_CLOSED can fire twice; the both-accepted settle above is idempotent
    if Trade.pending and (GetTime() - Trade.pending.at) > 30 then Trade.pending = nil end
  elseif event == "UI_INFO_MESSAGE" then
    local msg = type(a2) == "string" and a2 or a1
    if msg == (ERR_TRADE_COMPLETE or "Trade complete.") then Trade.OnComplete() end
  elseif event == "UI_ERROR_MESSAGE" then
    local msg = type(a2) == "string" and a2 or a1
    if type(msg) == "string" and msg:lower():find("already trading") then
      Trade.pending = nil
      Warn("the client thinks a trade is still open - /gamba fixtrade")
    end
  end
end

function Trade.FixStuck()
  Trade.pending, Trade.live = nil, false
  if CancelTrade then pcall(CancelTrade) end
  if CloseTrade then pcall(CloseTrade) end
  if TradeFrame and TradeFrame:IsShown() then pcall(HideUIPanel, TradeFrame) end
  Print("cleared the trade state - try again")
end

----------------------------------------------------------------------------
-- the window
--
-- One control row for everyone, in fixed places; what you may not do is greyed.
-- Under it, the people at the table in one of two views:
--   2d     class-coloured 2D portraits in a grid (cheap, 40 people fit)
--   3d     head-and-shoulders 3D portrait models in the same grid
----------------------------------------------------------------------------
UI = { seats = {}, rows = {} }
G.UI = UI

local VIEWS = { "2d", "3d" }

-- One grid, one cell size, for every view. Switching views only changes what is
-- drawn in the art box - never the size of anything - so nothing moves under the
-- mouse when you flip between them.
local ROLL_H = 16        -- the roll number's own strip above the art
local TEXT_H = 48        -- name + two owe lines: "owes 1g" / "to Kumlust" wraps
                         -- to four lines at this cell width, so reserve for four -
                         -- too little and the debt text spills onto the footer row
local CELL_W = 48
local ART_W, ART_H = 30, 38   -- compact portraits: the 3D models shrink with the cell
local CELL_H = ROLL_H + ART_H + 6 + TEXT_H
local COLS = 13          -- up to 13 to a row now the cells are smaller
local MIN_W = math.max(5 * CELL_W + 2 * PAD, 486)   -- the control row's floor, not the grid's
local MAX_ROWS = 3       -- 39 seats, thirteen to a row - a full 25-man is two rows

-- Header prompt budget (bis-theme header law, landmine #9). The prompt+words sit
-- at x=12; the header button strip is x(22) options(50) board(74) sync(38)
-- debts(44) 3d(26) 2d(26) with a -4 gap each and -10 before the view pair and -8
-- at the close, so the leftmost button's left edge is 486 - (8+22+4+50+4+74+4+38+4
-- +44+10+26+2+26) = 486 - 316 = 170 from the left. 170 - 12 = 158 clear; held at
-- 148 so a long line keeps air instead of touching the 2d button.
local CONSOLE_W = 148

-- what a 2D portrait does instead of an animation
local MOOD_WORD = {
  [ANIM.cheer] = "cheers!", [ANIM.cry] = "cries", [ANIM.laugh] = "laughs", [ANIM.applaud] = "claps",
  [ANIM.flex] = "flexes", [ANIM.dance] = "dances", [ANIM.kneel] = "kneels", [ANIM.beg] = "begs",
  [ANIM.shy] = "sweats", [ANIM.talk] = "shrugs", [ANIM.wave] = "waves", [ANIM.question] = "hm?",
  [ANIM.exclaim] = "!", [ANIM.point] = "points",
}

local function SmallButton(parent, text, w)
  local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
  b:SetSize(w or 22, 20)
  T.skin(b, "line2")
  b:SetBackdropColor(T.rgba("sunken", 1))
  local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  fs:SetPoint("CENTER", 0, 0)
  fs:SetText(text)
  fs:SetTextColor(T.rgb("ink2"))
  b.text = fs
  b:SetScript("OnEnter", function(self) if not self.off then self:SetBackdropBorderColor(T.rgb("accent")) end; if self.tip then GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText(self.tip); GameTooltip:Show() end end)
  b:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(T.rgb(self.off and "line" or self.hot and "accent" or "line2")); GameTooltip:Hide() end)
  return b
end

local function SetHot(b, hot)
  b.hot = hot
  b:SetBackdropBorderColor(T.rgb(hot and "accent" or "line2"))
  b.text:SetTextColor(T.rgb(hot and "accent" or "ink2"))
end

-- greyed out: still hoverable for the tooltip, but does nothing
local function SetOff(b, off)
  b.off = off
  if off then
    b.text:SetTextColor(T.rgb("dim"))
    b:SetBackdropColor(T.rgba("surface", 1))
    b:SetBackdropBorderColor(T.rgb("line"))
  else
    b:SetBackdropColor(T.rgba("sunken", 1))
    b:SetBackdropBorderColor(T.rgb(b.hot and "accent" or "line2"))
    b.text:SetTextColor(T.rgb(b.hot and "accent" or "ink2"))
  end
end

local function NpcFor(race, sex)
  sex = (sex == 3) and 3 or 2
  local o = db.npc and db.npc[race] and db.npc[race][sex]
  if o then return o end
  local t = NPC[race]
  return t and (t[sex] or t[2])
end

local function View() return db.view or "2d" end

local function Pose(seat)
  local m = seat.model
  if View() == "3d" then
    if m.SetPortraitZoom then pcall(m.SetPortraitZoom, m, db.portrait or 0.75)
    else pcall(m.SetPosition, m, 1.2, 0, -0.8) end
  else
    if m.SetPortraitZoom then pcall(m.SetPortraitZoom, m, 0) end
    pcall(m.SetPosition, m, db.zoom or 0, 0, db.z or 0)
  end
  pcall(m.SetFacing, m, 0)
  pcall(m.SetAnimation, m, seat.anim or ANIM.stand)
end

-- 2D: the real portrait when they are in range, their class icon otherwise
local function ApplyPortrait(seat)
  local p, tex = seat.person, seat.portrait
  local unit = UnitFor(p.name)
  local ok
  if unit and UnitIsVisible and UnitIsVisible(unit) and SetPortraitTexture then
    ok = pcall(SetPortraitTexture, tex, unit)
    if ok then tex:SetTexCoord(0, 1, 0, 1); seat.how = "live" end
  end
  if not ok then
    local coords = p.class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[p.class]
    if coords then
      tex:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
      tex:SetTexCoord(unpack(coords))
      seat.how = "class icon"
    else
      tex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
      tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
      seat.how = "unknown"
    end
  end
end

local function ApplyModel(seat)
  local m, p = seat.model, seat.person
  pcall(m.ClearModel, m)
  local ok
  local unit = UnitFor(p.name)
  if unit and UnitIsVisible and UnitIsVisible(unit) then
    ok = pcall(m.SetUnit, m, unit)
    if ok then seat.how = "live" end
  end
  if not ok and p.race and NpcFor(p.race, p.sex) then
    ok = pcall(m.SetCreature, m, NpcFor(p.race, p.sex))
    if ok then seat.how = "npc" end
  end
  if not ok then
    pcall(m.SetDisplayInfo, m, db.wisp or WISP)
    seat.how = "wisp"
  end
  Pose(seat)
end

local function ApplyArt(seat)
  if View() == "2d" then
    seat.model:Hide(); seat.portrait:Show(); seat.frame2d:Show()
    ApplyPortrait(seat)
  else
    seat.portrait:Hide(); seat.frame2d:Hide(); seat.model:Show()
    ApplyModel(seat)
  end
end

function UI:Emote(seat, anim, hold)
  seat.anim = anim
  pcall(seat.model.SetAnimation, seat.model, anim)
  seat.restAt = GetTime() + (hold or 4)
  seat.mood:SetText(T.text("muted", MOOD_WORD[anim] or ""))
end

local function ShortName(name, n)
  n = n or 10
  if #name > n + 1 then return name:sub(1, n) .. "." end
  return name
end

local function SeatTooltip(seat)
  local p = seat.person
  if not p then return end
  GameTooltip:SetOwner(seat.hit, "ANCHOR_RIGHT")
  GameTooltip:AddLine(p.name, T.classRGB(p.class or ""))
  if p.roll then GameTooltip:AddLine("rolled " .. p.roll .. (p.tieRoll and (", tiebreak " .. p.tieRoll) or ""), T.rgb("ink2")) end
  local wr, wg, wb = T.rgb("warn")
  local gr, gg, gb = T.rgb("good")
  for _, d in ipairs(Ledger.Owes(p.name)) do GameTooltip:AddDoubleLine("owes " .. d.to, Gold(d.amount), wr, wg, wb, wr, wg, wb) end
  for _, d in ipairs(Ledger.OwedTo(p.name)) do GameTooltip:AddDoubleLine(d.from .. " owes them", Gold(d.amount), gr, gg, gb, gr, gg, gb) end
  local r = db.stats[p.name]
  if type(r) == "table" and (r.games or 0) > 0 then
    GameTooltip:AddLine(("all time %s%s over %d game%s (%d-%d)"):format(r.net >= 0 and "+" or "-",
      Gold(math.abs(r.net)), r.games, r.games == 1 and "" or "s", r.wins, r.losses),
      T.rgb(r.net >= 0 and "good" or "warn"))
    if r.best > 0 then GameTooltip:AddLine("best win " .. Gold(r.best), T.rgb("muted")) end
    if r.worst > 0 then GameTooltip:AddLine("worst loss " .. Gold(r.worst), T.rgb("muted")) end
  end
  if seat.how then GameTooltip:AddLine(seat.how, T.rgb("dim")) end
  GameTooltip:AddLine(" ")
  local me = MyName()
  if p.name ~= me and FindDebt(me, p.name) then GameTooltip:AddLine("Left: pay them", T.rgb("muted")) end
  if Game.IsHost() then GameTooltip:AddLine("Right: remove from table   Shift-right: poke", T.rgb("muted")) end
  GameTooltip:Show()
end

-- A looping bounce on alpha (and optionally scale). The campfire's drawn fire
-- is built the same way; "Interface\\Cooldown\\star4" on ADD is the one soft
-- blob this client definitely has.
local function Flicker(tex, fromA, toA, secs, fromS, toS)
  if not tex.CreateAnimationGroup then return end
  local g = tex:CreateAnimationGroup()
  if not g then return end
  g:SetLooping("BOUNCE")
  local a = g:CreateAnimation("Alpha")
  if a then
    a:SetFromAlpha(fromA); a:SetToAlpha(toA); a:SetDuration(secs); a:SetSmoothing("IN_OUT")
  end
  if fromS then
    local sc = g:CreateAnimation("Scale")
    if sc then
      if sc.SetScaleFrom then sc:SetScaleFrom(fromS, fromS); sc:SetScaleTo(toS, toS)
      else sc:SetScale(toS / fromS, toS / fromS) end
      sc:SetDuration(secs); sc:SetSmoothing("IN_OUT")
      sc:SetOrigin("BOTTOM", 0, 0)
    end
  end
  g:Play()
  return g
end

local function MakeSeat(i, parent)
  local seat = { index = i }
  local cell = CreateFrame("Frame", nil, parent)
  cell:SetSize(CELL_W, CELL_H)
  seat.cell = cell

  -- the art: a model and a portrait share the same box, one is shown at a time
  local m = CreateFrame("DressUpModel", nil, cell)
  m:SetPoint("TOP", 0, -ROLL_H)
  seat.model = m
  m:SetScript("OnModelLoaded", function() Pose(seat) end)

  local f2 = CreateFrame("Frame", nil, cell, "BackdropTemplate")
  f2:SetPoint("BOTTOM", cell, "TOP", 0, -(ROLL_H + ART_H))
  T.skin(f2, "line2")
  f2:SetBackdropColor(T.rgba("sunken", 1))
  seat.frame2d = f2
  local tex = f2:CreateTexture(nil, "ARTWORK")
  tex:SetPoint("TOPLEFT", 2, -2); tex:SetPoint("BOTTOMRIGHT", -2, 2)
  seat.portrait = tex

  -- one invisible button on top takes the mouse for both
  local hit = CreateFrame("Button", nil, cell)
  hit:SetPoint("TOP", 0, -ROLL_H)
  hit:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  seat.hit = hit
  hit:SetScript("OnEnter", function() SeatTooltip(seat) end)
  hit:SetScript("OnLeave", function() GameTooltip:Hide() end)
  hit:SetScript("OnClick", function(_, button)
    local p = seat.person
    if not p then return end
    if button == "RightButton" then
      if IsShiftKeyDown() then UI:Emote(seat, ANIM.point) elseif Game.IsHost() then Game.Remove(p.name) end
    else
      if p.name ~= MyName() and FindDebt(MyName(), p.name) then Trade.Pay(p.name) end
    end
  end)

  -- Biggest winner: a halo behind them. A 3D model has a see-through background
  -- so a glow behind it reads perfectly; the 2D portrait is an opaque tile, so it
  -- gets a second glow in front (low alpha, ADD, which gilds it rather than
  -- washing it out) plus a gold rim.
  local aura = cell:CreateTexture(nil, "BACKGROUND", nil, 2)
  aura:SetTexture("Interface\\Cooldown\\star4")
  aura:SetBlendMode("ADD")
  aura:SetVertexColor(1, 0.82, 0.3)
  aura:SetSize(ART_W + 26, ART_H + 28)
  aura:SetPoint("CENTER", cell, "TOP", 0, -(ROLL_H + ART_H / 2))
  aura:Hide()
  Flicker(aura, 0.4, 0.8, 1.6, 0.94, 1.07)
  seat.aura = aura

  local gild = hit:CreateTexture(nil, "OVERLAY", nil, 1)
  gild:SetTexture("Interface\\Cooldown\\star4")
  gild:SetBlendMode("ADD")
  gild:SetVertexColor(1, 0.8, 0.25)
  gild:SetSize(ART_W + 10, ART_W + 10)
  gild:SetPoint("BOTTOM", hit, "BOTTOM", 0, -4)
  gild:Hide()
  Flicker(gild, 0.16, 0.34, 1.6, 0.96, 1.05)
  seat.gild = gild

  -- Biggest loser: on fire. The flames live on the hit frame, above the art, so
  -- they lick up over the body in both views. They are wider than the portrait
  -- so they break its outline instead of sitting politely inside it.
  local flames = {}
  local function flame(r, g, b, w, h, dy, a1, a2, secs, s1, s2)
    local t = hit:CreateTexture(nil, "ARTWORK", nil, #flames + 1)
    t:SetTexture("Interface\\Cooldown\\star4")
    t:SetBlendMode("ADD")
    t:SetVertexColor(r, g, b)
    t:SetSize(w, h)
    t:SetPoint("BOTTOM", hit, "BOTTOM", 0, dy)
    t:Hide()
    Flicker(t, a1, a2, secs, s1, s2)
    flames[#flames + 1] = t
  end
  flame(1, 0.22, 0.04, ART_W + 22, ART_H * 1.05, -10, 0.55, 0.9, 0.45, 0.95, 1.09)
  flame(1, 0.5, 0.08, ART_W + 6, ART_H * 0.85, -7, 0.6, 1, 0.31, 0.9, 1.13)
  flame(1, 0.85, 0.35, ART_W * 0.7, ART_H * 0.55, -4, 0.5, 1, 0.23, 0.85, 1.16)
  seat.flames = flames

  -- whoever is running the table wears the crown
  local crown = hit:CreateTexture(nil, "OVERLAY")
  crown:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon")
  crown:SetSize(17, 17)
  crown:SetPoint("TOPRIGHT", hit, "TOPRIGHT", 5, 5)
  crown:Hide()
  seat.crown = crown

  -- a win/lose streak badge over the head, top-left (opposite the crown)
  local streak = hit:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  streak:SetPoint("TOPLEFT", hit, "TOPLEFT", -3, 5)
  streak:Hide()
  seat.streak = streak

  -- the roll, in its own strip above the art
  local roll = cell:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  roll:SetPoint("TOP", cell, "TOP", 0, -1)
  seat.roll = roll

  -- a hairline under the art for state
  local ring = cell:CreateTexture(nil, "OVERLAY")
  ring:SetTexture("Interface\\Buttons\\WHITE8x8")
  ring:SetSize(ART_W - 6, 2)
  ring:SetPoint("TOP", cell, "TOP", 0, -(ROLL_H + ART_H + 3))
  ring:SetVertexColor(T.rgba("line2", 1))
  seat.ring = ring

  local name = cell:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  name:SetPoint("TOP", ring, "BOTTOM", 0, -1)
  name:SetWidth(CELL_W - 2)
  seat.name = name

  local owe = cell:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  owe:SetPoint("TOP", name, "BOTTOM", 0, 0)
  owe:SetWidth(CELL_W - 2)
  seat.owe = owe

  local owe2 = cell:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  owe2:SetPoint("TOP", owe, "BOTTOM", 0, 0)
  owe2:SetWidth(CELL_W - 2)
  seat.owe2 = owe2

  -- on the hit frame, which sits above the art: on the cell it would be behind it
  local mood = hit:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  mood:SetPoint("BOTTOM", hit, "BOTTOM", 0, 2)
  seat.mood = mood

  cell:Hide()
  return seat
end

-- The art box is the same rectangle in every view; only what fills it changes.
-- The 2D portrait is square and sits on the same foot line as the models.
local function SizeSeat(seat)
  seat.model:SetSize(ART_W, ART_H)
  seat.frame2d:SetSize(ART_W, ART_W)
  seat.hit:SetSize(ART_W, ART_H)
  seat.hit:SetFrameLevel(seat.cell:GetFrameLevel() + 5)
end

-- the best and worst records among the people currently at the table
local topDog, underDog
local function Extremes()
  topDog, underDog = nil, nil
  local best, worst
  for _, name in ipairs(Game.order) do
    local r = db.stats[name]
    local net = (type(r) == "table" and (r.games or 0) > 0) and r.net or nil
    if net then
      if net > 0 and (not best or net > best) then best, topDog = net, name end
      if net < 0 and (not worst or net < worst) then worst, underDog = net, name end
    end
  end
end

local function FillSeat(seat, p)
  seat.person = p
  if not p then
    seat.cell:Hide(); seat.artKey = nil
    seat.aura:Hide(); seat.gild:Hide(); seat.crown:Hide(); seat.streak:Hide()
    for _, t in ipairs(seat.flames) do t:Hide() end
    return
  end
  seat.cell:Show()
  -- win/lose streak over the head, from the round ledger
  local skKind, skRun = G.Streak(p.name)
  if skRun >= 2 then
    seat.streak:SetText(T.text(skKind == "win" and "gold" or "warn", (skKind == "win" and "W" or "L") .. skRun))
    seat.streak:Show()
  else
    seat.streak:Hide()
  end
  local winning, losing = p.name == topDog, p.name == underDog
  seat.aura:SetShown(winning)
  seat.gild:SetShown(winning and View() == "2d")
  seat.crown:SetShown(p.name == Game.host)
  for _, t in ipairs(seat.flames) do t:SetShown(losing) end
  local r, g, b = T.classRGB(p.class or "")
  seat.name:SetText(ShortName(p.name, 9))
  seat.name:SetTextColor(r, g, b)
  if p.name == MyName() then seat.name:SetTextColor(T.rgb("gold")) end
  -- the 2D tile's rim carries the same news as the aura and the fire
  if winning then seat.frame2d:SetBackdropBorderColor(1, 0.82, 0.3)
  elseif losing then seat.frame2d:SetBackdropBorderColor(1, 0.42, 0.1)
  else seat.frame2d:SetBackdropBorderColor(r, g, b) end

  -- the host's own body carries the last call
  local cd = Game.Countdown()
  if cd and p.name == Game.host then
    local n = math.ceil(cd)
    seat.roll:SetText(tostring(n))
    seat.roll:SetTextColor(T.rgb(n <= 3 and "warn" or "accent"))
    seat.ring:SetVertexColor(T.rgba(n <= 3 and "warn" or "accent", 1))
    seat.owe:SetText(T.text("muted", "last call"))
    seat.owe2:SetText("")
    local key = View() .. ":" .. p.name
    if seat.artKey ~= key then seat.artKey = key; ApplyArt(seat) end
    return
  end

  local inTie = Game.state == "TIE" and Game.tied and Game.tied[p.name]
  local shown
  if inTie then shown = p.tieRoll else shown = p.roll end
  if shown then
    seat.roll:SetText(shown)
    if Game.result then
      if p.name == Game.result.winner then seat.roll:SetTextColor(T.rgb("good"))
      elseif p.name == Game.result.loser then seat.roll:SetTextColor(T.rgb("warn"))
      else seat.roll:SetTextColor(T.rgb("ink2")) end
    else
      seat.roll:SetTextColor(T.rgb("ink"))
    end
  else
    seat.roll:SetText((Game.state == "ROLL" or inTie) and T.text("muted", "?") or "")
  end

  if Game.result and p.name == Game.result.winner then seat.ring:SetVertexColor(T.rgba("good", 1))
  elseif Game.result and p.name == Game.result.loser then seat.ring:SetVertexColor(T.rgba("warn", 1))
  elseif inTie then seat.ring:SetVertexColor(T.rgba("accent", 1))
  else seat.ring:SetVertexColor(T.rgba("line2", 1)) end

  local owes, owed = Ledger.Net(p.name)
  local line1, line2 = "", ""
  if owes > 0 then
    local list = Ledger.Owes(p.name)
    line1 = T.text("warn", "owes " .. Gold(owes))
    if #list == 1 then line2 = T.text("muted", "to " .. ShortName(list[1].to, 8)) elseif #list > 1 then line2 = T.text("muted", #list .. " people") end
  end
  if owed > 0 then
    local txt = T.text("good", "gets " .. Gold(owed))
    if line1 == "" then line1 = txt else line2 = txt end
  end
  seat.owe:SetText(line1)
  seat.owe2:SetText(line2)
  if not seat.restAt then seat.mood:SetText("") end
  -- only reload the art when who / which view / where-from changed
  local key = View() .. ":" .. p.name
  if seat.artKey ~= key then seat.artKey = key; ApplyArt(seat) end
end

function UI:Build()
  if self.frame then return end
  local f = CreateFrame("Frame", "BiSGambaFrame", UIParent, "BackdropTemplate")
  f:SetSize(MIN_W, HEAD_H + 100)
  f:SetFrameStrata("MEDIUM")
  f:SetMovable(true); f:EnableMouse(true); f:SetClampedToScreen(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, rel, x, y = self:GetPoint()
    db.point, db.rel, db.x, db.y = point, rel, x, y
  end)
  f:SetScale(db.scale or 1)
  if db.x then f:SetPoint(db.point or "CENTER", UIParent, db.rel or db.point or "CENTER", db.x, db.y) else f:SetPoint("CENTER") end
  T.skin(f, "line2")
  f:SetBackdropColor(T.rgba("bg", 1))
  tinsert(UISpecialFrames, "BiSGambaFrame")
  f:Hide()
  self.frame = f

  -- header strip: the two control rows sit on their own ground
  local head = f:CreateTexture(nil, "BACKGROUND")
  head:SetTexture("Interface\\Buttons\\WHITE8x8")
  head:SetPoint("TOPLEFT", 1, -1)
  head:SetPoint("TOPRIGHT", -1, -1)
  head:SetHeight(HEAD_H - 22)
  head:SetVertexColor(T.rgba("surface", 1))
  local headLine = f:CreateTexture(nil, "ARTWORK")
  headLine:SetTexture("Interface\\Buttons\\WHITE8x8")
  headLine:SetHeight(1)
  headLine:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 7, 0)
  headLine:SetPoint("TOPRIGHT", head, "BOTTOMRIGHT", -7, 0)
  headLine:SetVertexColor(T.rgba("line2", 1))

  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", 12, -10)
  self.title = title
  -- the title IS the BiS> prompt now; its words rotate the game's standing state
  -- (name, host, seats, whose turn) and events jump in over them. No chat clutter.
  self.con = T.Console(title, { width = CONSOLE_W })
  self.con:Set("name", "Gamba", "accent")

  local close = SmallButton(f, "x")
  close:SetPoint("TOPRIGHT", -8, -8)
  close:SetScript("OnClick", function() f:Hide() end)

  local cfg = SmallButton(f, "options", 50)
  cfg:SetPoint("RIGHT", close, "LEFT", -4, 0)
  cfg.tip = "Settings"
  cfg:SetScript("OnClick", function() self:ToggleConfig() end)
  self.cfgBtn = cfg

  local board = SmallButton(f, "leaderboard", 74)
  board:SetPoint("RIGHT", cfg, "LEFT", -4, 0)
  board.tip = "Biggest winners and losers, all time"
  board:SetScript("OnClick", function() self:ToggleBoard() end)
  self.boardBtn = board

  local sync = SmallButton(f, "sync", 38)
  sync:SetPoint("RIGHT", board, "LEFT", -4, 0)
  sync.tip = "Swap missing rounds with the group so everyone's board agrees"
  sync:SetScript("OnClick", function() Game.Sync(); Print("asking the group for any rounds we missed") end)
  self.syncBtn = sync

  local debts = SmallButton(f, "debts", 44)
  debts:SetPoint("RIGHT", sync, "LEFT", -4, 0)
  debts.tip = "Everything still owed"
  debts:SetScript("OnClick", function() self:ToggleDebts() end)
  self.debtsBtn = debts

  -- view switch
  self.viewBtns = {}
  local prev = debts
  for i = #VIEWS, 1, -1 do
    local v = VIEWS[i]
    local b = SmallButton(f, v, 26)
    b:SetPoint("RIGHT", prev, "LEFT", i == #VIEWS and -10 or -2, 0)
    b.tip = ({ ["2d"] = "2D portraits", ["3d"] = "3D portraits" })[v]
    b:SetScript("OnClick", function() db.view = v; self:Refresh() end)
    self.viewBtns[v] = b
    prev = b
  end

  -- host controls
  local lbl = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  lbl:SetPoint("TOPLEFT", 12, -34)
  lbl:SetText(T.text("muted", "/roll"))
  self.wagerLabel = lbl

  local box = CreateFrame("EditBox", "BiSGambaWager", f, "BackdropTemplate")
  box:SetSize(60, 20)
  box:SetPoint("LEFT", lbl, "RIGHT", 6, 0)
  box:SetAutoFocus(false)
  box:SetNumeric(true)
  box:SetMaxLetters(7)
  box:SetFontObject(GameFontHighlightSmall)
  box:SetTextInsets(6, 6, 0, 0)
  T.skin(box, "line2")
  box:SetBackdropColor(T.rgba("sunken", 1))
  box:SetText(tostring(db.wager or 100))
  box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  box:SetScript("OnEditFocusLost", function(self) local n = tonumber(self:GetText()); if n and n >= 2 then db.wager = n else self:SetText(tostring(db.wager)) end end)
  self.wager = box

  local start = SmallButton(f, "start", 44)
  start:SetPoint("LEFT", box, "RIGHT", 8, 0)
  start.tip = "Open the table (posts in chat)"
  start:SetScript("OnClick", function()
    box:ClearFocus()
    if start.off then return end
    if Game.state == "JOIN" and Game.IsHost() then Game.StartRolls()
    else Game.Open(tonumber(box:GetText())) end
  end)
  self.startBtn = start

  local call = SmallButton(f, "last call", 58)
  call:SetPoint("LEFT", start, "RIGHT", 4, 0)
  call.tip = "Ten seconds' warning in chat, then the rolls start by themselves"
  call:SetScript("OnClick", function() if not call.off then Game.LastCall() end end)
  self.callBtn = call

  local stop = SmallButton(f, "end", 36)
  stop:SetPoint("LEFT", call, "RIGHT", 4, 0)
  stop.tip = "Settle now with the rolls in, or close the table"
  stop:SetScript("OnClick", function() if not stop.off then Game.End() end end)
  self.endBtn = stop

  -- join / leave: everybody has it, in the same place; greyed when not usable
  local join = SmallButton(f, "join", 50)
  join:SetPoint("LEFT", stop, "RIGHT", 12, 0)
  join.tip = "Types 1 in raid chat (or -1 to leave)"
  join:SetScript("OnClick", function() if join.off then return end; Game.JoinMe() end)
  self.joinBtn = join

  -- open this window by itself when a host starts a table?
  local footLine = f:CreateTexture(nil, "ARTWORK")
  footLine:SetTexture("Interface\\Buttons\\WHITE8x8")
  footLine:SetHeight(1)
  footLine:SetPoint("BOTTOMLEFT", 8, 24)
  footLine:SetPoint("BOTTOMRIGHT", -8, 24)
  footLine:SetVertexColor(T.rgba("line", 1))

  -- the footer switches, laid out right to left
  local function FooterCheck(label, tip, onClick)
    local cb = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    cb:SetSize(18, 18)
    cb:SetScript("OnClick", function(self) onClick(self:GetChecked() and true or false) end)
    cb:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:SetText(tip, nil, nil, nil, nil, true)
      GameTooltip:Show()
    end)
    cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    local txt = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    txt:SetPoint("RIGHT", cb, "LEFT", -2, 0)
    txt:SetText(T.text("dim", label))
    cb.label = txt
    return cb
  end

  local auto = FooterCheck("open when a game starts",
    "Open this window by itself when somebody starts a game.",
    function(on)
      db.autoOpen = on
      Print(on and "the table will pop up when a host starts a game" or "the table stays closed until you /gamba")
    end)
  auto:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -7, 4)
  self.autoOpen = auto

  local snd = FooterCheck("sound",
    "Play the sound cues: last call, your turn to roll, winning, losing.",
    function(on)
      db.sound = on
      Sound.quiet = false
      Print(on and "sounds on" or "sounds off")
      if on then Sound.Play("open") end
    end)
  snd:SetPoint("RIGHT", auto.label, "LEFT", -14, 0)
  self.soundCheck = snd

  local never = FooterCheck("never open anything",
    "Nothing appears on its own, ever: no window when a game starts, no window back after combat, and no pop-ups from other people. Everything you click still works.",
    function(on)
      db.neverOpen = on
      Print(on and "nothing will open by itself - the window is yours to open" or "the window may open by itself again")
      UI:Refresh()
    end)
  never:SetPoint("RIGHT", snd.label, "LEFT", -14, 0)
  self.neverOpen = never

  -- shared: roll + pay
  local roll = SmallButton(f, "roll", 44)
  roll:SetPoint("LEFT", join, "RIGHT", 4, 0)
  roll.tip = "Roll the right range"
  roll:SetScript("OnClick", function() box:ClearFocus(); if roll.off then return end; Game.RollMe() end)
  self.rollBtn = roll

  local pay = SmallButton(f, "pay", 40)
  pay:SetPoint("LEFT", roll, "RIGHT", 12, 0)
  pay.tip = "Open a trade with the next person you owe and put the gold in"
  pay:SetScript("OnClick", function() Trade.Pay() end)
  self.payBtn = pay

  local status = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  status:SetPoint("TOPLEFT", 12, -60)
  status:SetPoint("RIGHT", f, "RIGHT", -10, 0)
  status:SetJustifyH("LEFT")
  self.status = status

  -- the seats
  local scene = CreateFrame("Frame", nil, f)
  scene:SetPoint("TOPLEFT", PAD, -HEAD_H)
  scene:SetPoint("RIGHT", -PAD, 0)
  scene:SetHeight(100)
  self.scene = scene
  for i = 1, 40 do self.seats[i] = MakeSeat(i, scene) end

  self.empty = scene:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  self.empty:SetPoint("CENTER", 0, 0)
  self.empty:SetText(T.text("muted", "nobody at the table"))

  -- debts panel, under the seats
  local dp = CreateFrame("Frame", nil, f, "BackdropTemplate")
  dp:SetPoint("TOPLEFT", scene, "BOTTOMLEFT", 0, -4)
  dp:SetPoint("RIGHT", -PAD, 0)
  T.skin(dp, "line")
  dp:SetBackdropColor(T.rgba("surface", 1))
  dp:Hide()
  self.debtPanel = dp
  for i = 1, 12 do
    local row = CreateFrame("Button", nil, dp)
    row:SetHeight(16)
    row:SetPoint("TOPLEFT", 6, -6 - (i - 1) * 16)
    row:SetPoint("RIGHT", -6, 0)
    local t = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    t:SetPoint("LEFT"); t:SetJustifyH("LEFT")
    row.text = t
    local x = SmallButton(row, "paid", 34)
    x:SetSize(34, 14)
    x:SetPoint("RIGHT")
    x.tip = "Mark this one paid (everyone with the addon hears)"
    x:SetScript("OnClick", function()
      local d = row.debt
      if not d then return end
      Ledger.Announce(d.from, d.to, d.amount)
      Ledger.Clear(d.from, d.to)
      Print(d.from .. " -> " .. d.to .. " marked paid")
      UI:Refresh()
    end)
    row.paid = x
    row:Hide()
    self.rows[i] = row
  end

  -- leaderboard, under the debts panel
  local bp = CreateFrame("Frame", nil, f, "BackdropTemplate")
  bp:SetPoint("TOPLEFT", scene, "BOTTOMLEFT", 0, -4)
  bp:SetPoint("RIGHT", -PAD, 0)
  T.skin(bp, "line")
  bp:SetBackdropColor(T.rgba("surface", 1))
  bp:Hide()
  self.boardPanel = bp

  local scope = SmallButton(bp, "guild only", 68)
  scope:SetSize(68, 16)
  scope:SetPoint("TOPRIGHT", -6, -4)
  scope.tip = "Guild only, or every round including pugs"
  scope:SetScript("OnClick", function()
    db.boardScope = (G.Scope() == "guild") and "all" or "guild"
    Rebuild()
    self:Refresh()
  end)
  self.scopeBtn = scope

  local wipe = SmallButton(bp, "reset all", 62)
  wipe:SetSize(62, 16)
  wipe:SetPoint("RIGHT", scope, "LEFT", -4, 0)
  wipe.tip = "Start everyone at zero. Asks each person to confirm; debts are kept."
  wipe:SetScript("OnClick", function() G.AskToWipe(nil) end)
  self.wipeBtn = wipe

  local caption = bp:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  caption:SetPoint("TOPLEFT", 8, -6)
  self.boardCaption = caption

  -- Shown against whoever is holding the fullest ledger: take theirs instead of
  -- yours. One button, moved to the right row (or the caption, if they have no
  -- record of their own to sit beside).
  local adopt = SmallButton(bp, "sync", 40)
  adopt:SetSize(40, 14)
  adopt:Hide()
  self.adoptBtn = adopt

  self.boardRows = {}
  for i = 1, 10 do
    local row = CreateFrame("Frame", nil, bp)
    row:SetHeight(16)
    row:SetPoint("TOPLEFT", 6, -24 - (i - 1) * 16)
    row:SetPoint("RIGHT", -6, 0)
    row.rank = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.rank:SetPoint("LEFT"); row.rank:SetWidth(22); row.rank:SetJustifyH("LEFT")
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", row.rank, "RIGHT", 2, 0); row.name:SetJustifyH("LEFT")
    row.rec = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.rec:SetPoint("RIGHT", -76, 0); row.rec:SetJustifyH("RIGHT")
    row.net = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.net:SetPoint("RIGHT"); row.net:SetWidth(72); row.net:SetJustifyH("RIGHT")
    row:Hide()
    self.boardRows[i] = row
  end

  f:SetScript("OnUpdate", function(_, elapsed)
    self.tick = (self.tick or 0) + elapsed
    local now = GetTime()

    if self.con then self.con:Paint() end   -- blink, rotate the slots, expire events

    -- the last call ticks once a second: redraw, and give the host a beat
    local left = Game.Countdown()
    local n = left and math.ceil(left) or nil
    if n ~= self.lastTick then
      self.lastTick = n
      self:Refresh()
      -- only beep 3 and 2; earlier ticks drown other cues, and 1 stacks on the
      -- "go" that fires at zero.
      if n and n >= 2 and n <= 3 then Sound.Play("tick3", n) end
      if n then
        for _, seat in ipairs(self.seats) do
          if seat.person and seat.person.name == Game.host then
            UI:Emote(seat, n <= 3 and ANIM.exclaim or ANIM.point, 1.1)
            seat.mood:SetText(T.text(n <= 3 and "warn" or "accent", n))
            break
          end
        end
      end
    end

    for _, seat in ipairs(self.seats) do
      if seat.person and seat.restAt and now > seat.restAt then
        seat.restAt = nil; seat.anim = ANIM.stand
        pcall(seat.model.SetAnimation, seat.model, ANIM.stand)
        seat.mood:SetText("")
      end
    end
    if self.tick > 5 then
      self.tick = 0
      -- somebody walked into range: swap their stand-in for the real thing
      for _, seat in ipairs(self.seats) do
        if seat.person and seat.how ~= "live" then
          local u = UnitFor(seat.person.name)
          if u and UnitIsVisible and UnitIsVisible(u) then ApplyArt(seat) end
        end
      end
    end
  end)
  f:SetScript("OnShow", function() Comm.Send("HI"); Game.Sync() end)
end

-- One grid for both views: the cells never move or change size, only the art
-- inside them does.
-- The table starts small ("nobody at the table") and grows as people join:
-- the row widens to COLS, then wraps to a new row, up to MAX_ROWS. Each row is
-- centred, so a part-full last row sits under the middle. The control row above
-- never moves - only this seat area below it changes size.
local function GridLayout(self, n)
  local scene = self.scene
  Extremes()
  local rows = (n == 0) and 0 or math.min(MAX_ROWS, math.ceil(n / COLS))
  local widest = math.min(COLS, math.max(n, 1))
  local w = math.max(widest * CELL_W + PAD * 2, MIN_W)
  local base = scene:GetFrameLevel() + 2

  for i, seat in ipairs(self.seats) do
    local p = Game.order[i] and Game.players[Game.order[i]]
    if p then
      local r, col = math.floor((i - 1) / COLS), (i - 1) % COLS
      local rowCount = (r == rows - 1) and (n - r * COLS) or COLS
      local left = (w - PAD * 2 - rowCount * CELL_W) / 2 + PAD   -- centre this row in the window
      seat.cell:SetSize(CELL_W, CELL_H)
      seat.cell:ClearAllPoints()
      seat.cell:SetPoint("TOPLEFT", scene, "TOPLEFT", left + col * CELL_W, -r * CELL_H)
      seat.cell:SetFrameLevel(base)
      SizeSeat(seat)
    end
    FillSeat(seat, p)
  end

  return w, (n == 0) and 44 or rows * CELL_H   -- empty is a short strip, not a full row
end

function UI:Layout()
  local n = math.min(#Game.order, COLS * MAX_ROWS)
  local w, h = GridLayout(self, n)
  self.scene:SetHeight(h)
  local dh = 0
  if self.debtPanel:IsShown() then
    local shown = math.min(12, #db.debts)
    dh = 12 + math.max(1, shown) * 16 + 4
    self.debtPanel:SetHeight(dh - 4)
  end
  local bh = 0
  if self.boardPanel:IsShown() then
    local shown = math.min(10, #G.Board())
    bh = 30 + math.max(1, shown) * 16 + 4
    self.boardPanel:SetHeight(bh - 4)
    self.boardPanel:ClearAllPoints()
    local above = self.debtPanel:IsShown() and self.debtPanel or self.scene
    self.boardPanel:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, -4)
    self.boardPanel:SetPoint("RIGHT", self.frame, "RIGHT", -PAD, 0)
  end
  self.frame:SetSize(w, HEAD_H + h + dh + bh + PAD + 28)
  if n == 0 then self.empty:Show() else self.empty:Hide() end
end

-- An event line in the header prompt: jumps in over the slots, holds, then the
-- rotation resumes. No-op until the window (and its console) is built.
function UI:Event(text, colour)
  if self.con then self.con:Say(text, colour) end
end

-- The header prompt's standing slots: whose table, the stakes, and either the
-- seat count (joining) or who still owes a roll (rolling). Events go through Say.
function UI:Console()
  local con = self.con
  if not con then return end
  local s = Game.state
  if Game.Active() then
    con:Set("host", Game.IsHost() and "your table" or (Bare(Game.host) .. "'s table"),
      Game.IsHost() and "gold" or "muted")
    con:Set("pot", "/roll " .. Game.max, "ink2")
  else
    con:Set("host", nil); con:Set("pot", nil)
  end
  if s == "JOIN" then
    con:Set("phase", #Game.order .. " in", "good")
  elseif s == "ROLL" or s == "TIE" then
    local miss = Game.Missing()
    if #miss > 0 then
      local names = {}
      for i = 1, math.min(3, #miss) do names[i] = Bare(miss[i]) end
      if #miss > 3 then names[#names + 1] = "+" .. (#miss - 3) end
      con:Set("phase", "roll: " .. table.concat(names, ", "), "gold")
    else
      con:Set("phase", "all rolled", "good")
    end
  else
    con:Set("phase", nil)
  end
end

function UI:Refresh()
  if not self.frame or not self.frame:IsShown() then return end
  self:Layout()
  local s, st = Game.state, self.status
  local me = MyName()
  local hosting = Game.IsHost() or not Game.Remote()
  local seated = Game.Seated()

  -- Everybody gets the same row in the same places; what you may not do is
  -- greyed, never moved or hidden. Anyone may open the next table once the
  -- current one is finished, so "start" belongs to everybody then.
  self.autoOpen:SetChecked(db.autoOpen ~= false and db.neverOpen ~= true)
  self.soundCheck:SetChecked(db.sound ~= false)
  self.neverOpen:SetChecked(db.neverOpen == true)
  -- with nothing allowed to open, the auto-open switch has nothing to say
  local blocked = db.neverOpen == true
  self.autoOpen:SetEnabled(not blocked)
  self.autoOpen.label:SetText(T.text(blocked and "muted" or "dim", "open when a game starts"))
  local canOpen = Game.IsHost() or not Game.Active()
  local running = Game.IsHost() and Game.Active()
  self.wagerLabel:SetTextColor(T.rgb(canOpen and "muted" or "dim"))
  self.wager:EnableMouse(canOpen)
  self.wager:SetTextColor(T.rgb(canOpen and "ink" or "dim"))
  if not canOpen then self.wager:ClearFocus() end
  self:Console()

  if s == "IDLE" then
    local owes, owed = Ledger.Net(me)
    local bits = {}
    if owes > 0 then bits[#bits + 1] = T.text("warn", "you owe " .. Gold(owes)) end
    if owed > 0 then bits[#bits + 1] = T.text("good", "you're owed " .. Gold(owed)) end
    st:SetText(#bits > 0 and table.concat(bits, "   ") or T.text("muted", "start a table"))
  elseif s == "JOIN" then
    local left = Game.Countdown()
    if left then
      st:SetText(T.text("ink2", #Game.order .. " in") .. T.text("accent", ("   last call - %d"):format(math.ceil(left))))
    else
      st:SetText(T.text("ink2", #Game.order .. " in") .. T.text("muted", hosting and "  -  1 in chat to join; last call, or start the rolls" or (seated and "  -  you're in, waiting for the host" or "  -  join to play")))
    end
  elseif s == "ROLL" or s == "TIE" then
    local miss = Missing()
    local names = {}
    for i = 1, math.min(6, #miss) do names[i] = ShortName(miss[i], 9) end
    if #miss > 6 then names[#names + 1] = "+" .. (#miss - 6) end
    local tail
    if not seated then tail = T.text("muted", "  -  table closed, catch the next one")
    elseif #miss > 0 then tail = T.text("muted", "  waiting: " .. table.concat(names, ", "))
    else tail = "" end
    st:SetText(T.text("accent", (s == "TIE" and "tiebreak " or "rolling ") .. "/" .. Game.max) .. tail)
  elseif s == "DONE" then
    local r = Game.result
    if r then
      local hi = Game.players[r.winner] and Game.players[r.winner].roll
      local lo = Game.players[r.loser] and Game.players[r.loser].roll
      local owes
      if r.loser == me then owes = T.text("warn", "you owe " .. Gold(r.amount))
      elseif r.winner == me then owes = T.text("good", "you get " .. Gold(r.amount))
      else owes = T.text("ink2", r.loser .. " owes " .. Gold(r.amount)) end
      st:SetText(T.text("good", r.winner .. (hi and (" " .. hi) or "")) ..
        T.text("muted", "  beats  ") ..
        T.text("warn", r.loser .. (lo and (" " .. lo) or "")) ..
        T.text("muted", "   -   ") .. owes)
    else st:SetText(T.text("muted", "no result")) end
  end

  local open = s == "JOIN" and Game.IsHost()
  local counting = Game.Countdown() ~= nil
  self.startBtn.text:SetText(open and (counting and "start now" or "start rolls") or "start")
  self.startBtn:SetWidth(open and (counting and 62 or 66) or 46)
  SetHot(self.startBtn, open or (canOpen and not Game.Active()))
  SetOff(self.startBtn, not canOpen)
  self.callBtn.text:SetText(counting and ("last call " .. math.ceil(Game.Countdown())) or "last call")
  SetHot(self.callBtn, open and not counting)
  SetOff(self.callBtn, not open or counting)
  SetHot(self.endBtn, running and (s == "ROLL" or s == "TIE"))
  SetOff(self.endBtn, not running)
  self.joinBtn.text:SetText(seated and "leave" or "join")
  SetHot(self.joinBtn, s == "JOIN" and not seated)
  SetOff(self.joinBtn, s ~= "JOIN")
  local can = Game.CanRoll()
  -- the one cue that matters most: it is your turn and the button just lit up
  if can and not self.couldRoll then Sound.Play("you") end
  self.couldRoll = can
  SetHot(self.rollBtn, can)
  SetOff(self.rollBtn, not can)
  local owes = Ledger.Net(me)
  local label, tip = "pay", "Open a trade with the next person you owe and put the gold in"
  if Trade.live then
    local who = TradePartner()
    local d = who and FindDebt(me, who)
    if d then label = "put " .. Gold(d.amount) .. " in"; tip = "Put " .. Gold(d.amount) .. " in the trade for " .. who end
  elseif owes > 0 then
    label = "pay " .. Gold(owes)
  end
  SetHot(self.payBtn, owes > 0)
  self.payBtn.text:SetText(label)
  self.payBtn.tip = tip
  self.payBtn:SetWidth(math.max(40, 24 + #label * 6))
  if not (self.wager.HasFocus and self.wager:HasFocus()) then
    self.wager:SetText(tostring((s == "IDLE" or s == "DONE") and db.wager or Game.max))
  end
  for v, b in pairs(self.viewBtns) do SetHot(b, View() == v) end
  self:RefreshDebts()
  self:RefreshBoard()
end

function UI:RefreshBoard()
  if not self.boardPanel:IsShown() then return end
  local list = G.Board()
  local me = MyName()
  local guildOnly = G.Scope() == "guild"
  self.scopeBtn.text:SetText(guildOnly and "guild only" or "everyone")
  SetHot(self.scopeBtn, guildOnly)
  local guild = MyGuild()
  local caption = guildOnly and (guild or "guild") or "every round, pugs included"

  -- who, if anyone, has more of the ledger than we do
  local fuller, count = G.BestLedger()
  local adopt = self.adoptBtn
  adopt:Hide()
  if fuller then
    adopt.who = fuller
    adopt.tip = ("Take %s's ledger instead of yours (%d rounds, you have %d)"):format(fuller, count, G.RoundCount())
    adopt:SetScript("OnClick", function() G.Adopt(adopt.who) end)
    SetHot(adopt, true)
  end
  for i, row in ipairs(self.boardRows) do
    local e = list[i]
    if e then
      local r = e.r
      row.rank:SetText(T.text(i == 1 and "gold" or "muted", "#" .. i))
      row.name:SetText(T.text(e.name == me and "gold" or "ink2", e.name)
        .. (e.name == Game.host and T.text("muted", "  (host)") or ""))
      row.rec:SetText(T.text("muted", ("%d-%d"):format(r.wins, r.losses)))
      row.net:SetText(T.text(r.net >= 0 and "good" or "warn",
        (r.net >= 0 and "+" or "-") .. Gold(math.abs(r.net))))
      row:Show()
      if fuller and e.name == fuller then
        adopt:ClearAllPoints()
        adopt:SetPoint("LEFT", row.name, "RIGHT", 8, 0)
        adopt:SetParent(row)
        adopt:Show()
      end
    else
      row:Hide()
    end
  end
  -- they hold the fullest ledger but have never played: put it by the caption
  if fuller and not adopt:IsShown() then
    caption = caption .. "  -  " .. fuller .. " has " .. count .. " rounds"
    adopt:SetParent(self.boardPanel)
    adopt:ClearAllPoints()
    adopt:SetPoint("LEFT", self.boardCaption, "RIGHT", 8, 0)
    adopt:Show()
  end
  self.boardCaption:SetText(T.text("muted", caption))
  if #list == 0 then
    local row = self.boardRows[1]
    row.rank:SetText(""); row.rec:SetText(""); row.net:SetText("")
    row.name:SetText(T.text("muted", "nobody has played a round yet"))
    row:Show()
  end
end

function UI:ToggleBoard()
  if self.boardPanel:IsShown() then self.boardPanel:Hide() else self.boardPanel:Show() end
  SetHot(self.boardBtn, self.boardPanel:IsShown())
  self:Refresh()
end

function UI:RefreshDebts()
  local dp = self.debtPanel
  if not dp:IsShown() then return end
  local list = {}
  for _, d in ipairs(db.debts) do list[#list + 1] = d end
  table.sort(list, function(a, b) return a.amount > b.amount end)
  local me = MyName()
  for i, row in ipairs(self.rows) do
    local d = list[i]
    row.debt = d
    if d then
      local mine = d.from == me
      local from = mine and T.text("gold", "you") or T.text("ink2", d.from)
      local to = d.to == me and T.text("gold", "you") or T.text("ink2", d.to)
      row.text:SetText(from .. T.text("muted", mine and " owe " or " owes ") .. to
        .. "  " .. T.text(mine and "warn" or d.to == me and "good" or "ink", Gold(d.amount)))
      row:Show()
    else
      row:Hide()
    end
  end
  if #list == 0 then
    self.rows[1].text:SetText(T.text("muted", "nobody owes anybody"))
    self.rows[1].paid:Hide(); self.rows[1]:Show()
  else
    self.rows[1].paid:Show()
  end
end

function UI:ToggleDebts()
  if self.debtPanel:IsShown() then self.debtPanel:Hide() else self.debtPanel:Show() end
  SetHot(self.debtsBtn, self.debtPanel:IsShown())
  self:Refresh()
end

function UI:Show()
  self:Build()
  -- nobody wants a gambling table over their raid frames mid-pull; it comes back
  if db.combat ~= false and InCombatLockdown and InCombatLockdown() then
    self.pendingShow = true
    return
  end
  self.frame:Show()
  self:Refresh()
end

--- Anything the addon opens on its own comes through here. "never open
--- anything" shuts this door; clicking things yourself still calls UI:Show.
function UI:AutoShow()
  if db.neverOpen then return false end
  if db.autoOpen == false then return false end
  self:Show()
  return true
end

--- Combat starts: get out of the way, and remember to come back.
function UI:CombatHide()
  if db.combat == false then return end
  if self.frame and self.frame:IsShown() then
    self.pendingShow = true
    self.frame:Hide()
  end
end

function UI:CombatShow()
  if not self.pendingShow then return end
  self.pendingShow = nil
  if db.combat == false then return end
  if db.neverOpen then return end
  self:Show()
end

function UI:Toggle()
  self:Build()
  if self.frame:IsShown() then self.frame:Hide() else self:Show() end
end

local function SeatOf(name)
  for _, seat in ipairs(UI.seats) do
    if seat.person and seat.person.name == name then return seat end
  end
end

function UI:OnRoll(name, roll)
  self:Refresh()
  local seat = SeatOf(name)
  local n = Game.max
  -- the whole table reacts to the extremes: a rolled 1 gets laughed at, a rolled
  -- max gets cheered. Everyone else at the table joins in.
  if roll == 1 or roll == n then
    local you, them = (roll == 1) and ANIM.cry or ANIM.flex, (roll == 1) and ANIM.laugh or ANIM.cheer
    if seat then self:Emote(seat, you, 4) end
    for _, s in ipairs(self.seats) do
      if s.person and s ~= seat then self:Emote(s, them, 4) end
    end
    return
  end
  if not seat then return end
  -- otherwise just a quick reaction to your own number
  if roll >= n * 0.9 then self:Emote(seat, ANIM.exclaim, 3)
  elseif roll <= n * 0.1 then self:Emote(seat, ANIM.question, 3)
  else self:Emote(seat, ANIM.talk, 2) end
end

-- the round is settled: everybody reacts by where they landed
function UI:OnResult(winner, loser)
  self:Refresh()
  local me = MyName()
  Sound.Play(me == winner and "win" or me == loser and "lose" or "done")
  local list = Sorted("roll")
  local n = #list
  for i, p in ipairs(list) do
    local seat = SeatOf(p.name)
    if seat then
      if p.name == winner then self:Emote(seat, ANIM.cheer, 8)
      elseif p.name == loser then self:Emote(seat, ANIM.cry, 8)
      else
        -- among the people in between: 0 = right next to paying, 1 = right next to winning
        local pos = (n > 3) and ((n - 1 - i) / (n - 3)) or 0.5
        local band = pos < 0.4 and MOOD[1] or pos > 0.6 and MOOD[3] or MOOD[2]
        self:Emote(seat, band[math.random(#band)], 6)
      end
    end
  end
end

----------------------------------------------------------------------------
-- Options window (the shared BiSTheme/Options.lua kit; Gamba is an adopter).
--
-- One narrow flat window, four control kinds, no tabs. Each row's `set` calls a
-- shared owner in `Own` that does the work and its live side effect; the same
-- owner is what the /gamba slash handlers call, so the window and chat never
-- drift. The window says every change in its BiS> prompt; the slash adds the
-- chat line. See claude/bis-options.md for the law.
----------------------------------------------------------------------------

-- owners: work + live side effect, no chat line (the window prompt says it; the
-- slash handler adds the chat). One per setting, shared by both callers.
local Own = {}
G.Own = Own
function Own.minimap(on)
  db.minimap = on and true or false
  local M = G.Minimap
  if M and M.button then if db.minimap then M.button:Show() else M.button:Hide() end end
end
function Own.comm(on)
  local lib = _G.LibBiSComm
  if lib then lib:SetEnabled(on and true or false) end
  if G.SharedComm then G.SharedComm.Save() end
end
function Own.recenter()
  if UI.frame then
    UI.frame:ClearAllPoints(); UI.frame:SetPoint("CENTER")
    db.point, db.rel, db.x, db.y = "CENTER", "CENTER", 0, 0
  end
end
function Own.wager(v) db.wager = v end
function Own.flat(on) db.payDiff = not on; UI:Refresh() end   -- on = flat (full wager)
function Own.autojoin(on) db.autoJoin = on and true or false end
function Own.announce(on) db.announce = on and true or false end
function Own.lastCall(v) db.lastCall = v end
function Own.grace(v) db.grace = v end
function Own.remind(v) db.remind = v end
function Own.scope(v) db.boardScope = v; if Rebuild then Rebuild() end; UI:Refresh() end
function Own.whisper(on) db.whisper = on and true or false end
function Own.autocopy(on) db.autoCopy = on and true or false end
function Own.sound(on) db.sound = on and true or false; if db.sound and Sound then Sound.quiet = false end end
function Own.channel(v) db.soundChannel = v end
function Own.view(v) db.view = v; UI:Refresh() end
function Own.scale(v) db.scale = v; if UI.frame then UI.frame:SetScale(v) end end
function Own.portrait(v) db.portrait = v; UI:Refresh() end
function Own.combat(on) db.combat = on and true or false end
function Own.popup(on) db.autoOpen = on and true or false; UI:Refresh() end
function Own.neveropen(on) db.neverOpen = on and true or false; UI:Refresh() end

-- the FojjiCore voice packs, as a stepper list: off, auto, then each pack.
local function VoiceList()
  local out = { "off", "auto" }
  local fc = _G.FojjiCore
  if fc and fc.voicePackOrder then for _, n in ipairs(fc.voicePackOrder) do out[#out + 1] = n end end
  return out
end
local function VoiceShort(v)
  v = v or "auto"
  if v == "off" or v == "auto" then return v end
  return ShortPack(v)
end
function Own.voice(i)
  local l = VoiceList()
  if i < 1 then i = 1 elseif i > #l then i = #l end
  db.voice = l[i]
  if Sound then Sound.voice = {}; if db.voice ~= "off" then Sound.Play("open") end end
end
G.VoiceList = VoiceList

-- The option list: sections top to bottom, each a { title, rows }. Rebuilt on
-- open so it reflects whether FojjiCore / LibBiSComm are actually here.
function UI:OptionSections()
  local gamba = {
    { kind = "toggle", label = "minimap button",
      get = function() return db.minimap ~= false end, set = function(_, on) Own.minimap(on) end },
  }
  if _G.LibBiSComm then
    gamba[#gamba + 1] = { kind = "toggle", label = "BiS channel (/bis)",
      get = function() local lib = _G.LibBiSComm; return lib and lib:Enabled() and true or false end,
      set = function(_, on) Own.comm(on) end }
  end
  gamba[#gamba + 1] = { kind = "button", label = "reset window position", button = "reset",
    action = function() Own.recenter() end }

  local sound = {
    { kind = "toggle", label = "sound cues",
      get = function() return db.sound ~= false end, set = function(_, on) Own.sound(on) end },
    { kind = "seg", label = "channel", values = { "SFX", "Master" },
      get = function() return db.soundChannel == "Master" and "Master" or "SFX" end,
      set = function(_, v) Own.channel(v) end },
  }
  if _G.FojjiCore and _G.FojjiCore.voicePackOrder then
    local vlist = VoiceList()
    sound[#sound + 1] = { kind = "step", label = "voice pack", min = 1, max = #vlist, step = 1,
      get = function() local l = VoiceList(); for i, n in ipairs(l) do if n == (db.voice or "auto") then return i end end; return 2 end,
      set = function(_, i) Own.voice(i) end,
      show = function() return VoiceShort(db.voice) end }
  end
  sound[#sound + 1] = { kind = "button", label = "test the cues", button = "test",
    action = function()
      if Sound then
        Sound.quiet = false; Sound.warned = false
        for i, name in ipairs({ "open", "call", "tick", "tick3", "go", "you", "tie", "redo", "win", "lose", "paid" }) do
          After((i - 1) * 1.0, function() Sound.Play(name) end)
        end
      end
    end }

  return {
    { title = "gamba", rows = gamba },
    { title = "table", rows = {
      { kind = "step", label = "default roll range", min = 10, max = 1000, step = 10,
        get = function() return db.wager or 100 end, set = function(_, v) Own.wager(v) end,
        show = function() return "/roll " .. (db.wager or 100) end },
      { kind = "toggle", label = "flat stakes",
        get = function() return not db.payDiff end, set = function(_, on) Own.flat(on) end },
      { kind = "toggle", label = "seat anyone who rolls",
        get = function() return db.autoJoin and true or false end, set = function(_, on) Own.autojoin(on) end },
      { kind = "toggle", label = "announce in chat",
        get = function() return db.announce ~= false end, set = function(_, on) Own.announce(on) end },
    } },
    { title = "timing", rows = {
      { kind = "step", label = "last call", min = 3, max = 30, step = 1,
        get = function() return db.lastCall or 10 end, set = function(_, v) Own.lastCall(v) end,
        show = function() return (db.lastCall or 10) .. "s" end },
      { kind = "step", label = "settle grace", min = 0, max = 10, step = 1,
        get = function() return db.grace or 3 end, set = function(_, v) Own.grace(v) end,
        show = function() return (db.grace or 3) .. "s" end },
      { kind = "step", label = "straggler reminder", min = 0, max = 120, step = 5,
        get = function() return db.remind or 30 end, set = function(_, v) Own.remind(v) end,
        show = function() local r = db.remind or 30; return r == 0 and "off" or (r .. "s") end },
    } },
    { title = "ledger", rows = {
      { kind = "seg", label = "board", values = { "guild", "all" },
        get = function() return G.Scope() end, set = function(_, v) Own.scope(v) end },
      { kind = "toggle", label = "whisper the balance",
        get = function() return db.whisper ~= false end, set = function(_, on) Own.whisper(on) end },
      { kind = "toggle", label = "select the amount",
        get = function() return db.autoCopy ~= false end, set = function(_, on) Own.autocopy(on) end },
      { kind = "button", label = "wipe my ledger", button = "wipe",
        action = function() G.WipeStats(); if UI.frame then UI:Refresh() end end },
      { kind = "button", label = "reset board for all", button = "reset",
        action = function() G.AskToWipe(nil) end },
    } },
    { title = "sound", rows = sound },
    { title = "display", rows = {
      { kind = "seg", label = "portraits", values = { "2d", "3d" },
        get = function() return View() end, set = function(_, v) Own.view(v) end },
      { kind = "step", label = "window scale", min = 50, max = 200, step = 5,
        get = function() return math.floor((db.scale or 1) * 100 + 0.5) end,
        set = function(_, v) Own.scale(v / 100) end,
        show = function() return math.floor((db.scale or 1) * 100 + 0.5) .. "%" end },
      { kind = "step", label = "3d zoom", min = 0, max = 100, step = 5,
        get = function() return math.floor((db.portrait or 0.75) * 100 + 0.5) end,
        set = function(_, v) Own.portrait(v / 100) end,
        show = function() return math.floor((db.portrait or 0.75) * 100 + 0.5) .. "%" end },
      { kind = "toggle", label = "hide in combat",
        get = function() return db.combat ~= false end, set = function(_, on) Own.combat(on) end },
      { kind = "toggle", label = "open on a new game",
        get = function() return db.autoOpen ~= false end, set = function(_, on) Own.popup(on) end },
      { kind = "toggle", label = "never open anything",
        get = function() return db.neverOpen == true end, set = function(_, on) Own.neveropen(on) end },
    } },
  }
end

-- Build the window from the option list, once. The kit carries the chrome.
function UI:BuildOptions()
  if self.opt then return self.opt end
  local f = T.Options("BiSGambaOptions", T.OPTIONS and T.OPTIONS.W or 230, "Gamba")
  for _, sec in ipairs(self:OptionSections()) do
    f:Section(sec.title)
    for _, row in ipairs(sec.rows) do if row then f:Row(row, db) end end
  end
  f:Fit()
  f.onChange = function() if UI.frame and UI.frame:IsShown() then UI:Refresh() end end
  f:Recenter()     -- the kit anchors nothing itself; give it a home or it opens off-screen
  self.opt = f
  tinsert(UISpecialFrames, "BiSGambaOptions")
  return f
end

-- Park the options window beside the table when the table is up, else centre it.
function UI:PlaceOptions(f)
  f:ClearAllPoints()
  if self.frame and self.frame:IsShown() then
    f:SetPoint("TOPLEFT", self.frame, "TOPRIGHT", 8, 0)
  else
    f:Recenter()
  end
end

function UI:OpenConfig()
  local f = self:BuildOptions()
  self:PlaceOptions(f)
  f:Toggle(true)
end
function UI:ToggleConfig()
  local f = self:BuildOptions()
  if f:IsShown() then f:Toggle(false) else self:PlaceOptions(f); f:Toggle(true) end
end



----------------------------------------------------------------------------
-- minimap button
----------------------------------------------------------------------------
local Mini = {}
G.Minimap = Mini
local RADIUS = 80

local function angle()
  local a = tonumber(db.minimapAngle)
  if not a or a ~= a then a = 200 end
  return math.rad(a)
end

function Mini:Place()
  local b = self.button
  if not b or not Minimap then return end
  local a = angle()
  b:ClearAllPoints()
  b:SetPoint("CENTER", Minimap, "CENTER", RADIUS * math.cos(a), RADIUS * math.sin(a))
end

local function dragUpdate()
  local mx, my = Minimap:GetCenter()
  local scale = Minimap:GetEffectiveScale()
  if not mx or not scale or scale <= 0 then return end
  local cx, cy = GetCursorPosition()
  cx, cy = cx / scale, cy / scale
  db.minimapAngle = math.deg(math.atan2(cy - my, cx - mx))
  Mini:Place()
end

function Mini:Build()
  if self.button or not Minimap then return end
  local b = CreateFrame("Button", "BiSGambaMinimapButton", Minimap)
  b:SetSize(32, 32)
  b:SetFrameStrata("MEDIUM")
  b:SetFrameLevel(8)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:RegisterForDrag("LeftButton")
  local icon = b:CreateTexture(nil, "BACKGROUND")
  icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_02")
  icon:SetSize(20, 20)
  icon:SetPoint("CENTER", 0, 1)
  icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  local border = b:CreateTexture(nil, "OVERLAY")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetSize(54, 54)
  border:SetPoint("TOPLEFT")
  b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  b:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", dragUpdate) end)
  b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
  b:SetScript("OnClick", function(_, button)
    if button == "RightButton" then UI:Show(); Game.RollMe() else UI:Toggle() end
  end)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine(T.text("accent", "BiS Gamba"))
    local owes, owed = Ledger.Net(MyName())
    if owes > 0 then GameTooltip:AddLine("you owe " .. Gold(owes), T.rgb("warn")) end
    if owed > 0 then GameTooltip:AddLine("you're owed " .. Gold(owed), T.rgb("good")) end
    GameTooltip:AddLine("Left: table   Right: roll   Drag: move", T.rgb("muted"))
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  self.button = b
  self:Place()
  if db.minimap == false then b:Hide() end
end

----------------------------------------------------------------------------
-- slash
----------------------------------------------------------------------------
local function Help()
  Print(T.text("accent", "BiS Gamba") .. " " .. T.text("muted", ((C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata("BiSGamba", "Version"))
    or (GetAddOnMetadata and GetAddOnMetadata("BiSGamba", "Version")) or "")) .. " - commands:")
  local lines = {
    "/gamba              toggle the table",
    "/gamba start [N]    open a table, /roll N (default " .. tostring(db.wager) .. ")",
    "/gamba call [secs]  last call: a countdown, then the rolls start themselves",
    "/gamba go           stop taking joins, start rolling now",
    "/gamba join         join / leave somebody else's table (types 1 / -1)",
    "/gamba roll         roll the right range",
    "/gamba view [2d|3d]  switch between 2D and 3D portraits",
    "/gamba end          settle with the rolls in / close the table",
    "/gamba nudge        name the people still to roll, in chat",
    "/gamba remind N     seconds before the straggler reminder (0 = off)",
    "/gamba pay [name]   trade the gold to the next person you owe",
    "/gamba config       the settings window (options | settings)",
    "/gamba debts        print who owes who",
    "/gamba board        the leaderboard, biggest winners first",
    "/gamba sync         swap missing rounds with the group so the board agrees",
    "/gamba adopt [who]  throw your ledger away and take theirs whole",
    "/gamba rounds       the round ledger the leaderboard is built from",
    "/gamba rebuild      recompute the leaderboard from the ledger",
    "/gamba history      the last ten rounds",
    "/gamba scope [guild|all]   whether pug rounds count on the board",
    "/gamba wipestats yes       throw away your ledger",
    "/gamba wipestats all       ask everyone with the addon to wipe theirs too",
    "/gamba paid A B     mark A's debt to B paid",
    "/gamba clear        wipe every debt",
    "/gamba flat         toggle: loser pays the difference (default) or the full wager",
    "/gamba autojoin     toggle: seat anyone in the group who /rolls the range (default off: only 1 / join counts)",
    "/gamba quiet        toggle chat announcements",
    "/gamba popup        toggle: open the window when a host starts a game",
    "/gamba combat       toggle hiding the window while you're in combat",
    "/gamba neveropen    toggle: nothing ever appears on its own",
    "/gamba sound        toggle the cues (sound test | probe | kit <id> | sfx|master)",
    "/gamba voice        speak the cues with a FojjiCore voice pack (voice list | <name> | off | auto)",
    "/gamba whisper      toggle whispering the balance to people without the addon",
    "/gamba users        who else you have seen running BiS Gamba",
    "/gamba autocopy     toggle selecting the amount for you when a trade opens",
    "/gamba scale X | zoom X | npc Race 2|3 id | minimap | fixtrade | tradedebug | reset",
  }
  for _, l in ipairs(lines) do DEFAULT_CHAT_FRAME:AddMessage("  " .. T.text("ink2", l)) end
end

local function Slash(msg)
  msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
  local cmd, rest = msg:match("^(%S+)%s*(.*)$")
  cmd = (cmd or ""):lower()
  if cmd == "" then UI:Toggle()
  elseif cmd == "start" or cmd == "open" then UI:Show(); Game.Open(tonumber(rest))
  elseif cmd == "go" then UI:Show(); Game.StartRolls()
  elseif cmd == "call" or cmd == "lastcall" then UI:Show(); Game.LastCall(tonumber(rest))
  elseif cmd == "roll" then UI:Show(); Game.RollMe()
  elseif cmd == "end" or cmd == "settle" or cmd == "stop" then Game.End()
  elseif cmd == "add" and rest ~= "" then UI:Show(); Game.Add(Bare(rest))
  elseif cmd == "pay" then Trade.Pay(rest ~= "" and Bare(rest) or nil)
  elseif cmd == "debts" or cmd == "owe" then
    if #db.debts == 0 then Print("nobody owes anybody") end
    for _, d in ipairs(db.debts) do Print(("%s owes %s %s"):format(d.from, d.to, Gold(d.amount))) end
  elseif cmd == "join" or cmd == "leave" then UI:Show(); Game.JoinMe()
  elseif cmd == "view" then
    local v = rest:lower()
    if v ~= "2d" and v ~= "3d" then v = (View() == "2d") and "3d" or "2d" end
    db.view = v; Print("view: " .. v); UI:Refresh()
  elseif cmd == "paid" then
    local a, b = rest:match("^(%S+)%s+(%S+)$")
    local d = a and FindDebt(Bare(a), Bare(b))
    if d then Ledger.Announce(d.from, d.to, d.amount) end
    if a and Ledger.Clear(Bare(a), Bare(b)) then Print(a .. " -> " .. b .. " marked paid"); UI:Refresh()
    else Warn("usage: /gamba paid <who owes> <who is owed>") end
  elseif cmd == "clear" then Ledger.ClearAll(); Print("ledger wiped"); UI:Refresh()
  elseif cmd == "flat" then db.payDiff = not db.payDiff; Print(db.payDiff and "loser pays the difference" or "loser pays the full wager")
  elseif cmd == "nudge" then Game.Remind(true)
  elseif cmd == "remind" then db.remind = tonumber(rest) or 30; Print("straggler reminder after " .. db.remind .. "s (0 = off)")
  elseif cmd == "autojoin" then db.autoJoin = not db.autoJoin; Print("autojoin " .. (db.autoJoin and "on" or "off"))
  elseif cmd == "autocopy" then db.autoCopy = db.autoCopy == false; Print(db.autoCopy and "the amount is selected for you, ready to Ctrl+C" or "click the amount yourself to select it")
  elseif cmd == "whisper" then db.whisper = db.whisper == false; Print(db.whisper and "whispering the balance to people without the addon" or "not whispering on trades")
  elseif cmd == "users" then
    local n = 0
    for name, at in pairs(db.users or {}) do n = n + 1; Print(name .. "  " .. math.floor((Now() - at) / 86400) .. "d ago") end
    if n == 0 then Print("nobody else seen running the addon yet") end
  elseif cmd == "quiet" then db.announce = not db.announce; Print(db.announce and "announcing in chat" or "quiet: results only to you")
  elseif cmd == "scale" then db.scale = math.max(0.5, math.min(2, tonumber(rest) or 1)); if UI.frame then UI.frame:SetScale(db.scale) end
  elseif cmd == "zoom" then db.portrait = math.max(0, math.min(1, tonumber(rest) or 0.75)); UI:Refresh()
  elseif cmd == "npc" then
    local race, sex, id = rest:match("^(%a+)%s+(%d)%s+(%d+)$")
    if race and NPC[race] then db.npc[race] = db.npc[race] or {}; db.npc[race][tonumber(sex)] = tonumber(id); Print(race .. " " .. sex .. " -> npc " .. id); UI:Refresh()
    else Warn("usage: /gamba npc <Race> <2|3> <npcID>   races: " .. (function() local t = {} for r in pairs(NPC) do t[#t + 1] = r end table.sort(t) return table.concat(t, " ") end)()) end
  elseif cmd == "autoopen" or cmd == "popup" then
    db.autoOpen = db.autoOpen == false; Print(db.autoOpen and "the table will pop up when a host starts a game" or "the table stays closed until you /gamba"); UI:Refresh()
  elseif cmd == "sound" then
    local v = rest:lower()
    local kit = v:match("^kit%s+(%d+)$")
    if kit then
      local id = tonumber(kit)
      local ok, willPlay = pcall(PlaySound, id, db.soundChannel or "Master")
      Print(("kit %d on %s: %s"):format(id, db.soundChannel or "Master",
        (ok and willPlay ~= false) and T.text("good", "played") or T.text("warn", "nothing")))
    elseif v == "probe" then
      Print("looking for sounds this client will play...")
      Sound.Probe()
    elseif v == "test" then
      Sound.quiet, Sound.warned = false, false
      local order = { "open", "call", "tick", "tick3", "go", "you", "tie", "redo", "win", "lose", "paid" }
      Print("playing every cue...")
      for i, name in ipairs(order) do
        After((i - 1) * 1.1, function() Print("  " .. name); Sound.Play(name) end)
      end
    elseif v == "master" or v == "sfx" or v == "ambience" or v == "music" or v == "dialog" then
      db.soundChannel = v == "master" and "Master" or (v:sub(1, 1):upper() .. v:sub(2))
      Print("sounds play on the " .. db.soundChannel .. " channel")
    else
      db.sound = db.sound == false
      Sound.quiet = false
      Print(db.sound and "sounds on" or "sounds off")
      if db.sound then Sound.Play("open") end
    end
  elseif cmd == "voice" then
    local v = rest:match("^%s*(.-)%s*$")
    local fc = _G.FojjiCore
    local packs = fc and fc.voicePackOrder or {}
    if v == "" or v:lower() == "list" then
      local cur = VoicePack()
      Print("voice: " .. (cur and T.text("good", cur) or T.text("ink2", "off")) .. (db.voice == "auto" and " (auto)" or ""))
      if #packs == 0 then
        Print("FojjiCore is " .. (fc and "loaded but has no packs" or "not installed") .. " - the cues stay musical")
      else
        Print("packs: " .. table.concat(packs, ", "))
      end
    elseif v:lower() == "off" or v:lower() == "auto" then
      db.voice = v:lower()
      Sound.voice = {}
      local cur = VoicePack()
      Print(cur and ("the cues are spoken by " .. cur) or "the cues are back to the motifs")
      if cur then Sound.Play("open") end
    else
      local found
      for _, name in ipairs(packs) do if name:lower() == v:lower() then found = name end end
      if not found then
        for _, name in ipairs(packs) do if name:lower():find(v:lower(), 1, true) then found = found or name end end
      end
      db.voice = found or v
      Sound.voice = {}
      Print("the cues are spoken by " .. db.voice .. (found and "" or " (if FojjiCore has that folder)"))
      Sound.Play("open")
    end
  elseif cmd == "neveropen" then
    db.neverOpen = not db.neverOpen
    Print(db.neverOpen and "nothing will open by itself" or "the window may open by itself again")
    UI:Refresh()
  elseif cmd == "combat" then
    db.combat = db.combat == false
    Print(db.combat and "the window hides while you're in combat" or "the window stays put in combat")
  elseif cmd == "minimap" then
    db.minimap = db.minimap == false
    if Mini.button then if db.minimap then Mini.button:Show() else Mini.button:Hide() end end
  elseif cmd == "tradedebug" then
    Print("trade window: " .. tostring(TradeFrame and TradeFrame:IsShown()))
    Print("partner: " .. tostring(TradePartner()))
    Print("SetTradeMoney " .. type(SetTradeMoney) .. ", MoneyInputFrame_SetCopper " .. type(MoneyInputFrame_SetCopper))
    Print("GetPlayerTradeMoney " .. type(GetPlayerTradeMoney) .. ", MoneyInputFrame_GetCopper " .. type(MoneyInputFrame_GetCopper))
    Print("input frame: " .. tostring(TradePlayerInputMoneyFrame ~= nil))
    Print("live trade: " .. tostring(Trade.live) .. ", both accepted: " .. tostring(Trade.bothAccepted))
    Print("on the table: mine " .. tostring(GetPlayerTradeMoney and GetPlayerTradeMoney()) .. ", theirs " .. tostring(GetTargetTradeMoney and GetTargetTradeMoney()))
    Print("reads back: " .. tostring(TradeMoneyNow()) .. " copper")
  elseif cmd == "fixtrade" then Trade.FixStuck()
  elseif cmd == "reset" then Game.Reset(); Print("table reset")
  elseif cmd == "config" or cmd == "options" or cmd == "settings" or cmd == "opt" then UI:OpenConfig()
  elseif cmd == "sync" then Game.Sync(); Print("asking the group for any rounds we missed")
  elseif cmd == "adopt" then
    local who = rest ~= "" and Bare(rest) or (G.BestLedger())
    if who then G.Adopt(who) else Print("nobody has a fuller ledger than yours - open the board and hit sync first") end
  elseif cmd == "scope" then
    local v = rest:lower()
    db.boardScope = (v == "all" or v == "guild") and v or ((G.Scope() == "guild") and "all" or "guild")
    Rebuild(); Print("leaderboard: " .. (G.Scope() == "guild" and ("guild only (" .. tostring(MyGuild()) .. ")") or "every round")); UI:Refresh()
  elseif cmd == "wipestats" then
    local how = rest:lower()
    if how == "yes" then
      G.WipeStats(); Print("your leaderboard is wiped"); UI:Refresh()
    elseif how == "all" then
      AskToWipe(nil)
    else
      local n = 0
      for _ in pairs(db.rounds) do n = n + 1 end
      Warn(("this throws away the round ledger (%d rounds) and everyone's record"):format(n))
      Print("  " .. T.text("ink", "/gamba wipestats yes") .. " wipes yours")
      Print("  " .. T.text("ink", "/gamba wipestats all") .. " asks everyone with the addon to wipe theirs too")
    end
  elseif cmd == "rounds" then
    local list = {}
    for id, rd in pairs(db.rounds) do list[#list + 1] = { id = id, rd = rd } end
    table.sort(list, function(a, b) return (a.rd.at or 0) > (b.rd.at or 0) end)
    Print(("%d rounds on file"):format(#list))
    for i = 1, math.min(15, #list) do
      local e = list[i]
      Print(("%s  /%d  %s beat %s for %s"):format(e.id, e.rd.max or 0, e.rd.winner, e.rd.loser, Gold(e.rd.amount)))
    end
  elseif cmd == "rebuild" then Rebuild(); Print("leaderboard rebuilt from the rounds on file"); UI:Refresh()
  elseif cmd == "board" or cmd == "leaderboard" or cmd == "top" then
    local list = G.Board()
    if #list == 0 then Print("nobody has played a round yet") end
    for i = 1, math.min(10, #list) do
      local e = list[i]
      Print(("#%d  %s  %s%s  (%d-%d)"):format(i, e.name, e.r.net >= 0 and "+" or "-", Gold(math.abs(e.r.net)), e.r.wins, e.r.losses))
    end
  elseif cmd == "history" then
    for i = 1, math.min(10, #db.history) do
      local h = db.history[i]
      Print(("/%d  %s high, %s low, %s"):format(h.max, h.high, h.low, Gold(h.amount)))
    end
  else Help() end
end

SLASH_BISGAMBA1 = "/gamba"
SLASH_BISGAMBA2 = "/bisgamba"
SLASH_BISGAMBA3 = "/gamble"
SlashCmdList.BISGAMBA = Slash

----------------------------------------------------------------------------
-- events
----------------------------------------------------------------------------
--------------------------------------------------------------------------
-- The shared BiS channel (Libs\LibBiSComm-1.0, embedded byte-identical from
-- _bisdev). It is NOT a Gamba feature and no setting here may gate it: just
-- carrying this addon makes the client answer WHERE and SUM for any BiS
-- summoner in the raid - "one addon gets you half way". Only /bis off mutes it.
-- Gamba's own BiSGamba pipe (PREFIX above) is a separate channel, untouched.
-- The lib keeps no SavedVariables, so its off switch is remembered in
-- BiSGambaDB.comm and restored next login.
--------------------------------------------------------------------------
local SharedComm = {}
G.SharedComm = SharedComm

function SharedComm.Boot()
  local lib = _G.LibBiSComm
  if not lib then return end
  lib:RegisterAddon(ADDON, (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version"))
    or (GetAddOnMetadata and GetAddOnMetadata(ADDON, "Version")) or "dev")
  if db and db.comm == false then lib:SetEnabled(false) end   -- restore the off switch
  lib:Boot()
end

function SharedComm.Save()
  local lib = _G.LibBiSComm
  if lib and db then db.comm = lib:Enabled() and true or false end
end

local ev = CreateFrame("Frame")
G._ev = ev
local function Reg(e) pcall(ev.RegisterEvent, ev, e) end
Reg("ADDON_LOADED")
Reg("PLAYER_LOGIN")
Reg("PLAYER_LOGOUT")

local CHAT = { CHAT_MSG_RAID = true, CHAT_MSG_RAID_LEADER = true, CHAT_MSG_PARTY = true,
  CHAT_MSG_PARTY_LEADER = true, CHAT_MSG_SAY = true, CHAT_MSG_RAID_WARNING = true }
local TRADE = { "TRADE_SHOW", "TRADE_CLOSED", "TRADE_REQUEST_CANCEL", "TRADE_MONEY_CHANGED",
  "PLAYER_TRADE_MONEY", "TRADE_ACCEPT_UPDATE", "UI_INFO_MESSAGE", "UI_ERROR_MESSAGE" }

ev:SetScript("OnEvent", function(_, event, a1, a2, ...)
  if event == "ADDON_LOADED" then
    if a1 == ADDON then InitDB() end
  elseif event == "PLAYER_LOGIN" then
    if not db then InitDB() end
    Mini:Build()
    Comm.Register()
    SharedComm.Boot()                -- the shared BiS channel, alongside our own pipe
    Reg("CHAT_MSG_ADDON")
    Reg("CHAT_MSG_SYSTEM")
    for e in pairs(CHAT) do Reg(e) end
    for _, e in ipairs(TRADE) do Reg(e) end
    Reg("GROUP_ROSTER_UPDATE")
    Reg("PLAYER_GUILD_UPDATE")
    Reg("PLAYER_REGEN_DISABLED")
    Reg("PLAYER_REGEN_ENABLED")
    Rebuild()                        -- guild is usually known by login; recompute the scoped board
  elseif event == "CHAT_MSG_SYSTEM" then
    local who, roll, lo, hi = ParseRoll(a1 or "")
    if who then Game.OnRoll(who, roll, lo, hi) end
  elseif CHAT[event] then
    Game.OnChat(a1, a2)
  elseif event == "CHAT_MSG_ADDON" then
    if a1 == PREFIX then Game.OnComm(a2 or "", (select(2, ...))) end
  elseif event == "PLAYER_LOGOUT" then
    SharedComm.Save()                -- the lib has no SavedVariables; its switch is ours to keep
  elseif event == "PLAYER_REGEN_DISABLED" then
    UI:CombatHide()
  elseif event == "PLAYER_REGEN_ENABLED" then
    UI:CombatShow()
  elseif event == "GROUP_ROSTER_UPDATE" then
    -- host gone, or sitting there disconnected: their table is dead, let go of it
    if Game.Remote() then
      local u = UnitFor(Game.host)
      local gone = not u or (UnitIsConnected and not UnitIsConnected(u))
      if gone then Print(Game.host .. " left - table closed"); Game.Reset() end
    end
    if UI.frame and UI.frame:IsShown() then UI:Refresh() end
  else
    Trade.OnEvent(event, a1, a2)
  end
end)
