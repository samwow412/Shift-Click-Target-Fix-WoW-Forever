# ShiftClickTargetFix

Restores **Shift / Ctrl / Alt + Left-Click targeting** on unit frames, including combinations like **Alt+Shift**.

## The problem

Modified left-clicks on unit frames (player, target, party, raid, etc.) that resolve to "target" are blocked by the game. Shift+click on a party member just does nothing.

## What this addon does

It makes those clicks work again, without touching anything else.

- Works on Blizzard unit frames and frames registered through `ClickCastFrames` (Clique, ElvUI and similar)
- Supports Shift, Ctrl, Alt, and combinations (Alt+Shift, Ctrl+Shift, Alt+Ctrl, Alt+Ctrl+Shift)
- Each modifier can be toggled on or off
- Never touches nameplates
- Safe around combat: changes are applied out of combat and queued if needed

## How it works

Unit frames are secure buttons, and the game blocks a modified click that goes straight to "target". The `click` action is not blocked, so the addon:

1. Creates a hidden 1x1 secure button on each unit frame whose only job is to target the frame's unit.
2. Sets attributes on the frame so that, for example, `Shift+Left` becomes a click on that hidden button.
3. Repeats this for each enabled modifier and combination.

Secure attributes can't be changed in combat, so the addon applies them at login, when your group changes, and when new frames appear. If an update is needed mid-fight, it waits until combat ends.

## Installation

1. Download the latest release zip.
2. Extract it so the folder is `Interface/AddOns/ShiftClickTargetFix`.
3. Restart the game or `/reload`.

## Usage

| Command | What it does |
|---|---|
| `/shiftfix` | Opens the settings window |
| `/shiftfix apply` | Re-scans frames and re-applies the fix |
| `/shiftfix debug` | Prints diagnostic info |
| `/shiftfix focus` | After 3 seconds, reports on the frame under your mouse (useful if a frame doesn't respond) |

Settings: one checkbox each for Shift, Ctrl and Alt, plus **Also allow combos**. A combo is only active if every key in it is enabled.

## Things to know

- **Overrides other click-casting** on the keys you leave enabled. If you want Shift+click to heal, untick Shift in the settings and the addon leaves it alone.
- **Only left-clicks on unit frames** are affected. Keybinds, action bars, movement, right-clicks and nameplates are not.
- **Click Casting profile:** if the client supports it and you have no Shift+Left binding, the addon adds a Shift+Left → Target entry. An existing Shift+Left binding is left alone.
- **`ClickCastFrames` wrapper:** the addon wraps this global table so other addons' frames get the fix. Writes pass through to the original table.

## Compatibility

- Originally written for retail (Interface 120100).
- Adapted for WoW Forever (Classic-based client): added Classic-style party frame names (`PartyMemberFrame#`), guarded optional APIs, and made the settings UI not depend on retail-only template fields.
- Known to work on Forever for the author. Frame names on other clients may differ; use `/shiftfix focus` to check and open an issue with the output.

## Reporting issues

Please include the output of `/shiftfix debug` and, for a frame that doesn't respond, `/shiftfix focus` while hovering it.
