# D8: Гейты CI и ревью по риску

> Статус: DRAFT
> Тип: спека-набросок
> Модуль E1: `gates` (режимы `off | warn | enforce`, по умолчанию `off`). Полезная нагрузка — CI-шаблоны, которые ставятся в `.github/` потребителя через **правку E1 `ciTemplates`** (описана здесь)
> Зависит от: E1 (правка `ciTemplates`), D2 (риск карточки, перепрогон `done_when` и бюджет диффа в CI, `task show --json`), D3 (`scope-check` и `config.protected` — клиентская половина гейта 6), D5 (`adr-gate`), D6 (гейт 2, карта модулей из `CONTRACT.md` для гейта 3), D7 (риск по тестам), D10 (шаг гейта 1)   Блокирует: D9 (счётчик отключённых гейтов), приёмку D6/D7/D10 в CI

## Goal
Один переиспользуемый workflow в репо потребителя собирает гейты §6 брифа (1–7) в одну обязательную проверку; high-risk PR не мержится без аппрува человека; отключить гейт может только человек, только записью со ссылкой на карточку возврата и сроком — и это проверяется машиной, которую PR не может переписать.

## User value
Бриф §6: «Гейт падает → PR не мержится. Точка». Сейчас у потребителя CI нет вовсе, а в обычном CI агент может выключить проверку тем же PR (`if: false`, удалённый шаг), и PR это же и проверит. Закрыто, когда сценарии S1–S5 проходят на тестовом репо с включённой защитой ветки.

## Non-goals
- Не пишем сами проверки сборки/тестов/perf проекта — гейты 1, 3, 4, 5 вызывают **команды проекта** из конфига `gates`.
- Не запрещаем агенту запись файлов на клиенте — это D3; D8 — серверная сторона.
- Не автоматизируем изменение настроек репозитория без человека: скрипт защиты ветки по умолчанию только печатает, применение — явным запуском владельца.
- Не используем environments с required reviewers (для приватных репо на Free/Pro/Team недоступны — см. docs).

## Current state
CI самой OS (`.github/workflows/ci.yml`, 7 джоб) — пример гейтов, но в потребителя не ставится: `init-claude-project` явно исключает `.github/`. E1 пишет только в `<project>/.claude/`. Скиллы `ci-cd-automation`, `ci-failure-triage`, `principal-code-reviewer-agent` — проза; остаются инструкциями «как чинить упавший гейт» и «как ревьюить».

## Assumptions
- `ASSUMPTION:` защита веток и rulesets для **приватных** репо требуют платного плана (Pro/Team); на Free для приватного репо гейты D8 только советуют. Проверить: `gh api repos/{o}/{r}/branches/main/protection` на приватном репо Free-аккаунта; doctor обязан громко сказать «advisory only».
- `ASSUMPTION:` `GITHUB_TOKEN` в `pull_request_target` видит список файлов и ревью PR (`pulls/{n}/files`, `pulls/{n}/reviews`) с правами `pull-requests: read`. Проверить на тестовом репо.
- `ASSUMPTION:` чтение защиты ветки требует админ-прав, поэтому сверка дрейфа защиты идёт локально из-под `gh` владельца, а не в CI. Проверить: GET protection с `GITHUB_TOKEN`.
- `ASSUMPTION:` трейлер `Co-Authored-By: Claude` в коммитах есть по умолчанию; он выключается настройкой `attribution` (docs `managed-settings`), значит — только сигнал «PR писал агент», не механизм безопасности.

## Questions
1. **Q1. Идентичность агента.** GitHub не даёт автору аппрувить свой PR. Если агент пушит и открывает PR под учёткой владельца, (а) владелец не сможет аппрувить, (б) сервер не отличит агента от человека. По умолчанию — **отдельная машинная идентичность** для `gh` агента (GitHub App или machine user: `contents:write`, `pull_requests:write`, без `administration`), владелец — единственный в `approvers`. Если владелец откажется — «соло-режим»: аппрув = комментарий `/srednoff approve <sha>` от владельца, и doctor честно помечает гейт 7 как **пожелание**, потому что агент с теми же учётными данными может написать тот же комментарий; остаётся только клиентская страховка (deny-правила ниже).

## GitHub research
| Repo | License | Что берём | Риск |
|---|---|---|---|
| re-actors/alls-green (173★) | BSD-3-Clause | паттерн одной агрегирующей обязательной джобы над `needs` | реализуем сами на `needs.*.result`, без зависимости |
| smixs/code-quality | MIT | «агенту — один раунд на исправление, дальше человек» | паттерн |
| CI самой OS (`hook-canary`) | репо | проверка гейта синтетическим плохим входом | — |

## Official docs checked
GitHub docs, сверено 2026-09-27: `events-that-trigger-workflows` — `pull_request` исполняет workflow из **merge-коммита PR** (PR может править собственную проверку), `pull_request_target` — из **ветки по умолчанию**, с предупреждением не исполнять код PR; `about-protected-branches` — обязательные проверки проходят со статусом `successful`, **`skipped`** или `neutral`; есть «Require review from Code Owners» и распространение ограничений на админов; `deployments-and-environments` — required reviewers в environments только для публичных репо на Free/Pro/Team; `about-rulesets` — bypass-списки по ролям/командам/Apps. Claude Code: PF-28 (инструмент PowerShell мимо матчера `Bash`), A-18 (разбор составных команд), PF-16.

## Architecture (дизайн)
**Файлы в репо потребителя** (все под CODEOWNERS владельца):
- `.github/workflows/srednoff-gates.yml` — `on: workflow_call`; джобы `g1-build` … `g7-risk` + агрегатор `srednoff-gates-ok` (`if: always()`, падает, если любой ожидаемый гейт не `success`; ожидаемый набор берётся из конфига `gates`, поэтому `skipped` от подсунутого `if: false` = провал).
- `.github/workflows/srednoff-ci.yml` — вызывающий: `on: pull_request` и `pull_request_review`; `fetch-depth: 0` (нужно D7).
- `.github/workflows/srednoff-integrity.yml` — `on: pull_request_target`, **исполняется версия с ветки по умолчанию**; head PR не чекаутится, файлы PR читаются через API как данные; права `contents: read`, `pull-requests: read`.
- `.claude/os-modules/gates/config/project.json` (JSON, как `config/` E1 и D3: без парсера YAML в CI); управляемый блок в `.github/CODEOWNERS` между маркерами.
**Гейты:** g1 — `build`, `lint`, `format_check` проекта + D10; g2 — D6; g3 — изменённые файлы → модули по карте D6 → `unit_module` с подстановкой `{module}` (без D6 — `unit_all`), плюс перепрогон `done_when` карточки и бюджет диффа D2; g4 — `scenario`; «только через публичный API» проверяется механически, если `tests/scenario` оформлен модулем D6, а его `## Зависимости` разрешают рёбра только к модулям, чей `## Публичный API` (D5) — точка входа; g5 — `perf` проекта печатает `{metric: value}`, сравнение с `perf/budgets/*.json` (сами бюджеты — защищённая зона D7); g6 — `scope-check` D3 по диффу PR против карточки и `config.protected` → нарушение `forbidden`/`outside` валит гейт, задетая защищённая зона → риск high (серверная половина D3; обходы shell-слоя D3 ловятся здесь); g7 — risk-gate: `effective = max(risk карточки, D7, g6, D5 adr-gate, integrity)`. Карточка PR — файл, который этот PR переносит в `tasks/done/` (D2 двигает его `git mv`); нет такого файла — риск не ниже `medium` и строка «PR без карточки»; при high требуется ревью `APPROVED` от логина из `approvers`, на **текущем** head SHA, от не-автора.
**Integrity** (отдельная обязательная проверка): если PR меняет управляемые файлы (`.github/workflows/srednoff-*`, `.github/CODEOWNERS`, `.claude/os-modules/**` — там конфиги D3, D6, D7, D10 и этого модуля, `.claude/settings*.json`, `**/CONTRACT.md`, `docs/architecture.md`, `docs/glossary.md`) — риск high и требование аппрува; вызывает `adr-gate` D5 (правка контракта без принятого ADR — провал); валидирует записи `disabled`.
**Отключение гейта** — только запись `disabled` в конфиге `gates` (`gate, reason, card, until, approved_by`): карточка существует в `tasks/` и среди её `done_when` есть `cmd: gates-status --require-enabled <gate>` — возврат гейта и есть её Definition of Done, новых полей D2 не нужно; `until` не дальше 30 дней, просроченная запись валит integrity **на каждом PR**, пока гейт не вернут. Сам PR с записью — high-risk, значит — через человека.
**Защита ветки:** `gates-protect.{ps1,sh}` — по умолчанию печатает JSON для `PUT /branches/{b}/protection` (обязательные `srednoff-gates-ok` и `srednoff-integrity`, PR обязателен, code owners, сброс устаревших аппрувов, `enforce_admins: true`, без force-push и удаления); `-Apply` запускает только владелец. `gates-verify` — чтение и сверка дрейфа + `actions/permissions/workflow` → `can_approve_pull_request_reviews` должен быть `false`; вызывается из doctor (контракт проверок O1).
**Клиентская страховка** (не граница, а глубина защиты): deny-правила в settings-примере модуля на `Bash(gh pr merge *)`, `Bash(gh pr review *)`, `Bash(gh api *protection*)`, `Bash(gh api *rulesets*)` и те же для `PowerShell(...)` (PF-28); обход через составные команды и `curl` возможен (A-18).
**Правка E1 `ciTemplates`:** `metadata.srednoffOs.ciTemplates: [{src, dest}]`; `enable` копирует в `.github/…`, пишет sha256 в `installed.json`, **не перезаписывает** отличающийся файл (как `init-claude-project` с git-tracked); `disable` удаляет только файлы с совпавшим хэшем; каталоги CI-модулей в `.claude/os-modules/<id>/` коммитятся (скрипты нужны раннеру), `.state/` — нет. Caller-workflow перегенерируется из включённых модулей при `mode`.
Отвергнуто: reusable workflow из репо форка по `uses: owner/repo/...@sha` — для приватного потребителя нужен доступ к форку и сеть; копия в репо проще аудировать. Environments — план (см. docs).

## API contracts (интерфейсы и форматы)
```json
{ "schema": 1,
  "commands": { "build": "make build", "lint": "make lint", "format_check": "make fmt-check", "unit_all": "make test",
                "unit_module": "make test-mod MOD={module}", "scenario": "make test-scenario", "perf": "make perf-json" },
  "approvers": ["owner-login"], "identity": "machine",
  "disabled": [ { "gate": "g5", "reason": "perf stand down", "card": "T-0201", "until": "2026-10-15", "approved_by": "owner-login" } ] }
```
`gates-status [--require-enabled G]` печатает включённые гейты и код 1, если G отключён.
Коды скриптов: `0` ок, `1` гейт не пройден, `2` конфиг невалиден. `risk.json` (артефакт): `{effective, sources:[{from, level, reason}]}`.

## Data model / migrations
Всё состояние — в репо потребителя и в GitHub (ревью, статусы). `schema` целое в конфиге `gates`; перегенерация шаблонов — через `installed.json`.

## Security model
Защищаем от: агент выключил гейт в том же PR (`if: false`, удалил шаг, поменял команду) — integrity из ветки по умолчанию + CODEOWNERS + агрегатор с ожидаемым набором; агент снял метку риска — risk-gate пересчитывает сам; аппрув устаревшего SHA — только текущий head. Не защищаем: соло-режим (Q1); владелец сам ослабил защиту; агент с админ-токеном владельца меняет настройки репо через API (закрывается только машинной идентичностью без `administration`); приватный репо на Free (допущение про план).

## Risks
| Риск | Вероятность | Влияние | Митигация |
|---|---|---|---|
| Соло-идентичность делает гейт 7 пожеланием | высокая | высокое | Q1: машинная идентичность по умолчанию; doctor пишет WARN |
| `pull_request_target` исполняет код PR по ошибке шаблона | низкая | высокое | шаблон без checkout head; канарейка в CI OS: PR-фикстура с вредным скриптом не запускается |
| Длинный CI тормозит серийную работу | средняя | среднее | g3 только по затронутым модулям |
| Дрейф защиты ветки после ручных правок | средняя | высокое | `gates-verify` в doctor |

## Acceptance criteria
1. Подсунутый `if: false` или удалённый шаг гейта не даёт зелёного мержа — S1.
2. Отключение гейта без карточки или просроченное — провал integrity — S2, S3.
3. High-risk PR требует аппрув человека на текущем SHA — S4.
4. `gates-protect` без `-Apply` ничего не меняет — S5.

## Testing plan
```gherkin
Scenario: S1 агент выключил гейт в своём PR
  Given тестовый репо с включённой защитой ветки и srednoff-gates-ok обязательной
  And PR добавляет "if: false" к джобе g3-unit
  When отрабатывают srednoff-ci и srednoff-integrity
  Then srednoff-gates-ok падает с причиной "g3-unit: skipped, expected success"
  And srednoff-integrity помечает PR high-risk "gate workflow changed"

Scenario: S2 отключение без карточки возврата
  Given PR добавляет в конфиг gates запись disabled g5 с card T-0999
  And файла tasks/*/T-0999.yaml нет
  When отрабатывает srednoff-integrity
  Then проверка падает с причиной "disabled g5: card T-0999 not found"

Scenario: S3 просроченное отключение валит любой PR
  Given в конфиге gates на ветке по умолчанию запись disabled g5 until 2026-09-01
  When открыт PR, меняющий только README.md
  Then srednoff-integrity падает с причиной "disabled g5 expired"

Scenario: S4 аппрув устаревшего коммита не считается
  Given PR с эффективным риском high и аппрувом owner-login на коммите A
  When в PR запушен коммит B
  Then g7-risk падает до нового аппрува owner-login на коммите B

Scenario: S5 защита ветки без явного применения
  Given репо без защиты ветки
  When запускаю gates-protect без -Apply
  Then печатается JSON запроса и в GitHub ничего не изменилось
```
Сценарии S1–S4 — на отдельном тестовом репо (живые прогоны Actions), S5 и генерация шаблонов — behave локально на обеих ОС. Шаблоны проверяются actionlint в CI OS.

## Rollback plan
`os-module mode gates off` (PR под CODEOWNERS) → caller-workflow удаляется, обязательные проверки снимает владелец (`gates-protect -Remove -Apply`), иначе PR повиснут в ожидании. `uninstall` удаляет только неизменённые шаблоны.

## Estimate (оценка объёма)
Правка E1 `ciTemplates` — 1 сессия; шаблоны gates/ci/integrity + агрегатор — 1,5; risk-gate и `disabled` — 1; `gates-protect`/`gates-verify` ps1+sh — 1; тестовый репо и S1–S5 — 1. Итого **≈ 5,5 сессии**. Взорвать может: план GitHub владельца (приватные репо на Free), решение по Q1.

## План работ
Заполняется после аппрува.

## Definition of done
- [ ] S1–S5 зелёные; шаблоны проходят actionlint.
- [ ] doctor показывает дрейф защиты и режим идентичности.
- [ ] Правка E1 `ciTemplates` принята в спеку E1.

## Progress log
- 2026-09-27 — создана спека-набросок
