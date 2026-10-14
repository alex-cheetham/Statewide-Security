SWS = SWS or {}

local isServer = IsDuplicityVersion()

function SWS.Debug(...)
    if Config.Debug then
        print(('[statewide_security:%s]'):format(isServer and 'sv' or 'cl'), ...)
    end
end

function SWS.Clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

function SWS.Round(v, places)
    local m = 10 ^ (places or 0)
    return math.floor(v * m + 0.5) / m
end

-- range = { min, max } -> random integer in range
function SWS.RandRange(range)
    return math.random(range[1], range[2])
end

function SWS.Pick(list)
    return list[math.random(1, #list)]
end

-- weights = { key = weight, ... }
function SWS.WeightedPick(weights, filter)
    local total, pool = 0, {}
    for key, w in pairs(weights) do
        if w > 0 and (not filter or filter(key)) then
            total = total + w
            pool[#pool + 1] = { key = key, w = w }
        end
    end
    if total <= 0 then return nil end
    -- sort for deterministic iteration order across runs
    table.sort(pool, function(a, b) return a.key < b.key end)
    local roll = math.random() * total
    for _, entry in ipairs(pool) do
        roll = roll - entry.w
        if roll <= 0 then return entry.key end
    end
    return pool[#pool].key
end

function SWS.GetRank(xp)
    local index = 1
    for i, rank in ipairs(Config.Ranks) do
        if xp >= rank.xp then index = i end
    end
    return index, Config.Ranks[index]
end

function SWS.GetSite(id)
    for i, site in ipairs(Config.Sites) do
        if site.id == id then return site, i end
    end
    return nil
end

function SWS.Dist2D(a, b)
    local dx, dy = a.x - b.x, a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end

function SWS.FormatTime(seconds)
    seconds = math.max(0, math.floor(seconds))
    return ('%02d:%02d'):format(seconds // 60, seconds % 60)
end

-------------------------------------------------------------------------------
-- Lightweight callback system (standalone, no framework dependency)
-------------------------------------------------------------------------------
if isServer then
    local callbacks = {}

    function SWS.RegisterCallback(name, fn)
        callbacks[name] = fn
    end

    RegisterNetEvent('sws:cb:req', function(name, id, ...)
        local src = source
        local fn = callbacks[name]
        if not fn then
            TriggerClientEvent('sws:cb:res', src, id, nil)
            return
        end
        local ok, result = pcall(fn, src, ...)
        if not ok then
            print(('[statewide_security] callback %s errored: %s'):format(name, result))
            result = nil
        end
        TriggerClientEvent('sws:cb:res', src, id, result)
    end)
else
    local pending, nextId = {}, 0

    function SWS.Callback(name, ...)
        nextId = nextId + 1
        local id = nextId
        local p = promise.new()
        pending[id] = p
        TriggerServerEvent('sws:cb:req', name, id, ...)
        SetTimeout(15000, function()
            if pending[id] then
                pending[id] = nil
                p:resolve(nil)
            end
        end)
        return Citizen.Await(p)
    end

    RegisterNetEvent('sws:cb:res', function(id, result)
        local p = pending[id]
        if p then
            pending[id] = nil
            p:resolve(result)
        end
    end)
end
