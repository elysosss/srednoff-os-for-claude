# 10-github-research.md

> Канонический источник. Развёрнутая версия — `.agent/GITHUB_RESEARCH.md`; при правке одного файла проверь и обнови второй.

Перед нетривиальным решением проверь GitHub.

## Когда проверка обязательна

Новая архитектура; выбор библиотеки, фреймворка, SDK или шаблона; интеграции (Supabase, Vercel,
GitHub Actions, Telegram, Stripe, OpenAI, Anthropic/Claude API, CRM, парсеры, очереди, cron, auth);
UI/UX, анимации, Three.js, shadcn, 21st.dev, landing pages; парсеры, боты, AI-агенты, workflow
automation; MCP servers; Claude Code hooks и skills; безопасность, авторизация, платежи, деплой;
производительность, кэширование, фоновые задачи; любое решение, которое может уже существовать в
open-source.

Не нужна только для мелких правок: опечатка, переименование, локальный баг на 1–2 строки,
форматирование.

Найди минимум 5 релевантных репозиториев/примеров, если они существуют.

Сравни:

- stars; recency; license; stack; tests; README;
- issues/PR health; architecture; применимость; риски копирования.

Формат:

```md
## GitHub Research

| Repo | Stars | Updated | License | Useful pattern | Risk |
|---|---:|---|---|---|---|
|  |  |  |  |  |  |

Decision:
- Adopt:
- Adapt:
- Avoid:
- Build ourselves:
```

Не копируй код без проверки лицензии. Извлекай паттерны: структура папок, архитектура, подход к API,
тестам, деплою, error handling.

Нет доступа к GitHub → напиши это честно, продолжай по локальному анализу и пометь решение как «без
внешней проверки».
