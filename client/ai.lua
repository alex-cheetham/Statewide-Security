-- Incident NPCs: spawning, behaviour state machine, escalation and resolution

Sec.Incidents = {}

local CUFF_DICT, CUFF_ANIM = 'mp_arresting', 'idle'
local KNEEL_DICT, KNEEL_ANIM = 'random@arrests@busted', 'idle_a'

-- states in which the subject can be talked to
Sec.TalkStates = { idle = true, engaged = true, subdued = true, detained = true, escorted = true, collapsed = true }

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------
local function removeProp(inc)
    if inc.prop and DoesEntityExist(inc.prop) then DeleteEntity(inc.prop) end
    inc.prop = nil
end

local function removeBlips(inc)
    if inc.blip then RemoveBlip(inc.blip) inc.blip = nil end
    if inc.areaBlip then RemoveBlip(inc.areaBlip) inc.areaBlip = nil end
end

local function playLoop(ped, dict, anim, flag)
    if Sec.LoadAnim(dict) then
        TaskPlayAnim(ped, dict, anim, 8.0, -8.0, -1, flag or 1, 0, false, false, false)
    end
end

function Sec.Log(inc, text)
    TriggerServerEvent('sws:incident:log', inc.id, text)
end

function Sec.Say(inc, text)
    -- floating speech above the NPC for a few seconds + dialog transcript
    inc.speech = { text = text, untilTime = GetGameTimer() + 5000 }
    SendNUIMessage({ action = 'dialogLine', id = inc.id, who = 'npc', text = text })
end

function Sec.Willingness(inc)
    local p = inc.profile
    return p.compliance - p.stress * 0.5 + inc.rapport
end

function Sec.Demeanor(inc)
    local s = inc.profile.stress
    if inc.def.collapsed then return 'Unresponsive', 'grey' end
    if s < 30 then return 'Calm', 'green' end
    if s < 55 then return 'Uneasy', 'yellow' end
    if s < 80 then return 'Agitated', 'orange' end
    return 'Hostile', 'red'
end

function Sec.Cooperation(inc)
    local w = Sec.Willingness(inc)
    if inc.state == 'detained' or inc.state == 'subdued' then return 'Restrained' end
    if w >= 55 then return 'Cooperative' end
    if w >= 35 then return 'Hesitant' end
    return 'Uncooperative'
end

-------------------------------------------------------------------------------
-- Idle behaviour
-------------------------------------------------------------------------------
local function applyIdle(inc)
    local ped, idle = inc.ped, inc.def.idle
    ClearPedTasks(ped)
    if idle.scenario then
        TaskStartScenarioInPlace(ped, idle.scenario, 0, true)
    elseif idle.anim then
        playLoop(ped, idle.anim[1], idle.anim[2], 1)
    end
    if idle.prop and not inc.prop then
        local hash = Sec.LoadModel(idle.prop)
        if hash then
            local c = GetEntityCoords(ped)
            inc.prop = CreateObject(hash, c.x, c.y, c.z, true, true, false)
            AttachEntityToEntity(inc.prop, ped, GetPedBoneIndex(ped, 57005), 0.11, 0.05, -0.06, 28.0, 30.0, 0.0,
                true, true, false, true, 1, true)
            SetModelAsNoLongerNeeded(hash)
        end
    end
end

-------------------------------------------------------------------------------
-- State machine
-------------------------------------------------------------------------------
function Sec.SetState(inc, state)
    local ped = inc.ped
    if not ped or not DoesEntityExist(ped) then return end
    local prev = inc.state
    inc.state = state
    local player = PlayerPedId()

    if state ~= 'idle' then removeProp(inc) end

    if state == 'engaged' then
        ClearPedTasks(ped)
        TaskTurnPedToFaceEntity(ped, player, -1)

    elseif state == 'leaving' then
        ClearPedTasks(ped)
        local exit = SWS.GetSite(inc.site).exit
        TaskGoToCoordAnyMeans(ped, exit.x, exit.y, exit.z, 1.0, 0, false, 786603, 0.0)
        inc.leaveStart = GetGameTimer()

    elseif state == 'fleeing' then
        inc.flags.resisted = true
        inc.flags.escalations = inc.flags.escalations + 1
        ClearPedTasks(ped)
        SetPedFleeAttributes(ped, 0, false)
        SetPedMoveRateOverride(ped, 1.1)
        TaskSmartFleePed(ped, player, 1000.0, -1, false, false)
        Sec.Log(inc, 'Subject fled on foot')
        SendNUIMessage({ action = 'objective', text = 'Subject is fleeing! Close in and press E to tackle.' })

    elseif state == 'fighting' then
        inc.flags.resisted = true
        inc.flags.escalations = inc.flags.escalations + 1
        ClearPedTasks(ped)
        if inc.armed and inc.weapon then
            GiveWeaponToPed(ped, GetHashKey(inc.weapon), 60, false, true)
            SetCurrentPedWeapon(ped, GetHashKey(inc.weapon), true)
            inc.flags.armedThreat = true
            Sec.Log(inc, ('Subject armed with %s'):format(inc.weapon:gsub('WEAPON_', ''):lower()))
            Sec.Notify('The subject has drawn a weapon!', 'error')
        end
        SetPedCombatAttributes(ped, 46, true)
        SetPedCombatAttributes(ped, 5, true)
        SetPedCombatAbility(ped, 1)
        SetPedCombatRange(ped, 0)
        TaskCombatPed(ped, player, 0, 16)
        Sec.Log(inc, 'Subject became violent')
        SendNUIMessage({ action = 'objective', text = 'Subject is violent! Subdue them (melee / taser), then detain.' })

    elseif state == 'subdued' then
        ClearPedTasksImmediately(ped)
        RemoveAllPedWeapons(ped, true)
        inc.profile.compliance = math.max(inc.profile.compliance, 85)
        inc.profile.stress = math.min(inc.profile.stress, 60)
        playLoop(ped, KNEEL_DICT, KNEEL_ANIM, 1)
        Sec.Log(inc, 'Subject subdued')
        SendNUIMessage({ action = 'objective', text = 'Subject subdued. Interact to detain.' })

    elseif state == 'detained' then
        ClearPedTasks(ped)
        SetEnableHandcuffs(ped, true)
        playLoop(ped, CUFF_DICT, CUFF_ANIM, 49)
        inc.flags.detained = true
        Sec.Log(inc, 'Subject detained in handcuffs')
        SendNUIMessage({ action = 'objective', text = 'Subject detained. Run their ID, search them, and request police.' })

    elseif state == 'escorted' then
        AttachEntityToEntity(ped, player, 11816, 0.54, 0.44, 0.0, 0.0, 0.0, 0.0, false, false, false, false, 2, true)
        playLoop(ped, CUFF_DICT, CUFF_ANIM, 49)

    elseif state == 'collapsed' then
        local idle = inc.def.idle
        playLoop(ped, idle.anim[1], idle.anim[2], 1)
    end

    if prev == 'escorted' and state ~= 'escorted' then
        DetachEntity(ped, true, false)
    end
end

-------------------------------------------------------------------------------
-- Escalation: called after every interaction
-------------------------------------------------------------------------------
function Sec.CheckEscalation(inc)
    local p = inc.profile
    if inc.state == 'detained' or inc.state == 'subdued' or inc.state == 'escorted' or inc.def.collapsed then return false end

    inc.peakStress = math.max(inc.peakStress, p.stress)
    if inc.peakStress >= 50 and p.stress <= 25 and not inc.flags.deescalated then
        inc.flags.deescalated = true
        Sec.Log(inc, 'Situation de-escalated')
    end

    if p.stress < 85 then return false end

    if p.aggression >= 60 then
        Sec.Say(inc, Dialogue.Line(inc.type, 'escalate_fight'))
        Sec.SetState(inc, 'fighting')
        return true
    elseif p.flight >= 45 then
        Sec.Say(inc, Dialogue.Line(inc.type, 'escalate_flee'))
        Sec.SetState(inc, 'fleeing')
        return true
    end
    Sec.Say(inc, Dialogue.Line(inc.type, 'escalate_argue'))
    return false
end

-------------------------------------------------------------------------------
-- Spawning
-------------------------------------------------------------------------------
local function spawnSubject(inc)
    local hash = Sec.LoadModel(inc.model)
    if not hash then return false end
    local s = inc.spawn
    local ground = Sec.Ground(vector3(s.x, s.y, s.z))
    local ped = CreatePed(4, hash, ground.x, ground.y, ground.z, s.w, true, true)
    SetModelAsNoLongerNeeded(hash)
    if not DoesEntityExist(ped) then return false end

    SetEntityAsMissionEntity(ped, true, true)
    local netId = NetworkGetNetworkIdFromEntity(ped)
    SetNetworkIdCanMigrate(netId, false)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedKeepTask(ped, true)
    SetPedDropsWeaponsWhenDead(ped, false)
    SetPedMaxHealth(ped, 200)
    SetEntityHealth(ped, 200)
    SetPedDiesWhenInjured(ped, false)
    SetPedCanRagdollFromPlayerImpact(ped, true)
    inc.subdueHealth = 145

    if inc.def.clipset and Sec.LoadClipset(inc.def.clipset) then
        SetPedMovementClipset(ped, inc.def.clipset, 0.25)
    end

    inc.ped = ped
    inc.blip = AddBlipForEntity(ped)
    SetBlipSprite(inc.blip, 1)
    SetBlipColour(inc.blip, inc.def.benign and 3 or 1)
    SetBlipScale(inc.blip, 0.7)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(inc.label)
    EndTextCommandSetBlipName(inc.blip)

    if inc.def.collapsed then
        Sec.SetState(inc, 'collapsed')
    else
        inc.state = 'idle'
        applyIdle(inc)
    end
    return true
end

RegisterNetEvent('sws:client:incidentNew', function(data)
    local inc = data
    inc.def = Incidents.Types[data.type]
    inc.state = 'pending'
    inc.rapport = 0
    inc.peakStress = data.profile.stress
    inc.flags = { escalations = 0 }
    inc.transcript = {}
    Sec.Incidents[inc.id] = inc

    local s = inc.spawn
    inc.areaBlip = AddBlipForRadius(s.x, s.y, s.z, 35.0)
    SetBlipColour(inc.areaBlip, inc.priority >= 3 and 1 or 47)
    SetBlipAlpha(inc.areaBlip, 110)
    inc.blip = AddBlipForCoord(s.x, s.y, s.z)
    SetBlipSprite(inc.blip, inc.priority >= 3 and 161 or 280)
    SetBlipColour(inc.blip, inc.priority >= 3 and 1 or 47)
    SetBlipRoute(inc.blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(('Incident: %s'):format(inc.label))
    EndTextCommandSetBlipName(inc.blip)

    Sec.Radio(inc.priority >= 3 and 'PRIORITY' or 'DISPATCH', inc.dispatch)
    SendNUIMessage({ action = 'incidentAlert', label = inc.label, location = inc.location, priority = inc.priority })
    if inc.def.alarm then
        CreateThread(function()
            for _ = 1, 4 do
                PlaySoundFrontend(-1, 'Beep_Red', 'DLC_HEIST_HACKING_SNAKE_SOUNDS', true)
                Wait(400)
            end
        end)
    end
end)

-------------------------------------------------------------------------------
-- Resolution & cleanup
-------------------------------------------------------------------------------
local function cleanup(inc, outcome, keepPed)
    removeBlips(inc)
    removeProp(inc)
    Sec.CloseDialog(inc.id)
    local ped = inc.ped
    if ped and DoesEntityExist(ped) and not keepPed then
        if inc.state == 'escorted' then DetachEntity(ped, true, false) end
        if outcome == 'timeout' or outcome == 'cancelled' then
            DeleteEntity(ped)
        elseif outcome == 'left_site' or outcome == 'assisted' or outcome == 'released' then
            SetEnableHandcuffs(ped, false)
            ClearPedTasks(ped)
            if IsPedInAnyVehicle(ped, false) then
                TaskLeaveVehicle(ped, GetVehiclePedIsIn(ped, false), 16)
                Wait(1500)
            end
            SetBlockingOfNonTemporaryEvents(ped, false)
            TaskWanderStandard(ped, 10.0, 10)
            SetPedAsNoLongerNeeded(ped)
        else
            SetPedAsNoLongerNeeded(ped)
        end
    end
    SendNUIMessage({ action = 'objective', clear = true })
    Sec.Incidents[inc.id] = nil
end

function Sec.ResolveIncident(inc, outcome, keepPed)
    if inc.resolving then return end
    inc.resolving = true
    CreateThread(function()
        local res = SWS.Callback('sws:incident:resolve', inc.id, outcome, inc.flags)
        cleanup(inc, outcome, keepPed)
        if res then
            SendNUIMessage({ action = 'incidentResult', label = inc.label, result = res })
        else
            Sec.Notify('Incident closed.', 'info')
        end
    end)
end

RegisterNetEvent('sws:client:incidentEnd', function(id, reason)
    local inc = Sec.Incidents[id]
    if not inc then return end
    inc.resolving = true
    cleanup(inc, reason)
end)

function Sec.ClearAllIncidents()
    for _, inc in pairs(Sec.Incidents) do
        inc.resolving = true
        cleanup(inc, 'cancelled')
    end
end

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, inc in pairs(Sec.Incidents) do
        removeBlips(inc)
        removeProp(inc)
        if inc.ped and DoesEntityExist(inc.ped) then DeleteEntity(inc.ped) end
    end
end)

-------------------------------------------------------------------------------
-- Main behaviour loop
-------------------------------------------------------------------------------
CreateThread(function()
    while true do
        Wait(250)
        local player = PlayerPedId()
        local ppos = GetEntityCoords(player)
        local playerDown = IsPedDeadOrDying(player, true) or IsPedFatallyInjured(player)

        for _, inc in pairs(Sec.Incidents) do
            if not inc.resolving then
                if inc.state == 'pending' then
                    local s = inc.spawn
                    if #(ppos - vector3(s.x, s.y, s.z)) < Config.Director.SpawnDistance then
                        if inc.blip then RemoveBlip(inc.blip) inc.blip = nil end
                        if not spawnSubject(inc) then
                            Sec.ResolveIncident(inc, 'timeout')
                        end
                    end
                else
                    local ped = inc.ped
                    if not ped or not DoesEntityExist(ped) then
                        Sec.ResolveIncident(inc, 'escaped')
                    elseif IsPedDeadOrDying(ped, true) then
                        Sec.Log(inc, 'Subject is deceased')
                        Sec.ResolveIncident(inc, 'fatality')
                    elseif playerDown and (inc.state == 'fighting' or inc.state == 'fleeing') then
                        Sec.Log(inc, 'Guard incapacitated')
                        Sec.ResolveIncident(inc, 'guard_down')
                    else
                        local pos = GetEntityCoords(ped)
                        local d = #(ppos - pos)
                        local state = inc.state

                        -- first contact
                        if not inc.engaged and d < 12.0 then
                            inc.engaged = true
                            TriggerServerEvent('sws:incident:engage', inc.id)
                            if inc.areaBlip then RemoveBlip(inc.areaBlip) inc.areaBlip = nil end
                            -- some subjects bolt as soon as they see a uniform
                            if state == 'idle' and inc.profile.flight >= 55 and math.random(100) < inc.profile.flight - 25 then
                                Sec.Say(inc, Dialogue.Line(inc.type, 'escalate_flee'))
                                Sec.SetState(inc, 'fleeing')
                                state = 'fleeing'
                            end
                        end

                        -- force used on someone who wasn't resisting (taser / baton / fists)
                        if (state == 'idle' or state == 'engaged' or state == 'leaving')
                            and (IsPedBeingStunned(ped, 0) or GetEntityHealth(ped) < inc.subdueHealth) then
                            inc.flags.usedForce = true
                            Sec.Log(inc, 'Force used on a non-resisting subject')
                            Sec.CloseDialog(inc.id)
                            Sec.SetState(inc, 'subdued')
                            state = 'subdued'
                        end

                        if state == 'leaving' then
                            local site = SWS.GetSite(inc.site)
                            local exit = site.exit
                            if #(pos - exit) < 5.0 or SWS.Dist2D(pos, site.center) > site.radius + 25.0
                                or GetGameTimer() - inc.leaveStart > 75000 then
                                Sec.Log(inc, 'Subject left the property')
                                Sec.ResolveIncident(inc, inc.leaveOutcome or 'left_site')
                            end

                        elseif state == 'fleeing' then
                            if d > Config.FleeEscapeDistance then
                                Sec.Log(inc, 'Lost sight of subject')
                                Sec.ResolveIncident(inc, 'escaped')
                            elseif IsPedBeingStunned(ped, 0) or GetEntityHealth(ped) < inc.subdueHealth then
                                inc.flags.usedForce = true
                                Sec.SetState(inc, 'subdued')
                            end

                        elseif state == 'fighting' then
                            if IsPedBeingStunned(ped, 0) or GetEntityHealth(ped) < inc.subdueHealth then
                                inc.flags.usedForce = true
                                Sec.SetState(inc, 'subdued')
                            elseif d > Config.FleeEscapeDistance then
                                Sec.ResolveIncident(inc, 'escaped')
                            end

                        elseif state == 'subdued' then
                            if not IsEntityPlayingAnim(ped, KNEEL_DICT, KNEEL_ANIM, 3) and not IsPedRagdoll(ped) then
                                playLoop(ped, KNEEL_DICT, KNEEL_ANIM, 1)
                            end

                        elseif state == 'detained' or state == 'escorted' then
                            if not IsEntityPlayingAnim(ped, CUFF_DICT, CUFF_ANIM, 3) and not IsPedInAnyVehicle(ped, false) then
                                playLoop(ped, CUFF_DICT, CUFF_ANIM, 49)
                            end

                        elseif state == 'collapsed' then
                            local idle = inc.def.idle
                            if not IsEntityPlayingAnim(ped, idle.anim[1], idle.anim[2], 3) then
                                playLoop(ped, idle.anim[1], idle.anim[2], 1)
                            end

                        elseif state == 'engaged' then
                            -- calm slowly returns while the guard is talking normally
                            if GetGameTimer() - (inc.lastAction or 0) > 6000 then
                                inc.lastAction = GetGameTimer()
                                inc.profile.stress = math.max(0, inc.profile.stress - 2)
                            end
                            -- guard wandered off: subject goes back to what they were doing
                            if d > 30.0 then
                                inc.state = 'idle'
                                applyIdle(inc)
                            end
                        end
                    end
                end
            end
        end
    end
end)

-- floating speech text
CreateThread(function()
    while true do
        local sleep = 500
        local now = GetGameTimer()
        for _, inc in pairs(Sec.Incidents) do
            if inc.speech and inc.ped and DoesEntityExist(inc.ped) then
                if now < inc.speech.untilTime then
                    sleep = 0
                    local c = GetEntityCoords(inc.ped)
                    Sec.Draw3D(vector3(c.x, c.y, c.z + 1.05), inc.speech.text)
                else
                    inc.speech = nil
                end
            end
        end
        Wait(sleep)
    end
end)
