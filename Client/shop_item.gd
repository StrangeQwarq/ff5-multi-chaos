extends Panel

@onready var item_name_label = $ItemName
@onready var item_description_label = $ItemDescription
@onready var item_cost_label = $ItemCost

var item_id = ""
var item_cost = 0
var client:FF5Client = null

func set_client(c:FF5Client):
	client = c

func set_data(id:String, name:String, description:String, cost:String):
	item_id = id
	item_cost = cost.to_int()
	item_name_label.text = name
	item_description_label.text = description
	item_cost_label.text = cost + " GB"

func buy_item():
	if client.current_gregbux >= item_cost:
		client.set_pending_purchase(item_name_label.text, item_cost)
		client.send_message("B" + item_id)
		#client.current_gregbux -= item_cost
		#client.item_purchased.emit()


func _on_buy_button_pressed() -> void:
	buy_item()
