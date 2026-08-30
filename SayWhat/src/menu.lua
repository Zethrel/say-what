-------------------------------------------------------------------------------
-- SayWhat - menus.
--
-- The player selection menu (tick a nearby player to show them in the Nearby
-- window) plus the options submenu.
--
-- Menus are described as plain tables and then rendered with whichever menu
-- API the client has: MenuUtil on modern retail, UIDropDownMenu on older
-- clients.
--
--   { type = "title",    text = ... }
--   { type = "button",   text = ..., func = ... }
--   { type = "checkbox", text = ..., checked = fn, func = fn }
--   { type = "submenu",  text = ..., entries = { ... } }
--   { type = "divider" }
--
-------------------------------------------------------------------------------

local ADDON_NAME, Me = ...

Me.Menu = {}
local Menu = Me.Menu

-------------------------------------------------------------------------------
-- Modern renderer (MenuUtil, Dragonflight and later).
--
local function RenderModern( root, entries )
	for _, item in ipairs( entries ) do
		if item.type == "title" then
			root:CreateTitle( item.text )

		elseif item.type == "divider" then
			root:CreateDivider()

		elseif item.type == "checkbox" then
			root:CreateCheckbox( item.text,
				function() return item.checked() end,
				function()
					item.func()
					return MenuResponse and MenuResponse.Refresh
				end )

		elseif item.type == "submenu" then
			local sub = root:CreateButton( item.text )
			RenderModern( sub, item.entries )

		else
			root:CreateButton( item.text, function() item.func() end )
		end
	end
end

-------------------------------------------------------------------------------
-- Legacy renderer (UIDropDownMenu).
--
-- Nesting works by handing the submenu's entry table through as menuList,
-- which the dropdown passes straight back to the initializer.
--
local g_legacy_frame
local g_legacy_entries

local function RenderLegacy( self, level, menuList )
	local entries = menuList or g_legacy_entries
	if not entries then return end

	for _, item in ipairs( entries ) do
		local info = UIDropDownMenu_CreateInfo()

		if item.type == "title" then
			info.text         = item.text
			info.isTitle      = true
			info.notCheckable = true

		elseif item.type == "divider" then
			info.text         = ""
			info.disabled     = true
			info.notCheckable = true

		elseif item.type == "checkbox" then
			info.text             = item.text
			info.checked          = item.checked()
			info.isNotRadio       = true
			info.keepShownOnClick = true
			info.func             = function() item.func() end

		elseif item.type == "submenu" then
			info.text             = item.text
			info.notCheckable     = true
			info.hasArrow         = true
			info.keepShownOnClick = true
			info.menuList         = item.entries

		else
			info.text         = item.text
			info.notCheckable = true
			info.func         = function() item.func() end
		end

		UIDropDownMenu_AddButton( info, level )
	end
end

-------------------------------------------------------------------------------
-- Open a described menu anchored to a frame.
--
function Menu.Show( owner, entries )
	if MenuUtil and MenuUtil.CreateContextMenu then
		MenuUtil.CreateContextMenu( owner, function( _, root )
			RenderModern( root, entries )
		end)
		return
	end

	if not UIDropDownMenu_Initialize then
		Me.Print( "This client has no menu API that I know how to use. Use /sw list instead." )
		return
	end

	if not g_legacy_frame then
		g_legacy_frame = CreateFrame( "Button", "SayWhatContextMenu", UIParent,
		                              "UIDropDownMenuTemplate" )
		g_legacy_frame.displayMode = "MENU"
	end

	g_legacy_entries = entries
	UIDropDownMenu_Initialize( g_legacy_frame, RenderLegacy, "MENU" )
	ToggleDropDownMenu( 1, nil, g_legacy_frame, owner, 0, 0 )
end

-------------------------------------------------------------------------------
-- "5m ago" style text for a roster entry.
--
local function AgeText( last )
	if not last or last == 0 then return "never" end

	local age = time() - last
	if age < 60   then return age .. "s ago" end
	if age < 3600 then return math.floor( age / 60 ) .. "m ago" end
	if age < 86400 then return math.floor( age / 3600 ) .. "h ago" end
	return math.floor( age / 86400 ) .. "d ago"
end
Menu.AgeText = AgeText

-------------------------------------------------------------------------------
-- One line per known player: class colored name, whether they're still in
-- range, and how long ago we heard them.
--
local function PlayerEntries()
	local entries = {}
	local list    = Me.Roster.List()

	if #list == 0 then
		table.insert( entries, {
			type = "button";
			text = "|cff808080Nobody has spoken nearby yet|r";
			func = function() end;
		})
		return entries
	end

	for _, item in ipairs( list ) do
		local marker = item.nearby and "|cff40ff40*|r " or "|cff808080-|r "
		local label  = string.format( "%s%s |cff808080(%s)|r",
		               marker, Me.ColorName( item.name ), AgeText( item.last ))

		table.insert( entries, {
			type    = "checkbox";
			text    = label;
			checked = function() return Me.IsSelected( item.name ) end;
			func    = function() Me.ToggleSelected( item.name ) end;
		})
	end

	return entries
end

-------------------------------------------------------------------------------
local function EventEntries( setting_key )
	local entries = {}
	for _, event in ipairs( Me.EVENT_ORDER ) do
		table.insert( entries, {
			type    = "checkbox";
			text    = Me.EVENT_LABELS[event];
			checked = function() return Me.db.settings[setting_key][event] and true or false end;
			func    = function()
				local set = Me.db.settings[setting_key]
				if set[event] then set[event] = nil else set[event] = true end
				if setting_key == "show_events" then Me.Window.Refresh() end
			end;
		})
	end
	return entries
end

-------------------------------------------------------------------------------
local function OptionsEntries()
	local settings = function() return Me.db.settings end

	local function Flag( key, text, on_change )
		return {
			type    = "checkbox";
			text    = text;
			checked = function() return settings()[key] and true or false end;
			func    = function()
				settings()[key] = not settings()[key]
				if on_change then on_change() end
			end;
		}
	end

	return {
		{ type = "title", text = "Options" },

		{ type = "submenu", text = "Show in window",
		  entries = EventEntries( "show_events" ) },

		{ type = "submenu", text = "Counts as nearby",
		  entries = EventEntries( "track_events" ) },

		{ type = "divider" },

		Flag( "include_self", "Include my own chat", function() Me.Window.Refresh() end ),
		Flag( "timestamps",   "Timestamps",          function() Me.Window.Refresh() end ),
		Flag( "auto_show",    "Open window on new message" ),
		Flag( "announce_new", "Announce new players in chat" ),
		Flag( "locked",       "Lock window",         function() Me.Window.ApplySettings() end ),

		{ type = "divider" },

		{ type = "button", text = "Font size +", func = function()
			Me.Window.AdjustFontSize( 1 )
		end },
		{ type = "button", text = "Font size -", func = function()
			Me.Window.AdjustFontSize( -1 )
		end },
	}
end

-------------------------------------------------------------------------------
-- The main menu: pick who the Nearby window listens to.
--
function Menu.OpenPlayerSelect( owner )
	local entries = {
		{ type = "title", text = string.format( "Nearby Players (%d in range)",
		                                        Me.Roster.NearbyCount() ) },
	}

	for _, item in ipairs( PlayerEntries() ) do
		table.insert( entries, item )
	end

	table.insert( entries, { type = "divider" } )
	table.insert( entries, { type = "button", text = "Select everyone in range",
		func = function()
			local added = Me.SelectAllNearby()
			Me.Print( "Added %d player(s).", added )
		end })
	table.insert( entries, { type = "button", text = "Clear selection",
		func = function()
			local removed = Me.ClearSelection()
			Me.Print( "Cleared %d player(s).", removed )
		end })
	table.insert( entries, { type = "button", text = "Forget everyone not selected",
		func = function()
			Me.Print( "Forgot %d player(s).", Me.Roster.Clear() )
		end })

	table.insert( entries, { type = "divider" } )
	table.insert( entries, { type = "submenu", text = "Options",
	                         entries = OptionsEntries() } )

	Menu.Show( owner, entries )
end

-------------------------------------------------------------------------------
-- The little menu you get from clicking a name inside the Nearby window.
--
function Menu.OpenPlayer( owner, full )
	local entries = {
		{ type = "title", text = Me.ShortName( full ) },

		{ type = "button";
		  text = Me.IsSelected( full ) and "Remove from Nearby" or "Add to Nearby";
		  func = function()
			local state = Me.ToggleSelected( full )
			Me.Print( state and "Added %s." or "Removed %s.", Me.ColorName( full ) )
		  end },

		{ type = "button", text = "Whisper", func = function()
			if ChatFrame_OpenChat then
				ChatFrame_OpenChat( "/w " .. full .. " " )
			end
		end },
	}

	Menu.Show( owner, entries )
end

-------------------------------------------------------------------------------
-- Add "Add to / Remove from Nearby" to the right-click menu you get on a
-- player's name in the chat window or on a unit frame.
--
-- This is the "manage players straight from the chat window" path; the slash
-- commands and the window's own menu are the others.
--
function Me.SetupUnitPopup()
	if not (_G.Menu and _G.Menu.ModifyMenu) then return end

	local function Handler( owner, root, context )
		if not context then return end

		local name  = context.name
		local realm = context.server
		if not name or name == "" then return end
		if Me.IsSecret( name, realm ) then return end

		local full = Me.FullName( realm and realm ~= "" and (name .. "-" .. realm) or name )
		if not full or full == Me.MyFullName() then return end

		root:CreateDivider()
		root:CreateButton(
			Me.IsSelected( full ) and "SayWhat: Remove from Nearby"
			                       or "SayWhat: Add to Nearby",
			function()
				local state = Me.ToggleSelected( full )
				Me.Print( state and "Added %s." or "Removed %s.", Me.ColorName( full ) )
			end )
	end

	-- Menu tag names have moved around between patches, so each one is tried
	-- on its own: a tag this client doesn't have shouldn't cost us the rest.
	local TAGS = {
		"MENU_UNIT_PLAYER",       -- names in the chat window, other players
		"MENU_UNIT_FRIEND",
		"MENU_UNIT_PARTY",
		"MENU_UNIT_RAID_PLAYER",
	}

	for _, tag in ipairs( TAGS ) do
		pcall( _G.Menu.ModifyMenu, tag, Handler )
	end
end
