# Junkie UI - Featherlight (WoW 3.3.5a)

Plug and play. No profiles.

## Install
1. Copy the `JunkieUI` folder to `World of Warcraft\Interface\AddOns\`
2. Restart the client.

## What it does
- UI scale forced to 0.5333
- Square minimap, 1px border #232323, with a custom clock box
- Action bars, black #232323 borders on a dark background:
  - Bottom plate top to bottom: Bar4 (6x2), Bar1 (12), Bar3 (12), Bar2 (6x2)
  - Right side: Bar5, 12 buttons downward
  - Bar1 paging: `[stealth] 8; [stance:1] 7; [stance:2] 9; [stance:3] 10; [stance:4] 10`
- Unit frames 250x40 (ElvUI-flat) with target castbar and target auras
- Player debuffs anchored right to left, 200px above the player frame
- Chat in a dark box with the edit box directly below the chat

## Settings: `/jui`
Player/target gap slider (1-500 with manual input), shared Y offset, power bar
toggles, cooldown text and a movable quest tracker.

## Changelog

### 1.6.6 BETA
- Bar 1 visibility now runs through a single secure state driver instead of twelve, removing the stutter during combat, stealth and stance changes
- Same overlap protection as 1.6.5, at a twelfth of the restricted-environment work

### 1.6.5 BETA
- Normal Bar 1 buttons are now securely hidden for the entire stance, stealth and vehicle state, so icons and glows cannot bleed through the bonus bar
- Blizzard still owns stance paging, action IDs and spell dragging; buttons stay in their original secure hierarchy
- Every stance page keeps the same opaque dark button backgrounds, including empty slots
- Bonus buttons also use an explicit higher frame level to prevent transition-frame flicker

### 1.6.4 BETA
- Removed the custom Bar 1 secure holder and duplicate state driver entirely
- ActionButton1-12 remain in Blizzard's original secure hierarchy, preventing partial grid/icon loss after stance changes
- Blizzard exclusively controls the swap between normal and bonus buttons; JunkieUI only anchors both sets to the same position

### 1.6.3 BETA
- Bar 1 now keeps all 12 dark slots visible before, during and after stance/stealth paging
- Removed the competing alpha and mouse event fallback that could leave Bar 1 invisible after a combat stance change
- Empty slots use a mouse-transparent visual row underneath Blizzard's secure ActionButtons and BonusActionButtons, so spell dragging and combat paging remain Blizzard-controlled

### 1.5.5 BETA
- Player buffs and debuffs are back to the Blizzard default layout — all custom buff positioning, CVar forcing and layout hooks removed
- Minimap is 10% smaller so it no longer collides with the default buff rows
- Removed the now unused buff layout driver and event watchers
- Code cleanup: removed leftover comments and dead arguments in the action bar layout

### 1.5.4 BETA
- Performance optimizing: reduced frame-time spikes across action bars, buffs, tooltips and minimap buttons
- Combat performance: unit frames only run the update an event invalidates, group-mate events are discarded cheaply
- Buff grid re-layout throttled during aura churn; action bars no longer rebuild the full layout on leaving combat
