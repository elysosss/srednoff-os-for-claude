# X3: Классификатор задач — делать самому или делегировать

> Статус: DRAFT
> Тип: спека-набросок
> Модуль E1: `task-classifier` (зависит от `delegate`; `executor-routes` — опционально)
> Зависит от: E1, X1, X2 (для поля `route`)   Блокирует: —

## Goal
Детерминированный классификатор брифа задачи отвечает, выполнить её Claude самому или делегировать внешнему исполнителю (X1), и если делегировать — на какой маршрут (X2). Ответ совещательный: решает Claude, а при сомнении — владелец.

## User value
Нет ручного «а не отдать ли это DeepSeek?» на каждую задачу, и главное, рискованная работа не уходит наружу случайно. Закрыто, когда: на наборе фикстур классификатор никогда не советует делегировать задачи режима `critical` и задачи с чувствительными путями, а механические задачи получают совет «делегировать» с маршрутом.

## Non-goals
- LLM-классификатор. CLAUDE.md §4 требует не звать LLM там, где хватает правил; при неуверенности правил судит сам Claude, он и так в контуре.
- Автоматический запуск делегации по результату классификации. Классификатор ничего не исполняет.
- Замена `mode-router`/`domain-router`. X3 их потребитель, а не конкурент.
- Экономия ценой качества (Принцип №1): «делегировать» советуется, только когда ожидаемое качество с ревью Claude не хуже.

## Current state
- `registry/routing-lib.{ps1,sh}`: `get_mode` (режимы `fast/standard/production/critical/turbo`, критичный паттерн — security/auth/payments/миграции БД/crypto) и `get_domain_tags`. Вызываются из `mode-router`/`domain-router`.
- **Помеха:** эти роутеры рассчитаны на глобальный `~/.claude/registry`, а `init-claude-project` намеренно не копирует `registry/` в проект. Глобальная установка владельцем запрещена, поэтому per-project модулю звать `~/.claude/registry/mode-router` нельзя.
- Паттерны `routing-lib` почти целиком английские (кроме «максималь», «не эконом», «глубокий»), а владелец пишет брифы по-русски.
- Фикстурный прогон `scripts/run-evals.{ps1,sh}` + `registry/evals/*-fixtures.json` уже есть — туда ложатся фикстуры X3.

## Assumptions
- `ASSUMPTION:` E1 позволяет модулю поставлять вендоренную копию файла из `registry/` со сверкой хэша в CI (один канон — `registry/routing-lib`, копия — артефакт сборки). Проверить по финальной спеке E1; иначе логика режима дублируется в модуле с фикстурами на совпадение.
- `ASSUMPTION:` списка изменяемых путей, который Claude передаёт через `--paths`, достаточно, чтобы поймать чувствительный контекст. Путей, которые исполнитель прочтёт сам, классификатор не видит (см. X1, модель угроз).

## Questions
1. Порог уверенности для совета «delegate»? По умолчанию совет даётся, только когда совпал хотя бы один «делегируемый» сигнал и ни одного запрещающего. Иначе — `self`.
2. Показывать совет владельцу каждый раз или только Claude? По умолчанию только Claude, одной строкой в отчёте (как фиксация выбора модели в правиле 80).

## GitHub research
| Repo | License | Что берём | Риск |
|---|---|---|---|
| `diegosouzapw/OmniRoute` @ `a58000c7685f` | MIT | `open-sse/services/intentClassifier.ts`: синхронный классификатор без I/O (<1 мс), типы `code/math/reasoning/creative/simple/medium`, результат `{type, confidence, signals[]}`, словари ключевых слов на 9 языках, **включая русский**; `autoCombo/intentTaskFitnessMap.ts` — отображение класса задачи на пригодность маршрута | Классифицирует **промпт к LLM**, а не инженерную задачу с риском; классы нам не подходят как есть. Берём форму ответа (`signals[]`), многоязычные словари и идею «класс → маршрут», код не копируем |
| (внутренний) `registry/routing-lib` | MIT (репо) | Режим качества и доменные теги как входные признаки | Дрейф копии в модуле — закрывается сверкой хэша |

## Official docs checked
Не взаимодействует с Claude Code напрямую: скрипт зовёт навык `delegate` или сам Claude. PF-xx не требуются. Проверено сверх: CLAUDE.md §4 и правила 70/80 (качество первично, модель не занижать).

## Architecture (дизайн)
`bin/task-classify.{ps1,sh} --brief <text> [--paths a,b] [--json]` — чистая функция без сети:
1. **Режим**: `get_mode` из вендоренной `routing-lib`.
2. **Жёсткие запреты (`self`, без вариантов)**: режим `critical` или `turbo`; путь из `--paths` совпадает с секретными паттернами `protect-secrets` (`.env`, `*.pem`, `credentials.json`, …) или с `denyPaths` конфига; бриф требует контекста текущего диалога («как мы обсуждали», «исправь то, что выше»); задача про сам OS, хуки или права; модуль `delegate` выключен.
3. **Делегируемые сигналы** (RU+EN словари в `config/signals.json`): массовая механическая правка, переименование по шаблону, генерация тестов по готовому образцу, перевод и форматирование доков, boilerplate по спецификации. Режим `fast`/`standard`.
4. **Класс → маршрут**: таблица `classRoutes` (`bulk-edit → cheap-code`, `docs → docs-bulk`). Если X2 выключен, в ответе только `executor` по умолчанию из X1.
5. Выход: `{decision: self|delegate|ask, class, route|null, mode, signals[], blockers[], confidence}`. `ask` — когда есть и делегируемые, и «серые» сигналы (production-режим, больше N файлов, неизвестный домен): Claude спрашивает владельца по правилу 30.

Как это использует Claude: навык `delegate` в начале вызывает `task-classify`. При `self` навык отказывается делегировать и называет блокер; при `delegate` Claude может следовать совету или отклонить его одной строкой с причиной. Классификатор никогда не повышает риск: запрет сильнее любого сигнала.

Отвергнутые альтернативы: звать `mode-router` из `~/.claude/registry` (глобальная установка запрещена); отдельная LLM-классификация через внешний исполнитель (тратит деньги и отдаёт бриф наружу раньше решения о делегировании — это утечка сама по себе).

## API contracts (интерфейсы и форматы)
```json
{ "decision": "delegate", "class": "bulk-edit", "route": "cheap-code", "mode": "standard",
  "signals": ["rename-pattern:ru", "files>=10"], "blockers": [], "confidence": 0.7 }
```
Коды выхода: 0 — есть решение, 2 — модуль выключен (печатает `{"decision":"self","blockers":["classifier-disabled"]}`), 1 — ошибка разбора (тоже трактуется как `self`, fail-safe в сторону «не делегировать»). Конфиг `config/default.json`: `enabled`, `signals` (путь), `classRoutes`, `denyPaths[]`, `askFileThreshold`.

## Data model / migrations
Состояния нет. Конфиг и словари версионируются `schemaVersion`. Фикстуры — `tests/fixtures/task-class-fixtures.json` в формате `registry/evals` (`{id, brief, paths, expectedDecision, expectedRoute}`), прогоняются и `run-evals`, и behave.

## Security model
Защищаем: от случайной отправки наружу задач с секретами, auth/payments/миграциями и задач про саму OS. Любая ошибка классификатора даёт `self`, то есть сбой закрыт в безопасную сторону.
Не защищаем: от брифа, который сознательно маскирует рискованную задачу под механическую; от чувствительных данных в файлах, не упомянутых в `--paths`. Эти случаи ловит ревью Claude и модель угроз X1.

## Risks
| Риск | Вероятность | Влияние | Митигация |
|---|---|---|---|
| Ложное «delegate» для задачи с чувствительным контекстом | средняя | высокое | Запреты сильнее сигналов; фикстуры-«ловушки» на русском; решение всё равно за Claude |
| Ложное «self» — польза модуля нулевая | средняя | низкое | Журнал решений в отчёте, подстройка словарей по фикстурам |
| Дрейф вендоренной `routing-lib` | средняя | среднее | Сверка хэша в CI, фикстуры режимов прогоняются и против копии |

## Acceptance criteria
- AC1: выключенный модуль всегда отвечает `self` с блокером `classifier-disabled` → S1.
- AC2: бриф режима `critical` (в том числе по-русски) даёт `self` → S2.
- AC3: `--paths` с `.env` даёт `self` при любых сигналах → S3.
- AC4: механическая массовая правка по-русски даёт `delegate` и маршрут из `classRoutes` → S4.

## Testing plan
```gherkin
Scenario: S1 disabled classifier never recommends delegation
  Given task-classifier is installed in mode "off"
  When I classify "переименуй все snake_case функции в camelCase"
  Then the decision is "self" and blockers contain "classifier-disabled"
Scenario: S2 critical work stays with Claude
  When I classify "поправь проверку OAuth токена в auth middleware"
  Then the decision is "self" and the mode is "critical"
Scenario: S3 sensitive paths block delegation
  When I classify "отформатируй конфиги" with paths ".env, config/app.json"
  Then the decision is "self" and blockers contain "sensitive-path"
Scenario: S4 bulk mechanical edit is delegated to the mapped route
  Given classRoutes maps "bulk-edit" to "cheap-code"
  When I classify "переименуй во всех 40 файлах logger.warn в log.warning"
  Then the decision is "delegate" and the route is "cheap-code"
```
Плюс ≥ 30 табличных фикстур (половина на русском, треть «ловушек») через `run-evals`. Паритет `.ps1/.sh` — одинаковые ответы на всех фикстурах.

## Rollback plan
Режим `off` (E1) — навык `delegate` работает без совета. Удаление модуля ничего не оставляет: состояния нет.

## Estimate (оценка объёма)
- Вендоринг `routing-lib` + сверка хэша + скелет `task-classify` — 0.5 сессии.
- Словари RU/EN, запреты, фикстуры и behave S1–S4 — 1–1.5 сессии.
Итого ~2 сессии. Взорвать может: E1 без механизма вендоринга (тогда дублирование с отдельными фикстурами, +0.5 сессии).

## План работ
Заполняется после аппрува.

## Definition of done
- [ ] Фикстуры: 0 ложных `delegate` на «ловушках», паритет PS/bash 100 %
- [ ] behave S1–S4 зелёные на Windows и Linux
- [ ] Навык `delegate` вызывает классификатор и уважает `self`

## Progress log
- 2026-09-27 — создан набросок спеки
