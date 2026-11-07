# EtaDSU

LSPosed module for `com.deepseek.chat` (DeepSeek Android client).

Forces `thinking_enabled` / `search_enabled` to true and injects a prompt prefix
by rewriting the request model fields `h02.e` / `h02.f` / `h02.g`.

## Key technical note

Those three fields are declared `PUBLIC FINAL` in the target app. On Android ART,
`Field.set()` on a final field throws `IllegalAccessException`. The module must
clear the FINAL bit in `Field.modifiers` (`& ~0x10`) before writing, which is what
`stripFinal()` in the source does.

See `GITHUB_ACTIONS_教程.md` for build instructions.
