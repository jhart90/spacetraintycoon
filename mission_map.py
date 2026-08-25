#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
mission_map.py — extract every mission's definition, trigger, objectives, and
completion effects straight from build_game.py, so the mission flow can be
reviewed without hand-reading the source.

Usage:
    python -X utf8 mission_map.py            # full table, source order
    python -X utf8 mission_map.py --md       # GitHub-flavoured markdown table
    python -X utf8 mission_map.py <id>       # just one mission (e.g. produce_iron)

It reads three regions of build_game.py:
  1. MISSION_DEFS[]                  -> id, name, objectives, reward, prerequisite
  2. pendingMissionIntros.push(...)  -> intro TRIGGER (nearest preceding `if(`)
  3. the completion sweep            -> `if(m.id==='X'){...}` completion EFFECTS

Heuristic, not a JS parser: it relies on build_game.py's one-mission-per-block
formatting. If a future refactor changes that shape, adjust the markers below.
"""
import os, re, sys

ROOT = os.path.dirname(os.path.abspath(__file__))
SRC  = open(os.path.join(ROOT, "build_game.py"), encoding="utf-8").read()
LINES = SRC.split("\n")

# ── 1. MISSION_DEFS: id, name, objectives, reward, prerequisite, details ──────
def _slice(start_marker, depth_open="[", depth_close="]"):
    i = SRC.index(start_marker)
    j = SRC.index(depth_open, i)
    depth, k = 0, j
    while k < len(SRC):
        if SRC[k] == depth_open: depth += 1
        elif SRC[k] == depth_close:
            depth -= 1
            if depth == 0: return SRC[j:k+1]
        k += 1
    return SRC[j:]

defs_blob = _slice("const MISSION_DEFS=[")

# Split into per-mission blocks on the TOP-LEVEL `{id:'...'` boundaries only
# (each mission line is indented exactly 2 spaces; nested objective entries are
# indented deeper, so an anchored 2-space match skips them).
blocks, idxs = [], [m.start() for m in re.finditer(r"(?m)^  \{id:'[a-z_]+',", defs_blob)]
for a, b in zip(idxs, idxs[1:] + [len(defs_blob)]):
    blocks.append(defs_blob[a:b])

def field(block, name, default=None):
    m = re.search(name + r":\s*'((?:[^'\\]|\\.)*)'", block)
    if m: return m.group(1)
    m = re.search(name + r":\s*([0-9]+(?:\.[0-9]+)?|null|true|false)", block)
    return m.group(1) if m else default

missions = []
for b in blocks:
    mid = re.search(r"\{id:'([a-z_]+)'", b).group(1)
    objs = [(re.search(r"id:'([a-z0-9_]+)'", o).group(1),
             re.search(r"text:'((?:[^'\\]|\\.)*)'", o).group(1))
            for o in re.findall(r"\{id:'[a-z0-9_]+',\s*text:'(?:[^'\\]|\\.)*'\}", b)]
    missions.append(dict(
        id=mid,
        name=field(b, "name", mid),
        prerequisite=field(b, "prerequisite"),
        reward=field(b, "reward"),
        rewardText=field(b, "rewardText"),
        timeLimit=field(b, "timeLimit"),
        startsAfter=field(b, "startsAfter"),
        details=field(b, "details", ""),
        objectives=objs,
    ))
by_id = {m["id"]: m for m in missions}

# ── 2. Triggers: the `if(...)` guarding each pendingMissionIntros.push ─────────
triggers = {}
for i, l in enumerate(LINES):
    m = re.search(r"pendingMissionIntros\.push\(\{defId:'([a-z_]+)'", l)
    if not m: continue
    did = m.group(1)
    # Walk back to the nearest line containing `if(` (the gate condition).
    cond = None
    for j in range(i, max(0, i - 8), -1):
        if "if(" in LINES[j]:
            cond = LINES[j].strip(); break
    triggers.setdefault(did, []).append((i + 1, cond or l.strip()))

# ── 3. Completion effects: `if(m.id==='X'){ ... }` in the completion sweep ─────
completion = {}
sweep_start = next((i for i, l in enumerate(LINES) if "MISSION COMPLETE:" in l), 0)
i = sweep_start
while i < min(len(LINES), sweep_start + 220):
    m = re.search(r"if\(m\.id==='([a-z_]+)'", LINES[i])
    if m:
        did, body = m.group(1), [LINES[i].strip()]
        # capture the braced block if it spans multiple lines
        depth = LINES[i].count("{") - LINES[i].count("}")
        j = i + 1
        while depth > 0 and j < len(LINES) and j < i + 25:
            body.append(LINES[j].strip()); depth += LINES[j].count("{") - LINES[j].count("}"); j += 1
        completion.setdefault(did, []).append("\n        ".join(body))
        i = j
    else:
        i += 1

# ── render ────────────────────────────────────────────────────────────────────
def reward_str(m):
    if m["reward"] and m["reward"] != "null": return "+" + format(int(m["reward"]), ",") + " cr"
    if m["rewardText"]: return m["rewardText"]
    return "—"

def render(m, md=False):
    out = []
    h = ("## " if md else "") + f"{m['name']}  ({m['id']})"
    out.append(h)
    meta = []
    if m["prerequisite"]: meta.append(f"prerequisite: {m['prerequisite']}")
    if m["timeLimit"] and m["timeLimit"] != "null": meta.append(f"time limit: {m['timeLimit']} SD")
    if m["startsAfter"]: meta.append(f"startsAfter: {m['startsAfter']} SD")
    if meta: out.append("  [" + ", ".join(meta) + "]")
    out.append(f"  REWARD: {reward_str(m)}")
    out.append("  TRIGGER:")
    trs = triggers.get(m["id"])
    if m["prerequisite"]:
        out.append(f"    - prerequisite chain: introduced when '{m['prerequisite']}' completes")
    if trs:
        for ln, cond in trs: out.append(f"    - L{ln}: {cond}")
    elif not m["prerequisite"]:
        out.append("    - (no pendingMissionIntros.push found — dormant / removed?)")
    out.append("  OBJECTIVES:")
    for oid, txt in m["objectives"]:
        out.append(f"    - [{oid}] {txt}")
    out.append("  ON COMPLETE:")
    out.append("    - award reward + green Mission-Reward popup (if +credits) + chat 'MISSION COMPLETE'")
    for body in completion.get(m["id"], []):
        out.append("    - " + body)
    if not completion.get(m["id"]):
        out.append("    - (no special effect beyond reward + prerequisite-chain)")
    return "\n".join(out)

def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    md = "--md" in sys.argv
    sel = [by_id[a] for a in args if a in by_id] or missions
    print(f"# {len(missions)} missions in MISSION_DEFS (build_game.py)\n")
    print(("\n\n" if md else "\n" + "-" * 78 + "\n").join(render(m, md) for m in sel))

if __name__ == "__main__":
    main()
