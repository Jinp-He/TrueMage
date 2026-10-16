class_name MapData
extends RefCounted
## 一局的地图：从左往右走 LAYERS 层，最后一层之后是首领。
## 战斗层和服务层交替出现：战斗（普通或精英）打赢后先学习咒语，再到下一层挑一个服务节点（休息、商店、抄写室、宝箱）。
## 每层 2～4 个节点，相邻两层之间的路线不交叉，并保证每个节点都有路进、有路出。

const BATTLE := "battle"
const ELITE := "elite"
const SHOP := "shop"
const REST := "rest"
const SCRIPTORIUM := "scriptorium"
const TREASURE := "treasure"
const BOSS := "boss"

const NAMES := {
	BATTLE: "战斗", ELITE: "精英", SHOP: "咒语商店", REST: "休息处", SCRIPTORIUM: "抄写室", TREASURE: "宝箱", BOSS: "首领",
}

## 偶数层是战斗层，奇数层是服务层；最后一层（首领前）固定是休息处。
const LAYERS := 8
const REST_LAYER := LAYERS - 1
## 从这一层起，战斗层里的节点有机会是精英；每个战斗层至少留一个普通战斗。
const ELITE_FROM_LAYER := 2
const ELITE_CHANCE := 0.3
## 服务层从这个袋子里轮流抽，一层里尽量不重复，让每层都是真正的选择。
const SERVICE_BAG := [REST, SHOP, SCRIPTORIUM, REST, SHOP, SCRIPTORIUM, TREASURE]


static func is_battle_layer(layer: int) -> bool:
	return layer % 2 == 0


class MapNode:
	extends RefCounted
	var layer: int
	var row: int
	var type: String
	## 纵向位置，0 是地图顶部，1 是底部。
	var y: float
	## 下一层里连得到的节点在该层的序号。
	var next: Array[int] = []
	var visited := false

	func _init(p_layer: int, p_row: int) -> void:
		layer = p_layer
		row = p_row


## layers[i] 是第 i 层的节点，按从上到下排列；最后一个元素是只有首领的一层。
var layers: Array = []


static func generate() -> MapData:
	var map := MapData.new()
	for layer in LAYERS:
		var count := 3 if layer == 0 else randi_range(2, 4)
		map.layers.append(_make_layer(layer, count))
	map.layers.append(_make_layer(LAYERS, 1))
	map.layers[LAYERS][0].type = BOSS
	for layer in LAYERS:
		_connect(map.layers[layer], map.layers[layer + 1])
		_assign_types(map.layers[layer], layer)
	return map


static func _make_layer(layer: int, count: int) -> Array:
	var nodes := []
	for row in count:
		var node := MapNode.new(layer, row)
		# 均匀分布再加一点抖动，避免排成死板的网格。
		node.y = (row + 0.5) / count + randf_range(-0.12, 0.12) / count
		nodes.append(node)
	return nodes


## 两层之间走一条“阶梯”：两边都从最上面的节点开始，每一步往下移一边或两边，
## 每一步连一条线。这样的连线不会交叉，而且两层的每个节点都至少连到一条。
static func _connect(from: Array, to: Array) -> void:
	var i := 0
	var j := 0
	from[0].next.append(0)
	while i < from.size() - 1 or j < to.size() - 1:
		var step := randi_range(0, 2)
		if i == from.size() - 1:
			step = 1
		elif j == to.size() - 1:
			step = 0
		if step != 1:
			i += 1
		if step != 0:
			j += 1
		if not j in from[i].next:
			from[i].next.append(j)


static func _assign_types(nodes: Array, layer: int) -> void:
	if layer == REST_LAYER:
		for node: MapNode in nodes:
			node.type = REST
		return
	if is_battle_layer(layer):
		for node: MapNode in nodes:
			node.type = ELITE if layer >= ELITE_FROM_LAYER and randf() < ELITE_CHANCE else BATTLE
		if nodes.all(func(node: MapNode) -> bool: return node.type == ELITE):
			nodes.pick_random().type = BATTLE
		return
	# 服务层：洗一袋，按顺序发，同一层先不重复。
	var bag := []
	for node: MapNode in nodes:
		if bag.is_empty():
			bag = SERVICE_BAG.duplicate()
			bag.shuffle()
		var used := nodes.map(func(other: MapNode) -> String: return other.type)
		var pick: int = bag.find_custom(func(type: String) -> bool: return not type in used)
		node.type = bag.pop_at(maxi(pick, 0))


func node_at(layer: int, row: int) -> MapNode:
	return layers[layer][row]


func boss() -> MapNode:
	return layers[LAYERS][0]


## 当前所在节点之后能去的节点；还没出发时是第一层的全部节点。
func reachable_from(current: MapNode) -> Array[MapNode]:
	var result: Array[MapNode] = []
	if current == null:
		result.assign(layers[0])
		return result
	if current.layer >= LAYERS:
		return result
	for row in current.next:
		result.append(node_at(current.layer + 1, row))
	return result
