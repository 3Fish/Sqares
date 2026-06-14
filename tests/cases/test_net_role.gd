extends TestCase

## Unit tests for MatchDirector.resolve_net_role: the per-slot simulation-role
## matrix for networked play (#27).


func _test_offline_is_all_local() -> void:
	# Not networked: every slot simulates locally regardless of host/local args.
	assert_eq(
		MatchDirector.resolve_net_role(false, false, 0, -1), Player.NetRole.LOCAL,
		"offline slot 0 -> LOCAL"
	)
	assert_eq(
		MatchDirector.resolve_net_role(false, true, 3, 0), Player.NetRole.LOCAL,
		"offline slot 3 -> LOCAL"
	)


func _test_host_owns_local_slot_simulates_rest() -> void:
	# Host (local_slot 0): its own square is LOCAL, remote peers are SIMULATED.
	assert_eq(
		MatchDirector.resolve_net_role(true, true, 0, 0), Player.NetRole.LOCAL,
		"host's own slot -> LOCAL"
	)
	assert_eq(
		MatchDirector.resolve_net_role(true, true, 1, 0), Player.NetRole.SIMULATED,
		"host's view of a remote peer -> SIMULATED"
	)
	assert_eq(
		MatchDirector.resolve_net_role(true, true, 2, 0), Player.NetRole.SIMULATED,
		"host's view of another remote peer -> SIMULATED"
	)


func _test_client_predicts_own_puppets_rest() -> void:
	# Client whose own slot is 1: that square is PREDICTED, others are PUPPETs.
	assert_eq(
		MatchDirector.resolve_net_role(true, false, 1, 1), Player.NetRole.PREDICTED,
		"client's own slot -> PREDICTED"
	)
	assert_eq(
		MatchDirector.resolve_net_role(true, false, 0, 1), Player.NetRole.PUPPET,
		"client's view of the host -> PUPPET"
	)
	assert_eq(
		MatchDirector.resolve_net_role(true, false, 2, 1), Player.NetRole.PUPPET,
		"client's view of another client -> PUPPET"
	)
