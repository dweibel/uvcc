# Holding the C925e at a zoomable format

`hold-camera.sh` keeps the Logitech C925e streaming at 1024x576 so that the pan and zoom preset in `set-camera-defaults.sh` is honored by Teams. See the comments in both scripts for why this is necessary. This page covers launching it without a terminal: from a Desktop icon, and from a keyboard shortcut.

Both paths call `toggle-hold-camera.sh`, which starts the holder in the background the first time and stops it the next time. It posts a notification either way, and writes the holder's output to `$TMPDIR/hold-camera.log`.

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
