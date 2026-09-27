# O1: `/os-doctor` — доктор OS: демон F1, исполнители, порты, endpoint Claude

> Статус: DRAFT
> Тип: спека-набросок
> Модуль E1: не модуль — расширение ядра `scripts/doctor.{ps1,sh}`; команда `/os-doctor` ставится вместе с ядром
> Зависит от: E1 (контракт модуля, `installed.json`), F1 (`os-maskd`)   Блокирует: O2, O3, O5

## Goal
Одна команда отвечает «запустится ли OS в этом проекте и не утекает ли трафик Claude мимо подписки»: ядро, модули E1, демон F1, исполнители, порты и отдельная проверка, что у Claude нигде не выставлен `ANTHROPIC_BASE_URL`.

## User value
Сейчас fail-open обнаруживается постфактум (история PR #8/#9: `grep -P` и локаль молча гасили правила). Закрыто, когда `/os-doctor` в проекте без глобальной установки даёт один вердикт OK/WARN/FAIL и называет источник каждой проблемы (файл/переменная), не печатая значений.

## Non-goals
- Не новый инструмент: параллельного `os-doctor.ps1` не будет, расширяется существующий `doctor.*`.
- Не встроенный `/doctor` Claude Code и не `claude doctor` (последний в 2.1.177 пропускает trust-диалог и **запускает stdio-MCP из `.mcp.json`** — побочный эффект, по умолчанию не вызываем).
- Не чинит endpoint/учётные данные сам: только диагноз и точная команда исправления.

## Current state
`doctor.*` уже умеет 15 проверок (jq-dependency … fix-safe), вывод `--json` `{overall, checks[{name,status,detail}]}`. Жёстко привязан к `$HOME/.claude/registry` и шаблону в `~/.claude/templates` — в папочном режиме (HANDOFF §2) работает только через фальшивый HOME (§5). Проверка `version-control` делает `git add -A` в registry/template — в папочном режиме это был бы автокоммит в чекаут форка (грабли HANDOFF §6.1). Модулей, демонов и проверки endpoint нет.

## Assumptions
- `ASSUMPTION:` `claude auth status --json` (есть в 2.1.177, поля `loggedIn, authMethod, apiProvider, subscriptionType`) меняет `authMethod` при активных `ANTHROPIC_API_KEY`/`ANTHROPIC_AUTH_TOKEN`/`apiKeyHelper`. Проверить: вызов под фальшивым HOME с фиктивным ключом.
- `ASSUMPTION:` `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=1` (PF-15) не вычищает `ANTHROPIC_BASE_URL` из окружения хука, а `ANTHROPIC_API_KEY` вычищает. Проверить спайком SessionStart-хука, печатающего только булевы флаги.
- `ASSUMPTION:` `"ANTHROPIC_BASE_URL": ""` в `env` settings-файла гасит экспорт из шелла (доки обещают это для переменных выбора провайдера). Проверить: шелл `BASE_URL=http://127.0.0.1:9` + проектный `""` → `claude -p` проходит.
- `ASSUMPTION:` строка `remote-settings.json` в бинаре 2.1.177 — кеш server-managed settings в каталоге конфигурации. Проверить на Team-аккаунте; на Pro файла нет.
- `ASSUMPTION:` расширение VS Code умеет инжектить env в процесс Claude (настройка вида `environmentVariables`). Проверить по `package.json` расширения.

## Questions
1. `HTTPS_PROXY` без `NO_PROXY` для хостов Anthropic — FAIL или WARN? По умолчанию **FAIL** (жёсткое ограничение 1), с флагом `--allow-forward-proxy` → WARN.

## GitHub research
| Repo | License | Что берём | Риск |
|---|---|---|---|
| diegosouzapw/OmniRoute (`bin/cli/commands/doctor.mjs`) | MIT, push 2026-09-27 | паттерн: проверка портов и liveness как отдельные check-функции `ok/warn/fail` | сам OmniRoute — шлюз, выставляющий `ANTHROPIC_BASE_URL`; код не берём |

## Official docs checked
PF-12, PF-13, PF-15, PF-16, PF-18. Сверх них: доки `env-vars` (settings `env` перекрывает шелл; `CLAUDE_CONFIG_DIR` игнорируется в project/local), `managed-settings` (пути: `C:\Program Files\ClaudeCode\managed-settings.json` + `managed-settings.d/*.json`, `HKLM|HKCU\SOFTWARE\Policies\ClaudeCode\Settings`; строки подтверждены в бинаре 2.1.177), `authentication` (порядок учётных данных; `.credentials.json` под `CLAUDE_CONFIG_DIR`), `cli-reference`/`--help` 2.1.177 (`--settings`, `claude auth status --json`, `claude doctor`).

## Architecture (дизайн)
1. **Разрешение корня OS**: `-OsRoot` > `osRoot` из `.claude/os-modules/installed.json` > `$HOME/.claude/templates/claude-md-os` (легаси). Registry — `<osRoot>/registry`. В режиме `osRoot` проверка `version-control` → `SKIP` (никаких автокоммитов в форк).
2. **Новые проверки ядра**:
   - `claude-endpoint` (FAIL): ищет `ANTHROPIC_BASE_URL` во всех источниках: env процесса; Windows User/Machine env (`[Environment]::GetEnvironmentVariable(n,'User'|'Machine')`); `env` в `<configDir>/settings.json`, `.claude/settings.json`, `.claude/settings.local.json`; managed-файлы и `managed-settings.d`; HKLM/HKCU policy; кеш server-managed; оверлеи `--settings` и каталоги `CLAUDE_CONFIG_DIR` профилей O4; шелл-профили (`$PROFILE` всех четырёх видов для WindowsPowerShell и pwsh, `~/.bashrc`, `~/.bash_profile`, `~/.profile`, `~/.zshrc`, `~/.zshenv`, `/etc/environment`, проектный `.envrc`) — только поиск имени переменной строкой, файл не выводится. Пустое значение в `env` = «гасит», отчитывается как OK-защита.
   - `claude-credential-override` (FAIL): `ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN`, `apiKeyHelper`, `CLAUDE_CODE_USE_BEDROCK|VERTEX|FOUNDRY` в тех же источниках (PF-18: ключ перекрывает подписку, в `-p` всегда). `CLAUDE_CODE_OAUTH_TOKEN` → WARN (подписка, но inference-only: Remote Control недоступен).
   - `claude-proxy-env`: `HTTPS_PROXY|HTTP_PROXY|ALL_PROXY` без покрытия в `NO_PROXY` (см. Questions).
   - `claude-auth`: `claude auth status --json` → `authMethod=="claude.ai"`, `apiProvider=="firstParty"`; иначе FAIL.
   - `claude-runtime-env`: читает булев маркер от опционального SessionStart-хука (что реально видел процесс Claude); маркер старше 7 дней → WARN.
3. **Модули**: для каждого модуля из `installed.json` читает `.claude-plugin/plugin.json → metadata.srednoffOs`, запускает объявленные проверки **последовательно** (ограничение 4), выключенный модуль → `SKIP`, проверки не запускаются.
4. **Порты и демоны** (обобщённо, F1 — первый потребитель): для объявленного порта — занят ли, кем (PID/имя процесса), привязка только `127.0.0.1`/`::1` (иначе FAIL), `GET /health` ≤ 2 с, в ответе `instanceId` совпадает с файлом состояния демона (защита от чужого процесса на порту).
5. **Исполнители**: объявленные CLI (внешние модели, ограничение 2) — наличие, версия, что вызываются отдельным процессом; их переменные (`OPENAI_BASE_URL` и т. п.) не должны стоять в `env` settings Claude (WARN).

## API contracts (интерфейсы и форматы)
Флаги: `-OsRoot/--os-root`, `-Only/--only <glob>`, `-NoModules/--no-modules`, `-AllowForwardProxy`. Статусы расширяются `SKIP`. Коды выхода прежние: 1 при FAIL.
```json
"metadata": { "srednoffOs": {
  "doctor": { "checks": [ { "id": "maskd-health", "run": { "ps1": "bin/doctor/maskd-health.ps1", "sh": "bin/doctor/maskd-health.sh" },
                            "timeoutSec": 10, "critical": true } ] },
  "ports": [ { "name": "maskd", "configKey": "daemon.port", "bind": "loopback", "health": "/health" } ],
  "executors": [ { "id": "codex", "command": "codex", "versionArgs": ["--version"] } ] } }
```
Проверка получает на stdin `{projectRoot, moduleRoot, configPath, stateDir, osRoot, platform}`, печатает одну строку `{"status":"OK|WARN|FAIL|SKIP","detail":"..."}`. Таймаут, ненулевой код или невалидный JSON → **никогда не OK**: `FAIL` при `critical`, иначе `WARN "no verdict"`. Имя в отчёте: `module/<id>/<check>`. `detail` ≤ 500 символов и проходит секрет-скан `hook-lib`; при совпадении заменяется на `[redacted: <rule>]`.
`/os-doctor` = `.claude/commands/os-doctor.md`: читает `osRoot`, запускает `doctor.ps1 -Json` (или `.sh`), пересказывает FAIL/WARN. `-FixSafe` из команды — только после явного «да» владельца.

## Data model / migrations
Состояния нет, кроме маркера `.claude/os-modules/.state/os-core/runtime-env.json` (только булевы флаги и версия Claude). Старый JSON-вывод совместим: добавлено поле `source: core|module:<id>`.

## Security model
Защищаем от: тихой маршрутизации трафика Claude через прокси/шлюз, тихой подмены подписки ключом, чужого процесса на порту демона, утечки значений в отчёт (значения не читаются в вывод — только имя и источник). Не защищаем от: администратора машины, меняющего managed-политику после проверки; переменных, выставленных лаунчером, которого doctor не видит (закрывается runtime-маркером).

## Risks
| Риск | Вероятность | Влияние | Митигация |
|---|---|---|---|
| Ложный OK: источник переменной, о котором не знаем | средняя | высокое | runtime-маркер из процесса Claude как второй независимый сигнал |
| Модульная проверка виснет | средняя | низкое | таймаут на проверку, последовательный запуск, вердикт «no verdict» |
| Чтение HKLM без прав | низкая | низкое | WARN «не удалось прочитать», не OK |

## Acceptance criteria
- AC1 `ANTHROPIC_BASE_URL` в любом из перечисленных источников → FAIL с именем источника, без значения (S1).
- AC2 Упавший демон F1 → FAIL `module/f1/maskd-health`; выключенный F1 → SKIP (S2, S3).
- AC3 Проверка модуля, вышедшая по таймауту, не даёт OK (S4).

## Testing plan
```gherkin
Scenario: S1 BASE_URL в проектном settings.local.json
  Given проект с ".claude/settings.local.json" где env.ANTHROPIC_BASE_URL = "http://127.0.0.1:9"
  When запускаю doctor с "--json --os-root <fork>"
  Then check "claude-endpoint" имеет status "FAIL" и detail содержит ".claude/settings.local.json"
  And вывод не содержит "127.0.0.1:9"
Scenario: S2 демон F1 не отвечает
  Given модуль "f1" включён и порт демона свободен
  When запускаю doctor
  Then check "module/f1/maskd-health" имеет status "FAIL"
Scenario: S3 модуль выключен
  Given модуль "f1" выключен в installed.json
  Then check "module/f1/maskd-health" имеет status "SKIP" и проверка не запускалась
Scenario: S4 проверка модуля зависла
  Given проверка с critical=true спит дольше timeoutSec
  Then её status "FAIL" и overall "FAIL"
```
behave в venv модуля; паритет: каждый сценарий гоняется для `.ps1` и `.sh`; CI-джоба `hook-canary` дополняется шагом `claude-endpoint` на фальшивом HOME.

## Rollback plan
Новые проверки за флагом ядра; `--no-modules` возвращает прежнее поведение. Удаление: revert изменений `doctor.*` и файла команды; маркер `.state/os-core/` удаляется вместе с каталогом.

## Estimate (оценка объёма)
Разрешение `osRoot` + SKIP: 0.5. Проверки endpoint/credentials/proxy/auth (обе платформы): 1.5. Контракт модульных проверок + порты/исполнители: 1.5. Команда + behave: 1. Итого ≈ 4.5 сессии. Взорвать может: чтение реестра/managed на CI без прав, поведение `auth status` (A-допущение выше).

## План работ
Заполняется после аппрува.

## Definition of done
- [ ] AC1–AC3 зелёные на Windows PowerShell 5.1 и bash
- [ ] Ни одна проверка не выводит значение переменной
- [ ] `docs/validation.md` дополнена новыми проверками

## Progress log
- 2026-09-27 — создана спека-набросок
