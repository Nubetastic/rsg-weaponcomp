# Weapon Tint Notes

## Short answer

In this resource, tints do not use a separate "weapon tint index" native. They are configured and saved as normal weapon component hashes, then applied with the same component functions as barrels, grips, wraps, stocks, materials, and engravings.

So, conceptually, a tint should color or swap the visible variant for its target part. It should not intentionally remove the default stock by itself.

If applying a tint makes the default stock/grip disappear, the likely causes are:

- the base stock/grip component was not applied before the tint;
- the tint hash belongs to the wrong weapon group or part;
- the tint is being treated by the game as a replacement component for the same drawable slot;
- the saved component set is incomplete, so reload clears the original/default part and reapplies only the tint;
- the preview object path behaves differently from the ped-held weapon path.

## How this script currently handles tints

### Config

Tint choices live in `Config.Shared` or `Config.Specific` under categories ending in `_TINT`, for example:

- `CYLINDER_TINT`
- `BARREL_TINT`
- `TRIGGER_TINT`
- `GRIPSTOCK_TINT`
- `WRAP_TINT`
- `GRIP_TINT`

The tint menu collects only categories where the category name ends with `_TINT`.

### Preview/menu application

`client/client.lua` uses one helper for all component types:

```lua
local function applyWeaponComponent(obj, prevComp, nextComp, wHash)
    local mdl = GetWeaponComponentTypeModel(nextComp)
    if mdl and mdl ~= 0 then
        lib.requestModel(mdl)
    end
    if prevComp then RemoveWeaponComponentFromWeaponObject(obj, prevComp) end
    GiveWeaponComponentToEntity(obj, nextComp, wHash, true)
end
```

When a tint slider changes, the menu removes only the previous component stored under the same tint category, then gives the new tint component to the weapon object.

Important detail: the preview path does not call `ApplyShopItemToPed`; it is applying to the spawned weapon object only.

### Saving

The server saves the selected table directly into `item.info.componentshash`.

Each category stores one component name:

```lua
componentshash = {
    BARREL = "...",
    GRIP = "...",
    GRIPSTOCK_TINT = "...",
}
```

Tints are not special on the server. They are just another category in the saved component table.

### Reloading onto the held weapon

`client/inhands.lua` reloads saved components like this:

1. Get the saved component table from the server.
2. Clear all known components from the held weapon.
3. Sort categories so base categories are applied before suffix categories.
4. Apply each saved component to the ped-held weapon.

The current order puts `_TINT` categories after base categories, materials, and engravings. That is the right general idea: stock/grip first, tint later.

The held weapon path applies components with:

```lua
GiveWeaponComponentToEntity(ped, compHash, weaponHash, true)
ApplyShopItemToPed(ped, compHash, true, true, true)
```

This means saved tints may behave more correctly on the held weapon than in the spawned preview object.

## Does a tint remove the default stock?

Not intentionally.

But with this implementation, the default stock can disappear as a side effect if the stock is not part of the saved/applied set.

The key reload behavior is `clearAllComponents()`: it removes every configured component for that weapon/group before reapplying only the saved components. If the weapon normally needs a `STOCK`, `GRIP`, or `GRIPSTOCK` component to show its default furniture, and only a tint is saved, reload may clear the default component and then apply the tint without restoring the base part.

That would look like "the tint removed the stock", even though the real issue is probably "reload cleared the stock and the saved table did not include the default/base stock."

## Current risk points

### 1. Defaults only apply `BARREL` and `GRIP`

`applyDefaults()` currently applies only:

```lua
local listcomps = { 'BARREL', 'GRIP' }
```

The broader intended list is commented out:

```lua
-- local listcomps = { 'BARREL','GRIP','SIGHT','CLIP','MAG','STOCK','TUBE','TORCH_MATCHSTICK','GRIPSTOCK' }
```

If a weapon needs `STOCK` or `GRIPSTOCK` for its default look, the customization preview/save flow may not preserve it.

### 2. Opening the main menu reapplies every selected component without removing old ones

`MainWeaponMenu()` loops over `selectedCache` and calls:

```lua
applyWeaponComponent(wepObj, nil, compHash, wHash)
```

Because `prevComp` is nil here, this can stack/reapply components on the preview object instead of replacing a previous component. This may make preview behavior unreliable, especially for tint-like components.

### 3. Longarm `GRIPSTOCK_TINT` uses shortarm hashes

In `Config.Shared['LONGARM']['GRIPSTOCK_TINT']`, the entries are:

```lua
"COMPONENT_SHORTARM_GRIPSTOCK_TINT_A_1"
...
"COMPONENT_SHORTARM_GRIPSTOCK_TINT_BURLED"
```

That looks suspicious. A longarm gripstock tint category probably should not use `COMPONENT_SHORTARM_*` hashes unless RedM explicitly aliases them. Wrong-family hashes are a strong candidate for stock/grip visuals disappearing or not tinting correctly.

### 4. Preview object and held weapon use different native paths

Preview object:

```lua
GiveWeaponComponentToEntity(obj, nextComp, wHash, true)
```

Held ped weapon:

```lua
GiveWeaponComponentToEntity(ped, compHash, weaponHash, true)
ApplyShopItemToPed(ped, compHash, true, true, true)
```

If tints require shop-item application to resolve correctly, the preview may lie.

## Suggested review/fix direction

1. Confirm whether each weapon with stock issues has a saved `STOCK`, `GRIP`, or `GRIPSTOCK` entry after buying only a tint.
2. Expand default application/preservation so base visual parts are included before tint categories.
3. Audit tint hashes by weapon group, especially `LONGARM` `GRIPSTOCK_TINT`.
4. Avoid reapplying all `selectedCache` components on every return to `MainWeaponMenu()` unless the preview object has first been reset or cleared.
5. Test held-weapon reload separately from preview, because they use different application natives.

## Working theory

Tints are supposed to color or variant the stock/grip/wrap, not remove the default stock. The disappearing stock symptom is probably caused by component state management: clearing defaults, missing base stock/grip entries, or applying mismatched tint hashes.

## Springfield Review

Reviewed for `WEAPON_RIFLE_SPRINGFIELD`.

### Current Springfield-specific config

The Springfield config has these weapon-specific visual categories:

```lua
["WEAPON_RIFLE_SPRINGFIELD"] = {
    ["GRIP"] = {
      "COMPONENT_RIFLE_SPRINGFIELD_GRIP",
      "COMPONENT_RIFLE_SPRINGFIELD_GRIP_IRONWOOD",
      "COMPONENT_RIFLE_SPRINGFIELD_GRIP_ENGRAVED",
      "COMPONENT_RIFLE_SPRINGFIELD_GRIP_BURLED",
    },
    ["SIGHT"] = {
      "COMPONENT_RIFLE_SPRINGFIELD_SIGHT_NARROW",
      "COMPONENT_RIFLE_SPRINGFIELD_SIGHT_WIDE",
    },
    ["WRAP"] = {
      "COMPONENT_RIFLE_SPRINGFIELD_WRAP1",
      "COMPONENT_RIFLE_SPRINGFIELD_WRAP2",
      "COMPONENT_RIFLE_SPRINGFIELD_WRAP3",
      "COMPONENT_RIFLE_SPRINGFIELD_WRAP4",
      "COMPONENT_RIFLE_SPRINGFIELD_WRAP5",
      "COMPONENT_RIFLE_SPRINGFIELD_WRAP6",
    },
    ["SCOPE"] = {
      "COMPONENT_RIFLE_SCOPE02",
      "COMPONENT_RIFLE_SCOPE03"
    }
}
```

There is no Springfield-specific `GRIP_TINT` or `GRIPSTOCK_TINT` category in `Config.Specific["WEAPON_RIFLE_SPRINGFIELD"]`.

### External weapon data cross-check

The external weapon-data snippet I found for `WEAPON_RIFLE_SPRINGFIELD` lists the Springfield grip components under attach bone `WAPGRIP`:

```xml
<Name>COMPONENT_RIFLE_SPRINGFIELD_GRIP</Name>
<Name>COMPONENT_RIFLE_SPRINGFIELD_GRIP_IRONWOOD</Name>
<Name>COMPONENT_RIFLE_SPRINGFIELD_GRIP_ENGRAVED</Name>
<Name>COMPONENT_RIFLE_SPRINGFIELD_GRIP_BURLED</Name>
```

It also marks `COMPONENT_RIFLE_SPRINGFIELD_GRIP` as the default component, and lists the Springfield wrap/sight/scope components separately.

Source used for this cross-check:

- Nexus Mods documentation page containing a `WEAPON_RIFLE_SPRINGFIELD` weapon-data excerpt: `https://www.nexusmods.com/reddeadredemption2/mods/2816?tab=docs`

This supports that the Springfield-specific `GRIP`, `SIGHT`, `WRAP`, and `SCOPE` names currently in `config.lua` are plausible/correct.

### What looks wrong for the tint symptom

The tint menu is built from `GetAvailableComponents()`, which merges:

1. shared group components for `GROUP_RIFLE` -> `LONGARM`;
2. Springfield-specific components.

Because Springfield is a longarm, it inherits `Config.Shared["LONGARM"]["GRIPSTOCK_TINT"]`.

Current shared longarm `GRIPSTOCK_TINT` entries are:

```lua
"COMPONENT_SHORTARM_GRIPSTOCK_TINT_A_1",
"COMPONENT_SHORTARM_GRIPSTOCK_TINT_A_2",
...
"COMPONENT_SHORTARM_GRIPSTOCK_TINT_BURLED",
```

Those names are suspicious for a Springfield rifle. They are `SHORTARM` gripstock tint hashes being offered to a `LONGARM` rifle.

I did not find `COMPONENT_LONGARM_GRIPSTOCK_TINT_*` in the external Springfield data page. That page only shows Springfield's real grip variants as `COMPONENT_RIFLE_SPRINGFIELD_GRIP*`.

### How this matches the observed behavior

Observed:

- In the propplace/customization view, the grip updates correctly.
- When applied to the hands, the tinted grip gets replaced with the gun's default grip.

Current behavior that may explain it:

- Preview applies directly to the spawned weapon object with `GiveWeaponComponentToEntity`.
- Held-weapon reload applies to the ped with both `GiveWeaponComponentToEntity` and `ApplyShopItemToPed`.
- Reload clears known components first, then reapplies saved components sorted by category.
- `GRIP` is applied before `_TINT`, so the saved Springfield grip may go on correctly, then the inherited `SHORTARM` tint hash is applied afterward.

Working hypothesis for Springfield:

The Springfield grip hashes appear correct. The bad piece is probably not the Springfield `GRIP` list. It is probably the shared longarm `GRIPSTOCK_TINT` list. The tint component may preview on the object, but when the held weapon is rebuilt on the ped, `ApplyShopItemToPed` or RedM's weapon component resolver rejects/overrides that shortarm tint on a rifle and falls back to the default Springfield grip.

### Next checks before coding

1. Confirm the saved `componentshash` after purchase contains both:
   - `GRIP = COMPONENT_RIFLE_SPRINGFIELD_GRIP_*`
   - `GRIPSTOCK_TINT = COMPONENT_SHORTARM_GRIPSTOCK_TINT_*`
2. Test whether the held weapon keeps a non-default Springfield `GRIP` when no `GRIPSTOCK_TINT` is saved.
3. Test whether the held weapon resets only after `GRIPSTOCK_TINT` is saved.
4. Check whether RedM has valid longarm/rifle-specific grip tint hashes, or whether Springfield grip color should be handled only by the four Springfield `GRIP` components.

## Correct Springfield Tint Settings

For `WEAPON_RIFLE_SPRINGFIELD`, the correct conclusion from the available component data is: do not use a separate grip tint category.

The Springfield grip/stock appearance is controlled by the Springfield-specific `GRIP` components:

```lua
["GRIP"] = {
  "COMPONENT_RIFLE_SPRINGFIELD_GRIP",
  "COMPONENT_RIFLE_SPRINGFIELD_GRIP_IRONWOOD",
  "COMPONENT_RIFLE_SPRINGFIELD_GRIP_ENGRAVED",
  "COMPONENT_RIFLE_SPRINGFIELD_GRIP_BURLED",
}
```

The correct Springfield tint setting is effectively no grip tint:

```lua
-- Do not offer these for WEAPON_RIFLE_SPRINGFIELD:
-- ["GRIPSTOCK_TINT"] = { ... }
-- ["GRIP_TINT"] = { ... }
```

The current inherited `LONGARM -> GRIPSTOCK_TINT` list should not be treated as correct for Springfield because it contains `COMPONENT_SHORTARM_GRIPSTOCK_TINT_*` entries. Those are not shown in the Springfield weapon attach-point data, and they match the observed failure where the in-hand weapon falls back to the default Springfield grip.

Important implementation note for later: with the current `GetAvailableComponents()` merge behavior, adding an empty Springfield-specific `GRIPSTOCK_TINT = {}` will not block the shared longarm tint list. The Springfield would need to be excluded from inherited `GRIPSTOCK_TINT`, or the available-component builder would need an override/deny-list mechanism.

Sources checked:

- Nexus Mods page with `WEAPON_RIFLE_SPRINGFIELD` attach-point data: `https://www.nexusmods.com/reddeadredemption2/mods/2806?tab=docs`
- Nexus Mods page with the same Springfield attach-point data: `https://www.nexusmods.com/reddeadredemption2/mods/2816?tab=docs`
- Scribd armory config excerpt listing Springfield `GRIP`, `SIGHT`, and `WRAP`, with no Springfield tint category: `https://www.scribd.com/document/855719042/Trad-Armurerie-2-RDR`

## Longarm Gripstock Tint Test

Question: would `COMPONENT_LONGARM_GRIPSTOCK_TINT_*` work with `WEAPON_RIFLE_SPRINGFIELD`?

Current answer: worth testing, but not guaranteed.

These are much more plausible than the current inherited `COMPONENT_SHORTARM_GRIPSTOCK_TINT_*` hashes because Springfield is a `GROUP_RIFLE` / `LONGARM` weapon. I found an external armory-style config excerpt that lists `COMPONENT_LONGARM_GRIPSTOCK_TINT_*` under longarm shared customization, so the names are plausible component names.

However, the Springfield weapon attach-point data itself only lists these grip components under `WAPGRIP`:

```lua
"COMPONENT_RIFLE_SPRINGFIELD_GRIP"
"COMPONENT_RIFLE_SPRINGFIELD_GRIP_IRONWOOD"
"COMPONENT_RIFLE_SPRINGFIELD_GRIP_ENGRAVED"
"COMPONENT_RIFLE_SPRINGFIELD_GRIP_BURLED"
```

It does not show Springfield-specific gripstock tint attach-point entries. So the longarm tint hashes may work as overlay/shop-item tints, or the in-hand weapon may still reject them and fall back to a Springfield grip variant.

### Fastest config-only test

Do not add a Springfield-specific `GRIPSTOCK_TINT` list on top of the current config yet. `GetAvailableComponents()` merges shared and specific categories, so adding a Springfield-specific `GRIPSTOCK_TINT` would append to the inherited bad shortarm list instead of replacing it.

For the quickest test, temporarily replace the current `Config.Shared["LONGARM"]["GRIPSTOCK_TINT"]` list with the longarm hashes:

```lua
['GRIPSTOCK_TINT'] = {
  "COMPONENT_LONGARM_GRIPSTOCK_TINT_A_1",
  "COMPONENT_LONGARM_GRIPSTOCK_TINT_A_2",
  "COMPONENT_LONGARM_GRIPSTOCK_TINT_A_3",
  "COMPONENT_LONGARM_GRIPSTOCK_TINT_A_4",
  "COMPONENT_LONGARM_GRIPSTOCK_TINT_A_5",
  "COMPONENT_LONGARM_GRIPSTOCK_TINT_A_6",
  "COMPONENT_LONGARM_GRIPSTOCK_TINT_A_7",
  "COMPONENT_LONGARM_GRIPSTOCK_TINT_A_8",
  "COMPONENT_LONGARM_GRIPSTOCK_TINT_B_1",
  "COMPONENT_LONGARM_GRIPSTOCK_TINT_B_2",
  "COMPONENT_LONGARM_GRIPSTOCK_TINT_B_3",
  "COMPONENT_LONGARM_GRIPSTOCK_TINT_B_4",
  "COMPONENT_LONGARM_GRIPSTOCK_TINT_B_5",
  "COMPONENT_LONGARM_GRIPSTOCK_TINT_B_6",
  "COMPONENT_LONGARM_GRIPSTOCK_TINT_B_7",
  "COMPONENT_LONGARM_GRIPSTOCK_TINT_B_8",
  "COMPONENT_LONGARM_GRIPSTOCK_TINT_GUTTAPERCHA",
  "COMPONENT_LONGARM_GRIPSTOCK_TINT_PEARL",
  "COMPONENT_LONGARM_GRIPSTOCK_TINT_GRAY_BIRCH",
  "COMPONENT_LONGARM_GRIPSTOCK_TINT_BURLED",
},
```

### Test steps

1. Restart the resource/server after the temporary config change.
2. Use a Springfield with no saved `componentshash`, or clear the saved components for that weapon first.
3. Select a non-default Springfield `GRIP`, such as `COMPONENT_RIFLE_SPRINGFIELD_GRIP_IRONWOOD`.
4. Select one `GRIPSTOCK_TINT`, preferably a very visible one like `COMPONENT_LONGARM_GRIPSTOCK_TINT_PEARL` or `COMPONENT_LONGARM_GRIPSTOCK_TINT_BURLED`.
5. Buy/save.
6. Run the load/reload path so the held weapon rebuilds in hands.
7. Check whether the held Springfield keeps the selected grip/tint or snaps back to `COMPONENT_RIFLE_SPRINGFIELD_GRIP`.

### How to read the result

If the in-hand weapon keeps the selected tint, then the current issue is probably the wrong `SHORTARM` tint hashes in the longarm shared list.

If the in-hand weapon still resets to the default grip, then Springfield likely does not support separate gripstock tint overlays, and its color/material choice should stay limited to the four Springfield `GRIP` components.

Source checked for plausible longarm tint names:

- Scribd armory config excerpt listing `COMPONENT_LONGARM_GRIPSTOCK_TINT_*`: `https://www.scribd.com/document/855719042/Trad-Armurerie-2-RDR`
