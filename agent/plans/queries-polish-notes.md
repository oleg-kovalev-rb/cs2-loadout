# Queries / Serializers Polish — рабочий инвентарь

> Это **не дев-план**. Черновик для формулировки задачи и код-ресерча.
> Ничего отсюда не реализуем до `create-dev-plan` + `styleguides-check`.
>
> Историческая заметка: финальный API после реализации использует
> `InventoryValueQuery.call` и `RarityBreakdownQuery.call`; см.
> `agent/plans/queries-serializers-polish.md`.

## Scope

- `app_fetcher/app/queries/**`
- `app_fetcher/app/serializers/**`
- call sites: `Api::Public::ItemsController`, `Api::Public::InventoriesController`,
  `Api::V1::ItemPricesController`, `Api::V1::InventoryValuesController`,
  `Api::Admin::ItemsController`
- specs: `spec/queries/**`, `spec/serializers/**`, request specs

## Locked decisions (2026-10-20)

Имена:

- `InventoryValuation` → `InventoryValueQuery`
- `Snapshot` → `ValueSnapshot`
- `Change` → `ValueDelta`
- `Series` → `ValueHistory`
- `Point` → `ValueHistory::Point`
- `Page` (concern) → `InventoryValue`
- `InventoryCatalogQuery` → `InventoryListQuery`
- `InventoryCatalogQuery::Page`/`Listing` → `InventorySummaries`
- `InventoryDetailQuery::Page`/`Detail` → `InventoryDetails`
- top-items-блок detail → `InventoryItems` (отдельная структура)
- `ItemCatalogQuery::Page` → `ItemCatalog`
- `ItemCatalogQuery::PriceStats` → `PriceChangeStats`
- `ItemPriceHistoryQuery::Page` → `ItemPriceHistory`
- `ItemPriceHistoryQuery::Point` → `PricePoint`
- `InventoryCatalogSerializer` → `InventoryListSerializer`
- `InventoryCatalogCache` → `InventoryListCache` (+ bump cache key version)
- `InventoryValuationSerializer` → `InventoryValueSerializer`

Scope:

- тянем `ItemCatalogQuery` и `ItemPriceHistoryQuery` + shared serializers;
- `InventoryItems` остаётся отдельной структурой;
- `PriceHistoryCache`/`ItemTrendCache` **не** приводим к общему `PricePoint`:
  кэш остаётся hash-форматом; `ItemPriceHistorySerializer` покрывает только
  query-ветку.

Cross-cutting (согласовано):

- в query — `Time`/`Date`, в serializer — `.iso8601`;
- `complete` — только из `ValueSnapshot#complete?`;
- shared helper для `change_24h_percent`;
- shared `metadata`/`rarity_breakdown` serializers;
- shared rarity counting для catalog/detail.

Поведение:

- `ItemCatalogQuery#last_synced_at` пока оставляем глобальным
  (`Item.marketable.maximum(:updated_at)`), не scoped by filters; если
  понадобится filtered freshness — отдельное решение.
- `InventoryValueHistoryQuery` остаётся тонким адаптером; неизвестный
  `steam_id` → `snapshot: nil` + пустая `history` (контракт V1).

## Инвентарь

| Файл | Строк | Роль | Замечания |
|---|---:|---|---|
| `inventory_valuation.rb` | 213 | concern query: снапшот, серия, baseline | самый большой; SQL-константы + история + сборка отчёта |
| `inventory_catalog_query.rb` | 136 | список инвентарей | `AGGREGATE_COLUMNS`, позиционная склейка строк, `InventorySummary` |
| `inventory_detail_query.rb` | 123 | деталь инвентаря | `Page` на 21 поле, дублирует `Snapshot`/`Series`/`Point` |
| `item_catalog_query.rb` | 51 | каталог предметов | в целом компактный |
| `item_price_history_query.rb` | 45 | история цены предмета | `Page` без пагинации; inline-map в контроллере |
| `inventory_value_history_query.rb` | 23 | обёртка над `InventoryValuation.page` | имя расходится с concern |
| `appliers/*` | 92 | пагинация/сортировка/фильтры | механически чистые |
| `options/*` | 140 | enum-опции параметров | механически чистые |
| `serializers/*` | 360 | shaping ответов | много повторяющейся математики/маппинга |

Итого top-level `queries/*` + `serializers/*` ≈ 950 строк; вместе с
`appliers/` и `options/` ≈ 1180. Основной долг — inventory-тройка
(`InventoryCatalogQuery`, `InventoryDetailQuery`, `InventoryValuation`) и
сериализаторы, а не `ItemCatalogQuery`/`ItemPriceHistoryQuery`.

## Пункты пользователя: оценка и варианты

### 1. «Огромные Sorbet-структуры; логику с ними перенести в сериализаторы»

**Оценка: направление согласовано частично, буквальный перенос — нет.**

Факты:

- `T::Struct` здесь — типизированный контракт между query и serializer.
  Если перенести структуры в сериализаторы, query либо начнёт возвращать
  `Hash`/`Array` (потеря Sorbet, отход от ADR), либо сериализатор будет
  объявлять входную структуру, а query — зависеть от неё. Строк не убавится,
  направление зависимостей станет хуже.
- Реальная проблема не в самих структурах, а в **дублировании**:
  - `InventoryDetailQuery::HistoryPoint` 1:1 повторяет
    `InventoryValuation::Point`;
  - `InventoryDetailQuery::Page` повторяет поля `Snapshot` (6 полей) и
    `Series` (5 полей) + отдельный `history`;
  - `InventoryCatalogQuery::InventorySummary` повторяет `Snapshot` + change-поля;
  - `complete` считается и в query, и в `InventoryCatalogSerializer`;
  - `change_24h_percent` считается в 4 сериализаторах;
  - `metadata_json` и `rarity_breakdown_json` продублированы в двух
    public-сериализаторах.

Варианты:

- **A (рекомендуемый).** Оставить у query минимальные read-model структуры,
  но собрать их композицией: `Snapshot`, `Series`, новый `Change`; форматирование
  (`iso8601`, проценты, `complete`, breakdown) — только в сериализаторах.
- **B.** Сериализатор объявляет входной DTO, query возвращает его. Не
  рекомендуется: те же строки, но query зависит от serializer.
- **C.** Query возвращает `Hash`/`Array`. Отклонить: теряется Sorbet и
  контракт, ради которого слой и вводился.

Что именно переносить в сериализаторы:

- `.iso8601` для `last_synced_at`, `change_basis_at`, `Point#at`,
  `oldest_price_at`;
- `change_24h_percent`;
- `complete`/`complete?` — как булево из `Snapshot#complete?`, без повторного
  сравнения counts в сериализаторе;
- `rarity_breakdown` (tier/count/percent);
- `metadata` и item-entry маппинг;
- общий расчёт процента изменения.

Что **не** переносить в сериализаторы (это доменная логика, не presentation):

- выбор baseline и `BASELINE_MAX_AGE_DAYS`;
- `change_available`/`change_partial`;
- агрегаты `total_value_cents`, counts, completeness;
- rarity counting.

Ожидаемый эффект: не «в разы», но порядка 70–100 строк и, главное, меньше
расхождений между query и serializer.

### 2. `AGGREGATE_COLUMNS` и связка с `InventoryValuation`

**Оценка: проблема реальная; с `Options::*` — не согласен.**

Что не так:

- `InventoryValuation::AGGREGATE_COLUMNS` — публичная деталь SQL-проекции.
  `InventoryCatalogQuery` конкатенирует её со своими колонками и затем
  разбирает строку позиционно:
  `_id, steam_id, updated_at, *aggregate_values`.
  Добавление/перестановка колонки в `InventoryValuation` молча ломает
  сопоставление.
- `InventoryValuation::AGGREGATE_EXPRESSIONS` — не используется нигде (dead
  constant); при этом дублирует те же пять выражений, что и
  `AGGREGATE_COLUMNS`.
- `AGGREGATE_COLUMNS` смешивает «что считаем» (concern) и «как выбираем для
  конкретного endpoint» (catalog).

Варианты:

- **A (рекомендуемый).** Оставить владение в `InventoryValuation`, но
  спрятать SQL за поведением:
  `InventoryValuation.snapshots_for(user_inventory_ids)` →
  `Hash[Integer, Snapshot]`, либо
  `InventoryValuation.with_aggregates(scope)` → scope с named-колонками.
  `AGGREGATE_COLUMNS`/expressions сделать приватными.
- **B.** Вынести concern-scoped projection:
  `InventoryValuation::Aggregate.apply(scope)` + `snapshot_from_row`.
  Это ближе к «applier», но не `Appliers::*`: `Appliers::*` по styleguide
  обязан быть resource-agnostic, а здесь SQL про `items`.
- **C.** `Options::InventoryAggregateColumn` / `Appliers::AggregateApplier`.
  Отклонить: `Options::*` — это closed-enum **query params**, а не выбор
  SQL-колонок; пользователь их не передаёт.

Дополнительно:

- заменить позиционный `snapshot_from_row` на named mapping
  (`Snapshot.from_hash`/keyword args), чтобы не держать хрупкий порядок;
- удалить `AGGREGATE_EXPRESSIONS`;
- учесть, что `Options::InventorySortOption` сейчас сортирует по алиасам
  `total_value_cents`/`items_count`. Если убрать select-алиасы из catalog,
  сортировке понадобится либо concern-level API для выражений, либо
  `with_aggregates(scope)`. Это ключевое ограничение при выборе A/B.

### 3. Название `Page`

**Оценка: согласен, `Page` — плохое имя для большинства этих структур.**

- `InventoryCatalogQuery::Page` и `ItemCatalogQuery::Page` ещё можно
  оправдать (там реально страница), но `InventoryDetailQuery::Page`,
  `ItemPriceHistoryQuery::Page`, `InventoryValuation::Page` — нет:
  это detail/history/report, а не страница.
- `Page` также не говорит, **что** передаётся сериализатору.

Варианты:

- **A (рекомендуемый).** Доменные имена:
  `InventoryListQuery::Listing` (или `Catalog`), `InventoryDetailQuery::Detail`,
  `ItemCatalogQuery::Catalog`, `ItemPriceHistoryQuery::History`,
  `InventoryValuation::Report`.
- **B.** Единый `Result` везде:
  `...Query::Result`, `InventoryValuation::Result`. Плюс — единообразие;
  минус — расплывчато и легко спутать с `Result`-обёрткой, которую ADR
  сознательно отклонил.
- **C.** `Page` только для пагинированных list-структур, остальные —
  `Detail`/`History`/`Report`. Минимальные изменения, но неоднородно.
- **D.** `Data`/`Payload` — слишком абстрактно/HTTP-но, отклонить.

Рекомендация: A. Заодно переименовать локальные переменные `page` в
`listing`/`detail`/`history`/`report`, иначе имя структуры и переменной
разъедутся.

### 4. Название `InventoryCatalogQuery`

**Оценка: согласен, «inventory catalog» неоднозначно.**

- Читается и как «каталог инвентарей», и как «инвентарь/каталог предметов».
- Модель называется `UserInventory`, публичный ресурс — `inventory`,
  endpoint — `/api/public/inventories` (list) и `/inventories/:steam_id`
  (detail). Пара `InventoryCatalogQuery` + `InventoryDetailQuery` звучит
  несимметрично.
- `InventoryCatalogCache`/`InventoryCatalogSerializer` наследуют ту же
  неоднозначность.

Варианты:

- **A (рекомендуемый).** `InventoryListQuery` + `InventoryDetailQuery`.
  Явно говорит «список инвентарей», хорошо сочетается с detail. Требует
  осознанно обновить styleguide/ADR: `<Resource>CatalogQuery` → допустить
  `<Resource>ListQuery` для обычного index-списка.
- **B.** `UserInventoryCatalogQuery` — точно по модели, минимальные изменения
  конвенции, но длиннее и-vs публичное имя ресурса.
- **C.** `InventoryOverviewQuery`/`InventorySummariesQuery` — точнее описывает
  агрегированный обзор, но не вписывается в `<Resource>CatalogQuery`.
- **D.** `InventoriesCatalogQuery` — грамматически неудобно, отклонить.

Рекомендация: A. Если не хочется трогать конвенцию сейчас — B как
low-churn вариант. При переименовании query, вероятно, стоит переименовать
serializer/cache и поднять `InventoryCatalogCache::CACHE_KEY_VERSION`.

## Дополнительные находки

- `InventoryDetailQuery::HistoryPoint` — точная копия
  `InventoryValuation::Point`; удалить, `history` = `series.points`.
- `InventoryDetailQuery::Page` дублирует `Snapshot` + `Series`; собрать
  композицией, а не 15 полей вручную.
- `InventoryCatalogQuery::InventorySummary` дублирует `Snapshot`; хранить
  `valuation: Snapshot` + `change` + `last_synced_at` + `rarity_counts`.
- В query-структурах смешаны `Time` и `String`: `oldest_price_at` —
  `Time`, `last_synced_at`/`change_basis_at`/`Point#at` — уже
  отформатированные строки. Оставить `Time`/`Date` в query, `.iso8601` —
  в сериализаторах.
- `InventoryCatalogSerializer` сам считает `complete: priced >= pricable`,
  хотя `Snapshot#complete?` уже есть; в detail используется готовый
  `page.complete`. Свести к одному источнику.
- `change_24h_percent` дублируется в `InventoryCatalogSerializer`,
  `ItemCatalogSerializer`, `InventoryDetailSerializer`,
  `ItemPriceDynamicsSerializer`; вынести общий helper.
- `metadata_json` дублируется в `ItemCatalogSerializer` и
  `InventoryDetailSerializer`; `rarity_breakdown_json` — в
  `InventoryCatalogSerializer` и `InventoryDetailSerializer`.
- `rarity_counts_for` дублируется в catalog/detail и создаёт fake
  `Item.new` на каждую строку; вынести общий concern/scope, сохранив
  семантику `RarityTier.for_item` (`★`, Extraordinary/Contraband → Gold).
- `ItemPricesController#history` мапит `Point` в hash inline — просится
  `ItemPriceHistorySerializer` (сейчас сериализатор-слой обойдён).
- `InventoryValueHistoryQuery` называется «value», а concern —
  `InventoryValuation`; рассмотреть `InventoryValuationHistoryQuery` или
  `InventoryValuation.report`.
- `InventoryValuation.page` для неизвестного `steam_id` возвращает
  `current: nil` + пустую серию, а `InventoryDetailQuery` кидает
  `RecordNotFound`. Это два разных контракта; зафиксировать как решение
  (не обязательно баг) и покрыть тестом.
- `InventoryValuation` (213 строк) владеет и SQL-агрегатами, и серией, и
  сборкой отчёта; при желании можно разделить на snapshot/aggregate и
  series/report, но это отдельное решение, не обязательное для полишинга.
- `InventoryCatalogQuery` использует магические индексы `row[0]`, `row[1]`;
  заменить на named-доступ при рефакторинге `AGGREGATE_COLUMNS`.

## Кандидатный список изменений

> Порядок — черновой, не план реализации.

- [ ] Зафиксировать naming: query (`InventoryListQuery` vs
      `UserInventoryCatalogQuery`), result-структуры, `change`.
- [ ] Переименовать `Page` → доменные `Listing`/`Catalog`/`Detail`/`History`/
      `Report`; обновить локальные переменные и спеки.
- [ ] Удалить `HistoryPoint`, использовать `InventoryValuation::Point`.
- [ ] Собрать detail-результат из `Snapshot` + `Series` + `Change`; убрать
      копирование полей.
- [ ] Собрать catalog summary из `Snapshot` + `Change` + sync/rarity.
- [ ] Ввести `InventoryValuation::Change` (cents/basis/partial/available)
      и использовать его в catalog и series.
- [ ] Оставить в query `Time`/`Date`, перенести `.iso8601` в сериализаторы.
- [ ] Убрать повторный расчёт `complete` в сериализаторе.
- [ ] Спрятать `AGGREGATE_COLUMNS`/`AGGREGATE_EXPRESSIONS`; удалить dead
      constant; дать `InventoryValuation` bulk/aggregate API.
- [ ] Заменить позиционный `snapshot_from_row` на named mapping.
- [ ] Перенести baseline/change-логику из `InventoryCatalogQuery` в
      `InventoryValuation`.
- [ ] Вынести общие serializer-хелперы: change %, metadata, rarity breakdown.
- [ ] Вынести общий rarity counting для catalog/detail.
- [ ] Добавить `ItemPriceHistorySerializer` вместо inline-map в контроллере.
- [ ] Решить судьбу `InventoryValueHistoryQuery` (rename/fold).
- [ ] Обновить styleguide/ADR под новые имена и границы слоёв.

## Naming: второй проход

| Сейчас | Варианты | Рекомендация |
|---|---|---|
| `InventoryValuation` | `InventoryValueQuery`, `InventoryValue`, `InventoryValueCalculator`, `InventoryWorthQuery` | `InventoryValueQuery` — домен + слой; `Calculator` звучит как чистая математика, `InventoryValue` — как модель |
| `InventoryValuation::Snapshot` | `ValueSnapshot`, `CurrentValue`, `CurrentState` | `ValueSnapshot` — явно говорит, что это снимок стоимости |
| `InventoryValuation::Change` | `ValueDelta`, `ValueChange`, `Delta`, `ChangeSummary` | `ValueDelta` — явно числовое изменение; `Change` слишком общий |
| `InventoryValuation::Series` | `ValueHistory`, `History`, `Timeline` | `ValueHistory` — явно история значений |
| `InventoryValuation::Page` | `InventoryValue`, `InventoryValueReport`, `Report` | `InventoryValue` — «значение инвентаря»: snapshot + history; `Report` — альтернатива, если хочется подчеркнуть композит |
| `InventoryCatalogQuery::Page`/`Listing` | `InventorySummaries`, `InventoryCatalog`, `Inventories`, `Result` | `InventorySummaries` — внутри именно summary-строки инвентарей + пагинация |
| `InventoryDetailQuery::Page`/`Detail` | `InventoryDetails`, `InventoryProfile`, `Detail`, `Result` | `InventoryDetails` — внутри детали одного инвентаря |
| top-items-блок detail | `InventoryItems`, `TopItems`, `InventoryItemList` | `InventoryItems` — предметы инвентаря; `TopItems` — если хочется подчеркнуть top-N |

Рекомендуемый набор:

```text
InventoryValueQuery
  ::ValueSnapshot          # текущее состояние стоимости
  ::ValueDelta             # изменение: cents/percent/basis_at/partial/available
  ::ValueHistory           # points + delta
  ::InventoryValue         # snapshot + history (результат concern-запроса)

InventoryListQuery::InventorySummaries
InventoryDetailQuery::InventoryDetails
  ::InventoryItems         # top_items + pagination + trends (опционально)
ItemCatalogQuery::ItemCatalog
ItemPriceHistoryQuery::ItemPriceHistory
```

Поля в result-структурах:

```ruby
InventorySummary#snapshot              # было valuation
InventorySummary#delta                 # было change
InventoryListQuery::InventorySummaries#inventories
InventoryDetailQuery::InventoryDetails#value    # InventoryValueQuery::InventoryValue
InventoryDetailQuery::InventoryDetails#items    # InventoryDetailQuery::InventoryItems
InventoryDetailQuery::InventoryItems#entries    # Item[]
InventoryValueQuery::InventoryValue#snapshot
InventoryValueQuery::InventoryValue#history
```

Почему для списка `InventorySummaries`, а не `InventoryItems`:
`InventoryItems` читается как «предметы внутри инвентаря», а list-query
возвращает не предметы, а строки-инвентари. `InventoryItems` хорошо
подходит для вложенного блока `top_items` в detail-запросе (или
`TopItems`, если хочется подчеркнуть, что это только top-N).

Альтернативы:

- **`InventoryValueReport`** вместо `InventoryValueQuery::InventoryValue`:
  точнее говорит, что внутри ещё и history, но длиннее.
- **`InventoryCatalog`** вместо `InventoryListQuery::InventorySummaries`:
  доменнее, но снова появляется неоднозначный «catalog».
- **`TopItems`** вместо `InventoryDetailQuery::InventoryItems`: явно
  top-N, но менее симметрично с `InventoryDetails`.
- **Всё через `Result`:** `InventoryListQuery::Result`,
  `InventoryDetailQuery::Result` и т.д. — единообразно, но менее
  содержательно; для этого набора не рекомендую.

Если выбираем рекомендуемый набор, эскиз ниже нужно механически обновить:
`InventoryValuation` → `InventoryValueQuery`, `Snapshot` → `ValueSnapshot`,
`Change` → `ValueDelta`, `Series` → `ValueHistory`, `Page`/`Report` →
`InventoryValue`, `Listing` → `InventorySummaries`, `Detail` →
`InventoryDetails`.

## Эскиз целевого `InventoryListQuery` (вариант A, не финальный код)

> В коде ниже пока старые имена (`InventoryValuation`, `Snapshot`, `Change`,
> `Listing`); после выбора набора имён они меняются механически.


```ruby
# app/queries/inventory_list_query.rb
# typed: strict

class InventoryListQuery
  extend T::Sig

  DEFAULT_PER_PAGE = T.let(24, Integer)

  class InventorySummary < T::Struct
    const :steam_id, String
    const :valuation, InventoryValuation::Snapshot
    const :change, InventoryValuation::Change
    const :last_synced_at, ActiveSupport::TimeWithZone
    const :rarity_counts, T::Hash[RarityTier, Integer]
  end

  class Listing < T::Struct
    const :inventories, T::Array[InventorySummary]
    const :pagination, Appliers::Pagination
    const :total_count, Integer
  end

  class << self
    extend T::Sig

    sig { params(params: ActionController::Parameters).returns(Listing) }
    def call(params)
      pagination = Appliers::Pagination.new(
        params[:page], params[:per_page], default_per_page: DEFAULT_PER_PAGE
      )

      scope = InventoryValuation.with_aggregates(
        UserInventory
          .left_joins(user_inventory_items: :item)
          .group("user_inventories.id")
          .select("user_inventories.id", "user_inventories.steam_id", "user_inventories.updated_at")
      )

      scope = Appliers::SortApplier.call(
        scope,
        params,
        enum_class: Options::InventorySortOption,
        default: Options::InventorySortOption::ValueDesc
      )

      inventories = pagination.apply(scope).to_a
      baselines = InventoryValuation.baseline_for(inventories.map(&:steam_id), Date.current - 1)
      rarity_counts = RarityBreakdown.for_inventories(inventories.map(&:id))

      Listing.new(
        inventories: inventories.map do |inventory|
          summary_for(inventory, rarity_counts[inventory.id] || {}, baselines[inventory.steam_id])
        end,
        pagination: pagination,
        total_count: UserInventory.count
      )
    end

    private

    sig do
      params(
        inventory: UserInventory,
        rarity_counts: T::Hash[RarityTier, Integer],
        baseline: T.nilable(InventoryValueLog)
      ).returns(InventorySummary)
    end
    def summary_for(inventory, rarity_counts, baseline)
      valuation = InventoryValuation.snapshot_from(inventory)

      InventorySummary.new(
        steam_id: inventory.steam_id,
        valuation: valuation,
        change: InventoryValuation.change_for(valuation, baseline),
        last_synced_at: inventory.updated_at,
        rarity_counts: rarity_counts
      )
    end
  end
end
```

Что изменилось в `InventoryValuation`:

```ruby
class Change < T::Struct
  const :cents, Integer
  const :percent, Float
  const :basis_at, T.nilable(Time)
  const :partial, T::Boolean
  const :available, T::Boolean
end

class Series < T::Struct
  const :points, T::Array[Point]
  const :change, Change
end

class << self
  # Добавляет aliased-агрегаты к уже сгруппированному scope.
  # Константа AGGREGATE_SELECTS остаётся private.
  sig { params(scope: ActiveRecord::Relation).returns(ActiveRecord::Relation) }
  def with_aggregates(scope)
    scope.select(*AGGREGATE_SELECTS)
  end

  # Читает aliased-атрибуты по именам, без позиционного *values.
  sig { params(record: UserInventory).returns(Snapshot) }
  def snapshot_from(record)
    Snapshot.new(
      total_value_cents: record.read_attribute(:total_value_cents).to_i,
      items_count: record.read_attribute(:items_count).to_i,
      pricable_items_count: record.read_attribute(:pricable_items_count).to_i,
      priced_items_count: record.read_attribute(:priced_items_count).to_i,
      oldest_price_at: record.read_attribute(:oldest_price_at)
    )
  end

  # BASELINE_MAX_AGE_DAYS и change-логика переехали сюда из catalog-запроса.
  sig do
    params(snapshot: Snapshot, baseline: T.nilable(InventoryValueLog))
      .returns(Change)
  end
  def change_for(snapshot, baseline)
    return empty_change(partial: !snapshot.complete?) if baseline.nil?

    partial = !snapshot.complete? || !baseline.complete?
    basis_at = Time.utc(baseline.log_date.year, baseline.log_date.month, baseline.log_date.day)

    unless baseline.log_date >= Date.current - BASELINE_MAX_AGE_DAYS
      return Change.new(cents: 0, percent: 0.0, basis_at: basis_at, partial: partial, available: false)
    end

    cents = snapshot.total_value_cents - baseline.total_value_cents
    Change.new(
      cents: cents,
      percent: percentage(cents, baseline.total_value_cents),
      basis_at: basis_at,
      partial: partial,
      available: true
    )
  end
end
```

Сериализатор после этого только раскладывает готовые значения:

```ruby
def inventory_json(summary)
  valuation = summary.valuation
  change = summary.change

  {
    steam_id: summary.steam_id,
    total_value_cents: valuation.total_value_cents,
    change_24h_cents: change.cents,
    change_24h_percent: change.percent,
    items_count: valuation.items_count,
    pricable_items_count: valuation.pricable_items_count,
    priced_items_count: valuation.priced_items_count,
    complete: valuation.complete?,
    change_basis_at: change.basis_at&.to_date&.iso8601,
    change_partial: change.partial,
    change_available: change.available,
    rarity_breakdown: RarityBreakdownSerializer.call(summary.rarity_counts),
    last_synced_at: summary.last_synced_at.iso8601
  }
end
```

Важно:

- `Options::InventorySortOption` продолжает сортировать по алиасам
  `total_value_cents`/`items_count`, поэтому `with_aggregates` добавляет их в
  `SELECT`. Если позже убрать алиасы, сортировку придётся переводить на
  выражения concern-а.
- Каталожный `change_basis_at` сейчас отдаётся как дата (`YYYY-MM-DD`),
  detail/V1 — как timestamp. В эскизе это сохранено через
  `change.basis_at.to_date.iso8601` в catalog-сериализаторе.
- Спеки запроса механически меняются: `summary.items_count` →
  `summary.valuation.items_count`, `summary.change_24h_cents` →
  `summary.change.cents`.
- `Point#at` в целевом состоянии — `Time`, а `.iso8601` делают
  сериализаторы; это меняет тип в структуре, но не JSON-контракт.

## Остальные query: аналогичные изменения

### Сводка

| Query | Result сейчас | Result после | Основное |
|---|---|---|---|
| `ItemCatalogQuery` | `Page`, `PriceStats` | `ItemCatalog`, `PriceChangeStats` | naming, `last_synced_at` → `Time`, явный `DEFAULT_PER_PAGE`, аккуратный row для stats |
| `ItemPriceHistoryQuery` | `Page`, `Point` | `ItemPriceHistory`, `PricePoint` | `at` → `Time`, стабильный `ORDER BY created_at, id`, новый serializer вместо inline-map |
| `InventoryDetailQuery` | `Page`, `HistoryPoint` | `InventoryDetails`, `InventoryItems` | композиция `InventoryValue` + `InventoryItems`, удаление `HistoryPoint`, Time, общий rarity |
| `InventoryValueHistoryQuery` | `InventoryValueQuery::InventoryValue` | то же | тонкий адаптер, `.page` → `.report`, общий result с detail |
| `InventoryValueQuery` | `Page`/`Snapshot`/`Change`/`Series`/`Point` | `InventoryValue`/`ValueSnapshot`/`ValueDelta`/`ValueHistory`/`ValueHistory::Point` | naming, приватный SQL, `delta_for`, `with_aggregates` |

### `ItemCatalogQuery`

Result:

```ruby
class ItemCatalog < T::Struct
  const :items, T::Array[Item]
  const :pagination, Appliers::Pagination
  const :total_count, Integer
  const :price_change_stats, PriceChangeStats
  const :trends, T::Hash[String, T::Array[ItemTrendCache::TrendPoint]]
  const :last_synced_at, T.nilable(Time)
end

class PriceChangeStats < T::Struct
  const :gaining_count, Integer
  const :losing_count, Integer
end
```

Что поменять:

- `Page` → `ItemCatalog`, `PriceStats` → `PriceChangeStats`.
- `last_synced_at` хранить как `Time`, `.iso8601` — в сериализаторе.
- добавить `DEFAULT_PER_PAGE = 25` и передавать его в `Appliers::Pagination` явно.
- `scope.pluck(...).first` заменить на `T.must(...)`/`pick`, чтобы не
  держать неявный nil.
- `trends` остаются как есть: это уже готовый read-through cache.
- `last_synced_at` сейчас считается по всему `Item.marketable`, а не по
  filtered scope — зафиксировать как осознанное решение (или сделать
  scoped, если мета должна отражать фильтр).

Сериализатор: `ItemCatalogSerializer.call(ItemCatalogQuery::ItemCatalog)`.
Общие части (`metadata`, `change_24h_percent`, `trend_7d`) вынести в
shared item-serializer, чтобы не дублировать с detail.

### `ItemPriceHistoryQuery`

Result:

```ruby
class ItemPriceHistory < T::Struct
  const :range, Options::DateRange
  const :points, T::Array[PricePoint]
end

class PricePoint < T::Struct
  const :at, Time
  const :price_cents, Integer
  const :volume, Integer
end
```

Что поменять:

- `Page` → `ItemPriceHistory`, `Point` → `PricePoint`.
- `at` хранить как `Time`; `.iso8601` — в сериализаторе.
- добавить tie-breaker: `.order(:created_at, :id)`.
- добавить `ItemPriceHistorySerializer.call(ItemPriceHistoryQuery::ItemPriceHistory)`
  и убрать inline-map из `ItemPricesController#history`.
- кэш-ветка (`30d`) уже отдаёт сериализованные hash-и из
  `PriceHistoryCache`; сериализатор нужен только для query-ветки, либо
  кэш тоже можно привести к `PricePoint` (отдельное решение).
- `PriceHistoryCache::PricePoint` и `ItemTrendCache::TrendPoint` имеют
  одинаковую форму `at/price_cents/volume`; при желании вынести общий
  тип, но это уже про `app/caching/`, не про query.

### `InventoryDetailQuery`

Result:

```ruby
class InventoryDetails < T::Struct
  const :steam_id, String
  const :last_synced_at, ActiveSupport::TimeWithZone
  const :range, Options::DateRange
  const :value, InventoryValueQuery::InventoryValue
  const :items, InventoryItems
  const :avg_item_value_cents, Integer
  const :priciest_item, T.nilable(Item)
  const :rarity_counts, T::Hash[RarityTier, Integer]
end

class InventoryItems < T::Struct
  const :entries, T::Array[Item]
  const :pagination, Appliers::Pagination
  const :total_count, Integer
  const :trends, T::Hash[String, T::Array[ItemTrendCache::TrendPoint]]
end
```

Что поменять:

- `Page` → `InventoryDetails`; `HistoryPoint` удалить.
- `value` — общий `InventoryValueQuery::InventoryValue` (`snapshot` +
  `history`); убрать дублирующие `total_value_cents`, counts, `complete`,
  `oldest_price_at`, `change_*`, `history`.
- `items` — `InventoryItems` (`top_items` + pagination + trends);
  `top_items_total_count` становится `items.total_count`.
- `last_synced_at` — `Time`, форматирование в сериализаторе.
- `rarity_counts_for` вынести в общий `RarityBreakdown`.
- `avg_item_value_cents` и `priciest_item` оставить в `InventoryDetails`:
  это не part of the value snapshot.
- `complete` в сериализаторе брать из `value.snapshot.complete?`, не
  пересчитывать.

### `InventoryValueHistoryQuery`

- Остаётся тонким адаптером: `period` → `Options::DateRange::Param` →
  `InventoryValueQuery.report(steam_id, range)`.
- `.page` в concern переименовать в `.report`.
- Result — общий `InventoryValueQuery::InventoryValue`; отдельный
  `Page`/`Report` для history-запроса не нужен.
- Неизвестный `steam_id` по-прежнему даёт `snapshot: nil` + пустую
  `history`; зафиксировать как контракт V1 и покрыть тестом.
- `InventoryValuationSerializer` → `InventoryValueSerializer`,
  input — `InventoryValueQuery::InventoryValue`.

### `InventoryValueQuery` (бывш. `InventoryValuation`)

- Класс: `InventoryValueQuery`.
- Типы: `ValueSnapshot`, `ValueDelta`, `ValueHistory`,
  `ValueHistory::Point`, `InventoryValue`.
- Методы:
  - `.current` → `.snapshot_for`
  - `.series` → `.history`
  - `.page` → `.report`
  - `.change_for` → `.delta_for`
  - `.snapshot_from_row` — приватный named mapping
  - `.with_aggregates`, `.snapshot_from`, `.baseline_for` — публичный API
    concern-а.
- `AGGREGATE_EXPRESSIONS` удалить; `AGGREGATE_SELECTS` и SQL-константы —
  приватные.
- `ValueHistory` содержит `points` + `delta`; `ValueDelta` — cents/percent/
  basis_at/partial/available.
- `InventoryValueRecordingService` обновить на
  `InventoryValueQuery.snapshot_for` + `InventoryValueQuery::ValueSnapshot`.

### Cross-cutting

- `last_synced_at`/`change_basis_at`/`Point#at`: в query — `Time`/`Date`,
  в serializer — `.iso8601`. Это единое правило для всех query.
- `complete` не считать в сериализаторах; только `ValueSnapshot#complete?`.
- `change_24h_percent` — один shared serializer helper на все места.
- `metadata`/`rarity_breakdown` — shared serializers; `rarity_counts` —
  shared query/concern.
- `InventoryCatalogSerializer`/`InventoryCatalogCache` при переименовании
  query в `InventoryListQuery` переименовать в
  `InventoryListSerializer`/`InventoryListCache`; поднять cache key version.
- `Options::*`/`Appliers::*` специально не трогаем: они уже механически
  чистые. Единственное исключение — если `InventorySortOption` начнёт
  ссылаться на aliases, которых больше нет в `SELECT` (см. ограничение
  `with_aggregates`).

## Открытые решения

Принято:

- `InventoryValuation` → `InventoryValueQuery`;
- `Snapshot` → `ValueSnapshot`, `Change` → `ValueDelta`,
  `Series` → `ValueHistory`;
- result-структуры называем по содержимому:
  `InventoryValue`, `InventorySummaries`, `InventoryDetails`,
  `InventoryItems`, `ItemCatalog`, `ItemPriceHistory`.

Осталось уточнить на код-ресерче:

1. `AGGREGATE_COLUMNS`: bulk-API `snapshots_for(ids)` или concern-scoped
   `with_aggregates(scope)`. Из-за сортировки по алиасам
   `total_value_cents`/`items_count` практичнее выглядит
   `with_aggregates`; подтвердить по фактическому SQL.
2. Точные сигнатуры `InventoryValueQuery`: `.snapshot_for`,
   `.history`, `.report`, `.delta_for` — проверить, не конфликтуют ли с
   существующими вызовами и не удобнее ли `.value_for`.
3. `ItemPriceHistorySerializer`: отдавать массив points или объект
   `{ range:, points: }` — сейчас API отдаёт голый массив, поэтому
   сериализатор, вероятно, должен возвращать массив.
