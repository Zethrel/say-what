# SayWhat

A World of Warcraft addon that keeps track of the players who talk in **/say
range** around you, and mirrors the ones you care about into a dedicated
**Nearby** window.

Busy roleplay hubs drown you in chat. SayWhat notices everyone who speaks
within say range, lets you tick the handful of people you're actually talking
to, and gives them a window of their own. Your picks are remembered between
sessions.

Inspired by [Listener](https://www.curseforge.com/wow/addons/listener), written
from scratch with no library dependencies.

## Features

- **Nearby tracker** — every player you hear in /say range is recorded, with
  when you last heard them, how many messages, their class color, and the zone.
- **Nearby window** — a movable, resizable chat window that shows *only* the
  players you selected.
- **Player selection menu** — click **Players** in the window (or right-click
  the window body) for a checklist of everyone nearby.
- **Manage players from chat** — `/sw list` prints the roster with clickable
  `[+]` / `[-]` buttons, and right-clicking a player's name in the chat window
  gets a *SayWhat: Add to Nearby* entry.
- **Roleplay names** — shows the name from Total RP 3, MyRolePlay or XRP when
  a profile has been received, and corrects itself when one arrives late.
- **Persistent selection** — saved variables remember your picks per character
  through reloads, relogs and expansions' worth of sessions.
- **Retroactive filtering** — adding someone shows what they already said this
  session, instead of an empty window.

## Installing

Copy the **`SayWhat`** folder from this repository into
`World of Warcraft\_retail_\Interface\AddOns\`, so that this exact path
exists:

```
Interface\AddOns\SayWhat\SayWhat.toc
```

Copy the `SayWhat` folder, not the repository folder. WoW requires an addon's
folder name to match its `.toc` filename exactly, and this repository is called
`say-what`, which does not match. That's why the addon lives in a subfolder.

**Then restart the game client.** WoW only scans `Interface\AddOns` when it
launches; `/reload` re-runs the addons it already found and will never pick up a
newly added folder.

### The addon doesn't appear in the list

In order of likelihood:

1. **The folder name is wrong.** `Interface\AddOns\say-what\SayWhat.toc` does
   not work, and neither does a nested `SayWhat\SayWhat\SayWhat.toc` (which is
   what unzipping a GitHub download usually gives you). The `.toc` has to sit
   directly inside a folder named `SayWhat`.
2. **The client wasn't restarted.** See above — `/reload` is not enough.
3. **You're looking at the wrong game version.** `_retail_`, not `_classic_`.
   This addon targets retail.

Once it is listed, if it shows greyed out or *Out of Date*, your client is on a
different patch than the `## Interface:` line in the `.toc`. Tick **Load out of
date AddOns** in the AddOns list, and tell me the patch so I can bump it.

To confirm the game found it, run this in game:

```
/dump C_AddOns.GetAddOnInfo("SayWhat")
```

A `nil` name means the folder still isn't where WoW is looking.

## Commands

`/saywhat`, `/sw` and `/nearby` all work.

| Command | What it does |
| --- | --- |
| `/sw` | Toggle the Nearby window |
| `/sw list` | List the roster with `[+]`/`[-]` links |
| `/sw menu` | Open the player selection menu |
| `/sw add [name]` | Show a player — defaults to your target or mouseover |
| `/sw remove [name]` | Stop showing a player |
| `/sw toggle [name]` | Flip a player on or off |
| `/sw all` | Select everyone currently in range |
| `/sw clear` | Deselect everyone |
| `/sw forget` | Empty the roster (selected players are kept) |
| `/sw show`, `/sw hide` | Open/close the window |
| `/sw lock`, `/sw unlock` | Lock the window's position and size |
| `/sw status` | Print what the addon currently thinks is going on |
| `/sw help` | The list above, in game |

Names are matched case-insensitively against players you've heard, so
`/sw add alice` finds `Alice-WyrmrestAccord` if she's the Alice you heard.
Otherwise your own realm is assumed.

## How "nearby" is decided

There is no client API that gives you the distance to another player, so the
addon doesn't try to measure one. It doesn't need to: **the server only
delivers `CHAT_MSG_SAY` when the sender is inside say range** (about 40 yards).
Receiving the event *is* the range test. If someone's say reached you, they
were in range at that moment.

Consequences worth knowing:

- **Yell is not proximity.** `/yell` carries roughly 300 yards, so it is
  captured for display but never marks anyone as nearby. You can turn that on
  under *Options → Counts as nearby* if you want it anyway.
- **Emotes are proximity**, and use the same range as say. They're off by
  default in the tracker so the roster stays a "who is talking near me" list,
  and can be switched on in the same menu.
- **Being in range is a moment, not a state.** A player counts as *in range*
  for 5 minutes after you last heard them (`nearby_timeout`). They stay in the
  roster and in the menu for a day after that, so you can still tick someone
  who's gone quiet.
- **Instances hide chat from addons.** Since patch 12.0, chat delivered while
  you're inside an instance arrives as a *secret value* that addons are not
  allowed to read. Those messages are dropped: SayWhat can neither display nor
  track what it cannot read. Everywhere else works normally.

## Roleplay names

If you have **Total RP 3**, **MyRolePlay** or **XRP** installed, the window
shows people under their roleplay name instead of their character name.
Total RP 3 is read directly (its title, first name and last name are separate
fields); MyRolePlay and XRP are read through LibMSP, where the name arrives as
one string and a leading title is stripped heuristically.

Neither is a dependency. With no roleplay addon installed nothing changes.

Three things worth knowing:

- **You only get a name for a profile you've actually received.** RP addons
  fetch profiles on mouseover, target or proximity, so someone who speaks from
  across the square may show as their character name at first. The window
  rewrites the lines already on screen once their profile lands — through the
  addon's own update event where there is one, and a 5-second poll as a
  backstop.
- **Identity is always the character name.** Roleplay names aren't unique and
  people change them mid-session, so the roster, the selection and the saved
  variables all stay keyed on `Character-Realm`. Only what you see changes. A
  filter set up under one roleplay name keeps working after it changes.
- **Commands accept both.** `/sw add elowen` works on a roleplay name (whole
  name or first name) as well as the character name, and the Players menu lists
  both so you can see who you're actually ticking.

Turn it off under *Options → Roleplay names*. *Roleplay name colors* uses the
profile's own color instead of the class color; it's off by default because
class colors carry information and custom colors aren't always readable.

## Options

In the **Players → Options** submenu:

- **Show in window** — which chat types the window displays (say, emote, text
  emote, yell).
- **Counts as nearby** — which chat types add someone to the roster.
- **Include my own chat** — your own say/emote rides along with the
  conversation.
- **Roleplay names** and **Roleplay name colors** — see above.
- **Timestamps**, **font size**, **lock window**.
- **Open window on new message** — pop the window up when a selected player
  speaks.
- **Announce new players in chat** — print `X is nearby [+]` the first time
  someone new speaks near you.

## Saved variables

| File | Holds |
| --- | --- |
| `SayWhatDB` (account-wide) | Settings and the window's position, size and font |
| `SayWhatCharDB` (per character) | The nearby roster and which players are selected |

Proximity is a per-character thing, so the roster and your selection live with
the character while display preferences follow the account. Chat text itself is
never written to disk — the message buffer is a live 500-message window that
starts empty each session.

## Layout

```
SayWhat/                 The addon folder - this is what you copy into AddOns
  SayWhat.toc            Addon manifest and load order
  src/core.lua           Namespace, saved variables, name handling, chat pipeline
  src/roster.lua         The nearby roster and the player selection
  src/log.lua            Rolling in-memory message buffer
  src/rpnames.lua        Roleplay names from Total RP 3 / MyRolePlay / XRP
  src/menu.lua           Player selection menu, options, unit right-click entry
  src/window.lua         The Nearby window
  src/links.lua          Clickable [+]/[-] chat links
  src/commands.lua       Slash commands
tests/                   Headless test suite (see below), not shipped
```

## Tests

The addon logic runs headless against a mock of the WoW API, using the same
Lua 5.1 the game does:

```sh
lua5.1 tests/run.lua
```

The suite covers range behavior (say tracks, yell doesn't, timeouts, pruning),
player names (cross-realm keys, text-emote realm recovery, case-insensitive
lookup), filtering accuracy (selection, retroactive backlog, same name on two
realms, event types, secret values), persistence (reload, relog, per-character
selection, old saved-variable files picking up new defaults), and the commands,
menu and chat links.

### In-game checklist

The mock can't prove how the real client behaves, so these are worth walking
through in game after any change:

1. **Range** — stand in a city, `/sw status`, and watch the roster fill as
   people talk. Walk away from a talkative group until their says stop arriving
   and confirm nobody new is added past that point.
2. **Names** — check a cross-realm player (`Name-Realm` shown in full) and a
   same-realm one (realm hidden), and that `/sw add <partial case>` finds them.
   Test a text emote (`/wave` at you) from a cross-realm player.
3. **Reload** — select two players, `/reload`, confirm they're still selected
   and the window reopens where you left it.
4. **Relog** — log to an alt: the alt has its own empty selection, but the
   window layout and options carried over. Log back and the original selection
   is intact.
5. **Filtering** — with one player selected, have two people talk and confirm
   only the selected one appears; tick the second in the **Players** menu and
   confirm their earlier lines appear too.
6. **Chat management** — `/sw list`, click `[+]` and `[-]`; right-click a name
   in the default chat frame and use the *SayWhat* entry.
7. **Instances** — zone into a dungeon and confirm the addon stays quiet and
   error-free (chat is unreadable to addons there).
8. **Roleplay names** — with TRP3 running, confirm a selected player shows
   their RP name, and that someone whose profile you haven't loaded starts as a
   character name and switches over within a few seconds of you mousing over
   them. `/sw status` reports which roleplay addon was detected.

## License

MIT. See [LICENSE](LICENSE).
