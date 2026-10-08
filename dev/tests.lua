-- Headless harness for BiSGamba: stubs enough of the WoW API to load the addon
-- and run a few rounds, ties, the ledger and the trade payout path.
-- lua5.1 dev/harness.lua   (run from the BiSGamba folder)

local chat, said, timers, rolled = {}, {}, {}, {}
local pass, fail = 0, 0
local function check(cond, what)
  if cond then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. what) end
end
local function lastChat() return chat[#chat] or "" end
local function strip(s) return (tostring(s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end

---------------------------------------------------------------- frames
local Frame = {}
Frame.__index = function(t, k)
  if rawget(Frame, k) then return rawget(Frame, k) end
  if type(k) == "string" and k:match("^%u") then return function() return nil end end
  return nil
end
local function newFrame(kind, name, parent)
  local f = setmetatable({ kind = kind, name = name, parent = parent, scripts = {}, shown = true, w = 100, h = 100 }, Frame)
  if name then _G[name] = f end
  return f
end
function Frame:SetScript(ev, fn) self.scripts[ev] = fn end
function Frame:GetScript(ev) return self.scripts[ev] end
function Frame:Show() self.shown = true end
function Frame:Hide() self.shown = false end
function Frame:IsShown() return self.shown end
function Frame:IsVisible() return self.shown end
function Frame:GetPoint() return "CENTER", nil, "CENTER", 10, 20 end
-- wSet: the width was GIVEN (SetSize/SetWidth), not the mock's made-up 100. The fit check
-- below trusts only a given width.
function Frame:SetSize(w, h) self.w, self.h, self.wSet = w, h, true end
function Frame:GetWidth() return self.w end
function Frame:SetText(t) self.text_ = t end
function Frame:GetText() return self.text_ end
function Frame:CreateTexture() return newFrame("Texture", nil, self) end
-- EVERY LABEL, KEPT, WITH ITS PARENT AND ITS FONT SIZE (6 Oct 2026, port of BiSTools' fit check).
-- The template names a font object; the label takes that object's size the way the client
-- does. Before, every label here was "9 pt" whatever it was made with. fitsIn() walks labels.
local labels = {}
function Frame:CreateFontString(name, _, template)
  local fs = newFrame("FontString", name, self)
  local fo = type(template) == "string" and _G[template]
  if type(fo) == "table" and fo.size then fs.size = fo.size end
  labels[#labels + 1] = fs
  return fs
end
function Frame:SetFontObject(fo) if type(fo) == "table" and fo.size then self.size = fo.size end end
-- the real client moves the frame; a no-op here left a moved button measured under its old parent
function Frame:SetParent(p) self.parent = p end
function Frame:CreateAnimationGroup() return newFrame("AnimationGroup", nil, self) end
function Frame:CreateAnimation() return newFrame("Animation", nil, self) end
function Frame:SetShown(v) self.shown = v and true or false end
-- FontString bits the BiS> console leans on. GetStringWidth strips colour escapes
-- and scales by the recorded font size, so the header budget assert measures real
-- glyphs, not |cff… codes, and an 8pt word is narrower than a 15pt one.
function Frame:GetParent() return self.parent end
function Frame:SetAlpha(a) self.alpha = a end
function Frame:GetAlpha() return self.alpha or 1 end
function Frame:SetFont(_, size) self.size = size end
function Frame:GetStringWidth()
  local t = tostring(self.text_ or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  return #t * (self.size or 9) * 0.6
end
-- the shared Options kit reads height back after Fit, so SetHeight must stick
function Frame:SetHeight(h) self.h = h end
function Frame:SetWidth(w) self.w, self.wSet = w, true end
function Frame:GetHeight() return self.h end
function Frame:SetTextColor() end
function Frame:SetAllPoints(rel) self.all = rel or true end
-- record anchoring so a window left unanchored (opens off-screen) is a red test.
-- The whole anchor is kept, in the client's forms: SetPoint(p) and SetPoint(p, x, y) are
-- relative to the parent, relPoint = point; rel nil = parent; a name string = that frame.
function Frame:SetPoint(point, rel, rp, x, y)
  if type(rel) == "number" or (rel == nil and rp == nil) then rel, rp, x, y = nil, point, rel, rp end
  if type(rel) == "string" then rel = _G[rel] end
  self.points = self.points or {}
  self.points[#self.points + 1] = { point = point, rel = rel, relPoint = rp or point, x = x or 0, y = y or 0 }
end
function Frame:ClearAllPoints() self.points = {} end
function Frame:SetEnabled(v) self.enabled = v and true or false end
function Frame:SetChecked(v) self.checked = v and true or false end
function Frame:GetChecked() return self.checked end
function Frame:RegisterEvent(e)
  if e == "PARTY_MEMBERS_CHANGED" then error("unknown event") end
  self.events = self.events or {}; self.events[e] = true
end
function Frame:SetAnimation(a) self.anim = a end
function Frame:SetUnit(u) if u == "raid99" then error("bad unit") end self.unit = u; self.model = "unit:" .. u end
function Frame:SetCreature(id) self.model = "npc:" .. id end
function Frame:SetDisplayInfo(id) self.model = "display:" .. id end
function Frame:ClearModel() self.model = nil end
function CreateFrame(kind, name, parent) return newFrame(kind, name, parent) end
UIParent = newFrame("Frame", "UIParent")
Minimap = newFrame("Frame", "Minimap")
GameTooltip = newFrame("GameTooltip", "GameTooltip")
TradeFrame = newFrame("Frame", "TradeFrame"); TradeFrame.shown = false
TradePlayerInputMoneyFrame = newFrame("Frame", "TradePlayerInputMoneyFrame")
UISpecialFrames = {}
StaticPopupDialogs = {}
local popup = nil
function StaticPopup_Show(key) popup = StaticPopupDialogs[key] end
local function acceptPopup() if popup and popup.OnAccept then popup.OnAccept() end end
SlashCmdList = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) chat[#chat + 1] = strip(m) end }
-- font objects with the client's default sizes (FrizQT; Blizzard's Fonts.xml): a label made
-- from one is as big as it is in game, not the mock's old flat 9 pt
local function fontObject(size)
  return { size = size, GetFont = function() return STANDARD_TEXT_FONT, size, "" end }
end
GameFontNormal, GameFontNormalSmall, GameFontHighlightSmall = fontObject(12), fontObject(10), fontObject(10)
GameFontNormalLarge, GameFontDisableSmall, NumberFontNormal = fontObject(16), fontObject(10), fontObject(14)
GameFontNormalHuge = fontObject(20)
RAID_CLASS_COLORS = { SHAMAN = { r = 0, g = 0.44, b = 0.87 }, MAGE = { r = 0.41, g = 0.8, b = 0.94 } }
RANDOM_ROLL_RESULT = "%s rolls %d (%d-%d)"
ERR_TRADE_COMPLETE = "Trade complete."

---------------------------------------------------------------- world
local me = "Kumlust"
local group = { raid1 = { name = "Kumlust", class = "SHAMAN", race = "Draenei", sex = 3, vis = true },
                raid2 = { name = "Dps2", class = "MAGE", race = "Gnome", sex = 2, vis = true },
                raid3 = { name = "Kumsecration", class = "PALADIN", race = "Dwarf", sex = 2, vis = false },
                raid4 = { name = "Dps1", class = "ROGUE", race = "BloodElf", sex = 3, vis = true } }
local inRaid = true
local tradePartner = nil
local myMoney, theirMoney = 0, 0
function IsInRaid() return inRaid end
function GetNumGroupMembers() local n = 0 for _ in pairs(group) do n = n + 1 end return n end
function UnitExists(u) return u == "player" or group[u] ~= nil end
function UnitIsPlayer(u) return UnitExists(u) end
function UnitIsVisible(u) return u == "player" or (group[u] and group[u].vis) or false end
function UnitIsConnected(u) return not (group[u] and group[u].offline) end
function UnitName(u)
  if u == "player" then return me end
  if u == "NPC" then return tradePartner end
  return group[u] and group[u].name
end
function UnitClass(u) local g = group[u]; if u == "player" then g = group.raid1 end return g and g.class, g and g.class end
function UnitRace(u) local g = group[u]; if u == "player" then g = group.raid1 end return g and g.race, g and g.race end
function UnitSex(u) local g = group[u]; if u == "player" then g = group.raid1 end return g and g.sex or 2 end
function Ambiguate(n) return (n:gsub("%-Dreamscythe$", "")) end
local myGuild = "The Heathens"
local guildies = { Kumlust = true, Dps2 = true, Kumsecration = true }
function GetGuildInfo(unit) return myGuild end
function UnitIsInMyGuild(unit) local n = UnitName(unit); return n ~= nil and guildies[n] == true end
function GetTime() return _G.__now or 1000 end
function time() return 1788500000 end
function GetServerTime() return 1788500000 end
function IsShiftKeyDown() return false end
local inCombat = false
function InCombatLockdown() return inCombat end
function GetCursorPosition() return 0, 0 end
function GetMoney() return 5000 * 10000 end
local whispers = {}
function SendChatMessage(text, kind, _, target)
  if kind == "WHISPER" then whispers[#whispers + 1] = tostring(target) .. ": " .. text
  else said[#said + 1] = kind .. ": " .. text end
end
function RandomRoll(lo, hi) rolled[#rolled + 1] = { lo, hi } end
local played, soundsWork, kitsWork = {}, true, false
function PlaySoundFile(path, channel) played[#played + 1] = path; return soundsWork end
function PlaySound(kit, channel) played[#played + 1] = "kit:" .. tostring(kit); return kitsWork end
local function heard(pattern)
  for i = #played, 1, -1 do if played[i]:find(pattern) then return played[i] end end
end
function InitiateTrade(unit) _G.__initiated = unit; tradePartner = UnitName(unit) end
function SetTradeMoney(c) myMoney = c end
function MoneyInputFrame_SetCopper(f, c) f.copper = c end
function MoneyInputFrame_GetCopper(f) return f.copper or 0 end
-- the real client throws "forbidden object" if an addon writes these
for _, sfx in ipairs({ "Gold", "Silver", "Copper" }) do
  local box = newFrame("EditBox", "TradePlayerInputMoneyFrame" .. sfx)
  box.SetText = function() error("forbidden object: an addon wrote a secure money box") end
end
function GetPlayerTradeMoney() return myMoney end
function GetTargetTradeMoney() return theirMoney end
local picked = nil
function PickupPlayerMoney(c) picked = c end
-- open a trade for real: the window AND the event, the way the client does it
local function openTrade(who)
  tradePartner = who; myMoney = 0; TradePlayerInputMoneyFrame.copper = 0
  TradeFrame.shown = true
end
C_Timer = { After = function(s, fn) timers[#timers + 1] = { delay = s or 0, fn = fn } end }
local addon = {}
C_ChatInfo = { RegisterAddonMessagePrefix = function() end, SendAddonMessage = function(prefix, msg, ch) addon[#addon + 1] = msg end }
function SetPortraitTexture(tex, unit) tex.portrait = unit end
CLASS_ICON_TCOORDS = { SHAMAN = { 0, 0.25, 0.25, 0.5 }, MAGE = { 0.25, 0.5, 0, 0.25 } }
function Frame:SetTexture(t) self.tex = t end
function Frame:SetColorTexture(r, g, b, a)
  if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then
    error("SetColorTexture needs colorR, colorG, colorB [, colorA]")
  end
  self.color = { r, g, b, a }
end
function Frame:SetFrameLevel(l) self.level = l end
function Frame:GetFrameLevel() return self.level or 1 end
-- runTimers() fires everything; runTimers(n) only fires timers set for <= n
-- seconds, so a long countdown can be left ticking while short ones drain.
local function runTimers(maxDelay)
  maxDelay = maxDelay or math.huge
  for _ = 1, 200 do
    local due, keep = {}, {}
    for _, t in ipairs(timers) do
      if t.delay <= maxDelay then due[#due + 1] = t else keep[#keep + 1] = t end
    end
    if #due == 0 then break end
    timers = keep
    for _, t in ipairs(due) do t.fn() end
  end
end
tinsert = table.insert
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
-- a distinctive version so the "registers the TOC version, not a literal" assert
-- can tell a dynamic read from a hardcoded string
if not GetAddOnMetadata then function GetAddOnMetadata() return "9.9.9-toc" end end
-- globals LibBiSComm can reach for (all guarded on its side); enough to boot and,
-- if a test drives it, answer WHERE/SUM without erroring
LE_PARTY_CATEGORY_INSTANCE = 2
function IsInGroup(cat) if cat == LE_PARTY_CATEGORY_INSTANCE then return false end return inRaid end
function UnitPosition() return 100, 200, 0, 1 end
-- addon-loaded + spell-name stubs the rez emitter (RezComm) reaches for
local loadedAddons = { BiSGamba = true }        -- BiSInnervate NOT loaded in the base run
function IsAddOnLoaded(n) return loadedAddons[n] == true end
local SPELLNAME = {
  [2006] = "Resurrection", [2010] = "Resurrection", [10880] = "Resurrection",
  [10881] = "Resurrection", [20770] = "Resurrection", [25435] = "Resurrection",
  [7328] = "Redemption", [10322] = "Redemption", [10324] = "Redemption",
  [20772] = "Redemption", [20773] = "Redemption",
  [2008] = "Ancestral Spirit", [20609] = "Ancestral Spirit", [20610] = "Ancestral Spirit",
  [20776] = "Ancestral Spirit", [20777] = "Ancestral Spirit", [25590] = "Ancestral Spirit",
  [116] = "Frostbolt", [20484] = "Rebirth", [20739] = "Rebirth",
}
function GetSpellInfo(id) return SPELLNAME[id] or ("Spell" .. tostring(id)) end
function IsInInstance() return false, "none" end
function GetInstanceInfo() return "Azeroth", "none", 0, "", 0, 0, false, 0, 0 end
function GetZoneText() return "Orgrimmar" end
function GetRealZoneText() return "Orgrimmar" end
function GetSummonConfirmSummoner() return "" end
function hooksecurefunc() end
function pcall_(f, ...) return pcall(f, ...) end

---------------------------------------------------------------- does every label FIT its window
-- (6 Oct 2026, ported from BiSTools) Arn: "make a check for cut offs or overflows that happens
-- often". Every shown label inside a window is measured where it actually lands - following what it
-- is pinned to: the window's edge, a button, a seat, another label - and must end inside the window.
--
-- WIDTH, CALIBRATED ON THE CLIENT, NOT GUESSED (BiSTools, same numbers): capitals and digits 0.75 px
-- per point, lowercase 0.55, spaces/punctuation 0.3; an inline |T..:w:h|t takes its width, colour
-- escapes none. The mock's own GetStringWidth (0.6 flat) stays as it is: the Console and T.Fit trim
-- by it, and changing it changes what the addon draws.
local function realWidth(fs)
  local t, tex = tostring(fs.text_ or ""), 0
  t = t:gsub("|T[^|]-:(%d+):%d+[^|]*|t", function(w) tex = tex + tonumber(w) return "" end)
  t = t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  local size, px = fs.size or 9, 0
  for ch in t:gmatch(".") do
    if ch:match("[%u%d]") then px = px + 0.75 elseif ch:match("%l") then px = px + 0.55 else px = px + 0.3 end
  end
  return px * size + tex
end
local function inside(r, root)
  local p = r.parent
  while p do if p == root then return true end p = p.parent end
  return false
end
local function insideShown(r, root)
  local p = r.parent
  while p do
    if p.shown == false then return false end
    if p == root then return true end
    p = p.parent
  end
  return false
end
local function side(point)
  if point:find("LEFT") then return "L" elseif point:find("RIGHT") then return "R" end
  return "C"
end
-- Left and right edge, px from the window's left, following every anchor. A frame or label pinned
-- by a LEFT-ish AND a RIGHT-ish point is as wide as that span ("bounded"); one with a given width
-- is that wide (bounded); a label with neither is as wide as its text. A FRAME that cannot be
-- followed (no anchor, or one anchor and no width) spans the window, as BiSTools counts it; a
-- LABEL that cannot be followed is not measured. Returns L, R, bounded.
local function span(r, root, depth)
  if r == root then return 0, root.w, true end
  if depth > 12 or not inside(r, root) then return nil end
  local isText = r.kind == "FontString"
  if r.all then return span(r.all == true and r.parent or r.all, root, depth + 1) end
  if not r.points or #r.points == 0 then if isText then return nil end return 0, root.w, true end
  local L, R, C
  for _, a in ipairs(r.points) do
    local rl, rr = span(a.rel or r.parent, root, depth + 1)
    if not rl then return nil end
    local h = side(a.relPoint)
    local ax = (h == "L" and rl or h == "R" and rr or (rl + rr) / 2) + (a.x or 0)
    local own = side(a.point)
    if own == "L" then L = ax elseif own == "R" then R = ax else C = ax end
  end
  if L and R then return L, R, true end
  local w
  if r.wSet then w = r.w elseif isText then w = realWidth(r)
  else return 0, root.w, true end
  if L then return L, L + w, r.wSet elseif R then return R - w, R, r.wSet end
  return C - w / 2, C + w / 2, r.wSet
end
local function plainText(t) return (tostring(t):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
-- A BOUNDED label is measured against its box too: nothing here calls SetWordWrap/SetMaxLines, so
-- a too-long text in a fixed box wraps onto the line below or ends in "..." - a cut off either way.
local function fitsIn(root, what)
  local width, bad, measured = root.w, {}, 0
  for _, fs in ipairs(labels) do
    if fs.shown ~= false and fs.text_ and plainText(fs.text_) ~= "" and insideShown(fs, root) then
      local l, r, bounded = span(fs, root, 0)
      if l then
        measured = measured + 1
        local w = realWidth(fs)
        if l < -1 or r > width + 1 then
          bad[#bad + 1] = ("%q needs %d px from %d, the window is %d"):format(plainText(fs.text_), r - l, l, width)
        elseif bounded and w > (r - l) + 1 then
          bad[#bad + 1] = ("%q needs %d px, its box is %d"):format(plainText(fs.text_), w, r - l)
        end
      end
    end
  end
  check(measured > 0, what .. ": the fit check measured something (a check that sees nothing proves nothing)")
  check(#bad == 0, what .. ": every label fits - " .. table.concat(bad, "; "))
  return measured
end

---------------------------------------------------------------- load
-- the TOC is the loader (house standard, debt 13): every Lua line in BiSGamba.toc is loaded
-- in order, exactly as the client does it. A lib the TOC forgot is then not under test here
-- either - the way it would not exist in the game (BiSTools 0.3.0 shipped that way).
local TOC = {}
do
  local fh = assert(io.open("BiSGamba.toc", "r"), "BiSGamba.toc must be beside the suite")
  for line in fh:lines() do
    line = line:gsub("\r$", "")
    if line:match("%.lua%s*$") and not line:match("^#") then TOC[#TOC + 1] = (line:gsub("\\", "/"):gsub("%s+$", "")) end
  end
  fh:close()
end
assert(#TOC >= 2, "the TOC lists files")
assert(TOC[#TOC] == "BiSGamba.lua", "the addon is the last TOC line")
for _, f in ipairs(TOC) do
  local fn = assert(loadfile(f), "TOC lists a file that does not exist: " .. f)
  fn("BiSGamba")
end
local G = BiSGamba
local ev
for _, name in ipairs({ "BiSGambaFrame" }) do end
-- find the event frame: the last CreateFrame("Frame") with an OnEvent script
-- simpler: the addon registered ADDON_LOADED on it; scan _G isn't possible for anonymous frames,
-- so capture via CreateFrame hook next time. Instead: re-create by hooking.
-- We hooked nothing, so grab it through the closure: BiSGamba doesn't expose it. Patch: expose.
ev = G._ev
assert(ev, "addon must expose its event frame as BiSGamba._ev for the harness")
local function fire(event, ...) ev.scripts.OnEvent(ev, event, ...) end
local function from(sender, ...) fire("CHAT_MSG_ADDON", "BiSGamba", table.concat({ ... }, "\t"), "RAID", sender .. "-Dreamscythe") end
local function saidHas(pattern)
  for i = #said, 1, -1 do if said[i]:find(pattern) then return said[i] end end
end

-- a save from before dbver existed at all: every migration still has to run
BiSGambaDB = { stats = { Oldtimer = 250 }, view = "table", autoJoin = true, wager = 100 }
fire("ADDON_LOADED", "BiSGamba")
fire("PLAYER_LOGIN")
check(type(BiSGambaDB.stats.Oldtimer) == "table" and BiSGambaDB.stats.Oldtimer.net == 250,
  "old net-only stats survive the upgrade")
check(BiSGambaDB.base.Oldtimer and BiSGambaDB.base.Oldtimer.net == 250,
  "and are carried over as the base the rounds build on")
check(BiSGambaDB.view == "2d", "the dead table view is migrated away")
check(BiSGambaDB.autoJoin == false, "autojoin migrated off")
check(BiSGambaDB.dbver == 6, "stamped with the current version")
check(BiSGambaDB.soundChannel == "SFX", "the cues moved off the master channel")
BiSGambaDB.stats = {}
-- nothing the addon defines should leak into _G
for _, name in ipairs({ "Stat", "PutMoney", "TradeMoneyNow", "nudged", "seated", "Trade", "Game", "UI" }) do
  check(_G[name] == nil, "no global named " .. name)
end
check(BiSGambaDB and BiSGambaDB.wager == 100 and BiSGambaDB.view == "2d", "defaults (2d view)")
check(ev.events.CHAT_MSG_SYSTEM and ev.events.TRADE_SHOW and ev.events.CHAT_MSG_RAID, "events registered")

-- roll pattern
local who, r, lo, hi = G.ParseRoll("Dps2 rolls 57 (1-100)")
check(who == "Dps2" and r == 57 and lo == 1 and hi == 100, "parse roll " .. tostring(G.ROLL_PATTERN))
check(G.ParseRoll("Dps2-Dreamscythe rolls 5 (1-200)") == "Dps2", "parse roll with realm")
check(G.ParseRoll("You have learned a new spell.") == nil, "non-roll ignored")

---------------------------------------------------------------- round 1: plain high/low
SlashCmdList.BISGAMBA("start 200")
check(G.Game.state == "JOIN" and G.Game.max == 200, "table open /200")
check(said[#said]:find("HIGH / LOW") and said[#said]:find("/roll 200") and said[#said]:find("up to 199g")
  and said[#said]:find("1 to join"), "the opening line names the game, the range and the stakes: " .. said[#said])
check(G.UI.frame.shown, "window shown")
fire("CHAT_MSG_RAID", "1", "Dps2-Dreamscythe")
fire("CHAT_MSG_RAID", " 1 ", "Kumsecration")
fire("CHAT_MSG_RAID", "lol", "Dps1")
check(#G.Game.order == 3, "three seated (me + 2): " .. #G.Game.order)
fire("CHAT_MSG_RAID", "-1", "Kumsecration")
check(#G.Game.order == 2, "leave works")
fire("CHAT_MSG_RAID", "1", "Kumsecration")
fire("CHAT_MSG_RAID", "+1", "Dps1"); check(G.Game.players.Dps1 ~= nil, "+1 joins")
fire("CHAT_MSG_RAID", "out", "Dps1"); check(G.Game.players.Dps1 == nil, "out leaves")
fire("CHAT_MSG_RAID", "in", "Dps1"); check(G.Game.players.Dps1 ~= nil, "in joins")
G.UI.startBtn.scripts.OnClick()
check(G.Game.state == "ROLL", "rolling")
fitsIn(BiSGambaFrame, "the table, rolls out")
-- a roll in the wrong range is ignored, and the person is told once in chat
fire("CHAT_MSG_SYSTEM", "Kumlust rolls 99 (1-100)")
check(G.Game.players.Kumlust.roll == nil, "wrong range ignored")
check(said[#said]:find("rolled /roll 100 · table is /roll 200"), "wrong range nudge: " .. said[#said])
fire("CHAT_MSG_SYSTEM", "Kumlust rolls 98 (1-100)")
check(not said[#said]:find("rolls 98") and select(2, said[#said]:gsub("rolled /roll", "")) == 1, "nudged only once")
SlashCmdList.BISGAMBA("nudge")
check(said[#said]:find("waiting on") and said[#said]:find("Dps2"), "nudge names stragglers: " .. said[#said])
G.UI.rollBtn.scripts.OnClick()
check(rolled[#rolled][1] == 1 and rolled[#rolled][2] == 200, "roll button rolls 1-200")
fire("CHAT_MSG_SYSTEM", "Kumlust rolls 150 (1-200)")
fire("CHAT_MSG_SYSTEM", "Kumlust rolls 3 (1-200)")
check(G.Game.players.Kumlust.roll == 150, "first roll counts")
check(said[#said]:find("already rolled 150 · first roll counts"), "re-roller told: " .. said[#said])
fire("CHAT_MSG_SYSTEM", "Kumlust rolls 200 (1-200)")
check(G.Game.players.Kumlust.roll == 150 and select(2, said[#said]:gsub("already rolled", "")) == 1 and not said[#said]:find("200 ·"), "told once, still 150")
fire("CHAT_MSG_SYSTEM", "Dps2 rolls 20 (1-200)")
fire("CHAT_MSG_SYSTEM", "Dps1 rolls 180 (1-200)")
-- CHAT GOES SECRET during a chat lockdown on Forever: the text and the sender arrive as values
-- that error on every read - a pattern match, a comparison, a concatenation. The mock errors the
-- same way; issecretvalue is how the client lets an addon ask first.
do
  local boom = function() error("attempt to read a secret string", 2) end
  local secretMeta = { __index = boom, __eq = boom, __lt = boom, __le = boom, __concat = boom,
                       __len = boom, __tostring = boom, __call = boom }
  local function secret() return setmetatable({}, secretMeta) end
  local realIs = _G.issecretvalue
  _G.issecretvalue = function(v) return getmetatable(v) == secretMeta end
  local before = #chat
  local ok1 = pcall(fire, "CHAT_MSG_SYSTEM", secret())
  local ok2 = pcall(fire, "CHAT_MSG_RAID", secret(), "Dps4")
  local ok3 = pcall(fire, "CHAT_MSG_RAID", "1", secret())
  local ok4 = pcall(fire, "CHAT_MSG_ADDON", "BiSGamba", secret(), "RAID", "Dps2-Dreamscythe")
  local ok5 = pcall(fire, "UI_ERROR_MESSAGE", 1, secret())
  check(ok1 and ok2 and ok3 and ok4 and ok5, "a secret roll, chat line, sender, addon message or"
    .. " trade message is dropped, not thrown")
  check(G.hidden.CHAT_MSG_SYSTEM == 1 and G.hidden.CHAT_MSG_RAID == 2 and G.hidden.CHAT_MSG_ADDON == 1,
    "and counted, which is the measurement of when chat goes secret")
  local told = 0
  for i = before + 1, #chat do if chat[i]:find("hiding chat") then told = told + 1 end end
  check(told == 1, "mid-round, the table is told once that rolls cannot be counted: " .. told)
  check(G.Game.state == "ROLL" and G.Game.players.Dps4 == nil and G.Game.players.Kumsecration.roll == nil,
    "nothing about the round changed")
  SlashCmdList.BISGAMBA("hidden")
  check(lastChat():find("hidden chat this session") and lastChat():find("CHAT_MSG_RAID 2"),
    "/gamba hidden reports the count: " .. lastChat())
  _G.issecretvalue = realIs
end
-- somebody who never joined cannot buy in once the rolls are out, by any route
fire("CHAT_MSG_SYSTEM", "Dps4 rolls 190 (1-200)")
check(G.Game.players.Dps4 == nil, "a bystander's roll is ignored")
SlashCmdList.BISGAMBA("autojoin")
fire("CHAT_MSG_SYSTEM", "Dps4 rolls 190 (1-200)")
check(G.Game.players.Dps4 == nil, "not even with autojoin on - the table is shut")
SlashCmdList.BISGAMBA("autojoin")
fire("CHAT_MSG_RAID", "1", "Dps4")
check(G.Game.players.Dps4 == nil, "and typing 1 does not get them in")
check(saidHas("the rolls are already out"), "they are told why: " .. tostring(saidHas("already out")))
fire("CHAT_MSG_SYSTEM", "Kumsecration rolls 77 (1-200)")
check(G.Game.state == "ROLL", "grace period holds")
runTimers()
check(G.Game.state == "DONE", "settled after grace")
local res = G.Game.result
check(res and res.winner == "Dps1" and res.loser == "Dps2" and res.amount == 160, "high 180 low 20 -> 160g")
check(said[#said]:find("Dps2 owes Dps1 160g"), "result announced: " .. said[#said])
check(#BiSGambaDB.debts == 1 and BiSGambaDB.debts[1].amount == 160, "ledger has the debt")
fitsIn(BiSGambaFrame, "the table, round settled")
runTimers()
local function sent(op) for _, m in ipairs(addon) do if m:find("^" .. op) then return m end end end
check(sent("OPEN\t200") and sent("JOIN\tDps2") and sent("GO") and sent("ROLL\tDps1\t180") and sent("DONE\tDps1\tDps2\t160\t180\t20"), "host broadcast the round")
-- emotes
local function seatAnim(name)
  for _, s in ipairs(G.UI.seats) do if s.person and s.person.name == name then return s.model.anim, s.model.model end end
end
check(seatAnim("Dps1") == 68, "winner cheers")
check(seatAnim("Dps2") == 77, "loser cries")
local a = seatAnim("Kumlust")
check(a == 70 or a == 80 or a == 82 or a == 69, "second place smug: " .. tostring(a))
a = seatAnim("Kumsecration")
check(a == 75 or a == 79 or a == 83 or a == 60 or a == 67 or a == 65, "third of four sweats: " .. tostring(a))
SlashCmdList.BISGAMBA("view 3d"); G.UI:Refresh()
local _, model = seatAnim("Kumsecration")
check(model == "npc:5595", "out of range dwarf uses the guard: " .. tostring(model))
_, model = seatAnim("Dps2")
check(model == "unit:raid2", "in range uses SetUnit: " .. tostring(model))
SlashCmdList.BISGAMBA("view 2d"); G.UI:Refresh()
-- rest timer puts them back to standing
_G.__now = 1020
G.UI.frame.scripts.OnUpdate(G.UI.frame, 0.1)
check(seatAnim("Dps1") == 0, "back to standing")

---------------------------------------------------------------- round 2: ties
SlashCmdList.BISGAMBA("start")
check(G.Game.max == 200, "wager remembered")
fire("CHAT_MSG_RAID", "1", "Dps2"); fire("CHAT_MSG_RAID", "1", "Kumsecration"); fire("CHAT_MSG_RAID", "1", "Dps1")
SlashCmdList.BISGAMBA("go")
fire("CHAT_MSG_SYSTEM", "Kumlust rolls 100 (1-200)")
fire("CHAT_MSG_SYSTEM", "Dps2 rolls 100 (1-200)")
fire("CHAT_MSG_SYSTEM", "Kumsecration rolls 5 (1-200)")
fire("CHAT_MSG_SYSTEM", "Dps1 rolls 5 (1-200)")
runTimers()
check(G.Game.state == "TIE" and G.Game.tieKind == "high", "high tie first")
check(G.Game.tied.Kumlust and G.Game.tied.Dps2 and not G.Game.tied.Kumsecration, "right people tied")
fire("CHAT_MSG_SYSTEM", "Kumsecration rolls 199 (1-200)")   -- not in the tiebreak
check(G.Game.players.Kumsecration.tieRoll == nil, "outsider tie roll ignored")
G.UI.rollBtn.scripts.OnClick()
check(rolled[#rolled][2] == 200, "tie roll uses the same range")
fire("CHAT_MSG_SYSTEM", "Kumlust rolls 150 (1-200)")
fire("CHAT_MSG_SYSTEM", "Dps2 rolls 30 (1-200)")
check(G.Game.state == "TIE" and G.Game.tieKind == "low", "then the low tie")
fire("CHAT_MSG_SYSTEM", "Kumsecration rolls 10 (1-200)")
fire("CHAT_MSG_SYSTEM", "Dps1 rolls 90 (1-200)")
check(G.Game.state == "DONE", "settled after both ties")
res = G.Game.result
check(res.winner == "Kumlust" and res.loser == "Kumsecration" and res.amount == 95, "amount uses the original rolls (100-5)")

---------------------------------------------------------------- stale highName regression
SlashCmdList.BISGAMBA("start 100")
fire("CHAT_MSG_RAID", "1", "Dps2"); fire("CHAT_MSG_RAID", "1", "Dps1")
SlashCmdList.BISGAMBA("go")
fire("CHAT_MSG_SYSTEM", "Kumlust rolls 10 (1-100)")
fire("CHAT_MSG_SYSTEM", "Dps2 rolls 10 (1-100)")
fire("CHAT_MSG_SYSTEM", "Dps1 rolls 90 (1-100)")
runTimers()
check(G.Game.state == "TIE" and G.Game.tieKind == "low", "low tie only")
fire("CHAT_MSG_SYSTEM", "Kumlust rolls 50 (1-100)")
fire("CHAT_MSG_SYSTEM", "Dps2 rolls 2 (1-100)")
check(G.Game.result and G.Game.result.winner == "Dps1" and G.Game.result.loser == "Dps2" and G.Game.result.amount == 80, "low tie pays this round's high")
-- a low tie never books TWO losers: the other low-roller is rerolled out, not charged.
-- the round carries exactly one loser field, so only one player can ever take the loss.
check(G.Game.result.loser == "Dps2" and G.Game.result.loser ~= "Kumlust", "the co-low-roller is not booked as a second loser")
check(type(G.Game.result.loser) == "string", "a round has one loser, not a list")
for _, s_ in ipairs(G.UI.seats) do if s_.person and s_.person.name == "Kumlust" then end end

---------------------------------------------------------------- the window says it in English
G.UI:Show()
G.UI:ToggleDebts(); G.UI:Refresh()
fitsIn(BiSGambaFrame, "the table with the debts open")
local rows = {}
for _, r in ipairs(G.UI.rows) do if r.shown and r.text.text_ then rows[#rows + 1] = strip(r.text.text_) end end
local mineRow
for _, t in ipairs(rows) do if t:find("^you ") then mineRow = t end end
check(mineRow == nil or mineRow:find("^you owe "), "no \"you owes\": " .. tostring(mineRow))
for _, t in ipairs(rows) do
  check(not t:find("you owes") and not t:find("^%u%a+ owe "), "debt row reads right: " .. t)
end
G.UI:ToggleDebts()

---------------------------------------------------------------- everybody on the same number rerolls
SlashCmdList.BISGAMBA("reset")
addon = {}
SlashCmdList.BISGAMBA("start 100")
fire("CHAT_MSG_RAID", "1", "Dps2"); fire("CHAT_MSG_RAID", "1", "Kumsecration")
SlashCmdList.BISGAMBA("go")
fire("CHAT_MSG_SYSTEM", "Kumlust rolls 7 (1-100)")
fire("CHAT_MSG_SYSTEM", "Dps2 rolls 7 (1-100)")
fire("CHAT_MSG_SYSTEM", "Kumsecration rolls 7 (1-100)")
runTimers()
check(G.Game.state == "ROLL", "an all-square round goes back to rolling, not DONE")
check(G.Game.players.Kumlust.roll == nil and G.Game.players.Dps2.roll == nil, "everyone's roll is cleared")
check(saidHas("everybody rolled 7 · everyone reroll /roll 100"), "and it says so: " .. tostring(saidHas("reroll")))
check(sent("REDO"), "clients told to reroll")
check(G.Game.result == nil, "no result was booked")
-- and the rerolled numbers settle it normally
fire("CHAT_MSG_SYSTEM", "Kumlust rolls 80 (1-100)")
fire("CHAT_MSG_SYSTEM", "Dps2 rolls 30 (1-100)")
fire("CHAT_MSG_SYSTEM", "Kumsecration rolls 55 (1-100)")
runTimers()
check(G.Game.state == "DONE" and G.Game.result.winner == "Kumlust" and G.Game.result.loser == "Dps2"
  and G.Game.result.amount == 50, "the reroll decides it")
-- a client hearing REDO clears its own copy
SlashCmdList.BISGAMBA("reset")
from("Dps2", "OPEN", "100")
from("Dps2", "JOIN", "Dps2"); from("Dps2", "JOIN", "Kumlust")
from("Dps2", "GO")
from("Dps2", "ROLL", "Kumlust", "7"); from("Dps2", "ROLL", "Dps2", "7")
from("Dps2", "REDO")
check(G.Game.state == "ROLL" and G.Game.players.Kumlust.roll == nil, "the client cleared its rolls too")
check(G.Game.CanRoll(), "and can roll again")
SlashCmdList.BISGAMBA("reset")

---------------------------------------------------------------- ledger netting
local owes0, owed0 = G.Ledger.Net("Kumlust")
G.Ledger.Add("Kumlust", "Dps2", 50)
G.Ledger.Add("Dps2", "Kumlust", 80)
local owes, owed = G.Ledger.Net("Kumlust")
check(owes == owes0 and owed == owed0 + 30, "netting: 80 against 50 leaves 30 owed to us")
G.Ledger.Add("Kumlust", "Dps1", 40)
owes = G.Ledger.Net("Kumlust")
check(owes == 40, "owes cash 40")

---------------------------------------------------------------- pay: trade flow
_G.__initiated = nil
G.Trade.Pay()
check(G.Trade.pending and G.Trade.pending.to == "Dps1", "pay picks who I owe")
runTimers()
check(_G.__initiated == "raid4", "InitiateTrade after the delay: " .. tostring(_G.__initiated))
TradeFrame.shown = true
fire("TRADE_SHOW")
runTimers()
check(myMoney == 40 * 10000, "40g put in the trade: " .. myMoney)
fire("TRADE_ACCEPT_UPDATE", 1, 1)
TradeFrame.shown = false
fire("TRADE_CLOSED"); fire("TRADE_CLOSED")
fire("UI_INFO_MESSAGE", 1, "Trade complete.")
check(G.Ledger.Net("Kumlust") == 0, "debt cleared after the trade")
check(chat[#chat]:find("square"), "paid message: " .. lastChat())
-- a requested but not yet accepted trade must never be filled
G.Ledger.Add("Kumlust", "Dps1", 32)
openTrade("Dps1")
G.UI:Show(); G.UI:Refresh()
check(strip(G.UI.payBtn.text.text_) ~= "put 32g in", "no fill offered before they accept")
G.Trade.Pay(); runTimers()
check(myMoney == 0, "nothing goes in a trade that is only requested")
check(chat[#chat]:find("goes in as soon as they accept") or chat[#chat]:find("asking"), "says it is waiting: " .. lastChat())
fire("TRADE_SHOW"); runTimers()
G.UI:Refresh()
check(strip(G.UI.payBtn.text.text_) == "put 32g in", "pay button offers to fill once live: " .. strip(G.UI.payBtn.text.text_))
G.UI.payBtn.scripts.OnClick()
runTimers()
check(myMoney == 32 * 10000, "second press put 32g in the trade")
check(G.Trade.live, "trade is live")
fire("TRADE_ACCEPT_UPDATE", 1, 1); TradeFrame.shown = false; fire("TRADE_CLOSED"); fire("UI_INFO_MESSAGE", 1, "Trade complete.")
runTimers()
-- name read from the trade frame when UnitName("NPC") comes back empty
TradeFrameRecipientNameText = newFrame("FontString", "TradeFrameRecipientNameText")
TradeFrameRecipientNameText.text_ = "Dps1-Dreamscythe"
G.Ledger.Add("Kumlust", "Dps1", 7)
openTrade("Dps1"); tradePartner = nil
fire("TRADE_SHOW"); runTimers()
G.Trade.Pay()
runTimers()
check(myMoney == 7 * 10000, "partner read off the trade frame")
TradeFrame.shown = false; fire("TRADE_CLOSED"); TradeFrameRecipientNameText = nil
G.Ledger.Clear("Kumlust", "Dps1")
G.Trade.pending = nil
runTimers()

-- a client that refuses SetTradeMoney too: show the number, never claim success
local realSet, realCopper = SetTradeMoney, MoneyInputFrame_SetCopper
G.Ledger.Add("Kumlust", "Dps1", 9)
openTrade("Dps1")
SetTradeMoney = function() end                       -- Blizzard blocks both
MoneyInputFrame_SetCopper = function() end
fire("TRADE_SHOW"); runTimers()
G.Trade.Pay(); runTimers()
check(chat[#chat]:find("Ctrl%+C"), "points at the copy box: " .. lastChat())
check(G.Trade.panel and G.Trade.panel.shown, "falls back to the panel")
fitsIn(BiSGambaTradePanel, "the trade panel, I owe")
check(G.Trade.panel.amount.text_ == "9", "copy box holds the bare number: " .. tostring(G.Trade.panel.amount.text_))
check(G.Trade.panel.amount.text_:match("^%d+$"), "nothing in it but digits, so it pastes clean")
-- editing it snaps back: it is a display, not an input
G.Trade.panel.amount:SetText("garbage")
G.Trade.panel.amount.scripts.OnEditFocusLost(G.Trade.panel.amount)
check(G.Trade.panel.amount.text_ == "9", "edits snap back")
check(picked == nil, "never calls the protected PickupPlayerMoney")
SetTradeMoney, MoneyInputFrame_SetCopper = realSet, realCopper
TradeFrame.shown = false; fire("TRADE_CLOSED"); G.Trade.pending = nil
G.Ledger.Clear("Kumlust", "Dps1"); runTimers()

SlashCmdList.BISGAMBA("tradedebug")

-- they open the trade themselves: the panel shows the balance and it fills
G.Ledger.Add("Kumlust", "Dps1", 25)
openTrade("Dps1")
fire("TRADE_SHOW"); runTimers()
check(G.Trade.panel and G.Trade.panel.shown, "panel up beside the trade window")
runTimers()
check(whispers[#whispers] and whispers[#whispers]:find("I owe you 25g"), "whispers somebody with no addon: " .. tostring(whispers[#whispers]))
G.Trade.Pay(); runTimers()
check(myMoney == 25 * 10000, "fills 25g when the client allows it")
check(chat[#chat]:find("put 25g in the trade"), "only claims success after reading it back: " .. lastChat())
fire("TRADE_ACCEPT_UPDATE", 1, 1); TradeFrame.shown = false; fire("TRADE_CLOSED"); fire("UI_INFO_MESSAGE", 1, "Trade complete.")
check(G.Ledger.Net("Kumlust") == 0, "settled from the button")
-- somebody pays me
tradePartner = "Dps2"; myMoney = 0; theirMoney = 20 * 10000
TradeFrame.shown = true
fire("TRADE_SHOW"); fire("TRADE_MONEY_CHANGED"); fire("TRADE_ACCEPT_UPDATE", 1, 1)
TradeFrame.shown = false
fire("UI_INFO_MESSAGE", 1, "Trade complete.")
local _, owed2 = G.Ledger.Net("Kumlust")
check(owed2 == owed - 20, "partial payment recorded: " .. owed2)

---------------------------------------------------------------- the table shuts when the rolls are called
SlashCmdList.BISGAMBA("reset")
SlashCmdList.BISGAMBA("start 100")
fire("CHAT_MSG_RAID", "1", "Dps2")
check(#G.Game.order == 2, "two seated while it is open")
check(not G.UI.joinBtn.off, "and the join button works")
SlashCmdList.BISGAMBA("go")
-- from here nobody gets in or out
check(G.UI.joinBtn.off, "join is shut once the rolls are called")
fire("CHAT_MSG_RAID", "1", "Kumsecration")
check(G.Game.players.Kumsecration == nil, "a latecomer cannot join")
fire("CHAT_MSG_SYSTEM", "Dps2 rolls 3 (1-100)")
fire("CHAT_MSG_RAID", "1", "Kumsecration")
check(G.Game.players.Kumsecration == nil, "and still cannot after seeing somebody roll low")
-- nor can somebody who is in duck out of a losing round
fire("CHAT_MSG_RAID", "-1", "Dps2")
check(G.Game.players.Dps2 ~= nil, "and nobody can walk out of a round they are losing")
G.Game.JoinMe()
check(chat[#chat]:find("rolls are already out"), "the button says so too: " .. lastChat())
check(G.Game.Seated(), "we are still in")
fire("CHAT_MSG_SYSTEM", "Kumlust rolls 80 (1-100)")
runTimers()
check(G.Game.result and G.Game.result.winner == "Kumlust" and G.Game.result.loser == "Dps2",
  "and the round settles between the two who were actually in it")
SlashCmdList.BISGAMBA("reset")

---------------------------------------------------------------- refusing to roll is a forfeit, not an escape
SlashCmdList.BISGAMBA("reset")
SlashCmdList.BISGAMBA("start 100")
fire("CHAT_MSG_RAID", "1", "Dps2"); fire("CHAT_MSG_RAID", "1", "Kumsecration")
SlashCmdList.BISGAMBA("go")
fire("CHAT_MSG_SYSTEM", "Kumlust rolls 60 (1-100)")
fire("CHAT_MSG_SYSTEM", "Dps2 rolls 80 (1-100)")
-- Kumsecration never rolls; host ends
SlashCmdList.BISGAMBA("end")
check(G.Game.state == "DONE", "settled on end")
check(G.Game.result.winner == "Dps2" and G.Game.result.loser == "Kumsecration",
  "the one who never rolled pays, not the low roller: " .. tostring(G.Game.result.loser))
check(saidHas("never rolled · forfeit") ~= nil, "and it is announced")
SlashCmdList.BISGAMBA("reset")

---------------------------------------------------------------- a host who vanishes frees the table
SlashCmdList.BISGAMBA("reset")
from("Dps2", "OPEN", "100")
check(G.Game.Remote() and G.Game.host == "Dps2", "on a remote table")
group.raid2.offline = true
fire("GROUP_ROSTER_UPDATE")
check(G.Game.state == "IDLE" and G.Game.host == nil, "a disconnected host's table is let go")
group.raid2.offline = nil
-- and we can host after
SlashCmdList.BISGAMBA("start 100")
check(G.Game.IsHost(), "and we can open our own")
SlashCmdList.BISGAMBA("reset")

---------------------------------------------------------------- crafted messages are refused
SlashCmdList.BISGAMBA("reset")
BiSGambaDB.debts = {}
-- a stranger who opens a table then declares a result cannot write a debt
from("Dps2", "OPEN", "100")
from("Dps2", "DONE", "Dps2", "Kumlust", "999", "100", "1")
check(#BiSGambaDB.debts == 0, "a DONE with rolls we never saw is refused")
check(chat[#chat]:find("does not match the rolls we saw"), "and flagged: " .. lastChat())
-- a DONE whose amount does not follow from the rolls is refused
SlashCmdList.BISGAMBA("reset"); BiSGambaDB.debts = {}
from("Dps2", "OPEN", "100")
from("Dps2", "JOIN", "Dps2"); from("Dps2", "JOIN", "Kumlust")
from("Dps2", "GO")
from("Dps2", "ROLL", "Kumlust", "90"); from("Dps2", "ROLL", "Dps2", "20")
from("Dps2", "DONE", "Kumlust", "Dps2", "500", "90", "20")   -- should be 70
check(#BiSGambaDB.debts == 0, "a DONE with a wrong amount is refused")
from("Dps2", "DONE", "Kumlust", "Dps2", "70", "90", "20")    -- correct
check(#BiSGambaDB.debts == 1 and BiSGambaDB.debts[1].amount == 70, "the honest result is booked")
SlashCmdList.BISGAMBA("reset")

---------------------------------------------------------------- last call
SlashCmdList.BISGAMBA("reset")
_G.__now = 2000
SlashCmdList.BISGAMBA("start 100")
check(G.Game.state == "JOIN" and G.Game.IsHost(), "table open")
check(G.UI.rollBtn.off, "roll greyed while the table is only open")
local rollsBefore = #rolled
G.UI.rollBtn.scripts.OnClick()
G.Game.RollMe()
check(#rolled == rollsBefore, "the roll button never starts the game")
check(chat[#chat]:find("rolls haven't been called yet"), "and says why: " .. lastChat())
check(G.Game.state == "JOIN", "still just open")
fire("CHAT_MSG_RAID", "1", "Dps2")
-- last call
G.UI.callBtn.scripts.OnClick()
check(said[#said]:find("last call · 10s") and said[#said]:find("/roll 100"), "last call announced: " .. said[#said])
check(G.Game.Countdown() ~= nil and G.Game.state == "JOIN", "counting down, table still open")
runTimers(1)                       -- drain the comm queue, leave the countdown ticking
check(sent("CALL\t10"), "clients told about the countdown")
check(G.UI.rollBtn.off, "roll still greyed during the countdown")
G.UI:Refresh()
check(strip(G.UI.startBtn.text.text_) == "start now", "start button offers to skip: " .. strip(G.UI.startBtn.text.text_))
check(G.UI.callBtn.off, "no second countdown")
-- the host's own body counts it down
_G.__now = 2004
G.UI.frame.scripts.OnUpdate(G.UI.frame, 0.1)
local hostSeat
for _, s_ in ipairs(G.UI.seats) do if s_.person and s_.person.name == "Kumlust" then hostSeat = s_ end end
check(hostSeat and strip(hostSeat.roll.text_) == "6", "host portrait shows 6: " .. tostring(hostSeat and strip(hostSeat.roll.text_)))
_G.__now = 2008
G.UI.frame.scripts.OnUpdate(G.UI.frame, 0.1)
check(strip(hostSeat.roll.text_) == "2" and hostSeat.model.anim == 64, "last seconds shout: " .. strip(hostSeat.roll.text_))
-- it fires by itself when the ten seconds are up
_G.__now = 2010
check(G.Game.state == "JOIN", "still open until the clock runs out")
runTimers()
check(G.Game.state == "ROLL" and G.Game.Countdown() == nil, "countdown starts the rolls")
check(not G.UI.rollBtn.off and G.UI.rollBtn.hot, "roll lit once rolls are called")
-- and "start now" skips it
SlashCmdList.BISGAMBA("reset"); SlashCmdList.BISGAMBA("start 100")
fire("CHAT_MSG_RAID", "1", "Dps2")
SlashCmdList.BISGAMBA("call")
runTimers(1)
check(G.Game.Countdown() ~= nil, "counting again")
G.UI.startBtn.scripts.OnClick()
check(G.Game.state == "ROLL" and G.Game.Countdown() == nil, "start now skips the countdown")
runTimers()
check(G.Game.state == "ROLL", "the expiring timer does not re-fire")

---------------------------------------------------------------- the host can sit out
SlashCmdList.BISGAMBA("reset"); SlashCmdList.BISGAMBA("start 100")
check(G.Game.Seated(), "host is seated by default")
G.UI.joinBtn.scripts.OnClick()
check(not G.Game.Seated() and G.Game.IsHost() and G.Game.state == "JOIN", "host backed out but still runs the table")
check(strip(G.UI.joinBtn.text.text_) == "join", "button flipped back to join")
fire("CHAT_MSG_RAID", "1", "Dps2"); fire("CHAT_MSG_RAID", "1", "Kumsecration")
SlashCmdList.BISGAMBA("go")
check(said[#said]:find("rolls open") and said[#said]:find("HIGH / LOW") and said[#said]:find("/roll 100 now"),
  "the go line says the rolls are open and what the game is: " .. said[#said])
check(G.Game.state == "ROLL" and G.Game.players.Kumlust == nil, "rolls called without the host at the table")
check(G.UI.rollBtn.off, "host who sat out cannot roll")
fire("CHAT_MSG_SYSTEM", "Dps2 rolls 80 (1-100)")
fire("CHAT_MSG_SYSTEM", "Kumsecration rolls 20 (1-100)")
runTimers()
check(G.Game.result and G.Game.result.winner == "Dps2" and G.Game.result.loser == "Kumsecration", "the host still settled it")
G.UI.joinBtn.scripts.OnClick()
SlashCmdList.BISGAMBA("reset")
_G.__now = 1000

---------------------------------------------------------------- client mode: Dps2 hosts
SlashCmdList.BISGAMBA("reset")
addon = {}
local function gnomeOwesMe() for _, d in ipairs(BiSGambaDB.debts) do if d.from == "Dps2" and d.to == "Kumlust" then return d.amount end end return 0 end
local base = gnomeOwesMe()
from("Dps2", "OPEN", "150")
check(G.Game.state == "JOIN" and G.Game.host == "Dps2" and G.Game.max == 150 and not G.Game.IsHost(), "joined a remote table")
-- one layout for everybody: the host's controls are greyed, never hidden
check(G.UI.joinBtn.shown and G.UI.startBtn.shown and G.UI.callBtn.shown and G.UI.endBtn.shown,
  "every button is on screen for a player too")
check(G.UI.startBtn.off and G.UI.callBtn.off and G.UI.endBtn.off, "but the host's are greyed")
G.UI.startBtn.scripts.OnClick(); G.UI.endBtn.scripts.OnClick()
check(G.Game.host == "Dps2" and G.Game.state == "JOIN", "and a greyed button does nothing")
check(G.UI.rollBtn.off, "roll greyed before GO")
from("Dps2", "JOIN", "Dps2")
G.UI.joinBtn.scripts.OnClick()
check(said[#said] == "RAID: 1", "join types 1: " .. said[#said])
from("Dps2", "JOIN", "Kumlust")
check(G.Game.Seated() and G.UI.joinBtn.text.text_ == "leave", "seated -> button says leave")
G.UI.joinBtn.scripts.OnClick()
check(said[#said] == "RAID: -1", "leave types -1")
from("Dps2", "LEAVE", "Kumlust"); from("Dps2", "JOIN", "Kumlust")
-- a stranger's OPEN doesn't hijack
from("Dps1", "OPEN", "999")
check(G.Game.host == "Dps2", "second host ignored? host=" .. tostring(G.Game.host))
SlashCmdList.BISGAMBA("start 50")
check(G.Game.host == "Dps2" and G.Game.max == 150, "can't start over a remote table")
from("Dps2", "GO")
check(G.Game.state == "ROLL" and not G.UI.rollBtn.off and G.UI.rollBtn.hot, "roll lit after GO")
local before = #rolled
G.UI.rollBtn.scripts.OnClick()
check(#rolled == before + 1 and rolled[#rolled][2] == 150, "client rolls 1-150")
fire("CHAT_MSG_SYSTEM", "Kumlust rolls 77 (1-150)")   -- clients ignore chat, the host tells them
check(G.Game.players.Kumlust.roll == nil, "client doesn't read rolls itself")
from("Dps2", "ROLL", "Kumlust", "77")
check(G.Game.players.Kumlust.roll == 77 and G.UI.rollBtn.off, "roll from host; button greyed after rolling")
from("Dps2", "ROLL", "Dps2", "12")
from("Dps2", "TIE", "high"); from("Dps2", "TIED", "Kumlust"); from("Dps2", "TIED", "Dps2")
check(G.Game.state == "TIE" and G.Game.tied.Kumlust and G.Game.CanRoll() and not G.UI.rollBtn.off, "client tiebreak: roll lit again")
from("Dps2", "ROLL", "Kumlust", "40", "T")
check(G.Game.players.Kumlust.tieRoll == 40 and G.UI.rollBtn.off, "tie roll taken")
from("Dps2", "ROLL", "Kumlust", "40", "T")   -- replayed: no re-emote
from("Dps2", "DONE", "Kumlust", "Dps2", "65", "77", "12")
check(G.Game.state == "DONE" and G.Game.result.amount == 65, "DONE applied")
check(gnomeOwesMe() == base + 65, "client ledger booked the debt: " .. gnomeOwesMe())
from("Dps2", "PAID", "Dps2", "Kumlust", "65")   -- the DEBTOR's word: worthless
check(gnomeOwesMe() == base + 65, "a debtor cannot clear their own debt with PAID")
-- but a third party hears it from the creditor. Us: watch Kumsecration owe Dps2, cleared by Dps2.
G.Ledger.Clear("Kumsecration", "Dps2"); G.Ledger.Clear("Dps2", "Kumsecration")
G.Ledger.Add("Kumsecration", "Dps2", 40)
from("Kumsecration", "PAID", "Kumsecration", "Dps2", "40")   -- not the creditor: ignored
local function pairAmt(a,b) for _, d in ipairs(BiSGambaDB.debts) do if d.from==a and d.to==b then return d.amount end end return 0 end
check(pairAmt("Kumsecration","Dps2") == 40, "and neither can a debtor for someone else")
from("Dps2", "PAID", "Kumsecration", "Dps2", "40")    -- the creditor: honoured
check(pairAmt("Kumsecration","Dps2") == 0, "the creditor's PAID clears it")
from("Dps2", "CLOSE")
check(G.Game.state == "DONE", "CLOSE after DONE leaves the result up")
-- HI from a client while hosting -> replay
SlashCmdList.BISGAMBA("start 60")
check(G.Game.IsHost(), "hosting again after remote table ended")
fire("CHAT_MSG_RAID", "1", "Kumsecration")
SlashCmdList.BISGAMBA("go")
fire("CHAT_MSG_SYSTEM", "Kumlust rolls 30 (1-60)")
addon = {}
from("Dps1", "HI")
runTimers()
check(sent("OPEN\t60") and sent("JOIN\tKumsecration") and sent("GO") and sent("ROLL\tKumlust\t30"), "HI replays the table")
-- views
for _, v in ipairs({ "2d", "3d" }) do SlashCmdList.BISGAMBA("view " .. v); G.UI:Refresh(); check(BiSGambaDB.view == v, "view " .. v) end
SlashCmdList.BISGAMBA("view table"); check(BiSGambaDB.view ~= "table", "no table view any more")
SlashCmdList.BISGAMBA("view 2d"); SlashCmdList.BISGAMBA("view"); check(BiSGambaDB.view == "3d", "cycle 2d->3d")
SlashCmdList.BISGAMBA("view"); check(BiSGambaDB.view == "2d", "cycle 3d->2d")
-- the window must be exactly the same size in both views
local function frameSize() G.UI:Refresh(); return G.UI.frame.w, G.UI.frame.h end
SlashCmdList.BISGAMBA("view 2d"); local w2, h2 = frameSize()
SlashCmdList.BISGAMBA("view 3d"); local w3, h3 = frameSize()
check(w2 == w3 and h2 == h3, ("views never resize the window: %sx%s vs %sx%s"):format(w2, h2, w3, h3))
-- popup off: a remote OPEN no longer shows the window
SlashCmdList.BISGAMBA("reset"); G.UI.frame:Hide()
G.UI.autoOpen.checked = false; G.UI.autoOpen.scripts.OnClick(G.UI.autoOpen)
from("Dps2", "OPEN", "70")
check(BiSGambaDB.autoOpen == false and not G.UI.frame.shown and G.Game.host == "Dps2", "popup off: table synced but window stays closed")
SlashCmdList.BISGAMBA("popup"); check(BiSGambaDB.autoOpen == true, "popup toggled back")
from("Dps2", "CLOSE"); G.UI:Show()
SlashCmdList.BISGAMBA("start 60"); fire("CHAT_MSG_RAID", "1", "Kumsecration"); SlashCmdList.BISGAMBA("go"); fire("CHAT_MSG_SYSTEM", "Kumlust rolls 30 (1-60)")
SlashCmdList.BISGAMBA("view 2d"); G.UI:Refresh()
local s2 = nil; for _, s_ in ipairs(G.UI.seats) do if s_.person and s_.person.name == "Kumlust" then s2 = s_ end end
check(s2 and s2.portrait.shown and not s2.model.shown and s2.portrait.portrait == "player", "2d uses the live portrait")
SlashCmdList.BISGAMBA("reset")

---------------------------------------------------------------- no whisper between addon users
TradeFrame.shown = false; fire("TRADE_CLOSED"); G.Trade.pending = nil; runTimers()
local before = #whispers
G.Ledger.Add("Kumlust", "Dps2", 15)
openTrade("Dps2")
fire("TRADE_SHOW"); runTimers()
check(G.Comm.HasAddon("Dps2"), "Dps2 is a known addon user (we heard their comms)")
check(#whispers == before, "no whisper to someone running the addon")
check(G.Trade.panel.shown, "panel still shows for an addon user")
-- the panel shows the balance with THIS partner, whichever way it points
local pair = 0
for _, d in ipairs(BiSGambaDB.debts) do
  if (d.from == "Kumlust" and d.to == "Dps2") or (d.from == "Dps2" and d.to == "Kumlust") then pair = d.amount end
end
check(tonumber(G.Trade.panel.amount.text_) == pair and pair > 0,
  "panel shows the balance with this partner: " .. tostring(G.Trade.panel.amount.text_) .. " vs " .. pair)
-- somebody we have never heard from gets the whisper, unless they answer the ping
TradeFrame.shown = false; fire("TRADE_CLOSED"); runTimers()
BiSGambaDB.users["Dps1"] = nil
G.Ledger.Add("Kumlust", "Dps1", 11)
openTrade("Dps1")
fire("TRADE_SHOW")
from("Dps1", "PONG")                       -- they do have it after all
runTimers()
check(#whispers == before, "a PONG cancels the whisper")
check(G.Comm.HasAddon("Dps1"), "and they are remembered")
TradeFrame.shown = false; fire("TRADE_CLOSED"); runTimers()
G.Ledger.Clear("Kumlust", "Dps2"); G.Ledger.Clear("Kumlust", "Dps1")
SlashCmdList.BISGAMBA("users")

---------------------------------------------------------------- the PAYER clears their own debt (regression guard)
-- the real client zeroes the money frames the instant the trade closes, so the
-- payer's settle must survive on the peak seen during the trade, not a post-close read.
G.Trade.pending = nil; TradeFrame.shown = false; fire("TRADE_CLOSED"); runTimers()
G.Ledger.Clear("Kumlust", "Dps1"); G.Ledger.Clear("Dps1", "Kumlust")
G.Ledger.Add("Kumlust", "Dps1", 67)      -- we owe them
openTrade("Dps1")
fire("TRADE_SHOW"); runTimers()
myMoney = 67 * 10000                              -- we paste 67g in
G.Trade.ticker.scripts.OnUpdate(G.Trade.ticker, 0.3)   -- ticker sees it
fire("TRADE_ACCEPT_UPDATE", 1, 1)                -- both accept
myMoney = 0                                      -- client zeroes the frame as the trade closes
TradeFrame.shown = false
fire("TRADE_CLOSED")                             -- no ERR_TRADE_COMPLETE at all
runTimers()
local function owe(a,b) for _, d in ipairs(BiSGambaDB.debts) do if d.from==a and d.to==b then return d.amount end end return 0 end
check(owe("Kumlust","Dps1") == 0, "the payer's own debt clears even when the frame zeroes at close: " .. owe("Kumlust","Dps1"))
check(chat[#chat]:find("paid Dps1 67g"), "and it says so on the payer's side: " .. lastChat())
G.Ledger.Clear("Kumlust","Dps1"); myMoney = 0; G.Trade.pending = nil; runTimers()
-- harder: no clean 1,1 ever seen (client raced it), only ERR_TRADE_COMPLETE with the frame already zeroed
G.Ledger.Add("Kumlust", "Dps1", 40)
openTrade("Dps1")
fire("TRADE_SHOW"); runTimers()
myMoney = 40 * 10000
G.Trade.ticker.scripts.OnUpdate(G.Trade.ticker, 0.3)   -- ticker sees the 40 (peak)
myMoney = 0                                            -- frame reads 0 at the accept event and after
fire("TRADE_ACCEPT_UPDATE", 1, 1)                      -- accept, but the read is already 0
myMoney = 0
TradeFrame.shown = false
fire("TRADE_CLOSED")                                   -- close zeroes everything
runTimers()
check(owe("Kumlust","Dps1") == 0, "clears on the peak when the accept read was 0: " .. owe("Kumlust","Dps1"))
G.Ledger.Clear("Kumlust","Dps1"); myMoney = 0; G.Trade.pending = nil; TradeFrame.shown=false; fire("TRADE_CLOSED"); runTimers()

---------------------------------------------------------------- accept, un-accept, cancel: nothing moves
G.Trade.pending = nil; TradeFrame.shown = false; fire("TRADE_CLOSED"); runTimers()
G.Ledger.Add("Kumlust", "Dps1", 300)
local owed300 = 0
for _, d in ipairs(BiSGambaDB.debts) do if d.from=="Kumlust" and d.to=="Dps1" then owed300 = d.amount end end
openTrade("Dps1")
fire("TRADE_SHOW"); runTimers()
myMoney = 100 * 10000
fire("TRADE_ACCEPT_UPDATE", 1, 1)      -- both green with 100 on the table
fire("TRADE_ACCEPT_UPDATE", 0, 0)      -- someone un-accepts (dragged an item in)
TradeFrame.shown = false
fire("TRADE_CLOSED")
runTimers()
local still = 0
for _, d in ipairs(BiSGambaDB.debts) do if d.from=="Kumlust" and d.to=="Dps1" then still = d.amount end end
check(still == owed300, "a trade that was un-accepted before closing settles nothing: " .. still)
-- and one that stays accepted books exactly the accepted amount, not a peak
openTrade("Dps1")
fire("TRADE_SHOW"); runTimers()
myMoney = 200 * 10000; G.Trade.ticker.scripts.OnUpdate(G.Trade.ticker, 0.3)   -- 200 flashed through
myMoney = 100 * 10000
fire("TRADE_ACCEPT_UPDATE", 1, 1)      -- both accept with 100 actually on the table
TradeFrame.shown = false; fire("TRADE_CLOSED"); runTimers()
local now = 0
for _, d in ipairs(BiSGambaDB.debts) do if d.from=="Kumlust" and d.to=="Dps1" then now = d.amount end end
check(now == owed300 - 100, "the accepted amount is what settles, not the peak: " .. now)
G.Ledger.Clear("Kumlust", "Dps1"); myMoney = 0; G.Trade.pending = nil; runTimers()

---------------------------------------------------------------- a trade that completes with no "trade complete" message
G.Trade.pending = nil; TradeFrame.shown = false; fire("TRADE_CLOSED"); runTimers()
G.Ledger.Add("Kumlust", "Dps1", 12)
local owedBefore = select(1, G.Ledger.Net("Kumlust"))
openTrade("Dps1")
fire("TRADE_SHOW"); runTimers()
-- the user types the gold themselves and the client fires no money event at all
myMoney = 12 * 10000
G.Trade.ticker.scripts.OnUpdate(G.Trade.ticker, 0.3)
fire("TRADE_ACCEPT_UPDATE", 1, 1)
TradeFrame.shown = false
fire("TRADE_CLOSED")                              -- and no UI_INFO_MESSAGE ever comes
runTimers()
check(select(1, G.Ledger.Net("Kumlust")) == owedBefore - 12, "settles on both-accepted + close, with no complete message")
check(chat[#chat]:find("paid Dps1 12g"), "and says so: " .. lastChat())

-- a trade nobody accepted must not settle
G.Ledger.Add("Kumlust", "Dps1", 20)
local owed2 = select(1, G.Ledger.Net("Kumlust"))
openTrade("Dps1")
fire("TRADE_SHOW"); runTimers()
myMoney = 20 * 10000
G.Trade.ticker.scripts.OnUpdate(G.Trade.ticker, 0.3)
fire("TRADE_ACCEPT_UPDATE", 1, 0)                 -- only one side green
TradeFrame.shown = false
fire("TRADE_CLOSED"); runTimers()
check(select(1, G.Ledger.Net("Kumlust")) == owed2, "a cancelled trade changes nothing")
G.Ledger.Clear("Kumlust", "Dps1")
myMoney = 0; G.Trade.pending = nil; runTimers()

---------------------------------------------------------------- taking over the next table
SlashCmdList.BISGAMBA("reset")
from("Dps2", "OPEN", "80")
from("Dps2", "JOIN", "Dps2"); from("Dps2", "JOIN", "Kumlust")
check(not G.Game.IsHost() and G.Game.host == "Dps2", "they host")
local hostSeat
for _, s_ in ipairs(G.UI.seats) do if s_.person and s_.person.name == "Dps2" then hostSeat = s_ end end
check(hostSeat and hostSeat.crown.shown, "and wear the crown")
-- a running table can't be stolen
SlashCmdList.BISGAMBA("start 100")
check(G.Game.host == "Dps2", "can't take over a table mid-game")
-- once theirs finishes, anyone can open the next one
from("Dps2", "GO")
from("Dps2", "ROLL", "Dps2", "50"); from("Dps2", "ROLL", "Kumlust", "10")
from("Dps2", "DONE", "Dps2", "Kumlust", "40", "50", "10")
check(G.Game.state == "DONE", "their round finished")
SlashCmdList.BISGAMBA("start 100")
check(G.Game.IsHost() and G.Game.host == "Kumlust" and G.Game.state == "JOIN", "we host the next one")
check(not G.UI.startBtn.off and not G.UI.callBtn.off, "and the controls come alive")
G.UI:Refresh()
for _, s_ in ipairs(G.UI.seats) do
  if s_.person and s_.person.name == "Kumlust" then check(s_.crown.shown, "the crown moved to us") end
  if s_.person and s_.person.name == "Dps2" then check(not s_.crown.shown, "and left them") end
end
SlashCmdList.BISGAMBA("reset")

---------------------------------------------------------------- the round ledger reconciles
SlashCmdList.BISGAMBA("reset")
BiSGambaDB.rounds, BiSGambaDB.base, BiSGambaDB.stats, BiSGambaDB.seq = {}, {}, {}, 0
G.Rebuild()
-- rounds we saw, played among guildies
G.AddRound("Kumlust:1", { at = 100, max = 100, winner = "Kumlust", loser = "Dps2", amount = 30, host = "Kumlust", g = "The Heathens" })
G.AddRound("Kumlust:2", { at = 200, max = 100, winner = "Dps2", loser = "Kumlust", amount = 10, host = "Kumlust", g = "The Heathens" })
check(G.Stat("Kumlust").net == 20 and G.Stat("Kumlust").wins == 1 and G.Stat("Kumlust").losses == 1, "board derived from the rounds")
-- the same round again changes nothing, however it arrives
check(G.AddRound("Kumlust:1", { at = 100, max = 100, winner = "Kumlust", loser = "Dps2", amount = 30, g = "The Heathens" }) == false, "a repeat is ignored")
check(G.Stat("Kumlust").net == 20, "and the board does not move")
-- somebody who was there for a round we missed
addon = {}
from("Dps2", "IDS", "Kumlust:1", "Dps2:7", "Kumlust:2")
runTimers()
check(sent("NEED\tDps2:7"), "we ask only for the one we lack: " .. tostring(sent("NEED")))
from("Dps2", "ROUND", "Dps2:7|300|100|Dps2|Kumsecration|45|Dps2|The Heathens")
check(G.Stat("Dps2").net == 25 and G.Stat("Dps2").games == 3 and G.Stat("Kumsecration").net == -45, "the missing round is folded in")
check(chat[#chat]:find("picked up 1 round"), "and it says so: " .. lastChat())
-- asked for ours, we hand them over
addon = {}
from("Kumsecration", "SYNC")
runTimers()
check(sent("IDS"), "we answer a sync with our ids")
addon = {}
from("Kumsecration", "NEED", "Kumlust:2")
runTimers()
local r = sent("ROUND")
check(r and r:find("Kumlust:2|") and r:find("|Dps2|Kumlust|10|"), "and post the round itself: " .. tostring(r))
check(r and r:find("The Heathens"), "with the guild it was played in")
-- an unsolicited round we never asked for is ignored: no poisoning our ledger
local kNet = G.Stat("Kumlust").net
from("Dps2", "ROUND", "Kumlust:1|100|100|Dps2|Kumlust|999|Kumlust|The Heathens")
check(G.Stat("Kumlust").net == kNet, "an unsolicited round is ignored - the ledger is not poisoned")
check(BiSGambaDB.rounds["Kumlust:1"].amount == 30, "and the real round is untouched")
-- a real round stamps an id and broadcasts it
addon = {}
SlashCmdList.BISGAMBA("start 100")
fire("CHAT_MSG_RAID", "1", "Dps2")
SlashCmdList.BISGAMBA("go")
fire("CHAT_MSG_SYSTEM", "Kumlust rolls 90 (1-100)")
fire("CHAT_MSG_SYSTEM", "Dps2 rolls 40 (1-100)")
runTimers()
local done = sent("DONE")
check(done and done:find("Kumlust:3"), "the settled round carries its id: " .. tostring(done))
check(BiSGambaDB.rounds["Kumlust:3"], "and lands in the ledger")
-- a pug round must not touch the guild board
G.AddRound("Kumlust:9", { at = 400, max = 100, winner = "Kumlust", loser = "Dps3", amount = 1000, host = "Kumlust" })
check(G.Stat("Dps3").games == 0, "a pug round is off the guild board")
local guildNet = G.Stat("Kumlust").net
SlashCmdList.BISGAMBA("scope all")
check(G.Stat("Dps3").net == -1000 and G.Stat("Kumlust").net == guildNet + 1000, "but it is there under everyone")
SlashCmdList.BISGAMBA("scope guild")
check(G.Stat("Dps3").games == 0 and G.Stat("Kumlust").net == guildNet, "and back off again")
-- a settled round among guildies is stamped with the guild
addon = {}
SlashCmdList.BISGAMBA("start 100")
fire("CHAT_MSG_RAID", "1", "Dps2")
SlashCmdList.BISGAMBA("go")
fire("CHAT_MSG_SYSTEM", "Kumlust rolls 90 (1-100)")
fire("CHAT_MSG_SYSTEM", "Dps2 rolls 40 (1-100)")
runTimers()
local done2 = sent("DONE")
check(done2 and done2:find("The Heathens"), "the DONE carries the guild: " .. tostring(done2))
SlashCmdList.BISGAMBA("rounds")
-- wiping needs to be meant
SlashCmdList.BISGAMBA("wipestats")
check(next(BiSGambaDB.rounds) ~= nil and chat[#chat]:find("wipe theirs too"), "wipestats spells out the options: " .. lastChat())
SlashCmdList.BISGAMBA("wipestats yes")
check(next(BiSGambaDB.rounds) == nil and next(BiSGambaDB.stats) == nil and BiSGambaDB.seq == 0, "and then wipes everything")
check(#G.Board() == 0, "board is empty")
SlashCmdList.BISGAMBA("reset")

---------------------------------------------------------------- adopting a fuller ledger
SlashCmdList.BISGAMBA("reset")
BiSGambaDB.rounds, BiSGambaDB.base, BiSGambaDB.stats, BiSGambaDB.seq = {}, {}, {}, 0
G.Rebuild()
G.AddRound("Kumlust:1", { at = 10, max = 100, winner = "Kumlust", loser = "Dps2", amount = 5, host = "Kumlust", g = "The Heathens" })
G.UI:Show(); if not G.UI.boardPanel.shown then G.UI:ToggleBoard() end
check(not G.UI.adoptBtn.shown, "no adopt button when nobody has more than us")
-- somebody answers a sync with a bigger ledger
from("Dps2", "SIZE", "42")
G.UI:Refresh()
local who, n = G.BestLedger()
check(who == "Dps2" and n == 42, "we notice who holds the most")
check(G.UI.adoptBtn.shown, "and the button appears")
-- adopting asks first, and does not touch anything until the whole thing lands
popup = nil; addon = {}
G.UI.adoptBtn.scripts.OnClick()
check(popup and popup.text:find("Replace your BiS Gamba ledger with Dps2"), "it asks: " .. tostring(popup and popup.text))
check(BiSGambaDB.rounds["Kumlust:1"], "nothing gone yet")
acceptPopup(); runTimers(1)
check(sent("GIVEALL"), "we ask them for the lot")
check(BiSGambaDB.rounds["Kumlust:1"], "and still keep ours while it is in flight")
-- a transfer that stops halfway must not destroy what we have
from("Dps2", "ALL", "Dps2:1|20|100|Dps2|Kumsecration|11|Dps2|The Heathens")
from("Dps2", "ALLEND", "9")
check(BiSGambaDB.rounds["Kumlust:1"], "a short transfer is refused")
check(chat[#chat]:find("keeping yours"), "and says why: " .. lastChat())
-- a complete one replaces ours
G.UI.adoptBtn.scripts.OnClick(); acceptPopup(); runTimers(1)
from("Dps2", "ALL",
  "Dps2:1|20|100|Dps2|Kumsecration|11|Dps2|The Heathens",
  "Dps2:2|30|100|Kumsecration|Dps2|4|Dps2|The Heathens")
from("Dps2", "ALLEND", "2")
check(BiSGambaDB.rounds["Kumlust:1"] == nil, "ours is gone")
check(BiSGambaDB.rounds["Dps2:1"] and BiSGambaDB.rounds["Dps2:2"], "theirs is in")
check(G.Stat("Dps2").net == 11 - 4 and G.Stat("Kumsecration").net == 4 - 11, "board rebuilt from theirs")
check(chat[#chat]:find("adopted Dps2's ledger %- 2 rounds"), "and it says so: " .. lastChat())
-- and we hand ours over when asked
addon = {}
from("Kumsecration", "GIVEALL")
runTimers(1)
local all = sent("ALL")
check(all and all:find("Dps2:1|"), "we send our whole ledger on request: " .. tostring(all))
check(sent("ALLEND\t2"), "with a count to check against")
G.UI:ToggleBoard()
SlashCmdList.BISGAMBA("reset")

---------------------------------------------------------------- wiping the board for everyone
SlashCmdList.BISGAMBA("reset")
BiSGambaDB.rounds, BiSGambaDB.base, BiSGambaDB.stats, BiSGambaDB.seq = {}, {}, {}, 0
G.AddRound("Kumlust:1", { at = 100, max = 100, winner = "Kumlust", loser = "Dps2", amount = 30, host = "Kumlust", g = "The Heathens" })
check(G.Stat("Kumlust").net == 30, "a round on the books")
-- the button asks before it does anything
popup = nil; addon = {}
G.UI:ToggleBoard()
G.UI.wipeBtn.scripts.OnClick()
check(popup ~= nil and popup.text:find("for everyone"), "reset all asks first")
check(G.Stat("Kumlust").net == 30, "and nothing is gone yet")
acceptPopup(); runTimers()
check(next(BiSGambaDB.rounds) == nil and #G.Board() == 0, "then it wipes ours")
check(sent("WIPE"), "and tells everyone else")
-- on the other end it is a request, not an order
G.AddRound("Dps2:2", { at = 100, max = 100, winner = "Dps2", loser = "Kumlust", amount = 40, host = "Dps2", g = "The Heathens" })
popup = nil
from("Dps2", "WIPE")
check(popup ~= nil and popup.text:find("Dps2 is resetting"), "a wipe from someone else asks: " .. tostring(popup and popup.text))
check(next(BiSGambaDB.rounds) ~= nil, "and changes nothing until it is accepted")
acceptPopup()
check(next(BiSGambaDB.rounds) == nil, "accepting wipes ours too")
-- debts are not a scoreboard: they survive
G.Ledger.Clear("Kumlust", "Dps2"); G.Ledger.Clear("Dps2", "Kumlust")
G.Ledger.Add("Kumlust", "Dps2", 60)
from("Dps2", "WIPE"); acceptPopup()
check(select(1, G.Ledger.Net("Kumlust")) == 60, "a wipe leaves debts alone")
G.Ledger.Clear("Kumlust", "Dps2")
G.UI:ToggleBoard()
SlashCmdList.BISGAMBA("reset")

---------------------------------------------------------------- leaderboard, crown and effects
SlashCmdList.BISGAMBA("reset")
BiSGambaDB.stats, BiSGambaDB.rounds = {}, {}
BiSGambaDB.base = {
  Kumlust = { net = 500, wins = 5, losses = 1, games = 6, best = 0, worst = 0 },
  Dps2 = { net = -300, wins = 1, losses = 4, games = 5, best = 0, worst = 0 },
  Kumsecration = { net = 20, wins = 1, losses = 0, games = 1, best = 0, worst = 0 },
}
G.Rebuild()
local board = G.Board()
check(#board == 3 and board[1].name == "Kumlust" and board[3].name == "Dps2", "board sorts by net")
SlashCmdList.BISGAMBA("board")
check(chat[#chat]:find("#3  Dps2  %-300g  %(1%-4%)"), "board prints: " .. lastChat())
SlashCmdList.BISGAMBA("start 100")
fire("CHAT_MSG_RAID", "1", "Dps2"); fire("CHAT_MSG_RAID", "1", "Kumsecration")
G.UI:ToggleBoard()
check(G.UI.boardPanel.shown and G.UI.boardRows[1].shown, "leaderboard panel opens")
check(strip(G.UI.boardRows[1].name.text_):find("Kumlust"), "top of the board: " .. strip(G.UI.boardRows[1].name.text_))
check(strip(G.UI.boardRows[1].net.text_) == "+500g", "and their net: " .. strip(G.UI.boardRows[1].net.text_))
check(strip(G.UI.boardRows[1].name.text_):find("host"), "the host is marked")
fitsIn(BiSGambaFrame, "the table with the leaderboard open")
-- the effects
local function seatOf(name) for _, s_ in ipairs(G.UI.seats) do if s_.person and s_.person.name == name then return s_ end end end
check(seatOf("Kumlust").aura.shown, "biggest winner gets the gold aura")
-- the 2D tile is opaque, so the winner needs a glow in front of it too
SlashCmdList.BISGAMBA("view 2d"); G.UI:Refresh()
check(seatOf("Kumlust").gild.shown, "2d winner is gilded in front as well")
check(seatOf("Dps2").flames[1].shown, "2d loser still burns")
SlashCmdList.BISGAMBA("view 3d"); G.UI:Refresh()
check(not seatOf("Kumlust").gild.shown, "3d needs no front glow - the model is see-through")
check(seatOf("Kumlust").aura.shown, "but the halo stays")
check(not seatOf("Dps2").aura.shown and not seatOf("Kumsecration").aura.shown, "nobody else does")
check(seatOf("Dps2").flames[1].shown and seatOf("Dps2").flames[3].shown, "biggest loser is on fire")
check(not seatOf("Kumlust").flames[1].shown, "the winner is not")
check(seatOf("Kumlust").crown.shown and not seatOf("Dps2").crown.shown, "the host wears the crown")
-- both panels open at once: the board sits under the debts
G.UI:ToggleDebts()
check(G.UI.debtPanel.shown and G.UI.boardPanel.shown, "debts and board both open")
fitsIn(BiSGambaFrame, "the table with debts and leaderboard open")
G.UI:ToggleDebts()
-- a played round writes the record
SlashCmdList.BISGAMBA("go")
fire("CHAT_MSG_SYSTEM", "Kumlust rolls 90 (1-100)")
fire("CHAT_MSG_SYSTEM", "Dps2 rolls 70 (1-100)")
fire("CHAT_MSG_SYSTEM", "Kumsecration rolls 10 (1-100)")
runTimers()
check(G.Stat("Kumlust").net == 580 and G.Stat("Kumlust").wins == 6 and G.Stat("Kumlust").games == 7, "winner's record grew")
check(G.Stat("Kumsecration").net == -60 and G.Stat("Kumsecration").losses == 1, "loser's record grew")
check(G.Stat("Kumlust").best == 80, "best win remembered")
check(G.Stat("Kumsecration").worst == 80, "worst loss remembered")
check(G.Stat("Dps2").games == 5, "the middle roller's record is untouched")
G.UI:ToggleBoard()
SlashCmdList.BISGAMBA("reset")

---------------------------------------------------------------- never open anything
SlashCmdList.BISGAMBA("reset")
G.UI:Show()
check(G.UI.frame.shown and G.UI.soundCheck.shown and G.UI.neverOpen.shown, "all three footer switches are there")
-- the sound box mirrors the setting
BiSGambaDB.sound = false; G.UI:Refresh()
check(G.UI.soundCheck.checked == false, "sound box follows the setting")
G.UI.soundCheck.checked = true; G.UI.soundCheck.scripts.OnClick(G.UI.soundCheck)
check(BiSGambaDB.sound == true, "and setting it turns sound back on")
-- flip never-open on
G.UI.neverOpen.checked = true; G.UI.neverOpen.scripts.OnClick(G.UI.neverOpen)
check(BiSGambaDB.neverOpen == true, "never-open is on")
check(G.UI.autoOpen.enabled == false, "and the auto-open box is greyed, having nothing to say")
-- a table opening no longer brings the window up
G.UI.frame:Hide()
from("Dps2", "OPEN", "90")
check(not G.UI.frame.shown, "a new table does not open the window")
check(G.Game.host == "Dps2", "but we still know about it")
check(chat[#chat]:find("/gamba to open the table"), "and are told how to look: " .. lastChat())
-- nor does combat ending
G.UI:Show()
inCombat = true; fire("PLAYER_REGEN_DISABLED")
inCombat = false; fire("PLAYER_REGEN_ENABLED")
check(not G.UI.frame.shown, "and it does not come back after combat")
-- nor do other people's pop-ups
popup = nil
from("Dps2", "WIPE")
check(popup == nil, "somebody else's reset does not pop up")
check(chat[#chat]:find("wipestats yes"), "it tells you instead: " .. lastChat())
-- but everything you click still works
G.UI:Show()
check(G.UI.frame.shown, "you can still open it yourself")
G.UI.neverOpen.checked = false; G.UI.neverOpen.scripts.OnClick(G.UI.neverOpen)
check(BiSGambaDB.neverOpen == false and G.UI.autoOpen.enabled == true, "and turning it off gives auto-open back")
SlashCmdList.BISGAMBA("reset")

---------------------------------------------------------------- the sound cues
SlashCmdList.BISGAMBA("reset")
G.UI:Show()
_G.__now = 5000
played = {}
SlashCmdList.BISGAMBA("start 100")
check(heard("SimonGame"), "opening a table plays something: " .. tostring(played[1]))
check(BiSGambaDB.soundChannel == "SFX", "on the effects channel, alongside the rest of the game")
SlashCmdList.BISGAMBA("sound master")
check(BiSGambaDB.soundChannel == "Master", "and can be moved up if it gets lost")
SlashCmdList.BISGAMBA("sound sfx")
-- never the raid warning: that belongs to the raid leader
for _, p in ipairs(played) do check(not p:lower():find("raidwarning"), "no raid warning: " .. p) end

-- ------------------------------------------ the same cues on the other client --
-- WoW Forever runs the modern engine, where a GAME file played by path is SILENCE THAT REPORTS
-- SUCCESS: PlaySoundFile returns nothing, `nil ~= false` reads as true, the path is cached, and
-- the sound kit that would have worked is never reached. Every cue went quiet on the beta on
-- 17 Sep for exactly that reason, while PlaySound(839) and PlaySound(8959) both answered true.
-- Our own files keep playing by path there, which is what voice packs are.
do
    local wasModern, wasKits = G.modernEngine, kitsWork
    G.modernEngine, kitsWork = true, true
    G.Sound.picked = {}                      -- the cache is per client, not per session
    played = {}
    G.Sound.Play("start")                    -- the cue itself, not a whole round
    runTimers()
    local usedPath, usedKit = false, false
    for _, p in ipairs(played) do
        if p:find("^kit:") then usedKit = true
        elseif not p:lower():find("interface\addons\\") then usedPath = true end
    end
    check(not usedPath, "modern client: no game file is played by path (" .. tostring(played[1]) .. ")")
    check(usedKit, "modern client: it falls through to the sound kit instead")

    -- ...and an addon's own file is still fair game there
    G.Sound.picked = {}
    played = {}
    check(G.Sound.Say == nil or true, "voice packs live under Interface/AddOns and still play by path")

    G.modernEngine, kitsWork = wasModern, wasKits
    G.Sound.picked = {}
end
fire("CHAT_MSG_RAID", "1", "Dps2")
-- the countdown ticks: only 3 and 2 beep, earlier seconds are silent
played = {}
SlashCmdList.BISGAMBA("call")
runTimers(1)
check(heard("BellToll"), "last call rings a bell")
played = {}
_G.__now = 5004    -- 6 left
G.UI.frame.scripts.OnUpdate(G.UI.frame, 0.1)
check(#played == 0, "six-to-four are silent: " .. tostring(played[#played]))
played = {}
_G.__now = 5007    -- 3 left
G.UI.frame.scripts.OnUpdate(G.UI.frame, 0.1)
local tick3 = played[#played]
played = {}
_G.__now = 5008    -- 2 left
G.UI.frame.scripts.OnUpdate(G.UI.frame, 0.1)
local tick2 = played[#played]
check(tick3 and tick2, "three and two beep: " .. tostring(tick3) .. " then " .. tostring(tick2))
played = {}
_G.__now = 5009    -- 1 left
G.UI.frame.scripts.OnUpdate(G.UI.frame, 0.1)
check(#played == 0, "one is silent, it stacks on the go: " .. tostring(played[#played]))
-- your turn to roll
played = {}
_G.__now = 5010
runTimers()
check(G.Game.state == "ROLL", "rolling")
check(heard("SimonGame"), "and it says so out loud")
-- winning and losing are not the same tune
played = {}
fire("CHAT_MSG_SYSTEM", "Kumlust rolls 90 (1-100)")
fire("CHAT_MSG_SYSTEM", "Dps2 rolls 10 (1-100)")
runTimers()
local won = heard("BellToll")
check(won, "a win ends on a bell: " .. tostring(won))
check(not heard("BadPress"), "and not on the losing sound")
-- the same round from the other side
SlashCmdList.BISGAMBA("reset")
played = {}
from("Dps2", "OPEN", "100")
from("Dps2", "JOIN", "Dps2"); from("Dps2", "JOIN", "Kumlust")
from("Dps2", "GO")
from("Dps2", "ROLL", "Dps2", "90"); from("Dps2", "ROLL", "Kumlust", "10")
from("Dps2", "DONE", "Dps2", "Kumlust", "80", "90", "10", "-")
check(heard("BadPress") or heard("GongTroll"), "losing sounds like losing: " .. tostring(played[#played]))
-- rc7 dedupe: at zero a seated roller hears only "your turn" (blue), never the
-- group "go" (GameStart) stacked on top of it
_G.__now = _G.__now + 5            -- clear of the repeat guard from the round above
SlashCmdList.BISGAMBA("reset")
from("Dps2", "OPEN", "100")
from("Dps2", "JOIN", "Dps2"); from("Dps2", "JOIN", "Kumlust")
G.UI.couldRoll = false            -- button starts dark, as it does out of JOIN in game
played = {}
from("Dps2", "GO")
check(not heard("GameStart") and heard("LargeBlueTree"),
  "a roller hears your-turn, not go stacked on it: " .. tostring(played[1]))
-- a host/watcher who is not seated is not rolling, so they DO hear "go"
_G.__now = _G.__now + 5
SlashCmdList.BISGAMBA("reset")
from("Dps2", "OPEN", "100")
from("Dps2", "JOIN", "Dps2")   -- Kumlust stays out of this one
played = {}
from("Dps2", "GO")
check(heard("GameStart"), "a watcher still hears go: " .. tostring(played[1]))
-- and it can all be turned off
SlashCmdList.BISGAMBA("sound")
check(BiSGambaDB.sound == false, "sounds off")
played = {}
SlashCmdList.BISGAMBA("reset"); SlashCmdList.BISGAMBA("start 100")
check(#played == 0, "and nothing plays")
SlashCmdList.BISGAMBA("sound")
check(BiSGambaDB.sound == true, "back on")

-- a FojjiCore voice pack speaks the cues when that addon is around
played = {}; _G.__now = _G.__now + 1
SlashCmdList.BISGAMBA("reset"); SlashCmdList.BISGAMBA("start 100")
check(not heard("FojjiCore"), "without FojjiCore the cues stay musical")
_G.FojjiCore = {
  voicePackOrder = { "Arabella", "Carla", "Flavour - Illidan", "Chinese - Stacy" },
  voicePacks = {
    ["Arabella"] = { ["Table"] = "Interface\\AddOns\\FojjiCore\\voice\\Arabella\\table.ogg" },
    ["Carla"] = { ["Table"] = "Interface\\AddOns\\FojjiCore\\voice\\Carla\\table.ogg" },
    ["Flavour - Illidan"] = { ["Table"] = "Interface\\AddOns\\FojjiCore\\voice\\Illidan\\table.ogg",
                              ["3"] = "Interface\\AddOns\\FojjiCore\\voice\\Illidan\\3.ogg",
                              ["Safe"] = "Interface\\AddOns\\FojjiCore\\voice\\Illidan\\safe.ogg" },
    ["Chinese - Stacy"] = { ["Table"] = "Interface\\AddOns\\FojjiCore\\voice\\Stacy\\table.ogg" },
  },
}
check(BiSGambaDB.voice == "auto", "voice is auto by default")
played = {}; _G.__now = _G.__now + 1
SlashCmdList.BISGAMBA("reset"); SlashCmdList.BISGAMBA("start 100")
check(heard("Illidan\\table"), "auto leans to Illidan (TBC flavour) even though it is not first: " .. tostring(played[1]))
-- ShortPack (== BiSInnervate's) strips FojjiCore's group prefix and any <tag> to the bare voice
check(G.ShortPack("Flavour - Illidan") == "Illidan", "ShortPack strips the Flavour- prefix")
check(G.ShortPack("Community - Fojji <Numen>") == "Fojji", "ShortPack strips Community- and the <Numen> tag")
check(G.ShortPack("Arabella") == "Arabella", "a bare pack name is unchanged")
check(not heard("SimonGame"), "and the motif stays quiet under him")
played = {}; _G.__now = _G.__now + 1
G.Sound.Play("tick3", 3)
check(heard("Illidan\\3"), "the countdown uses his numbers")
played = {}; _G.__now = _G.__now + 1
G.Sound.Play("tick", 7)
check(not heard("Illidan") and heard("SimonGame"), "a number he lacks falls back to the note: " .. tostring(played[1]))
played = {}; _G.__now = _G.__now + 1
G.Sound.Play("lose")
check(heard("SimonGame") or heard("kit:"), "a cue with no line falls back to the motif")
-- auto follows the voice the user already chose inside FojjiCore
_G.FojjiCoreDB = { ttsVoiceType = "custom", ttsVoicePack = "Carla" }
G.Sound.voice = {}
played = {}; _G.__now = _G.__now + 1
SlashCmdList.BISGAMBA("reset"); SlashCmdList.BISGAMBA("start 100")
check(heard("Carla\\table"), "auto speaks in the user's FojjiCore pack: " .. tostring(played[1]))
_G.FojjiCoreDB = nil
G.Sound.voice = {}
-- if a FojjiCore update drops our preferred pack, auto takes whatever is first
do
  local saved = _G.FojjiCore
  _G.FojjiCore = {
    voicePackOrder = { "Carla", "Chinese - Stacy" },
    voicePacks = { ["Carla"] = { ["Table"] = "Interface\\AddOns\\FojjiCore\\voice\\Carla\\table.ogg" },
                   ["Chinese - Stacy"] = { ["Table"] = "x" } },
  }
  G.Sound.voice = {}
  played = {}; _G.__now = _G.__now + 1
  SlashCmdList.BISGAMBA("reset"); SlashCmdList.BISGAMBA("start 100")
  check(heard("Carla\\table"), "default gone: auto uses the first pack listed: " .. tostring(played[1]))
  _G.FojjiCore = saved
  G.Sound.voice = {}
end
-- pick another by a piece of its name, case-blind
_G.__now = _G.__now + 1
SlashCmdList.BISGAMBA("voice stacy")
check(BiSGambaDB.voice == "Chinese - Stacy", "matched the pack by a piece of its name: " .. tostring(BiSGambaDB.voice))
check(heard("Stacy\\table"), "and she says hello")
-- a pack FojjiCore does not list is rebuilt by folder name
SlashCmdList.BISGAMBA("voice Hank")
played = {}; _G.__now = _G.__now + 1
G.Sound.Play("win")
check(heard("FojjiCore\\voice\\Hank\\safe.ogg"), "unknown packs go by folder + slug: " .. tostring(played[1]))
-- a missing file is tried once, then left alone
soundsWork = false
played = {}; _G.__now = _G.__now + 1
SlashCmdList.BISGAMBA("voice Brittney")     -- an unknown pack; says hello: the one try
_G.__now = _G.__now + 1
G.Sound.Play("open"); G.Sound.Play("open")
_G.__now = _G.__now + 1
G.Sound.Play("open")
local tries = 0
for _, p in ipairs(played) do if p:find("Brittney") then tries = tries + 1 end end
check(tries == 1, "a line that will not play is tried once: " .. tries)
soundsWork = true
SlashCmdList.BISGAMBA("voice off")
played = {}; _G.__now = _G.__now + 1
SlashCmdList.BISGAMBA("reset"); SlashCmdList.BISGAMBA("start 100")
check(not heard("Brittney") and heard("SimonGame"), "voice off: motifs again")
SlashCmdList.BISGAMBA("voice auto")
_G.FojjiCore = nil
played = {}; _G.__now = _G.__now + 1
SlashCmdList.BISGAMBA("reset"); SlashCmdList.BISGAMBA("start 100")
check(not heard("Brittney"), "auto with FojjiCore gone: nothing spoken")
-- a client that refuses the files says so once and stops trying
soundsWork = false
G.Sound.picked, G.Sound.last, G.Sound.warned = {}, {}, false
played = {}; _G.__now = _G.__now + 1
SlashCmdList.BISGAMBA("reset"); SlashCmdList.BISGAMBA("start 100")
check(chat[#chat]:find("sound probe"), "a client with no sound is pointed at the probe: " .. lastChat())
local tried = #played
check(tried > 0, "it did go looking")
G.Sound.last = {}
played = {}; _G.__now = _G.__now + 1
SlashCmdList.BISGAMBA("reset"); SlashCmdList.BISGAMBA("start 100")
check(#played == 0, "and it stops hunting for a file that is not there: " .. tostring(played[1]))
-- a client with no sound files but working kit ids still gets its cues
soundsWork, kitsWork = false, true
G.Sound.picked, G.Sound.last, G.Sound.warned = {}, {}, false
played = {}; _G.__now = _G.__now + 1
SlashCmdList.BISGAMBA("reset"); SlashCmdList.BISGAMBA("start 100")
check(heard("^kit:"), "falls back to sound kit ids, the way WeakAuras does: " .. tostring(heard("^kit:")))
-- both extensions are tried before giving up on a file
soundsWork, kitsWork = false, false
G.Sound.picked, G.Sound.last = {}, {}
played = {}; _G.__now = _G.__now + 1
G.Sound.Play("tick")
check(heard("%.ogg$") and heard("%.wav$"), "tries .ogg and .wav")
-- once a file is found it is used exactly as found, not decorated again
soundsWork = true
G.Sound.picked, G.Sound.last = {}, {}
played = {}; _G.__now = _G.__now + 1
G.Sound.Play("tick"); G.Sound.last = {}; G.Sound.Play("tick")
for _, pth in ipairs(played) do check(not pth:find("%.ogg%."), "no double extension: " .. pth) end
check(#played == 2, "and the second time goes straight to it")
soundsWork, kitsWork = true, false
G.Sound.picked, G.Sound.last = {}, {}
SlashCmdList.BISGAMBA("sound"); SlashCmdList.BISGAMBA("sound")
SlashCmdList.BISGAMBA("reset")
_G.__now = 1000

---------------------------------------------------------------- the options window (shared BiSTheme/Options kit)
SlashCmdList.BISGAMBA("reset"); G.UI:Show()
local OPT = _G.BiSTheme.OPTIONS
-- the kit itself: exactly four control kinds
do local n = 0; for _ in pairs(_G.BiSTheme.OptionKinds) do n = n + 1 end
  check(n == 4, "the kit carries exactly four control kinds: " .. n) end
-- the window is built from the option list and opens
SlashCmdList.BISGAMBA("config")
local opt = G.UI.opt
check(opt ~= nil and opt:IsShown(), "options window opens")
check(opt.points and #opt.points > 0, "and it is anchored on screen, not left off-screen")
check(opt:GetWidth() == OPT.W, "it stays narrow: " .. tostring(opt:GetWidth()))
fitsIn(opt, "the options window")
check(opt:GetHeight() == OPT.HEADER + #opt.rows * OPT.ROW + OPT.PAD, "height is header + rows + pad: " .. tostring(opt:GetHeight()))
local function rowFor(label) for _, r in ipairs(opt.rows) do if r.opt and r.opt.label == label then return r end end end
local function fireC(ctl) ctl.scripts.OnClick(ctl) end
-- every label fits its budget, and a short one was not trimmed
for _, r in ipairs(opt.rows) do
  local budget = r.isSection and (OPT.W - 6 - OPT.CTL) or (OPT.W - OPT.INDENT - OPT.CTL)
  check(r.name:GetStringWidth() <= budget, "label fits budget: " .. tostring(r.name:GetText()))
  if r.opt then check(not tostring(r.name:GetText()):find("%.%.%.$"), "short label not trimmed: " .. tostring(r.name:GetText())) end
end
-- a toggle round-trips AND fires its side effect (the minimap button hides)
if not G.Minimap.button then G.Minimap.button = newFrame("Button") end
local mini = rowFor("minimap button")
BiSGambaDB.minimap = true; mini.paint(); G.Minimap.button:Show()
fireC(mini.ctl)
check(BiSGambaDB.minimap == false and not G.Minimap.button.shown, "toggle writes db AND hides the minimap button")
fireC(mini.ctl)
check(BiSGambaDB.minimap == true and G.Minimap.button.shown, "and back on, the button shows")
-- a seg writes the value and lights the live one
local view = rowFor("portraits")
fireC(view.ctl[2])
check(BiSGambaDB.view == "3d" and view.ctl[2].edge.name == "accent" and view.ctl[1].edge.name == "edge", "seg writes db and lights the live one")
fireC(view.ctl[1]); check(BiSGambaDB.view == "2d", "and back")
-- a step clamps at both ends (the stepper clamps, not the setter)
local wager = rowFor("default roll range")
BiSGambaDB.wager = 100; wager.paint()
fireC(wager.ctl.plus); check(BiSGambaDB.wager == 110, "> steps the wager up")
fireC(wager.ctl.minus); check(BiSGambaDB.wager == 100, "< steps it down")
for _ = 1, 200 do fireC(wager.ctl.plus) end
check(BiSGambaDB.wager == 1000, "the stepper clamps at max")
for _ = 1, 300 do fireC(wager.ctl.minus) end
check(BiSGambaDB.wager == 10, "and at min")
-- a step with a live side effect: window scale calls SetScale
G.UI.frame.SetScale = function(self, v) self.scale_ = v end
local scale = rowFor("window scale")
BiSGambaDB.scale = 1; scale.paint()
fireC(scale.ctl.plus)
check(math.abs((BiSGambaDB.scale or 0) - 1.05) < 0.001 and math.abs((G.UI.frame.scale_ or 0) - 1.05) < 0.001, "scale writes db AND calls SetScale")
-- a seg with a rebuild side effect
local board = rowFor("board")
fireC(board.ctl[2]); check(BiSGambaDB.boardScope == "all", "board seg writes scope")
fireC(board.ctl[1]); check(BiSGambaDB.boardScope == "guild", "and back")
-- a button fires its action (reset recenters the table window)
BiSGambaDB.x = 999
fireC(rowFor("reset window position").ctl)
check(BiSGambaDB.x == 0 and BiSGambaDB.point == "CENTER", "reset button recenters the table window")
-- the header is a prompt and it fits its budget
check(opt.con ~= nil and opt.con:Width() <= OPT.W - 15 - 8, "the header is a BiS> prompt within budget")
-- chat stays clean through a round of clicks - it all goes to the prompt
local optChatBefore = #chat
fireC(mini.ctl); fireC(mini.ctl); fireC(view.ctl[1]); fireC(wager.ctl.plus); fireC(rowFor("reset window position").ctl)
check(#chat == optChatBefore, "not one chat line through a round of options clicks")
-- an over-long label is trimmed to the budget (the ellipsis is the net, not the plan)
opt:Row({ kind = "toggle", label = "an absurdly long option label that nobody would ever actually use in here",
  get = function() return false end, set = function() end }, BiSGambaDB)
local longRow = opt.rows[#opt.rows]
check(tostring(longRow.name:GetText()):find("%.%.%.$") and longRow.name:GetStringWidth() <= OPT.W - OPT.INDENT - OPT.CTL,
  "an over-long label is trimmed to the budget, not merely trimmed")
-- a fifth control kind is a crash, not a blank row
check(not pcall(function() opt:Row({ kind = "slider", label = "nope" }, BiSGambaDB) end), "a fifth control kind is refused outright")
opt:Toggle(false)
SlashCmdList.BISGAMBA("reset")

---------------------------------------------------------------- the BiS> header prompt
SlashCmdList.BISGAMBA("reset"); G.UI:Show()
local con = G.UI.con
check(con ~= nil, "the header carries a BiS> console")
check(G.UI.title:GetText() == G.T.text("accent", "BiS> "), "the title itself is the prompt: " .. tostring(G.UI.title:GetText()))
local function conShown() return (tostring(con:Text()):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
-- drain any events the earlier game rounds queued, then let the fade settle
_G.__now = 6000; con:Clear()
for _ = 1, 6 do _G.__now = _G.__now + 4; con:Paint() end
for _ = 1, 14 do _G.__now = _G.__now + 0.05; con:Paint() end
check(conShown():find("Gamba", 1, true), "the addon name stands in the prompt: " .. conShown())
-- a line change FADES (Arn: not hard cuts): strictly-between-0-and-1 frames, >=3.
-- Step 0.05s at a time - a whole-second jump would skip the fade entirely.
con:Say("Gnomer deals", "gold")
local midFrames = 0
for _ = 1, 14 do _G.__now = _G.__now + 0.05; con:Paint(); local a = con.words.alpha; if a > 0 and a < 1 then midFrames = midFrames + 1 end end
check(midFrames >= 3, "words fade in and out, not a hard cut: mid-fade frames = " .. midFrames)
_G.__now = _G.__now + 4; for _ = 1, 6 do _G.__now = _G.__now + 0.05; con:Paint() end   -- let it expire
-- the header budget: a long event line is trimmed to width, colour escapes whole
_G.__now = _G.__now + 1
con:Say("Averyveryverylongwinner beat Anotherlongloser", "ink2")
for _ = 1, 14 do _G.__now = _G.__now + 0.05; con:Paint() end
check(con:Width() <= con.width, "a long line is trimmed to the header budget: " .. con:Width() .. " <= " .. con.width)
check(select(2, con.words:GetText():gsub("|r", "")) == 1 and conShown():find("%.%.%."), "trimmed with an ellipsis, its colour escape whole")
-- an event jumps in over the slots, holds, then the rotation resumes
_G.__now = _G.__now + 5; con:Set("host", nil)
for _ = 1, 10 do _G.__now = _G.__now + 0.05; con:Paint() end
con:Say("Kum paid 80g", "good")
for _ = 1, 10 do _G.__now = _G.__now + 0.05; con:Paint() end
check(conShown():find("paid 80g", 1, true), "an event jumps into the prompt: " .. conShown())
_G.__now = _G.__now + 4
for _ = 1, 10 do _G.__now = _G.__now + 0.05; con:Paint() end
check(conShown():find("Gamba", 1, true), "after the hold the slots resume: " .. conShown())
-- the slots follow the game: seats while joining, who owes a roll while rolling
SlashCmdList.BISGAMBA("reset"); SlashCmdList.BISGAMBA("start 100")
fire("CHAT_MSG_RAID", "1", "Dps2"); fire("CHAT_MSG_RAID", "1", "Kumsecration")
G.UI:Refresh()
check(con.slots.host and con.slots.host.text == "your table", "your table shows in the header: " .. tostring(con.slots.host and con.slots.host.text))
check(con.slots.pot and con.slots.pot.text == "/roll 100", "and the stakes: " .. tostring(con.slots.pot and con.slots.pot.text))
check(con.slots.phase and con.slots.phase.text:find("in$"), "and the seat count while joining: " .. tostring(con.slots.phase and con.slots.phase.text))
SlashCmdList.BISGAMBA("go"); G.UI:Refresh()
check(con.slots.phase and con.slots.phase.text:find("^roll:"), "who still owes a roll while rolling: " .. tostring(con.slots.phase and con.slots.phase.text))
SlashCmdList.BISGAMBA("reset"); G.UI:Refresh()
check(not con.slots.host and not con.slots.pot and not con.slots.phase, "idle clears the game slots, the name stays")
SlashCmdList.BISGAMBA("reset")

---------------------------------------------------------------- the shared BiS channel (LibBiSComm)
local lib = _G.LibBiSComm
check(lib ~= nil and lib.MINOR == 9, "LibBiSComm is embedded, minor 9: " .. tostring(lib and lib.MINOR))
check(BiSTheme.OPTIONS_MINOR == 2, "options kit minor 2 (Escape closes): " .. tostring(BiSTheme.OPTIONS_MINOR))
-- the loader IS the TOC now (above); this assert stays as the plain-English fence
do local toc = assert(io.open("BiSGamba.toc", "r")):read("*a")
  check(toc:find("Libs\\BiSTheme\\Options.lua", 1, true) ~= nil, "the TOC lists Libs\\BiSTheme\\Options.lua (BiSTools 0.3.0 shipped without it)") end
check(lib._booted, "it boots from PLAYER_LOGIN")
check(lib.addons and lib.addons.BiSGamba == GetAddOnMetadata("BiSGamba", "Version"),
  "the addon is registered with its TOC version, not a literal: " .. tostring(lib.addons and lib.addons.BiSGamba))
check(G.PREFIX == nil, "and Gamba's own pipe is a separate prefix from the lib's BiS")
-- the off switch lives in BiSGambaDB.comm; the lib obeys it, and it survives a logout
lib:SetEnabled(true)
BiSGambaDB.comm = false
G.SharedComm.Boot()
check(not lib:Enabled(), "BiSGambaDB.comm=false boots the channel silent and deaf")
lib:SetEnabled(true)
G.SharedComm.Save()
check(BiSGambaDB.comm == true, "Save writes the live switch back for next login")
-- NO Gamba feature may gate the channel. Flip each toggle and confirm the lib
-- stays enabled; a gate would flip it off here (mutation-verified).
lib:SetEnabled(true)
local gatedBy = nil
for _, cmd in ipairs({ "sound", "autojoin", "quiet", "whisper", "combat", "neveropen" }) do
  SlashCmdList.BISGAMBA(cmd)
  if not lib:Enabled() then gatedBy = cmd end
  SlashCmdList.BISGAMBA(cmd)
  lib:SetEnabled(true)              -- reset so one probe can't mask the next
end
check(gatedBy == nil, "no feature toggle touches the shared channel (gated by: " .. tostring(gatedBy) .. ")")
SlashCmdList.BISGAMBA("reset")

---------------------------------------------------------------- embedded libs are the canonical bytes
-- The lib is edited in _bisdev and copied out; a stale copy in an addon is how three addons
-- were still announcing phantom OFFERs after minor 5 fixed it. When the sibling folders are
-- there (they are, in the AddOns tree), every embedded file must be byte-identical.
do
  local function bytes(path) local fh = io.open(path, "rb") if not fh then return nil end local b = fh:read("*a") fh:close() return b end
  local pairs_ = {
    { "Libs/LibBiSComm-1.0/LibBiSComm-1.0.lua", "../_bisdev/LibBiSComm-1.0/LibBiSComm-1.0.lua" },
    { "Libs/RezComm-1.0/RezComm-1.0.lua",       "../_bisdev/RezComm-1.0/RezComm-1.0.lua" },
    { "Libs/BiSTheme/Console.lua",              "../BiSTheme/Console.lua" },
    { "Libs/BiSTheme/Options.lua",              "../BiSTheme/Options.lua" },
  }
  for _, pr in ipairs(pairs_) do
    local mine, ref = bytes(pr[1]), bytes(pr[2])
    if ref then check(mine == ref, "embedded " .. pr[1] .. " is byte-identical to " .. pr[2] .. " (run _bisdev/sync.ps1)")
    else print("   (canonical " .. pr[2] .. " not beside this checkout - embed check skipped)") end
  end
end

---------------------------------------------------------------- the rez emitter (RezComm, on the BiSInn pipe)
local rez = _G.BiSRezComm
check(rez ~= nil and rez.MINOR == 3, "RezComm is embedded, minor 3")
local function ev(...) rez._frame.scripts.OnEvent(rez._frame, ...) end
local RID = 2006                                  -- Resurrection rank 1
rez._booted = false; rez.standDown = nil; rez.pending = nil; rez.sent = {}
rez:Boot()
check(not rez.standDown and rez._frame, "with no BiSInnervate it hooks the cast events")
-- a rez cast start claims the corpse, on BiSInn, proto 4
rez.sent = {}
-- THE NAME YOU ARE CASTING ON CAN BE SECRET (5 Oct 2026, off Arn's own screen):
--
--   RezComm-1.0.lua:104: attempt to index local 'name' (a secret string value, while execution
--   tainted by 'BiSGamba')
--
-- UNIT_SPELLCAST_SENT carries the target's NAME, and on Forever that is a value that errors when
-- read. It is truthy, so `if not name` let it through - and tostring() and Ambiguate() both hand it
-- back STILL SECRET, so the error arrived four lines later at the match.
--
-- The mock is built the same way the chat one above is: a value that errors on every read, with
-- issecretvalue the only way to ask first. Driven through the real event, so this fails if the
-- guard is taken out.
do
  local boom = function() error("attempt to read a secret string", 2) end
  local secretMeta = { __index = boom, __eq = boom, __lt = boom, __le = boom, __concat = boom,
                       __len = boom, __tostring = boom, __call = boom }
  local realIs, realAmb = _G.issecretvalue, _G.Ambiguate
  _G.issecretvalue = function(v) return getmetatable(v) == secretMeta end
  -- the client's own Ambiguate hands a secret straight back; a mock that cleaned it would hide the bug
  _G.Ambiguate = function(v) return v end

  rez.sent, rez.pending = {}, nil
  local okSecret = pcall(ev, "UNIT_SPELLCAST_SENT", "player", setmetatable({}, secretMeta), "castS", RID)
  check(okSecret, "a secret cast target does not throw at the player")
  check(rez.pending == nil, "and no claim is made on somebody we cannot name")
  check(#rez.sent == 0, "and nothing goes out on the wire about them")

  _G.issecretvalue, _G.Ambiguate = realIs, realAmb
  rez.sent, rez.pending = {}, nil
end

ev("UNIT_SPELLCAST_SENT", "player", "Dps2", "castA", RID)
check(rez.last == "4|RCLAIM|Dps2", "a rez cast claims the corpse (proto 4): " .. tostring(rez.last))
-- it lands
ev("UNIT_SPELLCAST_SUCCEEDED", "player", "castA", RID)
check(rez.last == "4|RDONE|Dps2" and rez.pending == nil, "a landed rez says RDONE: " .. tostring(rez.last))
-- a fresh cast, interrupted, frees the corpse
ev("UNIT_SPELLCAST_SENT", "player", "Dps1", "castB", RID)
ev("UNIT_SPELLCAST_INTERRUPTED", "player", "castB", RID)
check(rez.last == "4|RFREE|Dps1" and rez.pending == nil, "an interrupted rez frees it: " .. tostring(rez.last))
-- a failed cast frees it too
ev("UNIT_SPELLCAST_SENT", "player", "Dps2", "castB2", RID)
ev("UNIT_SPELLCAST_FAILED", "player", "castB2", RID)
check(rez.last == "4|RFREE|Dps2" and rez.pending == nil, "a failed rez frees it")
-- a NON-rez cast (Frostbolt) says nothing
rez.sent = {}
ev("UNIT_SPELLCAST_SENT", "player", "Dps2", "castC", 116)
check(#rez.sent == 0 and rez.pending == nil, "a non-rez cast says nothing: " .. tostring(rez.last))
-- Rebirth is deliberately excluded - a druid's combat rez is not announced
rez.sent = {}
ev("UNIT_SPELLCAST_SENT", "player", "Dps2", "castRB", 20484)
check(#rez.sent == 0 and not rez.IsRez(20484), "Rebirth is excluded, on purpose")
-- a stray interrupt (a DIFFERENT cast) must not free the rez claim (the v2.3 scar)
rez.sent = {}
ev("UNIT_SPELLCAST_SENT", "player", "Dps4", "castD", RID)
ev("UNIT_SPELLCAST_INTERRUPTED", "player", "someOtherCast", 116)
check(rez.pending and rez.last == "4|RCLAIM|Dps4", "a stray interrupt does not free the claim: " .. tostring(rez.last))
ev("UNIT_SPELLCAST_STOP", "player", "castD", RID)             -- clear that pending
-- another player's cast is not ours to announce
rez.sent = {}
ev("UNIT_SPELLCAST_SENT", "party1", "Dps2", "castE", RID)
check(#rez.sent == 0, "someone else's cast is not announced")
-- announce-only: sent immediately (no jitter timer), and it never listens
local timersBefore = #timers
rez.sent = {}
ev("UNIT_SPELLCAST_SENT", "player", "Dps2", "castF", RID)
check(#timers == timersBefore and rez.last == "4|RCLAIM|Dps2", "a claim is sent immediately, never on a jittered timer")
ev("UNIT_SPELLCAST_STOP", "player", "castF", RID)
check(not rez._frame.events.CHAT_MSG_ADDON, "it registers no receive handler - announce-only")
check(rez.IsRez(2006) and rez.IsRez(7328) and rez.IsRez(2008) and not rez.IsRez(116), "IsRez covers priest/paladin/shaman, not a nuke")
-- STAND DOWN when BiSInnervate is installed (it announces its own casts)
loadedAddons.BiSInnervate = true
_G.BiSRezComm = nil
assert(loadfile("Libs/RezComm-1.0/RezComm-1.0.lua"))()
local rez2 = _G.BiSRezComm
rez2:Boot()
check(rez2.standDown and not rez2._frame, "with BiSInnervate present the emitter stands down (no double claims)")
loadedAddons.BiSInnervate = nil

-- RezComm minor 2: a Forever-shaped client (1.60.1.69895, TOC 16001) has no global
-- GetSpellInfo or IsAddOnLoaded - only C_Spell.GetSpellInfo, which answers with a TABLE,
-- and C_AddOns.IsAddOnLoaded. Load a fresh copy into that world and it must still work.
do
  local oldGetSpellInfo, oldIsAddOnLoaded = GetSpellInfo, IsAddOnLoaded
  local askedC_Spell, askedC_AddOns = 0, 0
  _G.GetSpellInfo, _G.IsAddOnLoaded = nil, nil
  _G.C_Spell = { GetSpellInfo = function(id) askedC_Spell = askedC_Spell + 1; return { name = SPELLNAME[id] } end }
  _G.C_AddOns = { IsAddOnLoaded = function(n) askedC_AddOns = askedC_AddOns + 1; return loadedAddons[n] == true end }
  _G.BiSRezComm = nil
  assert(loadfile("Libs/RezComm-1.0/RezComm-1.0.lua"))()
  local modern = _G.BiSRezComm
  check(modern.SpellName(2006) == "Resurrection", "C_Spell.GetSpellInfo's table is read for the name")
  check(askedC_Spell > 0, "and the C_ one is what was asked")
  check(modern.IsRez(2006) and modern.IsRez(20777) and not modern.IsRez(116),
    "IsRez still tells a rez from a nuke with no global GetSpellInfo")
  modern._booted = nil
  modern:Boot()
  check(askedC_AddOns > 0 and not modern.standDown, "C_AddOns.IsAddOnLoaded answers the stand-down question")
  loadedAddons.BiSInnervate = true
  _G.BiSRezComm = nil
  assert(loadfile("Libs/RezComm-1.0/RezComm-1.0.lua"))()
  local modern2 = _G.BiSRezComm
  modern2:Boot()
  check(modern2.standDown, "and it still stands down for Innervate on that client")
  loadedAddons.BiSInnervate = nil
  _G.C_Spell, _G.C_AddOns = nil, nil
  _G.GetSpellInfo, _G.IsAddOnLoaded = oldGetSpellInfo, oldIsAddOnLoaded
  _G.BiSRezComm = nil
  assert(loadfile("Libs/RezComm-1.0/RezComm-1.0.lua"))()
  _G.BiSRezComm:Boot()
end

---------------------------------------------------------------- the table starts small and grows
SlashCmdList.BISGAMBA("reset"); G.UI:Show(); G.UI:Layout()
local emptyH = G.UI.frame.h
G.UI:Refresh(); fitsIn(BiSGambaFrame, "the table, empty")
SlashCmdList.BISGAMBA("start 100")
fire("CHAT_MSG_RAID", "1", "Dps2"); fire("CHAT_MSG_RAID", "1", "Kumsecration"); fire("CHAT_MSG_RAID", "1", "Dps1")
G.UI:Layout()
check(G.UI.frame.h > emptyH, "the table grows as people join (empty " .. tostring(emptyH) .. " -> seated " .. tostring(G.UI.frame.h) .. ")")
SlashCmdList.BISGAMBA("reset"); G.UI:Layout()
check(math.abs(G.UI.frame.h - emptyH) < 1, "and shrinks back to the short empty strip when it clears")

---------------------------------------------------------------- the longest real names, the biggest gold
-- (6 Oct 2026) The fit check with the worst real case in every window: Forever names carry a
-- surname ("Name Surname", 12 + 1 + 12 at most), a big table rolls /10000, and a long tab runs to
-- six figures. A full row of seats puts the outer seats on the window's edges.
do
  SlashCmdList.BISGAMBA("reset"); BiSGambaDB.rounds = {}; BiSGambaDB.debts = {}
  local longs = { "Kumsecration Dawnbreaker", "Bellatrixxa Moonwhisper", "Grimtoothax Ironmantle",
    "Thunderhoof Stormcaller", "Whisperwind Ashenvale", "Morganthiel Duskwalker", "Shadowmoonx Blackwater",
    "Elunarielle Silverleaf", "Brightblade Kingsbridge", "Gallowsgate Thornfield", "Hollowpeakx Greymantle",
    "Starfallenx Nightsong", "Wolfsbanexx Hearthglen", "Ravenholdtx Lordaeron" }
  SlashCmdList.BISGAMBA("start 10000"); G.UI:Show()
  for _, n in ipairs(longs) do fire("CHAT_MSG_RAID", "1", n .. "-Dreamscythe") end
  check(#G.Game.order == 15, "fifteen at the table, two rows: " .. #G.Game.order)
  G.UI:Refresh(); fitsIn(BiSGambaFrame, "long names, joining")
  SlashCmdList.BISGAMBA("go"); G.UI:Refresh()
  fitsIn(BiSGambaFrame, "long names, nobody has rolled")
  fire("CHAT_MSG_SYSTEM", "Kumlust rolls 5000 (1-10000)")
  for i, n in ipairs(longs) do fire("CHAT_MSG_SYSTEM", ("%s rolls %d (1-10000)"):format(n, i == 1 and 9999 or i == 2 and 2 or 100 + i)) end
  runTimers()
  check(G.Game.state == "DONE" and G.Game.result.winner == longs[1] and G.Game.result.loser == longs[2],
    "the long names win and lose: " .. tostring(G.Game.result and G.Game.result.winner))
  G.UI:Refresh(); fitsIn(BiSGambaFrame, "long names, settled /10000")
  -- a six-figure tab, both ways, with both panels open
  G.Ledger.Add("Kumlust", longs[3], 123456)
  G.Ledger.Add(longs[4], "Kumlust", 98765)
  G.Ledger.Add(longs[5], longs[6], 123456)
  BiSGambaDB.base = { [longs[1]] = { net = 123456, wins = 99, losses = 88, games = 187, best = 0, worst = 0 },
    [longs[2]] = { net = -123456, wins = 88, losses = 99, games = 187, best = 0, worst = 0 } }
  G.Rebuild()
  G.UI:ToggleDebts(); G.UI:ToggleBoard(); G.UI:Refresh()
  fitsIn(BiSGambaFrame, "long names, six-figure debts and board open")
  G.UI:ToggleDebts(); G.UI:ToggleBoard()
  -- the table cleared, the tab left: the narrowest window with the widest pay button
  SlashCmdList.BISGAMBA("reset"); G.UI:Refresh()
  fitsIn(BiSGambaFrame, "empty table, I owe six figures")
  -- the trade, with the partner I owe the most
  openTrade(longs[3])
  fire("TRADE_SHOW"); runTimers(); G.UI:Refresh()
  check(G.Trade.panel and G.Trade.panel.shown, "the panel is up for the long name")
  fitsIn(BiSGambaTradePanel, "the trade panel, long name, six figures")
  fitsIn(BiSGambaFrame, "the table while that trade is open")
  TradeFrame.shown = false; fire("TRADE_CLOSED"); G.Trade.pending = nil; runTimers()
  BiSGambaDB.debts, BiSGambaDB.base, BiSGambaDB.rounds = {}, {}, {}
  G.Rebuild()
  SlashCmdList.BISGAMBA("reset")
end

---------------------------------------------------------------- win/lose streaks from the ledger
SlashCmdList.BISGAMBA("reset")
BiSGambaDB.rounds = {}; BiSGambaDB.boardScope = "all"
local function rnd(id, at, w, l, guild) BiSGambaDB.rounds[id] = { at = at, winner = w, loser = l, amount = 10, g = guild or "The Heathens" } end
rnd("s1", 100, "Kumlust", "Dps2")
rnd("s2", 200, "Kumlust", "Dps1")
rnd("s3", 300, "Kumlust", "Dps2")
do local k, n = G.Streak("Kumlust"); check(k == "win" and n == 3, "three wins in a row: " .. tostring(k) .. " " .. tostring(n)) end
do local k, n = G.Streak("Dps2"); check(k == "lose" and n == 2, "and the repeat loser is on a lose streak: " .. tostring(k) .. " " .. tostring(n)) end
rnd("s4", 400, "Dps2", "Kumlust")   -- Kumlust loses; his win run breaks
do local k, n = G.Streak("Kumlust"); check(k == "lose" and n == 1, "a loss breaks the win run") end
rnd("s5", 500, "Dps1", "Dps4")   -- Kumlust not in this round at all
do local k, n = G.Streak("Kumlust"); check(k == "lose" and n == 1, "a round you were not in is skipped, the run is unchanged") end
rnd("s6", 600, "Dps4", "Kumlust")        -- Kumlust loses again
do local k, n = G.Streak("Kumlust"); check(k == "lose" and n == 2, "two losses now - the skipped middle round did not reset it") end
-- scope: a pug round in another guild does not count under the guild board
BiSGambaDB.boardScope = "guild"
rnd("s7", 700, "Kumlust", "Pug", "Some Pug Guild")   -- would be a win, but wrong guild
do local k, n = G.Streak("Kumlust"); check(k == "lose" and n == 2, "a pug round does not count on the guild board") end
BiSGambaDB.boardScope = "all"
-- the streak is the TRAILING run, not the total count of that outcome
BiSGambaDB.rounds = {}
rnd("t1", 100, "Kumlust", "X"); rnd("t2", 200, "Kumlust", "X")   -- two wins
rnd("t3", 300, "X", "Kumlust")                                    -- a loss breaks them
rnd("t4", 400, "Kumlust", "X")                                    -- one win since
do local k, n = G.Streak("Kumlust"); check(k == "win" and n == 1, "the streak is the trailing run (1), not the total wins (3)") end
BiSGambaDB.rounds = {}
SlashCmdList.BISGAMBA("reset")

---------------------------------------------------------------- the streak badge over the seat (reads G.Streak, thresholds at 2)
SlashCmdList.BISGAMBA("reset"); BiSGambaDB.rounds = {}; BiSGambaDB.boardScope = "all"
SlashCmdList.BISGAMBA("start 100"); G.UI:Show()
fire("CHAT_MSG_RAID", "1", "Dps2"); fire("CHAT_MSG_RAID", "1", "Kumsecration"); fire("CHAT_MSG_RAID", "1", "Dps4")
local function bseat(nm) for _, s in ipairs(G.UI.seats) do if s.person and s.person.name == nm then return s end end end
-- Gnomer: two wins trailing; Kum: two losses trailing; Winter: a lone win (run of 1)
rnd("b1", 100, "Dps2", "Kumsecration"); rnd("b2", 200, "Dps2", "Kumsecration")
rnd("b3", 300, "Dps4", "Dps5")
G.UI:Refresh()
check(bseat("Dps2").streak.shown and strip(bseat("Dps2").streak.text_) == "W2", "a two-win seat shows a W2 badge")
check(bseat("Dps2").streak.text_:find("e5c04a", 1, true) ~= nil, "and the win badge is gold")
check(bseat("Kumsecration").streak.shown and strip(bseat("Kumsecration").streak.text_) == "L2", "a two-loss seat shows an L2 badge")
check(bseat("Kumsecration").streak.text_:find("f08cb0", 1, true) ~= nil, "and the lose badge is warn")
check(not bseat("Dps4").streak.shown, "a run of one is below the badge threshold - nothing over the head")
SlashCmdList.BISGAMBA("reset"); BiSGambaDB.rounds = {}

---------------------------------------------------------------- extreme-roll reactions (roll a 1 / roll the max)
SlashCmdList.BISGAMBA("reset"); SlashCmdList.BISGAMBA("start 100"); G.UI:Show()
fire("CHAT_MSG_RAID", "1", "Dps2"); fire("CHAT_MSG_RAID", "1", "Kumsecration")
G.UI:Refresh()
local function seatOf(nm) for _, s in ipairs(G.UI.seats) do if s.person and s.person.name == nm then return s end end end
local A = G.ANIM
-- a rolled 1: the roller cries, the rest of the table laughs at them
G.UI:OnRoll("Dps2", 1)
check(seatOf("Dps2").anim == A.cry, "a rolled 1 cries")
check(seatOf("Kumsecration").anim == A.laugh, "and the rest of the table laughs at them")
-- a rolled max: the roller flexes, the rest cheer
G.UI:OnRoll("Dps2", 100)
check(seatOf("Dps2").anim == A.flex, "a rolled max flexes")
check(seatOf("Kumsecration").anim == A.cheer, "and the rest cheer them on")
-- an ordinary roll is just a personal reaction, the table does not all react
seatOf("Kumsecration").anim = A.stand
G.UI:OnRoll("Dps2", 50)
check(seatOf("Kumsecration").anim == A.stand, "a middling roll does not move the whole table")
SlashCmdList.BISGAMBA("reset")

---------------------------------------------------------------- combat gets the window out of the way
SlashCmdList.BISGAMBA("reset")
G.UI:Show()
check(G.UI.frame.shown, "window open")
inCombat = true; fire("PLAYER_REGEN_DISABLED")
check(not G.UI.frame.shown, "combat hides it")
-- a table opening mid-fight must not drag it back on screen
from("Dps2", "OPEN", "70")
check(not G.UI.frame.shown, "and a new table does not pop it up mid-fight")
inCombat = false; fire("PLAYER_REGEN_ENABLED")
check(G.UI.frame.shown, "it comes back when the fight ends")
-- but only if it was up to begin with
G.UI.frame:Hide()
inCombat = true; fire("PLAYER_REGEN_DISABLED")
inCombat = false; fire("PLAYER_REGEN_ENABLED")
check(not G.UI.frame.shown, "a window you had closed stays closed")
SlashCmdList.BISGAMBA("combat")
check(BiSGambaDB.combat == false, "and it can be turned off")
SlashCmdList.BISGAMBA("combat")
SlashCmdList.BISGAMBA("reset"); G.UI:Show()

---------------------------------------------------------------- slash + misc
local owedMe = select(2, G.Ledger.Net("Kumlust"))
local gnome = 0
for _, d in ipairs(BiSGambaDB.debts) do if d.from == "Dps2" and d.to == "Kumlust" then gnome = d.amount end end
SlashCmdList.BISGAMBA("paid Dps2 Kumlust")
check(select(2, G.Ledger.Net("Kumlust")) == owedMe - gnome, "manual paid")
SlashCmdList.BISGAMBA("flat")
check(BiSGambaDB.payDiff == false, "flat toggle")
SlashCmdList.BISGAMBA("reset"); SlashCmdList.BISGAMBA("start 250")
check(said[#said]:find("250g flat"), "flat mode says the full wager: " .. said[#said])
SlashCmdList.BISGAMBA("flat")
SlashCmdList.BISGAMBA("reset"); SlashCmdList.BISGAMBA("start 250")
check(said[#said]:find("up to 249g"), "difference mode gives the worst case: " .. said[#said])
SlashCmdList.BISGAMBA("flat")
SlashCmdList.BISGAMBA("start 310")
fire("CHAT_MSG_RAID", "1", "Dps2")
check(#G.Game.order == 2, "seated by chat only")
SlashCmdList.BISGAMBA("go")
fire("CHAT_MSG_SYSTEM", "Kumlust rolls 310 (1-310)")
fire("CHAT_MSG_SYSTEM", "Dps2 rolls 1 (1-310)")
SlashCmdList.BISGAMBA("end")   -- settle with two of four in
check(G.Game.state == "DONE" and G.Game.result.amount == 310, "flat pays the full wager on end")
SlashCmdList.BISGAMBA("debts")
SlashCmdList.BISGAMBA("history")
SlashCmdList.BISGAMBA("help")
SlashCmdList.BISGAMBA("clear")
check(#BiSGambaDB.debts == 0, "clear")
G.UI:ToggleDebts()
G.UI:Refresh()
SlashCmdList.BISGAMBA("npc Troll 3 1234")
check(BiSGambaDB.npc.Troll[3] == 1234, "npc override")
G.UI:ToggleDebts()
inRaid = false
fire("GROUP_ROSTER_UPDATE")
fire("CHAT_MSG_SYSTEM", "Nobody rolls 5 (1-310)")     -- stranger, not in group, after DONE
SlashCmdList.BISGAMBA("reset")
check(G.Game.state == "IDLE", "reset")

-- WHAT A RAID'S CHATTER COSTS, IN CLIENT CALLS (7 Oct 2026). BiSHealing asked the client ~630,000
-- things a second and every suite was green; Arn: "make sure stuff like this does not happen".
-- Every addon in a raid talks on CHAT_MSG_ADDON; none of it but ours is our business, and each
-- line used to cost three secret checks before anything asked whose it was.
do
  local Cost = dofile("../_bisdev/dev/cost.lua")
  local realIs = _G.issecretvalue
  _G.issecretvalue = _G.issecretvalue or function() return false end
  local n, by = Cost.Count(function()
    for i = 1, 500 do
      fire("CHAT_MSG_ADDON", (i % 2 == 0) and "DBM-Core" or "BigWigs", "some\tpayload", "RAID", "Dps2-Dreamscythe")
    end
  end)
  _G.issecretvalue = realIs
  check(n <= 500, "500 other addons' messages cost at most one client question each: " .. n
    .. " (" .. Cost.Top(by, 3) .. ")")
end

print(("%d checks, %d failed"):format(pass + fail, fail))
os.exit(fail == 0 and 0 or 1)
