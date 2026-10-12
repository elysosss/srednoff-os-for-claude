# demo

One sentence: what this module does and why it exists.

## Modes

| Mode | Behaviour |
|---|---|
| `off` | Changes nothing: hooks exit 0 with empty stdout, the module's skills, commands and agents are not present in `.claude/`. Default. |
| `on` | The module's behaviour (replace this row with the real modes). |

## Use

```
os-module install demo --project <project>
os-module enable demo --project <project>
os-module mode demo on --project <project>
os-module mode demo off --project <project>      # switch off without uninstalling
os-module uninstall demo --project <project>     # --purge also removes the state directory
```

On Windows PowerShell use `scripts\os-module.ps1` with `-Project`, `-Shared`, `-Purge`.

## Layout

See `docs/specs/E1-module-format.md`. Hooks are templates in `hooks/hooks.json` (bash) and
`hooks/hooks.windows.json`; `{{MODULE_DIR}}` is replaced with the installed module path when the
module is enabled. The first action of every hook is reading the mode (`scripts/mode.*`).
`tests/off-mode-calls.json` holds 20 reference tool calls: a module in `off` must answer every
one with exit 0 and empty stdout.

Anything secret or machine-bound goes to `stateDir` (outside the project), never to `config/`.
