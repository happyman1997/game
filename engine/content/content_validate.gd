class_name ContentValidate
extends RefCounted
## Проверка контента модов: ссылки на несуществующие записи и неизвестные
## ключи в скриптовых блоках. Результат показывается в менеджере модов и
## выводится командой tools/validate.gd.


static func validate(engine: GameEngine) -> Array:
	var c := engine.content
	var v = ScriptValidator.new(engine)
	for p in c.all("provinces"):
		if p.get("impassable", false):
			continue
		var w = "provinces/" + p.id
		v.ref("cultures", p.get("culture"), w)
		v.ref("faiths", p.get("faith"), w)
		v.ref("terrain", p.get("terrain"), w)
		for h in Data.as_array(p.get("holdings")):
			v.ref("holdings", h, w)
		v.ref("titles", p.get("duchy"), w)
	for t in c.all("titles"):
		v.ref("titles", t.get("liege"), "titles/" + t.id)
	for t in c.all("traits"):
		for o in Data.as_array(t.get("opposites")):
			v.ref("traits", o, "traits/" + t.id)
	for ch in c.all("characters"):
		var w = "characters/" + ch.id
		for t in Data.as_array(ch.get("traits")):
			v.ref("traits", t, w)
		v.ref("cultures", ch.get("culture"), w)
		v.ref("faiths", ch.get("faith"), w)
		v.ref("dynasties", ch.get("dynasty"), w)
		v.ref("characters", ch.get("father"), w)
		v.ref("characters", ch.get("mother"), w)
	for b in c.all("bookmarks"):
		var holders: Variant = b.get("holders")
		if holders is Dictionary:
			for title in holders:
				v.ref("titles", title, "bookmarks/" + b.id)
				v.ref("characters", holders[title], "bookmarks/" + b.id)
	for law in c.all("succession_laws"):
		if not engine.succession_algorithms.has(str(law.get("algorithm"))):
			v.issue("succession_laws/%s: нет алгоритма \"%s\"" % [law.id, law.get("algorithm")])
	for cb in c.all("casus_belli"):
		if not engine.cb_targets.has(str(cb.get("targets"))):
			v.issue("casus_belli/%s: нет поставщика целей \"%s\"" % [cb.id, cb.get("targets")])
		v.trigger(cb.get("is_valid"), "casus_belli/%s is_valid" % cb.id)
		for k in ["on_declare", "on_victory", "on_white_peace", "on_defeat"]:
			v.effect(cb.get(k), "casus_belli/%s %s" % [cb.id, k])
	for e in c.all("events"):
		var w = "events/" + e.id
		v.trigger(e.get("trigger"), w + " trigger")
		v.effect(e.get("immediate"), w + " immediate")
		v.effect(e.get("after"), w + " after")
		var opts := Data.as_array(e.get("options"))
		for i in opts.size():
			if opts[i] is Dictionary:
				v.trigger(opts[i].get("trigger"), "%s option %d" % [w, i + 1])
				v.effect(opts[i].get("effect"), "%s option %d" % [w, i + 1])
				var sp: Variant = opts[i].get("skill")
				if sp is Dictionary:
					if sp.get("skill") != null and not c.has("skills", str(sp.skill)):
						v.issue("%s option %d: нет навыка \"%s\"" % [w, i + 1, sp.skill])
					if sp.get("archetype") != null and not c.has("skill_archetypes", str(sp.archetype)):
						v.issue("%s option %d: нет архетипа \"%s\"" % [w, i + 1, sp.archetype])
					if sp.get("check") != null:
						v.effect(opts[i].get("success"), "%s option %d success" % [w, i + 1])
						v.effect(opts[i].get("failure"), "%s option %d failure" % [w, i + 1])
				elif sp != null:
					v.issue("%s option %d: skill — словарь { skill, min | check } или { archetype }" % [w, i + 1])
	for a in c.all("skill_archetypes"):
		if not (a.get("skills") is Array) or a.skills.size() < 2:
			v.issue("skill_archetypes/%s: skills — список из двух и более навыков" % a.id)
			continue
		for sk in a.skills:
			if not c.has("skills", str(sk)):
				v.issue("skill_archetypes/%s: нет навыка \"%s\"" % [a.id, sk])
	for d in c.all("decisions"):
		v.trigger(d.get("is_shown"), "decisions/%s is_shown" % d.id)
		v.trigger(d.get("is_valid"), "decisions/%s is_valid" % d.id)
		v.effect(d.get("effect"), "decisions/%s effect" % d.id)
	for d in c.all("interactions"):
		var w = "interactions/" + d.id
		v.trigger(d.get("is_shown"), w + " is_shown")
		v.trigger(d.get("is_valid"), w + " is_valid")
		v.trigger(d.get("ai_potential"), w + " ai_potential")
		v.effect(d.get("on_accept"), w + " on_accept")
		v.effect(d.get("on_decline"), w + " on_decline")
		var sa: Variant = d.get("secondary_actor")
		if sa is Dictionary:
			v.trigger(sa.get("trigger"), w + " secondary_actor")
			for l in Data.as_array(sa.get("list")):
				if not engine.scripting.lists.has(str(l)):
					v.issue("%s: нет списка \"%s\"" % [w, l])
		var tg: Variant = d.get("target")
		if tg is Dictionary and not engine.interaction_targets.has(str(tg.get("provider"))):
			v.issue("%s: нет поставщика целей \"%s\"" % [w, tg.get("provider")])
		v.ref("schemes", d.get("scheme"), w)
		var dec: Variant = d.get("decider")
		if dec != null and dec != "recipient" and dec != "guardian" and not engine.interaction_deciders.has(str(dec)):
			v.issue("%s: нет решающего \"%s\"" % [w, dec])
	for s in c.all("schemes"):
		v.trigger(s.get("is_valid"), "schemes/%s is_valid" % s.id)
		for k in ["on_success", "on_failure", "on_discovered"]:
			v.effect(s.get(k), "schemes/%s %s" % [s.id, k])
	for oa in c.all("on_actions"):
		v.effect(oa.get("effect"), "on_actions/" + oa.id)
		for ev in Data.as_array(oa.get("events")):
			v.ref("events", ev, "on_actions/" + oa.id)
		var re: Variant = oa.get("random_events")
		if re is Dictionary:
			var evs: Variant = re.get("events")
			var ids := []
			if evs is Array:
				ids = evs.map(func(x): return x.get("event") if x is Dictionary else x)
			elif evs is Dictionary:
				ids = evs.keys()
			for ev in ids:
				v.ref("events", ev, "on_actions/" + oa.id)
	for st in c.all("scripted_triggers"):
		v.trigger(Interp.body_of(st, "trigger"), "scripted_triggers/" + st.id)
	for se in c.all("scripted_effects"):
		v.effect(Interp.body_of(se, "effect"), "scripted_effects/" + se.id)
	for b in c.all("buildings"):
		v.trigger(b.get("trigger"), "buildings/" + b.id)
	for id in engine.content_validators.ids():
		engine.content_validators.get_item(id).call(engine, v)
	return v.issues
