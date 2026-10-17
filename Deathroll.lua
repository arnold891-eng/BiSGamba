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
-- 1.43:1, the BiS window shape - wide enough for a duel: you, the rolls, them (Arn, 17 Oct: "that looks
-- too like fojji ... lets add 3d models. we are standing on the left them on the right, and rolls in
-- the middle")
D.W = 520
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
  if D.Celebrate then D.Celebrate(winner, loser) end
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
-- the window: a duel
--
-- YOU ON THE LEFT, THEM ON THE RIGHT, THE ROLLS IN THE MIDDLE (Arn, 17 Oct 2026, on the first form:
-- "that looks too like fojji can we add a scrollable thing in ours about people in our party or raid
-- and lets add 3d models"). Before a game the right side is the people in your group, a list you
-- scroll and click; picked, it is them, in 3D, facing you. No number is filled in for you ("no
-- prefilled number"): the start is yours to type, and an empty wager is for fun.
--------------------------------------------------------------------

D.SIDE = 150                      -- each model's column; the middle gets the rest
D.ROWS, D.ROW_H = 9, 22           -- the people list
D.FACE = 0.55                     -- radians each model turns toward the middle

local function Box(f, w, numeric, hint)
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
  -- the hint sits inside, faint, and goes the moment there is anything typed
  if hint then
    b.hint = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    b.hint:SetPoint("LEFT", 6, 0)
    b.hint:SetText(hint)
    b:SetScript("OnTextChanged", function(self)
      local t = self:GetText()
      if t == nil or t == "" then self.hint:Show() else self.hint:Hide() end
    end)
  end
  return b
end

local function Label(f, text)
  local fs = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  fs:SetText(T.text("muted", text))
  return fs
end

local function Model(f)
  local m = CreateFrame("DressUpModel", nil, f)
  m:SetSize(D.SIDE, D.H - 74)
  return m
end

--- Put somebody on a model: the real character when the client will draw them, a wisp otherwise
--- (a guildmate far away, or someone not in the group at all).
local function Wear(m, name, facing)
  if not m then return end
  pcall(m.ClearModel, m)
  local unit = name and (name == K.MyName() and "player" or K.UnitFor(name))
  local ok = false
  if unit and (unit == "player" or (UnitIsVisible and UnitIsVisible(unit))) then
    ok = pcall(m.SetUnit, m, unit)
  end
  if not ok then pcall(m.SetDisplayInfo, m, K.WISP) end
  if m.SetPortraitZoom then pcall(m.SetPortraitZoom, m, 0) end
  pcall(m.SetFacing, m, facing or 0)
  pcall(m.SetAnimation, m, K.ANIM.stand)
  m.who = name
  m:Show()
end

--- Everyone in the party or raid you could challenge, by name, with their class.
function D.People()
  local out, me = {}, K.MyName()
  for _, u in ipairs(K.GroupUnits()) do
    if UnitExists and UnitExists(u) and not (UnitIsUnit and UnitIsUnit(u, "player")) then
      local n = K.Bare(UnitName(u))
      if n and n ~= me then
        local _, class = UnitClass(u)
        local online = not UnitIsConnected or UnitIsConnected(u)
        out[#out + 1] = { name = n, class = class, online = online and true or false }
      end
    end
  end
  table.sort(out, function(a, b)
    if a.online ~= b.online then return a.online end
    return a.name < b.name
  end)
  return out
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
  -- THE TABLE'S OWN HEADER (Arn, 17 Oct: "make the deathroll and gamba window similar style"): the
  -- live BiS> prompt, as on the Gamba table; plain words where the console is not loaded
  if T.Console then
    f.con = T.Console(f.title, { width = 200 })
    f.con:Set("name", "Deathroll", "accent")
    -- the cursor blinks while the window is open, and only then (OnUpdate runs only while shown)
    f:SetScript("OnUpdate", function() if f.con then f.con:Paint() end end)
  else
    f.title:SetText(T.text("accent", "BiS>") .. T.text("ink", " Deathroll"))
  end
  local close = K.SmallButton(f, "x")
  close:SetPoint("TOPRIGHT", -8, -8)
  close:SetScript("OnClick", function() f:Hide() end)

  -- LEFT: you
  f.me = Model(f)
  f.me:SetPoint("TOPLEFT", 10, -34)
  f.meName = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  f.meName:SetPoint("BOTTOM", f.me, "BOTTOM", 0, -16)

  -- RIGHT: them, or the people to pick from
  f.them = Model(f)
  f.them:SetPoint("TOPRIGHT", -10, -34)
  f.themName = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  f.themName:SetPoint("BOTTOM", f.them, "BOTTOM", 0, -16)
  f.change = K.SmallButton(f, "pick someone else", D.SIDE - 20)
  f.change:SetPoint("BOTTOM", f.them, "BOTTOM", 0, -40)
  f.change:SetScript("OnClick", function() D.pick = nil D.Refresh() end)

  local list = CreateFrame("Frame", nil, f)
  list:SetPoint("TOPRIGHT", -10, -34)
  list:SetSize(D.SIDE, D.ROWS * D.ROW_H + 4)
  list:EnableMouseWheel(true)
  list:SetScript("OnMouseWheel", function(_, delta)
    D.scroll = math.max(0, math.min((D.scroll or 0) - delta, math.max(0, #D.People() - D.ROWS)))
    D.Refresh()
  end)
  f.listHead = Label(f, "your party / raid")
  f.listHead:SetPoint("BOTTOMLEFT", list, "TOPLEFT", 2, 2)
  f.list, f.rows = list, {}
  for i = 1, D.ROWS do
    local r = CreateFrame("Button", nil, list)
    r:SetSize(D.SIDE, D.ROW_H - 2)
    r:SetPoint("TOPLEFT", 0, -(i - 1) * D.ROW_H)
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.bg:SetColorTexture(T.rgba("sunken", 1))
    r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.text:SetPoint("LEFT", 8, 0)
    r.hl = r:CreateTexture(nil, "HIGHLIGHT")
    r.hl:SetAllPoints()
    r.hl:SetColorTexture(1, 1, 1, 0.08)
    r:SetScript("OnClick", function(self)
      if self.person and self.person.online then D.pick = self.person.name D.Refresh() end
    end)
    f.rows[i] = r
  end
  -- a guildmate outside the group: by whole name
  f.who = Box(f, D.SIDE, false, "or a guildmate's whole name")
  f.who:SetPoint("TOP", list, "BOTTOM", 0, -6)
  f.who:SetScript("OnEnterPressed", function(self)
    self:ClearFocus()
    local n = self:GetText()
    if n and n:match("%S") then D.pick = (n:gsub("^%s+", ""):gsub("%s+$", "")) D.Refresh() end
  end)

  -- MIDDLE: the numbers before, the rolls during
  local mid = CreateFrame("Frame", nil, f)
  mid:SetPoint("TOPLEFT", f.me, "TOPRIGHT", 10, 0)
  mid:SetPoint("BOTTOMRIGHT", f.them, "BOTTOMLEFT", -10, 0)
  f.mid = mid
  local mw = D.W - 2 * D.SIDE - 40
  -- ONE NUMBER (Arn, 17 Oct: "the start at is not needed it almost always start at the gold
  -- wagered"): the gold you bet is where the rolls start. "for fun" keeps the number as the start
  -- and bets nothing.
  f.betL = Label(mid, "gold - the rolls start here")
  f.betL:SetPoint("TOP", mid, "TOP", 0, -26)
  f.bet = Box(mid, mw - 40, true, "500?")
  f.bet:SetPoint("TOP", f.betL, "BOTTOM", 0, -4)
  f.bet:SetText("")                                   -- empty: no number filled in for you
  f.fun = K.SmallButton(mid, "for fun - no gold", mw - 40)
  f.fun:SetPoint("TOP", f.bet, "BOTTOM", 0, -6)
  f.fun.tip = "Roll down from that number, but nobody owes anybody"
  f.fun:SetScript("OnClick", function() D.fun = not D.fun K.SetHot(f.fun, D.fun) D.Refresh() end)

  f.line1 = mid:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  f.line1:SetPoint("TOP", mid, "TOP", 0, -8)
  f.line1:SetWidth(mw)
  f.line2 = mid:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.line2:SetPoint("TOP", f.line1, "BOTTOM", 0, -6)
  f.line2:SetWidth(mw)
  f.log = mid:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  f.log:SetPoint("TOP", f.line2, "BOTTOM", 0, -12)
  f.log:SetWidth(mw)
  f.log:SetJustifyH("CENTER")

  f.go = K.SmallButton(mid, "challenge", mw - 20)
  f.go:SetSize(mw - 20, 24)
  f.go:SetPoint("BOTTOM", mid, "BOTTOM", 0, 30)
  f.go:SetScript("OnClick", function() D.Go() end)
  f.alt = K.SmallButton(mid, "close", mw - 20)
  f.alt:SetSize(mw - 20, 20)
  f.alt:SetPoint("TOP", f.go, "BOTTOM", 0, -4)
  f.alt:SetScript("OnClick", function() D.Alt() end)

  f:Hide()
  return f
end

--- The left button: challenge, accept, roll, or another game - whatever the state asks for.
function D.Go()
  local g, f = D.game, D.frame
  if not g or g.state == "DONE" then
    local again = g and g.state == "DONE"
    local foe = again and g.foe or D.pick
    local start, wager
    if again then
      start, wager = g.start, g.wager
    else
      local gold = tonumber(f.bet:GetText() or "")
      if not gold or gold < 2 then K.Warn("deathroll: type how much gold - the rolls start there") return end
      start, wager = gold, D.fun and 0 or gold
    end
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
  elseif g.state == "DONE" then D.game = nil D.pick = nil D.Refresh()
  end
end

local function ClassColour(class, text)
  local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
  if c and c.colorStr then return "|c" .. c.colorStr .. text .. "|r" end
  return T.text("ink", text)
end

--- Who is on the right: the opponent of a game, else the one picked, else nobody (the list).
local function Opponent()
  local g = D.game
  if g then return g.foe end
  return D.pick
end

function D.Refresh()
  local f = D.frame
  if not f then return end
  local g, me = D.game, K.MyName()

  -- you, always
  if f.me.who ~= me then Wear(f.me, me, D.FACE) end
  f.meName:SetText(T.text("gold", me or "you"))

  -- them, or the list
  local foe = Opponent()
  if foe then
    f.list:Hide(); f.listHead:Hide(); f.who:Hide()
    if f.them.who ~= foe then Wear(f.them, foe, -D.FACE) end
    f.themName:SetText(T.text("ink", foe))
    if g then f.change:Hide() else f.change:Show() end
  else
    f.them:Hide(); f.themName:SetText(""); f.change:Hide()
    f.list:Show(); f.listHead:Show(); f.who:Show()
    local people = D.People()
    D.scroll = math.max(0, math.min(D.scroll or 0, math.max(0, #people - D.ROWS)))
    for i, r in ipairs(f.rows) do
      local p = people[i + D.scroll]
      r.person = p
      if p then
        r.text:SetText(p.online and ClassColour(p.class, p.name) or T.text("dim", p.name .. " (offline)"))
        r:Show()
      else
        r:Hide()
      end
    end
    if #people == 0 then
      f.rows[1].person = nil
      f.rows[1].text:SetText(T.text("muted", "nobody in your group"))
      f.rows[1]:Show()
    end
  end

  -- the middle
  local function lbl(b, text, off)
    b.text:SetText(text)
    K.SetOff(b, off and true or false)
    b:Show()
  end
  local setup = not g
  for _, r in ipairs({ f.betL, f.bet, f.fun }) do if setup then r:Show() else r:Hide() end end
  f.line1:SetText("") f.line2:SetText("") f.log:SetText("")
  if not g then
    f.line1:SetText(T.text("muted", foe and "how much?" or "pick someone"))
    lbl(f.go, "challenge", not foe)
    lbl(f.alt, "close")
    return
  end
  local stake = g.wager > 0 and K.Gold(g.wager) or "fun"
  if g.state == "ASKED" then
    f.line1:SetText(T.text("muted", "waiting for an answer"))
    f.line2:SetText(T.text("muted", ("from %d for %s"):format(g.start, stake)))
    lbl(f.go, "challenge", true)
    lbl(f.alt, "take it back")
  elseif g.state == "INVITED" then
    f.line1:SetText(T.text("ink", "challenged!"))
    f.line2:SetText(T.text("muted", ("from %d for %s"):format(g.start, stake)))
    f.log:SetText(T.text("muted", "they roll first"))
    lbl(f.go, "accept")
    lbl(f.alt, "decline")
  elseif g.state == "PLAY" then
    local mine = g.turn == me
    f.line1:SetText(mine and T.text("gold", ("your roll: 1 - %d"):format(g.max))
      or T.text("ink", ("%s: 1 - %d"):format(g.turn, g.max)))
    f.line2:SetText(T.text("muted", ("for %s"):format(stake)))
    -- THE BUTTON SAYS THE ROLL (Arn, 17 Oct: "like roll /500 and if the other person got 450 they get
    -- a /roll 450 button"): the exact range, one press, on your turn; greyed on theirs
    lbl(f.go, mine and ("/roll " .. g.max) or "their roll", not mine or g.rolled)
    if f.go.hot ~= mine then K.SetHot(f.go, mine) end
    f.alt:Hide()
  else
    local won = g.winner == me
    -- two short lines: the middle column is narrow, and a sentence cut in half reads as nothing
    f.line1:SetText(won and T.text("good", "you win") or T.text("warn", "you rolled 1"))
    f.line2:SetText(g.wager == 0 and T.text("muted", "just for fun")
      or won and T.text("good", ("%s owes you %s"):format(g.loser, K.Gold(g.wager)))
      or T.text("warn", ("you owe %s %s"):format(g.winner, K.Gold(g.wager))))
    lbl(f.go, "again")
    if f.go.hot then K.SetHot(f.go, false) end
    lbl(f.alt, "done")
  end
  -- the rolls, down the middle, newest at the top: yours gold, theirs white, the 1 red
  local out = {}
  for i = #g.rolls, math.max(1, #g.rolls - 7), -1 do
    local r = g.rolls[i]
    local word = ("%s %d"):format(r.who == me and "you" or r.who, r.roll)
    out[#out + 1] = r.roll == 1 and T.text("warn", word) or (r.who == me and T.text("gold", word) or T.text("ink", word))
  end
  f.log:SetText(table.concat(out, "\n"))
end

--- The end: the winner cheers, the loser cries - the table's own reactions.
function D.Celebrate(winner, loser)
  local f = D.frame
  if not f then return end
  local me = K.MyName()
  local function act(m, who)
    if m and m:IsShown() then pcall(m.SetAnimation, m, who == winner and K.ANIM.cheer or K.ANIM.cry) end
  end
  act(f.me, me)
  act(f.them, me == winner and loser or winner)
end

function D.Show(name)
  local f = D.Build()
  if name and name ~= "" and not D.Active() then D.pick = name f.who:SetText(name) end
  if not D.Active() and not D.pick and UnitIsPlayer and UnitIsPlayer("target") then
    local t = K.Bare(UnitName("target"))
    if t and t ~= K.MyName() and K.InGroup(t) then D.pick = t end
  end
  D.Refresh()
  D.Place()
  f:Show()
  if f.Raise then f:Raise() end
end

--- IN FRONT, AND BESIDE THE TABLE, NOT ON IT (Arn's screenshot, 17 Oct 2026: the deathroll window
--- opened under the Gamba table, its list covered). The family rule: a window never opens on top of
--- another. Left of the table when there is room, else right of it, else where it was.
function D.Place()
  local f, t = D.frame, _G.BiSGambaFrame
  if f.SetToplevel then f:SetToplevel(true) end
  if not (t and t:IsShown() and t.GetLeft and t:GetLeft() and t.GetRight and t:GetRight()) then return end
  local screen = UIParent.GetWidth and UIParent:GetWidth() or 1920
  local left, right = t:GetLeft(), t:GetRight()
  f:ClearAllPoints()
  if left - D.W - 8 >= 0 then
    f:SetPoint("TOPRIGHT", t, "TOPLEFT", -8, 0)
  elseif right + 8 + D.W <= screen then
    f:SetPoint("TOPLEFT", t, "TOPRIGHT", 8, 0)
  else
    f:SetPoint("TOP", t, "BOTTOM", 0, -8)
  end
end

function D.Toggle()
  if D.frame and D.frame:IsShown() then D.frame:Hide() else D.Show() end
end

--- /bisgamba dr [name]
function D.Slash(rest)
  D.Show(rest and rest ~= "" and rest or nil)
end
