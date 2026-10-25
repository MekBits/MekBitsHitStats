"""Extract every talent/spell that gives hit from 3.3.5a DBC files.

usage: py -3 -I extract_hit_talents.py <dbc-dir> [spell-id ...]

Reads Spell.dbc, Talent.dbc and TalentTab.dbc (build 12340 layout) and prints, for every
Talent.dbc rank spell, the effects that touch hit chance:
  54  SPELL_AURA_MOD_HIT_CHANCE            (melee + ranged %, flat)
  55  SPELL_AURA_MOD_SPELL_HIT_CHANCE      (spell %, flat)
  199 SPELL_AURA_MOD_INCREASES_SPELL_PCT_TO_HIT (spell %, by school mask in MiscValue)
  107/108 with MiscValue 16 = SPELLMOD_RESIST_MISS_CHANCE (spell-class-mask limited spell hit)
  189 SPELL_AURA_MOD_RATING with a CR_HIT_* bit (talent that gives hit *rating*)
Also prints extra spell ids given on the command line (racials, buffs).
"""
import struct
import sys
import os

CLASS = {1: "WARRIOR", 2: "PALADIN", 4: "HUNTER", 8: "ROGUE", 16: "PRIEST", 32: "DEATHKNIGHT",
         64: "SHAMAN", 128: "MAGE", 256: "WARLOCK", 1024: "DRUID"}


def load(path, nf):
    d = open(path, "rb").read()
    magic, n, f, rs, ss = struct.unpack("<4s4I", d[:20])
    assert magic == b"WDBC" and f == nf and rs == nf * 4, (path, magic, n, f, rs)
    st = d[20 + n * rs:]
    rows = {}
    for i in range(n):
        r = struct.unpack_from("<%dI" % nf, d, 20 + i * rs)
        rows[r[0]] = r
    return rows, st


def cstr(st, o):
    e = st.index(b"\0", o)
    return st[o:e].decode("utf-8", "replace")


def sint(v):
    return v - (1 << 32) if v >= (1 << 31) else v


# Spell.dbc 3.3.5a field indices
F_ATTR0 = 4
F_EQ_CLASS, F_EQ_SUB, F_EQ_INV = 68, 69, 70
F_EFFECT, F_DIE, F_BASE, F_AURA, F_MISC = 71, 74, 80, 95, 110
F_MASK = 122  # 3 effects * 3 uint32
F_NAME, F_RANK, F_DESC = 136, 153, 170
F_FAMILY, F_FLAGS = 208, 209
F_SCHOOL = 227
F_STANCES = 12
F_CASTER_AURASPELL = 24


def effects(sp, r):
    out = []
    for i in range(3):
        eff = r[F_EFFECT + i]
        if eff == 0:
            continue
        base = sint(r[F_BASE + i])
        die = sint(r[F_DIE + i])
        pts = base + (1 if die <= 1 else 0)
        out.append(dict(i=i, eff=eff, aura=r[F_AURA + i], pts=pts, base=base, die=die,
                        misc=sint(r[F_MISC + i]),
                        mask=tuple(r[F_MASK + i * 3 + j] for j in range(3))))
    return out


def interesting(e):
    if e["eff"] != 6 and e["eff"] != 35:  # APPLY_AURA / APPLY_AREA_AURA_PARTY
        return False
    a = e["aura"]
    if a in (54, 55, 199):
        return True
    if a in (107, 108) and e["misc"] == 16:
        return True
    if a == 189 and (e["misc"] & (1 << 5 | 1 << 6 | 1 << 7)):  # CR_HIT_MELEE/RANGED/SPELL = 5,6,7? see below
        return True
    return False


def main():
    d = sys.argv[1]
    sp, sst = load(os.path.join(d, "Spell.dbc"), 234)
    tal, _ = load(os.path.join(d, "Talent.dbc"), 23)
    tab, tst = load(os.path.join(d, "TalentTab.dbc"), 24)
    # CR_HIT_MELEE = 5, CR_HIT_RANGED = 6, CR_HIT_SPELL = 7 in the *server* enum (0-based);
    # the client's 1-based GetCombatRating constants are 6/7/8. MiscValue is a bit mask over the 0-based enum.
    print("# talents (Talent.dbc) whose rank spells touch hit")
    seen = set()
    rows = []
    for tid, t in sorted(tal.items()):
        tabid, tier, col = t[1], t[2], t[3]
        tt = tab[tabid]
        cm = tt[20]
        tabname = cstr(tst, tt[1])
        order = tt[22]
        for rank in range(9):
            spid = t[4 + rank]
            if not spid:
                continue
            r = sp.get(spid)
            if not r:
                continue
            es = [e for e in effects(sp, r) if interesting(e)]
            if es:
                rows.append((CLASS.get(cm, str(cm)), order, tabname, tier, col, tid, rank + 1, spid,
                             cstr(sst, r[F_NAME]), r, es))
    for (cls, order, tabname, tier, col, tid, rank, spid, name, r, es) in rows:
        print("%-11s tab%d %-14s r%d c%d talent=%-4d rank=%d spell=%-6d %-26s eqClass=%d eqSub=0x%x fam=%d"
              % (cls, order, tabname, tier, col, tid, rank, spid, name, sint(r[F_EQ_CLASS]), r[F_EQ_SUB], r[F_FAMILY]))
        for e in es:
            print("      eff%d aura=%d pts=%d misc=0x%x mask=%s" % (e["i"], e["aura"], e["pts"], e["misc"] & 0xffffffff,
                                                                  ",".join("%08x" % m for m in e["mask"])))
        print("      desc:", cstr(sst, r[F_DESC]).replace("\n", " ")[:200])
    print("\n# other spells")
    for a in sys.argv[2:]:
        spid = int(a)
        r = sp.get(spid)
        if not r:
            print(spid, "missing")
            continue
        print(spid, cstr(sst, r[F_NAME]), "|", cstr(sst, r[F_RANK]), "| eqClass", sint(r[F_EQ_CLASS]), "eqSub 0x%x" % r[F_EQ_SUB],
              "school 0x%x" % r[F_SCHOOL], "stances 0x%x" % r[F_STANCES])
        for e in effects(sp, r):
            print("      eff%d effect=%d aura=%d pts=%d misc=0x%x mask=%s" % (e["i"], e["eff"], e["aura"], e["pts"], e["misc"] & 0xffffffff,
                                                                            ",".join("%08x" % m for m in e["mask"])))
        print("      desc:", cstr(sst, r[F_DESC]).replace("\n", " ")[:300])




# ---------------------------------------------------------------------------------------------
# --lua OUT: machine readable list for the test harness (test/dbc_expected.lua)
# ---------------------------------------------------------------------------------------------
def write_lua(d, out):
    sp, sst = load(os.path.join(d, "Spell.dbc"), 234)
    tal, _ = load(os.path.join(d, "Talent.dbc"), 23)
    tab, tst = load(os.path.join(d, "TalentTab.dbc"), 24)
    excluded = {
        788: "Insect Swarm: -3% hit on the enemy target, not on the druid",
        1309: "Survival Tactics: lowers the resist chance of Feign Death and traps (spellmod on those spells only)",
    }
    needs_by_mask = {0x2a5f3: "melee", 0xa091: "onehand", 0x5a09d: "rogue"}
    lines = ["-- GENERATED by test/tools/extract_hit_talents.py --lua; do not edit",
             "-- source: Spell.dbc / Talent.dbc / TalentTab.dbc (3.3.5a build 12340 layout)",
             "return {", "  talents = {"]
    for tid, t in sorted(tal.items()):
        tt = tab[t[1]]
        cls = CLASS.get(tt[20])
        ranks = []
        for rank in range(9):
            if t[4 + rank]:
                ranks.append(t[4 + rank])
        per = []
        hit = False
        for spid in ranks:
            r = sp[spid]
            m = s = school = sm = 0
            mask = 0
            for e in effects(sp, r):
                if not interesting(e):
                    continue
                hit = True
                if e["aura"] == 54 and e["pts"] > 0:
                    m = e["pts"]
                elif e["aura"] == 55:
                    s = e["pts"]
                elif e["aura"] == 199:
                    school = e["pts"]
                    mask = e["misc"] & 0xffffffff
                elif e["aura"] in (107, 108):
                    sm = e["pts"]
            per.append((spid, m, s, school, sm, mask, sint(r[F_EQ_CLASS]), r[F_EQ_SUB]))
        if not hit:
            continue
        if not any(p[1] or p[2] or p[3] or p[4] for p in per) and tid not in excluded:
            continue
        name = cstr(sst, sp[ranks[0]][F_NAME])
        lines.append("    { id = %d, class = %r, name = %r, tab = %d, tier = %d, col = %d, maxRank = %d," %
                     (tid, cls, name, tt[22] + 1, t[2] + 1, t[3] + 1, len(ranks)))
        lines.append("      spells = { %s }," % ", ".join(str(p[0]) for p in per))
        if tid in excluded:
            lines.append("      excluded = %r }," % excluded[tid])
            continue
        lines.append("      m = { %s }, s = { %s }, school = { %s }, schoolMask = %d, spellmod = { %s },"
                     % (", ".join(str(p[1]) for p in per), ", ".join(str(p[2]) for p in per),
                        ", ".join(str(p[3]) for p in per), per[0][5], ", ".join(str(p[4]) for p in per)))
        eqc, eqs = per[0][6], per[0][7]
        lines.append("      eqClass = %d, eqSub = %d, needs = %s }," %
                     (eqc, eqs, ('%r' % needs_by_mask[eqs]) if eqc >= 0 else "nil"))
    lines.append("  },")
    # non-talent racial
    lines.append("  racials = {")
    for spid in (6562, 28878):
        r = sp[spid]
        m = s = 0
        for e in effects(sp, r):
            if e["aura"] == 54:
                m = e["pts"]
            if e["aura"] == 55:
                s = e["pts"]
        lines.append("    [%d] = { name = %r, m = %d, s = %d }," % (spid, cstr(sst, r[F_NAME]), m, s))
    lines.append("  },")
    lines.append("}")
    open(out, "w", encoding="utf-8", newline="\n").write("\n".join(lines) + "\n")


if "--lua" in sys.argv:
    i = sys.argv.index("--lua")
    out = sys.argv[i + 1]
    d = sys.argv[1]
    write_lua(d, out)
    print("wrote", out)
    sys.exit(0)

if __name__ == "__main__":
    main()
