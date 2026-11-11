# Local models and xt3d

Lets a model in LM Studio (or Claude Desktop) work with xt3d and the running LiveCode IDE.

| File | What it is |
|---|---|
| `xt3d_mcp.py` | MCP tool server (standard library only). Registered in LM Studio's `mcp.json` as `xt3d`. |
| `livecode_primer.md` | LiveCode Script primer. Small models don't know LiveCode; with this they write it correctly. |
| `ask_local.py` | Ask a local model from the terminal, with the same tools: `python3 llm/ask_local.py "question"` |

## Tools the model gets

`livecode_primer`, `xt3d_find_handlers` (searches the manifest), `livecode_status`,
`livecode_run`, `livecode_eval`, `bench_list_models`, `bench_load_model`,
`bench_run_checks`, `livecode_errors`, `bench_snapshot` (image, for vision models).

Primer, handler search, model list and error log work without LiveCode. The rest need
the test bench open, which starts the dev server.

## In LM Studio

1. Restart LM Studio once, so it reads `mcp.json` (backup of the old one:
   `mcp.json.bak-before-xt3d`).
2. In a chat, switch on the `xt3d` integration (Program / Integrations panel).
3. Paste this as the system prompt:

   > You help with the xt3d project: raylib 3D for LiveCode 9.6.3. You can call tools to look up xt3d handlers, read a LiveCode primer, and run code in the user's LiveCode test bench. Read livecode_primer before writing any LiveCode Script; LiveCode is not JavaScript or Python. Use xt3d_find_handlers to look up exact xt3d names and parameters instead of guessing. Answer briefly.

4. For spark-x2.6-4b, set reasoning effort to low if offered. Otherwise it can think for
   thousands of tokens without answering.

`livecode_run` runs real code in the IDE. Leave LM Studio's "ask before each tool call"
on.

## Tested (2026-11-11, spark-x2.6-4b, Q4_K_M)

- Without the primer it writes JavaScript-like code (`tText.split("\n")`). With the
  primer: correct LiveCode on four of four small tasks, after two fixes to the primer.
- Tool calling works. It reads the primer by itself, looks up handlers, and writes
  correct `xt3d_` calls in about 10 seconds.
- Not yet tested: tools that need LiveCode running (no bench was open).
