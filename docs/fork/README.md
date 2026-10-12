# Форк: состояние, план, как продолжить — начни здесь

Этот каталог — **канон работы над форком**: решения, план, состояние, как продолжить с
другого ПК. Всё, что раньше жило в локальном `HANDOFF.md` вне репозитория, теперь здесь.
Каталог `docs/` в проекты при установке OS не копируется, поэтому сюда можно писать
свободно.

| Файл | Что в нём |
|---|---|
| [DECISIONS.md](DECISIONS.md) | датированный журнал решений владельца (новые сверху) |
| этот README | курс, состояние, план, как продолжить, правила |
| [history/](history/) | старые планы, на которые ссылаются решения |
| [../specs/](../specs/README.md) | спеки расширений (E1, F1, O*, X*, C*, D1–D10) и факты платформы |
| [../../FORK.md](../../FORK.md) | модель веток и что считается намеренным расхождением с апстримом |
| [../../FORK-VERSION](../../FORK-VERSION) | версия сборки форка |

Задачи — [issues форка](https://github.com/elysosss/srednoff-os-for-claude/issues).

---

## Курс (с 2026-10-12)

Форк — **«OS для программиста»**: своя сборка поверх SREDNOFF OS, которая в апстриме
задумана «для всего». В апстрим уходят только общие вещи (баги OS, исправления без
зависимостей от форк-кода); всё для программистов — модули, плейбук агентной разработки,
делегирование, проверки — живёт и развивается здесь. Подробно — [DECISIONS.md](DECISIONS.md)
и [FORK.md](../../FORK.md).

## Состояние на 2026-10-12

- `main` форка синхронизирован с апстримом (последний мерж апстрима — #20). Открытых PR в
  апстрим нет; все прошлые (#4–#20) влиты.
- Реализации расширений ещё нет — есть 28 спек (`docs/specs/`) и задачи #6–#33 по ним, плюс
  #4 (битые ссылки в скиллах) и #5 (разбор mattpocock/skills).
- Тест-контур OS: `run-evals` 94/94 на bash и PowerShell; CI апстрима 7/7.

## План

| Шаг | Что | Задача | Метка | Объём |
|---|---|---|---|---|
| 0 | Перевести задачи и спеки на модель форка — **сделано 12.10** (этот коммит); осталось решить судьбу старых заметок `PR-BODIES.md`, `tmp.md` (не в git) и удалить влитые локальные ветки | — | — | — |
| 1 | **Перезатирание CLAUDE.md и файлов проекта** (create-only, см. ниже) | [#34](https://github.com/elysosss/srednoff-os-for-claude/issues/34) | upstream-candidate | 1–1.5 сессии |
| 2 | PowerShell-инструмент обходит все хуки OS (PF-28) | [#6](https://github.com/elysosss/srednoff-os-for-claude/issues/6) | upstream-candidate | 1 |
| 3 | Спайк F1: go/no-go по A-02 (оригинал секрета в транскрипте и при `--resume`) и A-09 (что модель видит после Edit) | [#8](https://github.com/elysosss/srednoff-os-for-claude/issues/8) | fork-only | 1 |
| 4 | E1 — формат модулей; на нём стоит всё остальное | [#7](https://github.com/elysosss/srednoff-os-for-claude/issues/7) | fork-only | 2.5–3.5 |
| 5 | Дальше по ценности: F1 (#9, если спайк зелёный); D2 + D3 (#25, #26) — карточки и страж области; часть O1 (#10) про `ANTHROPIC_BASE_URL`/ключи — кандидат в апстрим | см. задачи | | |

Порядок внутри спек и зависимости — [docs/specs/README.md](../specs/README.md).

### Шаг 1 подробно: что ещё перезатирается

Фикс от 11.08 (апстрим PR #4) остановил порчу README/LICENSE/.gitignore и защитил файлы,
**закоммиченные** в git проекта. По коду на 12.10 остались:

| # | Как | Где |
|---|---|---|
| V1 | `init-claude-project` без `--skip-existing-claude-md` заменяет CLAUDE.md, если тот не закоммичен или проект без git | `scripts/init-claude-project.{sh,ps1}`, ветка «untracked differs» |
| V2 | любой файл allow-list (`.claude/rules|skills|commands|hooks/**`, `settings*.example.json`, `.agent/**`, `code_review.md`, `AGENTS.md`), который отличается и не закоммичен — молча `.bak` + замена; срабатывает и в фоне: глобальный SessionStart-хук, `doctor --fix-safe`, `apply-os-all --sync` | там же |
| V3 | `gen-profile-lock` всегда вставляет блок `SREDNOFF-OS:SELECTION` в CLAUDE.md проекта (встречено вживую); PowerShell-версия пишет CRLF | `scripts/gen-profile-lock.{sh,ps1}` |
| V4 | `.bak.<stamp>` копятся без уборки | init |

Решение (DECISIONS 12.10, п. 4): **create-only** по умолчанию — существующие файлы не
меняются, отличия печатаются; замена — только явным флагом и руками; CLAUDE.md проекта без
флага не трогается никогда. Фикстуры на V1–V3 в `registry/evals`, до/после числами в PR.
Делать до C1 (#16), который тоже меняет `gen-profile-lock`.

---

## Как продолжить на другом ПК

```bash
git clone https://github.com/elysosss/srednoff-os-for-claude.git
cd srednoff-os-for-claude
git remote add upstream https://github.com/srednoff888-art/srednoff-os-for-claude.git
git fetch upstream
```

Затем: прочитать [DECISIONS.md](DECISIONS.md) и раздел «План» выше, открыть задачу текущего
шага. Нужны: `git`, `gh` (авторизованный), `jq`; на Windows — PowerShell 5.1 и Git Bash; для
F1 — Go ≥ 1.26.5.

**Проверки без глобальной установки** (скрипты OS ждут раскладку `~/.claude`; собираем её во
временном HOME — так же делает CI):

```bash
TH="$(mktemp -d)/fakehome"
mkdir -p "$TH/.claude/templates/claude-md-os" "$TH/.claude/registry"
cp -r . "$TH/.claude/templates/claude-md-os/"; rm -rf "$TH/.claude/templates/claude-md-os/.git"
cp -r registry/. "$TH/.claude/registry/"
HOME="$TH" bash scripts/run-evals.sh          # сейчас 94/94
```

PowerShell: `$env:USERPROFILE = "<тот же путь>"; powershell -File .\scripts\run-evals.ps1`.
Прогон занимает минуты — запускать в фоне. Валидаторы, дублирующие CI:
`scripts/validate-skills-library`, `registry/validate-catalog-format`,
`registry/audit-registry`, `registry/gen-catalog-json --check`, `scripts/validate-docs`,
`scripts/validate-exec-bits`, `scripts/validate-ps1-encoding`.

**Поставить OS в свой проект** — только папочно, из чекаута форка:

```powershell
& "<чекаут форка>\scripts\init-claude-project.ps1" "<путь к проекту>" -SkipExistingClaudeMd
```

`-SkipExistingClaudeMd` обязателен, пока не сделан шаг 1.

---

## Правила работы (не менялись)

- **OS ставится только в папку проекта.** Никакой записи в `~/.claude/{CLAUDE.md,
  code_review.md,templates,registry}`, никаких глобальных установщиков.
- Трафик Claude не идёт через прокси: `ANTHROPIC_BASE_URL` для Claude не выставляется.
  Внешние модели — только исполнители отдельными процессами.
- В git добавлять файлы **поимённо**, никогда `git add -A`.
- Скрипты OS — парами `.ps1`/`.sh`, без кириллицы в `.ps1`. Тесты — фикстуры `run-evals`,
  без behave.
- Каждый баг сначала воспроизвести и показать «до/после» числами — апстрим берёт именно такие
  PR, и форк держит ту же планку.

## Грабли, на которые уже наступали

1. `git add -A` дважды подобрал чужое (кэш PowerShell, чужую незакоммиченную работу).
2. В Git Bash MSYS ломает `git show branch:path` → `export MSYS_NO_PATHCONV=1`.
3. Эвалы краснеют от окружения, а не от кода: локаль и `grep -P` (апстрим #8/#9), случайное
   имя временного каталога, накормившее эвристику по имени проекта (апстрим #20).
4. Windows-Python не понимает `/d/...`; в Python-строках `\b`, `\2`, `\t` в путях становятся
   управляющими символами — писать пути через raw-строки или прямые слэши.
5. `git fetch upstream origin` — неверно (второе слово — refspec); фетчить по одному.
6. Рабочий Claude Code — **десктопный, обновляется сам**; CLI в PATH может быть старее.
   Контракт хуков может поменяться без действий владельца — проверять пробами (O3).
7. Сабагенты ошибаются уверенно: их утверждения про чужие репозитории перепроверять; при
   параллельной работе нескольких сабагентов сразу задавать карту «кто за что», иначе их
   спеки расходятся.
