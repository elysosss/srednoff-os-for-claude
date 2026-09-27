# D1: Иерархия артефактов проекта — каркас, машинные инварианты, линтер ссылок

> Статус: DRAFT
> Тип: спека-набросок
> Модуль E1: `artifacts`
> Зависит от: E1   Блокирует: D2 (ссылки карточек на спек и якоря, раскладка `tasks/`), D5 (место `docs/adr/`, формат инвариантов в CONTRACT.md), D9 (прогон инвариантов в отчёте), D10 (файл `glossary.md`)

## Goal
В проекте-потребителе всё знание лежит в репозитории по предсказуемым путям (§1 плейбука), а связи «карточка → спек#якорь → ADR/модули» и «инвариант → команда проверки» проверяет машина: битая ссылка или инвариант без команды валят проверку, а не ждут, пока их заметит агент.

## User value
Сейчас в OS нет ни раскладки проектных документов, ни формата инвариантов: `.agent/TASK_TEMPLATE.md` и ExecPlan (правило 60) — прозаические шаблоны, связи между документами держатся на памяти агента. Закрыто, когда (а) `artifacts init` создаёт каркас, не трогая существующие файлы; (б) `artifacts lint` находит каждую битую ссылку и каждый инвариант без `check:`; (в) `invariants run` даёт PASS/FAIL/MANUAL по каждому инварианту, и доля MANUAL видна числом — это и есть счётчик «пожеланий» вместо правил.

## Non-goals
- Линтер глоссария (D10), линтер границ модулей (D6), метрики эрозии (D9), CI-проводка проверок (D8). D1 даёт им файлы и форматы, но не их логику.
- Формат ADR и CONTRACT.md — D5. Схема карточек — D2.
- Генерация содержимого `vision.md`/`architecture.md` агентом. Каркас создаёт пустые файлы с шапкой-подсказкой; заполняет человек (vision) или архитектор через ADR (architecture, D5).
- Раскладка самого форка OS: его `docs/specs/` — спеки расширений OS, к проектной иерархии отношения не имеют.

## Current state
- `scripts/init-claude-project.{ps1,sh}` копирует в проект только поверхность OS (CLAUDE.md, `.claude/**`, `.agent/**`); `docs/**` форка в проект **никогда** не попадает (явный allow-list в скрипте). Значит, проектные `docs/`, `tasks/` — территория нового модуля, а не init.
- Формат спек OS (`docs/specs/TEMPLATE.md`) заголовочными строками `> Зависит от:` показывает прецедент машинно читаемой шапки в markdown.
- В `skills-library/documentation-adrs` — общий 33-строчный шаблон рабочего процесса без форматов; для D1 он ничего конкретного не даёт.
- PowerShell 5.1 не имеет парсера YAML и читает файлы без BOM в ANSI-кодировке: все форматы D1 — markdown с построчными полями, читаются с явным `-Encoding UTF8`.

## Assumptions
- `ASSUMPTION:` слаг заголовка, который строит GitHub для кириллических заголовков (нижний регистр, пробел → `-`, пунктуация удаляется, кириллица сохраняется), воспроизводим одним регулярным выражением в `.ps1` и `.sh`. Проверить: 20 заголовков-фикстур, сравнить со ссылками, которые рендерит GitHub. Если не совпадёт — линтер признаёт только явные якоря `<a id="..."></a>`, а слаги из заголовков отключаются.
- `ASSUMPTION:` в проектах владельца `git` есть всегда (линтер берёт список файлов из `git ls-files`, чтобы не ходить в `node_modules`/`target`). Без git — отказ с кодом 3, а не обход всего дерева.

## Questions
1. Пути по умолчанию как в плейбуке (`docs/`, `tasks/`) или под префиксом (`docs/project/`)? По умолчанию — как в плейбуке, но все пути читаются из `config` модуля, и `init` отказывает, если `docs/specs/` уже существует с чужим содержимым без флага `--adopt`.

## GitHub research
| Repo | License | Что берём | Риск |
|---|---|---|---|
| `github/spec-kit` (push 2026-09-25) | MIT | Идею «конституция один раз на проект → спек на фичу → задачи»: наш `vision.md` + `invariants.md` играют роль конституции | У них конституция — проза; у нас инвариант без команды помечается MANUAL и считается |
| `MrLesk/Backlog.md` (push 2026-09-24) | MIT | Всё состояние проекта — markdown-файлы в репо, читаемые и человеком, и агентом | DoD у них — чеклист-проза, у нас — команда (D2) |

## Official docs checked
н/п для платформы: D1 не использует хуков и API Claude Code, только файлы и скрипты. Опирается на E1 (режим `off`, `config`, `doctor/checks.json`).

## Architecture (дизайн)
Три скрипта-пары в `bin/` модуля и шаблоны в `templates/`:
1. **`artifacts init`** — создаёт недостающее: `docs/{vision,architecture,invariants,glossary}.md`, `docs/adr/`, `docs/specs/_template.md`, `docs/specs/maintenance.md` (постоянный спек для техдолга и инструментов — чтобы правило «каждая карточка ссылается на спек» не имело исключений), `tasks/{backlog,active,blocked,done,returned}/.gitkeep`. Только создание; существующий файл не трогается никогда (сильнее, чем `init-claude-project`: даже без бэкапа-перезаписи). Папки `blocked/` и `returned/` — расширение плейбука, обоснование в D2.
2. **`artifacts lint`** — связи и форматы; вызывается D2 (`task validate`), D8 (CI) и вручную. Проверки L1–L7 ниже.
3. **`invariants run`** — прогон команд из `invariants.md` (и из разделов «Инварианты» всех CONTRACT.md, если стоит D5) через общий **исполнитель команд** `lib/cmd-runner.{ps1,sh}`; этот же исполнитель D2 использует для `done_when`.

Проверки линтера:
- L1 каждая ссылка `путь#якорь` из карточек (D2) и спек ведёт в существующий файл и существующий якорь (явный `<a id>` или слаг заголовка);
- L2 шапка спека содержит строки `> ADR:` и `> Modules:` (допустимо `—`); каждый ADR существует, статус не `Rejected`; `Superseded` — предупреждение с именем замены;
- L3 каждый модуль из `> Modules:` — каталог с `CONTRACT.md` (D5; канон модулей и рёбер — сами контракты, D6), иначе существующий каталог;
- L4 каждая относительная markdown-ссылка внутри `docs/` разрешается;
- L5 в `invariants.md` у каждого `## INV-NNNN` (и в разделе «Инварианты» каждого CONTRACT.md у `### INV-<module>-NNNN`, D5) ровно одно поле `check:`; `check: manual` требует `why-manual:`; id уникальны;
- L6 `vision.md` и `architecture.md` существуют и не пусты сверх шаблонной шапки (предупреждение);
- L7 каждый критерий приёмки спека имеет якорь (иначе на него нельзя сослаться из карточки).

Команды инвариантов исполняются так: `check:` запускается шеллом из `config.shell` (`auto` → bash, если найден, иначе PowerShell); для разных ОС допустимы `check.posix:` и `check.windows:`. Рабочий каталог — корень репо, таймаут — поле `timeout:` или 300 с, stdout/stderr — в `.claude/os-modules/.state/artifacts/runs/<ts>/`.

Отвергнуто: YAML-файл `invariants.yaml` (нет парсера в PowerShell 5.1, человеку хуже читать); инварианты только как тесты в коде (теряется список «что обязано быть правдой», который читает человек); обход всего дерева вместо `git ls-files` (медленно, ловит сгенерированное).

## API contracts (интерфейсы и форматы)
Формат `docs/invariants.md`:
```md
## INV-0003: sim/transport не зависит от render
- check: `cargo test -p boundaries -- transport_no_render`
- scope: sim/transport
- source: ADR-0007
## INV-0009: Кадр ощущается плавным
- check: manual
- why-manual: субъективная оценка, проверяет человек при приёмке фичи
```
Шапка проектного спека: `> ADR: ADR-0007, ADR-0012` и `> Modules: sim/transport` в первых 15 строках; критерий приёмки — `### <a id="stops"></a>Вместимость остановки`.
```text
artifacts-init.{ps1,sh}  [--project P] [--adopt] [--dry-run]
artifacts-lint.{ps1,sh}  [--project P] [--only L1,L5] [--json]
invariants-run.{ps1,sh}  [--project P] [--id INV-0003] [--scope <module>] [--json]
```
Коды выхода: 0 — всё хорошо; 1 — найдены нарушения / FAIL инварианта; 2 — модуль выключен (печатает `artifacts disabled`, ничего не делает); 3 — нет git или не парсится вход. JSON-вывод: `{overall, findings:[{rule, file, line, message}]}` / `{results:[{id, status: PASS|FAIL|MANUAL|TIMEOUT, durationSec}]}`.

## Data model / migrations
Проектные файлы (`docs/`, `tasks/`) — данные проекта, коммитятся, принадлежат проекту и **не удаляются** при `uninstall` модуля. Состояние модуля — только журналы прогонов в `.claude/os-modules/.state/artifacts/` (gitignored по E1), хранятся последние 20. Формат `invariants.md` версионируется строкой `<!-- invariants-format: 1 -->` в начале файла; неизвестная версия — отказ с сообщением.

## Security model
Защищаем: от молчаливо битых связей и от инвариантов-пожеланий, выдающих себя за проверки. `invariants run` исполняет команды из репо — это тот же уровень доверия, что `make test`; запускается только явно, никогда из хука. Не защищаем: от изменения самих инвариантов агентом (это задача D3: `docs/invariants.md` в глобальной защищённой зоне по умолчанию, и D8: изменение файла → high-risk).

## Risks
| Риск | Вероятность | Влияние | Митигация |
|---|---|---|---|
| Слаги якорей расходятся с GitHub | средняя | среднее | фикстуры; фолбэк на явные `<a id>` |
| Разный разбор `.ps1`/`.sh` (кодировки, CRLF) | средняя | среднее | общий набор фикстур, чтение UTF-8 явно, нормализация CRLF |
| Команды инвариантов медленные (минуты) | высокая | низкое | `--scope`, `--id`, таймауты; полный прогон — в CI (D8) |
| Каркас конфликтует с раскладкой проекта | средняя | низкое | только создание, `--dry-run`, пути из `config` |

## Acceptance criteria
- AC1: модуль в `off` — все три команды выходят с кодом 2 и ничего не пишут → S1.
- AC2: `init` в проекте с существующим `docs/vision.md` не меняет его ни на байт → S2.
- AC3: карточка со ссылкой на несуществующий якорь даёт находку L1 и код 1 → S3.
- AC4: инвариант без `check:` даёт L5; `check: manual` без `why-manual:` даёт L5 → S4.
- AC5: `invariants run` различает PASS/FAIL/MANUAL/TIMEOUT одинаково в PowerShell 5.1 и bash → S5.

## Testing plan
```gherkin
Scenario: S1 disabled module is a no-op
  Given the artifacts module is installed in mode "off"
  When I run artifacts-init, artifacts-lint and invariants-run
  Then each exits with code 2 and git status is unchanged
Scenario: S2 init never overwrites
  Given a project with docs/vision.md containing "our vision"
  When I run artifacts-init
  Then docs/vision.md is byte-identical and tasks/backlog exists
Scenario: S3 broken spec anchor
  Given docs/specs/transport.md without an anchor "stops"
  And a card referencing "docs/specs/transport.md#stops"
  When I run artifacts-lint
  Then the finding L1 names the card file and the exit code is 1
Scenario: S4 an invariant must name its check
  Given invariants.md with INV-0001 lacking "check:" and INV-0002 "check: manual" without "why-manual:"
  When I run artifacts-lint --only L5
  Then there are 2 findings L5
Scenario: S5 invariant statuses
  Given invariants with checks "exit 0", "exit 1", "manual" and a check sleeping past its timeout
  When I run invariants-run --json
  Then statuses are PASS, FAIL, MANUAL, TIMEOUT on both PowerShell 5.1 and bash
```
Юнит: слаги (фикстуры кириллица/латиница/пунктуация), разбор шапки спека. Вручную: `init` на реальном проекте владельца с `--dry-run`.

## Rollback plan
Режим `off` — команды ничего не делают. `uninstall` удаляет модуль и журналы прогонов; созданные `docs/` и `tasks/` остаются — это данные проекта, удаляются владельцем вручную, если нужно.

## Estimate (оценка объёма)
Каркас и шаблоны — 0.5 сессии; линтер L1–L7 парой `.ps1/.sh` с фикстурами — 1 сессия; `cmd-runner` + `invariants run` — 0.5–1 сессии. Итого 2–2.5 сессии. Взорвать может: слаги GitHub и кодировки PowerShell 5.1.

## План работ
Заполняется после аппрува.

## Definition of done
- [ ] Пары `.ps1/.sh` проходят паритет CI, в `.ps1` нет кириллицы; S1–S5 зелёные на Windows и Linux
- [ ] `doctor/checks.json` модуля: каркас на месте, `invariants.md` парсится
- [ ] `lib/cmd-runner` задокументирован как общий для D2

## Progress log
- 2026-09-27 — создан набросок спеки
