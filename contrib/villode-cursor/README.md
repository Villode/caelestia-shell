# Villode cursor shake-to-find

Mac-style pointer magnification for Hyprland. Enlarges the **pointer sprite**
(not the desktop). Uses a click-through SVG overlay with springy easing.

## Install (user)

```bash
install -Dm755 villode-cursor-shake ~/.local/bin/villode-cursor-shake
install -Dm644 shake.conf ~/.config/villode-cursor/shake.conf
install -Dm644 assets/left_ptr.svg ~/.local/share/villode-cursor/left_ptr.svg
# Hyprland: source cursor.conf from your session config
install -Dm644 cursor.conf ~/.config/villode-hyprland/cursor.conf
```

Then `source = ~/.config/villode-hyprland/cursor.conf` and restart the daemon:

```bash
villode-cursor-shake &
```

`Super+Shift+C` pulses the pointer. Shake vigorously left-right to magnify.
