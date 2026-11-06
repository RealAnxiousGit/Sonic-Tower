// Sonic Tower's patch: run by UndertaleModTool's CLI on a copy held in memory, saved to a separate data file.
// The player's own data.win is only read.
using System;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;
using UndertaleModLib;
using UndertaleModLib.Compiler;
using UndertaleModLib.Models;

EnsureDataLoaded();

string here = Path.GetDirectoryName(ScriptPath) ?? ".";
string gmlDir = Path.Combine(here, "gml");
string Gml(string name) => File.ReadAllText(Path.Combine(gmlDir, name + ".gml"));

// 1. Sonic's code, and the small additions to the game's own
var import = new CodeImportGroup(Data);
import.QueueReplace("gml_GlobalScript_st_tables", Gml("st_tables"));
import.QueueReplace("gml_GlobalScript_st_main", Gml("st_main"));
// Sonic Tower keeps its own saves
import.QueueFindReplace("gml_GlobalScript_scr_savesystem", "return \"saves\";", "return \"sonictower_saves\";");
// the credits stay in the player's Pizza Tower folder, read through the launcher's link to it
import.QueueFindReplace("gml_GlobalScript_scr_lang", "scr_lang_get_file_arr(\"credits.txt\")", "scr_lang_get_file_arr(\"pizzatower/credits.txt\")");
import.QueueFindReplace("gml_GlobalScript_scr_lang", "scr_lang_get_file_arr(\"noisecredits.txt\")", "scr_lang_get_file_arr(\"pizzatower/noisecredits.txt\")");
// Sonic on the TV, the ring count under it
import.QueueAppend("gml_Object_obj_tv_Draw_64", "st_draw_hud();\n");
// Sonic in Peppino's place on the file select
import.QueueFindReplace("gml_Object_obj_mainmenu_Draw_0", "draw_sprite_ext(sprite_index, image_index, _x, _y, image_xscale, image_yscale, image_angle, image_blend, image_alpha);", "st_menu_draw(_x, _y);");
// and on the white fade into the results
import.QueueFindReplace("gml_Object_obj_endlevelfade_Draw_0", "draw_sprite_ext(sprite_index, image_index, x, y, xscale, yscale, image_angle, image_blend, image_alpha);", "st_fade_draw();");
import.Import();

// 2. The game's calls go to Sonic's wrappers: only the call's target changes, in compiled code, nothing is recompiled.
var pairs = System.Text.Json.JsonDocument.Parse(File.ReadAllText(Path.Combine(here, "hooks.json"))).RootElement;
var map = new System.Collections.Generic.Dictionary<UndertaleFunction, UndertaleFunction>();
UndertaleFunction FindFn(string name)
{
    var f = Data.Functions.ByName("gml_Script_" + name) ?? Data.Functions.ByName(name);
    if (f == null) throw new ScriptException("Function not found: " + name);
    return f;
}
foreach (var p in pairs.EnumerateArray())
    map[FindFn(p.GetProperty("original").GetString())] = FindFn(p.GetProperty("wrapper").GetString());

int swapped = 0;
foreach (var code in Data.Code)
{
    if (code == null || code.ParentEntry != null) continue;
    string name = code.Name.Content;
    if (name.StartsWith("gml_GlobalScript_st_")) continue;
    foreach (var ins in code.Instructions)
    {
        if (ins.Kind == UndertaleInstruction.Opcode.Call && ins.ValueFunction != null && map.TryGetValue(ins.ValueFunction, out var to))
        {
            ins.ValueFunction = to;
            swapped++;
        }
    }
}
ScriptMessage($"Sonic Tower patched: {swapped} calls redirected.");
if (swapped < 500) throw new ScriptException("Too few calls redirected: " + swapped);
