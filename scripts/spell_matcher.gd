class_name SpellMatcher
extends RefCounted
## 从一句咒文里识别出所有已装备法术。
## 每个法术的每一次出现都算一次触发；不同法术（以及同一法术的重叠出现）可以共用符文。


## 返回按起始位置排序的匹配列表，每项为 {spell, start, length, row}。
## row 是括号所在的行号：互相重叠的匹配会被分到不同的行。
static func find_matches(sentence: String, spells: Array[SpellData]) -> Array[Dictionary]:
	var matches: Array[Dictionary] = []
	for spell in spells:
		var from := 0
		while true:
			var at := sentence.find(spell.pattern, from)
			if at == -1:
				break
			matches.append({"spell": spell, "start": at, "length": spell.pattern.length(), "row": 0})
			from = at + 1
	matches.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.start != b.start:
			return a.start < b.start
		return a.length < b.length)

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


## damage 是总伤害，其中 pierce 部分无视敌人的防御。
static func totals(matches: Array[Dictionary]) -> Dictionary:
	var result := {"damage": 0, "pierce": 0, "shield": 0, "heal": 0, "gold": 0}
	for m in matches:
		var spell: SpellData = m.spell
		result.damage += spell.damage
		if spell.pierce:
			result.pierce += spell.damage
		result.shield += spell.shield
		result.heal += spell.heal
		result.gold += spell.gold
	return result
