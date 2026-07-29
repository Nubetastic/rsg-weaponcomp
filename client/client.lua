local RSGCore = exports['rsg-core']:GetCoreObject()
lib.locale()

local SpawnedProps   = {}
local PackingUpProps = {}
local gunZones       = {}
local ingunZone      = false
local isBusy         = false
local wepObj         = nil
local camera         = nil
local selectedCache  = {}
local selectedLabels  = {}
local savedComponents = {}
local removedComponents = {}
local savedStyles = {}
local canPickupAllowed = false

local rotateL = nil
local rotateR = nil
local randomPos = nil
local zoomIn = nil
local zoomOut = nil
local reset = nil
local promptGroup = GetRandomIntInRange(0, 0xffffff)
local promptThreadActive = false
local c_zoom = 1.5
local c_offset = 0.20
local cameraOrbit = { yaw = 0.0, pitch = 15.0, radius = 0.50, baseRadius = 0.50, zoom = 50 }
local nuiContext = nil

local function FreezePlayer()
    FreezeEntityPosition(cache.ped, true)
    SetEntityInvincible(cache.ped, true)
    SetBlockingOfNonTemporaryEvents(cache.ped, true)
    SetPedCanRagdoll(cache.ped, false)
end

local function UnfreezePlayer()
    FreezeEntityPosition(cache.ped, false)
    SetEntityInvincible(cache.ped, false)
    SetBlockingOfNonTemporaryEvents(cache.ped, false)
    SetPedCanRagdoll(cache.ped, true)
end

local MenuData = {}
----------------------------------------
-- Basics
----------------------------------------
local WeaponTypeMap = {
    [GetHashKey('GROUP_REPEATER')] = "LONGARM",
    [GetHashKey('GROUP_SHOTGUN'  )] = "SHOTGUN",
    [GetHashKey('GROUP_PISTOL'   )] = "SHORTARM",
    [GetHashKey('GROUP_REVOLVER')] = "SHORTARM",
    [GetHashKey('GROUP_RIFLE'    )] = "LONGARM",
    [GetHashKey('GROUP_SNIPER'   )] = "LONGARM",
    [GetHashKey('GROUP_MELEE'    )] = "MELEE_BLADE",
    [GetHashKey('GROUP_BOW'      )] = "GROUP_BOW",
}

function GetWeaponType(hash)
    return WeaponTypeMap[GetWeapontypeGroup(hash)]
end

-- Merge components from source into merged
local function mergeComponents(merged, source)
    for cat, list in pairs(source) do
        merged[cat] = merged[cat] or {}
        for _, comp in ipairs(list) do
            merged[cat][#merged[cat]+1] = comp
        end
    end
end

-- Build specific + shared merged table
local function GetAvailableComponents(weaponName, wHash)
    local specific = Config.Specific[weaponName] or {}
    local merged   = {}
    local group    = GetWeaponType(wHash)

    if group and Config.Shared[group] then    -- Shared (group) components
        mergeComponents(merged, Config.Shared[group])
    end

    mergeComponents(merged, specific)    -- Specific components
    if Config.GunstockTints ~= true then
        merged.GRIPSTOCK_TINT = nil
    end
    return merged
end

local function CanPlacePropHere(pos)
    for _,p in ipairs(Config.PlayerProps) do
        if #(pos - vector3(p.x,p.y,p.z)) < 1.3 then return false end
    end
    return true
end

-- Spawn weapon on the prop
local function spawnWeaponOnProp(propObj, spawnPos, wHash)
    if wepObj ~= nil and DoesEntityExist(wepObj) then
        DeleteObject(wepObj)
        wepObj = nil
    end
    -- create new
    wepObj = Citizen.InvokeNative(0x9888652B8BA77F73, wHash, 0, spawnPos.x, spawnPos.y, spawnPos.z, false, 1.0)
    -- place weapon
    if wepObj and DoesEntityExist(wepObj) then
        AttachEntityToEntity(wepObj, propObj, -1, -0.06, 0.0, 0.28, 0.0, 0.0, 90.0, false, false, false, false, 2, true)
        FreezeEntityPosition(wepObj, true)
    end
end

----------------------------------------
-- cameras
----------------------------------------
-- start camera menu
local function StartCamOnWeapon(obj, fov)
    if not (obj and DoesEntityExist(obj)) then return end
    ClearFocus()
    local forward, right, up, origin = table.unpack({ GetEntityMatrix(obj) })

    local distBack = Config.distBack
    local distSide = Config.distSide
    local distUp   = Config.distUp

    local camPos = vector3(
        origin.x - forward.x * distBack + right.x * distSide + up.x * distUp,
        origin.y - forward.y * distBack + right.y * distSide + up.y * distUp,
        origin.z - forward.z * distBack + right.z * distSide + up.z * distUp
    )

    if camera then DestroyCam(camera, true) end
    camera = CreateCamWithParams(
        "DEFAULT_SCRIPTED_CAMERA",
        camPos.x, camPos.y, camPos.z,
        0, 0, 0,    -- rotaciÃ³n; la fijamos con PointCamAtCoord
        fov or 75.0,
        false, 0
    )

    SetCamActive(camera, true)
    RenderScriptCams(true, true, 1000, true, false)
    PointCamAtCoord(camera, origin.x, origin.y, origin.z + 0.1)

    local currentCam = GetCamCoord(camera)
    local delta = currentCam - origin
    cameraOrbit.radius = #(delta) > 0.01 and #(delta) or 0.50
    cameraOrbit.baseRadius = cameraOrbit.radius
    cameraOrbit.zoom = 50
    cameraOrbit.yaw = math.deg(math.atan(delta.y, delta.x))
    cameraOrbit.pitch = math.deg(math.asin(math.clamp(delta.z / cameraOrbit.radius, -1.0, 1.0)))
end

RegisterNetEvent('rsg-weaponcomp:client:ExitCam')
AddEventHandler('rsg-weaponcomp:client:ExitCam', function()
    ClearFocus()
    RenderScriptCams(false, false, 0, true, false)
    if camera then DestroyCam(camera,true) end
    camera = nil
    DestroyAllCams(true)

    if wepObj ~= nil and DoesEntityExist(wepObj) then
        SetEntityAsMissionEntity(wepObj, false)
        FreezeEntityPosition(wepObj, false)
        DeleteObject(wepObj)
    end
    ClearCameraPrompts()
    promptThreadActive = false
    MenuData.CloseAll()
    if WeaponCompNUI then WeaponCompNUI.Close() end
    TriggerEvent('HideAllUI')
    UnfreezePlayer()
end)

-- save
local function StartCamClean(zoom, offset)
    ClearFocus()
    local zoomOffset = tonumber(zoom)
    local coords = GetEntityCoords(cache.ped)
    local playerHeading = GetEntityHeading(cache.ped)
    local angle = playerHeading * math.pi / 180.0

    local pos = {
        x = coords.x - tonumber(zoomOffset * math.sin(angle)),
        y = coords.y + tonumber(zoomOffset * math.cos(angle)),
        z = coords.z + offset
    }

    local camera_pos = GetObjectOffsetFromCoords(pos.x, pos.y, pos.z, 0.0, 1.0, 1.0, 1.0)

    camera = CreateCamWithParams("DEFAULT_SCRIPTED_CAMERA", pos.x, pos.y, pos.z + 0.5, 300.00, 0.00, 0.00, 50.00, false, 0)
    local pCoords = GetEntityCoords(cache.ped)
    PointCamAtCoord(camera, pCoords.x, pCoords.y, pCoords.z + offset)

    SetCamActive(camera, true)
    RenderScriptCams(true, true, 1000, true, false)
end

RegisterNetEvent("rsg-weaponcomp:client:animationSaved")
AddEventHandler("rsg-weaponcomp:client:animationSaved", function(objecthash, serial)
    SetCurrentPedWeapon(cache.ped, objecthash, true)

    if camera then DestroyCam(camera,true) end
    camera = nil

    if wepObj ~= nil and DoesEntityExist(wepObj) then
        SetEntityAsMissionEntity(wepObj, false)
        FreezeEntityPosition(wepObj, false)
        DeleteObject(wepObj)
    end

    local weapon_type = GetWeaponType(objecthash)
    local boneIndex2 = GetEntityBoneIndexByName(cache.ped, "SKEL_L_Finger00")
    local Cloth = CreateObject(GetHashKey('s_balledragcloth01x'), GetEntityCoords(cache.ped), false, true, false, false, true)
    local animDict = nil
    local animName = nil

    if weapon_type == 'SHORTARM' then
       animDict = "mech_inspection@weapons@shortarms@volcanic@base"
       animName = "clean_loop"
        c_zoom = 0.85
        c_offset = 0.10
    elseif weapon_type == 'LONGARM' then
        animDict = "mech_inspection@weapons@longarms@sniper_carcano@base"
        animName = "clean_loop"
        c_zoom = 1.5
        c_offset = 0.20
    elseif weapon_type == 'SHOTGUN' then
        animDict = "mech_inspection@weapons@longarms@shotgun_double_barrel@base"
        animName = "clean_loop"
        c_zoom = 1.2
        c_offset = 0.15
    elseif weapon_type == 'GROUP_BOW' then
        c_zoom = 1.5
        c_offset = 0.15
    elseif weapon_type == 'MELEE_BLADE' then
        c_zoom = 1.2
        c_offset = 0.15
    end

    StartCamClean(c_zoom, c_offset)
    Wait(100)

    if animDict ~= nil and animName ~= nil then
        AttachEntityToEntity(Cloth, cache.ped, boneIndex2, 0.02, -0.035, 0.00, 20.0, -24.0, 165.0, true, false, true, false, 0, true)

        lib.progressBar({
            duration = tonumber(Config.animationSave),
            useWhileDead = false,
            canCancel = false,
            disable = { move = true, car = true, combat= true, mouse= false, sprint = true, },
            anim = { dict = animDict, clip = animName, flag = 15, },
            label = locale('cl_lang_1'),
        })


        if Cloth ~= nil and DoesEntityExist(Cloth) then
            SetEntityAsNoLongerNeeded(Cloth)
            DeleteEntity(Cloth)
        end
    end

    TriggerServerEvent("rsg-weaponcomp:server:check_comps")
    TriggerEvent('rsg-weaponcomp:client:ExitCam')
end)

local function SetRandomCameraAroundWeapon()
    if not camera or not wepObj then return end

    local wepCoords = GetEntityCoords(wepObj)
    local radius = 0.50

    local angleDeg = math.random(1, 360)
    local pitchDeg = math.random(-10, 50)

    local angleRad = math.rad(angleDeg)
    local pitchRad = math.rad(pitchDeg)

    local xOffset = radius * math.cos(angleRad) * math.cos(pitchRad)
    local yOffset = radius * math.sin(angleRad) * math.cos(pitchRad)
    local zOffset = radius * math.sin(pitchRad)

    local camX = wepCoords.x + xOffset
    local camY = wepCoords.y + yOffset
    local camZ = wepCoords.z + zOffset

    SetCamCoord(camera, camX, camY, camZ)
    PointCamAtCoord(camera, wepCoords.x, wepCoords.y, wepCoords.z)
end

local function smoothZoom(cam, fromFov, toFov, duration)
    local startTime = GetGameTimer()
    while true do
        local now = GetGameTimer()
        local elapsed = now - startTime
        if elapsed >= duration then break end

        local progress = elapsed / duration
        local currentFov = fromFov + (toFov - fromFov) * progress
        SetCamFov(cam, currentFov)
        Wait(0)
    end
    SetCamFov(cam, toFov)
end

-- Zoom in/out con transiciÃ³n suave
local function AdjustZoom(increase)
    if not camera or not wepObj then return end
    local currentFov = GetCamFov(camera)
    local targetFov = increase and (currentFov - 5.0) or (currentFov + 5.0)
    targetFov = math.clamp(targetFov, 15.0, 90.0)

    -- Zoom suave en 150ms (ajustable)
    CreateThread(function()
        smoothZoom(camera, currentFov, targetFov, 150)
    end)
end

-- Reset a posiciÃ³n inicial del client:startcustom
local function ResetCameraToDefault()
    if not camera or not wepObj then return end
    StartCamOnWeapon(wepObj, Config.distFov)
end

----------------------------------------
-- prompts
----------------------------------------
function ClearCameraPrompts()
    rotateL = nil
    rotateR = nil
    randomPos = nil
    zoomIn = nil
    zoomOut = nil
    reset = nil
end

-- Function to create and register a prompt
local function RegisterPrompt(control, textKey, group, hold)
    local txt = locale(textKey)
    local p = PromptRegisterBegin()
    PromptSetControlAction(p, control)
    PromptSetText(p, CreateVarString(10, 'LITERAL_STRING', txt))
    PromptSetEnabled(p, true)
    PromptSetVisible(p, true)
    if hold then PromptSetHoldMode(p, true) else PromptSetStandardMode(p, true) end
    PromptSetGroup(p, group)
    Citizen.InvokeNative(0xC5F428EE08FA7F2C, p, true)
    PromptRegisterEnd(p)
    return p
end

-- Prompt log (without activation prompt)
local function RegisterCameraPrompts()
    zoomIn    = RegisterPrompt(Config.prompts.zoIn, 'zoom',           promptGroup, false) -- ScrollUp
    zoomOut   = RegisterPrompt(Config.prompts.zoOut, 'zoom',          promptGroup, false) -- ScrollDown
    reset     = RegisterPrompt(Config.prompts.re, 'weapon_cam_reset',  promptGroup, true)  -- v
end

local function StartPromptThread()
    if promptThreadActive then return end
    promptThreadActive = true
    CreateThread(function()

        RegisterCameraPrompts()
        while promptThreadActive do
            if camera then
                local promptText = CreateVarString(10, 'LITERAL_STRING', 'Camera Controls')
                PromptSetActiveGroupThisFrame(promptGroup, promptText)
                if IsControlJustPressed(2, Config.prompts.zoIn) then AdjustZoom(true) end
                if IsControlJustPressed(2, Config.prompts.zoOut) then AdjustZoom(false) end
                if IsControlJustPressed(2, Config.prompts.re) then ResetCameraToDefault()end
            end
            Wait(0)
        end
    end)
end

----------------------------------------
-- aply menu
----------------------------------------
local function applyWeaponComponent(obj, prevComp, nextComp, wHash)
    local mdl = GetWeaponComponentTypeModel(nextComp)
    if mdl and mdl ~= 0 then
        lib.requestModel(mdl)
    end
    if prevComp then RemoveWeaponComponentFromWeaponObject(obj, prevComp) end
    GiveWeaponComponentToEntity(obj, nextComp, wHash, true)
end

-- Initialize first set comp
local function applyDefaults(obj, wHash)
    local name = Citizen.InvokeNative(0x89CF5FF3D363311E, wHash, Citizen.ResultAsString())
    local comps = GetAvailableComponents(name, wHash)
    local listcomps = { 'BARREL', 'GRIP' }
    -- local listcomps = { 'BARREL','GRIP','SIGHT','CLIP','MAG','STOCK','TUBE','TORCH_MATCHSTICK','GRIPSTOCK' }
    for _, cat in ipairs(listcomps) do
        local options = comps[cat]
        if options and #options > 0 then
            local defaultComp = options[1]                     -- nombre del componente
            local compHash    = GetHashKey(defaultComp)       -- su hash
            applyWeaponComponent(obj, nil, compHash, wHash)   -- lo aplicas
            selectedCache[cat] = defaultComp                  -- y lo guardas en la cachÃ©
            selectedLabels[cat] = defaultComp
        end
    end
end

----------------------------------------
-- Menu
----------------------------------------
TriggerEvent('rsg-menubase:getData', function(call)
    MenuData = call
end)

local function OpenComponentMenu(wname, wHash, serial, propid)
    local comps = Config.Specific[wname] or {}
    local elements = {}
    local a = 1

    for cat, list in pairs(comps) do
        local hashes, labels, labelsSends = {}, {}, {}
        for i, comp in ipairs(list) do
            hashes[i], labels[i], labelsSends[i] = GetHashKey(comp), comp, locale(comp)            -- labels[i] = comp
        end
        elements[#elements+1] = {
            label  = locale(cat),
            type   = "slider",
            name   = cat,
            min    = 1,
            max    = #list,
            value  = selectedCache[cat] and (function()
                for idx,v in ipairs(list) do if v==selectedCache[cat] then return idx end end
                return 1
            end)() or 1,
            hashes = hashes,
            labels = labels,
            labelsSends = labelsSends,
            id = a
        }
    end

    MenuData.Open("default", GetCurrentResourceName(), "weapon_specific_menu", {
        title    = locale('cl_lang_2') ..  ":",
        align    = "top-left",
        elements = elements,
    }, function(data, menu)
        local sel = data.current
        if sel.hashes then
            local prev = selectedCache[sel.name] and GetHashKey(selectedCache[sel.name]) or nil
            local nxt  = sel.hashes[sel.value]
            applyWeaponComponent(wepObj, prev, nxt, wHash)
            selectedCache[sel.name] = sel.labels[sel.value]
            selectedLabels[sel.name] = sel.labelsSends[sel.value]  -- Almacena el label
            -- FocusCam(wepObj)
        end
    end, function(_, menu)
        menu.close()
        MainWeaponMenu(wname, wHash, serial, propid)
    end)
end

-- Menu MATERIAL (not _ENGRAVING_MATERIAL)
local function OpenMaterialMenu(wname, wHash, serial, propid)
    local comps = GetAvailableComponents(wname, wHash)
    local elements = {}
    local a = 1
    for cat, items in pairs(comps) do
      if cat:find('_MATERIAL$') and not cat:find('_ENGRAVING_MATERIAL$') then
        local hashes, labels, labelsSends = {}, {}, {}
        for i, comp in ipairs(items) do
            hashes[i], labels[i], labelsSends[i] = GetHashKey(comp), comp, locale(comp)
        end
        table.insert(elements, {
          label  = locale(cat),
          type   = 'slider',
          name   = cat,
          min    = 1,
          max    = #items,
          value  = selectedCache[cat] and (function()
            for idx,v in ipairs(items) do if v==selectedCache[cat] then return idx end end
            return 1
          end)() or 1,
          hashes = hashes,
          labels = labels,
          labelsSends = labelsSends,
          id = a
        })
      end
    end

    if #elements == 0 then
        lib.notify({ title = locale('cl_notify_1'), description = locale('cl_notify_2'), type='error' })
        return
    end

    MenuData.Open('default', GetCurrentResourceName(), 'weapon_mat_menu', {
      title    = locale('cl_lang_3') .. ':',
      align    = 'top-left',
      elements = elements,
    }, function(data, menu)
        local sel = data.current
        if sel.hashes then
            local prev = selectedCache[sel.name] and GetHashKey(selectedCache[sel.name]) or nil
            local nxt  = sel.hashes[sel.value]
            applyWeaponComponent(wepObj, prev, nxt, wHash)
            selectedCache[sel.name] = sel.labels[sel.value]
            selectedLabels[sel.name] = sel.labelsSends[sel.value]  -- Almacena el label
            -- FocusCam(wepObj)
        end
    end, function(_, menu)
        menu.close()
        MainWeaponMenu(wname, wHash, serial, propid)
    end)
end

  -- Menu ENGRAVING (add _ENGRAVING y _ENGRAVING_MATERIAL)
local function OpenEngravingMenu(wname, wHash, serial, propid)
    local comps = GetAvailableComponents(wname, wHash)
    local elements = {}
    local a = 1

    for cat, items in pairs(comps) do
      if cat:find('_ENGRAVING') then
        local hashes, labels, labelsSends = {}, {}, {}
        for i, comp in ipairs(items) do
            hashes[i], labels[i], labelsSends[i] = GetHashKey(comp), comp, locale(comp)
        end
        table.insert(elements, {
          label  = locale(cat),
          type   = 'slider',
          name   = cat,
          min    = 1,
          max    = #items,
          value  = selectedCache[cat] and (function()
            for idx,v in ipairs(items) do if v==selectedCache[cat] then return idx end end
            return 1
          end)() or 1,
          hashes = hashes,
          labels = labels,
          labelsSends = labelsSends,
          id = a
        })
      end
    end

    if #elements == 0 then
        lib.notify({ title=locale('cl_notify_3'), description=locale('cl_notify_4'), type='error' })
        return
    end

    MenuData.Open('default', GetCurrentResourceName(), 'weapon_eng_menu', {
      title    = locale('cl_lang_4') ..':',
      align    = 'top-left',
      elements = elements,
    }, function(data, menu)
        local sel = data.current
        if sel.hashes then
            local prev = selectedCache[sel.name] and GetHashKey(selectedCache[sel.name]) or nil
            local nxt  = sel.hashes[sel.value]
            applyWeaponComponent(wepObj, prev, nxt, wHash)
            selectedCache[sel.name] = sel.labels[sel.value]
            selectedLabels[sel.name] = sel.labelsSends[sel.value]  -- Almacena el label
        end
    end, function(_, menu)
        menu.close()
        MainWeaponMenu(wname, wHash, serial, propid)
    end)
end

-- Menu TINTS
local function OpenTintsMenu(wname, wHash, serial, propid)
    local comps    = GetAvailableComponents(wname, wHash)
    local elements = {}

    -- Recolectamos solo categorÃ­as _TINT
    for cat, items in pairs(comps) do
        -- Melee grip tints remain hidden; firearm gunstock tints use the config toggle.
        if cat:find('_TINT$') and cat ~= 'GRIP_TINT'
            and (cat ~= 'GRIPSTOCK_TINT' or Config.GunstockTints == true)
        then
            local hashes, labels, labelsSends = {}, {}, {}
            for i, comp in ipairs(items) do
                hashes[i], labels[i], labelsSends[i] = GetHashKey(comp), comp, locale(comp)
            end
            table.insert(elements, {
                label  = locale(cat),
                type   = 'slider',
                name   = cat,
                min    = 1,
                max    = #items,
                value  = selectedCache[cat] and (function()
                    for idx, v in ipairs(items) do
                        if v == selectedCache[cat] then return idx end
                    end
                    return 1
                end)() or 1,
                hashes = hashes,
                labels = labels,
                labelsSends = labelsSends,
                id     = #elements + 1
            })
        end
    end

    if #elements == 0 then
        lib.notify({ title = locale('cl_notify_7'), description = locale('cl_notify_8'), type = 'error' })
        return
    end

    -- AquÃ­ cambio el ID a 'weapon_tint_menu'
    MenuData.Open('default', GetCurrentResourceName(), 'weapon_tint_menu', {
        title    = locale('cl_lang_5') .. ':',
        align    = 'top-left',
        elements = elements,
    }, function(data, menu)
        local sel = data.current
        if sel.hashes then
            local prev = selectedCache[sel.name] and GetHashKey(selectedCache[sel.name]) or nil
            local nxt  = sel.hashes[sel.value]
            -- local tintIndex = sel.value - 1  -- native usa 0-7
            -- applyWeaponTint(cache.ped, wHash, tintIndex)
            applyWeaponComponent(wepObj, prev, nxt, wHash)
            selectedCache[sel.name] = sel.labels[sel.value]
            selectedLabels[sel.name] = sel.labelsSends[sel.value]  -- Almacena el label
        end
    end, function(_, menu)
        menu.close()
        MainWeaponMenu(wname, wHash, serial, propid)
    end)
end

local function CalculateNewPrice(current, saved)
    local total = 0
    for cat, name in pairs(current or {}) do
        if saved[cat] ~= name then
            total = total + (Config.price[cat] or 0)
        end
    end
    return total
end

function MainWeaponMenu(wname, wHash, serial, propid)
    MenuData.CloseAll()
    TriggerEvent('HideAllUI')

    for cat, compName in pairs(selectedCache) do
        local compHash = GetHashKey(compName)
        applyWeaponComponent(wepObj, nil, compHash, wHash)
    end

    local buyPrice = CalculateNewPrice(selectedCache, savedComponents)
    local priceStr = string.format("%.2f", buyPrice)

    local el = {
        { label=locale('cl_lang_6'),  value='specific' },
        { label=locale('cl_lang_7'),  value='material' },
        { label=locale('cl_lang_8'),  value='engraving' },
        { label=locale('cl_lang_9'),  value='tints' },
        { label=locale('cl_lang_10') .. priceStr, value='buy' },
        { label=locale('cl_promp_1'), value='cancel' },
    }
    MenuData.Open('default', GetCurrentResourceName(), 'main_weapon_menu', {
        title    = locale('cl_lang_13'),
        align    = 'top-left',
        elements = el,
    }, function(data, menu)
        if data.current.value == 'specific' then
            OpenComponentMenu(wname, wHash, serial)

        elseif data.current.value == 'material' then
            OpenMaterialMenu(wname, wHash, serial)

        elseif data.current.value == 'engraving' then
            OpenEngravingMenu(wname, wHash, serial)

        elseif data.current.value == 'tints' then
            OpenTintsMenu(wname, wHash, serial)

        elseif data.current.value == 'buy' then
            if next(selectedCache) then
                local alert = lib.alertDialog({
                    header = locale('cl_lang_10') .. priceStr,
                    content = locale('sv_lang_12') .. priceStr,
                    centered = true,
                    cancel = true,
                    labels = {
                        confirm = locale('cl_lang_26'),
                        cancel = locale('cl_lang_27'),
                    },
                })
                if alert ~= 'confirm' then return end
                TriggerServerEvent('rsg-weaponcomp:server:setComponents',
                    wHash, serial, selectedCache, selectedLabels
                )
                menu.close()
            else
                lib.notify({ title=locale('cl_notify_10'), type="error" })
            end
        elseif data.current.value == 'packup' then
            TriggerEvent('rsg-weaponcomp:client:confirmpackup', propid)
            TriggerEvent('rsg-weaponcomp:client:ExitCam')
            selectedCache  = {}
            selectedLabels = {}
            savedComponents = {}
            menu.close()

        elseif data.current.value == 'cancel' then
            TriggerEvent('rsg-weaponcomp:client:ExitCam')
            selectedCache  = {}
            selectedLabels = {}
            savedComponents = {}
            menu.close()
        end
    end, function(_, menu)
        TriggerEvent('rsg-weaponcomp:client:ExitCam')
        selectedCache  = {}
        selectedLabels = {}
        savedComponents = {}
        menu.close()
    end)
end

----------------------------------------
-- START CUSTOM EVENT

local NUIComponentOrder = {
    'BARREL', 'GRIP', 'SIGHT', 'CLIP', 'MAG', 'STOCK', 'TUBE', 'SCOPE', 'WRAP',
    'TORCH_MATCHSTICK', 'BARREL_RIFLING', 'FRAME_VERTDATA',
    'FRAME_MATERIAL', 'BARREL_MATERIAL', 'CYLINDER_MATERIAL', 'TRIGGER_MATERIAL',
    'HAMMER_MATERIAL', 'SIGHT_MATERIAL', 'GRIP_MATERIAL', 'WRAP_MATERIAL',
    'FRAME_ENGRAVING', 'BARREL_ENGRAVING', 'CYLINDER_ENGRAVING',
    'GRIPSTOCK_ENGRAVING', 'MELEE_BLADE_ENGRAVING',
    'FRAME_ENGRAVING_MATERIAL', 'BARREL_ENGRAVING_MATERIAL',
    'CYLINDER_ENGRAVING_MATERIAL', 'MELEE_BLADE_ENGRAVING_MATERIAL',
    'BARREL_TINT', 'CYLINDER_TINT', 'TRIGGER_TINT', 'GRIPSTOCK_TINT', 'WRAP_TINT',
}

local function IsRemovableComponent(component)
    return type(component) == 'string' and (component == 'WRAP'
        or component == 'SCOPE'
        or component == 'GRIP_MATERIAL'
        or component == 'BARREL_RIFLING'
        or component == 'FRAME_VERTDATA'
        or component:find('_ENGRAVING', 1, true) ~= nil)
end

local function NormalizeStyleOption(category, component)
    local removable = {
        part = true,
        color = true,
        material = true,
        tint = true,
        metal = true,
        engraving = true,
    }
    for word in tostring(category or ''):lower():gmatch('[^_]+') do
        removable[word] = true
    end
    for _, word in ipairs((Config.MetalList and Config.MetalList[category]) or {}) do
        removable[tostring(word):lower()] = true
    end

    local words = {}
    local label = tostring(locale(component) or component):lower():gsub('[^%w]+', ' ')
    for word in label:gmatch('%S+') do
        words[#words + 1] = word
    end
    while #words > 1 and removable[words[1]] do
        table.remove(words, 1)
    end
    return table.concat(words, ' ')
end

local function ResolveStyleComponent(category, component, items)
    if type(component) ~= 'string' or type(items) ~= 'table' then return nil end
    for _, candidate in ipairs(items) do
        if candidate == component then return candidate end
    end

    local wanted = NormalizeStyleOption(category, component)
    if wanted == '' then return nil end
    for _, candidate in ipairs(items) do
        if NormalizeStyleOption(category, candidate) == wanted then
            return candidate
        end
    end
end

local function BuildNUIData()
    local groups = {
        { key = 'specific', label = locale('cl_lang_2'), components = Config.Specific[nuiContext.wname] or {} },
        { key = 'material', label = locale('cl_lang_3'), components = {} },
        { key = 'engraving', label = locale('cl_lang_4'), components = {} },
        { key = 'tints', label = locale('cl_lang_5'), components = {} },
    }
    local available = GetAvailableComponents(nuiContext.wname, nuiContext.wHash)
    for cat, items in pairs(available) do
        if cat:find('_MATERIAL$') and not cat:find('_ENGRAVING_MATERIAL$') then
            groups[2].components[cat] = items
        elseif cat:find('_ENGRAVING') then
            groups[3].components[cat] = items
        elseif cat:find('_TINT$') and cat ~= 'GRIP_TINT'
            and (cat ~= 'GRIPSTOCK_TINT' or Config.GunstockTints == true)
        then
            groups[4].components[cat] = items
        end
    end
    local result = {
        categories = {},
        styles = {},
        metalList = Config.MetalList or {},
        price = string.format('%.2f', CalculateNewPrice(selectedCache, savedComponents)),
        cameraZoom = cameraOrbit.zoom,
        canPickup = canPickupAllowed,
    }
    for _, group in ipairs(groups) do
        local category = { key = group.key, label = group.label, count = 0, groups = {} }
        local added = {}
        local function addComponentGroup(component, items)
            if not items or #items == 0 or added[component] then return end
            added[component] = true
            local removable = IsRemovableComponent(component)
            local offset = removable and 1 or 0
            local componentGroup = { key = component, label = locale(component), count = #items + offset, currentIndex = 1, options = {} }
            if removable then
                componentGroup.options[1] = { component = component, index = 1, label = 'None', remove = true, current = selectedCache[component] == nil }
            end
            for index, name in ipairs(items) do
                local isCurrent = selectedCache[component] == name
                local menuIndex = index + offset
                if isCurrent then componentGroup.currentIndex = menuIndex end
                componentGroup.options[#componentGroup.options + 1] = { component = component, index = menuIndex, label = locale(name), current = isCurrent }
            end
            category.groups[#category.groups + 1] = componentGroup
            category.count = category.count + 1
        end
        for _, component in ipairs(NUIComponentOrder) do
            addComponentGroup(component, group.components[component])
        end
        local remaining = {}
        for component in pairs(group.components) do
            if not added[component] then remaining[#remaining + 1] = component end
        end
        table.sort(remaining)
        for _, component in ipairs(remaining) do
            addComponentGroup(component, group.components[component])
        end
        if category.count > 0 then result.categories[#result.categories + 1] = category end
    end
    local available = GetAvailableComponents(nuiContext.wname, nuiContext.wHash)
    for _, style in ipairs(savedStyles) do
        local compatible, unsupported, invalid = 0, 0, 0
        for category, entry in pairs(style.components or {}) do
            local items = available[category]
            if not items then
                unsupported = unsupported + 1
            elseif entry.action == 'remove' and IsRemovableComponent(category) then
                compatible = compatible + 1
            elseif entry.action == 'set' then
                if ResolveStyleComponent(category, entry.component, items) then
                    compatible = compatible + 1
                else
                    invalid = invalid + 1
                end
            else
                invalid = invalid + 1
            end
        end
        result.styles[#result.styles + 1] = {
            id = style.id,
            name = style.name,
            compatible = compatible,
            unsupported = unsupported,
            invalid = invalid,
        }
    end
    return result
end

local function RefreshSavedStyles(done)
    RSGCore.Functions.TriggerCallback('rsg-weaponcomp:server:getStyles', function(styles)
        savedStyles = type(styles) == 'table' and styles or {}
        if done then done() end
    end)
end

local function BuildCurrentStyleEntries()
    if not nuiContext then return {} end
    local available = GetAvailableComponents(nuiContext.wname, nuiContext.wHash)
    local entries = {}
    for category in pairs(available) do
        if selectedCache[category] then
            entries[category] = { action = 'set', component = selectedCache[category] }
        elseif IsRemovableComponent(category) then
            entries[category] = { action = 'remove' }
        end
    end
    return entries
end

local function FindSavedStyle(styleId)
    styleId = tonumber(styleId)
    for _, style in ipairs(savedStyles) do
        if tonumber(style.id) == styleId then return style end
    end
end

local function RefreshStylesNUI(message)
    RefreshSavedStyles(function()
        if message then lib.notify({ title = 'Saved Styles', description = message, type = 'success' }) end
        if nuiContext and WeaponCompNUI then WeaponCompNUI.Update(BuildNUIData()) end
    end)
end

local function CloseNUIAndExit()
    if WeaponCompNUI then WeaponCompNUI.Close() end
    TriggerEvent('rsg-weaponcomp:client:ExitCam')
    selectedCache, selectedLabels, savedComponents, removedComponents, savedStyles, nuiContext = {}, {}, {}, {}, {}, nil
    canPickupAllowed = false
end

function MainWeaponMenu(wname, wHash, serial, propid)
    nuiContext = { wname = wname, wHash = wHash, serial = serial, propid = propid }
    MenuData.CloseAll()
    TriggerEvent('HideAllUI')
    for _, compName in pairs(selectedCache) do applyWeaponComponent(wepObj, nil, GetHashKey(compName), wHash) end
    WeaponCompNUI.Open(BuildNUIData())
end

RegisterNetEvent('rsg-weaponcomp:client:nuiSelect', function(data)
    if not nuiContext or not data.component or not data.index then return end
    local groups = { specific = Config.Specific[nuiContext.wname] or {}, material = {}, engraving = {}, tints = {} }
    local available = GetAvailableComponents(nuiContext.wname, nuiContext.wHash)
    for cat, items in pairs(available) do
        if cat:find('_MATERIAL$') and not cat:find('_ENGRAVING_MATERIAL$') then groups.material[cat] = items
        elseif cat:find('_ENGRAVING') then groups.engraving[cat] = items
        elseif cat:find('_TINT$') and cat ~= 'GRIP_TINT'
            and (cat ~= 'GRIPSTOCK_TINT' or Config.GunstockTints == true)
        then groups.tints[cat] = items end
    end
    local items = groups[data.group] and groups[data.group][data.component]
    if not items then return end
    local removable = IsRemovableComponent(data.component)
    local previous = selectedCache[data.component] and GetHashKey(selectedCache[data.component]) or nil
    if removable and data.index == 1 then
        if previous then RemoveWeaponComponentFromWeaponObject(wepObj, previous) end
        selectedCache[data.component] = nil
        selectedLabels[data.component] = nil
        removedComponents[data.component] = true
        WeaponCompNUI.Update(BuildNUIData())
        return
    end
    local itemIndex = data.index - (removable and 1 or 0)
    if not items[itemIndex] then return end
    local nextName = items[itemIndex]
    applyWeaponComponent(wepObj, previous, GetHashKey(nextName), nuiContext.wHash)
    selectedCache[data.component], selectedLabels[data.component] = nextName, locale(nextName)
    removedComponents[data.component] = nil
    WeaponCompNUI.Update(BuildNUIData())
end)

RegisterNetEvent('rsg-weaponcomp:client:nuiBuy', function()
    if not nuiContext or (not next(selectedCache) and not next(removedComponents)) then
        return lib.notify({ title = locale('cl_notify_10'), type = 'error' })
    end
    TriggerServerEvent('rsg-weaponcomp:server:setComponents', nuiContext.wHash, nuiContext.serial, selectedCache, selectedLabels, removedComponents)
    CloseNUIAndExit()
end)

RegisterNetEvent('rsg-weaponcomp:client:nuiPickup', function()
    if not nuiContext or not canPickupAllowed then return end

    local propid = nuiContext.propid
    CloseNUIAndExit()
    TriggerEvent('rsg-weaponcomp:client:confirmpackup', propid)
end)

RegisterNetEvent('rsg-weaponcomp:client:nuiClose', CloseNUIAndExit)
RegisterNetEvent('rsg-weaponcomp:client:nuiBack', function() end)

RegisterNetEvent('rsg-weaponcomp:client:nuiStyleLoad', function(data)
    if not nuiContext then return end
    local style = FindSavedStyle(data.id)
    if not style then return end
    local available = GetAvailableComponents(nuiContext.wname, nuiContext.wHash)
    local applied, skipped = 0, 0
    for category, entry in pairs(style.components or {}) do
        local items = available[category]
        if not items then
            skipped = skipped + 1
        elseif entry.action == 'remove' and IsRemovableComponent(category) then
            local previous = selectedCache[category] and GetHashKey(selectedCache[category]) or nil
            if previous then RemoveWeaponComponentFromWeaponObject(wepObj, previous) end
            selectedCache[category], selectedLabels[category] = nil, nil
            removedComponents[category] = true
            applied = applied + 1
        elseif entry.action == 'set' then
            local resolvedComponent = ResolveStyleComponent(category, entry.component, items)
            if resolvedComponent then
                local previous = selectedCache[category] and GetHashKey(selectedCache[category]) or nil
                applyWeaponComponent(wepObj, previous, GetHashKey(resolvedComponent), nuiContext.wHash)
                selectedCache[category], selectedLabels[category] = resolvedComponent, locale(resolvedComponent)
                removedComponents[category] = nil
                applied = applied + 1
            else
                skipped = skipped + 1
            end
        else
            skipped = skipped + 1
        end
    end
    WeaponCompNUI.Update(BuildNUIData())
    lib.notify({ title = 'Saved Styles', description = ('Applied %d groups, skipped %d'):format(applied, skipped), type = applied > 0 and 'success' or 'error' })
end)

RegisterNetEvent('rsg-weaponcomp:client:nuiStyleCreate', function(data)
    local entries = BuildCurrentStyleEntries()
    RSGCore.Functions.TriggerCallback('rsg-weaponcomp:server:createStyle', function(success, message)
        if not success then return lib.notify({ title = 'Saved Styles', description = message or 'Unable to save style', type = 'error' }) end
        RefreshStylesNUI('Style saved')
    end, data.name, entries)
end)

RegisterNetEvent('rsg-weaponcomp:client:nuiStyleUpdate', function(data)
    local entries = BuildCurrentStyleEntries()
    RSGCore.Functions.TriggerCallback('rsg-weaponcomp:server:updateStyle', function(success, message)
        if not success then return lib.notify({ title = 'Saved Styles', description = message or 'Unable to update style', type = 'error' }) end
        RefreshStylesNUI('Style updated')
    end, data.id, entries)
end)

RegisterNetEvent('rsg-weaponcomp:client:nuiStyleAddMissing', function(data)
    local entries = BuildCurrentStyleEntries()
    RSGCore.Functions.TriggerCallback('rsg-weaponcomp:server:addMissingStyle', function(success, added)
        if not success then return lib.notify({ title = 'Saved Styles', description = added or 'Unable to add style groups', type = 'error' }) end
        RefreshStylesNUI(('%d missing groups added'):format(tonumber(added) or 0))
    end, data.id, entries)
end)

RegisterNetEvent('rsg-weaponcomp:client:nuiStyleRemove', function(data)
    local style = FindSavedStyle(data.id)
    if not style then return end
    RSGCore.Functions.TriggerCallback('rsg-weaponcomp:server:removeStyle', function(success)
        if not success then return lib.notify({ title = 'Saved Styles', description = 'Unable to remove style', type = 'error' }) end
        RefreshStylesNUI('Style removed')
    end, data.id)
end)

local function UpdateOrbitCamera()
    if not camera or not wepObj then return end
    local target = GetEntityCoords(wepObj)
    local yaw, pitch = math.rad(cameraOrbit.yaw), math.rad(cameraOrbit.pitch)
    local horizontal = cameraOrbit.radius * math.cos(pitch)
    SetCamCoord(camera, target.x + horizontal * math.cos(yaw), target.y + horizontal * math.sin(yaw), target.z + cameraOrbit.radius * math.sin(pitch))
    PointCamAtCoord(camera, target.x, target.y, target.z)
end

RegisterNetEvent('rsg-weaponcomp:client:nuiPivot', function(data)
    if not camera or not wepObj then return end
    cameraOrbit.yaw = cameraOrbit.yaw - (tonumber(data.dx) or 0.0) * 0.35
    cameraOrbit.pitch = math.clamp(cameraOrbit.pitch + (tonumber(data.dy) or 0.0) * 0.25, -55.0, 65.0)
    UpdateOrbitCamera()
end)

RegisterNetEvent('rsg-weaponcomp:client:nuiZoom', function(data)
    if not camera or not wepObj then return end
    cameraOrbit.zoom = math.clamp(tonumber(data.zoom) or 50, 0, 100)
    local normalized = cameraOrbit.zoom / 100.0
    cameraOrbit.radius = cameraOrbit.baseRadius * (1.35 - (normalized * 0.75))
    SetCamFov(camera, 85.0 - (normalized * 55.0))
    UpdateOrbitCamera()
end)
----------------------------------------
RegisterNetEvent('rsg-weaponcomp:client:startcustom', function(propid, wHash, serial, weaponName)
    if isBusy then return end
    isBusy = true
    removedComponents = {}

    local propData = SpawnedProps[propid]
    if not propData then isBusy = false; return end
    local propObj = propData.obj
    local coords = GetEntityCoords(propObj)
    spawnWeaponOnProp(propObj, coords, wHash)
    FreezePlayer()
    Wait(500)

    RSGCore.Functions.TriggerCallback('rsg-weaponcomp:server:getPlayerWeaponComponents', function(result)
        local comps = result and result.components or {}
        local labels = result and result.labels or {}
        savedComponents = {}
        if next(comps) then
            for cat, compName in pairs(comps) do
                selectedCache[cat] = compName
                selectedLabels[cat] = labels[cat] or compName
                savedComponents[cat] = compName
                local compHash = GetHashKey(compName)
                if compHash ~= 0 then
                    applyWeaponComponent(wepObj, nil, compHash, wHash)
                end
            end
            if Config.Debug then
                print(('[%s] Loaded saved components for serial %s'):format(GetCurrentResourceName(), serial))
                print(('[%s]   components: %s'):format(GetCurrentResourceName(), json.encode(selectedCache)))
                print(('[%s]   labels: %s'):format(GetCurrentResourceName(), json.encode(selectedLabels)))
            end
        else
            if Config.Debug then
                print(('[%s] No saved components for serial %s, applying defaults'):format(GetCurrentResourceName(), serial))
            end
            applyDefaults(wepObj, wHash)
        end

        StartCamOnWeapon(wepObj, Config.distFov)
        StartPromptThread()
        RefreshSavedStyles(function()
            RSGCore.Functions.TriggerCallback('rsg-weaponcomp:server:canPickupProp', function(allowed)
                canPickupAllowed = allowed == true
                MainWeaponMenu(weaponName, wHash, serial, propid)
                isBusy = false
            end)
        end)
    end, serial)
end)

--------------------------
-- Spawn & track existing props + zones + targets
----------------------------
Citizen.CreateThread(function()
    while true do
        Wait(500)
        local ped = cache.ped or PlayerPedId()
        local pos = GetEntityCoords(ped)
        local inRange = false
        if not Config.PlayerProps then Wait(5000); goto continue end
        for k, v in ipairs(Config.PlayerProps) do
            if #(pos - vector3(v.x,v.y,v.z)) < 50.0 then
                inRange = true
                if not SpawnedProps[v.propid] and not PackingUpProps[v.propid] then
                    local m = joaat(v.propmodel)
                    lib.requestModel(m)
                    local obj = CreateObject(m, v.x, v.y, v.z, false, true, true)
                    SetEntityHeading(obj, v.h)
                    FreezeEntityPosition(obj, true)

                    local propConfig = Config.PlayerProps[k]

                    if Config.gunZoneActive then
                        gunZones[v.propid] = lib.zones.sphere({
                            coords = vec3(propConfig.x, propConfig.y, propConfig.z),
                            radius = Config.gunZoneSize,
                            debug = false,
                            onEnter = function()
                                ingunZone = true
                                if propConfig.item == Config.Gunsmithitem then
                                    if Config.showTextZone then
                                        lib.showTextUI(tostring(propConfig.gunsitename))
                                    end
                                end
                            end,
                            onExit = function()
                                ingunZone = false
                                if Config.showTextZone then
                                    lib.hideTextUI()
                                end
                            end
                        })
                    end
                    exports.ox_target:addLocalEntity(obj, {
                        {
                            name     = 'gunsite_prop',
                            icon     = 'far fa-eye',
                            label    = locale('cl_lang_14'),
                            onSelect = function()
                                local wHash = GetPedCurrentHeldWeapon(PlayerPedId())
                                if wHash == `WEAPON_UNARMED` then
                                    return lib.notify({ title = locale('cl_notify_13'), description=locale('cl_notify_14'), type='error' })
                                end
                                local serial = exports['rsg-weapons']:weaponInHands()[wHash]
                                local weaponName = Citizen.InvokeNative(0x89CF5FF3D363311E, wHash, Citizen.ResultAsString())
                                if not serial then
                                    return lib.notify({ title = locale('cl_notify_13'), description=locale('cl_notify_14'), type='error' })
                                end
                                TriggerEvent('rsg-weaponcomp:client:startcustom', v.propid, wHash, serial, weaponName)
                            end,
                            distance = 2.0
                        },
                    })

                    SpawnedProps[v.propid] = { obj = obj }
                end
            end
        end

        if not inRange then Wait(5000) end
        ::continue::
    end
end)

-- update props
RegisterNetEvent('rsg-weaponcomp:client:updatePropData')
AddEventHandler('rsg-weaponcomp:client:updatePropData', function(data)
    Config.PlayerProps = data
end)

-- setup new gunsite
RegisterNetEvent('rsg-weaponcomp:client:setupgunzone')
AddEventHandler('rsg-weaponcomp:client:setupgunzone', function(propmodel, item, coords, heading)
    RSGCore.Functions.TriggerCallback('rsg-weaponcomp:server:countprop', function(result)
        -- distance check
        local playercoords = GetEntityCoords(cache.ped)
        if #(playercoords - coords) > Config.PlaceDistance then
            lib.notify({ title = locale('cl_lang_15'), description = locale('cl_lang_16'), type = 'error', duration = 5000 })
            return
        end
        -- check gunsites
        if result >= Config.MaxGunsites then
            lib.notify({ title = locale('cl_lang_17'), description = locale('cl_lang_18'), type = 'error', duration = 7000 })
            return
        end
        -- check guning zone
        if ingunZone then
            lib.notify({ title = locale('cl_lang_19'), description = locale('cl_lang_20'), type = 'error', duration = 7000 })
            return
        end
        -- check not in town and other props
        if not CanPlacePropHere(coords) then
            lib.notify({ title = locale('cl_lang_21'), description = locale('cl_lang_22'), type = 'error', duration = 7000 })
            return
        end
        if not IsPedInAnyVehicle(cache.ped, false) and not isBusy then
            isBusy = true
            local anim1 = `WORLD_HUMAN_STAND_WAITING`
            FreezeEntityPosition(cache.ped, true)
            TaskStartScenarioInPlace(cache.ped, anim1, 0, true)
            Wait(10000)
            ClearPedTasks(cache.ped)
            FreezeEntityPosition(cache.ped, false)
            TriggerServerEvent('rsg-weaponcomp:server:createnewprop', propmodel, item, coords, heading)
            isBusy = false
            return
        end
    end, item)
end)

-- confirm gunsite packup
RegisterNetEvent('rsg-weaponcomp:client:confirmpackup', function(propid)
    local alert = lib.alertDialog({
        header = locale('cl_lang_23'),
        content = locale('cl_lang_25'),
        centered = true,
        cancel = true,
        labels = {
            confirm = locale('cl_lang_26'),
            cancel = locale('cl_lang_27'),
        },
    })
    if alert ~= 'confirm' then return end

    LocalPlayer.state:set('inv_busy', true, true)
    lib.progressBar({
        duration = 10000,
        position = 'bottom',
        useWhileDead = false,
        canCancel = false,
        disableControl = true,
        disable = {
            move = true,
            mouse = false,
        },
        label = locale('cl_lang_28'),
    })

    LocalPlayer.state:set('inv_busy', false, true)
    TriggerEvent('rsg-weaponcomp:client:packupgunsite', propid)
end)

-- packup gunsite
RegisterNetEvent('rsg-weaponcomp:client:packupgunsite', function(propid)

    TriggerServerEvent('rsg-weaponcomp:server:removegunsiteprops', propid)

    PackingUpProps[propid] = true
    local propData = SpawnedProps[propid]
    if propData and DoesEntityExist(propData.obj) then
        SetEntityAsMissionEntity(propData.obj, true, true)
        DeleteObject(propData.obj)
        Wait(100)
    end
    SpawnedProps[propid] = nil
    if Config.gunZoneActive then
        if gunZones[propid] then
            gunZones[propid]:remove()
            gunZones[propid] = nil
        end

        if Config.showTextZone then
            lib.hideTextUI()
        end
        ingunZone = false
    end
    PackingUpProps[propid] = false
    TriggerServerEvent('rsg-weaponcomp:server:additem')
end)

---------------------------------------------
-- Request prop data on resource start (handles late-join after server restart)
---------------------------------------------
AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    TriggerServerEvent('rsg-weaponcomp:server:requestPropData')
end)

---------------------------------------------
-- clean up
---------------------------------------------
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end

    DestroyAllCams(true)
    if camera then DestroyCam(camera,true) end
    MenuData.CloseAll()

    if wepObj ~= nil and DoesEntityExist(wepObj) then
        SetEntityAsMissionEntity(wepObj, false)
        FreezeEntityPosition(wepObj, false)
        DeleteObject(wepObj)
    end

    for k, v in pairs(SpawnedProps) do
        local props = SpawnedProps[k].obj
        SetEntityAsMissionEntity(props, false)
        FreezeEntityPosition(props, false)
        DeleteObject(props)
    end

    SpawnedProps   = {}        -- [propid] = { obj }
    PackingUpProps = {}

    if Config.gunZoneActive then
        ingunZone      = false
        gunZones       = {}
        if Config.showTextZone then lib.hideTextUI() end
    end

    promptThreadActive = false
    ClearCameraPrompts()
    isBusy         = false
    camera         = nil

    selectedCache  = {}
    selectedLabels = {}
    savedComponents = {}
    removedComponents = {}
    savedStyles = {}
end)
