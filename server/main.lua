-- Duty, profiles, rewards, team sync, radio checks, panic, vehicles

Guards = {} -- [src] = runtime state for on-duty guards

local function getIdentifier(src)
    for _, id in ipairs(GetPlayerIdentifiers(src)) do
        if id:sub(1, 8) == 'license:' then return id end
    end
    return GetPlayerIdentifier(src, 0) or ('src:' .. src)
end

local function hasAccess(src)
    local mode = Config.Access.Mode
    if mode == 'open' then return true end
    if mode == 'ace' then return IsPlayerAceAllowed(src, Config.Access.Ace) end
    if mode == 'identifiers' then
        local ids = GetPlayerIdentifiers(src)
        for _, allowed in ipairs(Config.Access.Identifiers) do
            for _, id in ipairs(ids) do
                if id == allowed then return true end
            end
        end
    end
    return false
end

local function playerCoords(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    return GetEntityCoords(ped)
end

local function near(src, point, radius)
    local c = playerCoords(src)
    if not c then return false end
    return #(c - vector3(point.x, point.y, point.z)) <= radius
end

SWS.GetIdentifier = getIdentifier
SWS.PlayerCoords = playerCoords
SWS.Near = near

function SWS.GetProfile(src)
    return Storage.GetGuard(getIdentifier(src), GetPlayerName(src))
end

function SWS.GetGuard(src)
    return Guards[src]
end

function SWS.Notify(src, msg, kind)
    TriggerClientEvent('sws:client:notify', src, msg, kind or 'info')
end

function SWS.Radio(src, msg, from)
    TriggerClientEvent('sws:client:radio', src, from or 'DISPATCH', msg)
end

function SWS.RadioAll(msg, from)
    for src in pairs(Guards) do
        SWS.Radio(src, msg, from)
    end
end

function SWS.IsSupervisor(src)
    local profile = SWS.GetProfile(src)
    local _, rank = SWS.GetRank(profile.xp)
    return rank.supervisor == true or IsPlayerAceAllowed(src, Config.Access.AdminAce)
end

-- Apply rank & site multipliers and credit pay/xp to the active shift
function SWS.Reward(src, pay, xp, reason)
    local guard = Guards[src]
    local profile = SWS.GetProfile(src)
    local oldRank = SWS.GetRank(profile.xp)
    local _, rank = SWS.GetRank(profile.xp)

    local mult = rank.payMult or 1.0
    if guard and guard.site then
        local site = SWS.GetSite(guard.site)
        if site and site.payMult then mult = mult * site.payMult end
    end

    pay = math.floor((pay or 0) * mult + 0.5)
    xp = math.floor(xp or 0)

    profile.xp = math.max(0, profile.xp + xp)
    Storage.MarkGuardsDirty()

    if guard then
        guard.shift.pay = math.max(0, guard.shift.pay + pay)
        guard.shift.xp = guard.shift.xp + xp
    end

    TriggerClientEvent('sws:client:reward', src, { pay = pay, xp = xp, reason = reason, totalXp = profile.xp })

    local newRank, newRankData = SWS.GetRank(profile.xp)
    if newRank ~= oldRank then
        local promoted = newRank > oldRank
        SWS.Notify(src, (promoted and 'Promoted to %s!' or 'Demoted to %s.'):format(newRankData.name), promoted and 'success' or 'error')
        if promoted then
            SWS.RadioAll(('All units, congratulations to %s on promotion to %s.'):format(profile.callsign, newRankData.name))
        end
        TriggerClientEvent('sws:client:rankChanged', src, newRank)
    end
    return pay, xp
end

-------------------------------------------------------------------------------
-- Duty
-------------------------------------------------------------------------------
local function newShift()
    return {
        started = os.time(),
        pay = 0,
        xp = 0,
        checkpoints = 0,
        routes = 0,
        incidents = 0,
        radioChecks = 0,
        log = {},
    }
end

function SWS.ShiftLog(src, text)
    local guard = Guards[src]
    if not guard then return end
    table.insert(guard.shift.log, 1, { t = os.time(), text = text })
    if #guard.shift.log > 40 then table.remove(guard.shift.log) end
end

local function scheduleRadioCheck(guard)
    if not Config.RadioCheck.Enabled then return end
    guard.radio = { nextAt = os.time() + SWS.RandRange(Config.RadioCheck.Interval) }
end

SWS.RegisterCallback('sws:duty:clockOn', function(src)
    if Guards[src] then return { ok = false, msg = 'You are already on duty.' } end
    if not hasAccess(src) then return { ok = false, msg = 'You are not employed by ' .. Config.CompanyName .. '.' } end
    if not near(src, Config.HQ.duty, 6.0) then return { ok = false, msg = 'You must be at the duty point.' } end

    local profile = SWS.GetProfile(src)
    local rankIndex = SWS.GetRank(profile.xp)
    Guards[src] = {
        src = src,
        identifier = profile.identifier,
        shift = newShift(),
        site = nil,
        patrol = nil,
        status = 'Available',
        vehicle = nil,
    }
    scheduleRadioCheck(Guards[src])
    SWS.ShiftLog(src, 'Clocked on at HQ')
    SWS.Radio(src, Dialogue.DispatchLine('clockOn', profile.callsign))
    return { ok = true, callsign = profile.callsign, rank = rankIndex, xp = profile.xp }
end)

local function endShift(src, dropped)
    local guard = Guards[src]
    if not guard then return nil end

    if Incidents.EndAllFor then Incidents.EndAllFor(src, dropped) end

    if guard.vehicle and DoesEntityExist(guard.vehicle) then
        DeleteEntity(guard.vehicle)
    end

    local profile = Storage.GetGuard(guard.identifier)
    local shift = guard.shift
    local duration = os.time() - shift.started
    profile.earnings = profile.earnings + shift.pay
    profile.shifts = profile.shifts + 1
    Storage.MarkGuardsDirty()

    local summary = {
        duration = duration,
        pay = shift.pay,
        xp = shift.xp,
        checkpoints = shift.checkpoints,
        routes = shift.routes,
        incidents = shift.incidents,
        radioChecks = shift.radioChecks,
    }

    local ok, err = pcall(Config.OnPayout, src, shift.pay, summary)
    if not ok then print('[statewide_security] Config.OnPayout error: ' .. tostring(err)) end

    Guards[src] = nil
    TriggerClientEvent('sws:client:teamRemove', -1, src)
    return summary
end

SWS.RegisterCallback('sws:duty:clockOff', function(src)
    if not Guards[src] then return { ok = false, msg = 'You are not on duty.' } end
    if not near(src, Config.HQ.duty, 6.0) then return { ok = false, msg = 'Return to HQ to clock off.' } end
    local profile = SWS.GetProfile(src)
    local summary = endShift(src, false)
    SWS.Radio(src, Dialogue.DispatchLine('clockOff', profile.callsign))
    return { ok = true, summary = summary }
end)

AddEventHandler('playerDropped', function()
    local src = source
    if Guards[src] then endShift(src, true) end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for src in pairs(Guards) do
        local guard = Guards[src]
        if guard.vehicle and DoesEntityExist(guard.vehicle) then DeleteEntity(guard.vehicle) end
    end
end)

-------------------------------------------------------------------------------
-- Vehicles (server-spawned so plates/ownership can be trusted)
-------------------------------------------------------------------------------
SWS.RegisterCallback('sws:vehicle:spawn', function(src, model)
    local guard = Guards[src]
    if not guard then return { ok = false, msg = 'Clock on first.' } end
    if not near(src, Config.HQ.garage, 8.0) then return { ok = false, msg = 'You are not at the garage.' } end

    local entry
    for _, v in ipairs(Config.Vehicles) do
        if v.model == model then entry = v end
    end
    if not entry then return { ok = false, msg = 'Unknown vehicle.' } end

    local profile = SWS.GetProfile(src)
    if SWS.GetRank(profile.xp) < entry.minRank then
        return { ok = false, msg = ('Requires rank: %s'):format(Config.Ranks[entry.minRank].name) }
    end

    if guard.vehicle and DoesEntityExist(guard.vehicle) then
        DeleteEntity(guard.vehicle)
    end

    local s = Config.HQ.vehicleSpawn
    local veh = CreateVehicle(GetHashKey(entry.model), s.x, s.y, s.z, s.w, true, true)
    local timeout = GetGameTimer() + 5000
    while not DoesEntityExist(veh) and GetGameTimer() < timeout do Wait(50) end
    if not DoesEntityExist(veh) then return { ok = false, msg = 'Vehicle failed to spawn.' } end

    local plate = ('%s%03d'):format(Config.VehiclePlatePrefix, math.random(0, 999))
    SetVehicleNumberPlateText(veh, plate)
    guard.vehicle = veh
    return { ok = true, netId = NetworkGetNetworkIdFromEntity(veh), plate = plate }
end)

SWS.RegisterCallback('sws:vehicle:return', function(src)
    local guard = Guards[src]
    if not guard or not guard.vehicle then return { ok = false, msg = 'No company vehicle signed out.' } end
    if DoesEntityExist(guard.vehicle) then
        if #(GetEntityCoords(guard.vehicle) - vector3(Config.HQ.garage.x, Config.HQ.garage.y, Config.HQ.garage.z)) > 20.0 then
            return { ok = false, msg = 'Bring the vehicle back to the garage.' }
        end
        DeleteEntity(guard.vehicle)
    end
    guard.vehicle = nil
    return { ok = true }
end)

-------------------------------------------------------------------------------
-- Team sync: every on-duty guard sees every other on-duty guard
-------------------------------------------------------------------------------
local function teamSnapshot()
    local list = {}
    for src, guard in pairs(Guards) do
        local profile = Storage.GetGuard(guard.identifier)
        local _, rank = SWS.GetRank(profile.xp)
        local c = playerCoords(src)
        local site = guard.site and SWS.GetSite(guard.site)
        list[#list + 1] = {
            src = src,
            name = GetPlayerName(src),
            callsign = profile.callsign,
            rank = rank.name,
            site = site and site.label or nil,
            status = guard.status,
            coords = c and { x = c.x, y = c.y, z = c.z } or nil,
        }
    end
    return list
end
SWS.TeamSnapshot = teamSnapshot

CreateThread(function()
    while true do
        Wait(4000)
        if next(Guards) then
            local snap = teamSnapshot()
            for src in pairs(Guards) do
                TriggerClientEvent('sws:client:team', src, snap)
            end
        end
    end
end)

function SWS.SetStatus(src, status)
    if Guards[src] then Guards[src].status = status end
end

-------------------------------------------------------------------------------
-- Radio checks (AI dispatcher welfare checks)
-------------------------------------------------------------------------------
CreateThread(function()
    while true do
        Wait(5000)
        local now = os.time()
        for src, guard in pairs(Guards) do
            local r = guard.radio
            if r then
                if r.pending and now >= r.deadline then
                    r.pending = nil
                    local profile = Storage.GetGuard(guard.identifier)
                    profile.stats.radioMissed = profile.stats.radioMissed + 1
                    SWS.Reward(src, 0, Config.XP.RadioCheckMissed, 'Missed radio check')
                    SWS.ShiftLog(src, 'Missed a radio check')
                    TriggerClientEvent('sws:client:radioCheckEnd', src)
                    SWS.RadioAll(Dialogue.DispatchLine('radioMissed', profile.callsign))
                    scheduleRadioCheck(guard)
                elseif not r.pending and now >= r.nextAt then
                    local profile = Storage.GetGuard(guard.identifier)
                    r.pending = true
                    r.deadline = now + Config.RadioCheck.ResponseWindow
                    SWS.Radio(src, Dialogue.DispatchLine('radioCheck', profile.callsign))
                    TriggerClientEvent('sws:client:radioCheck', src, Config.RadioCheck.ResponseWindow)
                end
            end
        end
    end
end)

RegisterNetEvent('sws:radio:ack', function()
    local src = source
    local guard = Guards[src]
    if not guard or not guard.radio or not guard.radio.pending then return end
    local profile = SWS.GetProfile(src)
    guard.radio.pending = nil
    guard.shift.radioChecks = guard.shift.radioChecks + 1
    SWS.Reward(src, Config.Pay.RadioCheck, Config.XP.RadioCheck, 'Radio check')
    SWS.Radio(src, Dialogue.DispatchLine('radioAck', profile.callsign))
    TriggerClientEvent('sws:client:radioCheckEnd', src)
    scheduleRadioCheck(guard)
end)

-------------------------------------------------------------------------------
-- Panic button
-------------------------------------------------------------------------------
local lastPanic = {}
RegisterNetEvent('sws:panic', function()
    local src = source
    if not Guards[src] then return end
    if lastPanic[src] and os.time() - lastPanic[src] < 30 then
        SWS.Notify(src, 'Panic button is recharging.', 'error')
        return
    end
    lastPanic[src] = os.time()
    local c = playerCoords(src)
    if not c then return end
    local profile = SWS.GetProfile(src)
    local guard = Guards[src]
    local where = guard.site and SWS.GetSite(guard.site).label or 'their location'
    SWS.ShiftLog(src, 'Activated panic alarm')
    SWS.SetStatus(src, 'PANIC')
    for other in pairs(Guards) do
        TriggerClientEvent('sws:client:panic', other, {
            src = src, callsign = profile.callsign, coords = { x = c.x, y = c.y, z = c.z }, own = other == src,
        })
        SWS.Radio(other, Dialogue.DispatchLine('panic', profile.callsign, where), 'PRIORITY')
    end
    SetTimeout(90000, function()
        if Guards[src] and Guards[src].status == 'PANIC' then SWS.SetStatus(src, 'Available') end
    end)
end)

-------------------------------------------------------------------------------
-- Tablet dashboard
-------------------------------------------------------------------------------
SWS.RegisterCallback('sws:tablet:data', function(src)
    local profile = SWS.GetProfile(src)
    local rankIndex, rank = SWS.GetRank(profile.xp)
    local nextRank = Config.Ranks[rankIndex + 1]
    local guard = Guards[src]

    local sites = {}
    for _, site in ipairs(Config.Sites) do
        sites[#sites + 1] = {
            id = site.id,
            label = site.label,
            minRank = site.minRank,
            minRankName = Config.Ranks[site.minRank].name,
            locked = rankIndex < site.minRank,
            payMult = site.payMult or 1.0,
            briefing = site.briefing,
            checkpoints = #site.checkpoints,
            active = guard and guard.site == site.id or false,
        }
    end

    local shift
    if guard then
        local site = guard.site and SWS.GetSite(guard.site)
        shift = {
            elapsed = os.time() - guard.shift.started,
            pay = guard.shift.pay,
            xp = guard.shift.xp,
            checkpoints = guard.shift.checkpoints,
            routes = guard.shift.routes,
            incidents = guard.shift.incidents,
            radioChecks = guard.shift.radioChecks,
            site = site and site.label or nil,
            patrol = guard.patrol and {
                index = guard.patrol.index,
                total = site and #site.checkpoints or 0,
                lap = guard.patrol.lap,
                next = site and site.checkpoints[guard.patrol.index] and site.checkpoints[guard.patrol.index].label or nil,
            } or nil,
            log = guard.shift.log,
            status = guard.status,
        }
    end

    local categories = {}
    local seen = {}
    for _, t in pairs(Incidents.Types) do
        if not seen[t.category] then
            seen[t.category] = true
            categories[#categories + 1] = t.category
        end
    end
    table.sort(categories)

    local outcomes = {}
    for k, v in pairs(Incidents.OutcomeLabels) do
        outcomes[#outcomes + 1] = { id = k, label = v }
    end
    table.sort(outcomes, function(a, b) return a.label < b.label end)

    local ranks = {}
    for i, r in ipairs(Config.Ranks) do
        ranks[#ranks + 1] = { name = r.name, xp = r.xp, current = i == rankIndex }
    end

    local pending = {}
    for _, p in pairs(profile.pendingReports) do pending[#pending + 1] = p end
    table.sort(pending, function(a, b) return a.time > b.time end)

    return {
        company = Config.CompanyName,
        onDuty = guard ~= nil,
        profile = {
            name = GetPlayerName(src),
            callsign = profile.callsign,
            xp = profile.xp,
            rank = rank.name,
            rankIndex = rankIndex,
            nextRank = nextRank and nextRank.name or nil,
            nextRankXp = nextRank and nextRank.xp or nil,
            rankXp = rank.xp,
            earnings = profile.earnings,
            shifts = profile.shifts,
            stats = profile.stats,
            supervisor = SWS.IsSupervisor(src),
        },
        ranks = ranks,
        shift = shift,
        sites = sites,
        team = guard and teamSnapshot() or {},
        pendingReports = pending,
        categories = categories,
        outcomes = outcomes,
    }
end)

-------------------------------------------------------------------------------
-- Admin
-------------------------------------------------------------------------------
RegisterCommand('secadmin', function(src, args)
    if src ~= 0 and not IsPlayerAceAllowed(src, Config.Access.AdminAce) then return end
    local sub, target, value = args[1], tonumber(args[2]), args[3]
    local function reply(msg)
        if src == 0 then print(msg) else SWS.Notify(src, msg, 'info') end
    end
    if sub == 'setxp' and target and tonumber(value) then
        local profile = SWS.GetProfile(target)
        profile.xp = math.max(0, math.floor(tonumber(value)))
        Storage.MarkGuardsDirty()
        TriggerClientEvent('sws:client:rankChanged', target, SWS.GetRank(profile.xp))
        reply(('Set %s XP to %d'):format(GetPlayerName(target), profile.xp))
    elseif sub == 'callsign' and target and value then
        local profile = SWS.GetProfile(target)
        profile.callsign = value:sub(1, 10)
        Storage.MarkGuardsDirty()
        reply(('Callsign for %s set to %s'):format(GetPlayerName(target), profile.callsign))
    elseif sub == 'incident' and target and value then
        if not Guards[target] or not Guards[target].site then
            reply('That player must be on duty and signed in to a site.')
        elseif not Incidents.Types[value] then
            reply('Unknown incident type.')
        else
            Incidents.Create(target, value)
            reply('Incident created.')
        end
    elseif sub == 'save' then
        Storage.Flush()
        reply('Saved.')
    else
        reply('Usage: secadmin setxp <id> <xp> | callsign <id> <text> | incident <id> <type> | save')
    end
end, false)
