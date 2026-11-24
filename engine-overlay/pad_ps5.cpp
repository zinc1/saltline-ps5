// SPDX-License-Identifier: MIT
// Native DualSense to original Godot 4 Input bridge (experimental).
#include "pad_ps5.h"
#include "core/input/input.h"
#include "core/os/os.h"
#include <cstdio>
#include <cstring>
#include <cstdint>
#include <cerrno>
#include <ctime>
#include <fcntl.h>
#include <unistd.h>

extern "C" {
int sceUserServiceInitialize(const void *);
int sceUserServiceGetInitialUser(int *);
int sceUserServiceTerminate();
int scePadInit();
int scePadOpen(int user, int type, int index, const void *);
int scePadRead(int handle, ps5_pad::RawReport *, int);
int scePadClose(int handle);
int scePadSetVibrationMode(int handle, int mode);
int scePadSetVibration(int handle, const void *param);
int scePadSetTriggerEffect(int handle, const void *param);
}


// ---------------------------------------------------------------------------
// Saltline haptics bridge.
//
// The game (GDScript, `Pad` autoload) writes a tiny state file; this driver
// reads it a few times per frame and drives the DualSense.  Doing it here means
// the pad handle is the title's own valid handle: no payload daemon, no
// ptrace, no borrowing SceShellCore.  The classic two-motor path needs
// scePadSetVibrationMode(handle, 2) once after open.
//
// File: /data/Saltline/pad_state
//   seq vibLarge vibSmall l2Mode a b c d r2Mode a b c d
// Trigger modes: 0 off, 1 feedback(pos,str), 2 weapon(start,end,str),
//                3 vibration(pos,amp,freq), 5 slope(start,end,strStart,strEnd)
// ---------------------------------------------------------------------------
namespace {

struct TrigCmd {
    int32_t mode;
    uint8_t padding[4];
    uint8_t data[48];
};
struct TrigParam {
    uint8_t mask;
    uint8_t padding[7];
    TrigCmd cmd[2];
};
static_assert(sizeof(TrigCmd) == 56, "ScePad trigger command ABI");
static_assert(sizeof(TrigParam) == 120, "ScePadTriggerEffectParam ABI");

struct HapticRequest {
    long seq = -1;
    int vib_large = 0;
    int vib_small = 0;
    int l2_mode = 0;
    int l2[4] = {0, 0, 0, 0};
    int r2_mode = 0;
    int r2[4] = {0, 0, 0, 0};
};

HapticRequest g_want;
HapticRequest g_done;
int g_tick = 0;
long g_last_change_ms = 0;
long g_last_mode_ms = 0;
bool g_mode_ok = false;
char g_last_line[160] = {0};

long now_ms() {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1000L + ts.tv_nsec / 1000000L;
}

void build_cmd(TrigCmd &c, int mode, const int p[4]) {
    std::memset(&c, 0, sizeof(c));
    c.mode = mode;
    switch (mode) {
        case 1:
            c.data[0] = static_cast<uint8_t>(p[0] < 0 ? 0 : p[0] > 9 ? 9 : p[0]);
            c.data[1] = static_cast<uint8_t>(p[1] < 1 ? 1 : p[1] > 8 ? 8 : p[1]);
            break;
        case 2:
            c.data[0] = static_cast<uint8_t>(p[0] < 0 ? 0 : p[0] > 9 ? 9 : p[0]);
            c.data[1] = static_cast<uint8_t>(p[1] < 0 ? 0 : p[1] > 9 ? 9 : p[1]);
            c.data[2] = static_cast<uint8_t>(p[2] < 1 ? 1 : p[2] > 8 ? 8 : p[2]);
            break;
        case 3:
            c.data[0] = static_cast<uint8_t>(p[0] < 0 ? 0 : p[0] > 9 ? 9 : p[0]);
            c.data[1] = static_cast<uint8_t>(p[1] < 1 ? 1 : p[1] > 8 ? 8 : p[1]);
            c.data[2] = static_cast<uint8_t>(p[2] < 1 ? 1 : p[2] > 255 ? 255 : p[2]);
            break;
        case 5:
            c.data[0] = static_cast<uint8_t>(p[0] < 0 ? 0 : p[0] > 9 ? 9 : p[0]);
            c.data[1] = static_cast<uint8_t>(p[1] < 0 ? 0 : p[1] > 9 ? 9 : p[1]);
            c.data[2] = static_cast<uint8_t>(p[2] < 1 ? 1 : p[2] > 8 ? 8 : p[2]);
            c.data[3] = static_cast<uint8_t>(p[3] < 1 ? 1 : p[3] > 8 ? 8 : p[3]);
            break;
        default:
            c.mode = 0;
            break;
    }
}

bool read_request(HapticRequest &out) {
    static CharString state_path;
    if (state_path.is_empty()) {
        const String dir = OS::get_singleton()->get_user_data_dir();
        state_path = (dir + "/pad_state").utf8();
    }
    int fd = open(state_path.get_data(), O_RDONLY);
    if (fd < 0) fd = open("/data/Saltline/pad_state", O_RDONLY);
    if (fd < 0) return false;
    char buf[256];
    const ssize_t n = read(fd, buf, sizeof(buf) - 1);
    close(fd);
    if (n <= 0) return false;
    buf[n] = 0;
    long seq;
    int vl, vs, lm, a, b, c, d, rm, e, f, g, h;
    const int got = std::sscanf(buf, "%ld %d %d %d %d %d %d %d %d %d %d %d %d",
                                &seq, &vl, &vs, &lm, &a, &b, &c, &d,
                                &rm, &e, &f, &g, &h);
    if (got != 13) return false;
    if (seq == out.seq) return false;
    out.seq = seq;
    out.vib_large = vl;
    out.vib_small = vs;
    out.l2_mode = lm;
    out.l2[0] = a; out.l2[1] = b; out.l2[2] = c; out.l2[3] = d;
    out.r2_mode = rm;
    out.r2[0] = e; out.r2[1] = f; out.r2[2] = g; out.r2[3] = h;
    return true;
}

bool triggers_differ(const HapticRequest &a, const HapticRequest &b) {
    return a.l2_mode != b.l2_mode || a.r2_mode != b.r2_mode ||
           std::memcmp(a.l2, b.l2, sizeof(a.l2)) != 0 ||
           std::memcmp(a.r2, b.r2, sizeof(a.r2)) != 0;
}

void apply_vibration(int handle, int large, int small) {
    const uint8_t v[2] = {
        static_cast<uint8_t>(large < 0 ? 0 : large > 255 ? 255 : large),
        static_cast<uint8_t>(small < 0 ? 0 : small > 255 ? 255 : small)};
    scePadSetVibration(handle, v);
}

void apply_triggers(int handle, const HapticRequest &r) {
    TrigParam p{};
    if (r.l2_mode) p.mask |= 0x01;
    if (r.r2_mode) p.mask |= 0x02;
    build_cmd(p.cmd[0], r.l2_mode, r.l2);
    build_cmd(p.cmd[1], r.r2_mode, r.r2);
    scePadSetTriggerEffect(handle, &p);
}

} // namespace

namespace ps5_pad {
void Bridge::initialize() {
    // Godot constructs its Input singleton before calling initialize_joypads.
    if (!Input::get_singleton()) return;
    const int user_init = sceUserServiceInitialize(nullptr);
    user_service_owned = user_init == 0;
    if (user_init != 0 && static_cast<uint32_t>(user_init) != 0x80960003u)
        std::fprintf(stderr, "[GodotPS5 PAD] USER_INIT status=0x%08x\n", unsigned(user_init));
    int rc = sceUserServiceGetInitialUser(&initial_user);
    if (rc != 0) {
        std::fprintf(stderr, "[GodotPS5 PAD] NO_USER status=0x%08x\n", unsigned(rc));
        initial_user = -1;
        return;
    }
    const int pad_init = scePadInit();
    std::fprintf(stderr, "[GodotPS5 PAD] SDK_INIT status=0x%08x user=%d\n",
                 unsigned(pad_init), initial_user);
    std::fflush(stderr);
    retry_ticks = 0;
}

void Bridge::poll() {
    Input *const input = Input::get_singleton();
    if (!input) return;
    if (handle < 0) {
        if (initial_user < 0) return;
        if (retry_ticks-- > 0) return;
        retry_ticks = 120; // Retry once in roughly two seconds at 60 fps.
        handle = scePadOpen(initial_user, 0, 0, nullptr);
        if (handle < 0) return;
        std::fprintf(stderr, "[GodotPS5 PAD] PAD_OPEN handle=%d\n", handle);
        // Classic two-motor emulation: without mode 2 the DualSense stays in
        // audio-haptics mode and the two vibration bytes do nothing.
        const int vmode = scePadSetVibrationMode(handle, 2);
        g_mode_ok = vmode == 0;
        std::fprintf(stderr, "[GodotPS5 PAD] VIB_MODE status=0x%08x\n", unsigned(vmode));
        std::fflush(stderr);
        connected = false;
        last_buttons = 0;
        g_want.seq = -1;
        g_done.seq = -1;
        std::memset(last_axes, 0, sizeof(last_axes));
    }

    RawReport samples[32]{};
    const int count = scePadRead(handle, samples, 32);
    if (count < 0) {
        if (connected) {
            input->joy_connection_changed(0, false, "DualSense");
            connected = false;
        }
        scePadClose(handle);
        handle = -1;
        retry_ticks = 120;
        std::fprintf(stderr, "[GodotPS5 PAD] PAD_READ_FAILED status=0x%08x\n", unsigned(count));
        return;
    }
    if (count > 32) return;

    // --- Saltline haptics bridge: 1 read every other poll (~30 Hz) ----------
    if ((g_tick++ & 1) == 0 && g_mode_ok) {
        if (read_request(g_want)) {
            g_last_change_ms = now_ms();
            const bool vib_diff = g_want.vib_large != g_done.vib_large ||
                                  g_want.vib_small != g_done.vib_small;
            const bool trig_diff = triggers_differ(g_want, g_done);
            if (vib_diff) {
                apply_vibration(handle, g_want.vib_large, g_want.vib_small);
                g_done.vib_large = g_want.vib_large;
                g_done.vib_small = g_want.vib_small;
            }
            if (trig_diff && now_ms() - g_last_mode_ms >= 50) {
                apply_triggers(handle, g_want);
                g_done.l2_mode = g_want.l2_mode;
                g_done.r2_mode = g_want.r2_mode;
                std::memcpy(g_done.l2, g_want.l2, sizeof(g_done.l2));
                std::memcpy(g_done.r2, g_want.r2, sizeof(g_done.r2));
                g_last_mode_ms = now_ms();
                std::fprintf(stderr, "[GodotPS5 PAD] HAPTICS seq=%ld vib=%d/%d l2=%d r2=%d\n",
                             g_want.seq, g_want.vib_large, g_want.vib_small,
                             g_want.l2_mode, g_want.r2_mode);
                std::fflush(stderr);
            }
        } else if (g_done.vib_large || g_done.vib_small) {
            // The game stopped refreshing (crash/menu): do not leave the pad
            // buzzing. 1.5 s of silence clears both motors and the triggers.
            if (now_ms() - g_last_change_ms > 1500) {
                apply_vibration(handle, 0, 0);
                g_done.vib_large = 0;
                g_done.vib_small = 0;
                HapticRequest off;
                apply_triggers(handle, off);
                g_done.l2_mode = 0;
                g_done.r2_mode = 0;
                std::memcpy(g_done.l2, off.l2, sizeof(off.l2));
                std::memcpy(g_done.r2, off.r2, sizeof(off.r2));
            }
        }
    }
    for (int i = 0; i < count; ++i) {
        const RawReport &raw = samples[i];
        if (raw.connected == 0 || (raw.buttons & 0x80000000u)) {
            if (connected) {
                input->joy_connection_changed(0, false, "DualSense");
                connected = false;
                last_buttons = 0;
                std::fprintf(stderr, "[GodotPS5 PAD] DISCONNECTED_OR_INTERCEPTED\n");
            }
            continue;
        }
        if (!connected) {
            Dictionary info;
            info["mapping_handled"] = true;
            input->joy_connection_changed(0, true, "DualSense PS5", "ps5-dualsense", info);
            connected = true;
            last_buttons = 0;
            std::memset(last_axes, 0, sizeof(last_axes));
            std::fprintf(stderr, "[GodotPS5 PAD] CONNECTED dev=0\n");
        }
        for (const Mapping &map : kButtons) {
            const uint32_t changed = last_buttons ^ raw.buttons;
            if (changed & map.native_bit) {
                const bool down = (raw.buttons & map.native_bit) != 0;
                input->joy_button(0, static_cast<JoyButton>(map.godot_button), down);
                if (map.godot_button == 0) {
                    std::fprintf(stderr, "[GodotPS5 PAD] CROSS_%s\n", down ? "DOWN" : "UP");
                    std::fflush(stderr);
                }
            }
        }
        last_buttons = raw.buttons;
        const float axes[6] = {
            axis(raw.lx), axis(raw.ly), axis(raw.rx), axis(raw.ry),
            trigger(raw.l2), trigger(raw.r2)
        };
        for (int a = 0; a < 6; ++a) {
            if (axes[a] != last_axes[a]) {
                last_axes[a] = axes[a];
                input->joy_axis(0, static_cast<JoyAxis>(a), axes[a]);
            }
        }
    }
}

void Bridge::shutdown() {
    if (connected && Input::get_singleton()) {
        Input::get_singleton()->joy_connection_changed(0, false, "DualSense");
    }
    connected = false;
    if (handle >= 0) {
        apply_vibration(handle, 0, 0);
        HapticRequest off;
        apply_triggers(handle, off);
        scePadClose(handle);
        handle = -1;
    }
    if (user_service_owned) sceUserServiceTerminate();
    user_service_owned = false;
}
} // namespace ps5_pad
