<div align="center">

# V-Mouse鼠标映射

**A macOS mouse-button remapping tool**

macOS 13+ · Swift / AppKit · No virtual HID · No special entitlements

[简体中文](README.zh-CN.md) · [Architecture](V-Mouse鼠标映射_Architecture.md) · [Licensing](#licensing)

</div>

---

## What it does

V-Mouse鼠标映射 is a macOS mouse-button remapping tool. It reads the onboard values your mouse already sends and maps them a second time—without rewriting onboard memory—to keys, shortcuts, mouse actions, system features, apps or files, commands, text, macros, profile switches, and Mos-style scroll controls.

The mouse first sends the value defined by its onboard profile. V-Mouse鼠标映射 then decides whether that input should pass through, be suppressed, or run a configured Mac action. This second mapping happens entirely in software and does not modify mouse firmware or onboard configuration.

Everything is stored **locally on your Mac**. The app opens your mouse in read-only, non-exclusive mode: it never rewrites onboard buttons, macros, lighting, or DPI, and it never seizes the device from the system.

It was built around the **Razer Naga V2 HyperSpeed**, but it also drives ordinary standard-HID mice and keyboards you select manually.

## Highlights

- **Onboard-value learning** — For each input, press it three times inside a 20-second window; the app records the HID signal, the matching system event, and the timing offset. Read-only: it identifies your signals, it does not modify the mouse.
- **Precise interception** — At runtime each HID press/release creates a short-lived, one-shot token. An Event Tap intercepts an event only when its type, phase, key code, **and** calibrated timestamp all match, so a physical keyboard is never mistaken for the mouse. Per-input **"intercept onboard value"** toggle; off means the original signal passes straight through.
- **Rich action types** — Key sequences, macOS shortcuts (grouped like Mos: function keys, window & app, document editing, Finder, system, screenshot, navigation, modifiers), open app/file/folder/URL, shell command, text snippet, macro, profile switch, mouse click, and held scroll controls.
- **Scroll enhancement** (ported from [Mos](https://github.com/Caldis/Mos)) — Smooth scrolling with independent vertical/horizontal reverse, trackpad simulation, and tunable step / speed / duration / dead-zone. Held controls for acceleration, vertical-to-horizontal, and temporarily disabling smoothing. Trackpad gestures are excluded and left untouched.
- **Built-in trackpad policy** — The main screen can request that macOS disable its built-in trackpad while this app is running and an external mouse is connected. Turning the option off, disconnecting the mouse, or quitting restores the trackpad.
- **Multiple devices and identity rules** — VID/PID is the default device-family identity. Enhanced recognition can be enabled per family, and every enabled condition must match. Each device keeps its own onboard-value table and can share profiles with other devices.
- **Profile mounting** — A device can activate at most one profile or intentionally have none. Even its last profile can be removed from the device; in that state Mac actions and normal interception are disabled, and onboard input passes through by default. Only a device-level ⌘ ⇄ Control swap explicitly enabled by the user remains active. The profile stays available under Unmounted Profiles.
- **Personalization** — Built-in and custom input groups can all be renamed, reordered, and deleted once empty. Learn new inputs in any group; create, duplicate, share, import, and export profiles.
- **Native & localized** — Pure AppKit, following the macOS light/dark appearance, with three themes (frosted glass / night / pure black). Five in-app languages: 简体中文, English, 日本語, 한국어, Deutsch. Optional launch at login.

## Requirements & permissions

- **macOS 13 (Ventura) or later.**
- **Input Monitoring** — to read raw HID reports from the mouse.
- **Accessibility** — to run the interception Event Tap and post your configured actions.
- **Bluetooth** *(optional)* — battery level only, for Bluetooth-connected mice.

The app does not create a virtual HID device, does not take exclusive control of the mouse, and needs no special Apple HID entitlement. Grant Input Monitoring and Accessibility under **System Settings → Privacy & Security**.

## Supported devices

- **Razer Naga V2 HyperSpeed** — over Bluetooth and over the USB 2.4 GHz HyperSpeed receiver, via dedicated, byte-exact report decoders.
- **Standard-HID mice and keyboards** — any device you manually select. Keyboard, Consumer, System Control, and mouse buttons 3+ are supported. Vendor-private protocols and unknown devices are shown with the reason they can't be driven, rather than being silently guessed at.

Each device starts with **side buttons 1–12, DPI+, DPI−, scroll-wheel left, and scroll-wheel right**. Built-in and custom groups can be renamed, reordered, and deleted after they are emptied. New inputs can be learned in any group, are named Custom Key 1, 2… in order, and can later be renamed or moved. DPI± only becomes learnable after you change it from Razer's private DPI function to a normal key in the mouse's onboard (Windows) configuration; the app never writes that itself.

## Build & self-test

```bash
bash Scripts/build_app.sh
```

The script produces a Release binary, runs the built-in self-tests (report decoding, HID key codes, one-shot token routing, multi-device isolation, five-language completeness), creates an ad-hoc-signed `V-Mouse鼠标映射-v0.7.4.app`, and packages `V-Mouse鼠标映射-v0.7.4.dmg`. Release filenames contain the version only and no date suffix.

Run the self-test on its own:

```bash
./V-Mouse鼠标映射-v0.7.4.app/Contents/MacOS/NagaController --self-test-hid-codec
```

Design constraints, the source-discrimination model, and stability guarantees are documented in [V-Mouse鼠标映射_Architecture.md](V-Mouse鼠标映射_Architecture.md).

## How it stays safe

- Read-only, non-exclusive HID access — the mouse keeps working normally even with mapping off.
- Never writes onboard buttons, macros, lighting, or DPI.
- Interception is proven per-event by HID timestamp, never by bare key code, so physical keyboards are protected.
- All synthetic input is released on device disconnect, Event Tap teardown, config change, macro cancel, or quit; a disabled Event Tap is automatically re-enabled.
- Config lives only on your Mac.

## Licensing

This combined project is provided for non-commercial use under [CC BY-NC 4.0](https://creativecommons.org/licenses/by-nc/4.0/). Portions derived from [DParent10/NagaController](https://github.com/DParent10/NagaController) retain their MIT terms; portions derived from [Caldis/Mos](https://github.com/Caldis/Mos) remain subject to CC BY-NC 4.0. See [LICENSE](LICENSE) and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

Commercial use requires permission from the relevant rights holders or replacement of all code subject to the non-commercial restriction.

## Trademark

Razer and Naga are trademarks of Razer Inc. This is an independent, unofficial project and is not affiliated with or endorsed by Razer.
