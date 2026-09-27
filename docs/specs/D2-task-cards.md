# D2: Карточки атомарных задач — схема, валидатор, CLI `task`, жизненный цикл

> Статус: DRAFT
> Тип: спека-набросок
> Модуль E1: `tasks` (`requires.modules: ["artifacts"]`)
> Зависит от: E1, D1 (раскладка `tasks/`, линтер ссылок, `cmd-runner`)   Блокирует: D3 (источник `touch_allowed`/`forbidden`), D4 (карточка — единица работы ролей), D5 (статус `blocked`), D8 (перепрогон `done_when` и бюджет диффа в CI), D9 (попытки, возвраты, объём контекста)

## Goal
Атомарная задача (§2 плейбука) — YAML-карточка в `tasks/<статус>/`, которую машина проверяет до старта (схема, граф, ссылки, область), при старте (одна активная на модуль, лимит попыток) и при закрытии (`done_when` зелёный, дифф в бюджете и в области). Статус — это папка, двигает её только CLI `task`.

## User value
Сейчас `.agent/TASK_TEMPLATE.md` — прозаический промпт, «Done when» в нём — фраза, которую никто не исполняет. Закрыто, когда карточку нельзя закрыть, пока её команды не зелёные, нельзя начать третью попытку, нельзя начать вторую карточку в том же модуле, и всё это видно по коду выхода, а не по добросовестности агента.

## Non-goals
- Трекер с UI, доски, оценки в часах, импорт из GitHub issues (зеркало — только наружу). Автоматическая декомпозиция спека — работа планировщика (D4), D2 только валидирует результат.
- Замена ExecPlan: ExecPlan (правило 60, `.agent/PLANS.md`) остаётся планом **фичи**; карточка — атом внутри него. Если карточке понадобился бы свой ExecPlan (> 30 мин, несколько модулей), она не атомарна — сигнал на передробление. Параллельная работа по умолчанию (ограничение 4): `maxActive: 1`, параллелизм по модулям — выключенная возможность.

## Current state
- `.agent/TASK_TEMPLATE.md`: Goal / Constraints / Done when прозой. Связь: `task brief <id>` рендерит карточку **в форму этого шаблона** (цель из `title` + якорь спека, «Что нельзя менять» из `forbidden`, Done when — список команд), чтобы свежая сессия получала знакомый промпт. Шаблон не меняется.
- D1 (набросок) создаёт `tasks/{backlog,active,blocked,done,returned}/` и `lib/cmd-runner`. Плейбук называет три папки; `blocked/` (ждёт ADR, D5) и `returned/` (ждёт передробления) добавлены, потому что обе группы **нельзя стартовать**, и папка делает это проверяемым без чтения полей.
- В PowerShell 5.1 нет парсера YAML; Python в OS-скриптах не используется. Внутренние задачи Claude Code (`TaskCreated`/`TaskCompleted`) — его список дел, к карточкам отношения не имеют.

## Assumptions
- `ASSUMPTION:` рабочие деревья, которые создаёт Claude Code (`isolation: worktree` у сабагента, `--worktree`), — обычные `git worktree` с общим `git rev-parse --git-common-dir`; тогда замок модуля в общем каталоге git виден всем деревьям одного клона. Проверить: `git worktree list` и `git rev-parse --git-common-dir` из сабагента с `isolation: worktree`.
- `ASSUMPTION:` подмножество YAML ниже покрывает все карточки плейбука без потерь (пример из §2 разбирается им целиком — проверено вручную по тексту; при переходе в полную спеку — фикстурой).

## Questions

**Решено владельцем 2026-09-27:** строгое подмножество YAML с парным парсером `.ps1`/`.sh`, без PyYAML.

1. Можно ли зависеть от Python (PyYAML) ради полного YAML? По умолчанию **нет**: строгое подмножество YAML с парным парсером `.ps1/.sh`; всё вне подмножества — ошибка валидатора, а не тихий неверный разбор. 2. Коммитит ли `task` переходы сам? По умолчанию нет (`autoCommit: false`): `git mv` в индекс, коммитит владелец или исполнитель в составе PR.

## GitHub research
| Repo | License | Что берём | Риск |
|---|---|---|---|
| `MrLesk/Backlog.md` (push 2026-09-24, 6.8k★) | MIT | Задача = файл в репо; «плохой результат → уточнить задачу и перезапустить в **свежей** сессии»; зависимости и «кто кого ждёт» | DoD — чеклист-проза; у нас каждый пункт — команда или проверка файла |
| `github/spec-kit` (push 2026-09-25) | MIT | Цепочка spec → plan → tasks, пометка параллелизуемых задач | задачи — строки markdown без схемы; не берём |
| `eyaltoledano/claude-task-master` (push 2026-04-28) | «Task Master License» (MIT с доп. условиями — не сверялись) | Граф зависимостей задач и «следующая доступная задача» | код не берём из-за лицензии |

## Official docs checked
н/п для хуков: D2 — скрипты и файлы. PF-24 учтён для корня репо в worktree (CLI берёт корень из `git rev-parse --show-toplevel`, не из `CLAUDE_PROJECT_DIR`).

## Architecture (дизайн)
**Схема карточки** (`tasks/<status>/T-0142.yaml`, имя файла = `id`):
```yaml
id: T-0142
title: Вместимость автобусной остановки
spec: docs/specs/public-transport.md#stops
module: sim/transport
also_modules: []            # не больше одного; только тесты или контракт (§2)
kind: impl                  # impl | test | refactor | contract | golden
depends_on: [T-0139]
context_files: [sim/transport/CONTRACT.md, sim/transport/stop.rs]
touch_allowed: [sim/transport/**, tests/transport/**]
forbidden: [tests/golden/**]
done_when:
  - cmd: make test-mod MOD=transport
  - new_test: tests/transport/test_stop_capacity.rs
risk: low                   # low | medium | high
adr: []                     # D5
diff_budget: 400            # необязательно; выше config.diffBudget.fail требует diff_budget_reason
attempts: 0                 # поля ниже пишет только task
returns: []                 # [{at, reason}]
```
Подмножество YAML: скаляры в одну строку, списки скаляров (`[a, b]` или `- a`), списки однострочных отображений (`- cmd: ...`); без якорей, многострочных скаляров, вложенности глубже двух уровней. Файлы — UTF-8, CRLF нормализуется. Служебные поля `blocked_by` (D5), `replaces` и `github_issue` (зеркало) тоже пишет только `task`.

**Валидатор** (`task validate [<id>|--all]`): V1 поля и типы по схеме, неизвестный ключ — ошибка; V2 `id` уникален во всех папках и совпадает с именем файла; V3 `depends_on` существует, граф ациклический (топосорт), все зависимости стартуемой карточки в `done/`; V4 `spec` и якорь — через `artifacts lint` L1 (D1); V5 каждый `context_files` существует; `module` — каталог с `CONTRACT.md` (D5, он же модуль для D6), иначе существующий каталог; V6 `touch_allowed` не пуст, у каждого шаблона неподвижный префикс лежит внутри `module`, `also_modules` или `config.testRoots`, иначе «карточка не в одном модуле»; V7 `done_when` содержит хотя бы один `cmd`; первое слово каждого `cmd` находится (`Get-Command` / `command -v`); `new_test` лежит внутри `touch_allowed` и на момент старта не существует; V8 `forbidden` ∩ `touch_allowed` пусто по фикстурному матчеру D3; V9 минимальный риск вычисляется: `kind: contract|golden`, `touch_allowed` задевает `**/CONTRACT.md` или глобальную защищённую зону (D3) → `risk` не ниже `high`, заниженный — ошибка; V10 прокси «влезает в контекст»: сумма байт `context_files` + секции спека ≤ `config.contextBudgetBytes` (по умолчанию 160 КБ) — **предупреждение**, это оценка, а не токены.

**Машина состояний** (двигает только `task`, файлы — `git mv`):
| Переход | Команда | Условия (машинные) |
|---|---|---|
| backlog → active | `task start` | V1–V9 зелёные; активных < `maxActive` (по умолчанию 1); замок модуля свободен; `attempts < 2` |
| active → done | `task done` | все `done_when` зелёные через `cmd-runner`; дифф от базы в бюджете; `scope-check` D3 чист; `adr-gate` D5 чист |
| active → backlog | `task return --reason` | `attempts++`, запись в `returns`; при `attempts ≥ 2` — сразу в `returned/` |
| active → blocked | `task block --adr` | D5 создаёт черновик ADR, `blocked_by` заполнен |
| blocked → backlog | `task unblock` | ADR из `blocked_by` в статусе `Accepted` (D5) |
| returned → (удаление) | `task split <id> --into T-…` | новые карточки валидны; исходная удаляется, id записывается в `replaces:` новых |

Попытка = один `task start`. Карточка, найденная в `active/` при новом `task start --retry` (сессия умерла без `done`), считается проваленной попыткой. Третьей попытки нет: «провал = информация» (§3) реализуется отказом `start`, а не текстом.
- **Замок модуля**: файл `<git-common-dir>/srednoff-tasks/locks/<module-slug>.lock` (`{card, pid, host, since}`), общий для всех worktree клона; снимается `done/return/block`, протухший (> `config.lockTtlHours`) снимает `doctor --fix`. Между машинами замок не действует — там страховка D8 (CI: две открытые PR с активными карточками одного модуля → предупреждение). Кроме замка, `task start` пишет **указатель активной карточки** в собственный (не общий) каталог git рабочего дерева: `<git-dir>/srednoff-tasks/active-card` с `id`. По нему хук D3 узнаёт карточку своего дерева, не угадывая по сессии; `done/return/block` указатель удаляют.
- **Бюджет диффа**: `git diff --numstat <base>...HEAD` + неотслеживаемые файлы, минус `config.diffBudget.exclude` (lock-файлы, сгенерированное; сам `config` модуля — защищённая зона D3, чтобы бюджет не обходили расширением `exclude`); `warn` 300, `fail` 400 строк (добавлено + удалено). На этапе планирования объём диффа неизвестен — проверяется только при `done` и в CI; честно.
- **Зеркало в GitHub issues** (выключено, `mirror: off`): `task mirror <id>` создаёт или обновляет issue с телом «канон — `tasks/…/T-0142.yaml`» и номером в `github_issue`. Односторонне; `gh issue create/edit` проходит через X4 как запись (`ask`).
- Отвергнуто: статус полем внутри файла (расходится с папкой; два источника правды); JSON-карточки (хуже читать и ревьюить человеку); замок в `.claude/os-modules/.state` (разный в каждом worktree).

## API contracts (интерфейсы и форматы)
```text
task new --module M --spec PATH#ANCHOR --title T        -> tasks/backlog/T-NNNN.yaml (следующий свободный id)
task validate [ID|--all] [--json]    task graph [--next]    task brief ID
task start ID [--retry]   task check ID   task done ID [--base REF]   task return ID --reason TEXT
task block ID --adr TITLE (D5)   task unblock ID   task split ID --into ID,ID   task mirror ID
```
Вызов — `${CLAUDE_PROJECT_DIR}/.claude/os-modules/tasks/bin/task.{ps1,sh}` (как в X1: `bin/` модуля не в `PATH`), плюс команда `/task`. Коды выхода: 0 успех; 1 нарушение валидации или красный `done_when`; 2 модуль выключен; 3 замок занят / лимит активных; 4 лимит попыток исчерпан; 5 зависимость не в `done/`; 6 `task done` отклонён архитектурным гейтом D5 (`needs-adr`).

## Data model / migrations
Карточки — данные проекта, коммитятся. История для D9 берётся из `git log` перемещений в `tasks/` и поля `returns`, отдельного журнала событий нет (не конфликтует при слиянии веток). Состояние модуля: замки (общий каталог git), логи прогонов `done_when` — `.claude/os-modules/.state/tasks/runs/`. Схема версионируется ключом `schema: 1` в `config`; карточка без поля `schema` читается как 1.

## Security model
Защищаем: от «сделал не то, но убедительно объяснил» — закрытие только по коду выхода команд; от ослабления DoD — CI (D8) сравнивает `done_when`, `touch_allowed`, `forbidden`, `risk` карточки с версией в базовой ветке: для карточки, существовавшей в базе, меняться могут только папка и поля `attempts/returns/blocked_by`, иначе PR получает high-risk. Сами файлы `tasks/**` для роли исполнителя — защищённая зона D3; CLI работает процессом, не инструментами Edit/Write. Не защищаем: исполнитель может вызвать `git mv` руками через Bash — CI перепрогоняет `done_when` у каждой карточки, попавшей в `done/` в этом PR. `done_when` исполняет команды из репо: уровень доверия `make test`, запуск только явный, никогда из хука.

## Risks
| Риск | Вероятность | Влияние | Митигация |
|---|---|---|---|
| Самописный разбор YAML ошибается молча | средняя | высокое | строгое подмножество, всё прочее — ошибка; общий набор фикстур `.ps1/.sh` |
| Замок висит после падения сессии | высокая | низкое | TTL + `doctor --fix`; `task start --retry` видит мёртвую попытку |
| `new_test` проверяет существование, а не качество теста | высокая | среднее | ослабление тестов — D7; качество — ревьюер (D4) |

## Acceptance criteria
- AC1: цикл `depends_on` и ссылка на несуществующий якорь дают ошибки V3/V4 → S1.
- AC2: вторая карточка того же модуля не стартует (код 3), в том числе из другого worktree → S2.
- AC3: `task done` с красной командой не двигает карточку (код 1) → S3.
- AC4: после двух возвратов карточка в `returned/`, `start` даёт код 4 → S4.
- AC5: модуль в `off` — `task` печатает `tasks disabled`, код 2, файлы не двигаются → S5.

## Testing plan
```gherkin
Scenario: S1 invalid graph and anchor
  Given cards T-0001 and T-0002 depending on each other and T-0003 with spec "docs/specs/x.md#missing"
  When I run task validate --all
  Then findings are V3 for T-0001 and V4 for T-0003 and the exit code is 1
Scenario: S2 one active card per module across worktrees
  Given T-0010 in module "sim/transport" is started in the main worktree
  When I run task start T-0011 of module "sim/transport" in a second git worktree
  Then the exit code is 3 and T-0011 stays in backlog
Scenario: S3 red done_when blocks closing
  Given active T-0012 with done_when cmd "exit 1"
  When I run task done T-0012
  Then the exit code is 1 and T-0012 is still in tasks/active
Scenario: S4 two failures send the card back to the planner
  Given T-0013 was returned once
  When I start T-0013 and run task return T-0013 --reason "tests flaky"
  Then T-0013 is in tasks/returned with attempts 2 and task start T-0013 exits with code 4
Scenario: S5 disabled module
  Given the tasks module is in mode "off"
  When I run task start T-0014
  Then the exit code is 2 and git status is unchanged
```
Юнит: парсер подмножества YAML (включая отказ на якорях и `|`-скалярах), топосорт, матчер шаблонов (общий с D3). Вручную: полный цикл одной карточки на Windows 10 в десктопе 2.1.281.

## Rollback plan
`off` — CLI отвечает «disabled». `uninstall` удаляет модуль, замки (`<git-common-dir>/srednoff-tasks/`) и логи; карточки остаются как данные проекта.

## Estimate (оценка объёма)
Парсер подмножества YAML парой + фикстуры — 1 сессия; валидатор V1–V10 — 1; CLI и машина состояний, замки, бюджет — 1.5; `brief`, `mirror`, сценарии S1 (run-evals)–S5 на двух ОС — 1. Итого 4.5 сессии. Взорвать может: паритет парсера YAML в bash 3.2 (macOS) и поведение `git mv` с кириллицей в путях на Windows.

## План работ
Заполняется после аппрува.

## Definition of done
- [ ] Пары `.ps1/.sh` проходят паритет CI, в `.ps1` нет кириллицы; S1–S5 зелёные на Windows и Linux
- [ ] Пример карточки из §2 плейбука проходит `task validate` без правок; `doctor` модуля: протухшие замки, карточки в `active/` без замка и наоборот

## Progress log
- 2026-09-27 — создан набросок спеки
