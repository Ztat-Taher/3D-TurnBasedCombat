class_name GunModule
extends WeaponModule
## Firearm weapon category. Presence of this module marks the weapon's
## [Weapon.equip_kind] as [Weapon.WType.GUN], so only gun-type allies can
## equip it.
##
## Currently data-only — no runtime node, no combat modifiers. This is the
## extension point for future gun-specific mechanics (ammo, reload, recoil,
## dual wield): give them fields here and spawn a runtime node from
## [method create_runtime], same as OrbModule/HitEchoModule.
