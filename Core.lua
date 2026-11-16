-- ImmerseMe: Weather - the weather simulation.
-- Everything is derived from zone name + realm time, so the result is stable
-- (no flicker on reload) and identical for every player running the addon.
local _, ns = ...

local floor, sin, cos, pi, max, min = math.floor, math.sin, math.cos, math.pi, math.max, math.min

local function clamp(v, lo, hi) return max(lo, min(hi, v)) end

-- Deterministic pseudo-random number in [0,1) from a string key and an integer.
local M = 2147483647
local function hash01(key, n)
	local h = 5381
	for i = 1, #key do h = (h * 33 + key:byte(i)) % M end
	h = (h + n * 2654435) % M
	h = (h * 48271) % M
	local x = sin((h % 1000003) * 0.6180339 + 0.1) * 43758.5453
	return x - floor(x)
end

-- Smoothly varying noise in [0,1): one new random value per unit of x.
local function smooth(key, x)
	local i = floor(x)
	local f = x - i
	f = f * f * (3 - 2 * f)
	local a, b = hash01(key, i), hash01(key, i + 1)
	return a + (b - a) * f
end

ns.Phases = {
	{ 0,    "Dead of Night" },
	{ 4,    "Before Dawn" },
	{ 5.5,  "Dawn",    twilight = true },
	{ 7,    "Morning" },
	{ 11,   "Midday" },
	{ 14,   "Afternoon" },
	{ 18,   "Evening" },
	{ 19.5, "Dusk",    twilight = true },
	{ 21,   "Night" },
}

function ns.GetPhase(hour)
	local phase = ns.Phases[1]
	for _, p in ipairs(ns.Phases) do
		if hour >= p[1] then phase = p end
	end
	return phase[2], (hour < 5.5 or hour >= 21), phase.twilight or false
end

local MOON = { "New Moon", "Waxing Crescent", "First Quarter", "Waxing Gibbous",
               "Full Moon", "Waning Gibbous", "Last Quarter", "Waning Crescent" }
function ns.GetMoonPhase(t)
	local age = ((t - 947182440) / 86400 / 29.530588) % 1
	local i = floor(age * 8 + 0.5) % 8
	return MOON[i + 1], i          -- name, index 0 (new) .. 4 (full) .. 7
end

local COMPASS = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }
local WIND_NAMES = { { 2, "Calm" }, { 12, "Light breeze" }, { 29, "Steady breeze" },
                     { 50, "Strong wind" }, { 75, "Gale" }, { 1e9, "Storm winds" } }

local function climateFor(zone, inInstance)
	if inInstance then return ns.Climates[ns.INSTANCE_CLIMATE] end
	return ns.Climates[ns.Zones[zone] or ns.DEFAULT_CLIMATE] or ns.Climates[ns.DEFAULT_CLIMATE]
end

-- 0 = fairest weather the zone gets, 1 = foulest. Drifts slowly over hours.
local function wetness(zone, t)
	local w = 0.8 * smooth(zone .. ":w", t / 21600) + 0.2 * smooth(zone .. ":w2", t / 5400)
	return clamp(0.5 + (w - 0.5) * 1.6, 0, 0.9999)
end

local function pickCondition(climate, wet)
	local total = 0
	for _, s in ipairs(climate.sky) do total = total + s[2] end
	local acc = 0
	for _, s in ipairs(climate.sky) do
		acc = acc + s[2] / total
		if wet < acc then return s[1] end
	end
	return climate.sky[#climate.sky][1]
end

local FREEZE = { drizzle = "flurries", rain = "snow", storm = "blizzard" }
local THAW   = { flurries = "drizzle", snow = "rain", blizzard = "storm" }

-- Bends the simulated sky to what the game is really doing.
-- real = { kind = "clear" | "rain" | "snow" | "sandstorm", intensity = number }
local function observed(climate, key, real)
	local ladder = ns.GameWeather[real.kind]
	if ladder then
		for _, step in ipairs(ladder) do
			if real.intensity < step[1] then return step[2] end
		end
		return ladder[#ladder][2]
	end
	if real.kind ~= "clear" or not ns.Precipitation[key] then return key end
	-- the game shows a dry sky: step down the zone's ladder to its nearest dry condition
	local dry = "overcast"
	for _, s in ipairs(climate.sky) do
		if s[1] == key then break end
		if not ns.Precipitation[s[1]] then dry = s[1] end
	end
	return dry
end

-- zone: zone name, t: realm epoch seconds, hour: fractional hour of day (0-24),
-- opts.weather: what the game reports right now (see observed above), if the client can tell.
-- opts.instance / opts.sheltered / opts.heated: player is in an instance / under a roof /
-- in a warmed building (an inn, a tavern, a city hall: anywhere the game lets you rest).
-- opts.heat: a key of ns.HeatSources when the player is standing by a fire or forge.
function ns.Simulate(zone, t, hour, opts)
	opts = opts or {}
	zone = (zone and zone ~= "") and zone or "Unknown"
	local climate = climateFor(zone, opts.instance)
	local phaseName, isNight, isTwilight = ns.GetPhase(hour)
	local d = date("*t", t)
	local yearPos = ((d.month - 1) + (d.day - 1) / 30) / 12          -- 0..1 through the year

	-- small permanent per-zone quirks so unlisted zones differ from each other
	local quirkT = (hash01(zone .. ":qt", 0) - 0.5) * 4
	local quirkH = (hash01(zone .. ":qh", 0) - 0.5) * 10

	local seasonal = -cos((yearPos - 0.04) * 2 * pi) * climate.season     -- coldest mid-January
	local diurnal  = cos((hour - 15) / 24 * 2 * pi) * climate.swing / 2  -- warmest at 15:00
	local drift    = (smooth(zone .. ":t", t / 21600) - 0.5) * 6
	local temp     = climate.temp + quirkT + seasonal + diurnal + drift

	local wet = wetness(zone, t)
	local key = climate.indoor and "indoors" or pickCondition(climate, wet)
	if temp < -1 and FREEZE[key] then key = FREEZE[key] end
	if temp > 3 and THAW[key] then key = THAW[key] end
	local real = not climate.indoor and opts.weather or nil
	if real then key = observed(climate, key, real) end
	local cond = ns.Conditions[key]

	-- a clear night is colder than a clear day is warm
	local condTemp = cond.temp
	if isNight and (key == "clear" or key == "haze") then condTemp = -condTemp end
	temp = temp + condTemp
	-- the thermometer has to agree with what is actually falling
	if real and real.kind == "snow" then temp = min(temp, 0) end
	if real and real.kind == "rain" then temp = max(temp, 1) end

	local hum = climate.hum + quirkH + cond.hum - diurnal * 1.2
	          + (smooth(zone .. ":h", t / 14400) - 0.5) * 12
	if key == "fog" then hum = max(hum, 94) elseif key == "mist" then hum = max(hum, 85) end
	hum = clamp(hum, 3, 100)

	local wind = climate.wind * (0.4 + smooth(zone .. ":v", t / 5400) * 1.3) * cond.windMul + cond.wind
	local bearing = ((climate.dir or 270) + (smooth(zone .. ":d", t / 18000) - 0.5) * 200) % 360

	local sheltered = opts.sheltered and not climate.indoor
	local heated = sheltered and opts.heated or false
	local outside = temp
	if heated then
		-- a fire in the hearth: comfortable whatever the weather, a touch cooler on the coldest nights
		temp = 19 + (temp - 19) * 0.12
		hum = hum + (45 - hum) * 0.6
		wind = 0
	elseif sheltered then
		-- a roof but no fire (caves, barns, ruins): out of the wind, milder, still cold in winter
		temp = temp + (12 - temp) * 0.45
		wind = 0
	end
	if climate.indoor then wind = 0 end

	-- standing by a fire or a forge; a hearth in the open is only a campfire
	local heatKey = opts.heat
	if heatKey == "hearth" and not sheltered and not climate.indoor then heatKey = "campfire" end
	local heat = heatKey and ns.HeatSources[heatKey]
	if heat then
		temp = temp + (heat.temp - temp) * heat.hold
		hum = hum + (heat.hum - hum) * 0.6
	end

	-- feels-like: wind chill when cold, mugginess when hot
	local feels = temp
	if temp <= 10 and wind > 5 then
		local v = wind ^ 0.16
		feels = 13.12 + 0.6215 * temp - 11.37 * v + 0.3965 * temp * v
	elseif temp >= 27 then
		feels = temp + (hum - 40) * 0.1
	end

	local windName = WIND_NAMES[#WIND_NAMES][2]
	for _, w in ipairs(WIND_NAMES) do
		if wind < w[1] then windName = w[2] break end
	end

	local pressure = 1034 - wet * 48 + (hash01(zone .. ":p", 0) - 0.5) * 6
	local ahead = wetness(zone, t + 3600)
	local trend = (ahead - wet > 0.04) and "falling" or (wet - ahead > 0.04) and "rising" or "steady"

	local w = {
		zone = zone, hour = hour, phase = phaseName, isNight = isNight, isTwilight = isTwilight,
		key = key, label = isNight and cond.night or cond.day,
		flavor = isNight and cond.flavor.night or cond.flavor.day,
		icon = cond.icon or (isNight and ns.MOON_ICON or ns.SUN_ICON),
		temp = temp, feels = feels, humidity = floor(hum + 0.5),
		wind = wind, windName = windName, windDir = COMPASS[floor(bearing / 45 + 0.5) % 8 + 1],
		pressure = floor(pressure + 0.5), trend = trend,
		sheltered = sheltered, heated = heated, outside = outside, indoor = climate.indoor or false,
		heat = heat and heatKey or nil, heatLabel = heat and heat.label or nil,
	}
	w.moon, w.moonIndex = ns.GetMoonPhase(t)
	return w
end

-- Sky colour, horizon glow colour and glow strength for an hour and sky mood.
local function lerp3(a, b, t)
	return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t }
end

function ns.SkyAt(hour, moodName)
	local rows = ns.SkyByHour
	local a, b = rows[#rows], rows[1]
	for i, row in ipairs(rows) do
		if hour >= row[1] then a, b = row, rows[i + 1] or rows[1] end
	end
	local span = (b[1] - a[1]) % 24
	if span == 0 then span = 24 end
	local t = ((hour - a[1]) % 24) / span
	t = t * t * (3 - 2 * t)
	local sky, glowCol = lerp3(a[2], b[2], t), lerp3(a[3], b[3], t)
	local glow = a[4] + (b[4] - a[4]) * t

	local m = ns.SkyMoods[moodName or "clear"] or ns.SkyMoods.clear
	if m.desat and m.desat > 0 then
		local l = sky[1] * 0.3 + sky[2] * 0.59 + sky[3] * 0.11
		sky = lerp3(sky, { l, l, l * 1.08 }, m.desat)
		glowCol = lerp3(glowCol, { l + 0.3, l + 0.3, l + 0.3 }, m.desat * 0.7)
	end
	if m.tint then sky = lerp3(sky, m.tint, m.amount) end
	local d = m.dark or 1
	sky = { sky[1] * d, sky[2] * d, sky[3] * d }
	return sky, glowCol, glow * (m.glow or 1)
end

-- Where the sun (by day) or the moon (by night) is on its arc: 0 = rising, 0.5 = highest, 1 = setting.
function ns.ArcAt(hour)
	local rise, set = ns.SUNRISE, ns.SUNSET
	if hour >= rise and hour < set then
		return (hour - rise) / (set - rise), true
	end
	local nightLen = 24 - (set - rise)
	return ((hour - set) % 24) / nightLen, false
end

-- What the sky will be doing a few hours from now (for the "outlook" line).
function ns.Outlook(zone, t, hour, opts, hoursAhead)
	-- a forecast: what the game shows now says nothing about later
	local ahead = {}
	for k, v in pairs(opts or {}) do ahead[k] = v end
	ahead.weather = nil
	local w = ns.Simulate(zone, t + hoursAhead * 3600, (hour + hoursAhead) % 24, ahead)
	return w.label, w.phase
end
