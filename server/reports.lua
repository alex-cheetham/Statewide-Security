-- Incident reports: guards write them, the server grades them, supervisors review them

local function gradeReport(pending, data)
    local grade, feedback = 0, {}

    if data.category == pending.category then
        grade = grade + 0.4
    else
        feedback[#feedback + 1] = ('Wrong category (expected %s)'):format(pending.category)
    end

    if data.outcome == pending.outcome then
        grade = grade + 0.2
    else
        feedback[#feedback + 1] = 'Outcome does not match the incident record'
    end

    local len = #(data.narrative or '')
    if len >= 160 then
        grade = grade + 0.3
    elseif len >= 70 then
        grade = grade + 0.15
        feedback[#feedback + 1] = 'Narrative could be more detailed'
    else
        feedback[#feedback + 1] = 'Narrative too short'
    end

    if pending.subject then
        local named = (data.subjectName or ''):lower()
        if named ~= '' and named == pending.subject.name:lower() then
            grade = grade + 0.1
        else
            feedback[#feedback + 1] = 'Subject was identified but not named correctly'
        end
    else
        grade = grade + 0.1 -- nothing to name
    end

    return SWS.Clamp(grade, 0, 1), feedback
end

local function clean(str, max)
    if type(str) ~= 'string' then return '' end
    str = str:gsub('[<>]', '')
    return str:sub(1, max)
end

SWS.RegisterCallback('sws:reports:submit', function(src, incidentId, data)
    if type(data) ~= 'table' then return { ok = false, msg = 'Invalid report.' } end
    local profile = SWS.GetProfile(src)
    local key = tostring(incidentId)
    local pending = profile.pendingReports[key]
    if not pending then return { ok = false, msg = 'No pending report for that incident.' } end

    data.category = clean(data.category, 40)
    data.outcome = clean(data.outcome, 20)
    data.narrative = clean(data.narrative, 2000)
    data.subjectName = clean(data.subjectName, 60)

    local grade, feedback = gradeReport(pending, data)
    profile.pendingReports[key] = nil
    profile.stats.reports = profile.stats.reports + 1
    Storage.MarkGuardsDirty()

    local _, rank = SWS.GetRank(profile.xp)
    local report = Storage.AddReport({
        incidentId = pending.incidentId,
        author = profile.identifier,
        authorName = GetPlayerName(src),
        callsign = profile.callsign,
        authorRank = rank.name,
        site = pending.site,
        location = pending.location,
        typeLabel = pending.typeLabel,
        category = data.category,
        outcome = data.outcome,
        recordedOutcome = pending.outcome,
        subjectName = data.subjectName,
        narrative = data.narrative,
        timeline = pending.timeline,
        contraband = pending.contraband,
        systemNotes = pending.notes,
        complaint = pending.complaint,
        grade = math.floor(grade * 100 + 0.5),
        feedback = feedback,
        filed = os.time(),
        review = nil,
    })

    local pay, xp = 0, 0
    if SWS.GetGuard(src) then
        pay, xp = SWS.Reward(src, Config.Pay.ReportMax * grade, Config.XP.ReportMax * grade, 'Incident report filed')
    else
        -- off duty: xp still counts, pay is forfeited
        profile.xp = profile.xp + math.floor(Config.XP.ReportMax * grade)
        xp = math.floor(Config.XP.ReportMax * grade)
        Storage.MarkGuardsDirty()
    end

    -- let supervisors know something is waiting for review
    for other in pairs(Guards) do
        if other ~= src and SWS.IsSupervisor(other) then
            SWS.Notify(other, ('New report #%d from %s awaiting review.'):format(report.id, profile.callsign), 'info')
        end
    end

    return { ok = true, id = report.id, grade = report.grade, feedback = feedback, pay = pay, xp = xp }
end)

local function summarise(r)
    return {
        id = r.id,
        callsign = r.callsign,
        authorName = r.authorName,
        authorRank = r.authorRank,
        site = r.site,
        location = r.location,
        typeLabel = r.typeLabel,
        category = r.category,
        outcome = Incidents.OutcomeLabels[r.outcome] or r.outcome,
        subjectName = r.subjectName,
        narrative = r.narrative,
        timeline = r.timeline,
        contraband = r.contraband,
        systemNotes = r.systemNotes,
        complaint = r.complaint,
        grade = r.grade,
        feedback = r.feedback,
        filed = os.date('%Y-%m-%d %H:%M', r.filed),
        review = r.review,
    }
end

SWS.RegisterCallback('sws:reports:list', function(src, scope)
    local profile = SWS.GetProfile(src)
    local list
    if scope == 'all' and SWS.IsSupervisor(src) then
        list = Storage.QueryReports(nil, 60)
    elseif scope == 'unreviewed' and SWS.IsSupervisor(src) then
        list = Storage.QueryReports(function(r) return r.review == nil end, 60)
    else
        list = Storage.QueryReports(function(r) return r.author == profile.identifier end, 30)
    end
    local out = {}
    for _, r in ipairs(list) do out[#out + 1] = summarise(r) end
    return out
end)

SWS.RegisterCallback('sws:reports:review', function(src, reportId, verdict, comment)
    if not SWS.IsSupervisor(src) then return { ok = false, msg = 'Supervisors only.' } end
    local report = Storage.GetReport(tonumber(reportId))
    if not report then return { ok = false, msg = 'Report not found.' } end
    if report.review then return { ok = false, msg = 'Already reviewed.' } end

    local reviewer = SWS.GetProfile(src)
    if report.author == reviewer.identifier then return { ok = false, msg = 'You cannot review your own report.' } end
    if verdict ~= 'approved' and verdict ~= 'returned' and verdict ~= 'commended' then
        return { ok = false, msg = 'Invalid verdict.' }
    end

    report.review = {
        verdict = verdict,
        comment = clean(comment, 500),
        by = reviewer.callsign,
        at = os.date('%Y-%m-%d %H:%M'),
    }
    Storage.MarkReportsDirty()

    local author = Storage.FindGuard(report.author)
    if author then
        local delta = verdict == 'commended' and 20 or (verdict == 'returned' and -10 or 0)
        author.xp = math.max(0, author.xp + delta)
        if verdict == 'commended' then author.stats.commendations = author.stats.commendations + 1 end
        Storage.MarkGuardsDirty()
    end

    -- notify the author if online
    for _, playerId in ipairs(GetPlayers()) do
        local pid = tonumber(playerId)
        if SWS.GetIdentifier(pid) == report.author then
            SWS.Notify(pid, ('Your report #%d was %s by %s.'):format(report.id, verdict, reviewer.callsign),
                verdict == 'returned' and 'error' or 'success')
        end
    end

    -- small reward for doing supervisor work
    if SWS.GetGuard(src) then SWS.Reward(src, 15, 3, 'Report reviewed') end
    return { ok = true }
end)
