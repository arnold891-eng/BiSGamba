--[[
  BiS Gamba :: Deathroll.lua - one on one: roll down from a number, whoever rolls 1 pays.

  Arn, 16 Oct 2026, looking at FojjiCore's Deathroll on a flight: "maybe we do this for our bis gamba
  so people can deathroll each other" - and "maybe its only challenging people in same raid or party
  or guild". Ideas taken, nothing of theirs copied: the rules are the old ones every server knows.

  THE GAME. The challenger names a player, a start (1000) and a wager in gold. The other side gets a
  window to accept or decline. The challenger rolls first, /roll 1-1000; then the other rolls 1 to
  whatever that came to, and so on down. Whoever rolls a 1 loses and owes the wager.

  WHO. Only someone in your party, raid or guild - by their WHOLE name (Forever's "Frank G" is not
  "Frank"; FojjiCore sent a challenge to "Frank" off "Frank G", 16 Oct). Nothing is heard from anyone
  else, so a stranger can never put a challenge in front of you.

  THE ROLLS ARE REAL /rolls. Each side's own client reads its own roll out of chat and tells the other
  (a guildmate outside the group never sees your roll in chat). When both are in the group, the chat
  line is what counts and the message only fills in what chat did not show.

  THE MONEY goes in the same book as a high/low round: the debts list, "pay" and the trade settle it,
  and a wager over 0 lands on the leaderboard (a round with mode "dr"). A wager of 0 is just for fun.

  THE CONVERSATION (whispers on Gamba's own prefix):
    DRASK  id start wager      a challenge
    DRYES  id / DRNO id why    the answer
    DRROLL id roll max         a roll, from the one who rolled it
    DRBYE  id                  a challenge taken back before it was answered
]]
local G = BiSGamba
local K = G.Kit
local T = G.T

local D = { game = nil, seq = 0 }
G.Deathroll = D

D.START, D.MAX_START, D.MAX_WAGER = 1000, 1000000, 100000
D.ANSWER = 60                     -- seconds a challenge waits for its answer
D.W = 330                         -- 1.43:1, the BiS window shape
D.H = math.floor(D.W / 1.43 + 0.5)

local function db() return K.DB() end

--------------------------------------------------------------------
-- who may play
--------------------------------------------------------------------

--- In the guild? Read off the roster - a guildmate outside the group has no unit to ask.
function D.InGuild(name)
  if not (name and IsInGuild and IsInGuild() and GetNumGuildMembers) then return false end
  for i = 1, (GetNumGuildMembers() or 0) do
    local n = GetGuildRosterInfo(i)
    if n and K.Bare(n) == name then return true end
  end
  return false
end

function D.CanReach(name)
  if not name or name == "" or name == K.MyName() then return false end
  return K.InGroup(name) or D.InGuild(name)
end

--------------------------------------------------------------------
-- the game
--------------------------------------------------------------------

local function Send(...) G.Comm.SendTo(D.game and D.game.foe, ...) end

function D.Active() return D.game ~= nil and D.game.state ~= "DONE" end

--- Challenge `foe` from `start` for `wager` gold. Answers true or nil, why.
function D.Challenge(foe, start, wager)
  if foe then
    local trimmed = tostring(foe):gsub("^%s+", ""):gsub("%s+$", "")
    foe = K.Bare(trimmed)
  end
  start, wager = math.floor(tonumber(start) or 0), math.floor(tonumber(wager) or 0)
  if D.Active() then return nil, "a deathroll is already going" end
  if not foe or foe == "" then return nil, "name somebody to challenge" end
  if foe == K.MyName() then return nil, "you cannot deathroll yourself" end
  if not D.CanReach(foe) then return nil, foe .. " is not in your group or guild (use their whole name)" end
  if start < 2 or start > D.MAX_START then return nil, "start somewhere from 2 to " .. D.MAX_START end
  if wager < 0 or wager > D.MAX_WAGER then return nil, "a wager from 0 to " .. K.Gold(D.MAX_WAGER) end
  local d = db()
  d.drseq = (tonumber(d.drseq) or 0) + 1
  local id = K.MyName() .. ":dr" .. d.drseq
  D.game = { id = id, foe = foe, start = start, wager = wager, max = start, rolls = {},
             mine = true, first = K.MyName(), state = "ASKED", at = K.Now() }
  Send("DRASK", id, start, wager)
  K.Print(("deathroll: challenged %s from %d for %s - waiting for an answer"):format(foe, start,
    wager > 0 and K.Gold(wager) or "fun"))
  local g = D.game
  K.After(D.ANSWER, function()
    if D.game == g and g.state == "ASKED" then
      K.Print(("deathroll: no answer from %s. They may not run BiS Gamba."):format(foe))
      D.game = nil
      D.Refresh()
    end
  end)
  D.Refresh()
  return true
end

function D.Answer(yes)
  local g = D.game
  if not g or g.state ~= "INVITED" then return false end
  if yes then
    Send("DRYES", g.id)
    g.state, g.turn = "PLAY", g.foe              -- the challenger rolls first
    K.Print(("deathroll with %s: they roll first"):format(g.foe))
  else
    Send("DRNO", g.id, "declined")
    D.game = nil
  end
  D.Refresh()
  return true
end

function D.TakeBack()
  local g = D.game
  if not g or g.state ~= "ASKED" then return false end
  Send("DRBYE", g.id)
  D.game = nil
  D.Refresh()
  return true
end

--- Roll, when it is our turn.
function D.Roll()
  local g = D.game
  if not g or g.state ~= "PLAY" or g.turn ~= K.MyName() or g.rolled then return false end
  g.rolled = true                                 -- one press, one roll, until it lands
  RandomRoll(1, g.max)
  return true
end

local function other(g, name) return name == g.foe and K.MyName() or g.foe end

--- A roll that counts. Whoever rolled 1 loses.
function D.Apply(who, roll, max)
  local g = D.game
  if not g or g.state ~= "PLAY" or who ~= g.turn or max ~= g.max then return false end
  if roll < 1 or roll > max then return false end
  g.rolls[#g.rolls + 1] = { who = who, roll = roll, max = max }
  g.rolled = nil
  if roll == 1 then return D.Finish(who) end
  g.max, g.turn = roll, other(g, who)
  if g.turn == K.MyName() and G.Sound then pcall(G.Sound.Play, "you") end
  D.Refresh()
  return true
end

function D.Finish(loser)
  local g = D.game
  local winner = other(g, loser)
  g.state, g.winner, g.loser = "DONE", winner, loser
  if g.wager > 0 then
    G.Ledger.Add(loser, winner, g.wager)
    if G.AddRound then
      G.AddRound(g.id, { at = K.Now(), max = g.start, winner = winner, loser = loser, amount = g.wager,
                         host = g.first, mode = "dr" })
      if G.Rebuild then G.Rebuild() end
    end
  end
  local me = K.MyName()
  if G.Sound then pcall(G.Sound.Play, me == winner and "win" or "lose") end
  K.Print(("deathroll: %s rolled 1 - %s"):format(loser == me and "you" or loser,
    g.wager > 0 and (("%s %s %s"):format(loser == me and "you owe" or (loser .. " owes"),
      winner == me and "you" or winner, K.Gold(g.wager))) or "just for fun"))
  if G.Fire then
    pcall(G.Fire, "BiSGamba_RoundEnded", { id = g.id, winner = winner, loser = loser, amount = g.wager,
      max = g.start, host = g.first, at = K.Now(), mode = "dr" })
  end
  if G.UI and G.UI.Refresh then G.UI:Refresh() end
  D.Refresh()
  return true
end

--------------------------------------------------------------------
-- what we hear
--------------------------------------------------------------------

function D.OnRoll(who, roll, lo, hi)
  local g = D.game
  if not g or g.state ~= "PLAY" or lo ~= 1 or who ~= g.turn then return end
  if D.Apply(who, roll, hi) and who == K.MyName() then
    -- tell the other side what we rolled: outside the group they never see it in chat
    G.Comm.SendTo(g.foe, "DRROLL", g.id, roll, hi)
  end
end

function D.OnComm(msg, sender)
  if not D.CanReach(sender) then return end         -- party, raid or guild; nobody else
  G.Comm.Seen(sender)
  local p = {}
  for s in (msg .. "\t"):gmatch("(.-)\t") do p[#p + 1] = s end
  local op, id = p[1], p[2]
  local g = D.game
  if op == "DRASK" then
    local start, wager = math.floor(tonumber(p[3]) or 0), math.floor(tonumber(p[4]) or -1)
    if start < 2 or start > D.MAX_START or wager < 0 or wager > D.MAX_WAGER or not id then return end
    if D.Active() then G.Comm.SendTo(sender, "DRNO", id, "busy") return end
    D.game = { id = id, foe = sender, start = start, wager = wager, max = start, rolls = {},
               mine = false, first = sender, state = "INVITED", at = K.Now() }
    if G.Sound then pcall(G.Sound.Play, "open") end
    D.Show()
    return
  end
  if not g or g.id ~= id or g.foe ~= sender then return end
  if op == "DRYES" and g.state == "ASKED" then
    g.state, g.turn = "PLAY", K.MyName()
    K.Print(("deathroll: %s accepted - you roll first, 1-%d"):format(sender, g.start))
    D.Show()
  elseif op == "DRNO" and g.state == "ASKED" then
    K.Print(("deathroll: %s %s"):format(sender, p[3] == "busy" and "is in another deathroll" or "declined"))
    D.game = nil
    D.Refresh()
  elseif op == "DRBYE" and g.state == "INVITED" then
    K.Print(("deathroll: %s took the challenge back"):format(sender))
    D.game = nil
    D.Refresh()
  elseif op == "DRROLL" and g.state == "PLAY" then
    -- in the group, chat may already have shown it: then it was applied and this does nothing
    D.Apply(sender, math.floor(tonumber(p[3]) or 0), math.floor(tonumber(p[4]) or 0))
  end
end

--------------------------------------------------------------------
-- the window
--------------------------------------------------------------------

local function Box(f, w, numeric)
  local b = CreateFrame("EditBox", nil, f, "BackdropTemplate")
  b:SetSize(w, 20)
  b:SetAutoFocus(false)
  if numeric then b:SetNumeric(true) end
  b:SetMaxLetters(numeric and 7 or 40)
  b:SetFontObject(GameFontHighlightSmall)
  b:SetTextInsets(6, 6, 0, 0)
  T.skin(b, "line2")
  b:SetBackdropColor(T.rgba("sunken", 1))
  b:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  b:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  return b
end

local function Label(f, text)
  local fs = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  fs:SetText(T.text("muted", text))
  return fs
end

function D.Build()
  if D.frame then return D.frame end
  local f = CreateFrame("Frame", "BiSGambaDeathroll", UIParent, "BackdropTemplate")
  D.frame = f
  f:SetSize(D.W, D.H)
  f:SetFrameStrata("MEDIUM")
  f:SetMovable(true); f:EnableMouse(true); f:SetClampedToScreen(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
  T.skin(f, "line")
  f:SetBackdropColor(T.rgba("bg", 0.97))
  tinsert(UISpecialFrames, "BiSGambaDeathroll")

  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  f.title:SetPoint("TOPLEFT", 12, -10)
  f.title:SetText(T.text("accent", "BiS>") .. T.text("ink", " Deathroll"))
  local close = K.SmallButton(f, "x")
  close:SetPoint("TOPRIGHT", -8, -8)
  close:SetScript("OnClick", function() f:Hide() end)

  -- the challenge form
  f.whoL = Label(f, "player (whole name)")
  f.whoL:SetPoint("TOPLEFT", 14, -40)
  f.who = Box(f, D.W - 28)
  f.who:SetPoint("TOPLEFT", f.whoL, "BOTTOMLEFT", -2, -4)
  f.startL = Label(f, "start at")
  f.startL:SetPoint("TOPLEFT", f.who, "BOTTOMLEFT", 2, -10)
  f.start = Box(f, 120, true)
  f.start:SetPoint("TOPLEFT", f.startL, "BOTTOMLEFT", -2, -4)
  f.betL = Label(f, "wager (gold, 0 = for fun)")
  f.betL:SetPoint("LEFT", f.startL, "LEFT", 150, 0)
  f.bet = Box(f, 120, true)
  f.bet:SetPoint("TOPLEFT", f.betL, "BOTTOMLEFT", -2, -4)

  -- the game, in words
  f.line1 = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  f.line1:SetPoint("TOP", f, "TOP", 0, -48)
  f.line2 = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  f.line2:SetPoint("TOP", f.line1, "BOTTOM", 0, -8)
  f.log = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.log:SetPoint("TOP", f.line2, "BOTTOM", 0, -10)
  f.log:SetWidth(D.W - 28)

  -- the one button that matters, and the one beside it
  f.go = K.SmallButton(f, "challenge", 110)
  f.go:SetSize(110, 22)
  f.go:SetPoint("BOTTOM", f, "BOTTOM", -60, 14)
  f.go:SetScript("OnClick", function() D.Go() end)
  f.alt = K.SmallButton(f, "decline", 110)
  f.alt:SetSize(110, 22)
  f.alt:SetPoint("BOTTOM", f, "BOTTOM", 60, 14)
  f.alt:SetScript("OnClick", function() D.Alt() end)

  f.start:SetText(tostring(D.START))
  f.bet:SetText("0")
  f:Hide()
  return f
end

--- The left button: challenge, accept, roll, or another game - whatever the state asks for.
function D.Go()
  local g, f = D.game, D.frame
  if not g or g.state == "DONE" then
    local foe = (g and g.state == "DONE") and g.foe or f.who:GetText()
    local start = (g and g.state == "DONE") and g.start or f.start:GetText()
    local wager = (g and g.state == "DONE") and g.wager or f.bet:GetText()
    D.game = nil
    local ok, why = D.Challenge(foe, start, wager)
    if not ok then K.Warn("deathroll: " .. why) end
    D.Refresh()
  elseif g.state == "INVITED" then D.Answer(true)
  elseif g.state == "PLAY" then D.Roll()
  end
end

function D.Alt()
  local g = D.game
  if not g then if D.frame then D.frame:Hide() end return end
  if g.state == "INVITED" then D.Answer(false)
  elseif g.state == "ASKED" then D.TakeBack()
  elseif g.state == "DONE" then D.game = nil D.Refresh()
  end
end

local function Form(show)
  local f = D.frame
  for _, r in ipairs({ f.whoL, f.who, f.startL, f.start, f.betL, f.bet }) do
    if show then r:Show() else r:Hide() end
  end
end

function D.Refresh()
  local f = D.frame
  if not f then return end
  local g, me = D.game, K.MyName()
  local function lbl(b, text, off)
    b.text:SetText(text)
    K.SetOff(b, off and true or false)
    b:Show()
  end
  f.line1:SetText("") f.line2:SetText("") f.log:SetText("")
  if not g then
    Form(true)
    lbl(f.go, "challenge")
    lbl(f.alt, "close")
    return
  end
  Form(false)
  local stake = g.wager > 0 and K.Gold(g.wager) or "fun"
  if g.state == "ASKED" then
    f.line1:SetText(T.text("ink", g.foe))
    f.line2:SetText(T.text("muted", ("from %d for %s - waiting for an answer"):format(g.start, stake)))
    lbl(f.go, "challenge", true)
    lbl(f.alt, "take it back")
  elseif g.state == "INVITED" then
    f.line1:SetText(T.text("ink", g.foe) .. T.text("muted", " challenges you"))
    f.line2:SetText(T.text("muted", ("deathroll from %d for %s - they roll first"):format(g.start, stake)))
    lbl(f.go, "accept")
    lbl(f.alt, "decline")
  elseif g.state == "PLAY" then
    local mine = g.turn == me
    f.line1:SetText(mine and T.text("gold", ("your roll: 1 - %d"):format(g.max))
      or T.text("ink", ("%s rolls 1 - %d"):format(g.turn, g.max)))
    f.line2:SetText(T.text("muted", ("against %s, for %s"):format(g.foe, stake)))
    lbl(f.go, "roll", not mine or g.rolled)
    if f.go.hot ~= mine then K.SetHot(f.go, mine) end
    f.alt:Hide()
  else
    local won = g.winner == me
    f.line1:SetText(won and T.text("good", "you win" .. (g.wager > 0 and (" " .. K.Gold(g.wager)) or ""))
      or T.text("warn", "you rolled 1" .. (g.wager > 0 and (" - you owe " .. g.winner .. " " .. K.Gold(g.wager)) or "")))
    f.line2:SetText(T.text("muted", ("against %s, from %d"):format(g.foe, g.start)))
    lbl(f.go, "again")
    if f.go.hot then K.SetHot(f.go, false) end
    lbl(f.alt, "done")
  end
  -- the last few rolls, newest first
  local out = {}
  for i = #g.rolls, math.max(1, #g.rolls - 4), -1 do
    local r = g.rolls[i]
    out[#out + 1] = ("%s %d (1-%d)"):format(r.who == me and "you" or r.who, r.roll, r.max)
  end
  f.log:SetText(T.text("dim", table.concat(out, "   ")))
end

function D.Show(name)
  local f = D.Build()
  if name and name ~= "" and not D.Active() then f.who:SetText(name) end
  if not D.Active() and f.who:GetText() == "" and UnitIsPlayer and UnitIsPlayer("target") then
    local t = K.Bare(UnitName("target"))
    if t and t ~= K.MyName() then f.who:SetText(t) end
  end
  D.Refresh()
  f:Show()
end

function D.Toggle()
  if D.frame and D.frame:IsShown() then D.frame:Hide() else D.Show() end
end

--- /bisgamba dr [name]
function D.Slash(rest)
  D.Show(rest and rest ~= "" and rest or nil)
end
