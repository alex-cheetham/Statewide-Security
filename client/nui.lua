-- Security tablet (NUI)

local tabletOpen = false
local tabletProp = nil

local function tabletAnim(enable)
    local ped = PlayerPedId()
    if enable then
        if IsPedInAnyVehicle(ped, false) then return end
        local dict = 'amb@code_human_in_bus_passenger_idles@female@tablet@base'
        if Sec.LoadAnim(dict) then
            TaskPlayAnim(ped, dict, 'base', 3.0, 3.0, -1, 49, 0, false, false, false)
        end
        local hash = Sec.LoadModel('prop_cs_tablet')
        if hash then
            local pos = GetEntityCoords(ped)
            tabletProp = CreateObject(hash, pos.x, pos.y, pos.z + 0.2, true, true, false)
            AttachEntityToEntity(tabletProp, ped, GetPedBoneIndex(ped, 60309), 0.03, 0.002, -0.0, 10.0, 160.0, 0.0,
                true, false, false, false, 2, true)
            SetModelAsNoLongerNeeded(hash)
        end
    else
        if tabletProp and DoesEntityExist(tabletProp) then DeleteEntity(tabletProp) end
        tabletProp = nil
        StopAnimTask(ped, 'amb@code_human_in_bus_passenger_idles@female@tablet@base', 'base', 3.0)
    end
end

function Sec.OpenTablet(tab)
    if tabletOpen then return end
    local data = SWS.Callback('sws:tablet:data')
    if not data then
        Sec.Notify('Tablet could not connect.', 'error')
        return
    end
    tabletOpen = true
    tabletAnim(true)
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'tablet', open = true, data = data, tab = tab })
end

RegisterCommand('sectablet', function() Sec.OpenTablet() end, false)
RegisterKeyMapping('sectablet', 'Security: open tablet', 'keyboard', Config.Keys.Tablet)

RegisterNUICallback('close', function(_, reply)
    reply('ok')
    SetNuiFocus(false, false)
    if tabletOpen then
        tabletOpen = false
        tabletAnim(false)
    end
end)

RegisterNUICallback('refresh', function(_, reply)
    reply(SWS.Callback('sws:tablet:data') or {})
end)

RegisterNUICallback('setWaypoint', function(data, reply)
    reply('ok')
    local site = SWS.GetSite(data.siteId)
    if site then
        SetNewWaypoint(site.manager.coords.x, site.manager.coords.y)
        Sec.Notify(('GPS set: %s. Report to the site contact.'):format(site.label), 'info')
    elseif data.siteId == 'hq' then
        SetNewWaypoint(Config.HQ.duty.x, Config.HQ.duty.y)
    end
end)

RegisterNUICallback('reports', function(data, reply)
    reply(SWS.Callback('sws:reports:list', data.scope) or {})
end)

RegisterNUICallback('submitReport', function(data, reply)
    reply(SWS.Callback('sws:reports:submit', data.incidentId, data.report) or { ok = false, msg = 'No response.' })
end)

RegisterNUICallback('reviewReport', function(data, reply)
    reply(SWS.Callback('sws:reports:review', data.id, data.verdict, data.comment) or { ok = false, msg = 'No response.' })
end)

RegisterNUICallback('radioAck', function(_, reply)
    reply('ok')
    TriggerServerEvent('sws:radio:ack')
end)
