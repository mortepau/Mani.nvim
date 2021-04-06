local M = {}

local STATUS = { FAILED = 'FAILED', PASSED = 'PASSED', INCOMPLETE = 'INCOMPLETE' }

function M.evaluate(test, output)
  if output == nil then
    return {
      status = STATUS.FAILED,
      reason = 'Expected output should not be nil'
    }
  end

  if test.output == nil then
    return {
      status = STATUS.FAILED,
      reason = 'Actual output should not be nil'
    }
  end

  if type(test.output) ~= type(output) then
    return {
      status = STATUS.FAILED,
      reason = 'Expected output is of type ' .. type(test.output) .. ', while actual output is of type ' .. type(output)
    }
  end

  if type(output) == 'userdata' or type(output) == 'thread' or type(output) == 'function' then
    return {
      status = STATUS.INCOMPLETE,
      reason = 'Cannot verify values of type "' .. type(output) .. '"'
    }
  elseif type(output) == 'table' then
    return M.table_equal(test.output, output)
  else
    if test.output == output then
      return {
        status = STATUS.PASSED,
        reason = 'The expected output and actual output is equal'
      }
    else
      return {
        status = STATUS.FAILED,
        reason = 'The expected output and actual output are not equal: ' .. test.output .. ' ~= ' .. output
      }
    end
  end
end

function M.table_has(entry, table)
  for _, e in ipairs(table) do
    if e == entry then
      return true
    end
  end

  return false
end

function M.table_equal(t1, t2)
  -- Check that both lengths are equal
  if #t1 ~= #t2 then
    return {
      status = STATUS.FAILED,
      reason = 'Different lengths on expected output and actual output'
    }
  end

  for key, value in pairs(t1) do
    -- Check that both tables have the key
    if t2[key] == nil then
      return {
        status = STATUS.FAILED,
        reason = 'The actual output does not have the key ' .. key
      }
    end

    -- Check that the type of the values are equal
    if type(value) ~= type(t2[key]) then
      return {
        status = STATUS.FAILED,
        reason = 'The type of key ' .. key .. ' does not match: ' .. type(value) .. ' ~= ' .. type(t2[key])
      }
    end

    if type(value) == 'table' then
      -- Recurse down if the value is a table
      local retval = M.table_equal(value, t2[key])
      if retval.status ~= STATUS.PASSED then return retval end
    elseif type(value) == 'userdata' or type(value) == 'thread' or type(value) == 'function' then
      return {
        status = STATUS.INCOMPLETE,
        reason = 'Cannot verify values of type "' .. type(value) .. '"'
      }
    else
      -- Check if the values are equal
      if value ~= t2[key] then
        return {
          status = STATUS.FAILED,
          reason = 'The value of key ' .. key .. ' does not match: ' .. value .. ' ~= ' .. t2[key]
        }
      end
    end
  end

  -- All values are equal
  return {
    status = STATUS.PASSED,
    reason = 'All key/value-pairs are equal'
  }
end

return M
