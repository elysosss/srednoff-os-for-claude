# Спеки расширений OS

> Fork-local. Спеки — **не реализация**: каждая реализуется только после аппрува владельца.
> Входные брифы — «OS Extensions — бриф на спецификации» и «Agent Dev Playbook» (оба 2026-09-27).
> Каждой спеке соответствует задача в [issues форка](https://github.com/elysosss/srednoff-os-for-claude/issues); реализация — ветками от `upstream/main` и PR в апстрим.

## Как устроено

- [TEMPLATE.md](TEMPLATE.md) — шаблон: ExecPlan из `.claude/rules/60-exec-plans.md` плюс
  разделы, которых требует бриф (Не-цели, Риски, Критерии приёмки, Оценка объёма).
- [PLATFORM-FACTS.md](PLATFORM-FACTS.md) — единый канон проверенных фактов о Claude Code
  2.1.177 (`PF-xx`), о движке фильтра (`GF-xx`) и непроверенных допущений (`A-xx`). Спеки
  ссылаются на id, а не пересказывают.
- Жёсткие ограничения брифа действуют для всех спек: трафик Claude не идёт через прокси и
  `ANTHROPIC_BASE_URL` для Claude не выставляется; внешние модели — только исполнители в
  отдельных процессах; всё выключаемо и в выключенном виде не меняет OS; работа серийная;
  каждое расширение — модуль формата E1.

## Порядок

1. **E1** — формат модуля, ровно столько, чтобы было куда класть F1.
2. **F1** — фильтр; начинается со спайка (фаза 0), который закрывает допущения A-01…A-14.
3. **O1**, **O3** — doctor и регрессионные пробы (проверки F1 и контракта хуков).
4. **X1**, **X4** — делегирование внешнему исполнителю и права на внешние CLI.
5. Плейбук D1–D10 — своим порядком (ниже, в реестре); D2/D3 встают рядом с E1, раньше F1 их ставить незачем.
6. Остальное — по результатам.

## Реестр

Баг существующей OS, найденный по ходу: инструмент PowerShell обходит все хуки — [#6](https://github.com/elysosss/srednoff-os-for-claude/issues/6).

| ID | Спека | Задача | Тип | Статус | Одна строка |
|---|---|---|---|---|---|
| E1 | [E1-module-format.md](E1-module-format.md) | [#7](https://github.com/elysosss/srednoff-os-for-claude/issues/7) | полная | DRAFT | модуль = раскладка плагина Claude Code + `metadata.srednoffOs`; ставится в проект (`.claude/os-modules/`), хуки сливаются в `settings.local.json`, учёт в `installed.json`, конфликт переписывания ловится при включении |
| F1 | [F1-sensitive-data-filter.md](F1-sensitive-data-filter.md) | [#9](https://github.com/elysosss/srednoff-os-for-claude/issues/9), спайк [#8](https://github.com/elysosss/srednoff-os-for-claude/issues/8) | полная | DRAFT, ждёт спайка | Go-демон `os-maskd` на правилах `guardrails-llm-filter` + клиент хука тем же бинарём; HMAC-плейсхолдеры, таблицы в памяти, демаскирование по политике инструмента, fail-closed внутри клиента |
| O1 | [O1-os-doctor.md](O1-os-doctor.md) | [#10](https://github.com/elysosss/srednoff-os-for-claude/issues/10) | набросок | DRAFT | расширяет существующий `scripts/doctor.*`: корень OS из `installed.json` (без глобальной установки), проверки `claude-endpoint` / `claude-credential-override` по всем источникам `ANTHROPIC_BASE_URL` и ключей, контракт проверок модулей, порты и демоны; значения никогда не печатаются |
| O3 | [O3-regression-probes.md](O3-regression-probes.md) | [#11](https://github.com/elysosss/srednoff-os-for-claude/issues/11) | набросок | DRAFT | три слоя проб (статика, окружение хуков, живые `claude -p` по согласию) с вердиктами HOLDS/BROKEN, привязанными к id из PLATFORM-FACTS; ловит тихие поломки контракта хуков после самообновления десктопа |
| X1 | [X1-delegate.md](X1-delegate.md) | [#12](https://github.com/elysosss/srednoff-os-for-claude/issues/12) | набросок | DRAFT | навык `delegate`: внешний CLI в отдельном worktree вне проекта, окружение собирается с нуля по allowlist (любые `ANTHROPIC_*`/`CLAUDE_*` — отказ), назад diff + итог как недоверенные данные, применяет только Claude; маскирование F1 для задачи/worktree опционально и с честными границами |
| X4 | [X4-external-cli-permissions.md](X4-external-cli-permissions.md) | [#13](https://github.com/elysosss/srednoff-os-for-claude/issues/13) | набросок | DRAFT | PreToolUse на `Bash\|PowerShell` с разбором подкоманд `gh`: credential → deny, write → ask (в auto — deny), неизвестное → запись, неразобранное → ask; нативные deny-правила как страховка на случай fail-open хука |
| X2 | [X2-executor-routes.md](X2-executor-routes.md) | [#14](https://github.com/elysosss/srednoff-os-for-claude/issues/14) | набросок | DRAFT | именованные цепочки исполнителей со строгим приоритетом; переход дальше только при квоте/лимите/недоступности/нет учётки, при плохом результате — стоп; платное звено требует явного одобрения маршрута; последнее звено всегда `self` |
| X3 | [X3-task-classifier.md](X3-task-classifier.md) | [#15](https://github.com/elysosss/srednoff-os-for-claude/issues/15) | набросок | DRAFT | детерминированный классификатор без LLM и сети: жёсткие запреты (critical/turbo, секретные пути, задачи про саму OS) сильнее любых сигналов; ответ `self\|delegate\|ask` — совет, решает Claude |
| C1 | [C1-prefix-hygiene.md](C1-prefix-hygiene.md) | [#16](https://github.com/elysosss/srednoff-os-for-claude/issues/16) | набросок | DRAFT | без нового файла правил: правка строки в `80-model-routing` (повышать модель сабагентом, не `/model`), `gen-profile-lock` пишет стабильные байты в конец CLAUDE.md, отчёт `prefix-report` по отпечаткам и промахам кэша из транскриптов |
| C2 | [C2-context-compression.md](C2-context-compression.md) | [#17](https://github.com/elysosss/srednoff-os-for-claude/issues/17) | исследование | DRAFT | протокол замеров M0–M3 на транскриптах владельца; потолок экономии 13.7–18.2 % входа, реалистично ~4–5 %; сначала штатный `bashOutputMaxChars`, потом обёртка команд, потом `updatedToolOutput`; все прокси-решения отвергнуты |
| C3 | [C3-two-tier-memory.md](C3-two-tier-memory.md) | [#18](https://github.com/elysosss/srednoff-os-for-claude/issues/18) | набросок | DRAFT | журнал `.agent/log` append-only (уровень 1) → продвижение только командой владельца с механически проверяемым доказательством → дайджест ≤ 4 КБ через SessionStart (уровень 2); вводит `.agent/NAV.md` и `.agent/notes/` |
| O2 | [O2-os-sysinfo.md](O2-os-sysinfo.md) | [#19](https://github.com/elysosss/srednoff-os-for-claude/issues/19) | набросок | DRAFT | allow-list полей вместо вычистки, переменные окружения только set/unset, финальный секрет-скан fail-closed (нашёл — файл не пишется), файл в игнорируемом git `.claude/os-modules/.state/sysinfo/` |
| O4 | [O4-profiles.md](O4-profiles.md) | [#20](https://github.com/elysosss/srednoff-os-for-claude/issues/20) | набросок | DRAFT | профиль = оверлей `--settings` + карта режимов модулей, запуск лаунчером `os-claude -Profile`; ключи endpoint/API-key в профиле запрещены; `CLAUDE_CONFIG_DIR` — только для второго аккаунта и выключен до решения владельца |
| O5 | [O5-remote-mode.md](O5-remote-mode.md) | [#21](https://github.com/elysosss/srednoff-os-for-claude/issues/21) | набросок | DRAFT | SSH-алиас + tmux на VM, Remote Control поверх той же сессии опционально; OS хранит только имена контекстов; attach отказывает, если doctor на VM даёт FAIL; нужна юридическая проверка (A-25) |
| O6 | [O6-backup-export.md](O6-backup-export.md) | [#22](https://github.com/elysosss/srednoff-os-for-claude/issues/22) | набросок | DRAFT | экспорт по allow-list путей и ключей (из settings — только `hooks`/`permissions`), учётки, состояние F1, транскрипты и память не экспортируются никогда; импорт по умолчанию — dry-run |
| E2 | [E2-hot-reload.md](E2-hot-reload.md) | [#23](https://github.com/elysosss/srednoff-os-for-claude/issues/23) | набросок | DRAFT | всё, что Claude Code перезагружает сам (PF-16), не трогаем; хуки не кешируют конфиг; демоны — опрос файлов + validate-then-swap с прогоном golden-фикстур, при ошибке остаётся последний рабочий набор; сетевого API изменения состояния нет |

### Плейбук агентной разработки (D1–D10)

Из «Agent Dev Playbook» (разделы 1–8; раздел 9 «симуляция / игра» не прислан). Каждая спека превращает прозу плейбука в машинную проверку или честно пишет, где это невозможно.

| ID | Спека | Задача | Тип | Статус | Одна строка |
|---|---|---|---|---|---|
| D1 | [D1-artifact-hierarchy.md](D1-artifact-hierarchy.md) | [#24](https://github.com/elysosss/srednoff-os-for-claude/issues/24) | набросок | DRAFT | `artifacts init` создаёт `docs/{vision,architecture,invariants,glossary}.md`, `adr/`, `specs/`, `tasks/` и не перезаписывает; инвариант = `## INV-NNNN` + обязательная `check:`-команда; линтер ссылок карточка → спек → ADR/модули |
| D2 | [D2-task-cards.md](D2-task-cards.md) | [#25](https://github.com/elysosss/srednoff-os-for-claude/issues/25) | набросок | DRAFT | статус карточки = папка, переходы только через CLI `task`; валидатор V1–V10; не больше двух попыток, потом передробление; замок модуля в `git-common-dir`; бюджет диффа при `done` и в CI |
| D3 | [D3-scope-guard.md](D3-scope-guard.md) | [#26](https://github.com/elysosss/srednoff-os-for-claude/issues/26) | набросок | DRAFT | PreToolUse только `deny`: запись вне `touch_allowed`, в `forbidden` и в защищённые зоны; файловый слой fail-closed, shell по возможности; настоящая гарантия — `scope-check` по диффу в `task done`, X1 и CI |
| D4 | [D4-agent-roles-pipeline.md](D4-agent-roles-pipeline.md) | [#27](https://github.com/elysosss/srednoff-os-for-claude/issues/27) | набросок | DRAFT | семь ролей как сабагенты с ограничением инструментов и путей (через D3); ревьюер получает только дифф + карточку + спек и работает отдельным процессом; одна сессия на карточку |
| D5 | [D5-adr-module-contracts.md](D5-adr-module-contracts.md) | [#28](https://github.com/elysosss/srednoff-os-for-claude/issues/28) | набросок | DRAFT | архитектурное решение → карточка в `blocked/` + ADR Proposed; `CONTRACT.md` на модуль, его `## Зависимости` — единственный канон рёбер; `adr-gate`: правка архитектуры без Accepted ADR — отказ |
| D6 | [D6-module-boundaries.md](D6-module-boundaries.md) | [#29](https://github.com/elysosss/srednoff-os-for-claude/issues/29) | набросок | DRAFT | граф модулей строят штатные инструменты языков (grimp, dependency-cruiser, `cargo metadata`, `go list`), скрипт сравнивает с `CONTRACT.md`; новое ребро валит CI |
| D7 | [D7-test-weakening-detector.md](D7-test-weakening-detector.md) | [#30](https://github.com/elysosss/srednoff-os-for-claude/issues/30) | набросок | DRAFT | девять детерминированных правил по диффу: удалённые assert, skip/xfail, расширенные допуски, эталоны → high-risk; «тест до кода» — пара карточек `kind: test` → `kind: impl` |
| D8 | [D8-ci-gates-risk-review.md](D8-ci-gates-risk-review.md) | [#31](https://github.com/elysosss/srednoff-os-for-claude/issues/31) | набросок | DRAFT | одна агрегирующая обязательная проверка, целостность через `pull_request_target`; отключить гейт — только с карточкой на возврат; аппрув человека реален только при отдельной учётке агента |
| D9 | [D9-erosion-metrics-auditor.md](D9-erosion-metrics-auditor.md) | [#32](https://github.com/elysosss/srednoff-os-for-claude/issues/32) | набросок | DRAFT | локальный read-only отчёт: контекст на карточку из транскриптов, hotspots, доля возвратов, новые рёбра, чтение вне `context_files`; каждая N-я карточка — техдолг |
| D10 | [D10-glossary-linter.md](D10-glossary-linter.md) | [#33](https://github.com/elysosss/srednoff-os-for-claude/issues/33) | набросок | DRAFT | `docs/glossary.md` с запрещёнными синонимами; проверяются только новые публичные символы; неизвестный термин — всегда только предупреждение |

Порядок внутри плейбука: D1 → D2 → D3 → D5 → D6 → D7 → D8, затем D4, D9, D10. Сквозные решения: канон рёбер модулей — `CONTRACT.md` (без отдельного `modules.yaml`); язык ядра анализаторов D6/D7/D10 и учётка агента для D8 — за владельцем (вопросы в [#29](https://github.com/elysosss/srednoff-os-for-claude/issues/29) и [#31](https://github.com/elysosss/srednoff-os-for-claude/issues/31)).

## Сквозные находки, всплывшие при подготовке спек

- **Рабочая среда — десктоп на Claude Code 2.1.281**, а не CLI 2.1.177 из PATH (PF-01).
  Десктоп обновляется сам — контракт хуков может поменяться без действий владельца; отсюда
  вес O3. Наброски местами ссылаются на 2.1.177 как на «установленную» версию — читать как
  нижнюю границу совместимости.
- **Инструмент PowerShell обходит все хуки OS** (PF-28): матчеры только `Bash`. Это баг
  существующей OS, а не расширений; вынесен в отдельную задачу под апстрим-PR.
- **У `guardrails-llm-filter` есть API маскирования** (`POST /v1/scan`, GF-05), вопреки брифу;
  но стабильных плейсхолдеров он не даёт, а его маскировщик — в `internal/` (GF-04, GF-06).
- **OmniRoute маршрутизирует подписочный OAuth Claude Code через свой шлюз** — прямое
  противоречие ограничению 1. Из него берутся только паттерны (приоритеты, квоты, cooldown,
  именованные контексты), не код и не запуск. Заявленные цифры сжатия (89 %) не
  подтвердились — это арифметика из двух несвязанных чисел (см. C2).
- **«Бандла памяти dsh» в ядре DeepSeek Harness нет** — есть класс сторонних плагинов; C3
  берёт только паттерны. **`nav-map` и заметок** в форке и в `osint-os` нет — C3 их вводит.
- **dsh-плагин для `gh`** (0★, один день активности) содержит две проверенные дыры:
  `gh api -X DELETE` считается чтением, `gh auth status --show-token` в списке чтения. X4
  закрывает обе фикстурами.
