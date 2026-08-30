-------------------------------------------------------------------------------
-- SayWhat - slash commands.
--
--   /saywhat, /sayw, /nearby
--
-- /sw is deliberately not among them: that's Blizzard's stopwatch. Before
-- claiming a name we check whether anything else already answers to it, so a
-- clash with another addon costs us that one alias rather than breaking
-- somebody's command.
--
-------------------------------------------------------------------------------

local ADDON_NAME, Me = ...

-------------------------------------------------------------------------------
-- Add, remove or toggle a player. Falls back to your target or mouseover when
-- no name is given.
--
local function ChangePlayer( arg, mode )
	local full = arg and Me.ResolveName( arg ) or Me.GetTargetName()

	if not full then
		Me.Print( "Give me a name, or target someone first." )
		return
	end

	if full == Me.MyFullName() then
		Me.Print( "That's you. Your own chat is controlled by the " ..
		          "\"Include my own chat\" option." )
		return
	end

	local state
	if mode == "toggle" then
		state = Me.ToggleSelected( full )
	else
		state = (mode == "add")
		if not Me.SetSelected( full, state ) then
			Me.Print( state and "%s is already in the window."
			                 or "%s isn't in the window.", Me.ColorName( full ) )
			return
		end
	end

	if state then
		local heard = Me.Log.CountFor( full )
		if heard > 0 then
			Me.Print( "Added %s. |cff808080(%d message(s) from this session)|r",
			          Me.ColorName( full ), heard )
		else
			Me.Print( "Added %s.", Me.ColorName( full ) )
		end
	else
		Me.Print( "Removed %s.", Me.ColorName( full ) )
	end
end

-------------------------------------------------------------------------------
local function ListPlayers()
	local list = Me.Roster.List()

	if #list == 0 then
		Me.Print( "Nobody has spoken in range yet." )
		return
	end

	Me.Print( "Nearby roster |cff808080(%d selected)|r:", Me.SelectedCount() )

	for _, item in ipairs( list ) do
		local marker = item.nearby and "|cff40ff40in range|r"
		                            or "|cff808080" .. Me.Menu.AgeText( item.last ) .. "|r"
		local mark   = item.selected and "|cff40ff40*|r" or " "

		Me.Print( "  %s %s %s - %s", mark, Me.Links.Toggle( item.name ),
		          Me.ColorName( item.name ), marker )
	end
end

-------------------------------------------------------------------------------
-- Help is built around whichever command name we actually managed to claim,
-- so it never tells anyone to type something that isn't registered.
--
local HELP = {
	"|cff4fd1c5SayWhat|r - tracks who talks in /say range.",
	"  |cffffff00%s|r - toggle the Nearby window.",
	"  |cffffff00%s list|r - list nearby players, with [+]/[-] to filter them.",
	"  |cffffff00%s menu|r - open the player selection menu.",
	"  |cffffff00%s add [name]|r - show a player (defaults to your target).",
	"  |cffffff00%s remove [name]|r - stop showing a player.",
	"  |cffffff00%s toggle [name]|r - flip a player on or off.",
	"  |cffffff00%s all|r - select everyone currently in range.",
	"  |cffffff00%s clear|r - deselect everyone.",
	"  |cffffff00%s forget|r - empty the roster of players you haven't picked.",
	"  |cffffff00%s show|r, |cffffff00%s hide|r, |cffffff00%s lock|r",
	"  |cffffff00%s minimap|r - show or hide the minimap button.",
	"  |cffffff00%s status|r - what the addon currently thinks is going on.",
}

local function PrintHelp()
	local main = Me.SlashCommand()

	for _, line in ipairs( HELP ) do
		Me.Print( (line:gsub( "%%s", main )) )
	end

	if #Me.slash_names > 1 then
		Me.Print( "  Also answers to %s.",
		          table.concat( Me.slash_names, ", ", 2, #Me.slash_names ) )
	end
end

-------------------------------------------------------------------------------
local function PrintStatus()
	local tracked, shown = {}, {}
	for _, event in ipairs( Me.EVENT_ORDER ) do
		if Me.db.settings.track_events[event] then
			table.insert( tracked, Me.EVENT_LABELS[event] )
		end
		if Me.db.settings.show_events[event] then
			table.insert( shown, Me.EVENT_LABELS[event] )
		end
	end

	Me.Print( "Window: %s. Selected: %d. In range: %d. Known: %d.",
	          Me.Window.IsShown() and "shown" or "hidden",
	          Me.SelectedCount(), Me.Roster.NearbyCount(),
	          #Me.Roster.List() )
	Me.Print( "Counts as nearby: %s.",
	          #tracked > 0 and table.concat( tracked, ", " ) or "nothing" )
	Me.Print( "Shown in window: %s.",
	          #shown > 0 and table.concat( shown, ", " ) or "nothing" )
	Me.Print( "Buffered messages: %d.", #Me.Log.All() )

	Me.Print( "Commands: %s.", table.concat( Me.slash_names, ", " ) )
	for _, clash in ipairs( Me.slash_conflicts ) do
		Me.Print( "|cffff8080%s is taken by %s, so it wasn't registered.|r",
		          clash.token, clash.owner )
	end

	local source = Me.RPNames.Source()
	if not Me.db.settings.rp_names then
		Me.Print( "Roleplay names: off." )
	elseif source then
		Me.Print( "Roleplay names: on, reading %s.", source )
	else
		Me.Print( "Roleplay names: on, but no roleplay addon was found." )
	end
end

-------------------------------------------------------------------------------
-- @param msg The raw text after the slash command.
--
function Me.RunCommand( msg )
	msg = msg or ""

	local command, rest = msg:match( "^%s*(%S*)%s*(.-)%s*$" )
	command = (command or ""):lower()
	if rest == "" then rest = nil end

	if command == "" then
		Me.Window.Toggle()

	elseif command == "show" then
		Me.Window.Show()

	elseif command == "hide" then
		Me.Window.Hide()

	elseif command == "menu" then
		Me.Menu.OpenPlayerSelect( Me.MenuOwner() )

	elseif command == "add" then
		ChangePlayer( rest, "add" )

	elseif command == "remove" or command == "rem" or command == "del" then
		ChangePlayer( rest, "remove" )

	elseif command == "toggle" then
		ChangePlayer( rest, "toggle" )

	elseif command == "list" or command == "who" then
		ListPlayers()

	elseif command == "all" then
		local added = Me.SelectAllNearby()
		Me.Print( "Added %d player(s) currently in range.", added )

	elseif command == "clear" then
		local removed = Me.ClearSelection()
		Me.Print( "Deselected %d player(s).", removed )

	elseif command == "forget" then
		local forgotten = Me.Roster.Clear()
		Me.Print( "Forgot %d player(s). Selected players are kept.", forgotten )

	elseif command == "lock" then
		Me.db.settings.locked = true
		Me.Window.ApplySettings()
		Me.Print( "Window locked." )

	elseif command == "unlock" then
		Me.db.settings.locked = false
		Me.Window.ApplySettings()
		Me.Print( "Window unlocked." )

	elseif command == "minimap" then
		local shown = Me.Minimap.SetShown( nil )
		Me.Print( shown and "Minimap button shown." or "Minimap button hidden." )

	elseif command == "status" then
		PrintStatus()

	elseif command == "help" or command == "?" then
		PrintHelp()

	else
		Me.Print( "Don't know \"%s\". Try %s help.", command, Me.SlashCommand() )
	end
end

-------------------------------------------------------------------------------
-- A menu has to hang off something that's actually on screen.
--
function Me.MenuOwner()
	if Me.Window.IsShown() then return Me.Window.frame end
	return UIParent
end

-------------------------------------------------------------------------------
-- The names we'd like, best first. /sw is Blizzard's stopwatch and is not
-- among them.
--
local SLASH_TOKENS = { "/saywhat", "/sayw", "/nearby" }

-- The ones we actually registered, and anything we had to skip.
Me.slash_names     = {}
Me.slash_conflicts = {}

-------------------------------------------------------------------------------
-- The command to tell people to type: the first name we claimed.
--
function Me.SlashCommand()
	return Me.slash_names[1] or SLASH_TOKENS[1]
end

-------------------------------------------------------------------------------
-- Who, if anyone, already answers to this slash command.
--
-- Blizzard's own commands are registered when FrameXML loads, well before us,
-- so they're all visible here. Addons that load after us are not, which is why
-- this is a courtesy rather than a guarantee.
--
local function SlashCommandOwner( token )
	for name in pairs( SlashCmdList ) do
		for index = 1, 20 do
			local existing = _G["SLASH_" .. name .. index]
			if not existing then break end
			if existing:lower() == token then return name end
		end
	end
end

-------------------------------------------------------------------------------
function Me.SetupCommands()
	Me.slash_names     = {}
	Me.slash_conflicts = {}

	for _, token in ipairs( SLASH_TOKENS ) do
		local owner = SlashCommandOwner( token )
		if owner then
			table.insert( Me.slash_conflicts, { token = token, owner = owner } )
		else
			table.insert( Me.slash_names, token )
		end
	end

	if #Me.slash_names == 0 then
		-- Everything we wanted is taken. Register the primary name anyway:
		-- fighting over it beats having no way to reach the addon at all.
		Me.slash_names = { SLASH_TOKENS[1] }
	end

	for index, token in ipairs( Me.slash_names ) do
		_G["SLASH_SAYWHAT" .. index] = token
	end

	SlashCmdList["SAYWHAT"] = function( msg )
		Me.RunCommand( msg )
	end
end

-------------------------------------------------------------------------------
-- The addon compartment button on the minimap, declared in the TOC.
--
function _G.SayWhat_OnCompartmentClick( _, button )
	if button == "RightButton" then
		Me.Menu.OpenPlayerSelect( Me.MenuOwner() )
	else
		Me.Window.Toggle()
	end
end
