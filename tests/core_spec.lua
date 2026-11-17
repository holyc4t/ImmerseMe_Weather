-- Runs under standalone Lua (tests/run.lua), not the WoW client.
---@diagnostic disable: undefined-global
-- ns.Simulate: the weather for a zone at a moment.

local T0 = 1700000000          -- a fixed realm time (November 2023), so every run sees the same weather
local COMPASS = { N = true, NE = true, E = true, SE = true, S = true, SW = true, W = true, NW = true }
local TRENDS = { rising = true, falling = true, steady = true }

-- Every zone in the data, plus one the data doesn't know.
local function allZones()
	local zones = { "Nowhere In Particular" }
	for z in pairs(ns.Zones) do zones[#zones + 1] = z end
	table.sort(zones)
	return zones
end

-- Calls fn(w, zone, t, hour) for a spread of times in every outdoor zone.
local function sweep(fn, opts, steps)
	for _, zone in ipairs(allZones()) do
		for k = 0, (steps or 40) - 1 do
			local t, hour = T0 + k * 7919, (k * 2.37) % 24
			fn(ns.Simulate(zone, t, hour, opts), zone, t, hour)
		end
	end
end

-- Searches the sweep for a moment whose simulated sky passes pred(w); returns zone, t, hour.
local function find(pred)
	local hit
	sweep(function(w, zone, t, hour) if not hit and pred(w) then hit = { zone, t, hour } end end, nil, 200)
	if hit then return hit[1], hit[2], hit[3] end
end

test("same inputs give the same weather", function()
	eq(ns.Simulate("Duskwood", T0, 13.5), ns.Simulate("Duskwood", T0, 13.5))
end)

test("weather changes over time", function()
	local a = ns.Simulate("Elwynn Forest", T0, 12)
	local b = ns.Simulate("Elwynn Forest", T0 + 6 * 3600, 18)
	ok(a.temp ~= b.temp, "temperature drifts")
end)

test("empty or missing zone is 'Unknown'", function()
	eq(ns.Simulate("", T0, 12).zone, "Unknown")
	eq(ns.Simulate(nil, T0, 12).zone, "Unknown")
end)

test("every reading is well formed", function()
	sweep(function(w, zone)
		local where = zone .. " @" .. w.hour
		ok(ns.Conditions[w.key], where .. " key " .. tostring(w.key))
		ok(type(w.label) == "string" and w.label ~= "", where .. " label")
		ok(type(w.flavor) == "string" and w.flavor ~= "", where .. " flavor")
		ok(w.humidity >= 3 and w.humidity <= 100, where .. " humidity " .. w.humidity)
		ok(w.wind >= 0, where .. " wind >= 0")
		ok(COMPASS[w.windDir], where .. " windDir " .. tostring(w.windDir))
		ok(TRENDS[w.trend], where .. " trend " .. tostring(w.trend))
		ok(w.temp > -60 and w.temp < 70, where .. " temp plausible " .. w.temp)
		ok(w.pressure > 950 and w.pressure < 1060, where .. " pressure plausible " .. w.pressure)
		ok(type(w.moon) == "string", where .. " moon")
	end)
end)

test("label follows day and night", function()
	local w = ns.Simulate("Elwynn Forest", T0, 2)
	ok(w.isNight, "2am is night")
	eq(w.label, ns.Conditions[w.key].night)
	w = ns.Simulate("Elwynn Forest", T0, 12)
	ok(not w.isNight, "noon is day")
	eq(w.label, ns.Conditions[w.key].day)
end)

test("an instance is under stone with no wind", function()
	local w = ns.Simulate("Elwynn Forest", T0, 12, { instance = true })
	eq(w.key, "indoors")
	eq(w.wind, 0)
	ok(w.indoor, "indoor")
end)

test("an indoor city (Ironforge) has no sky and no wind", function()
	sweep(function(w, zone)
		if zone == "Ironforge" or zone == "Undercity" then
			eq(w.key, "indoors", zone)
			eq(w.wind, 0, zone)
		end
	end)
end)

test("sheltered: out of the wind, temperature pulled towards 12", function()
	local open = ns.Simulate("Dun Morogh", T0, 3)
	local roof = ns.Simulate("Dun Morogh", T0, 3, { sheltered = true })
	ok(roof.sheltered and not roof.heated, "sheltered, not heated")
	eq(roof.wind, 0)
	near(roof.temp, open.temp + (12 - open.temp) * 0.45, 1e-9)
	near(roof.outside, open.temp, 1e-9, "outside keeps the open-air temperature")
end)

test("heated: comfortable whatever the weather", function()
	sweep(function(w, zone)
		if w.indoor then return end   -- indoor cities (Ironforge, Undercity) have their own climate
		ok(w.heated, zone .. " heated")
		eq(w.wind, 0, zone)
		ok(math.abs(w.temp - 19) < 8, zone .. " temp near 19, got " .. w.temp)
	end, { sheltered = true, heated = true })
end)

test("heated needs a roof", function()
	local w = ns.Simulate("Elwynn Forest", T0, 12, { heated = true })
	ok(not w.heated, "heated without sheltered is ignored")
end)

test("a hearth in the open is a campfire", function()
	local w = ns.Simulate("Elwynn Forest", T0, 12, { heat = "hearth" })
	eq(w.heat, "campfire")
	eq(w.heatLabel, ns.HeatSources.campfire.label)
	w = ns.Simulate("Elwynn Forest", T0, 12, { heat = "hearth", sheltered = true })
	eq(w.heat, "hearth")
end)

test("standing by a fire warms you", function()
	local cold = ns.Simulate("Dun Morogh", T0, 3)
	local fire = ns.Simulate("Dun Morogh", T0, 3, { heat = "forge" })
	local h = ns.HeatSources.forge
	near(fire.temp, cold.temp + (h.temp - cold.temp) * h.hold, 1e-9)
end)

test("game snow: snowy key by intensity, thermometer at or below freezing", function()
	local w = ns.Simulate("Elwynn Forest", T0, 12, { weather = { kind = "snow", intensity = 0.1 } })
	eq(w.key, "flurries")
	ok(w.temp <= 0, "temp <= 0, got " .. w.temp)
	eq(ns.Simulate("Elwynn Forest", T0, 12, { weather = { kind = "snow", intensity = 0.5 } }).key, "snow")
	eq(ns.Simulate("Elwynn Forest", T0, 12, { weather = { kind = "snow", intensity = 0.9 } }).key, "blizzard")
end)

test("game rain: rainy key by intensity, thermometer above freezing", function()
	local w = ns.Simulate("Dun Morogh", T0, 3, { weather = { kind = "rain", intensity = 0.5 } })
	eq(w.key, "rain")
	ok(w.temp >= 1, "temp >= 1, got " .. w.temp)
	eq(ns.Simulate("Dun Morogh", T0, 3, { weather = { kind = "rain", intensity = 2 } }).key, "storm")
end)

test("a clear game sky removes simulated precipitation", function()
	local zone, t, hour = find(function(w) return ns.Precipitation[w.key] end)
	ok(zone, "the sweep finds some simulated precipitation")
	local w = ns.Simulate(zone, t, hour, { weather = { kind = "clear", intensity = 0 } })
	ok(not ns.Precipitation[w.key], ("%s: clear game sky but key %s"):format(zone, w.key))
end)

test("game weather is ignored indoors", function()
	local w = ns.Simulate("Ironforge", T0, 12, { weather = { kind = "snow", intensity = 0.9 } })
	eq(w.key, "indoors")
end)

test("no rain below freezing, no snow above thaw (without game weather)", function()
	-- rain turns to snow under -1C and snow to rain over 3C, judged before the condition's own
	-- temperature modifier is added, so take that modifier back off to check
	sweep(function(w, zone)
		if w.indoor then return end
		local before = w.temp - ns.Conditions[w.key].temp
		local snowy = w.key == "flurries" or w.key == "snow" or w.key == "blizzard"
		local rainy = w.key == "drizzle" or w.key == "rain" or w.key == "storm"
		if snowy then ok(before <= 3 + 1e-9, ("%s %s at %.2f"):format(zone, w.key, before)) end
		if rainy then ok(before >= -1 - 1e-9, ("%s %s at %.2f"):format(zone, w.key, before)) end
	end, nil, 80)
end)

test("snowy zones rain when they warm up (thaw) and never snow above 3C", function()
	-- the alpine sky ladder has no rain at all, so any rain there is snow that thawed
	local rained = false
	for zone, climate in pairs(ns.Zones) do
		if climate == "alpine" then
			for k = 0, 365 do                                  -- a year, a day and a bit at a time
				local w = ns.Simulate(zone, T0 + k * (86400 + 3607), (k * 5.3) % 24)
				local before = w.temp - ns.Conditions[w.key].temp
				if w.key == "drizzle" or w.key == "rain" or w.key == "storm" then rained = true end
				if w.key == "flurries" or w.key == "snow" or w.key == "blizzard" then
					ok(before <= 3 + 1e-9, ("%s %s at %.2f"):format(zone, w.key, before))
				end
			end
		end
	end
	ok(rained, "a warm spell in an alpine zone brings rain")
end)

test("outlook ignores what the game shows now", function()
	local opts = { weather = { kind = "snow", intensity = 0.9 } }
	local label, phase = ns.Outlook("Elwynn Forest", T0, 22, opts, 3)
	local later = ns.Simulate("Elwynn Forest", T0 + 3 * 3600, 1, {})
	eq(label, later.label)
	eq(phase, later.phase)
	ok(opts.weather, "caller's opts are not modified")
end)
