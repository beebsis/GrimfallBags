# GrimfallBags Changelog

## [2.1.0]

### Added

- **Heroic item support**: the search language now understands `heroic` (and `heroisch`), matching the custom-server "Heroic x/5" tooltip line. Tooltip-only words can also be used as **tags**, so a category named `Heroic` with tags `heroic` and query `heroic` actually collects those items. Tooltip scanning now reads the right-hand column of each tooltip line as well.
- **`/gfbags junk`**: dumps the Junk rule's state (`junkSeeded`, hidden flag, position, query) plus how every poor-quality item currently in the bags was categorized - for diagnosing missing/duplicated categories.
- **`/gfbags clickdebug`**: toggles per-click tracing for item slots (bag, parent id, slot, mouse button, item name/id/count, cooldown, locked/usable state, and the action the addon took).
- **Cached-view click feedback**: clicking an item in a cached (offline) character view, or in a remotely-viewed guild bank, now explains that items can't be used or moved there instead of appearing broken.

### Changed

- **Options cleanup**: removed the blue "ElvUI detected" hint block, the three "Replace Blizzard bags/bank/guild bank" toggles, the category/single-view toggles (the in-window **Switch view** buttons remain the way to change view), and the "Auto-open bags at merchants/mailboxes" toggles.
- **Auto-open is now unconditional**: the bags open at merchants and mailboxes without a setting.

### Fixed

- **Duplicate "Item ID" tooltip lines**: the Item ID line is now skipped when another tooltip addon already prints one (EllesmereUI's `ItemID`, Questie's optional line, ...), so item tooltips no longer show two IDs. The check is generic, not hard-coded to one addon.
- **Junk category could disappear permanently**: if the seeded `Junk` rule was ever lost from the saved config while `junkSeeded` was already true, it was never recreated. It is now restored at login whenever it is missing, and deleting it in the category editor records an explicit "removed" marker so a deliberate deletion still sticks.

### Notes

- `heroic` is a Grimfall-specific keyword (the server's "Heroic x/5" tooltip line); it is not part of the stock Syndicator keyword set.

## [2.0.0]

### Added

- **Cross-character inventory search**: type a query in the bag/bank search box and press **Enter** (or click the "Search all characters" toolbar button) to search every character's cached bags, bank, mail, auctions, and guild bank. Results open in a scrollable window with one row per hit showing icon, quality-colored name, count, character, and source. Click a row to link the item into chat. This is read-only: no remote move or withdraw.
- **Guild bank search + quick filters**: the guild bank window now has the same search box, quality swatches, and type filters as the bag/bank windows (shared implementation, not copy-pasted).
- **Sort methods: Name and Item ID**: added to the sort dropdown (Type remains the default); the guild-bank sorter uses the same key.
- **Category header context menu**: right-clicking a category header opens a dropdown with **Sell** (merchant only), **Deposit to bank** (bank open only), **Deposit to guild bank** (guild bank open only), and **Cancel**. Every destructive action is disabled when not applicable and confirmation-guarded.
- **Confirmed bulk actions**: the bank window gains explicit **Deposit all** / **Withdraw all** buttons, and the transfer button with an empty search now routes through the same confirmation instead of silently moving everything. Protected categories/items are always skipped and reported in the completion message.
- **Guild-bank "Deposit matching items"**: deposits matching bag items into the current guild-bank tab (deposit-only, by design).
- **Cross-character count badge**: a blue number on item icons showing the total of that item across all characters (bags + bank + mail), cached and refreshed on data change; toggle in General options.
- **"Category: <name>" tooltip line**: shows the category an item resolves to, so rule priority is debuggable in-game.
- **Guide tab**: a color-coded, scrollable filter reference in the options window.
- **Skin selector**: a "Skin" dropdown (Flat dark / ElvUI) in the options, with a reload prompt.
- **Dedicated key bindings** (`Bindings.xml`): assign keys for **Toggle Bags**, **Open Bank**, **Open Guild Bank**, **Sort Bags**, and **Search** (Key Bindings → AddOns; no defaults set). This gives the bank window, the guild-bank window, and bag sorting a key, which Blizzard provides no binding for.
- **Hook re-assertion**: the bag-function hooks (`OpenAllBags`, `ToggleBag`, `ToggleBackpack`, and others) are re-applied every 2 seconds, so ElvUI's bag module or a late-loading addon can no longer steal them after `PLAYER_ENTERING_WORLD`.

### Changed

- **Flat theme palette** now matches Ellesmere UI (blue-black panels, white hairline border, `#0CD29D` teal accent), and the accent is applied consistently to tabs, headers, and highlights.
- **Character menu** now lists only current-realm characters, shows entries as `Name - Realm - Bag` / `Name - Realm - Bank`, and lets you view your own character's cached bank without visiting the bank.
- **Search/filter show-hide toggle** now applies to the bag, bank, and guild-bank windows at once.
- **Sort method** moved to a single dropdown in the General tab.

### Fixed

- Tooltips no longer run off the top of the screen in the character sheet (clamping is restored for non-GrimfallBags tooltips).
- Blizzard's invisible guild-bank column buttons no longer float over the window (the frame is pinned off-screen).
- Guild-bank deposit/withdraw buttons no longer overlap the item grid.
- Added a gap below the search/filter row so category headers don't crowd the search bar.
- "Junk" is always sorted last and can't be renamed or moved in the category editor.
- Character-list bag/bank entries and guild-bank search layout spacing cleanups.
- **`OpenAllBags` now opens instead of toggles**: a macro, another addon, or the Shift-B-style binding that calls `OpenAllBags()` no longer closes the bag window when it is already open. `CloseAllBags` remains close-only.
- **Right-click equips/uses items again**: equippable gear (including two-handed weapons) equips via a direct `UseContainerItem` call, and consumables use via the secure "item" action, when right-clicked in the bag window.

### Notes

- The 3.3.5a keyring is intentionally left to Blizzard's frame (documented in the README); it is not folded into the unified window.
- The "replace bags" gate is kept: choosing "Keep ElvUI's" still hands the Blizzard bag binds back to ElvUI, while the new `GFBAGS_*` bindings keep working regardless.
