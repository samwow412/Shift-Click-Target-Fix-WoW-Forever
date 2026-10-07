In the game's current version, holding Shift, Ctrl or Alt and left-clicking a unit frame (your party, raid, target and so on) no longer targets that unit. The game blocks that kind of click from going straight to "target." This addon restores that behavior.

How it works

Each unit frame is a secure button. The addon gives every frame a tiny hidden helper button that does nothing except target the frame's unit. It then tells the frame: "When Shift+Left is clicked, click the helper button instead." The game doesn't block that indirect click, so you get your target.

It does the same for Ctrl, Alt and combinations like Alt+Shift. Those combos needed their own entries because the game treats each combination as a separate case.

When it runs

The game doesn't allow changes to secure buttons during combat. So the addon sets everything up out of combat: at login, when your group changes, and when new frames appear. If something needs updating mid-fight, it waits until combat ends.

What it touches

Only left-clicks on unit frames while holding a modifier key.
Not your keybinds, action bars, movement, right-clicks, or nameplates.
On the keys you leave enabled, it overrides what other click-casting addons (like Clique) do with that same click. If you want Shift+click to heal, turn Shift off in /shiftfix and the addon leaves it alone.
It may add a Shift+Left → Target entry to the game's Click Casting profile if you don't already have a Shift+Left binding. If you do, it just leaves yours alone.

Settings

Type /shiftfix to open the settings window. It has a checkbox for each modifier and one for allowing combos. Changes apply immediately (or after combat if you're fighting). /shiftfix debug prints what it found, and /shiftfix focus tells you about the frame under your mouse, which helps if one frame doesn't respond.
