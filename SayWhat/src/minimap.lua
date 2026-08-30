-------------------------------------------------------------------------------
-- SayWhat - the minimap button.
--
-- A plain button parented to the minimap: left-click toggles the Nearby
-- window, right-click opens the player selection menu, and dragging moves it
-- around the ring. Its angle is remembered account-wide.
--
-- Hand-rolled rather than pulled from LibDBIcon, so the addon keeps its "no
-- libraries" promise. The layout numbers below are the ones every minimap
-- button uses; they're what makes the icon sit correctly inside the ring art.
--
-- The AddOn Compartment entry (declared in the toc) does the same job for
-- people who prefer it. This is for people who don't.
-------------------------------------------------------------------------------

local ADDON_NAME, Me = ...

Me.Minimap = {}
local MinimapButton = Me.Minimap

-- How far out from the minimap's center the button sits. The minimap is round
-- on modern clients, so a single radius is all we need.
local RADIUS_PADDING = 10

-------------------------------------------------------------------------------
-- Place the button on the ring at the saved angle.
--
function MinimapButton.UpdatePosition()
	local button = MinimapButton.button
	if not button or not Minimap then return end

	local angle  = math.rad( Me.db.settings.minimap.angle )
	local radius = (Minimap:GetWidth() / 2) + RADIUS_PADDING

	button:SetPoint( "CENTER", Minimap, "CENTER",
	                 math.cos( angle ) * radius,
	                 math.sin( angle ) * radius )
end

-------------------------------------------------------------------------------
-- Follow the cursor around the ring while being dragged.
--
local function OnDragUpdate( button )
	local mx, my = Minimap:GetCenter()
	local px, py = GetCursorPosition()

	local scale = Minimap:GetEffectiveScale()
	px, py = px / scale, py / scale

	Me.db.settings.minimap.angle = math.deg( math.atan2( py - my, px - mx ) )
	MinimapButton.UpdatePosition()
end

-------------------------------------------------------------------------------
local function OnEnter( button )
	GameTooltip:SetOwner( button, "ANCHOR_LEFT" )
	GameTooltip:AddLine( "SayWhat" )
	GameTooltip:AddLine( string.format(
		"|cffffffff%d|r selected, |cffffffff%d|r in range",
		Me.SelectedCount(), Me.Roster.NearbyCount() ), 0.7, 0.7, 0.7 )
	GameTooltip:AddLine( " " )
	GameTooltip:AddLine( "|cffffff00Left-click|r toggle the Nearby window", 1, 1, 1 )
	GameTooltip:AddLine( "|cffffff00Right-click|r pick nearby players", 1, 1, 1 )
	GameTooltip:AddLine( "|cffffff00Drag|r move this button", 1, 1, 1 )
	GameTooltip:Show()
end

-------------------------------------------------------------------------------
function MinimapButton.Create()
	if MinimapButton.button then return MinimapButton.button end
	if not Minimap then return end

	local button = CreateFrame( "Button", "SayWhatMinimapButton", Minimap )
	MinimapButton.button = button

	button:SetSize( 31, 31 )
	button:SetFrameStrata( "MEDIUM" )
	button:SetFrameLevel( 8 )
	button:RegisterForClicks( "LeftButtonUp", "RightButtonUp" )
	button:RegisterForDrag( "LeftButton" )
	button:SetMovable( true )

	local background = button:CreateTexture( nil, "BACKGROUND" )
	background:SetSize( 20, 20 )
	background:SetPoint( "TOPLEFT", 7, -5 )
	background:SetTexture( "Interface\\Minimap\\UI-Minimap-Background" )

	local icon = button:CreateTexture( nil, "ARTWORK" )
	icon:SetSize( 17, 17 )
	icon:SetPoint( "TOPLEFT", 7, -6 )
	icon:SetTexture( "Interface\\Icons\\INV_Misc_Ear_Human_01" )
	button.icon = icon

	-- The ring that makes it look like a minimap button. It's deliberately
	-- larger than the button and anchored at the corner.
	local border = button:CreateTexture( nil, "OVERLAY" )
	border:SetSize( 53, 53 )
	border:SetPoint( "TOPLEFT" )
	border:SetTexture( "Interface\\Minimap\\MiniMap-TrackingBorder" )

	button:SetHighlightTexture(
		"Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight" )

	button:SetScript( "OnClick", function( self, click )
		if click == "RightButton" then
			Me.Menu.OpenPlayerSelect( self )
		else
			Me.Window.Toggle()
		end
	end)

	button:SetScript( "OnDragStart", function( self )
		self:SetScript( "OnUpdate", OnDragUpdate )
		GameTooltip:Hide()
	end)

	button:SetScript( "OnDragStop", function( self )
		self:SetScript( "OnUpdate", nil )
	end)

	button:SetScript( "OnEnter", OnEnter )
	button:SetScript( "OnLeave", function() GameTooltip:Hide() end )

	MinimapButton.UpdatePosition()
	MinimapButton.ApplySettings()

	return button
end

-------------------------------------------------------------------------------
function MinimapButton.ApplySettings()
	local button = MinimapButton.button
	if not button then return end

	button:SetShown( Me.db.settings.minimap.show and true or false )
	MinimapButton.UpdatePosition()
end

-------------------------------------------------------------------------------
-- @param show true to show the button, false to hide it, nil to flip it.
--
function MinimapButton.SetShown( show )
	local settings = Me.db.settings.minimap
	if show == nil then show = not settings.show end

	settings.show = show and true or false
	MinimapButton.ApplySettings()
	return settings.show
end
