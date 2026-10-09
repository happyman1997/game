class_name FeatureList
extends RefCounted
## Встроенные механики движка.


static func builtin() -> Array:
	return [Lifestyles.new(), Council.new(), Prison.new(), Factions.new(), Regiments.new(), Secrets.new(), Laws.new(), Knights.new(), Politics.new()]
