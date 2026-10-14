Dialogue = {}

-- Player actions shown in the interaction panel.
--   tone      : calm | neutral | command | force (shown as a colour in the UI)
--   stress    : change applied to the subject's stress before the reaction roll
--   rapport   : change to rapport (calm conversation builds trust over time)
Dialogue.Actions = {
    greet          = { label = 'Greet & identify yourself',      tone = 'calm',    stress = -12, rapport = 8 },
    ask_purpose    = { label = 'Ask what they are doing here',   tone = 'calm',    stress = -4,  rapport = 4 },
    reassure       = { label = 'Reassure / de-escalate',         tone = 'calm',    stress = -18, rapport = 6 },
    explain_rules  = { label = 'Explain site rules',             tone = 'neutral', stress = -6,  rapport = 3 },
    request_id     = { label = 'Request identification',         tone = 'neutral', stress = 4,   rapport = 0 },
    run_id         = { label = 'Run ID with dispatch',           tone = 'neutral', stress = 6,   rapport = 0 },
    ask_leave      = { label = 'Ask them to leave the property', tone = 'neutral', stress = 2,   rapport = 0 },
    trespass_warn  = { label = 'Issue formal trespass warning',  tone = 'command', stress = 8,   rapport = -2 },
    order_stop     = { label = 'Order them to stop and comply',  tone = 'command', stress = 12,  rapport = -4 },
    threaten       = { label = 'Threaten use of force',          tone = 'force',   stress = 28,  rapport = -15 },
    search         = { label = 'Search subject',                 tone = 'command', stress = 10,  rapport = -3 },
    detain         = { label = 'Detain (handcuff)',              tone = 'force',   stress = 20,  rapport = -8 },
    offer_help     = { label = 'Offer assistance / directions',  tone = 'calm',    stress = -10, rapport = 10 },
    check_vitals   = { label = 'Check breathing and pulse',      tone = 'calm',    stress = 0,   rapport = 0 },
    first_aid      = { label = 'Render first aid',               tone = 'calm',    stress = -10, rapport = 0 },
    call_police    = { label = 'Request police attendance',      tone = 'neutral', stress = 10,  rapport = -2 },
    call_ems       = { label = 'Request EMS attendance',         tone = 'calm',    stress = -2,  rapport = 2 },
    escort         = { label = 'Escort subject (grab/let go)',   tone = 'command', stress = 0,   rapport = 0 },
    release        = { label = 'Release / dismiss subject',      tone = 'calm',    stress = -10, rapport = 5 },
}

-- Generic NPC lines keyed by reaction
Dialogue.Lines = {
    greet_ok        = { 'Oh. Hey. Evening.', 'Uh, hi officer.', 'Yeah? What\'s up?' },
    greet_cold      = { 'What do you want?', 'Rent-a-cop. Great.', 'I ain\'t talking to you.' },
    reassure_ok     = { 'Alright... alright. I\'m calm.', 'Okay, okay. Sorry, it\'s been a long day.', 'Fine. I hear you.' },
    reassure_fail   = { 'Don\'t tell me to calm down!', 'You\'re not helping, man.' },
    rules           = { 'Didn\'t see any signs.', 'Okay, I get it.', 'Whatever, man.' },
    id_show         = { 'Here. Happy now?', 'Sure, here you go.', 'Fine. Take it.' },
    id_refuse       = { 'You\'re not a real cop. I don\'t have to show you anything.', 'Nah. Not happening.', 'I left it at home. Honestly.' },
    leave_ok        = { 'Alright, I\'m going.', 'Fine, I\'m out of here.', 'Okay, okay. I\'ll leave.' },
    leave_refuse    = { 'I\'m not going anywhere.', 'Public place, man. Make me.', 'Give me five minutes.' },
    warned          = { 'Yeah, yeah. Trespass. Got it.', 'Fine, I won\'t come back.', 'Whatever you say.' },
    order_ok        = { 'Okay! Okay, I\'m not moving.', 'Alright, chill. I\'m stopped.' },
    order_defy      = { 'Or what?', 'You can\'t order me around.', 'Back off!' },
    threaten        = { 'You wanna go? Let\'s go!', 'Try it.', 'Woah, woah, alright!' },
    search_consent  = { 'Go ahead, I got nothing.', 'Fine. Be quick about it.' },
    search_refuse   = { 'You\'re not touching me.', 'No way. I know my rights.' },
    detain_ok       = { 'This is ridiculous...', 'Alright, alright. Easy on the wrists.', 'I didn\'t do anything!' },
    detain_flee     = { 'Nope!', 'Not today!', 'Catch me if you can!' },
    detain_fight    = { 'Get your hands off me!', 'You\'re gonna regret that!', 'Don\'t touch me!' },
    escalate_flee   = { 'I\'m out!', 'Screw this!' },
    escalate_fight  = { 'That\'s it!', 'I warned you!' },
    escalate_argue  = { 'You\'re really getting on my nerves.', 'Keep pushing, see what happens.' },
    help_thanks     = { 'Thank you so much!', 'You\'re a lifesaver.', 'Appreciate it, thanks.' },
    help_decline    = { 'I don\'t need your help.', 'I\'m fine.' },
    released        = { 'About time.', 'Thanks. I guess.', 'Can I go now? Cool.' },
    police_called   = { 'You called the cops? Seriously?', 'Oh, great.', 'For this?!' },
    ems_called      = { 'I... I don\'t need an ambulance.', 'Okay... okay.' },
    restrained      = { 'These cuffs are too tight.', 'I want a lawyer.', 'This is harassment.' },
    groan           = { '*groans*', '*breathing heavily*', '*doesn\'t respond*' },
}

-- Type-specific overrides
Dialogue.TypeLines = {
    trespasser = {
        purpose = { 'Just cutting through, man. Quicker this way.', 'Looking for my dog, he ran in here.', 'Skating spot. No harm done.' },
    },
    suspicious = {
        purpose = { 'Waiting for a friend.', 'Just taking pictures. Architecture, you know?', 'None of your business.' },
    },
    vandal = {
        purpose = { 'It\'s art, man. Expression!', 'Wall was ugly anyway.', 'What paint? I didn\'t do that.' },
    },
    burglar = {
        purpose = { 'I... work here. Maintenance.', 'Door was open, I swear.', 'Just looking for somewhere to sleep.' },
    },
    aggressive = {
        purpose = { 'Nobody in there will listen to me!', 'I\'ve been waiting three hours!', 'Your people towed my car!' },
        greet_cold = { 'Oh, now security shows up!', 'Are you gonna fix this? No? Then go away!' },
    },
    intoxicated = {
        purpose = { 'I\'m jusht... resting my eyes.', 'Wherezz my car?', 'Party\'s over? Aw man.' },
        greet_ok = { 'Heyyy buddy! You my Uber?', 'Offisher! Love the hat.' },
    },
    lost = {
        purpose = { 'I\'m trying to find the delivery entrance.', 'I think my GPS took me to the wrong place.', 'Is this the way to the parking garage?' },
        greet_ok = { 'Oh thank goodness, someone who works here!', 'Hi! Maybe you can help me.' },
    },
    medical = {
        purpose = { '*groans* ...chest... hurts...', '*unresponsive*' },
        greet_ok = { '*groans*' },
        greet_cold = { '*groans*' },
    },
}

-- Lines spoken by the AI dispatcher
Dialogue.Dispatch = {
    clockOn = { 'Dispatch copies, %s. You\'re on the board. Stay safe out there.', '%s, you\'re 10-8. Welcome aboard.' },
    clockOff = { '%s, dispatch copies you 10-7. Good work today.' },
    siteSignIn = { '%s, dispatch copies you on site at %s.' },
    radioCheck = { '%s, radio check. Respond with your status.', '%s, dispatch. Welfare check, acknowledge.' },
    radioAck = { 'Copy that %s, thanks.', '10-4 %s.' },
    radioMissed = { '%s missed a radio check. Supervisor has been notified.' },
    idClear = { '%s, your subject %s comes back clear. No wants or warrants.' },
    idWarrant = { '%s, be advised: %s has an active warrant for %s. Detain if safe to do so and await police.' },
    idUnknown = { '%s, no record found for that name. Could be a false ID.' },
    policeEnRoute = { 'LSPD notified. Unit en route, ETA %s seconds.' },
    emsEnRoute = { 'EMS dispatched, ETA %s seconds. Keep them comfortable.' },
    panic = { 'PANIC ALARM from %s at %s! All available units respond!' },
    escaped = { '%s, copy subject lost. I\'ll pass the description to LSPD.' },
}

function Dialogue.Line(incidentType, key)
    local typed = Dialogue.TypeLines[incidentType]
    local pool = (typed and typed[key]) or Dialogue.Lines[key]
    if not pool then return '...' end
    return pool[math.random(1, #pool)]
end

function Dialogue.DispatchLine(key, ...)
    local pool = Dialogue.Dispatch[key]
    if not pool then return '' end
    return pool[math.random(1, #pool)]:format(...)
end
