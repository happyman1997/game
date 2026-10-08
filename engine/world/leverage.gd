class_name Leverage
extends RefCounted
## Крюки (hooks): рычаг давления одного персонажа на другого. Слабый крюк
## можно использовать один раз, сильный — многократно, с перерывом.
## Использованный крюк заставляет принять взаимодействие (поле use_hook).


static func hook_on(game: Game, c: Dictionary, target_id: String) -> Variant:
	for h in c.hooks:
		if h.target == target_id and (h.get("expires") == null or h.expires > game.date):
			return h
	return null


static func add_hook(game: Game, owner: Dictionary, target: Dictionary, strong: bool = false, days: int = 0) -> void:
	if owner.id == target.id:
		return
	var prev: Variant = hook_on(game, owner, target.id)
	# Сильный крюк не заменяется слабым.
	if prev != null and prev.get("strong", false) and not strong:
		return
	owner.hooks = owner.hooks.filter(func(h): return h.target != target.id)
	owner.hooks.append({"target": target.id, "strong": strong, "expires": game.date + days if days > 0 else null})
	game.emit("hook.added", {"owner": owner, "target": target, "strong": strong})


static func remove_hook(owner: Dictionary, target_id: String) -> void:
	owner.hooks = owner.hooks.filter(func(h): return h.target != target_id)


## Можно ли сейчас использовать крюк (сильный — не чаще раза в strong_hook_cooldown_years).
static func can_use_hook(game: Game, owner: Dictionary, target_id: String) -> bool:
	var h: Variant = hook_on(game, owner, target_id)
	if h == null:
		return false
	if not h.get("strong", false):
		return true
	var cd: Variant = owner.flags.get("hook_cd:" + target_id)
	return cd == null or cd <= game.date


static func use_hook(game: Game, owner: Dictionary, target_id: String) -> bool:
	var h: Variant = hook_on(game, owner, target_id)
	if h == null or not can_use_hook(game, owner, target_id):
		return false
	if h.get("strong", false):
		owner.flags["hook_cd:" + target_id] = game.date + roundi(game.def_num("hooks.strong_hook_cooldown_years", 5) * 365)
	else:
		remove_hook(owner, target_id)
	game.emit("hook.used", {"owner": owner, "target": target_id, "strong": h.get("strong", false)})
	return true
