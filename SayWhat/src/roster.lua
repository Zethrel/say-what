-------------------------------------------------------------------------------
-- SayWhat - the nearby roster.
--
-- Who did we hear in say range, when, and which of them is the Nearby window
-- allowed to show?
--
-- The roster lives in the per-character saved variables, so it survives a
-- reload or a relog. The selection lives beside it and is deliberately never
-- pruned: if you picked someone last week, they stay picked.
-------------------------------------------------------------------------------

local ADDON_NAME, Me = ...

Me.Roster = {}
local Roster = Me.Roster

-------------------------------------------------------------------------------
-- Class of a player from their guid, for name coloring. Returns nil when the
-- guid is missing, secret, or not a player.
--
local function ClassFromGUID( guid )
	if not guid or Me.IsSecret( guid ) then return nil end
	if not GetPlayerInfoByGUID then return nil end

	local ok, _, class = pcall( GetPlayerInfoByGUID, guid )
	if ok and class and class ~= "" and not Me.IsSecret( class ) then
		return class
	end
	return nil
end

-------------------------------------------------------------------------------
-- Note that we heard this player in range, right now.
--
-- @param full  Canonical "Name-Realm".
-- @param guid  Sender guid, if the event gave us one.
-- @param when  Unix time of the message.
--
function Roster.Record( full, guid, when )
	local roster = Me.chardb.roster
	local entry  = roster[full]

	if not entry then
		entry = { count = 0 }
		roster[full] = entry

		if Me.db.settings.announce_new then
			Me.Print( "%s is nearby. %s", Me.ColorName( full ),
			          Me.Links.Toggle( full ) )
		end
	end

	entry.last  = when
	entry.count = (entry.count or 0) + 1
	entry.class = ClassFromGUID( guid ) or entry.class

	if GetRealZoneText then
		local zone = GetRealZoneText()
		if zone and zone ~= "" then entry.zone = zone end
	end

	if Me.Window then Me.Window.UpdateTitle() end
end

-------------------------------------------------------------------------------
-- Is this player still counted as in range, i.e. did we hear them recently
-- enough?
--
function Roster.IsNearby( full, now )
	local entry = Me.chardb.roster[full]
	if not entry or not entry.last then return false end
	return (now or time()) - entry.last <= Me.db.settings.nearby_timeout
end

-------------------------------------------------------------------------------
-- Every player the addon knows about: heard recently, or selected (even if
-- they've long since wandered off).
--
-- @returns a table keyed by full name.
--
function Roster.Known()
	local known = {}
	for name in pairs( Me.chardb.roster ) do known[name] = true end
	for name in pairs( Me.chardb.selected ) do known[name] = true end
	return known
end

-------------------------------------------------------------------------------
-- The roster as a sorted array, most recently heard first, for the menu and
-- the list command.
--
-- Each item: { name, last, count, class, zone, selected, nearby }
--
function Roster.List()
	local now  = time()
	local list = {}

	for name in pairs( Roster.Known() ) do
		local entry = Me.chardb.roster[name] or {}
		table.insert( list, {
			name     = name;
			last     = entry.last or 0;
			count    = entry.count or 0;
			class    = entry.class;
			zone     = entry.zone;
			selected = Me.IsSelected( name );
			nearby   = Roster.IsNearby( name, now );
		})
	end

	table.sort( list, function( a, b )
		if a.last ~= b.last then return a.last > b.last end
		return a.name < b.name
	end)

	return list
end

-------------------------------------------------------------------------------
-- Number of players currently in range.
--
function Roster.NearbyCount()
	local now, count = time(), 0
	for name in pairs( Me.chardb.roster ) do
		if Roster.IsNearby( name, now ) then count = count + 1 end
	end
	return count
end

-------------------------------------------------------------------------------
-- Forget players we haven't heard from in roster_expiry seconds. Selected
-- players are kept, since dropping them would silently change the filter.
--
function Roster.Prune()
	local now    = time()
	local expiry = Me.db.settings.roster_expiry
	local roster = Me.chardb.roster

	for name, entry in pairs( roster ) do
		local last = entry.last or 0
		if now - last > expiry and not Me.IsSelected( name ) then
			roster[name] = nil
		end
	end
end

-------------------------------------------------------------------------------
-- Forget every player you haven't selected. Selected players keep their entry
-- so the window filter and the menu stay intact.
--
-- @returns how many were forgotten.
--
function Roster.Clear()
	local kept, forgotten = {}, 0

	for name, entry in pairs( Me.chardb.roster ) do
		if Me.IsSelected( name ) then
			kept[name] = entry
		else
			forgotten = forgotten + 1
		end
	end

	Me.chardb.roster = kept
	if Me.Window then Me.Window.UpdateTitle() end
	return forgotten
end

-------------------------------------------------------------------------------
-- Selection
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
function Me.IsSelected( full )
	return full ~= nil and Me.chardb.selected[full] == true
end

-------------------------------------------------------------------------------
-- @param state true to show this player in the Nearby window, false to stop.
-- @returns true if anything actually changed.
--
function Me.SetSelected( full, state )
	if not full then return false end

	local current = Me.IsSelected( full )
	if current == state then return false end

	Me.chardb.selected[full] = state and true or nil

	if Me.Window then Me.Window.Refresh() end
	return true
end

-------------------------------------------------------------------------------
function Me.ToggleSelected( full )
	local state = not Me.IsSelected( full )
	Me.SetSelected( full, state )
	return state
end

-------------------------------------------------------------------------------
-- Select everyone currently in range. Returns how many were added.
--
function Me.SelectAllNearby()
	local now, added = time(), 0
	for name in pairs( Me.chardb.roster ) do
		if Roster.IsNearby( name, now ) and Me.SetSelected( name, true ) then
			added = added + 1
		end
	end
	return added
end

-------------------------------------------------------------------------------
-- Deselect everyone. Returns how many were removed.
--
function Me.ClearSelection()
	local removed = 0
	for name in pairs( Me.chardb.selected ) do
		Me.chardb.selected[name] = nil
		removed = removed + 1
	end

	if removed > 0 and Me.Window then Me.Window.Refresh() end
	return removed
end

-------------------------------------------------------------------------------
function Me.SelectedCount()
	local count = 0
	for _ in pairs( Me.chardb.selected ) do count = count + 1 end
	return count
end

-------------------------------------------------------------------------------
-- Class colored display name.
--
function Me.ColorName( full )
	local name = Me.DisplayName( full )

	-- A roleplay profile can carry its own name color. Opt-in, since class
	-- colors tell you something and custom ones can be hard to read.
	if Me.db.settings.rp_names and Me.db.settings.rp_colors then
		local _, rp_color = Me.RPNames.Get( full )
		if rp_color then
			return "|c" .. rp_color .. name .. "|r"
		end
	end

	local entry = Me.chardb and Me.chardb.roster and Me.chardb.roster[full]
	local class = entry and entry.class

	local colors = _G.RAID_CLASS_COLORS
	if class and colors and colors[class] then
		local c = colors[class]
		local hex = c.colorStr
		if not hex then
			hex = string.format( "ff%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255 )
		end
		return "|c" .. hex .. name .. "|r"
	end

	return name
end
