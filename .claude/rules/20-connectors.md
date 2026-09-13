# 20-connectors.md

> Канонический источник. Развёрнутая версия — `.agent/CONNECTORS.md`; при правке одного файла проверь и обнови второй.

Используй MCP/коннекторы только если они помогают получить факты или выполнить действие.

## GitHub
- repo analysis; issues/PR; CI; branches; PR review; open-source research.

## Vercel
- deployments; logs; env vars; preview URLs; build diagnostics.
- production (env vars, домены, деплой) не менять без подтверждения.

## Supabase
- schema; migrations; RLS; auth; storage; edge functions; logs.
- не удалять данные и не отключать RLS без подтверждения.

## Figma / Canva
- UI references; design systems; assets; visual direction.

## Gmail / Calendar / Contacts
Только для задач коммуникации, встреч, follow-up или контактов.

## Rule
Перед destructive действиями запроси подтверждение.
