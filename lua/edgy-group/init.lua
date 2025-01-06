local Config = require('edgy.config')
local Editor = require('edgy.editor')
local Util = require('edgy.util')

-- Define groups of edgebar views by title
---@class EdgyGroups
---@field groups_by_pos table<Edgy.Pos, EdgyGroup.IndexedGroups> list of groups for each position
---@field toggle boolean close group if at least one window in the group is open
---@field pick_function? fun(key: string) override the behavior of the pick function when a key is pressed.
local M = {}

---@param opts EdgyGroup.Opts
function M.setup(opts)
  local parsed_opts = require('edgy-group.config').setup(opts)
  M.groups_by_pos = parsed_opts.groups
  M.toggle = parsed_opts.toggle
  M.pick_function = parsed_opts.statusline.pick_function
  require('edgy-group.stl').setup(parsed_opts.groups, parsed_opts.statusline)
  require('edgy-group.commands').setup()
end

---@class EdgyGroup.Indexed
---@field position Edgy.Pos position of the group
---@field index number index of the group at position
---@field group EdgyGroup

-- Get list of EdgyGroup with position by key
---@param key string key to pick a group
---@param position? Edgy.Pos position of the group
---@return EdgyGroup.Indexed[]
function M.get_groups_by_key(key, position)
  local groups_with_pos = {}
  for pos, indexed_groups in pairs(M.groups_by_pos) do
    if position == nil or pos == position then
      for i, group in ipairs(indexed_groups.groups) do
        if group.pick_key == key then table.insert(groups_with_pos, { position = pos, group = group, index = i }) end
      end
    end
  end
  return groups_with_pos
end

-- Filter views by title
---@param views Edgy.View[]
---@param titles string[]
---@return Edgy.View[]
local function filter_by_titles(views, titles)
  -- return vim.tbl_filter(function(view)
  --   return vim.tbl_contains(titles, view.title)
  -- end, views)

  local output = {}
  for _, title in pairs(titles) do
    for _, view in pairs(views) do
      if view.title == title then table.insert(output, view) end
    end
  end
  return output
end

function array_remove(t, fnKeep)
  local j, n = 1, #t

  for i = 1, n do
    if fnKeep(t, i, j) then
      -- Move i's kept value to j's position, if it's not already there.
      if i ~= j then
        t[j] = t[i]
        t[i] = nil
      end
      j = j + 1 -- Increment position of where we'll place the next kept value.
    else
      t[i] = nil
    end
  end

  return t
end

-- Open window from open function
---@param view Edgy.View
local function open(view)
  if type(view.open) == 'function' then
    Util.try(view.open)
  elseif type(view.open) == 'string' then
    Util.try(function()
      vim.cmd(view.open)
    end)
  end
end

-- Close edgebar views for the given position and title
---@param pos Edgy.Pos
---@param titles string[]
function M.close_edgebar_views_by_titles(pos, titles)
  -- print('Close views by pos and titles:', pos, vim.inspect(titles))
  local edgebar = Config.layout[pos]
  if edgebar ~= nil then
    local views = filter_by_titles(edgebar.views, titles)
    for _, view in ipairs(views) do
      for _, win in ipairs(view.wins) do
        -- Hide pinned window
        if win:is_valid() then
          if win:is_pinned() then
            win:hide()
          else
            win:close()
          end
        end
      end
    end
  end
end

-- Open edgebar views for the given position and title
-- Do not open a view if at least one window is already open
---@param pos Edgy.Pos
---@param titles string[]
function M.open_edgebar_views_by_titles(pos, titles)
  -- print('Open views by pos and titles:', pos, vim.inspect(titles))
  local edgebar = Config.layout[pos]
  if edgebar ~= nil then
    local views = filter_by_titles(edgebar.views, titles)
    for _, view in ipairs(views) do
      -- Skip already open views
      local is_open = vim.tbl_contains(view.wins, function(win)
        return win:is_valid()
      end, { predicate = true })
      if not is_open then open(view) end
    end
  end
end

-- Check if at least one window is open for the given position and titles
---@param pos Edgy.Pos
---@param titles string[]
---@return boolean is_open true if at least one window is open
function M.is_one_window_open(pos, titles)
  local edgebar = Config.layout[pos]
  local views = edgebar and edgebar.views or {}
  return vim.tbl_contains(filter_by_titles(views, titles), function(view)
    return vim.tbl_contains(view.wins, function(win)
      return win:is_valid()
    end, { predicate = true })
  end, { predicate = true })
end

-- Open group at index at given position
---@param pos Edgy.Pos
---@param index number Index relative to the group at given position
---@param toggle? boolean either to toggle already selected group or not
function M.open_group_index(pos, index, toggle)
  -- print('Open: ', pos, index, toggle)

  local g = M.groups_by_pos[pos]
  local indexed_group = g and g.groups[index]
  -- print('Open Group: ', vim.inspect(indexed_group))

  if indexed_group then
    -- print('Requested open views by titles: ', vim.inspect(indexed_group.titles))

    local get_view_by_win = function(win)
      win = win or vim.api.nvim_get_current_win()
      for _, edgebar in pairs(Config.layout) do
        for _, w in ipairs(edgebar.wins) do
          if w.win == win then return w.view end
        end
      end
    end

    local wins = Editor.list_wins()
    -- print('Check:', vim.inspect(wins))

    local current_views_by_titles = {}
    for _, win in pairs(wins.edgy) do
      -- print('Win:', win)
      local view = get_view_by_win(win)
      -- print('  Title:', view.title)
      -- print('  Pos:  ', view.edgebar.pos)
      -- print('  Win:  ', win)
      if view.edgebar.pos == pos then table.insert(current_views_by_titles, view.title) end
    end
    -- print('Current views by titles: ', vim.inspect(current_views_by_titles))

    local close_views_by_titles = vim.tbl_deep_extend('force', current_views_by_titles, {})
    array_remove(close_views_by_titles, function(titles, i, _)
      local title = titles[i]
      for _, requested_title in pairs(indexed_group.titles) do
        if requested_title == title then return false end
      end
      return true
    end)
    -- print('Close views by titles: ', vim.inspect(close_views_by_titles))

    -- local open_views_by_titles = vim.tbl_deep_extend('force', indexed_group.titles, {})
    -- array_remove(open_views_by_titles, function(titles, i, _)
    --   local title = titles[i]
    --   for _, current_title in pairs(current_views_by_titles) do
    --     if current_title == title then return false end
    --   end
    --   return true
    -- end)
    -- open_views_by_titles = vim.iter(open_views_by_titles):flatten():totable()
    -- print('Open views by titles: ', vim.inspect(open_views_by_titles))
    -- M.open_edgebar_views_by_titles(pos, open_views_by_titles)

    M.close_edgebar_views_by_titles(pos, close_views_by_titles)
    M.open_edgebar_views_by_titles(pos, indexed_group.titles)

    -- g.selected_index = index
    -- print(vim.inspect({}))
  end
end

-- Open group relative to the currently selected group for the given position
---@param pos Edgy.Pos
---@param offset number
function M.open_group_offset(pos, offset)
  local g = M.groups_by_pos[pos]
  if g then M.open_group_index(pos, g:get_offset_index(offset)) end
end

---@class EdgyGroup.OpenOpts
---@field position? Edgy.Pos position of the group
---@field toggle? boolean toggle a group if at least one window in the group is open

-- Open groups by key, this might open on or multiple groups sharing the same key
---@param key string
---@param opts? EdgyGroup.OpenOpts option to open a group
function M.open_groups_by_key(key, opts)
  local opts = opts or {}
  local toggle_group = opts.toggle == nil and M.toggle or opts.toggle
  vim.iter(M.get_groups_by_key(key, opts.position)):each(function(group)
    -- pcall(M.open_group_index, group.position, group.index, toggle_group)
    vim.schedule(function()
      M.open_group_index(group.position, group.index, toggle_group)
    end)
  end)
end

-- Get the currently selected group for the given position
---@param pos Edgy.Pos
---@return EdgyGroup?
function M.selected(pos)
  local g = M.groups_by_pos[pos]
  return g and g:get_selected_group()
end

return M
