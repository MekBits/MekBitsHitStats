-- MekBitsHitStats / Data.lua
--
-- Every 3.3.5a talent and racial that changes hit chance, taken from Spell.dbc + Talent.dbc +
-- TalentTab.dbc (build 12340) and cross-checked against how the AzerothCore core applies them
-- (see README.md, "Where the data comes from"). Nothing here was written from memory;
-- test/tools/extract_hit_talents.py regenerates test/dbc_expected.lua and the harness fails if this
-- file drifts from it.
--
-- A talent is identified by its position (tab, tier, column), which is language independent.
-- tab = talent tree order (1..3), tier = row (1..7), col = column (1..4); GetTalentInfo(tab, i) returns
-- tier and column as its 3rd and 4th values. maxRank is checked at runtime, so a different talent
-- layout (another core or client patch) is skipped with a note instead of being counted wrongly.
--
-- Effect fields (value per rank, in percentage points):
--   m       aura 54  SPELL_AURA_MOD_HIT_CHANCE       -> melee AND ranged hit (the core adds it to both)
--   s       aura 55  SPELL_AURA_MOD_SPELL_HIT_CHANCE -> spell hit, all schools
--   school  aura 199 MOD_INCREASES_SPELL_PCT_TO_HIT  -> spell hit for the schools in `mask` (the core
--                                                       matches on school mask only, not on spell family)
--   spellmod aura 107 with misc 16 (SPELLMOD_RESIST_MISS_CHANCE) -> spell hit, but only for the spells
--                                                       in the talent's class mask; `mask` is the school
--                                                       those spells belong to (a close approximation)
-- needs: the DBC gives the spell an EquippedItemClass/SubClassMask; the core only keeps the aura while a
--        matching, unbroken item is equipped in main hand, off hand or ranged slot.

local MBHS = MekBitsHitStats or {}
MekBitsHitStats = MBHS

-- spell school bits (same as the core's SpellSchoolMask)
MBHS.SCHOOL = { PHYSICAL = 1, HOLY = 2, FIRE = 4, NATURE = 8, FROST = 16, SHADOW = 32, ARCANE = 64 }

-- Which GetItemInfo equipSlot values satisfy each `needs` rule. Derived from the item subclass masks in
-- the DBC (bit n = ITEM_SUBCLASS_WEAPON n), mapped onto language independent INVTYPE_* strings:
--   melee   Warrior Precision (mask 0x2a5f3): axe/mace/sword 1h+2h, polearm, staff, fist, dagger, spear
--   onehand Nerves of Cold Steel (0xa091): 1h axe/mace/sword, fist, dagger
--   rogue   Rogue Precision (0x5a09d): onehand + bow, gun, thrown, crossbow
-- (a fishing pole also reports INVTYPE_2HWEAPON; the DBC masks exclude it. Ignored on purpose.)
MBHS.NEEDS = {
    melee = {
        label = "a melee weapon",
        slots = { INVTYPE_WEAPON = 1, INVTYPE_2HWEAPON = 1, INVTYPE_WEAPONMAINHAND = 1, INVTYPE_WEAPONOFFHAND = 1 },
    },
    onehand = {
        label = "a one-handed weapon",
        slots = { INVTYPE_WEAPON = 1, INVTYPE_WEAPONMAINHAND = 1, INVTYPE_WEAPONOFFHAND = 1 },
    },
    rogue = {
        label = "a weapon or ranged weapon",
        slots = { INVTYPE_WEAPON = 1, INVTYPE_WEAPONMAINHAND = 1, INVTYPE_WEAPONOFFHAND = 1,
                  INVTYPE_RANGED = 1, INVTYPE_RANGEDRIGHT = 1, INVTYPE_THROWN = 1 },
    },
}

local S = MBHS.SCHOOL

-- id = Talent.dbc id; spells = rank spell ids (documentation + DBC cross-check)
MBHS.Talents = {
    MAGE = {
        { key = "Arcane Focus", id = 76, tab = 1, tier = 1, col = 2, maxRank = 3,
          spells = { 11222, 12839, 12840 },
          spellmod = { mask = S.ARCANE, v = { 1, 2, 3 } } },
        { key = "Precision", id = 1649, tab = 3, tier = 2, col = 3, maxRank = 3,
          spells = { 29438, 29439, 29440 },
          s = { 1, 2, 3 } },
    },
    PRIEST = {
        { key = "Shadow Focus", id = 463, tab = 3, tier = 2, col = 3, maxRank = 3,
          spells = { 15260, 15327, 15328 },
          spellmod = { mask = S.SHADOW, v = { 1, 2, 3 } } },
    },
    ROGUE = {
        { key = "Precision", id = 181, tab = 2, tier = 2, col = 4, maxRank = 5,
          spells = { 13705, 13832, 13843, 13844, 13845 },
          m = { 1, 2, 3, 4, 5 }, s = { 1, 2, 3, 4, 5 }, needs = "rogue" },
    },
    WARRIOR = {
        { key = "Precision", id = 1657, tab = 2, tier = 5, col = 1, maxRank = 3,
          spells = { 29590, 29591, 29592 },
          m = { 1, 2, 3 }, needs = "melee" },
    },
    WARLOCK = {
        { key = "Suppression", id = 1005, tab = 1, tier = 1, col = 2, maxRank = 3,
          spells = { 18174, 18175, 18176 },
          school = { mask = S.FIRE + S.SHADOW, v = { 1, 2, 3 } } },
    },
    SHAMAN = {
        { key = "Elemental Precision", id = 1685, tab = 1, tier = 6, col = 1, maxRank = 3,
          spells = { 30672, 30673, 30674 },
          school = { mask = S.FIRE + S.NATURE + S.FROST, v = { 1, 2, 3 } } },
        -- The DBC spell has no item requirement, and the core does not check for an off-hand weapon:
        -- on AzerothCore the bonus applies even with a single weapon. See MBHS.Config.DWS_REQUIRES_OFFHAND.
        { key = "Dual Wield Specialization", id = 1692, tab = 2, tier = 7, col = 1, maxRank = 3,
          spells = { 30816, 30818, 30819 },
          m = { 2, 4, 6 }, dualWield = true },
    },
    DRUID = {
        { key = "Balance of Power", id = 1783, tab = 1, tier = 6, col = 3, maxRank = 2,
          spells = { 33592, 33596 },
          school = { mask = S.HOLY + S.FIRE + S.NATURE + S.FROST + S.SHADOW + S.ARCANE, v = { 2, 4 } } },
    },
    DEATHKNIGHT = {
        { key = "Nerves of Cold Steel", id = 2022, tab = 2, tier = 2, col = 4, maxRank = 3,
          spells = { 49226, 50137, 50138 },
          m = { 1, 2, 3 }, needs = "onehand" },
        { key = "Virulence", id = 1932, tab = 3, tier = 1, col = 2, maxRank = 3,
          spells = { 48962, 49567, 49568 },
          s = { 1, 2, 3 } },
    },
    PALADIN = {
        { key = "Enlightened Judgements", id = 2191, tab = 1, tier = 10, col = 3, maxRank = 2,
          spells = { 53556, 53557 },
          m = { 2, 4 }, s = { 2, 4 } },
    },
    HUNTER = {
        { key = "Focused Aim", id = 2197, tab = 2, tier = 1, col = 2, maxRank = 3,
          spells = { 53620, 53621, 53622 },
          m = { 1, 2, 3 } },
    },
}

-- Racial: Heroic Presence. Spell 28878 (player racial; 6562 is the older twin), both with
-- aura 54 + aura 55 = +1% melee, ranged and spell hit, applied to the caster and as a party
-- area aura (effect 35, radius index 10) to group members.
MBHS.Racials = {
    Draenei = { key = "Heroic Presence", spells = { 28878, 6562 }, m = 1, s = 1 },
}

-- Settings that mirror server behaviour and may change if the core is changed.
MBHS.Config = {
    -- AzerothCore (checked on core 7b2cecef9) gives Shaman Dual Wield Specialization its hit even
    -- when no off-hand weapon is equipped. Set true to count it only while dual wielding (retail text).
    DWS_REQUIRES_OFFHAND = false,
}
