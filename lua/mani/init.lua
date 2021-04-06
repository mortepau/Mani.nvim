local evaluator = require('mani.evaluator')
local report = require('mani.report')

local Mani = {}

local STATUS = {
  -- Test output equals expected output
  PASSED     = 'PASSED',
  -- Test output not equal expected output
  FAILED     = 'FAILED',
  -- Test is waiting to execute
  WAITING    = 'WAITING',
  -- Test could not finish
  INCOMPLETE = 'INCOMPLETE',
  -- Test could finish
  COMPLETED  = 'COMPLETED',
  -- Test is disabled
  DISABLED   = 'DISABLED',
}

local function time_to_string(time)
  if time == 0 then
    return '0.000s'
  elseif time < 1e-12 then
    local new_time = time * 1e15
    return string.format('%.3f%s', new_time, 'fs')
  elseif time < 1e-9 then
    local new_time = time * 1e12
    return string.format('%.3f%s', new_time, 'ps')
  elseif time < 1e-6 then
    local new_time = time * 1e9
    return string.format('%.3f%s', new_time, 'ns')
  elseif time < 1e-3 then
    local new_time = time * 1e6
    return string.format('%.3f%s', new_time, 'us')
  elseif time < 1 then
    local new_time = time * 1e3
    return string.format('%.3f%s', new_time, 'ms')
  elseif time < 60 then
    local new_time = time
    return string.format('%.3f%s', new_time, 's')
  else
    return string.format('%d%s %.3f%s', math.floor(time / 60), 'min', time % 60, 's')
  end
end

-- Create a new test environment
-- Accepts a table of values
-- Optional keys:
--  name_generator - Function to generate names for the tests if they are
--                   unnamed
function Mani:new(opts)
  if opts == nil then
    opts = {}
  end

  if opts.name_generator then
    local fn
    if type(opts.name_generator) == 'string' then
      fn = function(value) return opts.name_generator .. value end
    elseif type(opts.name_generator) == 'table' then
      fn = function(value) return opts.name_generator[value] end
    elseif type(opts.name_generator) == 'function' then
      fn = opts.name_generator
    else
      error('[Mani] new: name_generator must be one of string, table or function')
    end
    self.name_generator = {
      counter = 0,
      fn = fn
    }
  else
    self.name_generator = {
      counter = 0,
      fn = function(value) 
        return 'Anonymous Test #' .. value
      end
    }
  end

  -- Table of test results
  self.results = {
    passed     = 0,
    failed     = 0,
    incomplete = 0,
    completed  = 0,
    disabled   = 0,
    total      = 0
  }

  -- Total execution time of all tests
  self.execution_time = 0

  -- Table of test specs
  self.tests = {}

  -- Table for namespace information
  self.namespaces = {}
end

-- TODO: Move this to somewhere more sane
function Mani:generate_name()
  self.name_generator.counter = self.name_generator.counter + 1
  return self.name_generator.fn(self.name_generator.counter)
end

-- Add a new specification to the list of test specifications.
-- Accepts either a table for a single spec or a table of specs
-- Required keys:
--  input - Table of inputs for `fn`
--  fn - Function accepting `input`
--  output - Expected output from running `fn` with `input` as input
-- Optional keys:
--  name - Name to use for test in report
--  namespace - Namespace for test, if disabling a set of tests
--  enforce_keys - Enforce that all keys in output are present
--  expect_error - Expect the test to raise an error
function Mani:add(specs)
  -- If a single spec is inserted, wrap it so that we can use the same
  -- functionality for a single and multiple specs
  if specs.input then
    specs = { specs }
  end

  -- Insert all the new specs in the tests variable
  for _, spec in ipairs(specs) do
    -- Verify that the required keys are present and have the correct type
    assert(
      spec.input, 
      '[Mani] add: "input" key is required'
    )
    assert(
      type(spec.input) == 'table',
      '[Mani] add: "input" key has to be a table'
    )
    assert(
      spec.fn,
      '[Mani] add: "fn" key is required'
    )
    assert(
      type(spec.fn) == 'function',
      '[Mani] add: "fn" key has to be a function'
    )
    assert(
      spec.output,
      '[Mani] add: "output" key is required'
    )

    if not spec.name then
      spec.name = self:generate_name()
    end

    if not spec.namespace then
      spec.namespace = 'General'
    end

    if spec.enforce_keys ~= nil then
      spec.enforce_keys = false
    end

    if spec.expect_error ~= nil then
      spec.expect_error = false
    end

    -- Current status for the test
    spec.result = {
      status = STATUS.WAITING,
      reason = 'Waiting to run'
    }
    -- Flag to define if the test is disabled or not
    spec.disabled = false

    -- Time to execute test
    spec.execution_time = 0

    if self.tests[spec.namespace] == nil then
      self.tests[spec.namespace] = {}
    end
    table.insert(self.tests[spec.namespace], spec)
    self.results.total = self.results.total + 1

    if self.namespaces[spec.namespace] == nil then
      self.namespaces[spec.namespace] = {
        results = {
          passed     = 0,
          failed     = 0,
          completed  = 0,
          incomplete = 0,
          disabled   = 0,
          total      = 0
        },
        execution_time = 0
      }
    end
  end
end

-- Run all the added tests
-- Opts is a table that can have the following keys:
--  disable - Either a string or a table of strings of namespaces to disable
function Mani:run(opts)
  opts = opts or {}
  if opts.disable then
    assert(
      type(opts.disable) == 'string' or type(opts.disable) == 'table',
      '[Mani] run: The disable key has to either be a string or a table of strings'
    )

    -- Disable all tests in the disabled namespaces
    local namespaces = type(opts.disable) == 'string' and { opts.disable } or opts.disable
    for _, namespace in ipairs(namespaces) do
      for test_namespace, tests in pairs(self.tests) do
        if namespace == test_namespace then
          for _, test in ipairs(tests) do
            test.disabled = true
          end
        end
      end
    end
  end

  assert(
    self.results.total > 0,
    '[Mani] run: Need at least 1 test to run'
  )

  for namespace, tests in pairs(self.tests) do
    for i, test in ipairs(tests) do
      test.number = i
      self.namespaces[namespace].results.total = self.namespaces[namespace].results.total + 1
      if test.disabled then
        self.results.disabled = self.results.disabled + 1
        self.namespaces[namespace].results.disabled = self.namespaces[namespace].results.disabled + 1
        test.result = {
          status = STATUS.DISABLED,
          reason = 'Disabled as it belongs to the namespace "' .. test.namespace .. '"'
        }
      else
        -- Execute the test
        local test_info = Mani:execute(test)

        -- Update the results table with whether the test completed or not
        self.results[string.lower(test_info.result.status)] = self.results[string.lower(test_info.result.status)] + 1
        -- Update the namespace results table
        self.namespaces[namespace].results[string.lower(test_info.result.status)] = self.namespaces[namespace].results[string.lower(test_info.result.status)] + 1

        -- Update the execution time tables
        test.execution_time = test_info.time
        self.execution_time = self.execution_time + test_info.time
        self.namespaces[namespace].execution_time = self.namespaces[namespace].execution_time + test.execution_time

        if test_info.result.status == STATUS.COMPLETED then
          -- Evaluate the output
          test.result = evaluator.evaluate(test, test_info.output)

          -- Update the results table with the status after evaluating the output
          self.results[string.lower(test.result.status)] = self.results[string.lower(test.result.status)] + 1
          self.namespaces[namespace].results[string.lower(test.result.status)] = self.namespaces[namespace].results[string.lower(test.result.status)] + 1
        else
          test.result = test_info.result
        end
      end
    end
  end
end

function Mani:execute(test)
  -- Small workaround to be able to unpack args
  local function test_wrapper(fn, args)
    return fn(unpack(args))
  end

  local start_time, end_time

  start_time = os.clock()
  local ok, result = pcall(test_wrapper, test.fn, test.input)
  end_time = os.clock()

  -- TODO: Do something with test.expect_error
  if not ok and not test.expect_error then
    return {
      result = {
        status = STATUS.INCOMPLETE,
        reason = result,
      },
      output = {},
      time = end_time - start_time
    }
  else
    return {
      result = {
        status = STATUS.COMPLETED,
        reason = 'Test finished executing',
      },
      output = result,
      time = end_time - start_time
    }
  end
end

function Mani:report(opts)
  report:new(opts)

  report:insert({
    {
      left = '+', rigth = '+', opts = { fill = '=' }
    },
    {
      left = '|', center = 'Mani Test Report', right = '|'
    },
    {
      left = '+', rigth = '+', opts = { fill = '=' }
    }
  })

  for namespace, tests in pairs(self.tests) do
    report:insert({
      {
        left = '+', right = '+', opts = { verbose = true, fill = '-' }
      },
      {
        left = '|',
        center = namespace,
        right = '|',
        opts = { verbose = true }
      },
      {
        left = '+', right = '+', opts = { verbose = true, fill = '-' }
      }
    })

    for _, test_result in ipairs(tests) do
      report:insert({
        {
          left = string.format('Test #%0d: %s', test_result.number, test_result.name),
          opts = { verbose = true}
        },
        {
          left = '    Status: ' .. test_result.result.status,
          opts = { verbose = true }
        },
        {
          left = '    Reason: ' .. test_result.result.reason,
          opts = { verbose = true }
        },
        {
          left = '    Execution time: ' .. time_to_string(test_result.execution_time),
          opts = { verbose = true }
        }
      })
    end

    report:insert({
      {
        left = '-', right = '-', opts = { fill = '-' }
      },
      {
        left = 'Summary:'
      },
      {
        left = '    Passed:',
        right = self.namespaces[namespace].results.passed .. ' test(s)'
      },
      {
        left = '    Failed:',
        right = self.namespaces[namespace].results.failed .. ' test(s)'
      },
      {
        left = '    Incomplete:',
        right = self.namespaces[namespace].results.incomplete .. ' test(s)'
      },
      {
        left = '    Disabled:',
        right = self.namespaces[namespace].results.disabled .. ' test(s)'
      },
      {
        left = '    -',
        right = '-',
        opts = { fill = '-' }
      },
      {
        left = '    Total:',
        right = self.namespaces[namespace].results.total .. ' test(s)'
      },
      {
        left = '    -',
        right = '-',
        opts = { fill = '-' }
      },
      {
        left = '    Execution time:',
        right = time_to_string(self.namespaces[namespace].execution_time)
      }
    })
  end

  report:insert({
    {
      left = '+', right = '+', opts = { fill = '=' }
    },
    {
      left = '|', center = 'Summary', right = '|'
    },
    {
      left = '+', right = '+', opts = { fill = '=' }
    },
    {
      left = 'Passed:',
      right = self.results.passed .. ' test(s)',
    },
    {
      left = 'Failed:',
      right = self.results.failed .. ' test(s)',
    },
    {
      left = 'Incomplete:',
      right = self.results.incomplete .. ' test(s)',
    },
    {
      left = 'Disabled:',
      right = self.results.disabled .. ' test(s)',
    },
    {
      left = '-', right = '-', opts = { fill = '-' }
    },
    {
      left = 'Total:',
      right = self.results.total .. ' test(s)',
    },
    {
      left = '-', right = '-', opts = { fill = '-' }
    },
    {
      left = 'Execution time:',
      right = time_to_string(self.execution_time)
    },
    {
      left = '-', right = '-', opts = { fill = '-' }
    }
  })

  report:write()
end

return Mani
