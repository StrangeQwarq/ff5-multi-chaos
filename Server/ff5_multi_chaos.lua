local socket = require("socket")


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

-- battle status. 0x0 = in battle, other values indicate battle results
local battle_status_addr = 0x7E7BDE

-- address of the current encounter. up to 0x1FF is valid, only valid in battle.
local battle_encounter_id_addr = 0x7E04F0

-- start of the player names. each one is 6 bytes with a 0xFF terminator
local names_base_addr = 0x7E0990

-- indicates the position of the character that's active, 0x180 and smaller means a player
local active_character_index_addr = 0x7E010D --0x7E0032

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
local control_form = forms.newform(250, 260, "FF5 Multi-Chaos Control Panel")

-- encounter counter 0x7e16a9

-- handle to the textbox for setting the port
local port_textbox = forms.textbox(control_form, "32024", 100, 30, "UNSIGNED", 10, 30, false)
local port_label   = forms.label(control_form, "Server Port", 10, 10, 100, 20)

-- handle to the textbox for setting the server password
local password_textbox = forms.textbox(control_form, "", 100, 10, nil, 120, 30, false)
local password_label   = forms.label(control_form, "Server Password", 120, 10, 100, 20)

-- colors for the server status label
local red_label = forms.createcolor(200, 30, 30, 255)
local green_label = forms.createcolor(30, 200, 30, 255)

local server_status_label = forms.label(control_form, "Server Offline", 10, 170, 200, 20)
forms.setproperty(server_status_label, "ForeColor", red_label)
forms.setproperty(server_status_label, "TextAlign", 2)

-- buttons used to kick players
local kick_buttons = {["Bartz"] = nil, ["Lenna"] = nil, ["Galuf"] = nil, ["Faris"] = nil}

local low_encounter_rate = false
forms.label(control_form, "Lower Encounter Rate", 25, 195, 200, 20)
local encounter_rate_checkbox = forms.checkbox(control_form, "", 10, 190)
forms.addclick(encounter_rate_checkbox, function()
	low_encounter_rate = not low_encounter_rate
end)

-- dummy out the bizhawk tables when testing outisde of bizhawk
if emu == nil then
	emu = {}
	function emu.frameadvance()
		socket.sleep(0.1)
	end
end

if gameinfo == nil then
	gameinfo = {}
	function gameinfo.getromhash()
		return "x"
	end
end

if joypad == nil then
	joypad = {}
	function joypad.set(t)
	   return
	end
end

if bit == nil then
	bit = {}
	function bit.band(val, val2)
	   return val
	end

	function bit.bor(val, val2)
		return val
	end
end

if memory == nil then
	memory = {}
	function memory.read_u8(addr)
		return 0
	end

	function memory.read_u16_be(addr)
		return 666
	end

	function memory.read_u16_le(addr)
		return 666
	end

	function memory.write_u8(addr, val)
		return
	end
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
			new_client:send("DF")
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
					show_players()
				else
					local new_player = create_player(player_index, pending_client)
					new_player["socket"]:settimeout(0)
					new_player["socket"]:send("C" .. player_index .. "\n")
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
	new_player["socket"]        = socket
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
			player["socket"]:send("D" .. code .. "\n")
		end
		player["socket"]:close()
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
		player["last_received"] = get_ms_time()
		local command_type = string.sub(data, 0, 1)

		if command_type == "I" then
			-- inputs
			player["inputs"] = tonumber(string.sub(data, 2, -1))
			if player["inputs"] == nil then
				player["inputs"] = nil
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
				player["socket"]:send("C" .. requested_character_name .. "\n")
				update_kick_buttons()
			end
		elseif command_type == "N" then
			local name = string.sub(data, 2, max_player_name_size + 1)
			set_player_name(index, name)
			print("Update player " .. index .. " name to: " .. name)
		elseif command_type == "D" then
			-- disconnect
			print("Player " .. index .. " manual disconnect")
			disconnect_player(index)
			show_players()
		end
	else
		local time_since_last_data = get_ms_time() - player["last_received"]
		if time_since_last_data >= player_input_timeout then
			-- exceeded the input update interval. assume no input to avoid extending button presses
			player["inputs"] = 0
		elseif time_since_last_data >= player_timeout_threshold then
			-- no data received. see if the player has timed out
			print("Player " .. index .. " timeout")
			disconnect_player(index, "T")
		show_players()
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

	local has_players = false
	for _, value in pairs(players) do
		if value ~= nil then
			has_players = true
		end
	end

	-- if no one is connected let the host control the game directly
	if has_players then
		local inputs_table = generate_inputs_table(final_input)
		joypad.set(inputs_table, 1)
		draw_inputs()
	end
end

function process_mods()
	if low_encounter_rate and not was_in_battle then
		memory.write_u8(0x7E16A9, 1)
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
	for key, value in pairs(character_indexes) do
		local bit_mask = 2^value
		local player = players[key]
		if player ~= nil then
			local control_value = "0"
			if bit.band(bits, bit_mask) > 0 then
				control_value = "1"
			end

			player["socket"]:send("I" .. control_value .. "\n")
		end
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

function get_ms_time()
	return socket.gettime() * 1000
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
	local encounter_id  = memory.read_u16_le(battle_encounter_id_addr)
	current_enemy_formation = encounter_id

	return battle_status == 0 and encounter_id <= 0x1FF
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
		player["socket"]:close()
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

	while true do
		if server ~= nil then
			handle_all_players()
			connect()
			process_input()
			process_mods()
		end

		emu.frameadvance()
	end
end

main()
