-------------------------------------------------------------------------------
-- A small mock of the World of Warcraft API, enough to load SayWhat outside
-- the game and drive it from a test script.
--
-- Nothing here is used by the addon itself; it exists so the chat pipeline,
-- the roster, the filter and the saved variables can be exercised with plain
-- Lua 5.1, which is the same Lua the game runs.
-------------------------------------------------------------------------------

local M = {}

-------------------------------------------------------------------------------
-- Widget mocks
-------------------------------------------------------------------------------

local Widget = {}
Widget.__index = function( self, key )
	local method = rawget( Widget, key )
	if method then return method end

	-- Anything we didn't bother implementing is a no-op, which is what most
	-- of the layout calls are as far as the tests care.
	local noop = function() end
	rawset( self, key, noop )
	return noop
end

function Widget.new( kind, name, parent )
	local self = setmetatable( {}, Widget )
	self.kind     = kind
	self.name     = name
	self.parent   = parent
	self.shown    = true
	self.scripts  = {}
	self.events   = {}
	self.lines    = {}
	self.width    = 400
	self.height   = 260
	self.point    = { "CENTER", nil, "CENTER", 0, 0 }
	self.text     = ""
	return self
end

function Widget:GetName()   return self.name end
function Widget:GetParent() return self.parent end

function Widget:Show()          self.shown = true  end
function Widget:Hide()          self.shown = false end
function Widget:IsShown()       return self.shown end
function Widget:IsVisible()     return self.shown end
function Widget:SetShown( v )   self.shown = v and true or false end

function Widget:SetSize( w, h ) self.width, self.height = w, h end
function Widget:SetWidth( w )   self.width = w end
function Widget:SetHeight( h )  self.height = h end
function Widget:GetWidth()      return self.width end
function Widget:GetHeight()     return self.height end

function Widget:SetPoint( point, a, b, c, d )
	if type( a ) == "string" then
		-- SetPoint( point, relpoint, x, y )
		self.point = { point, nil, a, b or 0, c or 0 }
	elseif type( a ) == "table" then
		-- SetPoint( point, relframe, relpoint, x, y )
		self.point = { point, a, b, c or 0, d or 0 }
	else
		self.point = { point, nil, point, a or 0, b or 0 }
	end
end

function Widget:GetPoint()
	local p = self.point
	return p[1], p[2], p[3], p[4], p[5]
end

function Widget:SetText( text ) self.text = text end
function Widget:GetText()       return self.text end

function Widget:SetScript( name, fn ) self.scripts[name] = fn end
function Widget:GetScript( name )     return self.scripts[name] end
function Widget:HasScript()           return true end

function Widget:RegisterEvent( event )
	self.events[event] = true
	M.frames[self] = true
end

function Widget:UnregisterEvent( event ) self.events[event] = nil end

function Widget:CreateTexture()    return Widget.new( "Texture", nil, self ) end
function Widget:CreateFontString() return Widget.new( "FontString", nil, self ) end

-- ScrollingMessageFrame
function Widget:AddMessage( text, r, g, b )
	table.insert( self.lines, { text = text, r = r, g = g, b = b } )
end

function Widget:Clear() self.lines = {} end

function Widget:GetNumMessages() return #self.lines end

function Widget:GetFont() return "Fonts\\FRIZQT__.TTF", 12, "" end

M.Widget = Widget

-------------------------------------------------------------------------------
-- Environment
-------------------------------------------------------------------------------

-- Everything the mock installs into the global table, so a test can rebuild a
-- clean "game session" between reloads.
--
-- @param opts.player  Player name (default "Testerman")
-- @param opts.realm   Player realm (default "MoonGuard")
--
function M.Install( opts )
	opts = opts or {}

	M.player = opts.player or "Testerman"
	M.realm  = opts.realm  or "MoonGuard"
	M.frames = {}
	M.chat_output = {}
	M.timers = {}
	M.hooks  = {}
	M.secret = {}
	M.units  = {}

	_G.UIParent = Widget.new( "Frame", "UIParent" )

	_G.CreateFrame = function( kind, name, parent, template )
		local frame = Widget.new( kind, name, parent )
		if name then _G[name] = frame end
		return frame
	end

	_G.time = os.time
	_G.date = os.date

	-- The game's uptime clock. Held still by default so cache expiry is
	-- deterministic; a test that wants time to pass sets WoW.gametime.
	M.gametime = 0
	_G.GetTime = function() return M.gametime end

	_G.DEFAULT_CHAT_FRAME = Widget.new( "Frame", "DefaultChatFrame" )
	_G.DEFAULT_CHAT_FRAME.AddMessage = function( self, text )
		table.insert( M.chat_output, text )
	end

	_G.ChatFontNormal = Widget.new( "Font", "ChatFontNormal" )

	_G.C_AddOns = {
		GetAddOnMetadata = function( addon, field )
			if field == "Version" then return "1.0.0" end
		end;
	}

	_G.C_Timer = {
		After = function( delay, fn )
			table.insert( M.timers, { delay = delay, fn = fn, ticker = false } )
		end;
		NewTicker = function( delay, fn )
			table.insert( M.timers, { delay = delay, fn = fn, ticker = true } )
			return { Cancel = function() end }
		end;
	}

	_G.UnitFullName = function( unit )
		if unit == "player" then return M.player, M.realm end
		local u = M.units[unit]
		if u then return u.name, u.realm end
	end

	_G.UnitName = function( unit )
		if unit == "player" then return M.player, "" end
		local u = M.units[unit]
		if u then return u.name, u.realm end
	end

	_G.UnitExists   = function( unit ) return M.units[unit] ~= nil or unit == "player" end
	_G.UnitIsPlayer = function( unit ) return unit ~= nil end
	_G.UnitGUID     = function( unit )
		if unit == "player" then return "Player-1-PLAYER" end
		local u = M.units[unit]
		return u and u.guid
	end

	_G.GetPlayerInfoByGUID = function( guid )
		local class = M.guid_class and M.guid_class[guid]
		if not class then return nil end
		-- localizedClass, englishClass, ...
		return class:sub(1,1) .. class:sub(2):lower(), class
	end

	_G.GetRealZoneText = function() return M.zone or "Elwynn Forest" end

	_G.ChatTypeInfo = {
		SAY        = { r = 1.0, g = 1.0, b = 1.0 };
		EMOTE      = { r = 1.0, g = 0.5, b = 0.25 };
		TEXT_EMOTE = { r = 1.0, g = 0.5, b = 0.25 };
		YELL       = { r = 1.0, g = 0.25, b = 0.25 };
	}

	_G.RAID_CLASS_COLORS = {
		MAGE   = { r = 0.41, g = 0.8,  b = 0.94, colorStr = "ff3fc7eb" };
		ROGUE  = { r = 1.0,  g = 0.96, b = 0.41, colorStr = "fffff569" };
	}

	_G.SlashCmdList  = {}
	_G.IsShiftKeyDown = function() return false end

	_G.SetItemRef = function( link, text, button, frame )
		for _, hook in ipairs( M.hooks.SetItemRef or {} ) do
			hook( link, text, button, frame )
		end
	end

	_G.hooksecurefunc = function( name, fn )
		M.hooks[name] = M.hooks[name] or {}
		table.insert( M.hooks[name], fn )
	end

	_G.ChatFrame_OpenChat = function() end

	-- Secret value support, off unless a test turns it on.
	_G.issecretvalue = function( value )
		return M.secret[value] == true
	end

	M.InstallMenuMock()
end

-------------------------------------------------------------------------------
-- MenuUtil mock. Captures the menu description tree that the addon builds so
-- tests can inspect entries and "click" them.
-------------------------------------------------------------------------------
function M.InstallMenuMock()
	local Node = {}
	Node.__index = Node

	local function NewNode( kind, text )
		return setmetatable( {
			kind = kind, text = text, children = {}
		}, Node )
	end

	function Node:CreateTitle( text )
		local node = NewNode( "title", text )
		table.insert( self.children, node )
		return node
	end

	function Node:CreateDivider()
		local node = NewNode( "divider" )
		table.insert( self.children, node )
		return node
	end

	function Node:CreateButton( text, func )
		local node = NewNode( "button", text )
		node.func = func
		table.insert( self.children, node )
		return node
	end

	function Node:CreateCheckbox( text, is_selected, set_selected )
		local node = NewNode( "checkbox", text )
		node.checked = is_selected
		node.func    = set_selected
		table.insert( self.children, node )
		return node
	end

	-- Depth first search over the captured tree.
	function Node:Find( pattern )
		for _, child in ipairs( self.children ) do
			if child.text and child.text:find( pattern, 1, true ) then
				return child
			end
			local found = child:Find( pattern )
			if found then return found end
		end
	end

	function Node:Count( kind )
		local count = 0
		for _, child in ipairs( self.children ) do
			if child.kind == kind then count = count + 1 end
			count = count + child:Count( kind )
		end
		return count
	end

	_G.MenuResponse = { Refresh = "refresh", Close = "close" }

	_G.MenuUtil = {
		CreateContextMenu = function( owner, generator )
			local root = NewNode( "root" )
			generator( owner, root )
			M.last_menu = root
			return root
		end;
	}

	_G.Menu = {
		ModifyMenu = function( tag, handler )
			M.unit_menu_handlers = M.unit_menu_handlers or {}
			M.unit_menu_handlers[tag] = handler
		end;
	}

	M.NewMenuNode = NewNode
end

-------------------------------------------------------------------------------
-- Roleplay addon mocks
-------------------------------------------------------------------------------

-- Total RP 3. `profiles` maps "Character-Realm" to a characteristics table,
-- e.g. { FN = "Elowen", LN = "Duskwhisper", CH = "aa66cc", IC = "spell_holy" }.
--
function M.InstallTRP3( profiles )
	M.trp3 = { profiles = profiles or {}, callbacks = {}, ready = true }

	_G.TRP3_API = {
		register = {
			getCharacterList = function()
				return M.trp3.ready and M.trp3.profiles or nil
			end;
			isUnitIDKnown = function( unit_id )
				return M.trp3.profiles[unit_id] ~= nil
			end;
			getUnitIDCurrentProfile = function( unit_id )
				local ch = M.trp3.profiles[unit_id]
				return ch and { characteristics = ch } or nil
			end;
		};

		globals = {
			player_id       = M.player .. "-" .. M.realm;
			player_realm_id = M.realm;
		};

		profile = {
			getData = function()
				local ch = M.trp3.profiles[M.player .. "-" .. M.realm]
				return ch and { characteristics = ch } or nil
			end;
		};

		Events = {
			REGISTER_DATA_UPDATED = "REGISTER_DATA_UPDATED";
			registerCallback = function( event, callback )
				table.insert( M.trp3.callbacks, { event = event, fn = callback } )
			end;
		};
	}
end

-- A profile arriving after the fact, which is the normal case: you hear
-- someone before their profile has been fetched.
--
function M.TRP3AddProfile( unit_id, characteristics )
	M.trp3.profiles[unit_id] = characteristics
end

function M.TRP3FireUpdate()
	for _, entry in ipairs( M.trp3.callbacks ) do
		entry.fn()
	end
end

-- LibMSP, which is what MyRolePlay and XRP populate. `chars` maps a name to
-- its fields, e.g. { NA = "Lady Elowen Duskwhisper" }.
--
function M.InstallMSP( chars )
	local char = {}
	for name, fields in pairs( chars or {} ) do
		char[name] = { supported = true, field = fields }
	end

	_G.msp = { char = char, callback = { received = {} } }
	M.msp = _G.msp
end

function M.MSPFireReceived( name )
	for _, callback in ipairs( M.msp.callback.received ) do
		callback( name )
	end
end

-------------------------------------------------------------------------------
-- Run every one-shot timer that's been scheduled (C_Timer.After), the way the
-- game would once their delay elapsed. Tickers are left alone.
--
function M.RunTimers()
	local pending = M.timers
	M.timers = {}

	for _, timer in ipairs( pending ) do
		if timer.ticker then
			table.insert( M.timers, timer )
		else
			timer.fn()
		end
	end
end

-------------------------------------------------------------------------------
-- Fire an event at every frame that registered for it.
--
function M.FireEvent( event, ... )
	for frame in pairs( M.frames ) do
		if frame.events[event] and frame.scripts.OnEvent then
			frame.scripts.OnEvent( frame, event, ... )
		end
	end
end

-------------------------------------------------------------------------------
-- Convenience: send a chat message as if it came from the server.
--
-- @param event  e.g. "CHAT_MSG_SAY"
-- @param text   Message body.
-- @param sender Sender as the game gives it: "Name" or "Name-Realm".
-- @param guid   Optional sender guid.
--
function M.Say( event, text, sender, guid )
	M.FireEvent( event, text, sender, "Common", "", "", "", 0, 0, "", 0, 1,
	             guid or ("Player-1-" .. sender) )
end

-------------------------------------------------------------------------------
-- Saved variable serialization, mirroring what the game writes to
-- SavedVariables\SayWhat.lua and reads back on the next session.
-------------------------------------------------------------------------------

local function Serialize( value, indent )
	indent = indent or ""

	local t = type( value )
	if t == "string" then
		return string.format( "%q", value )
	elseif t == "number" or t == "boolean" then
		return tostring( value )
	elseif t == "table" then
		local parts = { "{" }
		for k, v in pairs( value ) do
			local key
			if type( k ) == "string" then
				key = "[" .. string.format( "%q", k ) .. "]"
			else
				key = "[" .. tostring( k ) .. "]"
			end
			table.insert( parts, indent .. "\t" .. key .. " = "
			              .. Serialize( v, indent .. "\t" ) .. "," )
		end
		table.insert( parts, indent .. "}" )
		return table.concat( parts, "\n" )
	end

	return "nil"
end

function M.SaveVariables( names )
	local chunks = {}
	for _, name in ipairs( names ) do
		if _G[name] ~= nil then
			table.insert( chunks, name .. " = " .. Serialize( _G[name] ) )
		end
	end
	return table.concat( chunks, "\n" )
end

function M.LoadVariables( text )
	if not text or text == "" then return end
	local chunk = assert( loadstring( text ) )
	chunk()
end

return M
