-------------------------------------------------------------------------------
-- SayWhat - the message log.
--
-- A rolling in-memory buffer of everything we captured this session, selected
-- or not. The Nearby window is rebuilt from this whenever the filter changes,
-- so switching a player on shows what they already said instead of an empty
-- window.
--
-- This is intentionally not saved between sessions: it's a live conversation
-- buffer, not a chat archive.
-------------------------------------------------------------------------------

local ADDON_NAME, Me = ...

Me.Log = {}
local Log = Me.Log

-- How many captured messages we keep around.
local MAX_ENTRIES = 500

Log.entries = {}

-------------------------------------------------------------------------------
function Log.Add( entry )
	local entries = Log.entries
	entries[#entries + 1] = entry

	-- Trim from the front in one pass when we overflow, rather than shifting
	-- the whole table on every single message.
	if #entries > MAX_ENTRIES * 1.2 then
		local trimmed, start = {}, #entries - MAX_ENTRIES + 1
		for i = start, #entries do
			trimmed[#trimmed + 1] = entries[i]
		end
		Log.entries = trimmed
	end
end

-------------------------------------------------------------------------------
-- Everything we have, oldest first.
--
function Log.All()
	return Log.entries
end

-------------------------------------------------------------------------------
function Log.Clear()
	Log.entries = {}
end

-------------------------------------------------------------------------------
-- How many stored messages a given player accounts for.
--
function Log.CountFor( full )
	local count = 0
	for _, entry in ipairs( Log.entries ) do
		if entry.s == full then count = count + 1 end
	end
	return count
end
