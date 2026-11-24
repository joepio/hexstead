extends RefCounted
## Same-origin, local-page transport for the Splitscreen Club game protocol.
## Keep this instance alive while the parent hosts the game.

var _page: JavaScriptObject
var _callback: JavaScriptObject
var _receiver: Callable

func attach(receiver: Callable) -> bool:
	if not OS.has_feature("web"):
		return false
	var window := JavaScriptBridge.get_interface("window")
	if not window.hasOwnProperty("SplitscreenClubWebGame"):
		return false
	_page = JavaScriptBridge.get_interface("SplitscreenClubWebGame")
	if _page == null:
		return false
	_receiver = receiver
	_callback = JavaScriptBridge.create_callback(_receive)
	_page.bindReceiver(_callback)
	return true

func attached() -> bool:
	return _page != null

func send(message: Dictionary) -> void:
	_page.sendToParent(JSON.stringify(message))

func _receive(args: Array) -> void:
	if args.size() == 1 and args[0] is String:
		var message: Variant = JSON.parse_string(args[0])
		if message is Dictionary: _receiver.call(message)
