# D5: ADR и контракты модулей — протокол «стоп и черновик ADR», CONTRACT.md, архитектурный гейт

> Статус: DRAFT
> Тип: спека-набросок
> Модуль E1: `adr` (`requires.modules: ["artifacts", "tasks"]`)
> Зависит от: E1, D1 (`docs/adr/`, формат инвариантов, линтер L2/L3), D2 (состояние `blocked`, поле `adr`), D3 (защита `architecture.md` и `CONTRACT.md`)   Блокирует: D6 (правило «правка раздела `## Зависимости` в `CONTRACT.md` требует ADR»), D8 (признак high-risk «архитектура без ADR»), D4 (роль архитектора)

## Goal
Агент внутри карточки не принимает архитектурных решений (§1): когда решение нужно, карточка останавливается в `blocked/` и порождает черновик ADR на ревью человеку. Каждый модуль несёт `CONTRACT.md` (§4) с публичным API, инвариантами-командами и тем, чего модуль не делает. Изменение `docs/architecture.md`, любого `CONTRACT.md` или объявленного архитектурно-чувствительного файла без ссылки на принятый ADR машинно делает изменение high-risk и требует аппрува человека.

## User value
Сейчас «почему так» живёт в журнале наблюдений (правило 60, `.agent/OBSERVATION_LOG.md`), который сам говорит: объяснение длиннее предложения — это ExecPlan или ADR; но формата ADR в OS нет. Закрыто, когда (а) карточку с решением нельзя закрыть без принятого ADR; (б) правка контракта не проходит молча ни через `task done`, ни через CI; (в) у каждого модуля есть проверяемый список «не делает».

## Non-goals
- Линтер графа зависимостей и физические границы модулей — D6; канон модулей и разрешённых рёбер — сами `CONTRACT.md` (раздел `## Зависимости`), D6 читает их и сравнивает с фактическим графом; отдельного `modules.yaml` нет. Метрики — D9.
- Распознавание «это архитектурное решение» по смыслу диффа моделью. Мы честно ограничиваемся путями и файлами-манифестами; остальное — ревьюер (D4) и человек.
- Полный MADR со всеми опциональными разделами; ADR для самой OS (у форка свои спеки).

## Current state
- Журнал наблюдений: однострочные `decision/rejected` записи, месячные файлы; ADR будет тем, на что журнал ссылается. Связь: запись `decision` о решении по архитектуре содержит `ADR-NNNN`.
- D1 даёт `docs/adr/`, линтер L2 (спек → ADR, статус не `Rejected`) и формат инвариантов `## INV-NNNN` + `check:`; D2 даёт `blocked/` и поле `adr: []`; D3 — защищённые зоны.
- `skills-library/documentation-adrs` и `principal-architect-agent` — общие шаблоны процесса без формата ADR; роль архитектора (D4) может их предзагрузить, шаблон ADR D5 поставляет сам.

## Assumptions
- `ASSUMPTION:` при squash-мерже GitHub строки-трейлеры коммитов (`ADR: 0012`) попадают в тело итогового коммита, но не обязательно как трейлеры, распознаваемые `git interpret-trailers`. Поэтому канон ссылки — поле `adr:` карточки, а трейлер — вспомогательный. Проверить на тестовой PR со squash.
- `ASSUMPTION:` без установленного D6 «модуль = каталог, где лежит `CONTRACT.md`» достаточно для проектов владельца (крейты, пакеты); D6 использует то же определение модуля. Проверить на двух реальных проектах владельца: совпадает ли множество каталогов с CONTRACT.md с модулями по манифестам сборки.

## Questions
1. Кто меняет статус ADR на `Accepted`? По умолчанию — только мерж PR с обязательным ревью человека (D8, правила ветки); `adr accept` локально лишь проставляет дату и проверяет формат и в CI без ревью не засчитывается.

## GitHub research
| Repo | License | Что берём | Риск |
|---|---|---|---|
| `adr/madr` (push 2026-08-28) | MIT OR CC0-1.0 | Структуру: статус, контекст, варианты, решение, последствия; с атрибуцией в шаблоне | полная форма тяжела для агента; берём сокращённую |
| `npryce/adr-tools` (push 2024-04-25) | GPL-3.0 | Только конвенцию `NNNN-slug.md`, «supersedes/superseded by» | GPL — код не берём и не смотрим в реализацию |
| `bmad-code-org/BMAD-METHOD` | MIT | Архитектор как отдельная роль, пишущая документ до разработчика | решения там не останавливают задачу машинно |

## Official docs checked
н/п для платформы сверх D3: D5 не добавляет хуков; защита путей — через D3 (PF-06, PF-10, PF-28 учтены там).

## Architecture (дизайн)
**ADR.** `docs/adr/NNNN-slug.md`, номер = максимум существующих + 1, четыре цифры. Шапка построчно (как у спек D1): `> Status: Proposed | Accepted | Rejected | Superseded | Deprecated`, `> Date:`, `> Modules:`, `> Cards: T-0142`, `> Supersedes:` / `> Superseded-by:`. Тело: Контекст → Варианты → Решение → Последствия (плейбук: «контекст → решение → последствия», варианты добавлены из MADR, чтобы отказ был виден).

**Линтер `adr lint`** (A1–A6): A1 шапка и статус из списка; A2 номера уникальны, имя файла совпадает с номером; A3 `Superseded` требует `Superseded-by` на существующий ADR и наоборот; A4 тело `Accepted` ADR не меняется относительно базы (CI): правка принятого — только новым ADR с `Supersedes`; A5 модули из `Modules:` существуют (L3 D1); A6 карточки из `Cards:` существуют. Конфликт номеров из параллельных веток ловит A2 в CI; перенумеровать можно только `Proposed`.

**Протокол «стоп и черновик ADR»**:
1. Исполнитель понимает, что нужен выбор (библиотека, новый поток данных, изменение контракта) — **это пожелание**, машина его не видит. Машина видит последствия: D3 отклоняет правку `architecture.md`/`CONTRACT.md`, `adr-gate` ниже отклоняет `task done`, D6 валит новое ребро. Причина каждого такого отказа содержит одну команду: `task block T-0142 --adr "<title>"`.
2. `task block` (реализует D5 поверх машины D2): создаёт `docs/adr/NNNN-slug.md` из шаблона со статусом `Proposed`, Контекстом из карточки (спек#якорь, id, текст причины) и `Cards: T-0142`; двигает карточку `active → blocked`, `blocked_by: ADR-NNNN`; снимает замок модуля; исполнитель завершает сессию с disposition `blocked` (правило 90). Попытка не засчитывается как провал.
3. Архитектор (D4) заполняет Варианты/Решение; человек принимает мержем PR.
4. `task unblock T-0142` — только если ADR `Accepted`; карточка идёт в `backlog/` с `adr: [ADR-NNNN]`; планировщик решает, нужно ли передробить.

**CONTRACT.md** (`<module>/CONTRACT.md`) — шаблон и линтер `contract lint` (K1–K4). Разделы: `## Назначение`; `## Публичный API` (список экспортируемых символов/путей, по строке); `## Инварианты` (формат D1: `### INV-<module>-NNNN` + `check:`; прогоняет `invariants run` D1); `## Не делает` (не пуст — K2); `## Зависимости` (`- allow: <module>` по строке — **канон** разрешённых рёбер, его читает D6); `## ADR` (ссылки). K1 все разделы есть; K3 инварианты с `check:` (или `manual` + `why-manual`); K4 ADR из раздела существуют и не `Rejected`; K5 каждое `allow:` указывает на существующий модуль (каталог с `CONTRACT.md`) и не на сам модуль; соответствие рёбер реальному коду проверяет D6.

**Архитектурный гейт `adr-gate --base REF [--card ID]`**. Архитектурно-чувствительные пути: `docs/architecture.md`, `**/CONTRACT.md`, плюс `config.archSensitive` (по умолчанию манифесты зависимостей внутри модулей: `**/Cargo.toml`, `**/package.json`, `**/pyproject.toml`, `**/go.mod`, `**/*.csproj`). Если дифф их задевает: нужен хотя бы один ADR со статусом `Accepted` в поле `adr:` карточки (или трейлер коммита `ADR: NNNN`, если карточки нет) и у ADR `Modules:` пересекается с задетыми модулями. Иначе: `task done` отказывает (код 6), в CI (D8) PR помечается `high-risk: architecture-without-adr` и требует ручного аппрува. Дополнительно D2 V9 поднимает `risk` до `high` у карточек `kind: contract` и у любых карточек, чей `touch_allowed` задевает эти пути.

Отвергнуто: ADR-решения в спеке фичи (смешивает «что» и «почему», теряется при переписывании спека); модель-классификатор «архитектурность диффа» (недетерминированно, ложные срабатывания без объяснения); запрет правок `architecture.md` вообще (он должен меняться — но через ADR).

## API contracts (интерфейсы и форматы)
```text
adr new --title T [--modules M,..] [--card ID]   -> docs/adr/NNNN-slug.md (Proposed)
adr lint [--base REF] [--json]    adr list [--status S]    adr accept NNNN (дата + формат; см. Questions)
contract new <module>   contract lint [<module>|--all] [--json]
adr-gate --base REF [--card ID] [--json]  -> {touched:[path], modules:[..], adrs:[..], verdict: ok|needs-adr}
task block ID --adr TITLE   task unblock ID            (подкоманды CLI D2, реализация здесь)
```
Коды выхода: 0 ок; 1 нарушения линтера; 2 модуль выключен; 6 `needs-adr`.

## Data model / migrations
ADR и CONTRACT.md — данные проекта, коммитятся, при `uninstall` остаются. Состояния у модуля нет, кроме журналов прогонов в `.claude/os-modules/.state/adr/`. Формат шапки версионируется строкой `<!-- adr-format: 1 -->`.

## Security model
Защищаем: от тихого архитектурного решения внутри карточки (гейт по путям + D6 по рёбрам), от переписывания принятых ADR задним числом (A4), от контракта-пожелания (K2/K3). Не защищаем: решение, выраженное только в коде внутри разрешённых файлов модуля (новая абстракция, смена алгоритма) — ловит только ревьюер и человек; подлинность «Accepted» локально (см. D4 Security model — аппрув доказывает только GitHub).

## Risks
| Риск | Вероятность | Влияние | Митигация |
|---|---|---|---|
| Гейт шумит на рутинных правках манифестов (bump патч-версии) | высокая | среднее | `archSensitive` настраивается; отдельный режим `deps: warn` для манифестов |
| Карточки массово уходят в `blocked` и работа встаёт | средняя | среднее | метрика доли blocked в D9; планировщик заранее выносит решения в ADR до декомпозиции |
| Агент пишет формальный ADR ради прохода гейта | средняя | среднее | `Accepted` только мержем с ревью человека |

## Acceptance criteria
- AC1: `off` — все команды печатают `adr disabled`, код 2, `task block` не создаёт файлов → S1.
- AC2: `task block` создаёт ADR `Proposed`, двигает карточку в `blocked/` и снимает замок → S2.
- AC3: `task unblock` при ADR `Proposed` отказывает → S3.
- AC4: дифф, меняющий `CONTRACT.md` без принятого ADR в карточке, даёт `needs-adr` и код 6 → S4.
- AC5: правка тела `Accepted` ADR даёт A4 → S5.

## Testing plan
```gherkin
Scenario: S1 disabled module
  Given the adr module is in mode "off"
  When I run task block T-0142 --adr "Use ring buffer"
  Then the exit code is 2 and docs/adr is unchanged
Scenario: S2 stop and draft
  Given active T-0142 in module "sim/transport" and ADRs up to 0011
  When I run task block T-0142 --adr "Use ring buffer"
  Then docs/adr/0012-use-ring-buffer.md has Status "Proposed" and Cards "T-0142"
  And T-0142 is in tasks/blocked with blocked_by "ADR-0012" and the module lock is free
Scenario: S3 unblock needs an accepted ADR
  Given T-0142 blocked by ADR-0012 with Status "Proposed"
  When I run task unblock T-0142
  Then the exit code is 1 and T-0142 stays in tasks/blocked
Scenario: S4 contract change without ADR
  Given active T-0150 with adr [] whose diff modifies sim/transport/CONTRACT.md
  When I run adr-gate --base main --card T-0150
  Then the verdict is "needs-adr" and the exit code is 6
Scenario: S5 accepted ADRs are immutable
  Given ADR-0007 is Accepted on main
  When a branch edits the Decision section of ADR-0007
  Then adr lint --base main reports A4
```
Юнит: нумерация и слаг, разбор шапки, пересечение модулей. Вручную: цикл block → ADR → мерж → unblock на реальном проекте.

## Rollback plan
`off` — команды ничего не делают, `adr-gate` возвращает 2 (D2 и D8 трактуют как «гейт выключен» и пишут это в отчёт, а не молча пропускают). `uninstall` удаляет модуль; ADR и CONTRACT.md остаются данными проекта.

## Estimate (оценка объёма)
Шаблоны ADR/CONTRACT + `adr new/lint` — 0.5–1 сессия; `contract lint` — 0.5; `adr-gate` + `task block/unblock` — 1; behave S1–S5 на двух ОС — 0.5. Итого 2.5–3 сессии. Взорвать может: A4 на squash-мержах и шум гейта на манифестах в монорепо.

## План работ
Заполняется после аппрува.

## Definition of done
- [ ] Паритет `.ps1/.sh`, в `.ps1` нет кириллицы; S1–S5 зелёные на Windows и Linux
- [ ] Шаблон ADR содержит атрибуцию MADR; кода adr-tools нет
- [ ] K5 и чтение раздела `## Зависимости` в D6 проверены на одной фикстуре

## Progress log
- 2026-09-27 — создан набросок спеки
