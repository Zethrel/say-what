-------------------------------------------------------------------------------
-- SayWhat - clickable chat links.
--
-- The list command prints the roster with [+] / [-] buttons next to each name, so you
-- can manage the filter straight from the chat window without retyping names.
--
-- Custom link types printed into a chat frame end up in SetItemRef, which we
-- hook to catch our own.
-------------------------------------------------------------------------------

local ADDON_NAME, Me = ...

Me.Links = {}
local Links = Me.Links

local LINK_COLOR = "|cff4fd1c5"

-------------------------------------------------------------------------------
-- @param action "add", "remove" or "toggle"
--
function Links.Make( action, full, label )
	return LINK_COLOR .. "|Hsaywhat:" .. action .. ":" .. full .. "|h["
	       .. label .. "]|h|r"
end

-------------------------------------------------------------------------------
-- The [+] or [-] button for a player, whichever applies right now.
--
function Links.Toggle( full )
	if Me.IsSelected( full ) then
		return Links.Make( "remove", full, "-" )
	end
	return Links.Make( "add", full, "+" )
end

-------------------------------------------------------------------------------
function Links.OnClick( link )
	local action, full = link:match( "^saywhat:([^:]+):(.+)$" )
	if not action then return false end

	if action == "add" then
		if Me.SetSelected( full, true ) then
			Me.Print( "Added %s.", Me.ColorName( full ) )
		end
	elseif action == "remove" then
		if Me.SetSelected( full, false ) then
			Me.Print( "Removed %s.", Me.ColorName( full ) )
		end
	elseif action == "toggle" then
		local state = Me.ToggleSelected( full )
		Me.Print( state and "Added %s." or "Removed %s.", Me.ColorName( full ) )
	end

	return true
end

-------------------------------------------------------------------------------
if hooksecurefunc and _G.SetItemRef then
	hooksecurefunc( "SetItemRef", function( link )
		if type( link ) == "string" and link:sub( 1, 8 ) == "saywhat:" then
			Links.OnClick( link )
		end
	end)
end
