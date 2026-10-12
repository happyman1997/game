class_name AmbitionPanel
extends RefCounted
## Желания в окне персонажа: карточка текущего желания (ход, терпение,
## как исполнить, награда), выбор своего желания игроком из предложенных,
## кнопки «Исполнить» (сюзерену) и «Оставить желание» (игроку).


## Раздел «Желание» (или null, если показывать нечего).
static func section(app: App, c: Dictionary) -> Variant:
	var g := app.game
	if not g.engine.has_feature("ambitions") or c.death != null:
		return null
	var is_me := g.is_player(c.id)
	var a: Variant = Ambitions.current(c)
	if a != null:
		return K.section(app.t("ui.ambition"), [card(app, c, a)], "star")
	if not is_me:
		return null
	var offs := Ambitions.offers(c)
	if not offs.is_empty():
		return offers_section(app, c, offs)
	var cd: Variant = c.vars.get("ambition_cd")
	if cd != null and int(cd) > g.date:
		return K.section(app.t("ui.ambition"), [K.label(app.t("ui.ambition_cooldown", {"date": CharacterPanel.fmt_date(app, int(cd))}), "MutedLabel")], "star")
	return null


## Подстановки для подсказки «как исполнить»: цель, сколько нужно и осталось.
static func _params(g: Game, c: Dictionary, aid: String, target: Variant) -> Dictionary:
	var out := {"target": g.scope_name(target) if target is Dictionary else ""}
	var d: Variant = Ambitions.def_of(g, aid)
	var pr: Variant = d.get("progress") if d != null else null
	if not (pr is Dictionary):
		return out
	var cur: Variant = Ambitions.current(c)
	var prog: Variant = Ambitions.progress_of(g, c) if cur != null and str(cur.id) == aid else null
	if prog != null:
		out["need"] = K.fmt(float(prog.need))
		out["left"] = K.fmt(maxf(0.0, float(prog.need) - float(prog.done)))
	else:
		var ctx := Ambitions._ctx(g, c, target)
		var need := maxf(1.0, Interp.eval_value(ctx, ctx.root, pr.get("need", 1)))
		out["need"] = K.fmt(need)
		out["left"] = K.fmt(need)
	return out


static func _yrs(app: App, y: float) -> String:
	return app.t("ui.years_short", {"n": K.fmt(y, 1 if y < 10.0 and y != floorf(y) else 0)})


## Награда за исполнение (эффект on_fulfilled) строкой BBCode.
static func _reward_bb(app: App, c: Dictionary, d: Dictionary, target: Variant) -> String:
	var g := app.game
	if d.get("on_fulfilled") == null:
		return BB.muted(app.t("ui.ambition_reward_none"))
	var scopes := {"owner": {"type": "character", "id": c.id}}
	if target is Dictionary:
		scopes["target"] = target
	return BB.effect(g, d.on_fulfilled, {"type": "character", "id": c.id}, scopes)


## Карточка текущего желания. Своё — подробно; чужое — кратко (заголовок,
## ход и терпение), остальное — в подсказке.
static func card(app: App, c: Dictionary, a: Dictionary) -> Control:
	var g := app.game
	var aid := str(a.id)
	var d: Variant = Ambitions.def_of(g, aid)
	if d == null:
		return K.label(aid, "MutedLabel")
	var is_me := g.is_player(c.id)
	var compact := not is_me
	var p: Variant = g.player
	var cid: String = c.id
	var box := K.vbox([], 6)
	var name := Ambitions.describe_name(g, c, a)
	var head := K.hbox([K.icon(d.get("icon", "star"), 24 if compact else 28), K.label(name, "GoldLabel")], 8)
	head.add_child(K.expand())
	var years := Ambitions.years_of(g, c)
	var since := _yrs(app, floorf(years)) if years >= 1.0 else app.t("ui.months_short", {"n": maxi(1, floori(years * 12.0))})
	head.add_child(K.label(app.t("ui.ambition_since", {"n": since}), "MutedLabel"))
	box.add_child(head)
	var tipbb := BB.title(name)
	var desc := g.loc.t_or("ambition_desc." + aid, "")
	if desc != "":
		if compact:
			tipbb += "\n" + BB.i(desc)
		else:
			box.add_child(K.para(desc, "MutedLabel"))
	# как исполнить
	if g.loc.t_or("ambition_hint." + aid, "") != "":
		var how := BB.gold(app.t("ui.ambition_how") + ": ") + BB.esc(g.loc.t("ambition_hint." + aid, _params(g, c, aid, a.get("target"))))
		if compact:
			tipbb += "\n\n" + how
		else:
			box.add_child(K.rich(how))
	# ход исполнения
	var pr: Variant = Ambitions.progress_of(g, c)
	if pr != null:
		var done := minf(float(pr.done), float(pr.need))
		box.add_child(K.bar(done, float(pr.need), Color("#4a8a50"), 22,
			app.t("ui.ambition_progress", {"done": K.fmt(done), "need": K.fmt(float(pr.need))})))
	# терпение: сколько ещё ждать до обиды и до отказа
	var patience := Data.num(d.get("patience"), 3)
	var expire := Data.num(d.get("expire"), 8)
	var credit_liege: bool = d.get("credit") == "liege" and not is_me
	if credit_liege:
		var over := years >= patience
		var txt := app.t("ui.ambition_patience_over") if over else app.t("ui.ambition_patience", {"n": _yrs(app, ceilf(patience - years))})
		var fr := Ambitions.frustration(g, c)
		if fr > 0.0:
			txt += " · " + app.t("ui.ambition_frustration", {"n": K.fmt(-fr)})
		var bar := K.bar(years, expire, Color("#8a3028") if over else Color("#8a6a2a"), 22, txt)
		var max_fr := _n(g, "frustration_max", 25)
		K.tip(bar, BB.title(app.t("ui.ambition_patience", {"n": _yrs(app, patience)})) + "\n" + BB.i(app.t("ui.ambition_patience_tip",
			{"p": _yrs(app, patience), "max": K.fmt(-max_fr), "expire": _yrs(app, expire)})))
		box.add_child(bar)
	elif not compact:
		box.add_child(K.label(app.t("ui.ambition_expire", {"n": _yrs(app, maxf(0.0, ceilf(expire - years)))}), "SmallLabel"))
	# награда и благодарность
	var rew := BB.gold(app.t("ui.ambition_reward") + ":") + "\n" + _reward_bb(app, c, d, a.get("target"))
	if credit_liege and p != null and c.liege == p.id:
		var om: Variant = g.content.get_def("opinion_modifiers", "ambition_fulfilled")
		if om != null:
			rew += "\n" + BB.good(app.t("ui.ambition_credit", {"n": K.signed(Data.num(om.get("value"))), "years": _yrs(app, Data.num(om.get("years"), 10))}))
	if compact:
		tipbb += "\n\n" + rew
	else:
		box.add_child(K.rich(rew))
	# кнопки
	if p != null and Ambitions.grantable_by(g, c, p):
		var idef: Variant = g.content.get_def("interactions", "fulfill_ambition")
		if idef != null:
			var cost := {"gold": Ambitions.grant_cost(g, c, "gold"), "prestige": Ambitions.grant_cost(g, c, "prestige")}
			var b := K.button(app.t("ui.ambition_grant"), func():
				InteractionWindow.open(app, idef, app.game.player.id, cid), {"icon": "star", "variation": "GoldButton"})
			K.tip(b, BB.title(app.t("ui.ambition_grant")) + "\n" + BB.i(app.t("ui.ambition_grant_tip")) + "\n" + BB.cost(g, cost))
			head.add_child(b)
	if is_me:
		var b := K.button(app.t("ui.ambition_abandon"), func():
			var ch: Variant = app.game.ch(cid)
			if ch != null:
				Ambitions.abandon(app.game, ch)
			app.mark_dirty(true), {"icon": "close"})
		K.tip(b, BB.title(app.t("ui.ambition_abandon")) + "\n" + BB.bad(app.t("ui.ambition_abandon_tip", {"n": K.fmt(_n(g, "abandon_stress", 10))})))
		box.add_child(K.hbox([b], 6))
	var panel := K.panel(K.margin(box, 10, 6 if compact else 8), "RowPanel")
	if compact:
		K.tip(panel, tipbb)
	return panel


static func _n(g: Game, key: String, def: float) -> float:
	return g.def_num("ambitions." + key, def)


## Выбор своего желания игроком.
static func offers_section(app: App, c: Dictionary, offs: Array) -> Control:
	var g := app.game
	var list := K.vbox([], 6)
	list.add_child(K.para(app.t("ui.ambition_choose_tip"), "MutedLabel"))
	for i in offs.size():
		var o: Dictionary = offs[i]
		var aid := str(o.id)
		var d: Variant = Ambitions.def_of(g, aid)
		if d == null:
			continue
		var name := g.loc.t("ambition." + aid, {"target": g.scope_name(o.target) if o.get("target") is Dictionary else ""})
		var idx: int = i
		var cid: String = c.id
		var pick := K.button(app.t("ui.ambition_pick"), func():
			var ch: Variant = app.game.ch(cid)
			if ch != null:
				Ambitions.choose_offer(app.game, ch, idx)
			app.mark_dirty(true), {"variation": "GoldButton", "min_w": 110})
		var head := K.hbox([K.icon(d.get("icon", "star"), 26), K.label(name, "GoldLabel"), K.expand(), pick], 8)
		var inner := K.vbox([head], 4)
		var hint := g.loc.t_or("ambition_hint." + aid, "")
		if hint != "":
			inner.add_child(K.rich(BB.esc(g.loc.t("ambition_hint." + aid, _params(g, c, aid, o.get("target"))))))
		inner.add_child(K.rich(BB.gold(app.t("ui.ambition_reward") + ":") + "\n" + _reward_bb(app, c, d, o.get("target"))))
		var card := K.panel(K.margin(inner, 10, 6), "RowPanel")
		var desc := g.loc.t_or("ambition_desc." + aid, "")
		if desc != "":
			K.tip(card, BB.title(name) + "\n" + BB.i(desc))
		list.add_child(card)
	var cid2: String = c.id
	var dec := K.button(app.t("ui.ambition_decline"), func():
		var ch: Variant = app.game.ch(cid2)
		if ch != null:
			Ambitions.choose_offer(app.game, ch, -1)
		app.mark_dirty(true), {"icon": "hourglass"})
	K.tip(dec, BB.muted(app.t("ui.ambition_decline_tip")))
	list.add_child(K.hbox([K.expand(), dec], 0))
	return K.section(app.t("ui.ambition_choose"), [list], "star")
