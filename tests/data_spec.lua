-- Runs under standalone Lua (tests/run.lua), not the WoW client.
---@diagnostic disable: undefined-global
-- Data.lua is meant to be hand-edited; these catch typos that would only show up in game.

local function str(v) return type(v) == "string" and v ~= "" end

test("every condition is complete", function()
	for key, c in pairs(ns.Conditions) do
		ok(str(c.day) and str(c.night), key .. " day/night labels")
		ok(type(c.flavor) == "table" and str(c.flavor.day) and str(c.flavor.night), key .. " flavor")
		for _, f in ipairs({ "temp", "hum", "windMul", "wind" }) do
			ok(type(c[f]) == "number", key .. "." .. f .. " is a number")
		end
		ok(c.icon == nil or c.icon:find("^Interface\\Icons\\"), key .. " icon has the icon path prefix")
	end
end)

test("every climate is complete and its sky ladder names real conditions", function()
	for name, cl in pairs(ns.Climates) do
		for _, f in ipairs({ "temp", "swing", "season", "hum", "wind" }) do
			ok(type(cl[f]) == "number", name .. "." .. f .. " is a number")
		end
		if cl.indoor then
			ok(cl.sky == nil, name .. " is indoor and has no sky")
		else
			ok(type(cl.sky) == "table" and #cl.sky > 0, name .. " has a sky ladder")
			for i, step in ipairs(cl.sky) do
				ok(ns.Conditions[step[1]], ("%s sky[%d] %s is a condition"):format(name, i, tostring(step[1])))
				ok(type(step[2]) == "number" and step[2] > 0, ("%s sky[%d] weight > 0"):format(name, i))
			end
		end
	end
end)

test("default and instance climates exist", function()
	ok(ns.Climates[ns.DEFAULT_CLIMATE], "DEFAULT_CLIMATE")
	ok(ns.Climates[ns.INSTANCE_CLIMATE], "INSTANCE_CLIMATE")
	ok(ns.Climates[ns.INSTANCE_CLIMATE].indoor, "instance climate is indoor")
end)

test("every zone maps to a real climate", function()
	ok(next(ns.Zones), "ns.Zones not empty")
	for zone, climate in pairs(ns.Zones) do
		ok(ns.Climates[climate], zone .. " -> " .. tostring(climate))
	end
end)

test("sky moods and particles refer to real conditions", function()
	for cond, mood in pairs(ns.SkyMood) do
		ok(ns.Conditions[cond], "SkyMood key " .. cond)
		ok(ns.SkyMoods[mood], "SkyMood " .. cond .. " -> " .. mood)
	end
	for cond in pairs(ns.StarrySky) do ok(ns.Conditions[cond], "StarrySky " .. cond) end
	for cond in pairs(ns.Precipitation) do ok(ns.Conditions[cond], "Precipitation " .. cond) end
	for cond, p in pairs(ns.OrbParticles) do
		ok(ns.Conditions[cond], "OrbParticles " .. cond)
		ok(type(p.n) == "number" and type(p.speed) == "number", cond .. " particles n/speed")
	end
end)

test("game weather ladders are ascending and name real conditions", function()
	for kind, ladder in pairs(ns.GameWeather) do
		local last = -math.huge
		for i, step in ipairs(ladder) do
			ok(step[1] > last, ("%s step %d threshold ascends"):format(kind, i))
			ok(ns.Conditions[step[2]], ("%s step %d -> %s"):format(kind, i, tostring(step[2])))
			last = step[1]
		end
	end
end)

test("sky by hour is sorted and in range", function()
	local last = -1
	for i, row in ipairs(ns.SkyByHour) do
		ok(row[1] > last and row[1] < 24, "row " .. i .. " hour ascends within the day")
		for c = 2, 3 do
			for ch = 1, 3 do
				local v = row[c][ch]
				ok(v >= 0 and v <= 1, ("row %d colour %d channel %d in 0..1"):format(i, c, ch))
			end
		end
		ok(row[4] >= 0 and row[4] <= 1, "row " .. i .. " glow in 0..1")
		last = row[1]
	end
	ok(ns.SUNRISE < ns.SUNSET, "sunrise before sunset")
end)

test("heat sources and warm places", function()
	for key, h in pairs(ns.HeatSources) do
		ok(type(h.temp) == "number" and type(h.hum) == "number", key .. " temp/hum")
		ok(h.hold > 0 and h.hold <= 1, key .. " hold in (0,1]")
		ok(str(h.label), key .. " label")
	end
	for place, kind in pairs(ns.WarmPlaces) do
		ok(ns.HeatSources[kind], place .. " -> " .. tostring(kind))
	end
	for i, spot in ipairs(ns.FireSpots) do
		ok(type(spot[1]) == "number" and type(spot[2]) == "number", "FireSpots[" .. i .. "] x/y")
		ok(ns.HeatSources[spot[4]], "FireSpots[" .. i .. "] kind")
	end
end)
