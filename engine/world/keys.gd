class_name Keys
extends RefCounted
## Ключи к запертым действиям. Действие открыто всем (is_shown), но вершинные
## — чудо, показательная казнь, великий сбор — нужно заслужить; к каждому ведёт
## несколько дорог: перк стези, черта, вещь, деяния, положение, слава или
## страх. Поле keys у решения или взаимодействия — список ключей, хватает
## любого; без них действие видно, но заперто: «Нужен один из ключей: …».
##
## Ключ:
##   { perk: <перк> }                  — открыт перк стези
##   { trait: <черта> }                — есть черта
##   { deed: <деяние>, count: N }      — столько деяний за жизнь (deed_goal.<деяние>)
##   { artifact: <тип вещи> }          — есть вещь этого типа
##   { trigger: { ... }, desc: <ключ> } — любое условие (desc — как назвать)
## Ключи — про того, кто действует (root): ИИ проверяет их один раз, не глядя
## на того, к кому обращаются.


static func has_keys(def: Dictionary) -> bool:
	return def.get("keys") is Array and not def.keys.is_empty()


## Условие ключа.
static func trigger_of(key: Variant) -> Variant:
	if not (key is Dictionary):
		return null
	if key.get("perk") != null:
		return {"has_perk": key.perk}
	if key.get("trait") != null:
		return {"has_trait": key.trait}
	if key.get("deed") != null:
		return {"deeds_" + str(key.deed): ">= %d" % int(Data.num(key.get("count"), 1))}
	if key.get("artifact") != null:
		return {"has_artifact_type": key.artifact}
	return key.get("trigger")


## Как ключ называется в подсказке.
static func name_of(game: Game, ctx: ScriptContext, key: Variant) -> String:
	if not (key is Dictionary):
		return "?"
	if key.get("desc") != null:
		return game.text(key.desc, ctx)
	if key.get("perk") != null:
		return game.loc.t("key.perk", {"name": game.name_of("perks", str(key.perk))})
	if key.get("trait") != null:
		return game.loc.t("key.trait", {"name": game.name_of("traits", str(key.trait))})
	if key.get("deed") != null:
		return game.loc.t("key.deed", {"goal": game.text("deed_goal." + str(key.deed)), "n": int(Data.num(key.get("count"), 1))})
	if key.get("artifact") != null:
		return game.loc.t("key.artifact", {"name": game.name_of("artifact_types", str(key.artifact))})
	return "?"


## Ключи действия: [{name, ok}].
static func status(ctx: ScriptContext, scope: Variant, def: Dictionary) -> Array:
	var out := []
	for k in Data.as_array(def.get("keys")):
		out.append({"name": name_of(ctx.game, ctx, k), "ok": Interp.eval_trigger(ctx, scope, trigger_of(k))})
	return out


## Есть ли хоть один ключ (действие без ключей открыто всегда).
static func opened(ctx: ScriptContext, scope: Variant, def: Dictionary) -> bool:
	if not has_keys(def):
		return true
	for k in def.keys:
		if Interp.eval_trigger(ctx, scope, trigger_of(k)):
			return true
	return false


## Причина «заперто» для списка препятствий (или пусто).
static func blocker(ctx: ScriptContext, scope: Variant, def: Dictionary) -> String:
	if opened(ctx, scope, def):
		return ""
	var names := Data.as_array(def.keys).map(func(k): return name_of(ctx.game, ctx, k))
	return ctx.game.loc.t("ui.keys_needed", {"list": ctx.game.loc.t("ui.keys_or").join(names)})


static func validate(v: ScriptValidator, def: Dictionary, where: String) -> void:
	if def.get("keys") == null:
		return
	if not (def.keys is Array):
		v.issue("%s: keys — список ключей" % where)
		return
	for k in def.keys:
		if not (k is Dictionary):
			v.issue("%s: ключ — словарь { perk | trait | deed | artifact | trigger }" % where)
			continue
		if k.get("perk") != null:
			v.ref("perks", k.perk, where + " keys")
		elif k.get("trait") != null:
			v.ref("traits", k.trait, where + " keys")
		elif k.get("deed") != null:
			v.ref("deeds", k.deed, where + " keys")
		elif k.get("artifact") != null:
			v.ref("artifact_types", k.artifact, where + " keys")
		elif k.get("trigger") != null:
			v.trigger(k.trigger, where + " keys")
			if k.get("desc") == null:
				v.issue("%s: у ключа-условия нужен desc" % where)
		else:
			v.issue("%s: ключ без perk, trait, deed, artifact или trigger" % where)
