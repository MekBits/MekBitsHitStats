-- MekBitsHitStats test harness. Run from the addon directory with Lua 5.1:  lua5.1 test/run.lua
-- (see test/run.sh). Exits non-zero on the first failed group.

local M = dofile("test/mocks.lua")
MekBitsHitStats = {}
dofile("Data.lua")
dofile("Calc.lua")
dofile("UI.lua")
local MBHS = MekBitsHitStats

local passed, failed = 0, 0
local failures = {}

local function check(name, cond, detail)
    if cond then
        passed = passed + 1
    else
        failed = failed + 1
        failures[#failures + 1] = name .. (detail and (" -- " .. detail) or "")
        print("FAIL: " .. name .. (detail and (" -- " .. detail) or ""))
    end
end

local function near(name, got, want)
    check(name, math.abs(got - want) < 1e-9, string.format("got %.6f want %.6f", got, want))
end

local function find(list, text)
    for _, o in ipairs(list) do
        if o.label:find(text, 1, true) then return o end
    end
end

local R_MELEE, R_SPELL = 32.79, 26.23
local W1 = { equip = "INVTYPE_WEAPON" }
local W1B = { equip = "INVTYPE_WEAPON", broken = true }
local W2 = { equip = "INVTYPE_2HWEAPON" }

------------------------------------------------------------------------------------------
-- 1. Data.lua against the DBC-derived list
------------------------------------------------------------------------------------------
do
    local seen = {}
    for _, e in ipairs(M.expected.talents) do
        local data
        for _, d in ipairs(MBHS.Talents[e.class] or {}) do
            if d.id == e.id then data = d end
        end
        if e.excluded then
            check("DBC excluded talent not in Data: " .. e.name, data == nil)
        else
            check("DBC talent present in Data: " .. e.class .. " " .. e.name, data ~= nil)
            if data then
                seen[data] = true
                local n = e.class .. " " .. e.name
                check(n .. ": position", data.tab == e.tab and data.tier == e.tier and data.col == e.col,
                      string.format("data %d/%d/%d dbc %d/%d/%d", data.tab, data.tier, data.col, e.tab, e.tier, e.col))
                check(n .. ": maxRank", data.maxRank == e.maxRank)
                check(n .. ": key", data.key == e.name)
                for i = 1, e.maxRank do
                    check(n .. ": spell id r" .. i, data.spells[i] == e.spells[i])
                    check(n .. ": melee r" .. i, ((data.m and data.m[i]) or 0) == e.m[i])
                    check(n .. ": spell r" .. i, ((data.s and data.s[i]) or 0) == e.s[i])
                    check(n .. ": school r" .. i, ((data.school and data.school.v[i]) or 0) == e.school[i])
                    check(n .. ": spellmod r" .. i, ((data.spellmod and data.spellmod.v[i]) or 0) == e.spellmod[i])
                end
                if data.school then check(n .. ": school mask", data.school.mask == e.schoolMask) end
                check(n .. ": needs", data.needs == e.needs, tostring(data.needs) .. " vs " .. tostring(e.needs))
                check(n .. ": no extra ranks", data.spells[e.maxRank + 1] == nil)
            end
        end
    end
    for class, list in pairs(MBHS.Talents) do
        for _, d in ipairs(list) do
            check("Data talent exists in DBC list: " .. class .. " " .. d.key, seen[d] == true)
        end
    end
    local dr = MBHS.Racials.Draenei
    for _, id in ipairs(dr.spells) do
        local r = M.expected.racials[id]
        check("Racial " .. id .. " in DBC", r ~= nil and r.m == dr.m and r.s == dr.s)
    end
end

------------------------------------------------------------------------------------------
-- 2. Scenarios
------------------------------------------------------------------------------------------

-- Fury warrior, dual wield, Precision 3/3
M.setup({ class = "WARRIOR", race = "Human", ratings = { [6] = 328 }, talents = { Precision = 3 },
          items = { [16] = W1, [17] = W1 } })
do
    local r = MBHS:Compute()
    near("warrior: melee total", r.melee.total, 328 / R_MELEE + 3)
    near("warrior: melee talents", r.melee.talentPct, 3)
    near("warrior: ranged total (aura 54 also feeds ranged)", r.ranged.total, 3)
    near("warrior: spell total", r.spell.total, 0)
    check("warrior: label", r.melee.on[1] and r.melee.on[1].label == "Precision 3/3")
end
-- same, weapons broken
M.setup({ class = "WARRIOR", race = "Human", ratings = { [6] = 328 }, talents = { Precision = 3 },
          items = { [16] = W1B, [17] = W1B } })
do
    local r = MBHS:Compute()
    near("warrior broken weapons: melee total is rating only", r.melee.total, 328 / R_MELEE)
    check("warrior broken weapons: listed as not counted", #r.melee.off == 1 and r.melee.off[1].why:find("melee weapon", 1, true))
end
-- one broken, one fine -> still active (core: any fitting unbroken item)
M.setup({ class = "WARRIOR", race = "Human", ratings = {}, talents = { Precision = 2 }, items = { [16] = W1B, [17] = W1 } })
near("warrior one broken weapon: still active", MBHS:Compute().melee.total, 2)
-- 2H weapon
M.setup({ class = "WARRIOR", race = "Human", ratings = {}, talents = { Precision = 3 }, items = { [16] = W2 } })
near("warrior 2H: active", MBHS:Compute().melee.total, 3)
-- naked
M.setup({ class = "WARRIOR", race = "Human", ratings = {}, talents = { Precision = 3 }, items = {} })
near("warrior no weapon: inactive", MBHS:Compute().melee.total, 0)
-- bow only: not in the warrior's subclass mask
M.setup({ class = "WARRIOR", race = "Human", ratings = {}, talents = { Precision = 3 },
          items = { [18] = { equip = "INVTYPE_RANGED" } } })
near("warrior bow only: inactive (mask is melee weapons)", MBHS:Compute().melee.total, 0)
-- rank 0
M.setup({ class = "WARRIOR", race = "Human", ratings = { [6] = 100 }, talents = {}, items = { [16] = W1 } })
near("warrior no talent: rating only", MBHS:Compute().melee.total, 100 / R_MELEE)

-- Frost mage: Precision 3/3 (all spells) + Arcane Focus 3/3 (arcane spells only)
M.setup({ class = "MAGE", race = "Gnome", ratings = { [8] = 262 }, talents = { Precision = 3, ["Arcane Focus"] = 3 }, items = {} })
do
    local r = MBHS:Compute()
    near("mage: spell total", r.spell.total, 262 / R_SPELL + 3)
    near("mage: melee total", r.melee.total, 0)
    check("mage: one school row (arcane)", #r.schools == 1 and r.schools[1].school == 64)
    near("mage: arcane extra", r.schools[1].extra, 3)
    near("mage: arcane total", r.schools[1].total, 262 / R_SPELL + 6)
    check("mage: arcane row says class mask", r.schools[1].sources[1]:find("Arcane spells only", 1, true) ~= nil)
end

-- Draenei Enhancement shaman: DWS 3/3 + Elemental Precision 3/3 + Heroic Presence
M.setup({ class = "SHAMAN", race = "Draenei", ratings = { [6] = 164, [8] = 262 },
          talents = { ["Dual Wield Specialization"] = 3, ["Elemental Precision"] = 3 }, items = { [16] = W1, [17] = W1 } })
do
    local r = MBHS:Compute()
    near("shaman: melee total", r.melee.total, 164 / R_MELEE + 6 + 1)
    near("shaman: ranged total", r.ranged.total, 6 + 1)
    near("shaman: spell total (racial only)", r.spell.total, 262 / R_SPELL + 1)
    check("shaman: 3 schools", #r.schools == 3)
    local by = {}
    for _, s in ipairs(r.schools) do by[s.school] = s end
    check("shaman: fire/nature/frost", by[4] and by[8] and by[16] and not by[32] and not by[64])
    near("shaman: fire total", by[4].total, 262 / R_SPELL + 1 + 3)
    check("shaman: no DWS note with off-hand", #r.melee.notes == 0)
end
-- same shaman, only a 2H weapon: AzerothCore still applies DWS
M.setup({ class = "SHAMAN", race = "Orc", ratings = {}, talents = { ["Dual Wield Specialization"] = 2 }, items = { [16] = W2 } })
do
    local r = MBHS:Compute()
    near("shaman 2H (default config): DWS counted like the server does", r.melee.total, 4)
    check("shaman 2H: note explains it", #r.melee.notes == 1 and r.melee.notes[1]:find("without an off-hand", 1, true) ~= nil)
    MBHS.Config.DWS_REQUIRES_OFFHAND = true
    r = MBHS:Compute()
    near("shaman 2H (config DWS_REQUIRES_OFFHAND): not counted", r.melee.total, 0)
    check("shaman 2H (config): listed as not counted", #r.melee.off == 1)
    M.setup({ class = "SHAMAN", race = "Orc", ratings = {}, talents = { ["Dual Wield Specialization"] = 2 }, items = { [16] = W1, [17] = { equip = "INVTYPE_WEAPONOFFHAND" } } })
    near("shaman dual wield (config): counted", MBHS:Compute().melee.total, 4)
    MBHS.Config.DWS_REQUIRES_OFFHAND = false
end

-- Hunter Focused Aim 3/3: melee and ranged
M.setup({ class = "HUNTER", race = "Orc", ratings = { [7] = 328 }, talents = { ["Focused Aim"] = 3 }, items = { [18] = { equip = "INVTYPE_RANGEDRIGHT" } } })
do
    local r = MBHS:Compute()
    near("hunter: ranged total", r.ranged.total, 328 / R_MELEE + 3)
    near("hunter: melee total", r.melee.total, 3)
    near("hunter: spell total", r.spell.total, 0)
end

-- Rogue Precision 5/5: melee, ranged and spell (poisons)
M.setup({ class = "ROGUE", race = "Human", ratings = { [6] = 164, [8] = 262 }, talents = { Precision = 5 },
          items = { [16] = { equip = "INVTYPE_WEAPONMAINHAND" }, [17] = { equip = "INVTYPE_WEAPONOFFHAND" } } })
do
    local r = MBHS:Compute()
    near("rogue: melee", r.melee.total, 164 / R_MELEE + 5)
    near("rogue: spell", r.spell.total, 262 / R_SPELL + 5)
    near("rogue: ranged", r.ranged.total, 5)
end
M.setup({ class = "ROGUE", race = "Human", ratings = {}, talents = { Precision = 5 }, items = {} })
near("rogue no weapons: inactive", MBHS:Compute().melee.total, 0)
M.setup({ class = "ROGUE", race = "Human", ratings = {}, talents = { Precision = 5 }, items = { [18] = { equip = "INVTYPE_THROWN" } } })
near("rogue thrown only: active (mask has thrown)", MBHS:Compute().melee.total, 5)

-- Death knight: Nerves of Cold Steel (one-hand only) + Virulence (spell)
M.setup({ class = "DEATHKNIGHT", race = "Human", ratings = { [6] = 164 }, talents = { ["Nerves of Cold Steel"] = 3, Virulence = 3 },
          items = { [16] = W2 } })
do
    local r = MBHS:Compute()
    near("dk 2H: melee has no NoCS", r.melee.total, 164 / R_MELEE)
    near("dk 2H: virulence on spell", r.spell.total, 3)
    check("dk 2H: NoCS listed as not counted", #r.melee.off == 1 and r.melee.off[1].why:find("one-handed", 1, true))
end
M.setup({ class = "DEATHKNIGHT", race = "Human", ratings = { [6] = 164 }, talents = { ["Nerves of Cold Steel"] = 3, Virulence = 3 },
          items = { [16] = W1, [17] = W1 } })
do
    local r = MBHS:Compute()
    near("dk dual wield: NoCS counted", r.melee.total, 164 / R_MELEE + 3)
    near("dk dual wield: ranged also +3 (the core adds aura 54 to ranged)", r.ranged.total, 3)
end

-- Paladin Enlightened Judgements 2/2: all three
M.setup({ class = "PALADIN", race = "Human", ratings = {}, talents = { ["Enlightened Judgements"] = 2 }, items = {} })
do
    local r = MBHS:Compute()
    near("paladin: melee", r.melee.total, 4)
    near("paladin: ranged", r.ranged.total, 4)
    near("paladin: spell", r.spell.total, 4)
end

-- Warlock Suppression: fire + shadow only (the core matches on school mask)
M.setup({ class = "WARLOCK", race = "Human", ratings = { [8] = 262 }, talents = { Suppression = 3 }, items = {} })
do
    local r = MBHS:Compute()
    near("warlock: base spell unchanged", r.spell.total, 262 / R_SPELL)
    check("warlock: fire and shadow rows", #r.schools == 2 and r.schools[1].school == 4 and r.schools[2].school == 32)
    near("warlock: shadow total", r.schools[2].total, 262 / R_SPELL + 3)
end

-- Druid Balance of Power 2/2: every magic school
M.setup({ class = "DRUID", race = "Night Elf", ratings = {}, talents = { ["Balance of Power"] = 2 }, items = {} })
do
    local r = MBHS:Compute()
    check("druid: six schools", #r.schools == 6)
    for _, s in ipairs(r.schools) do near("druid: " .. s.name, s.extra, 4) end
end

-- Priest Shadow Focus 3/3
M.setup({ class = "PRIEST", race = "Human", ratings = {}, talents = { ["Shadow Focus"] = 3 }, items = {} })
do
    local r = MBHS:Compute()
    check("priest: one shadow row", #r.schools == 1 and r.schools[1].school == 32 and r.schools[1].extra == 3)
end

-- Layout mismatch: the talent has another max rank than the data says -> not counted, noted on all three stats
M.setup({ class = "WARRIOR", race = "Human", ratings = {}, talents = { Precision = 3 }, items = { [16] = W1 }, maxRankOverride = { Precision = 5 } })
do
    local r = MBHS:Compute()
    near("mismatch: not counted", r.melee.total, 0)
    check("mismatch: noted", #r.melee.notes == 1 and #r.spell.notes == 1)
end

-- Heroic Presence as a visible aura on a non-Draenei; counted once
M.setup({ class = "WARRIOR", race = "Human", ratings = {}, talents = {}, items = {}, buffs = { 1459, 28878 } })
do
    local r = MBHS:Compute()
    near("aura: melee +1", r.melee.total, 1)
    near("aura: spell +1", r.spell.total, 1)
end
M.setup({ class = "WARRIOR", race = "Draenei", ratings = {}, talents = {}, items = {}, buffs = { 28878 } })
near("draenei with the aura too: counted once", MBHS:Compute().melee.total, 1)
-- Draenei in party, no visible aura: noted, not counted
M.setup({ class = "WARRIOR", race = "Human", ratings = {}, talents = {}, items = {}, party = { party2 = "Draenei" } })
do
    local r = MBHS:Compute()
    near("party draenei: not counted", r.melee.total, 0)
    check("party draenei: noted", #r.melee.notes == 1)
end

-- Class without hit talents, nothing equipped: only rating
M.setup({ class = "WARRIOR", race = "Human", ratings = { [6] = 50, [7] = 60, [8] = 70 }, talents = {}, items = {} })
do
    local r = MBHS:Compute()
    near("plain: melee", r.melee.total, 50 / R_MELEE)
    near("plain: ranged", r.ranged.total, 60 / R_MELEE)
    near("plain: spell", r.spell.total, 70 / R_SPELL)
end

-- Talent info not loaded (login): no layout, no talents, no crash, no note
M.setup({ class = "MAGE", race = "Human", ratings = {}, talents = {}, items = {} })
do
    local saved = GetNumTalents
    GetNumTalents = function() return 0 end
    local r = MBHS:Compute()
    GetNumTalents = saved
    near("no talent info: total 0", r.spell.total, 0)
    check("no talent info: no note", #r.spell.notes == 0)
end

------------------------------------------------------------------------------------------
-- 3. Tooltip text
------------------------------------------------------------------------------------------
M.setup({ class = "SHAMAN", race = "Draenei", ratings = { [6] = 164, [8] = 262 },
          talents = { ["Dual Wield Specialization"] = 3, ["Elemental Precision"] = 3 }, items = { [16] = W1, [17] = W1 } })
do
    local r = MBHS:Compute()
    local melee = MBHS:TooltipText("melee", r)
    check("tooltip melee: total line", melee:find(string.format("Total hit chance: %.2f%%", r.melee.total), 1, true))
    check("tooltip melee: rating line", melee:find("Rating: 5.00%", 1, true))
    check("tooltip melee: talent line", melee:find("Dual Wield Specialization 3/3: +6%", 1, true))
    check("tooltip melee: other line", melee:find("Heroic Presence (racial): +1%", 1, true))
    local spell = MBHS:TooltipText("spell", r)
    check("tooltip spell: schools", spell:find("By school", 1, true) and spell:find("Fire:", 1, true) and spell:find("Elemental Precision", 1, true))
    print("---- sample tooltip (spell) ----\n" .. spell .. "\n--------------------------------")
end

------------------------------------------------------------------------------------------
-- 4. Hook on the character sheet
------------------------------------------------------------------------------------------
M.setup({ class = "WARRIOR", race = "Human", ratings = { [6] = 328 }, talents = { Precision = 3 }, items = { [16] = W1, [17] = W1 } })
do
    check("hook registered", M.hooks and M.hooks.PaperDollFrame_SetRating ~= nil)
    local f = M.makeStatFrame("PlayerStatFrameLeft4")
    MekBitsHitStatsDB = nil
    PaperDollFrame_SetRating(f, 6)
    check("sheet: label shortened", _G.PlayerStatFrameLeft4Label:GetText() == "Hit:")
    check("sheet: total percent shown", _G.PlayerStatFrameLeft4StatText:GetText() == string.format("%.2f%%", 328 / R_MELEE + 3),
          tostring(_G.PlayerStatFrameLeft4StatText:GetText()))
    check("sheet: Blizzard tooltip kept", f.tooltip2:find("Blizzard text", 1, true) ~= nil)
    check("sheet: breakdown appended", f.tooltip2:find("Precision 3/3: +3%", 1, true) ~= nil)
    check("sheet: default mode saved", MekBitsHitStatsDB and MekBitsHitStatsDB.mode == "percent")

    -- other rating indexes untouched
    local g = M.makeStatFrame("PlayerStatFrameLeft5")
    PaperDollFrame_SetRating(g, 2)
    check("sheet: non-hit rating untouched", _G.PlayerStatFrameLeft5Label:GetText() == "Hit Rating:" and g.tooltip2:find("MekBits", 1, true) == nil)

    -- mode rating: number stays, tooltip still extended
    SlashCmdList["MEKBITSHITSTATS"]("rating")
    check("slash: mode changed", MekBitsHitStatsDB.mode == "rating" and M.chat:find("mode = rating", 1, true))
    check("slash: sheet refresh requested", (M.updateCalls or 0) >= 1)
    PaperDollFrame_SetRating(f, 6)
    check("sheet rating mode: number stays", _G.PlayerStatFrameLeft4StatText:GetText() == 328 and _G.PlayerStatFrameLeft4Label:GetText() == "Hit Rating:")
    check("sheet rating mode: tooltip extended", f.tooltip2:find("Total hit chance", 1, true) ~= nil)

    -- mode off: stock
    SlashCmdList["MEKBITSHITSTATS"](" OFF ")
    PaperDollFrame_SetRating(f, 6)
    check("sheet off mode: stock", f.tooltip2:find("MekBits", 1, true) == nil and _G.PlayerStatFrameLeft4StatText:GetText() == 328)
    SlashCmdList["MEKBITSHITSTATS"]("garbage")
    check("slash: garbage keeps mode", MekBitsHitStatsDB.mode == "off")
    SlashCmdList["MEKBITSHITSTATS"]("percent")

    -- an API error must not break the sheet
    local saved = GetTalentInfo
    GetTalentInfo = function() error("boom") end
    local ok = pcall(PaperDollFrame_SetRating, f, 6)
    GetTalentInfo = saved
    check("sheet: API error does not propagate", ok)
    check("sheet: error recorded for /mbhs", MBHS.lastError ~= nil and tostring(MBHS.lastError):find("boom", 1, true) ~= nil)
    SlashCmdList["MEKBITSHITSTATS"]("")
    check("slash: shows last error", M.chat:find("last error", 1, true) ~= nil)

    -- event frame: dirty flag then OnUpdate refreshes the open sheet
    local ef = M.eventFrame
    M.updateCalls = 0
    ef._scripts.OnEvent(ef, "CHARACTER_POINTS_CHANGED")
    ef._scripts.OnUpdate(ef)
    check("events: talent change refreshes the sheet", M.updateCalls == 1)
    ef._scripts.OnUpdate(ef)
    check("events: refresh only once", M.updateCalls == 1)
    ef._scripts.OnEvent(ef, "UNIT_AURA", "target")
    ef._scripts.OnUpdate(ef)
    check("events: other units' auras ignored", M.updateCalls == 1)
end

------------------------------------------------------------------------------------------
print(string.format("\n%d checks passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
