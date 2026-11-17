-- Runs under standalone Lua (tests/run.lua), not the WoW client.
---@diagnostic disable: undefined-global
-- Time of day, moon, and the orb's sky colours and arc.

test("phases of the day", function()
	local cases = {
		{ 0,     "Dead of Night", true,  false },
		{ 3.99,  "Dead of Night", true,  false },
		{ 4,     "Before Dawn",   true,  false },
		{ 5.5,   "Dawn",          false, true },
		{ 12,    "Midday",        false, false },
		{ 19.5,  "Dusk",          false, true },
		{ 20.99, "Dusk",          false, true },
		{ 21,    "Night",         true,  false },
		{ 23.99, "Night",         true,  false },
	}
	for _, c in ipairs(cases) do
		local name, night, twilight = ns.GetPhase(c[1])
		eq({ name, night, twilight }, { c[2], c[3], c[4] }, "hour " .. c[1])
	end
end)

test("moon phases", function()
	local NEW = 947182440                       -- the reference new moon in Core.lua
	local MONTH = 29.530588 * 86400
	eq({ ns.GetMoonPhase(NEW) }, { "New Moon", 0 })
	eq({ ns.GetMoonPhase(NEW + MONTH / 2) }, { "Full Moon", 4 })
	eq({ ns.GetMoonPhase(NEW + MONTH / 4) }, { "First Quarter", 2 })
	eq({ ns.GetMoonPhase(NEW + MONTH * 100) }, { "New Moon", 0 }, "a hundred months later")
end)

test("sky colour at a row's hour is that row's colour", function()
	for i, row in ipairs(ns.SkyByHour) do
		local sky, glowCol, glow = ns.SkyAt(row[1], "clear")
		for ch = 1, 3 do
			near(sky[ch], row[2][ch], 1e-9, "row " .. i .. " sky")
			near(glowCol[ch], row[3][ch], 1e-9, "row " .. i .. " glow colour")
		end
		near(glow, row[4], 1e-9, "row " .. i .. " glow")
	end
end)

test("sky colour wraps smoothly past midnight", function()
	local last, first = ns.SkyByHour[#ns.SkyByHour], ns.SkyByHour[1]
	local late = ns.SkyAt(23.999)
	for ch = 1, 3 do near(late[ch], first[2][ch], 1e-3, "just before midnight ~ first row") end
	local mid = ns.SkyAt((last[1] + 24) / 2 % 24)
	for ch = 1, 3 do
		local lo, hi = math.min(last[2][ch], first[2][ch]), math.max(last[2][ch], first[2][ch])
		ok(mid[ch] >= lo - 1e-9 and mid[ch] <= hi + 1e-9, "between the last and first rows")
	end
end)

test("sky colours stay in 0..1 for every mood and hour", function()
	for mood in pairs(ns.SkyMoods) do
		for h = 0, 23.75, 0.25 do
			local sky, glowCol, glow = ns.SkyAt(h, mood)
			for ch = 1, 3 do
				ok(sky[ch] >= 0 and sky[ch] <= 1, ("%s %s sky ch%d = %s"):format(mood, h, ch, sky[ch]))
				ok(glowCol[ch] >= 0 and glowCol[ch] <= 1.3, ("%s %s glow ch%d"):format(mood, h, ch))
			end
			ok(glow >= 0 and glow <= 1, mood .. " glow")
		end
	end
end)

test("dark weather darkens the sky; unknown mood is clear", function()
	local function sum(c) return c[1] + c[2] + c[3] end
	ok(sum((ns.SkyAt(12, "dark"))) < sum((ns.SkyAt(12, "clear"))), "dark is darker than clear")
	eq({ ns.SkyAt(12, "no such mood") }, { ns.SkyAt(12, "clear") })
	eq({ ns.SkyAt(12) }, { ns.SkyAt(12, "clear") })
end)

test("sun and moon arcs", function()
	local rise, set = ns.SUNRISE, ns.SUNSET
	eq({ ns.ArcAt(rise) }, { 0, true })
	eq({ ns.ArcAt((rise + set) / 2) }, { 0.5, true })
	eq({ ns.ArcAt(set) }, { 0, false })
	local f, isSun = ns.ArcAt((set + 24 + rise) / 2 % 24)
	near(f, 0.5, 1e-9, "middle of the night")
	ok(not isSun, "moon at night")
	f = ns.ArcAt(rise - 0.001)
	ok(f > 0.99 and f < 1, "just before sunrise the moon is setting")
end)
