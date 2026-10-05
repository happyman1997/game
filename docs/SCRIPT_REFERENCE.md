# Справочник скриптового языка

> Файл сгенерирован командой `npm run docs:script` из реестров движка и включённых модов.
> Колонка «Источник» показывает, кто зарегистрировал элемент (core — движок, иначе id мода).

## Триггеры (условия)

| Имя | Скоупы | Описание | Источник |
|---|---|---|---|
| `can_marry` | character | Может вступить в брак с персонажем | core |
| `can_use_hook_on` | character | Крюк на персонажа можно использовать сейчас | core |
| `capital_has_disease` | character | В столице персонажа (или его сюзерена) эпидемия. | plague |
| `culture` | character, province | Культура равна | core |
| `dynasty` | character | Династия равна | core |
| `faction_type` | faction | Тип фракции | core/factions |
| `faith` | character, province | Вера равна | core |
| `global_var` | любой | Сравнение глобальной переменной | core |
| `has_any_claim` | character | Есть претензии | core |
| `has_building` | province | Есть постройка | core |
| `has_claim_on` | character | Есть претензия на титул | core |
| `has_council_task` | character | Сюзерен: на какой-то должности выбрана задача | core/council |
| `has_flag` | character | Есть флаг | core |
| `has_focus` | character | Выбран фокус образа жизни | core/lifestyles |
| `has_global_flag` | любой | Есть глобальный флаг | core |
| `has_holding` | province | Есть владение типа | core |
| `has_hook_on` | character | Есть крюк на персонажа | core |
| `has_imprisonment_reason` | character | Есть законный повод заключить персонажа (преступление против этого персонажа) | core/prison |
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
| `has_strong_hook_on` | character | Есть сильный крюк на персонажа | core |
| `has_succession_law` | character | Закон наследования | core |
| `has_trait_category` | character | Есть черта категории | core |
| `has_trait` | character | Есть черта | core |
| `has_truce_with` | character | Перемирие с персонажем | core |
| `has_var` | character | Есть переменная | core |
| `holds_title` | character | Владеет титулом | core |
| `is_adult` | character | Совершеннолетний | core |
| `is_ai` | character | Персонаж ИИ | core |
| `is_alive` | character | Жив | core |
| `is_allied_with` | character | Союзник персонажа | core |
| `is_at_war_with` | character | Воюет с персонажем | core |
| `is_at_war` | character | Ведёт войну | core |
| `is_child_of` | character | Ребёнок персонажа | core |
| `is_child` | character | Ребёнок | core |
| `is_close_family_of` | character | Близкая семья | core |
| `is_close_relative_of` | character | Слишком близкое родство для брака | core |
| `is_coastal` | province | Прибрежная | core |
| `is_councillor` | character | Заседает в совете (yes) или на должности: is_councillor: marshal | core/council |
| `is_courtier_of` | character | Придворный персонажа | core |
| `is_courtier` | character | Придворный | core |
| `is_faction_leader` | character | Возглавляет фракцию | core/factions |
| `is_female` | character | Женщина | core |
| `is_heir_of` | character | Основной наследник персонажа | core |
| `is_held` | title | У титула есть владелец | core |
| `is_imprisoned_by` | character | В темнице у персонажа | core/prison |
| `is_imprisoned` | character | В темнице | core/prison |
| `is_in_faction` | character | Состоит во фракции (yes/no или тип) | core/factions |
| `is_in_realm_of` | character | Состоит в державе персонажа | core |
| `is_independent` | character | Независимый правитель | core |
| `is_knight` | character | Служит рыцарем у своего сюзерена | core/knights |
| `is_landed` | character | Владеет землями | core |
| `is_liege_of` | character | Сюзерен персонажа | core |
| `is_lowborn` | character | Безродный | core |
| `is_male` | character | Мужчина | core |
| `is_married` | character | В браке | core |
| `is_occupied` | province | Оккупирована | core |
| `is_parent_of` | character | Родитель персонажа | core |
| `is_player` | character | Персонаж игрока | core |
| `is_pregnant` | character | Беременна | core |
| `is_primary_heir` | character | Основной наследник своего сюзерена/отца | core |
| `is_ruler` | character | Владеет землями | core |
| `is_same_as` | любой | Тот же объект, что и путь | core |
| `is_scheme_target` | character | Является целью интриги | core |
| `is_sibling_of` | character | Брат/сестра персонажа | core |
| `is_spouse_of` | character | Супруг(а) персонажа | core |
| `is_vassal_of` | character | Прямой вассал персонажа | core |
| `is_vassal` | character | Вассал | core |
| `knows_secret_of` | character | Знает какой-то секрет персонажа | core/secrets |
| `province_has_disease` | province | В провинции эпидемия. Аргумент: yes или id болезни. | plague |
| `random_chance` | любой | Случайный шанс в процентах (используйте осторожно в триггерах) | core |
| `religion` | character | Религия равна | core |
| `same_culture_as` | character | Та же культура | core |
| `same_dynasty_as` | character | Та же династия | core |
| `same_faith_as` | character | Та же вера | core |
| `terrain` | province | Местность | core |
| `tier_is` | title | Ранг титула: county/duchy/kingdom/empire | core |
| `var` | любой | Сравнение переменной: var: { name: x, value: ">= 2" } | core |

## Эффекты

| Имя | Скоупы | Описание | Источник |
|---|---|---|---|
| `add_alliance` | character | Союз с персонажем | core |
| `add_building` | province | Добавить постройку | core |
| `add_claim` | character | Претензия на титул | core |
| `add_courtier` | character | Принять ко двору | core |
| `add_development` | province | Изменить развитие | core |
| `add_dynasty_prestige` | character | Престиж династии | core |
| `add_faction_discontent` | faction | Изменить недовольство фракции | core/factions |
| `add_gold` | character | Изменить gold | core |
| `add_health` | character | Изменить базовое здоровье | core |
| `add_hook` | character | Крюк на персонажа: path или { target, strong, years } | core |
| `add_lifestyle_xp` | character | Опыт образа жизни: число (текущий образ жизни) или { lifestyle, value } | core/lifestyles |
| `add_modifier` | character | Добавить модификатор: id или { id, years/months/days } | core |
| `add_opinion` | character | Мнение этого персонажа о target: { target, modifier, value? } | core |
| `add_perk` | character | Открыть перк бесплатно | core/lifestyles |
| `add_piety` | character | Изменить piety | core |
| `add_prestige` | character | Изменить prestige | core |
| `add_province_modifier` | province | Модификатор провинции | core |
| `add_regiment` | character | Получить отряд бесплатно (сверх предела) | core/regiments |
| `add_secret` | character | Персонаж получает секрет: add_secret: тип или { type, target, known_by } | core/secrets |
| `add_skill` | character | Навсегда изменить навык: { skill, value } | core |
| `add_stress` | character | Изменить стресс | core |
| `add_trait` | character | Добавить черту | core |
| `annex_war_targets` | character | Присоединить цели войны (в контексте войны) | core |
| `appoint_councillor` | character | Назначить в совет: { position, who } | core/council |
| `become_independent` | character | Стать независимым | core |
| `become_vassal_of` | character | Стать вассалом | core |
| `blackmail` | character | Шантажировать персонажа его самым тяжёлым известным секретом (получить крюк) | core/secrets |
| `break_alliance` | character | Разорвать союз | core |
| `change_culture` | character, province | Сменить культуру | core |
| `change_faith` | character, province | Сменить веру | core |
| `change_var` | любой | Изменить переменную: { name, add } | core |
| `create_character` | character | Создать персонажа: { culture, faith, female, age, traits, dynasty: new\|none\|path, court, save_scope_as } | core |
| `death` | character | Смерть: yes, причина или { reason, killer } | core |
| `discover_scheme_against` | character | Раскрыть случайную враждебную интригу против персонажа или его семьи | core/council |
| `discover_secret` | character | Узнать случайный секрет кого-то из своей державы | core/secrets |
| `divorce` | character | Развод | core |
| `end_war` | любой | Завершить войну: victory/white_peace/defeat | core |
| `expose_secret` | character | Разоблачить самый тяжёлый известный секрет персонажа | core/secrets |
| `faction_enforce_demands` | faction | Сюзерен выполняет требования фракции | core/factions |
| `faction_start_war` | faction | Фракция поднимает мятеж | core/factions |
| `gain_title` | character | Получить титул | core |
| `give_title` | character | Пожаловать титул: { title, to } — получатель становится вассалом | core |
| `imprison` | character | Заключить персонажа в свою темницу: imprison: scope:x или { target, reason } | core/prison |
| `join_faction` | character | Вступить во фракцию против сюзерена (или создать): join_faction: <тип> | core/factions |
| `leave_faction` | character | Выйти из фракции | core/factions |
| `lose_all_titles` | character | Потерять все титулы | core |
| `lose_title` | character | Потерять титул (переходит к сюзерену) | core |
| `make_pregnant` | character | Беременность: { father } | core |
| `mark_criminal` | character | Даёт target законный повод заключить этого персонажа: { target, years } | core/prison |
| `marry` | character | Заключить брак | core |
| `move_to_court` | character | Переехать ко двору персонажа | core |
| `pay_gold` | character | Передать золото: { target, value } | core |
| `release_from_prison` | character | Освободить этого персонажа из темницы | core/prison |
| `remove_building` | province | Убрать постройку | core |
| `remove_claim` | character | Убрать претензию | core |
| `remove_flag` | character | Убрать флаг | core |
| `remove_global_flag` | любой | Убрать глобальный флаг | core |
| `remove_hook` | character | Убрать крюк | core |
| `remove_modifier` | character | Убрать модификатор | core |
| `remove_opinion` | character | Убрать модификатор мнения: { target, modifier } | core |
| `remove_perk` | character | Убрать перк | core/lifestyles |
| `remove_province_modifier` | province | Убрать модификатор провинции | core |
| `remove_trait` | character | Убрать черту | core |
| `remove_var` | любой | Удалить переменную | core |
| `reverse_add_opinion` | character | Мнение target об этом персонаже: { target, modifier, value? } | core |
| `seize_primary_title` | character | Забрать основной титул персонажа (претендент): прежний владелец становится вассалом | core/factions |
| `send_message` | character | Сообщение игроку (если этот персонаж — игрок) | core |
| `set_flag` | character | Установить флаг: name или { name, days/months/years } | core |
| `set_focus` | character | Сменить фокус образа жизни (без перерыва) | core/lifestyles |
| `set_global_flag` | любой | Глобальный флаг | core |
| `set_global_var` | любой | Глобальная переменная | core |
| `set_nickname` | character | Прозвище (ключ локализации или текст) | core |
| `set_province_flag` | province | Флаг провинции | core |
| `set_realm_law` | character | Установить закон державы (без цены и перерыва) | core/laws |
| `set_succession_law` | character | Закон наследования | core |
| `set_var` | любой | Переменная: { name, value } | core |
| `start_disease` | province | Начать эпидемию в провинции: start_disease: bubonic_plague | plague |
| `start_scheme` | character | Начать интригу: { type, target } | core |
| `take_title` | character | Отобрать титул себе: { title, from? } | core |

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
| `attraction` | character | Привлекательность | core |
| `commander_advantage` | character | Характеристика: commander_advantage | core |
| `council_size` | character | Число занятых мест в совете | core/council |
| `crown_authority_level` | character | Уровень закона группы crown_authority (−1, если не действует) | core/laws |
| `current_year` | любой | Текущий год | core |
| `days_since_start` | любой | Дней с начала партии | core |
| `development` | province | Развитие провинции | core |
| `diplomacy` | character | Навык: diplomacy | core |
| `domain_limit` | character | Лимит домена | core |
| `dynasty_prestige` | character | Престиж династии | core |
| `faction_discontent` | faction | Недовольство фракции (0–100) | core/factions |
| `faction_power` | faction | Сила фракции в % от силы сюзерена | core/factions |
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
| `levy_flat` | character | Характеристика: levy_flat | core |
| `levy_ratio` | character | Доля восстановленных ополчений | core |
| `levy` | province | Ополчение провинции | core |
| `lifestyle_xp` | character | Опыт текущего образа жизни | core/lifestyles |
| `martial` | character | Навык: martial | core |
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
| `stat` | character | Устарело: используйте имя характеристики | core |
| `stewardship` | character | Навык: stewardship | core |
| `stress_level` | character | Уровень стресса (стресс / 100) | core |
| `stress` | character | Стресс | core |
| `tax` | province | Налог провинции | core |
| `tier` | character | Ранг основного титула (0 — нет земель, 1 — граф ... 4 — император) | core |
| `title_tier` | title | Ранг титула | core |
| `vassal_opinion` | character | Характеристика: vassal_opinion | core |
| `war_duration_days` | war | Длительность войны | core |

## Ссылки на скоупы

| Имя | Из скоупа | Описание | Источник |
|---|---|---|---|
| `attacker` | war | Нападающий | core |
| `capital_province` | title | Столица титула | core |
| `capital` | character | Столица (провинция) | core |
| `chancellor` | character | Советник на должности chancellor | core/council |
| `controller` | province | Кто контролирует провинцию | core |
| `county` | province | Графство провинции | core |
| `court_chaplain` | character | Советник на должности court_chaplain | core/council |
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

| Имя | Из скоупа | Описание | Источник |
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
| `prisoner` | character | Пленники персонажа | core/prison |
| `province` | любой | Все провинции | core |
| `realm_province` | character | Провинции державы | core |
| `realm_vassal` | character | Все вассалы державы | core |
| `ruler` | любой | Все правители (глобально) | core |
| `self` | любой | Сам этот объект (удобно для списков кандидатов) | core |
| `sibling` | character | Братья и сёстры | core |
| `son` | character | Сыновья | core |
| `spouse` | character | Супруги | core |
| `vassal` | character | Прямые вассалы | core |
| `war_attacker` | war | Участники войны на стороне нападения | core/factions |
| `war_defender` | war | Участники войны на стороне защиты | core/factions |
| `war_enemy` | character | Враги по войнам | core |
| `war` | любой | Все войны | core |

## Константы

| Имя | Значение |  | Источник |
|---|---|---|---|
| `county` | 1 |  | core |
| `duchy` | 2 |  | core |
| `empire` | 4 |  | core |
| `kingdom` | 3 |  | core |

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

Отключение: `defines.disabled_features: [id, ...]`. Источник `core/<механика>` в таблицах выше — элементы, которые регистрирует механика.

## Реестры движка

- **successionAlgorithms**: `primogeniture`, `partition`, `seniority`, `elective`
- **cbTargets**: `claim`, `de_jure`, `independence`, `adjacent_county`, `holy_war`, `faction`
- **interactionTargets**: `grantable_titles`, `revocable_titles`, `recipient_claims`
- **interactionDeciders**: `payer`
- **modifierProviders**: `buildings`, `stress`, `lifestyle`, `council`, `prison`, `realm_laws`, `plague_fear`
- **provinceModifierProviders**: 
- **opinionProviders**: `stored`, `traits`, `general`, `attraction`, `culture`, `faith`, `family`, `liege`, `claim`, `council`
- **contentValidators**: `lifestyles`, `council`, `factions`, `regiments`, `secrets`, `laws`
- **systems**: `upkeep` (0), `economy` (10), `council` (15), `demography` (20), `prison` (22), `lifestyles` (25), `events` (30), `schemes` (40), `secrets` (42), `military` (50), `regiments` (52), `war` (55), `factions` (58), `construction` (60), `plague` (65), `ai` (70), `development` (80), `laws` (85)
- **ui.mapModes**: `plague`
