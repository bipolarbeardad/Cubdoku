extends RefCounted
## Builds placeholder material sheets in board space. A replacement sheet uses
## the same square dimensions, with one continuous view of the material.

const CELL_SIZE := 84
const BOARD_CAPACITY := 10
const SHEET_SIZE := CELL_SIZE * BOARD_CAPACITY
const SAMPLE_SIZE := int(SHEET_SIZE * 0.5)
const MATERIALS := ["Grass", "Wood", "Stone", "Dirt", "Mud", "Gravel", "Forest Floor", "Water", "Sand", "Moss"]
const BASE_COLORS := [
	Color("#416831"), Color("#96633a"), Color("#536271"), Color("#80503b"),
	Color("#47403d"), Color("#827a6b"), Color("#564b31"),
	Color("#26749d"), Color("#c9a255"), Color("#3b8070"),
]


static func make_texture(material: int) -> Texture2D:
	var noise := FastNoiseLite.new()
	noise.seed = 6721 + material * 47
	noise.frequency = 0.039
	var rng := RandomNumberGenerator.new()
	rng.seed = 361 + material * 53
	var image := Image.create_empty(SAMPLE_SIZE, SAMPLE_SIZE, false, Image.FORMAT_RGB8)
	for y in SAMPLE_SIZE:
		for x in SAMPLE_SIZE:
			var variation := noise.get_noise_2d(x, y) * 0.22 + rng.randf_range(-0.045, 0.045)
			if material == 1:
				var grain_y := y + noise.get_noise_2d(x * 0.23, y * 0.58) * 12.0
				variation += sin(grain_y * 0.57) * 0.072
				variation -= pow(0.5 + 0.5 * sin(grain_y * 1.37), 5.0) * 0.14
			elif material == 4:
				var pooling := noise.get_noise_2d(x * 0.48, y * 0.68)
				variation += smoothstep(0.03, 0.34, pooling) * 0.12
				variation += sin(y * 0.18 + pooling * 11.0) * smoothstep(0.12, 0.5, pooling) * 0.05
			elif material == 7:
				var wave := sin(y * 0.38 + 3.0 * sin(x * 0.052) + noise.get_noise_2d(x, y) * 2.0)
				variation += maxf(wave, 0.0) ** 6 * 0.25
			elif material == 8:
				variation += rng.randf_range(-0.14, 0.09)
			image.set_pixel(x, y, _shade(BASE_COLORS[material], variation))

	match material:
		0:
			for index in 3100:
				var point := _random_point(rng)
				var tip := point + Vector2(rng.randf_range(-3.0, 2.0), -rng.randf_range(2.0, 6.0))
				_stroke(image, point, tip, _shade(Color("#618348"), rng.randf_range(-0.24, 0.09)))
		2:
			_scatter(image, rng, 17, Vector2(11, 8), Color("#768591"), 0.22)
		3:
			_scatter(image, rng, 5, Vector2(2, 1), Color("#986b50"), 0.16)
		5:
			_scatter(image, rng, 7, Vector2(3.4, 2.6), Color("#a49a85"), 0.31)
		6:
			for index in 925:
				var point := _random_point(rng)
				var angle := rng.randf_range(0, TAU)
				var color := _shade(Color("#9c7240").lerp(Color("#775030"), rng.randf()), rng.randf_range(-0.19, 0.06))
				var radii := Vector2(rng.randf_range(3.0, 6.5), rng.randf_range(1.5, 2.6))
				_oval(image, point, radii, angle, color)
				var axis := Vector2.from_angle(angle) * radii.x * 0.8
				_stroke(image, point - axis, point + axis, color.darkened(0.28))
		9:
			_scatter(image, rng, 9, Vector2(5.4, 4.8), Color("#69a58c"), 0.23)
	image.resize(SHEET_SIZE, SHEET_SIZE, Image.INTERPOLATE_BILINEAR)
	return ImageTexture.create_from_image(image)


static func _shade(color: Color, amount: float) -> Color:
	return color.lightened(amount) if amount >= 0.0 else color.darkened(-amount)


static func _random_point(rng: RandomNumberGenerator) -> Vector2:
	return Vector2(rng.randf() * SAMPLE_SIZE, rng.randf() * SAMPLE_SIZE)


static func _stroke(image: Image, from: Vector2, to: Vector2, color: Color) -> void:
	var steps := maxi(1, ceili(from.distance_to(to)))
	var bounds := Rect2i(0, 0, SAMPLE_SIZE, SAMPLE_SIZE)
	for step in steps + 1:
		var point := Vector2i(from.lerp(to, float(step) / steps).round())
		if bounds.has_point(point):
			image.set_pixelv(point, color)


static func _scatter(
	image: Image, rng: RandomNumberGenerator, spacing: int, radii: Vector2,
	base_color: Color, variation: float,
) -> void:
	for y in range(0, SAMPLE_SIZE + spacing, spacing):
		for x in range(0, SAMPLE_SIZE + spacing, spacing):
			var point := Vector2(x, y) + Vector2(rng.randf_range(-0.42, 0.42), rng.randf_range(-0.42, 0.42)) * spacing
			var size := radii * rng.randf_range(0.64, 1.24)
			var color := _shade(base_color, rng.randf_range(-variation, variation * 0.46))
			_oval(image, point, size, rng.randf_range(0, TAU), color)


static func _oval(image: Image, center: Vector2, radii: Vector2, angle: float, color: Color) -> void:
	var extent := ceili(maxf(radii.x, radii.y) + 2.0)
	var axis := Vector2.from_angle(angle)
	var cross_axis := axis.orthogonal()
	for y in range(maxi(0, int(center.y) - extent), mini(SAMPLE_SIZE, int(center.y) + extent + 1)):
		for x in range(maxi(0, int(center.x) - extent), mini(SAMPLE_SIZE, int(center.x) + extent + 1)):
			var offset := Vector2(x, y) - center
			var local := Vector2(offset.dot(axis), offset.dot(cross_axis)) / radii
			var distance := local.length_squared()
			if distance > 1.15:
				continue
			var edge := smoothstep(0.62, 1.12, distance)
			var lit := _shade(color, -offset.y * 0.16 / extent - edge * 0.28)
			image.set_pixel(x, y, image.get_pixel(x, y).lerp(lit, 1.0 - smoothstep(0.84, 1.15, distance)))
