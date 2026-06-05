//! Audio subsystem — RIX background music via pal-adplug.
//!
//! Configuration mirrors SDLPAL's gConfig defaults:
//!   OPL core   = DBFLT (DOSBox floating-point)
//!   OPL chip   = OPL2 (auto-upgraded to DUAL_OPL2 by surround)
//!   OPL rate   = 49716 Hz
//!   Output     = 44100 Hz, stereo
//!   Surround   = on, offset=384
//!   Resampler  = SINC quality
//!
//! Threading model: command-queue handoff, no mutex.
//!
//! All `pal_rix_player_*` calls (rewind, reset_opl, render) happen on the
//! libretro thread inside `produce()`. The game thread's `playMusic()` only
//! writes a single Pending slot; the libretro thread reads-and-clears it
//! at the top of each produce(). This avoids the race we hit when the game
//! thread called reset_opl mid-render and shredded chip state under our feet.
//!
//! The Pending slot is racy on word-sized fields, but only between two
//! threads with one writer each, and consequence of a torn read is at most a
//! one-frame-lag music switch — not a hang. SDLPAL's libretro port relies on
//! the same convention.

const std = @import("std");
const global = @import("global.zig");
const palcommon = @import("palcommon.zig");
const voc_mod = @import("voc.zig");

const c = @cImport({
    @cInclude("pal_adplug.h");
    @cInclude("resampler.h");
});

pub const SAMPLE_RATE: u32 = 44100;
pub const CHANNELS: u32 = 2;
const FRAMES_PER_VIDEO_FRAME: u32 = SAMPLE_RATE / 60; // 735 frames @ 60 Hz

const Pending = struct {
    set: bool = false,
    num: i32 = 0,
    loop: bool = false,
    fade_seconds: f32 = 0,
};

const Music = struct {
    num: i32 = 0,
    loop: bool = false,
    active: bool = false,

    fade: enum { none, in, out } = .none,
    fade_remaining: u32 = 0,
    fade_total: u32 = 1, // never zero — used as denominator
    /// When fade-out completes, switch to this song. -1 = just stop.
    next: i32 = -1,
    next_loop: bool = false,
    next_fade_in_total: u32 = 0,
};

var g_player: ?*c.pal_rix_player_t = null;
var g_music: Music = .{};
var g_pending: Pending = .{};
var g_init_attempted: bool = false;

/// User-controlled toggles backed by the in-game system menu. Both default
/// to enabled so a vanilla launch sounds like SDLPAL out of the box.
/// Plain `bool` because they're written by the game thread and read by the
/// libretro thread once per produce(); the worst case of a torn read is one
/// frame of stale audio and that's fine.
var g_music_enabled: bool = true;
var g_sound_enabled: bool = true;

pub fn musicEnabled() bool {
    return g_music_enabled;
}
pub fn soundEnabled() bool {
    return g_sound_enabled;
}
pub fn setMusicEnabled(on: bool) void {
    g_music_enabled = on;
}
pub fn setSoundEnabled(on: bool) void {
    g_sound_enabled = on;
}

// --- Sound effect mixer ---------------------------------------------------
//
// Up to MAX_VOICES voices play concurrently; each owns a sinc resampler that
// upsamples the VOC's native rate (typically 11025 Hz) to SAMPLE_RATE.
// SDLPAL handles SFX the same way (sound.c:728 SOUND_Play).

const MAX_VOICES: usize = 8;
const SFX_QUEUE: usize = 16; // power of two preferred for the modulo

const Voice = struct {
    active: bool = false,
    cursor: usize = 0,
    samples: []const u8 = &.{}, // 8-bit unsigned mono PCM
    rate: u32 = 0,
    /// One resampler per output channel. Allocated lazily on first use; freed
    /// only at deinit so we don't churn malloc on rapid SFX.
    resampler: [2]?*anyopaque = .{ null, null },
};

const SfxRequest = struct {
    num: i32 = -1,
};

var g_voices: [MAX_VOICES]Voice = [_]Voice{.{}} ** MAX_VOICES;
/// Last-played SFX number. SDLPAL's player->lastSFX deduplicates rapid
/// duplicate triggers (SOUND_Play returns FALSE if num matches lastSFX);
/// we mirror that behaviour to avoid the same hit/footstep stacking up.
var g_last_sfx: i32 = 0;

var g_sfx_queue: [SFX_QUEUE]SfxRequest = [_]SfxRequest{.{}} ** SFX_QUEUE;
var g_sfx_head: u32 = 0; // libretro thread reads here
var g_sfx_tail: u32 = 0; // game thread writes here

fn tryInit() void {
    if (g_player != null or g_init_attempted) return;

    const mus_bytes = global.res_buffers.mus orelse return;
    g_init_attempted = true;

    var cfg: c.pal_rix_config_t = undefined;
    c.pal_rix_config_default(&cfg);
    cfg.sample_rate = @intCast(SAMPLE_RATE);
    cfg.stereo = if (CHANNELS == 2) 1 else 0;

    g_player = c.pal_rix_player_create(&cfg, mus_bytes.ptr, mus_bytes.len);
    if (g_player == null) {
        std.log.err("audio: pal_rix_player_create failed (mus.mkf {d} bytes)", .{mus_bytes.len});
        return;
    }
    std.log.info("audio: rix player up; mus.mkf {d} bytes", .{mus_bytes.len});
}

pub fn deinit() void {
    if (g_player) |p| c.pal_rix_player_destroy(p);
    g_player = null;
    g_init_attempted = false;
    g_music = .{};
    g_pending = .{};

    for (&g_voices) |*v| {
        for (&v.resampler) |*r| {
            if (r.*) |ptr| c.resampler_delete(ptr);
            r.* = null;
        }
        v.* = .{};
    }
    g_sfx_head = 0;
    g_sfx_tail = 0;
    g_last_sfx = 0;
}

/// Called from the game thread. Drops a request into the pending slot.
/// Last writer wins — multiple play calls in the same video frame collapse
/// to whichever the libretro thread sees on the next produce(). For PAL the
/// only realistic case is "stopMusic immediately followed by playMusic"
/// (battle entry); we want the playMusic to win, which is what happens if
/// the libretro thread hasn't picked up the stopMusic yet.
pub fn playMusic(num: i32, loop: bool, fade_seconds: f32) void {
    std.log.info("audio: playMusic num={d} loop={} fade={d:.1}s cur={d} active={} fade_state=.{s}", .{
        num,
        loop,
        fade_seconds,
        g_music.num,
        g_music.active,
        @tagName(g_music.fade),
    });
    g_pending = .{
        .set = true,
        .num = num,
        .loop = loop,
        .fade_seconds = fade_seconds,
    };
}

pub fn stopMusic(fade_seconds: f32) void {
    playMusic(0, false, fade_seconds);
}

/// Game-thread API. Drops a request into a small ring; the libretro thread
/// pops it next produce(). Negative numbers are treated as their absolute
/// value (matches SDLPAL convention where flags ride in the sign bit).
pub fn playSound(num: i32) void {
    if (num == 0) return;
    const sfx = if (num < 0) -num else num;
    std.log.info("audio: playSound num={d}", .{sfx});
    const idx = g_sfx_tail % SFX_QUEUE;
    g_sfx_queue[idx] = .{ .num = sfx };
    g_sfx_tail +%= 1;
}

/// Drain the SFX request queue and start matching voices. Runs on the
/// libretro thread inside produce().
fn drainSfxQueue() void {
    while (g_sfx_head != g_sfx_tail) {
        const req = g_sfx_queue[g_sfx_head % SFX_QUEUE];
        g_sfx_head +%= 1;
        if (req.num <= 0) continue;
        startVoice(req.num);
    }
}

fn startVoice(sfx_num: i32) void {
    // Mirror SDLPAL's lastSFX dedupe (sound.c:769).
    if (g_last_sfx == sfx_num) {
        std.log.info("audio: SFX {d} dedup (lastSFX)", .{sfx_num});
        return;
    }

    const voc_buf = global.res_buffers.voc orelse {
        std.log.err("audio: SFX {d} — voc.mkf not loaded", .{sfx_num});
        return;
    };
    const mkf = palcommon.MkfFile.fromMemory(voc_buf);
    const chunk = mkf.getChunkData(@intCast(sfx_num)) catch |err| {
        std.log.err("audio: SFX {d} — getChunkData: {}", .{ sfx_num, err });
        return;
    };
    const parsed = voc_mod.parse(chunk) orelse {
        std.log.err("audio: SFX {d} — VOC parse failed (chunk {d} bytes)", .{ sfx_num, chunk.len });
        return;
    };
    std.log.info("audio: SFX {d} starting (rate={d} samples={d})", .{
        sfx_num,
        parsed.rate,
        parsed.samples.len,
    });

    // Find an idle voice; if none, recycle the oldest by index. SDLPAL keeps
    // an unbounded linked list — at 8 voices we never hit it in practice.
    var slot: usize = 0;
    var found = false;
    for (&g_voices, 0..) |*v, i| {
        if (!v.active) {
            slot = i;
            found = true;
            break;
        }
    }
    if (!found) slot = 0;
    const v = &g_voices[slot];

    // Lazily create resamplers; reuse them across voices (cheap to clear).
    inline for (0..2) |i| {
        if (v.resampler[i] == null) {
            v.resampler[i] = c.resampler_create();
        } else {
            c.resampler_clear(v.resampler[i]);
        }
        const integer_conversion =
            (parsed.rate % SAMPLE_RATE == 0) or (SAMPLE_RATE % parsed.rate == 0);
        c.resampler_set_quality(
            v.resampler[i],
            if (integer_conversion) c.RESAMPLER_QUALITY_MIN else c.RESAMPLER_QUALITY_MAX,
        );
        c.resampler_set_rate(
            v.resampler[i],
            @as(f64, @floatFromInt(parsed.rate)) / @as(f64, @floatFromInt(SAMPLE_RATE)),
        );
    }

    v.cursor = 0;
    v.samples = parsed.samples;
    v.rate = parsed.rate;
    v.active = true;
    g_last_sfx = sfx_num;
}

/// Mix all active voices into the BGM-filled output buffer. Bytes from the
/// VOC are 8-bit unsigned, so subtract 0x80 before scaling. We mix into the
/// stereo BGM frame additively, with SDLPAL's clipping.
fn mixSfx(out: []i16) void {
    for (&g_voices) |*v| {
        if (!v.active) continue;
        mixVoice(v, out);
    }
}

fn mixVoice(v: *Voice, out: []i16) void {
    var written: usize = 0;
    const frames_total = out.len / CHANNELS;

    while (written < frames_total and v.cursor < v.samples.len) {
        // Feed: top up the resampler from the source buffer.
        const free_count: c_int = c.resampler_get_free_count(v.resampler[0]);
        if (free_count > 0) {
            var fed: usize = 0;
            const max_feed: usize = @intCast(free_count);
            while (fed < max_feed and v.cursor < v.samples.len) : (fed += 1) {
                // 8-bit unsigned -> 16-bit signed centred on 0.
                const u: i16 = @as(i16, v.samples[v.cursor]) - 0x80;
                const s: i16 = u << 8; // scale to full s16 range
                c.resampler_write_sample(v.resampler[0], s);
                v.cursor += 1;
            }
        }

        // Drain: pull resampled samples and add them to both channels.
        while (written < frames_total) {
            const avail = c.resampler_get_sample_count(v.resampler[0]);
            if (avail <= 0) break;
            const raw = c.resampler_get_sample(v.resampler[0]) >> 8;
            c.resampler_remove_sample(v.resampler[0]);

            const idx = written * CHANNELS;
            inline for (0..CHANNELS) |ch| {
                const mixed: i32 = @as(i32, out[idx + ch]) + raw;
                const clipped: i16 = @intCast(@max(@min(mixed, 32767), -32768));
                out[idx + ch] = clipped;
            }
            written += 1;
        }

        // If we couldn't feed and couldn't drain anything, the voice is done.
        if (free_count == 0 and v.cursor >= v.samples.len) break;
    }

    // Voice exhausted? Drain any tail in the resampler then mark inactive.
    if (v.cursor >= v.samples.len) {
        while (written < frames_total) {
            const avail = c.resampler_get_sample_count(v.resampler[0]);
            if (avail <= 0) break;
            const raw = c.resampler_get_sample(v.resampler[0]) >> 8;
            c.resampler_remove_sample(v.resampler[0]);
            const idx = written * CHANNELS;
            inline for (0..CHANNELS) |ch| {
                const mixed: i32 = @as(i32, out[idx + ch]) + raw;
                const clipped: i16 = @intCast(@max(@min(mixed, 32767), -32768));
                out[idx + ch] = clipped;
            }
            written += 1;
        }
        v.active = false;
        v.samples = &.{};
        if (g_last_sfx == 0) {} // keep silencing-line below to look like SDLPAL
        // SDLPAL sets player->lastSFX = 0 here to allow the same SFX to retrigger
        // immediately after it ends. Mirror that.
        g_last_sfx = 0;
    }
}

/// Apply a Pending request, on the libretro thread. This is where every
/// pal_rix_player_* mutation happens.
fn applyPending() void {
    if (!g_pending.set) return;
    const req = g_pending;
    g_pending.set = false;

    const player = g_player orelse return;

    const fade_samples: u32 = blk: {
        const f = req.fade_seconds * @as(f32, @floatFromInt(SAMPLE_RATE));
        if (f <= 0.0) break :blk 0;
        break :blk @intFromFloat(f / 2.0); // half for fade-out, half for fade-in
    };

    if (req.num == 0) {
        // Stop request.
        if (!g_music.active) return;
        if (fade_samples == 0) {
            g_music.active = false;
            g_music.fade = .none;
            return;
        }
        g_music.fade = .out;
        g_music.fade_total = fade_samples;
        g_music.fade_remaining = fade_samples;
        g_music.next = -1;
        return;
    }

    if (g_music.active and g_music.num == req.num and g_music.fade != .out) {
        // Same song already playing, just update loop flag.
        g_music.loop = req.loop;
        return;
    }

    if (fade_samples == 0 or !g_music.active) {
        // Hard switch.
        g_music.num = req.num;
        g_music.loop = req.loop;
        g_music.active = true;
        g_music.fade = .none;
        c.pal_rix_player_reset_opl(player);
        c.pal_rix_player_rewind(player, req.num);
        return;
    }

    // Cross-fade: schedule fade-out, then fade-in to req.num.
    g_music.fade = .out;
    g_music.fade_total = fade_samples;
    g_music.fade_remaining = fade_samples;
    g_music.next = req.num;
    g_music.next_loop = req.loop;
    g_music.next_fade_in_total = fade_samples;
}

fn render(out: []i16) void {
    @memset(out, 0);
    const player = g_player orelse return;
    if (!g_music.active) return;

    var off: usize = 0;
    var frames_left: u32 = @intCast(out.len / CHANNELS);

    while (frames_left > 0) {
        // Render in fade-aware chunks. When fade is active, cap each chunk at
        // fade_remaining so applyFadeRamp can finish the transition cleanly.
        var chunk_frames: u32 = frames_left;
        if (g_music.fade != .none and g_music.fade_remaining < chunk_frames) {
            chunk_frames = @max(g_music.fade_remaining, 1);
        }

        const slice_start = off;
        const slice_end = off + chunk_frames * CHANNELS;
        const more = c.pal_rix_player_render(
            player,
            out.ptr + slice_start,
            @intCast(chunk_frames),
        );

        if (g_music.fade != .none) applyFadeRamp(out[slice_start..slice_end]);

        if (more == 0) {
            // Song ended.
            if (g_music.loop) {
                c.pal_rix_player_rewind(player, g_music.num);
            } else if (g_music.fade != .out) {
                // Natural end — stop. Don't fight an already-running fade.
                g_music.active = false;
                return;
            }
        }

        off = slice_end;
        frames_left -= chunk_frames;
    }
}

fn applyFadeRamp(buf: []i16) void {
    const total_f = @as(f32, @floatFromInt(g_music.fade_total));
    const frames = buf.len / CHANNELS;

    var i: usize = 0;
    while (i < frames) : (i += 1) {
        if (g_music.fade_remaining == 0) {
            switch (g_music.fade) {
                .out => {
                    if (g_music.next > 0) {
                        if (g_player) |p| {
                            c.pal_rix_player_reset_opl(p);
                            c.pal_rix_player_rewind(p, g_music.next);
                        }
                        g_music.num = g_music.next;
                        g_music.loop = g_music.next_loop;
                        g_music.next = -1;
                        g_music.fade = .in;
                        g_music.fade_total = @max(g_music.next_fade_in_total, 1);
                        g_music.fade_remaining = g_music.fade_total;
                    } else {
                        g_music.active = false;
                        g_music.fade = .none;
                        @memset(buf[i * CHANNELS ..], 0);
                        return;
                    }
                },
                .in => {
                    g_music.fade = .none;
                    return;
                },
                .none => return,
            }
        }

        const t = @as(f32, @floatFromInt(g_music.fade_remaining)) / total_f;
        const vol: f32 = if (g_music.fade == .out) t else 1.0 - t;

        var ch: usize = 0;
        while (ch < CHANNELS) : (ch += 1) {
            const sample_f: f32 = @as(f32, @floatFromInt(buf[i * CHANNELS + ch])) * vol;
            buf[i * CHANNELS + ch] = @intFromFloat(sample_f);
        }
        g_music.fade_remaining -= 1;
    }
}

/// Convenience for libretro_core.zig: produce one video-frame's worth of
/// audio and hand it to RetroArch's batch callback. Runs on the libretro
/// thread; consumes any Pending command from the game thread first.
pub fn produce(batch_cb: ?*const fn ([*]const i16, usize) callconv(.c) usize) void {
    const cb = batch_cb orelse return;
    if (g_player == null) tryInit();
    applyPending();
    drainSfxQueue();
    var buf: [FRAMES_PER_VIDEO_FRAME * CHANNELS]i16 = undefined;
    if (g_music_enabled) render(&buf) else @memset(&buf, 0);
    if (g_sound_enabled) mixSfx(&buf);
    _ = cb(&buf, FRAMES_PER_VIDEO_FRAME);
}
