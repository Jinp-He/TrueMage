class_name RelicData
extends RefCounted
## 遗物：在休息处购买的被动效果。
## 属性类遗物在购买时直接改 Game 里的数值；其余的在战斗结算时由 battle.gd 用 Game.has_relic() 检查。
## 图标暂时借用 UI 图集里的现成切图。

var id: String
var name: String
var description: String
var icon: String
var cost: int


func _init(p_id: String, p_name: String, p_description: String, p_icon: String, p_cost: int) -> void:
	id = p_id
	name = p_name
	description = p_description
	icon = p_icon
	cost = p_cost


## 还没拥有、且对应数值没到上限时才会出现在货架上。
func available() -> bool:
	if Game.has_relic(id):
		return false
	match id:
		"scroll":
			return Game.max_length < Game.MAX_LENGTH_CAP
		"bookmark":
			return Game.spell_slots < Game.SPELL_SLOT_CAP
		"feather":
			return Game.max_clouds < Game.CLOUDS_CAP
	return true


## 购买时立刻生效的部分。
func on_acquire() -> void:
	match id:
		"hourglass":
			Game.build_time += 8.0
		"scroll":
			Game.max_length += 1
		"bookmark":
			Game.spell_slots += 1
		"feather":
			Game.max_clouds += 1
		"heart":
			Game.max_hp += 8
			Game.heal(8)


static func catalog() -> Array[RelicData]:
	return [
		RelicData.new("hourglass", "沙漏坠饰", "构句时间 +8 秒", "icon_hourglass", 7),
		RelicData.new("scroll", "长卷轴", "句子长度上限 +1", "ribbon_small", 9),
		RelicData.new("bookmark", "空白书页", "法术位 +1", "tile_empty", 10),
		RelicData.new("feather", "灵感之羽", "脑海同时可容纳的词云 +1", "cloud_pink", 7),
		RelicData.new("heart", "强心护符", "生命上限 +8，并恢复 8 点生命", "icon_heart_large", 6),
		RelicData.new("ember_ring", "火种戒指", "攻击法术每次触发，伤害 +1", "icon_fire", 9),
		RelicData.new("bracer", "寒铁护腕", "每回合释放时额外获得 3 点护盾", "icon_shield", 8),
		RelicData.new("crystal", "共鸣水晶", "句中每个被两个以上法术共用的符文，伤害 +2", "tile_shared", 10),
		RelicData.new("glove", "魔术手套", "脑海“换一批”不再消耗时间", "icon_glove", 6),
		RelicData.new("echo", "回响石", "句子写满时释放，伤害 +5", "tile_orange", 8),
	]


static func by_id(relic_id: String) -> RelicData:
	for relic in catalog():
		if relic.id == relic_id:
			return relic
	return null
