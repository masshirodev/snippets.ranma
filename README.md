# snippets.ranma

A plugin for [ranma](https://github.com/masshirodev/ranma), the terminal tiling window manager: saved shell commands with `{placeholders}`, typed into the focused pane.

## Install

With [hako](https://github.com/masshirodev/hako.ranma), in `~/.config/ranma/lua/plugins/snippets.lua`:

```lua
return { "masshirodev/snippets.ranma" }
```

Or by hand, as ranma loads any package under `pack/*/start/`:

```sh
git clone https://github.com/masshirodev/snippets.ranma ~/.config/ranma/pack/plugins/start/snippets.ranma
```

Needs: Nothing beyond ranma. `snip save` needs a shell that marks its commands with OSC 133 (ranma's [CONFIG.md](https://github.com/masshirodev/ranma/blob/main/doc/CONFIG.md), "Hooks").

## What it does

```text
snippets: saved shell commands, typed into the focused pane.

leader shift+c is a which-key folder: p the picker, s snip save, m snip
manage (require("snippets").pick, .save and .manage, to bind them
elsewhere). The picker lists snippets: the ones scoped to the pane's
repository first, then the ones for everywhere (a snippet scoped to another
repository is hidden unless snippets.show_all). Picking one asks for each
{placeholder} in it, or {placeholder:default}, one prompt each (the last
value given is offered next time), and types the result into the pane
WITHOUT Enter, so you read it first; a snippet with run = true presses Enter
too. A snippet of several lines is pasted, so a shell does not run it line
by line.

A placeholder is {name} or {name:default}, name being letters, digits, _
and -, starting with a letter or _. Anything else in braces is left alone:
${HOME}, {print $1}, {a,b}, {1..5}, find's {}.

The palette's snip command:
  snip            the picker
  snip NAME       that snippet straight away
  snip save       save the last command the pane ran as a snippet
  snip manage     the screen below
On the screen (filtered by name with /):
  enter  use it          n  new             e  edit its command
  r      rename          s  this repo / everywhere
  x      run on/off      d  delete (y confirms)
  c      copy a snippet from your configuration into your own

Your own snippets are kept in ranma.store("snippets"). Snippets from your
configuration are read-only here: require("snippets").setup { snippets =
{ { name =, command =, repo =, run = }, ... } } in init.lua (or in hako's
config function), or a JSON file of the same list named by snippets.file.
One of yours shadows a configured one of the same name, so c and then e is
how you change one. A repository is the name of the directory holding the
.git above the pane's directory (`kumiko` for ~/projects/kumiko/src).

`snip save` reads the command off the pane's screen as the shell starts it,
so it needs the OSC 133 marks ranma's CONFIG.md describes ("Hooks":
command_started). It takes the text after the first of snippets.prompt_ends
on the prompt's line; when a quick command has printed and the next prompt
is up already, the line above with the same prompt. Output that draws a
line like your prompt can fool it, so you correct it before it is saved.
```

## Binds and commands

| Key or command | |
| --- | --- |
| `leader shift+c` | A which-key folder, `snippets`, under the `plugins` group. |
| `leader shift+c p` | The picker. |
| `leader shift+c s` | `snip save`. |
| `leader shift+c m` | `snip manage`. |
| `snip` | The picker. |
| `snip NAME` | That snippet straight away (the palette completes names). |
| `snip save` | Save the last command the pane ran as a snippet. |
| `snip manage` | The screen: add, edit, rename, scope, delete. |

To move the folder, unbind it in `init.lua` after the plugin loads and bind the commands where you like, for example `ranma.unbind("shift+c")` and then `ranma.bind("n", function() require("snippets").pick() end, { desc = "snippets", exit = true })`. The module also has `save` and `manage`.

## Snippets in your configuration

A list in `init.lua`, or in hako's `config` function (hako's `opts` only sets options, and a list is not one):

```lua
return {
  "masshirodev/snippets.ranma",
  config = function()
    require("snippets").setup {
      snippets = {
        { name = "rebase main", command = "git fetch && git rebase origin/{branch:main}" },
        { name = "dev", command = "yarn run dev", repo = "kumiko", run = true },
      },
    }
  end,
}
```

Or the same list as JSON in a file that `snippets.file` names, which is read again whenever it changes. Each snippet takes `name` and `command`, and optionally `repo` (only in that repository) and `run` (press Enter after it). An unknown field is an error.

## Options

In ranma's settings panel under `snippets`, or with hako's `opts` (`{ "masshirodev/snippets.ranma", opts = { ... } }`), or `ranma.set { snippets = { ... } }` after the plugin has loaded.

| Option | Default | |
| --- | --- | --- |
| `snippets.show_all` | `false` | List snippets scoped to other repositories too, after the rest. |
| `snippets.file` | `""` | A JSON file of read-only snippets: a list of `{ name, command, repo, run }`. `~/` is your home. |
| `snippets.prompt_ends` | `"❯ ➜ $ % # > » λ"` | What a prompt ends with, separated by spaces: `snip save` takes the command after the first of them on its line. |

## License

MIT or Apache-2.0, as ranma.
