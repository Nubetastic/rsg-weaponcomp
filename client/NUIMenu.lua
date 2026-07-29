-- Presentation-only NUI for rsg-weaponcomp.
-- All component application, pricing, validation and purchase logic remains in client.lua.

WeaponCompNUI = WeaponCompNUI or {}

function WeaponCompNUI.Open(data)
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open', data = data })
end

function WeaponCompNUI.Update(data)
    SendNUIMessage({ action = 'update', data = data })
end

function WeaponCompNUI.Close()
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

local function forward(eventName, payload, cb)
    TriggerEvent(eventName, payload or {})
    if cb then cb({ ok = true }) end
end

RegisterNUICallback('weaponcomp:category', function(data, cb)
    forward('rsg-weaponcomp:client:nuiCategory', data, cb)
end)

RegisterNUICallback('weaponcomp:select', function(data, cb)
    forward('rsg-weaponcomp:client:nuiSelect', data, cb)
end)

RegisterNUICallback('weaponcomp:buy', function(_, cb)
    forward('rsg-weaponcomp:client:nuiBuy', {}, cb)
end)

RegisterNUICallback('weaponcomp:pickup', function(_, cb)
    forward('rsg-weaponcomp:client:nuiPickup', {}, cb)
end)

RegisterNUICallback('weaponcomp:close', function(_, cb)
    forward('rsg-weaponcomp:client:nuiClose', {}, cb)
end)

RegisterNUICallback('weaponcomp:back', function(_, cb)
    forward('rsg-weaponcomp:client:nuiBack', {}, cb)
end)

RegisterNUICallback('weaponcomp:pivot', function(data, cb)
    forward('rsg-weaponcomp:client:nuiPivot', data, cb)
end)

RegisterNUICallback('weaponcomp:zoom', function(data, cb)
    forward('rsg-weaponcomp:client:nuiZoom', data, cb)
end)

RegisterNUICallback('weaponcomp:styleLoad', function(data, cb)
    forward('rsg-weaponcomp:client:nuiStyleLoad', data, cb)
end)

RegisterNUICallback('weaponcomp:styleCreate', function(data, cb)
    forward('rsg-weaponcomp:client:nuiStyleCreate', data, cb)
end)

RegisterNUICallback('weaponcomp:styleUpdate', function(data, cb)
    forward('rsg-weaponcomp:client:nuiStyleUpdate', data, cb)
end)

RegisterNUICallback('weaponcomp:styleAddMissing', function(data, cb)
    forward('rsg-weaponcomp:client:nuiStyleAddMissing', data, cb)
end)

RegisterNUICallback('weaponcomp:styleRemove', function(data, cb)
    forward('rsg-weaponcomp:client:nuiStyleRemove', data, cb)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        SetNuiFocus(false, false)
    end
end)
