-- ImmerseMe: Weather - climate data. Everything in here is safe to tweak.
local ADDON, ns = ...

ns.MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"

-- Orb sky through the day. Each row: hour, sky colour, horizon glow colour,
-- horizon glow strength. Colours blend smoothly between rows (and from the
-- last row back to the first after midnight).
ns.SkyByHour = {
	{ 0,    { 0.09, 0.12, 0.30 }, { 0.20, 0.20, 0.45 }, 0.15 },   -- dead of night
	{ 4,    { 0.12, 0.14, 0.36 }, { 0.42, 0.28, 0.55 }, 0.40 },   -- before dawn
	{ 5.5,  { 0.36, 0.36, 0.68 }, { 1.00, 0.55, 0.45 }, 0.90 },   -- dawn
	{ 7,    { 0.42, 0.68, 1.00 }, { 1.00, 0.84, 0.58 }, 0.60 },   -- early morning
	{ 9,    { 0.34, 0.68, 1.00 }, { 1.00, 0.95, 0.80 }, 0.25 },   -- morning
	{ 12.5, { 0.22, 0.60, 1.00 }, { 1.00, 1.00, 1.00 }, 0.10 },   -- midday
	{ 16,   { 0.30, 0.62, 0.98 }, { 1.00, 0.92, 0.70 }, 0.25 },   -- afternoon
	{ 18.5, { 0.42, 0.55, 0.90 }, { 1.00, 0.66, 0.30 }, 0.70 },   -- evening
	{ 20,   { 0.40, 0.30, 0.60 }, { 1.00, 0.42, 0.28 }, 0.95 },   -- dusk
	{ 21,   { 0.16, 0.18, 0.42 }, { 0.45, 0.25, 0.45 }, 0.45 },   -- nightfall
	{ 22.5, { 0.11, 0.14, 0.36 }, { 0.22, 0.22, 0.50 }, 0.20 },   -- night
}

-- The sun crosses the orb from SUNRISE to SUNSET; the moon crosses it the rest of the time.
ns.SUNRISE, ns.SUNSET = 5.5, 21

-- How the weather changes that sky. desat = 0..1 towards grey, dark = brightness,
-- tint + amount = blend towards a colour, glow = horizon glow multiplier.
ns.SkyMoods = {
	clear = { desat = 0,    dark = 1,    glow = 1 },
	grey  = { desat = 0.65, dark = 0.85, glow = 0.4 },
	dark  = { desat = 0.75, dark = 0.60, glow = 0.25 },
	dust  = { tint = { 0.85, 0.62, 0.38 }, amount = 0.55, dark = 0.95, glow = 0.5 },
	ember = { tint = { 0.60, 0.22, 0.10 }, amount = 0.60, dark = 0.80, glow = 0.6 },
	sick  = { tint = { 0.48, 0.60, 0.28 }, amount = 0.50, dark = 0.85, glow = 0.4 },
}
-- Which mood each sky condition uses; anything not listed is "clear".
ns.SkyMood = {
	overcast = "grey", fog = "grey", drizzle = "grey", flurries = "grey", snow = "grey", mist = "grey",
	rain = "dark", storm = "dark", blizzard = "dark",
	sandstorm = "dust", ashfall = "ember", miasma = "sick",
}
-- Stars show through these at night.
ns.StarrySky = { clear = true, fair = true, haze = true }

local ICON = "Interface\\Icons\\"

-- Orb / clear-sky icons
ns.SUN_ICON  = ICON .. "Ability_Druid_EclipseOrange"
ns.MOON_ICON = ICON .. "Spell_Nature_Sentinal"

-- Fires you can stand by. temp = the heat it gives off, hold = how strongly it wins
-- against the air around it (0..1), hum = the humidity it dries the air towards,
-- label = what the readout's wind line says while you're by it.
ns.HeatSources = {
	forge    = { temp = 30, hold = 0.90, hum = 25, label = "By the forge" },
	hearth   = { temp = 24, hold = 0.85, hum = 40, label = "By the fire" },
	campfire = { temp = 22, hold = 0.55, hum = 50, label = "By the campfire" },  -- a fire in the open
}

-- Buildings with a fire or a forge, by the subzone name shown above the minimap.
-- They only count while you're under a roof. Use /imw fire or /imw forge for
-- anywhere not listed, and send new places upstream so everyone gets them.
ns.WarmPlaces = {
	["The Great Forge"]        = "forge",
	["Thunderbrew Distillery"] = "hearth",
}

-- Fires and forges out in the world: { x, y, continent, kind } in world yards
-- (UnitPosition). /imw spots prints the ones you have discovered in this format,
-- ready to paste here so every player feels them.
ns.FireSpots = {
}

-- Sky conditions. temp/hum/wind are modifiers applied on top of the zone climate.
-- windMul scales the zone's base wind, wind adds km/h on top.
ns.Conditions = {
	clear     = { day = "Clear skies",        night = "Clear and starlit",   temp = 1.5,  hum = -8,  windMul = 1.0, wind = 0,
	              flavor = { day = "Not a cloud troubles the sky.", night = "The stars burn cold and sharp overhead." } },
	fair      = { day = "Scattered clouds",   night = "Broken, moonlit cloud", temp = 0.5, hum = -3, windMul = 1.0, wind = 0,
	              flavor = { day = "Cloud shadows drift lazily across the land.", night = "Clouds slide across the face of the moon." } },
	overcast  = { day = "Overcast",           night = "Starless, heavy cloud", temp = -1, hum = 5,  windMul = 1.0, wind = 0, icon = "Spell_Frost_Wisp",
	              flavor = { day = "A grey lid of cloud presses down on the world.", night = "No star shows; the dark is close and total." } },
	mist      = { day = "Mist",               night = "Night mist",          temp = -1,   hum = 9,  windMul = 0.5, wind = 0, icon = "Spell_Magic_LesserInvisibilty",
	              flavor = { day = "Thin mist softens every outline.", night = "Mist coils low between the trees." } },
	fog       = { day = "Thick fog",          night = "Dense night fog",     temp = -1.5, hum = 14,  windMul = 0.3, wind = 0, icon = "Spell_Magic_LesserInvisibilty",
	              flavor = { day = "The fog swallows sound and distance alike.", night = "You can scarcely see your own hand before you." } },
	drizzle   = { day = "Drizzle",            night = "Night drizzle",       temp = -1.5, hum = 10,  windMul = 0.9, wind = 0, icon = "Spell_Nature_Tranquility",
	              flavor = { day = "A fine rain beads on cloak and steel.", night = "A fine cold rain whispers in the dark." } },
	rain      = { day = "Steady rain",        night = "Rain in the dark",    temp = -2.5, hum = 15,  windMul = 1.2, wind = 4, icon = "Spell_Nature_Tranquility",
	              flavor = { day = "Rain drums steadily; the roads turn to mud.", night = "Rain hammers down unseen in the blackness." } },
	storm     = { day = "Thunderstorm",       night = "Night thunderstorm",  temp = -3.5, hum = 17,  windMul = 1.5, wind = 22, icon = "Spell_Nature_CallStorm",
	              flavor = { day = "Thunder rolls across the land.", night = "Lightning tears the night open, again and again." } },
	flurries  = { day = "Snow flurries",      night = "Flurries in the dark", temp = -1.5, hum = 8,  windMul = 1.0, wind = 2, icon = "Spell_Frost_FrostBolt02",
	              flavor = { day = "Loose snowflakes wander down from a pale sky.", night = "Snowflakes drift silently out of the dark." } },
	snow      = { day = "Snowfall",           night = "Night snowfall",      temp = -3,   hum = 10,  windMul = 1.1, wind = 4, icon = "Spell_Frost_FrostNova",
	              flavor = { day = "Snow falls thick and steady, muffling the world.", night = "Snow buries your tracks almost as you make them." } },
	blizzard  = { day = "Blizzard",           night = "Night blizzard",      temp = -6,   hum = 12,  windMul = 1.6, wind = 35, icon = "Spell_Frost_IceStorm",
	              flavor = { day = "The wind screams; snow flies sideways.", night = "A white, howling dark. No night to be abroad." } },
	haze      = { day = "Heat haze",          night = "Dry, dusty air",      temp = 2,    hum = -4,  windMul = 0.8, wind = 0, icon = "Spell_Holy_SearingLight",
	              flavor = { day = "The horizon shimmers and swims in the heat.", night = "The baked earth gives its heat back to the night." } },
	sandstorm = { day = "Dust storm",         night = "Night dust storm",    temp = 1,    hum = -6,  windMul = 1.6, wind = 40, icon = "Spell_Nature_Cyclone",
	              flavor = { day = "Grit stings every inch of bare skin.", night = "Sand hisses against everything in the dark." } },
	ashfall   = { day = "Ashfall",            night = "Glowing ashfall",     temp = 3,    hum = -5,  windMul = 1.0, wind = 3, icon = "Spell_Fire_Immolation",
	              flavor = { day = "Grey ash sifts down; the air tastes of cinders.", night = "Embers ride the wind like slow red stars." } },
	miasma    = { day = "Plague miasma",      night = "Rank night miasma",   temp = 0,    hum = 12,  windMul = 0.5, wind = 0, icon = "Spell_Shadow_PlagueCloud",
	              flavor = { day = "A sickly haze hangs in the air. Breathe shallow.", night = "The dark itself smells of rot." } },
	indoors   = { day = "Under stone",        night = "Under stone",         temp = 0,    hum = 0,   windMul = 0,   wind = 0, icon = "INV_Misc_Lantern_01",
	              flavor = { day = "No sky here; only stone and lamplight.", night = "No sky here; only stone and lamplight." } },
}
for _, c in pairs(ns.Conditions) do
	if c.icon then c.icon = ICON .. c.icon end
end

-- Climates.
--   temp   = yearly mean (Celsius)      swing = day/night range
--   season = summer/winter amplitude    hum   = mean relative humidity (%)
--   wind   = mean wind (km/h)           dir   = prevailing wind bearing (degrees, where it blows FROM)
--   sky    = ladder from fairest to foulest weather, with relative weights
ns.Climates = {
	temperate = { temp = 14, swing = 9,  season = 8, hum = 62, wind = 12, dir = 250,
	              sky = { {"clear",3}, {"fair",3}, {"overcast",2}, {"drizzle",1}, {"rain",1.2}, {"storm",0.5} } },
	gloom     = { temp = 8,  swing = 5,  season = 5, hum = 80, wind = 6,  dir = 200,
	              sky = { {"overcast",1.5}, {"mist",3}, {"fog",2.5}, {"drizzle",1.5}, {"rain",1} } },
	undead    = { temp = 7,  swing = 6,  season = 7, hum = 80, wind = 10, dir = 300,
	              sky = { {"fair",0.5}, {"overcast",3}, {"mist",2}, {"drizzle",1.5}, {"rain",1.5}, {"storm",0.4} } },
	alpine    = { temp = -6, swing = 7,  season = 8, hum = 70, wind = 18, dir = 340,
	              sky = { {"clear",2}, {"fair",2}, {"overcast",2}, {"flurries",2}, {"snow",2}, {"blizzard",0.8} } },
	highland  = { temp = 10, swing = 10, season = 9, hum = 58, wind = 18, dir = 280,
	              sky = { {"clear",2.5}, {"fair",3}, {"overcast",2}, {"drizzle",1}, {"rain",1.2}, {"storm",0.5} } },
	coast     = { temp = 16, swing = 8,  season = 6, hum = 68, wind = 24, dir = 260,
	              sky = { {"clear",3}, {"fair",3}, {"overcast",1.5}, {"rain",1}, {"storm",0.6} } },
	plains    = { temp = 17, swing = 12, season = 9, hum = 48, wind = 22, dir = 230,
	              sky = { {"clear",3}, {"fair",3}, {"overcast",1.5}, {"rain",1}, {"storm",0.7} } },
	arid      = { temp = 27, swing = 16, season = 6, hum = 22, wind = 14, dir = 90,
	              sky = { {"clear",5}, {"fair",2}, {"haze",2}, {"sandstorm",0.6}, {"storm",0.2} } },
	desert    = { temp = 33, swing = 20, season = 5, hum = 10, wind = 16, dir = 110,
	              sky = { {"clear",5}, {"haze",3}, {"sandstorm",1.2} } },
	jungle    = { temp = 28, swing = 6,  season = 2, hum = 82, wind = 6,  dir = 150,
	              sky = { {"fair",2}, {"overcast",2}, {"mist",1.5}, {"rain",3}, {"storm",1.5} } },
	swamp     = { temp = 19, swing = 6,  season = 5, hum = 84, wind = 7,  dir = 170,
	              sky = { {"fair",1}, {"overcast",2}, {"mist",2.5}, {"fog",1.5}, {"drizzle",2}, {"rain",2}, {"storm",0.5} } },
	elven     = { temp = 12, swing = 6,  season = 5, hum = 74, wind = 8,  dir = 290,
	              sky = { {"clear",2}, {"fair",2.5}, {"mist",2}, {"overcast",1.5}, {"drizzle",1}, {"rain",1} } },
	volcanic  = { temp = 38, swing = 6,  season = 2, hum = 12, wind = 14, dir = 60,
	              sky = { {"haze",3}, {"overcast",1}, {"ashfall",4} } },
	blight    = { temp = 9,  swing = 6,  season = 7, hum = 72, wind = 9,  dir = 320,
	              sky = { {"overcast",3}, {"mist",1}, {"miasma",4}, {"drizzle",1.5} } },
	wastes    = { temp = 24, swing = 12, season = 4, hum = 20, wind = 20, dir = 130,
	              sky = { {"haze",3}, {"overcast",3}, {"sandstorm",1}, {"storm",1} } },
	-- enclosed places: no sky, no wind
	forge       = { temp = 24, swing = 1, season = 1, hum = 35, wind = 0, indoor = true },
	crypt       = { temp = 9,  swing = 1, season = 1, hum = 85, wind = 0, indoor = true },
	underground = { temp = 12, swing = 1, season = 2, hum = 70, wind = 0, indoor = true },
}

ns.DEFAULT_CLIMATE  = "temperate"
ns.INSTANCE_CLIMATE = "underground"

-- Zone -> climate (English zone names). Zones not listed here get the default
-- climate with a small per-zone offset, so they still feel distinct.
ns.Zones = {
	-- Eastern Kingdoms
	["Elwynn Forest"] = "temperate", ["Stormwind City"] = "temperate", ["Redridge Mountains"] = "highland",
	["Westfall"] = "coast", ["Duskwood"] = "gloom", ["Deadwind Pass"] = "wastes",
	["Stranglethorn Vale"] = "jungle", ["Swamp of Sorrows"] = "swamp", ["Blasted Lands"] = "wastes",
	["Burning Steppes"] = "volcanic", ["Searing Gorge"] = "volcanic", ["Badlands"] = "arid",
	["Dun Morogh"] = "alpine", ["Ironforge"] = "forge", ["Loch Modan"] = "highland", ["Wetlands"] = "swamp",
	["Arathi Highlands"] = "highland", ["Hillsbrad Foothills"] = "highland", ["Alterac Mountains"] = "alpine",
	["The Hinterlands"] = "highland", ["Silverpine Forest"] = "undead", ["Tirisfal Glades"] = "undead",
	["Undercity"] = "crypt", ["Western Plaguelands"] = "blight", ["Eastern Plaguelands"] = "blight",
	-- Kalimdor
	["Durotar"] = "arid", ["Orgrimmar"] = "arid", ["The Barrens"] = "arid", ["Mulgore"] = "plains",
	["Thunder Bluff"] = "plains", ["Teldrassil"] = "elven", ["Darnassus"] = "elven", ["Darkshore"] = "elven",
	["Ashenvale"] = "elven", ["Moonglade"] = "elven", ["Stonetalon Mountains"] = "highland",
	["Desolace"] = "wastes", ["Feralas"] = "jungle", ["Dustwallow Marsh"] = "swamp",
	["Thousand Needles"] = "arid", ["Tanaris"] = "desert", ["Un'Goro Crater"] = "jungle",
	["Silithus"] = "desert", ["Felwood"] = "blight", ["Azshara"] = "coast", ["Winterspring"] = "alpine",
}
