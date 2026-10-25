-- Minimal WoW 3.3.5a API mocks for the MekBitsHitStats harness (Lua 5.1).
-- The talent layout the client "returns" is built from test/dbc_expected.lua (generated from the DBC files),
-- NOT from Data.lua, so the harness checks Data.lua against an independent source.

local expected = dofile("test/dbc_expected.lua")

local M = {}
M.expected = expected

-- state set by M.setup(spec)
local S = {}

local RATING_DIV = { [6] = 32.79, [7] = 32.79, [8] = 26.23 }

-- client constants / globals the addon reads
CR_HIT_MELEE, CR_HIT_RANGED, CR_HIT_SPELL = 6, 7, 8
STAT_FORMAT = "%s:"
SPELL_SCHOOL1_NAME, SPELL_SCHOOL2_NAME, SPELL_SCHOOL3_NAME = "Holy", "Fire", "Nature"
SPELL_SCHOOL4_NAME, SPELL_SCHOOL5_NAME, SPELL_SCHOOL6_NAME = "Frost", "Shadow", "Arcane"

function UnitClass() return S.className or "Warrior", S.class end
function UnitRace(unit)
    if unit == "player" or unit == nil then return S.raceName or S.race, S.race end
    local r = S.party and S.party[unit]
    return r, r
end
function UnitExists(unit) return unit == "player" or (S.party and S.party[unit] ~= nil) end
function UnitIsUnit(a, b) return a == b end
function GetNumRaidMembers() return S.raid or 0 end

function GetCombatRating(cr) return (S.ratings and S.ratings[cr]) or 0 end
function GetCombatRatingBonus(cr) return GetCombatRating(cr) / (RATING_DIV[cr] or 1) end

-- talent layout: 3 tabs; hit-relevant talents of the class at their real position plus filler talents.
local function layoutFor(class)
    local tabs = { {}, {}, {} }
    for _, t in ipairs(expected.talents) do
        if t.class == class then
            table.insert(tabs[t.tab], { name = t.name, tier = t.tier, col = t.col, maxRank = t.maxRank })
        end
    end
    -- fillers must not collide with a real talent position
    local function taken(tab, tier, col)
        for _, t in ipairs(tabs[tab]) do if t.tier == tier and t.col == col then return true end end
        return false
    end
    for tab = 1, 3 do
        for col = 1, 4 do
            if not taken(tab, 3, col) then
                table.insert(tabs[tab], { name = "Filler " .. tab .. "-" .. col, tier = 3, col = col, maxRank = 5 })
            end
        end
    end
    return tabs
end

function GetNumTalentTabs() return 3 end
function GetNumTalents(tab) return #S.layout[tab] end
function GetTalentInfo(tab, i)
    local t = S.layout[tab][i]
    if not t then return nil end
    local rank = (S.talents and S.talents[t.name]) or 0
    local maxRank = t.maxRank
    if S.maxRankOverride and S.maxRankOverride[t.name] then maxRank = S.maxRankOverride[t.name] end
    return t.name, "Interface\\Icons\\Fake", t.tier, t.col, rank, maxRank, nil, true
end

local function itemFor(slot) return S.items and S.items[slot] end
function GetInventoryItemLink(unit, slot)
    local it = itemFor(slot)
    return it and ("|cffffffff|Hitem:%d:0:0:0:0:0:0:0:80|h[Fake]|h|r"):format(1000 + slot) or nil
end
function GetInventoryItemBroken(unit, slot)
    local it = itemFor(slot)
    return (it and it.broken) and 1 or nil
end
function GetItemInfo(link)
    local slot = tonumber(link:match("item:(%d+)")) - 1000
    local it = itemFor(slot)
    if not it then return nil end
    -- name, link, quality, iLevel, reqLevel, class, subclass, maxStack, equipSlot, texture, vendorPrice
    return "Fake", link, 1, 1, 1, "Weapon", "Localised subclass", 1, it.equip, "tex", 0
end

function UnitBuff(unit, i)
    local id = S.buffs and S.buffs[i]
    if not id then return nil end
    -- name, rank, icon, count, debuffType, duration, expirationTime, unitCaster, isStealable, shouldConsolidate, spellId
    return "Buff" .. id, "", "icon", 1, nil, 0, 0, "player", nil, nil, id
end

-- WoW utility globals used by the addon
function hooksecurefunc(name, fn)
    M.hooks = M.hooks or {}
    local orig = _G[name]
    assert(orig, "hooksecurefunc on missing " .. name)
    _G[name] = function(...)
        local r = { orig(...) }
        fn(...)
        return unpack(r)
    end
    M.hooks[name] = fn
end

-- frames
local function newFrame(name)
    local f = { _name = name, _events = {}, _scripts = {}, _text = "" }
    function f:GetName() return self._name end
    function f:RegisterEvent(e) self._events[e] = true end
    function f:SetScript(k, fn) self._scripts[k] = fn end
    function f:SetText(t) self._text = t end
    function f:GetText() return self._text end
    function f:IsVisible() return true end
    return f
end
M.newFrame = newFrame
function CreateFrame() M.eventFrame = newFrame(nil); return M.eventFrame end
function PaperDollFrame_UpdateStats() M.updateCalls = (M.updateCalls or 0) + 1 end
PaperDollFrame = newFrame("PaperDollFrame")
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) M.chat = m end }
SlashCmdList = {}

-- Blizzard's PaperDollFrame_SetRating, reduced to what matters here (3.3.5 FrameXML/PaperDollFrame.lua:319)
function PaperDollFrame_SetRating(statFrame, ratingIndex)
    local label = _G[statFrame:GetName() .. "Label"]
    local text = _G[statFrame:GetName() .. "StatText"]
    label:SetText(STAT_FORMAT:format("Hit Rating"))
    text:SetText(GetCombatRating(ratingIndex))
    statFrame.tooltip = "Hit Rating " .. GetCombatRating(ratingIndex)
    statFrame.tooltip2 = "Blizzard text: increases hit by " .. GetCombatRatingBonus(ratingIndex)
end

function M.makeStatFrame(name)
    local f = newFrame(name)
    _G[name .. "Label"] = newFrame(name .. "Label")
    _G[name .. "StatText"] = newFrame(name .. "StatText")
    return f
end

-- spec = { class=, race=, ratings={[6]=,[7]=,[8]=}, talents={["Precision"]=3}, items={[16]={equip=,broken=}},
--          buffs={spellIds}, party={party1="Draenei"}, maxRankOverride={name=n} }
function M.setup(spec)
    S = {}
    for k, v in pairs(spec) do S[k] = v end
    S.className = S.class:sub(1, 1) .. S.class:sub(2):lower()
    S.layout = layoutFor(S.class)
end

return M
