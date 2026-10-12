-- snippets: saved shell commands, typed into the focused pane.
--
-- leader shift+c opens a picker of snippets: the ones scoped to the pane's
-- repository first, then the ones for everywhere (a snippet scoped to another
-- repository is hidden unless snippets.show_all). Picking one asks for each
-- {placeholder} in it, or {placeholder:default}, one prompt each (the last
-- value given is offered next time), and types the result into the pane
-- WITHOUT Enter, so you read it first; a snippet with run = true presses Enter
-- too. A snippet of several lines is pasted, so a shell does not run it line
-- by line.
--
-- A placeholder is {name} or {name:default}, name being letters, digits, _
-- and -, starting with a letter or _. Anything else in braces is left alone:
-- ${HOME}, {print $1}, {a,b}, {1..5}, find's {}.
--
-- The palette's snip command:
--   snip            the picker
--   snip NAME       that snippet straight away
--   snip save       save the last command the pane ran as a snippet
--   snip manage     the screen below
-- On the screen (filtered by name with /):
--   enter  use it          n  new             e  edit its command
--   r      rename          s  this repo / everywhere
--   x      run on/off      d  delete (y confirms)
--   c      copy a snippet from your configuration into your own
--
-- Your own snippets are kept in ranma.store("snippets"). Snippets from your
-- configuration are read-only here: require("snippets").setup { snippets =
-- { { name =, command =, repo =, run = }, ... } } in init.lua (or in hako's
-- config function), or a JSON file of the same list named by snippets.file.
-- One of yours shadows a configured one of the same name, so c and then e is
-- how you change one. A repository is the name of the directory holding the
-- .git above the pane's directory (`kumiko` for ~/projects/kumiko/src).
--
-- `snip save` reads the command off the pane's screen as the shell starts it,
-- so it needs the OSC 133 marks ranma's CONFIG.md describes ("Hooks":
-- command_started). It takes the text after the first of snippets.prompt_ends
-- on the prompt's line; when a quick command has printed and the next prompt
-- is up already, the line above with the same prompt. Output that draws a
-- line like your prompt can fool it, so you correct it before it is saved.
--
-- ranma's plugin API: https://github.com/masshirodev/ranma/blob/main/doc/CONFIG.md ("Pickers and
-- prompts", "Screens", "A plugin's state", "Commands", "Hooks").

ranma.option("snippets.show_all", {
  type = "bool", default = false,
  name = "Every repository's", desc = "List snippets scoped to other repositories too, after the rest.",
})
ranma.option("snippets.file", {
  type = "string", default = "",
  name = "From a file", desc = "A JSON file of read-only snippets: a list of { name, command, repo, run }. ~/ is your home.",
})
ranma.option("snippets.prompt_ends", {
  type = "string", default = "❯ ➜ $ % # > » λ",
  name = "Prompt ends with",
  desc = "What a prompt ends with, separated by spaces: snip save takes the command after the first of them on its line.",
})

local api = require("snippets")
local store = ranma.store("snippets")
local HOME = os.getenv("HOME") or ""

-- The placeholder syntax, with what precedes the brace so ${VAR} is skipped,
-- and what follows the name so {print $1} and {a,b} are too.
local PH = "(%$?){([%a_][%w_%-]*)(:?)([^{}\n]*)}"

local function is_placeholder(dollar, colon, default)
  return dollar == "" and (colon == ":" or default == "")
end

-- Each placeholder once, in order, with the first default given for it.
local function fields(command)
  local list, seen = {}, {}
  for dollar, name, colon, default in command:gmatch(PH) do
    if is_placeholder(dollar, colon, default) and not seen[name] then
      seen[name] = true
      list[#list + 1] = { name = name, default = default }
    end
  end
  return list
end

local function fill(command, values)
  return (command:gsub(PH, function(dollar, name, colon, default)
    if is_placeholder(dollar, colon, default) then return values[name] end
  end))
end

-- The name of the repository `dir` is in, or nil. A .git file counts too:
-- that is a worktree.
local function repo_of(dir)
  while dir and dir ~= "" do
    local f = io.open(dir .. "/.git", "r")
    if f then
      f:close()
      return dir:match("([^/]+)/*$")
    end
    if dir == "/" then return nil end
    dir = dir:match("^(.*)/[^/]*$")
    if dir == "" then dir = "/" end
  end
end

local function mine()
  return store:get("snippets") or {}
end

local function find_mine(name)
  for i, s in ipairs(mine()) do
    if s.name == name then return i, s end
  end
end

-- Writes the whole list: a store is written whole on every set anyway.
local function save_mine(list)
  store:set("snippets", list)
end

-- The file is read on every listing, so an edit shows without a reload; its
-- text is parsed again only when it changed, and a fault toasts once, not on
-- every key the screen takes.
local file_cache = { path = nil, text = nil, list = {}, said = nil }

local function file_fault(msg)
  if file_cache.said ~= msg then
    file_cache.said = msg
    ranma.toast("snippets: " .. msg, { urgent = true })
  end
  return {}
end

local function from_file()
  local path = ranma.get("snippets.file")
  if path == "" then return {} end
  path = path:gsub("^~/", HOME .. "/")
  local f = io.open(path, "r")
  if not f then return file_fault("cannot read " .. path) end
  local text = f:read("a")
  f:close()
  if path == file_cache.path and text == file_cache.text then return file_cache.list end
  file_cache.path, file_cache.text, file_cache.list = path, text, {}
  local ok, list = pcall(ranma.json.decode, text)
  if not ok or type(list) ~= "table" then return file_fault(path .. " is not a JSON list") end
  local out = {}
  for i, item in ipairs(list) do
    local snip, err = api.check(item, path .. "[" .. i .. "]")
    if not snip then return file_fault(err) end
    out[#out + 1] = snip
  end
  file_cache.list, file_cache.said = out, nil
  return out
end

-- Every snippet with where it came from and an id for the screen; stored
-- ones are named by name, which is unique among them.
local function everything()
  local all = {}
  for _, s in ipairs(mine()) do
    all[#all + 1] = { snip = s, id = "s:" .. s.name, own = true }
  end
  for i, s in ipairs(api.declared) do
    all[#all + 1] = { snip = s, id = "c:" .. i, from = "init.lua" }
  end
  for i, s in ipairs(from_file()) do
    all[#all + 1] = { snip = s, id = "f:" .. i, from = "snippets.file" }
  end
  return all
end

-- Snippets for `repo`, those for everywhere, and those for other repositories.
local function sorted(repo)
  local here, everywhere, other = {}, {}, {}
  for _, e in ipairs(everything()) do
    local r = e.snip.repo
    if not r then everywhere[#everywhere + 1] = e
    elseif r == repo then here[#here + 1] = e
    else other[#other + 1] = e end
  end
  return here, everywhere, other
end

local function last_values(name)
  return (store:get("last") or {})[name] or {}
end

local function remember_values(name, values)
  local last = store:get("last") or {}
  last[name] = values
  store:set("last", last)
end

-- Typing it. A newline sent as text is Enter, so several lines are pasted
-- instead: bracketed, a shell takes them as one edit and runs nothing yet.
local function deliver(p, text, run)
  if not p:alive() then return ranma.toast("snippets: the pane is gone", { urgent = true }) end
  if text:find("\n", 1, true) then p:paste(text) else p:send(text) end
  if run then p:keys("return") end
end

-- Asks for each placeholder in turn, then types the snippet into `p`.
local function use(s, p)
  if not p then return ranma.toast("snippets: no pane to type into", { urgent = true }) end
  local list = fields(s.command)
  local last = last_values(s.name)
  local values = {}
  local function ask(i)
    if i > #list then
      if #list > 0 then remember_values(s.name, values) end
      return deliver(p, fill(s.command, values), s.run)
    end
    local f = list[i]
    ranma.input {
      title = s.name .. " · " .. f.name .. (#list > 1 and (" (" .. i .. "/" .. #list .. ")") or ""),
      text = last[f.name] or f.default,
      on_submit = function(text)
        values[f.name] = text
        ask(i + 1)
      end,
    }
  end
  ask(1)
end

local function one_line(text)
  local first, rest = text:match("^([^\n]*)\n(.*)$")
  if not first then return text end
  local _, n = rest:gsub("\n", "")
  return first .. "  (+" .. (n + 1) .. " lines)"
end

-- One of yours shadows a configured snippet of the same name: c copies one
-- into your own to change it, and the copy is the one used from then on.
local function shadowed(e)
  return not e.own and find_mine(e.snip.name) ~= nil
end

local function pick()
  local p = ranma.pane()
  if not p then return ranma.toast("snippets: no pane to type into", { urgent = true }) end
  local repo = repo_of(p:cwd())
  local here, everywhere, other = sorted(repo)
  local items = {}
  local function add(list, tag)
    for _, e in ipairs(list) do
      if not shadowed(e) then
        local detail = one_line(e.snip.command)
        if tag then detail = detail .. "  · " .. tag(e) end
        items[#items + 1] = { label = e.snip.name, detail = detail, snip = e.snip }
      end
    end
  end
  add(here, function() return repo end)
  add(everywhere)
  if ranma.get("snippets.show_all") then add(other, function(e) return e.snip.repo end) end
  if #items == 0 then
    return ranma.toast("snippets: none yet. snip save keeps the last command, snip manage adds one")
  end
  ranma.picker {
    title = repo and ("snippets · " .. repo) or "snippets",
    items = items,
    on_select = function(item) use(item.snip, p) end,
  }
end

-- A screen line split at its prompt: what the prompt is, up to and with the
-- first of snippets.prompt_ends followed by a space (or ending the line), and
-- what was typed after it; nil if no prompt end is on it. Four spaces or more
-- and then text at the end is taken for a right prompt and cut off.
local function split_prompt(line)
  line = line:gsub("%s%s%s%s+%S.*$", ""):gsub("%s+$", "")
  local best_s, best_e
  for mark in ranma.get("snippets.prompt_ends"):gmatch("%S+") do
    local s, e = line:find(mark, 1, true)
    while s do
      local after = line:sub(e + 1, e + 1)
      if after == " " or after == "" then
        if not best_s or s < best_s then best_s, best_e = s, e end
        break
      end
      s, e = line:find(mark, e + 1, true)
    end
  end
  if not best_s then return nil end
  return line:sub(1, best_e), line:sub(best_e + 1):match("^%s*(.-)$")
end

-- The command the shell has just started, read off the screen. The hook
-- runs once ranma has read all the output that came with the start mark, so
-- a quick command may have printed and the next prompt be up already: then
-- the command is on the nearest line above with the same prompt (or, after
-- a cd changed it, any prompt). Otherwise it is on the last prompt line.
local function command_line(p)
  local top = p:range()
  local lines = p:lines(math.max(top, -200), p.rows - 1)
  local last
  for i = #lines, 1, -1 do
    if lines[i]:find("%S") then last = i break end
  end
  if not last then return nil end
  local prompt, typed = split_prompt(lines[last])
  if prompt and typed == "" then
    for i = last - 1, 1, -1 do
      local pr, cmd = split_prompt(lines[i])
      if pr == prompt and cmd ~= "" then return cmd end
    end
    last = last - 1
  end
  for i = last, 1, -1 do
    local pr, cmd = split_prompt(lines[i])
    if pr and cmd ~= "" then return cmd end
  end
end

ranma.on("command_started", function(ev)
  local p = ranma.pane(ev.pane)
  if not p then return end
  local cmd = command_line(p)
  if cmd then p.vars.snippets_last = cmd end
end)

local function add_mine(s)
  local list = mine()
  list[#list + 1] = s
  save_mine(list)
end

local function save_last()
  local p = ranma.pane()
  local repo = p and repo_of(p:cwd())
  ranma.input {
    title = "snippet command",
    text = p and p.vars.snippets_last or "",
    on_submit = function(command)
      if command == "" then return end
      ranma.input {
        title = "snippet name",
        text = command:match("^%S+") or "",
        on_submit = function(name)
          if name == "" then return end
          if find_mine(name) then return ranma.toast("snippets: " .. name .. " exists already", { urgent = true }) end
          local function keep(r)
            add_mine({ name = name, command = command, repo = r, run = false })
            ranma.toast("saved " .. name .. (r and (" for " .. r) or ""))
          end
          if not repo then return keep(nil) end
          ranma.picker {
            title = "use " .. name .. " in",
            items = { { label = "every directory", r = false }, { label = "only " .. repo, r = repo } },
            on_select = function(item) keep(item.r or nil) end,
          }
        end,
      }
    end,
  }
end

-- The screen.

local state = { screen = nil, repo = nil, pane = nil }

local function entry(id)
  for _, e in ipairs(everything()) do
    if e.id == id then return e end
  end
end

local function close()
  if state.screen then state.screen:close() end
  state.screen = nil
end

local refresh

-- Changes one of your own snippets in place, by name; nil if it went meanwhile.
local function change(name, fn)
  local list = mine()
  local i = find_mine(name)
  if not i then return nil end
  fn(list[i])
  save_mine(list)
  return list[i]
end

local function ask_text(prompt, text, fn)
  state.screen:ask {
    blocks = { { "text", prompt, strong = true } },
    input = { prefix = "›", text = text or "" },
    keys = { { "enter", "save", function(_, t) fn(t or "") end }, { "esc", "cancel" } },
  }
end

local function own(id, fn)
  local e = entry(id)
  if not e then return end
  if not e.own then return ranma.notify("from " .. e.from .. ": c copies it into your own") end
  fn(e.snip)
end

local row_keys = {
  { "enter", "use", function(id)
    local e = entry(id)
    if not e then return end
    local p = state.pane
    close()
    use(e.snip, p and p:alive() and p or ranma.pane())
  end },
  { "e", "edit", function(id)
    own(id, function(s)
      ask_text("The command for " .. s.name .. ":", s.command, function(t)
        if t == "" then return end
        change(s.name, function(x) x.command = t end)
        refresh(id)
      end)
    end)
  end },
  { "r", "rename", function(id)
    own(id, function(s)
      ask_text("A new name for " .. s.name .. ":", s.name, function(t)
        if t == "" or t == s.name then return end
        if find_mine(t) then return ranma.notify(t .. " exists already") end
        change(s.name, function(x) x.name = t end)
        refresh("s:" .. t)
      end)
    end)
  end },
  { "s", "scope", function(id)
    own(id, function(s)
      if not s.repo and not state.repo then return ranma.notify("the pane is in no repository") end
      change(s.name, function(x) x.repo = (not x.repo) and state.repo or nil end)
      refresh(id)
    end)
  end },
  { "x", "run", function(id)
    own(id, function(s)
      change(s.name, function(x) x.run = not x.run end)
      refresh(id)
    end)
  end },
  { "d", "delete", function(id)
    own(id, function(s)
      state.screen:ask {
        blocks = { { "text", "Delete " .. s.name .. "?", role = "urgent", strong = true },
                   { "log", lines = { s.command } } },
        keys = {
          { "y", "delete it", function()
            local list, i = mine(), find_mine(s.name)
            if i then table.remove(list, i) save_mine(list) end
            refresh()
          end, role = "urgent" },
          { "esc", "keep it" },
        },
      }
    end)
  end },
  { "c", "copy to mine", function(id)
    local e = entry(id)
    if not e then return end
    if e.own then return ranma.notify("it is yours already") end
    local name = e.snip.name
    while find_mine(name) do name = name .. "'" end
    add_mine({ name = name, command = e.snip.command, repo = e.snip.repo, run = e.snip.run })
    refresh("s:" .. name)
  end },
}

local function row(e)
  local s = e.snip
  local list = fields(s.command)
  local names = {}
  for _, f in ipairs(list) do names[#names + 1] = f.name end
  local facts = { "facts",
    { "where", s.repo or "everywhere" },
    { "enter", s.run and "runs it" or "types it" },
    { "from", e.own and "yours" or e.from } }
  if #names > 0 then facts[#facts + 1] = { "asks", table.concat(names, ", ") } end
  local value
  if shadowed(e) then value = { "yours instead", "dim" }
  elseif not e.own then value = { "read-only", "dim" }
  elseif s.run then value = { "runs", "accent" } end
  return {
    "row", id = e.id, name = s.name, note = one_line(s.command), value = value,
    keys = row_keys,
    detail = { { "text", s.command, max = 4 }, facts },
  }
end

local function body()
  local here, everywhere, other = sorted(state.repo)
  local out, n = {}, 0
  local function group(title, tag, list)
    if #list == 0 then return end
    out[#out + 1] = { "heading", title, tag = tag, count = #list }
    for _, e in ipairs(list) do
      out[#out + 1] = row(e)
      n = n + 1
    end
  end
  if state.repo then group("Here", state.repo, here) end
  group("Everywhere", nil, everywhere)
  group("Other repositories", nil, other)
  return out, n
end

local function count(n)
  return n == 1 and "1 snippet" or (n .. " snippets")
end

function refresh(select)
  if not state.screen then return end
  local b, n = body()
  state.screen:set { body = b, count = count(n), select = select }
end

local function new()
  ask_text("The new snippet's name:", "", function(name)
    if name == "" then return end
    if find_mine(name) then return ranma.notify(name .. " exists already") end
    ask_text("The command for " .. name .. " ({placeholder} or {placeholder:default}):",
      state.pane and state.pane:alive() and state.pane.vars.snippets_last or "", function(command)
        if command == "" then return end
        add_mine({ name = name, command = command, repo = nil, run = false })
        refresh("s:" .. name)
      end)
  end)
end

local function manage()
  local p = ranma.pane()
  state.pane = p
  state.repo = p and repo_of(p:cwd())
  local b, n = body()
  state.screen = ranma.screen {
    title = "snippets", chip = "SNIP", filter = "names", detail = 6, options = true,
    count = count(n),
    status = { state.repo or "no repository", "dim" },
    empty = "no snippets: n adds one",
    body = b,
    keys = { { "n", "new", new } },
    card = {
      { "enter", "type it into the pane (run = true presses Enter)" },
      { "n", "a new snippet" },
      { "e", "edit its command" },
      { "r", "rename it" },
      { "s", "only this repository, or everywhere" },
      { "x", "press Enter after it, or not" },
      { "d", "delete it (y confirms)" },
      { "c", "copy one from your configuration into your own" },
      { "o", "options" },
    },
    on_close = function() state.screen = nil end,
  }
end

local function by_name(name)
  for _, e in ipairs(everything()) do
    if e.snip.name == name then return e.snip end
  end
end

ranma.command("snip", function(arg)
  arg = arg and arg:match("^%s*(.-)%s*$") or ""
  if arg == "" then return pick() end
  if arg == "save" then return save_last() end
  if arg == "manage" then return manage() end
  local s = by_name(arg)
  if not s then return ranma.toast("snippets: no snippet named " .. arg, { urgent = true }) end
  use(s, ranma.pane())
end, {
  desc = "saved commands", args = "[NAME|save|manage]",
  complete = function()
    local names = { "save", "manage" }
    for _, e in ipairs(everything()) do names[#names + 1] = e.snip.name end
    return names
  end,
})

ranma.bind("shift+c", pick, { desc = "snippets", group = "plugins", exit = true })
