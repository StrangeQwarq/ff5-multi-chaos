extends Node2D

# server connection form
@onready var server_ip_input:LineEdit = $UI/VBoxContainer/ServerIP/ServerIPInput
@onready var server_port_input:LineEdit = $UI/VBoxContainer/ServerPort/ServerPortInput
@onready var player_name_input:LineEdit = $UI/VBoxContainer/PlayerName/PlayerNameInput
@onready var password_input:LineEdit = $UI/VBoxContainer/Password/PasswordInput

# preferred character dropdown
@onready var preferred_char_input:OptionButton = $UI/VBoxContainer/PreferredCharacter/PreferredCharacterInput

# connect/disconnect. only one is displayed at a time
@onready var connect_button:Button = $UI/Buttons/ConnectButton
@onready var disconnect_button:Button = $UI/Buttons/DisconnectButton

# stores a log of important data
@onready var log_area:TextEdit = $UI/Log

# stops checking input when checked, in case the player needs keyboard interaction elsewhere
@onready var disable_input_checkbox:CheckBox = $UI/DisableInputCheckbox

@onready var player_sprite:TextureRect = $UI/CharacterIndexLabel/PlayerSprite

@onready var in_control_label:Label = $UI/ControlStatusLabel
@onready var character_index_label:Label = $UI/CharacterIndexLabel

@onready var sandworm_animator = $UI/Control/Sprite2D/AnimationPlayer
@onready var sandworm_button = $UI/SandwormButton

# various data about each input. keys are bit masks, button is the display/mouse input for each input
# input_name is the identifier for Godot's input map
@onready var input_labels = {
	1:    {"button": $UI/ControlDisplay/InputUp,     "input_name": "snes_up"},
	2:    {"button": $UI/ControlDisplay/InputDown,   "input_name": "snes_down"},
	4:    {"button": $UI/ControlDisplay/InputLeft,   "input_name": "snes_left"},
	8:    {"button": $UI/ControlDisplay/InputRight,  "input_name": "snes_right"},
	16:   {"button": $UI/ControlDisplay/InputA,      "input_name": "snes_a"},
	32:   {"button": $UI/ControlDisplay/InputB,      "input_name": "snes_b"},
	64:   {"button": $UI/ControlDisplay/InputX,      "input_name": "snes_x"},
	128:  {"button": $UI/ControlDisplay/InputY,      "input_name": "snes_y"},
	256:  {"button": $UI/ControlDisplay/InputR,      "input_name": "snes_r"},
	512:  {"button": $UI/ControlDisplay/InputL,      "input_name": "snes_l"},
	1024: {"button": $UI/ControlDisplay/InputStart,  "input_name": "snes_start"},
	2048: {"button": $UI/ControlDisplay/InputSelect, "input_name": "snes_select"}
}

@onready var player_textures = {
	"bartz": preload("res://img/bartz.png"),
	"lenna": preload("res://img/lenna.png"),
	"galuf": preload("res://img/galuf.png"),
	"faris": preload("res://img/faris.png")
}

# socket connected to the FF5 server
var socket := StreamPeerTCP.new()

# socket status from the previous frame
var previous_status:StreamPeerTCP.Status = socket.STATUS_NONE

# most recent name that was sent to the server
var previous_name:String = ""

# name of the character the player has been assigned after connection
var player_index:String = ""

# bit field of all inputs from the last frame
var last_input:int = 0

# re-send the current input if the user hasn't pressed anything for some number of seconds
var no_input_refresh_interval:float = 0.5

# how long since the last time the the user's input changed
var time_since_last_input:float = 0

var sandworm_clicked_count:int = 0

# log some text to the big TextEdit field
func client_log(text:String):
	log_area.text += text + "\n";
	log_area.scroll_vertical = log_area.get_v_scroll_bar().max_value


func try_connecting():
	var ip:String   = server_ip_input.text
	var port:int = server_port_input.text.to_int()
	var name:String = player_name_input.text

	if ip.length() < 8:
		client_log("Please enter the server IP address")
		return

	if port <= 0 || port >= 65536:
		client_log("Please enter the server port")
		return

	if name.length() == 0:
		client_log("Please enter a player name")
		return

	client_log("Connecting to " + ip + ":" + str(port))

	if socket.get_status() == socket.STATUS_CONNECTING:
		socket.disconnect_from_host()

	var result = socket.connect_to_host(ip, port)
	if result != OK:
		client_log("Error connecting to server:" + result)


func _ready() -> void:
	disconnect_button.hide()


func poll_input() -> void:
	var i:int = get_input()
	client_log("I: " + str(i))


func _process(delta:float) -> void:
	socket.poll()
	var status = socket.get_status()
	if 	status != previous_status:
		previous_status = status
		match status:
			socket.STATUS_NONE:
				server_disconnect("C")
			socket.STATUS_CONNECTING:
				connect_button.hide()
				disconnect_button.show()
				client_log("Connecting...")
			socket.STATUS_ERROR:
				connect_button.show()
				disconnect_button.hide()
				client_log("Connection error")
			socket.STATUS_CONNECTED:
				connect_button.hide()
				disconnect_button.show()
				send_password_message()
				send_character_message()
				send_name_message()
				client_log("Connected!")

	if status == socket.STATUS_CONNECTED:
		var num_bytes:int = socket.get_available_bytes()
		if num_bytes > 0:
			var raw_data = socket.get_partial_data(num_bytes)
			var data:String = PackedByteArray(raw_data[1]).get_string_from_ascii()
			var messages:PackedStringArray = data.split("\n")

			for message in messages:
				if message.length() == 0:
					continue

				match message[0]:
					"C":
						# client connected. get player index
						var id:String = message.substr(1)
						if id.length() != 5:
							client_log("Warning: invalid character index")

						client_log("Connected (player id:" + id + ")")
						set_character_index(id)
					"D":
						# disconnected
						server_disconnect(message[1])
					"I":
						# player gains or loses control
						if message[1] == "1":
							set_in_control()
						else:
							set_not_in_control()

		time_since_last_input += delta
		var input_bits:int = get_input()
		if last_input != input_bits || time_since_last_input >= no_input_refresh_interval:
			time_since_last_input = 0

			# If input is disabled keep sending 0 to keep the connection alive
			if disable_input_checkbox.button_pressed:
				send_input_message(0)
			else:
				send_input_message()

		last_input = input_bits


func get_input() -> int:
	var input_bits:int = 0

	for key in input_labels:
		var input_data = input_labels[key]
		var bit := 0

		if Input.is_action_pressed(input_data.input_name) || input_data["button"].button_pressed == true:
			bit = key

		input_data["button"].modulate = Color.GREEN if bit > 0 else Color.WHITE
		input_bits += bit

	return input_bits


func _on_connect_button_pressed() -> void:
	try_connecting()


func set_character_index(index:String) -> void:
	index = index.substr(0, 5)
	player_index = index
	if index.length() == 0:
		character_index_label.text = ""
	else:
		character_index_label.text = "Your character: " + index

	var lower_index = index.to_lower()
	if player_textures.has(lower_index):
		player_sprite.texture = player_textures[lower_index]


func send_input_message(input_bits = null) -> void:
	if input_bits == null:
		input_bits = get_input()
	var message := "I" + str(input_bits)
	send_message(message)


func send_name_message() -> void:
	var name := player_name_input.text.substr(0, 6)
	var command := "N" + name
	client_log("Changing name to " + name)
	send_message(command)


func send_character_message():
	var msg = "R" + preferred_char_input.get_item_text(preferred_char_input.selected).substr(0, 5)
	send_message(msg)

func send_password_message():
	var pw = "P" + password_input.text
	send_message(pw)


func send_disconnect_message():
	client_log("Disconnecting...")
	send_message("D")


func send_message(msg:String, log:bool = false):
	if socket.get_status() == socket.STATUS_CONNECTED:
		# server separates messaged based on \n\r
		if log:
			client_log("Sending: " + msg)
		msg = msg.strip_escapes() + "\n\r"
		var msg_buffer = msg.to_utf8_buffer()
		socket.put_data(msg_buffer)


func server_disconnect(reason:String):
	send_disconnect_message()
	socket.disconnect_from_host()
	player_index = ""
	in_control_label.text = ""
	set_character_index(player_index)
	connect_button.show()
	disconnect_button.hide()
	player_sprite.texture = null
	match reason[0]:
		"C":
			client_log("Disconnected (socket closed)")
		"T":
			client_log("Disconnected (timed out)")
		"F":
			client_log("Disconnected (lobby full)")
		"P":
			client_log("Disconnected (invalid password)")
		"M":
			client_log("Disconnected (by client)")


func set_in_control():
	in_control_label.text = "YOU'RE IN CONTROL"
	in_control_label.label_settings.font_color = Color.GREEN


func set_not_in_control():
	in_control_label.text = "YOU'RE NOT IN CONTROL"
	in_control_label.label_settings.font_color = Color.RED


func _on_change_name_pressed() -> void:
	send_name_message()


func _on_disconnect_button_pressed() -> void:
	server_disconnect("M")


func _on_clear_log_pressed() -> void:
	log_area.text = ""


func _on_sandworm_button_pressed() -> void:
	var dive_time = 1 + min(5, sandworm_clicked_count)
	sandworm_clicked_count += 1
	sandworm_button.disabled = true

	sandworm_animator.play("hide")
	await sandworm_animator.animation_finished
	await get_tree().create_timer(dive_time).timeout

	if sandworm_clicked_count == 5:
		disable_input_checkbox.button_pressed = true
		sandworm_button.disabled = true
		return

	sandworm_animator.play("show")
	await sandworm_animator.animation_finished

	sandworm_button.disabled = false
