Config = {}

Config.Debug = false            -- prints extra info and enables /secpos
Config.CompanyName = 'Statewide Security'

-------------------------------------------------------------------------------
-- Access
-------------------------------------------------------------------------------
-- 'open'        : anyone can clock on
-- 'ace'         : requires ACE permission Config.Access.Ace (add_ace group.security statewide.security allow)
-- 'identifiers' : only identifiers listed in Config.Access.Identifiers
Config.Access = {
    Mode = 'open',
    Ace = 'statewide.security',
    AdminAce = 'statewide.security.admin',  -- can use /secadmin commands
    Identifiers = {
        -- 'license:xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx',
    },
}

-------------------------------------------------------------------------------
-- Ranks & progression
-------------------------------------------------------------------------------
Config.Ranks = {
    { name = 'Trainee Guard',     xp = 0,     payMult = 1.00 },
    { name = 'Security Officer',  xp = 600,   payMult = 1.15 },
    { name = 'Senior Officer',    xp = 1800,  payMult = 1.30 },
    { name = 'Field Supervisor',  xp = 4000,  payMult = 1.50, supervisor = true },
    { name = 'Site Manager',      xp = 8000,  payMult = 1.75, supervisor = true },
}

-------------------------------------------------------------------------------
-- Pay (standalone: pay is tracked and handed to Config.OnPayout on clock-off)
-------------------------------------------------------------------------------
Config.Pay = {
    PerCheckpoint = 20,
    RouteComplete = 120,
    RadioCheck = 10,
    IncidentMax = 250,     -- best possible incident outcome before rank multiplier
    ReportMax = 80,
}

Config.XP = {
    PerCheckpoint = 4,
    RouteComplete = 25,
    RadioCheck = 2,
    RadioCheckMissed = -10,
    IncidentMax = 60,
    ReportMax = 30,
    Complaint = -40,       -- excessive force / wrongful detention
}

-- Hook your own economy here. Called server-side when a guard clocks off.
Config.OnPayout = function(src, amount, summary)
    -- e.g. exports['my_bank']:AddMoney(src, amount)
end

-------------------------------------------------------------------------------
-- Headquarters
-------------------------------------------------------------------------------
Config.HQ = {
    label = 'Statewide Security HQ',
    duty = vector3(215.9, -809.8, 30.73),
    locker = vector3(212.4, -806.3, 30.86),
    garage = vector3(222.7, -804.2, 30.66),
    vehicleSpawn = vector4(229.6, -800.4, 30.57, 160.0),
    blip = { sprite = 487, color = 38, scale = 0.85 },
}

-- extrasOff = true turns off every vehicle extra (lightbars, pushbars, etc.) on spawn
Config.Vehicles = {
    { model = 'sec11vicyw',     label = '2011 Ford Crown Victoria',     minRank = 1, extrasOff = true, description = 'Classic patrol car for mobile security.' },
    { model = 'sec18chargeryw', label = '2018 Dodge Charger',           minRank = 1, extrasOff = true, description = 'Patrol car for mobile security.' },
    { model = 'sec16fpiuyw',    label = '2016 Ford Interceptor Utility', minRank = 2, extrasOff = true, description = 'Patrol SUV for site and mobile security.' },
    { model = 'sec21fpiuyw',    label = '2021 Ford Interceptor Utility', minRank = 2, extrasOff = true, description = 'Patrol SUV for site and mobile security.' },
    { model = 'sec21durangoyw', label = '2021 Dodge Durango',           minRank = 2, extrasOff = true, description = 'Patrol SUV.' },
    { model = 'sec19tahoeyw',   label = '2019 Chevrolet Tahoe',         minRank = 3, extrasOff = true, description = 'Full-size patrol SUV.' },
    { model = 'sec22transit',   label = '2022 Ford Transit',            minRank = 3, extrasOff = true, description = 'Security van for cash runs and crew transport.' },
    { model = 'sec22tahoeyw',   label = '2022 Chevrolet Tahoe',         minRank = 4, extrasOff = true, description = 'Full-size patrol SUV.' },
}
Config.VehicleLivery = 0
Config.VehiclePlatePrefix = 'SWS'

Config.Equipment = {
    { weapon = 'WEAPON_FLASHLIGHT', ammo = 0,  minRank = 1 },
    { weapon = 'WEAPON_NIGHTSTICK', ammo = 0,  minRank = 1 },
    { weapon = 'WEAPON_STUNGUN',    ammo = 25, minRank = 2 },
}

-- Uniforms only apply to freemode peds. [component] = { drawable, texture }
Config.Uniform = {
    male = {
        components = { [3] = {11, 0}, [4] = {35, 0}, [6] = {25, 0}, [8] = {58, 0}, [11] = {55, 0} },
        props = { [0] = {-1, 0} },
    },
    female = {
        components = { [3] = {14, 0}, [4] = {34, 0}, [6] = {25, 0}, [8] = {35, 0}, [11] = {48, 0} },
        props = { [0] = {-1, 0} },
    },
}

-------------------------------------------------------------------------------
-- Patrol
-------------------------------------------------------------------------------
Config.Patrol = {
    ScanRadius = 3.0,          -- metres from checkpoint to be allowed to scan
    ScanTime = 4500,           -- ms holding the scan
    MinSecondsBetweenScans = 8,-- anti-exploit (server enforced)
    MarkerDrawDistance = 60.0,
    SiteSignInRadius = 3.0,
}

-- Incident director: how often the server considers spawning something at your site
Config.Director = {
    FirstIncidentDelay = { 60, 120 },   -- seconds after starting patrol
    Interval = { 90, 210 },             -- seconds between rolls
    Chance = 0.65,                      -- chance a roll produces an incident
    MaxActivePerGuard = 1,
    IncidentTimeout = 900,              -- seconds before an untouched incident auto-closes
    SpawnDistance = 140.0,              -- client spawns the NPC when within this range
}

-- AI dispatch radio checks
Config.RadioCheck = {
    Enabled = true,
    Interval = { 420, 720 },     -- seconds
    ResponseWindow = 45,         -- seconds to answer with /10-4 (or the keybind)
}

-- AI police / EMS response
Config.Response = {
    PoliceModel = 's_m_y_cop_01',
    PoliceVehicle = 'police3',
    EmsModel = 's_m_m_paramedic_01',
    EmsVehicle = 'ambulance',
    EtaSeconds = { 25, 60 },
    SpawnDistance = 160.0,
    DriveSpeed = 22.0,
}

Config.FleeEscapeDistance = 110.0   -- suspect is lost when this far from you
Config.TackleDistance = 2.2

-------------------------------------------------------------------------------
-- Keybinds (players can rebind in GTA Settings > Key Bindings > FiveM)
-------------------------------------------------------------------------------
Config.Keys = {
    Tablet = 'F6',
    Panic = 'F9',
    RadioAck = 'F10',
    Interact = 38, -- E (control index, used for contextual prompts)
}

-------------------------------------------------------------------------------
-- Sites
-- checkpoints : patrol route, scanned in order (Z is snapped to ground client-side)
-- spawns      : where incident NPCs can appear
-- exit        : where NPCs who agree to leave will walk to
-------------------------------------------------------------------------------
Config.Sites = {
    {
        id = 'pacific',
        label = 'Pacific Standard Bank',
        minRank = 2,
        payMult = 1.25,
        center = vector3(240.0, 218.0, 106.3),
        radius = 85.0,
        manager = { model = 'a_m_m_business_01', coords = vector4(227.7, 203.8, 105.5, 340.0) },
        briefing = 'High-value site. Watch the side alleys and the rear loading area. Report anyone loitering near the vault side.',
        checkpoints = {
            { label = 'Main Entrance',      coords = vector3(232.0, 205.0, 105.4) },
            { label = 'Vinewood Blvd Corner', coords = vector3(268.0, 194.0, 104.8) },
            { label = 'East Alley',         coords = vector3(281.0, 224.0, 106.3) },
            { label = 'Rear Loading Bay',   coords = vector3(258.0, 252.0, 105.7) },
            { label = 'West Parking',       coords = vector3(205.0, 232.0, 105.6) },
        },
        spawns = {
            vector4(276.0, 233.0, 106.3, 90.0),
            vector4(255.0, 258.0, 105.7, 200.0),
            vector4(210.0, 240.0, 105.6, 250.0),
            vector4(272.0, 200.0, 104.8, 30.0),
        },
        exit = vector3(186.0, 205.0, 105.6),
        incidents = { trespasser = 3, suspicious = 5, vandal = 2, burglar = 3, aggressive = 2, lost = 2, intoxicated = 1, medical = 1 },
    },
    {
        id = 'construction',
        label = 'Pillbox Construction Site',
        minRank = 1,
        payMult = 1.0,
        center = vector3(-141.0, -1037.0, 27.3),
        radius = 90.0,
        manager = { model = 's_m_y_construct_01', coords = vector4(-97.0, -1013.0, 27.3, 160.0) },
        briefing = 'Copper theft is up. Check the material stores and the crane base. Nobody should be on site after hours.',
        checkpoints = {
            { label = 'Front Gate',      coords = vector3(-102.0, -1018.0, 27.3) },
            { label = 'Material Store',  coords = vector3(-128.0, -1062.0, 27.3) },
            { label = 'Crane Base',      coords = vector3(-162.0, -1050.0, 27.3) },
            { label = 'Site Office',     coords = vector3(-178.0, -1010.0, 27.3) },
            { label = 'Generator Yard',  coords = vector3(-140.0, -995.0, 27.3) },
        },
        spawns = {
            vector4(-131.0, -1069.0, 27.3, 0.0),
            vector4(-170.0, -1055.0, 27.3, 300.0),
            vector4(-185.0, -1005.0, 27.3, 220.0),
            vector4(-145.0, -985.0, 27.3, 180.0),
        },
        exit = vector3(-80.0, -1020.0, 28.0),
        incidents = { trespasser = 5, suspicious = 3, vandal = 3, burglar = 4, intoxicated = 3, lost = 2, medical = 2 },
    },
    {
        id = 'port',
        label = 'Port of Los Santos - Warehouse Row',
        minRank = 1,
        payMult = 1.1,
        center = vector3(1000.0, -3100.0, 5.9),
        radius = 120.0,
        manager = { model = 's_m_m_dockwork_01', coords = vector4(1010.0, -3050.0, 5.9, 180.0) },
        briefing = 'Containers are being cracked overnight. Check seals on every row and keep an eye on the fence line.',
        checkpoints = {
            { label = 'Gatehouse',        coords = vector3(1012.0, -3060.0, 5.9) },
            { label = 'Container Row A',  coords = vector3(970.0, -3090.0, 5.9) },
            { label = 'Container Row C',  coords = vector3(960.0, -3150.0, 5.9) },
            { label = 'Crane Lane',       coords = vector3(1040.0, -3160.0, 5.9) },
            { label = 'Fence Line East',  coords = vector3(1060.0, -3100.0, 5.9) },
        },
        spawns = {
            vector4(965.0, -3120.0, 5.9, 90.0),
            vector4(1050.0, -3140.0, 5.9, 0.0),
            vector4(1065.0, -3080.0, 5.9, 270.0),
            vector4(985.0, -3170.0, 5.9, 45.0),
        },
        exit = vector3(1010.0, -3020.0, 5.9),
        incidents = { trespasser = 4, suspicious = 4, burglar = 5, vandal = 2, lost = 3, intoxicated = 2, aggressive = 1, medical = 1 },
    },
    {
        id = 'pillbox',
        label = 'Pillbox Hill Medical Center',
        minRank = 1,
        payMult = 1.0,
        center = vector3(298.0, -584.0, 43.3),
        radius = 70.0,
        manager = { model = 's_m_m_doctor_01', coords = vector4(294.0, -592.0, 43.2, 70.0) },
        briefing = 'Busy public site. Most people here need help, not handcuffs. Be courteous and de-escalate.',
        checkpoints = {
            { label = 'Main Entrance',     coords = vector3(296.0, -590.0, 43.3) },
            { label = 'Ambulance Bay',     coords = vector3(318.0, -560.0, 28.7) },
            { label = 'Staff Parking',     coords = vector3(340.0, -590.0, 28.8) },
            { label = 'North Plaza',       coords = vector3(280.0, -560.0, 43.2) },
        },
        spawns = {
            vector4(300.0, -575.0, 43.2, 160.0),
            vector4(325.0, -570.0, 28.8, 90.0),
            vector4(275.0, -585.0, 43.1, 300.0),
        },
        exit = vector3(250.0, -600.0, 42.0),
        incidents = { aggressive = 5, intoxicated = 4, lost = 5, medical = 5, suspicious = 2, trespasser = 1 },
    },
    {
        id = 'vangelico',
        label = 'Vangelico Jewelry Store',
        minRank = 3,
        payMult = 1.4,
        center = vector3(-630.0, -237.0, 38.0),
        radius = 60.0,
        manager = { model = 'a_f_y_business_01', coords = vector4(-627.0, -233.0, 38.0, 210.0) },
        briefing = 'Prime robbery target. Treat anyone casing the windows seriously and call it in early.',
        checkpoints = {
            { label = 'Store Front',      coords = vector3(-632.0, -240.0, 38.0) },
            { label = 'Rear Service Door', coords = vector3(-620.0, -222.0, 38.0) },
            { label = 'Roof Access',      coords = vector3(-605.0, -245.0, 38.0) },
            { label = 'Rockford Plaza',   coords = vector3(-655.0, -260.0, 36.0) },
        },
        spawns = {
            vector4(-640.0, -250.0, 38.0, 300.0),
            vector4(-615.0, -218.0, 38.0, 120.0),
            vector4(-650.0, -230.0, 37.7, 210.0),
        },
        exit = vector3(-680.0, -260.0, 36.0),
        incidents = { suspicious = 6, burglar = 4, trespasser = 2, aggressive = 2, lost = 2, vandal = 1 },
    },
}
