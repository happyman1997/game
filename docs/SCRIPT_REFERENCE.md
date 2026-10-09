# Справочник скриптового языка

> Файл сгенерирован командой `godot --headless --path . -s tools/script_docs.gd` из реестров движка и включённых модов.
> Колонка «Источник» показывает, кто зарегистрировал элемент (core — движок, иначе id мода).

## Триггеры (условия)

| Имя | Скоупы | Описание | Источник |
|---|---|---|---|
| `can_marry` | character | Может вступить в брак с персонажем | core |
| `can_use_hook_on` | character | Крюк на персонажа можно использовать сейчас | core |
| `capital_has_disease` | character | В столице персонажа (или его сюзерена) эпидемия. | plague |
| `culture` | character, province | Культура равна | core |
| `dragon_wary` | character | Ближайший дракон настороже после недавней охоты | arcana |
| `dynasty` | character | Династия равна | core |
| `faction_type` | faction | Тип фракции | core/factions |
| `faith` | character, province | Вера равна | core |
| `global_var` | любой | Сравнение глобальной переменной | core |
| `has_any_claim` | character | Есть претензии | core |
| `has_building` | province | Есть постройка | core |
| `has_claim_on` | character | Есть претензия на титул | core |
| `has_council_task` | character | Сюзерен: на какой-то должности выбрана задача (или одна из списка) | core/council |
| `has_flag` | character | Есть флаг | core |
| `has_focus` | character | Выбран фокус образа жизни | core/lifestyles |
| `has_global_flag` | любой | Есть глобальный флаг | core |
| `has_holding` | province | Есть владение типа | core |
| `has_hook_on` | character | Есть крюк на персонажа | core |
| `has_imprisonment_reason` | character | Есть законный повод заключить персонажа (преступление против этого персонажа) | core/prison |
| `has_known_trait` | character | Есть черта, известная всем (не скрытая или разоблачённая) | core |
| `has_lifestyle` | character | Текущий фокус принадлежит образу жизни | core/lifestyles |
| `has_modifier` | character | Есть модификатор | core |
| `has_opinion_modifier` | character | Есть модификатор мнения: { target, modifier } | core |
| `has_perk` | character | Открыт перк | core/lifestyles |
| `has_province_flag` | province | Есть флаг провинции | core |
| `has_province_modifier` | province | Есть модификатор провинции | core |
| `has_realm_law` | character | Действует закон державы | core/laws |
| `has_regiment` | character | Есть отряд этого типа (или любой: yes) | core/regiments |
| `has_scheme` | character | Ведёт интригу: has_scheme: murder или { type, target } | core |
| `has_secret` | character | Есть секрет (yes или тип) | core/secrets |
| `has_snubbed_powerful_vassal` | character | Кто-то из влиятельных вассалов не получил места в совете | core/politics |
| `has_strong_hook_on` | character | Есть сильный крюк на персонажа | core |
| `has_succession_law` | character | Закон наследования | core |
| `has_trait` | character | Есть черта | core |
| `has_trait_category` | character | Есть черта категории | core |
| `has_truce_with` | character | Перемирие с персонажем | core |
| `has_var` | character | Есть переменная | core |
| `holds_title` | character | Владеет титулом | core |
| `is_adult` | character | Совершеннолетний | core |
| `is_ai` | character | Персонаж ИИ | core |
| `is_alive` | character | Жив | core |
| `is_allied_with` | character | Союзник персонажа | core |
| `is_arcanist` | character | Владеет колдовством (дар или навык ≥ 6) | arcana |
| `is_at_war` | character | Ведёт войну | core |
| `is_at_war_with` | character | Воюет с персонажем | core |
| `is_child` | character | Ребёнок | core |
| `is_child_of` | character | Ребёнок персонажа | core |
| `is_close_family_of` | character | Близкая семья | core |
| `is_close_relative_of` | character | Слишком близкое родство для брака | core |
| `is_coastal` | province | Прибрежная | core |
| `is_councillor` | character | Заседает в совете (yes) или на должности: is_councillor: marshal | core/council |
| `is_courtier` | character | Придворный | core |
| `is_courtier_of` | character | Придворный персонажа | core |
| `is_faction_leader` | character | Возглавляет фракцию | core/factions |
| `is_female` | character | Женщина | core |
| `is_heir_of` | character | Основной наследник персонажа | core |
| `is_held` | title | У титула есть владелец | core |
| `is_imprisoned` | character | В темнице | core/prison |
| `is_imprisoned_by` | character | В темнице у персонажа | core/prison |
| `is_in_faction` | character | Состоит во фракции (yes/no или тип) | core/factions |
| `is_in_realm_of` | character | Состоит в державе персонажа | core |
| `is_independent` | character | Независимый правитель | core |
| `is_knight` | character | Служит рыцарем у своего сюзерена | core/knights |
| `is_known_monster` | character | Разоблачённое чудовище (вампир, лич, некромант, оборотень) | arcana |
| `is_landed` | character | Владеет землями | core |
| `is_liege_of` | character | Сюзерен персонажа | core |
| `is_lowborn` | character | Безродный | core |
| `is_male` | character | Мужчина | core |
| `is_married` | character | В браке | core |
| `is_occupied` | province | Оккупирована | core |
| `is_parent_of` | character | Родитель персонажа | core |
| `is_player` | character | Персонаж игрока | core |
| `is_powerful_vassal` | character | Один из влиятельных вассалов своего сюзерена | core/politics |
| `is_pregnant` | character | Беременна | core |
| `is_primary_heir` | character | Основной наследник своего сюзерена/отца | core |
| `is_ruler` | character | Владеет землями | core |
| `is_same_as` | любой | Тот же объект, что и путь | core |
| `is_scheme_target` | character | Является целью интриги | core |
| `is_sibling_of` | character | Брат/сестра персонажа | core |
| `is_spouse_of` | character | Супруг(а) персонажа | core |
| `is_vassal` | character | Вассал | core |
| `is_vassal_of` | character | Прямой вассал персонажа | core |
| `knows_secret_of` | character | Знает какой-то секрет персонажа | core/secrets |
| `near_dragon_lair` | character | Логово дракона в державе персонажа или по соседству | arcana |
| `province_has_disease` | province | В провинции эпидемия. Аргумент: yes или id болезни. | plague |
| `province_restless` | province | В провинции бродят мертвецы | arcana |
| `random_chance` | любой | Случайный шанс в процентах (используйте осторожно в триггерах) | core |
| `realm_has_barrow` | character | В державе персонажа есть древний курган | arcana |
| `realm_has_fey_hills` | character | В державе персонажа есть холмы фей | arcana |
| `realm_has_restless_dead` | character | В державе персонажа восстали мертвецы | arcana |
| `religion` | character | Религия равна | core |
| `same_culture_as` | character | Та же культура | core |
| `same_dynasty_as` | character | Та же династия | core |
| `same_faith_as` | character | Та же вера | core |
| `terrain` | province | Местность | core |
| `tier_is` | title | Ранг титула: county/duchy/kingdom/empire | core |
| `var` | любой | Сравнение переменной: var: { name: x, value: ">= 2" } | core |
| `vassal_obligation` | character | Условия службы вассала: vassal_obligation: heavy | core/politics |

## Эффекты

| Имя | Описание | Источник |
|---|---|---|
| `add_alliance` | Союз с персонажем | core |
| `add_arcane_power` | Изменить колдовскую силу: add_arcane_power: -30 | arcana |
| `add_beast_control` | Сдвинуть власть оборотня над зверем (+ укрощение, − одичание) | arcana |
| `add_blood_potency` | Изменить силу крови вампира | arcana |
| `add_blood_thirst` | Изменить жажду крови | arcana |
| `add_building` | Добавить постройку | core |
| `add_claim` | Претензия на титул | core |
| `add_courtier` | Принять ко двору | core |
| `add_development` | Изменить развитие | core |
| `add_dread` | Изменить страх, который внушает правитель | core/politics |
| `add_dynasty_prestige` | Престиж династии | core |
| `add_faction_discontent` | Изменить недовольство фракции | core/factions |
| `add_gold` | Изменить gold | core |
| `add_health` | Изменить базовое здоровье | core |
| `add_hook` | Крюк на персонажа: path или { target, strong, years } | core |
| `add_lifestyle_xp` | Опыт образа жизни: число (текущий образ жизни) или { lifestyle, value } | core/lifestyles |
| `add_modifier` | Добавить модификатор: id или { id, years/months/days } | core |
| `add_monster_kill` | Засчитать уничтоженное чудовище: add_monster_kill: 2 (слава охотника) | arcana |
| `add_opinion` | Мнение этого персонажа о target: { target, modifier, value? } | core |
| `add_perk` | Открыть перк бесплатно | core/lifestyles |
| `add_piety` | Изменить piety | core |
| `add_prestige` | Изменить prestige | core |
| `add_province_modifier` | Модификатор провинции | core |
| `add_regiment` | Получить отряд бесплатно (сверх предела) | core/regiments |
| `add_secret` | Персонаж получает секрет: add_secret: тип или { type, target, known_by } | core/secrets |
| `add_skill` | Навсегда изменить навык: { skill, value } | core |
| `add_stress` | Изменить стресс | core |
| `add_trait` | Добавить черту | core |
| `annex_war_targets` | Присоединить цели войны (в контексте войны) | core |
| `appoint_councillor` | Назначить в совет: { position, who } | core/council |
| `arcane_witness` | Риск свидетелей: { secret, chance } — кто-то при дворе узнаёт тайну | arcana |
| `awaken_dead` | Мёртвые восстают в провинции: awaken_dead: 30 (сила) | arcana |
| `become_independent` | Стать независимым | core |
| `become_vassal_of` | Стать вассалом | core |
| `blackmail` | Шантажировать персонажа его самым тяжёлым известным секретом (получить крюк) | core/secrets |
| `bless_domain` | Светлый чародей благословляет земли домена | arcana |
| `break_alliance` | Разорвать союз | core |
| `calm_factions` | Снизить недовольство всех фракций против правителя: calm_factions: 40 | core/politics |
| `cast_curse_on` | Проклясть персонажа (со стоимостью и риском разоблачения) | arcana |
| `change_culture` | Сменить культуру | core |
| `change_faith` | Сменить веру | core |
| `change_var` | Изменить переменную: { name, add } | core |
| `command_restless_dead` | Некромант подчиняет восставших мёртвых своей державы | arcana |
| `consecrate_against_dead` | Освятить земли державы против нежити | arcana |
| `create_character` | Создать персонажа: { culture, faith, female, age, traits, dynasty: new\|none\|path, court, save_scope_as } | core |
| `cure_ailments` | Снять болезни, раны и порчу | arcana |
| `death` | Смерть: yes, причина или { reason, killer } | core |
| `discover_scheme_against` | Раскрыть случайную враждебную интригу против персонажа или его семьи | core/council |
| `discover_secret` | Узнать случайный секрет кого-то из своей державы | core/secrets |
| `divorce` | Развод | core |
| `end_war` | Завершить войну: victory/white_peace/defeat | core |
| `expose_secret` | Разоблачить самый тяжёлый известный секрет персонажа | core/secrets |
| `faction_enforce_demands` | Сюзерен выполняет требования фракции | core/factions |
| `faction_start_war` | Фракция поднимает мятеж | core/factions |
| `feed_on_blood` | Вампир утоляет жажду (жертва — пленник или придворный) | arcana |
| `firestorm` | Огненная буря на крупнейшее вражеское войско у границ | arcana |
| `gain_title` | Получить титул | core |
| `give_title` | Пожаловать титул: { title, to } — получатель становится вассалом | core |
| `grant_minor_county` | Пожаловать персонажу самое бедное графство своего домена (не столицу) | core/politics |
| `hunt_dragon` | Выйти на бой с ближайшим драконом | arcana |
| `hunt_monsters` | Выследить чудовище в державе: найденная тайна раскрывается | arcana |
| `imprison` | Заключить персонажа в свою темницу: imprison: scope:x или { target, reason } | core/prison |
| `join_faction` | Вступить во фракцию против сюзерена (или создать): join_faction: <тип> | core/factions |
| `learn_secret` | Узнать тайну персонажа: { owner, type } | arcana |
| `leave_faction` | Выйти из фракции | core/factions |
| `lose_all_titles` | Потерять все титулы | core |
| `lose_title` | Потерять титул (переходит к сюзерену) | core |
| `make_pregnant` | Беременность: { father } | core |
| `mark_criminal` | Даёт target законный повод заключить этого персонажа: { target, years } | core/prison |
| `marry` | Заключить брак | core |
| `move_to_court` | Переехать ко двору персонажа | core |
| `pay_gold` | Передать золото: { target, value } | core |
| `plague_of_the_dead` | Лич поднимает мёртвых в столице главного врага | arcana |
| `purge_restless_dead` | Выжечь нежить в самой поражённой провинции державы (purge_restless_dead: { magic: yes } — светом чар, а не ополчением) | arcana |
| `release_from_prison` | Освободить этого персонажа из темницы | core/prison |
| `remove_building` | Убрать постройку | core |
| `remove_claim` | Убрать претензию | core |
| `remove_flag` | Убрать флаг | core |
| `remove_from_council` | Советник лишается места в совете сюзерена | core/politics |
| `remove_global_flag` | Убрать глобальный флаг | core |
| `remove_hook` | Убрать крюк | core |
| `remove_modifier` | Убрать модификатор | core |
| `remove_opinion` | Убрать модификатор мнения: { target, modifier } | core |
| `remove_perk` | Убрать перк | core/lifestyles |
| `remove_province_modifier` | Убрать модификатор провинции | core |
| `remove_trait` | Убрать черту | core |
| `remove_var` | Удалить переменную | core |
| `reveal_trait` | Разоблачить скрытую черту (concealed): теперь её видят все | core |
| `reverse_add_opinion` | Мнение target об этом персонаже: { target, modifier, value? } | core |
| `seat_in_council` | Дать персонажу место в своём совете (на должность по его лучшему навыку) | core/politics |
| `seize_primary_title` | Забрать основной титул персонажа (претендент): прежний владелец становится вассалом | core/factions |
| `send_message` | Сообщение игроку (если этот персонаж — игрок) | core |
| `set_flag` | Установить флаг: name или { name, days/months/years } | core |
| `set_focus` | Сменить фокус образа жизни (без перерыва) | core/lifestyles |
| `set_global_flag` | Глобальный флаг | core |
| `set_global_var` | Глобальная переменная | core |
| `set_nickname` | Прозвище (ключ локализации или текст) | core |
| `set_province_flag` | Флаг провинции | core |
| `set_realm_law` | Установить закон державы (без цены и перерыва) | core/laws |
| `set_succession_law` | Закон наследования | core |
| `set_var` | Переменная: { name, value } | core |
| `set_vassal_obligation` | Установить вассалу условия службы: set_vassal_obligation: privileged | core/politics |
| `shift_realm_law` | Сдвинуть закон группы на ступени: shift_realm_law: { group: crown_authority, by: -1 } (без цены) | core/laws |
| `sow_discord` | Посеять раздор между вассалом и его ближайшим союзником: sow_discord: scope:recipient | core/politics |
| `start_disease` | Начать эпидемию в провинции: start_disease: bubonic_plague | plague |
| `start_scheme` | Начать интригу: { type, target } | core |
| `take_title` | Отобрать титул себе: { title, from? } | core |
| `witch_hunt` | Охота на ведьм в державе | arcana |

## Значения

| Имя | Скоупы | Описание | Источник |
|---|---|---|---|
| `age` | character | Возраст | core |
| `ai_aggression` | character | Личность ИИ: aggression | core |
| `ai_boldness` | character | Личность ИИ: boldness | core |
| `ai_compassion` | character | Личность ИИ: compassion | core |
| `ai_energy` | character | Личность ИИ: energy | core |
| `ai_greed` | character | Личность ИИ: greed | core |
| `ai_honor` | character | Личность ИИ: honor | core |
| `ai_rationality` | character | Личность ИИ: rationality | core |
| `ai_sociability` | character | Личность ИИ: sociability | core |
| `ai_vengefulness` | character | Личность ИИ: vengefulness | core |
| `ai_zeal` | character | Личность ИИ: zeal | core |
| `arcane_power` | character | Колдовская сила персонажа | arcana |
| `attraction` | character | Привлекательность | core |
| `beast_control` | character | Власть оборотня над зверем: −100 (одичал) … 100 (вожак стаи) | arcana |
| `blood_potency` | character | Сила крови вампира (растёт с годами и кормлением) | arcana |
| `blood_thirst` | character | Жажда крови вампира (0–100) | arcana |
| `commander_advantage` | character | Характеристика: commander_advantage | core |
| `council_size` | character | Число занятых мест в совете | core/council |
| `crown_authority_level` | character | Уровень закона группы crown_authority (−1, если не действует) | core/laws |
| `current_year` | любой | Текущий год | core |
| `days_since_start` | любой | Дней с начала партии | core |
| `development` | province | Развитие провинции | core |
| `diplomacy` | character | Навык: diplomacy | core |
| `domain_limit` | character | Лимит домена | core |
| `dread` | character | Страх, который внушает правитель (0–100) | core/politics |
| `dynasty_prestige` | character | Престиж династии | core |
| `faction_discontent` | faction | Недовольство фракции (0–100) | core/factions |
| `faction_power` | faction | Сила фракции в % от силы сюзерена | core/factions |
| `fear_of_liege` | character | Страх перед сюзереном (0 у храбрых и гневливых) | core/politics |
| `fertility` | character | Плодовитость | core |
| `fort_level` | province | Уровень укреплений | core |
| `general_opinion` | character | Характеристика: general_opinion | core |
| `gold` | character | Золото | core |
| `health` | character | Здоровье | core |
| `income` | character | Ежемесячный доход | core |
| `infected_provinces` | любой | Число заражённых провинций в мире. | plague |
| `intrigue` | character | Навык: intrigue | core |
| `knights_power` | character | Сила рыцарей (в ополченцах) | core/knights |
| `learning` | character | Навык: learning | core |
| `levies` | character | Ополчение державы | core |
| `levy` | province | Ополчение провинции | core |
| `levy_flat` | character | Характеристика: levy_flat | core |
| `levy_ratio` | character | Доля восстановленных ополчений | core |
| `lifestyle_xp` | character | Опыт текущего образа жизни | core/lifestyles |
| `martial` | character | Навык: martial | core |
| `monsters_slain` | character | Сколько чудовищ уничтожил персонаж (слава охотника) | arcana |
| `monthly_piety` | character | Характеристика: monthly_piety | core |
| `monthly_prestige` | character | Характеристика: monthly_prestige | core |
| `num_buildings` | province | Число построек | core |
| `num_children` | character | Число живых детей | core |
| `num_claims` | character | Число претензий | core |
| `num_counties` | character | Графств в домене | core |
| `num_courtiers` | character | Число придворных | core |
| `num_de_jure_counties` | title | Де-юре графств в титуле | core |
| `num_faction_members` | faction | Число членов фракции | core/factions |
| `num_holdings` | province | Число владений | core |
| `num_hooks` | character | Число крюков персонажа на других | core |
| `num_knights` | character | Число рыцарей | core/knights |
| `num_known_secrets` | character | Сколько чужих секретов знает персонаж | core/secrets |
| `num_perks` | character | Число открытых перков | core/lifestyles |
| `num_powerful_vassals` | character | Число влиятельных вассалов | core/politics |
| `num_prisoners` | character | Число пленников | core/prison |
| `num_regiments` | character | Число отрядов | core/regiments |
| `num_secrets` | character | Число секретов персонажа | core/secrets |
| `num_spouses` | character | Число супругов | core |
| `num_traits` | character | Число черт | core |
| `num_vassals` | character | Число прямых вассалов | core |
| `num_wars` | character | Число войн | core |
| `opinion` | character | Мнение о персонаже: opinion(scope:x) | core |
| `piety` | character | Благочестие | core |
| `prestige` | character | Престиж | core |
| `prison_months` | character | Сколько месяцев персонаж в темнице | core/prison |
| `prowess` | character | Навык: prowess | core |
| `ransom_cost` | character | Размер выкупа за пленника | core/prison |
| `realm_size` | character | Графств в державе | core |
| `regiment_cap` | character | Предел отрядов | core/regiments |
| `regiment_power` | character | Сила отрядов, не поднятых в армию (в ополченцах) | core/regiments |
| `reverse_opinion` | character | Мнение персонажа-аргумента об этом персонаже | core |
| `scheme_defense` | character | Характеристика: scheme_defense | core |
| `scheme_power` | character | Характеристика: scheme_power | core |
| `scheme_progress` | scheme | Прогресс интриги | core |
| `sorcery` | character | Навык: sorcery | core |
| `stewardship` | character | Навык: stewardship | core |
| `stress` | character | Стресс | core |
| `stress_level` | character | Уровень стресса (стресс / 100) | core |
| `tax` | province | Налог провинции | core |
| `tier` | character | Ранг основного титула (0 — нет земель, 1 — граф ... 4 — император) | core |
| `title_tier` | title | Ранг титула | core |
| `vampire_tier` | character | Уровень вампира: 1 птенец, 2 вампир, 3 старейшина, 4 древний (0 — не вампир) | arcana |
| `vassal_opinion` | character | Характеристика: vassal_opinion | core |
| `war_duration_days` | war | Длительность войны | core |
| `world_vampires` | любой | Сколько вампиров живёт в мире (считается раз в месяц) | arcana |

## Ссылки на скоупы

| Имя | Скоупы | Описание | Источник |
|---|---|---|---|
| `attacker` | war | Нападающий | core |
| `capital` | character | Столица (провинция) | core |
| `capital_province` | title | Столица титула | core |
| `chancellor` | character | Советник на должности chancellor | core/council |
| `controller` | province | Кто контролирует провинцию | core |
| `county` | province | Графство провинции | core |
| `court_chaplain` | character | Советник на должности court_chaplain | core/council |
| `court_mage` | character | Советник на должности court_mage | core/council |
| `de_jure_liege` | title | Де-юре сюзеренный титул | core |
| `defender` | war | Защитник | core |
| `dynasty` | character | Династия | core |
| `employer` | character | Синоним liege | core |
| `faction_claimant` | faction | Претендент фракции | core/factions |
| `faction_leader` | faction | Лидер фракции | core/factions |
| `faction_target` | faction | Сюзерен, против которого фракция | core/factions |
| `father` | character | Отец | core |
| `founder` | dynasty | Основатель династии | core |
| `holder` | title, province | Владелец титула/графства | core |
| `joined_faction` | character | Фракция, в которой состоит персонаж | core/factions |
| `killer` | character | Убийца | core |
| `liege` | character | Сюзерен (или владелец двора для придворных) | core |
| `marshal` | character | Советник на должности marshal | core/council |
| `mother` | character | Мать | core |
| `owner` | scheme, army | Владелец интриги/армии | core |
| `player` | любой | Персонаж игрока | core |
| `primary_heir` | character | Основной наследник | core |
| `primary_title` | character | Основной титул | core |
| `province` | title | Провинция графства | core |
| `spouse` | character | Супруг(а) (первый) | core |
| `spymaster` | character | Советник на должности spymaster | core/council |
| `steward` | character | Советник на должности steward | core/council |
| `target` | scheme | Цель интриги | core |
| `top_liege` | character | Верховный сюзерен | core |

## Списки (any_ / every_ / random_ / ordered_)

| Имя | Скоупы | Описание | Источник |
|---|---|---|---|
| `ally` | character | Союзники | core |
| `child` | character | Живые дети | core |
| `claim` | character | Претензии | core |
| `close_family` | character | Близкая семья (супруги, дети, родители, братья/сёстры) | core |
| `councillor` | character | Члены совета | core/council |
| `courtier` | character | Придворные | core |
| `daughter` | character | Дочери | core |
| `de_jure_county` | title | Де-юре графства | core |
| `de_jure_vassal_title` | title | Де-юре вассальные титулы | core |
| `domain_province` | character | Провинции домена | core |
| `dynasty_member` | character | Живые члены династии | core |
| `faction_against` | character | Фракции против персонажа | core/factions |
| `faction_member` | faction | Члены фракции | core/factions |
| `grandchild` | character | Внуки | core |
| `held_title` | character | Титулы | core |
| `independent_ruler` | любой | Независимые правители | core |
| `knight` | character | Рыцари правителя | core/knights |
| `known_secret_owner` | character | Персонажи, чьи секреты известны этому персонажу | core/secrets |
| `liege` | character | Сюзерен (список из одного персонажа) | core |
| `living_character` | любой | Все живые персонажи | core |
| `neighbor` | province | Соседние провинции | core |
| `neighboring_county` | character | Чужие графства, граничащие с державой | core/council |
| `neighboring_ruler` | character | Независимые правители по соседству | core |
| `parent` | character | Родители | core |
| `powerful_vassal` | character | Влиятельные вассалы | core/politics |
| `prisoner` | character | Пленники персонажа | core/prison |
| `province` | любой | Все провинции | core |
| `realm_province` | character | Провинции державы | core |
| `realm_vassal` | character | Все вассалы державы | core |
| `ruler` | любой | Все правители (глобально) | core |
| `self` | любой | Сам этот объект (удобно для списков кандидатов) | core |
| `sibling` | character | Братья и сёстры | core |
| `snubbed_powerful_vassal` | character | Влиятельные вассалы без места в совете | core/politics |
| `son` | character | Сыновья | core |
| `spouse` | character | Супруги | core |
| `vassal` | character | Прямые вассалы | core |
| `war` | любой | Все войны | core |
| `war_attacker` | war | Участники войны на стороне нападения | core/factions |
| `war_defender` | war | Участники войны на стороне защиты | core/factions |
| `war_enemy` | character | Враги по войнам | core |

## Константы

| Имя | Значение | Источник |
|---|---|---|
| `county` | 1 | core |
| `duchy` | 2 | core |
| `empire` | 4 | core |
| `kingdom` | 3 | core |

## Механики

| Механика | Описание | Включена |
|---|---|---|
| `lifestyles` | Образ жизни: фокусы, опыт и деревья перков | да |
| `council` | Совет: должности, задачи и их эффекты | да |
| `prison` | Темница: заключение, выкуп, казнь, плен на войне | да |
| `factions` | Фракции вассалов: независимость, претендент; ультиматумы и мятежи | да |
| `regiments` | Профессиональные войска: найм, жалованье, контры и местность в бою | да |
| `secrets` | Секреты: раскрытие, шантаж (крюки) и разоблачение | да |
| `laws` | Законы державы: власть короны и другие группы законов | да |
| `knights` | Рыцари: доблестные придворные и вассалы усиливают армию правителя | да |
| `politics` | Политика двора: условия службы вассалов, влиятельные вассалы и совет, страх, прошения | да |

Отключение: `defines.disabled_features: [id, ...]`.

## Реестры движка

- **succession_algorithms**: `primogeniture`, `partition`, `seniority`, `elective`
- **cb_targets**: `claim`, `de_jure`, `independence`, `adjacent_county`, `holy_war`, `faction`, `monster_hunt`
- **interaction_targets**: `grantable_titles`, `revocable_titles`, `recipient_claims`
- **interaction_deciders**: `payer`
- **modifier_providers**: `buildings`, `stress`, `lifestyle`, `council`, `prison`, `realm_laws`, `vassal_obligation`, `plague_fear`
- **province_modifier_providers**: 
- **opinion_providers**: `stored`, `traits`, `general`, `attraction`, `culture`, `faith`, `family`, `liege`, `claim`, `council`, `politics`, `arcana_faith`
- **content_validators**: `lifestyles`, `council`, `factions`, `regiments`, `secrets`, `laws`, `politics`
- **systems**: `upkeep` (0), `economy` (10), `council` (15), `demography` (20), `prison` (22), `lifestyles` (25), `events` (30), `schemes` (40), `secrets` (42), `military` (50), `regiments` (52), `war` (55), `politics` (57), `factions` (58), `construction` (60), `plague` (65), `arcana` (66), `ai` (70), `development` (80), `laws` (85)
- **ui.map_modes**: `arcana`, `plague`
