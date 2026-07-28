# rsg-weaponcomp

Weapon customization system for RedM (RSG Core). Customize weapon components — barrels, grips, sights, materials, engravings, tints, wraps, and more — through placeable gunsmith props with a 3D inspection camera.

## Features

- **Placeable gunsmith props** — Use a `gunsmith` item to place a workbench prop in the world. Each player has a configurable max limit.
- **Full component customization** — Swap barrels, grips, sights, clips, magazines, tubes, wraps, stocks, and scopes on supported weapons.
- **Material, engraving & tint system** — Change trigger/sight/hammer/frame/barrel/cylinder/grip materials, engravings, and color tints.
- **Per-weapon & shared component config** — Common components (materials, engravings) are shared across weapon classes (SHORTARM, LONGARM, SHOTGUN, MELEE_BLADE). Weapon-specific parts (barrels, grips, sights) are defined per weapon hash.
- **3D inspection camera** — Interactive camera with zoom, rotate, and position reset to preview components before purchase.
- **Live price calculation** — Display shows total cost based on selected components. Only new/changed components are charged on apply.
- **Confirmation dialogs** — Purchase and packup actions require confirmation.
- **Diff-based pricing** — Only components that differ from the weapon's current saved state are charged.
- **Dual payment type** — Supports `cash` or `bloodmoney` payment.
- **ox_target integration** — Right-click the placed prop for "Weapon Customization" and "PackUp" options.
- **Native weapon inspection** — RDR2-style stats UI, clean animation with real-time stat recovery. Open via `/inspect` or weapon wheel **Maintain** (scroll click). Cleaning uses `gun_oil`; full repair remains `weapon_repair_kit` via `rsg-weapons`.
- **Weapon restriction list** — Certain weapons (knives, throwables, binoculars, lasso, etc.) can be excluded from customization.
- **Persistence** — All prop and component data saved to MySQL database (`player_weapons_custom` table).

## Dependencies

- [rsg-core](https://github.com/Rexshack-RedM/rsg-core)
- [ox_lib](https://github.com/overextended/ox_lib)
- [oxmysql](https://github.com/overextended/oxmysql)
- [ox_target](https://github.com/overextended/ox_target) (client-side dependency for prop interaction)
- [rsg-weapons](https://github.com/Rexshack-RedM/rsg-weapons)

## Installation

1. Clone the repository into your server's `resources/[framework]/` directory:
   ```
   git clone https://github.com/your-org/rsg-weaponcomp.git
   ```

2. Add the SQL table to your database:
   ```sql
   CREATE TABLE IF NOT EXISTS `player_weapons_custom` (
     `id` int(11) NOT NULL AUTO_INCREMENT,
     `propid` varchar(50) NOT NULL,
     `citizenid` varchar(50) NOT NULL,
     `item` varchar(50) DEFAULT NULL,
     `propdata` longtext DEFAULT NULL,
     PRIMARY KEY (`id`),
     KEY `citizenid` (`citizenid`)
   );
   ```

3. Ensure the resource in your `server.cfg`:
   ```
   ensure rsg-weaponcomp
   ```

4. Add the `gunsmith` item to your items table (or configure a different item name in `config.lua`):
   ```sql
   INSERT INTO `items` (`name`, `label`, `limit`, `rare`, `can_remove`) VALUES
   ('gunsmith', 'Gunsmith Kit', 1, 0, 1);
   ```

5. Add a **`gun_oil`** item for inspection cleaning (example — adjust for your items setup):
   ```lua
   gun_oil = { name = 'gun_oil', label = 'Gun Oil', weight = 120, type = 'item', image = 'weapon_repair_kit.png', unique = false, useable = false, shouldClose = true, description = 'Cleans weapons during inspection' },
   ```

   Optional: integrate `rsg-weapons` callbacks `consumeGunOil` / `syncCleanedWeapon` to persist cleaned quality. Without them, cleaning still works visually; item removal falls back to `rsg-weapons:server:removeitem`.

## Configuration

All settings in `config.lua`:

| Config Key | Type | Default | Description |
|---|---|---|---|
| `Config.Debug` | bool | `false` | Enable debug logging |
| `Config.LoadNotification` | bool | `false` | Show load notifications |
| `Config.PlaceDistance` | float | `5.0` | Max distance to place a gunsmith prop |
| `Config.RepairItem` | string | `weapon_repair_kit` | Full repair item (via `rsg-weapons`) |
| `Config.CleanItem` | string | `gun_oil` | Item consumed when cleaning during inspection |
| `Config.WeaponWheelInspect` | bool | `true` | Hook weapon wheel Maintain action (scroll click) |
| `Config.Gunsmithitem` | string | `gunsmith` | Item used to deploy a gunsmith prop |
| `Config.Gunsmithprop` | hash | `p_gunsmithprops09x` | Prop model for the gunsmith workbench |
| `Config.MaxGunsites` | int | `1` | Max props per player |
| `Config.MaxWeapon` | int | `1` | *(reserved)* |
| `Config.PaymentType` | string | `cash` | `cash` or `bloodmoney` |
| `Config.animationSave` | int | `10000` | Component apply/remove animation duration (ms) |
| `Config.gunZoneActive` | bool | `false` | Enable interaction zones around props |
| `Config.gunZoneSize` | float | `3.0` | Zone radius |
| `Config.showTextZone` | bool | `false` | Show zone text UI |
| `Config.showStats` | bool | `true` | Show weapon stats in inspect mode |
| `Config.Commandinspect` | string | `inspect` | Inspect command name |
| `Config.Commandloadweapon` | string | `loadweapon` | Load weapon command name |
| `Config.RemovePrice` | float | `0.3` | Cost multiplier for removing components (0.0–1.0) |

### Prices

Set per-category prices in `Config.price`. Example:
```lua
Config.price = {
  ["BARREL"] = 1.00,
  ["GRIP"] = 1.00,
  ...
}
```

### Weapon Restriction

Add weapon hashes to `Config.WeaponRestriction` to prevent customization on those weapons.

### Adding Components

- **Shared components** (materials, engravings, tints): Add to `Config.Shared[WEAPON_CLASS][CATEGORY]`
- **Weapon-specific components** (barrels, grips, sights): Add to `Config.Specific[WEAPON_HASH][CATEGORY]`

### Translating

Add/edit locale files in the `locales/` directory. Available locales: `cs`, `en`, `es`, `pl`, `pt-br`.

## Commands

| Command | Description |
|---|---|
| `/inspect` | Native weapon inspection (stats + optional clean with gun oil) |
| `/loadweapon` | Load custom weapon skin |
| `/scope` | Equip scope attachment |
| `/unscope` | Remove scope attachment |

## Export

```lua
exports['rsg-weaponcomp']:startWeaponInspection(hasCleanItem, cleanCallbacks, weaponHashOverride)
```
