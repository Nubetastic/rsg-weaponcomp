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
