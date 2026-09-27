# D3: Страж области изменений — PreToolUse-запрет записи вне карточки и в защищённые зоны

> Статус: DRAFT
> Тип: спека-набросок
> Модуль E1: `scope-guard` (`rewrites: {}` — только `deny`)
> Зависит от: E1, D2 (активная карточка, указатель `active-card`), D1 (пути по умолчанию для защищённых зон)   Блокирует: D4 (путевые права ролей и «сессия на карточку» исполняются здесь), D7 (защищённые тестовые зоны), D8 (CI переиспользует `scope-check`)

## Goal
Инструменты записи Claude (`Edit|Write|MultiEdit|NotebookEdit`) получают `deny`, если путь вне `touch_allowed` активной карточки, внутри её `forbidden`, внутри глобальной защищённой зоны или вне прав роли (§2, §5 плейбука). Команды `Bash|PowerShell` проверяются по возможности. Окончательная гарантия — не хук, а пост-фактум `scope-check` диффа при `task done` и в CI.

## User value
«Хук блокирует остальное» из шаблона карточки сейчас — пожелание: в OS есть только `protect-secrets` (секретные пути и содержимое). Закрыто, когда (а) правка вне области отклоняется в момент вызова с причиной, которая говорит агенту, что делать дальше; (б) любая запись в обход хука (скрипт, упавший хук) ловится `scope-check` до закрытия карточки и до мержа.

## Non-goals
- Граница безопасности против злонамеренного процесса: Python/Node-скрипт, пишущий файлы сам, хук не видит (так же говорят доки permissions про нативные правила). Для этого — песочница Claude Code, не D3.
- Ограничение чтения (кроме правила ревьюера в D4) и секреты (это `protect-secrets` и F1).
- Переписывание входа (`updatedInput`): только `deny`, поэтому A-03 и конфликт `rewrites` E1 к D3 неприменимы.
- Внешние исполнители X1: их процесс мимо хуков; для них — `scope-check` на возвращённом диффе.

## Current state
- `protect-secrets.{ps1,sh}` — PreToolUse `Read|Edit|Write|MultiEdit`, читает `file_path // path // notebook_path`, отвечает `permissionDecision: "deny"`, пишет журнал `~/.claude/logs/hook-events.jsonl` через `hook-lib`. D3 повторяет этот контракт и журнал.
- Все хуки OS матчатся на `Bash`, инструмент PowerShell их обходит (PF-28). D3 обязан матчить `Bash|PowerShell`.
- Разбор shell-команд (bash-лексер, PowerShell AST через `System.Management.Automation.Language.Parser`) проектируется в X4 — D3 берёт ту же библиотеку, а не пишет вторую.
- Доки permissions: `Edit(path)`-deny покрывает Edit/Write, распознанные файловые команды Bash (`sed`, `tee` …) и цели перенаправлений `>`; правила для `Write(...)`/`MultiEdit(...)`/`NotebookEdit(...)` не консультируются (нужен `Edit(...)`); gitignore-синтаксис; deny-правила действуют независимо от ответа хука.

## Assumptions
- `ASSUMPTION:` нативные `Edit(...)`-deny срабатывают и на запись через инструмент **PowerShell** (`Set-Content`, `Out-File`, `>`), как на перенаправления Bash; доки явно пишут про Bash. Проверить: deny `Edit(/golden/**)` + `Set-Content golden/x.txt` через PowerShell.
- `ASSUMPTION:` у сабагента с `isolation: worktree` поле `cwd` во входе хука указывает внутрь его worktree (PF-24 говорит «следует за Claude», для изолированных сабагентов не сверено). Проверить хуком-дампером. Без этого указатель карточки берётся из главного дерева — неверно для параллельного режима.
- A-15 (у PowerShell есть `tool_input.command`), A-13 (`${CLAUDE_PROJECT_DIR}` в exec-форме проектного хука).

## Questions
1. Поведение без активной карточки? По умолчанию `noCard: protected-only` — запрещены только глобальные защищённые зоны, остальная работа идёт как без модуля. Строгие проекты ставят `deny`, мягкие — `ask`.
2. Добавлять ли нативные `Edit(...)`-deny для глобальных зон при `enable`? По умолчанию **да** (страховка на случай fail-open хука, PF-12), с платой: даже роль «по отдельной карточке» не сможет править зону, пока человек не выполнит `scope-guard unlock` (см. ниже).

## GitHub research
| Repo | License | Что берём | Риск |
|---|---|---|---|
| X4 (своя спека) | — | Разборщик подкоманд, PowerShell AST, «не разобрал → не решаю / ask» | общий код — ошибка в нём бьёт по обоим модулям; общий набор фикстур |
| Нативные permission-правила Claude Code (доки permissions) | — | gitignore-семантику путей и якоря `/`, `//`, `~/` — матчер D3 обязан совпадать с ней на фикстурах | семантика глубины для одиночных каталогов различается по типу правила — фикстуры из таблицы доков |

Внешних репозиториев с хуком «область карточки» не найдено; поиск шёл по README `Backlog.md`, `spec-kit`, `BMAD-METHOD` — у всех область задачи описана прозой.

## Official docs checked
PF-06 (все хуки параллельно, `deny` побеждает — совместимость с `protect-secrets`, X4, F1 без координации), PF-10 (хуки settings срабатывают в сабагентах, есть `agent_type` — основа ролевых прав), PF-12 (таймаут и падение хука = fail-open), PF-14/A-13 (exec-форма), PF-16 (`disableAllHooks`, горячая перезагрузка), PF-21 (`if`-фильтр best-effort — не используем), PF-24 (`cwd` против `CLAUDE_PROJECT_DIR`), PF-28 (матчер `Bash|PowerShell`). Сверх: permissions.md, разделы Read and Edit, Redirections.

## Architecture (дизайн)
Хук `hooks/scope-guard.{ps1,sh}`, PreToolUse, два матчера: `Edit|Write|MultiEdit|NotebookEdit` (точный слой) и `Bash|PowerShell` (слой по возможности). Порядок решения для файлового инструмента:
1. Режим E1 `off` → выход 0, пустой stdout.
2. Путь из `file_path` / `notebook_path`; нормализация: абсолютный от `cwd`, `realpath` (симлинки, junction), `..`, прямые слэши, регистр — без учёта на Windows; относительный от корня **рабочего дерева** (`git rev-parse --show-toplevel` от `cwd`, не `CLAUDE_PROJECT_DIR`, PF-24). Вне дерева → нет решения.
3. **Самозащита** (всегда): `.claude/os-modules/**`, `.claude/settings*.json` → `deny`. Иначе модель выключает страж записью `state.json` (угроза из E1 Security model).
4. **Глобальные зоны** `config.protected` (по умолчанию: `docs/vision.md`, `docs/invariants.md`, `tests/golden/**`, `tasks/**`, `**/CONTRACT.md` и `docs/architecture.md` при D5) → `deny`, кроме зон, разблокированных человеком (`unlock.json`, см. ниже) и ролевых исключений D4 (планировщику — `tasks/backlog/**`; архитектору — новые файлы `docs/adr/**`, а `docs/architecture.md` и `**/CONTRACT.md` — только при активной карточке `kind: contract`, наличие принятого ADR проверяет `adr-gate` D5 при `task done`).
5. **Роль** (`agent_type` есть → таблица путей роли из D4): вне разрешённого → `deny`.
6. **Сессия** (политика D4 «свежая сессия на карточку», `oneCardPerSession: true`): первый разрешённый вызов записи привязывает `session_id` к карточке; сессия, уже привязанная к другой карточке или к прошлой попытке этой (`task start --retry`), получает `deny`.
7. **Карточка** из `<git-dir>/srednoff-tasks/active-card` (D2): путь в `forbidden` → `deny`; не в `touch_allowed` → `deny`. Нет карточки → политика `noCard`.
Причина отказа всегда инструктивна: `scope-guard: sim/render/x.rs is outside T-0142 touch_allowed [sim/transport/**, tests/transport/**]. If the change is required, stop and run: task return T-0142 --reason scope`.

Слой `Bash|PowerShell`: разбор X4 извлекает цели записи (перенаправления, `tee`, `sed -i`, `cp/mv/rm`, `git checkout/restore -- <path>`, `Set-Content/Add-Content/Out-File/New-Item/Remove-Item/Move-Item/Copy-Item`); проверяются только шаги 3–4 и `forbidden` из шага 7. `touch_allowed` для shell не применяется (сборка пишет повсюду — ложные срабатывания). Не разобрал → нет решения, записывается в журнал: **fail-open по замыслу**, прикрытый пост-фактум проверкой.

**Пост-фактум `scope-check`** (`bin/scope-check.{ps1,sh} --card ID --base REF`): `git diff --name-status REF...HEAD` + неотслеживаемые → те же шаги 3–7 без сессии. Вызывают `task done` (D2), `delegate-apply` (X1, перед применением диффа внешнего исполнителя) и CI (D8). Это единственная проверка, которую нельзя обойти скриптом.

**Отказоустойчивость**: для файлового слоя `failMode: closed` — битая карточка, непарсящийся конфиг, внутренний таймаут 3 с → `deny` с причиной «run task validate». Падение процесса или таймаут платформы остаются fail-open (PF-12) — их страхуют нативные `Edit(...)`-deny для глобальных зон и `scope-check`. Для shell-слоя — `failMode: open`.

**Разблокировка зоны** человеком: `scope-guard unlock <glob> --card ID --ttl 2h` пишет `.claude/os-modules/.state/scope-guard/unlock.json` и временно снимает соответствующее нативное правило (E1 учитывает его в `installed.json`); `lock` возвращает. Команда предназначена для терминала владельца или `!`-строки команды (A-10); из инструментов Claude файл защищён шагом 3. Честно: shell-скрипт модели может его переписать — ловит D8 (изменение защищённой зоны без аппрува).

Взаимодействие: `protect-secrets` и D3 — оба только `deny`, запускаются параллельно, побеждает `deny` (PF-06); F1 переписывает содержимое, но не пути, а D3 видит исходный вход (параллельный запуск) — корректно, пока F1 не подменяет пути. Кэш: разобранная карточка кэшируется по mtime в `.state/scope-guard/`, чтобы не парсить YAML на каждый вызов.

Отвергнуто: только нативные правила (статичны, не знают активной карточки и роли); `if`-фильтр в проводке (PF-21, пропускает формы); `ask` вместо `deny` вне области (в `auto` режиме A-17 делает его молчаливым `allow` на старых версиях).

## API contracts (интерфейсы и форматы)
Вывод хука: `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"scope-guard: ..."}}`, код 0; без решения — пустой stdout. Конфиг:
```json
{ "schema": 1, "noCard": "protected-only", "failMode": {"file": "closed", "shell": "open"},
  "protected": ["docs/vision.md", "docs/invariants.md", "tests/golden/**", "tasks/**"],
  "nativeBackstop": true, "oneCardPerSession": true, "internalTimeoutMs": 3000 }
```
`scope-check` → `{card, base, violations:[{path, rule: protected|forbidden|outside|role}]}`, код 1 при нарушениях. `scope-guard explain <path>` печатает, какой шаг решил бы и почему (отладка и фикстуры).

## Data model / migrations
`.claude/os-modules/.state/scope-guard/{cache/, sessions.json, unlock.json}` (gitignored). `sessions.json`: `{session_id: {card, attempt, boundAt}}`, записи старше 30 дней удаляются. Журнал решений — общий `hook-events.jsonl` (sha256 входа). Схема конфига — `schema`, миграции через E1.

## Security model
Защищаем: от случайной и «удобной» правки вне области инструментами записи; от выключения стража самой моделью через Edit/Write; от незамеченной записи в обход хука — через `scope-check` в `task done` и CI. Не защищаем: запись произвольными процессами (скрипты, сборка) до момента `scope-check`; обход через неразобранную shell-форму; человека (его правки хук не видит и видеть не должен).

## Risks
| Риск | Вероятность | Влияние | Митигация |
|---|---|---|---|
| Матчер путей расходится с gitignore-семантикой | средняя | высокое | фикстуры из таблицы доков permissions, общий матчер D2/D3/D8 |
| Задержка: PowerShell 5.1 стартует 0.3–0.5 с на каждый Edit | высокая | среднее | кэш карточки; exec-форма; замер в DoD; при > 1 с — предупреждение `doctor` |
| Ложные `deny` мешают работе без карточек | средняя | среднее | `noCard: protected-only` по умолчанию |
| Нативный backstop блокирует законную правку golden | средняя | низкое | `unlock` с TTL, привязкой к карточке и записью в журнал |

## Acceptance criteria
- AC1: `off` → ни одного решения на 20 эталонных вызовах → S1.
- AC2: Edit вне `touch_allowed` активной карточки → `deny` с id карточки в причине → S2.
- AC3: `Set-Content tests/golden/a.txt` через PowerShell → `deny` → S3.
- AC4: файл, изменённый скриптом вне области, валит `scope-check` → S4.
- AC5: запись в `.claude/os-modules/scope-guard/state.json` через Write → `deny` при любом режиме, кроме `off` → S5.

## Testing plan
```gherkin
Scenario: S1 disabled guard is silent
  Given scope-guard is in mode "off" and T-0142 is active
  When the hook receives 20 reference Edit, Write and PowerShell calls
  Then every call exits 0 with empty stdout
Scenario: S2 edit outside the card is denied
  Given active card T-0142 with touch_allowed "sim/transport/**"
  When the hook receives Edit of "sim/render/frame.rs"
  Then the decision is "deny" and the reason contains "T-0142" and "task return"
Scenario: S3 PowerShell write to a protected zone
  When the hook receives PowerShell command "Set-Content tests/golden/a.txt 'x'"
  Then the decision is "deny"
Scenario: S4 bypass is caught after the fact
  Given active card T-0142 and a script that wrote "sim/render/frame.rs"
  When I run scope-check --card T-0142 --base main
  Then the exit code is 1 and the violation rule is "outside"
Scenario: S5 the guard protects its own switch
  Given scope-guard is in mode "on"
  When the hook receives Write of ".claude/os-modules/scope-guard/state.json"
  Then the decision is "deny"
```
Табличные фикстуры матчера (≥ 50, включая Windows-регистр, `..`, junction, кириллицу) — через `run-evals`. Вручную: живой прогон в десктопе 2.1.281 и CLI 2.1.177 через оба инструмента, Bash и PowerShell; проверка nativeBackstop с `disableAllHooks`.

## Rollback plan
`off` — хук молчит; нативные deny остаются, пока модуль установлен. `uninstall` через E1 удаляет запись хука и ровно добавленные deny-правила из `installed.json`, каталог `.state/scope-guard/`.

## Estimate (оценка объёма)
Файловый слой + матчер + фикстуры — 1.5 сессии; shell-слой на библиотеке X4 — 0.5 (при готовом X4; без него +1.5); `scope-check`, `unlock`, backstop — 1; behave S1–S5 и живые прогоны — 0.5–1. Итого 3.5–4 сессии. Взорвать может: готовность разборщика X4, A-13 на путях с пробелами, задержка PowerShell 5.1.

## План работ
Заполняется после аппрува.

## Definition of done
- [ ] Паритет `.ps1/.sh`, в `.ps1` нет кириллицы; S1–S5 зелёные на Windows и Linux; матчер `Bash|PowerShell` проверен живым прогоном
- [ ] Медиана задержки хука на Windows ≤ 600 мс (замер в Progress log)
- [ ] `doctor` модуля: хук подключён, backstop на месте, `unlock.json` без просроченных записей

## Progress log
- 2026-09-27 — создан набросок спеки
