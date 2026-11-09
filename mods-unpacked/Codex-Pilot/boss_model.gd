extends Reference

# Independent linear pieces of a moving, expanding orbit. Each piece has its
# own active window; extrapolate its origin back to t=0 for danger_path.
func orbit_segments(center, center_velocity, offset, angular_speed, radial_speed, target_radius):
	var result = []
	var radius = offset.length()
	for i in range(5):
		var a = i * 0.13
		var b = (i + 1) * 0.13
		var pa = center + center_velocity * a + offset.normalized().rotated(angular_speed*a) * min(target_radius,radius+radial_speed*a)
		var pb = center + center_velocity * b + offset.normalized().rotated(angular_speed*b) * min(target_radius,radius+radial_speed*b)
		var velocity = (pb-pa)/(b-a)
		result.append([pa-velocity*a,62.0,1,velocity,a,b])
	return result

func focus_cost(distance, health_ratio, imminent_charge, retained):
	return distance + clamp(health_ratio,0.0,1.0)*200.0 + (280.0 if imminent_charge else 0.0) - (120.0 if retained else 0.0)

func charge_segment(origin, direction, speed, delay, duration):
	var start = max(0.0,delay)
	var end = min(0.65,start+duration)
	if start >= end or direction.length_squared() < 0.001:
		return []
	var velocity = direction.normalized()*speed
	return [origin-velocity*start,90.0,1,velocity,start,end]
