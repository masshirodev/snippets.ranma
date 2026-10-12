# AGENTS.md

snippets.ranma is a ranma plugin in Lua: `plugin/snippets.lua` is the plugin,
and its header comment is the reference that `README.md` repeats.
`lua/snippets.lua` is the small module a configuration `require`s for
`setup`; it only holds the declared snippets and checks them. ranma's API is
https://github.com/masshirodev/ranma/blob/main/doc/CONFIG.md (`ranma --dump-types` prints it as LuaLS annotations).

- Push to `main`.
- A change to what it does changes the header comment and `README.md` in the
  same commit, and an option goes in the README's table.
- Use only API the latest ranma release has: CI loads the plugin into it.
- Check it loads: `ranma --check-config` lists every plugin and why one failed;
  `ranma lua` runs code in the live server.
  CI (`.github/workflows/ci.yml`) loads it into the latest ranma release on
  every push and fails if it does not.
- Try behaviour in a private ranma (its own `RANMA_CONFIG_DIR`,
  `XDG_RUNTIME_DIR` and `XDG_STATE_HOME`, with `RANMA_SOCKET`, `RANMA`,
  `RANMA_PANE` and `TMUX` unset), never in the terminal you work in: the store
  is `$XDG_STATE_HOME/ranma/store/snippets.json`.
- `AGENTS.local.md` (gitignored) carries what is true of one checkout on one
  machine. Never commit it.
