local _, ns = ...

local Track = {}
ns.Track = Track

local function num(v)
	if type(v) ~= "number" or ns.IsSecret(v) then return nil end
	return v
end

local function pass(ok, ...)
	if ok then return ... end
end

local function call(fn, ...)
	if not fn then return nil end
	return pass(pcall(fn, ...))
end

local function now()
	return GetTime and GetTime() or 0
end

local s

local function fresh()
	s = {
		start = now(), xp = 0, levels = 0, kills = 0, killXP = {}, questXP = {},
		earned = 0, spent = 0, reps = {}, levelStart = now(), levelFull = false,
	}
end
fresh()

local lastXP, lastMax, lastMoney
local looseXP, looseAt, killAt, questAt
local standings

function Track.MaxLevel()
	local max = num(call(GetMaxPlayerLevel))
	if not max or max < 1 then max = 60 end
	return max
end

function Track.XP()
	local level = num(call(UnitLevel, "player"))
	local raw, rawMax = call(UnitXP, "player"), call(UnitXPMax, "player")
	local xp, max = num(raw), num(rawMax)
	local rested = num(call(GetXPExhaustion)) or 0
	local info = { level = level, raw = raw, rawMax = rawMax, xp = xp, max = max, rested = rested }
	info.capped = level ~= nil and level >= Track.MaxLevel()
	info.known = xp ~= nil and max ~= nil and max > 0
	return info
end

local function average(list)
	if #list == 0 then return nil end
	local sum = 0
	for _, v in ipairs(list) do sum = sum + v end
	return sum / #list
end

local function push(list, v, keep)
	list[#list + 1] = v
	while #list > keep do table.remove(list, 1) end
end

function Track.Elapsed()
	return math.max(1, now() - s.start)
end

function Track.Rate()
	local elapsed = Track.Elapsed()
	if elapsed < 30 or s.xp <= 0 then return 0 end
	return s.xp / elapsed * 3600
end

function Track.Estimate()
	local info = Track.XP()
	local out = { info = info, rate = Track.Rate() }
	if not info.known then return out end
	out.left = info.max - info.xp
	if out.rate > 0 then out.seconds = out.left / out.rate * 3600 end
	local kill = average(s.killXP)
	if kill and kill > 0 then out.kills = math.ceil(out.left / kill) end
	local quest = average(s.questXP)
	if quest and quest > 0 then out.quests = math.ceil(out.left / quest) end
	return out
end

local function xpChanged()
	local info = Track.XP()
	if not info.known then return end
	if lastXP and lastMax then
		local delta = info.xp - lastXP
		if info.max ~= lastMax or delta < 0 then delta = (lastMax - lastXP) + info.xp end
		if delta > 0 then
			s.xp = s.xp + delta
			local t = now()
			if questAt and t - questAt <= 2 then
				questAt = nil
			elseif killAt and t - killAt <= 2 then
				killAt = nil
				push(s.killXP, delta, 12)
			else
				looseXP, looseAt = delta, t
			end
		end
	end
	lastXP, lastMax = info.xp, info.max
	ns:Fire("CHANGED")
end

local function watched()
	if C_Reputation and C_Reputation.GetWatchedFactionData then
		local d = call(C_Reputation.GetWatchedFactionData)
		if type(d) == "table" and type(d.name) == "string" and d.name ~= "" then
			local value, lo, hi = num(d.currentStanding), num(d.currentReactionThreshold), num(d.nextReactionThreshold)
			if value and lo and hi then
				return { name = d.name, id = d.factionID, standing = num(d.reaction) or 4, value = value, lo = lo, hi = hi }
			end
		end
		return nil
	end
	if GetWatchedFactionInfo then
		local name, standing, lo, hi, value, id = call(GetWatchedFactionInfo)
		if type(name) == "string" and num(value) and num(lo) and num(hi) then
			return { name = name, id = id, standing = num(standing) or 4, value = value, lo = lo, hi = hi }
		end
	end
	return nil
end
Track.Watched = watched

function Track.Rep()
	local w = watched()
	if not w then return nil end
	local r = s.reps[w.name]
	if not r then
		r = { first = w.value, start = now(), gained = 0, last = w.value }
		s.reps[w.name] = r
	end
	if w.value ~= r.last then
		if w.value > r.last then r.gained = r.gained + (w.value - r.last) end
		r.last = w.value
	end
	local elapsed = math.max(1, now() - r.start)
	w.gained = r.gained
	w.rate = (elapsed >= 30 and r.gained > 0) and r.gained / elapsed * 3600 or 0
	w.left = w.hi - w.value
	if w.rate > 0 and w.left > 0 then w.seconds = w.left / w.rate * 3600 end
	return w
end

local function factions()
	local out = {}
	if C_Reputation and C_Reputation.GetNumFactions and C_Reputation.GetFactionDataByIndex then
		for i = 1, num(call(C_Reputation.GetNumFactions)) or 0 do
			local d = call(C_Reputation.GetFactionDataByIndex, i)
			if type(d) == "table" and type(d.name) == "string" and not ns.IsSecret(d.name) and (not d.isHeader or d.isHeaderWithRep) then
				out[#out + 1] = { name = d.name, id = d.factionID, index = i, watched = d.isWatched, value = num(d.currentStanding) }
			end
		end
	elseif GetNumFactions and GetFactionInfo then
		for i = 1, num(call(GetNumFactions)) or 0 do
			local name, _, _, _, _, value, _, _, isHeader, _, hasRep, isWatched, _, id = call(GetFactionInfo, i)
			if type(name) == "string" and not ns.IsSecret(name) and (not isHeader or hasRep) then
				out[#out + 1] = { name = name, id = id, index = i, watched = isWatched, value = num(value) }
			end
		end
	end
	return out
end

local function watch(f)
	if not ns.db or not ns.db.autoRep or f.watched then return end
	if C_Reputation and C_Reputation.SetWatchedFactionByID and f.id then
		pcall(C_Reputation.SetWatchedFactionByID, f.id)
	elseif C_Reputation and C_Reputation.SetWatchedFactionByIndex then
		pcall(C_Reputation.SetWatchedFactionByIndex, f.index)
	elseif SetWatchedFactionIndex then
		pcall(SetWatchedFactionIndex, f.index)
	end
end

local function scanReps(msg)
	local list = factions()
	local best, gain
	if standings then
		for _, f in ipairs(list) do
			local old = standings[f.name]
			if f.value and old and f.value > old then
				local r = s.reps[f.name]
				if not r then
					r = { first = old, start = s.start, gained = 0, last = old }
					s.reps[f.name] = r
				end
				if f.value > r.last then
					r.gained = r.gained + (f.value - r.last)
					r.last = f.value
				end
				if not gain or f.value - old > gain then best, gain = f, f.value - old end
			end
		end
	end
	standings = standings or {}
	for _, f in ipairs(list) do
		if f.value then standings[f.name] = f.value end
	end
	if not best and type(msg) == "string" and not ns.IsSecret(msg) then
		for _, f in ipairs(list) do
			if msg:find(f.name, 1, true) and (not best or #f.name > #best.name) then best = f end
		end
	end
	if best then watch(best) end
end
Track.ScanReps = scanReps

function Track.Share()
	local info = Track.XP()
	local parts = {}
	if info.known and not info.capped then
		parts[#parts + 1] = string.format("Level %s: %s / %s XP (%d%%), %s to go", tostring(info.level or "?"), ACore.Short(info.xp), ACore.Short(info.max),
			math.floor(info.xp / info.max * 100), ACore.Short(info.max - info.xp))
		if info.rested > 0 then parts[#parts + 1] = "rested " .. math.floor(info.rested / info.max * 100 + 0.5) .. "%" end
	end
	local w = watched()
	if w then
		local span = w.hi - w.lo
		parts[#parts + 1] = w.name .. (span > 0 and (": " .. (w.value - w.lo) .. " / " .. span) or "")
	end
	return table.concat(parts, ", ")
end

function Track.Summary()
	local elapsed = Track.Elapsed()
	local hours = elapsed / 3600
	local lines = {
		{ "Session", ns.Time(elapsed) },
		{ "Experience gained", ACore.Short(s.xp) .. (Track.Rate() > 0 and ("  (" .. ACore.Short(Track.Rate()) .. " per hour)") or "") },
		{ "Levels gained", tostring(s.levels) },
		{ "Mobs killed", tostring(s.kills) },
		{ "Gold earned", ACore.Money(s.earned) .. "  (" .. ACore.Money(s.earned / hours) .. " per hour)" },
		{ "Gold spent", ACore.Money(s.spent) },
	}
	return lines
end

function Track.Session()
	return s
end

function Track.Reset()
	fresh()
	local info = Track.XP()
	lastXP, lastMax = info.xp, info.max
	lastMoney = num(call(GetMoney))
	ns:Fire("CHANGED")
end

ns:Listen("LOGIN", function()
	Track.Reset()
	scanReps()
end)

ns:On("PLAYER_XP_UPDATE", xpChanged)
ns:On("UPDATE_EXHAUSTION", function() ns:Fire("CHANGED") end)
ns:On("PLAYER_UPDATE_RESTING", function() ns:Fire("CHANGED") end)
ns:On("PLAYER_ENTERING_WORLD", function() ns:Fire("CHANGED") end)

ns:On("PLAYER_LEVEL_UP", function(level)
	s.levels = s.levels + 1
	local took = now() - s.levelStart
	local full = s.levelFull
	s.levelStart = now()
	s.levelFull = true
	ns.After(0.5, function()
		xpChanged()
		ns:Fire("LEVEL", num(level), took, full)
	end)
end)

ns:On("CHAT_MSG_COMBAT_XP_GAIN", function(msg)
	local t = now()
	if type(msg) ~= "string" or ns.IsSecret(msg) then
		s.kills = s.kills + 1
		if looseXP and t - looseAt <= 2 then
			push(s.killXP, looseXP, 12)
		else
			killAt = t
		end
		looseXP = nil
		ns:Fire("CHANGED")
		return
	end
	local amount = tonumber((msg:gsub("[,%.](%d%d%d)", "%1"):match("(%d+)")))
	if not amount or amount <= 0 then return end
	s.kills = s.kills + 1
	looseXP = nil
	push(s.killXP, amount, 12)
	ns:Fire("CHANGED")
end)

ns:On("QUEST_TURNED_IN", function(_, xp)
	questAt = now()
	looseXP = nil
	xp = num(xp)
	if xp and xp > 0 then push(s.questXP, xp, 6) end
end)

ns:On("PLAYER_MONEY", function()
	local money = num(call(GetMoney))
	if not money then return end
	if lastMoney then
		local delta = money - lastMoney
		if delta > 0 then s.earned = s.earned + delta else s.spent = s.spent - delta end
	end
	lastMoney = money
end)

ns:On("UPDATE_FACTION", function()
	ns.Debounce("reps", 0.2, function()
		scanReps()
		ns:Fire("CHANGED")
	end)
end)
ns:On("CHAT_MSG_COMBAT_FACTION_CHANGE", function(msg)
	scanReps(msg)
	ns:Fire("CHANGED")
end)
