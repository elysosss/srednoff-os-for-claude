# D7: Детектор ослабления тестов

> Статус: DRAFT
> Тип: спека-набросок
> Модуль E1: `test-guard` (режимы `off | warn | enforce`, по умолчанию `off`); CI-джоба через `ciTemplates` D8
> Зависит от: E1, D2 (поля карточки `kind: test|impl|golden`, `depends_on`, `risk`; вывод `--json` CLI `task`), D3 (`config.protected`, привязка `session_id` к карточке — шаг 6, `scope-check`), D6 (Q1 — язык ядра; карта модулей для `mock_of_sut`), D8 (доставка в CI, превращение `risk: high` в обязательный аппрув)   Блокирует: D8 (вход «риск» для гейта 7), D9 (счётчик high-risk PR)

## Goal
CI по диффу PR находит ослабление тестов — удалённые проверки, пропуски, расширенные допуски, удалённые тесты, правки эталонов и perf-бюджетов — и поднимает риск PR до `high`, что по D8 требует аппрува человека. Отдельно — механическая проверка пары «тест до кода» для карточек D2.

## User value
Бриф §5: агент, которому «надо, чтобы прошло», правит тест. Сейчас это ловит только ревьюер, если заметит. Закрыто, когда каждый приём из списка ниже на фикстуре даёт `high` с `file:line`, а PR с таким диффом не мержится без человека.

## Non-goals
- Не блокируем запись в тесты во время сессии — это клиентский хук D3 (`forbidden`, защищённые зоны). D7 — серверная детекция по итоговому диффу.
- Не доказываем, что тест «имеет зубы». Семантическое ослабление (`assert x == x`, ожидание подменено вычисленным значением, мок подменил тестируемый модуль) диффом ловится только частично — см. Security model; глубокая проверка — мутационное тестирование, опционально и не на каждый PR.
- Не решаем, кто прав: детектор повышает риск и объясняет, отклонить или принять решает человек.

## Current state
В OS нет проверок тестов потребителя. Скилл `mutation-testing-strategy` — проза; `test-driven-development`, `cross-language-test-gate` — тоже. D7 — их машинная часть. Похожие молодые проекты (таблица ниже) подтверждают набор приёмов: `skip`, выброшенные assert'ы, `toEqual → toBeTruthy`, мок тестируемого модуля, правка baseline.

## Assumptions
- `ASSUMPTION:` сравнение числа проверок **на тест-функцию** (base против head, по AST для Python и по регэкспам для Go/Rust/TS) даёт на реальных PR владельца долю ложных `high` ниже 10 %. Проверить: прогон по последним 100 PR/коммитам проекта владельца в режиме `warn`, разметка вручную.
- `ASSUMPTION:` метка PR `srednoff:risk-high`, выставленная джобой с `pull-requests: write`, видна джобе risk-gate D8 в том же прогоне через API. Проверить на тестовом репо.

## Questions

**Решено владельцем 2026-09-27:** ядро D6/D7/D10 — **парные `.ps1`/`.sh`**, как все скрипты OS; Python в ядро не вводится. Уточнение: адаптер языка может вызывать штатный инструмент самого проверяемого проекта (для Python-проекта — его интерпретатор и `ast`, для Go — `go list`), это зависимость проекта, а не OS. Оценка ниже пересчитана с учётом парности (≈ ×1.8 к ядру).

1. Правка ожидаемого значения внутри той же проверки (`assert f() == 3` → `== 4`) — `high` или `medium`? По умолчанию `medium` (ревьюеру отдельной строкой): это и легитимная смена поведения по спеке. Для путей из зон `golden`/`protected` — всегда `high`.

## GitHub research
| Repo | License | Что берём | Риск |
|---|---|---|---|
| smixs/code-quality (13★, push 2026-09) | MIT | классы находок `test-skipped / assertion-weakened / mock-added / baseline-touched`; «только новые находки на изменённых строках» | молодой, только паттерны |
| hidevinliu/red-green-mode (10★) | MIT | stdlib-Python, детерминированные коды выхода; «сначала красный, потом зелёный» как проверка пары | молодой, только паттерны |
| boxed/mutmut | BSD-3-Clause | опциональная мутационная проверка Python на high-risk PR | долго на больших наборах |
| sourcefrog/cargo-mutants | MIT | то же для Rust | долго |
| stryker-mutator/stryker-js | Apache-2.0 | то же для TS | долго |
| go-gremlins/gremlins | Apache-2.0 | то же для Go | push 2026-06, медленнее прочих |

Решение: **Build ourselves** на stdlib (`ast`, `difflib`, `git diff`) по паттернам выше; мутационные инструменты — **Adopt** как опциональный вызов.

## Official docs checked
Claude Code не задействован (CI). Про метки и права `GITHUB_TOKEN` — см. D8 «Official docs checked».

## Architecture (дизайн)
Вход: `git diff --merge-base <base> HEAD` + файлы в base и head. Шаги:
1. **Классификация путей**: `test_globs` → тестовый файл; зоны `golden`, `perf_budget`, `protected` (последняя — `config.protected` модуля D3; D7 своей копии не держит, отсутствие D3 → только свои зоны и предупреждение).
2. **Правила** (каждое — чистая функция `(base_file, head_file, diff) → findings[]`):
   - `assert_removed`: число проверок в тест-функции уменьшилось (Python — `ast`: `assert`, `self.assert*`, `pytest.raises`, `pytest.approx`-сравнения; Go — `t.Error*/t.Fatal*`, `require.*`, `assert.*`; Rust — `assert!/assert_eq!/assert_ne!/…`; TS — `expect(`).
   - `assert_loosened`: сильная проверка заменена слабой (`toEqual → toBeTruthy`, `assert_eq! → assert!`, `assertEqual → assertTrue`, `== → is not None`).
   - `skip_added`: `@pytest.mark.skip|skipif|xfail`, `pytest.skip(`, `unittest.skip`, `t.Skip(`, `#[ignore]`, `it.skip|describe.skip|test.skip|xit|xdescribe`, **а также** `.only` (фокус выключает остальные).
   - `tolerance_widened`: в парных строках (`difflib`) число в контексте допуска выросло: `approx(…rel=|abs=)`, `assertAlmostEqual(…places|delta)`, `assert_allclose(…rtol|atol)`, `assert_relative_eq!(…epsilon)`, `InDelta/InEpsilon`, ключи `tolerance|epsilon|eps|atol|rtol` в конфигах тестов.
   - `test_deleted`: удалён тестовый файл или тест-функция без переноса (перенос = такое же тело в другом файле диффа).
   - `expectation_changed`: изменено ожидаемое значение внутри той же проверки — `medium` (Q1); в зонах `golden`/`protected` — `high`.
   - `mock_of_sut`: в тест модуля M добавлен мок/patch символа из самого M (карта модулей D6, если включён) — `medium`.
   - `runner_narrowed`: правка `addopts`, `--deselect`, `-k "not …"`, `testpaths`, `[[test]]`, `-run`/`-skip` в конфиге или скрипте запуска — `high`.
   - `zone_touched`: любая правка в `golden`/`perf_budget`/`protected` — `high`.
3. **Сводка**: `risk = max(правил)`; в CI — аннотации `file:line`, job summary, метка `srednoff:risk-high`; D8 объединяет с риском карточки: `effective = max(card.risk, D7, …)`. Только **новые** находки на изменённых строках, как у code-quality: старый долг не шумит.
4. **Пара «тест до кода»** (`pairing`) — без новых полей D2: пара = карточка `kind: impl`, у которой в `depends_on` есть карточка `kind: test` того же `module`. Проверяется, что (а) тестовая карточка в `done/`, её коммит — предок base (V3 D2 это уже требует для старта); (б) PR реализации **не меняет и не удаляет** строки, внесённые коммитами тестовой карточки (только добавления рядом), иначе `high`; (в) локально при `task done` — `session_id`, привязанные D3 к двум карточкам, различаются. Честно: (в) видно только на машине, где шла работа (состояние D3 не в git), в CI проверяются (а) и (б); разные сессии — не разный «разум», разные модели — только если тестовую карточку исполнял внешний исполнитель X1/X2. Для модулей из `config.testFirst` карточка `impl` без пары — ошибка валидации (правило подключается к `task validate` D2).
5. **Мутации** (опционально, `mutation: on_high_risk`): для high-risk PR — мутационный прогон только по изменённым строкам кода; выживший мутант на строке, чей тест ослаблен, — строка в отчёт. Выключено по умолчанию: минуты и часы CI.
Отвергнуто: LLM-судья диффа (недетерминирован, противоречит главному принципу брифа); запрет любых правок тестов (исполнитель по брифу может добавлять тесты).

## API contracts (интерфейсы и форматы)
Конфиг `.claude/os-modules/test-guard/config/project.json` (коммитится; файл гейта D8, локально под самозащитой D3):
```json
{ "schema": 1,
  "testGlobs": ["tests/**", "**/test_*.py", "**/*_test.go", "**/*.spec.ts", "**/*.test.ts"],
  "zones": { "golden": ["tests/golden/**"], "perfBudget": ["perf/budgets/**"] },
  "severity": { "assert_removed": "high", "assert_loosened": "high", "skip_added": "high", "tolerance_widened": "high",
    "test_deleted": "high", "runner_narrowed": "high", "zone_touched": "high", "mock_of_sut": "medium", "expectation_changed": "medium" },
  "pairing": "enforce", "testFirst": ["sim/transport"], "mutation": "off" }
```
Команда: `test-guard.{ps1,sh} [-Base REF] [-Card T-xxxx] [-Json]`. Коды: `0` риск low/medium; `1` найден high (в режиме `enforce`); `2` конфиг; `3` нет git-истории base (shallow checkout — fail-closed, D8 делает `fetch-depth: 0`). Отчёт: `{schema, risk, findings:[{rule, severity, file, line, before, after}], pairing:{card, status, reasons[]}}`.

Требования к D2 (схемой владеет D2): новых полей не нужно — `kind`, `depends_on`, `module`, `risk` уже есть; нужен машинный вывод `task show ID --json` (или `task validate --json` с карточкой), чтобы D7 не разбирал YAML сам. Требование к D3: `scope-guard` отдаёт привязку `session_id → card` командой с `--json`.

## Data model / migrations
Состояния нет, кроме отчёта-артефакта CI и `.claude/os-modules/.state/test-guard/last.json` при локальном прогоне. `schema` целое.

## Security model
Защищаем от: приёмы из списка правил, включая тихие (`.only`, сужение раннера). Не защищаем (слепые зоны, пишутся в README и в отчёт одной строкой): тавтологичные проверки; ожидание, переписанное вычисленным значением (ловится как `expectation_changed`, только `medium`); ослабление внутри хелпер-функций проверок вне тестовых файлов; ослабление через данные фикстур вне `golden`. Для них — мутации и ревьюер D4. Агент может выключить D7 правкой конфига — закрыто D8 (CODEOWNERS + gate-integrity).

## Risks
| Риск | Вероятность | Влияние | Митигация |
|---|---|---|---|
| Ложные `high` на рефакторинге тестов (перенос, параметризация) | высокая | среднее | детект переноса тела; `pytest.mark.parametrize` считается как N проверок; месяц в `warn` |
| Регэкспы Go/Rust/TS пропускают макросы и хелперы | средняя | среднее | список имён проверок расширяется в конфиге; ast-grep как опциональный точный адаптер |
| Shallow checkout ломает base | средняя | высокое | код 3, не 0; шаблон D8 с `fetch-depth: 0` |
| Метка риска снимается агентом | средняя | высокое | risk-gate D8 пересчитывает риск сам, метка — только отображение |

## Acceptance criteria
1. Каждое правило из списка на фикстуре даёт находку с `file:line` — S1, S2, S3.
2. Правка golden → `high` независимо от карточки `risk: low` — S4.
3. Нарушение пары «тест до кода» → `high` — S5.
4. Одинаковые отчёты `.ps1`/`.sh`; в `off` ничего не запускается.

## Testing plan
```gherkin
Scenario: S1 удалённая проверка
  Given в base тест test_capacity содержит 3 assert
  And в head тот же тест содержит 1 assert
  When запускаю test-guard --base base в режиме enforce
  Then код выхода 1 и находка assert_removed "tests/test_stop.py:12" с before=3 after=1

Scenario: S2 пропуск и фокус
  Given в head к тесту добавлен "@pytest.mark.xfail" и в spec.ts появился "it.only("
  When запускаю test-guard --json
  Then в findings две находки skip_added severity high

Scenario: S3 расширенный допуск
  Given строка "assert x == pytest.approx(1.0, rel=1e-6)" стала "rel=1e-2"
  When запускаю test-guard
  Then находка tolerance_widened с before "1e-6" after "1e-2"

Scenario: S4 эталон при карточке low
  Given карточка T-0142 с risk low и PR меняет tests/golden/stops.json
  When CI выполняет гейты D8
  Then эффективный риск high и risk-gate требует аппрув человека

Scenario: S5 реализация переписала тест своей пары
  Given карточка T-0150 kind impl с depends_on T-0149 kind test того же module в статусе done
  And PR T-0150 меняет строку, внесённую коммитом T-0149
  When запускаю test-guard --card T-0150
  Then pairing.status "violated" и риск high
```
Юнит-тесты каждого правила — таблица фикстур в стиле `registry/evals/*-fixtures.json` (вход base/head → ожидаемые находки), гоняется на обеих ОС. Ручное: месяц `warn` на проекте владельца, разметка ложных срабатываний.

## Rollback plan
`os-module mode test-guard off` (правка под CODEOWNERS) → D8 убирает джобу из caller-workflow; `uninstall` — удаление файлов по `installed.json`. Метки на старых PR остаются, вреда нет.

## Estimate (оценка объёма)
Ядро и классификатор путей — 0,5 сессии; правила Python (AST) — 1; Go/Rust/TS регэкспы — 1; pairing — 0,5; фикстуры, запускатели, CI — 1. Итого **≈ 6 сессий** (было ≈ 4 при Python-ядре; парность `.ps1`/`.sh`); мутационный режим — ещё 1. Взорвать может: доля ложных срабатываний выше допущения — тогда правила Go/Rust/TS переводятся на ast-grep (+1 сессия).

## План работ
Заполняется после аппрува.

## Definition of done
- [ ] Девять правил с фикстурами на четырёх языках; S1–S5 зелёные на Windows и Linux.
- [ ] Риск доходит до risk-gate D8; метка — только отображение.
- [ ] Слепые зоны перечислены в README модуля и в отчёте.

## Progress log
- 2026-09-27 — создана спека-набросок
