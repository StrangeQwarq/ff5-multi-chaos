extends Node2D

class_name FF5Client

signal item_purchased

@onready var main_ui: CanvasLayer = $UI
@onready var connect_form: CanvasLayer = $ConnectForm

# server connection form
@onready var server_ip_input:LineEdit = $ConnectForm/ConnectFields/ServerIP/ServerIPInput
@onready var server_port_input:LineEdit = $ConnectForm/ConnectFields/ServerPort/ServerPortInput
@onready var password_input:LineEdit = $ConnectForm/ConnectFields/Password/PasswordInput
@onready var preferred_char_input:OptionButton = $ConnectForm/ConnectFields/PreferredCharacter/PreferredCharacterInput

@onready var player_name_input:LineEdit = $UI/VBoxContainer/PlayerName/PlayerNameInput
@onready var player_name_input_connect:LineEdit = $ConnectForm/ConnectFields/PlayerName/PlayerNameInput

# connect/disconnect. only one is displayed at a time
@onready var connect_button:Button = $ConnectForm/ConnectButton
@onready var disconnect_button:Button = $UI/Buttons/DisconnectButton
@onready var disconnect_button2:Button = $ConnectForm/DisconnectButton

# stores a log of important data
@onready var log_area:TextEdit = $UI/Log
@onready var log_area_connect:TextEdit = $ConnectForm/Log

# stops checking input when checked, in case the player needs keyboard interaction elsewhere
@onready var disable_input_checkbox:CheckBox = $UI/DisableInput/DisableInputCheckbox

@onready var player_sprite:TextureRect = $UI/CharacterIndexLabel/PlayerSprite

@onready var in_control_label:Label = $UI/ControlStatusLabel
@onready var character_index_label:Label = $UI/CharacterIndexLabel

@onready var sandworm_animator = $UI/Control/Sprite2D/AnimationPlayer
@onready var sandworm_button = $UI/SandwormButton

@onready var video = $UI/VideoPanel/VideoTexture

@onready var shop_root = $UI/Shop
@onready var shop_item_list = $UI/Shop/ShopScroll/ShopItemList
@onready var gregbux_count_label = $UI/GregBuxCount

@onready var help_panel = $HelpAndInfo/HelpPanel

# When clicking buy on an item, remember what it was so that the response
# with the updated gregbux count can be checked to see if it succeeded
var pending_purchase_name = null
var pending_purchase_cost = null

var shop_item_scene = preload("res://shop_item.tscn")

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
var no_input_refresh_interval:float = 0.25

# how long since the last time the the user's input changed
var time_since_last_input:float = 0

var sandworm_clicked_count:int = 0

var shop_items = []

var current_gregbux:int = 69

var frame_data:PackedByteArray = PackedByteArray()
var frame_size:int

# log some text to the big TextEdit field
func client_log(text:String):
	log_area.text += text + "\n";
	log_area.scroll_vertical = log_area.get_v_scroll_bar().max_value
	log_area_connect.text = log_area.text
	log_area.scroll_vertical = log_area_connect.get_v_scroll_bar().max_value


func try_connecting():
	var ip:String   = server_ip_input.text
	var port:int = server_port_input.text.to_int()
	var name:String = player_name_input_connect.text

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
	socket.set_no_delay(true)
	main_ui.hide()
	connect_form.show()
	disconnect_button2.hide()
	help_panel.hide()
	item_purchased.connect(update_gregbux_count)


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
				disconnect_button2.show()
				client_log("Connecting...")
			socket.STATUS_ERROR:
				connect_button.show()
				disconnect_button2.hide()
				client_log("Connection error")
			socket.STATUS_CONNECTED:
				main_ui.show()
				connect_form.hide()
				connect_button.hide()
				disconnect_button2.show()
				send_password_message()
				send_character_message()
				send_name_message(player_name_input_connect.text)
				client_log("Connected!")

	if status == socket.STATUS_CONNECTED:
		var num_bytes:int = socket.get_available_bytes()
		if num_bytes > 0:
			var raw_data: = socket.get_partial_data(num_bytes)
			var raw_size = raw_data[1].size()
			var data:String = PackedByteArray(raw_data[1]).get_string_from_ascii()

			# Start of frame data
			#if raw_data[1][0] == "F".to_utf8_buffer()[0]: #0x89:
				#frame_size = int(data.substr(1, 6))
				#if num_bytes < frame_size:
					## Only part of the frame is here
					## store current data wait for more to come in
					#var remaining_data_size = frame_size - frame_data.size()
					#frame_data.append_array(raw_data[1].slice(7))
				#else:
					## The whole frame is available
					#draw_video_frame(raw_data[1].slice(7))
				#return
#
			## Additional frame data
			#if frame_size > 0 && frame_data.size() <= frame_size:
				#var stop = true
				#var remaining_data_size = frame_size - frame_data.size()
				#if (raw_data.size() <= remaining_data_size):
					## Still not enough data, but load what we have
					#frame_data.append_array(raw_data[1])
				#else:
					## We have at least enough data for the frame. Load the remaining amount
					#frame_data.append_array(raw_data[1].slice(0, remaining_data_size))
					#data = raw_data[1].slice(remaining_data_size)
					#stop = false
#
				#if (frame_data.size() == frame_size):
					#draw_video_frame(frame_data)
#
				#if (stop):
					#return

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
					"S":
						# get shop data
						shop_items = parse_shop_data(message.substr(1))
						redraw_shop()
					"M":
						var previous_gregbux = current_gregbux
						current_gregbux = message.substr(1).to_int()
						if (pending_purchase_name):
							if (current_gregbux <= previous_gregbux):
								client_log("Purchased " + pending_purchase_name + " for " + str(pending_purchase_cost) + "GB")

							pending_purchase_name = null
							pending_purchase_cost = null
						item_purchased.emit()
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
	player_name_input.text = player_name_input_connect.text
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


func send_name_message(name:String = "") -> void:
	if (name.length() == 0):
		name = player_name_input.text

	var command := "N" + name.substr(0, 6)
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

func parse_shop_data(raw_shop_data:String):
	var temp_shop_items = []
	var item_string_list := raw_shop_data.split("@")
	for item_string in item_string_list:
		if item_string.length() == 0:
			continue

		var item_string_details = item_string.split("|")
		var item_dict := {
			"id": item_string_details[0],
			"cost": item_string_details[1],
			"desc": item_string_details[2],
			"name": item_string_details[3]
		}

		temp_shop_items.append(item_dict)
	return temp_shop_items

func redraw_shop():
	for child in shop_item_list.get_children():
		shop_item_list.remove_child(child)

	for item in shop_items:
		var new_item_scene = shop_item_scene.instantiate()
		shop_item_list.add_child(new_item_scene)
		new_item_scene.set_client(self)
		new_item_scene.set_data(item["id"], item["name"], item["desc"], item["cost"])

func server_disconnect(reason:String):
	send_disconnect_message()
	socket.disconnect_from_host()
	player_index = ""
	in_control_label.text = ""
	set_character_index(player_index)
	connect_button.show()
	disconnect_button2.hide()
	player_sprite.texture = null
	video.texture = null
	gregbux_count_label.hide()
	shop_items = []
	redraw_shop()
	main_ui.hide()
	connect_form.show()
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


func draw_video_frame(frame_data:PackedByteArray):
	var frame = Image.create(256, 244, false, Image.FORMAT_RGBA8)
	frame.load_png_from_buffer(frame_data)
	var texture = ImageTexture.create_from_image(frame)
	video.texture = texture
	frame_size = 0
	frame_data.clear()


func set_in_control():
	in_control_label.text = "YOU'RE IN CONTROL"
	in_control_label.label_settings.font_color = Color.GREEN


func set_not_in_control():
	in_control_label.text = "YOU'RE NOT IN CONTROL"
	in_control_label.label_settings.font_color = Color.RED

func update_gregbux_count():
	gregbux_count_label.show()
	gregbux_count_label.text = str(current_gregbux) + " GregBux"

func set_pending_purchase(name, cost):
	pending_purchase_name = name
	pending_purchase_cost = cost


func _on_change_name_pressed() -> void:
	send_name_message()


func _on_disconnect_button_pressed() -> void:
	server_disconnect("M")


func _on_clear_log_pressed() -> void:
	log_area.text = ""
	log_area_connect.text = ""


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


func _on_tab_bar_tab_changed(tab: int) -> void:
	if tab == 0:
		shop_root.show()
		log_area.hide()
	else:
		shop_root.hide()
		log_area.show()


func _on_link_button_pressed() -> void:
	if (help_panel.visible):
		help_panel.hide()
	else:
		help_panel.show()


func _on_close_help_button_pressed() -> void:
	help_panel.hide()


func _on_help_text_meta_clicked(meta: Variant) -> void:
	OS.shell_open(str(meta))
