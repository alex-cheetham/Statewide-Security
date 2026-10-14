-- Site sign-in / sign-out and server-validated checkpoint scanning

SWS.RegisterCallback('sws:site:signIn', function(src, siteId)
    local guard = SWS.GetGuard(src)
    if not guard then return { ok = false, msg = 'Clock on at HQ first.' } end

    local site = SWS.GetSite(siteId)
    if not site then return { ok = false, msg = 'Unknown site.' } end
    if guard.site then return { ok = false, msg = 'You are already assigned to a site. Sign out first.' } end

    local profile = SWS.GetProfile(src)
    if SWS.GetRank(profile.xp) < site.minRank then
        return { ok = false, msg = ('This site requires %s or above.'):format(Config.Ranks[site.minRank].name) }
    end

    local m = site.manager.coords
    if not SWS.Near(src, m, 8.0) then
        return { ok = false, msg = 'Speak to the site contact in person to sign in.' }
    end

    guard.site = site.id
    guard.patrol = { index = 1, lap = 1, lastScan = 0 }
    guard.status = 'On Patrol'
    guard.nextIncidentAt = os.time() + SWS.RandRange(Config.Director.FirstIncidentDelay)

    SWS.ShiftLog(src, ('Signed in at %s'):format(site.label))
    SWS.Radio(src, Dialogue.DispatchLine('siteSignIn', profile.callsign, site.label))
    return { ok = true, site = site.id, index = 1, lap = 1 }
end)

SWS.RegisterCallback('sws:site:signOut', function(src)
    local guard = SWS.GetGuard(src)
    if not guard or not guard.site then return { ok = false, msg = 'You are not signed in to a site.' } end
    local site = SWS.GetSite(guard.site)
    if not SWS.Near(src, site.manager.coords, 8.0) then
        return { ok = false, msg = 'Hand over to the site contact in person.' }
    end
    Incidents.EndAllFor(src, false)
    SWS.ShiftLog(src, ('Signed out of %s'):format(site.label))
    guard.site = nil
    guard.patrol = nil
    guard.status = 'Available'
    return { ok = true }
end)

SWS.RegisterCallback('sws:patrol:scan', function(src, index)
    local guard = SWS.GetGuard(src)
    if not guard or not guard.patrol then return { ok = false, msg = 'No active patrol.' } end
    local site = SWS.GetSite(guard.site)
    local patrol = guard.patrol

    if index ~= patrol.index then
        return { ok = false, msg = 'Checkpoints must be scanned in order.' }
    end

    local now = os.time()
    if now - patrol.lastScan < Config.Patrol.MinSecondsBetweenScans then
        return { ok = false, msg = 'Scanner is still syncing. Try again shortly.' }
    end

    local cp = site.checkpoints[index]
    local coords = SWS.PlayerCoords(src)
    if not coords then return { ok = false } end
    -- 2D distance + loose Z because checkpoint Z is ground-snapped on the client
    if SWS.Dist2D(coords, cp.coords) > Config.Patrol.ScanRadius + 1.5 or math.abs(coords.z - cp.coords.z) > 8.0 then
        return { ok = false, msg = 'You are too far from the checkpoint.' }
    end

    patrol.lastScan = now
    guard.shift.checkpoints = guard.shift.checkpoints + 1
    local profile = SWS.GetProfile(src)
    profile.stats.checkpoints = profile.stats.checkpoints + 1
    SWS.Reward(src, Config.Pay.PerCheckpoint, Config.XP.PerCheckpoint, ('Checkpoint: %s'):format(cp.label))

    local routeComplete = false
    if index >= #site.checkpoints then
        routeComplete = true
        patrol.index = 1
        patrol.lap = patrol.lap + 1
        guard.shift.routes = guard.shift.routes + 1
        profile.stats.routes = profile.stats.routes + 1
        SWS.Reward(src, Config.Pay.RouteComplete, Config.XP.RouteComplete, 'Patrol route complete')
        SWS.ShiftLog(src, ('Completed patrol lap %d at %s'):format(patrol.lap - 1, site.label))
    else
        patrol.index = index + 1
    end
    Storage.MarkGuardsDirty()

    return { ok = true, index = patrol.index, lap = patrol.lap, routeComplete = routeComplete }
end)
