-------------------------------------------------------------------------------
-- SayWhat - roleplay names.
--
-- Reads the roleplay name a player has set in their RP addon, so the Nearby
-- window can show "Elowen Duskwhisper" instead of "Alicewynn".
--
-- Two sources, tried in that order:
--
--   TRP3_API  Total RP 3's own registry. Preferred, because the title, first
--             name and last name are separate fields, so we can drop the title
--             without guessing.
--   msp       LibMSP, which covers MyRolePlay and XRP. One combined name
--             field, so titles have to be stripped heuristically.
--
-- Both are optional globals: with no RP addon installed nothing here fires and
-- names fall back to the character name. Nothing in this file is a dependency.
--
-- Identity is never an RP name. The roster, the selection and the saved
-- variables all stay keyed on "Character-Realm": RP names aren't unique, and
-- people change them mid-session. Only what you see changes.
--
-- The approach follows Tammya-MoonGuard's RPNames library, which shipped with
-- Listener; this is a reimplementation, not a copy.
-------------------------------------------------------------------------------

local ADDON_NAME, Me = ...

Me.RPNames = {}
local RPNames = Me.RPNames

-- The whole cache is dumped this often. Profiles arrive at unpredictable
-- times and there's no per-entry invalidation worth the bookkeeping.
local CACHE_TTL = 5

-- How often we re-check whether a displayed name has changed.
local POLL_INTERVAL = 5

-- Coalescing delay for profile-received callbacks, which can arrive in bursts.
local REFRESH_DELAY = 0.5

local g_cache      = {}
local g_cache_time = 0

-------------------------------------------------------------------------------
-- Titles to strip from a name that arrived as one blob (the MSP case).
--
local TITLES = {}

do
	local words = {
		-- Military
		"private", "pvt", "pfc", "corporal", "cpl", "sergeant", "sgt",
		"lieutenant", "lt", "captain", "cpt", "commander", "major", "admiral",
		"ensign", "officer", "cadet", "guard", "general", "marshal",
		-- Nobility
		"dame", "sir", "knight", "lady", "lord", "mister", "mistress",
		"master", "miss", "king", "queen", "prince", "princess", "archduke",
		"archduchess", "duke", "duchess", "marquess", "marquis", "marchioness",
		"count", "countess", "viscount", "viscountess", "baron", "baroness",
		"baronet",
		-- Civility
		"mr", "mrs", "ms", "dr", "doctor", "professor",
		-- Religion
		"bishop", "father", "mother", "brother", "sister", "priest",
		"priestess", "archbishop", "cleric",
	}

	for _, word in ipairs( words ) do
		TITLES[word] = true
		TITLES[word .. "."] = true  -- "Dr." as well as "Dr"
	end
end

-------------------------------------------------------------------------------
-- "Duke Maxen Montclair" -> "Maxen Montclair". A single word is left alone
-- even if it looks like a title, since dropping it would leave nothing.
--
function RPNames.StripTitle( name )
	local first = name:match( "^%s*(%S+)" )
	if first and TITLES[first:lower()] and name:match( "^%s*%S+%s+%S" ) then
		name = name:gsub( "^%s*%S+%s+", "" )
	end
	return name
end

-------------------------------------------------------------------------------
-- Strip color escapes and trim. RP addons let people put color codes in the
-- name field, and we want the raw text so our own coloring stays in control.
--
local function CleanName( name )
	if type( name ) ~= "string" then return nil end

	local color = name:match( "^|c(%x%x%x%x%x%x%x%x)" )

	name = name:gsub( "|c%x%x%x%x%x%x%x%x", "" ):gsub( "|r", "" )
	name = name:gsub( "^%s+", "" ):gsub( "%s+$", "" )

	if name == "" then return nil end
	return name, color
end

-------------------------------------------------------------------------------
-- Total RP 3.
--
-- @returns name, color
--
local function GetFromTRP3( full )
	local api = _G.TRP3_API
	if not api then return end

	local register = api.register
	if not (register and register.isUnitIDKnown) then return end

	-- TRP3 hands out an empty character list until its registry is ready.
	if register.getCharacterList and not register.getCharacterList() then
		return
	end

	local globals = api.globals
	local profile

	if globals and full == globals.player_id then
		profile = api.profile and api.profile.getData and api.profile.getData( "player" )
	elseif register.isUnitIDKnown( full ) and register.getUnitIDCurrentProfile then
		profile = register.getUnitIDCurrentProfile( full )
	else
		return
	end

	local ch = profile and profile.characteristics
	if not ch then return end

	local name = CleanName( ch.FN )
	if not name then return end

	local last = CleanName( ch.LN )
	if last then name = name .. " " .. last end

	local color
	if type( ch.CH ) == "string" and ch.CH ~= "" then
		color = "ff" .. ch.CH
	end

	-- A profile that came in over the MSP bridge puts everything in FN,
	-- title included, so strip anyway.
	return RPNames.StripTitle( name ), color
end

-------------------------------------------------------------------------------
-- LibMSP: MyRolePlay, XRP, and TRP3's compatibility layer.
--
-- @returns name, color
--
local function GetFromMSP( full )
	local msp = _G.msp
	if not (msp and msp.char) then return end

	-- Which key LibMSP files a player under has changed over the years, so
	-- try the full name and the bare one.
	for _, key in ipairs({ full, Me.ShortName( full ) }) do
		local entry = msp.char[key]
		if entry and entry.supported and entry.field then
			local name, color = CleanName( entry.field.NA )
			if name then
				return RPNames.StripTitle( name ), color
			end
		end
	end
end

-------------------------------------------------------------------------------
-- Which RP addon we're reading from, for /sw status. nil when there is none.
--
function RPNames.Source()
	if _G.TRP3_API then return "Total RP 3" end
	if _G.msp then return "MyRolePlay / XRP" end
	return nil
end

-------------------------------------------------------------------------------
function RPNames.ClearCache()
	g_cache = {}
	g_cache_time = GetTime()
end

-------------------------------------------------------------------------------
-- The roleplay name for a character, or nil when there isn't one: no RP addon,
-- no profile received yet, or an empty name field.
--
-- @param full Canonical "Character-Realm".
-- @returns name, color   color is "ffRRGGBB" or nil.
--
function RPNames.Get( full )
	if not full then return nil end

	if GetTime() > g_cache_time + CACHE_TTL then
		RPNames.ClearCache()
	end

	local cached = g_cache[full]
	if cached then
		return cached[1], cached[2]
	end

	-- RP addon internals are somebody else's code reached through a global.
	-- A change on their side should cost us a name, not the chat window.
	local ok, name, color = pcall( GetFromTRP3, full )
	if not ok or not name then
		ok, name, color = pcall( GetFromMSP, full )
		if not ok then name, color = nil, nil end
	end

	-- Cached either way: a miss is worth remembering for a few seconds too,
	-- otherwise every line in the window re-queries a profile we don't have.
	g_cache[full] = { name, color }
	return name, color
end

-------------------------------------------------------------------------------
-- Keeping the window current
-------------------------------------------------------------------------------

-- The name we last displayed for each player, so we can notice when a profile
-- arrives and changes it.
local g_displayed = {}

local g_refresh_pending = false

-------------------------------------------------------------------------------
-- Remember what we rendered. Called from the display path.
--
function RPNames.NoteDisplayed( full, name )
	g_displayed[full] = name
end

-------------------------------------------------------------------------------
-- Rebuild the window soon, coalescing bursts of profile updates.
--
function RPNames.RequestRefresh()
	if g_refresh_pending then return end
	g_refresh_pending = true

	local function refresh()
		g_refresh_pending = false
		RPNames.ClearCache()
		if Me.Window then Me.Window.Refresh() end
	end

	if C_Timer and C_Timer.After then
		C_Timer.After( REFRESH_DELAY, refresh )
	else
		refresh()
	end
end

-------------------------------------------------------------------------------
-- The backstop for RP addons that don't tell us when a profile lands: every
-- few seconds, see whether any displayed name has changed.
--
function RPNames.Poll()
	if not Me.db.settings.rp_names then return end

	RPNames.ClearCache()

	local changed = false

	for full in pairs( Me.chardb.selected ) do
		-- Read the previous value first: DisplayName records what it returns,
		-- so asking it afterwards would compare the new name against itself.
		local previous = g_displayed[full]
		local current  = Me.DisplayName( full )

		if previous and previous ~= current then
			changed = true
		end
	end

	if changed and Me.Window then
		Me.Window.Refresh()
	end
end

-------------------------------------------------------------------------------
-- Hook whatever "a profile arrived" notification the RP addon offers, for an
-- instant update instead of waiting for the poll.
--
function RPNames.HookProfileEvents()
	local msp = _G.msp
	if msp and msp.callback and type( msp.callback.received ) == "table" then
		table.insert( msp.callback.received, function()
			if Me.db.settings.rp_names then RPNames.RequestRefresh() end
		end)
	end

	local api = _G.TRP3_API
	local events = api and api.Events
	if events and events.registerCallback and events.REGISTER_DATA_UPDATED then
		pcall( events.registerCallback, events.REGISTER_DATA_UPDATED, function()
			if Me.db.settings.rp_names then RPNames.RequestRefresh() end
		end)
	end
end

-------------------------------------------------------------------------------
function RPNames.Setup()
	RPNames.HookProfileEvents()

	if C_Timer and C_Timer.NewTicker then
		C_Timer.NewTicker( POLL_INTERVAL, RPNames.Poll )
	end
end
