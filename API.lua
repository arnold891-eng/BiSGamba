--------------------------------------------------------------------------------
-- BiSGambaAPI: for other addons (16 Oct 2026).
--
-- Arn: "lets do api calls for the other addons, and going forward our stuff will have open api to
-- call". So a caller never reaches into BiS Gamba's insides (BiSGamba.Ledger, BiSGambaDB, the Game
-- table): it asks here, and here stays the same while the insides change. Shaped like BiSToolsAPI:
--   * BiSGambaAPI.version goes up when something is added; nothing is changed or taken away
--     without a new BiSGambaAPI.major. A caller checks `api.major == 1` first.
--   * READ-ONLY, plus opening the window. Nothing here moves gold, settles a debt, places a bet,
--     seats anybody or changes the books or a setting. Every answer is a fresh copy: editing it
--     never edits the ledger.
--   * Safe at any time: before the saved variables load every question answers nil, "not ready".
--     Nothing here errors - a fault inside answers nil, "error".
--
-- Names are as BiS Gamba keeps them: the realm-less name ("Kumlust"; Forever's whole "Name Surname").
-- A caller may pass "Name-Realm"; the realm is dropped. Gold is whole gold (not copper). Times are
-- GetServerTime() seconds. The board follows the player's own scope setting ("guild" = rounds played
-- among guildmates only, "all" = every round).
--
-- A record (Leaderboard, Standing):
--   { name =, net = (gold won minus lost), wins =, losses =, games =, best = (biggest win),
--     worst = (biggest loss) }
-- A debt: { from =, to =, amount = (gold), at = (when it last changed) }
--
-- Questions (all since version 1):
--   Ready()        -> true, or nil, "not ready"
--   Scope()        -> "guild" | "all", or nil, why. Which rounds the board counts.
--   Leaderboard()  -> list of records, best net first (ties by name), only people with games > 0;
--                     or nil, why.
--   Standing(name) -> a record plus streak = "win"|"lose"|nil, streakLength = n, owes = (gold this
--                     person owes in all), owed = (gold owed to them in all); or nil, why
--                     ("no name", "no such player" - never played and no debts).
--   Debts(name)    -> { owes = { debt, ... } biggest first, owed = { debt, ... } biggest first },
--                     or nil, why ("no name"). Somebody with no debts gets two empty lists.
--   AllDebts()     -> every open debt, biggest first; or nil, why.
--   RecentRounds(n)-> the last n settled rounds this client saw (default and most 50), newest first:
--                     { at =, max = (the roll's top), winner =, loser =, amount =, host =, id =,
--                     rolls = { [name] = roll } }; or nil, why.
--   Playing()      -> true while a table is open or rolling (anyone's), false when not; or nil, why.
--   Table()        -> { state = "IDLE"|"JOIN"|"ROLL"|"TIE"|"DONE", host = (name or nil),
--                     hosting = (true when this player hosts), max =, players = { { name =,
--                     roll = (nil until rolled) }, ... } in seat order, result = (nil, or
--                     { winner =, loser =, amount = } once settled) }; or nil, why.
--
-- Actions (since version 1) - only what a player could do with a click:
--   Open()         -> true when the window is shown; false, "after combat" when the player's
--                     "hide in combat" setting holds it until the fight ends (it opens then,
--                     exactly as the minimap button would); or nil, why.
--
-- Events (since version 1):
--   RegisterCallback(owner, event, fn) -> true, or nil, why ("bad event", "no owner", "no function").
--     owner is any table or string of the caller's; one fn per owner per event (a second replaces
--     the first). fn is called as fn(event, payload) inside a pcall - an error there never reaches
--     BiS Gamba or another listener.
--   UnregisterCallback(owner, event) -> true.
--   "BiSGamba_RoundEnded": a round was settled and is new to this client (hosted here, or watched
--     at somebody else's table). payload = { id =, winner =, loser =, amount =, high = (the winning
--     roll), low = (the paying roll), max =, host =, at = } - a copy for each listener.
--------------------------------------------------------------------------------

local API = { major = 1, version = 1 }
BiSGambaAPI = API

local function Gamba()
  local G = _G.BiSGamba
  if type(G) ~= "table" or type(G.db) ~= "table" then return nil, "not ready" end
  return G, G.db
end

-- every entry point runs inside this: a fault answers nil, "error", never an error
local function Answer(ok, ...)
  if not ok then return nil, "error" end
  return ...
end
local function Safe(fn)
  return function(...) return Answer(pcall(fn, ...)) end
end

local function Bare(name)
  if type(name) ~= "string" or name == "" then return nil end
  return name:match("^[^-]+") or name
end

local function Record(name, r)
  r = type(r) == "table" and r or {}
  return { name = name, net = tonumber(r.net) or 0, wins = tonumber(r.wins) or 0,
           losses = tonumber(r.losses) or 0, games = tonumber(r.games) or 0,
           best = tonumber(r.best) or 0, worst = tonumber(r.worst) or 0 }
end

local function Debt(d)
  return { from = d.from, to = d.to, amount = tonumber(d.amount) or 0, at = d.at }
end

local function Biggest(a, b)
  if a.amount == b.amount then return tostring(a.from) .. tostring(a.to) < tostring(b.from) .. tostring(b.to) end
  return a.amount > b.amount
end

local function DebtList(db)
  return type(db.debts) == "table" and db.debts or {}
end

API.Ready = Safe(function()
  local G, why = Gamba()
  if not G then return nil, why end
  return true
end)

API.Scope = Safe(function()
  local G, why = Gamba()
  if not G then return nil, why end
  return G.Scope()
end)

API.Leaderboard = Safe(function()
  local G, why = Gamba()
  if not G then return nil, why end
  local out = {}
  for _, row in ipairs(G.Board()) do out[#out + 1] = Record(row.name, row.r) end
  return out
end)

API.Standing = Safe(function(name)
  local G, db = Gamba()
  if not G then return nil, db end
  name = Bare(name)
  if not name then return nil, "no name" end
  -- read the stats table directly: BiSGamba.Stat() would CREATE a record for a stranger
  local r = type(db.stats) == "table" and db.stats[name] or nil
  local owes, owed = 0, 0
  for _, d in ipairs(DebtList(db)) do
    if d.from == name then owes = owes + (tonumber(d.amount) or 0) end
    if d.to == name then owed = owed + (tonumber(d.amount) or 0) end
  end
  if type(r) ~= "table" and owes == 0 and owed == 0 then return nil, "no such player" end
  local out = Record(name, r)
  local kind, len = G.Streak(name)
  out.streak, out.streakLength = kind, tonumber(len) or 0
  out.owes, out.owed = owes, owed
  return out
end)

API.Debts = Safe(function(name)
  local G, db = Gamba()
  if not G then return nil, db end
  name = Bare(name)
  if not name then return nil, "no name" end
  local owes, owed = {}, {}
  for _, d in ipairs(DebtList(db)) do
    if d.from == name then owes[#owes + 1] = Debt(d) end
    if d.to == name then owed[#owed + 1] = Debt(d) end
  end
  table.sort(owes, Biggest)
  table.sort(owed, Biggest)
  return { owes = owes, owed = owed }
end)

API.AllDebts = Safe(function()
  local G, db = Gamba()
  if not G then return nil, db end
  local out = {}
  for _, d in ipairs(DebtList(db)) do out[#out + 1] = Debt(d) end
  table.sort(out, Biggest)
  return out
end)

API.RecentRounds = Safe(function(n)
  local G, db = Gamba()
  if not G then return nil, db end
  n = math.floor(tonumber(n) or 50)
  if n > 50 then n = 50 end
  local out = {}
  for i, h in ipairs(type(db.history) == "table" and db.history or {}) do
    if i > n then break end
    local rolls = {}
    for who, roll in pairs(type(h.rolls) == "table" and h.rolls or {}) do rolls[who] = roll end
    out[#out + 1] = { at = h.at, max = h.max, winner = h.high, loser = h.low, amount = h.amount,
                      host = h.host, id = h.id, rolls = rolls }
  end
  return out
end)

API.Playing = Safe(function()
  local G, why = Gamba()
  if not G then return nil, why end
  return G.Game.Active() and true or false
end)

API.Table = Safe(function()
  local G, why = Gamba()
  if not G then return nil, why end
  local Game = G.Game
  local players = {}
  for _, name in ipairs(Game.order or {}) do
    local p = Game.players and Game.players[name]
    if p then players[#players + 1] = { name = name, roll = p.roll } end
  end
  local res = Game.result
  return { state = Game.state, host = Game.host, hosting = Game.IsHost() and true or false,
           max = Game.max, players = players,
           result = res and { winner = res.winner, loser = res.loser, amount = res.amount } or nil }
end)

API.Open = Safe(function()
  local G, why = Gamba()
  if not G then return nil, why end
  local UI = G.UI
  UI:Show()
  if UI.frame and UI.frame:IsShown() then return true end
  if UI.pendingShow then return false, "after combat" end
  return nil, "not shown"
end)

---------------------------------------------------------------- events
local EVENTS = { BiSGamba_RoundEnded = true }
local owners = {}            -- [event] = { [owner] = fn }

API.RegisterCallback = Safe(function(owner, event, fn)
  if not EVENTS[event] then return nil, "bad event" end
  if owner == nil then return nil, "no owner" end
  if type(fn) ~= "function" then return nil, "no function" end
  owners[event] = owners[event] or {}
  owners[event][owner] = fn
  return true
end)

API.UnregisterCallback = Safe(function(owner, event)
  if owners[event] and owner ~= nil then owners[event][owner] = nil end
  return true
end)

local function Copy(t)
  local out = {}
  for k, v in pairs(t) do out[k] = v end
  return out
end

-- BiSGamba.lua calls this (pcall'd) when something happens; one pcall per listener
local function Fire(event, payload)
  local list = owners[event]
  if not list then return end
  -- a listener may (un)register while we call: walk a snapshot, not the live table
  local fns = {}
  for _, fn in pairs(list) do fns[#fns + 1] = fn end
  for _, fn in ipairs(fns) do pcall(fn, event, Copy(type(payload) == "table" and payload or {})) end
end

if type(_G.BiSGamba) == "table" then _G.BiSGamba.Fire = Fire end
