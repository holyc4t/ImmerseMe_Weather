-- ImmerseMe: Weather - minimap sky orb, compact minimap readout, slash commands.
local ADDON, ns = ...

local floor, sqrt, max, min = math.floor, math.sqrt, math.max, math.min
local MEDIA = ns.MEDIA
local db

local DEFAULTS = {
	fahrenheit  = false,    -- temperature unit
	mph         = false,    -- wind unit
	localTime   = false,    -- false = realm time (matches the in-game sky), true = your PC clock
	showReadout = true,
	showOrb     = true,
	tempIcon    = true,     -- thermometer / snowflake next to the temperature
	useStock    = true,     -- draw the sky on the stock day/night icon instead of a separate orb
	locked      = false,    -- when unlocked, Shift-drag moves the orb
	fontSize    = 11,
	gap         = 10,       -- distance between the readout and the minimap edge
	arc         = "low",    -- where the readout sits on the minimap's left edge: high | middle | low
	yOffset     = 0,        -- extra vertical nudge in pixels (negative = lower)
	hide        = {},       -- names of stock frames to hide (see /imw hide)
	spots       = {},       -- fires and forges this player has discovered
}

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------
local function GetHour()
	local h, m
	if not db.localTime and GetGameTime then
		h, m = GetGameTime()
	end
	if not h then
		local d = date("*t")
		h, m = d.hour, d.min
	end
	return h + m / 60, h, m
end

-- A fire the player said they're standing by (/imw fire, /imw forge).
-- It lasts until they walk away from where they lit it, or FIRE_MINUTES pass.
local FIRE_RANGE, FIRE_MINUTES = 10, 30
local fire     -- { kind = "hearth" | "forge", x, y, map, expires }

local function PlayerPos()
	if not UnitPosition then return nil end
	local y, x, _, map = UnitPosition("player")
	return x, y, map
end

-- true when the player has walked away from the fire (or it burned out)
local function LeftFire()
	if not fire then return false end
	if GetTime() > fire.expires then return true end
	local x, y, map = PlayerPos()
	if not (x and fire.x) then return false end
	if map ~= fire.map then return true end
	return (x - fire.x) ^ 2 + (y - fire.y) ^ 2 > FIRE_RANGE * FIRE_RANGE
end

-- Fires the addon knows about: the shared list in Data.lua plus the ones this
-- player discovered (by cooking or smelting next to them, or with /imw fire | forge).
-- A spot is { x, y, continent, kind } in world yards.
local SPOT_RANGE, SPOT_MERGE = 8, 5
-- crafting that only works next to a heat source
-- (trade skill window names; the smelting window is "Mining" or "Smelting" depending on the client)
local LEARN_FROM = { Cooking = "hearth", Mining = "forge", Smelting = "forge" }

local function NearestSpot(maxDist)
	local x, y, map = PlayerPos()
	if not x then return nil end
	local best, bestD
	for _, list in ipairs({ ns.FireSpots or {}, (db and db.spots) or {} }) do
		for _, s in ipairs(list) do
			if s[3] == map then
				local d = (x - s[1]) ^ 2 + (y - s[2]) ^ 2
				if d <= maxDist * maxDist and (not bestD or d < bestD) then best, bestD = s, d end
			end
		end
	end
	return best
end

-- Remembers a heat source where the player stands. Returns true if it was new.
local function RememberSpot(kind)
	local x, y, map = PlayerPos()
	if not x or NearestSpot(SPOT_MERGE) then return false end
	table.insert(db.spots, { floor(x * 10 + 0.5) / 10, floor(y * 10 + 0.5) / 10, map, kind })
	return true
end

local function GetWorld()
	local hour, h, m = GetHour()
	local t = (GetServerTime and GetServerTime()) or time()
	local zone = GetRealZoneText() or GetZoneText() or ""
	local inInstance = IsInInstance and IsInInstance() or false
	local indoors = IsIndoors and IsIndoors() or false
	local subzone = GetSubZoneText and GetSubZoneText() or ""
	local opts = {
		instance  = inInstance,
		sheltered = indoors,
		heated    = IsResting and IsResting() or false,   -- inns, taverns, city buildings
		heat      = (fire and fire.kind) or (NearestSpot(SPOT_RANGE) or {})[4]
			or (indoors and ns.WarmPlaces[subzone]) or nil,
	}
	local w = ns.Simulate(zone, t, hour, opts)
	w.clock = ("%02d:%02d"):format(h, m)
	w.subzone = GetSubZoneText and GetSubZoneText() or ""
	w.outlook = ns.Outlook(zone, t, hour, opts, 3)
	return w
end

local function FormatTemp(c)
	if db.fahrenheit then return ("%d°F"):format(floor(c * 9 / 5 + 32 + 0.5)) end
	return ("%d°C"):format(floor(c + 0.5))
end

local function FormatWind(kmh)
	if db.mph then return ("%d mph"):format(floor(kmh * 0.621371 + 0.5)) end
	return ("%d km/h"):format(floor(kmh + 0.5))
end

local function TempColor(c)
	if c <= -5 then return 0.55, 0.75, 1.0
	elseif c <= 8 then return 0.75, 0.9, 1.0
	elseif c <= 22 then return 1.0, 1.0, 1.0
	elseif c <= 30 then return 1.0, 0.85, 0.5
	else return 1.0, 0.55, 0.3 end
end

-- How it *feels* drives the badge, so a windy 5°C shows the cold thermometer.
local function TempBadge(feels)
	if feels <= 0 then return "freezing"
	elseif feels <= 10 then return "cold"
	elseif feels <= 21 then return "mild"
	elseif feels <= 28 then return "warm"
	else return "hot" end
end

local function WindText(w)
	if w.indoor then return "Still air" end
	if w.heated then return "By the hearth" end
	if w.sheltered then return "Sheltered" end
	if w.wind < 2 then return "Calm" end
	return ("%s %s"):format(w.windDir, FormatWind(w.wind))
end


---------------------------------------------------------------------------
-- Tooltip (shared by orb and readout)
---------------------------------------------------------------------------
local function ShowTooltip(owner, anchor)
	local w = GetWorld()
	GameTooltip:SetOwner(owner, anchor or "ANCHOR_LEFT")
	GameTooltip:AddLine(w.zone, 1, 0.82, 0)
	if w.subzone ~= "" and w.subzone ~= w.zone then GameTooltip:AddLine(w.subzone, 0.8, 0.8, 0.8) end
	GameTooltip:AddDoubleLine(w.phase, w.clock, 1, 1, 1, 1, 1, 1)
	GameTooltip:AddLine(w.sheltered and (w.label .. " outside") or w.label, 0.6, 0.85, 1)
	GameTooltip:AddLine(" ")
	local r, g, b = TempColor(w.temp)
	GameTooltip:AddDoubleLine("Temperature", ("%s (feels %s)"):format(FormatTemp(w.temp), FormatTemp(w.feels)), 0.7, 0.7, 0.7, r, g, b)
	if w.heatLabel then
		GameTooltip:AddDoubleLine("Warmth", w.heatLabel, 0.7, 0.7, 0.7, 1, 0.7, 0.35)
	end
	if w.sheltered or w.heatLabel then
		GameTooltip:AddDoubleLine((w.heated or w.heatLabel) and "Outside the door" or "Outside", FormatTemp(w.outside),
			0.7, 0.7, 0.7, TempColor(w.outside))
	end
	GameTooltip:AddDoubleLine("Wind", (w.indoor or w.sheltered or w.wind < 2) and WindText(w)
		or ("%s from the %s, %s"):format(w.windName, w.windDir, FormatWind(w.wind)), 0.7, 0.7, 0.7, 1, 1, 1)
	GameTooltip:AddDoubleLine("Humidity", w.humidity .. "%", 0.7, 0.7, 0.7, 1, 1, 1)
	GameTooltip:AddDoubleLine("Barometer", ("%d hPa, %s"):format(w.pressure, w.trend), 0.7, 0.7, 0.7, 1, 1, 1)
	if not w.indoor then
		GameTooltip:AddDoubleLine("Moon", w.moon, 0.7, 0.7, 0.7, 1, 1, 1)
		GameTooltip:AddDoubleLine("Outlook", w.outlook, 0.7, 0.7, 0.7, 1, 1, 1)
	end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine(w.flavor, 0.85, 0.8, 0.65, true)
	if owner.isOrb and not db.locked then GameTooltip:AddLine("Shift-drag to move", 0.5, 0.5, 0.5) end
	GameTooltip:Show()
end

---------------------------------------------------------------------------
-- Minimap orb: a little window onto the sky.
-- Layers, back to front: sky gradient (tinted by hour and weather), horizon
-- glow (dawn / dusk), stars, the sun or moon on its arc, the weather.
---------------------------------------------------------------------------
local ORB_ICON = 20

local orb = CreateFrame("Button", "ImmerseMeWeatherOrb", Minimap)
orb:SetSize(31, 31)
orb:SetFrameStrata("MEDIUM")
orb:SetFrameLevel(Minimap:GetFrameLevel() + 10)
orb.isOrb = true
local skinned       -- the stock day/night frame the orb is drawn on, if any
local stockArt, stockRing   -- its sun/moon art and gold ring textures

orb.window = CreateFrame("Frame", nil, orb)   -- the round "window" onto the sky
orb.window:SetSize(ORB_ICON, ORB_ICON)
orb.window:SetPoint("CENTER")

orb.sky     = orb.window:CreateTexture(nil, "BACKGROUND", nil, 0)
orb.horizon = orb.window:CreateTexture(nil, "BACKGROUND", nil, 1)
orb.stars   = orb.window:CreateTexture(nil, "BACKGROUND", nil, 2)
orb.base    = orb.window:CreateTexture(nil, "ARTWORK", nil, 1)
orb.wx      = orb.window:CreateTexture(nil, "ARTWORK", nil, 2)
for _, key in ipairs({ "sky", "horizon", "stars", "wx" }) do orb[key]:SetAllPoints() end
orb.sky:SetTexture(MEDIA .. "sky")
orb.horizon:SetTexture(MEDIA .. "horizon")
orb.stars:SetTexture(MEDIA .. "stars")

if orb.CreateMaskTexture then
	local mask = orb.window:CreateMaskTexture()
	mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetAllPoints(orb.window)
	for _, tex in ipairs({ orb.sky, orb.horizon, orb.stars, orb.base, orb.wx }) do tex:AddMaskTexture(mask) end
end

orb.border = orb:CreateTexture(nil, "OVERLAY")
orb.border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
orb.border:SetSize(50, 50)
orb.border:SetPoint("TOPLEFT")

orb:SetScript("OnEnter", function(self) ShowTooltip(self, "ANCHOR_BOTTOMLEFT") end)
orb:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- Places the sun / moon on its arc: f = 0 rising (low left), 0.5 highest, 1 setting (low right).
-- The drift is kept small so the body stays big and readable, like the stock icon.
local function PlaceBody(f, size, raise)
	local W = orb.window:GetWidth() or ORB_ICON
	local lift = math.sin(math.pi * f)
	orb.base:ClearAllPoints()
	orb.base:SetSize(size * W, size * W)
	orb.base:SetPoint("CENTER", orb.window, "CENTER", (-0.15 + 0.30 * f) * W, (-0.16 + 0.24 * lift + (raise or 0)) * W)
	return lift
end

-- Weather that falls from a cloud: the sun / moon sits smaller and higher, behind the cloud.
local FALLING = { drizzle = true, rain = true, storm = true, flurries = true, snow = true, blizzard = true, ashfall = true }

-- size (fraction of the orb) and how far to raise the body, per kind of sky
local function BodySize(key, isSun, lift)
	if FALLING[key] then return 0.62, 0.2 end
	if key == "clear" or key == "fair" or key == "haze" then
		return isSun and (0.9 + 0.1 * lift) or 0.88, 0
	end
	return isSun and 0.8 or 0.78, 0
end

local function UpdateOrb(w)
	if w.indoor then
		orb.sky:SetVertexColor(0.30, 0.20, 0.12)
		orb.horizon:SetVertexColor(1.0, 0.6, 0.25)
		orb.horizon:SetAlpha(0.5)
		orb.stars:Hide()
		orb.base:SetTexture(ns.Conditions.indoors.icon)
		orb.base:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		orb.base:SetVertexColor(1, 1, 1)
		orb.base:ClearAllPoints()
		orb.base:SetAllPoints(orb.window)
		orb.wx:Hide()
		return
	end
	orb.base:SetTexCoord(0, 1, 0, 1)

	local mood = ns.SkyMood[w.key] or "clear"
	local sky, glowCol, glow = ns.SkyAt(w.hour, mood)
	orb.sky:SetVertexColor(sky[1], sky[2], sky[3])
	orb.horizon:SetVertexColor(glowCol[1], glowCol[2], glowCol[3])
	orb.horizon:SetAlpha(glow)

	local f, isSun = ns.ArcAt(w.hour)
	if isSun then
		orb.stars:Hide()
		orb.base:SetTexture(MEDIA .. "sun")
		local lift = math.sin(math.pi * f)
		PlaceBody(f, BodySize(w.key, true, lift))
		-- a low sun burns orange
		local low = 1 - math.min(1, lift * 2.2)
		orb.base:SetVertexColor(1, 1 - 0.28 * low, 1 - 0.45 * low)
	else
		orb.base:SetTexture(MEDIA .. "moon_" .. (w.moonIndex or 4))
		orb.base:SetVertexColor(1, 1, 1)
		local lift = PlaceBody(f, BodySize(w.key, false, 0))
		if ns.StarrySky[w.key] then
			orb.stars:SetAlpha(0.45 + 0.55 * lift)
			orb.stars:Show()
		else
			orb.stars:Hide()
		end
	end

	if w.key == "clear" then
		orb.wx:Hide()
	else
		orb.wx:SetTexture(MEDIA .. "wx_" .. w.key .. (w.isNight and "_night" or "_day"))
		orb.wx:Show()
	end
end

local function DefaultOrbPosition(frame)
	local r = Minimap:GetWidth() / 2 + 6
	local a = math.rad(55)      -- upper right, where the stock sun/moon sits
	frame:SetPoint("CENTER", Minimap, "CENTER", r * math.cos(a), r * math.sin(a))
end

---------------------------------------------------------------------------
-- Compact readout hugging the minimap's left edge
---------------------------------------------------------------------------
local font = CreateFont("ImmerseMeWeatherFont")

local readout = CreateFrame("Frame", "ImmerseMeWeatherReadout", Minimap)
readout:SetAllPoints(Minimap)
readout:SetFrameStrata("MEDIUM")
readout:SetFrameLevel(Minimap:GetFrameLevel() + 9)
readout:EnableMouse(false)    -- the minimap underneath stays clickable

local rows = {}
local function NewRow()
	local row = CreateFrame("Frame", nil, readout)
	row:EnableMouse(true)
	row.text = row:CreateFontString(nil, "OVERLAY")
	row.text:SetFontObject(font)
	row.text:SetPoint("RIGHT")
	row.text:SetJustifyH("RIGHT")
	row:SetScript("OnEnter", function(self) ShowTooltip(self) end)
	row:SetScript("OnLeave", function() GameTooltip:Hide() end)
	rows[#rows + 1] = row
	return row
end

local tempRow = NewRow()
tempRow.icon = tempRow:CreateTexture(nil, "OVERLAY")
tempRow.icon:SetPoint("RIGHT", tempRow.text, "LEFT", -1, 0)
local windRow, humRow, presRow = NewRow(), NewRow(), NewRow()

local function FitRow(row)
	local w = row.text:GetStringWidth()
	if row.icon and row.icon:IsShown() then w = w + row.icon:GetWidth() + 1 end
	row:SetWidth(max(1, w))
end

-- Places each line so its right edge follows the minimap's curve.
local function LayoutReadout()
	local size = db.fontSize
	font:SetFont(STANDARD_TEXT_FONT, size, "OUTLINE")
	font:SetShadowOffset(1, -1)
	font:SetShadowColor(0, 0, 0, 0.8)
	tempRow.icon:SetSize(size + 4, size + 4)

	local R = Minimap:GetWidth() / 2
	local step = size + 2
	local n = #rows
	local first
	if db.arc == "high" then
		first = R * 0.05 + (n - 0.5) * step
	elseif db.arc == "middle" then
		first = (n - 1) / 2 * step
	else
		first = -R * 0.28 - 10 - step / 2
	end
	for i, row in ipairs(rows) do
		local y = first + db.yOffset - (i - 1) * step
		local yy = min(R, math.abs(y))
		local x = sqrt(R * R - yy * yy) + db.gap
		row:SetHeight(step)
		row:ClearAllPoints()
		row:SetPoint("RIGHT", readout, "CENTER", -x, y)
		FitRow(row)
	end
end

-- The readout counts toward new values instead of jumping: step into a
-- tavern and the temperature climbs degree by degree while the wind dies down.
-- A change takes about COUNT_TIME seconds; small changes tick at a minimum pace.
local COUNT_TIME = 3
local MIN_RATE = { temp = 3, wind = 6, hum = 8, pres = 4 }   -- units per second
local shown, goal, current = {}, {}, nil

local function Render()
	local w = current
	if not w then return end
	local t = shown.temp
	tempRow.text:SetText(FormatTemp(t))
	tempRow.text:SetTextColor(TempColor(t))
	if db.tempIcon then
		-- the badge follows the counting value, keeping the wind-chill / humidity offset
		tempRow.icon:SetTexture(MEDIA .. "temp_" .. TempBadge(w.feels + (t - w.temp)))
		tempRow.icon:Show()
	else
		tempRow.icon:Hide()
	end
	local v = shown.wind
	if v < 2 then
		windRow.text:SetText(w.heatLabel or (w.indoor and "Still air") or (w.heated and "By the hearth")
			or (w.sheltered and "Sheltered") or "Calm")
	else
		windRow.text:SetText(("%s %s"):format(w.windDir, FormatWind(v)))
	end
	humRow.text:SetText(floor(shown.hum + 0.5) .. "%")
	presRow.text:SetText(("%d hPa"):format(floor(shown.pres + 0.5)))
	for _, row in ipairs(rows) do
		if row ~= tempRow then row.text:SetTextColor(0.9, 0.9, 0.9) end
		FitRow(row)
	end
end

local counter = CreateFrame("Frame")
counter:Hide()
counter:SetScript("OnUpdate", function(self, elapsed)
	local done = true
	for k, target in pairs(goal) do
		local diff = target - shown[k]
		if diff ~= 0 then
			local step = max(MIN_RATE[k], math.abs(diff) / COUNT_TIME) * elapsed
			if step >= math.abs(diff) then
				shown[k] = target
			else
				shown[k] = shown[k] + (diff > 0 and step or -step)
				done = false
			end
		end
	end
	Render()
	if done then self:Hide() end
end)

local function UpdateReadout(w)
	current = w
	goal.temp, goal.wind, goal.hum, goal.pres = w.temp, w.wind, w.humidity, w.pressure
	if shown.temp == nil then
		for k, v in pairs(goal) do shown[k] = v end     -- first reading: no count-up
	else
		counter:Show()
	end
	Render()
end

---------------------------------------------------------------------------
-- Dragging / position persistence (orb)
---------------------------------------------------------------------------
local function MakeMovable(frame, key)
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(self)
		if not db.locked and not skinned and IsShiftKeyDown() then self:StartMoving() end
	end)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relPoint, x, y = self:GetPoint(1)
		db[key] = { point, relPoint, x, y }
	end)
end

local function RestorePosition(frame, key, default)
	frame:ClearAllPoints()
	local p = db[key]
	if p then
		frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
	else
		default(frame)
	end
end

---------------------------------------------------------------------------
-- Refresh
---------------------------------------------------------------------------
local PlaceOrb      -- defined further down, used by Refresh

local function Refresh()
	if not db then return end
	local w = GetWorld()
	if db.showOrb and db.useStock and not skinned then PlaceOrb() end
	if stockArt then stockArt:SetAlpha(0) end
	if stockRing then stockRing:SetAlpha(0) end
	UpdateOrb(w)
	UpdateReadout(w)
	local owner = GameTooltip:GetOwner()
	if owner and (owner == orb or (skinned and owner == skinned) or owner:GetParent() == readout) and GameTooltip:IsShown() then
		ShowTooltip(owner, owner:GetParent() ~= readout and "ANCHOR_BOTTOMLEFT" or nil)
	end
end

local function ApplyHidden()
	for name in pairs(db.hide) do
		local f = _G[name]
		if type(f) == "table" and f.Hide then
			f:Hide()
			if f.HookScript and not f.__immerseMeHooked then
				f.__immerseMeHooked = true
				f:HookScript("OnShow", function(self) if db.hide[name] then self:Hide() end end)
			end
		end
	end
end

-- Take over the stock day/night indicator. On this client it is an unnamed
-- frame in MinimapCluster holding two atlas textures: the sun/moon art
-- (UI-HUD-Minimap-DayCycle / NightCycle) and its gold ring (...-Frame-Cycle).
-- We hide both and draw our sky inside a copy of the same ring, so the
-- result sits exactly where the stock icon was and looks native.
-- If the icon isn't found, the orb stands on its own next to the minimap.
local stockAlpha = {}   -- region -> original alpha, so we can give the art back

local function PathOf(f, depth)
	depth = depth or 0
	if type(f) ~= "table" or depth > 4 then return nil end
	local name = f.GetName and f:GetName()
	if name and not name:find("%.") and _G[name] == f then return name end
	local parent = f.GetParent and f:GetParent()
	local ppath = parent and PathOf(parent, depth + 1)
	if not ppath then return nil end
	for k, v in pairs(parent) do
		if v == f and type(k) == "string" and k:match("^[%a_][%w_]*$") then return ppath .. "." .. k end
	end
end

local function AtlasOf(region)
	return region.GetAtlas and region:GetAtlas() or nil
end

-- Returns the day/night frame, its art texture and its ring texture.
local function FindStock()
	local function search(frame, depth)
		if depth > 5 or frame == orb or frame == readout then return nil end
		local art, ring
		for _, region in ipairs({ frame:GetRegions() }) do
			local atlas = region:GetObjectType() == "Texture" and AtlasOf(region)
			if atlas and atlas:find("Cycle") then
				if atlas:find("Frame") then ring = region else art = region end
			end
		end
		if art then return frame, art, ring end
		for _, child in ipairs({ frame:GetChildren() }) do
			local f, a, r = search(child, depth + 1)
			if f then return f, a, r end
		end
	end
	if MinimapCluster then
		local f, a, r = search(MinimapCluster, 0)
		if f then return f, a, r end
	end
	return search(Minimap, 0)
end

local function Hide0(region)
	if not region then return end
	if stockAlpha[region] == nil then stockAlpha[region] = region:GetAlpha() end
	region:SetAlpha(0)
end

local function Unskin()
	if not skinned then return end
	for region, a in pairs(stockAlpha) do region:SetAlpha(a) end
	wipe(stockAlpha)
	skinned, stockArt, stockRing = nil, nil, nil
	orb:SetParent(Minimap)
	orb:SetSize(31, 31)
	orb:SetFrameStrata("MEDIUM")
	orb:SetFrameLevel(Minimap:GetFrameLevel() + 10)
	orb.window:ClearAllPoints()
	orb.window:SetSize(ORB_ICON, ORB_ICON)
	orb.window:SetPoint("CENTER")
	orb.border:SetTexCoord(0, 1, 0, 1)
	orb.border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	orb.border:ClearAllPoints()
	orb.border:SetSize(50, 50)
	orb.border:SetPoint("TOPLEFT")
end

local function Skin(f, art, ring)
	if skinned ~= f then Unskin() end
	skinned, stockArt, stockRing = f, art, ring
	Hide0(art)
	Hide0(ring)
	orb:SetParent(f)
	orb:ClearAllPoints()
	orb:SetAllPoints(f)
	orb:SetFrameStrata(f:GetFrameStrata())
	orb:SetFrameLevel(f:GetFrameLevel() + 2)
	-- the sky fills the space the stock art used, slightly inset so the ring covers its edge
	local aw = art:GetWidth() or 21
	orb.window:ClearAllPoints()
	orb.window:SetSize(aw * 0.92, aw * 0.92)
	orb.window:SetPoint("CENTER", art, "CENTER")
	local ringAtlas = ring and AtlasOf(ring)
	orb.border:ClearAllPoints()
	if ringAtlas then
		orb.border:SetAtlas(ringAtlas)
		orb.border:SetSize(ring:GetWidth(), ring:GetHeight())
		orb.border:SetPoint("CENTER", ring, "CENTER")
	else
		orb.border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
		orb.border:SetTexCoord(0, 0.6, 0, 0.6)
		orb.border:SetSize(aw * 1.45, aw * 1.45)
		orb.border:SetPoint("CENTER", orb.window, "CENTER")
	end
end

function PlaceOrb()
	local f, art, ring
	if db.showOrb and db.useStock then f, art, ring = FindStock() end
	if f then
		Skin(f, art, ring)
	else
		Unskin()
		RestorePosition(orb, "orbPos", DefaultOrbPosition)
	end
	orb:SetShown(db.showOrb)
end

local lastError
local function SafeRefresh()
	local ok, err = pcall(Refresh)
	if not ok and err ~= lastError then
		lastError = err
		print("|cffd8b25aImmerseMe: Weather|r |cffff6060error:|r " .. tostring(err))
	end
end

local function ApplySettings()
	PlaceOrb()
	readout:SetShown(db.showReadout)
	LayoutReadout()
	ApplyHidden()
	SafeRefresh()
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("ZONE_CHANGED")
events:RegisterEvent("ZONE_CHANGED_INDOORS")
events:RegisterEvent("ZONE_CHANGED_NEW_AREA")
events:RegisterEvent("PLAYER_UPDATE_RESTING")
events:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
events:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 ~= ADDON then return end
		ImmerseMeWeatherDB = ImmerseMeWeatherDB or {}
		db = ImmerseMeWeatherDB
		for k, v in pairs(DEFAULTS) do
			if db[k] == nil then db[k] = v end
		end
		db.stockFrame = nil   -- test builds stored a frame picked by mouse
		MakeMovable(orb, "orbPos")
		Minimap:HookScript("OnSizeChanged", function() if db then LayoutReadout() end end)
		ApplySettings()
		C_Timer.NewTicker(5, SafeRefresh)
		-- walking through a door doesn't always fire an event: watch for it twice a second
		local wasIndoors, wasResting, wasNear
		C_Timer.NewTicker(0.5, function()
			local indoors = IsIndoors and IsIndoors() or false
			local resting = IsResting and IsResting() or false
			if indoors ~= wasIndoors or resting ~= wasResting then
				wasIndoors, wasResting = indoors, resting
				SafeRefresh()
			end
			local near = NearestSpot(SPOT_RANGE)
			local nearKind = near and near[4] or false
			if nearKind ~= wasNear then
				wasNear = nearKind
				SafeRefresh()
			end
			if LeftFire() then
				fire = nil
				print("|cffd8b25aImmerseMe: Weather|r You step away from the warmth.")
				SafeRefresh()
			end
		end)
	elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
		-- cooking needs a fire and smelting needs a forge: a successful craft proves one is right here
		if arg1 ~= "player" or not db then return end
		local open = TradeSkillFrame and TradeSkillFrame:IsShown()
		local kind = open and GetTradeSkillLine and LEARN_FROM[(GetTradeSkillLine())]
		if kind and RememberSpot(kind) then
			print("|cffd8b25aImmerseMe: Weather|r You'll remember the warmth of this "
				.. (kind == "forge" and "forge." or "fire."))
			SafeRefresh()
		end
	elseif db then
		if event == "PLAYER_ENTERING_WORLD" then ApplyHidden(); PlaceOrb(); LayoutReadout() end
		SafeRefresh()
	end
end)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
local function Print(msg) print("|cffd8b25aImmerseMe: Weather|r " .. msg) end

local function Report(w)
	return ("%s in %s. %s, %s, %s, humidity %d%%."):format(
		w.phase, w.zone, w.label, FormatTemp(w.temp),
		(w.indoor or w.sheltered or w.wind < 2) and WindText(w):lower()
			or ("%s from the %s"):format(w.windName:lower(), w.windDir),
		w.humidity)
end

local HELP = {
	"/imw - print the current conditions",
	"/imw emote - share the conditions as an emote",
	"/imw c | f - Celsius / Fahrenheit",
	"/imw kmh | mph - wind unit",
	"/imw time realm | local - which clock drives day and night",
	"/imw readout | orb - show or hide the minimap readout / sky orb",
	"/imw icon - toggle the warm / cold badge next to the temperature",
	"/imw arc high | middle | low - where the readout sits on the minimap edge",
	"/imw gap <0-40> - distance between the readout and the minimap",
	"/imw y <-60-60> - nudge the readout up (+) or down (-)",
	"/imw font <8-18> - readout text size",
	"/imw stock on | off - draw the sky on the stock day/night icon (on), or give the orb its own spot (off)",
	"/imw fire | forge - you're standing by a fire or a forge; it's remembered, so next time it's automatic",
	"/imw forget - forget the remembered fire where you stand",
	"/imw spots - list the fires you've discovered (to share them)",
	"/imw lock | unlock - Shift-drag moves the orb while unlocked (when it has its own spot)",
	"/imw hide <FrameName> | unhide <FrameName> - hide a stock frame (find its name with /fstack)",
	"/imw reset - restore default layout",
}

SLASH_IMMERSEMEWEATHER1 = "/imw"
SLASH_IMMERSEMEWEATHER2 = "/weather"
SlashCmdList.IMMERSEMEWEATHER = function(input)
	local cmd, arg = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
	cmd = cmd:lower()

	if cmd == "" then
		Print(Report(GetWorld()))
		return
	elseif cmd == "help" or cmd == "?" then
		for _, line in ipairs(HELP) do Print(line) end
		return
	elseif cmd == "debug" then
		local function desc(f)
			if type(f) ~= "table" or not f.GetObjectType then return "missing" end
			local x, y = f:GetCenter()
			return ("%s shown=%s visible=%s strata=%s level=%s at=%s,%s size=%dx%d"):format(
				f:GetName() or "?", tostring(f:IsShown()), tostring(f:IsVisible()), f:GetFrameStrata(), f:GetFrameLevel(),
				x and floor(x) or "-", y and floor(y) or "-", floor(f:GetWidth()), floor(f:GetHeight()))
		end
		Print("client " .. tostring((select(4, GetBuildInfo()))) .. ", orb: " .. desc(orb))
		local ww, wh = orb.window:GetSize()
		Print(("window %.1fx%.1f visible=%s, last error: %s"):format(ww, wh, tostring(orb.window:IsVisible()), tostring(lastError)))
		for _, key in ipairs({ "sky", "horizon", "stars", "base", "wx" }) do
			local t = orb[key]
			local r, g, b = t:GetVertexColor()
			local tw, th = t:GetSize()
			Print(("  %s tex=%s shown=%s alpha=%.2f color=%.2f,%.2f,%.2f size=%.1fx%.1f"):format(key, tostring(t:GetTexture()),
				tostring(t:IsShown()), t:GetAlpha(), r or -1, g or -1, b or -1, tw or -1, th or -1))
		end
		Print("stock icon: " .. (skinned and (PathOf(skinned) or "found") or "not found") .. ", art atlas " .. tostring(stockArt and AtlasOf(stockArt)))
		-- every visible frame or texture on the minimap ring's upper-right,
		-- where the stock day/night icon sits (screen pixels, so scales don't matter)
		local function screen(obj)
			local x, y = obj:GetCenter()
			if not x then return nil end
			local s = obj.GetEffectiveScale and obj:GetEffectiveScale() or 1
			return x * s, y * s, (obj:GetWidth() or 0) * s
		end
		local mx, my, mw = screen(Minimap)
		local R = mw / 2
		local seen, found = {}, 0
		local function check(obj, label)
			if seen[obj] or found >= 20 or obj == orb or obj == orb.window then return end
			seen[obj] = true
			if obj.IsVisible and not obj:IsVisible() then return end
			local x, y, w = screen(obj)
			if not x then return end
			local dx, dy = x - mx, y - my
			local r = sqrt(dx * dx + dy * dy)
			if dx > 0 and dy > 0 and r > R * 0.75 and r < R * 1.6 and w > 8 and w < R then
				found = found + 1
				local tex = obj.GetTexture and obj:GetTexture()
				local atlas = obj.GetAtlas and obj:GetAtlas()
				Print(("ring: %s [%s] %dpx tex=%s%s mouse=%s"):format(PathOf(obj) or label, obj:GetObjectType(),
					floor(w), tostring(tex), atlas and (" atlas=" .. atlas) or "",
					tostring(obj.IsMouseEnabled and obj:IsMouseEnabled() or false)))
			end
		end
		local function scan(frame, path, depth)
			if depth > 4 or frame == orb or frame == readout then return end
			check(frame, path)
			for i, region in ipairs({ frame:GetRegions() }) do
				if region:GetObjectType() == "Texture" then check(region, path .. ":tex" .. i) end
			end
			for i, child in ipairs({ frame:GetChildren() }) do
				scan(child, (PathOf(child) or (path .. ":child" .. i)), depth + 1)
			end
		end
		if MinimapCluster then scan(MinimapCluster, "MinimapCluster", 0) end
		scan(Minimap, "Minimap", 0)
		if found == 0 then Print("ring: nothing found on the upper-right of the minimap ring") end
		local foci = GetMouseFoci and GetMouseFoci() or { GetMouseFocus and GetMouseFocus() }
		Print("under mouse: " .. desc(foci and foci[1]))
		return
	elseif cmd == "emote" then
		local w = GetWorld()
		local text = ("reads the sky: %s, %s, %s."):format(w.label:lower(), FormatTemp(w.temp),
			(w.indoor or w.sheltered or w.wind < 2) and WindText(w):lower()
				or ("%s from the %s"):format(w.windName:lower(), w.windDir))
		local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
		send(text, "EMOTE")
		return
	elseif cmd == "c" then db.fahrenheit = false
	elseif cmd == "f" then db.fahrenheit = true
	elseif cmd == "kmh" then db.mph = false
	elseif cmd == "mph" then db.mph = true
	elseif cmd == "time" then
		db.localTime = (arg:lower() == "local")
		Print("Day and night now follow " .. (db.localTime and "your local clock." or "realm time."))
	elseif cmd == "readout" or cmd == "panel" then db.showReadout = not db.showReadout
	elseif cmd == "orb" then db.showOrb = not db.showOrb
	elseif cmd == "icon" then db.tempIcon = not db.tempIcon
	elseif cmd == "arc" then
		arg = arg:lower()
		if arg ~= "high" and arg ~= "middle" and arg ~= "low" then Print("Usage: /imw arc high | middle | low") return end
		db.arc = arg
	elseif cmd == "gap" or cmd == "font" or cmd == "y" then
		local v = tonumber(arg)
		if not v then Print("Usage: /imw " .. cmd .. " <number>") return end
		if cmd == "gap" then db.gap = max(0, min(40, v))
		elseif cmd == "y" then db.yOffset = max(-60, min(60, floor(v)))
		else db.fontSize = max(8, min(18, floor(v))) end
	elseif cmd == "stock" then
		arg = arg:lower()
		if arg == "on" then db.useStock = true
		elseif arg == "off" then db.useStock = false
		else db.useStock = not db.useStock end
		Print(db.useStock and "The sky is drawn on the stock day/night icon."
			or "The orb now has its own spot; the stock day/night icon is back. Shift-drag moves it.")
	elseif cmd == "fire" or cmd == "forge" then
		local kind = cmd == "forge" and "forge" or "hearth"
		if fire and fire.kind == kind then
			fire = nil
			Print("You step away from the warmth.")
		else
			local x, y, map = PlayerPos()
			fire = { kind = kind, x = x, y = y, map = map, expires = GetTime() + FIRE_MINUTES * 60 }
			Print(kind == "forge" and "You stand in the heat of the forge. Walk away to leave it."
				or "You warm yourself by the fire. Walk away to leave it.")
			if RememberSpot(kind) then
				Print("Remembered: you'll feel it here automatically from now on (/imw forget to undo).")
			end
		end
	elseif cmd == "forget" then
		local x, y, map = PlayerPos()
		local n = 0
		for i = #db.spots, 1, -1 do
			local s = db.spots[i]
			if x and s[3] == map and (x - s[1]) ^ 2 + (y - s[2]) ^ 2 <= SPOT_RANGE * SPOT_RANGE then
				table.remove(db.spots, i)
				n = n + 1
			end
		end
		fire = nil
		Print(n > 0 and ("Forgot %d fire%s here."):format(n, n == 1 and "" or "s") or "No remembered fire here.")
	elseif cmd == "spots" then
		Print(("You have discovered %d fires and forges. As lines for ns.FireSpots in Data.lua:"):format(#db.spots))
		for _, s in ipairs(db.spots) do
			print(("{ %.1f, %.1f, %d, \"%s\" },"):format(s[1], s[2], s[3], s[4]))
		end
		return
	elseif cmd == "lock" then db.locked = true; Print("Locked.")
	elseif cmd == "unlock" then db.locked = false; Print("Unlocked. Shift-drag the orb to move it.")
	elseif cmd == "hide" or cmd == "unhide" then
		if arg == "" then Print("Usage: /imw " .. cmd .. " FrameName  (hover the frame with /fstack to find its name)") return end
		if cmd == "hide" then
			if type(_G[arg]) ~= "table" then Print("No frame named '" .. arg .. "' exists.") return end
			db.hide[arg] = true
			Print("Hiding " .. arg .. ".")
		else
			db.hide[arg] = nil
			if type(_G[arg]) == "table" and _G[arg].Show then _G[arg]:Show() end
			Print("No longer hiding " .. arg .. ".")
		end
	elseif cmd == "reset" then
		db.orbPos, db.gap, db.fontSize, db.arc, db.yOffset = nil, DEFAULTS.gap, DEFAULTS.fontSize, DEFAULTS.arc, 0
		Print("Layout reset.")
	else
		Print("Unknown command. Try /imw help")
		return
	end
	ApplySettings()
end
