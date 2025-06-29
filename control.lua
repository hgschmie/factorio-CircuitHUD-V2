local Event = require("stdlib/event/event")

local const = require("lib.constants")
local common = require("lib.common")

local player_settings = require("globals.player-settings")
local combinator = require("globals.combinator")
local player_data = require("globals.player-data")
local base_global = require("globals.base-global")

require "lib.migration"

local gui_hud = require("gui.hud-gui")
local gui_combinator = require('gui.combinator-gui')

require "events.gui-events"
require "events.custom-events"

-- Enable Lua API global Variable Viewer
-- https://mods.factorio.com/mod/gvv
if script.active_mods["gvv"] then
	require("__gvv__.gvv")()
end

--#region on_configuration_changed
local function on_configuration_changed()
     -- enable hud if circuit network is researched.
     for _, force in pairs(game.forces) do
        if force.recipes[const.HUD_COMBINATOR_NAME] and force.technologies['circuit-network'] then
            force.recipes[const.HUD_COMBINATOR_NAME].enabled = force.technologies['circuit-network'].researched
        end
    end
end
--#endregion

--#region Event Registrations
local function register_events()

	--#region On Nth Tick
	Event.on_nth_tick(1, function(event)
		-- go through each player and update their HUD based on the HUD Refresh rate
		for _, player in pairs(game.players) do
			if event.tick % player_settings.get_hud_refresh_rate_setting(player.index) == 0 then
				gui_hud.update(player.index)
				local combinator_gui = gui_combinator.get_combinator_gui(player.index)
				if combinator_gui then
					local unit_number = combinator_gui.tags['unit_number']
					if unit_number then
						gui_combinator.update_signals(player.index, unit_number)
					end
				end
			end
		end
	end)

	--#endregion
	--#region On Player Created

	Event.register(defines.events.on_player_created, function(event)
		local player = common.get_player(event.player_index)
		player_data.add_player_global(event.player_index)
		gui_hud.create(event.player_index)
		common.debug_log(event.player_index, 'Circuit HUD created for player ' .. player.name)
	end)

	--#endregion
	--#region On Player Removed

	Event.register(defines.events.on_player_removed, function(event)
		player_data.remove_player_global(event.player_index)
	end)

	--#endregion
	--#region On Runtime Mod Setting Changed

	Event.register(defines.events.on_runtime_mod_setting_changed, function(event)
		-- Only update when a CircuitHUD change has been made
		if event.player_index and string.find(event.setting, const.SETTINGS.prefix) then
			gui_hud.reset(event.player_index)
			-- Ensure the HUD is visible on mod setting change
			gui_hud.update_collapse_state(event.player_index, false)
		end
	end)

	--#endregion
	--#region Register / De-register HUD Combinator

	local function set_combinator_registration(entity, state)
		if state then
			combinator.register_combinator(entity)
		else
			combinator.unregister_combinator(entity)
		end
		gui_hud.check_all_player_hud_visibility()
	end

	local function close_combinator_gui(entity)
		if not (entity and entity.valid) then return end

		for player_index in pairs(game.players) do
			local gui = gui_combinator.get_combinator_gui(player_index)
			if gui and gui.tags.unit_number == entity.unit_number then
				gui_combinator.destroy(player_index, gui.name)
			end
		end
	end

	local entity_filter = function(event)
		return event and event.entity.name == const.HUD_COMBINATOR_NAME and true or false
	end

	Event.register({
			defines.events.on_built_entity,
			defines.events.on_robot_built_entity,
			defines.events.on_space_platform_built_entity,
			defines.events.script_raised_revive,
		}, function(event)
			set_combinator_registration(event.entity, true)
		end,
		entity_filter)

	Event.register({
			defines.events.on_player_mined_entity,
			defines.events.on_robot_mined_entity,
			defines.events.on_space_platform_mined_entity,
		}, function(event)
			close_combinator_gui(event.entity)
			set_combinator_registration(event.entity, false)
		end,
		entity_filter)

	--#endregion
	--#region Resolution Changes

	Event.register(defines.events.on_player_display_resolution_changed, function(event)
		gui_hud.reset(event.player_index)
	end)

	Event.register(defines.events.on_player_display_scale_changed, function(event)
		gui_hud.reset(event.player_index)
	end)

    Event.on_configuration_changed(on_configuration_changed)

	--#endregion
end

--#endregion

--#region OnInit

Event.on_init(function()
	for _, player in pairs(game.players) do
		common.debug_log(player.index, 'On Init')
	end
	-- Ensure the global state has been initialized
	base_global.ensure_global_state()
	-- Check all Combinator HUD references
	combinator.check_combinator_registrations()
	-- Ensure we have created the HUD for all players
	gui_hud.check_all_player_hud_visibility()

	register_events()
end)

--#endregion

--#region OnLoad

Event.on_load(register_events)

--#endregion
