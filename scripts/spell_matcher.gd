class_name SpellMatcher
extends RefCounted
## 从一句咒文里识别出所有已装备法术。
## 每个法术的每一次出现都算一次触发；不同法术（以及同一法术的重叠出现）可以共用符文。


## 返回按起始位置排序的匹配列表，每项为 {spell, start, length, row, cover, mult}。
## start/length 是匹配区间；cover 是使用的字符下标；mult 为效果倍率。
## row 是括号所在的行号：互相重叠的匹配会被分到不同的行。
static func find_matches(sentence: String, spells: Array[SpellData]) -> Array[Dictionary]:
	var matches: Array[Dictionary] = []
	for spell in spells:
		_find_exact(sentence, spell, matches)
	matches.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.start != b.start:
			return a.start < b.start
		if a.length != b.length:
			return a.length < b.length
		return spells.find(a.spell) < spells.find(b.spell))

	var row_ends: Array[int] = []
	for m in matches:
		var row := 0
		while row < row_ends.size() and row_ends[row] > m.start:
			row += 1
		if row == row_ends.size():
			row_ends.append(0)
		row_ends[row] = m.start + m.length
		m.row = row
	return matches


static func covers(m: Dictionary, index: int) -> bool:
	return index in m.cover


static func _add(matches: Array[Dictionary], spell: SpellData, start: int, length: int, cover: Array, mult: int = 1) -> void:
	matches.append({"spell": spell, "start": start, "length": length, "row": 0, "cover": cover, "mult": mult})


static func _span(start: int, length: int) -> Array:
	return range(start, start + length)


static func _find_exact(sentence: String, spell: SpellData, matches: Array[Dictionary]) -> void:
	var from := 0
	while true:
		var at := sentence.find(spell.pattern, from)
		if at == -1:
			break
		_add(matches, spell, at, spell.pattern.length(), _span(at, spell.pattern.length()))
		from = at + 1


## Pure preview by default. Randomness is sampled only during an actual cast.
## Matches resolve left to right; newly gained affinity affects later matches.
static func totals(matches: Array[Dictionary], affinity: int = 0, roll_random: bool = false) -> Dictionary:
	var result := {"damage": 0.0, "damage_min": 0, "damage_max": 0, "pierce": 0, "shield": 0, "heal": 0, "gold": 0, "affinity": affinity, "self_damage": 0, "steps": []}
	for m in matches:
		var spell: SpellData = m.spell
		var step := {"damage": 0.0, "shield": 0, "affinity": 0, "self_damage": 0}
		for occurrence in int(m.mult):
			result.affinity += spell.fire_affinity
			var base: int = spell.damage + spell.damage_per_affinity * result.affinity
			var bonus := spell.random_bonus if roll_random and randf() < 0.5 else 0
			var damage: float = base + (bonus if roll_random else spell.random_bonus * 0.5)
			result.damage += damage
			step.damage += damage
			step.shield += spell.shield + spell.shield_per_affinity * result.affinity
			step.affinity += spell.fire_affinity
			step.self_damage += spell.self_damage
			result.damage_min += base + (bonus if roll_random else 0)
			result.damage_max += base + (bonus if roll_random else spell.random_bonus)
			result.shield += spell.shield + spell.shield_per_affinity * result.affinity
			result.self_damage += spell.self_damage
		result.steps.append(step)
	return result
