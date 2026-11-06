// Sonic Tower: Sonic Mania's Sonic in Pizza Tower. Assets are read from the player's Sonic Mania at launch into sonic/.

function st_on()
{
    return global.st_ready && object_index == obj_player1;
}

// ---- assets

function st_log(_text)
{
    var _f = file_text_open_append("st_log.txt");
    if (_f != -1)
    {
        file_text_write_string(_f, _text);
        file_text_writeln(_f);
        file_text_close(_f);
    }
}

function st_read_text(_path)
{
    var _b = buffer_load(_path);
    if (_b == -1)
    {
        return "";
    }
    var _s = buffer_read(_b, buffer_string);
    buffer_delete(_b);
    return _s;
}

function st_load_sound(_name)
{
    var _file = "sonic/sfx/" + string_replace_all(_name, "/", "_") + ".pcm";
    var _b = buffer_load(_file);
    if (_b == -1)
    {
        st_log("sound file not readable: " + _file);
        return -1;
    }
    buffer_seek(_b, buffer_seek_start, 0);
    var _rate = buffer_read(_b, buffer_u32);
    var _ch = buffer_read(_b, buffer_u32);
    var _len = buffer_get_size(_b) - 8;
    // the audio engine plays straight from this buffer: fixed, aligned to the samples, and kept for the whole run
    var _pcm = buffer_create(_len, buffer_fixed, 2);
    buffer_copy(_b, 8, _len, _pcm, 0);
    buffer_delete(_b);
    var _snd = audio_create_buffer_sound(_pcm, buffer_s16, _rate, 0, _len, (_ch == 2) ? audio_stereo : audio_mono);
    if (_snd == -1 || _snd == undefined)
    {
        st_log("audio_create_buffer_sound failed for " + _name + " rate " + string(_rate) + " channels " + string(_ch) + " bytes " + string(_len) + " audio available " + string(audio_system_is_available()));
        buffer_delete(_pcm);
        return -1;
    }
    array_push(global.st_sound_buffers, _pcm);
    return _snd;
}

function st_load()
{
    global.st_ready = false;
    global.st_sound_buffers = [];
    global.st_maps = { Sonic: ds_map_create(), Tails: ds_map_create(), Knux: ds_map_create() };
    global.st_a = global.st_maps.Sonic;
    global.st_snd = ds_map_create();
    global.st_inst = ds_map_create();
    global.st_inst_last = ds_map_create();
    global.st_rings = 0;
    global.st_ring_shown = 0;
    global.st_ring_list = [];
    global.st_ring_room = -1;
    global.st_sprites_loaded = 0;
    global.st_sounds_loaded = 0;
    global.st_tick = 0;
    global.st_fx = [];
    global.st_fx_made = 0;
    global.st_spindust_shown = false;
    st_tables_init();

    var _meta = st_read_text("sonic/anims.json");
    if (_meta != "")
    {
        var _anims = json_parse(_meta);
        var _names = variable_struct_get_names(_anims);
        for (var i = 0; i < array_length(_names); i++)
        {
            var _a = variable_struct_get(_anims, _names[i]);
            if (_a.frames > 0)
            {
                _a.spr = sprite_add("sonic/spr/" + _a.file, _a.frames, false, false, _a.cx, _a.cy);
                if (_a.spr != -1)
                {
                    var _bar = string_pos("|", _names[i]);
                    if (_bar > 0)
                    {
                        var _who = string_copy(_names[i], 1, _bar - 1);
                        ds_map_set(variable_struct_get(global.st_maps, _who), string_delete(_names[i], 1, _bar), _a);
                    }
                    else
                    {
                        ds_map_set(global.st_maps.Sonic, _names[i], _a);
                        // Mania's effects are everybody's
                        if (string_char_at(_names[i], 1) == "@")
                        {
                            ds_map_set(global.st_maps.Tails, _names[i], _a);
                            ds_map_set(global.st_maps.Knux, _names[i], _a);
                        }
                    }
                    global.st_sprites_loaded++;
                }
            }
        }
    }
    var _list = global.st_sound_files;
    for (var i = 0; i < array_length(_list); i++)
    {
        var _s = st_load_sound(_list[i]);
        if (_s != -1)
        {
            ds_map_set(global.st_snd, _list[i], _s);
            global.st_sounds_loaded++;
        }
    }
    global.st_ready = ds_map_exists(global.st_a, "Idle");
    // what only Sonic has reads as the ball on the others
    ds_map_set(global.st_maps.Knux, "Dropdash", ds_map_find_value(global.st_maps.Knux, "Jump"));
    global.st_jump_mult = 1;
    global.st_lift = 0;
    global.st_ball_lift = 0;
    st_mode_load();
    st_log("loaded " + string(global.st_sprites_loaded) + " sprites, " + string(global.st_sounds_loaded) + " sounds");
    st_test_load();
}

// the same volume Pizza Tower's own sounds get: its sliders are steep curves, read from the mixer meter (physics sheet)
function st_slider_gain(_v)
{
    var _a = global.st_k_sfx_gain_at_17;
    var _b = global.st_k_sfx_gain_at_50;
    if (_v <= 0.17)
    {
        return (_v / 0.17) * _a;
    }
    if (_v <= 0.5)
    {
        return _a + ((_v - 0.17) / 0.33) * (_b - _a);
    }
    return _b + ((_v - 0.5) / 0.5) * (1 - _b);
}

function st_sfx_gain()
{
    return global.st_k_sfx_mix * st_slider_gain(global.option_master_volume) * st_slider_gain(global.option_sfx_volume);
}

function st_sound(_name, _pitch = 1)
{
    var _s = ds_map_find_value(global.st_snd, _name);
    if (_s == undefined)
    {
        return;
    }
    var _i = audio_play_sound(_s, 5, false);
    audio_sound_gain(_i, st_sfx_gain(), 0);
    audio_sound_pitch(_i, _pitch);
    if (variable_global_exists("st_test_on"))
    {
        var _n = ds_map_find_value(global.st_test_played, _name);
        ds_map_set(global.st_test_played, _name, (_n == undefined) ? 1 : (_n + 1));
        global.st_test_last_voice = _i;
    }
}

// plays what the sounds sheet says for this event: true when it replaced the game's sound
function st_event(_path)
{
    if (!variable_global_exists("st_ready") || !global.st_ready)
    {
        return false;
    }
    var _key = string_lower(_path);
    var _play = ds_map_find_value(global.st_sfx, _key);
    if (_play == undefined || _play == "keep")
    {
        return false;
    }
    var _r = ds_map_find_value(global.st_ring_events, _key);
    if (_r != undefined)
    {
        global.st_rings += _r;
    }
    if (_key == "event:/sfx/pep/hurt" && global.st_rings > 0)
    {
        // Mania: a hit with rings is the ring-loss sound; Global/Hurt is for a hit with none
        _play = "Global/LoseRings";
        global.st_ringloss_time = current_time;
    }
    if (_key == "event:/sfx/pep/groundpound" && instance_exists(obj_player1) && obj_player1.state == 108)
    {
        _play = global.st_pound_land;
    }
    if (_play != "mute")
    {
        st_sound(_play);
    }
    if (_key == "event:/sfx/pep/parry" && instance_exists(obj_player1))
    {
        st_fx_add("@InstaShield", obj_player1.x, obj_player1.y + 6, obj_player1.xscale, 0, 0);
    }
    if (_r != undefined && instance_exists(obj_player1))
    {
        st_fx_add("@Sparkle", obj_player1.x + irandom_range(-24, 24), obj_player1.y + irandom_range(-24, 24), 1, 0, 0);
    }
    return true;
}

// ---- animation

function st_anim(_name, _speed = -1)
{
    if (st_anim_name != _name)
    {
        var _next = 0;
        var _old = ds_map_find_value(global.st_a, st_anim_name);
        var _new = ds_map_find_value(global.st_a, _name);
        if (_old != undefined && _new != undefined && st_is_run_anim(st_anim_name) && st_is_run_anim(_name))
        {
            _next = floor((st_anim_frame / _old.frames) * _new.frames);
        }
        st_anim_name = _name;
        st_anim_frame = _next;
        if (_next == 0)
        {
            st_anim_timer = 0;
        }
    }
    st_anim_speed = _speed;
}

function st_is_run_anim(_n)
{
    return _n == "Walk" || _n == "Jog" || _n == "Run" || _n == "Dash";
}

// which running animation, with a margin so a speed near a boundary doesn't flip between two
function st_run_anim(_abs)
{
    var _c = st_anim_name;
    var _dash = (_c == "Dash") ? 18 : 20;
    var _run = (_c == "Run" || _c == "Dash") ? 11 : 12;
    var _jog = (_c == "Jog" || _c == "Run" || _c == "Dash") ? 7 : 8;
    if (_abs >= _dash)
    {
        st_anim("Dash", 256);
    }
    else if (_abs >= _run)
    {
        st_anim("Run", min(256, 64 + (_abs * 8)));
    }
    else if (_abs >= _jog)
    {
        st_anim("Jog", min(256, 48 + (_abs * 8)));
    }
    else
    {
        st_anim("Walk", min(256, 40 + (_abs * 8)));
    }
}

function st_anim_tick()
{
    var _a = ds_map_find_value(global.st_a, st_anim_name);
    if (_a == undefined)
    {
        return;
    }
    var _sp = (st_anim_speed >= 0) ? st_anim_speed : _a.speed;
    st_anim_timer += _sp;
    var _guard = 0;
    if (st_anim_frame >= _a.frames)
    {
        st_anim_frame = 0;
    }
    while (_guard < 4)
    {
        var _d = _a.dur[st_anim_frame];
        if (_d <= 0 || st_anim_timer < _d)
        {
            break;
        }
        st_anim_timer -= _d;
        st_anim_frame++;
        if (st_anim_frame >= _a.frames)
        {
            st_anim_frame = clamp(_a.loop, 0, _a.frames - 1);
        }
        _guard++;
    }
    st_spr = _a.spr;
    st_frame = st_anim_frame;
}

// ---- Mania's effects, played with their own frame timings

function st_fx_add(_name, _x, _y, _xs, _h, _v)
{
    var _a = ds_map_find_value(global.st_a, _name);
    if (_a == undefined || array_length(global.st_fx) >= 40)
    {
        return;
    }
    global.st_fx_made++;
    array_push(global.st_fx, { a: _a, x: _x, y: _y, xs: _xs, h: _h, v: _v, f: 0, t: 0, life: (_name == "@Flicky") ? 90 : -1 });
}

function st_fx_tick()
{
    var _list = global.st_fx;
    var _n = array_length(_list);
    if (_n == 0)
    {
        return;
    }
    var _keep = [];
    for (var i = 0; i < _n; i++)
    {
        var _e = _list[i];
        _e.x += _e.h;
        _e.y += _e.v;
        var _a = _e.a;
        var _sp = (_a.speed > 0) ? _a.speed : 1;
        _e.t += _sp;
        var _done = false;
        var _guard = 0;
        while (_guard < 4 && _a.dur[_e.f] > 0 && _e.t >= _a.dur[_e.f])
        {
            _e.t -= _a.dur[_e.f];
            _e.f++;
            if (_e.f >= _a.frames)
            {
                if (_e.life > 0)
                {
                    _e.f = 0;
                }
                else
                {
                    _e.f = _a.frames - 1;
                    _done = true;
                }
                break;
            }
            _guard++;
        }
        if (_e.life > 0)
        {
            _e.life--;
            if (_e.life == 0)
            {
                _done = true;
            }
        }
        if (_a.dur[_e.f] >= 256 && _sp < 16)
        {
            _done = true;
        }
        if (!_done)
        {
            array_push(_keep, _e);
        }
    }
    global.st_fx = _keep;
}

function st_fx_draw()
{
    var _list = global.st_fx;
    for (var i = 0; i < array_length(_list); i++)
    {
        var _e = _list[i];
        draw_sprite_ext(_e.a.spr, _e.f, round(_e.x), round(_e.y), _e.xs, 1, 0, c_white, 1);
    }
}

// ---- the player

function st_player_init()
{
    if (variable_instance_exists(id, "st_gsp"))
    {
        return;
    }
    st_gsp = 0;
    st_ball = false;
    st_jumped = false;
    st_air = false;
    st_spin = false;
    st_rev = 0;
    st_drop = 0;
    st_fly = false;
    st_fly_t = 0;
    st_fly_up = 0;
    st_glide = 0;
    st_climb = false;
    st_climb_dir = 1;
    st_was_own = false;
    st_door_t = 0;
    st_door_cx = x;
    st_prev_state = state;
    st_slope_angle = 0;
    st_slope_dir = 0;
    st_anim_name = "";
    st_anim_frame = 0;
    st_anim_timer = 0;
    st_anim_speed = -1;
    st_spr = -1;
    st_frame = 0;
    st_pose = -1;
    st_pose_seen = false;
    st_last_taunt_timer = 0;
    st_kills_seen = global.hit;
    st_skid = false;
    st_draw_angle = 0;
}

function st_low_ceiling()
{
    var _m = mask_index;
    mask_index = spr_player_mask;
    var _low = scr_solid(x, y);
    mask_index = _m;
    return _low;
}

function st_read_slope()
{
    st_slope_angle = 0;
    st_slope_dir = 0;
    var _s = instance_place(x, y + 3, obj_slope);
    if (_s != -4)
    {
        st_slope_dir = sign(_s.image_xscale);
        st_slope_angle = darctan2(abs(_s.bbox_bottom - _s.bbox_top), abs(_s.bbox_right - _s.bbox_left));
    }
}

function st_start_jump()
{
    vsp = -global.st_k_jump * global.st_jump_mult;
    jumpstop = false;
    st_jumped = true;
    st_ball = true;
    st_air = true;
    st_drop = 0;
    grounded = false;
    st_sound("Global/Jump");
}

function st_sonic()
{
    st_player_init();
    if (global.st_test_on)
    {
        st_test_input();
    }
    // the game handed Sonic over from one of its own states: keep the speed it gave him
    if (!st_was_own && st_prev_state != 61 && st_prev_state != 84)
    {
        if (state == 104 || state == 121 || state == 65 || state == 105 || state == 103)
        {
            st_gsp = xscale * movespeed;
        }
        else if (abs(hsp) > abs(st_gsp))
        {
            st_gsp = hsp;
        }
        st_ball = false;
        st_spin = false;
        st_drop = 0;
        st_jumped = false;
    }
    var _mv = key_left + key_right;
    if (key_jump)
    {
        input_buffer_jump = 15;
    }
    var _jump = key_jump || (grounded && input_buffer_jump > 0 && !st_was_own);
    st_read_slope();
    var _on_ground = grounded && vsp >= 0;
    var _sin = dsin(st_slope_angle) * st_slope_dir;

    if (_on_ground)
    {
        if (st_air)
        {
            // landing: the drop dash fires, otherwise the ball opens up
            st_air = false;
            st_jumped = false;
            if (st_drop >= global.st_k_drop_charge)
            {
                var _dir = (_mv != 0) ? _mv : xscale;
                var _sp = global.st_k_drop_base + (abs(st_gsp) / 4);
                if (sign(st_gsp) == _dir)
                {
                    _sp = global.st_k_drop_base + (abs(st_gsp) / 2);
                }
                st_gsp = _dir * min(_sp, global.st_k_drop_max);
                xscale = _dir;
                st_ball = true;
                st_sound("Global/Release");
                st_fx_add("@DropDust", x, y + 46, _dir, 0, 0);
            }
            else if (!key_down)
            {
                st_ball = false;
            }
            st_drop = 0;
        }
        if (st_spin)
        {
            st_gsp = 0;
            st_rev -= st_rev / 32;
            if (key_jump)
            {
                st_rev = min(st_rev + 2, 8);
                st_sound("Global/Charge", 1 + (st_rev / 16));
            }
            if (!key_down)
            {
                st_gsp = xscale * (global.st_k_spin_base + (floor(st_rev) * global.st_k_spin_per_rev));
                st_ball = true;
                st_spin = false;
                st_sound("Global/Release");
                st_fx_add("@Dust", x - (xscale * 16), y + 40, xscale, -xscale * 2, -1);
                st_fx_add("@Dust", x - (xscale * 32), y + 40, xscale, -xscale * 3, -1);
            }
        }
        else if (st_ball)
        {
            // Mania's roll: no steering, only braking
            if (st_gsp != 0)
            {
                var _s = sign(st_gsp);
                st_gsp -= _s * global.st_k_roll_frc;
                if (_mv == -_s)
                {
                    st_gsp -= _s * global.st_k_roll_dec;
                }
                if (sign(st_gsp) != _s)
                {
                    st_gsp = 0;
                }
                var _up = (sign(st_gsp) == st_slope_dir);
                st_gsp -= (_up ? global.st_k_slope_roll_up : global.st_k_slope_roll_down) * _sin;
            }
            else
            {
                st_gsp -= global.st_k_slope_roll_down * _sin;
            }
            if (abs(st_gsp) < global.st_k_roll_min)
            {
                if (st_low_ceiling())
                {
                    // under a low ceiling the ball keeps moving: where the player holds, turning at walls
                    var _crawl = (_mv != 0) ? _mv : xscale;
                    if (scr_solid(x + _crawl, y))
                    {
                        _crawl = -_crawl;
                    }
                    xscale = _crawl;
                    st_gsp = _crawl * 4;
                }
                else
                {
                    st_ball = false;
                }
            }
            if (_jump)
            {
                input_buffer_jump = 0;
                st_start_jump();
            }
        }
        else
        {
            st_skid = false;
            if (_jump && key_up && abs(st_gsp) < 2)
            {
                // Pizza Tower's super jump, reaching the same places
                input_buffer_jump = 0;
                st_gsp = 0;
                sprite_index = spr_superjumpprep;
                image_index = 0;
                hsp = 0;
                state = 99;
                st_sound("Global/Flying");
                st_was_own = true;
                st_prev_state = 0;
                exit;
            }
            else if (_jump && key_down && abs(st_gsp) < global.st_k_roll_start)
            {
                input_buffer_jump = 0;
                st_spin = true;
                st_rev = 0;
                st_gsp = 0;
                st_sound("Global/Charge");
            }
            else if (_jump)
            {
                input_buffer_jump = 0;
                st_start_jump();
            }
            else if ((key_down || key_attack2) && abs(st_gsp) >= global.st_k_roll_start)
            {
                st_ball = true;
                st_sound("Global/Roll");
            }
            else
            {
                if (_mv != 0)
                {
                    if (st_gsp != 0 && sign(st_gsp) != _mv)
                    {
                        if (abs(st_gsp) >= 8 && !st_skid)
                        {
                            st_skid = true;
                            if (st_anim_name != "Skid")
                            {
                                st_sound("Global/Skidding");
                            }
                        }
                        st_gsp += _mv * global.st_k_dec;
                        if (sign(st_gsp) == _mv)
                        {
                            st_gsp = _mv * global.st_k_dec;
                        }
                    }
                    else if (abs(st_gsp) < global.st_k_top)
                    {
                        st_gsp += _mv * global.st_k_acc;
                        if (abs(st_gsp) > global.st_k_top)
                        {
                            st_gsp = _mv * global.st_k_top;
                        }
                    }
                    xscale = _mv;
                }
                else
                {
                    var _s = sign(st_gsp);
                    st_gsp -= _s * min(global.st_k_frc, abs(st_gsp));
                }
                st_gsp -= global.st_k_slope * _sin;
                // running up a wall: Pizza Tower's climb, at Sonic's speed
                var _dirw = sign(st_gsp);
                if (abs(st_gsp) >= global.st_k_wall_run_speed && _mv == _dirw && scr_solid(x + _dirw, y) && !place_meeting(x + _dirw, y, obj_slope) && !place_meeting(x + _dirw, y, obj_destructibles))
                {
                    wallspeed = abs(st_gsp);
                    grabclimbbuffer = 9999;
                    xscale = _dirw;
                    vsp = -wallspeed;
                    state = 37;
                    sprite_index = spr_machclimbwall;
                    st_sound("Global/Roll");
                    st_was_own = true;
                    st_prev_state = 0;
                    exit;
                }
            }
        }
        if (st_low_ceiling() && !st_spin && !st_ball)
        {
            st_ball = true;
            if (abs(st_gsp) < 4)
            {
                st_gsp = xscale * 4;
            }
        }
    }
    else
    {
        st_air = true;
        st_spin = false;
        if (st_jumped && !key_jump2 && vsp < -global.st_k_jump_cut)
        {
            vsp = -global.st_k_jump_cut;
        }
        if (_mv != 0)
        {
            if (sign(st_gsp) != _mv || abs(st_gsp) < global.st_k_top)
            {
                st_gsp += _mv * global.st_k_air_acc;
            }
            xscale = _mv;
        }
        if (vsp < 0 && vsp > -8)
        {
            st_gsp -= st_gsp / 32;
        }
        if (key_jump && key_down && !st_climb)
        {
            // Pizza Tower's body slam, for floors that need it
            image_index = 0;
            sprite_index = spr_bodyslamstart;
            state = 108;
            vsp = -5;
            st_ball = true;
            st_sound(global.st_pound_start);
            st_was_own = true;
            st_prev_state = 0;
            exit;
        }
        // jump again in the air
        st_air_ability(_mv);
        // a wall reached in the air at speed
        var _dira = sign(st_gsp);
        if (!st_ball && !st_fly && st_glide == 0 && !st_climb && abs(st_gsp) >= global.st_k_wall_run_speed && _mv == _dira && scr_solid(x + _dira, y) && !place_meeting(x + _dira, y, obj_slope) && !place_meeting(x + _dira, y, obj_destructibles))
        {
            wallspeed = abs(st_gsp);
            grabclimbbuffer = 9999;
            xscale = _dira;
            vsp = -wallspeed;
            state = 37;
            sprite_index = spr_machclimbwall;
            st_was_own = true;
            st_prev_state = 0;
            exit;
        }
    }

    if (_on_ground)
    {
        st_fly = false;
        st_glide = 0;
        st_climb = false;
    }
    // into the world
    hsp = st_gsp;
    if (_on_ground && st_slope_dir != 0)
    {
        hsp = st_gsp * dcos(st_slope_angle);
    }
    movespeed = abs(st_gsp);
    mask_index = (st_ball || st_spin) ? spr_crouchmask : spr_player_mask;
    var _now_ground = _on_ground && vsp >= 0;
    state = _now_ground ? ((st_ball || st_spin) ? 65 : 0) : 92;
    if (state == 92)
    {
        jumpstop = true;
    }

    // animation
    var _abs = abs(st_gsp);
    if (st_climb)
    {
        var _cv = (key_down ? 1 : 0) - (key_up ? 1 : 0);
        st_anim((_cv < 0) ? "Climb Up" : ((_cv > 0) ? "Climb Down" : "Climb Idle"), -1);
    }
    else if (st_glide == 1)
    {
        st_anim("Glide", 0);
    }
    else if (st_glide == 2)
    {
        st_anim("Glide Drop", -1);
    }
    else if (st_fly)
    {
        st_anim((st_fly_t >= global.st_k_fly_ticks) ? "Fly Tired" : "Fly", -1);
    }
    else if (st_spin)
    {
        st_anim("Spindash", -1);
    }
    else if (st_ball)
    {
        if (st_drop >= global.st_k_drop_charge)
        {
            st_anim("Dropdash", 256);
        }
        else
        {
            st_anim("Jump", min(240, 60 + (_abs * 12)));
        }
    }
    else if (!_now_ground)
    {
        st_run_anim(_abs);
    }
    else if (st_skid || (_mv != 0 && st_gsp != 0 && sign(st_gsp) != _mv && _abs >= 2))
    {
        st_anim("Skid", -1);
        if ((global.st_tick mod 4) == 0)
        {
            st_fx_add("@Dust", x - (sign(st_gsp) * 10), y + 40, xscale, 0, -1);
        }
    }
    else if (_abs < 0.1 && _mv != 0 && scr_solid(x + _mv, y))
    {
        st_anim("Push", -1);
    }
    else if (_abs < 0.1)
    {
        if (key_up)
        {
            st_anim("Look Up", -1);
        }
        else if (key_down)
        {
            st_anim("Crouch", -1);
        }
        else if (!scr_solid(x + (xscale * 20), y + 50) && !place_meeting(x + (xscale * 20), y + 50, obj_platform))
        {
            st_anim("Balance 1", -1);
        }
        else
        {
            st_anim("Idle", 0);
        }
    }
    else
    {
        st_run_anim(_abs);
    }

    // taunting: the game's own, with its timing and parry
    st_was_own = true;
    scr_dotaunt();
}

// breaks and kills on contact while Sonic is a ball: every breakable the game has
function st_ball_hits()
{
    if (hsp != 0)
    {
        var _dx = hsp + sign(hsp);
        scr_destroy_destructibles(_dx, 0);
        with (instance_place(x + _dx, y, obj_metalblock))
        {
            instance_destroy();
        }
        with (instance_place(x + _dx, y, obj_tntblock))
        {
            instance_destroy();
        }
    }
    if (vsp != 0)
    {
        var _dy = vsp + sign(vsp);
        scr_destroy_destructibles(0, _dy);
        with (instance_place(x, y + _dy, obj_metalblock))
        {
            instance_destroy();
        }
        with (instance_place(x, y + _dy, obj_tntblock))
        {
            instance_destroy();
        }
    }
}

function st_scatter_rings()
{
    if (global.st_rings <= 0)
    {
        return;
    }
    var _count = min(global.st_rings, 32);
    global.st_rings = 0;
    if (!variable_global_exists("st_ringloss_time") || (current_time - global.st_ringloss_time) > 400)
    {
        st_sound("Global/LoseRings");
    }
    for (var i = 0; i < _count; i++)
    {
        var _ang = (360 / 16) * (i mod 16) + 11;
        var _sp = (i < 16) ? 8 : 4;
        array_push(global.st_ring_list, { x: x, y: y, h: lengthdir_x(_sp, _ang), v: lengthdir_y(_sp, _ang), t: 0 });
    }
}

function st_update_rings()
{
    if (global.st_ring_room != room)
    {
        global.st_ring_room = room;
        global.st_ring_list = [];
    }
    var _keep = [];
    var _list = global.st_ring_list;
    for (var i = 0; i < array_length(_list); i++)
    {
        var _r = _list[i];
        _r.t++;
        _r.v += 0.36;
        _r.x += _r.h;
        _r.y += _r.v;
        if (_r.v > 0 && position_meeting(_r.x, _r.y + 16, obj_solid))
        {
            _r.v = -_r.v * 0.75;
        }
        if (_r.t > 30 && point_distance(_r.x, _r.y, x, y) < 48)
        {
            global.st_rings++;
            st_sound("Global/Ring");
            st_fx_add("@Sparkle", _r.x, _r.y, 1, 0, 0);
        }
        else if (_r.t < 256)
        {
            array_push(_keep, _r);
        }
    }
    global.st_ring_list = _keep;
    if (global.st_ring_shown != global.st_rings)
    {
        global.st_ring_shown = global.st_rings;
    }
}

function st_pick_taunt_pose()
{
    var _n = array_length(global.st_taunt_pose_anim);
    var _p = irandom(_n - 1);
    if (_p == st_pose)
    {
        _p = (_p + 1) mod _n;
    }
    st_pose = _p;
    if (global.st_test_on)
    {
        global.st_test_poses[_p] = true;
    }
}

// what Sonic looks like in the game's own states
function st_entering_door()
{
    return (state == 112 && sprite_index == spr_lookdoor) || (state == 98 && sprite_index == spr_entergate);
}

function st_game_state_anim()
{
    if (state == 84)
    {
        var _super = (sprite_index == spr_supertaunt1 || sprite_index == spr_supertaunt2 || sprite_index == spr_supertaunt3 || sprite_index == spr_supertaunt4);
        if (_super)
        {
            if (!st_pose_seen)
            {
                st_pose_seen = true;
                var _n = array_length(global.st_super_pose_anim);
                st_anim(global.st_super_pose_anim[irandom(_n - 1)], -1);
                st_anim_frame = 0;
                st_anim_timer = 0;
            }
            st_anim_speed = 128;
            return;
        }
        if (!st_pose_seen || taunttimer > st_last_taunt_timer)
        {
            st_pose_seen = true;
            st_pick_taunt_pose();
        }
        st_last_taunt_timer = taunttimer;
        st_anim_name = "@pose";
        st_spr = -1;
        var _a = ds_map_find_value(global.st_a, global.st_taunt_pose_anim[st_pose]);
        if (_a != undefined)
        {
            st_spr = _a.spr;
            st_frame = clamp(global.st_taunt_pose_frame[st_pose], 0, _a.frames - 1);
        }
        return;
    }
    st_pose_seen = false;
    st_last_taunt_timer = 0;
    // going through a door or a level gate: to its middle, looks up at it, then in
    if (st_entering_door())
    {
        if (st_door_t == 0)
        {
            st_door_cx = x;
            var _dr = instance_place(x, y, obj_door);
            if (_dr == -4)
            {
                _dr = instance_place(x, y, obj_keydoor);
            }
            if (_dr == -4)
            {
                _dr = instance_place(x, y, obj_startgate);
            }
            if (_dr != -4)
            {
                st_door_cx = (_dr.bbox_left + _dr.bbox_right) / 2;
            }
        }
        st_door_t += (state == 98) ? global.st_k_gate_anim_rate : 1;
        if (st_door_t <= global.st_k_door_walk_ticks && abs(st_door_cx - x) > 2)
        {
            xscale = sign(st_door_cx - x);
            st_anim("Walk", -1);
            st_anim_speed = 96;
        }
        else
        {
            st_anim("Look Up", -1);
            if (st_door_t > global.st_k_door_fade_start && state == 112)
            {
                global.st_tour_door_in = true;
            }
        }
        return;
    }
    st_door_t = 0;
    // a pizza box: in and out as a ball
    if (state == 112 && (sprite_index == spr_downpizzabox || sprite_index == spr_uppizzabox))
    {
        st_anim("Jump", 180);
        return;
    }
    var _name = ds_map_find_value(global.st_state_anim, state);
    if (_name == undefined || _name == "by-move" || _name == "taunt-pose")
    {
        return;
    }
    if (_name == "Idle" && abs(hsp) > 0.5)
    {
        _name = "Walk";
    }
    st_anim(_name, (_name == "Jump") ? 180 : -1);
    if (_name == "Walk")
    {
        st_anim_speed = 96;
    }
    if (state == 37)
    {
        st_anim_speed = min(256, 96 + (abs(vsp) * 10));
    }
    if (_name == "Hang Move" && abs(vsp) < 0.5 && abs(hsp) < 0.5)
    {
        st_anim_speed = 0;
    }
}

function st_contact_hurt()
{
    if (st_ball || st_spin || (state != 0 && state != 92) || hurted || invhurt_buffer > 0)
    {
        return;
    }
    var _box = instance_place(x, y, obj_baddiecollisionbox);
    if (_box == -4 || !instance_exists(_box.baddieID))
    {
        return;
    }
    var _bad = _box.baddieID;
    if (_bad.state == 137 || _bad.state == 138 || _bad.state == 4 || _bad.state == 41 || _bad.invincible || _bad.invtime > 0 || _bad.stuntouchbuffer > 0 || _bad.thrown)
    {
        return;
    }
    if (vsp > 0 && y < _bad.y)
    {
        return;
    }
    var _me = id;
    with (_bad)
    {
        scr_hurtplayer(_me);
    }
}

// ---- hooks: the game's calls land here

function st_h_collide()
{
    if (!st_on())
    {
        scr_collide_player();
        exit;
    }
    st_player_init();
    var _own = (state == 0 || state == 92 || state == 65);
    if (_own && st_was_own && (st_ball || st_spin || st_glide == 1))
    {
        instakillmove = true;
        attacking = true;
    }
    if (st_was_own && st_ball && _own)
    {
        st_ball_hits();
    }
    var _was_ground = grounded && vsp >= 0;
    scr_collide_player();
    if (_own && st_was_own)
    {
        if (hsp == 0 && st_gsp != 0 && scr_solid(x + sign(st_gsp), y))
        {
            st_gsp = 0;
        }
        // Mania's ground hold: running down a slope doesn't turn into a fall
        if (_was_ground && !grounded && vsp >= 0 && !st_jumped)
        {
            var _reach = 4 + ceil(abs(hsp) * 0.75);
            for (var i = 1; i <= _reach; i++)
            {
                if (scr_solid_player(x, y + i))
                {
                    y += i - 1;
                    grounded = true;
                    vsp = grav;
                    break;
                }
            }
        }
        st_contact_hurt();
    }
    else
    {
        st_was_own = false;
    }
    if (_own && st_was_own && key_down && grounded && state == 0 && place_meeting(x, y + 1, obj_boxofpizza))
    {
        state = 65;
    }
    // a kill keeps the bounce Mania gives a ball in the air
    if (global.hit != st_kills_seen)
    {
        st_kills_seen = global.hit;
        if (st_ball && st_air && tauntstoredvsp > -14)
        {
            tauntstoredvsp = (tauntstoredvsp > 0) ? -tauntstoredvsp : (tauntstoredvsp - 2);
        }
        var _ex = x + (xscale * 40);
        st_fx_add("@Explosion", _ex, y + 10, 1, 0, 0);
        st_fx_add("@Flicky", _ex, y, (random(1) < 0.5) ? -1 : 1, (random(1) < 0.5) ? -3 : 3, -4);
    }
    if (state == 107 && st_prev_state != 107)
    {
        st_ball = false;
        st_spin = false;
        st_scatter_rings();
    }
    st_update_rings();
    st_fx_tick();
    // the game's hit freeze holds Sonic's current frame, as Mania's does
    if (state != 61)
    {
        if (!_own)
        {
            st_game_state_anim();
        }
        if (st_anim_name != "@pose")
        {
            st_anim_tick();
        }
    }
    if (_own && st_spr != -1)
    {
        sprite_index = st_spr;
        image_index = st_frame;
        image_speed = 0;
    }
    flash = false;
    st_prev_state = state;
}

function st_draw_rings()
{
    var _a = ds_map_find_value(global.st_a, "@Ring");
    if (_a == undefined)
    {
        return;
    }
    var _list = global.st_ring_list;
    for (var i = 0; i < array_length(_list); i++)
    {
        var _r = _list[i];
        if (_r.t > 180 && (_r.t mod 4) < 2)
        {
            continue;
        }
        draw_sprite(_a.spr, (current_time div 50) mod _a.frames, _r.x, _r.y);
    }
}

function st_h_draw_player()
{
    if (!st_on() || !variable_instance_exists(id, "st_spr") || st_spr == -1)
    {
        draw_player();
        exit;
    }
    shader_reset();
    st_draw_rings();
    st_fx_draw();
    // whole pixels, and steady through the game's hit freeze
    var _dx = (state == 61) ? hitX : x;
    var _dy = (state == 61) ? hitY : y;
    _dx = round(_dx);
    _dy = round(_dy);
    if (st_spin)
    {
        var _sd = ds_map_find_value(global.st_a, "@SpinDust");
        if (_sd != undefined)
        {
            global.st_spindust_shown = true;
            draw_sprite_ext(_sd.spr, global.st_tick mod _sd.frames, _dx, _dy + 46, xscale, 1, 0, c_white, 1);
        }
    }
    var _skip = hurted && state != 107 && ((current_time div 66) mod 2 == 0);
    if (!_skip)
    {
        var _ang = 0;
        var _yo = global.st_k_feet_offset + global.st_lift;
        if (st_anim_name == "Jump" || st_anim_name == "Dropdash")
        {
            _yo = global.st_k_feet_offset + global.st_k_ball_offset + global.st_ball_lift;
        }
        if (state == 37)
        {
            _ang = 90 * xscale;
            _dx += xscale * 8;
        }
        else if (state == 0 && !st_ball && st_slope_dir != 0)
        {
            st_draw_angle += angle_difference(st_slope_angle * st_slope_dir, st_draw_angle) * 0.35;
            _ang = st_draw_angle;
        }
        else
        {
            st_draw_angle = 0;
        }
        var _b = get_dark(image_blend, other.use_dark);
        var _sc = 1;
        var _al = image_alpha;
        if (st_entering_door())
        {
            var _in = clamp((st_door_t - global.st_k_door_fade_start) / global.st_k_door_fade_ticks, 0, 1);
            _dx = round(lerp(x, st_door_cx, clamp(st_door_t / global.st_k_door_walk_ticks, 0, 1)));
            _sc = lerp(1, global.st_k_door_scale_min, _in);
            _al *= 1 - _in;
            _b = merge_colour(_b, c_black, _in * 0.6);
        }
        else if (state == 95 && sprite_index != spr_Timesup)
        {
            // out of the door: grows back to full size as the walk plays
            var _out = clamp((image_index / max(1, image_number - 1)) * 1.5, 0, 1);
            _sc = lerp(global.st_k_door_scale_min, 1, _out);
            _al *= _out;
        }
        // shrinks towards the feet, which stay on the floor
        _yo += (1 - _sc) * 40;
        if (_sc == 1)
        {
            st_sidekick(_dx, _dy + _yo, xscale, _b, _al);
        }
        if (global.st_char == "Tails" && _ang == 0)
        {
            st_draw_tail(st_anim_name, _dx, _dy + _yo, xscale * _sc, yscale * _sc, _b, _al);
        }
        draw_sprite_ext(st_spr, st_frame, _dx, _dy + _yo, xscale * _sc, yscale * _sc, _ang, _b, _al);
    }
    shader_set(global.Pal_Shader);
}

function st_trail_sprite(_spr)
{
    if (variable_global_exists("st_ready") && global.st_ready && instance_exists(obj_player1) && variable_instance_exists(obj_player1, "st_spr") && obj_player1.st_spr != -1 && _spr == obj_player1.sprite_index)
    {
        return obj_player1.st_spr;
    }
    return _spr;
}

function st_h_blur(_x, _y, _spr, _i, _xs) { return create_blur_afterimage(_x, _y, st_trail_sprite(_spr), _i, _xs); }
function st_h_mach3effect(_x, _y, _spr, _i, _e = false) { return create_mach3effect(_x, _y, st_trail_sprite(_spr), _i, _e); }
function st_h_afterimage(_x, _y, _spr, _i) { return create_afterimage(_x, _y, st_trail_sprite(_spr), _i); }
function st_h_red(_x, _y, _spr, _i, _xs) { return create_red_afterimage(_x, _y, st_trail_sprite(_spr), _i, _xs); }
function st_h_blue(_x, _y, _spr, _i, _xs) { return create_blue_afterimage(_x, _y, st_trail_sprite(_spr), _i, _xs); }
function st_h_firemouth(_x, _y, _spr, _i, _xs) { return create_firemouth_afterimage(_x, _y, st_trail_sprite(_spr), _i, _xs); }
function st_h_heat(_x, _y, _spr, _i, _xs) { return create_heatattack_afterimage(_x, _y, st_trail_sprite(_spr), _i, _xs); }
function st_h_noiseimg(_x, _y, _spr, _i, _xs) { return create_noise_afterimage(_x, _y, st_trail_sprite(_spr), _i, _xs); }

function st_h_normal() { if (st_on()) { st_sonic(); } else { scr_player_normal(); } }
function st_h_jump() { if (st_on()) { st_sonic(); } else { scr_player_jump(); } }
function st_h_mach1() { if (st_on()) { st_sonic(); } else { scr_player_mach1(); } }
function st_h_mach2() { if (st_on()) { st_sonic(); } else { scr_player_mach2(); } }
function st_h_mach3() { if (st_on()) { st_sonic(); } else { scr_player_mach3(); } }
function st_h_machroll() { if (st_on()) { st_sonic(); } else { scr_player_machroll(); } }
function st_h_crouch() { if (st_on()) { st_sonic(); } else { scr_player_crouch(); } }
function st_h_crouchjump() { if (st_on()) { st_sonic(); } else { scr_player_crouchjump(); } }
function st_h_crouchslide() { if (st_on()) { st_sonic(); } else { scr_player_crouchslide(); } }
function st_h_machslide() { if (st_on()) { st_sonic(); } else { scr_player_machslide(); } }

function st_h_one_shot(_path)
{
    if (st_event(_path))
    {
        return undefined;
    }
    return fmod_event_one_shot(_path);
}

function st_h_one_shot_3d(_path, _x, _y)
{
    if (st_event(_path))
    {
        return undefined;
    }
    return fmod_event_one_shot_3d(_path, _x, _y);
}

function st_h_create_instance(_path)
{
    var _i = fmod_event_create_instance(_path);
    if (variable_global_exists("st_ready") && global.st_ready)
    {
        var _play = ds_map_find_value(global.st_sfx, string_lower(_path));
        if (_play != undefined && _play != "keep")
        {
            ds_map_set(global.st_inst, _i, _path);
        }
    }
    return _i;
}

function st_h_instance_play(_i)
{
    if (variable_global_exists("st_ready") && global.st_ready)
    {
        var _path = ds_map_find_value(global.st_inst, _i);
        if (_path != undefined)
        {
            var _last = ds_map_find_value(global.st_inst_last, _i);
            ds_map_set(global.st_inst_last, _i, current_time);
            if (_last == undefined || (current_time - _last) > 250)
            {
                st_event(_path);
            }
            return undefined;
        }
    }
    return fmod_event_instance_play(_i);
}

function st_h_achievement(_name)
{
    return undefined;
}

// these states never reach the collision hook, so Sonic's animation is driven from here
function st_door_anim()
{
    if (st_on())
    {
        st_player_init();
        st_game_state_anim();
        st_anim_tick();
    }
}

function st_h_door() { scr_player_door(); st_door_anim(); }
function st_h_comingoutdoor() { scr_player_comingoutdoor(); st_door_anim(); }
function st_h_victory() { scr_player_victory(); st_door_anim(); }

function st_h_hurtplayer(_who)
{
    var _attacking = false;
    with (_who)
    {
        _attacking = variable_instance_exists(id, "st_ball") && st_on() && (st_ball || st_spin);
    }
    if (_attacking && (object_is_ancestor(object_index, obj_baddie) || string_pos("hitbox", object_get_name(object_index)) > 0))
    {
        return undefined;
    }
    return scr_hurtplayer(_who);
}

function st_h_sleep(_ms)
{
    if (variable_global_exists("st_test_on") && global.st_test_on)
    {
        global.st_test_sleeps++;
        global.st_test_sleep_ms += _ms;
    }
    return 0;
}

function st_test_top_objects()
{
    var _counts = ds_map_create();
    with (all)
    {
        var _n = object_get_name(object_index);
        var _c = ds_map_find_value(_counts, _n);
        ds_map_set(_counts, _n, (_c == undefined) ? 1 : (_c + 1));
    }
    var _out = "";
    repeat (6)
    {
        var _best = undefined;
        var _bestn = 0;
        var _key = ds_map_find_first(_counts);
        while (_key != undefined)
        {
            if (ds_map_find_value(_counts, _key) > _bestn)
            {
                _bestn = ds_map_find_value(_counts, _key);
                _best = _key;
            }
            _key = ds_map_find_next(_counts, _key);
        }
        if (_best == undefined)
        {
            break;
        }
        _out += _best + " " + string(_bestn) + ", ";
        ds_map_delete(_counts, _best);
    }
    ds_map_destroy(_counts);
    return _out;
}

function st_h_tick()
{
    steam_update();
    if (!variable_global_exists("st_ready"))
    {
        st_load();
    }
    global.st_tick++;
    if (global.st_test_on)
    {
        st_test_tick();
        if ((global.st_tick mod 240) == 0)
        {
            st_log("perf fps " + string(fps) + " real " + string(round(fps_real)) + " room " + room_get_name(room) + " phase " + string(global.st_test_phase) + " sleeps skipped " + string(global.st_test_sleeps) + " (" + string(global.st_test_sleep_ms) + " ms) worst " + string(round(global.st_test_worst / 1000)) + "ms over20 " + string(global.st_test_over20) + " over40 " + string(global.st_test_over40));
            global.st_test_worst = 0;
            global.st_test_over20 = 0;
            global.st_test_over40 = 0;
        }
        global.st_test_worst = max(global.st_test_worst, delta_time);
        global.st_test_over20 += (delta_time > 20000);
        global.st_test_over40 += (delta_time > 40000);
        if (delta_time > 50000 && global.st_tick > global.st_test_slow_next)
        {
            global.st_test_slow_next = global.st_tick + 10;
            var _p = instance_exists(obj_player1) ? (" state " + string(obj_player1.state) + " x " + string(round(obj_player1.x))) : "";
            st_log("slow " + string(round(delta_time / 1000)) + "ms real " + string(round(fps_real)) + " phase " + string(global.st_test_phase) + _p + " instances " + string(instance_count) + " " + st_test_top_objects());
        }
    }
}

// the HUD: the game's stays, Sonic's TV and ring count are drawn on it
function st_draw_hud()
{
    if (!variable_global_exists("st_ready") || !global.st_ready || !instance_exists(obj_player1))
    {
        return;
    }
    shader_reset();
    st_make_art();
    var _tx = tv_x;
    var _ty = tv_y + hud_posY;
    var _p = obj_player1;
    if (room != strongcold_endscreen)
    {
        draw_sprite_ext(spr_tv_bgfinal, tv_bg_index, _tx, _ty, 1, 1, 0, c_white, alpha);
        if (variable_instance_exists(_p, "st_spr") && _p.st_spr != -1)
        {
            draw_sprite_ext(_p.st_spr, _p.st_frame, _tx, _ty + 8, 1.2, 1.2, 0, c_white, alpha);
        }
    }
    var _r = ds_map_find_value(global.st_a, "@Ring");
    if (_r != undefined)
    {
        var _hx = 40;
        var _hy = display_get_gui_height() - 56;
        draw_sprite(_r.spr, (current_time div 50) mod _r.frames, _hx, _hy);
        draw_set_font(lang_get_font("bigfont"));
        draw_set_halign(fa_left);
        draw_set_valign(fa_middle);
        draw_set_color((global.st_rings > 0 || (current_time div 400) mod 2 == 0) ? c_white : c_red);
        draw_text(_hx + 28, _hy, string(global.st_rings));
        draw_set_color(c_white);
        draw_set_valign(fa_top);
    }
    shader_set(global.Pal_Shader);
}

// ---- test mode: only while Melty's test file was handed over by the launcher

function st_test_load()
{
    global.st_test_on = false;
    global.st_test_poses = [];
    global.st_bot = { l: 0, r: 0, d: 0, u: 0, j: 0, jh: 0, t: 0 };
    var _text = st_read_text("sonic/test.json");
    if (_text == "")
    {
        return;
    }
    var _t = json_parse(_text);
    global.st_test_on = true;
    global.st_test_phase = 0;
    if (variable_struct_exists(_t, "run"))
    {
        var _runs = [0, 2, 3];
        st_mode_set(_runs[clamp(_t.run - 1, 0, 2)], false);
        st_log("run " + string(_t.run) + " plays " + global.st_modes[global.st_mode].label);
    }
    global.st_test_wait = 0;
    global.st_test_dir = 1;
    global.st_test_inst = -4;
    global.st_test_tries = 0;
    global.st_test_done = ds_map_create();
    global.st_test_played = ds_map_create();
    global.st_test_sleeps = 0;
    global.st_test_sleep_ms = 0;
    global.st_test_slow_next = 0;
    global.st_perftour = variable_struct_exists(_t, "perftour");
    global.st_perf_rooms = [];
    var _pn = ["entrance_3", "medieval_2", "medieval_6", "ruin_2", "ruin_6", "dungeon_2", "dungeon_6", "badland_2", "graveyard_2", "farm_2", "saloon_2", "plage_2", "forest_2", "space_2", "minigolf_2", "street_2", "sewer_2", "industrial_2", "freezer_2", "chateau_2", "kidsparty_2", "war_2", "tower_1", "tower_3", "tower_5"];
    for (var _pi = 0; _pi < array_length(_pn); _pi++)
    {
        var _pr = asset_get_index(_pn[_pi]);
        if (_pr != -1 && room_exists(_pr))
        {
            array_push(global.st_perf_rooms, _pr);
        }
    }
    global.st_test_worst = 0;
    global.st_test_over20 = 0;
    global.st_test_over40 = 0;
    global.st_test_last_voice = -1;
    global.st_test_poses = array_create(array_length(global.st_taunt_pose_anim), false);
    if (variable_struct_exists(_t, "seed"))
    {
        random_set_seed(_t.seed);
    }
}

function st_test_clear_run(_dir)
{
    // how far Sonic can roll this way on flat floor
    var _d = 0;
    while (_d < 420 && !scr_solid(x + (_dir * (_d + 16)), y) && scr_solid(x + (_dir * (_d + 16)), y + 8))
    {
        _d += 16;
    }
    return _d;
}

function st_test_go_home()
{
    with (obj_player1)
    {
        x = global.st_test_home_x;
        y = global.st_test_home_y;
        st_gsp = 0;
        hsp = 0;
        vsp = 0;
        st_ball = false;
        st_spin = false;
        st_rev = 0;
        state = 0;
        xscale = global.st_test_dir;
    }
}

function st_test_count(_name)
{
    var _n = ds_map_find_value(global.st_test_played, _name);
    return (_n == undefined) ? 0 : _n;
}

function st_test_hit(_rings)
{
    st_test_go_home();
    global.st_rings = _rings;
    with (obj_player1)
    {
        hurted = false;
        invtime = 0;
        invhurt_buffer = 0;
        var _me = id;
        scr_hurtplayer(_me);
    }
}

// ---- the door tour: every way between rooms, used the way a player uses it

// reports "door-goes-through" "door-arrival-control" "hallway-goes-through" "hallway-arrival-control" "box-goes-through" "box-arrival-control"
function st_tour_init()
{
    global.st_tour_rooms = [];
    var _names = ["entrance_1", "tower_1", "entrance_6", "tower_2", "tower_3", "tower_4", "tower_5", "medieval_1", "medieval_2", "medieval_3", "medieval_4", "medieval_5", "ruin_1", "ruin_2", "ruin_3", "ruin_4", "dungeon_1", "dungeon_2", "dungeon_3", "badland_1", "badland_2", "badland_3", "graveyard_1", "graveyard_2", "farm_1", "farm_2", "saloon_1", "saloon_2", "plage_1", "plage_2", "forest_1", "forest_2", "street_1", "street_2", "tower_entrancehall"];
    for (var i = 0; i < array_length(_names); i++)
    {
        var _r = asset_get_index(_names[i]);
        if (_r != -1 && room_exists(_r))
        {
            array_push(global.st_tour_rooms, _r);
        }
    }
    global.st_tour_room_i = -1;
    global.st_tour_step = "go";
    global.st_tour_kind = "";
    global.st_tour_inst = -4;
    global.st_tour_from = room;
    global.st_tour_x = 0;
    global.st_tour_left = ["door", "hallway", "box", "gate", "ladder"];
    global.st_tour_door_in = false;
    global.st_tour_door_out = false;
}

function st_tour_left_has(_kind)
{
    for (var i = 0; i < array_length(global.st_tour_left); i++)
    {
        if (global.st_tour_left[i] == _kind)
        {
            return true;
        }
    }
    return false;
}

function st_tour_mark(_kind)
{
    var _n = [];
    for (var i = 0; i < array_length(global.st_tour_left); i++)
    {
        if (global.st_tour_left[i] != _kind)
        {
            array_push(_n, global.st_tour_left[i]);
        }
    }
    global.st_tour_left = _n;
}

function st_tour_pick()
{
    global.st_tour_inst = -4;
    if (st_tour_left_has("door"))
    {
        with (obj_door)
        {
            if (!locked && !john && !place_meeting(x, y, obj_doorblocked) && object_index == obj_door)
            {
                global.st_tour_inst = id;
                global.st_tour_kind = "door";
            }
        }
    }
    if (global.st_tour_inst == -4 && st_tour_left_has("hallway"))
    {
        with (obj_hallway)
        {
            if (global.st_tour_inst == -4 || (bbox_left >= 0 && bbox_right <= room_width))
            {
                global.st_tour_inst = id;
                global.st_tour_kind = "hallway";
            }
        }
    }
    if (global.st_tour_inst == -4 && st_tour_left_has("box"))
    {
        with (obj_boxofpizza)
        {
            if (image_yscale == 1)
            {
                global.st_tour_inst = id;
                global.st_tour_kind = "box";
            }
        }
    }
    if (global.st_tour_inst == -4 && st_tour_left_has("ladder"))
    {
        with (obj_ladder)
        {
            global.st_tour_inst = id;
            global.st_tour_kind = "ladder";
        }
    }
    if (global.st_tour_inst == -4 && st_tour_left_has("gate"))
    {
        with (obj_startgate)
        {
            global.st_tour_inst = id;
            global.st_tour_kind = "gate";
        }
    }
    return global.st_tour_inst != -4;
}

function st_tour_next(_step)
{
    global.st_tour_step = _step;
    global.st_test_wait = 0;
}

function st_tour_tick()
{
    var _w = global.st_test_wait;
    var _b = global.st_bot;
    var _p = obj_player1;
    var _k = global.st_tour_kind;
    with (obj_player1)
    {
        invtime = 30;
    }
    switch (global.st_tour_step)
    {
        case "go":
            // on to the next room in the list
            st_test_clear_keys();
            if (array_length(global.st_tour_left) == 0)
            {
                st_tour_finish();
                break;
            }
            global.st_tour_room_i++;
            if (global.st_tour_room_i >= array_length(global.st_tour_rooms))
            {
                st_tour_finish();
                break;
            }
            with (obj_player)
            {
                targetRoom = global.st_tour_rooms[global.st_tour_room_i];
                targetDoor = "A";
                hallway = false;
                verticalhallway = false;
                box = false;
            }
            with (obj_player1)
            {
                instance_create(x, y, obj_fadeout);
            }
            st_tour_next("settle");
            break;
        case "settle":
            if (_w > 40 && room == global.st_tour_rooms[global.st_tour_room_i] && !instance_exists(obj_fadeout) && (_p.state == 0 || _p.state == 92))
            {
                st_log("tour room " + room_get_name(room) + " doors " + string(instance_number(obj_door)) + " hallways " + string(instance_number(obj_hallway)) + " vertical " + string(instance_number(obj_verticalhallway)) + " boxes " + string(instance_number(obj_boxofpizza)) + " gates " + string(instance_number(obj_startgate)));
                st_tour_next(st_tour_pick() ? "place" : "go");
            }
            else if (_w > 200)
            {
                st_log("tour: room never settled, in " + room_get_name(room) + " state " + string(_p.state) + " at " + string(_p.x) + "," + string(_p.y) + " gsp " + string(_p.st_gsp) + " ball " + string(_p.st_ball) + " fade " + string(instance_exists(obj_fadeout)));
                st_tour_next("go");
            }
            break;
        case "place":
            global.st_tour_from = room;
            var _i = global.st_tour_inst;
            var _cx = round((_i.bbox_left + _i.bbox_right) / 2);
            with (obj_player1)
            {
                st_gsp = 0;
                hsp = 0;
                vsp = 0;
                st_ball = false;
                st_spin = false;
                st_jumped = false;
                st_rev = 0;
                state = 92;
                x = _cx;
                switch (_k)
                {
                    case "door":
                        y = _i.y + 10;
                        break;
                    case "gate":
                        y = _i.bbox_bottom - 100;
                        break;
                    case "ladder":
                        x = _i.x + 16;
                        y = round((_i.bbox_top + _i.bbox_bottom) / 2);
                        break;
                    case "box":
                        y = _i.bbox_top - 90;
                        break;
                    case "hallway":
                        // arrives in its doorway at running speed, on clear ground
                        var _dir = sign(_i.image_xscale);
                        xscale = _dir;
                        st_gsp = _dir * 12;
                        y = _i.bbox_bottom - 48;
                        while (scr_solid(x, y) && y > _i.bbox_top - 64)
                        {
                            y -= 8;
                        }
                        state = 0;
                        break;
                }
            }
            st_log("tour " + _k + " at " + string(_i.x) + "," + string(_i.y) + " from " + room_get_name(room) + " to " + string(variable_instance_exists(_i, "targetRoom") ? _i.targetRoom : "?"));
            if (_k == "ladder")
            {
                _b.u = 1;
                st_tour_next("ladder");
                break;
            }
            st_tour_next((_k == "hallway") ? "wait_room" : "land");
            break;
        case "ladder":
            if (_p.state == 93 || _w > 60)
            {
                st_test_report("ladder-grabs", _p.state == 93, "state " + string(_p.state));
                st_log("tour ladder state " + string(_p.state) + " anim " + _p.st_anim_name);
                st_test_clear_keys();
                with (obj_player1)
                {
                    ladderbuffer = 30;
                    state = 92;
                }
                st_tour_mark("ladder");
                global.st_tour_room_i--;
                st_tour_next("go");
            }
            break;
        case "land":
            if (_p.grounded && _p.state == 0 && _w > 5)
            {
                st_log("tour landed y " + string(_p.y) + " want " + string(global.st_tour_inst.y + 50) + " x " + string(_p.x));
                if (_k == "box")
                {
                    _b.d = 1;
                }
                else
                {
                    _b.u = 1;
                }
                st_tour_next("wait_room");
            }
            else if (_w > 200)
            {
                st_log("tour never landed: state " + string(_p.state) + " y " + string(_p.y));
                st_tour_fail("never landed");
            }
            break;
        case "wait_room":
            if (room != global.st_tour_from)
            {
                st_test_clear_keys();
                st_log("tour " + _k + " arrived in " + room_get_name(room) + " state " + string(_p.state) + " at " + string(_p.x) + "," + string(_p.y) + " gsp " + string(_p.st_gsp));
                if (_k == "gate")
                {
                    st_test_report("gate-enters-level", true);
                    st_tour_mark("gate");
                    global.st_tour_room_i--;
                    st_tour_next("go");
                    break;
                }
                st_test_report(_k + "-goes-through", true);
                st_tour_next("arrive");
            }
            else if (_w > ((_k == "gate") ? 1200 : 240))
            {
                with (obj_player1)
                {
                    st_log("tour touching " + string(place_meeting(x, y, global.st_tour_inst)) + " up " + string(key_up) + " grounded " + string(grounded) + " spot " + string(spotlight) + " inst box " + string(global.st_tour_inst.bbox_left) + "-" + string(global.st_tour_inst.bbox_right) + " x " + string(global.st_tour_inst.bbox_top) + "-" + string(global.st_tour_inst.bbox_bottom));
                }
                st_tour_fail("still in " + room_get_name(room) + " state " + string(_p.state) + " y " + string(_p.y) + " want " + string(instance_exists(global.st_tour_inst) ? (global.st_tour_inst.y + 50) : -1));
            }
            break;
        case "arrive":
            if (_k == "door" && _p.state == 95 && _p.st_anim_name == "Walk")
            {
                global.st_tour_door_out = true;
            }
            // comes out, then the bot walks: does Sonic move?
            if (!instance_exists(obj_fadeout) && (_p.state == 0 || _p.state == 92))
            {
                global.st_tour_x = _p.x;
                var _dir2 = scr_solid(_p.x + 40, _p.y) ? -1 : 1;
                _b.l = (_dir2 < 0);
                _b.r = (_dir2 > 0);
                st_tour_next("moved");
            }
            else if (_w > 300)
            {
                st_test_report(_k + "-arrival-control", false, "stuck in state " + string(_p.state) + " sprite " + sprite_get_name(_p.sprite_index));
                st_tour_mark(_k);
                st_tour_next("go");
            }
            break;
        case "moved":
            if (_w > 40)
            {
                var _moved = abs(_p.x - global.st_tour_x);
                st_test_report(_k + "-arrival-control", _moved > 4, "moved " + string(_moved) + " state " + string(_p.state));
                st_test_clear_keys();
                st_tour_mark(_k);
                if (_k == "door")
                {
                    st_test_report("door-animation", global.st_tour_door_in && global.st_tour_door_out, "in " + string(global.st_tour_door_in) + " out " + string(global.st_tour_door_out));
                }
                // this room again: it may hold another kind
                global.st_tour_room_i--;
                st_tour_next("go");
            }
            break;
    }
}

function st_tour_fail(_why)
{
    var _k = global.st_tour_kind;
    st_log("tour " + _k + " failed: " + _why);
    if (_k == "ladder")
    {
        st_test_report("ladder-grabs", false, _why);
    }
    if (_k == "gate")
    {
        st_test_report("gate-enters-level", false, _why);
    }
    else
    {
        st_test_report(_k + "-goes-through", false, _why);
        st_test_report(_k + "-arrival-control", false, "never went through");
    }
    st_test_clear_keys();
    st_tour_mark(_k);
    st_tour_next("go");
}

function st_tour_finish()
{
    for (var i = 0; i < array_length(global.st_tour_left); i++)
    {
        var _k = global.st_tour_left[i];
        if (_k == "ladder")
        {
            st_test_report("ladder-grabs", false, "no ladder found on the tour");
        }
        else if (_k == "gate")
        {
            st_test_report("gate-enters-level", false, "no gate found on the tour");
        }
        else
        {
            st_test_report(_k + "-goes-through", false, "none found on the tour");
            st_test_report(_k + "-arrival-control", false, "none found on the tour");
            if (_k == "door")
            {
                st_test_report("door-animation", false, "no door found on the tour");
            }
        }
    }
    st_test_clear_keys();
    global.st_test_phase = 13;
    global.st_test_wait = 0;
    global.st_lv_step = global.st_perftour ? "perf_go" : "sjump_go";
    global.st_lv_i = -1;
}

// ---- a whole level's ending, and (locally) frame times across the game

function st_go_room(_r)
{
    with (obj_player1)
    {
        state = 92;
        vsp = 0;
        hsp = 0;
        st_gsp = 0;
        st_ball = false;
        st_spin = false;
    }
    with (obj_player)
    {
        targetRoom = _r;
        targetDoor = "A";
        hallway = false;
        verticalhallway = false;
        box = false;
    }
    with (obj_player1)
    {
        instance_create(x, y, obj_fadeout);
    }
    global.st_lv_room = _r;
}

function st_settled()
{
    return global.st_test_wait > 40 && room == global.st_lv_room && !instance_exists(obj_fadeout) && (obj_player1.state == 0 || obj_player1.state == 92);
}

function st_lv(_step)
{
    global.st_lv_step = _step;
    global.st_test_wait = 0;
    st_test_clear_keys();
}

function st_lv_place(_x, _y)
{
    with (obj_player1)
    {
        st_gsp = 0;
        hsp = 0;
        vsp = 0;
        st_ball = false;
        st_spin = false;
        st_jumped = false;
        st_rev = 0;
        state = 92;
        x = _x;
        y = _y;
    }
}

function st_level_tick()
{
    var _w = global.st_test_wait;
    var _b = global.st_bot;
    var _p = obj_player1;
    with (obj_player1)
    {
        invtime = 30;
    }
    switch (global.st_lv_step)
    {
        case "perf_go":
            global.st_lv_i++;
            if (global.st_lv_i >= array_length(global.st_perf_rooms))
            {
                st_lv("sjump_go");
                break;
            }
            st_go_room(global.st_perf_rooms[global.st_lv_i]);
            st_lv("perf_settle");
            break;
        case "perf_settle":
            if (st_settled())
            {
                st_lv("perf_run");
            }
            else if (_w > 200)
            {
                st_lv("perf_go");
            }
            break;
        case "perf_run":
            if (_w == 60)
            {
                global.st_test_worst = 0;
                global.st_test_over20 = 0;
                global.st_test_over40 = 0;
                global.st_lv_minfps = 999;
            }
            if (_w > 60)
            {
                global.st_lv_minfps = min(global.st_lv_minfps, fps);
            }
            var _m = _w mod 120;
            if (_m == 1)
            {
                _b.d = 1;
                _b.l = 0;
                _b.r = 0;
            }
            if (_m == 6 || _m == 16)
            {
                _b.j = 1;
            }
            if (_m == 30)
            {
                _b.d = 0;
                global.st_test_dir = ((_w div 240) mod 2 == 0) ? 1 : -1;
                st_test_hold_dir();
            }
            if (_m == 70 || _m == 95)
            {
                _b.j = 1;
            }
            if (_w > 360)
            {
                st_log("perfroom " + room_get_name(room) + " minfps " + string(global.st_lv_minfps) + " worst " + string(round(global.st_test_worst / 1000)) + "ms over20 " + string(global.st_test_over20) + " over40 " + string(global.st_test_over40) + " instances " + string(instance_count));
                st_lv("perf_go");
            }
            break;
        case "sjump_go":
            st_go_room(entrance_1);
            st_lv("sjump_settle");
            break;
        case "sjump_settle":
            if (st_settled() && _p.grounded)
            {
                global.st_lv_y = _p.y;
                global.st_lv_seen = false;
                _b.u = 1;
                _b.j = 1;
                global.st_test_wait = 0;
                global.st_lv_step = "sjump";
            }
            else if (_w > 300)
            {
                st_test_report("super-jump", false, "room never settled");
                st_lv("pillar_go");
            }
            break;
        case "sjump":
            if (_w > 3)
            {
                _b.u = 0;
            }
            global.st_lv_seen = global.st_lv_seen || (_p.state == 97);
            global.st_lv_y = max(global.st_lv_y, _p.y);
            if (_w > 90 || (global.st_lv_seen && (global.st_lv_y - _p.y) > 100))
            {
                st_test_report("super-jump", global.st_lv_seen && (global.st_lv_y - _p.y) > 100, "state " + string(_p.state) + " rose " + string(global.st_lv_y - _p.y));
                st_log("super jump state " + string(_p.state) + " anim " + _p.st_anim_name + " rose " + string(global.st_lv_y - _p.y));
                st_lv("pillar_go");
            }
            break;
        case "pillar_go":
            st_go_room(entrance_10);
            st_lv("pillar_settle");
            break;
        case "pillar_settle":
            if (st_settled())
            {
                var _pil = instance_find(obj_hungrypillar, 0);
                if (_pil == noone)
                {
                    st_test_report("spindash-starts-pizza-time", false, "no pillar in " + room_get_name(room));
                    st_lv("exit_go");
                    break;
                }
                global.st_test_inst = _pil;
                global.st_test_dir = 1;
                var _px = _pil.bbox_left - 180;
                with (obj_player1)
                {
                    if (scr_solid(_px, _pil.bbox_bottom - 60))
                    {
                        _px = _pil.bbox_right + 180;
                        global.st_test_dir = -1;
                    }
                }
                st_log("pillar at " + string(_pil.x) + "," + string(_pil.y) + " box " + string(_pil.bbox_left) + "-" + string(_pil.bbox_right) + " x " + string(_pil.bbox_top) + "-" + string(_pil.bbox_bottom) + " Sonic from " + string(_px));
                st_lv_place(_px, _pil.bbox_bottom - 80);
                st_lv("pillar_land");
            }
            else if (_w > 300)
            {
                st_test_report("spindash-starts-pizza-time", false, "room never settled: in " + room_get_name(room) + " state " + string(_p.state) + " fade " + string(instance_exists(obj_fadeout)));
                st_lv("exit_go");
            }
            break;
        case "pillar_land":
            if (_p.grounded && _p.state == 0 && _w > 5)
            {
                with (obj_player1)
                {
                    xscale = global.st_test_dir;
                }
                st_lv("pillar_dash");
            }
            else if (_w > 200)
            {
                st_test_report("spindash-starts-pizza-time", false, "never landed");
                st_lv("exit_go");
            }
            break;
        case "pillar_dash":
            st_test_spindash(_w);
            if (global.panic || _w > 240)
            {
                st_test_report("spindash-starts-pizza-time", global.panic, "panic false, Sonic at " + string(_p.x) + "," + string(_p.y) + " state " + string(_p.state) + " gsp " + string(_p.st_gsp));
                st_log("pillar: panic " + string(global.panic) + " at " + string(_p.x) + "," + string(_p.y));
                global.st_test_worst = 0;
                global.st_test_over20 = 0;
                global.st_test_over40 = 0;
                global.st_lv_minfps = 999;
                global.st_test_dir = -global.st_test_dir;
                st_lv("panic_run");
            }
            break;
        case "panic_run":
            // Pizza Time at Sonic's speed: the screen at its busiest
            global.st_lv_minfps = min(global.st_lv_minfps, fps);
            var _pm = _w mod 120;
            if (_pm == 1)
            {
                _b.d = 1;
                _b.l = 0;
                _b.r = 0;
            }
            if (_pm == 6 || _pm == 16)
            {
                _b.j = 1;
            }
            if (_pm == 30)
            {
                _b.d = 0;
                st_test_hold_dir();
            }
            if (_pm == 119)
            {
                global.st_test_dir = -global.st_test_dir;
            }
            if (_w > 480)
            {
                st_log("perfroom PizzaTime minfps " + string(global.st_lv_minfps) + " worst " + string(round(global.st_test_worst / 1000)) + "ms over20 " + string(global.st_test_over20) + " over40 " + string(global.st_test_over40) + " instances " + string(instance_count));
                st_lv("exit_go");
            }
            break;
        case "exit_go":
            st_go_room(entrance_1);
            st_lv("exit_settle");
            break;
        case "exit_settle":
            if (st_settled())
            {
                var _g = instance_find(obj_exitgate, 0);
                if (_g == noone)
                {
                    st_test_report("exit-gate-ends-level", false, "no exit gate in " + room_get_name(room));
                    st_lv("end");
                    break;
                }
                st_lv_place(_g.x, _g.bbox_bottom - 80);
                st_log("exit gate at " + string(_g.x) + "," + string(_g.y) + " panic " + string(global.panic));
                st_lv("exit_land");
            }
            else if (_w > 300)
            {
                st_test_report("exit-gate-ends-level", false, "room never settled");
                st_lv("end");
            }
            break;
        case "exit_land":
            if (_p.grounded && _p.state == 0 && _w > 5)
            {
                _b.u = 1;
                global.st_test_wait = 0;
                global.st_lv_step = "exit_wait";
            }
            else if (_w > 200)
            {
                st_test_report("exit-gate-ends-level", false, "never landed: state " + string(_p.state));
                st_lv("end");
            }
            break;
        case "exit_wait":
            if (instance_exists(obj_endlevelfade) || _w > 120)
            {
                st_test_report("exit-gate-ends-level", instance_exists(obj_endlevelfade), "panic " + string(global.panic) + " state " + string(_p.state) + " x " + string(_p.x));
                st_lv("end");
            }
            break;
        case "end":
        case "rank_next":
        case "rank_hold":
        case "rank_leave":
        case "sweep_next":
        case "sweep_hold":
        case "sweep_done":
            st_test_after_level();
            break;
    }
}

// ---- Sonic in Peppino's place: results screen, file select, boss VS art

// plays an animation by the clock, for screens where the draw event can run more than once a frame
function st_time_anim(_name)
{
    var _a = ds_map_find_value(global.st_a, _name);
    if (_a == undefined)
    {
        return undefined;
    }
    if (!variable_instance_exists(id, "st_ta_name") || st_ta_name != _name)
    {
        st_ta_name = _name;
        st_ta_f = 0;
        st_ta_t = 0;
        st_ta_last = current_time;
    }
    var _ticks = min(current_time - st_ta_last, 100) * 0.06;
    st_ta_last = current_time;
    st_ta_t += _ticks * max(_a.speed, 1);
    var _g = 0;
    while (_g < 16)
    {
        var _d = _a.dur[st_ta_f];
        if (_d <= 0 || st_ta_t < _d)
        {
            break;
        }
        st_ta_t -= _d;
        st_ta_f++;
        if (st_ta_f >= _a.frames)
        {
            st_ta_f = clamp(_a.loop, 0, _a.frames - 1);
        }
        _g++;
    }
    return _a;
}

function st_rank_sprite(_s)
{
    return _s == spr_rankD || _s == spr_rankC || _s == spr_rankB || _s == spr_rankA || _s == spr_rankS || _s == spr_rankP
        || _s == spr_rankND || _s == spr_rankNC || _s == spr_rankNB || _s == spr_rankNA || _s == spr_rankNS || _s == spr_rankNP
        || _s == spr_rankNPend || _s == spr_rankNPendstart;
}

// where the game's rank art keeps each letter, clear of Peppino, and its speech bubble
function st_rank_parts(_rank)
{
    switch (_rank)
    {
        case "d":
            return { spr: spr_rankD, text: spr_rankD_text, rects: [[652, 94, 198, 168]], bubble: [263, 86, 334, 204] };
        case "c":
            return { spr: spr_rankC, text: spr_rankC_text, rects: [[611, 68, 198, 161]], bubble: [347, 108, 189, 117] };
        case "b":
            return { spr: spr_rankB, text: spr_rankB_text, rects: [[571, 66, 318, 204]], bubble: [356, 84, 131, 120] };
        case "a":
            return { spr: spr_rankA, text: spr_rankA_text, rects: [[642, 22, 223, 248]], bubble: [414, 67, 144, 111] };
        case "s":
            return { spr: spr_rankS, text: spr_rankS_text, rects: [[706, 94, 202, 112], [697, 206, 211, 84], [660, 290, 248, 91]], bubble: -4 };
    }
    return -4;
}

function st_rank_bubble(_b, _tx, _ty)
{
    var _x1 = _b[0] - 10;
    var _y1 = _b[1] - 10;
    var _x2 = _b[0] + _b[2] + 10;
    var _y2 = _b[1] + _b[3] + 10;
    var _bx = lerp(_x1, _x2, 0.22);
    var _by = lerp(_y1, _y2, 0.8);
    draw_set_color(c_black);
    draw_ellipse(_x1 - 4, _y1 - 4, _x2 + 4, _y2 + 4, false);
    draw_triangle(_bx - 20, _by - 16, _bx + 24, _by + 2, _tx, _ty, false);
    draw_set_color(c_white);
    draw_ellipse(_x1, _y1, _x2, _y2, false);
    draw_triangle(_bx - 13, _by - 18, _bx + 16, _by - 4, _tx + 6, _ty - 8, false);
}

function st_h_draw_rank()
{
    var _a = (variable_global_exists("st_ready") && global.st_ready && st_rank_sprite(sprite_index)) ? st_time_anim("Victory") : undefined;
    if (_a == undefined)
    {
        scr_draw_rank();
        exit;
    }
    global.st_rank_drawn = global.rank;
    if (!variable_instance_exists(id, "st_rank_t0"))
    {
        st_rank_t0 = current_time;
        st_rank_sx = 480;
        st_rank_sy = 270;
        st_rank_xs = 1;
        if (instance_exists(obj_player1))
        {
            st_rank_sx = obj_player1.x - (x - 480);
            st_rank_sy = (obj_player1.y + global.st_k_feet_offset) - (y - 270);
            st_rank_xs = obj_player1.xscale;
        }
    }
    var _left = x - 480;
    var _top = y - 270;
    var _silhouette = shader_current() == shd_rank;
    var _col = _silhouette ? c_black : c_white;
    var _alpha = _silhouette ? draw_get_alpha() : 1;
    shader_reset();
    var _isp = global.rank == "p";
    if (sprite_index == spr_rankP && !_silhouette)
    {
        draw_sprite(spr_rankNPbg, 0, x, y);
    }
    // the camera moves in on him: slow start, slow finish
    var _el = current_time - st_rank_t0;
    var _t = clamp(_el / global.st_k_rank_zoom_ms, 0, 1);
    var _e = _t * _t * _t * ((_t * ((_t * 6) - 15)) + 10);
    var _ex = _isp ? 480 : global.st_k_rank_x;
    var _ey = _isp ? global.st_k_rank_p_y : global.st_k_rank_y;
    var _dx = _left + lerp(st_rank_sx, _ex, _e);
    var _dy = _top + lerp(st_rank_sy, _ey, _e);
    var _s = lerp(1, global.st_k_rank_scale, _e);
    var _xs = lerp(st_rank_xs, global.st_k_rank_scale, _e);
    var _filter = gpu_get_tex_filter();
    gpu_set_tex_filter(false);
    if (global.st_side)
    {
        var _ta = ds_map_find_value(global.st_maps.Tails, "Victory");
        if (_ta != undefined)
        {
            draw_sprite_ext(_ta.spr, min(st_ta_f, _ta.frames - 1), round(_dx) - (_s * 24), round(_dy) + (_s * global.st_tails_lift), _xs, _s, 0, _col, _alpha);
        }
    }
    if (global.st_char == "Tails")
    {
        st_draw_tail("Victory", round(_dx), round(_dy) + (_s * global.st_lift), _xs, _s, _col, _alpha);
    }
    draw_sprite_ext(_a.spr, st_ta_f, round(_dx), round(_dy) + (_s * global.st_lift), _xs, _s, 0, _col, _alpha);
    // the verdict lands once he has arrived
    var _parts = st_rank_parts(global.rank);
    if (_t >= 1 && _parts != -4)
    {
        if (!_silhouette && _parts.bubble != -4)
        {
            st_rank_bubble(_parts.bubble, _left + global.st_k_rank_x + 60, _top + global.st_k_rank_y - 90);
        }
        var _pop = 1 + (0.35 * (1 - clamp((_el - global.st_k_rank_zoom_ms) / 140, 0, 1)));
        for (var i = 0; i < array_length(_parts.rects); i++)
        {
            var _r = _parts.rects[i];
            draw_sprite_part_ext(_parts.spr, sprite_get_number(_parts.spr) - 1, _r[0], _r[1], _r[2], _r[3], _left + 760 + ((_r[0] - 760) * _pop), _top + 190 + ((_r[1] - 190) * _pop), _pop, _pop, _col, _alpha);
        }
        if (!_silhouette)
        {
            lang_draw_sprite_ext(_parts.text, 0, x, y, 1, 1, 0, c_white, 1);
        }
    }
    gpu_set_tex_filter(_filter);
    shader_set(_silhouette ? shd_rank : global.Pal_Shader);
}

// the white fade into the results: Sonic, already celebrating, where the game draws its player
function st_fade_draw()
{
    var _a = (variable_global_exists("st_ready") && global.st_ready && object_index == obj_player1) ? st_time_anim("Victory") : undefined;
    if (_a == undefined)
    {
        draw_sprite_ext(sprite_index, image_index, x, y, xscale, yscale, image_angle, image_blend, image_alpha);
        exit;
    }
    shader_reset();
    draw_sprite_ext(_a.spr, st_ta_f, round(x), round(y) + global.st_k_feet_offset + global.st_lift, xscale, 1, 0, c_white, 1);
    shader_set(global.Pal_Shader);
}

function st_menu_anim()
{
    if (state == 98)
    {
        return "Victory";
    }
    switch (sprite_index)
    {
        case spr_titlepep_punch:
            return "Hurt";
        case spr_titlepep_angry:
            return "Outta Here";
        case spr_titlepep_forward:
        case spr_titlepep_left:
        case spr_titlepep_middle:
        case spr_titlepep_right:
            return "Idle";
        case spr_titlepep_forwardtoleft:
        case spr_titlepep_lefttomiddle:
        case spr_titlepep_middletoleft:
        case spr_titlepep_middletoright:
        case spr_titlepep_righttomiddle:
            return "Walk";
    }
    return "";
}

function st_menu_face()
{
    switch (sprite_index)
    {
        case spr_titlepep_left:
        case spr_titlepep_forwardtoleft:
        case spr_titlepep_middletoleft:
        case spr_titlepep_righttomiddle:
            return -1;
    }
    return 1;
}

function st_menu_draw(_x, _y)
{
    var _n = (variable_global_exists("st_ready") && global.st_ready) ? st_menu_anim() : "";
    var _a = (_n != "") ? st_time_anim(_n) : undefined;
    if (_a == undefined)
    {
        draw_sprite_ext(sprite_index, image_index, _x, _y, image_xscale, image_yscale, image_angle, image_blend, image_alpha);
        exit;
    }
    shader_reset();
    // Noise's up and down belong to this now
    noise_unlocked = false;
    if (state == 0 && variable_instance_exists(id, "key_up2"))
    {
        var _pick = (key_down2 ? 1 : 0) - (key_up2 ? 1 : 0);
        if (_pick != 0)
        {
            var _count = array_length(global.st_modes);
            st_mode_set((global.st_mode + _pick + _count) mod _count);
            st_sound("Global/MenuBleep");
            _a = st_time_anim(_n);
        }
    }
    st_make_art();
    global.st_menu_drawn = true;
    var _filter = gpu_get_tex_filter();
    gpu_set_tex_filter(false);
    var _ms = global.st_k_menu_scale;
    var _face = st_menu_face();
    var _my = round(_y) + global.st_k_menu_y;
    if (global.st_side)
    {
        var _ta = ds_map_find_value(global.st_maps.Tails, _n);
        if (_ta != undefined)
        {
            draw_sprite_ext(_ta.spr, min(st_ta_f, _ta.frames - 1), round(_x) - (_face * _ms * 30), _my + (_ms * global.st_tails_lift), _ms * _face, _ms, 0, c_white, 1);
        }
    }
    if (global.st_char == "Tails")
    {
        st_draw_tail(_n, round(_x), _my + (_ms * global.st_lift), _ms * _face, _ms, c_white, 1);
    }
    draw_sprite_ext(_a.spr, min(st_ta_f, _a.frames - 1), round(_x), _my + (_ms * global.st_lift), _ms * _face, _ms, 0, c_white, 1);
    gpu_set_tex_filter(_filter);
    if (state == 0)
    {
        draw_set_font(lang_get_font("bigfont"));
        draw_set_halign(fa_center);
        draw_set_valign(fa_middle);
        draw_set_color(c_white);
        draw_set_alpha(extrauialpha);
        draw_text(480, 512, global.st_modes[global.st_mode].label);
        draw_set_alpha(1);
    }
    shader_set(global.Pal_Shader);
}

// redraws one of the game's pictures from Sonic's frames
function st_art_sprite(_target, _name, _w, _h, _ox, _oy, _cx, _cy, _scale, _col)
{
    var _a = ds_map_find_value(global.st_a, _name);
    if (_a == undefined)
    {
        return;
    }
    var _s = surface_create(_w, _h);
    surface_set_target(_s);
    draw_clear_alpha(c_black, 0);
    draw_sprite_ext(_a.spr, _a.frames - 1, _cx, _cy, _scale, _scale, 0, _col, 1);
    surface_reset_target();
    var _n = sprite_create_from_surface(_s, 0, 0, _w, _h, false, false, _ox, _oy);
    sprite_assign(_target, _n);
    sprite_delete(_n);
    surface_free(_s);
}

function st_make_art()
{
    if (variable_global_exists("st_art_made") && global.st_art_made == global.st_mode)
    {
        return;
    }
    global.st_art_made = global.st_mode;
    var _filter = gpu_get_tex_filter();
    gpu_set_tex_filter(false);
    st_art_sprite(spr_vspeppino, "Victory", 415, 357, 0, 357, 190, 190, 3, c_white);
    st_art_sprite(spr_vspeppinoshadow, "Victory", 415, 357, 0, 357, 190, 190, 3, c_black);
    st_art_sprite(spr_titlepep_punch, "Hurt", 390, 379, 213, 224, 213, 224, 3, c_white);
    var _idle = ds_map_find_value(global.st_a, "Idle");
    if (_idle != undefined)
    {
        var _ds = surface_create(960, 540);
        surface_set_target(_ds);
        draw_clear_alpha(c_black, 0);
        draw_sprite(spr_menudark, 0, 0, 0);
        draw_set_color(c_black);
        draw_rectangle(400, 190, 560, 510, false);
        draw_set_color(c_white);
        draw_sprite_ext(_idle.spr, 0, 486, 327 + global.st_k_menu_y + (global.st_lift * global.st_k_menu_scale), global.st_k_menu_scale, global.st_k_menu_scale, 0, make_colour_rgb(64, 64, 72), 1);
        surface_reset_target();
        var _dn = sprite_create_from_surface(_ds, 0, 0, 960, 540, false, false, 0, 0);
        sprite_assign(spr_menudark, _dn);
        sprite_delete(_dn);
        surface_free(_ds);
    }
    var _s = surface_create(960, 540);
    surface_set_target(_s);
    draw_clear_alpha(c_black, 0);
    draw_set_font(lang_get_font("bigfont"));
    draw_set_halign(fa_left);
    draw_set_valign(fa_top);
    draw_set_color(c_white);
    var _vs = global.st_modes[global.st_mode].label;
    var _ts = min(2.5, (1.6 * string_width("KNUCKLES")) / string_width(_vs));
    draw_text_transformed_color(55, 133, _vs, _ts, _ts, 0, c_black, c_black, c_black, c_black, 1);
    draw_text_transformed_color(51, 125, _vs, _ts, _ts, 0, c_white, c_white, c_white, c_white, 1);
    surface_reset_target();
    var _n = sprite_create_from_surface(_s, 0, 0, 960, 540, false, false, 0, 0);
    sprite_assign(spr_vstitle_player, _n);
    sprite_delete(_n);
    surface_free(_s);
    gpu_set_tex_filter(_filter);
    st_log("art rebuilt for " + global.st_name);
}

// test mode: every rank in turn, then the file select, then rooms the bot's level never reaches
function st_test_after_level()
{
    var _w = global.st_test_wait;
    switch (global.st_lv_step)
    {
        case "end":
            if (instance_exists(obj_rank))
            {
                global.st_rank_seen = ds_map_create();
                global.st_rank_list = ["d", "c", "b", "a", "s", "p"];
                global.st_rank_i = -1;
                st_lv("rank_next");
            }
            else if (_w > 900)
            {
                st_test_report("results-shows-sonic", false, "no rank screen");
                st_lv("rank_leave");
            }
            break;
        case "rank_next":
            global.st_rank_i++;
            if (global.st_rank_i >= array_length(global.st_rank_list))
            {
                var _all = true;
                for (var i = 0; i < array_length(global.st_rank_list); i++)
                {
                    _all = _all && ds_map_exists(global.st_rank_seen, global.st_rank_list[i]);
                }
                st_test_report("results-shows-sonic", _all, string(ds_map_size(global.st_rank_seen)) + " ranks");
                with (obj_rank)
                {
                    alarm[2] = 1;
                }
                st_lv("rank_leave");
                break;
            }
            global.rank = global.st_rank_list[global.st_rank_i];
            with (obj_rank)
            {
                alarm[2] = 900;
                st_rank_t0 = current_time;
                st_ta_f = 0;
                st_ta_t = 0;
            }
            st_log("look rank " + global.rank);
            st_lv("rank_hold");
            break;
        case "rank_hold":
            if (_w == 100 && variable_global_exists("st_rank_drawn") && global.st_rank_drawn == global.rank)
            {
                ds_map_set(global.st_rank_seen, global.rank, true);
            }
            with (obj_rank)
            {
                alarm[2] = 900;
            }
            if (_w > 600)
            {
                st_lv("rank_next");
            }
            break;
        case "rank_leave":
            // the silhouette, the toppins and the way out are the game's own
            if (_w == 1)
            {
                st_log("look rank silhouette");
            }
            if (_w > 780 || !instance_exists(obj_rank))
            {
                global.st_sweep = ["boss_pepperman", "boss_vigilante", "boss_noise", "boss_fakepep", "boss_pizzaface", "medieval_1", "ruin_1", "dungeon_1", "badland_1", "graveyard_1", "farm_1", "saloon_1", "forest_1", "space_1", "minigolf_1", "street_1", "sewer_1", "industrial_1", "freezer_1", "chateau_1", "kidsparty_1", "war_1", "exit_1", "tower_peppinohouse"];
                global.st_sweep_i = -1;
                st_lv("sweep_next");
            }
            break;
        case "sweep_next":
            global.st_sweep_i++;
            if (global.st_sweep_i >= array_length(global.st_sweep))
            {
                st_test_report("sweep-rooms", true, "");
                st_lv("sweep_done");
                break;
            }
            var _r = asset_get_index(global.st_sweep[global.st_sweep_i]);
            st_log("sweep room " + global.st_sweep[global.st_sweep_i]);
            if (_r != -1 && room_exists(_r))
            {
                st_go_room(_r);
                st_lv("sweep_hold");
            }
            break;
        case "sweep_hold":
            // in a boss room Sonic keeps spindashing at the boss, and its health goes in the log
            var _isboss = global.st_sweep_i < 5;
            if (_w == 120 && room != asset_get_index(global.st_sweep[global.st_sweep_i]))
            {
                st_log("sweep room again");
                st_go_room(asset_get_index(global.st_sweep[global.st_sweep_i]));
            }
            if (_isboss)
            {
                var _boss = -4;
                var _names = ["obj_pepperman", "obj_vigilanteboss", "obj_noiseboss", "obj_fakepepboss", "obj_pizzafaceboss"];
                for (var i = 0; i < array_length(_names); i++)
                {
                    var _o = asset_get_index(_names[i]);
                    if (_o != -1 && instance_exists(_o))
                    {
                        _boss = _o;
                    }
                }
                if (_boss != -4)
                {
                    var _m = _w mod 180;
                    if (_m == 0)
                    {
                        st_test_clear_keys();
                        global.st_test_dir = (_boss.x >= obj_player1.x) ? 1 : -1;
                        st_log("boss " + object_get_name(_boss) + " hp " + string(_boss.hp) + " state " + string(_boss.state) + " player state " + string(obj_player1.state) + " ball " + string(obj_player1.st_ball) + " dist " + string(round(abs(_boss.x - obj_player1.x))));
                    }
                    st_test_spindash(_m);
                }
                else if (_w mod 180 == 0)
                {
                    st_log("boss not found in " + room_get_name(room));
                }
            }
            if (_w > (_isboss ? 720 : 300))
            {
                st_log("sweep ok " + room_get_name(room) + " fps " + string(round(fps)) + " instances " + string(instance_count));
                if (room == tower_peppinohouse)
                {
                    st_log("room name: " + string(global.roommessage));
                }
                st_lv("sweep_next");
            }
            break;
    }
}

// ---- who plays: Mania's four choices

function st_mode_set(_i, _save = true)
{
    var _m = global.st_modes[_i];
    global.st_mode = _i;
    global.st_char = _m.ch;
    global.st_name = _m.name;
    global.st_side = _m.side;
    global.st_jump_mult = _m.jump;
    global.st_lift = _m.lift;
    global.st_ball_lift = _m.ball;
    global.st_a = variable_struct_get(global.st_maps, _m.ch);
    if (instance_exists(obj_player1) && variable_instance_exists(obj_player1, "st_anim_name"))
    {
        with (obj_player1)
        {
            st_anim_frame = 0;
            st_anim_timer = 0;
        }
    }
    if (_save)
    {
        var _f = file_text_open_write("st_character.txt");
        if (_f != -1)
        {
            file_text_write_string(_f, string(_i));
            file_text_close(_f);
        }
    }
}

function st_mode_load()
{
    var _i = 1;
    if (file_exists("st_character.txt"))
    {
        var _f = file_text_open_read("st_character.txt");
        if (_f != -1)
        {
            _i = clamp(floor(real(file_text_read_real(_f))), 0, array_length(global.st_modes) - 1);
            file_text_close(_f);
        }
    }
    st_mode_set(_i, false);
}

// the rest of the game's words name whoever is playing
function st_name_text(_s)
{
    if (!is_string(_s) || !variable_global_exists("st_name") || string_pos("eppino", _s) + string_pos("EPPINO", _s) == 0)
    {
        return _s;
    }
    _s = string_replace_all(_s, "PEPPINO", global.st_name);
    return string_replace_all(_s, "Peppino", string_upper(string_char_at(global.st_name, 1)) + string_lower(string_delete(global.st_name, 1, 1)));
}

function st_h_lang_value(_key)
{
    if (global.lang == "en" && variable_global_exists("st_text"))
    {
        var _line = ds_map_find_value(global.st_text, _key);
        if (_line != undefined)
        {
            return st_name_text(_line);
        }
    }
    return st_name_text(lang_get_value(_key));
}

function st_h_lang_newline(_key)
{
    return string_replace_all(st_h_lang_value(_key), "\\n", "\n");
}

// Tails's own tail is a separate sprite for the poses that don't draw one
function st_draw_tail(_name, _x, _y, _xs, _ys, _blend, _alpha)
{
    var _t = "";
    switch (_name)
    {
        case "Idle":
        case "Bored 1":
        case "Bored 2":
        case "Look Up":
        case "Crouch":
        case "Victory":
            _t = "@Tail0";
            break;
        case "Jump":
            _t = "@Tail1";
            break;
        case "Skid":
        case "Skid Turn":
            _t = "@Tail2";
            break;
        case "Push":
            _t = "@Tail3";
            break;
        case "Spindash":
            _t = "@Tail5";
            break;
    }
    if (_t == "")
    {
        return;
    }
    var _a = ds_map_find_value(global.st_a, _t);
    if (_a != undefined)
    {
        draw_sprite_ext(_a.spr, (current_time div 66) mod _a.frames, _x, _y, _xs, _ys, 0, _blend, _alpha);
    }
}

// Sonic & Tails: Tails follows a moment behind, doing what Sonic did
function st_sidekick(_x, _y, _xs, _blend, _alpha)
{
    if (!global.st_side)
    {
        return;
    }
    var _n = 18;
    if (!variable_global_exists("st_side_x") || global.st_side_room != room)
    {
        global.st_side_x = array_create(_n, _x);
        global.st_side_y = array_create(_n, _y);
        global.st_side_xs = array_create(_n, _xs);
        global.st_side_name = array_create(_n, "Idle");
        global.st_side_f = array_create(_n, 0);
        global.st_side_i = 0;
        global.st_side_room = room;
    }
    var _i = global.st_side_i;
    var _map = global.st_maps.Tails;
    var _a = ds_map_find_value(_map, global.st_side_name[_i]);
    if (_a == undefined)
    {
        _a = ds_map_find_value(_map, "Idle");
    }
    if (_a != undefined)
    {
        var _sx = global.st_side_x[_i];
        var _sn = global.st_side_name[_i];
        var _sy = global.st_side_y[_i] + ((_sn == "Jump" || _sn == "Dropdash") ? global.st_tails_ball : global.st_tails_lift);
        var _sf = min(global.st_side_f[_i], _a.frames - 1);
        var _old = global.st_a;
        global.st_a = _map;
        st_draw_tail(global.st_side_name[_i], _sx, _sy, global.st_side_xs[_i], 1, _blend, _alpha);
        global.st_a = _old;
        draw_sprite_ext(_a.spr, _sf, _sx, _sy, global.st_side_xs[_i], 1, 0, _blend, _alpha);
    }
    global.st_side_x[_i] = _x - (_xs * 26);
    global.st_side_y[_i] = _y;
    global.st_side_xs[_i] = _xs;
    global.st_side_name[_i] = st_anim_name;
    global.st_side_f[_i] = st_anim_frame;
    global.st_side_i = (_i + 1) mod _n;
}

// jump again in the air: Sonic's drop dash, Tails's flight, Knuckles's glide and climb
function st_air_ability(_mv)
{
    switch (global.st_char)
    {
        case "Sonic":
            if (st_jumped && st_ball)
            {
                if (key_jump2 && (st_drop > 0 || key_jump))
                {
                    st_drop++;
                    if (st_drop == global.st_k_drop_charge)
                    {
                        st_sound("Global/DropDash");
                    }
                }
                else if (!key_jump2)
                {
                    st_drop = 0;
                }
            }
            break;
        case "Tails":
            if (!st_fly && st_jumped && st_ball && key_jump)
            {
                st_fly = true;
                st_ball = false;
                st_jumped = false;
                st_fly_t = 0;
                st_fly_up = 12;
                st_sound("Global/Flying");
            }
            if (st_fly)
            {
                st_fly_t++;
                var _tired = st_fly_t >= global.st_k_fly_ticks;
                if (_tired && st_fly_t == global.st_k_fly_ticks)
                {
                    st_sound("Global/Tired");
                }
                if (!_tired && key_jump)
                {
                    st_fly_up = 12;
                }
                if (st_fly_up > 0)
                {
                    st_fly_up--;
                    vsp = max(vsp - global.st_k_fly_lift, -global.st_k_fly_up);
                }
                else
                {
                    vsp = min(vsp + global.st_k_fly_fall, global.st_k_fly_down);
                }
                vsp -= grav;
            }
            break;
        case "Knux":
            if (st_glide == 0 && !st_climb && st_jumped && st_ball && key_jump)
            {
                st_glide = 1;
                st_ball = false;
                st_jumped = false;
                st_gsp = xscale * max(abs(st_gsp), global.st_k_glide_start);
                vsp = max(vsp, 0);
                st_sound("Global/Flying");
            }
            if (st_glide == 1)
            {
                if (!key_jump2)
                {
                    st_glide = 2;
                }
                else
                {
                    st_gsp = Approach(st_gsp, xscale * global.st_k_glide_top, global.st_k_glide_acc);
                    vsp = min(vsp + 0.25, global.st_k_glide_fall) - grav;
                    if (scr_solid(x + xscale, y) && !place_meeting(x + xscale, y, obj_slope) && !place_meeting(x + xscale, y, obj_destructibles))
                    {
                        st_glide = 0;
                        st_climb = true;
                        st_climb_dir = xscale;
                        st_sound("Global/Grab");
                    }
                }
            }
            if (st_climb)
            {
                xscale = st_climb_dir;
                st_gsp = 0;
                var _v = (key_down ? 1 : 0) - (key_up ? 1 : 0);
                if (key_jump)
                {
                    st_climb = false;
                    xscale = -st_climb_dir;
                    st_gsp = xscale * global.st_k_glide_start;
                    vsp = -global.st_k_jump * global.st_jump_mult;
                    st_jumped = true;
                    st_ball = true;
                    st_sound("Global/Jump");
                }
                else if (!scr_solid(x + xscale, y - 30))
                {
                    // over the top
                    st_climb = false;
                    st_gsp = xscale * 4;
                    vsp = -global.st_k_jump * 0.8;
                }
                else if (!scr_solid(x + xscale, y + 30))
                {
                    st_climb = false;
                }
                else
                {
                    vsp = (_v * global.st_k_climb_speed) - grav;
                }
            }
            break;
    }
}

function st_test_report(_name, _ok, _why = "")
{
    if (ds_map_exists(global.st_test_done, _name))
    {
        return;
    }
    ds_map_set(global.st_test_done, _name, _ok);
    var _line = _ok ? ("pass " + _name) : ("fail " + _name + ": " + _why);
    var _f = file_text_open_append("st_checks_all.txt");
    if (_f != -1)
    {
        file_text_write_string(_f, _line);
        file_text_writeln(_f);
        file_text_close(_f);
    }
    var _counted = false;
    for (var i = 0; i < array_length(global.st_melty_checks); i++)
    {
        _counted = _counted || (global.st_melty_checks[i] == _name);
    }
    if (_counted)
    {
        _f = file_text_open_append("st_checks.txt");
        if (_f != -1)
        {
            file_text_write_string(_f, _line);
            file_text_writeln(_f);
            file_text_close(_f);
        }
    }
}

function st_test_input()
{
    var _b = global.st_bot;
    key_left = -_b.l;
    key_right = _b.r;
    key_down = _b.d;
    key_up = _b.u;
    key_jump = _b.j;
    key_jump2 = _b.jh;
    key_taunt2 = _b.t;
    key_attack = 0;
    key_attack2 = 0;
    _b.j = 0;
    _b.t = 0;
}

function st_test_clear_keys()
{
    var _b = global.st_bot;
    _b.l = 0;
    _b.r = 0;
    _b.d = 0;
    _b.u = 0;
    _b.jh = 0;
}

function st_test_hold_dir()
{
    var _b = global.st_bot;
    _b.l = (global.st_test_dir < 0);
    _b.r = (global.st_test_dir > 0);
}

function st_test_tick()
{
    global.st_test_wait++;
    var _w = global.st_test_wait;
    var _b = global.st_bot;
    switch (global.st_test_phase)
    {
        case 0:
            st_test_report("mania-sprites-read", global.st_sprites_loaded >= 30, string(global.st_sprites_loaded) + " sprites");
            st_test_report("mania-sfx-read", global.st_sounds_loaded >= 30, string(global.st_sounds_loaded) + " sounds");
            if (_w > 180 && room != Loadiingroom && instance_exists(obj_player1) && instance_exists(obj_savesystem) && obj_savesystem.state == 0)
            {
                // the file select first, the way the game starts
                if (!variable_global_exists("st_menu_drawn"))
                {
                    global.st_menu_drawn = false;
                    st_log("look menu");
                    room_goto(Mainmenu);
                    global.st_test_phase = 14;
                    global.st_test_wait = 0;
                    break;
                }
                global.currentsavefile = 3;
                with (obj_savesystem)
                {
                    ispeppino = true;
                }
                gamesave_async_load();
                global.st_test_phase = 1;
                global.st_test_wait = 0;
            }
            break;
        case 1:
            if (_w > 60 && obj_savesystem.state == 0)
            {
                global.collect = 0;
                global.startgate = true;
                global.leveltosave = "entrance";
                global.leveltorestart = entrance_1;
                global.levelattempts = 0;
                with (obj_player)
                {
                    backtohubstartx = x;
                    backtohubstarty = y;
                    backtohubroom = tower_entrancehall;
                    targetRoom = entrance_1;
                    targetDoor = "A";
                    visible = true;
                }
                with (obj_player1)
                {
                    instance_create(x, y, obj_fadeout);
                }
                global.st_test_phase = 2;
                global.st_test_wait = 0;
            }
            break;
        case 2:
            if (room == entrance_1 && !instance_exists(obj_fadeout))
            {
                with (obj_player1)
                {
                    if (state != 0 && state != 92)
                    {
                        state = 0;
                    }
                    visible = true;
                }
                global.st_test_phase = 3;
                global.st_test_wait = 0;
            }
            else if (_w > 600)
            {
                room_goto(entrance_1);
                global.st_test_wait = 300;
            }
            break;
        case 3:
            if (_w > 90)
            {
                var _ok = room == entrance_1 && obj_player1.st_spr != -1;
                st_test_report("level-entered", _ok, "room " + room_get_name(room));
                var _music = instance_exists(obj_music) && !is_real(obj_music.music);
                st_test_report("pizza-tower-music", _music, "no music struct");
                with (obj_player1)
                {
                    global.st_test_home_x = x;
                    global.st_test_home_y = y;
                    var _r = st_test_clear_run(1);
                    var _l = st_test_clear_run(-1);
                    global.st_test_dir = (_l > _r) ? -1 : 1;
                    global.st_test_room_dist = clamp(max(_l, _r) * 0.7, 100, 240);
                    st_log("test floor: right " + string(_r) + " left " + string(_l));
                }
                global.st_test_phase = 4;
                global.st_test_wait = 0;
            }
            break;
        case 4:
            st_test_hold_dir();
            if (abs(obj_player1.st_gsp) >= 6)
            {
                st_test_report("momentum", true);
                st_test_clear_keys();
                global.st_test_phase = 5;
                global.st_test_wait = 0;
            }
            else if (_w == 80 && abs(obj_player1.st_gsp) < 2)
            {
                global.st_test_dir = -global.st_test_dir;
            }
            else if (_w > 300)
            {
                st_test_report("momentum", false, "top " + string(abs(obj_player1.st_gsp)));
                st_test_clear_keys();
                global.st_test_phase = 5;
                global.st_test_wait = 0;
            }
            break;
        case 5:
            // stop, then a block ahead and a spindash into it
            if (_w == 20)
            {
                st_test_go_home();
                with (obj_player1)
                {
                    // floor-level block in Sonic's path: 32 tall, standing on the floor
                    var _px = x + (global.st_test_dir * global.st_test_room_dist);
                    global.st_test_inst = instance_create(_px, y + 14, obj_destroyable);
                }
                global.st_test_phase = 6;
                global.st_test_wait = 0;
            }
            break;
        case 6:
            if (st_test_spindash(_w))
            {
                var _gone = !instance_exists(global.st_test_inst);
                if (_gone || _w > 200)
                {
                    st_test_report("spindash-breaks-block", _gone, "block still there");
                st_test_report("spindash-dust", global.st_spindust_shown, "dust never drawn");
                    st_test_clear_keys();
                    global.st_test_phase = 7;
                    global.st_test_wait = 0;
                }
            }
            break;
        case 7:
            if (_w == 30)
            {
                st_test_go_home();
                with (obj_player1)
                {
                    var _ex = x + (global.st_test_dir * global.st_test_room_dist);
                    global.st_test_inst = instance_create(_ex, y, obj_forknight);
                    global.st_test_combo = global.combo;
                }
                global.st_test_phase = 8;
                global.st_test_wait = 0;
            }
            break;
        case 8:
            if (_w mod 20 == 0)
            {
                var _e = global.st_test_inst;
                var _p = obj_player1;
                st_log("kill w" + string(_w) + " p " + string(_p.x) + "," + string(_p.y) + " state " + string(_p.state) + " ball " + string(_p.st_ball) + " gsp " + string(_p.st_gsp) + " ik " + string(_p.instakillmove) + " e " + (instance_exists(_e) ? (string(_e.x) + "," + string(_e.y) + " state " + string(_e.state) + " inv " + string(_e.invtime) + " kill " + string(_e.instantkillable) + " box " + string(instance_number(obj_baddiecollisionbox))) : "gone"));
            }
            if (st_test_spindash(_w))
            {
                var _killed = !instance_exists(global.st_test_inst);
                if (global.combo > global.st_test_combo || _w > 240)
                {
                    st_test_report("spindash-kills-enemy", _killed || global.combo > global.st_test_combo, "enemy still there");
                    st_test_report("combo-ticks", global.combo > global.st_test_combo && global.combotime > 0, "combo " + string(global.combo));
                    st_test_clear_keys();
                    global.st_test_phase = 9;
                    global.st_test_wait = 0;
                    st_test_go_home();
                }
            }
            break;
        case 9:
            // taunts: the bot looks at which poses Sonic took
            if (_w mod 70 == 0 && obj_player1.state != 84)
            {
                _b.t = 1;
            }
            if (_w > 300)
            {
                var _seen = 0;
                for (var i = 0; i < array_length(global.st_test_poses); i++)
                {
                    if (global.st_test_poses[i])
                    {
                        _seen++;
                    }
                }
                st_test_report("taunt-poses", _seen >= 2, string(_seen) + " poses");
                global.st_test_phase = 11;
                global.st_test_wait = 0;
            }
            break;
        case 11:
            // what a hit and a ground pound really play
            if (_w == 1)
            {
                global.st_test_n = st_test_count("Global/LoseRings");
                st_test_hit(5);
            }
            if (_w == 8)
            {
                st_test_report("hit-sound-rings", st_test_count("Global/LoseRings") == global.st_test_n + 1, "played " + string(st_test_count("Global/LoseRings") - global.st_test_n) + " times");
                var _pos = audio_sound_get_track_position(global.st_test_last_voice);
                st_test_report("mania-sfx-plays", _pos > 0, "track position " + string(_pos));
                st_log("hit voice position " + string(_pos) + " gain " + string(audio_sound_get_gain(global.st_test_last_voice)) + " master " + string(audio_get_master_gain(0)));
            }
            if (_w == 200)
            {
                global.st_test_n = st_test_count("Global/Hurt");
                st_test_hit(0);
            }
            if (_w == 208)
            {
                st_test_report("hit-sound-no-rings", st_test_count("Global/Hurt") == global.st_test_n + 1, "played " + string(st_test_count("Global/Hurt") - global.st_test_n) + " times");
            }
            if (_w == 400)
            {
                st_test_go_home();
                _b.j = 1;
                global.st_test_n = st_test_count(global.st_pound_start);
                global.st_test_n2 = st_test_count(global.st_pound_land);
            }
            if (_w == 412)
            {
                _b.d = 1;
                _b.j = 1;
            }
            if (_w == 416)
            {
                _b.d = 0;
                st_test_report("ground-pound-sound", st_test_count(global.st_pound_start) == global.st_test_n + 1, "state " + string(obj_player1.state) + " played " + string(st_test_count(global.st_pound_start) - global.st_test_n) + " times");
            }
            if (_w == 520)
            {
                st_test_report("ground-pound-land-sound", st_test_count(global.st_pound_land) == global.st_test_n2 + 1, "state " + string(obj_player1.state) + " played " + string(st_test_count(global.st_pound_land) - global.st_test_n2) + " times");
                st_test_clear_keys();
                global.st_test_phase = 15;
                global.st_test_wait = 0;
            }
            break;
        case 15:
            if (_w == 1)
            {
                st_test_go_home();
            }
            if (_w == 30)
            {
                _b.j = 1;
                _b.jh = 1;
            }
            if (_w == 44)
            {
                _b.j = 1;
            }
            if (_w == 70)
            {
                var _p15 = obj_player1;
                var _ab = (global.st_char == "Sonic") || _p15.st_fly || (_p15.st_glide != 0) || _p15.st_climb;
                st_test_report("air-ability", _ab, global.st_char + " fly " + string(_p15.st_fly) + " glide " + string(_p15.st_glide) + " climb " + string(_p15.st_climb) + " vsp " + string(_p15.vsp));
                st_log("ability " + global.st_char + " fly " + string(_p15.st_fly) + " glide " + string(_p15.st_glide) + " climb " + string(_p15.st_climb) + " vsp " + string(_p15.vsp) + " anim " + _p15.st_anim_name);
                _b.jh = 0;
            }
            if (_w > 150)
            {
                st_test_clear_keys();
                global.st_test_phase = 12;
                global.st_test_wait = 0;
                st_tour_init();
            }
            break;
        case 14:
            if (_w == 300)
            {
                with (obj_mainmenu)
                {
                    state = 8;
                    currentselect = -1;
                    visualselect = -1;
                    darkcount = 7;
                    dark = false;
                    darkbuffer = 5;
                }
                st_log("look menu lit");
                global.st_test_mode = global.st_mode;
            }
            if (_w > 600 && _w < 1560 && (_w mod 240) == 0)
            {
                st_mode_set((global.st_mode + 1) mod array_length(global.st_modes), false);
                st_log("look menu " + global.st_modes[global.st_mode].label);
            }
            if (_w > 1680)
            {
                st_mode_set(global.st_test_mode, false);
                st_test_report("menu-shows-sonic", global.st_menu_drawn, "not drawn");
                var _hurt = st_h_lang_value("peppinohurt");
                var _house = st_h_lang_value("room_peppinohouse");
                var _teach = st_h_lang_value("tutorial5");
                st_log("text: " + _hurt + " | " + _house + " | " + _teach);
                st_test_report("text-follows-character", string_pos("eppino", _hurt) + string_pos("EPPINO", _house) == 0 && string_pos("spindash", _teach) > 0, _hurt + " " + _teach);
                global.st_test_phase = 0;
                global.st_test_wait = 181;
            }
            break;
        case 12:
            st_tour_tick();
            break;
        case 13:
            st_level_tick();
            break;
        case 10:
            // goes on playing for the recording: never ends the game
            if (_w == 1)
            {
                st_test_clear_keys();
                _b.d = 1;
            }
            if (_w == 6 || _w == 16 || _w == 26)
            {
                _b.j = 1;
            }
            if (_w == 40)
            {
                _b.d = 0;
                st_test_hold_dir();
            }
            if (_w == 90)
            {
                _b.j = 1;
                _b.jh = 1;
            }
            if (_w == 110)
            {
                _b.jh = 0;
            }
            if (_w > 170)
            {
                if (abs(obj_player1.st_gsp) < 1 && _w > 170)
                {
                    global.st_test_dir = -global.st_test_dir;
                }
                global.st_test_wait = 0;
            }
            break;
    }
}

function st_test_spindash(_w)
{
    var _b = global.st_bot;
    if (_w == 1)
    {
        _b.d = 1;
    }
    if (_w == 6 || _w == 16 || _w == 26)
    {
        _b.j = 1;
    }
    if (_w == 40)
    {
        _b.d = 0;
        st_test_hold_dir();
    }
    return _w > 40;
}
