-------------------------------------------------------------------------------
-- SayWhat - slash commands.
--
--   /saywhat, /sw, /nearby
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
local HELP = {
	"|cff4fd1c5SayWhat|r - tracks who talks in /say range.",
	"  |cffffff00/sw|r - toggle the Nearby window.",
	"  |cffffff00/sw list|r - list nearby players, with [+]/[-] to filter them.",
	"  |cffffff00/sw menu|r - open the player selection menu.",
	"  |cffffff00/sw add [name]|r - show a player (defaults to your target).",
	"  |cffffff00/sw remove [name]|r - stop showing a player.",
	"  |cffffff00/sw toggle [name]|r - flip a player on or off.",
	"  |cffffff00/sw all|r - select everyone currently in range.",
	"  |cffffff00/sw clear|r - deselect everyone.",
	"  |cffffff00/sw forget|r - empty the roster of players you haven't picked.",
	"  |cffffff00/sw show|r, |cffffff00/sw hide|r, |cffffff00/sw lock|r",
	"  |cffffff00/sw minimap|r - show or hide the minimap button.",
	"  |cffffff00/sw status|r - what the addon currently thinks is going on.",
}

local function PrintHelp()
	for _, line in ipairs( HELP ) do
		Me.Print( line )
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
		Me.Print( "Don't know \"%s\". Try /sw help.", command )
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
function Me.SetupCommands()
	SLASH_SAYWHAT1 = "/saywhat"
	SLASH_SAYWHAT2 = "/sw"
	SLASH_SAYWHAT3 = "/nearby"

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
