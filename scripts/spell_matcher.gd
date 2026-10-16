class_name SpellMatcher
extends RefCounted
## 从一句咒文里识别出所有已装备法术。
## 每个法术的每一次出现都算一次触发；不同法术（以及同一法术的重叠出现）可以共用符文。
## 条件咒式的识别规则见 SpellData 顶部的说明。


## 返回按起始位置排序的匹配列表，每项为 {spell, start, length, row, cover, mult}。
## start/length 是括号覆盖的区间；cover 是真正被这个法术用上的符文下标（计数型可以分散，缺席型为空）；
## mult 是效果倍率（首尾型按中间符文数，其余为 1）。
## row 是括号所在的行号：互相重叠的匹配会被分到不同的行。
static func find_matches(sentence: String, spells: Array[SpellData]) -> Array[Dictionary]:
	var matches: Array[Dictionary] = []
	for spell in spells:
		match spell.rule:
			SpellData.BOOKEND:
				_find_bookend(sentence, spell, matches)
			SpellData.VARIETY:
				_find_variety(sentence, spell, matches)
			SpellData.COUNT:
				_find_count(sentence, spell, matches)
			SpellData.ABSENT:
				_find_absent(sentence, spell, matches)
			_:
				_find_exact(sentence, spell, matches)
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


## 首尾呼应：每个首符文找它之后最近的尾符文，中间至少夹一个符文才算，夹几个就是几倍。
static func _find_bookend(sentence: String, spell: SpellData, matches: Array[Dictionary]) -> void:
	var head := spell.pattern[0]
	var tail := spell.pattern[1]
	for i in sentence.length():
		if sentence[i] != head:
			continue
		var j := sentence.find(tail, i + 1)
		if j - i >= 2:
			_add(matches, spell, i, j - i + 1, [i, j], j - i - 1)


## 多样：从左到右找连续 N 个互不相同的符文，找到一段就从段尾之后继续，不重叠。杂念符文不算。
static func _find_variety(sentence: String, spell: SpellData, matches: Array[Dictionary]) -> void:
	var need := spell.pattern.length()
	var start := 0
	while start + need <= sentence.length():
		var seen := {}
		var ok := true
		for k in need:
			var rune := sentence[start + k]
			if rune == CloudCard.JUNK_RUNE or seen.has(rune):
				ok = false
				break
			seen[rune] = true
		if ok:
			_add(matches, spell, start, need, _span(start, need))
			start += need
		else:
			start += 1


## 计数：从左到右收集咒式里要的符文，凑齐一组就触发一次，再从头凑下一组。
static func _find_count(sentence: String, spell: SpellData, matches: Array[Dictionary]) -> void:
	var need := _rune_counts(spell.pattern)
	var cover: Array = []
	for i in sentence.length():
		var rune := sentence[i]
		if need.get(rune, 0) <= 0:
			continue
		need[rune] -= 1
		cover.append(i)
		if cover.size() == spell.pattern.length():
			_add(matches, spell, cover[0], cover[-1] - cover[0] + 1, cover)
			need = _rune_counts(spell.pattern)
			cover = []


## 缺席：句子不为空，且一个禁用符文都没有时触发一次。括号盖住整句，但不算用上了任何符文。
static func _find_absent(sentence: String, spell: SpellData, matches: Array[Dictionary]) -> void:
	if sentence.is_empty():
		return
	for rune in spell.pattern:
		if rune in sentence:
			return
	_add(matches, spell, 0, sentence.length(), [])


static func _rune_counts(pattern: String) -> Dictionary:
	var counts := {}
	for rune in pattern:
		counts[rune] = counts.get(rune, 0) + 1
	return counts


## damage 是总伤害，其中 pierce 部分无视敌人的防御。
static func totals(matches: Array[Dictionary]) -> Dictionary:
	var result := {"damage": 0, "pierce": 0, "shield": 0, "heal": 0, "gold": 0}
	for m in matches:
		var spell: SpellData = m.spell
		var mult: int = m.mult
		result.damage += spell.damage * mult
		if spell.pierce:
			result.pierce += spell.damage * mult
		result.shield += spell.shield * mult
		result.heal += spell.heal * mult
		result.gold += spell.gold * mult
	return result
