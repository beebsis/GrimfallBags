# GrimfallBags

Bag / Bank / Guild Bank replacement for WoW 3.3.5a (Grimfall), with category and single-list views, auto-selling, sorting, and a full category system.

## Category filtering

Every category rule has two filters that are AND'ed together:

- **Tags** (comma-separated) — matched with **OR** semantics against the item's type / subtype / equip slot.
- **Query** — a search expression.

A rule matches when: `(tag1 OR tag2 OR …) AND (query)`.

### Query vocabulary

| Kind | Syntax | Matches |
|---|---|---|
| Operators | `&` `|` `!` `( )` | AND / OR / NOT / grouping (`!` → `&` → `|`) |
| Quality | `poor` `common` `uncommon` `rare` `epic` `legendary` `artifact` `heirloom` | rarity (also localized names) |
| Item level | `>200` `<200` `=200` `200-300` | ilvl comparisons / ranges |
| Special | `junk`/`grey`, `equipment`/`gear`, `boe`, `soulbound`/`bop`, `bou`, `heroic`, `new` | junk, equippable, bind-on-equip, soulbound, bind-on-use, "Heroic x/5", recently-looted |
| Item classes | `weapon` `armor` `container` `consumable` `glyph` `trade goods` `projectile` `quiver` `recipe` `gem` `miscellaneous` `quest` | item type (English or localized) |
| Plain text | `sword`, `of the`, `embersilk` | substring in name/type/subtype and full tooltip text |

### Example rules

**Selling / vendor management**

- `boe & epic` — BoE epics (safe to sell).
- `boe | bou` — anything not yet bound (BoE *or* Bind-on-Use).
- `(boe | soulbound) & !epic` — everything below epic, bound or not.
- `consumable & common` — white consumables.

**Gearing / upgrades**

- `weapon & rare & >200` — rare weapons at ilvl 200+.
- `armor & epic & heroic` — epic heroic armor.
- `equipment & (rare | epic) & !soulbound` — equippable rare/epic that isn't soulbound yet.

**Crafting / materials**

- `gem & rare` — rare gems only.
- `(trade goods | consumable) & embersilk` — Embersilk materials (name/tooltip match).
- `recipe & heroic` — heroic recipes.

**Cleanup / organizing**

- `!junk & !quest` — everything except junk and quest items.
- `quest & !soulbound` — unbound quest items (bank/transfer candidates).
- `junk` — grey vendor trash.

**Tag + query combos**

- Tags `weapon, armor` + Query `heroic` — heroic weapons **or** armor.
- Tags `consumable` + Query `new` — newly-looted consumables.
- Tags `armor` + Query `!soulbound` — unbound armor.

**Name / tooltip text**

- `of the` — items with "of the …" in the name (random-suffix gear).
- `!two-hand` — excludes two-handed items (the "Two-Hand" text is read from the tooltip's right column).

**Item-level ranges**

- `weapon & 200-300` — weapons in that ilvl band.
- `armor & >277` — armor above ilvl 277.

A concrete full rule: a category named **"Sellable Epics"** with no tags and query `boe & epic & !heroic` collects epics that are bind-on-equip and *not* heroic-upgraded.

## Commands

- `/gfbags` — toggle the bag window.
- `/gfbags log` — show the internal log.
- `/gfbags options` — open options.
- `/gfbags junk` — debug the Junk category.

## Key bindings

Open **Key Bindings → AddOns** (no defaults are set) and assign keys for:

- **Toggle Bags** — open/close the bag window.
- **Open Bank** — show the bank window (cached contents when away from the bank).
- **Open Guild Bank** — show the guild-bank window (live contents only while at the guild bank).
- **Sort Bags** — sort the player's bags using the selected sort method.
- **Search** — open the bag window and focus its search box.

While "replace bags" is on, Blizzard's own bag binds (`ToggleBackpack`, `OpenAllBags`, `ToggleBag 1–4`, …) are remapped to the unified window: `OpenAllBags` opens it and `CloseAllBags` closes it, and the per-bag `ToggleBag` binds all target the one unified window.

## Keyring

The 3.3.5a keyring (bag slot −2) is **not** folded into the unified window — keys aren't shown alongside bags, and the keyring key (`TOGGLEKEYRING`) still opens Blizzard's keyring frame. This is intentional.
