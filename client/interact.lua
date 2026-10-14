-- Talking to incident NPCs: dialogue engine, ID checks, searches, detain, tackle, escort

local openDialog = nil -- incident id whose panel is open

local function roll(inc, threshold)
    return Sec.Willingness(inc) + math.random(-15, 15) >= threshold
end

local function say(inc, key)
    Sec.Say(inc, Dialogue.Line(inc.type, key))
end

local function system(inc, text)
    SendNUIMessage({ action = 'dialogLine', id = inc.id, who = 'system', text = text })
end

-------------------------------------------------------------------------------
-- Which actions make sense right now
-------------------------------------------------------------------------------
local function availableActions(inc)
    local s, list = inc.state, {}
    local function add(key, extra)
        local a = Dialogue.Actions[key]
        list[#list + 1] = { id = key, label = extra or a.label, tone = a.tone }
    end

    if s == 'collapsed' then
        add('check_vitals')
        if inc.vitals then add('first_aid') end
        if not inc.emsCalled then add('call_ems') end
        if not inc.policeCalled then add('call_police') end
        return list
    end

    if s == 'subdued' or s == 'detained' or s == 'escorted' then
        if s == 'subdued' then add('detain') end
        add('reassure')
        if not inc.idShown then add('request_id') end
        if inc.idShown and not inc.idStatus then add('run_id') end
        if not inc.searched then add('search') end
        if not inc.policeCalled then add('call_police') end
        if inc.type == 'intoxicated' and not inc.emsCalled then add('call_ems') end
        if s ~= 'subdued' then add('escort') end
        add('release', s ~= 'subdued' and 'Remove cuffs & release' or 'Let them go')
        return list
    end

    add('greet')
    add('ask_purpose')
    if inc.profile.stress >= 35 then add('reassure') end
    add('explain_rules')
    if not inc.idShown then add('request_id') end
    if inc.idShown and not inc.idStatus then add('run_id') end
    add('offer_help')
    add('ask_leave')
    if not inc.warned then add('trespass_warn') end
    add('order_stop')
    add('threaten')
    if not inc.searched then add('search', 'Request consent to search') end
    add('detain')
    if not inc.policeCalled then add('call_police') end
    if (inc.type == 'intoxicated' or inc.type == 'medical') and not inc.emsCalled then add('call_ems') end
    add('release', 'Dismiss (let them stay)')
    return list
end

local function panelData(inc)
    local demeanor, color = Sec.Demeanor(inc)
    return {
        id = inc.id,
        label = inc.label,
        location = inc.location,
        subject = inc.identity and inc.identity.name or 'Unknown subject',
        dob = inc.identity and inc.identity.dob or nil,
        idNumber = inc.identity and inc.identity.idNumber or nil,
        idStatus = inc.idStatus,
        warrant = inc.warrant,
        contraband = inc.contraband,
        demeanor = demeanor,
        demeanorColor = color,
        cooperation = Sec.Cooperation(inc),
        state = inc.state,
        actions = availableActions(inc),
        policeCalled = inc.policeCalled,
        emsCalled = inc.emsCalled,
    }
end

local function refreshPanel(inc)
    if openDialog == inc.id then
        SendNUIMessage({ action = 'dialogUpdate', data = panelData(inc) })
    end
end

function Sec.CloseDialog(id)
    if openDialog and (not id or openDialog == id) then
        openDialog = nil
        SetNuiFocus(false, false)
        SendNUIMessage({ action = 'dialog', open = false })
    end
end

local function openPanel(inc)
    openDialog = inc.id
    if inc.state == 'idle' then Sec.SetState(inc, 'engaged') end
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'dialog', open = true, data = panelData(inc) })
end

-------------------------------------------------------------------------------
-- Physical actions
-------------------------------------------------------------------------------
local function playerAnim(dict, anim, duration, flag)
    if Sec.LoadAnim(dict) then
        TaskPlayAnim(PlayerPedId(), dict, anim, 8.0, -8.0, duration, flag or 0, 0, false, false, false)
    end
end

local function cuff(inc)
    local player = PlayerPedId()
    TaskTurnPedToFaceEntity(player, inc.ped, 800)
    Wait(600)
    playerAnim('mp_arresting', 'a_uncuff', 3000, 49)
    PlaySoundFrontend(-1, 'Lose_1st', 'GTAO_FM_Events_Soundset', true)
    Wait(2500)
    ClearPedTasks(player)
    Sec.SetState(inc, 'detained')
end

local function startEscort(inc)
    if inc.state == 'escorted' then
        Sec.SetState(inc, 'detained')
        Sec.Notify('You let go of the subject.', 'info')
    else
        Sec.SetState(inc, 'escorted')
        Sec.Notify('Escorting. [E] let go  [G] place in nearest vehicle', 'info')
    end
end

local function nearestVehicle(radius)
    local pos = Sec.PlayerPos()
    local best, bestDist = nil, radius
    for _, veh in ipairs(GetGamePool('CVehicle')) do
        local d = #(pos - GetEntityCoords(veh))
        if d < bestDist then best, bestDist = veh, d end
    end
    return best
end

local function placeInVehicle(inc)
    local veh = nearestVehicle(6.0)
    if not veh then
        Sec.Notify('No vehicle nearby.', 'error')
        return
    end
    for _, seat in ipairs({ 1, 2, 0 }) do
        if IsVehicleSeatFree(veh, seat) then
            DetachEntity(inc.ped, true, false)
            inc.state = 'detained'
            SetPedIntoVehicle(inc.ped, veh, seat)
            inc.vehicle = veh
            Sec.Log(inc, 'Subject secured in vehicle')
            Sec.Notify('Subject secured in the vehicle.', 'success')
            return
        end
    end
    Sec.Notify('No free seats in that vehicle.', 'error')
end

local function tackle(inc)
    local player = PlayerPedId()
    inc.flags.usedForce = true
    SetPedToRagdoll(player, 1200, 1200, 0, false, false, false)
    if math.random() < 0.75 then
        SetPedToRagdoll(inc.ped, 4000, 4000, 0, false, false, false)
        Sec.Log(inc, 'Subject tackled to the ground')
        Wait(2500)
        Sec.SetState(inc, 'subdued')
    else
        Sec.Notify('You missed the tackle!', 'error')
    end
end

-------------------------------------------------------------------------------
-- Dialogue engine
-------------------------------------------------------------------------------
local function doAction(inc, key)
    local a = Dialogue.Actions[key]
    if not a then return end
    local p = inc.profile
    local restrained = inc.state == 'detained' or inc.state == 'subdued' or inc.state == 'escorted'

    p.stress = SWS.Clamp(p.stress + a.stress, 0, 100)
    inc.rapport = SWS.Clamp(inc.rapport + a.rapport, -30, 30)
    inc.lastAction = GetGameTimer()
    SendNUIMessage({ action = 'dialogLine', id = inc.id, who = 'guard', text = a.label })
    Sec.Log(inc, ('Guard: %s'):format(a.label))

    if key == 'greet' then
        say(inc, Sec.Willingness(inc) >= 35 and 'greet_ok' or 'greet_cold')

    elseif key == 'ask_purpose' then
        say(inc, 'purpose')

    elseif key == 'reassure' then
        if roll(inc, 25) then
            p.stress = math.max(0, p.stress - 8)
            say(inc, restrained and 'restrained' or 'reassure_ok')
        else
            say(inc, 'reassure_fail')
        end

    elseif key == 'explain_rules' then
        p.compliance = math.min(100, p.compliance + 5)
        say(inc, 'rules')

    elseif key == 'request_id' then
        if restrained or roll(inc, 40) then
            local identity = SWS.Callback('sws:incident:showId', inc.id)
            if identity then
                inc.identity = identity
                inc.idShown = true
                say(inc, 'id_show')
                system(inc, ('ID: %s | DOB %s | %s'):format(identity.name, identity.dob, identity.idNumber))
            end
        else
            p.stress = math.min(100, p.stress + 5)
            say(inc, 'id_refuse')
        end

    elseif key == 'run_id' then
        system(inc, 'Running details with dispatch...')
        refreshPanel(inc)
        local res = SWS.Callback('sws:incident:runId', inc.id)
        if not res or not Sec.Incidents[inc.id] then return end
        inc.idStatus = res.status
        inc.warrant = res.warrant
        if res.status == 'warrant' then
            system(inc, ('WARRANT: %s'):format(res.warrant))
            if not restrained then
                -- they heard that on your radio
                p.stress = math.min(100, p.stress + 25)
                if p.flight >= 40 and not roll(inc, 50) then
                    say(inc, 'escalate_flee')
                    Sec.SetState(inc, 'fleeing')
                end
            end
        elseif res.status == 'unknown' then
            system(inc, 'No record found - possible false ID')
            p.stress = math.min(100, p.stress + 10)
        else
            system(inc, 'Subject is clear')
        end

    elseif key == 'offer_help' then
        if inc.type == 'lost' or (inc.type == 'intoxicated' and roll(inc, 30)) or (inc.type == 'aggressive' and p.stress < 50) then
            say(inc, 'help_thanks')
            inc.leaveOutcome = 'assisted'
            Sec.Log(inc, 'Subject assisted and directed off site')
            Sec.SetState(inc, 'leaving')
        else
            say(inc, 'help_decline')
        end

    elseif key == 'ask_leave' then
        local threshold = 45 - (inc.warned and 15 or 0)
        if inc.type == 'lost' or roll(inc, threshold) then
            say(inc, 'leave_ok')
            inc.leaveOutcome = inc.type == 'lost' and 'assisted' or 'left_site'
            Sec.SetState(inc, 'leaving')
        else
            say(inc, 'leave_refuse')
        end

    elseif key == 'trespass_warn' then
        inc.warned = true
        p.compliance = math.min(100, p.compliance + 10)
        say(inc, 'warned')
        if not inc.idShown then system(inc, 'Tip: warnings carry more weight once the subject is identified.') end

    elseif key == 'order_stop' then
        if roll(inc, 35) then
            p.compliance = math.min(100, p.compliance + 8)
            say(inc, 'order_ok')
        else
            say(inc, 'order_defy')
        end

    elseif key == 'threaten' then
        p.compliance = math.min(100, p.compliance + 5)
        say(inc, 'threaten')
        if inc.def.benign then inc.flags.usedForce = true end

    elseif key == 'search' then
        if restrained or roll(inc, 60) then
            if not restrained then say(inc, 'search_consent') end
            playerAnim('anim@gangops@facility@servers@bodysearch@', 'player_search', 4000, 48)
            Wait(4000)
            local items = SWS.Callback('sws:incident:search', inc.id)
            if not Sec.Incidents[inc.id] then return end
            inc.searched = true
            inc.contraband = items or {}
            if #inc.contraband > 0 then
                system(inc, ('Found: %s'):format(table.concat(inc.contraband, ', ')))
                if not restrained then
                    p.stress = math.min(100, p.stress + 20)
                    if inc.armed then
                        inc.flags.armedThreat = true
                        say(inc, 'escalate_fight')
                        Sec.SetState(inc, 'fighting')
                    end
                end
            else
                system(inc, 'Nothing found.')
            end
        else
            say(inc, 'search_refuse')
        end

    elseif key == 'detain' then
        if inc.state == 'subdued' or inc.def.benign or p.compliance >= 80 or roll(inc, 55) then
            say(inc, 'detain_ok')
            Sec.CloseDialog(inc.id)
            cuff(inc)
            return
        end
        Sec.CloseDialog(inc.id)
        if p.aggression >= p.flight then
            say(inc, 'detain_fight')
            Sec.SetState(inc, 'fighting')
        else
            say(inc, 'detain_flee')
            Sec.SetState(inc, 'fleeing')
        end
        return

    elseif key == 'check_vitals' then
        inc.vitals = true
        playerAnim('amb@medic@standing@tendtodead@idle_a', 'idle_a', 3500, 1)
        Wait(3500)
        ClearPedTasks(PlayerPedId())
        system(inc, 'Breathing is shallow, pulse weak. Subject needs medical attention.')

    elseif key == 'first_aid' then
        Sec.CloseDialog(inc.id)
        playerAnim('mini@cpr@char_a@cpr_str', 'cpr_pumpchest', 8000, 1)
        Wait(8000)
        ClearPedTasks(PlayerPedId())
        inc.flags.firstAid = true
        Sec.Log(inc, 'First aid rendered')
        Sec.Notify('First aid given. Keep them stable until EMS arrive.', 'success')
        return

    elseif key == 'call_police' then
        local res = SWS.Callback('sws:incident:callPolice', inc.id)
        if res and not res.already then
            inc.policeCalled = true
            Sec.SpawnResponse('police', inc, res.eta)
            if not inc.def.collapsed then say(inc, 'police_called') end
            if not restrained and not inc.def.benign and p.flight >= 50 and not roll(inc, 55) then
                say(inc, 'escalate_flee')
                Sec.SetState(inc, 'fleeing')
            end
        end

    elseif key == 'call_ems' then
        local res = SWS.Callback('sws:incident:callEms', inc.id)
        if res and not res.already then
            inc.emsCalled = true
            Sec.SpawnResponse('ems', inc, res.eta)
            if not inc.def.collapsed then say(inc, 'ems_called') end
        end

    elseif key == 'escort' then
        Sec.CloseDialog(inc.id)
        startEscort(inc)
        return

    elseif key == 'release' then
        say(inc, 'released')
        Sec.CloseDialog(inc.id)
        Sec.ResolveIncident(inc, (inc.type == 'lost') and 'assisted' or 'released')
        return
    end

    if Sec.Incidents[inc.id] and not Sec.TalkStates[inc.state] then
        -- they walked off / ran / attacked
        Sec.CloseDialog(inc.id)
        return
    end
    if Sec.CheckEscalation(inc) then
        Sec.CloseDialog(inc.id)
        return
    end
    refreshPanel(inc)
end

local busy = false
RegisterNUICallback('dialogAction', function(data, reply)
    reply('ok')
    local inc = Sec.Incidents[data.id]
    if not inc or busy or inc.resolving then return end
    busy = true
    CreateThread(function()
        local ok, err = pcall(doAction, inc, data.action)
        if not ok then print('[statewide_security] dialog error: ' .. tostring(err)) end
        if Sec.Incidents[inc.id] then refreshPanel(inc) end
        busy = false
    end)
end)

RegisterNUICallback('dialogClose', function(_, reply)
    reply('ok')
    Sec.CloseDialog()
end)

-------------------------------------------------------------------------------
-- Proximity prompts
-------------------------------------------------------------------------------
CreateThread(function()
    while true do
        local sleep = 500
        if next(Sec.Incidents) and not openDialog then
            local player = PlayerPedId()
            local ppos = GetEntityCoords(player)
            local inVeh = IsPedInAnyVehicle(player, false)

            for _, inc in pairs(Sec.Incidents) do
                local ped = inc.ped
                if ped and DoesEntityExist(ped) and not inc.resolving and not inVeh then
                    local d = #(ppos - GetEntityCoords(ped))
                    if d < 20.0 then sleep = 0 end

                    if inc.state == 'escorted' then
                        sleep = 0
                        Sec.HelpText('~INPUT_CONTEXT~ Let go   ~INPUT_DETONATE~ Place in vehicle   ~INPUT_COVER~ Talk')
                        if IsControlJustReleased(0, Config.Keys.Interact) then
                            startEscort(inc)
                        elseif IsControlJustReleased(0, 47) then
                            placeInVehicle(inc)
                        elseif IsControlJustReleased(0, 44) then
                            openPanel(inc)
                        end
                        break
                    elseif inc.state == 'fleeing' and d < Config.TackleDistance then
                        Sec.HelpText('~INPUT_CONTEXT~ Tackle')
                        if IsControlJustPressed(0, Config.Keys.Interact) then
                            CreateThread(function() tackle(inc) end)
                        end
                    elseif inc.state == 'detained' and inc.vehicle and IsPedInAnyVehicle(ped, false) and d < 4.0 then
                        Sec.HelpText('~INPUT_CONTEXT~ Take subject out of vehicle')
                        if IsControlJustReleased(0, Config.Keys.Interact) then
                            TaskLeaveVehicle(ped, inc.vehicle, 16)
                            inc.vehicle = nil
                        end
                    elseif Sec.TalkStates[inc.state] and d < 2.5 then
                        local label = inc.state == 'collapsed' and 'Attend to patient' or 'Speak with subject'
                        Sec.HelpText(('~INPUT_CONTEXT~ %s'):format(label))
                        if IsControlJustReleased(0, Config.Keys.Interact) then openPanel(inc) end
                    end
                end
            end
        end
        Wait(sleep)
    end
end)
