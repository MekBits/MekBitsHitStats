-- MekBitsHitStats / Calc.lua
--
-- Builds the hit breakdown from the 3.3.5a client API. No frames, no hooks: the test harness loads
-- this file with mocked API functions.
--
--   local r = MekBitsHitStats:Compute()
--   r.melee / r.ranged / r.spell = {
--       rating    = hit rating,           ratingPct = what the client converts it to
--       on        = { {label, pct}, ... } talents that the server counts (always-on ones and
--                                          weapon ones whose item requirement is met)
--       off       = { {label, pct, why} } talents learned but not counted right now
--       other     = { {label, pct}, ... } racials / buffs
--       talentPct, otherPct, total        total = ratingPct + talentPct + otherPct
--       notes     = { "text", ... }       things the player should know (not counted, layout mismatch ...)
--       schools   = { {school, name, extra, total, sources}, ... }  (spell only) extra hit per school
--   }

local MBHS = MekBitsHitStats

local CR_HIT_MELEE = CR_HIT_MELEE or 6
local CR_HIT_RANGED = CR_HIT_RANGED or 7
local CR_HIT_SPELL = CR_HIT_SPELL or 8

-- client inventory slots that the core scans for weapon-dependent auras (main hand, off hand, ranged)
local WEAPON_SLOTS = { 16, 17, 18 }

local SCHOOL_ORDER = { 4, 8, 16, 32, 64, 2 } -- fire, nature, frost, shadow, arcane, holy (physical has no spell hit mods)
local SCHOOL_FALLBACK = { [2] = "Holy", [4] = "Fire", [8] = "Nature", [16] = "Frost", [32] = "Shadow", [64] = "Arcane" }
local SCHOOL_GLOBAL = { [2] = "SPELL_SCHOOL1_NAME", [4] = "SPELL_SCHOOL2_NAME", [8] = "SPELL_SCHOOL3_NAME",
                        [16] = "SPELL_SCHOOL4_NAME", [32] = "SPELL_SCHOOL5_NAME", [64] = "SPELL_SCHOOL6_NAME" }

local function schoolName(bit)
    local g = SCHOOL_GLOBAL[bit]
    return (g and _G[g]) or SCHOOL_FALLBACK[bit] or tostring(bit)
end
MBHS.SchoolName = schoolName

local function newStat(rating, ratingPct)
    return { rating = rating or 0, ratingPct = ratingPct or 0, on = {}, off = {}, other = {}, notes = {},
             talentPct = 0, otherPct = 0, total = 0 }
end

-- talents[tab..":"..tier..":"..col] = { name, rank, maxRank }
local function readTalents()
    local t = {}
    local tabs = GetNumTalentTabs() or 0
    for tab = 1, tabs do
        local n = GetNumTalents(tab) or 0
        for i = 1, n do
            local name, _, tier, col, rank, maxRank = GetTalentInfo(tab, i)
            if name then
                t[tab .. ":" .. tier .. ":" .. col] = { name = name, rank = rank or 0, maxRank = maxRank or 0 }
            end
        end
    end
    return t
end

-- true if an unbroken item satisfying `needs` is in main hand, off hand or ranged slot
local function hasItemFor(needs)
    local rule = MBHS.NEEDS[needs]
    if not rule then return false end
    for _, slot in ipairs(WEAPON_SLOTS) do
        local link = GetInventoryItemLink("player", slot)
        if link and not GetInventoryItemBroken("player", slot) then
            local _, _, _, _, _, _, _, _, equipSlot = GetItemInfo(link)
            if equipSlot and rule.slots[equipSlot] then
                return true
            end
        end
    end
    return false
end

local function hasOffhandWeapon()
    local link = GetInventoryItemLink("player", 17)
    if not link then return false end
    local _, _, _, _, _, _, _, _, equipSlot = GetItemInfo(link)
    return equipSlot == "INVTYPE_WEAPON" or equipSlot == "INVTYPE_WEAPONOFFHAND"
end

local function hasBuff(spellIds)
    for i = 1, 40 do
        local name, _, _, _, _, _, _, _, _, _, spellId = UnitBuff("player", i)
        if not name then break end
        for _, id in ipairs(spellIds) do
            if spellId == id then return true end
        end
    end
    return false
end

local function otherDraenei()
    local function check(unit)
        if UnitExists(unit) and not UnitIsUnit(unit, "player") then
            local _, race = UnitRace(unit)
            return race == "Draenei"
        end
        return false
    end
    for i = 1, 4 do
        if check("party" .. i) then return true end
    end
    local raid = GetNumRaidMembers and GetNumRaidMembers() or 0
    for i = 1, raid do
        if check("raid" .. i) then return true end
    end
    return false
end

local function addTalentEffect(res, e, rank, label, active, why)
    -- one entry per stat the talent touches; `label` already contains rank text
    local function put(stat, pct)
        local list = active and stat.on or stat.off
        list[#list + 1] = { label = label, pct = pct, why = why }
        if active then stat.talentPct = stat.talentPct + pct end
    end
    if e.m then
        local v = e.m[rank]
        put(res.melee, v)
        put(res.ranged, v)
    end
    if e.s then
        put(res.spell, e.s[rank])
    end
end

function MBHS:Compute()
    local _, class = UnitClass("player")
    local _, race = UnitRace("player")

    local res = {
        class = class, race = race,
        melee = newStat(GetCombatRating(CR_HIT_MELEE), GetCombatRatingBonus(CR_HIT_MELEE)),
        ranged = newStat(GetCombatRating(CR_HIT_RANGED), GetCombatRatingBonus(CR_HIT_RANGED)),
        spell = newStat(GetCombatRating(CR_HIT_SPELL), GetCombatRatingBonus(CR_HIT_SPELL)),
        schools = {},
    }

    local function noteAll(text)
        res.melee.notes[#res.melee.notes + 1] = text
        res.ranged.notes[#res.ranged.notes + 1] = text
        res.spell.notes[#res.spell.notes + 1] = text
    end

    local extra = {}   -- school bit -> { pct, sources = {} }
    local function addSchool(bit, pct, label)
        local x = extra[bit]
        if not x then x = { pct = 0, sources = {} }; extra[bit] = x end
        x.pct = x.pct + pct
        x.sources[#x.sources + 1] = label
    end

    local list = self.Talents[class]
    if list then
        local talents = readTalents()
        for _, e in ipairs(list) do
            local t = talents[e.tab .. ":" .. e.tier .. ":" .. e.col]
            if not t then
                -- talent info not loaded yet, or a different tree layout: say nothing here, UI refreshes on talent events
                if next(talents) then
                    noteAll("talent layout differs from the 3.3.5a data (" .. e.key .. " not found); not counted")
                end
            elseif t.maxRank ~= e.maxRank then
                noteAll("talent layout differs from the 3.3.5a data (" .. e.key .. "); not counted")
            elseif t.rank > 0 then
                local rank = t.rank
                local label = string.format("%s %d/%d", t.name, rank, t.maxRank)
                local active, why = true, nil

                if e.needs then
                    if not hasItemFor(e.needs) then
                        active, why = false, "needs " .. MBHS.NEEDS[e.needs].label .. " equipped"
                    end
                elseif e.dualWield and MBHS.Config.DWS_REQUIRES_OFFHAND and not hasOffhandWeapon() then
                    active, why = false, "needs an off-hand weapon"
                end

                addTalentEffect(res, e, rank, label, active, why)

                if e.dualWield and active and not hasOffhandWeapon() then
                    res.melee.notes[#res.melee.notes + 1] = t.name .. " is counted without an off-hand weapon (the server applies it that way)"
                end

                local sch = e.school or e.spellmod
                if sch and active then
                    local v = (e.school or e.spellmod).v[rank]
                    for _, bit in ipairs(SCHOOL_ORDER) do
                        if sch.mask % (bit * 2) >= bit then   -- bit test without bitlib
                            addSchool(bit, v, e.spellmod and (t.name .. " (" .. schoolName(bit) .. " spells only)") or t.name)
                        end
                    end
                end
            end
        end
    end

    -- racial / buffs
    local rac = self.Racials[race]
    if rac then
        res.melee.other[#res.melee.other + 1] = { label = rac.key .. " (racial)", pct = rac.m }
        res.ranged.other[#res.ranged.other + 1] = { label = rac.key .. " (racial)", pct = rac.m }
        res.spell.other[#res.spell.other + 1] = { label = rac.key .. " (racial)", pct = rac.s }
    elseif hasBuff(self.Racials.Draenei.spells) then
        local d = self.Racials.Draenei
        res.melee.other[#res.melee.other + 1] = { label = d.key .. " (aura)", pct = d.m }
        res.ranged.other[#res.ranged.other + 1] = { label = d.key .. " (aura)", pct = d.m }
        res.spell.other[#res.spell.other + 1] = { label = d.key .. " (aura)", pct = d.s }
    elseif otherDraenei() then
        local note = "A Draenei in your group gives " .. self.Racials.Draenei.key .. " +1% within 30 yards (not counted)"
        noteAll(note)
    end

    for _, k in ipairs({ "melee", "ranged", "spell" }) do
        local s = res[k]
        for _, o in ipairs(s.other) do s.otherPct = s.otherPct + o.pct end
        s.total = s.ratingPct + s.talentPct + s.otherPct
    end

    for _, bit in ipairs(SCHOOL_ORDER) do
        local x = extra[bit]
        if x then
            res.schools[#res.schools + 1] = { school = bit, name = schoolName(bit), extra = x.pct,
                                              total = res.spell.total + x.pct, sources = x.sources }
        end
    end

    return res
end

-- Multi-line tooltip text for one stat ("melee" | "ranged" | "spell"). Colour codes only.
function MBHS:TooltipText(kind, res)
    local s = res[kind]
    local L = {}
    local function add(t) L[#L + 1] = t end
    local GREEN, GREY, GOLD, WHITE, CLOSE = "|cff20ff20", "|cff9d9d9d", "|cffffd100", "|cffffffff", "|r"

    add(GOLD .. "MekBits Hit Stats" .. CLOSE)
    add(string.format("%sTotal hit chance: %.2f%%%s", WHITE, s.total, CLOSE))
    add(string.format("  Rating: %.2f%%  (%d)", s.ratingPct, s.rating))
    if s.talentPct ~= 0 then
        add(string.format("  Talents: %s+%.2f%%%s", GREEN, s.talentPct, CLOSE))
        for _, o in ipairs(s.on) do
            add(string.format("    %s: +%d%%", o.label, o.pct))
        end
    end
    if s.otherPct ~= 0 then
        add(string.format("  Other: %s+%.2f%%%s", GREEN, s.otherPct, CLOSE))
        for _, o in ipairs(s.other) do
            add(string.format("    %s: +%d%%", o.label, o.pct))
        end
    end
    if #s.off > 0 then
        add(GREY .. "  Not counted right now:" .. CLOSE)
        for _, o in ipairs(s.off) do
            add(string.format("%s    %s: +%d%% (%s)%s", GREY, o.label, o.pct, o.why or "?", CLOSE))
        end
    end
    if kind == "spell" and #res.schools > 0 then
        add(GOLD .. "  By school:" .. CLOSE)
        for _, sc in ipairs(res.schools) do
            add(string.format("    %s: %.2f%%  (+%d%% %s)", sc.name, sc.total, sc.extra, table.concat(sc.sources, ", ")))
        end
    end
    for _, n in ipairs(s.notes) do
        add(GREY .. "  " .. n .. CLOSE)
    end
    return table.concat(L, "\n")
end
