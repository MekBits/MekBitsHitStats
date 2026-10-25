-- MekBitsHitStats / UI.lua
--
-- Hooks the character sheet. PaperDollFrame_SetRating(statFrame, ratingIndex) (3.3.5 FrameXML) draws the
-- Hit stat for melee, ranged and spell; we run after it and
--   * replace the number with the total hit chance (mode "percent"), or leave it (mode "rating"),
--   * append the rating / talents / other breakdown to the stat's tooltip.
-- Purely cosmetic: nothing here talks to the server or changes combat.

local MBHS = MekBitsHitStats

local CR_HIT_MELEE = CR_HIT_MELEE or 6
local CR_HIT_RANGED = CR_HIT_RANGED or 7
local CR_HIT_SPELL = CR_HIT_SPELL or 8

local KIND = { [CR_HIT_MELEE] = "melee", [CR_HIT_RANGED] = "ranged", [CR_HIT_SPELL] = "spell" }
local MODES = { percent = true, rating = true, off = true }

local function db()
    MekBitsHitStatsDB = MekBitsHitStatsDB or {}
    if not MODES[MekBitsHitStatsDB.mode] then MekBitsHitStatsDB.mode = "percent" end
    return MekBitsHitStatsDB
end

local function onSetRating(statFrame, ratingIndex)
    local kind = KIND[ratingIndex]
    if not kind then return end
    local mode = db().mode
    if mode == "off" then return end

    local ok, res = pcall(MBHS.Compute, MBHS)
    if not ok then
        -- never break the character sheet; /mbhs shows the last error
        MBHS.lastError = res
        return
    end

    local base = statFrame:GetName()
    if mode == "percent" then
        local label = _G[base .. "Label"]
        local text = _G[base .. "StatText"]
        if label and text then
            label:SetText(string.format(STAT_FORMAT or "%s:", "Hit"))
            text:SetText(string.format("%.2f%%", res[kind].total))
        end
    end

    local extra = MBHS:TooltipText(kind, res)
    statFrame.tooltip2 = (statFrame.tooltip2 and (statFrame.tooltip2 .. "\n\n") or "") .. extra
end

hooksecurefunc("PaperDollFrame_SetRating", onSetRating)

-- Refresh the sheet when something that feeds the numbers changes while it is open.
local dirty = false
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("CHARACTER_POINTS_CHANGED")
frame:RegisterEvent("PLAYER_TALENT_UPDATE")
frame:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
frame:RegisterEvent("UNIT_INVENTORY_CHANGED")
frame:RegisterEvent("PARTY_MEMBERS_CHANGED")
frame:RegisterEvent("RAID_ROSTER_UPDATE")
frame:RegisterEvent("UNIT_AURA")
frame:SetScript("OnEvent", function(self, event, unit)
    if (event == "UNIT_AURA" or event == "UNIT_INVENTORY_CHANGED") and unit ~= "player" then return end
    dirty = true
end)
frame:SetScript("OnUpdate", function()
    if dirty then
        dirty = false
        if PaperDollFrame and PaperDollFrame:IsVisible() and PaperDollFrame_UpdateStats then
            PaperDollFrame_UpdateStats()
        end
    end
end)

SLASH_MEKBITSHITSTATS1 = "/mbhs"
SlashCmdList["MEKBITSHITSTATS"] = function(msg)
    msg = string.lower(msg or "")
    msg = string.gsub(msg, "^%s+", "")
    msg = string.gsub(msg, "%s+$", "")
    if MODES[msg] then
        db().mode = msg
        if PaperDollFrame_UpdateStats then PaperDollFrame_UpdateStats() end
    end
    DEFAULT_CHAT_FRAME:AddMessage("MekBits Hit Stats: mode = " .. db().mode .. "  (usage: /mbhs percent | rating | off)")
    if MBHS.lastError then
        DEFAULT_CHAT_FRAME:AddMessage("MekBits Hit Stats: last error: " .. tostring(MBHS.lastError))
    end
end
