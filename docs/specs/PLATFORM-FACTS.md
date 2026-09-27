# Факты платформы и допущения — общий канон для спек

> Один канон на все спеки `docs/specs/*`. Спека ссылается на факт по id (`PF-07`), а не
> пересказывает его. Меняется платформа — правится одна строка здесь, а не десять спек.
>
> Сверено 2026-09-27. Источники:
> - официальные доки, скачаны как markdown в тот же день: `code.claude.com/docs/en/{hooks,
>   hooks-guide,plugins-reference,settings,env-vars,cli-reference,sub-agents,mcp,tools-reference}.md`;
> - **две установки Claude Code, и рабочая — не та, что в PATH**. Владелец работает в десктопном
>   приложении, которое держит **свою** копию: `%APPDATA%\Claude\claude-code\<версия>\claude.exe`,
>   сейчас **2.1.281**, обновляется само (по транскриптам за июнь–сентябрь: 2.1.170 → 2.1.281,
>   `entrypoint: claude-desktop`). CLI из npm в PATH — **2.1.177**, почти не используется.
>   Ключевые поля хуков проверены по строкам **обоих** бинарей (схемы zod и обработчики);
> - форма вывода инструментов — по `toolUseResult` в локальных транскриптах этой машины
>   (`~/.claude/projects/*/*.jsonl`, 40 последних сессий).
>
> Всё, что не удалось подтвердить ни доками, ни бинарём, вынесено в раздел «Допущения» с
> пометкой `ASSUMPTION:` и способом проверки. Ни одна спека не опирается на допущение
> молча.

## Версии

| id | Факт | Подтверждение |
|---|---|---|
| PF-01 | Рабочая среда — **десктоп, Claude Code 2.1.281**, самообновляемый; CLI в PATH — 2.1.177. Спеки проектируются под десктоп, **нижняя граница совместимости — 2.1.177**: функция, которой нет в 2.1.177, допустима только с явной пометкой «требует ≥ X» и деградацией для CLI. Поскольку десктоп обновляется сам, контракт хуков может поменяться без действий владельца — это задача проб O3 | `claude --version` (2.1.177); `%APPDATA%\Claude\claude-code\2.1.281\claude.exe --version`; поля `version`/`entrypoint` транскриптов |
| PF-25 | Поле `mcp_server` (имя и `source` MCP-сервера) во входе PreToolUse/PostToolUse появилось в **v2.1.274**: в десктопе 2.1.281 есть (строка `mcp_server` в бинаре), в CLI 2.1.177 нет. Доверие к MCP-серверу строится по `mcp_server.source`, а при его отсутствии — по префиксу `mcp__<server>__` имени инструмента | доки hooks, PreToolUse input; бинарь 2.1.281 |

## Хуки: переписывание данных

| id | Факт | Подтверждение |
|---|---|---|
| PF-02 | `PostToolUse` → `hookSpecificOutput.updatedToolOutput` заменяет результат **любого** инструмента до того, как его увидит модель. Для встроенных инструментов значение валидируется схемой вывода инструмента; **не прошедшее валидацию значение молча игнорируется и модель получает оригинал**. MCP-вывод не валидируется | доки hooks → PostToolUse decision control; бинари 2.1.177 и 2.1.281: `outputSchema?.safeParse(…updatedToolOutput)?.success!==!1` |
| PF-03 | `PostToolUse` с `decision:"block"` **не скрывает** оригинальный вывод — только добавляет `reason` рядом | доки hooks, таблица PostToolUse |
| PF-04 | Телеметрия (OTel-спаны, аналитика) фиксирует оригинальный вывод **до** хука | доки hooks, Warning к `updatedToolOutput` |
| PF-05 | `PreToolUse` → `hookSpecificOutput.updatedInput` заменяет вход инструмента целиком (неизменённые поля нужно вернуть). **Без `permissionDecision`** вход подменяется, а обычный поток разрешений идёт как шёл. С `"allow"` — подмена **и пропуск запроса разрешения**. Правила разрешений проверяются уже по подменённому входу | доки hooks → PreToolUse decision control; бинари 2.1.177 и 2.1.281: `updatedInput&&….permissionBehavior===void 0` → `hookUpdatedInput` |
| PF-06 | Все совпавшие хуки события запускаются **параллельно**. Приоритет решений: `deny` > `defer` > `ask` > `allow`. Что происходит, когда `updatedInput`/`updatedToolOutput` вернули два хука сразу, доки не описывают — см. A-03 | доки hooks |
| PF-07 | `UserPromptSubmit` **не может переписать промпт** — только заблокировать (`decision:"block"`: промпт стирается из контекста, `reason` видит пользователь, но не модель) или добавить `additionalContext`. Поле `prompt` приходит с уже развёрнутыми вставками (`[Pasted text #N]` раскрыт) | доки hooks → UserPromptSubmit; таблица «can't replace the prompt» |
| PF-21 | Поле `if` у обработчика (синтаксис правил разрешений, `Bash(gh *)`) фильтрует запуск на событиях инструментов. Фильтр best-effort: если Claude Code не может разобрать команду, хук запускается всегда | доки hooks → Common fields |

| PF-28 | На Windows с установленным Git Bash инструмент **`PowerShell`** включён по умолчанию для аккаунтов claude.ai и Console (без Git Bash — включён всегда; `CLAUDE_CODE_USE_POWERSHELL_TOOL=0` выключает). Хуки с матчером `Bash` его вызовы **не видят** — нужен матчер `Bash\|PowerShell`. Все хуки OS сейчас матчатся только на `Bash` (`hooks/hooks.json`, `settings*.example.json`) | доки env-vars → `CLAUDE_CODE_USE_POWERSHELL_TOOL`; наблюдается в этой сессии (инструмент PowerShell доступен) |

## Хуки: чего они не видят

| id | Факт | Подтверждение |
|---|---|---|
| PF-08 | Файлы, упомянутые через `@` в промпте, вставляются **без вызова инструмента**: ни PreToolUse, ни PostToolUse (включая матчер `Read`) не срабатывают. Доки предлагают вместо этого deny-правило `Read(...)` в разрешениях | доки hooks, Warning в PreToolUse |
| PF-09 | `CLAUDE.md`, правила `.claude/rules/*`, авто-память грузятся без инструментов. Событие `InstructionsLoaded` есть, но **без управления решением** — замаскировать загружаемое нельзя | доки hooks, таблица Decision control |
| PF-10 | Хуки из settings-файлов и плагинов **срабатывают внутри сабагентов** на их вызовах инструментов; во входе есть `agent_id` и `agent_type` | доки hooks → Hook locations |

## Хуки: сбои, таймауты, жизненный цикл

| id | Факт | Подтверждение |
|---|---|---|
| PF-11 | `SessionEnd`: причины `clear`, `resume`, `logout`, `prompt_input_exit`, `other`. Общий бюджет **1.5 с** (поднимается per-hook `timeout` до 60 с, у хуков плагинов — нет). Решения не принимает. При `kill`/падении процесса очевидно не срабатывает | доки hooks → SessionEnd |
| PF-12 | Таймаут по умолчанию: 600 с у `command`/`http`, **30 с** на `UserPromptSubmit`. **Истёкший по таймауту `PreToolUse`-хук не блокирует вызов** — вызов идёт обычным потоком разрешений. Любой код выхода, кроме 2, без валидного JSON — неблокирующая ошибка. Exit 2 блокирует `PreToolUse` и `UserPromptSubmit`. Не найденный скрипт (exit 127) — тоже неблокирующая ошибка | доки hooks → Exit code output, Timeouts |
| PF-13 | `http`-хук: обрыв соединения, не-2xx, таймаут — **неблокирующая ошибка, действие продолжается**. Запретить можно только ответом 2xx с JSON. Значит, `http`-хук по конструкции fail-open | доки hooks → HTTP response handling |
| PF-14 | Exec-форма (`command` + `args`, без шелла) есть в 2.1.177. На Windows `command` в exec-форме обязан быть настоящим `.exe`. Есть поле `shell: "bash"\|"powershell"` | бинари 2.1.177 и 2.1.281: `args:…array(…string()).optional().describe("Argument list for exec form…")`; доки hooks |
| PF-15 | Хуку экспортируются `CLAUDE_PROJECT_DIR`, у плагинов ещё `CLAUDE_PLUGIN_ROOT`, `CLAUDE_PLUGIN_DATA`, `CLAUDE_PLUGIN_OPTION_<KEY>`. Хук наследует окружение Claude Code; `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=1` вычищает учётные данные из окружения Bash, хуков и stdio-MCP | доки hooks, plugins-reference, env-vars |
| PF-16 | Settings-файлы отслеживаются; правки `hooks` и `permissions` подхватываются **без перезапуска**; на каждое изменение файла срабатывает хук `ConfigChange` (может заблокировать изменение, кроме policy). `disableAllHooks` выключает все не-managed хуки | доки settings → When edits take effect; hooks → Disable |
| PF-24 | В worktree `${CLAUDE_PROJECT_DIR}` остаётся корнем исходной сессии, а `cwd` во входе хука следует за Claude | доки hooks → Reference scripts by path |
| PF-26 | stdout успешного хука **пишется в debug-лог** (`~/.claude/debug/<session-id>.txt`), но только при запуске с `--debug`/`--debug-file`; по умолчанию debug-лога нет (на этой машине каталога `~/.claude/debug` нет). Значит, `updatedInput` с оригиналами окажется в debug-логе, если сессия запущена с `--debug` | доки hooks → Debug hooks; `ls ~/.claude/debug` |
| PF-27 | stdout хука обязан быть **одним JSON-объектом**; невалидный JSON или JSON, не прошедший схему, — неблокирующая ошибка, действие продолжается (fail-open). `additionalContext`/`systemMessage` обрезаются на 10 000 символов (остаток уходит в файл сессии) | доки hooks → JSON output, Exit code 0 |

## Плагины (кандидат в формат модуля)

| id | Факт | Подтверждение |
|---|---|---|
| PF-17 | Манифест `.claude-plugin/plugin.json`, обязательное поле одно — `name`. Есть `version`, `defaultEnabled`, `dependencies`, `userConfig` (значения `sensitive: true` уходят в защищённое хранилище ОС, не в `settings.json`), свободный объект `metadata` (**Claude Code его не читает** — место под поля OS). Неизвестные ключи верхнего уровня молча выбрасываются. `bin/` плагина попадает в `PATH` инструмента Bash. `${CLAUDE_PLUGIN_DATA}` = `~/.claude/plugins/data/<id>/`, переживает обновления, удаляется при деинсталляции. `--plugin-dir <путь>` грузит плагин **на одну сессию без установки** | доки plugins-reference |

## Окружение и маршрутизация

| id | Факт | Подтверждение |
|---|---|---|
| PF-18 | `ANTHROPIC_BASE_URL` переопределяет endpoint API (прокси/шлюз). `ANTHROPIC_API_KEY` **перекрывает подписку**, даже если выполнен вход (в `-p` — всегда). `CLAUDE_CONFIG_DIR` переопределяет каталог конфигурации: настройки, история, плагины | доки env-vars |

## Форма вывода инструментов (для `updatedToolOutput`)

| id | Факт | Подтверждение |
|---|---|---|
| PF-19 | Наблюдаемые формы `toolUseResult` (2.1.177, эта машина): **Read** `{type, file:{filePath, content, numLines, startLine, totalLines}}` (иногда строка); **Bash/PowerShell** `{stdout, stderr, interrupted, isImage[, noOutputExpected]}` (иногда строка); **Grep** `{mode, filenames[], numFiles, content?, numLines?}`; **Glob** `{filenames[], numFiles, truncated, durationMs}`; **WebFetch** `{result, url, code, codeText, bytes, durationMs}`; **WebSearch** `{query, results[], ...}`; **Edit** `{filePath, oldString, newString, originalFile, structuredPatch[], replaceAll, userModified}`; **Write** `{filePath, content, originalFile, structuredPatch[], type, userModified}`; **TaskOutput** `{task:{output, result, ...}}`; **MCP** — массив content-блоков | локальные транскрипты; см. A-05 |
| PF-20 | Проверка «файл изменён после чтения» у Edit/Write в 2.1.177 сравнивает **mtime** с меткой времени чтения, а не содержимое. Значит, маскированный Read сам по себе не ломает последующий Edit | бинари 2.1.177 и 2.1.281: `if(<mtime>(f)>…timestamp)return{…"File has been modified since read…"}`; подтвердить спайком F1 |

## Допущения (не подтверждены — проверить до реализации)

| id | Допущение | Как проверить | Кому важно |
|---|---|---|---|
| A-01 | `ASSUMPTION:` вызовы инструментов сабагента приходят в хук с **тем же `session_id`**, что и у родителя (доки говорят только про `agent_id`) | спайк: логирующий хук + вызов `Agent`, сравнить `session_id` | F1 (общая таблица соответствий) |
| A-02 | `ASSUMPTION:` что пишется в транскрипт `.jsonl` после `updatedToolOutput` — оригинал или замена — **неизвестно**. Если оригинал, то (а) секреты лежат на диске в `~/.claude/projects`, (б) при `--resume` контекст может восстановиться **с оригиналами** и уйти модели | спайк: канарейка в файле → Read под фильтром → `grep` канарейки в транскрипте → `--resume` и вопрос модели о значении | F1 — **блокирующий** |
| A-03 | `ASSUMPTION:` если `updatedInput` (или `updatedToolOutput`) вернули два хука на один вызов, выигрывает один из них непредсказуемо. Пока не доказано обратное, F1 должен быть **единственным** хуком, переписывающим эти инструменты | спайк: два хука с разными `updatedInput` | F1, X4, E1 (конфликт модулей) |
| A-04 | `ASSUMPTION:` команды bash-режима (`! cmd` в строке ввода) выполняются без PreToolUse/PostToolUse, а их вывод попадает в контекст как есть | спайк: `! echo <канарейка>` под фильтром | F1 (дыра) |
| A-05 | `ASSUMPTION:` форма `tool_response` в PostToolUse совпадает с `toolUseResult` из транскрипта (PF-19). Доки подтверждают это только для Write и Bash | спайк: хук-дампер `tool_response` на каждый инструмент | F1 (адаптеры вывода) |
| A-06 | `ASSUMPTION:` MCP-ресурсы, упомянутые через `@server:uri`, вставляются так же, как `@`-файлы, — мимо хуков. Доки говорят «similar to how you reference files», но явно про хуки не пишут | спайк с любым MCP-сервером с ресурсами | F1 (дыра) |
| A-07 | `ASSUMPTION:` сводка `/compact` строится из уже маскированных сообщений и новых оригиналов не вносит | следует из PF-02, если A-02 закрыт положительно; проверить спайком | F1 |
| A-08 | `ASSUMPTION:` хук `PreToolUse`, вернувший `updatedInput`, не показывает модели подменённый вход (в 2.1.177 факт подмены пишется только в debug-лог: `Hook ... modified tool input keys`) | бинарь указывает на это; подтвердить спайком | F1 |
| A-09 | `ASSUMPTION:` текст результата Edit/Write, который видит модель (сниппет «cat -n» вокруг правки), строится из полей структурного вывода (`newString`, `structuredPatch`, `originalFile`), и их маскирование через `updatedToolOutput` доходит до модели. Если сниппет строится иначе, оригинал, подставленный PreToolUse, **вернётся в контекст через результат правки** | спайк: Edit с плейсхолдером → что видит модель в tool_result | F1 — **блокирующий** |
| A-10 | `ASSUMPTION:` строки `` !`cmd` `` в файле команды (`.claude/commands/*.md`) выполняются при раскрытии команды пользователем **без** PreToolUse — то есть это канал, которым пользователь может переключить режим, а модель своим Bash-вызовом — нет | спайк: команда с `!` + логирующий PreToolUse | F1 (самозащита `/os-filter`) |
| A-11 | `ASSUMPTION:` в поле `prompt` хука `UserPromptSubmit` `@путь` остаётся сырым текстом, по которому хук может найти упомянутый файл | спайк: промпт с `@file` + дамп входа хука | F1 (закрытие дыры PF-08) |
| A-12 | `ASSUMPTION:` у `updatedToolOutput` нет лимита размера, аналогичного 10 000 символам у `additionalContext` (PF-27); замена вывода Read на 256 КБ проходит целиком | спайк: Read большого файла с канарейками в конце | F1 |
| A-13 | `ASSUMPTION:` плейсхолдер `${CLAUDE_PROJECT_DIR}` подставляется в `command`/`args` exec-формы и для хуков из **проектного** settings-файла (доки показывают exec-форму только с `${CLAUDE_PLUGIN_ROOT}`), в том числе на Windows с путём, содержащим пробелы | спайк: exec-хук из `.claude/settings.local.json` в каталоге с пробелом | E1, F1 |
| A-14 | `ASSUMPTION:` неизвестный ключ в объекте обработчика хука (например, метка модуля) приводит в 2.1.177 к ошибке валидации settings | спайк: хук с лишним ключом, смотреть `/hooks` и debug-лог | E1 |

## Движок фильтра — `cloud-ru-tech/guardrails-llm-filter` (сверено по GitHub API 2026-09-27)

| id | Факт |
|---|---|
| GF-01 | Apache-2.0, Go (`go 1.26.5` в `go.mod`), 182★, последний push 2026-09-07, релиз `v0.1.2.1` от 2026-07-26. **Проект молодой (0.1.x)** — стабильность API не обещана |
| GF-02 | Правил: 46 в `configs/guardrails_regex_rules.yaml` + 220 в `configs/guardrails_regex_rules.gitleaks.generated.yaml` = **266**. Валидаторы: `luhn, snils, inn_person, inn_org, ogrn, ogrnip, iban_mod97, email_ascii, payment_card, ip_v4, ip_v6, ip_public, ip_private` |
| GF-03 | **Импортируемы** (лежат в `pkg/`): `pkg/guardrails/regex/{registry, rule, scanners/sensitive, scanners/placeholder, validation, placeholderfmt}`; есть перезагружаемый реестр (`registry/reloadable.go`) |
| GF-04 | **Не импортируемы** (лежат в `internal/`, Go запрещает импорт извне модуля): маскировщик с дедупом (`internal/usecases/guardrails/mask`), демаскировщик (`internal/guardrails/demask`), загрузка встроенных правил (`internal/usecases/rules/builtins`). Их придётся написать заново или вендорить с соблюдением NOTICE |
| GF-05 | Отдельный API «замаскируй текст» **есть**, в отличие от сказанного в брифе: `POST /v1/scan` — dry-run тем же продакшн-пайплайном, ничего не хранит, upstream не зовёт, возвращает `masked_texts`, `placeholders[{placeholder, original, rule_id}]`, `triggered_rule_ids`, `total_ms`. Но стартовать процесс без `GUARDRAILS_UPSTREAM_BASE_URL` нельзя, а admin-API **без аутентификации** |
| GF-06 | Плейсхолдеры апстрима — `<TYPE_N>` со счётчиком **в пределах одного запроса**; между запросами не стабильны. Для F1 нужна своя схема |
| GF-07 | Режимы `enforce` / `detect` (shadow), типы данных 1–6 = `CREDENTIALS, API_KEYS, ACCESS_TOKENS, IP_ADDRESSES, PERSONAL_DATA, CUSTOM` — совпадают с брифом. Кастомные правила сканируются, только если включён тип `CUSTOM` |

## Допущения из набросков бэклога

Сформулированы в самих спеках (там же — как проверить); здесь только реестр с id, чтобы
спайки можно было планировать одним списком. Проверяются при переходе конкретной спеки из
наброска в полную.

| id | Допущение (кратко) | Спека |
|---|---|---|
| A-15 | вход PreToolUse инструмента `PowerShell` содержит `tool_input.command`, как у Bash | X4, F1 |
| A-16 | поле `permission_mode` приходит во вход PreToolUse (в схеме бинаря есть; по событиям не сверено) | X4 |
| A-17 | хуковый `ask` в режиме `auto` не одобряется классификатором молча — по докам исправлено в v2.1.211, т.е. в десктопе 2.1.281 верно, в CLI 2.1.177 — нет | X4 |
| A-18 | нативные Bash-правила разрешений делят составные команды (`&&`, `;`, `\|`) | X4 |
| A-19 | `claude auth status --json` меняет `authMethod` при активных `ANTHROPIC_API_KEY`/`ANTHROPIC_AUTH_TOKEN`/`apiKeyHelper` | O1 |
| A-20 | `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=1` не вычищает `ANTHROPIC_BASE_URL` из окружения хука | O1 |
| A-21 | пустое `"ANTHROPIC_BASE_URL": ""` в `env` settings-файла гасит экспорт из шелла | O1 |
| A-22 | `claude -p` на подписке выполняет проектные хуки так же, как интерактивная сессия | O3 |
| A-23 | хуки из `--settings` добавляются к хукам нижних уровней, а не заменяют их | O4 |
| A-24 | с `CLAUDE_CONFIG_DIR` ничего не читается из `~/.claude` и `~/.claude.json`; новый каталог требует повторного входа | O4 |
| A-25 | запуск подписки на своей VM (O5) не противоречит условиям Anthropic для потребительских планов — **нужна юридическая проверка до реализации** | O5 |
| A-26 | правки `CLAUDE.md`/правил доходят до модели только после `/compact`/`/clear` или перезапуска; `ConfigChange` срабатывает на project/local settings | E2, C1 |
| A-27 | `additionalContext` из `SessionStart` прикрепляется к разговору, а не к системному промпту, и не выдаётся сабагентам | C3, C1 |
| A-28 | `bashOutputMaxChars` в проектных настройках учитывается десктопом 2.1.281 | C2 |
| A-29 | нативные deny-правила `Edit(...)` срабатывают и на запись через инструмент PowerShell (`Set-Content`, `Out-File`, `>`), а не только на распознанные команды Bash | D3 |
| A-30 | у сабагента с `isolation: worktree` поле `cwd` во входе хука указывает внутрь его worktree | D3 |
| A-31 | вход PreToolUse для инструмента `Agent` содержит `subagent_type` и `prompt` | D4 |
| A-32 | `claude -p --agent <имя>` есть в 2.1.177 и 2.1.281 и выполняет проектные хуки (связано с A-22) | D4 |
| A-33 | `--resume` сохраняет прежний `session_id` | D4, D3 |
| A-34 | в транскриптах есть поля `cwd` и `gitBranch` (в 2.1.177 тоже) | D9 |
| A-35 | `systemMessage` из `SessionStart` виден пользователю, но не попадает в контекст модели | D9 |
