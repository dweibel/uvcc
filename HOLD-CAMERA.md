# Holding the C925e at a zoomable format

`hold-camera.sh` keeps the Logitech C925e streaming at 1024x576 so that the pan and zoom preset in `set-camera-defaults.sh` is honored by Teams. See the comments in both scripts for why this is necessary. This page covers launching it without a terminal: from a Desktop icon, and from a keyboard shortcut.

Both paths call `toggle-hold-camera.sh`, which starts the holder in the background the first time and stops it the next time. It posts a notification either way, and writes the holder's output to `$TMPDIR/hold-camera.log`.

## What `hold-camera.sh` does

It is the front door to the camera hold: one foreground script that owns the whole arrangement for as long as it runs, so that stopping it puts the camera back exactly as it was.

In order, it:

1. Builds `camhold` from `camhold.swift` if the binary is missing or older than the source, using `swiftc -O`. The binary is gitignored, so a fresh clone compiles on first run.
2. Starts `camhold` in the background, passing the format and the two timing flags described under [Tuning the glitch](#tuning-the-glitch). That process opens the camera and keeps it open, which is what pins the shared stream format low enough for the crop to apply.
3. Installs an `EXIT INT TERM` trap that kills the holder, so Ctrl-C or a `kill` releases the camera rather than orphaning a process that holds it open indefinitely.
4. Waits two seconds for the format to take, then runs `set-camera-defaults.sh` to apply the pan/tilt/zoom preset over USB via `uvcc` itself.
5. Blocks on the holder. The script running _is_ the camera being held; there is no daemon and no state beyond the process.

Three environment variables tune it, all read at startup: `CAMHOLD_SIZE` (default `1024x576`), `CAMHOLD_SETTLE` (`0.05`), and `CAMHOLD_RETRY` (`0.2`).

The division of labor is worth keeping straight, because the two halves fail differently. `camhold` is Swift and talks to **AVFoundation**: it controls the _stream format_, which is macOS-wide shared state. `set-camera-defaults.sh` shells out to **uvcc** and talks **USB UVC**: it controls _camera registers_ — pan, tilt, zoom. The preset alone does nothing visible, because the camera ignores its own crop at high formats; the hold alone changes nothing, because no preset has been applied. Both are required, in that order.

## One-time preparation

1. Build the holder once so the first launch does not have to compile it:

   ```bash
   cd ~/Workspace/uvcc && ./hold-camera.sh
   ```

   Wait for `Holding the camera at 1024x576`, then press Ctrl-C.

2. Check that the toggle works from a terminal:

   ```bash
   ~/Workspace/uvcc/toggle-hold-camera.sh   # starts, notification "Holding the camera"
   ~/Workspace/uvcc/toggle-hold-camera.sh   # stops, notification "Camera released"
   ```

## Desktop icon

A `.command` file is a shell script that Finder opens in Terminal when double-clicked.

1. Create the file:

   ```bash
   cat > ~/Desktop/Hold\ Camera.command <<'EOS'
   #!/usr/bin/env bash
   exec ~/Workspace/uvcc/toggle-hold-camera.sh
   EOS
   chmod +x ~/Desktop/Hold\ Camera.command
   ```

2. Double-click **Hold Camera** on the Desktop. A Terminal window opens, the notification appears, and the window can be closed. Double-click again to release the camera.

3. The first time, macOS asks whether Terminal may use the camera. Allow it. If the prompt never appears and the log says `camera access denied`, add Terminal under System Settings, Privacy & Security, Camera.

If you already have a Script Editor or Automator applet on the Desktop that runs `hold-camera.sh` directly, point it at `toggle-hold-camera.sh` instead. An applet that runs `hold-camera.sh` has no terminal to press Ctrl-C in, so the only way to release the camera is to kill the process; with the toggle, opening the applet a second time releases it.

To stop Terminal leaving a window behind each time, open Terminal Settings, Profiles, Shell, and set "When the shell exits" to "Close if the shell exited cleanly".

## Keyboard shortcut

Use the Shortcuts app. It can run a shell script and bind it to a global key combination.

1. Open **Shortcuts**, then Shortcuts Settings, Advanced, and turn on **Allow Running Scripts**.

2. Create a new shortcut with File, New Shortcut. Search the action list for **Run Shell Script** and add it.

3. In the action, set Shell to `bash`, set Input to `Nothing`, and replace the script body with:

   ```bash
   ~/Workspace/uvcc/toggle-hold-camera.sh
   ```

4. Name the shortcut **Hold Camera** by clicking the title at the top.

5. Open the details panel with the ⓘ button in the toolbar and click **Add Keyboard Shortcut**. Press the combination to use, for example Control-Option-Command-C. Pick one that Teams does not already use.

6. Optionally enable **Pin in Menu Bar** in the same panel, which gives a menu bar entry as a second way to trigger it.

7. Press the shortcut once. macOS asks whether Shortcuts may use the camera the first time. Allow it. Press it again to release the camera.

The shortcut is global, so it works while Teams is in the foreground. Press it when a call starts and again when it ends.

## Checking state

The holder is running when this prints a process:

```bash
pgrep -fl camhold
```

The log of the current or last run:

```bash
cat "$TMPDIR/hold-camera.log"
```

If the toggle ever loses track of the holder, for example after the machine sleeps, stop it by hand:

```bash
pkill -TERM -f uvcc/camhold
```

## Changing the format

The holder defaults to 1024x576, the largest format at which the camera applies the 2x preset. To use a different one, set `CAMHOLD_SIZE` before launching, for example `CAMHOLD_SIZE=640x360`. Both the Desktop file and the Shortcut can carry it on the same line as the command:

```bash
CAMHOLD_SIZE=640x360 ~/Workspace/uvcc/toggle-hold-camera.sh
```

## Tuning the glitch

When Teams takes the shared format up to 1280x720, the crop stops applying and the picture pans out to the full wide view until the holder takes the format back. That round trip is visible to everyone in the call, so the holder reacts as soon as the change is confirmed rather than waiting out a fixed delay.

Two settings control it, and both are seconds:

| Variable         | Default | What it does                                                                                                                                                                             |
| ---------------- | ------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `CAMHOLD_SETTLE` | `0.05`  | How long an off-size stream is tolerated before the format is taken back. This is the visible length of the glitch. Two frames at 30 fps, enough not to chase a single anomalous buffer. |
| `CAMHOLD_RETRY`  | `0.2`   | Spacing before a second attempt, doubling up to two seconds for as long as the format keeps coming back wrong.                                                                           |

Lowering `CAMHOLD_SETTLE` further shortens the glitch but risks reacting to a single stray frame during a legitimate format change. Raising it makes the holder calmer and the pan-out longer:

```bash
CAMHOLD_SETTLE=0.1 ~/Workspace/uvcc/toggle-hold-camera.sh
```

The backoff matters when another client refuses to give up the format. Without it the two would fight frame by frame and the picture would strobe; with it the attempts space out and the picture settles on the wrong size instead, which is worth knowing if it ever looks like the holder has stopped working. `camhold: re-asserted 1024x576` in the log each time, with no `back to 1024x576` line following, is that case.

The log reports how long each glitch actually lasted:

```text
camhold: stream format changed to 1280x720
camhold: re-asserted 1024x576
camhold: back to 1024x576 after 94 ms
```

## Maintenance notes

### The pan-out glitch, and why the fix is shaped this way

**The problem.** Teams does not accept the held format quietly. Partway into a call it sets the shared format up to 1280x720, where the C925e stops applying its crop, and the picture jumps from the 2x preset to the full wide view until `camhold` takes the format back. Everyone in the call sees it. Before 2026-10-02 that round trip lasted nearly a second.

**Where the time went.** Detection was never the problem. The watcher inspects every decoded frame, so it sees the wrong size on the next buffer — about 33 ms at 30 fps. The delay was a single deliberate constant in `camhold.swift`:

```swift
if now.timeIntervalSince(driftSince!) >= 1.0 {
```

One second of _tolerated_ drift before writing the format back. The glitch was not the camera being slow; it was the holder waiting.

**Why it could not simply be lowered.** That constant was doing two unrelated jobs at once. It set how fast the holder reacts, and it also rate-limited how often `activeFormat` could be written. The second job matters: without a floor, a client that re-takes the format every time it is taken away turns into a frame-by-frame fight, and the picture strobes between two sizes — worse than the glitch being fixed. Typing `0.2` over the `1.0` would have shortened the glitch and removed the strobe protection in the same edit.

**The solution** was to split the two jobs into separate flags, so each can be set to what it is actually for:

| Flag       | Env              | Default | Job                                                                                            |
| ---------- | ---------------- | ------- | ---------------------------------------------------------------------------------------------- |
| `--settle` | `CAMHOLD_SETTLE` | `0.05`  | How long drift is tolerated before the **first** correction. This alone is the visible glitch. |
| `--retry`  | `CAMHOLD_RETRY`  | `0.2`   | Spacing before a **second and later** attempt, doubling to a 2 s ceiling.                      |

The first correction now fires after about two frames instead of thirty. The backoff applies only when the first correction did not stick, which is exactly the case it was protecting against — and because it doubles, a client that keeps fighting is answered less and less often rather than more. Strobe protection is stronger than it was under the flat 1 s, not weaker.

Expect roughly 50 ms plus the camera's own format-switch time. `camhold` logs the measured duration (`back to 1024x576 after 94 ms`) so this is checkable rather than a matter of impression.

### Things that will bite the next person

- **The binary is gitignored and was previously only built when missing.** `hold-camera.sh` now rebuilds when `camhold.swift` is newer, because the old check silently ran a stale binary after any source edit — the change appears to do nothing, and the log still looks healthy. If you ever bypass the script and run `./camhold` directly, rebuild by hand.
- **Rebuilding `camhold` resets its macOS camera permission.** TCC grants access to a specific binary hash, so a fresh build is a new subject and the first run prompts again, or is killed outright if the prompt is suppressed. Expect to re-allow after a rebuild; this is also why a permission failure right after an edit is not evidence that the edit broke something.
- **The 2 s wait before applying the preset is load-bearing.** `set-camera-defaults.sh` must run after the low format is in effect, because pan has no room to move until the crop exists. The same reasoning puts zoom before pan inside that script, with its own 0.5 s gap.
- **`camhold` reacting but never succeeding looks like it has stopped working.** Repeated `re-asserted` lines with no `back to …` line following means another client is winning the format war and the backoff has stretched toward its ceiling. The holder is working; it is being overruled.
- **No automated test covers any of this.** `npm test` is lint only and does not touch Swift. Verification is a real call with a real camera, watching the log.
