-------------------------------------------------------------------------------
-- SayWhat
--
-- Tracks the players who speak in /say range around you, and mirrors their
-- chat into a dedicated "Nearby" window that only shows the people you pick.
--
-- Inspired by Listener (Tammya-MoonGuard). Written from scratch, no libraries.
--
-- This file holds the addon namespace, the saved variables, the name helpers,
-- and the chat event pipeline that feeds everything else.
-------------------------------------------------------------------------------

local ADDON_NAME, Me = ...

-- Expose the namespace so /run and other addons can poke at it.
_G.SayWhat = Me

Me.addon_name = ADDON_NAME

local GetAddOnMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or _G.GetAddOnMetadata
Me.version = (GetAddOnMetadata and GetAddOnMetadata( ADDON_NAME, "Version" )) or "dev"

-------------------------------------------------------------------------------
-- Chat events we can capture.
--
-- Range notes, which are the whole point of this addon:
--
--   SAY / EMOTE / TEXT_EMOTE are only delivered by the server when the sender
--   is inside normal say range (about 40 yards, less in some instanced
--   content). There is no client API that gives you the distance to an
--   arbitrary player, so *receiving the event is the range test*. If a
--   CHAT_MSG_SAY arrived, that player was in say range at that moment. That's
--   what "nearby" means here.
--
--   YELL carries much further (about 300 yards), so it is captured for display
--   but is NOT proof of proximity. It is off by default in the tracker.
--
local CHAT_EVENTS = {
	"CHAT_MSG_SAY",
	"CHAT_MSG_EMOTE",
	"CHAT_MSG_TEXT_EMOTE",
	"CHAT_MSG_YELL",
}

-- Human readable names for the event suffixes we deal with.
Me.EVENT_LABELS = {
	SAY        = "Say";
	EMOTE      = "Emote";
	TEXT_EMOTE = "Text Emote";
	YELL       = "Yell";
}

-- Menu/iteration order for the above.
Me.EVENT_ORDER = { "SAY", "EMOTE", "TEXT_EMOTE", "YELL" }

-------------------------------------------------------------------------------
-- Saved variable defaults.
--
-- SayWhatDB     - account wide: settings and window layout.
-- SayWhatCharDB - per character: the nearby roster and which players are
--                 selected. Proximity is a per-character thing, so the
--                 selection lives with the character.
--
local DB_VERSION = 1

local DEFAULT_DB = {
	version = DB_VERSION;

	settings = {
		-- Which events mark someone as "nearby". SAY only by default, since
		-- that is what the feature is about, and yell is not a range signal.
		track_events = {
			SAY = true, EMOTE = false, TEXT_EMOTE = false, YELL = false;
		};

		-- Which events the Nearby window displays for selected players.
		show_events = {
			SAY = true, EMOTE = true, TEXT_EMOTE = true, YELL = false;
		};

		-- Seconds of silence before a player stops counting as "in range".
		nearby_timeout = 300;

		-- Seconds of silence before an unselected player is forgotten
		-- entirely. Selected players are never forgotten.
		roster_expiry = 60 * 60 * 24;

		-- Show your own say/emote in the window even though you can't select
		-- yourself as "nearby".
		include_self = true;

		-- Pop the window open when a selected player says something.
		auto_show = false;

		-- Print "so-and-so is nearby [Add]" when a new player is picked up.
		announce_new = false;

		-- Show the roleplay name from Total RP 3 / MyRolePlay / XRP instead of
		-- the character name, where one has been received.
		rp_names  = true;

		-- Use the profile's own name color rather than the class color. Off by
		-- default: class colors carry information, and custom colors are not
		-- always readable on the window's background.
		rp_colors = false;

		timestamps = true;
		font_size  = 12;
		locked     = false;

		-- The minimap button. Angle is degrees around the minimap's ring.
		minimap = {
			show  = true;
			angle = 200;
		};

		window = {
			point   = "CENTER";
			relpoint= "CENTER";
			x       = 0;
			y       = 0;
			width   = 420;
			height  = 260;
			shown   = false;
		};
	};
}

local DEFAULT_CHAR_DB = {
	version  = DB_VERSION;
	selected = {};  -- [full name] = true
	roster   = {};  -- [full name] = { last, count, class, zone }
}

-------------------------------------------------------------------------------
-- Fill in anything missing in `dst` from `src`, recursively. Existing values
-- are never overwritten, so a saved variable file from an older version just
-- picks up the new keys.
--
local function CopyDefaults( dst, src )
	for k, v in pairs( src ) do
		if type( v ) == "table" then
			if type( dst[k] ) ~= "table" then dst[k] = {} end
			CopyDefaults( dst[k], v )
		elseif dst[k] == nil then
			dst[k] = v
		end
	end
	return dst
end
Me.CopyDefaults = CopyDefaults

-------------------------------------------------------------------------------
-- Secret value support. (Patch 12.0)
--
-- Chat payloads delivered while we're inside an instance arrive as "secret"
-- values. Addon code may hold such a value but may not read it: indexed access
-- and method calls raise a Lua error. We can't parse what we can't read, so
-- those messages are dropped.
--
-- On clients older than 12.0 issecretvalue doesn't exist and this always
-- reports false, leaving behavior unchanged.
--
local issecretvalue = _G.issecretvalue

function Me.IsSecret( ... )
	if not issecretvalue then return false end

	for i = 1, select( "#", ... ) do
		if issecretvalue( (select( i, ... )) ) then return true end
	end

	return false
end

-------------------------------------------------------------------------------
-- Chat output.
--
local PRINT_PREFIX = "|cff4fd1c5SayWhat:|r "

function Me.Print( text, ... )
	if select( "#", ... ) > 0 then
		text = string.format( text, ... )
	end
	local frame = DEFAULT_CHAT_FRAME
	if frame then
		frame:AddMessage( PRINT_PREFIX .. text )
	else
		print( PRINT_PREFIX .. text )
	end
end

-------------------------------------------------------------------------------
-- Name handling.
--
-- Everything is keyed on the full "Name-Realm" form so that two people with
-- the same name on different realms never collide. Display strips the realm
-- again when it matches our own.
-------------------------------------------------------------------------------

-- Cached from UnitFullName. This can be nil very early during login, so it is
-- refetched until it works.
Me.realm = nil

function Me.FetchRealm()
	local _, realm = UnitFullName( "player" )
	if realm and realm ~= "" then
		Me.realm = realm
	elseif C_Timer then
		C_Timer.After( 1, Me.FetchRealm )
	end
	return Me.realm
end

-------------------------------------------------------------------------------
-- Capitalize a name the way the game does: first letter upper, rest lower.
-- The realm part (after the dash) is left alone apart from case-insensitive
-- matching later, since realm names are CamelCase.
--
function Me.FixupName( name )
	local base, realm = name:match( "^([^-]+)-(.+)$" )
	base = base or name

	base = base:lower()
	-- (utf8 friendly) capitalize the first character
	base = base:gsub( "^[%z\1-\127\194-\244][\128-\191]*", string.upper )

	if realm then
		-- Realms never contain spaces in the name-realm form.
		realm = realm:gsub( "%s", "" )
		return base .. "-" .. realm
	end
	return base
end

-------------------------------------------------------------------------------
-- Turn any name into the canonical "Name-Realm" key.
--
function Me.FullName( name )
	if not name or name == "" then return nil end
	name = Me.FixupName( name )
	if name:find( "-", 1, true ) then return name end

	local realm = Me.realm or Me.FetchRealm()
	if not realm then
		-- Very early during login we don't know our own realm yet. Better to
		-- drop the name than to file someone under a realm we made up and
		-- never match their later messages.
		return nil
	end

	return name .. "-" .. realm
end

-------------------------------------------------------------------------------
-- The display form: drop the realm when it's ours, keep it otherwise.
--
function Me.ShortName( full )
	if not full then return "" end
	local base, realm = full:match( "^([^-]+)-(.+)$" )
	if not base then return full end
	if realm == Me.realm then return base end
	return full
end

-------------------------------------------------------------------------------
-- The name to show for a player: their roleplay name when we have one and the
-- option is on, otherwise the character name.
--
-- Identity is always the character name. This is display only.
--
function Me.DisplayName( full )
	if not full then return "" end

	if Me.db and Me.db.settings.rp_names then
		local rp = Me.RPNames.Get( full )
		if rp then
			Me.RPNames.NoteDisplayed( full, rp )
			return rp
		end
	end

	local short = Me.ShortName( full )
	Me.RPNames.NoteDisplayed( full, short )
	return short
end

-------------------------------------------------------------------------------
function Me.MyFullName()
	local name = UnitName( "player" )
	if Me.IsSecret( name ) then return nil end
	return Me.FullName( name )
end

-------------------------------------------------------------------------------
-- Resolve whatever the user typed into a roster/selection key.
--
-- Tries, in order: an exact key, a case-insensitive match against a known
-- player, and finally "assume it's someone on our realm".
--
function Me.ResolveName( input )
	if not input or input == "" then return nil end

	input = input:gsub( "^%s+", "" ):gsub( "%s+$", "" )
	if input == "" then return nil end

	-- Strip a player link if one was dragged in, e.g. |Hplayer:Name-Realm|h[Name]|h
	local linked = input:match( "|Hplayer:([^:|]+)" )
	if linked then input = linked end

	local direct = Me.FixupName( input )
	local known = Me.Roster.Known()

	if known[direct] then return direct end

	-- Case insensitive sweep over everyone we know about.
	local lowered = input:lower()
	for name in pairs( known ) do
		if name:lower() == lowered or Me.ShortName( name ):lower() == lowered then
			return name
		end
	end

	-- Then by roleplay name, so "add elowen" works when that's the only
	-- name you've seen. Both the whole name and its first word are accepted.
	if Me.db.settings.rp_names then
		for name in pairs( known ) do
			local rp = Me.RPNames.Get( name )
			if rp then
				rp = rp:lower()
				if rp == lowered or rp:match( "^%S+" ) == lowered then
					return name
				end
			end
		end
	end

	return Me.FullName( input )
end

-------------------------------------------------------------------------------
-- The name of whoever you're targeting or mousing over, for commands used
-- without an argument.
--
function Me.GetTargetName()
	for _, unit in ipairs({ "target", "mouseover" }) do
		if UnitExists( unit ) and UnitIsPlayer( unit ) then
			local name, realm = UnitName( unit )
			if not Me.IsSecret( name, realm ) then
				if realm and realm ~= "" then
					return Me.FullName( name .. "-" .. realm )
				end
				return Me.FullName( name )
			end
		end
	end
end

-------------------------------------------------------------------------------
-- Chat pipeline
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- CHAT_MSG_TEXT_EMOTE hands us a sender without a realm, but the realm is
-- sitting right there in the message text ("Tammya-MoonGuard waves."). Dig it
-- out so cross-realm text emotes key on the same player as their says.
--
local function RealmFromTextEmote( sender, message )
	if sender:find( "-", 1, true ) then return sender end

	local pattern = sender:gsub( "([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1" )
	local realm = message:match( pattern .. "%-([A-Za-z0-9']+)" )
	if realm then
		-- Drop a possessive that got swept up with it.
		realm = realm:gsub( "'s$", "" )
		return sender .. "-" .. realm
	end
	return sender
end

-------------------------------------------------------------------------------
-- The single entry point for every chat event we listen to.
--
-- Signature is the standard CHAT_MSG_* payload; guid is the 12th argument.
--
function Me.OnChatMsg( event, text, sender, language, channel, sender2, flags,
                       zone_id, channel_index, channel_base, unused, line_id,
                       guid )

	-- We can't read secret payloads at all, so there is nothing to filter on.
	if Me.IsSecret( text, sender, guid ) then return end
	if not sender or sender == "" then return end
	if not text then return end

	local kind = event:sub( 10 ) -- "CHAT_MSG_SAY" -> "SAY"

	if kind == "TEXT_EMOTE" then
		sender = RealmFromTextEmote( sender, text )
	end

	local full = Me.FullName( sender )
	if not full then return end

	local mine = (full == Me.MyFullName())
	local now  = time()

	-- Record proximity. Hearing this event *is* the range check.
	if not mine and Me.db.settings.track_events[kind] then
		Me.Roster.Record( full, guid, now )
	end

	-- Everything we captured goes in the log, selected or not, so that
	-- enabling a player shows what they already said.
	local entry = {
		t = now;
		e = kind;
		s = full;
		m = text;
		p = mine or nil;
	}

	Me.Log.Add( entry )

	if Me.Window then
		Me.Window.TryAddMessage( entry )
	end
end

-------------------------------------------------------------------------------
-- Should this log entry appear in the Nearby window?
--
function Me.ShouldDisplay( entry )
	if not Me.db.settings.show_events[entry.e] then return false end

	if entry.p then
		-- Our own messages ride along with the conversation.
		return Me.db.settings.include_self and true or false
	end

	return Me.IsSelected( entry.s )
end

-------------------------------------------------------------------------------
-- Initialization
-------------------------------------------------------------------------------

local g_event_frame

-------------------------------------------------------------------------------
function Me.OnAddonLoaded( loaded_name )
	if loaded_name ~= ADDON_NAME then return end

	SayWhatDB     = SayWhatDB or {}
	SayWhatCharDB = SayWhatCharDB or {}

	Me.db     = CopyDefaults( SayWhatDB, DEFAULT_DB )
	Me.chardb = CopyDefaults( SayWhatCharDB, DEFAULT_CHAR_DB )

	Me.db.version     = DB_VERSION
	Me.chardb.version = DB_VERSION

	Me.SetupCommands()
end

-------------------------------------------------------------------------------
function Me.OnPlayerLogin()
	Me.FetchRealm()

	-- Drop players we haven't heard from in a very long time. Selected
	-- players survive this, so a filter set up last week still works.
	Me.Roster.Prune()

	Me.RPNames.Setup()
	Me.Window.Create()
	Me.Minimap.Create()

	if Me.db.settings.window.shown then
		Me.Window.Show()
	end

	Me.SetupUnitPopup()

	if C_Timer and C_Timer.NewTicker then
		-- Keeps "in range" indicators and the roster honest over time.
		C_Timer.NewTicker( 60, function()
			Me.Roster.Prune()
			Me.Window.UpdateTitle()
		end)
	end
end

-------------------------------------------------------------------------------
local EVENT_HANDLERS = {
	ADDON_LOADED = function( name ) Me.OnAddonLoaded( name ) end;
	PLAYER_LOGIN = function() Me.OnPlayerLogin() end;
}

-------------------------------------------------------------------------------
function Me.Setup()
	g_event_frame = CreateFrame( "Frame" )

	g_event_frame:RegisterEvent( "ADDON_LOADED" )
	g_event_frame:RegisterEvent( "PLAYER_LOGIN" )

	for _, event in ipairs( CHAT_EVENTS ) do
		g_event_frame:RegisterEvent( event )
	end

	g_event_frame:SetScript( "OnEvent", function( self, event, ... )
		local handler = EVENT_HANDLERS[event]
		if handler then
			handler( ... )
		else
			Me.OnChatMsg( event, ... )
		end
	end)
end

Me.Setup()
