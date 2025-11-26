extends Node

var is_multiplayer: bool = false
var my_faction: String = "blue"
const PORT = 7777
const DEFAULT_IP = "127.0.0.1"

func reset():
	is_multiplayer = false
	my_faction = "blue"
