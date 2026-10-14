-- Core client state, helpers, HQ (duty / locker / garage)

Sec = {
    onDuty = false,
    callsign = nil,
    rank = 1,
    site = nil,         -- site id when signed in
    patrol = nil,       -- { index, lap }
    vehicle = nil,      -- entity
    savedOutfit = nil,
    givenWeapons = {},
    team = {},
}

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------
function Sec.Notify(msg, kind)
    SendNUIMessage({ action = 'notify', text = msg, kind = kind or 'info' })
end

function Sec.Radio(from, msg)
    SendNUIMessage({ action = 'radio', from = from or 'DISPATCH', text = msg })
    PlaySoundFrontend(-1, 'Start_Squelch', 'CB_RADIO_SFX', true)
    SetTimeout(250, function() PlaySoundFrontend(-1, 'End_Squelch', 'CB_RADIO_SFX', true) end)
end

function Sec.HelpText(text)
    BeginTextCommandDisplayHelp('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayHelp(0, false, false, -1)
end

function Sec.Draw3D(coords, text)
    local onScreen, x, y = World3dToScreen2d(coords.x, coords.y, coords.z)
    if not onScreen then return end
    SetTextScale(0.32, 0.32)
    SetTextFont(4)
    SetTextProportional(true)
    SetTextColour(255, 255, 255, 215)
    SetTextOutline()
    SetTextCentre(true)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(x, y)
end

function Sec.LoadModel(model)
    local hash = type(model) == 'number' and model or GetHashKey(model)
    if not IsModelInCdimage(hash) then
        print(('[statewide_security] invalid model: %s'):format(model))
        return nil
    end
    RequestModel(hash)
    local timeout = GetGameTimer() + 8000
    while not HasModelLoaded(hash) and GetGameTimer() < timeout do Wait(10) end
    return HasModelLoaded(hash) and hash or nil
end

function Sec.LoadAnim(dict)
    RequestAnimDict(dict)
    local timeout = GetGameTimer() + 5000
    while not HasAnimDictLoaded(dict) and GetGameTimer() < timeout do Wait(10) end
    return HasAnimDictLoaded(dict)
end

function Sec.LoadClipset(set)
    RequestAnimSet(set)
    local timeout = GetGameTimer() + 5000
    while not HasAnimSetLoaded(set) and GetGameTimer() < timeout do Wait(10) end
    return HasAnimSetLoaded(set)
end

local groundCache = {}
function Sec.Ground(v)
    local key = ('%.1f:%.1f'):format(v.x, v.y)
    if groundCache[key] then return groundCache[key] end
    local found, z = GetGroundZFor_3dCoord(v.x, v.y, v.z + 3.0, false)
    if found then
        groundCache[key] = vector3(v.x, v.y, z)
        return groundCache[key]
    end
    return vector3(v.x, v.y, v.z)
end

function Sec.PlayerPos()
    return GetEntityCoords(PlayerPedId())
end

function Sec.Marker(coords, r, g, b, scale)
    DrawMarker(1, coords.x, coords.y, coords.z - 0.98, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
        scale or 1.2, scale or 1.2, 0.6, r, g, b, 120, false, false, 2, false, nil, nil, false)
end

-------------------------------------------------------------------------------
-- Generic NUI menu (garage, site contact, etc.)
-------------------------------------------------------------------------------
local menuHandlers = {}

function Sec.OpenMenu(id, title, subtitle, items, cb)
    menuHandlers[id] = cb
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'menu', id = id, title = title, subtitle = subtitle, items = items })
end

RegisterNUICallback('menuSelect', function(data, reply)
    reply('ok')
    SetNuiFocus(false, false)
    local handler = menuHandlers[data.id]
    menuHandlers[data.id] = nil
    if handler and data.value ~= nil then
        CreateThread(function() handler(data.value) end)
    end
end)

-------------------------------------------------------------------------------
-- Uniform & equipment
-------------------------------------------------------------------------------
local function isFreemode(ped)
    local m = GetEntityModel(ped)
    if m == GetHashKey('mp_m_freemode_01') then return 'male' end
    if m == GetHashKey('mp_f_freemode_01') then return 'female' end
    return nil
end

local function saveOutfit(ped)
    local outfit = { components = {}, props = {} }
    for i = 0, 11 do
        outfit.components[i] = { GetPedDrawableVariation(ped, i), GetPedTextureVariation(ped, i), GetPedPaletteVariation(ped, i) }
    end
    for _, p in ipairs({ 0, 1, 2, 6, 7 }) do
        outfit.props[p] = { GetPedPropIndex(ped, p), GetPedPropTextureIndex(ped, p) }
    end
    return outfit
end

local function applyOutfit(ped, outfit)
    for i, c in pairs(outfit.components) do
        SetPedComponentVariation(ped, i, c[1], c[2], c[3] or 0)
    end
    for p, v in pairs(outfit.props) do
        if v[1] == -1 then ClearPedProp(ped, p) else SetPedPropIndex(ped, p, v[1], v[2], true) end
    end
end

function Sec.EquipUniform()
    local ped = PlayerPedId()
    local gender = isFreemode(ped)
    if not gender then
        Sec.Notify('Uniforms only fit freemode characters.', 'error')
        return
    end
    Sec.savedOutfit = Sec.savedOutfit or saveOutfit(ped)
    local u = Config.Uniform[gender]
    for comp, v in pairs(u.components) do SetPedComponentVariation(ped, comp, v[1], v[2], 0) end
    for prop, v in pairs(u.props or {}) do
        if v[1] == -1 then ClearPedProp(ped, prop) else SetPedPropIndex(ped, prop, v[1], v[2], true) end
    end
end

function Sec.RestoreOutfit()
    if Sec.savedOutfit then
        applyOutfit(PlayerPedId(), Sec.savedOutfit)
        Sec.savedOutfit = nil
    end
end

local function giveEquipment()
    local ped = PlayerPedId()
    Sec.givenWeapons = {}
    for _, e in ipairs(Config.Equipment) do
        if Sec.rank >= e.minRank then
            local hash = GetHashKey(e.weapon)
            if not HasPedGotWeapon(ped, hash, false) then
                GiveWeaponToPed(ped, hash, e.ammo, false, false)
                Sec.givenWeapons[#Sec.givenWeapons + 1] = hash
            end
        end
    end
end

local function removeEquipment()
    local ped = PlayerPedId()
    for _, hash in ipairs(Sec.givenWeapons) do RemoveWeaponFromPed(ped, hash) end
    Sec.givenWeapons = {}
end

-------------------------------------------------------------------------------
-- Duty
-------------------------------------------------------------------------------
local function clockOn()
    local res = SWS.Callback('sws:duty:clockOn')
    if not res or not res.ok then
        Sec.Notify(res and res.msg or 'Could not clock on.', 'error')
        return
    end
    Sec.onDuty = true
    Sec.callsign = res.callsign
    Sec.rank = res.rank
    Sec.EquipUniform()
    giveEquipment()
    Sec.Notify(('On duty as %s (%s)'):format(res.callsign, Config.Ranks[res.rank].name), 'success')
    SendNUIMessage({ action = 'hud', show = true, callsign = res.callsign, rank = Config.Ranks[res.rank].name })
end

local function clockOff()
    if Sec.site then
        Sec.Notify('Sign out of your site with the site contact first.', 'error')
        return
    end
    local res = SWS.Callback('sws:duty:clockOff')
    if not res or not res.ok then
        Sec.Notify(res and res.msg or 'Could not clock off.', 'error')
        return
    end
    Sec.onDuty = false
    Sec.vehicle = nil
    removeEquipment()
    Sec.RestoreOutfit()
    Sec.ClearTeamBlips()
    SendNUIMessage({ action = 'hud', show = false })
    SendNUIMessage({ action = 'shiftSummary', summary = res.summary })
    SetNuiFocus(true, true)
end

-------------------------------------------------------------------------------
-- Garage
-------------------------------------------------------------------------------
local function openGarage()
    local items = {}
    for _, v in ipairs(Config.Vehicles) do
        items[#items + 1] = {
            label = v.label,
            value = v.model,
            disabled = Sec.rank < v.minRank,
            desc = Sec.rank < v.minRank and ('Requires %s'):format(Config.Ranks[v.minRank].name) or v.description,
        }
    end
    Sec.OpenMenu('garage', 'Motor Pool', 'Sign out a patrol vehicle', items, function(model)
        local res = SWS.Callback('sws:vehicle:spawn', model)
        if not res or not res.ok then
            Sec.Notify(res and res.msg or 'Vehicle unavailable.', 'error')
            return
        end
        local timeout = GetGameTimer() + 5000
        while not NetworkDoesNetworkIdExist(res.netId) and GetGameTimer() < timeout do Wait(50) end
        local veh = NetToVeh(res.netId)
        timeout = GetGameTimer() + 3000
        while not DoesEntityExist(veh) and GetGameTimer() < timeout do
            Wait(50)
            veh = NetToVeh(res.netId)
        end
        if DoesEntityExist(veh) then
            Sec.vehicle = veh
            local entry
            for _, v in ipairs(Config.Vehicles) do
                if v.model == model then entry = v end
            end
            if entry and entry.extrasOff then
                for i = 0, 20 do
                    if DoesExtraExist(veh, i) then SetVehicleExtra(veh, i, true) end
                end
            end
            SetVehicleLivery(veh, Config.VehicleLivery)
            SetVehicleDirtLevel(veh, 0.0)
            SetVehicleEngineOn(veh, true, true, false)
            TaskWarpPedIntoVehicle(PlayerPedId(), veh, -1)
            Sec.Notify(('Vehicle signed out. Plate %s'):format(res.plate), 'success')
        end
    end)
end

local function returnVehicle()
    local res = SWS.Callback('sws:vehicle:return')
    if res and res.ok then
        Sec.vehicle = nil
        Sec.Notify('Vehicle returned to the motor pool.', 'success')
    else
        Sec.Notify(res and res.msg or 'Could not return vehicle.', 'error')
    end
end

-------------------------------------------------------------------------------
-- HQ loop
-------------------------------------------------------------------------------
CreateThread(function()
    local b = Config.HQ.blip
    local blip = AddBlipForCoord(Config.HQ.duty.x, Config.HQ.duty.y, Config.HQ.duty.z)
    SetBlipSprite(blip, b.sprite)
    SetBlipColour(blip, b.color)
    SetBlipScale(blip, b.scale)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(Config.HQ.label)
    EndTextCommandSetBlipName(blip)

    while true do
        local sleep = 1000
        local ped = PlayerPedId()
        local pos = GetEntityCoords(ped)
        local hq = Config.HQ

        if #(pos - hq.duty) < 25.0 then
            sleep = 0
            Sec.Marker(hq.duty, 50, 140, 255)
            if #(pos - hq.duty) < 1.5 then
                Sec.HelpText(Sec.onDuty and '~INPUT_CONTEXT~ Clock off duty' or '~INPUT_CONTEXT~ Clock on duty')
                if IsControlJustReleased(0, Config.Keys.Interact) then
                    if Sec.onDuty then clockOff() else clockOn() end
                end
            end

            if Sec.onDuty then
                Sec.Marker(hq.locker, 120, 200, 120)
                if #(pos - hq.locker) < 1.5 then
                    Sec.HelpText('~INPUT_CONTEXT~ Locker: re-equip uniform & gear')
                    if IsControlJustReleased(0, Config.Keys.Interact) then
                        Sec.EquipUniform()
                        giveEquipment()
                        Sec.Notify('Uniform and equipment issued.', 'success')
                    end
                end

                local inVeh = IsPedInAnyVehicle(ped, false)
                Sec.Marker(hq.garage, 255, 190, 60, inVeh and 4.0 or 1.2)
                local dist = #(pos - hq.garage)
                if inVeh and dist < 5.0 and GetVehiclePedIsIn(ped, false) == Sec.vehicle then
                    Sec.HelpText('~INPUT_CONTEXT~ Return company vehicle')
                    if IsControlJustReleased(0, Config.Keys.Interact) then returnVehicle() end
                elseif not inVeh and dist < 1.5 then
                    Sec.HelpText('~INPUT_CONTEXT~ Motor pool')
                    if IsControlJustReleased(0, Config.Keys.Interact) then openGarage() end
                end
            end
        end
        Wait(sleep)
    end
end)

-------------------------------------------------------------------------------
-- Server events
-------------------------------------------------------------------------------
RegisterNetEvent('sws:client:notify', function(msg, kind) Sec.Notify(msg, kind) end)
RegisterNetEvent('sws:client:radio', function(from, msg) Sec.Radio(from, msg) end)

RegisterNetEvent('sws:client:reward', function(data)
    SendNUIMessage({ action = 'reward', pay = data.pay, xp = data.xp, reason = data.reason })
end)

RegisterNetEvent('sws:client:rankChanged', function(rank)
    Sec.rank = rank
    if Sec.onDuty then
        giveEquipment()
        SendNUIMessage({ action = 'hud', show = true, callsign = Sec.callsign, rank = Config.Ranks[rank].name })
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if Sec.onDuty then
        removeEquipment()
        Sec.RestoreOutfit()
    end
    SetNuiFocus(false, false)
end)

if Config.Debug then
    RegisterCommand('secpos', function()
        local p = GetEntityCoords(PlayerPedId())
        local h = GetEntityHeading(PlayerPedId())
        local line = ('vector4(%.1f, %.1f, %.1f, %.1f)'):format(p.x, p.y, p.z, h)
        print(line)
        Sec.Notify(line, 'info')
    end, false)
end
