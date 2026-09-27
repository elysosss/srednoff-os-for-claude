# D6: Линтер границ модулей и графа зависимостей

> Статус: DRAFT
> Тип: спека-набросок
> Модуль E1: `boundaries` (режимы `off | warn | enforce`, по умолчанию `off`); CI-джоба ставится через правку E1 `ciTemplates`, описанную в D8
> Зависит от: E1, D5 (модуль = каталог с `CONTRACT.md`; раздел `## Зависимости` со строками `- allow: <module>` — источник разрешённых рёбер; правка раздела требует ADR), D1 (`docs/architecture.md`), D8 (доставка в CI, контроль файлов гейта)   Блокирует: D8 (гейт 2, карта «файл → модуль» для гейта 3), D9 (новые рёбра), D10 (публичные пути модулей)

## Goal
Разрешённые рёбра между модулями потребительского проекта уже записаны в `CONTRACT.md` каждого модуля (формат D5). D6 строит фактический граф зависимостей штатными инструментами языка и валит PR на любом ребре, которого нет в `## Зависимости`; тот же прогон отдаёт список рёбер для D9.

## User value
Бриф §4: эрозия идёт «чуть-чуть через границу в каждом PR», а правило в `architecture.md` агент прочитает не всегда. Закрыто, когда новое ребро не проходит мерж без правки `CONTRACT.md`, а правка `CONTRACT.md` не проходит без принятого ADR и аппрува человека (D5 `adr-gate`, D8).

## Non-goals
- Свой парсер импортов на каждый язык: зовём инструменты экосистемы, своё — только нормализация и сравнение.
- Сторонние зависимости (лицензии, CVE, минимализм) — это `dependency-minimalism-gate`, `supply-chain-sbom-sca`, cargo-deny `licenses/advisories`.
- Перестройка проекта в физические модули: D6 даёт метрику «модуль только логический» и совет; перестройка — карточки D2.
- Граф внутри одного модуля — вне v1 (кандидат: cargo-modules для Rust).

## Current state
В OS ничего про граф потребительского проекта нет. Скилл `monorepo-boundary-architecture` — прозаический чеклист («Do not introduce cross-package dependencies»), то есть пожелание; D6 — его машинная половина, скилл остаётся инструкцией «как чинить», когда гейт упал. D5 уже задаёт формат `## Зависимости` и считает манифесты (`Cargo.toml`, `pyproject.toml`, `go.mod`, `package.json`) архитектурно-чувствительными путями. CI самой OS (`hook-canary`) — образец проверки синтетическим плохим входом, его повторяем фикстурами.

## Assumptions
- `ASSUMPTION:` grimp строит граф статическим разбором, не импортируя код проекта, значит безопасен на недоверенном PR. Проверить: фикстура с `raise` на уровне модуля.
- `ASSUMPTION:` `cargo metadata --format-version 1` перечисляет path-зависимости членов workspace с полем `path` и не запускает `build.rs`. Проверить: фикстура из трёх крейтов и `build.rs`, пишущий файл-маркер.
- `ASSUMPTION:` `go list -json ./...` с `GOFLAGS=-mod=mod GOPROXY=off` отдаёт `Imports` без сети, если зависимости в кэше или vendor; иначе адаптер падает кодом 3, а не пропускает. Проверить в чистом контейнере.
- `ASSUMPTION:` у tach есть машинный вывод нарушений; если нет — tach используется только как «проект уже на tach»: сверка дрейфа `tach.toml` против `CONTRACT.md`. Проверить `tach check --help`.

## Questions

**Решено владельцем 2026-09-27:** ядро D6/D7/D10 — **парные `.ps1`/`.sh`**, как все скрипты OS; Python в ядро не вводится. Уточнение: адаптер языка может вызывать штатный инструмент самого проверяемого проекта (для Python-проекта — его интерпретатор и `ast`, для Go — `go list`), это зависимость проекта, а не OS. Оценка ниже пересчитана с учётом парности (≈ ×1.8 к ядру).

1. **Q1. Язык ядра D6/D7/D10.** D2 решил «Python в скриптах OS не используется» для карточек — это ядро рабочего цикла. D6, D7, D10 — анализаторы кода в CI (раннер ubuntu, `python3` есть), им нужны `ast`, `difflib`, разбор JSON инструментов. Предлагается: ядро на **Python ≥ 3.11, только stdlib**, `.ps1`/`.sh` — тонкие запускатели; конфиги — JSON (как `config/` E1 и D3), YAML не читаем, карточки берём через CLI D2 с `--json`. Если ответа нет — так; если владелец против — двойная реализация `.ps1`/`.sh`, оценки D6/D7/D10 ×1,8, AST-правила вырождаются в регэкспы.
2. **Q2.** Файл вне всех модулей — `warn` или ошибка? По умолчанию `warn`, настраивается.

## GitHub research
| Repo | License | Что берём | Риск |
|---|---|---|---|
| seddonym/import-linter (1.2k★, push 2026-09-16) | BSD-2-Clause | словарь контрактов `layers/independence/forbidden` для сообщений | контракты — чёрный список; у нас белый |
| python-grimp/grimp (движок import-linter) | BSD-2-Clause | **адаптер Python по умолчанию**: граф прямых импортов | 134★, малое сообщество |
| tach-org/tach (2.8k★, push 2026-09-15) | MIT | модель `modules + depends_on` = наша; режим «проект уже на tach» | смена владельца gauge-sh → tach-org |
| sverweij/dependency-cruiser (7.2k★) | MIT | адаптер JS/TS, `--output-type json` | только JS/TS |
| EmbarkStudios/cargo-deny (2.4k★) | Apache-2.0 | `bans.deny[].wrappers` для внешних крейтов — по желанию | не граф workspace |
| fe3dback/go-arch-lint (579★) | MIT | альтернатива адаптеру `go list` | лишний бинарь |
| OpenPeeDeeP/depguard (202★) | GPL-3.0 | ничего: чёрный список пакетов по файлам, не граф | не та модель; код не берём |
| TNG/ArchUnit (3.8k★) | Apache-2.0 | идея «правила архитектуры как тесты» | JVM вне приоритета |
| hashicorp/terraform-config-inspect | MPL-2.0 | адаптер Terraform: `module_calls[].source` локальных модулей | только Terraform |

Решение: **Adapt** — свой сравнитель рёбер + адаптеры над штатными инструментами. **Avoid** — собственный парсер импортов.

## Official docs checked
н/п для Claude Code: проверка идёт в CI и локальной командой, хуков нет. Документация инструментов сверяется при реализации каждого адаптера.

## Architecture (дизайн)
`модули (CONTRACT.md) → adapter(lang) → edges (нормализованные) → compare → report.json + код выхода`.
- **Модули**: каталоги с `CONTRACT.md` (D5), id = путь от корня. Язык определяется манифестом в каталоге (`Cargo.toml` → rust, `pyproject.toml`/`__init__.py` → python, `go.mod`/`*.go` → go, `package.json` → ts, `*.tf` → terraform), переопределяется в конфиге.
- **Адаптеры** (отдельные процессы; выход `[{from_path, to_path, evidence}]`): `python` (grimp; tach по выбору), `rust` (`cargo metadata`; компилятор уже запрещает необъявленное — проверяется манифест), `go` (`go list -json`, сопоставление по префиксу import path; `internal/` отмечается как физическая граница), `ts` (dependency-cruiser), `terraform` (terraform-config-inspect), `generic` (регэксп строк импорта — последний резерв, помечается «не физическая граница»).
- **Нормализатор**: пути/пакеты → id модулей, рёбра модуль→модуль со счётчиком и до 5 примеров `file:line`.
- **Сравнитель**: ребра нет в `## Зависимости` источника и цель не в `shared` → нарушение; цикл → нарушение; разрешённое, но неиспользуемое → `info`; файл вне модулей → `unmapped`. С `--base <ref>` — ещё «новые рёбра относительно merge-base»; их читает D9.
- **Физичность**: модуль без собственного манифеста (Python-пакет внутри общего `pyproject`, Go-пакет внутри общего `go.mod`) → `logical_only` с советом: Rust — крейт workspace; Python — пакет uv-workspace (и линтер всё равно нужен: импорт из того же окружения проходит); Go — отдельный module или `internal/`; TS — project references с `exports`.
Отвергнуто: отдельный `modules.yaml` рядом с `CONTRACT.md` (два источника правды; D5 уже требует ADR на правку контракта); tree-sitter-парсер на все языки (резолв импортов пришлось бы писать самим); генерация контрактов import-linter (белый список = O(n²) запретов).

## API contracts (интерфейсы и форматы)
Рёбра — в `CONTRACT.md` модуля (формат D5): `## Зависимости` → `- allow: sim/core`. Проектный конфиг `.claude/os-modules/boundaries/config/project.json` (коммитится, файл гейта D8):
```json
{ "schema": 1, "unmapped": "warn", "cycles": "forbid", "shared": ["shared/util"],
  "exclude": ["vendor/**", "**/generated/**"], "langOverride": { "tools/etl": "python" },
  "adapters": { "python": "grimp", "rust": "cargo-metadata", "go": "go-list", "ts": "depcruise", "terraform": "tf-inspect" } }
```
Команда `boundary-check.{ps1,sh} [-Project P] [-Base REF] [-Json]`. Коды: `0` ок (в `warn` — всегда, с аннотациями); `1` нарушения; `2` конфиг или `CONTRACT.md` невалиден; `3` нет нужного инструмента (в CI — провал, fail-closed). `report.json`: `{schema, commit, base, modules:[{id, lang, physical}], edges:[{from,to,count,evidence[]}], new_edges:[...], violations:[{kind,from,to,evidence[]}], unmapped:[...]}`.

## Data model / migrations
Правда — в `CONTRACT.md` и конфиге в репо. Снимки рёбер — `.claude/os-modules/.state/boundaries/edges-<date>-<sha7>.json` (gitignored, для D9); в CI — артефакт джобы. Неизвестная `schema` → код 2 без попытки угадать.

## Security model
Защищаем от: агент добавил ребро (гейт) или «разрешил» его правкой `CONTRACT.md`/конфига (D5 `adr-gate` + CODEOWNERS и integrity D8; локально — самозащита `.claude/os-modules/**` в D3 шаг 3). Адаптеры не исполняют код проекта (допущения выше). Не защищаем от динамических импортов (`importlib`, `reflect`, `require(var)`) — слепая зона пишется в отчёт; `generic`-поиск `importlib`/`__import__` даёт предупреждение.

## Risks
| Риск | Вероятность | Влияние | Митигация |
|---|---|---|---|
| Динамические импорты мимо графа | средняя | среднее | слепая зона в отчёте; предупреждение `generic` |
| `cargo metadata`/`go list` лезут в сеть в CI | средняя | среднее | офлайн-флаги, код 3 вместо пропуска |
| Агент правит `CONTRACT.md` вместе с кодом | высокая | высокое | D5 `adr-gate` + D8 |
| Поток `unmapped` на старте | высокая | низкое | `warn`; `boundary-check --suggest` печатает каталоги-кандидаты в модули |

## Acceptance criteria
1. Новое межмодульное ребро на фикстуре каждого адаптера → код 1 с `file:line` — S1.
2. Разрешение ребра правкой `CONTRACT.md` без ADR не проходит (вместе с D5/D8) — S2.
3. Нет инструмента в `enforce` → код 3 — S3.
4. `--base` отдаёт только новые рёбра — S4.
5. Одинаковый `report.json` из `.ps1` и `.sh` — S5.

## Testing plan
```gherkin
Scenario: S1 новое ребро валит проверку
  Given фикстура python с модулями "billing" и "ui", в ui/CONTRACT.md "- allow: billing"
  And в billing/api.py добавлен "from ui.widgets import Button"
  When запускаю boundary-check в режиме enforce
  Then код выхода 1 и нарушение "billing -> ui" с evidence "billing/api.py:1"

Scenario: S2 разрешение ребра без ADR
  Given PR добавляет "- allow: ui" в billing/CONTRACT.md и поле adr карточки пусто
  When CI выполняет гейты D8
  Then adr-gate D5 помечает PR "architecture-without-adr" и risk-gate D8 требует аппрув человека

Scenario: S3 нет инструмента — не молчим
  Given фикстура rust и в PATH нет cargo
  When запускаю boundary-check в режиме enforce
  Then код выхода 3 и сообщение называет отсутствующий инструмент

Scenario: S4 новые рёбра относительно базы
  Given в base есть ребро "a -> b", в head добавлено разрешённое "a -> c"
  When запускаю boundary-check --base base --json
  Then new_edges содержит ровно "a -> c" и код выхода 0

Scenario: S5 парность запускателей
  Given фикстура go из трёх пакетов с CONTRACT.md
  When запускаю boundary-check.ps1 и boundary-check.sh с --json
  Then отчёты совпадают после удаления поля времени
```
Юнит-тесты нормализатора и сравнителя; фикстуры-проекты по языку в `modules/boundaries/tests/fixtures/`. Ручное: неделя в `warn` на проекте владельца (Python + Terraform).

## Rollback plan
`os-module mode boundaries off` → D8 перегенерирует вызывающий workflow без джобы; `uninstall` удаляет скрипты и шаблон (по `installed.json`, только неизменённые файлы). `CONTRACT.md` остаются — это документы D5.

## Estimate (оценка объёма)
Ядро (модули из `CONTRACT.md`, нормализатор, сравнитель, отчёт, запускатели) — 1 сессия; адаптеры python + rust + go — 1,5; ts + terraform + generic — 1; фикстуры и связка с D8 — 0,5. Итого **≈ 5.5 сессии** (было ≈ 4 при Python-ядре; парность `.ps1`/`.sh` ≈ ×1.8 к ядру и запускателям). Взорвать может: сеть у `go list`/`cargo metadata` в CI, отказ от Python-ядра (Q1).

## План работ
Заполняется после аппрува.

## Definition of done
- [ ] Шесть адаптеров с фикстурами; S1–S5 зелёные на Windows и Linux.
- [ ] `report.json` читается D9 без повторного прогона.
- [ ] Формат `## Зависимости` согласован с D5; джоба в шаблоне D8.

## Progress log
- 2026-09-27 — создана спека-набросок
