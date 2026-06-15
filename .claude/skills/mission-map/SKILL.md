---
name: mission-map
description: >
  Extract and list every Space Train Tycoon mission straight from build_game.py —
  each mission's intro TRIGGER (what causes it to appear), its OBJECTIVES, its
  REWARD, its prerequisite, and what completing it TRIGGERS (unlocks, chained
  missions, world effects). Use this whenever the user asks to "list the missions",
  "what triggers mission X", "what does completing X do", "show the mission flow /
  chain", "mission objectives", "what unlocks the Class J engine", or wants to audit
  or rebalance the mission progression. Always prefer this over hand-reading
  MISSION_DEFS — the source is large and the triggers/completion effects are
  scattered across updateMissions.
---

# Mission Map Skill

`mission_map.py` parses `build_game.py` and prints, per mission: name/id,
prerequisite, reward, intro **trigger**, **objectives**, and **on-complete**
effects. It reads three regions so nothing has to be eyeballed:

1. `MISSION_DEFS[]` → id, name, objectives, reward/rewardText, prerequisite, timeLimit
2. every `pendingMissionIntros.push({defId:'X'…})` → the nearest preceding `if(` gate (the trigger)
3. the completion sweep in `updateMissions` → each `if(m.id==='X'){…}` block (the effects)

## Usage

```
cd "C:\Users\jackh\Desktop\Claude\Train Game"
python -X utf8 mission_map.py            # full table, source order
python -X utf8 mission_map.py --md       # markdown headings (good for pasting)
python -X utf8 mission_map.py produce_iron upgrade_station   # only these ids
```

## How to answer with it

1. Run the script (whole table, or pass the specific mission id(s) the user named).
2. Relay the relevant rows. The script prints raw JS for triggers/effects — translate
   those into plain English in the reply (e.g. `_ironCarUnlockedMs>0 && …>=10000`
   → "10 s after the Iron Car unlocks").
3. Every mission also implicitly does, on completion: pay its reward, show the green
   Mission-Reward popup (if it grants credits), log "MISSION COMPLETE", and introduce
   any mission whose `prerequisite` is this one (the prerequisite chain). The script
   notes this on every entry so it isn't forgotten.

## Notes / gotchas

- It's a heuristic extractor (regex over JS formatting), **not** a JS parser. It relies on
  build_game.py keeping one mission per 2-space-indented `{id:'…'}` block. If a refactor
  changes that shape, fix the `^  \{id:` boundary regex and the `MISSION COMPLETE:` /
  `if(m.id===` markers near the top of `mission_map.py`.
- A mission with **no** `pendingMissionIntros.push` and **no** prerequisite is dormant /
  removed (e.g. `visit_planet` — still in MISSION_DEFS but never introduced).
- Some missions have BOTH a prerequisite chain AND an explicit timer gate (e.g.
  `upgrade_station`); whichever fires first wins (the others are guarded by `_missionPending`).
- Trigger conditions that span multiple lines only show their leading `if(` line — open
  the cited `Lxxxx` line in build_game.py if the full multi-line condition is needed.
