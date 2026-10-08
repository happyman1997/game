class_name InteractionWindow
extends RefCounted
## Окно взаимодействия: выбор кандидата/цели, прогноз согласия, отправка.


static func open(app: App, def: Dictionary, actor_id: String, recipient_id: String) -> void:
	var g := app.game
	var st := {"secondary": null, "target": null, "use_hook": false}
	var body := K.vbox([], 10)
	body.custom_minimum_size = Vector2(560, 0)
	var panel := K.panel(K.margin(body, 6))
	var close_ref := [Callable()]
	var render_ref := [Callable()]
	var render := func() -> void:
		K.clear(body)
		var actor: Dictionary = g.ch(actor_id)
		var recipient: Dictionary = g.ch(recipient_id)
		var title := K.vbox([
			K.hbox([K.icon(def.get("icon", "scroll"), 26), K.label(g.name_of("interactions", def.id), "HeaderLabel")], 8, BoxContainer.ALIGNMENT_CENTER),
			K.para(g.desc_of("interactions", def.id), "MutedLabel"),
		], 4)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body.add_child(K.hbox([W.portrait(app, actor, 72, {"clickable": false}), title, W.portrait(app, recipient, 72, {"clickable": false})], 12))
		body.add_child(K.sep())
		var sa: Variant = def.get("secondary_actor")
		if sa != null:
			var cands := Interactions.secondary_candidates(g, def, actor, recipient)
			if st.secondary == null and cands.size() == 1:
				st.secondary = cands[0].id
			body.add_child(K.label(g.text(sa.get("title", "ui.choose_candidate")) if sa is Dictionary else app.t("ui.choose_candidate"), "SubheaderLabel"))
			var list := K.vbox([], 3)
			for c in cands:
				var acc := Interactions.acceptance(g, def, actor, recipient, {"secondary": c.id, "target": st.target})
				var right: Array = []
				if not acc.auto:
					right.append(K.rich(BB.signed(acc.total), false))
				var cid: String = c.id
				var row := K.button("", func():
					st.secondary = cid
					render_ref[0].call(), {"variation": "FlatButton", "toggled": st.secondary == c.id, "min_h": 52})
				var inner := K.hbox([W.portrait(app, c, 36, {"clickable": false}),
					K.vbox([K.label(Chars.full_name(g, c, true)), K.label(app.t("ui.age_n", {"n": Chars.age_of(g, c)}), "SmallLabel")], 0)], 8)
				inner.get_child(1).size_flags_horizontal = Control.SIZE_EXPAND_FILL
				for r in right:
					inner.add_child(r)
				inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 6)
				inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
				for ch in inner.get_children():
					ch.mouse_filter = Control.MOUSE_FILTER_IGNORE
				row.add_child(inner)
				list.add_child(row)
			if cands.is_empty():
				list.add_child(K.label(app.t("ui.no_candidates"), "MutedLabel"))
			var sc := K.scroll(list)
			sc.custom_minimum_size.y = mini(260, 58 * maxi(1, cands.size()))
			body.add_child(sc)
		var tg: Variant = def.get("target")
		if tg != null:
			var opts := Interactions.target_options(g, def, actor, recipient)
			if st.target == null and opts.size() == 1:
				st.target = opts[0].get("ref")
			body.add_child(K.label(g.text(tg.get("title", "ui.choose_target")) if tg is Dictionary else app.t("ui.choose_target"), "SubheaderLabel"))
			var list := K.vbox([], 3)
			for o in opts:
				var ref: Variant = o.get("ref")
				var selected: bool = st.target is Dictionary and ref is Dictionary and st.target.get("id") == ref.get("id")
				list.add_child(K.button(str(o.label), func():
					st.target = ref
					render_ref[0].call(), {"variation": "FlatButton", "toggled": selected, "align": HORIZONTAL_ALIGNMENT_LEFT}))
			var sc := K.scroll(list)
			sc.custom_minimum_size.y = mini(220, 36 * maxi(1, opts.size()))
			body.add_child(sc)
		var args := {"secondary": st.secondary, "target": st.target, "use_hook": st.use_hook}
		var ctx := Interactions.context(g, def, actor, recipient, args)
		var cost := Interactions.cost(g, def, ctx)
		body.add_child(K.rich("%s: %s" % [BB.esc(app.t("ui.cost")), BB.cost(g, cost)]))
		var ready: bool = (sa == null or st.secondary != null) and (tg == null or st.target != null)
		if ready:
			if def.get("scheme") != null:
				var tmp := {"id": "preview", "type": def.scheme, "owner": actor.id, "target": recipient.id, "progress": 0, "start": g.date, "discovered": false}
				var sdef: Variant = g.content.get_def("schemes", def.scheme)
				var sctx := Schemes.scheme_context(g, tmp)
				body.add_child(K.panel(K.rich(BB.title(app.t("ui.on_success")) + "\n" + BB.desc_lines(Interp.describe_effect(sctx, sctx.root, sdef.get("on_success") if sdef != null else null))), "InsetPanel"))
			else:
				if Interactions.hook_available(g, def, actor, recipient):
					var decider := Interactions.decider_of(g, def, recipient)
					var strong := false
					for hk in actor.get("hooks", []):
						if hk.target == decider.id and hk.get("strong", false):
							strong = true
					var cb := CheckBox.new()
					cb.text = app.t("ui.use_hook", {"kind": app.t("ui.hook_strong" if strong else "ui.hook_weak")})
					cb.button_pressed = st.use_hook
					cb.focus_mode = Control.FOCUS_NONE
					cb.toggled.connect(func(on):
						st.use_hook = on
						App.locked(render_ref[0]))
					body.add_child(cb)
				var acc := Interactions.acceptance(g, def, actor, recipient, args)
				if not acc.auto:
					var ok: bool = float(acc.total) > 0
					var head := BB.c("%s (%s)" % [app.t("ui.will_accept" if ok else "ui.will_decline"), K.signed(acc.total)], BB.GOOD if ok else BB.BAD)
					body.add_child(K.panel(K.rich("[font_size=17][b]%s[/b][/font_size]\n%s" % [head, BB.breakdown(acc.parts)]), "InsetPanel"))
				var lines: Array = Interp.describe_effect(ctx, ctx.root, def.get("on_accept"))
				if not lines.is_empty():
					body.add_child(K.panel(K.rich(BB.title(app.t("ui.effects")) + "\n" + BB.desc_lines(lines)), "InsetPanel"))
		var blockers := Interactions.blockers(g, def, actor, recipient, args) if ready else []
		if not blockers.is_empty():
			body.add_child(K.rich(BB.reasons(blockers)))
		var send := K.button(app.t("ui.start_scheme" if def.get("scheme") != null else "ui.send"), func():
			var res := Interactions.execute(g, def, actor, recipient, args)
			close_ref[0].call()
			var kind := "good" if res == "accepted" or res == "scheme" else ("bad" if res == "declined" or res == "invalid" else "info")
			app.toast(app.t("ui.ia_result." + res), kind)
			app.mark_dirty(true), {"variation": "GoldButton", "disabled": not ready or not blockers.is_empty(), "min_w": 180})
		body.add_child(K.hbox([K.expand(), send, K.button(app.t("ui.cancel"), func(): close_ref[0].call(), {"min_w": 120}), K.expand()], 10))
	render_ref[0] = render
	render.call()
	close_ref[0] = app.modal(panel)
