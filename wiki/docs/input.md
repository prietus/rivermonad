# Input devices

Keyboard layout, key repeat, touchpad and mouse are set in the
configuration's `input` field, and rivermonad applies them through
river's input protocols to every device, also those plugged in later.
Anything left out keeps the device or system default.

```haskell
  , input = def
      { keyboard = def { kbLayout = "us,es", kbVariant = ",", kbOptions = "grp:alt_shift_toggle,caps:escape"
                       , kbRepeat = Just (40, 250) }
      , touchpad = def { tapToClick = Just True, naturalScroll = Just True, disableWhileTyping = Just True }
      , mouse    = def { accelProfile = Just AccelFlat, accelSpeed = Just 0.3 }
      }
```

## Keyboard

The names are xkb's, as in `/etc/default/keyboard` or sway's `xkb_*`
settings (see `man xkeyboard-config`).

| Field | |
|---|---|
| `kbLayout` | `"us"`; several, comma-separated: `"us,es"` |
| `kbVariant` | per layout, comma-separated: `"altgr-intl"`, `",mac"` |
| `kbOptions` | `"caps:escape,compose:ralt"`, `"grp:alt_shift_toggle"` to switch layouts |
| `kbModel` | rarely needed |
| `kbRepeat` | `Just (keys per second, delay in ms)` |
| `kbNumlock` | `Just True`: Num Lock on when a keyboard appears |

`nextKeyboardLayout` switches to the next layout from a key binding; the
active layout is published on the [IPC socket](ipc.md) as
`keyboard_layout`, so a bar can show it, and `"NextKeyboardLayout"` switches
from a script.

## Touchpad and mouse

`touchpad` applies to devices that support tap to click, `mouse` to the
other pointers. Both take the same fields:

| Field | |
|---|---|
| `tapToClick` | |
| `naturalScroll` | content follows the fingers, like a phone |
| `disableWhileTyping` | |
| `leftHanded` | swap the buttons |
| `middleEmulation` | left and right together is a middle click |
| `accelProfile` | `AccelFlat` (no acceleration, for games) or `AccelAdaptive` |
| `accelSpeed` | from -1 (slowest) to 1 (fastest); 0 is the device's default |

## Cursor

```haskell
  , xcursorTheme = Just ("Adwaita", 24)
```
