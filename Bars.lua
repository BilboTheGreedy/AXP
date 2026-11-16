local _, ns = ...
local UI = ns.UI
local C = UI.colors
local Track = ns.Track

local Bars = {}
ns.Bars = Bars

local frame, toast

local STANDING = { "Hated", "Hostile", "Unfriendly", "Neutral", "Friendly", "Honored", "Revered", "Exalted" }
local REPCOLOR = {
	{ 0.8, 0.13, 0.13 }, { 0.8, 0.13, 0.13 }, { 0.75, 0.27, 0 }, { 0.9, 0.7, 0 },
	{ 0, 0.6, 0.1 }, { 0, 0.6, 0.1 }, { 0, 0.6, 0.45 }, { 0, 0.7, 0.7 },
}

local function tooltip(self)
	GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
	GameTooltip:AddLine("AXP", C.accent[1], C.accent[2], C.accent[3])
	local e = Track.Estimate()
	local info = e.info
	if info.known and not info.capped then
		GameTooltip:AddDoubleLine("Level " .. (info.level or "?"), ACore.Short(info.xp) .. " / " .. ACore.Short(info.max), 1, 1, 1, 1, 1, 1)
		GameTooltip:AddDoubleLine("To next level", ACore.Short(e.left) .. "  (" .. ns.Time(e.seconds) .. ")", 0.9, 0.9, 0.92, 0.9, 0.9, 0.92)
		if info.rested > 0 then
			GameTooltip:AddDoubleLine("Rested", ACore.Short(info.rested) .. "  (" .. math.floor(info.rested / info.max * 100 + 0.5) .. "%)", 0.35, 0.65, 1, 0.35, 0.65, 1)
		end
		if e.kills then GameTooltip:AddDoubleLine("Kills to level", tostring(e.kills), 0.9, 0.9, 0.92, 0.9, 0.9, 0.92) end
		if e.quests then GameTooltip:AddDoubleLine("Quests to level", "about " .. e.quests, 0.9, 0.9, 0.92, 0.9, 0.9, 0.92) end
	end
	local rep = Track.Rep()
	if rep then
		GameTooltip:AddLine(" ")
		GameTooltip:AddDoubleLine(rep.name, STANDING[rep.standing] or "", 1, 1, 1, 1, 1, 1)
		GameTooltip:AddDoubleLine("Progress", (rep.value - rep.lo) .. " / " .. (rep.hi - rep.lo), 0.9, 0.9, 0.92, 0.9, 0.9, 0.92)
		if rep.rate > 0 then
			GameTooltip:AddDoubleLine("Per hour", ACore.Short(rep.rate) .. "  (" .. ns.Time(rep.seconds) .. " to go)", 0.9, 0.9, 0.92, 0.9, 0.9, 0.92)
		end
	end
	GameTooltip:AddLine(" ")
	for _, line in ipairs(Track.Summary()) do
		GameTooltip:AddDoubleLine(line[1], line[2], 0.58, 0.6, 0.65, 0.9, 0.9, 0.92)
	end
	GameTooltip:AddLine("Right-click for options, drag to move", 0.58, 0.6, 0.65)
	GameTooltip:Show()
end

local function makeBar(parent)
	local bar = UI.Bar(parent, 14)
	UI.Border(bar)
	bar.rested = bar:CreateTexture(nil, "ARTWORK")
	bar.rested:SetColorTexture(0.35, 0.65, 1, 0.35)
	bar.rested:Hide()
	bar:EnableMouse(true)
	bar:RegisterForDrag("LeftButton")
	bar:SetScript("OnDragStart", function() frame:StartDrag() end)
	bar:SetScript("OnDragStop", function() frame:StopDrag() end)
	bar:SetScript("OnEnter", tooltip)
	bar:SetScript("OnLeave", function() GameTooltip:Hide() end)
	bar:SetScript("OnMouseUp", function(self, button)
		if button == "RightButton" then Bars.Menu(self) end
	end)
	return bar
end

local function build()
	frame = CreateFrame("Frame", "AXPFrame", UIParent)
	frame:SetFrameStrata("LOW")
	frame:SetSize(ns.db.width, ns.db.height)
	UI.Movable(frame, ns.db.bar)
	frame.xp = makeBar(frame)
	frame.rep = makeBar(frame)
end

local function font(bar, height)
	local name = height >= 14 and "GameFontHighlightSmall" or "GameFontHighlightExtraSmall"
	if bar.fontName == name then return end
	bar.fontName = name
	local obj = _G[name] or GameFontHighlightSmall
	if obj and bar.left.SetFontObject then
		bar.left:SetFontObject(obj)
		bar.right:SetFontObject(obj)
	end
end

local function updateXP(bar, width)
	local e = Track.Estimate()
	local info = e.info
	local mode = ns.db.text
	if not info.known then
		if info.raw ~= nil and info.rawMax ~= nil then
			pcall(bar.SetMinMaxValues, bar, 0, info.rawMax)
			pcall(bar.SetValue, bar, info.raw)
		end
		bar.rested:Hide()
		bar.left:SetText(mode == "none" and "" or ("Level " .. (info.level or "")))
		bar.right:SetText("")
		return
	end
	bar:SetMinMaxValues(0, info.max)
	bar:SetValue(info.xp)
	local resting = info.rested > 0
	if resting then
		bar:SetColor(0.2, 0.45, 0.9, 0.9)
	else
		bar:SetColor(0.58, 0.25, 0.75, 0.9)
	end
	if resting and info.xp < info.max then
		local from = info.xp / info.max * width
		local to = math.min(info.xp + info.rested, info.max) / info.max * width
		bar.rested:ClearAllPoints()
		bar.rested:SetPoint("TOPLEFT", bar, "TOPLEFT", from, 0)
		bar.rested:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", from, 0)
		bar.rested:SetWidth(math.max(1, to - from))
		bar.rested:Show()
	else
		bar.rested:Hide()
	end
	local pct = math.floor(info.xp / info.max * 1000 + 0.5) / 10
	if mode == "none" then
		bar.left:SetText("")
		bar.right:SetText("")
	elseif mode == "percent" then
		bar.left:SetText("Level " .. info.level)
		bar.right:SetText(pct .. "%")
	else
		bar.left:SetText("Level " .. info.level .. "   " .. ACore.Short(info.xp) .. " / " .. ACore.Short(info.max) .. "   " .. pct .. "%")
		if e.rate > 0 then
			bar.right:SetText(ACore.Short(e.rate) .. "/h   " .. ns.Time(e.seconds))
		elseif resting then
			bar.right:SetText("rested " .. math.floor(info.rested / info.max * 100 + 0.5) .. "%")
		else
			bar.right:SetText("")
		end
	end
end

local function updateRep(bar, rep)
	local span = rep.hi - rep.lo
	local c = REPCOLOR[rep.standing] or REPCOLOR[4]
	bar:SetColor(c[1], c[2], c[3], 0.9)
	if span <= 0 then
		bar:SetMinMaxValues(0, 1)
		bar:SetValue(1)
	else
		bar:SetMinMaxValues(0, span)
		bar:SetValue(rep.value - rep.lo)
	end
	local mode = ns.db.text
	local standing = STANDING[rep.standing] or ""
	if mode == "none" then
		bar.left:SetText("")
		bar.right:SetText("")
	elseif mode == "percent" then
		bar.left:SetText(rep.name)
		bar.right:SetText(span > 0 and (math.floor((rep.value - rep.lo) / span * 1000 + 0.5) / 10 .. "%") or standing)
	else
		bar.left:SetText(rep.name .. "   " .. standing .. (span > 0 and ("   " .. (rep.value - rep.lo) .. " / " .. span) or ""))
		bar.right:SetText(rep.rate > 0 and (ACore.Short(rep.rate) .. "/h   " .. ns.Time(rep.seconds)) or "")
	end
end

local BLIZZARD = { "MainMenuExpBar", "ReputationWatchBar", "MainStatusTrackingBarContainer", "StatusTrackingBarManager" }
local hidden = false

local function blizzard()
	local want = ns.db.hideBlizzard and true or false
	if want == hidden then return end
	hidden = want
	for _, name in ipairs(BLIZZARD) do
		local f = _G[name]
		if f and f.SetAlpha then
			pcall(f.SetAlpha, f, want and 0 or 1)
			if f.EnableMouse then pcall(f.EnableMouse, f, not want) end
		end
	end
end

function Bars.Refresh()
	if not ns.db then return end
	if not frame then build() end
	blizzard()
	local db = ns.db
	local info = Track.XP()
	local rep = db.rep and Track.Rep() or nil
	local showXP = db.xp and not info.capped
	local y = 0
	for _, bar in ipairs({ frame.xp, frame.rep }) do
		bar:SetHeight(db.height)
		font(bar, db.height)
	end
	if showXP then
		frame.xp:ClearAllPoints()
		frame.xp:SetPoint("TOPLEFT", 0, 0)
		frame.xp:SetPoint("TOPRIGHT", 0, 0)
		updateXP(frame.xp, db.width)
		frame.xp:Show()
		y = y + db.height + 2
	else
		frame.xp:Hide()
	end
	if rep then
		frame.rep:ClearAllPoints()
		frame.rep:SetPoint("TOPLEFT", 0, -y)
		frame.rep:SetPoint("TOPRIGHT", 0, -y)
		updateRep(frame.rep, rep)
		frame.rep:Show()
		y = y + db.height + 2
	else
		frame.rep:Hide()
	end
	frame:SetSize(db.width, math.max(1, y - 2))
	frame:SetShown(y > 0)
end

function Bars.Menu(anchor)
	if not frame then Bars.Refresh() end
	local a = anchor
	if not a then a = (frame and frame:IsShown()) and frame or UIParent end
	UI.Menu(a, ns.Options())
end

local function showToast(level, took, full)
	if not ns.db.toast then return end
	local text = "Level " .. (level or "up") .. " reached"
	local detail = full and ("That level took " .. ns.Time(took)) or ("Played " .. ns.Time(took) .. " this session before the level")
	ns.Print(text .. ". " .. detail)
	if not toast then
		toast = CreateFrame("Frame", "AXPToast", UIParent)
		toast:SetSize(320, 54)
		toast:SetPoint("TOP", 0, -160)
		toast:SetFrameStrata("HIGH")
		UI.Fill(toast, C.bg)
		UI.Border(toast, C.accent)
		toast.title = UI.Text(toast, "GameFontNormalLarge", "CENTER", C.accent)
		toast.title:SetPoint("TOP", 0, -8)
		toast.detail = UI.Text(toast, "GameFontHighlightSmall", "CENTER", C.text)
		toast.detail:SetPoint("BOTTOM", 0, 9)
	end
	toast.title:SetText(text)
	toast.detail:SetText(detail)
	toast:Show()
	toast.shown = (toast.shown or 0) + 1
	local id = toast.shown
	ns.After(6, function()
		if toast.shown == id then toast:Hide() end
	end)
end

ns:Listen("LEVEL", showToast)
ns:Listen("CHANGED", function() ns.Debounce("bars", 0.1, Bars.Refresh) end)
ns:Listen("OPTIONS", function() Bars.Refresh() end)
ns:Listen("LAYOUT_RESET", function()
	if frame then frame:Restore() end
end)
ns:Listen("LOGIN", function()
	Bars.Refresh()
	local ticker = CreateFrame("Frame")
	local elapsed = 0
	ticker:SetScript("OnUpdate", function(_, dt)
		elapsed = elapsed + (dt or 0)
		if elapsed < 5 then return end
		elapsed = 0
		Bars.Refresh()
	end)
end)
