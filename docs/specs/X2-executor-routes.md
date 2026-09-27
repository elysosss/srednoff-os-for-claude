# X2: Маршруты исполнителей с фолбэками

> Статус: DRAFT
> Тип: спека-набросок
> Модуль E1: `executor-routes` (зависит от модуля `delegate`)
> Зависит от: E1, X1   Блокирует: X3 (поле `route` в его ответе)

## Goal
Именованные цепочки внешних исполнителей из X1 с приоритетами: если текущий исполнитель недоступен или его квота исчерпана, делегация идёт к следующему звену. Когда цепочка кончилась, задача возвращается Claude.

## User value
Владелец держит несколько исполнителей (DeepSeek через `dsh`, Codex, OpenRouter через скрипт) и не выбирает руками, у кого осталась квота. Закрыто, когда: исчерпанный исполнитель пропускается автоматически, а платный без согласия не запускается. По журналу видно, почему выбран тот или иной исполнитель.

## Non-goals
- HTTP-шлюз и балансировщик LLM-запросов. Маршрутизируются **процессы-исполнители**, а не API-вызовы.
- Маршрутизация трафика самого Claude (ограничение 1). В цепочке нет и не может быть звена, которое ходит в Anthropic API от имени подписки.
- Скоринг, бандиты, «chaos»-стратегии OmniRoute. В v1 только строгий приоритет.
- Автоповтор задачи на другом исполнителе, если первый вернул **плохой результат**. Качество оценивает Claude, а не маршрутизатор.
- Запрос баланса у провайдеров по API: в v1 квоты локальные плюс реакция на ошибки.

## Current state
- X1 запускает ровно одного исполнителя по `id`. Понятия квоты и цепочки нет.
- В OS есть бюджетные понятия `lean/balanced/deep/turbo` (`registry/quality-modes.json`) — это бюджет контекста Claude, к деньгам на внешние API отношения не имеют. Смешивать их не будем.
- Правило 50 требует явного подтверждения платных действий; вызов платного API — платное действие.

## Assumptions
- `ASSUMPTION:` исчерпание квоты у `codex` и `dsh` различимо по stderr/коду выхода (текст с `429`, `rate limit`, `quota`, `insufficient balance`). Проверить: собрать реальные ответы при нулевом балансе и при rate limit для каждого CLI, положить в фикстуры классификатора ошибок.
- `ASSUMPTION:` время сброса квоты обычно не сообщается машиночитаемо. Тогда используется `cooldownSec` из конфига. Проверить на тех же образцах.
- `ASSUMPTION:` E1 поддерживает зависимость модуля от модуля (PF-17: у плагина есть `dependencies`; механизм per-project установки E1 его может не повторять). Проверить по финальной спеке E1.

## Questions
1. Спрашивать согласие на платного исполнителя на каждый запуск или один раз на маршрут? По умолчанию — один раз на маршрут: поле `paidApprovedAt` ставит владелец командой `/routes approve <route>`, а не Claude.
2. Нужен ли звену лимит в деньгах, а не только в запусках? По умолчанию нет: только число запусков в окне. Денежные лимиты требуют данных о цене, которых у CLI нет.

## GitHub research
| Repo | License | Что берём | Риск |
|---|---|---|---|
| `diegosouzapw/OmniRoute` @ `a58000c7685f` (ветка `release/v3.8.51`, push 2026-09-27) | MIT | Паттерны: combo = упорядоченная цепочка `(provider, model, connection)` со стратегией `priority` и автофолбэком (`docs/guides/FEATURES.md`); исчерпанная квота и открытый circuit делают кандидата неподходящим, неизвестная квота — подходящим (`docs/OMNIROUTE_ROUTING_POLICY.md`); класс оплаты — свойство подключения, а не модели, и «uncurated is not free», то есть `unknown` считается платным (`docs/routing/SUBSCRIPTION_LADDER.md`); `route preview` без реальных запросов | Огромная кодовая база (≈26.8k файлов), быстрые релизы. **OmniRoute рекламирует маршрутизацию подписочных OAuth-подключений Claude Code — для нас это прямо запрещено (ограничение 1)**. Код и сам шлюз не берём, только идеи |

## Official docs checked
Сверх PF-xx ничего: модуль не взаимодействует с Claude Code, кроме вызова скриптов навыком. PF-18 — основание для правила «ни одно звено не выставляет `ANTHROPIC_*`» (проверяется в X1 и `doctor`).

## Architecture (дизайн)
- `bin/route-pick.{ps1,sh} --route <name>` — выбирает первое **подходящее** звено и печатает его `executor id` с причинами. Ничего не запускает. Это аналог `route preview` у OmniRoute.
- `delegate-run` из X1 получает `--route <name>` вместо `--executor`: вызывает `route-pick`, запускает исполнителя, передаёт исход в `route-record`.
- `bin/route-record` классифицирует исход: `ok`, `task_failed`, `quota_exhausted`, `rate_limited`, `unavailable` (CLI не найден, сеть, 5xx), `auth_missing`. Классификатор — таблица регулярок на адаптер в `config/error-signatures.json`.
- Переход к следующему звену — **только** при `quota_exhausted | rate_limited | unavailable | auth_missing`. При `task_failed` цепочка останавливается, исход уходит Claude как `failed`: плохой результат — вопрос качества, решает Claude.
- Звено подходит, если: модуль исполнителя включён, CLI найден, не на cooldown, локальный счётчик в окне ниже `maxRuns`, а для `billing: metered|unknown` у маршрута есть `paidApprovedAt`.
- Конец цепочки — всегда неявное звено `self`: `route-pick` возвращает `{"executor": null, "disposition": "blocked", "reason": "..."}`, и Claude делает задачу сам или спрашивает владельца. Эскалации в «ещё один платный» по умолчанию нет.

Отвергнутые альтернативы: взвешенный скоринг (непрозрачен, а при серийной работе и трёх звеньях не нужен); поднять OmniRoute локально как endpoint для всех исполнителей (тяжёлая зависимость, supply-chain, и шлюз, который умеет проксировать Claude, держать рядом нельзя).

## API contracts (интерфейсы и форматы)
`config/default.json`:
```json
{ "schemaVersion": 1,
  "routes": {
    "cheap-code": { "steps": ["dsh-deepseek", "codex-openrouter", "codex-default"], "paidApprovedAt": null },
    "docs-bulk":  { "steps": ["dsh-deepseek"], "paidApprovedAt": null } },
  "limits": {
    "dsh-deepseek": { "billing": "metered", "window": "24h", "maxRuns": 40, "cooldownSec": 900 },
    "codex-default": { "billing": "subscription", "window": "5h", "maxRuns": 20, "cooldownSec": 1800 } } }
```
`route-pick` → stdout JSON `{route, executor|null, disposition: "ready"|"blocked", skipped:[{executor, reason}]}`; коды выхода 0 — выбран, 8 — цепочка исчерпана, 9 — маршрут не найден. Команда `/routes` (commands/) показывает состояние цепочек и счётчики; `/routes approve <route>` ставит `paidApprovedAt` (только из команды владельца, навык её не вызывает).

## Data model / migrations
`state/usage.jsonl` — строка на запуск: `{ts, route, executor, outcome, durationSec}` без текста задачи. `state/cooldowns.json` — `{executor: untilTs}`. Счётчики окна считаются по `usage.jsonl`; файл обрезается до 30 дней. Миграции конфига — полем `schemaVersion` через E1.

## Security model
Защищаем: деньги владельца (платное и `unknown` звено без `paidApprovedAt` не запускается; `unknown` = платное, как в OmniRoute); подписку Claude (звено с `ANTHROPIC_*` в env отвергает ещё X1). Журнал не хранит текст задач и секреты.
Не защищаем: точность квот (локальный счётчик не знает реального баланса у провайдера); злоупотребление исполнителем внутри его квоты.

## Risks
| Риск | Вероятность | Влияние | Митигация |
|---|---|---|---|
| Сигнатура квоты не распознана, фолбэка нет | средняя | низкое | Исход `unavailable` по умолчанию при ненулевом коде без текста результата; фикстуры сигнатур |
| Фолбэк на более дорогое звено незаметно тратит деньги | средняя | среднее | `paidApprovedAt` на маршрут, в ответе Claude всегда видно `skipped[]` и выбранное звено |
| Каскад повторов по цепочке затягивает задачу | низкая | низкое | Не больше одного перехода на тип ошибки, общий таймаут маршрута |

## Acceptance criteria
- AC1: в режиме `off` `delegate-run --route` отвечает «routes disabled», исполнитель не запускается → S1.
- AC2: звено с `quota_exhausted` пропускается, выбирается следующее, причина есть в `skipped` → S2.
- AC3: `task_failed` не вызывает переход к следующему звену → S3.
- AC4: платное звено без `paidApprovedAt` не выбирается → S4.

## Testing plan
Исполнители-заглушки печатают заданный stderr и код выхода.
```gherkin
Scenario: S1 disabled routes module is a no-op
  Given executor-routes is installed in mode "off"
  When I run delegate-run with route "cheap-code"
  Then no executor process is started
Scenario: S2 fallback on exhausted quota
  Given route "r" with steps "fake-a, fake-b" and fake-a prints "429 quota exceeded"
  When I run delegate-run with route "r"
  Then fake-b is started and route-pick lists fake-a as skipped with reason "quota_exhausted"
  And fake-a is on cooldown
Scenario: S3 task failure stops the chain
  Given route "r" with steps "fake-a, fake-b" and fake-a exits 1 with output "tests failed"
  When I run delegate-run with route "r"
  Then the disposition is "failed" and fake-b is not started
Scenario: S4 metered executor needs route approval
  Given route "r" with a single metered step and paidApprovedAt null
  When I run route-pick for "r"
  Then the exit code is 8 and the reason mentions "paid approval"
```
Юнит: классификатор сигнатур ошибок (табличные фикстуры в духе `registry/evals`), подсчёт окна. Паритет `.ps1/.sh`.

## Rollback plan
Режим `off` (E1) — X1 работает по `--executor` как раньше. Удаление модуля удаляет `state/` со счётчиками; X1 от него не зависит.

## Estimate (оценка объёма)
- `route-pick`, `route-record`, конфиг и сценарии S1 (run-evals)–S4 — 1.5 сессии.
- Сбор реальных сигнатур ошибок `codex`/`dsh` и фикстуры — 0.5–1 сессия.
Итого 2–3 сессии. Взорвать может: отсутствие стабильных сигнатур квоты у CLI (тогда только локальные счётчики).

## План работ
Заполняется после аппрува.

## Definition of done
- [ ] сценарии S1 (run-evals)–S4 зелёные на Windows и Linux, паритет пар скриптов
- [ ] Фикстуры сигнатур для `codex` и `dsh` собраны с реальных ответов
- [ ] `doctor` проверяет, что каждое звено маршрута — существующий исполнитель X1

## Progress log
- 2026-09-27 — создан набросок спеки
