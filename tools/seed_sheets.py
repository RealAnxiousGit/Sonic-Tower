"""One-off: seeds sheets/ from the decompiled game (event names, state table). The sheets are the truth afterwards."""
import json, os, re, sys, glob

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DECOMP = os.path.join(os.environ["LOCALAPPDATA"], "SonicTowerLab", "decomp", "CodeEntries")
OUT = os.path.join(ROOT, "sheets")
os.makedirs(OUT, exist_ok=True)


def save(name, rows, columns, note):
    with open(os.path.join(OUT, name + ".json"), "w", encoding="utf8") as f:
        json.dump({"sheet": name, "note": note, "columns": columns, "rows": rows}, f, indent=1)


# ---- sounds: every Pizza Tower sound effect event, what it plays in Sonic Tower
events = set()
for path in glob.glob(os.path.join(DECOMP, "*.gml")):
    with open(path, encoding="utf8", errors="ignore") as f:
        events.update(m.lower() for m in re.findall(r'"(event:/[sS]fx/[^"]+)"', f.read()))

G = "Global/"
S = "Stage/"
exact = {
    # Sonic's own moves and hits: Mania's sound
    "pep/jump": G + "Jump", "pep/rampjump": G + "Jump", "pep/superjump": G + "Flying", "pep/superjumpcancel": G + "Release",
    "pep/hurt": G + "Hurt", "pep/step": "mute", "pep/stepinshit": "mute", "pep/mach": "mute", "pep/machroll": G + "Roll",
    "pep/machslideboost": G + "Release", "pep/crouchslide": G + "Roll", "pep/backslide": G + "Skidding", "pep/slip": G + "Skidding",
    "pep/slipbump": S + "Impact2", "pep/slipend": "mute", "pep/spin": G + "Roll", "pep/tumble": G + "Roll", "pep/dive": G + "Roll",
    "pep/bump": S + "Impact3", "pep/bumpwall": S + "Impact3", "pep/hitwall": S + "Impact3", "pep/mach2bump": G + "Destroy",
    "pep/punch": G + "Destroy", "pep/uppercut": G + "Destroy", "pep/suplexdash": G + "Roll", "pep/grabcancel": "mute",
    "pep/groundpound": S + "Impact4", "pep/freefall": G + "Roll", "pep/splat": S + "Impact2", "pep/break": S + "LedgeBreak",
    "pep/box": S + "LedgeBreak", "pep/parry": G + "InstaShield", "pep/taunt": G + "Twinkle", "pep/supertaunt": G + "SpecialWarp",
    "pep/gotsupertaunt": G + "HyperRing", "pep/rollgetup": "mute", "pep/cross": G + "Twinkle", "pep/pray": "mute",
    "pep/burn": G + "FireShield", "pep/fireass": G + "FireDash", "pep/screamboss": "mute",
    # Pickups and the world's common sounds
    "misc/collect": G + "Ring", "misc/collectpizza": G + "Ring", "misc/collectgiantpizza": G + "HyperRing", "misc/collecttoppin": G + "SpecialRing",
    "misc/bellcollect": G + "Ring", "misc/bellcollectbig": G + "HyperRing", "misc/toppingot": G + "SpecialRing", "misc/foundtreasure": G + "SpecialRing",
    "misc/kashing": G + "ScoreAdd", "misc/kashingcombo": G + "ScoreTotal", "misc/checkpoint": G + "Starpost", "misc/secretfound": G + "SpecialWarp",
    "misc/secretenter": G + "Warp", "misc/secretexit": G + "Warp", "misc/lapenter": G + "Warp", "misc/lap2start": G + "SpecialWarp",
    "misc/breakblock": S + "LedgeBreak", "misc/breakmetal": S + "LedgeBreak3", "misc/rockbreak": S + "LedgeBreak3", "misc/breakice": S + "LedgeBreak",
    "misc/breakicebig": S + "LedgeBreak3", "misc/explosion": S + "Explosion2", "misc/superspring": G + "Spring", "misc/mushroombounce": G + "Spring",
    "misc/dashpad": G + "Release", "misc/keyunlock": S + "Button", "misc/switchstart": S + "Button", "misc/switchend": S + "Clack",
    "misc/door": S + "Clack", "misc/watersplash": S + "Splash", "misc/waterslidesplash": S + "Splash", "misc/transfo": S + "Transform",
    "misc/detransfo": G + "Teleport", "misc/teleporterstart": G + "Teleport", "misc/teleporterend": G + "Teleport", "misc/bosskey": G + "SpecialRing",
    "misc/bossbeaten": G + "SignPost", "misc/bossdefeattonk": S + "BossHit", "misc/bossvulnerable": S + "Beep", "misc/timerbegin": S + "Warning",
    "misc/timercount": S + "Beep", "misc/timerend": S + "Warning", "misc/escaperumble": S + "Rumble", "misc/gaterise": S + "Rumble",
    "misc/balloonpop": G + "Destroy", "misc/bottlepop": G + "Destroy", "misc/cardcollect": G + "Ring",
    "enemies/stomp": G + "Destroy", "enemies/killingblow": G + "Destroy", "enemies/kill": G + "Destroy", "enemies/hit": S + "BossHit",
    "ui/select": G + "MenuAccept", "ui/step": G + "MenuBleep", "ui/back": G + "MenuWoosh",
}
rows = []
for ev in sorted(events):
    key = ev[len("event:/sfx/") :]
    folder = key.split("/")[0]
    if key in exact:
        target = exact[key]
        why = "mania" if target != "mute" else "peppino-sound-removed"
    elif folder in ("voice",):
        target, why = "mute", "peppino-voice-removed"
    elif folder in ("ui",) and any(k in key for k in ("select", "accept", "confirm")):
        target, why = G + "MenuAccept", "mania"
    elif folder in ("ui",) and any(k in key for k in ("move", "step", "hover", "tick", "cursor")):
        target, why = G + "MenuBleep", "mania"
    elif folder == "enemies" and any(k in key for k in ("killing", "kill", "death", "die")):
        target, why = G + "Destroy", "mania"
    else:
        target, why = "keep", "no-mania-match-keeps-pizza-tower"
    ring = 1 if key in ("misc/collect", "misc/bellcollect", "misc/cardcollect") else 10 if key in ("misc/collectpizza", "misc/bellcollectbig") else 50 if key == "misc/collectgiantpizza" else 0
    rows.append({"event": ev, "plays": target, "reason": why, "rings": ring})
save("sounds", rows, ["event", "plays", "reason", "rings"], "Every Pizza Tower sound effect event. plays: Mania WAV under Data/SoundFX, or mute, or keep (the game's own). Music events are never touched.")

# ---- assets
wavs = sorted({r["plays"] for r in rows if "/" in r["plays"]} | {G + "Charge", G + "Release", G + "DropDash", G + "LoseRings", G + "Skidding", G + "Ring"})
save("mania_sfx", [{"name": w, "file": f"Data/SoundFX/{w}.wav"} for w in wavs], ["name", "file"], "Mania sounds read from the player's Data.rsdk at launch.")

anim_used = [
    ("Idle", "stand"), ("Bored 1", "taunt"), ("Bored 2", "taunt"), ("Look Up", "up"), ("Crouch", "crouch"), ("Walk", "walk"), ("Jog", "jog"), ("Run", "run"),
    ("Dash", "top speed"), ("Jump", "ball"), ("Spring Twirl", "springs"), ("Spring Diagonal", "springs"), ("Skid", "skid"), ("Skid Turn", "skid end"),
    ("Spindash", "charge"), ("Dropdash", "drop dash"), ("Push", "push"), ("Hurt", "hurt"), ("Die", "game over"), ("Balance 1", "ledge"), ("Balance 2", "ledge"),
    ("Spring CS", "taunt"), ("Stand CS", "taunt"), ("Fan", "taunt"), ("Victory", "taunt"), ("Outta Here", "taunt"), ("Hang", "ladders"), ("Hang Move", "ladders"),
    ("Pole Swing V", "poles"), ("Turntable", "taunt"), ("Twister", "taunt"), ("Spiral Run", "wall run"), ("Shimmy Move", "ledge"), ("Breathe", "taunt"),
    ("Ride", "rides"), ("Cling", "cling"), ("Transform", "super taunt"), ("Fly", "fly"),
]
save("mania_sprites", [{"anim": a, "use": u, "source": "Data/Sprites/Players/Sonic.bin"} for a, u in anim_used], ["anim", "use", "source"], "Sonic's animations read from the player's Data.rsdk at launch.")

# ---- player states
with open(os.path.join(DECOMP, "gml_Object_obj_player_Step_0.gml"), encoding="utf8") as f:
    lines = f.read().split("\n")[:760]
table = []
for i, line in enumerate(lines[:-1]):
    m = re.search(r"case UnknownEnum\.Value_(\d+):", line)
    n = re.match(r"\s+(scr_\w+)\(\)", lines[i + 1])
    if m and n:
        table.append((int(m.group(1)), n.group(1)))
sonic = {0, 92, 103, 104, 121, 65, 100, 101, 102, 105}
rules = [
    (r"hurt|bump|stunned|faceplant|ejected|thrown|hit$", "Hurt"), (r"gameover|bossdefeat", "Die"), (r"victory|keyget|gottreasure|smirk|levelcomplete", "Victory"),
    (r"ladder|hang", "Hang Move"), (r"Sjump|highjump|trickjump|rampjump", "Spring Twirl"), (r"climbwall", "Spiral Run"), (r"grind|current|tube|portal", "Ride"),
    (r"freefall|tumble|roll|slipnslide|chainsawbump|superslam|slam|machfreefall|punch|tackle|shoulder|lunge|dashtumble|fireass|firemouth|bombpep|cheese|boxxed|barrel|knight|ghost|mort|rocket|balloon|bee|antigrav|string|trash|motorcycle|skateboard|ride|boulder|pogo|fightball|handstand|slap|facestomp|jetpack|ratmount|noisecrusher|machcancel|shoulderbash|grab", "Jump"),
    (r"backbreaker", "taunt-pose"), (r"door|comingoutdoor|titlescreen|actor|animation|gotoplayer|backtohub|graffiti|bossintro|arenaintro|transitioncutscene|taxi|parry|pummel", "Idle"),
]
srows = []
for sid, script in sorted(table):
    if sid in sonic:
        handler, anim = "sonic", "by-move"
    else:
        handler = "game"
        anim = next((a for rx, a in rules if re.search(rx, script)), "Idle")
    srows.append({"state": sid, "script": script, "handler": handler, "anim": anim})
save("player_states", srows, ["state", "script", "handler", "anim"], "Every player state in obj_player's Step. handler sonic: Sonic's physics runs it; game: Pizza Tower's logic runs it, Sonic is drawn with anim.")
