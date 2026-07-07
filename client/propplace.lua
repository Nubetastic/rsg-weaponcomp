local confirmed
local heading
local CancelPrompt, SetPrompt, RotateLeftPrompt, RotateRightPrompt
local PromptPlacerGroup = GetRandomIntInRange(0, 0xffffff)
lib.locale()

CreateThread(function()
    CancelPrompt = PromptRegisterBegin()
    PromptSetControlAction(CancelPrompt, 0xF84FA74F)
    PromptSetText(CancelPrompt, CreateVarString(10, 'LITERAL_STRING', locale('cl_promp_1')))
    PromptSetEnabled(CancelPrompt, true)
    PromptSetVisible(CancelPrompt, true)
    PromptSetHoldMode(CancelPrompt, true)
    PromptSetGroup(CancelPrompt, PromptPlacerGroup)
    PromptRegisterEnd(CancelPrompt)

    SetPrompt = PromptRegisterBegin()
    PromptSetControlAction(SetPrompt, 0xC7B5340A)
    PromptSetText(SetPrompt, CreateVarString(10, 'LITERAL_STRING', locale('cl_promp_2')))
    PromptSetEnabled(SetPrompt, true)
    PromptSetVisible(SetPrompt, true)
    PromptSetHoldMode(SetPrompt, true)
    PromptSetGroup(SetPrompt, PromptPlacerGroup)
    PromptRegisterEnd(SetPrompt)

    RotateLeftPrompt = PromptRegisterBegin()
    PromptSetControlAction(RotateLeftPrompt, 0xA65EBAB4)
    PromptSetText(RotateLeftPrompt, CreateVarString(10, 'LITERAL_STRING', locale('cl_promp_3')))
    PromptSetEnabled(RotateLeftPrompt, true)
    PromptSetVisible(RotateLeftPrompt, true)
    PromptSetStandardMode(RotateLeftPrompt, true)
    PromptSetGroup(RotateLeftPrompt, PromptPlacerGroup)
    PromptRegisterEnd(RotateLeftPrompt)

    RotateRightPrompt = PromptRegisterBegin()
    PromptSetControlAction(RotateRightPrompt, 0xDEB34313)
    PromptSetText(RotateRightPrompt, CreateVarString(10, 'LITERAL_STRING', locale('cl_promp_4')))
    PromptSetEnabled(RotateRightPrompt, true)
    PromptSetVisible(RotateRightPrompt, true)
    PromptSetStandardMode(RotateRightPrompt, true)
    PromptSetGroup(RotateRightPrompt, PromptPlacerGroup)
    PromptRegisterEnd(RotateRightPrompt)
end)

local function RotationToDirection(rotation)
    local adjustedRotation =
    {
        x = (math.pi / 180) * rotation.x,
        y = (math.pi / 180) * rotation.y,
        z = (math.pi / 180) * rotation.z
    }
    local direction =
    {
        x = -math.sin(adjustedRotation.z) * math.abs(math.cos(adjustedRotation.x)),
        y = math.cos(adjustedRotation.z) * math.abs(math.cos(adjustedRotation.x)),
        z = math.sin(adjustedRotation.x)
    }
    return direction
end

local function DrawPropAxes(prop)
    local propForward, propRight, propUp, propCoords = GetEntityMatrix(prop)

    local propXAxisEnd = propCoords + propRight * 0.20
    local propYAxisEnd = propCoords + propForward * 0.20
    local propZAxisEnd = propCoords + propUp * 0.20

    DrawLine(propCoords.x, propCoords.y, propCoords.z + 0.1, propXAxisEnd.x, propXAxisEnd.y, propXAxisEnd.z, 255, 0, 0, 255)
    DrawLine(propCoords.x, propCoords.y, propCoords.z + 0.1, propYAxisEnd.x, propYAxisEnd.y, propYAxisEnd.z, 0, 255, 0, 255)
    DrawLine(propCoords.x, propCoords.y, propCoords.z + 0.1, propZAxisEnd.x, propZAxisEnd.y, propZAxisEnd.z, 0, 0, 255, 255)
end

local function RayCastGamePlayCamera(distance)
    local cameraRotation = GetGameplayCamRot()
    local cameraCoord = GetGameplayCamCoord()
    local direction = RotationToDirection(cameraRotation)
    local destination =
    {
        x = cameraCoord.x + direction.x * distance,
        y = cameraCoord.y + direction.y * distance,
        z = cameraCoord.z + direction.z * distance
    }
    local a, b, c, d, e = GetShapeTestResult(StartShapeTestRay(cameraCoord.x, cameraCoord.y, cameraCoord.z, destination.x, destination.y, destination.z, -1, PlayerPedId(), 0))
    return b, c, e
end

local function placeProp(propmodel, item, gunsitename, gunsiteid)
    local propModel = joaat(propmodel)
    heading = 0.0
    confirmed = false

    lib.requestModel(propModel)

    local hit, coords, entity

    while not hit do
        hit, coords, entity = RayCastGamePlayCamera(1000.0)
        Wait(0)
    end

    local propObj = CreateObject(propModel, coords.x, coords.y, coords.z, true, false, true)

    CreateThread(function()
        while not confirmed do
            hit, coords, entity = RayCastGamePlayCamera(1000.0)

            SetEntityCoordsNoOffset(propObj, coords.x, coords.y, coords.z, false, false, false, true)
            FreezeEntityPosition(propObj, true)
            SetEntityCollision(propObj, false, false)
            SetEntityAlpha(propObj, 150, false)
            DrawPropAxes(propObj)
            Wait(0)

            local PropPlacerGroupName  = CreateVarString(10, 'LITERAL_STRING', locale('cl_promp_5'))
            PromptSetActiveGroupThisFrame(PromptPlacerGroup, PropPlacerGroupName)

            if IsControlPressed(1, 0xA65EBAB4) then -- Left arrow key
                heading = heading + 1.0
            elseif IsControlPressed(1, 0xDEB34313) then -- Right arrow key
                heading = heading - 1.0
            end

            if heading > 360.0 then
                heading = 0.0
            elseif heading < 0.0 then
                heading = 360.0
            end

            SetEntityHeading(propObj, heading)

            if PromptHasHoldModeCompleted(SetPrompt) then
                confirmed = true
                SetEntityAlpha(propObj, 255, false)
                SetEntityCollision(propObj, true, true)
                DeleteObject(propObj)
                if item == Config.Gunsmithitem then
                    TriggerEvent('rsg-weaponcomp:client:setupgunzone', propmodel, item, coords, heading)
                else
                    TriggerEvent('rsg-weaponcomp:client:placegunsiteitem', propmodel, item, gunsiteid, coords, heading)
                end
            end

            if PromptHasHoldModeCompleted(CancelPrompt) then
                DeleteObject(propObj)
                SetModelAsNoLongerNeeded(propModel)
                break
            end

        end
    end)
end

RegisterNetEvent('rsg-weaponcomp:client:createprop', function(data)
    placeProp(data.propmodel, data.item, data.gunsitename, data.gunsiteid)
end)
