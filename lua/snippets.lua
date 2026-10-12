-- snippets: the part of the plugin a configuration talks to.
--
--   require("snippets").setup {
--     snippets = {
--       { name = "rebase main", command = "git fetch && git rebase origin/{branch:main}" },
--       { name = "dev", command = "yarn run dev", repo = "kumiko", run = true },
--     },
--   }
--
-- Snippets declared here are read-only on the screen (c copies one into your
-- own). plugin/snippets.lua does the rest; this file holds what
-- configuration declared, so the two share it through require's cache, and
-- the plugin puts pick, save and manage on it for binds of your own.

local M = { declared = {} }

local FIELDS = { name = "string", command = "string", repo = "string", run = "boolean" }

-- A snippet as given, checked as strictly as ranma checks its own settings:
-- the item, or nil and what is wrong with it, naming `where`.
function M.check(item, where)
  if type(item) ~= "table" then return nil, where .. ": a snippet is a table" end
  for k, v in pairs(item) do
    local want = FIELDS[k]
    if not want then return nil, where .. ": unknown field " .. tostring(k) end
    if type(v) ~= want then return nil, where .. "." .. k .. ": a " .. want .. ", not a " .. type(v) end
  end
  if not item.name or item.name == "" then return nil, where .. ": no name" end
  if not item.command or item.command == "" then return nil, where .. " (" .. item.name .. "): no command" end
  if item.repo == "" then item.repo = nil end
  return { name = item.name, command = item.command, repo = item.repo, run = item.run == true }
end

-- Replaces what an earlier call declared: a reload starts the Lua state over
-- anyway, so there is nothing to append to.
function M.setup(opts)
  if type(opts) ~= "table" then error("snippets.setup: takes a table", 2) end
  for k in pairs(opts) do
    if k ~= "snippets" then error("snippets.setup: unknown field " .. tostring(k), 2) end
  end
  local list = {}
  for i, item in ipairs(opts.snippets or {}) do
    local s, err = M.check(item, "snippets.setup: snippets[" .. i .. "]")
    if not s then error(err, 2) end
    list[#list + 1] = s
  end
  M.declared = list
end

return M
