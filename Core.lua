local ADDON, ns = ...

local defaults = {
	bar = { scale = 1, locked = false, default = { "TOP", "TOP", 0, -8 } },
	width = 420,
	height = 14,
	text = "full",
	xp = true,
	rep = true,
	autoRep = true,
	toast = true,
	hideBlizzard = false,
}

ACore.New(ADDON, ns, { db = "AXPDB", defaults = defaults })

ACore.Register({
	name = "AXP",
	title = "AXP",
	slash = "/axp",
	desc = "experience and reputation bars",
	toggle = function() ns.Bars.Menu() end,
})

function ns.Time(seconds)
	if not seconds or seconds ~= seconds or seconds == math.huge or seconds < 0 then return "-" end
	seconds = math.floor(seconds)
	local h = math.floor(seconds / 3600)
	local m = math.floor(seconds / 60) % 60
	if h >= 100 then return math.floor(h / 24) .. "d" end
	if h > 0 then return h .. "h " .. m .. "m" end
	if m > 0 then return m .. "m" end
	return seconds .. "s"
end

function ns.Options()
	local UI = ns.UI
	local db = ns.db
	local function changed() ns:Fire("OPTIONS") end
	local entries = {
		{ text = "Bars", title = true },
		UI.Check(db, "xp", "Experience bar", changed),
		UI.Check(db, "rep", "Reputation bar", changed),
		UI.Check(db, "autoRep", "Follow the faction I last gained reputation with"),
		UI.Check(db, "toast", "Level up message", changed),
		UI.Check(db, "hideBlizzard", "Hide the default bars", changed),
		UI.Check(db.bar, "locked", "Lock position"),
		{ text = "Reset session", func = function() ns.Track.Reset() end },
		{ text = "Text", title = true },
	}
	for _, t in ipairs({ { "full", "Values and rates" }, { "percent", "Percent only" }, { "none", "No text" } }) do
		entries[#entries + 1] = {
			text = t[2], checked = db.text == t[1],
			func = function()
				db.text = t[1]
				changed()
			end,
		}
	end
	entries[#entries + 1] = { text = "Width", title = true }
	for _, w in ipairs({ 260, 340, 420, 520, 640 }) do
		entries[#entries + 1] = {
			text = tostring(w), checked = db.width == w,
			func = function()
				db.width = w
				changed()
			end,
		}
	end
	entries[#entries + 1] = { text = "Height", title = true }
	for _, h in ipairs({ 8, 11, 14, 18, 22 }) do
		entries[#entries + 1] = {
			text = tostring(h), checked = db.height == h,
			func = function()
				db.height = h
				changed()
			end,
		}
	end
	for _, e in ipairs(UI.ScaleEntries(db.bar, changed)) do entries[#entries + 1] = e end
	return entries
end

SLASH_AXP1 = "/axp"
SlashCmdList["AXP"] = function(msg)
	local cmd = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	if cmd == "" then
		ns.Bars.Menu()
	elseif cmd == "lock" or cmd == "unlock" then
		ns.db.bar.locked = cmd == "lock"
		ns.Print(cmd == "lock" and "Locked" or "Unlocked, drag the bar to move it")
	elseif cmd == "reset" then
		ns.db.bar.pos = nil
		ns.db.bar.scale = 1
		ns:Fire("LAYOUT_RESET")
	elseif cmd == "session" then
		ns.Track.Reset()
		ns.Print("Session reset")
	elseif cmd == "report" then
		for _, line in ipairs(ns.Track.Summary()) do ns.Print(line[1] .. ": " .. line[2]) end
	else
		ns.Print("/axp, /axp lock, /axp unlock, /axp reset, /axp session, /axp report")
	end
end
