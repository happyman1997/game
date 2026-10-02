# Справочник скриптового языка

> Файл сгенерирован командой `npm run docs:script` из реестров движка и включённых модов.
> Колонка «Источник» показывает, кто зарегистрировал элемент (core — движок, иначе id мода).

## Триггеры (условия)

| Имя | Скоупы | Описание | Источник |
|---|---|---|---|
| `can_marry` | character | Может вступить в брак с персонажем | core |
| `capital_has_disease` | character | В столице персонажа (или его сюзерена) эпидемия. | plague |
| `culture` | character, province | Культура равна | core |
| `dynasty` | character | Династия равна | core |
| `faith` | character, province | Вера равна | core |
| `global_var` | любой | Сравнение глобальной переменной | core |
| `has_any_claim` | character | Есть претензии | core |
| `has_building` | province | Есть постройка | core |
| `has_claim_on` | character | Есть претензия на титул | core |
| `has_flag` | character | Есть флаг | core |
| `has_global_flag` | любой | Есть глобальный флаг | core |
| `has_holding` | province | Есть владение типа | core |
| `has_hook_on` | character | Есть крюк на персонажа | core |
| `has_modifier` | character | Есть модификатор | core |
| `has_opinion_modifier` | character | Есть модификатор мнения: { target, modifier } | core |
| `has_province_flag` | province | Есть флаг провинции | core |
| `has_province_modifier` | province | Есть модификатор провинции | core |
| `has_scheme` | character | Ведёт интригу: has_scheme: murder или { type, target } | core |
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
| `is_courtier_of` | character | Придворный персонажа | core |
| `is_courtier` | character | Придворный | core |
| `is_female` | character | Женщина | core |
| `is_heir_of` | character | Основной наследник персонажа | core |
| `is_held` | title | У титула есть владелец | core |
| `is_in_realm_of` | character | Состоит в державе персонажа | core |
| `is_independent` | character | Независимый правитель | core |
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
| `add_gold` | character | Изменить gold | core |
| `add_health` | character | Изменить базовое здоровье | core |
| `add_hook` | character | Крюк на персонажа: path или { target, strong, years } | core |
| `add_modifier` | character | Добавить модификатор: id или { id, years/months/days } | core |
| `add_opinion` | character | Мнение этого персонажа о target: { target, modifier, value? } | core |
| `add_piety` | character | Изменить piety | core |
| `add_prestige` | character | Изменить prestige | core |
| `add_province_modifier` | province | Модификатор провинции | core |
| `add_skill` | character | Навсегда изменить навык: { skill, value } | core |
| `add_stress` | character | Изменить стресс | core |
| `add_trait` | character | Добавить черту | core |
| `annex_war_targets` | character | Присоединить цели войны (в контексте войны) | core |
| `become_independent` | character | Стать независимым | core |
| `become_vassal_of` | character | Стать вассалом | core |
| `break_alliance` | character | Разорвать союз | core |
| `change_culture` | character, province | Сменить культуру | core |
| `change_faith` | character, province | Сменить веру | core |
| `change_var` | любой | Изменить переменную: { name, add } | core |
| `create_character` | character | Создать персонажа: { culture, faith, female, age, traits, dynasty: new\|none\|path, court, save_scope_as } | core |
| `death` | character | Смерть: yes, причина или { reason, killer } | core |
| `divorce` | character | Развод | core |
| `end_war` | любой | Завершить войну: victory/white_peace/defeat | core |
| `gain_title` | character | Получить титул | core |
| `give_title` | character | Пожаловать титул: { title, to } — получатель становится вассалом | core |
| `lose_all_titles` | character | Потерять все титулы | core |
| `lose_title` | character | Потерять титул (переходит к сюзерену) | core |
| `make_pregnant` | character | Беременность: { father } | core |
| `marry` | character | Заключить брак | core |
| `move_to_court` | character | Переехать ко двору персонажа | core |
| `pay_gold` | character | Передать золото: { target, value } | core |
| `remove_building` | province | Убрать постройку | core |
| `remove_claim` | character | Убрать претензию | core |
| `remove_flag` | character | Убрать флаг | core |
| `remove_global_flag` | любой | Убрать глобальный флаг | core |
| `remove_hook` | character | Убрать крюк | core |
| `remove_modifier` | character | Убрать модификатор | core |
| `remove_opinion` | character | Убрать модификатор мнения: { target, modifier } | core |
| `remove_province_modifier` | province | Убрать модификатор провинции | core |
| `remove_trait` | character | Убрать черту | core |
| `remove_var` | любой | Удалить переменную | core |
| `reverse_add_opinion` | character | Мнение target об этом персонаже: { target, modifier, value? } | core |
| `send_message` | character | Сообщение игроку (если этот персонаж — игрок) | core |
| `set_flag` | character | Установить флаг: name или { name, days/months/years } | core |
| `set_global_flag` | любой | Глобальный флаг | core |
| `set_global_var` | любой | Глобальная переменная | core |
| `set_nickname` | character | Прозвище (ключ локализации или текст) | core |
| `set_province_flag` | province | Флаг провинции | core |
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
| `current_year` | любой | Текущий год | core |
| `days_since_start` | любой | Дней с начала партии | core |
| `development` | province | Развитие провинции | core |
| `diplomacy` | character | Навык: diplomacy | core |
| `domain_limit` | character | Лимит домена | core |
| `dynasty_prestige` | character | Престиж династии | core |
| `fertility` | character | Плодовитость | core |
| `fort_level` | province | Уровень укреплений | core |
| `general_opinion` | character | Характеристика: general_opinion | core |
| `gold` | character | Золото | core |
| `health` | character | Здоровье | core |
| `income` | character | Ежемесячный доход | core |
| `infected_provinces` | любой | Число заражённых провинций в мире. | plague |
| `intrigue` | character | Навык: intrigue | core |
| `learning` | character | Навык: learning | core |
| `levies` | character | Ополчение державы | core |
| `levy_flat` | character | Характеристика: levy_flat | core |
| `levy_ratio` | character | Доля восстановленных ополчений | core |
| `levy` | province | Ополчение провинции | core |
| `martial` | character | Навык: martial | core |
| `monthly_piety` | character | Характеристика: monthly_piety | core |
| `monthly_prestige` | character | Характеристика: monthly_prestige | core |
| `num_buildings` | province | Число построек | core |
| `num_children` | character | Число живых детей | core |
| `num_claims` | character | Число претензий | core |
| `num_counties` | character | Графств в домене | core |
| `num_courtiers` | character | Число придворных | core |
| `num_de_jure_counties` | title | Де-юре графств в титуле | core |
| `num_holdings` | province | Число владений | core |
| `num_spouses` | character | Число супругов | core |
| `num_traits` | character | Число черт | core |
| `num_vassals` | character | Число прямых вассалов | core |
| `num_wars` | character | Число войн | core |
| `opinion` | character | Мнение о персонаже: opinion(scope:x) | core |
| `piety` | character | Благочестие | core |
| `prestige` | character | Престиж | core |
| `prowess` | character | Навык: prowess | core |
| `realm_size` | character | Графств в державе | core |
| `reverse_opinion` | character | Мнение персонажа-аргумента об этом персонаже | core |
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
| `controller` | province | Кто контролирует провинцию | core |
| `county` | province | Графство провинции | core |
| `de_jure_liege` | title | Де-юре сюзеренный титул | core |
| `defender` | war | Защитник | core |
| `dynasty` | character | Династия | core |
| `employer` | character | Синоним liege | core |
| `father` | character | Отец | core |
| `founder` | dynasty | Основатель династии | core |
| `holder` | title, province | Владелец титула/графства | core |
| `killer` | character | Убийца | core |
| `liege` | character | Сюзерен (или владелец двора для придворных) | core |
| `mother` | character | Мать | core |
| `owner` | scheme, army | Владелец интриги/армии | core |
| `player` | любой | Персонаж игрока | core |
| `primary_heir` | character | Основной наследник | core |
| `primary_title` | character | Основной титул | core |
| `province` | title | Провинция графства | core |
| `spouse` | character | Супруг(а) (первый) | core |
| `target` | scheme | Цель интриги | core |
| `top_liege` | character | Верховный сюзерен | core |

## Списки (any_ / every_ / random_ / ordered_)

| Имя | Из скоупа | Описание | Источник |
|---|---|---|---|
| `ally` | character | Союзники | core |
| `child` | character | Живые дети | core |
| `claim` | character | Претензии | core |
| `close_family` | character | Близкая семья (супруги, дети, родители, братья/сёстры) | core |
| `courtier` | character | Придворные | core |
| `daughter` | character | Дочери | core |
| `de_jure_county` | title | Де-юре графства | core |
| `de_jure_vassal_title` | title | Де-юре вассальные титулы | core |
| `domain_province` | character | Провинции домена | core |
| `dynasty_member` | character | Живые члены династии | core |
| `grandchild` | character | Внуки | core |
| `held_title` | character | Титулы | core |
| `independent_ruler` | любой | Независимые правители | core |
| `living_character` | любой | Все живые персонажи | core |
| `neighbor` | province | Соседние провинции | core |
| `neighboring_ruler` | character | Независимые правители по соседству | core |
| `parent` | character | Родители | core |
| `province` | любой | Все провинции | core |
| `realm_province` | character | Провинции державы | core |
| `realm_vassal` | character | Все вассалы державы | core |
| `ruler` | любой | Все правители (глобально) | core |
| `self` | любой | Сам этот объект (удобно для списков кандидатов) | core |
| `sibling` | character | Братья и сёстры | core |
| `son` | character | Сыновья | core |
| `spouse` | character | Супруги | core |
| `vassal` | character | Прямые вассалы | core |
| `war_enemy` | character | Враги по войнам | core |
| `war` | любой | Все войны | core |

## Константы

| Имя | Значение |  | Источник |
|---|---|---|---|
| `county` | 1 |  | core |
| `duchy` | 2 |  | core |
| `empire` | 4 |  | core |
| `kingdom` | 3 |  | core |

## Реестры движка

- **successionAlgorithms**: `primogeniture`, `partition`, `seniority`, `elective`
- **cbTargets**: `claim`, `de_jure`, `independence`, `adjacent_county`, `holy_war`
- **interactionTargets**: `grantable_titles`, `revocable_titles`, `recipient_claims`
- **modifierProviders**: `buildings`, `stress`, `plague_fear`
- **provinceModifierProviders**: 
- **opinionProviders**: `stored`, `traits`, `general`, `attraction`, `culture`, `faith`, `family`, `liege`, `claim`
- **systems**: `upkeep` (0), `economy` (10), `demography` (20), `events` (30), `schemes` (40), `military` (50), `war` (55), `construction` (60), `plague` (65), `ai` (70), `development` (80)
- **ui.mapModes**: `plague`
