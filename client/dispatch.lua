-- AI responders (LSPD / EMS), panic alarms, radio checks and team blips

local cfg = Config.Response
local units = {}      -- active responder units for cleanup
local teamBlips = {}  -- [src] = blip
local radioPending = false

-------------------------------------------------------------------------------
-- Responder units
-------------------------------------------------------------------------------
local function findSpawnNode(target, minDist)
    for n = 20, 220, 10 do
        local ok, pos, heading = GetNthClosestVehicleNodeWithHeading(target.x, target.y, target.z, n, 1, 3.0, 0)
        if ok and #(pos - target) >= minDist then return pos, heading end
    end
    local ok, pos, heading = GetClosestVehicleNodeWithHeading(target.x + minDist, target.y, target.z, 1, 3.0, 0)
    if ok then return pos, heading end
    return target + vector3(minDist, 0.0, 0.0), 0.0
end

local function setupCrew(ped)
    SetEntityAsMissionEntity(ped, true, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedKeepTask(ped, true)
    SetPedFleeAttributes(ped, 0, false)
    SetEntityInvincible(ped, true)
    SetPedCanBeDraggedOut(ped, false)
end

local function subjectPos(inc)
    if inc and inc.ped and DoesEntityExist(inc.ped) then return GetEntityCoords(inc.ped) end
    return nil
end

local function walkTo(ped, target, timeoutMs, run)
    TaskGoToEntity(ped, target, -1, 1.3, run and 3.0 or 1.6, 1073741824, 0)
    local deadline = GetGameTimer() + timeoutMs
    while GetGameTimer() < deadline do
        Wait(300)
        if not DoesEntityExist(target) then return false end
        if #(GetEntityCoords(ped) - GetEntityCoords(target)) < 2.0 then return true end
    end
    return false
end

local function crewAnim(ped, dict, anim, ms)
    if Sec.LoadAnim(dict) then
        TaskPlayAnim(ped, dict, anim, 8.0, -8.0, ms, 1, 0, false, false, false)
    end
    Wait(ms)
    ClearPedTasks(ped)
end

local function takeIntoVehicle(subject, veh)
    SetEntityAsMissionEntity(subject, true, true)
    ClearPedTasksImmediately(subject)
    SetEnableHandcuffs(subject, true)
    for _, seat in ipairs({ 1, 2 }) do
        if IsVehicleSeatFree(veh, seat) then
            TaskEnterVehicle(subject, veh, 10000, seat, 1.0, 1, 0)
            local deadline = GetGameTimer() + 10000
            while not IsPedInVehicle(subject, veh, false) and GetGameTimer() < deadline do Wait(300) end
            if not IsPedInVehicle(subject, veh, false) then SetPedIntoVehicle(subject, veh, seat) end
            return
        end
    end
end

-- police: take the subject into custody
local function policeOnScene(unit, inc)
    local officer, partner, veh = unit.driver, unit.partner, unit.veh

    if not inc or inc.resolving or not inc.ped or not DoesEntityExist(inc.ped) then
        -- nothing to collect (or a panic call): hold the scene, then clear
        TaskStartScenarioInPlace(officer, 'WORLD_HUMAN_COP_IDLES', 0, true)
        TaskStartScenarioInPlace(partner, 'WORLD_HUMAN_CLIPBOARD', 0, true)
        Sec.Radio('LSPD', 'On scene. Area secure, clearing in a moment.')
        local hostile
        for _, other in pairs(Sec.Incidents) do
            if other.ped and (other.state == 'fighting' or other.state == 'fleeing')
                and #(GetEntityCoords(other.ped) - GetEntityCoords(officer)) < 60.0 then
                hostile = other
            end
        end
        if hostile then
            hostile.policeCalled = true
            TriggerServerEvent('sws:incident:log', hostile.id, 'LSPD responded to panic alarm')
            -- reuse normal flow for the hostile subject (server needs to know police were called)
            local res = SWS.Callback('sws:incident:callPolice', hostile.id)
            if res then return policeOnScene(unit, hostile) end
        end
        Wait(20000)
        return nil
    end

    local subject = inc.ped
    local caught = walkTo(officer, subject, 40000, inc.state == 'fleeing')
    if partner then TaskGoToEntity(partner, subject, -1, 2.5, 2.0, 1073741824, 0) end
    if not caught or inc.resolving then
        Sec.Radio('LSPD', 'We lost them. Clearing the scene.')
        return nil
    end

    if inc.state == 'escorted' then DetachEntity(subject, true, false) end
    if inc.state == 'fighting' or inc.state == 'fleeing' then
        SetPedToRagdoll(subject, 2500, 2500, 0, false, false, false)
        Wait(2500)
    end
    TaskTurnPedToFaceEntity(officer, subject, 1000)
    Wait(800)
    crewAnim(officer, 'mp_arresting', 'a_uncuff', 2500)

    Sec.Radio('LSPD', inc.warrant and 'Subject in custody on the outstanding warrant. Good work.'
        or 'Subject in custody. Thanks for the assist.')
    inc.state = 'custody'
    Sec.ResolveIncident(inc, 'handed_police', true)
    takeIntoVehicle(subject, veh)
    return subject
end

-- EMS: treat and transport
local function emsOnScene(unit, inc)
    local medic, partner, veh = unit.driver, unit.partner, unit.veh
    if not inc or inc.resolving or not inc.ped or not DoesEntityExist(inc.ped) then
        Sec.Radio('EMS', 'Nobody here needing transport. Clearing.')
        Wait(8000)
        return nil
    end
    local patient = inc.ped
    walkTo(medic, patient, 40000, true)
    if partner then walkTo(partner, patient, 10000, true) end
    if inc.resolving then return nil end
    if inc.state == 'escorted' then DetachEntity(patient, true, false) end

    if partner then
        CreateThread(function() crewAnim(partner, 'amb@medic@standing@kneel@base', 'base', 7000) end)
    end
    crewAnim(medic, 'amb@medic@standing@tendtodead@idle_a', 'idle_a', 7000)

    Sec.Radio('EMS', 'Patient is stable. Transporting to Pillbox.')
    inc.state = 'custody'
    Sec.ResolveIncident(inc, 'handed_ems', true)
    SetEnableHandcuffs(patient, false)
    ClearPedTasksImmediately(patient)
    SetPedIntoVehicle(patient, veh, 2)
    return patient
end

local function despawnUnit(unit)
    for _, e in ipairs({ unit.passenger, unit.driver, unit.partner, unit.veh }) do
        if e and DoesEntityExist(e) then DeleteEntity(e) end
    end
    if unit.blip then RemoveBlip(unit.blip) end
    units[unit] = nil
end

function Sec.SpawnResponse(kind, inc, eta, coords)
    CreateThread(function()
        local isPolice = kind == 'police'
        -- part of the ETA is spent "en route" off-map, the rest is real driving
        Wait(math.floor(eta * 1000 * 0.4))

        local target = subjectPos(inc) or coords or Sec.PlayerPos()
        local vehHash = Sec.LoadModel(isPolice and cfg.PoliceVehicle or cfg.EmsVehicle)
        local pedHash = Sec.LoadModel(isPolice and cfg.PoliceModel or cfg.EmsModel)
        if not vehHash or not pedHash then return end

        local pos, heading = findSpawnNode(target, cfg.SpawnDistance)
        local veh = CreateVehicle(vehHash, pos.x, pos.y, pos.z, heading, true, false)
        SetEntityAsMissionEntity(veh, true, true)
        SetVehicleOnGroundProperly(veh)
        SetVehicleSiren(veh, true)
        SetVehicleEngineOn(veh, true, true, false)
        local driver = CreatePedInsideVehicle(veh, 4, pedHash, -1, true, false)
        local partner = CreatePedInsideVehicle(veh, 4, pedHash, 0, true, false)
        setupCrew(driver)
        setupCrew(partner)
        SetModelAsNoLongerNeeded(vehHash)
        SetModelAsNoLongerNeeded(pedHash)

        local unit = { veh = veh, driver = driver, partner = partner }
        units[unit] = true
        unit.blip = AddBlipForEntity(veh)
        SetBlipSprite(unit.blip, isPolice and 56 or 61)
        SetBlipColour(unit.blip, isPolice and 3 or 1)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(isPolice and 'LSPD Unit' or 'EMS Unit')
        EndTextCommandSetBlipName(unit.blip)

        TaskVehicleDriveToCoordLongrange(driver, veh, target.x, target.y, target.z, cfg.DriveSpeed, 786603, 15.0)
        local deadline = GetGameTimer() + 70000
        local lastRetask = GetGameTimer()
        while GetGameTimer() < deadline do
            Wait(500)
            local live = subjectPos(inc)
            if live and #(live - target) > 25.0 and GetGameTimer() - lastRetask > 5000 then
                target = live
                lastRetask = GetGameTimer()
                TaskVehicleDriveToCoordLongrange(driver, veh, target.x, target.y, target.z, cfg.DriveSpeed, 786603, 15.0)
            end
            if #(GetEntityCoords(veh) - target) < 28.0 then break end
        end

        -- stuck in traffic: put them on the nearest road to the scene
        if #(GetEntityCoords(veh) - target) >= 28.0 then
            local ok, npos, nheading = GetClosestVehicleNodeWithHeading(target.x, target.y, target.z, 1, 3.0, 0)
            if ok then
                SetEntityCoords(veh, npos.x, npos.y, npos.z, false, false, false, false)
                SetEntityHeading(veh, nheading)
                SetVehicleOnGroundProperly(veh)
            end
        end

        TaskVehicleTempAction(driver, veh, 27, 3000)
        Wait(1500)
        TaskLeaveVehicle(driver, veh, 0)
        TaskLeaveVehicle(partner, veh, 0)
        Wait(2500)

        local passenger
        if isPolice then
            passenger = policeOnScene(unit, inc)
        else
            passenger = emsOnScene(unit, inc)
        end
        unit.passenger = passenger

        -- head back
        TaskEnterVehicle(driver, veh, 15000, -1, 1.5, 1, 0)
        TaskEnterVehicle(partner, veh, 15000, 0, 1.5, 1, 0)
        local backBy = GetGameTimer() + 15000
        while GetGameTimer() < backBy and (not IsPedInVehicle(driver, veh, false) or not IsPedInVehicle(partner, veh, false)) do
            Wait(500)
        end
        if not IsPedInVehicle(driver, veh, false) then SetPedIntoVehicle(driver, veh, -1) end
        if not IsPedInVehicle(partner, veh, false) then SetPedIntoVehicle(partner, veh, 0) end
        SetVehicleSiren(veh, false)
        TaskVehicleDriveWander(driver, veh, 18.0, 786603)

        local leaveBy = GetGameTimer() + 45000
        while GetGameTimer() < leaveBy and #(GetEntityCoords(veh) - Sec.PlayerPos()) < 150.0 do
            Wait(1000)
        end
        despawnUnit(unit)
    end)
end

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for unit in pairs(units) do despawnUnit(unit) end
    for _, b in pairs(teamBlips) do RemoveBlip(b) end
end)

-------------------------------------------------------------------------------
-- Panic button
-------------------------------------------------------------------------------
RegisterCommand('secpanic', function()
    if not Sec.onDuty then return end
    TriggerServerEvent('sws:panic')
end, false)
RegisterKeyMapping('secpanic', 'Security: panic button', 'keyboard', Config.Keys.Panic)

RegisterNetEvent('sws:client:panic', function(data)
    local c = data.coords
    PlaySoundFrontend(-1, 'TIMER_STOP', 'HUD_MINI_GAME_SOUNDSET', true)
    SendNUIMessage({ action = 'panic', callsign = data.callsign, own = data.own })
    if data.own then
        Sec.SpawnResponse('police', nil, 15, vector3(c.x, c.y, c.z))
        return
    end
    local blip = AddBlipForCoord(c.x, c.y, c.z)
    SetBlipSprite(blip, 161)
    SetBlipColour(blip, 1)
    SetBlipScale(blip, 1.4)
    SetBlipFlashes(blip, true)
    SetBlipRoute(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(('PANIC: %s'):format(data.callsign))
    EndTextCommandSetBlipName(blip)
    SetTimeout(90000, function() RemoveBlip(blip) end)
end)

-------------------------------------------------------------------------------
-- Radio checks
-------------------------------------------------------------------------------
local function acknowledge()
    if not radioPending then return end
    radioPending = false
    TriggerServerEvent('sws:radio:ack')
end

RegisterCommand('10-4', acknowledge, false)
RegisterCommand('secack', acknowledge, false)
RegisterKeyMapping('secack', 'Security: acknowledge radio check', 'keyboard', Config.Keys.RadioAck)

RegisterNetEvent('sws:client:radioCheck', function(window)
    radioPending = true
    SendNUIMessage({ action = 'radioCheck', window = window, key = Config.Keys.RadioAck })
end)

RegisterNetEvent('sws:client:radioCheckEnd', function()
    radioPending = false
    SendNUIMessage({ action = 'radioCheck', clear = true })
end)

-------------------------------------------------------------------------------
-- Team blips
-------------------------------------------------------------------------------
function Sec.ClearTeamBlips()
    for src, b in pairs(teamBlips) do
        RemoveBlip(b)
        teamBlips[src] = nil
    end
end

RegisterNetEvent('sws:client:team', function(list)
    if not Sec.onDuty then return end
    Sec.team = list
    local me = GetPlayerServerId(PlayerId())
    local seen = {}
    for _, g in ipairs(list) do
        if g.src ~= me and g.coords then
            seen[g.src] = true
            local b = teamBlips[g.src]
            if not b then
                b = AddBlipForCoord(g.coords.x, g.coords.y, g.coords.z)
                SetBlipSprite(b, 1)
                SetBlipColour(b, 38)
                SetBlipScale(b, 0.75)
                SetBlipCategory(b, 7)
                teamBlips[g.src] = b
            else
                SetBlipCoords(b, g.coords.x, g.coords.y, g.coords.z)
            end
            SetBlipColour(b, g.status == 'PANIC' and 1 or 38)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(('%s - %s'):format(g.callsign, g.status or ''))
            EndTextCommandSetBlipName(b)
        end
    end
    for src, b in pairs(teamBlips) do
        if not seen[src] then
            RemoveBlip(b)
            teamBlips[src] = nil
        end
    end
end)

RegisterNetEvent('sws:client:teamRemove', function(src)
    if teamBlips[src] then
        RemoveBlip(teamBlips[src])
        teamBlips[src] = nil
    end
end)
