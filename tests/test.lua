local Mani = require('mani')

Mani:new()

Mani:add({
  {
    input = { 1, 2, 3 },
    fn = function(a,b,c) return { c, b, a } end,
    output = { 3, 2, 1 },
  },
  {
    input = { 1, 2, 3 },
    fn = function(a, b, c) return { a * a, b * b, c * c } end,
    output = { 1, 4, 9 }
  },
  {
    input = { 55 },
    fn = function(a) return a end,
    output = 54
  },
  {
    input = { 'a' },
    fn = function(a) return a .. 'b' end,
    output = 'ab',
    namespace = 'String concatenation'
  },
  {
    input = { 'b', 'c' },
    fn = function(a,b) return { a .. 'c', b .. 'd' } end,
    output = { 'bc', 'cd' },
    namespace = 'String concatenation'
  }
})

Mani:run({ disable = 'String concatenation' })

Mani:report({ verbose = true })
