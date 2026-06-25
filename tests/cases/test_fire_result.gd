extends TestCase

## Unit tests for the FireResult tri-state returned by Weapon.try_fire (#121).
##
## FireResult is a plain, scene-free value type, so these exercise its three
## constructors and predicates directly: it is what lets the netcode fire-intent
## path tell an accepted-but-delayed shot (SCHEDULED) apart from a refusal
## (REJECTED), which a bare Projectile-or-null return could not.


func _test_fired_carries_projectile_and_no_delay() -> void:
	# A FIRED result reports the spawned bullet (null stands in for a real
	# Projectile here — the type is irrelevant to the tri-state contract).
	var r := FireResult.fired(null)
	assert_true(r.is_fired(), "fired() is FIRED")
	assert_false(r.is_scheduled(), "fired() is not SCHEDULED")
	assert_false(r.is_rejected(), "fired() is not REJECTED")
	assert_eq(r.outcome, FireResult.Outcome.FIRED, "outcome is FIRED")
	assert_almost_eq(r.delay, 0.0, "a fired shot has no pending delay")


func _test_scheduled_carries_delay() -> void:
	var r := FireResult.scheduled(0.75)
	assert_true(r.is_scheduled(), "scheduled() is SCHEDULED")
	assert_false(r.is_fired(), "scheduled() is not FIRED")
	assert_false(r.is_rejected(), "scheduled() is not REJECTED")
	assert_eq(r.outcome, FireResult.Outcome.SCHEDULED, "outcome is SCHEDULED")
	assert_almost_eq(r.delay, 0.75, "the wait is carried so the host can ack it")
	assert_null(r.projectile, "nothing spawned yet for a scheduled shot")


func _test_rejected_is_empty() -> void:
	var r := FireResult.rejected()
	assert_true(r.is_rejected(), "rejected() is REJECTED")
	assert_false(r.is_fired(), "rejected() is not FIRED")
	assert_false(r.is_scheduled(), "rejected() is not SCHEDULED")
	assert_eq(r.outcome, FireResult.Outcome.REJECTED, "outcome is REJECTED")
	assert_null(r.projectile, "a rejected shot has no projectile")
	assert_almost_eq(r.delay, 0.0, "a rejected shot has no delay")


func _test_outcomes_are_distinct() -> void:
	assert_true(
		FireResult.Outcome.FIRED != FireResult.Outcome.SCHEDULED
			and FireResult.Outcome.SCHEDULED != FireResult.Outcome.REJECTED
			and FireResult.Outcome.FIRED != FireResult.Outcome.REJECTED,
		"the three outcomes are distinct enum values",
	)
