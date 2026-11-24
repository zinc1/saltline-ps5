# Technical notes — native 3D Godot on PS5

These notes record what was measured while bringing up the port. They are
deliberately free of machine- or account-specific identifiers.

## 1. The stock PS5 Godot port is 2D-only by build choice

The community port builds a "smoke" module set whose SCons flags include
`disable_3d=yes`. This is a link-scope decision (the first milestone did not
want to pull Embree/Jolt/3D importers into the link), not evidence that the GLES3
renderer cannot draw 3D. The project's milestone list marks 3D as unclaimed.

The renderer is upstream Godot's **GLES3** path running on Mesa 4.6 through the
PS5 AGC/EGL display server, and the display server presents the final
framebuffer. Turning the scene layer back on is therefore a build-flag change,
not a new renderer.

## 2. 3D module set

`tools/patch_engine_3d.py` adds a `smoke3d` case to the engine build script:

```
module_gdscript_enabled=yes
module_text_server_fb_enabled=yes
module_freetype_enabled=yes
builtin_freetype=yes
module_godot_physics_3d_enabled=yes
disable_physics_3d=no
module_navigation_3d_enabled=yes
disable_3d=no
disable_xr=yes
disable_advanced_gui=no
```

built with `opengl3=yes` and the native GLES3 display server
(`GODOT_PS5_NATIVE_GLES3=1`, `GODOT_PS5_GLES3_ARCHIVES=1`).
The resulting archives contain the expected `Node3D` / `MeshInstance3D` /
`Camera3D` symbols.

## 3. Rendering pitfalls on the PS5 GL stack

* **MSAA is resolved in software.** With `msaa_3d=1` the log shows
  `[ps5-gallium] msaa4-resolve color=1920x1080` and a matching
  `software-blit`, and the frame costs ~560 ms of CPU. Frame rate collapses to
  ~7.5 fps. Set `anti_aliasing/quality/msaa_3d=0`.
* **Scaling costs more than it saves.** Rendering the 3D viewport at 1600×900
  and presenting at 1080p (`stretch/mode="viewport"`) was *slower* than native
  1080p, because the presentation path scales in software. Native 1080p won.
* **Directional shadows cost about 5 fps** (2048² map). They are off by default;
  the pause menu can enable them.
* **Draw-call batching helps more than resolution tricks.** Containers and lit
  windows are `MultiMeshInstance3D` batches (one draw per colour / one for all
  windows); the same scene with individual `MeshInstance3D` nodes is noticeably
  slower.
* Glow/post-processing was disabled for the same reason (extra full-screen
  passes on a stack whose presentation is already partly software).

Measured on hardware (1080p, shadows off, batched level): ~58–59 fps,
`M13_FRAME_5S avg_cpu_ms ≈ 16.6` in steady state.

## 4. Native link and SELF conversion

The engine is linked by the PS5-DevBridge template into a signed `eboot.bin`.
macOS needs a few compatibility steps, all automated by
`tools/build_engine_3d.sh` and `tools/build_app_3d.sh`:

* a local bash 5 (the DevBridge scripts use `mapfile` / associative arrays,
  macOS ships bash 3.2);
* shims for `sha256sum`, `wget`, `realpath`, `ln`, `nproc`;
* **host zlib** for the packaging tools (the PS5-target zlib used by the app is
  a different ABI);
* the runtime **`libc.prx`** from the official engine release, verified against
  its SHA-256 manifest;
* a **weak-TLS fallback**: the SELF converter refuses undefined weak C++ TLS-init
  hooks such as `_ZTHN…`; those exact symbols are bound to null with
  `--defsym` before conversion (callers already test the address);
* Python 3.11+ for `hashlib.file_digest` in the archive packager.

## 5. ShadowMount packaging and title IDs

Directory layout of an installable folder:

```
<TITLE_ID>/
  eboot.bin            signed SELF
  sce_module/libc.prx  runtime shim
  sce_sys/param.json   titleId, contentId, localized title
  sce_sys/icon0.png
  assets/godot/smoke.pck
```

The engine's PCK search order is: `/data/GodotPS5/launch.txt`, then
`/data/GodotPS5/games`, `/mnt/usb0/godot`, …, then the bundled
`/app0/assets/godot/smoke.pck`. Shipping a `smoke.pck` inside the folder keeps
the package usable without `/data` configuration; during development it is
convenient to also copy the PCK to `/data/GodotPS5/games/` and point
`launch.txt` at it.

Deleting an installed folder leaves a `deleted:true` content flag in the system
database. ShadowMount then reports `[REG] Skip (already present in app.db)` and
the title cannot be registered or launched. The safe fix is a **fresh title ID**
(`PPSA` + five digits); editing `app.db` while the database is in use can
trigger a rebuild of the system databases.

## 6. Launching a mount title from a payload

`sceLncUtilLaunchApp(title_id, argv, NULL)` is rejected for these mount titles
(`0x80940005`). A 1024-byte parameter block works:

```c
char param[1024] = {0};
*(uint32_t *)(param + 0x00) = sizeof(param);   // structure size
*(int32_t  *)(param + 0x04) = foreground_user; // sceUserServiceGetForegroundUser()
*(uint32_t *)(param + 0x08) = 0;               // app options
*(uint64_t *)(param + 0x10) = 0;               // crash report
*(uint64_t *)(param + 0x18) = 0;               // check flag
sceLncUtilLaunchApp(title_id, NULL, param);
```

The call returns the app id and the title starts asynchronously; poll for the
`eboot.bin` process instead of trusting a negative return code.
`tools/launch_3d.sh` implements this.

## 7. DualSense output has to come from the title

A payload process does not own a UI/pad session:

* `scePadOpen` fails (`0x80920001` / `0x809b0001` depending on the user id),
* `scePadGetHandle` fails with `0x80920008`,
* `scePadInit` returns success but no handle becomes available.

Borrowing another process's pad session over `ptrace` is possible in principle,
but a daemon that dies while attached can leave a system process stopped — in
testing that left `SceShellCore` as a zombie and the console needed a reboot.
The final design avoids system processes entirely:

* the engine's pad driver opens the pad **inside the title**, which is the
  legitimate owner,
* it selects **classic two-motor mode** with
  `scePadSetVibrationMode(handle, 2)` (in the default audio-haptics mode the two
  motor bytes do nothing),
* it reads a small state file from `user://` and forwards it with
  `scePadSetVibration` and `scePadSetTriggerEffect`.

### Trigger effect ABI

`ScePadTriggerEffectParam` is 120 bytes:

```c
struct TrigCmd { int32_t mode; uint8_t pad[4]; uint8_t data[48]; };
struct TrigParam { uint8_t mask; uint8_t pad[7]; TrigCmd cmd[2]; }; /* L2, R2 */
```

Modes used by the game: `0` off, `1` feedback(position, strength),
`2` weapon(start, end, strength), `3` vibration(position, amplitude, frequency),
`5` slope(start, end, startStrength, endStrength), positions 0–9,
strengths 1–8.

### State-file race

The driver polls the file at roughly 30 Hz. Opening it for truncation while the
reader has it open intermittently fails with `EBUSY` on the console filesystem.
The game writes `user://pad_state.tmp` and renames it over `user://pad_state`;
the driver only ever opens the final path read-only. A write failure must not
disable the bridge permanently — retry on the next tick.

## 8. Quality options exposed in-game

Pause menu:

* **Shadows ON/OFF** — directional shadow map, about 5 fps.
* **Haptics ON/OFF** — silences rumble and clears trigger effects.
* **Controller test** — strong/weak rumble pattern plus 2.4 s of trigger slope
  resistance, useful when validating a new build on a fresh controller.

## 9. References

* Godot 4.7.2 — <https://github.com/godotengine/godot>
* PS5 Godot port / platform overlay — <https://github.com/Yahballon/PS5_Godot>
* PS5-DevBridge native-link template — <https://github.com/Yahballon/PS5-DevBridge>
* ps5-opengl SDK — <https://github.com/mihawk-99/ps5-opengl>
* ps5-payload-sdk / elfldr — <https://github.com/ps5-payload-dev>
* DualSense trigger effect layouts as used by shipping ports:
  <https://github.com/holdmysocks/mcla-recomp> (`ps5/game/ps5_triggers.h`)
