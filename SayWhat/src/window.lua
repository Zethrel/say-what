-------------------------------------------------------------------------------
-- SayWhat - the Nearby window.
--
-- A small movable, resizable chat window that shows only the players you have
-- selected from the nearby roster. Clicking a name in it opens that player's
-- menu, so you can drop someone without touching a slash command.
-------------------------------------------------------------------------------

local ADDON_NAME, Me = ...

Me.Window = {}
local Window = Me.Window

-- Chat lines the window keeps before it starts dropping the oldest.
local CHAT_BUFFER_SIZE = 500

local MIN_WIDTH, MIN_HEIGHT = 220, 120
local MIN_FONT, MAX_FONT    = 8, 24

-------------------------------------------------------------------------------
-- Message prefixes, matching how the default chat frame reads.
--
local PREFIX = {
	YELL = "[Yell] ";
}

-------------------------------------------------------------------------------
-- Color for an entry, taken from the player's own chat color settings.
--
local function EntryColor( entry )
	local info = ChatTypeInfo and ChatTypeInfo[entry.e]
	if not info then info = ChatTypeInfo and ChatTypeInfo.SAY end
	if not info then return 1, 1, 1 end
	return info.r, info.g, info.b
end

-------------------------------------------------------------------------------
-- A clickable name. Custom link, handled by the window's hyperlink script.
--
local function NameLink( full )
	return "|Hsaywhatname:" .. full .. "|h" .. Me.ColorName( full ) .. "|h"
end

-------------------------------------------------------------------------------
-- Turn a log entry into the line we print.
--
function Window.FormatEntry( entry )
	local stamp = ""
	if Me.db.settings.timestamps then
		stamp = "|cff808080" .. date( "%H:%M", entry.t ) .. "|r "
	end

	local name = NameLink( entry.s )
	local body

	if entry.e == "EMOTE" then
		-- "Name waves." - no separator, unless the emote starts with a
		-- possessive or a comma, which roleplay addons lean on.
		local lead = entry.m:sub( 1, 2 )
		if lead == "'s" or lead == ", " then
			body = name .. entry.m
		else
			body = name .. " " .. entry.m
		end

	elseif entry.e == "TEXT_EMOTE" then
		-- The player's name is already inside the message text; swap it for
		-- the clickable, colored version.
		local pattern = entry.s:gsub( "([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1" )
		local short   = Me.ShortName( entry.s )
		local shortpat= short:gsub( "([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1" )

		-- The replacement string is a gsub replacement, so any % in it would
		-- be read as a capture reference.
		local replacement = name:gsub( "%%", "%%%%" )

		body = entry.m:gsub( pattern, replacement, 1 )
		if body == entry.m then
			body = entry.m:gsub( shortpat, replacement, 1 )
		end
		if body == entry.m then
			body = name .. " " .. entry.m
		end

	else
		body = (PREFIX[entry.e] or "") .. name .. ": " .. entry.m
	end

	return stamp .. body
end

-------------------------------------------------------------------------------
-- Frame construction
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
local function MakeButton( parent, text, width )
	local button = CreateFrame( "Button", nil, parent )
	button:SetSize( width, 14 )

	local label = button:CreateFontString( nil, "OVERLAY", "GameFontNormalSmall" )
	label:SetAllPoints()
	label:SetText( text )
	button.label = label

	local highlight = button:CreateTexture( nil, "HIGHLIGHT" )
	highlight:SetAllPoints()
	highlight:SetColorTexture( 1, 1, 1, 0.15 )

	return button
end

-------------------------------------------------------------------------------
function Window.Create()
	if Window.frame then return Window.frame end

	local settings = Me.db.settings
	local layout   = settings.window

	local frame = CreateFrame( "Frame", "SayWhatNearbyFrame", UIParent )
	Window.frame = frame

	frame:SetSize( layout.width, layout.height )
	frame:SetPoint( layout.point, UIParent, layout.relpoint, layout.x, layout.y )
	frame:SetMovable( true )
	frame:SetResizable( true )
	frame:SetClampedToScreen( true )
	frame:EnableMouse( true )
	frame:SetFrameStrata( "LOW" )
	frame:Hide()

	if frame.SetResizeBounds then
		frame:SetResizeBounds( MIN_WIDTH, MIN_HEIGHT )
	elseif frame.SetMinResize then
		frame:SetMinResize( MIN_WIDTH, MIN_HEIGHT )
	end

	local bg = frame:CreateTexture( nil, "BACKGROUND" )
	bg:SetAllPoints()
	bg:SetColorTexture( 0, 0, 0, 0.4 )
	frame.bg = bg

	---------------------------------------------------------------------------
	-- Title bar: drag handle, title, player menu button, close button.
	---------------------------------------------------------------------------
	local bar = CreateFrame( "Frame", nil, frame )
	bar:SetPoint( "TOPLEFT" )
	bar:SetPoint( "TOPRIGHT" )
	bar:SetHeight( 16 )
	bar:EnableMouse( true )
	frame.bar = bar

	local barbg = bar:CreateTexture( nil, "BACKGROUND" )
	barbg:SetAllPoints()
	barbg:SetColorTexture( 0, 0, 0, 0.5 )

	local title = bar:CreateFontString( nil, "OVERLAY", "GameFontNormalSmall" )
	title:SetPoint( "LEFT", 4, 0 )
	title:SetText( "Nearby" )
	frame.title = title

	local close = MakeButton( bar, "|cffff8080X|r", 16 )
	close:SetPoint( "RIGHT", -2, 0 )
	close:SetScript( "OnClick", function() Window.Hide() end )

	local players = MakeButton( bar, "Players", 52 )
	players:SetPoint( "RIGHT", close, "LEFT", -2, 0 )
	players:SetScript( "OnClick", function( self )
		Me.Menu.OpenPlayerSelect( self )
	end)
	frame.players_button = players

	bar:SetScript( "OnMouseDown", function()
		if not Me.db.settings.locked then frame:StartMoving() end
	end)
	bar:SetScript( "OnMouseUp", function()
		frame:StopMovingOrSizing()
		Window.SaveLayout()
	end)

	---------------------------------------------------------------------------
	-- The chat box.
	---------------------------------------------------------------------------
	local chat = CreateFrame( "ScrollingMessageFrame", nil, frame )
	chat:SetPoint( "TOPLEFT", 4, -18 )
	chat:SetPoint( "BOTTOMRIGHT", -4, 4 )
	chat:SetJustifyH( "LEFT" )
	chat:SetFading( false )
	chat:SetMaxLines( CHAT_BUFFER_SIZE )
	chat:SetIndentedWordWrap( true )
	chat:EnableMouseWheel( true )
	chat:SetHyperlinksEnabled( true )
	frame.chat = chat

	chat:SetScript( "OnMouseWheel", function( self, delta )
		if delta > 0 then
			if IsShiftKeyDown() then self:ScrollToTop() else self:ScrollUp() end
		else
			if IsShiftKeyDown() then self:ScrollToBottom() else self:ScrollDown() end
		end
	end)

	chat:SetScript( "OnHyperlinkClick", function( self, link, text, button )
		local name = link:match( "^saywhatname:(.+)$" )
		if name then
			Me.Menu.OpenPlayer( self, name )
			return
		end
		if SetItemRef then SetItemRef( link, text, button, self ) end
	end)

	---------------------------------------------------------------------------
	-- Resize grip.
	---------------------------------------------------------------------------
	local grip = CreateFrame( "Button", nil, frame )
	grip:SetSize( 12, 12 )
	grip:SetPoint( "BOTTOMRIGHT", -1, 1 )
	grip:SetNormalTexture( "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up" )
	grip:SetHighlightTexture( "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight" )
	grip:SetPushedTexture( "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down" )
	frame.grip = grip

	grip:SetScript( "OnMouseDown", function()
		if not Me.db.settings.locked then frame:StartSizing( "BOTTOMRIGHT" ) end
	end)
	grip:SetScript( "OnMouseUp", function()
		frame:StopMovingOrSizing()
		Window.SaveLayout()
	end)

	-- Right-clicking anywhere in the window opens the player menu too.
	frame:SetScript( "OnMouseUp", function( self, button )
		if button == "RightButton" then
			Me.Menu.OpenPlayerSelect( self )
		end
	end)

	Window.ApplySettings()
	Window.Refresh()

	return frame
end

-------------------------------------------------------------------------------
-- Options that affect the frame itself.
--
function Window.ApplySettings()
	local frame = Window.frame
	if not frame then return end

	local settings = Me.db.settings

	-- A ScrollingMessageFrame built without a template has no font of its own,
	-- and AddMessage throws without one.
	local font = (ChatFontNormal and ChatFontNormal:GetFont())
	             or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
	frame.chat:SetFont( font, settings.font_size, "" )

	frame.grip:SetShown( not settings.locked )
	Window.UpdateTitle()
end

-------------------------------------------------------------------------------
function Window.AdjustFontSize( delta )
	local settings = Me.db.settings
	settings.font_size = math.max( MIN_FONT,
	                     math.min( MAX_FONT, settings.font_size + delta ))
	Window.ApplySettings()
	Window.Refresh()
end

-------------------------------------------------------------------------------
function Window.SaveLayout()
	local frame = Window.frame
	if not frame then return end

	local point, _, relpoint, x, y = frame:GetPoint()
	local layout = Me.db.settings.window

	layout.point    = point    or "CENTER"
	layout.relpoint = relpoint or "CENTER"
	layout.x        = x or 0
	layout.y        = y or 0
	layout.width    = frame:GetWidth()
	layout.height   = frame:GetHeight()
end

-------------------------------------------------------------------------------
function Window.UpdateTitle()
	local frame = Window.frame
	if not frame then return end

	frame.title:SetText( string.format( "Nearby |cff808080(%d selected, %d in range)|r",
	                     Me.SelectedCount(), Me.Roster.NearbyCount() ))
end

-------------------------------------------------------------------------------
-- Show / hide
-------------------------------------------------------------------------------

function Window.Show()
	local frame = Window.Create()
	frame:Show()
	Me.db.settings.window.shown = true
	Window.UpdateTitle()
end

function Window.Hide()
	if not Window.frame then return end
	Window.SaveLayout()
	Window.frame:Hide()
	Me.db.settings.window.shown = false
end

function Window.IsShown()
	return Window.frame and Window.frame:IsShown() and true or false
end

function Window.Toggle()
	if Window.IsShown() then Window.Hide() else Window.Show() end
end

-------------------------------------------------------------------------------
-- Messages
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- Print an entry into the window, no filtering.
--
function Window.AddMessage( entry )
	local frame = Window.frame
	if not frame then return end

	local r, g, b = EntryColor( entry )
	frame.chat:AddMessage( Window.FormatEntry( entry ), r, g, b )
end

-------------------------------------------------------------------------------
-- A new message came in: show it if it passes the filter.
--
function Window.TryAddMessage( entry )
	if not Window.frame then return end
	if not Me.ShouldDisplay( entry ) then return end

	if Window.showing_hint then
		-- The window is showing the "nothing here yet" note. Rebuilding drops
		-- it and prints the backlog, this message included.
		Window.Refresh()
	else
		Window.AddMessage( entry )
	end

	if Me.db.settings.auto_show and not Window.IsShown() then
		Window.Show()
	end
end

-------------------------------------------------------------------------------
-- Rebuild the whole window from the log. Called whenever the filter changes,
-- so turning a player on brings their earlier messages along.
--
function Window.Refresh()
	local frame = Window.frame
	if not frame then return end

	frame.chat:Clear()

	local shown = 0
	for _, entry in ipairs( Me.Log.All() ) do
		if Me.ShouldDisplay( entry ) then
			Window.AddMessage( entry )
			shown = shown + 1
		end
	end

	Window.showing_hint = (shown == 0)

	if shown == 0 then
		if Me.SelectedCount() == 0 then
			frame.chat:AddMessage(
				"|cff808080No players selected. Click |rPlayers|cff808080 above, " ..
				"or use |r/sw add <name>|cff808080.|r", 0.7, 0.7, 0.7 )
		else
			frame.chat:AddMessage(
				"|cff808080Nothing heard from your selection yet.|r", 0.7, 0.7, 0.7 )
		end
	end

	Window.UpdateTitle()
end
