local RSGCore = exports['rsg-core']:GetCoreObject()
lib.locale()

local STATE_MACHINE = -813354801
local HUD_CTX_INSPECT_ITEM = joaat('HUD_CTX_INSPECT_ITEM')
local BB_CLEAN_PROMPT = 'GENERIC_WEAPON_CLEAN_PROMPT_AVAILABLE'
local INPUT_NEXT_CAMERA = joaat('INPUT_NEXT_CAMERA')
local INPUT_CONTEXT_LT = joaat('INPUT_CONTEXT_LT')
local INPUT_CONTEXT_X = joaat('INPUT_CONTEXT_X')
local INPUT_QUICK_SELECT_INSPECT = joaat('INPUT_QUICK_SELECT_INSPECT')
local HUD_QUICK_SELECT = joaat('hud_quick_select')
local WEAPON_UNARMED = joaat('WEAPON_UNARMED')

local running = false
local uiContainer = nil

local function inv(hash, ...)
    return Citizen.InvokeNative(hash, ...)
end

local function InventoryGetGuidFromItemId(inventoryId, itemDataBuffer, category, slotId, outItemBuffer)
    return inv(0x886DFD3E185C8A89, inventoryId, itemDataBuffer, category, slotId, outItemBuffer)
end

local function SetWeaponDegradation(weaponObject, value)
    inv(0xA7A57E89E965D839, weaponObject, value, 0.0)
end

local function SetWeaponDamage(weaponObject, value)
    inv(0xE22060121602493B, weaponObject, value, false)
end

local function SetWeaponDirt(weaponObject, value)
    inv(0x812CE61DEBCAB948, weaponObject, value, false)
end

local function SetWeaponSoot(weaponObject, value)
    inv(0xA9EF4AD10BDDDB57, weaponObject, value, false)
end

local function DisableInspectControl(control)
    inv(0xFE99B66D079CF6BC, 0, control, true)
end

local function IsPedRunningInspectionTask(ped)
    return inv(0x038B1F1674F0E242, ped)
end

local function SetPedBlackboardBool(ped, name, value)
    inv(0xCB9401F918CB0F75, ped, name, value, -1)
end

local function GetWeaponDamage(weaponObject)
    return inv(0x904103D5D2333977, weaponObject, Citizen.ResultAsFloat())
end

local function GetWeaponDirt(weaponObject)
    return inv(0x810E8AE9AFEA7E54, weaponObject, Citizen.ResultAsFloat())
end

local function GetWeaponSoot(weaponObject)
    return inv(0x4BF66F8878F67663, weaponObject, Citizen.ResultAsFloat())
end

local function GetWeaponDegradation(weaponObject)
    return inv(0x0D78E1097F89E637, weaponObject, Citizen.ResultAsFloat())
end

local function GetWeaponPermanentDegradation(weaponObject)
    return inv(0xD56E5F336C675EFA, weaponObject, Citizen.ResultAsFloat())
end

local function GetWeaponName(weaponHash)
    return inv(0x89CF5FF3D363311E, weaponHash, Citizen.ResultAsString())
end

local function GetWeaponNameWithPermanentDegradation(weaponHash, value)
    return inv(0x7A56D66C78D8EF8E, weaponHash, value, Citizen.ResultAsString())
end

local function IsEntityDeadNative(entity)
    return inv(0x7D5B1F88E7504BBA, entity)
end

local function IsPedSwimmingNative(ped)
    return inv(0x9DE327631295B4C2, ped)
end

local function IsWeaponOneHanded(hash)
    return inv(0xD955FEE4B87AFA07, hash)
end

local function IsWeaponTwoHanded(hash)
    return inv(0x0556E9D2ECF39D01, hash)
end

local function GetObjectIndexFromEntityIndex(entity)
    return inv(0x280BBE5601EAA983, entity)
end

local function GetCurrentPedWeaponEntityIndex(ped, attachPoint)
    return inv(0x3B390A939AF0B5FC, ped, attachPoint)
end

local function GetItemInteractionFromPed(ped)
    return inv(0x6AA3DCA2C6F5EB6D, ped)
end

local function GetControlProgress(ped)
    return inv(0xBC864A70AD55E0C1, ped, INPUT_CONTEXT_X, Citizen.ResultAsFloat())
end

local function GetWheelHighlightedItem()
    return inv(0x9C409BBC492CB5B1)
end

local function clamp(value)
    if not value or value < 0.0 then return 0.0 end
    if value > 1.0 then return 1.0 end
    return value
end

local function getGuidFromItemId(inventoryId, itemData, category, slotId)
    local outItem = DataView.ArrayBuffer(256)
    local itemBuffer = itemData and itemData:Buffer() or 0
    local success = InventoryGetGuidFromItemId(inventoryId, itemBuffer, category, slotId, outItem:Buffer())
    return success and outItem or nil
end

local function getWeaponStruct(weaponHash)
    local charStruct = getGuidFromItemId(1, nil, joaat('CHARACTER'), -1591664384)
    if not charStruct then return nil end

    local inventoryStruct = getGuidFromItemId(1, charStruct, 923904168, -740156546)
    if not inventoryStruct then return nil end

    return getGuidFromItemId(1, inventoryStruct, weaponHash, -1591664384)
end

local function getWeaponConditionText(weaponObject)
    local degradation = GetWeaponDegradation(weaponObject)
    local permanent = GetWeaponPermanentDegradation(weaponObject)

    if degradation == 0.0 then
        return GetStringFromHashKey(1803343570)
    elseif permanent > 0.0 and degradation == permanent then
        return GetStringFromHashKey(-1933427003)
    end

    return GetStringFromHashKey(-54957657)
end

local function getWeaponDisplayName(weaponHash, weaponObject)
    local permanent = GetWeaponPermanentDegradation(weaponObject)
    local name = permanent > 0.0
        and GetWeaponNameWithPermanentDegradation(weaponHash, permanent)
        or GetWeaponName(weaponHash)

    return name and name ~= '' and joaat(name) or weaponHash
end

local function updateWeaponStats(player, container, weaponHash, weaponObject)
    if not Config.showStats then return end

    local weaponStruct = getWeaponStruct(weaponHash)
    if not weaponStruct then return end

    inv(0x46DB71883EE9D5AF, container, 'stats', weaponStruct:Buffer(), player)
    DatabindingAddDataHash(container, 'itemLabel', getWeaponDisplayName(weaponHash, weaponObject))
    DatabindingAddDataString(container, 'tipText', getWeaponConditionText(weaponObject))
end

local function cleanup()
    local ped = cache.ped

    pcall(function()
        SetPedBlackboardBool(ped, BB_CLEAN_PROMPT, 0)
    end)

    pcall(function()
        inv(0x4EB122210A90E2D8, STATE_MACHINE)
    end)

    if uiContainer then
        pcall(function()
            DatabindingRemoveDataEntry(uiContainer)
        end)
    end

    pcall(function()
        inv(0x8BC7C1F929D07BF3, HUD_CTX_INSPECT_ITEM)
    end)

    uiContainer = nil
end

local function initialize(player, weaponHash, weaponObject)
    if not Config.showStats then return nil, nil end

    local uiFlowBlock = RequestFlowBlock(joaat('PM_FLOW_WEAPON_INSPECT'))
    uiContainer = DatabindingAddDataContainerFromPath('', 'ItemInspection')

    DatabindingAddDataBool(uiContainer, 'Visible', true)
    updateWeaponStats(player, uiContainer, weaponHash, weaponObject)
    inv(0x4CC5F2FC1332577F, HUD_CTX_INSPECT_ITEM)

    return uiFlowBlock, uiContainer
end

local function shouldContinue(player)
    if IsEntityDeadNative(player) then
        return false
    elseif IsPedSwimmingNative(player) then
        ClearPedTasks(player, true, false)
        return false
    elseif not IsPedRunningInspectionTask(player) then
        return false
    end

    return true
end

local function toggleCleanPrompt(player, weaponObject, hasGunOil)
    local degradation = GetWeaponDegradation(weaponObject)
    local permanent = GetWeaponPermanentDegradation(weaponObject)
    local canClean = hasGunOil and degradation ~= 0.0 and degradation > permanent

    SetPedBlackboardBool(player, BB_CLEAN_PROMPT, canClean and 1 or 0)
end

local function cleanWeaponObject(weaponObject)
    local permanent = GetWeaponPermanentDegradation(weaponObject)

    SetWeaponDegradation(weaponObject, permanent)
    SetWeaponDamage(weaponObject, permanent)
    SetWeaponDirt(weaponObject, 0.0)
    SetWeaponSoot(weaponObject, 0.0)
end

local function createStateMachine(uiFlowBlock)
    if not uiFlowBlock or not inv(0x10A93C057B6BD944, uiFlowBlock) then
        return 0
    end

    inv(0x3B7519720C9DCB45, uiFlowBlock, 0)

    if not inv(0x5D15569C0FEBF757, STATE_MACHINE) then
        if not inv(0x4C6F2C4B7A03A266, STATE_MACHINE, uiFlowBlock) then
            return 0
        end
    end

    return 1
end

local function getInspectInteraction(weaponHash)
    if IsWeaponOneHanded(weaponHash) then
        return joaat('SHORTARM_HOLD_ENTER')
    elseif IsWeaponTwoHanded(weaponHash) then
        return joaat('LONGARM_HOLD_ENTER')
    end

    return nil
end

local function isCleanEnter(player)
    local interaction = GetItemInteractionFromPed(player)
    return interaction == joaat('LONGARM_CLEAN_ENTER')
        or interaction == joaat('SHORTARM_CLEAN_ENTER')
end

local function isCleanExit(player)
    local interaction = GetItemInteractionFromPed(player)
    return interaction == joaat('LONGARM_CLEAN_EXIT')
        or interaction == joaat('SHORTARM_CLEAN_EXIT')
end

local function getCleanItem()
    return Config.CleanItem or Config.RepairItem or 'gun_oil'
end

local function buildCleanCallbacks(weaponHash)
    return {
        onCleanStart = function()
            local cleanItem = getCleanItem()
            if not RSGCore.Functions.HasItem(cleanItem) then
                return false
            end

            if GetResourceState('rsg-weapons') ~= 'started' then
                return false
            end

            local serial = exports['rsg-weapons']:weaponInHands()[weaponHash]
            if not serial then return false end

            local ok, consumed = pcall(function()
                return lib.callback.await('rsg-weapons:server:consumeGunOil', false, serial)
            end)
            if ok and consumed then
                return true
            end

            TriggerServerEvent('rsg-weapons:server:removeitem', cleanItem, 1)
            return true
        end,
        onCleanComplete = function(weaponObject)
            local serial = exports['rsg-weapons']:weaponInHands()[weaponHash]
            if not serial then return end

            local permanent = GetWeaponPermanentDegradation(weaponObject)
            local cleanedQuality = math.floor((1.0 - permanent) * 10000 + 0.5) / 100
            TriggerServerEvent('rsg-weapons:server:syncCleanedWeapon', serial, cleanedQuality)
        end,
    }
end

local function ensureWeaponEquipped(ped, weaponHash)
    local _, currentWeapon = GetCurrentPedWeapon(ped, true, 0, true)
    if currentWeapon == weaponHash then return true end

    SetCurrentPedWeapon(ped, weaponHash, true, 0, false, false)

    local timeout = GetGameTimer() + 1500
    while GetGameTimer() < timeout do
        local _, equipped = GetCurrentPedWeapon(ped, true, 0, true)
        if equipped == weaponHash then
            return true
        end
        Wait(0)
    end

    return false
end

local function startWeaponInspection(hasCleanItem, cleanCallbacks, weaponHashOverride)
    if not Config.showStats then return false end

    if running then
        return false
    end

    if not DataView then
        return false
    end

    running = true

    local ok = pcall(function()
        local player = cache.ped
        local weaponHash = weaponHashOverride

        if not weaponHash then
            local hasWeapon
            hasWeapon, weaponHash = GetCurrentPedWeapon(player, true, 0, true)
            if not hasWeapon or not weaponHash or weaponHash == 0 or weaponHash == WEAPON_UNARMED then
                lib.notify({
                    title = locale('cl_notify_13'),
                    description = locale('cl_notify_14'),
                    type = 'error',
                })
                return
            end
        end

        local interaction = getInspectInteraction(weaponHash)
        if not interaction then
            lib.notify({
                title = locale('cl_notify_13'),
                description = locale('cl_notify_14'),
                type = 'error',
            })
            return
        end

        if not ensureWeaponEquipped(player, weaponHash) then
            lib.notify({
                title = locale('cl_notify_13'),
                description = locale('cl_notify_14'),
                type = 'error',
            })
            return
        end

        TaskItemInteraction(player, weaponHash, interaction, 1, 0, 0)

        local weaponEntity = GetCurrentPedWeaponEntityIndex(player, 0)
        local weaponObject = GetObjectIndexFromEntityIndex(weaponEntity)
        if not weaponObject or weaponObject == 0 then
            return
        end

        local permanent = GetWeaponPermanentDegradation(weaponObject)
        local initialDegradation = clamp(GetWeaponDegradation(weaponObject) - permanent)
        local initialDamage = clamp(GetWeaponDamage(weaponObject) - permanent)
        local initialDirt = clamp(GetWeaponDirt(weaponObject))
        local initialSoot = clamp(GetWeaponSoot(weaponObject))
        local uiFlowBlock, container = initialize(player, weaponHash, weaponObject)
        local state = createStateMachine(uiFlowBlock)

        while shouldContinue(player) do
            DisableInspectControl(INPUT_NEXT_CAMERA)
            DisableInspectControl(INPUT_CONTEXT_LT)

            if state == 0 then
                state = createStateMachine(uiFlowBlock)
            elseif state == 1 then
                toggleCleanPrompt(player, weaponObject, hasCleanItem)
                if isCleanEnter(player) then
                    if cleanCallbacks and cleanCallbacks.onCleanStart then
                        local consumed = cleanCallbacks.onCleanStart()
                        if not consumed then
                            lib.notify({
                                title = locale('cl_notify_13'),
                                description = locale('cl_clean_item_need'),
                                type = 'error',
                            })
                        else
                            state = 2
                        end
                    else
                        state = 2
                    end
                end
            elseif state == 2 then
                if isCleanExit(player) then
                    state = 3
                else
                    local progress = GetControlProgress(player)
                    if progress > 0.0 then
                        local currentPermanent = GetWeaponPermanentDegradation(weaponObject)
                        local degradation = (initialDegradation + currentPermanent) - (progress * initialDegradation)
                        local damage = (initialDamage + currentPermanent) - (progress * initialDamage)
                        local dirt = initialDirt - (progress * initialDirt)
                        local soot = initialSoot - (progress * initialSoot)

                        SetWeaponDegradation(weaponObject, degradation)
                        SetWeaponDamage(weaponObject, damage)
                        SetWeaponDirt(weaponObject, dirt)
                        SetWeaponSoot(weaponObject, soot)
                        updateWeaponStats(player, container, weaponHash, weaponObject)
                    end
                end
            elseif state == 3 then
                cleanWeaponObject(weaponObject)
                updateWeaponStats(player, container, weaponHash, weaponObject)
                if cleanCallbacks and cleanCallbacks.onCleanComplete then
                    cleanCallbacks.onCleanComplete(weaponObject)
                end
                state = 1
            end

            Wait(0)
        end
    end)

    cleanup()
    running = false

    return ok
end

RegisterNetEvent('rsg-weaponcomp:client:InspectionWeapon', function()
    local _, weaponHash = GetCurrentPedWeapon(cache.ped, true, 0, true)
    local hasCleanItem = RSGCore.Functions.HasItem(getCleanItem())
    startWeaponInspection(hasCleanItem, buildCleanCallbacks(weaponHash))
end)

exports('startWeaponInspection', function(hasCleanItem, cleanCallbacks, weaponHashOverride)
    return startWeaponInspection(hasCleanItem, cleanCallbacks, weaponHashOverride)
end)

CreateThread(function()
    while true do
        local sleep = 500

        if Config.WeaponWheelInspect and not running and IsUiappRunningByHash(HUD_QUICK_SELECT) == 1 then
            sleep = 0
            local highlighted = GetWheelHighlightedItem()

            if highlighted and highlighted ~= 0 and highlighted ~= WEAPON_UNARMED and getInspectInteraction(highlighted) then
                DisableControlAction(0, INPUT_QUICK_SELECT_INSPECT, true)

                if IsDisabledControlJustPressed(0, INPUT_QUICK_SELECT_INSPECT) then
                    CloseUiappByHash(HUD_QUICK_SELECT)
                    Wait(150)

                    local hasCleanItem = RSGCore.Functions.HasItem(getCleanItem())
                    startWeaponInspection(hasCleanItem, buildCleanCallbacks(highlighted), highlighted)
                end
            end
        end

        Wait(sleep)
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        cleanup()
    end
end)
