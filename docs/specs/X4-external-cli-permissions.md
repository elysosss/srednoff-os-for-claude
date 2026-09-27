# X4: Права на внешние CLI — трёхуровневая модель (`gh` первым)

> Статус: DRAFT
> Тип: спека-набросок
> Модуль E1: `cli-perms`
> Зависит от: E1   Блокирует: —

## Goal
Хук `PreToolUse` разбирает shell-команды Claude, в которых вызывается внешний CLI (в v1 — `gh`), и относит каждую к одному из трёх уровней. **Чтение** идёт обычным потоком разрешений, **запись** требует явного разрешения владельца, **команды с учётными данными** запрещены всегда.

## User value
Claude свободно читает PR, issues и CI через уже залогиненный `gh`, но не может без спроса смержить PR, удалить релиз или вывести токен в контекст. Закрыто, когда на наборе фикстур ни одна credential-команда не проходит, ни одна write-команда не проходит молча, а чтение не вызывает лишних запросов.

## Non-goals
- Граница безопасности вокруг программы. Скрипт `./release.sh`, который внутри зовёт `gh`, хук не видит — это задача песочницы, а не разбора текста.
- Внешние исполнители X1: их процессы идут мимо хуков Claude, там защита — пустой `GH_CONFIG_DIR` в env исполнителя (X1). Замена `block-dangerous-bash` и нативных правил `permissions` — X4 их дополняет. Другие CLI в v1. Формат политики общий, но в поставке только `gh`; `git`, `npm`, `docker`, `aws` — отдельными файлами политики позже.

## Current state
- `block-dangerous-bash.{ps1,sh}` — PreToolUse с матчером **`Bash`**: опасные паттерны плюс секреты в тексте команды. `gh` не различает.
- **Найдено при подготовке спеки:** все хуки OS в `hooks/hooks.json`, `settings.example.json` и `settings.windows.example.json` матчатся на `Bash`, а по докам (PF-28) на Windows с Git Bash инструмент `PowerShell` включён по умолчанию и хукам нужен матчер `Bash|PowerShell`. Команды через инструмент PowerShell сейчас проходят мимо `block-dangerous-bash`. Для X4 это обязательный матчер; починка существующих хуков — отдельная задача вне этой спеки.
- Нативные правила `permissions.allow/ask/deny` в OS-шаблонах не используются.

## Assumptions
- `ASSUMPTION:` в 2.1.177 вход PreToolUse для инструмента `PowerShell` имеет `tool_input.command`, как у Bash (так в текущих доках; в бинаре 2.1.177 не сверялось). Проверить хуком-дампером.
- `ASSUMPTION:` поле `permission_mode` приходит во вход PreToolUse в 2.1.177 (строка `permission_mode:k.string().optional()` в бинаре есть, по событиям не сверено). Проверить тем же дампером в режимах default/auto.
- `ASSUMPTION:` в режиме `auto` на 2.1.177 хуковый `"ask"` для Bash может быть молча одобрен классификатором: доки hooks говорят, что это исправлено только в v2.1.211. Поэтому в `auto` запись не спрашивается, а запрещается. Проверить: `gh issue create` в auto-режиме с хуком, отвечающим `ask`.
- `ASSUMPTION:` нативные Bash-правила в 2.1.177 уже делят составные команды по `&&`, `;`, `|` (доки описывают текущую версию). Проверить deny-правилом `Bash(gh auth token*)` против `echo x && gh auth token`.

## Questions
1. Отдавать ли на чтение `"allow"` (без запроса) или молчать? По умолчанию молчать: решает обычный поток разрешений. `"allow"` включается флагом `readDecision: "allow"` и отдаётся **только** для одиночной простой команды без разделителей, подстановок и перенаправлений. Иначе `allow` снял бы запрос со всей составной команды (PF-05: `allow` пропускает запрос разрешения). 2. Как дать разовое разрешение на запись в режиме `auto`? По умолчанию никак: `deny` с подсказкой переключиться в обычный режим или выполнить команду самому через `! gh ...`.

## GitHub research
| Repo | License | Что берём | Риск |
|---|---|---|---|
| `Nico0713520/dsh-github-cli` @ `529b2d9e5c10` (единственный день активности 2026-08-17, 0★) | MIT | Трёхуровневая модель: `READ_ONLY_COMMANDS` / запись по `fullAccess` / `SENSITIVE_COMMANDS` (`auth login/logout/refresh/token/setup-git`, `secret`, `ssh-key`) всегда запрещены; ключ команды из первых слов без флагов; `gh api -f/-F/--field/--raw-field/--input` неявно становится POST (`src/gh-runner.ts`) | Проект без истории и сообщества. **Две дыры, проверены по коду**: (1) метод ищется только в `--method`, поэтому `gh api -X DELETE /repos/o/r` считается чтением; (2) `auth status` в read-списке, а `gh auth status --show-token` (`-t`) печатает токен (проверено `gh auth status --help`, gh 2.100.0). Берём идею, дыры закрываем фикстурами |
| `deepseek-ai/deepseek-harness` @ `477b4f420553` | MIT | Контекст: у dsh плагин владеет исполнением (`execFile`, `shell:false`), поэтому разбор точный. У нас Claude пишет **текст shell-команды** — разбор хуже, отсюда уровень «не разобрал → ask» | — |

## Official docs checked
PF-05 (`allow` снимает запрос, правила проверяются по итоговому входу), PF-06 (все хуки параллельно; `deny` > `defer` > `ask` > `allow` — поэтому X4 и `block-dangerous-bash` совместимы без координации; `updatedInput` X4 не использует, A-03 не касается), PF-12 (истёкший по таймауту PreToolUse **не блокирует**, падение скрипта не блокирует — хук fail-open по конструкции), PF-16 (`disableAllHooks` выключает хук), PF-21 (`if`-фильтр best-effort). Сверх: permissions.md — порядок deny → ask → allow; Bash-правило «не граница безопасности» (`/usr/bin/curl`, `sh -c` его обходят); PowerShell-правила разбираются по AST. hooks.md — «Deny and ask rules are still evaluated regardless of what the hook returns».

## Architecture (дизайн)
Два слоя, потому что каждый в одиночку дырявый:
1. **Хук (основной, точный):** `hooks/cli-perms.{ps1,sh}`, событие PreToolUse, матчер `Bash|PowerShell`, **без** `if`-фильтра: `if: "Bash(gh *)"` пропустил бы `& gh.exe`, `/usr/bin/gh`, `"gh"` (PF-21). Внутри скрипта дешёвый предфильтр: токен `gh`/`gh.exe` в тексте. Нет — выход 0 без вывода.
2. **Нативные правила (страховка):** модуль при установке добавляет в проектный `settings.json` `deny` для credential-уровня (`Bash(gh auth token *)`, `Bash(gh secret *)`, `Bash(gh ssh-key *)`, `Bash(gh auth status *-t*)` — покрывает и `-t`, и `--show-token`, те же для `PowerShell(...)`). Они работают, даже если хук упал, истёк по таймауту или хуки выключены (PF-12, PF-16).

Разбор в хуке: команда делится на подкоманды (`&&`, `||`, `;`, `|`, переводы строк; в PowerShell — AST через `System.Management.Automation.Language.Parser`). В каждой подкоманде, где вызывается `gh`, строится ключ (первые 1–3 слова без флагов, флаги-со-значением пропускаются вместе со значением) и применяются правила:
- **credential → `deny`**: ключ из `credentialCommands`; флаг из `credentialFlags` **для своего ключа** (`-t`/`--show-token` у `auth status`; у `pr list` тот же `-t` означает `--template` и безопасен); префикс-присваивание `GH_TOKEN=`, `GITHUB_TOKEN=`, `GH_ENTERPRISE_TOKEN=`, `GH_CONFIG_DIR=`; `gh config get` c `oauth_token`.
- **write → `ask`** (или `deny` в режимах `auto`, `dontAsk`, `bypassPermissions`): ключ из `writeCommands`; **любой ключ, которого нет в `readCommands`** (сюда же попадают алиасы и расширения: `gh alias set pv 'pr merge'` делает `gh pv` неизвестным ключом); `gh api` с методом не GET в любой форме (`-X DELETE`, `-XPOST`, `--method=PUT`) или с флагом тела (`-f/-F/--field/--raw-field/--input`, в том числе `--field=…`); исключение — `gh api graphql`, где запись определяется словом `mutation` в `query`.
- **read → нет решения** (или `allow` по флагу, см. Questions).
- **не разобрал** (`$(...)`, обратные кавычки, `bash -c`/`sh -c`/`pwsh -c`/`Invoke-Expression`/`iex` с `gh` внутри, переменная в позиции команды, кодирование) → `ask`.
Итог по команде — самый строгий уровень среди подкоманд. Каждый `deny`/`ask` пишется в общий журнал `~/.claude/logs/hook-events.jsonl` форматом `hook-lib` (sha256 входа, не сам текст).

Отвергнутые альтернативы: только нативные правила (не видят `-X DELETE` и `--show-token` в середине команды, не различают `gh api` по методу); обёртка-shim `gh` в `PATH` (Claude может вызвать настоящий `gh` по полному пути, а подмена `PATH` глобальна); `updatedInput` для «исправления» команды (PF-05, A-03: конфликт с F1 и непрозрачность для владельца).

## API contracts (интерфейсы и форматы)
Политика `config/policies/gh.json`:
```json
{ "schemaVersion": 1, "cli": ["gh", "gh.exe"],
  "readCommands": ["pr view", "pr list", "pr diff", "pr checks", "pr status", "issue view", "issue list",
                   "repo view", "repo list", "run view", "run list", "workflow view", "workflow list",
                   "release view", "release list", "search", "auth status", "api", "version", "help"],
  "credentialCommands": ["auth token", "auth login", "auth logout", "auth refresh", "auth setup-git", "auth switch", "secret", "ssh-key", "gpg-key"],
  "credentialFlags": { "auth status": ["-t", "--show-token"] }, "credentialEnv": ["GH_TOKEN", "GITHUB_TOKEN", "GH_ENTERPRISE_TOKEN", "GH_CONFIG_DIR"],
  "writeCommands": ["pr merge", "pr create", "pr close", "issue create", "issue close", "repo delete", "release create", "release delete", "workflow run", "run rerun", "run cancel", "alias set", "extension install", "config set"],
  "apiMethodFlags": ["-X", "--method"], "apiBodyFlags": ["-f", "-F", "--field", "--raw-field", "--input"] }
```
Вывод хука — стандартный PreToolUse JSON: `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny|ask","permissionDecisionReason":"cli-perms: gh <key> is <tier>"}}`, код выхода 0. Режим модуля (E1, `state.json`) читается первым; `off` → выход 0 без вывода. Команда `/cli-perms check "<command>"` печатает уровень без исполнения (для отладки и фикстур).

## Data model / migrations
Состояния нет, кроме общего журнала `hook-lib`. Политики версионируются `schemaVersion`. Нативные `deny`-правила, добавленные модулем, помечаются в `installed.json` (E1), чтобы деинсталляция удалила ровно их.

## Security model
Защищаем: токен `gh` от вывода в контекст (credential-уровень плюс нативный deny); GitHub от незаметных изменений (запись всегда спрашивается или запрещается); от обхода через алиасы, расширения и неявный POST (неизвестное = запись).
Не защищаем: скрипты и бинарники, которые сами зовут `gh`; `gh`, переименованный или вызванный через интерпретатор иначе, чем распознаёт разбор (частично ловит «не разобрал → ask»); процессы исполнителей X1; сбой хука (fail-open, PF-12 — credential-уровень страхуют нативные правила, запись — нет).

## Risks
| Риск | Вероятность | Влияние | Митигация |
|---|---|---|---|
| Обход разбора экзотической формой команды | средняя | высокое | «не разобрал → ask», нативный deny для credential, фикстуры обходов из permissions.md |
| Лишние запросы на чтение (неизвестные read-подкоманды, новые версии `gh`) | высокая | низкое | `extraReadOnly` в конфиге, фикстуры на каждый релиз `gh`, `/cli-perms check` |
| `ask` молча одобрен в auto-режиме на 2.1.177 | средняя | высокое | В `auto`/`dontAsk`/`bypassPermissions` запись = `deny` |
| Расхождение разбора `.ps1` и `.sh` | средняя | среднее | Один набор фикстур на обе реализации, CI-паритет |

## Acceptance criteria
- AC1: выключенный модуль не выдаёт решений → S1.
- AC2: `gh auth token`, `gh auth status --show-token`, `gh secret list` запрещены всегда, в том числе в составной команде и через инструмент PowerShell → S2.
- AC3: `gh api -X DELETE …` и `gh pr merge 5` получают `ask` в default-режиме и `deny` в auto → S3.
- AC4: `gh pr list` не получает решения от хука → S4.
- AC5: `bash -c "gh pr merge 5"` получает `ask` → S5.

## Testing plan
behave подаёт в хук JSON входа PreToolUse и проверяет вывод; плюс табличные фикстуры (≥ 60, включая обе дыры `dsh-github-cli`) через `run-evals`.
```gherkin
Scenario: S1 disabled module is silent
  Given cli-perms is installed in mode "off"
  When the hook receives Bash command "gh auth token"
  Then the hook prints nothing and exits 0
Scenario Outline: S2 credential commands are always denied
  Given permission_mode "<mode>"
  When the hook receives <tool> command "<cmd>"
  Then the decision is "deny"
  Examples:
    | mode              | tool       | cmd                                      |
    | default           | Bash       | gh auth token                            |
    | bypassPermissions | Bash       | echo ok && gh auth status --show-token   |
    | default           | PowerShell | & gh.exe secret list                     |
Scenario Outline: S3 writes need explicit approval
  Given permission_mode "<mode>"
  When the hook receives Bash command "<cmd>"
  Then the decision is "<decision>"
  Examples:
    | mode    | cmd                                  | decision |
    | default | gh api -X DELETE /repos/o/r/labels/x | ask      |
    | default | gh pr merge 5 --squash               | ask      |
    | auto    | gh issue create --title t --body b   | deny     |
Scenario: S4 reads pass through the normal permission flow
  When the hook receives Bash command "gh pr list --state open -R o/r"
  Then the hook prints nothing and exits 0
Scenario: S5 unparseable wrapping asks
  When the hook receives Bash command "bash -c \"gh pr merge 5\""
  Then the decision is "ask"
```
Вручную: живой прогон в Claude Code 2.1.177 на Windows 10 — по одной команде каждого уровня через Bash и через PowerShell, плюс проверка нативного deny при выключенных хуках.

## Rollback plan
Режим `off` (E1) — хук молчит; нативные `deny`-правила остаются, пока модуль установлен (они безопасны). Деинсталляция через E1 удаляет запись хука из `settings.json` и ровно те `deny`-правила, что помечены в `installed.json`.

## Estimate (оценка объёма)
Разборщик подкоманд (bash-лексер, PowerShell AST, ключ команды, правила `gh api`) — 1.5 сессии; политика `gh`, нативные правила, установка и удаление через E1 — 0.5; фикстуры (≥ 60), behave S1–S5, паритет, живая проверка на 2.1.177 — 1. Итого ~3 сессии. Взорвать может: разбор bash-строк на стороне PowerShell (кавычки, экранирование), поведение `ask` в auto-режиме 2.1.177.

## План работ
Заполняется после аппрува.

## Definition of done
- [ ] Фикстуры: 0 пропущенных credential-команд, 0 молчаливых write, паритет `.ps1/.sh` 100 %
- [ ] behave S1–S5 зелёные на Windows и Linux; в `.ps1` нет кириллицы; матчер `Bash|PowerShell` проверен живым прогоном на 2.1.177
- [ ] `doctor` модуля: хук подключён, нативные deny на месте, `gh` найден

## Progress log
- 2026-09-27 — создан набросок спеки
