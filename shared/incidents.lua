Incidents = {}

-- Outcomes an incident can end with. `mult` values in each type's `outcomes`
-- table scale Config.Pay.IncidentMax / Config.XP.IncidentMax.
Incidents.OutcomeLabels = {
    left_site     = 'Subject left the site',
    handed_police = 'Handed over to police',
    handed_ems    = 'Handed over to EMS',
    assisted      = 'Subject assisted',
    released      = 'Subject released',
    escaped       = 'Subject escaped',
    fatality      = 'Subject deceased',
    guard_down    = 'Guard incapacitated',
    timeout       = 'Not attended',
}

-- profile ranges are { min, max } rolled server-side when the incident is created
Incidents.Types = {
    trespasser = {
        label = 'Trespasser',
        category = 'Trespass',
        priority = 2,
        models = { 'a_m_y_skater_01', 'a_m_y_hipster_01', 'a_f_y_hipster_01', 'a_m_y_genstreet_01', 'a_m_y_stbla_01' },
        idle = { scenario = 'WORLD_HUMAN_STAND_IMPATIENT' },
        profile = { compliance = { 45, 85 }, aggression = { 5, 35 }, flight = { 10, 45 }, stress = { 10, 30 } },
        armedChance = 0.05, weapons = { 'WEAPON_KNIFE' },
        warrantChance = 0.08,
        contraband = { { item = 'Bolt cutters', chance = 0.15 }, { item = 'Spray can', chance = 0.1 }, { item = 'Small bag of cannabis', chance = 0.12 } },
        outcomes = { left_site = 1.0, handed_police = 0.75, released = 0.55, escaped = 0.25, assisted = 0.4 },
        dispatch = {
            'CCTV has an individual in a restricted area near %s. Check it out.',
            'Site staff report someone wandering around %s. Please attend.',
        },
    },
    suspicious = {
        label = 'Suspicious Person',
        category = 'Suspicious Activity',
        priority = 2,
        models = { 'a_m_y_downtown_01', 'g_m_y_mexgoon_01', 'a_m_m_skater_01', 'g_m_y_ballaeast_01', 'a_m_y_methhead_01' },
        idle = { scenario = 'WORLD_HUMAN_STAND_MOBILE' },
        profile = { compliance = { 25, 70 }, aggression = { 15, 55 }, flight = { 25, 65 }, stress = { 25, 45 } },
        armedChance = 0.2, weapons = { 'WEAPON_KNIFE', 'WEAPON_SWITCHBLADE' },
        warrantChance = 0.35,
        contraband = { { item = 'Lockpick set', chance = 0.3 }, { item = 'Photos of the site layout', chance = 0.25 }, { item = 'Stolen credit cards', chance = 0.1 } },
        outcomes = { left_site = 0.85, handed_police = 1.0, released = 0.5, escaped = 0.2, assisted = 0.3 },
        dispatch = {
            'Caller reports someone casing the building near %s, taking photos.',
            'Unit, we have a male loitering by %s for twenty minutes. Make contact.',
        },
    },
    vandal = {
        label = 'Vandalism',
        category = 'Criminal Damage',
        priority = 2,
        models = { 'a_m_y_skater_01', 'g_m_y_famca_01', 'a_m_y_beachvesp_01', 'a_m_y_stwhi_01' },
        idle = { anim = { 'switch@franklin@lamar_tagging_wall', 'lamar_tagging_wall_loop_lamar' }, prop = 'prop_cs_spray_can' },
        profile = { compliance = { 20, 60 }, aggression = { 10, 40 }, flight = { 50, 90 }, stress = { 30, 50 } },
        armedChance = 0.05, weapons = { 'WEAPON_BOTTLE' },
        warrantChance = 0.1,
        contraband = { { item = 'Spray cans', chance = 0.95 }, { item = 'Marker pens', chance = 0.4 } },
        outcomes = { handed_police = 1.0, left_site = 0.6, released = 0.4, escaped = 0.2 },
        dispatch = {
            'Someone is tagging the wall near %s. Get over there before they finish.',
            'Hissing sounds and fresh paint reported near %s. Possible vandal.',
        },
    },
    burglar = {
        label = 'Break-in / Burglary',
        category = 'Burglary',
        priority = 3,
        minRank = 2,
        models = { 'g_m_y_mexgoon_02', 'a_m_y_methhead_01', 'g_m_m_chicold_01', 'a_m_m_hillbilly_01' },
        idle = { anim = { 'anim@amb@clubhouse@tutorial@bkr_tut_ig3@', 'machinic_loop_mechandplayer' } },
        profile = { compliance = { 10, 45 }, aggression = { 35, 80 }, flight = { 40, 85 }, stress = { 45, 65 } },
        armedChance = 0.45, weapons = { 'WEAPON_CROWBAR', 'WEAPON_KNIFE', 'WEAPON_PISTOL' },
        warrantChance = 0.5,
        contraband = { { item = 'Crowbar', chance = 0.6 }, { item = 'Lockpick set', chance = 0.5 }, { item = 'Stolen copper wire', chance = 0.4 }, { item = 'Burglary gloves', chance = 0.5 } },
        outcomes = { handed_police = 1.0, left_site = 0.35, released = 0.15, escaped = 0.15 },
        alarm = true,
        dispatch = {
            'ALARM ACTIVATION at %s. Door contact breached. Approach with caution.',
            'Intruder alarm triggered at %s. Possible forced entry in progress.',
        },
    },
    aggressive = {
        label = 'Aggressive Visitor',
        category = 'Disturbance',
        priority = 2,
        models = { 'a_m_m_genfat_01', 'a_m_y_musclbeac_01', 'a_f_m_fatwhite_01', 'a_m_m_hillbilly_02' },
        idle = { scenario = 'WORLD_HUMAN_STAND_IMPATIENT_UPRIGHT' },
        profile = { compliance = { 30, 65 }, aggression = { 45, 80 }, flight = { 5, 25 }, stress = { 55, 75 } },
        armedChance = 0.1, weapons = { 'WEAPON_BAT' },
        warrantChance = 0.1,
        contraband = { { item = 'Hip flask', chance = 0.3 } },
        outcomes = { left_site = 1.0, assisted = 0.9, handed_police = 0.6, released = 0.5, escaped = 0.3 },
        dispatch = {
            'Staff at %s report a visitor shouting at people. Attend and calm things down.',
            'Disturbance in progress at %s. Agitated individual refusing to leave.',
        },
    },
    intoxicated = {
        label = 'Intoxicated Person',
        category = 'Welfare',
        priority = 1,
        models = { 'a_m_m_tramp_01', 'a_m_o_tramp_01', 'a_f_m_tramp_01', 'a_m_y_hipster_02' },
        idle = { scenario = 'WORLD_HUMAN_DRINKING' },
        clipset = 'move_m@drunk@verydrunk',
        profile = { compliance = { 30, 60 }, aggression = { 5, 40 }, flight = { 0, 15 }, stress = { 15, 40 } },
        armedChance = 0.0, weapons = {},
        warrantChance = 0.05,
        contraband = { { item = 'Open bottle of liquor', chance = 0.8 } },
        outcomes = { assisted = 1.0, left_site = 0.9, handed_police = 0.6, handed_ems = 0.8, released = 0.5, escaped = 0.3 },
        dispatch = {
            'Someone appears heavily intoxicated near %s. Welfare check please.',
            'Report of a person stumbling and shouting near %s.',
        },
    },
    lost = {
        label = 'Lost Visitor',
        category = 'Assistance',
        priority = 1,
        benign = true,
        models = { 'a_f_y_tourist_01', 'a_m_m_tourist_01', 's_m_m_postal_01', 'a_f_m_bevhills_01', 's_m_m_ups_01' },
        idle = { scenario = 'WORLD_HUMAN_TOURIST_MAP' },
        profile = { compliance = { 75, 100 }, aggression = { 0, 10 }, flight = { 0, 10 }, stress = { 20, 45 } },
        armedChance = 0.0, weapons = {},
        warrantChance = 0.0,
        contraband = {},
        outcomes = { assisted = 1.0, left_site = 0.8, released = 0.6, handed_police = 0.0 },
        dispatch = {
            'Visitor near %s looks lost. Go give them a hand.',
            'Delivery driver at %s cannot find the drop-off point. Assist please.',
        },
    },
    medical = {
        label = 'Medical Emergency',
        category = 'Medical',
        priority = 3,
        benign = true,
        collapsed = true,
        models = { 'a_m_m_business_01', 'a_m_o_genstreet_01', 'a_f_m_downtown_01', 'a_m_m_genfat_02' },
        idle = { anim = { 'combat@damage@writhe', 'writhe_loop' } },
        profile = { compliance = { 100, 100 }, aggression = { 0, 0 }, flight = { 0, 0 }, stress = { 70, 90 } },
        armedChance = 0.0, weapons = {},
        warrantChance = 0.0,
        contraband = {},
        outcomes = { handed_ems = 1.0, assisted = 0.6, released = 0.2, left_site = 0.2 },
        dispatch = {
            'MEDICAL: person down near %s. Respond immediately.',
            'Caller reports someone collapsed near %s. Not responsive.',
        },
    },
}

-- Fake identities for ID checks
Incidents.FirstNames = {
    'James', 'Marcus', 'Tyler', 'Devon', 'Kyle', 'Luis', 'Andre', 'Brandon', 'Cody', 'Hector',
    'Ashley', 'Brittany', 'Jessica', 'Maria', 'Tanya', 'Kayla', 'Rosa', 'Dana', 'Jamie', 'Alex',
}
Incidents.LastNames = {
    'Harper', 'Delgado', 'Washington', 'Kowalski', 'Nguyen', 'Brooks', 'Ramirez', 'Fischer', 'Mitchell',
    'Okafor', 'Sullivan', 'Price', 'Vance', 'Morales', 'Hughes', 'Carter', 'Lindqvist', 'Russo',
}
Incidents.Warrants = {
    'Failure to appear', 'Burglary', 'Grand theft auto', 'Assault', 'Possession with intent',
    'Parole violation', 'Receiving stolen property', 'Criminal trespass (repeat)',
}
