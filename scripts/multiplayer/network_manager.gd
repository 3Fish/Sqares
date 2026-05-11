extends Node

## ENet peer setup, lobby management, and state sync.
## Implemented fully in feature/11-online-multiplayer.

const DEFAULT_PORT := 7777
const MAX_PEERS := 8

var peer: ENetMultiplayerPeer = null

signal server_started
signal client_connected
signal connection_failed
signal peer_connected(id: int)
signal peer_disconnected(id: int)


func host_game(port: int = DEFAULT_PORT) -> Error:
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PEERS)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	server_started.emit()
	return OK


func join_game(address: String, port: int = DEFAULT_PORT) -> Error:
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		connection_failed.emit()
		return err
	multiplayer.multiplayer_peer = peer
	multiplayer.connected_to_server.connect(func(): client_connected.emit())
	multiplayer.connection_failed.connect(func(): connection_failed.emit())
	return OK


func disconnect_game() -> void:
	if peer:
		peer.close()
		peer = null
	multiplayer.multiplayer_peer = null


func _on_peer_connected(id: int) -> void:
	peer_connected.emit(id)


func _on_peer_disconnected(id: int) -> void:
	peer_disconnected.emit(id)
