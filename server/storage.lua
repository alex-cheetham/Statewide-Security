-- Flat-file JSON persistence (standalone, no database required).
-- Files live in data/ inside the resource folder.

Storage = {}

local resource = GetCurrentResourceName()
local GUARDS_FILE = 'data/guards.json'
local REPORTS_FILE = 'data/reports.json'
local MAX_REPORTS = 1000

local guards = {}
local reports = {}
local nextReportId = 1
local dirtyGuards, dirtyReports = false, false

local function load(path, fallback)
    local raw = LoadResourceFile(resource, path)
    if not raw or raw == '' then return fallback end
    local ok, data = pcall(json.decode, raw)
    if not ok or type(data) ~= 'table' then
        print(('[statewide_security] could not parse %s, starting fresh'):format(path))
        return fallback
    end
    return data
end

local function save(path, data)
    local ok = SaveResourceFile(resource, path, json.encode(data), -1)
    if not ok then
        print(('[statewide_security] failed to write %s (does the data/ folder exist?)'):format(path))
    end
end

local function defaultGuard(identifier, name)
    return {
        identifier = identifier,
        name = name,
        callsign = ('SW-%d'):format(math.random(100, 899)),
        xp = 0,
        earnings = 0,
        shifts = 0,
        stats = {
            checkpoints = 0,
            routes = 0,
            incidents = 0,
            arrests = 0,
            assists = 0,
            complaints = 0,
            reports = 0,
            radioMissed = 0,
            commendations = 0,
        },
        pendingReports = {},
        created = os.time(),
    }
end

function Storage.Init()
    guards = load(GUARDS_FILE, {})
    reports = load(REPORTS_FILE, {})
    for _, r in ipairs(reports) do
        if r.id and r.id >= nextReportId then nextReportId = r.id + 1 end
    end
    local count = 0
    for _ in pairs(guards) do count = count + 1 end
    print(('[statewide_security] loaded %d guard profiles and %d reports'):format(count, #reports))
end

function Storage.GetGuard(identifier, name)
    local g = guards[identifier]
    if not g then
        g = defaultGuard(identifier, name)
        guards[identifier] = g
        dirtyGuards = true
    end
    -- forward-compat for profiles created by older versions
    local defaults = defaultGuard(identifier, name)
    for k, v in pairs(defaults) do
        if g[k] == nil then g[k] = v end
    end
    for k, v in pairs(defaults.stats) do
        if g.stats[k] == nil then g.stats[k] = v end
    end
    if name then g.name = name end
    return g
end

function Storage.FindGuard(identifier)
    return guards[identifier]
end

function Storage.AllGuards()
    return guards
end

function Storage.MarkGuardsDirty()
    dirtyGuards = true
end

function Storage.AddReport(report)
    report.id = nextReportId
    nextReportId = nextReportId + 1
    table.insert(reports, report)
    while #reports > MAX_REPORTS do
        table.remove(reports, 1)
    end
    dirtyReports = true
    return report
end

function Storage.GetReport(id)
    for _, r in ipairs(reports) do
        if r.id == id then return r end
    end
end

-- Returns newest first. filterFn(report) -> bool
function Storage.QueryReports(filterFn, limit)
    local out = {}
    for i = #reports, 1, -1 do
        local r = reports[i]
        if not filterFn or filterFn(r) then
            out[#out + 1] = r
            if limit and #out >= limit then break end
        end
    end
    return out
end

function Storage.MarkReportsDirty()
    dirtyReports = true
end

function Storage.Flush()
    if dirtyGuards then
        save(GUARDS_FILE, guards)
        dirtyGuards = false
    end
    if dirtyReports then
        save(REPORTS_FILE, reports)
        dirtyReports = false
    end
end

CreateThread(function()
    while true do
        Wait(30000)
        Storage.Flush()
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res == resource then Storage.Flush() end
end)

Storage.Init()
