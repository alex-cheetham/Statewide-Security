-- Incident director, hidden subject state (identity, warrants, contraband) and scoring

local Active = {}       -- [id] = incident
local nextId = 1

local function roll(range) return math.random(range[1], range[2]) end

local function nearestCheckpointLabel(site, coords)
    local best, bestDist = site.label, math.huge
    for _, cp in ipairs(site.checkpoints) do
        local d = SWS.Dist2D(cp.coords, coords)
        if d < bestDist then best, bestDist = cp.label, d end
    end
    return best
end

local function makeIdentity()
    local year = math.random(1960, 2005)
    return {
        name = ('%s %s'):format(SWS.Pick(Incidents.FirstNames), SWS.Pick(Incidents.LastNames)),
        dob = ('%02d/%02d/%d'):format(math.random(1, 28), math.random(1, 12), year),
        idNumber = ('SA-%07d'):format(math.random(0, 9999999)),
    }
end

local function countFor(src)
    local n = 0
    for _, inc in pairs(Active) do
        if inc.owner == src and not inc.closed then n = n + 1 end
    end
    return n
end

function Incidents.Create(src, forcedType)
    local guard = SWS.GetGuard(src)
    if not guard or not guard.site then return nil end
    local site = SWS.GetSite(guard.site)
    local profile = SWS.GetProfile(src)
    local rankIndex = SWS.GetRank(profile.xp)

    local typeKey = forcedType or SWS.WeightedPick(site.incidents, function(key)
        local t = Incidents.Types[key]
        return t and (t.minRank or 1) <= rankIndex
    end)
    if not typeKey then return nil end
    local def = Incidents.Types[typeKey]

    local spawn = SWS.Pick(site.spawns)
    local armed = math.random() < def.armedChance and #def.weapons > 0
    local fakeId = (typeKey == 'suspicious' or typeKey == 'burglar') and math.random() < 0.15

    local contraband = {}
    for _, c in ipairs(def.contraband) do
        if math.random() < c.chance then contraband[#contraband + 1] = c.item end
    end
    if armed then
        local w = SWS.Pick(def.weapons)
        contraband[#contraband + 1] = ('Weapon (%s)'):format(w:gsub('WEAPON_', ''):lower())
    end

    local inc = {
        id = nextId,
        owner = src,
        type = typeKey,
        site = site.id,
        spawn = { x = spawn.x, y = spawn.y, z = spawn.z, w = spawn.w },
        location = nearestCheckpointLabel(site, spawn),
        model = SWS.Pick(def.models),
        profile = {
            compliance = roll(def.profile.compliance),
            aggression = roll(def.profile.aggression),
            flight = roll(def.profile.flight),
            stress = roll(def.profile.stress),
        },
        armed = armed,
        weapon = armed and SWS.Pick(def.weapons) or nil,
        identity = makeIdentity(),
        fakeId = fakeId,
        warrant = (not fakeId and math.random() < def.warrantChance) and SWS.Pick(Incidents.Warrants) or nil,
        contraband = contraband,
        created = os.time(),
        timeline = {},
    }
    nextId = nextId + 1
    Active[inc.id] = inc

    local function stamp(text) table.insert(inc.timeline, { t = os.time(), text = text }) end
    inc.stamp = stamp
    stamp(('Dispatched: %s at %s'):format(def.label, inc.location))

    guard.status = ('Responding: %s'):format(def.label)
    SWS.ShiftLog(src, ('Dispatched to %s (%s)'):format(def.label, inc.location))

    -- what the client is allowed to know up-front
    TriggerClientEvent('sws:client:incidentNew', src, {
        id = inc.id,
        type = typeKey,
        label = def.label,
        priority = def.priority,
        site = site.id,
        spawn = inc.spawn,
        location = inc.location,
        model = inc.model,
        profile = inc.profile,
        armed = inc.armed,
        weapon = inc.weapon,
        dispatch = SWS.Pick(def.dispatch):format(inc.location),
    })
    return inc
end

local function getOwned(src, id)
    local inc = Active[id]
    if not inc or inc.owner ~= src or inc.closed then return nil end
    return inc
end

-- Director loop
CreateThread(function()
    while true do
        Wait(5000)
        local now = os.time()
        for src, guard in pairs(Guards) do
            if guard.patrol and guard.nextIncidentAt and now >= guard.nextIncidentAt then
                guard.nextIncidentAt = now + SWS.RandRange(Config.Director.Interval)
                if countFor(src) < Config.Director.MaxActivePerGuard and math.random() < Config.Director.Chance then
                    Incidents.Create(src)
                end
            end
        end
        -- expire stale incidents
        for id, inc in pairs(Active) do
            if not inc.closed and now - inc.created > Config.Director.IncidentTimeout then
                inc.closed = true
                TriggerClientEvent('sws:client:incidentEnd', inc.owner, id, 'timeout')
                SWS.Radio(inc.owner, ('Incident #%d at %s closed: not attended.'):format(id, inc.location))
                if SWS.GetGuard(inc.owner) then SWS.SetStatus(inc.owner, 'On Patrol') end
                Active[id] = nil
            elseif inc.closed and now - inc.created > Config.Director.IncidentTimeout * 2 then
                Active[id] = nil
            end
        end
    end
end)

function Incidents.EndAllFor(src, dropped)
    for id, inc in pairs(Active) do
        if inc.owner == src and not inc.closed then
            inc.closed = true
            if not dropped then TriggerClientEvent('sws:client:incidentEnd', src, id, 'cancelled') end
            Active[id] = nil
        end
    end
end

-------------------------------------------------------------------------------
-- Interaction callbacks (hidden info is only revealed through these)
-------------------------------------------------------------------------------
RegisterNetEvent('sws:incident:log', function(id, text)
    local inc = getOwned(source, id)
    if not inc or type(text) ~= 'string' then return end
    if #inc.timeline < 60 then inc.stamp(text:sub(1, 140)) end
end)

RegisterNetEvent('sws:incident:engage', function(id)
    local src = source
    local inc = getOwned(src, id)
    if not inc or inc.engaged then return end
    inc.engaged = true
    inc.engagedAt = os.time()
    inc.stamp('Guard on scene, contact made')
    SWS.SetStatus(src, ('On scene: %s'):format(Incidents.Types[inc.type].label))
end)

SWS.RegisterCallback('sws:incident:showId', function(src, id)
    local inc = getOwned(src, id)
    if not inc then return nil end
    inc.idShown = true
    inc.stamp(('Subject produced ID: %s'):format(inc.identity.name))
    return inc.identity
end)

SWS.RegisterCallback('sws:incident:runId', function(src, id)
    local inc = getOwned(src, id)
    if not inc or not inc.idShown then return nil end
    Wait(math.random(2500, 5000)) -- dispatcher "running" the name
    if inc.closed then return nil end
    inc.idChecked = true
    local profile = SWS.GetProfile(src)
    local msg, status
    if inc.fakeId then
        status = 'unknown'
        msg = Dialogue.DispatchLine('idUnknown', profile.callsign)
        inc.stamp('ID check: no record found (possible false ID)')
    elseif inc.warrant then
        status = 'warrant'
        msg = Dialogue.DispatchLine('idWarrant', profile.callsign, inc.identity.name, inc.warrant)
        inc.stamp(('ID check: active warrant (%s)'):format(inc.warrant))
    else
        status = 'clear'
        msg = Dialogue.DispatchLine('idClear', profile.callsign, inc.identity.name)
        inc.stamp('ID check: clear')
    end
    SWS.Radio(src, msg)
    return { status = status, warrant = inc.warrant }
end)

SWS.RegisterCallback('sws:incident:search', function(src, id)
    local inc = getOwned(src, id)
    if not inc then return nil end
    inc.searched = true
    if #inc.contraband > 0 then
        inc.stamp(('Search found: %s'):format(table.concat(inc.contraband, ', ')))
    else
        inc.stamp('Search: nothing found')
    end
    return inc.contraband
end)

local function eta() return SWS.RandRange(Config.Response.EtaSeconds) end

SWS.RegisterCallback('sws:incident:callPolice', function(src, id)
    local inc = getOwned(src, id)
    if not inc then return nil end
    if inc.policeCalled then return { eta = 0, already = true } end
    inc.policeCalled = true
    local t = eta()
    inc.stamp('Police requested')
    SWS.Radio(src, Dialogue.DispatchLine('policeEnRoute', t))
    return { eta = t }
end)

SWS.RegisterCallback('sws:incident:callEms', function(src, id)
    local inc = getOwned(src, id)
    if not inc then return nil end
    if inc.emsCalled then return { eta = 0, already = true } end
    inc.emsCalled = true
    local t = eta()
    inc.stamp('EMS requested')
    SWS.Radio(src, Dialogue.DispatchLine('emsEnRoute', t))
    return { eta = t }
end)

-------------------------------------------------------------------------------
-- Scoring
-------------------------------------------------------------------------------
local function score(inc, outcome, flags)
    local def = Incidents.Types[inc.type]
    local mult = def.outcomes[outcome] or 0
    local notes, complaint = {}, nil

    if outcome == 'fatality' then
        if inc.armed and flags.armedThreat then
            mult = 0.25
            notes[#notes + 1] = 'Lethal force against an armed subject - referred for review'
        else
            mult = 0
            complaint = 'Death of an unarmed subject'
        end
    elseif outcome == 'guard_down' then
        mult = 0.1
        notes[#notes + 1] = 'Guard was incapacitated - review officer safety'
    elseif outcome == 'escaped' then
        local profile = SWS.GetProfile(inc.owner)
        SWS.Radio(inc.owner, Dialogue.DispatchLine('escaped', profile.callsign))
    end

    if def.benign and flags.detained then
        complaint = complaint or 'Wrongful detention of a member of the public'
        mult = mult * 0.3
    end

    if flags.usedForce and not flags.resisted and not def.collapsed then
        complaint = complaint or 'Excessive force against a compliant subject'
        mult = mult * 0.4
    end

    if inc.warrant then
        if outcome == 'handed_police' then
            mult = mult + 0.15
            notes[#notes + 1] = 'Wanted subject handed to police'
        elseif inc.idChecked then
            mult = mult * 0.4
            notes[#notes + 1] = 'Subject with a known warrant was let go'
        else
            mult = mult * 0.85
            notes[#notes + 1] = 'Subject had a warrant - ID was never run'
        end
    end

    if inc.searched and #inc.contraband > 0 and outcome == 'handed_police' then
        mult = mult + 0.1
        notes[#notes + 1] = 'Evidence recovered'
    end

    if def.collapsed then
        if flags.firstAid then
            mult = mult + 0.1
            notes[#notes + 1] = 'First aid rendered'
        else
            notes[#notes + 1] = 'No first aid given'
            mult = mult * 0.8
        end
    end

    if flags.deescalated then
        mult = mult + 0.1
        notes[#notes + 1] = 'Good de-escalation'
    end
    if (tonumber(flags.escalations) or 0) >= 2 then
        mult = mult - 0.1
        notes[#notes + 1] = 'Situation escalated repeatedly'
    end

    -- reward quick response
    local responseTime = (inc.engagedAt or os.time()) - inc.created
    if inc.engaged and responseTime < 90 and outcome ~= 'timeout' then
        mult = mult + 0.05
        notes[#notes + 1] = 'Fast response'
    end

    return SWS.Clamp(mult, 0, 1.25), notes, complaint
end

SWS.RegisterCallback('sws:incident:resolve', function(src, id, outcome, flags)
    local inc = getOwned(src, id)
    if not inc then return nil end
    if not Incidents.OutcomeLabels[outcome] then return nil end
    flags = type(flags) == 'table' and flags or {}

    -- outcomes that require the service to have actually been requested
    if outcome == 'handed_police' and not inc.policeCalled then outcome = 'released' end
    if outcome == 'handed_ems' and not inc.emsCalled then outcome = 'assisted' end

    -- must be reasonably close unless the subject fled or the guard went down
    if outcome ~= 'escaped' and outcome ~= 'guard_down' then
        local c = SWS.PlayerCoords(src)
        if not c or SWS.Dist2D(c, inc.spawn) > 250.0 then
            return nil
        end
    end

    inc.closed = true
    local def = Incidents.Types[inc.type]
    local mult, notes, complaint = score(inc, outcome, flags)
    inc.stamp(('Closed: %s'):format(Incidents.OutcomeLabels[outcome]))

    local pay = Config.Pay.IncidentMax * mult
    local xp = Config.XP.IncidentMax * mult

    local profile = SWS.GetProfile(src)
    profile.stats.incidents = profile.stats.incidents + 1
    if outcome == 'handed_police' then profile.stats.arrests = profile.stats.arrests + 1 end
    if outcome == 'assisted' or outcome == 'handed_ems' then profile.stats.assists = profile.stats.assists + 1 end
    if complaint then
        profile.stats.complaints = profile.stats.complaints + 1
        xp = xp + Config.XP.Complaint
        pay = 0
    end

    local guard = SWS.GetGuard(src)
    if guard then
        guard.shift.incidents = guard.shift.incidents + 1
        guard.status = guard.patrol and 'On Patrol' or 'Available'
    end
    local paid, gained = SWS.Reward(src, pay, xp, ('Incident: %s'):format(def.label))
    SWS.ShiftLog(src, ('Closed %s: %s'):format(def.label, Incidents.OutcomeLabels[outcome]))

    -- queue an incident report for the guard to write
    local timeline = {}
    for _, e in ipairs(inc.timeline) do
        timeline[#timeline + 1] = ('[%s] %s'):format(os.date('%H:%M:%S', e.t), e.text)
    end
    profile.pendingReports[tostring(inc.id)] = {
        incidentId = inc.id,
        type = inc.type,
        typeLabel = def.label,
        category = def.category,
        site = SWS.GetSite(inc.site).label,
        location = inc.location,
        outcome = outcome,
        subject = inc.idShown and inc.identity or nil,
        contraband = inc.searched and inc.contraband or nil,
        timeline = timeline,
        notes = notes,
        complaint = complaint,
        time = os.time(),
    }
    Storage.MarkGuardsDirty()

    Active[id] = nil
    return {
        outcome = outcome,
        outcomeLabel = Incidents.OutcomeLabels[outcome],
        rating = math.floor(SWS.Clamp(mult, 0, 1) * 100 + 0.5),
        pay = paid,
        xp = gained,
        notes = notes,
        complaint = complaint,
    }
end)

