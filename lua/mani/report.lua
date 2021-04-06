local Report = {}

-- Iterate over all lines and find the max length of the components
local function max_length(lines)
  local max = 0
  local len = 0
  for _, line in ipairs(lines) do
    len = 0

    if line.left then
      len = len + #line.left
    end

    if line.center then
      len = len + #line.center
    end

    if line.right then
      len = len + #line.right
    end

    line.length = len

    if len > max then
      max = len
    end
  end

  return max
end

function Report:new(opts)
  -- Add extra information to report
  self.verbose = opts.verbose == nil and false or opts.verbose

  -- Where to output report
  -- Can be one of 'scratch' or 'messages'
  self.output = opts.output or 'scratch'

  if self.output == 'messages' then
    -- Clear the existing messages before writing
    self.clear_messages = opts.clear_messages == nil and true or opts.clear_messages
  end

  -- Ignore disabled tests in output
  self.ignore_disabled = opts.ignore_disabled == nil and false or opts.ignore_disabled

  -- Minimum line width
  self.min_width = opts.min_width or 40

  self.lines = {}
end

function Report:insert(lines)
  if lines.left or lines.right or lines.center then
    lines = { lines }
  end

  for _, line in ipairs(lines) do
    if not line.opts then
      line.opts = {}
    end

    if (line.opts.verbose and self.verbose) or (not line.opts.verbose) then
      table.insert(self.lines, line)
    end
  end
end

function Report:format()
  local max_width = max_length(self.lines)
  self.line_length = max_width > self.min_width and max_width or self.min_width

  local lines = {}

  for _, line in ipairs(self.lines) do
    local left = line.left or ''
    local center = line.center or ''
    local right = line.right or ''

    local space_left = string.rep(line.opts.fill or ' ', math.floor((self.line_length - line.length) / 2))
    local space_right = string.rep(line.opts.fill or ' ', math.ceil((self.line_length - line.length) / 2))

    local new_line = string.format('%s%s%s%s%s', left, space_left, center, space_right, right)

    table.insert(lines, new_line)
  end

  return lines
end

function Report:write()
  local lines = Report:format()

  if self.output == 'messages' then
    if self.clear_messages then
      vim.cmd('messages clear')
    end

    print(lines)
  else
    -- open a scratch buffer and write output
    vim.cmd('botright ' .. self.line_length + 10 .. 'vnew')
    vim.fn.append(0, lines)
  end
end

return Report
