extends RefCounted
class_name NetInterpolation

## Snapshot-interpolation buffer for a remote (PUPPET) player (#28, deferred
## follow-up from #27 tracked in #82).
##
## The host broadcasts one authoritative NetSnapshot per net tick (~30 Hz).
## Applying each snapshot directly to a PUPPET makes it visibly step at the net
## tick rate. Instead, each PUPPET feeds its incoming position/velocity samples
## into one of these buffers and renders a point slightly in the *past*
## (`render delay` behind the newest sample), interpolating between the two
## buffered samples that bracket that render time. This is the standard
## entity-interpolation technique: it trades a small, fixed display latency for
## continuous motion, and needs no wire-format change (the smoothing is purely
## a client-side rendering concern — the host stays authoritative for all hits,
## damage, and deaths, so interpolation never changes a match outcome).
##
## Plain and scene-free, like NetPrediction: callers push samples stamped with a
## monotonic local time (seconds) and query an interpolated state at a render
## time. All decision-bearing maths live here so they are unit-testable without
## a scene tree; the live wiring (snapshot receive → push, physics tick → apply)
## is the thin seam in NetReplicator / Player.

## Most samples retained. At a 30 Hz net tick this is ~1s of history — far more
## than the render delay needs — so the oldest are evicted once exceeded. Bounds
## memory for a PUPPET that lives for a whole match.
const MAX_SAMPLES := 32

## Time-ordered samples: each is {"time": float, "position": Vector2,
## "velocity": Vector2}. Snapshots arrive newest-last (NetReplicator already
## drops stale out-of-order packets by tick), so this stays sorted by time.
var _samples: Array = []


## Records an authoritative sample stamped with the local receive `time`
## (seconds). Out-of-order or duplicate timestamps (a stale packet that slipped
## through) are ignored so the buffer stays strictly time-ordered.
func push(time: float, position: Vector2, velocity: Vector2) -> void:
	if not _samples.is_empty() and time <= float(_samples.back()["time"]):
		return
	_samples.append({"time": time, "position": position, "velocity": velocity})
	while _samples.size() > MAX_SAMPLES:
		_samples.pop_front()


## Number of buffered samples.
func size() -> int:
	return _samples.size()


## Local time of the newest buffered sample, or 0.0 when empty. Callers derive a
## render time of `latest_time() - delay` to render that far behind live.
func latest_time() -> float:
	if _samples.is_empty():
		return 0.0
	return float(_samples.back()["time"])


## Drops all buffered samples (e.g. when the PUPPET re-spawns for a new round).
func clear() -> void:
	_samples.clear()


## Interpolated {"position", "velocity"} at `render_time`, or an empty dictionary
## when the buffer is empty. The render time is clamped to the buffered range:
## before the oldest sample it returns the oldest, after the newest it holds the
## newest (no extrapolation — a stalled stream freezes rather than drifting off).
## Between two samples it linearly interpolates both position and velocity.
func sample(render_time: float) -> Dictionary:
	if _samples.is_empty():
		return {}
	if render_time <= float(_samples[0]["time"]):
		return _state_of(_samples[0])
	var newest: Dictionary = _samples[_samples.size() - 1]
	if render_time >= float(newest["time"]):
		return _state_of(newest)
	for i in range(1, _samples.size()):
		var b: Dictionary = _samples[i]
		if render_time <= float(b["time"]):
			var a: Dictionary = _samples[i - 1]
			var span := float(b["time"]) - float(a["time"])
			var t := 0.0 if span <= 0.0 else (render_time - float(a["time"])) / span
			return {
				"position": (a["position"] as Vector2).lerp(b["position"], t),
				"velocity": (a["velocity"] as Vector2).lerp(b["velocity"], t),
			}
	# Unreachable given the bounds checks above, but keeps the return total.
	return _state_of(newest)


static func _state_of(s: Dictionary) -> Dictionary:
	return {"position": s["position"], "velocity": s["velocity"]}
