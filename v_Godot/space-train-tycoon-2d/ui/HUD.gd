extends CanvasLayer
## HUD — the 2D UI layer (composites on top of the world; the JS "HD text overlay
## composited last" hack is just native layer order here). Hosts the chrome.

const Chrome := preload("res://ui/Chrome.gd")
const PopupManager := preload("res://ui/PopupManager.gd")
const Tutorial := preload("res://ui/Tutorial.gd")

func _ready() -> void:
	layer = 1
	var chrome := Chrome.new()
	chrome.name = "Chrome"
	chrome.view = get_node_or_null("/root/Main/GalaxyView2D")
	add_child(chrome)
	# Tutorial bubbles over the chrome, under the popups.
	var tut := Tutorial.new()
	tut.name = "Tutorial"
	tut.view = chrome.view
	add_child(tut)
	# Popups draw + capture input ABOVE the chrome.
	var popups := PopupManager.new()
	popups.name = "Popups"
	popups.view = chrome.view
	add_child(popups)
