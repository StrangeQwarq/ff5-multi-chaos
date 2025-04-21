local socket = require("socket")
local shop_item_customized = require("effects")

-- abp doesn't work when used in battle
-- hp+ doesn't work in battle
-- when battle ends everyone doesn't get control
-- video streaming is fucked

-- new options
-- run from battle
-- set battle speed to max

-- binds to a port and accepts connections
local server = nil

-- password needed to connect as a client
local password = ""

-- clients that have connected but haven't sent a password yet
local pending_client = nil

-- time when the pending client first made the connection
local pending_client_connect_time = 0

-- max time to wait for a client to send their password
local pending_client_timeout = 1000

-- all player indexes, used to iterate over tables keyed by character names
local character_names = {"Bartz", "Lenna", "Galuf", "Faris"}

-- max number of characters for player names
local max_player_name_size = 6

-- how many players are current connected to the server
local num_players_connected = 0

local character_points_file_path = ""
-- number of GregBux owned by each character
local character_points = {["Bartz"] = 10, ["Lenna"] = 11, ["Galuf"] = 12, ["Faris"] = 13}

-- table of all active players. values be nil if no player is connected
local players = {["Bartz"] = nil, ["Lenna"] = nil, ["Galuf"] = nil, ["Faris"] = nil}

-- used to calculate address of each character's name
local character_indexes = {["Bartz"] = 0, ["Lenna"] = 1, ["Galuf"] = 2, ["Faris"] = 3}

-- which slot each character is in
local character_positions = {["Bartz"] = 1, ["Lenna"] = 2, ["Galuf"] = 3, ["Faris"] = 4}

-- ids for each character as defined in the game
local character_ids = {["0"] = "Bartz", ["1"] = "Lenna", ["2"] = "Galuf", ["3"] = "Faris", ["4"] = "Galuf"}

-- whether to use Krile instead of Galuf
local has_krile = false

-- bit value for each button
local button_masks = {Up = 1, Down = 2, Left = 4, Right = 8, A = 16, B = 32, X = 64, Y = 128, R = 256, L = 512, Start = 1024, ["Select"] = 2048}

-- was the group in battle last frame?
local was_in_battle = false

-- the last player character that was in control. taken from active_character_index_addr
local last_active_character = 0xF

-- starting value for uppercase letters
local upper_offset = 0x60

-- starting value for lowercase letters
local lower_offset = 0x7A

-- starting value for numeric letters
local number_offset = 0x53

local escape_percent_addr = 0x7E3EF0

--local battle_speed_addr = 0x7E2C9D
-- i think this one only applies in battle? 00 15 30 60 120 240 (from battle speed)
local battle_speed_addr = 0x7E3ED6

-- byte value is 0x10 when in battle and 0x0 when out of battle
-- i'm not sure what this value represents but it's more consistent than the battle status
local battle_status_addr = 0x7E014D --0x7E7BDE

-- 0x0 = battle not over, 0x1 = escaped, 0x20 = timed event end, 0x40 game over, 0x80 enemies died
local battle_over_flag_addr = 0x7E7BDE

-- address of the current encounter. up to 0x1FF is valid, only valid in battle.
local battle_encounter_id_addr = 0x7E04F0

-- start of the player names. each one is 6 bytes with a 0xFF terminator
local names_base_addr = 0x7E0990

-- indicates the position of the character that's active, 0x180 and smaller means a player
local active_character_index_addr = 0x7E010D

-- flags of the character's innate abilities. used to force set dash enabled
local player_1_innate_abilities_addr = 0x7E0520

local character_battle_data_size = 0x80

local character_world_data_size = 0x50

-- allows 10 seconds of no reponse from the client before kicking them
local player_timeout_threshold = 10000

-- if we haven't had an update on the player's input in this long, assume no inputs
local player_input_timeout = 500

-- how long the active player has been in control while in battle
local time_in_control = 0

-- how long a player can stay in control in battle
local max_time_in_control = 20000

-- if the player in control hasn't finished in some time, override their controls and let anyone act
local control_override = false

-- bitfield describing which players are in control
local control_bits = 0

-- id of the enemy battle formation. between 0 and 512, only set in battle
local current_enemy_formation = 0

-- handle to the window
local control_form = forms.newform(250, 330, "FF5 Multi-Chaos Control Panel")

local in_control_label = forms.label(control_form, "Who's in control:", 10, 255, 100, 15)
local in_control_name_label = forms.label(control_form, "Everyone", 10, 270, 100, 15)

-- handle to the textbox for setting the port
local port_textbox = forms.textbox(control_form, "32024", 100, 30, "UNSIGNED", 10, 30, false)
local port_label   = forms.label(control_form, "Server Port", 10, 10, 100, 20)

-- handle to the textbox for setting the server password
local password_textbox = forms.textbox(control_form, "", 100, 10, nil, 120, 30, false)
local password_label   = forms.label(control_form, "Server Password", 120, 10, 100, 20)

-- colors for the server status label
local red_label = forms.createcolor(200, 30, 30, 255)
local green_label = forms.createcolor(30, 200, 30, 255)

-- label showing whether the server is online
local server_status_label = forms.label(control_form, "Server Offline", 10, 170, 200, 20)
forms.setproperty(server_status_label, "ForeColor", red_label)
forms.setproperty(server_status_label, "TextAlign", 2)

-- buttons used to kick players
local kick_buttons = {["Bartz"] = nil, ["Lenna"] = nil, ["Galuf"] = nil, ["Faris"] = nil}

-- checkbox to toggle low encounter rate
local low_encounter_rate = false
--local low_encounter_rate_label = forms.label(control_form, "", 25, 195, 200, 20)
local encounter_rate_checkbox = forms.checkbox(control_form, "Fewer Battles", 10, 190)
forms.addclick(encounter_rate_checkbox, function()
	low_encounter_rate = not low_encounter_rate
end)

-- checkbox to toggle input display
local show_input = false
local show_input_checkbox = forms.checkbox(control_form, "Show Input", 10, 210)
forms.addclick(show_input_checkbox, function()
	show_input = not show_input
end)

local character_points_labels = {
	Bartz = forms.label(control_form, "Bartz: 0 points", 130, 190, 110, 15),
	Lenna = forms.label(control_form, "Lenna: 0 points", 130, 205, 110, 15),
	Galuf = forms.label(control_form, "Galuf: 0 points", 130, 220, 110, 15),
	Faris = forms.label(control_form, "Faris: 0 points", 130, 235, 110, 15),
}

-- data for each positive status. first element is the status type offset, second is the bit in that byte
local statuses = {
	float   = {0x1A, 0x08},
	mini    = {0x1A, 0x10},
	berserk = {0x1B, 0x08},
	blink   = {0x1B, 0x02},
	haste   = {0x1C, 0x08},
	shell   = {0x1C, 0x20},
	protect = {0x1C, 0x40},
	reflect = {0x1C, 0x80},
	regen   = {0x1C, 0x01},
}

-- sets a player's status
function set_status(character_index, status)
	local start_addr = 0x7E2000
	local character_battle_data_addr = start_addr + (character_battle_data_size * character_index)
	local status_addr = character_battle_data_addr + status[1]
	local current_status = memory.read_u8(status_addr)
	memory.write_u8(status_addr, bit.bor(current_status, status[2]))
end

-- serialized version of shop_items (minus func). set when the script starts
local shop_data_text = ""

local shop_items = {
	["speed"] = {
		cost = 2,
		name = "SPEED",
		desc = "Maxes out the battle speed",
		func = function(player)
			local in_battle = is_in_battle()
			local current_speed = memory.read_u8(battle_speed_addr)

			if not in_battle or current_speed == 0xF0 then
				return false
			else
				memory.write_u8(battle_speed_addr, 0xF0)
			end
		end
	},
	["run"] = {
		cost = 3,
		name = "RUN AWAY",
		desc = "Immediately run away from the current battle",
		func = function(player)
			if not is_in_battle() then
				print("run: not in battle")
				return false
			end

			local battle_over_flag = memory.read_u8(battle_over_flag_addr)
			local escape_chance_value = memory.read_u8(escape_percent_addr)
			local unrunnable = bit.band(escape_chance_value, 0x80)

			if battle_over_flag ~= 0x1 and unrunnable == 0 then
				memory.write_u8(battle_over_flag_addr, 0x1)
			else
				return false
			end
		end
	},
	["exp"] = {
		cost = 5,
		name = "EXP+",
		desc = "Gives some extra EXP based on your level (level ups won't happen until the end of the next battle)",
		func = function(player)
			local character_index = character_indexes[player["player_index"]]
			local current_exp_addr = nil

			local character_world_data_offset = (character_index * character_world_data_size)
			local character_battle_data_offset = (character_index * character_battle_data_size)

			-- use the out of battle level since we don't want in-battle level manipulation skewing the exp
			local player_level = memory.read_u8(0x7E0502 + character_world_data_offset)
			if is_in_battle() then
				current_exp_addr = 0x7E2003 + character_battle_data_offset
			else
				current_exp_addr = 0x7E0503 + character_world_data_offset
			end

			local current_exp = memory.read_u24_le(current_exp_addr)
			local bonus_exp = player_level * player_level * player_level

			memory.write_u24_le(current_exp_addr, current_exp + bonus_exp)
		end
	},
	["abp"] = {
		cost = 5,
		name = "ABP+",
		desc = "Gives 10 ABP for your current job (job level ups won't happen until the end of the next battle)",
		func = function(player)
			local abp_bonus = 10
			local character_index = character_indexes[player["player_index"]]
			local abp_addr = nil

			if is_in_battle() then
				abp_addr = 0x7E203B + (character_index * character_battle_data_size)
			else
				abp_addr = 0x7E053B + (character_index * character_world_data_size)
			end

			local current_abp = memory.read_u16_le(abp_addr)
			memory.write_u16_le(abp_addr, current_abp + abp_bonus)
		end
	},
	["heal"] = {
		cost = 5,
		name = "HEAL",
		desc = "Recovers 25% of max hp",
		func = function(player)
			local current_hp_addr = nil
			local max_hp_addr = nil
			local character_index = character_indexes[player["player_index"]]

			if is_in_battle() then
				current_hp_addr = 0x7E2006 + (character_index * character_battle_data_size)
				max_hp_addr = current_hp_addr + 2
			else
				current_hp_addr = 0x7E0506 + (character_index * character_world_data_size)
				max_hp_addr = current_hp_addr + 2
			end

			local current_hp = memory.read_u16_le(current_hp_addr)
			local max_hp = memory.read_u16_le(max_hp_addr)

			if current_hp == max_hp then
				return false
			end

			current_hp = math.min(current_hp + (max_hp * 0.25), max_hp)
			memory.write_u16_le(current_hp_addr, current_hp)
		end
	},
	["mp_recovery"] = {
		cost = 5,
		name = "MP RECOVER",
		desc = "Recovers 25% of max mp",
		func = function(player)
			local current_mp_addr = nil
			local max_mp_addr = nil
			local character_index = character_indexes[player["player_index"]]

			if is_in_battle() then
				current_mp_addr = 0x7E200A + (character_index * character_battle_data_size)
				max_mp_addr = current_mp_addr + 2
			else
				current_mp_addr = 0x7E050A + (character_index * character_world_data_size)
				max_mp_addr = current_mp_addr + 2
			end

			local current_mp = memory.read_u16_le(current_mp_addr)
			local max_mp = memory.read_u16_le(max_mp_addr)

			if current_mp == max_mp then
				return false
			end

			current_mp = math.min(current_mp + (max_mp * 0.25), max_mp)
			memory.write_u16_le(current_mp_addr, current_mp)
		end
	},
	["haste"] = {
		cost = 5,
		name = "HASTE",
		desc = "Get hasted. Only available in battle",
		func = function(player)
			if not is_in_battle() then
				return false
			end

			local character_name = player["player_index"]
			local index = character_indexes[character_name]
			set_status(index, statuses.haste)
		end
	},
	["protect"] = {
		cost = 5,
		name = "PROTECT",
		desc = "Cast protect on yourself (half physical damage). Only available in battle",
		func = function(player)
			if not is_in_battle() then
				return false
			end

			local character_name = player["player_index"]
			local index = character_indexes[character_name]
			set_status(index, statuses.protect)
		end
	},
	["shell"] = {
		cost = 5,
		name = "SHELL",
		desc = "Cast shell on yourself (half magic damage). Only available in battle",
		func = function(player)
			if not is_in_battle() then
				return false
			end

			local character_name = player["player_index"]
			local index = character_indexes[character_name]
			set_status(index, statuses.shell)
		end
	},
	["reflect"] = {
		cost = 5,
		name = "REFLECT",
		desc = "Cast reflect on yourself (bounces spells to enemies). Only available in battle",
		func = function(player)
			if not is_in_battle() then
				return false
			end

			local character_name = player["player_index"]
			local index = character_indexes[character_name]
			set_status(index, statuses.reflect)
		end
	},
	-- this will get the character back up, but they're still frozen and untargetable
	--["revive"] = {
	--	cost = 10,
	--	name = "REVIVE",
	--	desc = "If dead, instantly revive with 1 hp",
	--	func = function(player)
	--		local character_name = player["player_index"]
	--		local character_index = character_indexes[character_name]
	--		local base_status_addr = 0x7E201A
	--		local battle_data_offset = character_battle_data_size * character_index
	--		local status_addr = base_status_addr + battle_data_offset
	--		local status = memory.read_u8(status_addr)
	--
	--		if bit.band(status, 0x80) then
	--			-- player is dead. revive them
	--			memory.write_u8(0x7E2006 + battle_data_offset, 1)
	--			memory.write_u8(status_addr, status - 0x80)
	--		else
	--			return false
	--		end
	--	end
	--}
	-- need to figure out how to trigger armor recalculation before armor changes take effect
	--["bonemail"] = {
	--	cost = 5,
	--	name = "BONE MAIL",
	--	desc = "Equip the Bone Mail for this battle.  Only available in battle.",
	--	func = function(player)
	--		local bone_mail_index = 0xBF
	--		local character_name = player["player_index"]
	--		local index = character_indexes[character_name]
	--
	--		local body_equipment_addr = 0x7E200F + (index * character_battle_data_size)
	--		local current_armor = memory.read_u8(body_equipment_addr)
	--
	--		if not is_in_battle() or current_armor == bone_mail_index then
	--			return false
	--		end
	--
	--		memory.write_u8(body_equipment_addr, bone_mail_index)
	--	end
	--}
	--["status_heal"] = {
	--	cost = 5,
	--	name = "STATUS HEAL",
	--	desc = "Removes most negative status effects",
	--	func = function(player)
	--		-- petrify, toad, poison, zombie, darkness
	--		-- maybe need to do a heal if zombie?
	--		-- curable status 0x40 + 0x20 + 0x10 + 0x04 + 0x02 + 0x01
	--
	--		-- aging, sleep, paralyze, charm, berserk, mute
	--		-- temporary status 0x80 + 0x40 + 0x20 + 0x10 + 0x08 + 0x04
	--
	--		-- stop, slow
	--		-- dispellable status 0x10 + 0x04
	--	end
	--}
}

for key, value in pairs(shop_item_customized) do
	if shop_items[key] ~= nil then
		if value.enabled ~= nil then
			shop_items[key].enabled = value.enabled
		end
		if value.cost ~= nil then
			shop_items[key].cost = tonumber(value.cost)
		end
	end
end

print(shop_items)
function get_ms_time()
	return socket.gettime() * 1000
end

function serialize_shop_data()
	local data = ""
	for key, value in pairs(shop_items) do
		if (value ~= nil and value.enabled ~= false) then
			data = data .. key .. "|" .. value.cost .. "|" .. value.desc .. "|" .. value.name .. "@"
		end
	end

	return data
end

function award_points(add_amount, awarded_to)
	for character_name, current_amount in pairs(character_points) do
		if character_name == awarded_to or awarded_to == nil then
			character_points[character_name] = current_amount + add_amount
			local player = players[character_name]
			if player ~= nil then
				player.socket:send("M" .. character_points[character_name] .. "\n")
			end
		end
	end

	update_point_labels()
	write_character_points()
end

-- loops through each player to process their messages
function handle_all_players()
	for index, player in pairs(players) do
		if player ~= nil then
			handle_player(index)
		end
	end
end

-- checks for new players connecting and sets them up
function connect()
	server:settimeout(0)

	local new_client, timeout = server:accept()

	if timeout == nil then
		print('Initial Connection Made')
		if pending_client == nil and new_client ~= nil then
			new_client:settimeout(0)
			pending_client = new_client
			pending_client_connect_time = get_ms_time()
		elseif new_client ~= nil then
			new_client:send("DF\n")
			new_client:close()
		end
	end

	if pending_client ~= nil then
		if get_ms_time() - pending_client_connect_time > pending_client_timeout then
			pending_client:close()
			pending_client = nil
			return
		end

		local data, err = pending_client:receive("*l")
		if err == nil then
			local command_type = string.sub(data, 0, 1)
			local payload = string.sub(data, 2, -1)
			if (command_type == "P" and payload == password) or password == "" then
				local player_index = find_available_player_slot()
				if player_index == "" then
					print("Disconnected: Lobby full")
					pending_client:send("DF" .. "\n") -- disconnect:full
					pending_client:close()
					pending_client = nil
				else
					local new_player = create_player(player_index, pending_client)
					new_player.socket:settimeout(0)
					new_player.socket:send("C" .. player_index .. "\n")
					new_player.socket:send("S" .. shop_data_text .. "\n")
					new_player.socket:send("M" .. character_points[player_index] .. "\n")
					players[player_index] = new_player

					print("Player " .. player_index .. " connected")
					update_kick_buttons()
				end
			else
				-- password not sent or wrong password
				print("Incorrect password")
				pending_client:close()
			end
			pending_client = nil
		end
	end
end

function create_player(index, socket)
	local new_player = {}
	new_player.socket        = socket
	new_player["name"]          = "Player " .. index
	new_player["last_received"] = get_ms_time()
	new_player["last_updated"]  = get_ms_time()
	new_player["player_index"]  = index
	new_player["inputs"]        = 0

	return new_player
end

function disconnect_player(index, code)
	local player = players[index]
	if player ~= nil then
		if code ~= nil then
			player.socket:send("D" .. code .. "\n")
		end
		player.socket:close()
		players[index] = nil

		update_kick_buttons()
	end
end

-- handles messages received from a player
function handle_player(index)
	local player = players[index]
	local data, err = player.socket:receive("*l")

	if not err then
		-- received something from the player
		player.last_received = get_ms_time()
		local command_type = string.sub(data, 0, 1)

		if command_type == "I" then
			-- inputs
			player.inputs = tonumber(string.sub(data, 2, -1))
			if player.inputs == nil then
				player.inputs = nil
			end
		elseif command_type == "R" then
			-- request a specific character
			local requested_character_name = string.sub(data, 2, -1)
			local valid_character = character_indexes[requested_character_name]
			local target_player = players[requested_character_name]
			if valid_character ~= nil and target_player == nil then
				-- requested a character and the slot is available. swap them
				players[requested_character_name] = player
				players[index] = nil
				players[requested_character_name]["player_index"] = requested_character_name
				player.socket:send("C" .. requested_character_name .. "\n")
				player.socket:send("M" .. character_points[requested_character_name] .. "\n")
				update_kick_buttons()
			end
		elseif command_type == "B" then
			-- buying something from the shop
			local item_id = string.sub(data, 2, -1)
			local item = shop_items[item_id]
			local character_bux = character_points[index]
			if item and item.cost <= character_bux then
				local result = item["func"](players[index])
				if (result ~= false) then
					print(index .." bought " .. item_id)
					award_points(-1 * item.cost, index)
				end
			end
			update_point_labels()
		elseif command_type == "N" then
			local name = string.sub(data, 2, max_player_name_size + 1)
			set_player_name(index, name)
			print("Update player " .. index .. " name to: " .. name)
		elseif command_type == "D" then
			-- disconnect
			print("Player " .. index .. " manual disconnect")
			disconnect_player(index)
		elseif command_type == "B" then
			-- buy something from the shop
		end
	else
		local time_since_last_data = get_ms_time() - player["last_received"]
		if time_since_last_data >= player_input_timeout then
			-- exceeded the input update interval. assume no input to avoid extending button presses
			player["inputs"] = 0
		end
		if time_since_last_data >= player_timeout_threshold then
			-- no data received in quite a while. disconnect the player
			print("Player " .. index .. " timeout")
			disconnect_player(index, "T")
		end
	end
end

-- determines which players should be in control based on the game state
-- combines inputs from those players and applies them
function process_input()
	find_character_positions()
	local final_input = 0
	local in_battle = is_in_battle()

	-- battle just started
	if in_battle and not was_in_battle then
		print("Battle Start")
		award_points(1)
	end

	-- battle just ended
	if not in_battle and was_in_battle then
		print("Battle End")
	end

	was_in_battle = in_battle

	local active_character_index = 0xFFFF

	if in_battle then
		active_character_index = get_active_character_index()

		if last_active_character ~= active_character_index then
			-- don't register the character as switched until character_switch_timer frames have passed since the last switch
			time_in_control = get_ms_time()
			control_override = false
			print("Active Character: " .. active_character_index)
		end

		if not control_override and get_ms_time() - time_in_control > max_time_in_control then
			-- player took too long to act. give everyone control for this turn as a failsafe
			control_override = true
			print("Turn timeout. Everyone has control.")
		end

		last_active_character = active_character_index
	else
		time_in_control = get_ms_time()
		control_override = false
	end

	-- who's in control calculated for this frame
	local current_control_bits = 0

	-- consolidate the inputs from each player that's in control
	for index, player in pairs(players) do
		local is_active_character = active_character_index == index
		local active_character_has_player = players[active_character_index] ~= nil
		local player_has_battle_control = is_active_character or not active_character_has_player
		local i = character_indexes[index]

		if player == nil then
			-- do nothing
		elseif not in_battle or (in_battle and player_has_battle_control) or control_override then
			-- either not in battle and chaos reigns
			-- or in battle and that player's character is active
			-- or the character has no player and everyone can control them
			-- or the player took too long and triggered a failsafe to give everyone control
			final_input = bit.bor(final_input, player["inputs"])
			current_control_bits = current_control_bits + (2^i)
		end
	end

	-- if the control status has changed, update players
	if current_control_bits ~= control_bits then
		print("send control updates " .. current_control_bits)
		send_control_updates(current_control_bits)
		control_bits = current_control_bits
	end

	num_players_connected = 0
	for _, value in pairs(players) do
		if value ~= nil then
			num_players_connected = num_players_connected + 1
		end
	end

	-- if no one is connected let the host control the game directly
	if num_players_connected > 0 then
		local inputs_table = generate_inputs_table(final_input)
		joypad.set(inputs_table, 1)

		if show_input then
			draw_inputs()
		end
	end
end

function process_mods()
	if low_encounter_rate and not was_in_battle then
		memory.write_u8(0x7E16A9, 1)
	end

	-- always give the dash ability
	local innate = memory.read_u8(player_1_innate_abilities_addr)
	memory.write_u8(player_1_innate_abilities_addr, bit.bor(innate, 0x08))
end

local video_enabled = false
local frames_per_second = 10
local last_frame_time = get_ms_time()
local video_enabled_checkbox = forms.checkbox(control_form, "Send Video", 10, 230)

forms.addclick(video_enabled_checkbox, function()
	video_enabled = not video_enabled
end)

function process_video()
	if true then
		return
	end

	if video_enabled and num_players_connected > 0 and get_ms_time() - last_frame_time > 1000 / frames_per_second then
		last_frame_time = get_ms_time()
		local frame_file_path = "img/sc.png"
		client.screenshot(frame_file_path)
		local file = io.open(frame_file_path, "rb")
		if file then
			local image_data = file:read("*all")
			--print(image_data)
			--video_enabled = false
			send_frame(image_data)
			--file:close()
		end
	end
end

function send_frame(frame_data)
	for _, player in pairs(players) do
		local data_length = tostring(string.len(frame_data))
		while string.len(data_length) < 6 do
			data_length = "0" .. data_length
		end
		player.socket:send("F" .. data_length .. frame_data)
	end
end

function generate_inputs_table(input_bits)
	local pressed_keys = {}
	for key, value in pairs(button_masks) do
		pressed_keys[key] = bit.band(input_bits, value) > 0
	end

	return pressed_keys
end

-- figure out which character is in which slot
-- results stored in character_positions, indexed by character name
function find_character_positions()
	local character_data_addresses = {0x7E0500, 0x7E0550, 0x7E05A0, 0x7E05F0}

	has_krile = false
	for key, value in pairs(character_data_addresses) do
		-- only the first 3 bits determine the character id
		local character_id = tostring(bit.band(memory.read_u8(value), 0x7))

		if character_id == "4" then
			 has_krile = true
		 end

		if character_ids[character_id] ~= nil then
			local character_name = character_ids[character_id]
			character_positions[character_name] = key
		end
	end
end

-- updates connected clients with who's in control
-- takes a 4 bit value representing whether each of the 4 players is in control
-- this sort of depends on the order of character_indexes. hopefully that's not a problem?
function send_control_updates(bits)
	local all_in_control = true
	local active_name = ""

	for key, value in pairs(character_indexes) do
		local bit_mask = 2^value
		local player = players[key]
		if player ~= nil then
			local control_value = "0"
			if bit.band(bits, bit_mask) > 0 then
				control_value = "1"
				active_name = player.name
			else
				all_in_control = false
			end

			player.socket:send("I" .. control_value .. "\n")
		end
	end

	if all_in_control then
		forms.settext(in_control_name_label, "Everyone")
	else
		forms.settext(in_control_name_label, active_name)
	end
end

-- figure out which character is currently active in battle and return their name
function get_active_character_index()
	local active_character_index = ""

	-- 0 = Bartz, 1 = Lenna, 2 = Galuf/Krile, 3 = Faris
	local active_character_code = memory.read_u8(active_character_index_addr) + 1

	for key, value in pairs(character_positions) do
		-- look through the characters to see which is in the active slot
		if value == active_character_code then
			return key
		end
	end

	return active_character_index
end

function show_players()
	print(players["Bartz"])
	print(players["Lenna"])
	print(players["Galuf"])
	print(players["Faris"])
end

-- index of the first player slot that isn't filled. returns an empty string if none found
function find_available_player_slot()
	for index, name in pairs(character_names) do
		local player = players[name]
		if player == nil then
			return name
		end
	end

	return ""
end

-- whether the party is currently in battle
function is_in_battle()
	local battle_status = memory.read_u8(battle_status_addr)
	local battle_over_flag = memory.read_u8(battle_over_flag_addr)
	return battle_status ~= 0 and battle_over_flag == 0
end

-- updates the character's name in-game
function set_player_name(index, name)
	if character_indexes[index] == nil then
		print("No character index for " .. index)
		return
	end

	local name_bytes = convert_text(name)

	-- starting address of the name for the specified character
	local name_address_offset = 6 * character_indexes[index]

	-- ugly hack to update Krile's name if she's in the party
	if index == "Galuf" and has_krile then
		name_address_offset = name_address_offset + 12
	end

	-- copy each byte individually
	for i=1,max_player_name_size do
		local char_index = names_base_addr + name_address_offset + i - 1
		memory.write_u8(char_index, name_bytes[i])
	end

	local player = players[index]
	if player ~= nil then
		player["name"] = name
	end

	update_kick_buttons()
end

function load_character_points()
	local points_file = io.open("character_points.dat", "r")
	character_points["Bartz"] = tonumber(points_file:read("*l"))
	character_points["Lenna"] = tonumber(points_file:read("*l"))
	character_points["Galuf"] = tonumber(points_file:read("*l"))
	character_points["Faris"] = tonumber(points_file:read("*l"))
end

function write_character_points()
	local points_file = io.open("character_points.dat", "w")
	points_file:write(character_points["Bartz"] .. "\n")
	points_file:write(character_points["Lenna"] .. "\n")
	points_file:write(character_points["Galuf"] .. "\n")
	points_file:write(character_points["Faris"] .. "\n")
end

function update_point_labels()
	for character_name, label in pairs(character_points_labels) do
		forms.settext(label, character_name .. ": " .. character_points[character_name] .. " points")
	end
end

-- update the buttons on the control panel to show current character/player names
function update_kick_buttons()
	for index, button in pairs(kick_buttons) do
		local value = "------"
		local player = players[index]

		if player ~= nil then
			value = "Kick " .. player["name"] .. " (" .. index .. ")"
		end

		forms.settext(kick_buttons[index], value)
	end
end
-- converts the 5 character name to ff5's weird character encoding
-- maybe make a lookup table for this instead?
-- SNES
-- https://tasvideos.org/Bizhawk/LuaFunctions
-- https://www.ff6hacking.com/ff5wiki/index.php/FFV_RAM_map
-- 0x53 = 0, 0x5C = 9
-- 0x60 = A,0x79 = Z
-- 0x7A = a, 0x93 = z
function convert_text(name)
	local characters = {}
	for i=1, max_player_name_size do
		characters[i] = 0xFF
	end

	local name_length = string.len(name)

	for i=1, max_player_name_size do
		if name_length >= i then
			local char_value = string.byte(string.sub(name, i, i + 1))
			local char_offset = 0
			if char_value >= string.byte("A") and char_value <= string.byte("Z") then
				characters[i] = char_value - string.byte("A") + upper_offset
			elseif char_value >= string.byte("a") and char_value <= string.byte("z") then
				characters[i] = char_value - string.byte("a") + lower_offset
			elseif char_value >= string.byte("0") and char_value <= string.byte("9") then
				characters[i] = char_value - string.byte("0") + number_offset
			else
				-- invalid character. use default 0xFF value, which represents a space
			end
		end
	end

	return characters
end

function draw_inputs()
	local i = 5
	local input_height = 15

	for index, player in pairs(players) do
		local input = player["inputs"]

		gui.text(5, i, index)
		draw_single_input(60 + 5, i, "DU", input, button_masks.Up)
		draw_single_input(60 + 35, i, "DD", input, button_masks.Down)
		draw_single_input(60 + 65, i, "DL", input, button_masks.Left)
		draw_single_input(60 + 95, i, "DR", input, button_masks.Right)
		draw_single_input(60 + 125, i, "A", input, button_masks.A)
		draw_single_input(60 + 145, i, "B", input, button_masks.B)
		draw_single_input(60 + 165, i, "X", input, button_masks.X)
		draw_single_input(60 + 185, i, "Y", input, button_masks.Y)
		draw_single_input(60 + 205, i, "L", input, button_masks.R)
		draw_single_input(60 + 225, i, "R", input, button_masks.L)
		draw_single_input(60 + 245, i, "ST", input, button_masks.Start)
		draw_single_input(60 + 275, i, "SE", input, button_masks.Select)
		i = i + input_height
	end
end

function draw_single_input(x, y, text, input, bitmask)
	local color = red_label
	if bit.band(input, bitmask) > 0 then
		color = green_label
	end

	gui.text(x, y, text, color)
end

-------------------------------------------
-- Host control form stuff

function toggle_server()
   if server == nil then
	   start_server()
   else
	   stop_server()
   end
end

-- button to start or stop the server
local toggle_server_button = forms.button(control_form, "Start Server", toggle_server, 10, 55, 210, 30)

local button_positions = {{10, 90}, {120, 90}, {10, 130}, {120, 130}}
local button_index = 1

-- create buttons to kick players
for index, name in pairs(character_names) do
	local click_handler = function(a)
		if players[name] ~= nil then
			print("Kicked " .. players[name]["name"] .. "(" .. name .. ")")
			disconnect_player(name, "K")
		end
	end
	local position = button_positions[button_index]
	button_index = button_index + 1
	kick_buttons[name] = forms.button(control_form, "------", click_handler, position[1], position[2], 100, 40)
end

-- start listening for incomming connections
function start_server()
	if server ~= nil then
		print("Server is already active")
		return
	end

	local port_text = forms.gettext(port_textbox)
	local port = tonumber(port_text)
	if port > 1 and port < 65535 then
		server, error = socket.bind("*", port)
		if server then
			print("Server started on port " .. port)
			forms.setproperty(server_status_label, "ForeColor", green_label)
			forms.settext(server_status_label, "Server Online")
		end
	end

	password = forms.gettext(password_textbox)
	forms.settext(toggle_server_button, "Stop Server")
end

-- disconnect and wipe all clients and stop listening on the server's port
function stop_server()
	if server == nil then
		print("Server is not active")
	end

	for index, player in pairs(players) do
		player.socket:close()
		players[index] = nil
	end

	server:close()
	server = nil
	password = ""

	forms.setproperty(server_status_label, "ForeColor", red_label)
	forms.settext(server_status_label, "Server Offline")

	forms.settext(toggle_server_button, "Start Server")

	update_kick_buttons()
end
-------------------------------------------


function main()
	if gameinfo.getromhash() == "" then
		print("Waiting for FF5 ROM to be loaded")
		while gameinfo.getromhash() == "" do
			emu.frameadvance()
		end
	end

	shop_data_text = serialize_shop_data()
	load_character_points()
	update_point_labels()

	while true do
		if server ~= nil then
			handle_all_players()
			connect()
			process_input()
			process_mods()
			process_video()
		end

		emu.frameadvance()
	end
end

main()
