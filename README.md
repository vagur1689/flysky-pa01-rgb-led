# FlySky ProArt PA01 RGB LED Control

[Download scripts](https://github.com/vagur1689/flysky-pa01-rgb-led/archive/refs/heads/main.zip) · [中文说明](README.zh-CN.md)

Custom RGB lighting effects and an on-radio **RGB color wheel + slider configurator** for the **FlySky ProArt PA01** (`320×240` screen, EdgeTX 2.11+). Controls both the **power button RGB LEDs** and the **left/right side LED strips** with automatic **Disarmed (Locked) / Armed (Unlocked)** state switching.

## Features

| Target | Disarmed (`SA` up) | Armed (`SA` down) | Controls in Tools UI |
| --- | --- | --- | --- |
| **Power button LED** (2 RGB LEDs) | Solid / Breathing / State-linked / System default | Solid / Breathing / State-linked / System default | 25-color RGB wheel, brightness slider (`0–100%`), 4 modes |
| **Left & right side strips** (2 RGB LEDs per side) | Solid color (selectable on RGB wheel + brightness slider) | Independent Left & Right colors on RGB wheel + 5 effects | 25-color RGB wheel, brightness slider (`0–100%`), speed slider (`1–10`), L/R swap |

### Armed (Unlocked) effect modes

1. **Fixed Dual-Color (`固定双色`)** — Left strip stays on Left Color, right strip stays on Right Color.
2. **Sync Breath (`同步渐变`)** — Left and right strips breathe in sync with their respective colors.
3. **Alternating Breath (`反向渐变`)** — Left and right strips breathe `180°` out of phase.
4. **Dual-Color Cycle (`双色循环`)** — Smooth wave cycling back and forth between Left Color and Right Color across the 4 strip LEDs.
5. **Full Spectrum Cycle (`全色循环`)** — Continuous `360°` HSV rainbow flow across the left and right strips.

## Installation

1. Copy the two Lua files to your PA01 SD card:
   - `/SCRIPTS/TOOLS/pa01led.lua` — visual RGB color wheel & slider configurator (`320×240`).
   - `/SCRIPTS/RGBLED/pa01led.lua` — background RGB LED effect engine.
2. Enable the background script on the radio:
   - Long-press **SYS** → page to **Global Functions** (`全局功能`).
   - Edit the `RGB leds` (`RGB LED 灯`) entry (originally `FS_brth`), change the script to **`pa01led`**, and keep the switch **`ON`**.
3. Open the visual configurator:
   - Short-press **SYS** → **Tools** (`工具`) → select **`pa01led`**.
   - Use the **scroll wheel** to move between items, **press the wheel** to edit (the active slider knob or RGB color wheel border turns yellow), and **press again** to confirm.
   - Press **RTN (Exit)** or click **`[保存设置]`** at the bottom to save `/SCRIPTS/RGBLED/pa01led.cfg` to the SD card. Changes take effect immediately in real time without rebooting.

## Local Verification

~~~sh
luac -p SCRIPTS/RGBLED/pa01led.lua
luac -p SCRIPTS/TOOLS/pa01led.lua
lua tests/run.lua
~~~

## License & Terms of Use

Licensed under **[CC BY-NC-SA 4.0](LICENSE)** (Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International).

- **Non-Commercial Only**: Strictly for personal, hobbyist, and non-commercial use. Selling these scripts standalone or in bundles (on marketplaces, paid cloud drives, paid tuning/installation services, or pre-installed on commercial SD cards/radios) is **strictly prohibited**.
- **Attribution Required**: Any reposting, redistribution, or modification **must** visibly credit the original author (**`vagur1689`**) and link back to the original repository: <https://github.com/vagur1689/flysky-pa01-rgb-led>.
- **ShareAlike**: Derivative works must be distributed under the same **CC BY-NC-SA 4.0** license.
