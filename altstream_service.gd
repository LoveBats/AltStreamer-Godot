class_name AltStreamService
extends Node

const HOST		:= "https://altstream.online"
const API_ENDPOINT	:= "/api"
const CHAT_ENDPOINT	:= "/chat/stream?channel=%s"

signal connected
signal disconnected
signal connection_failed

signal chat_message_received(user: AltStreamUser, message: AltStreamMessage)
signal chat_message_sticker_received(user: AltStreamUser, message_id: String, _name: String, url: String) # name currently unvailable
signal chat_message_pinned(user: AltStreamUser, message: AltStreamMessage, pinned_by: String)
signal chat_message_unpinned()
signal chat_message_deleted(message_id: String)
signal chat_cleared()

signal highlight_received(user: AltStreamUser, message: AltStreamMessage, reward_name: String)

signal raid_incoming(from: AltStreamUser, raider_count: int)
signal raid_outgoing_started(target: AltStreamUser, viewer_count: int, countdown: int)
signal raid_outgoing_canceled()

signal reward_redeemed(user: AltStreamUser, message_id: String, reward_name: String, user_input: String)
signal shoutout(target: AltStreamUser, game_name: String, game_cover_url: String, shouted_by: AltStreamUser)

@export var autoconnect := true
@export var channel := ""

var client := EventStreamClient.new()

func _init() -> void:
	client.connected.connect(_on_connected)
	client.disconnected.connect(_on_disconnected)
	client.connection_failed.connect(_on_connection_failed)
	client.event_received.connect(_on_event_received)

func _ready() -> void:
	if autoconnect:
		alt_connect()

func _process(_delta: float) -> void:
	client.poll()

func _on_connected() -> void:
	print("Altstreamer connected")
	connected.emit()

func _on_disconnected(error: String) -> void:
	if error: print("Altstreamer disconnected: " + error)
	else: print("Altstreamer disconnected")
	disconnected.emit()

func _on_connection_failed(error: String) -> void:
	if error: print("Altstreamer failed to connect: " + error)
	else: print("Altstreamer failed to connect")
	connection_failed.emit()

func alt_connect(channel_connect: String = channel) -> void:
	if client.status == EventStreamClient.Status.DISCONNECTED:
		if not channel_connect.is_empty():
			client.connect_to_host(HOST, API_ENDPOINT + CHAT_ENDPOINT % channel_connect)
		else:
			print("No channel specified for Altstreamer connection")
	else:
		print("EventStream not disconnected, could not initiate new connection.")

func alt_disconnect() -> void:
	client.close()

func _on_event_received(_event: String, data: String) -> void:
	var messages := JSON.parse_string(data) as Array
	if not messages: return

	for msg: Dictionary in messages:
		var source  := _try_get_string(msg, "source")
		var message := _message_from_msg(msg)
		var user    := _user_from_msg(msg)

		if source == "local":
			if user.username and user.display_name:
				if message.text:
					chat_message_received.emit(user, message)
				elif message.sticker_url:
					chat_message_sticker_received.emit(user, message.id, "", message.sticker_url)
			return

		# "Special" messages (for the lack of an official name) typically come
		# in the format "[KIND]:{...}". While `source` may match kind, it may
		# also just be "system", so we'll just ignore it for this.
		var special := _special_regex.search(message.text)
		if special:
			var kind  := special.get_string(1)
			var value := special.get_string(2)
			message.text = "" # Don't ever expose this in our API.

			# Most of these hold a stringified JSON object which we're parsing
			# here, but there are exceptions, like `[DELETE]` and `[CLEAR_CHAT]`.
			var obj: Dictionary = JSON.parse_string(value) if value.begins_with("{") else {}

			match kind:
				"[HIGHLIGHT]":
					user.username    = _try_get_string(obj, "from")
					message.text     = _try_get_string(obj, "text")
					var reward_name := _try_get_string(obj, "rewardName")
					if user.username and user.display_name and message.text and reward_name:
						# Highlighted messages show up mostly as regular
						# chat messages, so we'll emit them as such.
						highlight_received.emit(user, message, reward_name)

				"[CHAT_PIN]":
					user    = _user_from_msg(obj)
					message = _message_from_msg(obj)
					var pinned_by := _try_get_string(obj, "pinnedBy")
					if user.username and user.display_name and message.text and pinned_by:
						chat_message_pinned.emit(user, message, pinned_by)

				"[CHAT_UNPIN]":
					chat_message_unpinned.emit()

				"[DELETE]":
					var message_id := value
					chat_message_deleted.emit(message_id)

				"[CLEAR_CHAT]":
					chat_cleared.emit()

				"[RAID_START]":
					var target := AltStreamUser.new()
					target.username     = _try_get_string(obj, "targetUsername")
					target.display_name = _try_get_string(obj, "targetDisplayName")
					target.avatar_url   = _try_get_string(obj, "targetImage")
					var viewers   := _try_get_int(obj, "viewers")
					var countdown := _try_get_int(obj, "countdownSeconds")
					if target.username and target.display_name:
						raid_outgoing_started.emit(target, viewers, countdown)

				"[RAID_CANCEL]":
					raid_outgoing_canceled.emit()

				"[REDEMPTION]":
					user.username    = _try_get_string(obj, "from")
					var reward_name := _try_get_string(obj, "rewardName")
					var user_input  := _try_get_string(obj, "userInput") # optional
					if user.username and user.display_name and reward_name:
						reward_redeemed.emit(user, message.id, reward_name, user_input)

				"[SHOUTOUT]":
					var target := AltStreamUser.new()
					target.username     = _try_get_string(obj, "targetUsername")
					target.display_name = _try_get_string(obj, "targetDisplayName")
					target.avatar_url   = _try_get_string(obj, "targetAvatar")
					var game_name      := _try_get_string(obj, "gameName")
					var game_cover_url := _try_get_string(obj, "gameCover")
					if target.username and target.display_name:
						shoutout.emit(user, game_name, game_cover_url, user)
			return

		# Incoming raid notifications have a unique text format that
		# we need to manually match and parse (see `_raid_regex`).
		var raid := _raid_regex.search(message.text)
		if raid:
			user.username = raid.get_string(1)
			var raider_count := int(raid.get_string(2))
			if user.username and user.display_name:
				raid_incoming.emit(user, raider_count)
			return


static var _special_regex := RegEx.create_from_string("^(\\[\\w+\\])(?:\\:(.*))?$")
static var _raid_regex    := RegEx.create_from_string("^@(\\w+) is raiding with a party of \"(\\d+)\"")

## Returns the value associated with `key` from this `Dictionary` as a `String`,
## or `default` if it's missing or a different data type (such as `TYPE_NIL`).
static func _try_get_string(dict: Dictionary, key: String, default := "") -> String:
	var variant = dict.get(key)
	return variant if (variant is String) else default

static func _try_get_int(dict: Dictionary, key: String, default := -1) -> int:
	var variant = dict.get(key)
	if variant is int: return variant
	elif variant is float: return roundi(variant)
	else: return default

static func _parse_color(value: String) -> Color:
	if value.is_empty(): return Color.WHITE
	var rgb := value.trim_prefix("#").hex_to_int()
	return Color.hex((rgb << 16) | 0x000000FF)

static func _user_from_msg(msg: Dictionary) -> AltStreamUser:
	var user := AltStreamUser.new()
	user.username     = _try_get_string(msg, "authorUsername")
	user.display_name = _try_get_string(msg, "author")
	user.avatar_url   = _try_get_string(msg, "authorImage")
	user.user_color   = _parse_color(
		_try_get_string(msg, "userColor"))
	return user

static func _message_from_msg(msg: Dictionary) -> AltStreamMessage:
	var message := AltStreamMessage.new()
	message.id          = _try_get_string(msg, "id")
	message.text        = _try_get_string(msg, "text")
	message.sent_at     = _try_get_int(msg, "sentAt")
	message.sticker_url = _try_get_string(msg, "stickerUrl")
	message.reply_to_id           = _try_get_string(msg, "replyToId")
	message.reply_to_username     = _try_get_string(msg, "replyToAuthor")
	message.reply_to_display_name = _try_get_string(msg, "replyToUsername")
	return message
