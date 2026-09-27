# O5: Удалённый режим — разработка на серверной VM, ноутбук как тонкий клиент

> Статус: DRAFT
> Тип: спека-набросок
> Модуль E1: `os-remote` (опциональный, по умолчанию выключен; ставится на ноутбук и на VM)
> Зависит от: O1 (doctor на VM), O4 (профиль на VM)   Блокирует: —

## Goal
Одной командой с Windows-ноутбука открыть сессию Claude Code, которая **работает на VM** (код, демон F1, исполнители — там), и вернуться к ней после обрыва связи; OS на VM развёрнута папочно и проверяется тем же doctor-ом.

## User value
Тяжёлые сборки и Docker не грузят ноутбук, сессия переживает сон крышки. Закрыто, когда `os-remote attach <ctx>` после разрыва возвращает ту же сессию, а `os-remote doctor <ctx>` показывает вердикт O1 для VM.

## Non-goals
- Не свой транспорт, сервер или токены: только SSH и встроенный Remote Control Claude Code.
- Не прокси для трафика Claude и не общий шлюз: Claude на VM ходит в first-party API своей подпиской (ограничение 1).
- Не облачные сессии claude.ai/code: это VM Anthropic, а не наша; F1 и исполнителей там нет.
- Не параллельные сессии на одной VM (ограничение 4).

## Current state
Ничего нет. OmniRoute `connect` в брифе назван образцом, но проверка показала: он управляет **удалённым шлюзом** OmniRoute со своего CLI (пароль → scoped-токен `oma_live_…`, контексты в `~/.omniroute/config.json`), а код и агенты остаются на ноутбуке. Это другая задача; берём только паттерн «именованные контексты + активный контекст».

## Assumptions
- `ASSUMPTION:` `claude auth login` на headless-VM через SSH в 2.1.177 проходит по схеме «открыть URL на ноутбуке, вставить код». Проверить на тестовой VM.
- `ASSUMPTION:` запуск официального клиента Claude Code под своей подпиской на собственной VM для одного пользователя не противоречит условиям подписки. Проверить по действующим Consumer Terms / странице usage policy до реализации; при сомнении — вопрос владельцу.
- `ASSUMPTION:` в 2.1.177 Remote Control при выставленном `ANTHROPIC_BASE_URL` ведёт себя неопределённо (явное отключение появилось в 2.1.196). Нам неважно: O1 не даёт его выставить.

## Questions
1. Основной путь — SSH+tmux или Remote Control? По умолчанию **SSH+tmux**; Remote Control — флаг `--rc` для доступа с телефона/браузера.

## GitHub research
| Repo | License | Что берём | Риск |
|---|---|---|---|
| diegosouzapw/OmniRoute (`bin/cli/commands/connect.mjs`, `docs/guides/REMOTE-MODE.md`) | MIT, push 2026-09-27 | паттерн контекстов: имя → цель, `contexts use`, файл контекстов с правами только владельца | по умолчанию `http://` и порт 20128, админ-токен при парольном входе — не копируем; секретов в контекстах у нас нет вообще |

## Official docs checked
PF-18. Доки `remote-control`: только подписки Pro/Max/Team/Enterprise, **API-ключи не поддерживаются**; только исходящий HTTPS, входящих портов нет; процесс должен жить (в доках прямо: tmux/screen на удалённой машине); на Team/Enterprise нужен тумблер Owner-а. `--help` 2.1.177: `claude remote-control --spawn same-dir|worktree|session --capacity <N>`, `--remote-control [name]`; `claude auth status --json`. Доки `authentication`: на Linux учётка — `~/.claude/.credentials.json` с правами 0600.

## Architecture (дизайн)
| Вариант | Где работает Claude | Доступ с ноутбука | Подписка | Минусы |
|---|---|---|---|---|
| SSH + tmux | VM | терминал | да, вход на VM | нужен терминал; телефон неудобен |
| Remote Control на VM (в tmux) | VM | claude.ai/code, приложение | да, только OAuth | зависит от сервиса Anthropic; UI без терминальных мелочей |
| VS Code Remote-SSH | VM | IDE | да | тяжелее, не наш слой |
| Облачные сессии | VM Anthropic | браузер | да | не наша VM, нет F1/исполнителей |

**Решение**: тонкая обёртка над SSH+tmux, Remote Control опционально поверх той же tmux-сессии.
1. **Контекст** = алиас `Host` из `~/.ssh/config` (источник правды о хосте, ключах, портах) + путь проекта на VM + имя профиля O4. Хранится в `<project>/.claude/os-modules/os-remote/contexts.json` — без секретов; ключи SSH живут в ssh-agent/Windows OpenSSH.
2. `os-remote attach <ctx>` → `ssh -t <alias> "tmux new -A -s os-<project> '<osRoot>/modules/os-profiles/bin/os-claude.sh -Profile <p>'"`. Одна сессия на проект: `new -A` переподключает к существующей.
3. `--rc`: в той же tmux-сессии `claude remote-control --spawn session` (одна сессия, ограничение 4; `--spawn worktree` не используем).
4. `os-remote doctor <ctx>` → по SSH запускает O1 `doctor.sh --json --os-root <remoteOsRoot>` и печатает вердикт; `os-remote sysinfo <ctx>` — O2 на VM, файл остаётся на VM.
5. **Бутстрап VM** (`os-remote bootstrap <ctx>`, только с подтверждением): клон форка в выбранный каталог, `init-claude-project.sh` в проект, проверка jq/`grep -P`. Ничего в `~/.claude` VM, кроме того, что сам Claude создаёт при входе.
6. Демон F1 и его порт живут на `127.0.0.1` VM; проброс его порта на ноутбук запрещён (O1 на VM проверяет привязку).

## API contracts (интерфейсы и форматы)
```json
{ "schema": 1, "contexts": { "vm1": { "sshAlias": "dev-vm", "projectPath": "/srv/work/app",
  "osRoot": "/srv/os/srednoff-os-for-claude", "profile": "work", "rc": false } }, "active": "vm1" }
```
Команды: `os-remote list|use <ctx>|attach [ctx]|doctor [ctx]|sysinfo [ctx]|bootstrap <ctx>`. Коды: 0 ок; 20 контекст не найден; 21 ssh недоступен; 22 doctor на VM = FAIL (attach не выполняется без `--force`).

## Data model / migrations
Только `contexts.json` (схема версионирована). Состояние сессии — в tmux на VM; транскрипты — в `~/.claude/projects` на VM, как у любого клиента.

## Security model
Защищаем от: открытых входящих портов (кроме уже существующего SSH), проброса порта F1, хранения токенов в файлах OS, случайного API-ключа на VM (O1 перед attach). Не защищаем от: компрометации VM — на ней лежит `.credentials.json` подписки и код; это осознанная цена варианта, фиксируется в README модуля. Remote Control: рекомендуем включить Trusted Devices в аккаунте.

## Risks
| Риск | Вероятность | Влияние | Митигация |
|---|---|---|---|
| Две сессии на одном проекте (tmux + RC) | средняя | среднее | один tmux-сеанс на проект, RC только `--spawn session` |
| Условия подписки не допускают удалённый запуск | низкая | высокое | допущение выше проверяется до реализации |
| Windows OpenSSH без `-t` ломает tmux | низкая | низкое | `ssh -t` всегда; проверка в doctor ноутбука |

## Acceptance criteria
- AC1 Повторный `attach` возвращает ту же tmux-сессию (S1).
- AC2 `attach` не стартует, если doctor на VM дал FAIL по `claude-endpoint` (S2).
- AC3 `contexts.json` не содержит ключей, токенов, паролей (S3).

## Testing plan
```gherkin
Scenario: S1 переподключение
  Given контекст "vm1" и существующая tmux-сессия "os-app" на VM
  When выполняю os-remote attach vm1
  Then ssh вызывается с "tmux new -A -s os-app"
Scenario: S2 VM с выставленным BASE_URL
  Given doctor на VM возвращает claude-endpoint = FAIL
  When выполняю os-remote attach vm1
  Then код выхода 22 и tmux не запускался
Scenario: S3 в контекстах нет секретов
  When сохраняю контекст с sshAlias
  Then секрет-скан hook-lib по contexts.json не находит совпадений
```
`ssh` в тестах — заглушка, записывающая аргументы. Ручной прогон на реальной VM: вход, обрыв, возврат, RC с телефона.

## Rollback plan
Выключить модуль на ноутбуке — команды пропадают; на VM убить tmux-сессию, удалить каталог форка и проектные файлы OS (init их не трогал вне проекта). Выход из подписки на VM — `claude auth logout`.

## Estimate (оценка объёма)
Контексты + attach/list/use: 1. doctor/sysinfo по SSH: 0.5. bootstrap VM: 1. RC-режим + ручная проверка: 0.5. Итого ≈ 3 сессии. Взорвать может: вход на headless-VM, кодировки/TTY Windows OpenSSH.

## План работ
Заполняется после аппрува.

## Definition of done
- [ ] AC1–AC3; ручной сценарий «обрыв → возврат» пройден на реальной VM
- [ ] Допущение об условиях подписки закрыто

## Progress log
- 2026-09-27 — создана спека-набросок
