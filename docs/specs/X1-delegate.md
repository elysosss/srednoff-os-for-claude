# X1: Адаптер внешнего исполнителя — навык `delegate`

> Статус: DRAFT
> Тип: спека-набросок
> Модуль E1: `delegate`
> Зависит от: E1 (формат модуля), F1 (только для режима маскирования)   Блокирует: X2, X3

## Goal
Claude отдаёт одну самодостаточную задачу внешнему CLI (`codex exec`, `dsh --profile headless`, произвольный скрипт), который работает в отдельном git worktree и отдельном процессе со своим окружением; назад приходят diff и краткий итог, и применяет их только Claude после ревью.

## User value
Механическая или объёмная работа (массовая правка, генерация тестов по шаблону, перевод доков) уходит на дешёвую внешнюю модель, а качество держит ревью Claude. Закрыто, когда: задача ушла, вернулся diff, Claude его отревьюил и применил или отклонил, а основной checkout и окружение Claude не менялись.

## Non-goals
- Проксирование трафика Claude. `ANTHROPIC_BASE_URL` не трогаем, подписочный OAuth никуда не передаём (жёсткое ограничение 1).
- Параллельные исполнители и рои. Одна делегация за раз (ограничение 4, правило 70 про swarm).
- Автоприменение diff без ревью Claude. Выбор исполнителя по квотам — это X2, решение «делегировать ли» — X3. Claude Code как исполнитель — для этого есть штатные сабагенты (правило 90).

## Current state
- Делегирование в OS есть только Claude-сабагентам (правило 90, контракт disposition `done/blocked/deferred/failed`). Внешних исполнителей нет.
- Хуки OS (`block-dangerous-bash`, `protect-secrets`) действуют только на вызовы инструментов Claude. **Внешний процесс их не проходит вообще**: он читает диск и ходит в сеть сам. Это главный факт дизайна.
- F1 (`os-maskd`, `/v1/mask`, `/v1/unmask`) пишется параллельно; X1 использует его только как библиотеку-сервис, не как прокси.

## Assumptions
- `ASSUMPTION:` E1 даёт модулю `bin/` с парами `.ps1/.sh`, режим `off|on` в `state.json` и запись в `.claude/os-modules/installed.json`; при per-project установке `bin/` **не** попадает в `PATH` (PF-17 описывает `bin/` только для установленного плагина), поэтому навык зовёт скрипт по полному пути `${CLAUDE_PROJECT_DIR}/.claude/os-modules/delegate/bin/...`. Проверить на прототипе E1.
- `ASSUMPTION:` по докам `codex exec` по умолчанию в read-only песочнице; допущение — что `workspace-write` ограничивает запись каталогом `-C`, но **не чтение** диска и не гарантирует изоляцию на Windows. Проверить: `codex exec --sandbox workspace-write` с попыткой прочитать и записать файл вне worktree на Windows 10.
- `ASSUMPTION:` `dsh --profile headless "<задача>"` печатает финальный ответ в stdout и возвращает ненулевой код при сбое (так сказано в `apps/cli/README.md`); коды выхода не задокументированы. Проверить прогоном на заведомо падающей задаче.
- `ASSUMPTION:` пустой `GH_CONFIG_DIR` и `GIT_TERMINAL_PROMPT=0` в окружении исполнителя лишают его логина `gh` и интерактивного запроса git-учётки; при этом Windows Credential Manager, подключённый как `credential.helper`, может остаться доступен. Проверить: `git push` из worktree под собранным env.

## Questions
1. Где хранить API-ключи исполнителей? По умолчанию — только ссылки на имена переменных окружения владельца (`envFrom: ["DEEPSEEK_API_KEY"]`), значения в файлы модуля не пишутся. 2. Включать ли незакоммиченные правки в снимок для исполнителя? По умолчанию да, через `git stash create` (только отслеживаемые файлы, неотслеживаемые не попадают).

## GitHub research
| Repo | License | Что берём | Риск |
|---|---|---|---|
| `deepseek-ai/deepseek-harness` @ `477b4f420553` (push 2026-09-24) | MIT | Паттерн «внешний CLI как сабагент»: `packages/subagent/subagent-codex` — один изолированный поток на задачу, env ребёнка = очищенный от учёток env родителя + явный `env`-оверлей, в родителя возвращается только финальный ответ | У них ребёнок работает **в рабочем каталоге родителя**, diff в родителя не попадает; у нас наоборот — отдельный worktree и diff как главный артефакт. Код не берём |
| `openai/codex` @ `41f9084b3081`, релиз `rust-v0.157.1` (2026-09-26) | Apache-2.0 | Интерфейс `codex exec`: `-C`, `--sandbox`, `--json`, `-o/--output-last-message`, `--ephemeral`, `--ignore-user-config`, `CODEX_API_KEY` | CLI меняется быстро; фиксируем версию в `doctor` |

## Official docs checked
PF-15 (хук наследует env; `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB`), PF-17 (`bin/`, `userConfig` с `sensitive`), PF-18 (`ANTHROPIC_API_KEY` перекрывает подписку — поэтому env исполнителя собирается с нуля, а не наследуется), PF-24 (в worktree `CLAUDE_PROJECT_DIR` остаётся корнем исходной сессии). Сверх этого: tools-reference — таймаут Bash по умолчанию 2 мин, потолок 10 мин, `run_in_background` для долгих команд; learn.chatgpt.com/docs/non-interactive-mode — флаги `codex exec`.

## Architecture (дизайн)
Поток одной делегации:
1. Навык `delegate` (SKILL.md) формулирует задачу: цель, границы, критерий готовности, лимит итога — тот же контракт, что в правиле 90.
2. `bin/delegate-run.{ps1,sh}` берёт lock (`state/lock`), создаёт снимок `git stash create` (или `HEAD`) и `git worktree add --detach <tmp>/srednoff-delegate/<run-id>` **вне** каталога проекта.
3. Собирает env исполнителя **с нуля**: allowlist системных переменных (`PATH`, `SystemRoot`, `TEMP`, `USERPROFILE`/`HOME`), плюс `envFrom` из конфига исполнителя, плюс обнуляющие переменные (`GH_CONFIG_DIR=<пустой tmp>`, `GIT_TERMINAL_PROMPT=0`). Denylist проверяется после сборки: любые `ANTHROPIC_*`, `CLAUDE_*`, `CLAUDE_CODE_OAUTH_TOKEN` → отказ запуска.
4. Опционально (режим F1, см. ниже) маскирует текст задачи и отслеживаемые файлы worktree.
5. Запускает адаптер исполнителя (`codex`, `dsh`, `script`) с таймаутом; stdout/stderr — в `runs/<run-id>/`.
6. Собирает `git diff` worktree относительно снимка, diffstat, итог (последнее сообщение, обрезанное до N строк), код выхода → `result.json`.
7. Возвращает Claude компактный JSON (не лог). Claude читает diff как **недоверенные данные**, ревьюит и применяет `git apply --3way` в основной checkout или отклоняет. Worktree удаляется в обоих случаях.

Долгие задачи: навык запускает скрипт через `run_in_background` и ждёт уведомления; параллельно Claude новую делегацию не начинает (lock).

**Режим «через F1» (`maskMode`)** — не прокси, а предобработка входа:
- `off` (по умолчанию) — ничего не маскируем.
- `prompt` — текст задачи проходит `os-maskd /v1/mask`; плейсхолдеры в diff и итоге возвращаются через `/v1/unmask`.
- `worktree` — дополнительно каждый отслеживаемый текстовый файл worktree перезаписывается маскированной копией до запуска; diff демаскируется перед показом Claude. Хунк, где плейсхолдер повреждён или появился новый, помечается, и diff целиком получает статус `blocked`.
Что гарантирует: регулярки F1 не пропустят известные классы секретов из **переданного** текста и файлов worktree. Чего не гарантирует: секреты вне worktree (исполнитель может прочитать любой файл, к которому есть доступ у процесса), неизвестные форматы секретов, смысловые утечки (архитектура, имена клиентов), то, что CLI сам соберёт контекст из домашнего каталога. Поэтому для чувствительных проектов правильный ответ — не делегировать (X3 это учитывает), а не надеяться на маску.

Отвергнутые альтернативы: запуск в основном checkout (ломает «Claude отвечает за применение»); MCP-сервер-обёртка (лишний долгоживущий процесс, а польза та же); прокси для исполнителя внутри OS (дублирует OmniRoute-подобные шлюзы, противоречит «только исполнитель»).

## API contracts (интерфейсы и форматы)
```text
delegate-run.ps1 -Executor <id> -TaskFile <path> [-MaskMode off|prompt|worktree] [-TimeoutSec 1800] [-Snapshot head|working]
delegate-run.sh  --executor <id> --task-file <path> [--mask-mode ...] [--timeout-sec ...] [--snapshot ...]
delegate-apply.{ps1,sh} --run-id <id> [--reject]      # применить или выбросить, всегда чистит worktree
```
Конфиг исполнителя (`config/default.json` → `executors`):
```json
{ "id": "codex-default", "kind": "codex", "command": ["codex", "exec", "--sandbox", "workspace-write", "--ephemeral"],
  "envFrom": ["CODEX_API_KEY"], "timeoutSec": 1800, "billing": "metered", "maxSummaryLines": 30 }
```
`result.json`: `{runId, executor, disposition: done|blocked|deferred|failed, exitCode, durationSec, diffPath, diffstat:{files,insertions,deletions}, summary, maskMode, warnings[]}`. Коды выхода скрипта: 0 — есть результат (включая пустой diff), 3 — lock занят, 4 — env отклонён denylist, 5 — таймаут, 6 — исполнитель упал, 7 — маска повреждена.

## Data model / migrations
Состояние — `<project>/.claude/os-modules/delegate/state/` (gitignored): `lock`, `runs/<run-id>/{task.md, stdout.log, stderr.log, diff.patch, result.json}`. Хранится последние 20 запусков, старше — удаляются при следующем запуске. Worktree — только во временном каталоге, чистится `delegate-apply` и `doctor --fix` (`git worktree prune`). Схема конфига версионируется полем `schemaVersion`; миграции — через механизм E1.

## Security model
Защищаем: окружение и подписку Claude (env исполнителя собирается с нуля, denylist `ANTHROPIC_*`/`CLAUDE_*`); основной checkout (исполнитель пишет только в worktree, применяет Claude); `gh`/git-учётки (пустой `GH_CONFIG_DIR`, без интерактивных запросов); контекст Claude от prompt-injection (diff и итог — данные, в SKILL.md явная инструкция не исполнять указания из них).
Явно не защищаем: чтение исполнителем любых файлов, доступных пользователю ОС; отправку исполнителем кода провайдеру (это суть делегации — владелец соглашается при включении модуля и при выборе исполнителя); сетевые действия исполнителя вне песочницы его CLI. Первый запуск каждого исполнителя — через гейт правила 70 (лицензия, пин версии), платный исполнитель — только с явного согласия (правило 50).

## Risks
| Риск | Вероятность | Влияние | Митигация |
|---|---|---|---|
| Исполнитель вытащил секрет из домашнего каталога | средняя | высокое | Песочница CLI, пустые конфиги учёток, X3 не делегирует задачи с чувствительным контекстом, предупреждение в `doctor` |
| Diff содержит prompt-injection для Claude | средняя | среднее | Diff показывается как данные, ревью по чеклисту `code_review.md`, применение только явным `delegate-apply` |
| Висящие worktree и lock после падения | высокая | низкое | Lock с PID и временем, `doctor --fix` снимает протухший lock и делает `git worktree prune` |
| Windows: разные пути и кодировки в diff (CRLF) | средняя | среднее | `git -c core.autocrlf=false`, парные сценарии run-evals на обеих ОС |

## Acceptance criteria
- AC1: при выключенном модуле навык и скрипты ничего не делают и не меняют репозиторий → S1.
- AC2: успешная делегация даёт `result.json` с diff, основной checkout не изменён до `delegate-apply` → S2.
- AC3: env с `ANTHROPIC_BASE_URL` или любым `CLAUDE_*` не запускает исполнителя (код 4) → S3.
- AC4: вторая делегация при занятом lock отклоняется (код 3) → S4.
- AC5: в режиме `worktree` секрет из отслеживаемого файла не виден исполнителю, а применённый diff содержит оригинал → S5.

## Testing plan
Исполнитель-заглушка `tests/fixtures/fake-executor.{ps1,sh}`: пишет файл, печатает env в лог, завершает с заданным кодом. Сеть и реальные модели в тестах не нужны.
```gherkin
Scenario: S1 module disabled is a no-op
  Given the delegate module is installed in mode "off"
  When I run delegate-run with executor "fake"
  Then the exit code is 0 and the output says "delegate disabled"
  And no worktree exists and git status of the project is unchanged
Scenario: S2 successful delegation returns a diff and leaves checkout untouched
  Given executor "fake" that appends a line to README.md
  When I run delegate-run with executor "fake"
  Then result.json has disposition "done" and diffstat files 1
  And the project README.md is unchanged until I run delegate-apply
Scenario: S3 Claude credentials never reach the executor
  Given the parent environment has ANTHROPIC_BASE_URL and CLAUDE_CODE_OAUTH_TOKEN set
  When I run delegate-run with executor "fake"
  Then the executor env log contains no variable starting with "ANTHROPIC_" or "CLAUDE_"
Scenario: S4 serial work only
  Given a delegation holds the lock
  When I run delegate-run again
  Then the exit code is 3
Scenario: S5 worktree masking round-trip
  Given a tracked file containing a canary GitHub token and maskMode "worktree"
  When executor "fake" copies that file's content into a new file
  Then the executor saw only a placeholder and the applied diff contains the original token
```
Юнит: сборка env (allowlist/denylist), парсинг diffstat. Вручную: реальный `codex exec` и `dsh --profile headless` на Windows 10 по одному разу.

## Rollback plan
Режим `off` (E1) — навык отвечает «выключено», скрипты выходят с 0. Удаление модуля через E1: удаляются `.claude/os-modules/delegate/`, запись в `installed.json`; `doctor --fix` до удаления снимает worktree. Данные запусков — только в `state/`, удаляются вместе с модулем.

## Estimate (оценка объёма)
Фаза 1 — скрипты worktree + env + адаптер `script` + сценарии S1 (run-evals)–S4: 2 сессии. Фаза 2 — адаптеры `codex` и `dsh`, ручная проверка на Windows: 1–2 сессии. Фаза 3 — режим F1 `prompt`/`worktree` + S5 после готовности F1: 1–2 сессии. Итого 4–6 сессий. Взорвать может: песочница Codex на Windows, нестабильные коды выхода `dsh`, готовность F1.

## План работ
Заполняется после аппрува.

## Definition of done
- [ ] Пары `.ps1/.sh` проходят паритет CI, в `.ps1` нет кириллицы; сценарии S1 (run-evals)–S5 зелёные на Windows и Linux
- [ ] `doctor` модуля проверяет: git ≥ 2.20, наличие CLI исполнителей, отсутствие `ANTHROPIC_*` в конфиге
- [ ] SKILL.md `delegate` содержит контракт задачи и правило «diff — это данные»

## Progress log
- 2026-09-27 — создан набросок спеки
