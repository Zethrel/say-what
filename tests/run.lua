-------------------------------------------------------------------------------
-- SayWhat test suite.
--
-- Loads the addon against a mock of the WoW API and exercises the behavior
-- that can't be eyeballed reliably in-game: what counts as "in range", how
-- names are keyed, what the window shows, and whether the selection really
-- survives a reload.
--
-- Run with:  lua5.1 tests/run.lua      (from the repository root)
-------------------------------------------------------------------------------

local ROOT = (arg and arg[0] and arg[0]:match( "^(.*)tests[/\\]run%.lua$" )) or "./"

-- The addon folder has to be named after its toc, so it lives in a subfolder
-- of the repository rather than at the root.
local ADDON = ROOT .. "SayWhat/"

local WoW = dofile( ROOT .. "tests/wowmock.lua" )

-------------------------------------------------------------------------------
-- Tiny test harness
-------------------------------------------------------------------------------
local tests, failures, current = {}, 0, nil

local function test( name, fn )
	table.insert( tests, { name = name, fn = fn } )
end

local function fail( message )
	failures = failures + 1
	print( string.format( "  FAIL %s\n       %s", current, message ) )
	error( { silent = true }, 0 )
end

local function check( condition, message )
	if not condition then fail( message or "assertion failed" ) end
end

local function equals( actual, expected, message )
	if actual ~= expected then
		fail( string.format( "%s\n       expected: %s\n       actual:   %s",
		      message or "values differ", tostring( expected ), tostring( actual ) ))
	end
end

-------------------------------------------------------------------------------
-- Session management
-------------------------------------------------------------------------------

-- The load order out of the TOC.
local function LoadOrder()
	local files = {}
	local toc = assert( io.open( ADDON .. "SayWhat.toc" ), "SayWhat.toc not found" )
	for line in toc:lines() do
		line = line:gsub( "\r", "" )
		if line:match( "%.lua%s*$" ) and not line:match( "^%s*#" ) then
			table.insert( files, (line:gsub( "\\", "/" ):gsub( "%s+$", "" )) )
		end
	end
	toc:close()
	assert( #files > 0, "no lua files listed in the toc" )
	return files
end

local FILES = LoadOrder()

-- Start a game session: fresh environment, saved variables restored from the
-- previous session's "SavedVariables file", addon loaded, player logged in.
local function StartSession( saved, opts )
	for _, name in ipairs({ "SayWhat", "SayWhatDB", "SayWhatCharDB",
	                        "SayWhatNearbyFrame", "SayWhat_OnCompartmentClick",
	                        "TRP3_API", "msp" }) do
		_G[name] = nil
	end

	for index = 1, 5 do _G["SLASH_SAYWHAT" .. index] = nil end

	WoW.Install( opts )

	-- Roleplay addons load before we do, so install them before login for the
	-- tests that care about our profile-update hooks.
	if opts and opts.trp3 then WoW.InstallTRP3( opts.trp3 ) end
	if opts and opts.msp  then WoW.InstallMSP( opts.msp )   end

	WoW.LoadVariables( saved )

	local Me = {}
	for _, file in ipairs( FILES ) do
		local chunk = assert( loadfile( ADDON .. file ) )
		chunk( "SayWhat", Me )
	end

	WoW.FireEvent( "ADDON_LOADED", "SayWhat" )
	WoW.FireEvent( "PLAYER_LOGIN" )

	return Me
end

-- Load the addon into an environment a test has already set up (used by the
-- slash command tests, which register other addons' commands first).
local function StartSessionWithExisting()
	local Me = {}
	for _, file in ipairs( FILES ) do
		local chunk = assert( loadfile( ADDON .. file ) )
		chunk( "SayWhat", Me )
	end

	WoW.FireEvent( "ADDON_LOADED", "SayWhat" )
	WoW.FireEvent( "PLAYER_LOGIN" )
	return Me
end

-- What the game would write to disk when you log out or reload.
local function SaveSession()
	return WoW.SaveVariables({ "SayWhatDB", "SayWhatCharDB" })
end

-- Strip hyperlink and color escapes so assertions can read like the text a
-- player sees, rather than the markup underneath it.
local function Readable( text )
	text = text:gsub( "|H.-|h", "" )      -- opening link tag, e.g. |Hsaywhatname:X|h
	text = text:gsub( "|h", "" )          -- its closing tag
	text = text:gsub( "|c%x%x%x%x%x%x%x%x", "" )
	text = text:gsub( "|r", "" )
	return text
end

-- Text of every line currently in the Nearby window, as it reads on screen.
local function WindowLines( Me )
	local lines = {}
	for _, line in ipairs( Me.Window.frame.chat.lines ) do
		table.insert( lines, Readable( line.text ) )
	end
	return lines
end

local function WindowHas( Me, text )
	for _, line in ipairs( WindowLines( Me ) ) do
		if line:find( text, 1, true ) then return true end
	end
	return false
end

local function Command( Me, text )
	SlashCmdList["SAYWHAT"]( text )
end

-------------------------------------------------------------------------------
-- Range behavior
-------------------------------------------------------------------------------

test( "a /say message puts the sender on the nearby roster", function()
	local Me = StartSession()
	WoW.Say( "CHAT_MSG_SAY", "hello there", "Alice" )

	check( Me.chardb.roster["Alice-MoonGuard"], "Alice should be on the roster" )
	equals( Me.chardb.roster["Alice-MoonGuard"].count, 1, "message count" )
	check( Me.Roster.IsNearby( "Alice-MoonGuard" ), "Alice should count as in range" )
	equals( Me.Roster.NearbyCount(), 1, "nearby count" )
end)

test( "a /yell does not count as being in say range", function()
	local Me = StartSession()
	WoW.Say( "CHAT_MSG_YELL", "HELLO", "Yeller" )

	check( not Me.chardb.roster["Yeller-MoonGuard"],
	       "yell carries ~300 yards, it must not mark someone as nearby" )
	equals( #Me.Log.All(), 1, "the yell is still captured in the log" )
end)

test( "emotes count as nearby once tracking is turned on", function()
	local Me = StartSession()
	Me.db.settings.track_events.EMOTE = true

	WoW.Say( "CHAT_MSG_EMOTE", "waves.", "Emoter" )
	check( Me.chardb.roster["Emoter-MoonGuard"], "emote should be tracked now" )
end)

test( "our own messages never land on the roster", function()
	local Me = StartSession()
	WoW.Say( "CHAT_MSG_SAY", "talking to myself", "Testerman" )

	check( not Me.chardb.roster["Testerman-MoonGuard"],
	       "you are not one of the nearby players" )
	equals( #Me.Log.All(), 1, "but the message is logged" )
end)

test( "a player stops being in range after the timeout, but stays known", function()
	local Me = StartSession()
	WoW.Say( "CHAT_MSG_SAY", "hello", "Alice" )

	-- Rewind their last-heard time past the nearby timeout.
	local entry = Me.chardb.roster["Alice-MoonGuard"]
	entry.last = entry.last - (Me.db.settings.nearby_timeout + 60)

	check( not Me.Roster.IsNearby( "Alice-MoonGuard" ), "should no longer be in range" )
	equals( Me.Roster.NearbyCount(), 0, "nearby count" )
	equals( #Me.Roster.List(), 1, "still listed so you can manage them" )
end)

test( "stale unselected players are pruned, selected ones are kept", function()
	local Me = StartSession()
	WoW.Say( "CHAT_MSG_SAY", "hello", "Alice" )
	WoW.Say( "CHAT_MSG_SAY", "hello", "Bob" )
	Me.SetSelected( "Bob-MoonGuard", true )

	local ancient = os.time() - (Me.db.settings.roster_expiry + 3600)
	Me.chardb.roster["Alice-MoonGuard"].last = ancient
	Me.chardb.roster["Bob-MoonGuard"].last   = ancient

	Me.Roster.Prune()

	check( not Me.chardb.roster["Alice-MoonGuard"], "Alice should be forgotten" )
	check( Me.chardb.roster["Bob-MoonGuard"], "a selected player is never forgotten" )
end)

-------------------------------------------------------------------------------
-- Player names
-------------------------------------------------------------------------------

test( "same-realm and cross-realm senders key on distinct full names", function()
	local Me = StartSession()
	WoW.Say( "CHAT_MSG_SAY", "hi from home", "Alice" )
	WoW.Say( "CHAT_MSG_SAY", "hi from away", "Alice-WyrmrestAccord" )

	check( Me.chardb.roster["Alice-MoonGuard"], "local Alice" )
	check( Me.chardb.roster["Alice-WyrmrestAccord"], "cross-realm Alice" )
	equals( Me.ShortName( "Alice-MoonGuard" ), "Alice", "own realm is hidden" )
	equals( Me.ShortName( "Alice-WyrmrestAccord" ), "Alice-WyrmrestAccord",
	        "other realms stay visible" )
end)

test( "a text emote recovers the realm from the message body", function()
	local Me = StartSession()
	Me.db.settings.track_events.TEXT_EMOTE = true

	-- The game hands us the sender without a realm for text emotes.
	WoW.FireEvent( "CHAT_MSG_TEXT_EMOTE", "Dan-WyrmrestAccord waves at you.",
	               "Dan", "Common", "", "", "", 0, 0, "", 0, 1, "Player-1-Dan" )

	check( Me.chardb.roster["Dan-WyrmrestAccord"],
	       "the realm should be recovered so text emotes key like says" )
	check( not Me.chardb.roster["Dan-MoonGuard"], "and not be filed under our realm" )
end)

test( "names typed in any case resolve to the right player", function()
	local Me = StartSession()
	WoW.Say( "CHAT_MSG_SAY", "hello", "Alice-WyrmrestAccord" )

	equals( Me.ResolveName( "alice-wyrmrestaccord" ), "Alice-WyrmrestAccord", "lowercase" )
	equals( Me.ResolveName( "ALICE-WyrmrestAccord" ), "Alice-WyrmrestAccord", "uppercase" )
	equals( Me.ResolveName( "bob" ), "Bob-MoonGuard", "unknown names assume our realm" )
	equals( Me.ResolveName( "|Hplayer:Carol-Ravenholdt|h[Carol]|h" ), "Carol-Ravenholdt",
	        "a player link resolves to the linked name" )
end)

-------------------------------------------------------------------------------
-- Filtering
-------------------------------------------------------------------------------

test( "the window shows only selected players", function()
	local Me = StartSession()
	Me.Window.Show()

	WoW.Say( "CHAT_MSG_SAY", "alpha", "Alice" )
	WoW.Say( "CHAT_MSG_SAY", "bravo", "Bob" )

	Me.SetSelected( "Alice-MoonGuard", true )

	check( WindowHas( Me, "alpha" ), "Alice is selected, her line should be there" )
	check( not WindowHas( Me, "bravo" ), "Bob is not selected" )

	WoW.Say( "CHAT_MSG_SAY", "charlie", "Bob" )
	check( not WindowHas( Me, "charlie" ), "new messages from Bob stay filtered out" )

	WoW.Say( "CHAT_MSG_SAY", "delta", "Alice" )
	check( WindowHas( Me, "delta" ), "new messages from Alice come through live" )
end)

test( "selecting a player pulls in what they already said", function()
	local Me = StartSession()
	Me.Window.Show()

	WoW.Say( "CHAT_MSG_SAY", "said this before you picked me", "Alice" )
	check( not WindowHas( Me, "said this before" ), "not shown yet" )

	Me.SetSelected( "Alice-MoonGuard", true )
	check( WindowHas( Me, "said this before" ),
	       "the window is rebuilt from the log when the filter changes" )

	Me.SetSelected( "Alice-MoonGuard", false )
	check( not WindowHas( Me, "said this before" ), "and cleaned up when removed" )
end)

test( "same name on another realm does not leak through the filter", function()
	local Me = StartSession()
	Me.Window.Show()
	Me.SetSelected( "Alice-MoonGuard", true )

	WoW.Say( "CHAT_MSG_SAY", "local alice", "Alice" )
	WoW.Say( "CHAT_MSG_SAY", "impostor alice", "Alice-WyrmrestAccord" )

	check( WindowHas( Me, "local alice" ), "the selected Alice shows" )
	check( not WindowHas( Me, "impostor alice" ), "the other realm's Alice does not" )
end)

test( "event types control what the window displays", function()
	local Me = StartSession()
	Me.Window.Show()
	Me.SetSelected( "Alice-MoonGuard", true )

	WoW.Say( "CHAT_MSG_SAY", "spoken", "Alice" )
	WoW.Say( "CHAT_MSG_YELL", "yelled", "Alice" )

	check( WindowHas( Me, "spoken" ), "say is shown by default" )
	check( not WindowHas( Me, "yelled" ), "yell is hidden by default" )

	Me.db.settings.show_events.YELL = true
	Me.Window.Refresh()
	check( WindowHas( Me, "yelled" ), "turning yell on brings it back from the log" )
end)

test( "your own chat follows the include_self option", function()
	local Me = StartSession()
	Me.Window.Show()

	WoW.Say( "CHAT_MSG_SAY", "my own words", "Testerman" )
	check( WindowHas( Me, "my own words" ), "shown by default" )

	Me.db.settings.include_self = false
	Me.Window.Refresh()
	check( not WindowHas( Me, "my own words" ), "hidden when the option is off" )
end)

test( "the empty window hint is replaced by the first real message", function()
	local Me = StartSession()
	Me.Window.Show()

	check( WindowHas( Me, "No players selected" ), "the hint is up" )

	Me.SetSelected( "Alice-MoonGuard", true )
	check( WindowHas( Me, "Nothing heard" ), "hint changes once someone is picked" )

	WoW.Say( "CHAT_MSG_SAY", "first words", "Alice" )
	check( WindowHas( Me, "first words" ), "the message shows" )
	check( not WindowHas( Me, "Nothing heard" ), "and the hint is gone" )
end)

test( "message formatting matches the chat type", function()
	local Me = StartSession()

	local say = Me.Window.FormatEntry({ t = os.time(), e = "SAY",
	                                    s = "Alice-MoonGuard", m = "hello" })
	check( say:find( "Alice", 1, true ), "the name is in there" )
	check( say:find( ": hello", 1, true ), "say uses name: text" )

	local emote = Me.Window.FormatEntry({ t = os.time(), e = "EMOTE",
	                                      s = "Alice-MoonGuard", m = "waves." })
	check( emote:find( "Alice|h waves.", 1, true ), "emote has no colon separator" )

	local possessive = Me.Window.FormatEntry({ t = os.time(), e = "EMOTE",
	                                           s = "Alice-MoonGuard", m = "'s hat falls off." })
	check( possessive:find( "Alice|h's hat", 1, true ), "possessive emotes keep no space" )

	local text_emote = Me.Window.FormatEntry({ t = os.time(), e = "TEXT_EMOTE",
	                                           s = "Alice-MoonGuard",
	                                           m = "Alice waves at you." })
	check( text_emote:find( "waves at you.", 1, true ), "the emote body survives" )
	check( not text_emote:find( "Alice waves", 1, true ),
	       "the plain name was replaced by the clickable one" )
end)

test( "messages we are not allowed to read are dropped", function()
	local Me = StartSession()
	local secret = "secret payload"
	WoW.secret[secret] = true

	WoW.Say( "CHAT_MSG_SAY", secret, "Ghost" )

	equals( #Me.Log.All(), 0, "a secret message is not logged" )
	check( not Me.chardb.roster["Ghost-MoonGuard"], "and does not create a roster entry" )
end)

-------------------------------------------------------------------------------
-- Persistence
-------------------------------------------------------------------------------

test( "the selection survives a reload", function()
	local Me = StartSession()
	WoW.Say( "CHAT_MSG_SAY", "hello", "Alice" )
	WoW.Say( "CHAT_MSG_SAY", "hello", "Bob-WyrmrestAccord" )
	Me.SetSelected( "Alice-MoonGuard", true )
	Me.SetSelected( "Bob-WyrmrestAccord", true )

	local saved = SaveSession()

	Me = StartSession( saved )

	check( Me.IsSelected( "Alice-MoonGuard" ), "Alice is still selected" )
	check( Me.IsSelected( "Bob-WyrmrestAccord" ), "cross-realm Bob is still selected" )
	equals( Me.SelectedCount(), 2, "selection count" )

	-- And the filter still works on the fresh session.
	Me.Window.Show()
	WoW.Say( "CHAT_MSG_SAY", "after reload", "Alice" )
	WoW.Say( "CHAT_MSG_SAY", "not me", "Carol" )

	check( WindowHas( Me, "after reload" ), "selected player still passes the filter" )
	check( not WindowHas( Me, "not me" ), "unselected player still filtered" )
end)

test( "the roster and window layout survive a reload", function()
	local Me = StartSession()
	WoW.Say( "CHAT_MSG_SAY", "hello", "Alice" )
	Me.Window.Show()
	Me.db.settings.window.width = 640
	Me.db.settings.font_size    = 15

	local saved = SaveSession()
	Me = StartSession( saved )

	check( Me.chardb.roster["Alice-MoonGuard"], "roster entry persisted" )
	equals( Me.db.settings.window.width, 640, "window width persisted" )
	equals( Me.db.settings.font_size, 15, "font size persisted" )
	check( Me.Window.IsShown(), "a window left open reopens on load" )
end)

test( "the message log does not persist, the filter still does", function()
	local Me = StartSession()
	Me.SetSelected( "Alice-MoonGuard", true )
	WoW.Say( "CHAT_MSG_SAY", "before the reload", "Alice" )

	local saved = SaveSession()
	check( not saved:find( "before the reload", 1, true ),
	       "chat text is a live buffer, it should never be written to disk" )

	Me = StartSession( saved )
	Me.Window.Show()

	equals( #Me.Log.All(), 0, "the log starts empty" )
	check( Me.IsSelected( "Alice-MoonGuard" ), "but the filter is intact" )
end)

test( "relogging on another character keeps its own selection", function()
	local Me = StartSession()
	WoW.Say( "CHAT_MSG_SAY", "hello", "Alice" )
	Me.SetSelected( "Alice-MoonGuard", true )
	Me.db.settings.font_size = 16

	-- Account-wide settings carry over; the per-character file does not.
	local account_saved = WoW.SaveVariables({ "SayWhatDB" })

	Me = StartSession( account_saved, { player = "Alt", realm = "MoonGuard" } )

	equals( Me.SelectedCount(), 0, "the alt starts with an empty selection" )
	equals( Me.db.settings.font_size, 16, "but shares the account-wide settings" )
end)

test( "an older saved variable file picks up new defaults", function()
	local Me = StartSession()
	-- Pretend this is what an earlier version wrote: a partial table.
	local saved = [[
		SayWhatDB = { ["settings"] = { ["font_size"] = 9 } }
		SayWhatCharDB = { ["selected"] = { ["Alice-MoonGuard"] = true } }
	]]

	Me = StartSession( saved )

	equals( Me.db.settings.font_size, 9, "existing values are kept" )
	equals( Me.db.settings.nearby_timeout, 300, "missing values get defaults" )
	check( type( Me.db.settings.show_events ) == "table", "missing tables are created" )
	check( Me.IsSelected( "Alice-MoonGuard" ), "the old selection is intact" )
	check( type( Me.chardb.roster ) == "table", "a missing roster is created" )
end)

-------------------------------------------------------------------------------
-- Commands, menu and links
-------------------------------------------------------------------------------

test( "slash commands add, remove and toggle players", function()
	local Me = StartSession()
	WoW.Say( "CHAT_MSG_SAY", "hello", "Alice" )

	Command( Me, "add alice" )
	check( Me.IsSelected( "Alice-MoonGuard" ), "add" )

	Command( Me, "remove Alice" )
	check( not Me.IsSelected( "Alice-MoonGuard" ), "remove" )

	Command( Me, "toggle alice" )
	check( Me.IsSelected( "Alice-MoonGuard" ), "toggle on" )

	Command( Me, "toggle alice" )
	check( not Me.IsSelected( "Alice-MoonGuard" ), "toggle off" )
end)

test( "add with no argument uses your target", function()
	local Me = StartSession()
	WoW.units.target = { name = "Carol", realm = "WyrmrestAccord", guid = "Player-1-Carol" }

	Command( Me, "add" )
	check( Me.IsSelected( "Carol-WyrmrestAccord" ), "the target was added" )
end)

test( "select all and clear work off the in-range set", function()
	local Me = StartSession()
	WoW.Say( "CHAT_MSG_SAY", "hi", "Alice" )
	WoW.Say( "CHAT_MSG_SAY", "hi", "Bob" )
	WoW.Say( "CHAT_MSG_SAY", "hi", "Carol" )

	-- Carol wandered off a while ago.
	Me.chardb.roster["Carol-MoonGuard"].last =
		os.time() - (Me.db.settings.nearby_timeout + 60)

	Command( Me, "all" )
	equals( Me.SelectedCount(), 2, "only players still in range are added" )

	Command( Me, "clear" )
	equals( Me.SelectedCount(), 0, "clear empties the selection" )
end)

test( "forget drops unselected players and keeps the rest", function()
	local Me = StartSession()
	WoW.Say( "CHAT_MSG_SAY", "hi", "Alice" )
	WoW.Say( "CHAT_MSG_SAY", "hi", "Bob" )
	Me.SetSelected( "Bob-MoonGuard", true )

	Command( Me, "forget" )

	check( not Me.chardb.roster["Alice-MoonGuard"], "Alice was forgotten" )
	check( Me.chardb.roster["Bob-MoonGuard"], "Bob is selected, so he stays" )
	check( Me.IsSelected( "Bob-MoonGuard" ), "and stays selected" )
end)

test( "the window toggles from the slash command", function()
	local Me = StartSession()
	check( not Me.Window.IsShown(), "starts hidden" )

	Command( Me, "" )
	check( Me.Window.IsShown(), "bare /sw opens it" )
	check( Me.db.settings.window.shown, "and remembers that for next login" )

	Command( Me, "" )
	check( not Me.Window.IsShown(), "and closes it again" )
end)

test( "/sw list prints a clickable toggle per player", function()
	local Me = StartSession()
	WoW.Say( "CHAT_MSG_SAY", "hi", "Alice" )
	WoW.chat_output = {}

	Command( Me, "list" )

	local joined = table.concat( WoW.chat_output, "\n" )
	check( joined:find( "Hsaywhat:add:Alice-MoonGuard", 1, true ),
	       "an [+] link for Alice" )

	-- Clicking the link is a SetItemRef with our custom link type.
	SetItemRef( "saywhat:add:Alice-MoonGuard", "[+]", "LeftButton" )
	check( Me.IsSelected( "Alice-MoonGuard" ), "clicking [+] selects the player" )

	SetItemRef( "saywhat:remove:Alice-MoonGuard", "[-]", "LeftButton" )
	check( not Me.IsSelected( "Alice-MoonGuard" ), "clicking [-] deselects them" )
end)

test( "the player menu lists everyone known and toggles them", function()
	local Me = StartSession()
	WoW.Say( "CHAT_MSG_SAY", "hi", "Alice" )
	WoW.Say( "CHAT_MSG_SAY", "hi", "Bob-WyrmrestAccord" )

	Me.Menu.OpenPlayerSelect( Me.Window.frame )
	local menu = WoW.last_menu

	local alice = menu:Find( "Alice" )
	check( alice, "Alice is in the menu" )
	equals( alice.kind, "checkbox", "as a checkbox" )
	check( menu:Find( "Bob" ), "Bob is in the menu" )
	check( not alice.checked(), "unchecked to start" )

	alice.func()
	check( Me.IsSelected( "Alice-MoonGuard" ), "clicking the checkbox selects" )
	check( alice.checked(), "and the checkbox reads back as checked" )

	-- The options submenu is built too.
	check( menu:Find( "Timestamps" ), "options are reachable from the same menu" )
end)

test( "the right-click menu on a player name toggles them", function()
	local Me = StartSession()
	local handler = WoW.unit_menu_handlers and WoW.unit_menu_handlers["MENU_UNIT_PLAYER"]
	check( handler, "the unit popup handler was registered" )

	local root = WoW.NewMenuNode( "root" )
	handler( nil, root, { name = "Alice", server = "WyrmrestAccord" } )

	local button = root:Find( "SayWhat" )
	check( button, "an entry was added to the unit menu" )
	button.func()
	check( Me.IsSelected( "Alice-WyrmrestAccord" ), "clicking it selects the player" )
end)

test( "unknown commands and empty input do not blow up", function()
	local Me = StartSession()
	Command( Me, "definitely-not-a-command" )
	Command( Me, "add" )        -- no target, no name
	Command( Me, "remove   " )
	Command( Me, "status" )
	Command( Me, "help" )
	Command( Me, "list" )
	check( true, "survived" )
end)

test( "the log is capped so a busy city cannot grow it forever", function()
	local Me = StartSession()
	for i = 1, 900 do
		WoW.Say( "CHAT_MSG_SAY", "message " .. i, "Alice" )
	end
	check( #Me.Log.All() <= 600, "log stayed bounded: " .. #Me.Log.All() )
	check( #Me.Log.All() >= 500, "and kept a useful backlog: " .. #Me.Log.All() )

	local last = Me.Log.All()[ #Me.Log.All() ]
	equals( last.m, "message 900", "the newest message is the one kept" )
end)

-------------------------------------------------------------------------------
-- Roleplay names
-------------------------------------------------------------------------------

test( "a Total RP 3 name is shown instead of the character name", function()
	local Me = StartSession()
	WoW.InstallTRP3({
		["Alice-MoonGuard"] = { FN = "Elowen", LN = "Duskwhisper" };
	})
	Me.RPNames.ClearCache()

	Me.Window.Show()
	Me.SetSelected( "Alice-MoonGuard", true )
	WoW.Say( "CHAT_MSG_SAY", "well met", "Alice" )

	equals( Me.DisplayName( "Alice-MoonGuard" ), "Elowen Duskwhisper", "display name" )
	check( WindowHas( Me, "Elowen Duskwhisper: well met" ), "the window uses it" )
	check( not WindowHas( Me, "Alice: well met" ), "and not the character name" )
end)

test( "a character with no profile keeps their character name", function()
	local Me = StartSession()
	WoW.InstallTRP3({ ["Bob-MoonGuard"] = { FN = "Bartholomew" } })
	Me.RPNames.ClearCache()

	equals( Me.DisplayName( "Alice-MoonGuard" ), "Alice",
	        "nobody has sent us Alice's profile" )
	equals( Me.DisplayName( "Bob-MoonGuard" ), "Bartholomew", "but Bob's arrived" )
end)

test( "names update retroactively when a profile arrives later", function()
	local Me = StartSession()
	WoW.InstallTRP3({})
	Me.RPNames.ClearCache()

	Me.Window.Show()
	Me.SetSelected( "Alice-MoonGuard", true )
	WoW.Say( "CHAT_MSG_SAY", "well met", "Alice" )

	check( WindowHas( Me, "Alice: well met" ), "character name until the profile lands" )

	-- Her profile arrives a moment later, the way TRP3 fetches on proximity.
	WoW.TRP3AddProfile( "Alice-MoonGuard", { FN = "Elowen", LN = "Duskwhisper" } )
	Me.RPNames.Poll()

	check( WindowHas( Me, "Elowen Duskwhisper: well met" ),
	       "the line already on screen is rewritten" )
	check( not WindowHas( Me, "Alice: well met" ), "the old name is gone" )
end)

test( "a profile-received callback refreshes the window", function()
	-- Installed before login, so our hook into TRP3's update event registers.
	local Me = StartSession( nil, { trp3 = {} } )
	Me.RPNames.ClearCache()

	Me.Window.Show()
	Me.SetSelected( "Alice-MoonGuard", true )
	WoW.Say( "CHAT_MSG_SAY", "well met", "Alice" )

	WoW.TRP3AddProfile( "Alice-MoonGuard", { FN = "Elowen" } )
	WoW.TRP3FireUpdate()
	WoW.RunTimers()   -- the refresh is coalesced behind a short timer

	check( WindowHas( Me, "Elowen: well met" ), "updated without waiting for the poll" )
end)

test( "MSP names are read, with the title stripped", function()
	local Me = StartSession()
	WoW.InstallMSP({
		["Alice-MoonGuard"] = { NA = "Lady Elowen Duskwhisper" };
		["Bob-MoonGuard"]   = { NA = "Bartholomew" };
	})
	Me.RPNames.ClearCache()

	equals( Me.DisplayName( "Alice-MoonGuard" ), "Elowen Duskwhisper",
	        "the title is dropped" )
	equals( Me.DisplayName( "Bob-MoonGuard" ), "Bartholomew",
	        "a single word is left alone" )
end)

test( "a color code in an MSP name is parsed out, not printed", function()
	local Me = StartSession()
	WoW.InstallMSP({
		["Alice-MoonGuard"] = { NA = "|cffaa66ccElowen|r" };
	})
	Me.RPNames.ClearCache()

	equals( Me.DisplayName( "Alice-MoonGuard" ), "Elowen", "the name is clean" )

	local _, color = Me.RPNames.Get( "Alice-MoonGuard" )
	equals( color, "ffaa66cc", "and the color came back separately" )
end)

test( "roleplay colors are opt-in", function()
	local Me = StartSession()
	WoW.InstallTRP3({
		["Alice-MoonGuard"] = { FN = "Elowen", CH = "aa66cc" };
	})
	Me.RPNames.ClearCache()

	check( not Me.ColorName( "Alice-MoonGuard" ):find( "aa66cc", 1, true ),
	       "off by default" )

	Me.db.settings.rp_colors = true
	Me.RPNames.ClearCache()
	check( Me.ColorName( "Alice-MoonGuard" ):find( "|cffaa66ccElowen|r", 1, true ),
	       "on when asked for" )
end)

test( "turning roleplay names off goes back to character names", function()
	local Me = StartSession()
	WoW.InstallTRP3({ ["Alice-MoonGuard"] = { FN = "Elowen" } })
	Me.RPNames.ClearCache()

	Me.Window.Show()
	Me.SetSelected( "Alice-MoonGuard", true )
	WoW.Say( "CHAT_MSG_SAY", "well met", "Alice" )
	check( WindowHas( Me, "Elowen: well met" ), "roleplay name to start" )

	Me.db.settings.rp_names = false
	Me.Window.Refresh()
	check( WindowHas( Me, "Alice: well met" ), "character name once turned off" )
end)

test( "identity stays the character name, never the roleplay name", function()
	local Me = StartSession()
	WoW.InstallTRP3({ ["Alice-MoonGuard"] = { FN = "Elowen", LN = "Duskwhisper" } })
	Me.RPNames.ClearCache()

	WoW.Say( "CHAT_MSG_SAY", "well met", "Alice" )
	Me.SetSelected( "Alice-MoonGuard", true )

	check( Me.chardb.roster["Alice-MoonGuard"], "the roster keys on the character" )
	check( Me.chardb.selected["Alice-MoonGuard"], "so does the selection" )
	check( not Me.chardb.selected["Elowen Duskwhisper"], "not on the roleplay name" )

	local saved = SaveSession()
	check( not saved:find( "Elowen", 1, true ),
	       "and no roleplay name is written to disk" )

	-- A roleplay name change must not break an existing selection.
	WoW.TRP3AddProfile( "Alice-MoonGuard", { FN = "Someone", LN = "Else" } )
	Me.RPNames.ClearCache()

	Me.Window.Show()
	WoW.Say( "CHAT_MSG_SAY", "still me", "Alice" )
	check( WindowHas( Me, "Someone Else: still me" ), "the filter still matches her" )
end)

test( "a player can be added by their roleplay name", function()
	local Me = StartSession()
	WoW.InstallTRP3({ ["Alice-MoonGuard"] = { FN = "Elowen", LN = "Duskwhisper" } })
	Me.RPNames.ClearCache()

	WoW.Say( "CHAT_MSG_SAY", "well met", "Alice" )

	Command( Me, "add elowen" )
	check( Me.IsSelected( "Alice-MoonGuard" ), "the first name resolves" )

	Command( Me, "remove Elowen Duskwhisper" )
	check( not Me.IsSelected( "Alice-MoonGuard" ), "so does the whole name" )
end)

test( "the player menu shows the character name alongside the roleplay one", function()
	local Me = StartSession()
	WoW.InstallTRP3({ ["Alice-MoonGuard"] = { FN = "Elowen" } })
	Me.RPNames.ClearCache()

	WoW.Say( "CHAT_MSG_SAY", "well met", "Alice" )
	Me.Menu.OpenPlayerSelect( Me.Window.frame )

	local entry = WoW.last_menu:Find( "Elowen" )
	check( entry, "listed under the roleplay name" )
	check( entry.text:find( "Alice", 1, true ),
	       "with the character name too, since that's what commands take" )
end)

test( "text emotes are rewritten with the roleplay name", function()
	local Me = StartSession()
	WoW.InstallTRP3({ ["Alice-MoonGuard"] = { FN = "Elowen" } })
	Me.RPNames.ClearCache()

	Me.Window.Show()
	Me.SetSelected( "Alice-MoonGuard", true )
	WoW.FireEvent( "CHAT_MSG_TEXT_EMOTE", "Alice waves at you.", "Alice",
	               "Common", "", "", "", 0, 0, "", 0, 1, "Player-1-Alice" )

	check( WindowHas( Me, "Elowen" ), "the roleplay name replaced the character one" )
	check( WindowHas( Me, "waves at you." ), "and the emote body survived" )
end)

test( "Total RP 3 is preferred over MSP when both are present", function()
	local Me = StartSession()
	WoW.InstallTRP3({ ["Alice-MoonGuard"] = { FN = "FromTRP" } })
	WoW.InstallMSP({ ["Alice-MoonGuard"] = { NA = "FromMSP" } })
	Me.RPNames.ClearCache()

	equals( Me.DisplayName( "Alice-MoonGuard" ), "FromTRP",
	        "TRP3 has separate name fields, so it wins" )
	equals( Me.RPNames.Source(), "Total RP 3", "and status reports it" )
end)

test( "MSP is used when Total RP 3 has no profile for someone", function()
	local Me = StartSession()
	WoW.InstallTRP3({})                                  -- installed, no profiles
	WoW.InstallMSP({ ["Alice-MoonGuard"] = { NA = "Elowen" } })
	Me.RPNames.ClearCache()

	equals( Me.DisplayName( "Alice-MoonGuard" ), "Elowen", "falls through to MSP" )
end)

test( "the name cache expires on its own as time passes", function()
	local Me = StartSession( nil, { trp3 = {} } )

	equals( Me.DisplayName( "Alice-MoonGuard" ), "Alice", "no profile yet" )

	WoW.TRP3AddProfile( "Alice-MoonGuard", { FN = "Elowen" } )
	equals( Me.DisplayName( "Alice-MoonGuard" ), "Alice",
	        "still the cached miss a moment later" )

	WoW.gametime = WoW.gametime + 30
	equals( Me.DisplayName( "Alice-MoonGuard" ), "Elowen",
	        "the cache drops it once the ttl passes" )
end)

test( "a broken roleplay addon costs a name, not the window", function()
	local Me = StartSession()

	-- Something that looks like TRP3 but throws when queried.
	_G.TRP3_API = {
		register = {
			isUnitIDKnown    = function() error( "boom" ) end;
			getCharacterList = function() return {} end;
		};
	}
	Me.RPNames.ClearCache()

	Me.Window.Show()
	Me.SetSelected( "Alice-MoonGuard", true )
	WoW.Say( "CHAT_MSG_SAY", "well met", "Alice" )

	equals( Me.DisplayName( "Alice-MoonGuard" ), "Alice", "falls back to the character" )
	check( WindowHas( Me, "Alice: well met" ), "and the message still shows" )
end)

-------------------------------------------------------------------------------
-- Minimap button
-------------------------------------------------------------------------------

test( "the minimap button toggles the window and opens the menu", function()
	local Me = StartSession()
	local button = Me.Minimap.button

	check( button, "the button was created on login" )
	check( button:IsShown(), "and is shown by default" )

	button.scripts.OnClick( button, "LeftButton" )
	check( Me.Window.IsShown(), "left-click opens the window" )

	button.scripts.OnClick( button, "LeftButton" )
	check( not Me.Window.IsShown(), "and closes it again" )

	button.scripts.OnClick( button, "RightButton" )
	check( WoW.last_menu and WoW.last_menu:Find( "Nearby Players" ),
	       "right-click opens the player selection menu" )
end)

test( "dragging the minimap button moves it and the angle persists", function()
	local Me = StartSession()
	local button = Me.Minimap.button
	local original = Me.db.settings.minimap.angle

	-- Drag to a point straight above the minimap's center: 90 degrees.
	button.scripts.OnDragStart( button )
	WoW.cursor.x, WoW.cursor.y = 500, 600
	button.scripts.OnUpdate( button )
	button.scripts.OnDragStop( button )

	equals( math.floor( Me.db.settings.minimap.angle + 0.5 ), 90,
	        "the angle follows the cursor" )
	check( Me.db.settings.minimap.angle ~= original, "and changed from the default" )
	check( button.scripts.OnUpdate == nil, "the drag handler is cleaned up" )

	local x, y = select( 4, button:GetPoint() )
	check( math.abs( x ) < 0.01, "sits directly above the center on x" )
	check( y > 0, "and above it on y" )

	Me = StartSession( SaveSession() )
	equals( math.floor( Me.db.settings.minimap.angle + 0.5 ), 90,
	        "the angle survives a reload" )
end)

test( "the minimap button can be hidden, and stays hidden", function()
	local Me = StartSession()

	Command( Me, "minimap" )
	check( not Me.Minimap.button:IsShown(), "/sw minimap hides it" )

	Me = StartSession( SaveSession() )
	check( not Me.Minimap.button:IsShown(), "still hidden after a reload" )

	Command( Me, "minimap" )
	check( Me.Minimap.button:IsShown(), "and can be brought back" )
end)

test( "the minimap option in the menu matches the button", function()
	local Me = StartSession()
	Me.Menu.OpenPlayerSelect( Me.Window.frame )

	local option = WoW.last_menu:Find( "Minimap button" )
	check( option, "the option is in the menu" )
	check( option.checked(), "checked while the button is shown" )

	option.func()
	check( not Me.Minimap.button:IsShown(), "clicking it hides the button" )
	check( not option.checked(), "and the checkbox follows" )
end)

-------------------------------------------------------------------------------
-- Slash commands
-------------------------------------------------------------------------------

test( "we never claim /sw, which is Blizzard's stopwatch", function()
	local Me = StartSession()

	for _, name in ipairs( Me.slash_names ) do
		check( name ~= "/sw", "/sw must not be one of ours" )
	end

	equals( SLASH_STOPWATCH3, "/sw", "and the stopwatch still has it" )
	equals( _G.SlashCmdList.STOPWATCH ~= nil, true, "with its handler intact" )
end)

test( "the commands we do claim are registered", function()
	local Me = StartSession()

	equals( Me.SlashCommand(), "/saywhat", "the primary name" )
	equals( SLASH_SAYWHAT1, "/saywhat", "registered with the game" )
	equals( SLASH_SAYWHAT2, "/sayw", "short form" )
	equals( SLASH_SAYWHAT3, "/nearby", "and the long one" )
	check( SlashCmdList["SAYWHAT"], "with a handler" )
end)

test( "a name another addon already owns is left alone", function()
	WoW.Install({})
	WoW.AddSlashCommand( "SOMEOTHERADDON", "/sayw" )

	-- Load into the session that already has that command registered.
	local Me = StartSessionWithExisting()

	for _, name in ipairs( Me.slash_names ) do
		check( name ~= "/sayw", "/sayw belongs to somebody else" )
	end

	local found
	for _, clash in ipairs( Me.slash_conflicts ) do
		if clash.token == "/sayw" then found = clash end
	end
	check( found, "the clash was recorded" )
	equals( found.owner, "SOMEOTHERADDON", "along with who owns it" )

	equals( Me.SlashCommand(), "/saywhat", "and we still have a way in" )
end)

test( "if everything is taken we claim the primary name anyway", function()
	WoW.Install({})
	WoW.AddSlashCommand( "HOSTILEADDON", "/saywhat", "/sayw", "/nearby" )

	local Me = StartSessionWithExisting()

	equals( #Me.slash_names, 1, "one name registered" )
	equals( Me.SlashCommand(), "/saywhat", "the primary one" )
	equals( #Me.slash_conflicts, 3, "all three clashes recorded" )
end)

test( "help and the window hint name a command that exists", function()
	local Me = StartSession()

	WoW.chat_output = {}
	Command( Me, "help" )
	local help = table.concat( WoW.chat_output, "\n" )

	check( help:find( "/saywhat list", 1, true ), "help uses the claimed name" )
	check( not help:find( "/sw ", 1, true ), "and never mentions /sw" )
	check( help:find( "/sayw, /nearby", 1, true ), "the aliases are listed" )

	Me.Window.Show()
	check( WindowHas( Me, "/saywhat add <name>" ),
	       "the empty-window hint uses it too" )
end)

-------------------------------------------------------------------------------
-- Run
-------------------------------------------------------------------------------

print( "SayWhat test suite" )
print( string.rep( "-", 60 ) )

for _, entry in ipairs( tests ) do
	current = entry.name
	local ok, err = pcall( entry.fn )
	if ok then
		print( "  ok   " .. entry.name )
	elseif type( err ) ~= "table" then
		failures = failures + 1
		print( string.format( "  ERROR %s\n       %s", entry.name, tostring( err ) ))
	end
end

print( string.rep( "-", 60 ) )
print( string.format( "%d test(s), %d failure(s)", #tests, failures ) )
os.exit( failures == 0 and 0 or 1 )
