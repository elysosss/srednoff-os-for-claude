# D4: Роли агентов и конвейер — сабагенты с правами, изолированный ревьюер, сессия на карточку

> Статус: DRAFT
> Тип: спека-набросок
> Модуль E1: `roles` (`requires.modules: ["tasks", "scope-guard"]`); требует правки E1 — установка `agents/` модуля в `.claude/agents/<module>--<name>.md`
> Зависит от: E1, D2 (карточка как единица работы), D3 (путевые права ролей, привязка сессии), D5 (роль архитектора, `task block --adr`), X1 (исполнитель-внешний CLI, по желанию), правило 90   Блокирует: D9 (роль аудитора — оболочка для его отчёта)

## Goal
Семь ролей §7 плейбука (аналитик, планировщик, архитектор, исполнитель, ревьюер, тестировщик, аудитор) становятся проектными сабагентами Claude Code с явным списком инструментов; путевые права ролей исполняет D3 по `agent_type`; ревьюер получает только дифф, карточку и спек без рассуждений исполнителя; одна карточка = одна свежая сессия; точки аппрува человека (§8) названы вместе с тем, что их реально обеспечивает.

## User value
Сейчас в OS одна роль — «Staff-инженер» из CLAUDE.md, и правило 90 описывает только контракт вызова сабагента. Боль плейбука «сделал не то, но убедительно объяснил» закрыта, когда ревьюер физически не может получить рассуждения исполнителя, а роль, которой запрещено писать код, получает `deny`, а не просьбу.

## Non-goals
- Автономный конвейер «идея → мерж» без человека. Каждый переход запускает человек командой (ограничение 4, гейт swarm в правиле 70); параллелизм ролей и модулей — выключенная возможность.
- Новые возможности ревью: чеклист остаётся в `code_review.md`; ослабление тестов — D7; CI-гейты — D8; содержимое отчёта аудитора — D9.
- Роли как внешние модели по умолчанию. Исполнитель может быть внешним CLI только через X1 (ограничение 2), остальные роли — Claude.

## Current state
- Правило 90: цель/границы/формат/лимит вывода и обязательный disposition `done|blocked|deferred|failed`. Роли D4 обязаны его соблюдать; disposition отображается на CLI D2: `done` → `task done`, `blocked` → `task block`, `failed` → `task return`.
- Правило 80: модель по сложности. Проектных сабагентов (`.claude/agents/`) OS не ставит; E1 ставит навыки и команды, но не агентов.
- `skills-library/principal-code-reviewer-agent`, `principal-architect-agent`, `documentation-adrs`, `mutation-testing-strategy` — общие 31–33-строчные шаблоны без форматов. Роль может предзагрузить их полем `skills:`, если они стоят в проекте, но D4 на их содержимое не опирается.
- Доки sub-agents: `tools`/`disallowedTools` — только имена инструментов, **путевых шаблонов нет**; не-форк сабагент не видит разговор родителя, прочитанные файлы и авто-память, но видит CLAUDE.md и сообщение-делегирование; хуки во frontmatter проектного агента требуют доверия к папке (проверка с v2.1.218); `omitClaudeMd` — с v2.1.271; есть `isolation: worktree`, `maxTurns` (v2.1.246).

## Assumptions
- `ASSUMPTION:` вход PreToolUse для инструмента `Agent` содержит `tool_input.subagent_type` и `tool_input.prompt` (доки схему не приводят). Проверить хуком-дампером на вызове проектного сабагента. На этом стоит гейт ревьюера (вариант Б ниже).
- `ASSUMPTION:` `claude -p --agent <name>` существует в CLI 2.1.177 и в копии десктопа 2.1.281 и выполняет проектные хуки (сюда же A-22). Проверить `claude --help` обеих копий и прогоном с логирующим хуком.
- `ASSUMPTION:` после `--resume` сессия сохраняет прежний `session_id` (доки не говорят). Если да — возобновлённая сессия остаётся привязанной к старой карточке, и D3 шаг 6 не даст ей начать новую; если нет — «продолжи вчерашнее» выглядит как новая сессия, и страхует только `task start --retry` (попытка засчитана).
- `ASSUMPTION:` `isolation: worktree` доступен в 2.1.177; если нет — параллельный режим объявляется «требует ≥ 2.1.2xx» с деградацией в последовательный.

## Questions
1. Кто исполнитель по умолчанию — главная сессия или сабагент? По умолчанию **главная сессия**, открытая заново (`/task-start T-0142`): у неё полный контекст инструментов, а сабагент-исполнитель нужен только в параллельном режиме.
2. Ревьюер отдельным процессом (`claude -p`) или сабагентом? По умолчанию — отдельный процесс (вариант А), сабагент с гейтом (вариант Б) — если A-22 или `--agent` не подтвердятся.

## GitHub research
| Repo | License | Что берём | Риск |
|---|---|---|---|
| `bmad-code-org/BMAD-METHOD` (push 2026-09-27, 53k★) | MIT | Роли analyst / architect / dev / QA как отдельные агенты; файл истории несёт весь контекст исполнителю (у нас — карточка + `task brief`) | роли различаются промптом, права не enforced; код не берём |
| `MrLesk/Backlog.md` | MIT | «Перезапуск в свежей сессии» как штатный путь при плохом результате | — |

## Official docs checked
PF-10 (хуки settings срабатывают в сабагентах, есть `agent_type`), PF-06, PF-12, PF-24. Сверх: sub-agents.md (поля frontmatter и версии выше, видимость контекста, глубина вложенности `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH`), skills.md (`allowed-tools` лишь предразрешает, ограничивает только `disallowed-tools`; `context: fork` + `agent`), permissions.md (`Agent(name)`-правила, frontmatter-хуки без доверия не исполняются).

## Architecture (дизайн)
**Роли** — файлы `agents/roles--<role>.md` модуля, E1 копирует их в `.claude/agents/`. Инструменты ограничивает Claude Code (`tools`/`disallowedTools`), пути — D3 по `agent_type` (settings-хук, работает без доверия к frontmatter-хукам), модель — по правилу 80.
| Роль | tools | disallowedTools | Пишет (D3) | Модель | Исход |
|---|---|---|---|---|---|
| analyst | Read, Grep, Glob, Write, Edit, WebFetch | Bash, PowerShell, Agent | `docs/specs/**` | opus | спек со статусом «на аппрув» |
| planner | Read, Grep, Glob, Write, Edit, Bash, PowerShell | NotebookEdit, Agent | только `tasks/backlog/**` (исключение D3 шаг 4) | opus | набор карточек, `task validate --all` зелёный |
| architect | Read, Grep, Glob, Write, Edit | Bash, PowerShell, Agent | новые `docs/adr/**`; `docs/architecture.md` и `**/CONTRACT.md` — только при активной карточке `kind: contract` (D5) | opus | ADR `Proposed` |
| executor | наследует | Agent | `touch_allowed` активной карточки | inherit | `task done`/`return`/`block` |
| reviewer | Read, Grep, Glob, Bash, PowerShell | Edit, Write, NotebookEdit, Agent, WebFetch | ничего | sonnet; при `risk: high` вариант А передаёт `--model opus` | вердикт `approve|changes|reject` + находки `файл:строка` |
| tester | Read, Grep, Glob, Bash, PowerShell, Write, Edit | Agent | `tests/**` кроме защищённых зон; найденное — только `task new` | sonnet | тесты + карточки на дефекты |
| auditor | Read, Grep, Glob, Bash, PowerShell | Edit, Write, NotebookEdit, Agent, WebFetch | ничего, кроме `.claude/os-modules/.state/roles/audit/` через скрипт D9 | haiku сбор, sonnet отчёт | отчёт человеку |

«Не делает» из §7 честно делится на два класса: **машинное** — запреты записи (D3) и инструментов (frontmatter); **пожелание** — «архитектор не мержит» (обеспечивает X4: `gh pr merge` = запись → `ask`/`deny`, и GitHub: автор не может одобрить свою PR), «ревьюер не переписывает код» (обеспечено отсутствием Edit/Write; через Bash — D3 shell-слой + то, что его дифф не коммитится: ревью идёт в отдельном worktree, см. ниже).

**Изоляция ревьюера.** Входной пакет строит скрипт, а не исполнитель: `task review-pack T-0142` → `.claude/os-modules/.state/roles/review/T-0142/{diff.patch, card.yaml, spec-section.md}`; дифф — `git diff <base>...HEAD`, без сообщений коммитов и описания PR (там живут объяснения исполнителя). Вариант А (по умолчанию): `task review T-0142` запускает отдельный процесс `claude -p --agent roles--reviewer` с **фиксированным** промптом из шаблона модуля (id карточки + путь к пакету) во временном worktree на коммите HEAD — изменения ревьюера в основной checkout не попадают. Вариант Б: сабагент из сессии; PreToolUse-хук на матчер `Agent` при `subagent_type == roles--reviewer` отклоняет любой `prompt`, не совпадающий побайтно с шаблоном, — так исполнитель не может «объяснить» ревьюеру. Оба варианта: D3 (роль reviewer) плюс read-гейт этого модуля отклоняют чтение `~/.claude/projects/**` (транскрипты) и `.claude/os-modules/.state/scope-guard/**`. Ревьюер **видит** CLAUDE.md и файлы репо — «только дифф, карточка, спек» означает «без рассуждений исполнителя», а не «без контекста кода»; `omitClaudeMd` (≥ 2.1.271) не включается, иначе ревьюер потеряет правила проекта.

**Свежая сессия на карточку.** Три механизма: (1) D3 шаг 6 — сессия, писавшая под одной карточкой или прошлой попыткой, не пишет под другой; (2) `/task-start T-0142` печатает `task brief` и требует пустой истории: команда отказывает, если в сессии уже были вызовы инструментов записи (по `sessions.json` D3); (3) состояние между сессиями — только карточка, репо и `returns` (D2); SessionStart-хук модуля при активной карточке добавляет одну строку «active card T-0142, run task brief» (≤ 200 байт, C1 — не раздувать префикс).

**Точки аппрува человека (§8)**:
| Точка | Что считается аппрувом | Чем обеспечено | Класс |
|---|---|---|---|
| спек | мерж PR со спеком | GitHub: автор не одобряет свою PR; X4 не даёт агенту `gh pr merge`/`gh pr review --approve` молча | машинное вне Claude |
| набор карточек | мерж PR планировщика в `tasks/backlog/` | то же | машинное вне Claude |
| ADR, контракт | статус `Accepted` в main | D5 `adr-gate` + обязательное ревью в CI (D8) | машинное вне Claude |
| защищённая зона | `scope-guard unlock` | D3, команда из терминала владельца | машинное локально, обходимо shell-скриптом → D8 |
| high-risk мерж | ручной аппрув | D8 + правила ветки GitHub | машинное вне Claude |
| приёмка фичи | человек играет/смотрит | `task graph --spec <path>` говорит только «все карточки спека в done» | пожелание, по природе ручное |

**Отношение к X1.** Исполнитель может быть внешним CLI: `task brief` становится `TaskFile` для `delegate-run`, `delegate-apply` обязан пройти `scope-check` (D3) до применения; хуки на внешний процесс не действуют (X1), поэтому других гарантий нет.

Отвергнуто: роли навыками с `allowed-tools` (не ограничивает, только предразрешает); навыки с `context: fork` (видят ту же проблему пути, а форк-режим сабагента наследует разговор — утечка рассуждений); frontmatter-хуки как основной механизм (требуют доверия к папке и версии ≥ 2.1.218; plugin-сабагенты их не поддерживают).

## API contracts (интерфейсы и форматы)
Команды: `/task-start ID`, `/task-review ID`, `/task-plan <spec>`, `/task-audit`. Скрипт: `task review ID [--variant subagent]` → `review/T-0142/verdict.json` `{card, verdict, findings:[{file, line, severity, text}], disposition}`; вердикт `changes` и `reject` не двигают карточку сам — решение за человеком или исполнителем в новой сессии. Шаблон промпта ревьюера — `templates/reviewer-prompt.txt` (ASCII, неизменяемый; хэш сверяется хуком варианта Б).

## Data model / migrations
Роли — файлы в `.claude/agents/` (учёт в `installed.json` по правке E1). Пакеты и вердикты ревью — `.claude/os-modules/.state/roles/` (gitignored), хранятся 30 дней. Вердикт, нужный CI, копируется в PR человеком или D8 — не коммитится агентом.

## Security model
Защищаем: ревьюера от влияния рассуждений исполнителя (фиксированный промпт, пакет без сообщений коммитов, запрет чтения транскриптов); роли без права писать — от записи инструментами; проект — от «продолжу вчерашнее». Не защищаем: подлинность человека локально — агент и владелец работают под одной учёткой ОС, поэтому локальные «аппрувы» не доказательство; настоящие аппрувы — только те, что проходят через GitHub и X4. Ревьюер-модель может ошибаться — это ревью, а не доказательство корректности; доказательство — `done_when` и CI.

## Risks
| Риск | Вероятность | Влияние | Митигация |
|---|---|---|---|
| A-22/`--agent` не подтвердятся — вариант А недоступен | средняя | среднее | вариант Б с гейтом по `prompt` |
| Схема входа `Agent` иная — гейт Б не работает | средняя | высокое | спайк до реализации; без него вариант Б не включается |
| Семь ролей в описаниях съедают бюджет 15 000 токенов описаний агентов | низкая | низкое | описания ≤ 200 символов |
| Роли размывают правило 90 | низкая | среднее | каждый файл роли ссылается на правило 90, не пересказывает |

## Acceptance criteria
- AC1: модуль в `off` — `/task-*` отвечают «disabled», файлов ролей в `.claude/agents/` нет (иначе Claude может делегировать им, и выключенный модуль меняет поведение; правка E1: `mode off` у модуля с `agents/` снимает файлы, `on` возвращает; `.claude/agents/` подхватывается без живой перезагрузки — нужен перезапуск сессии) → S1.
- AC2: сабагент `roles--reviewer` получает `deny` на Edit любого файла → S2.
- AC3: пакет ревью не содержит сообщений коммитов исполнителя → S3.
- AC4: вариант Б: вызов ревьюера с изменённым промптом отклоняется → S4.
- AC5: сессия, закрывшая T-0142, не может писать под T-0143 → S5.

## Testing plan
```gherkin
Scenario: S1 disabled roles module
  Given the roles module is in mode "off"
  When I run /task-review T-0142
  Then the command answers "roles disabled" and no review pack is created
Scenario: S2 reviewer cannot write
  Given a hook input with agent_type "roles--reviewer" and tool "Edit"
  When scope-guard evaluates it
  Then the decision is "deny"
Scenario: S3 the review pack carries no executor reasoning
  Given T-0142 was implemented in a commit with message "I chose X because Y"
  When I run task review-pack T-0142
  Then diff.patch contains the code change and no file in the pack contains "because Y"
Scenario: S4 fixed reviewer prompt
  Given variant "subagent" is configured
  When the hook receives tool "Agent" with subagent_type "roles--reviewer" and a prompt differing from the template
  Then the decision is "deny"
Scenario: S5 one session per card
  Given session "s1" wrote files under T-0142 and T-0142 is done
  And T-0143 is active
  When the hook receives Edit from session "s1" within T-0143 touch_allowed
  Then the decision is "deny" and the reason mentions a fresh session
```
Вручную: полный конвейер одной фичи из двух карточек в десктопе 2.1.281 (аналитик → планировщик → исполнитель → ревьюер), замер числа ручных шагов.

## Rollback plan
`off` — команды отвечают «disabled»; `disable` убирает агентов ролей из `.claude/agents/` по учёту E1. `uninstall` удаляет модуль и `.state/roles/`. Карточки, спеки и ADR — данные проекта, остаются.

## Estimate (оценка объёма)
Спайк A-22/`--agent`/вход `Agent`/`session_id` при resume — 0.5 сессии; файлы ролей и правка E1 (`agents/`) — 1; `review-pack`, вариант А, read-гейт — 1; вариант Б, `/task-start`, SessionStart-строка, behave S1–S5 — 1. Итого 3.5 сессии. Взорвать может: отрицательный спайк по обоим вариантам ревьюера (тогда изоляция держится только на `review-pack` и дисциплине — будет записано честно).

## План работ
Заполняется после аппрува.

## Definition of done
- [ ] Спайк закрыл четыре допущения, результаты перенесены в PLATFORM-FACTS с id
- [ ] S1–S5 зелёные на Windows и Linux; `.ps1` без кириллицы
- [ ] Каждый файл роли ссылается на правило 90 и называет свой disposition

## Progress log
- 2026-09-27 — создан набросок спеки
