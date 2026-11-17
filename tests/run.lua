-- Runs under standalone Lua (tests/run.lua), not the WoW client.
---@diagnostic disable: undefined-global, undefined-field, lowercase-global
-- Runs the pure-logic tests outside the game:  lua tests/run.lua  (from the repo root)
date = date or os.date
time = time or os.time
unpack = unpack or table.unpack

ns = {}
local ADDON = "ImmerseMe_Weather"
for _, file in ipairs({ "Data.lua", "Core.lua" }) do
	local chunk = assert(loadfile(file))
	chunk(ADDON, ns)
end

local tests = {}
function test(name, fn) tests[#tests + 1] = { name = name, fn = fn } end

local function deepEq(a, b)
	if type(a) ~= type(b) then return false end
	if type(a) ~= "table" then return a == b end
	for k, v in pairs(a) do if not deepEq(v, b[k]) then return false end end
	for k in pairs(b) do if a[k] == nil then return false end end
	return true
end

local function show(v, depth)
	depth = depth or 0
	if type(v) ~= "table" then return type(v) == "string" and ("%q"):format(v) or tostring(v) end
	if depth > 3 then return "{...}" end
	local keys = {}
	for k in pairs(v) do keys[#keys + 1] = k end
	table.sort(keys, function(x, y) return tostring(x) < tostring(y) end)
	local parts = {}
	for _, k in ipairs(keys) do parts[#parts + 1] = tostring(k) .. "=" .. show(v[k], depth + 1) end
	return "{" .. table.concat(parts, ", ") .. "}"
end

function eq(actual, expected, msg)
	if not deepEq(actual, expected) then
		error(("%sexpected %s, got %s"):format(msg and (msg .. ": ") or "", show(expected), show(actual)), 2)
	end
end

function ok(cond, msg)
	if not cond then error("not ok: " .. tostring(msg), 2) end
end

-- numbers equal within tol (default 1e-6)
function near(actual, expected, tol, msg)
	tol = tol or 1e-6
	if type(actual) ~= "number" or math.abs(actual - expected) > tol then
		error(("%sexpected %s (+/- %s), got %s"):format(msg and (msg .. ": ") or "", expected, tol, tostring(actual)), 2)
	end
end

for _, spec in ipairs({ "tests/data_spec.lua", "tests/core_spec.lua", "tests/sky_spec.lua" }) do dofile(spec) end

local passed, failed = 0, 0
for _, t in ipairs(tests) do
	local good, err = pcall(t.fn)
	if good then passed = passed + 1 else
		failed = failed + 1
		print("FAIL " .. t.name .. ": " .. tostring(err))
	end
end
print(("%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
