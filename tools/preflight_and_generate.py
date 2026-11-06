"""Preflight: every sheet cell filled, every cross-sheet reference resolved. Generates gml/st_tables.gml and the launcher's asset list only when clean."""
import json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHEETS = os.path.join(ROOT, "sheets")
sheets = {}
for fn in sorted(os.listdir(SHEETS)):
    if fn.endswith(".json"):
        with open(os.path.join(SHEETS, fn), encoding="utf8") as f:
            sheets[fn[:-5]] = json.load(f)

problems = []
cells = 0
for name, sh in sheets.items():
    for i, row in enumerate(sh["rows"]):
        for col in sh["columns"]:
            cells += 1
            if col not in row or row[col] is None or row[col] == "":
                problems.append(f"{name} row {i}: {col} unfilled")

sprites = {r["anim"] for r in sheets["mania_sprites"]["rows"]}
sfx = {r["name"] for r in sheets["mania_sfx"]["rows"]}
for r in sheets["sounds"]["rows"]:
    if r["plays"] not in ("keep", "mute") and r["plays"] not in sfx:
        problems.append(f"sounds {r['event']}: {r['plays']} not in mania_sfx")
for r in sheets["player_states"]["rows"]:
    if r["anim"] not in ("by-move", "taunt-pose", "hold-frame") and r["anim"] not in sprites:
        problems.append(f"player_states {r['state']}: {r['anim']} not in mania_sprites")
for r in sheets["taunt_poses"]["rows"]:
    if r["anim"] not in sprites:
        problems.append(f"taunt_poses {r['pose']}: {r['anim']} not in mania_sprites")
for r in sheets["moves"]["rows"]:
    if r["sound"] not in sfx:
        problems.append(f"moves {r['move']}: {r['sound']} not in mania_sfx")
    if r["land_sound"] != "none" and r["land_sound"] not in sfx:
        problems.append(f"moves {r['move']}: {r['land_sound']} not in mania_sfx")
hook_systems = {r["system"] for r in sheets["hooks"]["rows"]}
for r in sheets["hooks"]["rows"]:
    if r["system"] not in {s["system"] for s in sheets["systems"]["rows"]} | {"drawing", "collision", "runtime"}:
        problems.append(f"hooks {r['original']}: system {r['system']} not in systems")

main = open(os.path.join(ROOT, "gml", "st_main.gml"), encoding="utf8").read()
for r in sheets["hooks"]["rows"]:
    if f"function {r['wrapper']}(" not in main:
        problems.append(f"hooks {r['wrapper']}: no such function in st_main.gml")
for r in sheets["test_checks"]["rows"]:
    if f'"{r["name"]}"' not in main:
        problems.append(f"test_checks {r['name']}: st_main.gml never reports it")
for w in ["Global/Jump", "Global/Charge", "Global/Release", "Global/Roll", "Global/Skidding", "Global/DropDash", "Global/LoseRings", "Global/Ring", "Global/Flying"]:
    if w not in sfx:
        problems.append(f"st_main.gml uses {w}: not in mania_sfx")

for r in sheets["effects"]["rows"]:
    if f'"{r["name"]}"' not in main:
        problems.append(f"effects {r['name']}: st_main.gml never plays it")
for r in sheets["text"]["rows"]:
    if re.findall(r"\[(?![JDUMT]\])[^\]]*\]", r["text"]):
        problems.append(f"text {r['key']}: uses a button these characters don't use")
if sum(r["melty"] for r in sheets["test_checks"]["rows"]) > 12:
    problems.append("test_checks: Melty counts at most 12 checks")
print(f"preflight: {len(sheets)} sheets, {cells} cells, {len(problems)} problems")
for p in problems:
    print(" ", p)
if problems:
    sys.exit(1)

esc = lambda s: json.dumps(s)
out = ["// Generated from sheets/ by tools/preflight_and_generate.py. Change the sheet, not this file.", "function st_tables_init()", "{"]
for r in sheets["physics"]["rows"]:
    out.append(f"    global.st_k_{r['name']} = {r['value']};")
_pound = next(r for r in sheets["moves"]["rows"] if r["move"] == "ground_pound")
out.append(f"    global.st_pound_start = {esc(_pound['sound'])};")
out.append(f"    global.st_pound_land = {esc(_pound['land_sound'])};")
out.append("    global.st_sfx = ds_map_create();")
out.append("    global.st_ring_events = ds_map_create();")
for r in sheets["sounds"]["rows"]:
    if r["plays"] != "keep":
        out.append(f"    ds_map_set(global.st_sfx, {esc(r['event'])}, {esc(r['plays'])});")
    if r["rings"]:
        out.append(f"    ds_map_set(global.st_ring_events, {esc(r['event'])}, {r['rings']});")
out.append("    global.st_state_anim = ds_map_create();")
for r in sheets["player_states"]["rows"]:
    out.append(f"    ds_map_set(global.st_state_anim, {r['state']}, {esc(r['anim'])});")
poses = [r for r in sheets["taunt_poses"]["rows"] if r["kind"] == "pose"]
supers = [r for r in sheets["taunt_poses"]["rows"] if r["kind"] == "super"]
out.append("    global.st_taunt_pose_anim = [" + ", ".join(esc(r["anim"]) for r in poses) + "];")
out.append("    global.st_taunt_pose_frame = [" + ", ".join(str(r["frame"]) for r in poses) + "];")
out.append("    global.st_super_pose_anim = [" + ", ".join(esc(r["anim"]) for r in supers) + "];")
out.append("    global.st_melty_checks = [" + ", ".join(esc(r["name"]) for r in sheets["test_checks"]["rows"] if r["melty"]) + "];")
modes = sheets["characters"]["rows"]
out.append("    global.st_modes = [" + ", ".join("{ label: %s, ch: %s, name: %s, side: %s, jump: %s, lift: %s, ball: %s }" % (esc(r["label"]), esc(r["character"]), esc(r["name"]), "true" if r["sidekick"] == "yes" else "false", r["jump_mult"], r["feet_lift"], r["ball_lift"]) for r in modes) + "];")
_tails = next(r for r in modes if r["character"] == "Tails")
out.append(f"    global.st_tails_lift = {_tails['feet_lift']};")
out.append(f"    global.st_tails_ball = {_tails['ball_lift']};")
out.append("    global.st_text = ds_map_create();")
for r in sheets["text"]["rows"]:
    out.append(f"    ds_map_set(global.st_text, {esc(r['key'])}, {esc(r['text'])});")
out.append("    global.st_sound_files = [" + ", ".join(esc(n) for n in sorted(sfx)) + "];")
out.append("}")
with open(os.path.join(ROOT, "gml", "st_tables.gml"), "w", encoding="utf8", newline="\n") as f:
    f.write("\n".join(out) + "\n")

manifest = {
    "sprites": sorted(sprites),
    "sfx": [{"name": r["name"], "file": r["file"]} for r in sheets["mania_sfx"]["rows"]],
    "extra": [{"name": r["name"], "bin": r["bin"], "anim": r["anim"]} for r in sheets["effects"]["rows"]],
    "chars": [{"prefix": r["character"] + "|", "bin": r["bin"], "extra": [] if r["extra"] == "none" else r["extra"].split(",")} for r in sheets["characters"]["rows"] if r["character"] != "Sonic"],
}
with open(os.path.join(ROOT, "launcher", "assets.json"), "w", encoding="utf8", newline="\n") as f:
    json.dump(manifest, f, indent=1)
hooks = [{"original": r["original"], "wrapper": r["wrapper"]} for r in sheets["hooks"]["rows"]]
with open(os.path.join(ROOT, "patch", "hooks.json"), "w", encoding="utf8", newline="\n") as f:
    json.dump(hooks, f, indent=1)
print("generated gml/st_tables.gml, launcher/assets.json, patch/hooks.json")
