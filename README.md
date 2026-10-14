# Statewide Security

A standalone FiveM private-security job built around AI interaction. Players clock on at HQ, sign in with an AI site contact, patrol checkpoint routes, and deal with AI-driven incidents. Each incident NPC has hidden traits and reacts to how the player treats them. An AI dispatcher, AI police and EMS, incident reports, and supervisor review sit on top of that.

No framework required (no ESX/QBCore). Persistence is flat-file JSON.

## Features

**Duty & HQ**
- Clock on/off at HQ. A uniform is applied to freemode peds and your own outfit is restored when you clock off.
- Equipment is issued by rank (flashlight, nightstick, taser).
- Rank-locked patrol vehicles are spawned server-side.
- Access mode can be `open`, ACE-permission, or an identifier whitelist.

**Sites & patrols**
- 5 example sites: Pacific Standard, a construction site, the Port of LS, Pillbox Medical and Vangelico. Each has its own briefing, checkpoint route, incident mix, rank requirement and pay multiplier.
- An AI site contact at every site handles sign-in, briefings, patrol status and hand-over.
- Checkpoints are scanned in order: hold E and a clipboard animation plays.
- The server validates each scan: position, order and a cooldown, so it can't be teleported or spammed.
- Dispatch warns you over the radio if you wander away from your post.

**AI incidents.** A director on the server spawns these while you patrol:

| Type | What's going on | Best handling |
|---|---|---|
| Trespasser | Someone where they shouldn't be | Talk, identify, warn, ask to leave |
| Suspicious Person | Casing the site, may have a warrant or false ID | Identify, run ID, detain and hand to LSPD if wanted |
| Vandalism | Tagging a wall (spray can prop), likely to run | Catch, detain, police |
| Break-in / Burglary | Alarm activation, often armed, high flight risk | Approach carefully, subdue, police |
| Aggressive Visitor | Angry and shouting | De-escalate. Force is a last resort |
| Intoxicated Person | Stumbling drunk | Welfare: help them off site or call EMS |
| Lost Visitor | Harmless member of the public | Help them. Detaining them earns a complaint |
| Medical Emergency | Person down | Check vitals, first aid, call EMS |

**How the NPCs think**
- Each subject rolls hidden **compliance, aggression, flight risk and stress** on the server.
- Every action you take shifts their stress and your rapport with them. Calm actions build trust; commands and threats raise stress.
- The panel lets you read the subject: **Demeanor** (Calm / Uneasy / Agitated / Hostile) and **Cooperation** (Cooperative / Hesitant / Uncooperative).
- If stress goes too high they argue, run, or fight. Armed subjects draw their weapon.
- Some subjects bolt the moment they see a uniform. Running their name may reveal a warrant, and they may hear it over your radio and run.
- If a subject runs, close the gap and press E to tackle (75% chance it lands).
- Subdue fighters with melee or the taser, then cuff them. After that you can escort them (E/G) and put them in a vehicle.
- **Hidden info only comes from the server:** identity, warrants, false IDs and contraband are revealed only through ID checks and searches.

**AI dispatch & responders**
- The dispatcher sends radio traffic for incidents, sign-ins and ID checks.
- Random **radio checks** must be answered with F10 or `/10-4`. Missing one costs XP and every unit hears about it.
- **AI LSPD units** drive to the scene with sirens. The officers walk over, cuff the subject, put them in the car and drive off. They chase fleeing subjects on foot.
- **AI EMS units** treat the patient and transport them.
- **Panic button** (F9): every on-duty guard gets a flashing blip and a route to you, and LSPD responds and deals with any hostile subject nearby.

**Scoring, reports & progression**
- Every incident is scored on the server: outcome, warrant handling, evidence, de-escalation, response time, first aid.
- **Complaints** are filed for wrongful detention, excessive force on a compliant subject, or killing an unarmed subject.
- Closing an incident produces a **report** that you write in the tablet. You pick the category and outcome, name the subject, and write a narrative. It is auto-graded.
- **Supervisors** can approve, commend (+XP) or return (−XP) reports.
- There are 5 ranks with pay multipliers, plus vehicle, equipment and site unlocks.
- Lifetime stats: arrests, assists, complaints, commendations and more.

**Tablet (F6)**: overview with rank ladder and shift stats, sites with GPS, the live team roster, reports, and the supervisor queue.

## Install

1. Drop the folder into `resources/` and rename it `statewide_security`.
2. Add `ensure statewide_security` to `server.cfg`.
3. **OneSync must be enabled.** The server reads player positions and spawns vehicles.
4. Make sure `data/` is writable. Profiles and reports are saved to `data/guards.json` and `data/reports.json`.

### Permissions (optional)

```cfg
# Config.Access.Mode = 'ace'
add_ace group.security statewide.security allow
add_principal identifier.license:xxxx group.security

# admin commands
add_ace group.admin statewide.security.admin allow
```

### Paying players

The resource is standalone, so pay is tracked and handed to `Config.OnPayout(src, amount, summary)` when a guard clocks off. Connect it to your economy there.

## Controls

| Key | Action |
|---|---|
| E | Interact / talk / scan (hold) / tackle |
| G | Place escorted subject in nearest vehicle |
| Q | Talk while escorting |
| F6 | Security tablet (`/sectablet`) |
| F9 | Panic button (`/secpanic`) |
| F10 | Answer radio check (`/10-4`) |

Players can rebind F6/F9/F10 under *Settings → Key Bindings → FiveM*.

## Admin

```
secadmin setxp <id> <xp>          set a guard's XP (rank follows)
secadmin callsign <id> <text>     change a callsign
secadmin incident <id> <type>     force an incident (trespasser, suspicious, vandal, burglar, aggressive, intoxicated, lost, medical)
secadmin save                     flush data to disk
```

## Configuring sites

Everything lives in `config.lua`. The site coordinates are starting points, so walk your sites in-game and tune them:

1. Set `Config.Debug = true`.
2. Stand where you want a checkpoint, spawn point or site contact and run `/secpos`. It prints a `vector4(...)` to F8 and to a notification.
3. Paste it into the site's `checkpoints`, `spawns`, `manager.coords` or `exit`.

Checkpoint Z values are ground-snapped on the client, so rough heights are fine. Each site's `incidents` table sets the weight of each incident type at that site. New incident types can be added in `shared/incidents.lua`, with dialogue lines in `shared/dialogue.lua`.

## File layout

```
config.lua              all tuning: access, ranks, pay, HQ, vehicles, sites, director, responders
shared/incidents.lua    incident type definitions (behaviour profiles, outcomes, dispatch lines)
shared/dialogue.lua     player actions and NPC/dispatcher lines
server/storage.lua      JSON persistence
server/main.lua         duty, rewards, ranks, vehicles, team sync, radio checks, panic, tablet data
server/patrol.lua       site sign-in/out, checkpoint validation
server/incidents.lua    director, hidden subject data, scoring
server/reports.lua      report grading and supervisor review
client/ai.lua           NPC spawning and behaviour state machine
client/interact.lua     dialogue engine, ID/search/detain/tackle/escort
client/dispatch.lua     AI LSPD/EMS units, panic, radio checks, team blips
client/patrol.lua       site contacts, checkpoints
client/main.lua         HQ, uniform, garage, helpers
client/nui.lua          tablet bridge
html/                   NUI (tablet, interaction panel, HUD)
```
