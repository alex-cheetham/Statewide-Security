-- Site contacts (AI NPCs), sign-in/out and checkpoint patrols

local managers = {}        -- [siteId] = ped
local cpBlip, siteBlip = nil, nil
local scanning = false
local lastAwayWarning = 0

local function clearPatrolBlips()
    if cpBlip then RemoveBlip(cpBlip) cpBlip = nil end
    if siteBlip then RemoveBlip(siteBlip) siteBlip = nil end
end

local function updateCheckpointBlip()
    if cpBlip then RemoveBlip(cpBlip) cpBlip = nil end
    if not Sec.site or not Sec.patrol then return end
    local site = SWS.GetSite(Sec.site)
    local cp = site.checkpoints[Sec.patrol.index]
    cpBlip = AddBlipForCoord(cp.coords.x, cp.coords.y, cp.coords.z)
    SetBlipSprite(cpBlip, 1)
    SetBlipColour(cpBlip, 5)
    SetBlipScale(cpBlip, 0.8)
    ShowNumberOnBlip(cpBlip, Sec.patrol.index)
    SetBlipRoute(cpBlip, true)
    SetBlipRouteColour(cpBlip, 5)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(('Checkpoint: %s'):format(cp.label))
    EndTextCommandSetBlipName(cpBlip)
    SendNUIMessage({
        action = 'patrol',
        site = site.label,
        index = Sec.patrol.index,
        total = #site.checkpoints,
        lap = Sec.patrol.lap,
        next = cp.label,
    })
end

local function startPatrol(siteId, index, lap)
    local site = SWS.GetSite(siteId)
    Sec.site = siteId
    Sec.patrol = { index = index, lap = lap }
    siteBlip = AddBlipForRadius(site.center.x, site.center.y, site.center.z, site.radius)
    SetBlipColour(siteBlip, 38)
    SetBlipAlpha(siteBlip, 70)
    updateCheckpointBlip()
end

local function endPatrol()
    Sec.site = nil
    Sec.patrol = nil
    clearPatrolBlips()
    SendNUIMessage({ action = 'patrol', clear = true })
end

-------------------------------------------------------------------------------
-- Site contact NPCs
-------------------------------------------------------------------------------
local function spawnManager(site)
    local hash = Sec.LoadModel(site.manager.model)
    if not hash then return nil end
    local c = site.manager.coords
    local ped = CreatePed(4, hash, c.x, c.y, c.z - 1.0, c.w, false, false)
    SetEntityInvincible(ped, true)
    FreezeEntityPosition(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedCanRagdoll(ped, false)
    SetPedFleeAttributes(ped, 0, false)
    TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_CLIPBOARD', 0, true)
    SetModelAsNoLongerNeeded(hash)
    return ped
end

local function talkToManager(site)
    local rankLocked = Sec.rank < site.minRank
    local items = {}

    if Sec.site == site.id then
        local cp = site.checkpoints[Sec.patrol.index]
        items[#items + 1] = { label = 'Patrol status', value = 'status', desc = ('Lap %d - next: %s'):format(Sec.patrol.lap, cp.label) }
        items[#items + 1] = { label = 'Ask for the briefing again', value = 'brief' }
        items[#items + 1] = { label = 'Sign out & hand over the site', value = 'signout' }
    elseif Sec.site then
        Sec.Notify('You are already assigned to another site.', 'error')
        return
    else
        items[#items + 1] = {
            label = 'Sign in & start patrol',
            value = 'signin',
            disabled = rankLocked,
            desc = rankLocked and ('Requires %s'):format(Config.Ranks[site.minRank].name) or ('Pay x%.2f'):format(site.payMult or 1.0),
        }
        items[#items + 1] = { label = 'Ask about the site', value = 'brief' }
    end

    Sec.OpenMenu('manager', site.label, 'Site contact', items, function(choice)
        if choice == 'brief' or choice == 'status' then
            Sec.Radio('SITE CONTACT', site.briefing)
        elseif choice == 'signin' then
            local res = SWS.Callback('sws:site:signIn', site.id)
            if not res or not res.ok then
                Sec.Notify(res and res.msg or 'Sign in failed.', 'error')
                return
            end
            startPatrol(res.site, res.index, res.lap)
            Sec.Radio('SITE CONTACT', site.briefing)
            Sec.Notify(('Patrol started at %s. Scan %d checkpoints in order.'):format(site.label, #site.checkpoints), 'success')
        elseif choice == 'signout' then
            local res = SWS.Callback('sws:site:signOut')
            if not res or not res.ok then
                Sec.Notify(res and res.msg or 'Sign out failed.', 'error')
                return
            end
            Sec.ClearAllIncidents()
            endPatrol()
            Sec.Notify('Signed out. Remember to file your incident reports.', 'success')
        end
    end)
end

CreateThread(function()
    while true do
        local sleep = 1000
        local pos = Sec.PlayerPos()
        for _, site in ipairs(Config.Sites) do
            local c = site.manager.coords
            local dist = #(pos - vector3(c.x, c.y, c.z))
            local ped = managers[site.id]
            if dist < 80.0 and not ped and Sec.onDuty then
                managers[site.id] = spawnManager(site)
            elseif (dist > 110.0 or not Sec.onDuty) and ped then
                DeleteEntity(ped)
                managers[site.id] = nil
            end

            if managers[site.id] and dist < 12.0 then
                sleep = 0
                Sec.Draw3D(vector3(c.x, c.y, c.z + 1.0), ('~b~%s~w~ Site Contact'):format(site.label))
                if dist < 2.2 and not IsPedInAnyVehicle(PlayerPedId(), false) then
                    Sec.HelpText('~INPUT_CONTEXT~ Speak to the site contact')
                    if IsControlJustReleased(0, Config.Keys.Interact) then talkToManager(site) end
                end
            end
        end
        Wait(sleep)
    end
end)

-------------------------------------------------------------------------------
-- Checkpoints
-------------------------------------------------------------------------------
local function scanCheckpoint(cp, index)
    scanning = true
    local ped = PlayerPedId()
    TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_CLIPBOARD', 0, true)
    SendNUIMessage({ action = 'progress', label = ('Scanning %s'):format(cp.label), duration = Config.Patrol.ScanTime })

    local finish = GetGameTimer() + Config.Patrol.ScanTime
    local cancelled = false
    while GetGameTimer() < finish do
        Wait(0)
        DisableControlAction(0, 21, true) -- sprint
        if not IsControlPressed(0, Config.Keys.Interact) or #(Sec.PlayerPos() - cp.ground) > Config.Patrol.ScanRadius + 0.5 then
            cancelled = true
            break
        end
    end

    ClearPedTasks(ped)
    SendNUIMessage({ action = 'progress', cancel = true })
    if cancelled then
        Sec.Notify('Scan cancelled. Hold the key until it completes.', 'error')
        scanning = false
        return
    end

    PlaySoundFrontend(-1, 'Beep_Green', 'DLC_HEIST_HACKING_SNAKE_SOUNDS', true)
    local res = SWS.Callback('sws:patrol:scan', index)
    scanning = false
    if not res or not res.ok then
        Sec.Notify(res and res.msg or 'Scan rejected.', 'error')
        return
    end
    Sec.patrol.index = res.index
    Sec.patrol.lap = res.lap
    if res.routeComplete then
        Sec.Notify(('Route complete! Starting lap %d.'):format(res.lap), 'success')
    end
    updateCheckpointBlip()
end

CreateThread(function()
    while true do
        local sleep = 750
        if Sec.site and Sec.patrol and not scanning then
            local site = SWS.GetSite(Sec.site)
            local cp = site.checkpoints[Sec.patrol.index]
            cp.ground = cp.ground or Sec.Ground(cp.coords)
            local pos = Sec.PlayerPos()
            local dist = #(pos - cp.ground)

            if dist < Config.Patrol.MarkerDrawDistance then
                sleep = 0
                DrawMarker(21, cp.ground.x, cp.ground.y, cp.ground.z + 1.0, 0.0, 0.0, 0.0, 0.0, 180.0, 0.0,
                    0.6, 0.6, 0.6, 255, 210, 60, 160, true, true, 2, false, nil, nil, false)
                Sec.Marker(cp.ground, 255, 210, 60, Config.Patrol.ScanRadius * 2)
                if dist < Config.Patrol.ScanRadius and not IsPedInAnyVehicle(PlayerPedId(), false) then
                    Sec.HelpText(('Hold ~INPUT_CONTEXT~ to scan checkpoint: %s'):format(cp.label))
                    if IsControlJustPressed(0, Config.Keys.Interact) then
                        scanCheckpoint(cp, Sec.patrol.index)
                    end
                end
            end

            -- away-from-post warning
            if SWS.Dist2D(pos, site.center) > site.radius * 3 and GetGameTimer() - lastAwayWarning > 90000 then
                lastAwayWarning = GetGameTimer()
                Sec.Radio('DISPATCH', ('%s, you appear to be away from %s. Return to your post.'):format(Sec.callsign or 'Unit', site.label))
            end
        end
        Wait(sleep)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, ped in pairs(managers) do
        if DoesEntityExist(ped) then DeleteEntity(ped) end
    end
    clearPatrolBlips()
end)
