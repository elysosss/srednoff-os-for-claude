# 50-security.md

Запрещено без явного подтверждения:

- удалять production-данные;
- менять production env vars;
- отключать RLS/auth/security;
- читать/публиковать секреты без необходимости;
- логировать токены, cookies, private keys или PII;
- коммитить `.env`;
- выполнять платные действия;
- менять DNS/domain/payment settings;
- делать irreversible migrations.

Всегда проверяй:

- input validation; auth boundaries; RBAC; SQL injection; XSS; SSRF; CSRF;
- rate limits; secrets handling; PII handling.
