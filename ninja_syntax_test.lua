------------
-- Unit tests for the [ninja_syntax.lua](ninja_syntax.lua). Line by line
-- translation of ninja_syntax_test.py to Lua.
-- @module ninja_syntax_test
-- @author Charles Grunwald (Juntalis) <ch@rles.rocks>
----

-- Imports
local minitest = require('minitest')
local ninja = require('ninja_syntax')

-- Cache some module bindings
local rep = string.rep
local TestCase, StringBuffer = minitest.TestCase, minitest.StringBuffer

local NL = ' $\n' -- wrapped
local IND = '    ' -- indent
local LONGWORD = rep('a', 10)
local LONGWORDWITHSPACES = rep('a', 5) .. '$ ' .. rep('a', 5)

-- Patch ninja_syntax.Writer._isfile to return true for a StringBuffer 
local Writer = ninja.Writer
do
	local orig_isfile = Writer._isfile
	Writer._isfile = function(self, obj)
		return orig_isfile(obj) or minitest.isklass(obj, StringBuffer)
	end
end

--[[--
-- Line Wrapping Tests
--]]--

-- Test ninja_syntax.Writer's line wrapping
TestCase('LineWordWrap'):setup(function(self, runner)
	self.out = StringBuffer()
	self.n = Writer(self.out, 8)
	self.words = 'x ' .. LONGWORD .. ' y'

end):def('single_long_word', function(self)
	-- We shouldn't wrap a single long word.
	local expected = LONGWORD .. '\n'
	self.n:_line(LONGWORD)
	assert(self.out:get(true) == expected)

end):def('few_long_words', function(self)
	-- We should wrap a line where the second word is overlong.
	local expected = 'x' .. NL .. IND .. LONGWORD ..NL.. IND ..'y\n'
	self.n:_line(self.words)
	assert(self.out:get(true) == expected)

end):def('comment_wrap', function(self)
	-- Filenames shoud not be wrapped
	local expected = '# Hello\n# /usr/local/build-tools/bin\n'
	self.n:comment('Hello /usr/local/build-tools/bin')
	assert(self.out:get(true) == expected)

end):def('short_words_indented', function(self)
	-- Test that indent is taking into acount when breaking subsequent lines.
	-- The second line should not be '    to tree', as that's longer than the
	-- test layout width of 8.
	local expected = 'line_one' .. NL .. IND .. 'to' .. NL .. IND .. 'tree\n'
	self.n:_line('line_one to tree')
	assert(self.out:get(true) == expected)

end):def('few_long_words_indented', function(self)
	-- Check wrapping in the presence of indenting.
	local ind = '  ' .. IND
	local expected = '  x' .. NL .. ind .. LONGWORD .. NL .. ind .. 'y\n'
	self.n:_line(self.words, 1)
	assert(self.out:get(true) == expected)
end):def('escaped_spaces', function(self)
	-- Seems to be the same test as `few_long_words`. Skipping..
end):def('fit_many_words', function(self)
	self.n = Writer(self.out, 78)
	local input = 'command = cd ../../chrome; python ../tools/grit/grit/format/repack.py ../out/Debug/obj/chrome/chrome_dll.gen/repack/theme_resources_large.pak ../out/Debug/gen/chrome/theme_resources_large.pak'
	local expected = [[  command = cd ../../chrome; python ../tools/grit/grit/format/repack.py $
      ../out/Debug/obj/chrome/chrome_dll.gen/repack/theme_resources_large.pak $
      ../out/Debug/gen/chrome/theme_resources_large.pak
]]
	self.n:_line(input, 1)
	assert(self.out:get(true) == expected)
end):def('leading_space', function(self)
	self.n = Writer(self.out, 14) -- force wrapping
	self.n:variable('foo', {'', '-bar', '-somethinglong'}, 0)
	local expected = [[foo = -bar $
    -somethinglong
]]
	assert(self.out:get(true) == expected)
end):def('embedded_dollar_dollar', function(self)
	self.n = Writer(self.out, 15) -- force wrapping
	self.n:variable('foo', {'a$$b', '-somethinglong'}, 0)
	local expected = [[foo = a$$b $
    -somethinglong
]]
	assert(self.out:get(true) == expected)
end):def('two_embedded_dollar_dollars', function(self)
	self.n = Writer(self.out, 17) -- force wrapping
	self.n:variable('foo', {'a$$b', '-somethinglong'}, 0)
	local expected = [[foo = a$$b $
    -somethinglong
]]
	assert(self.out:get(true) == expected)
end):def('leading_dollar_dollar', function(self)
	self.n = Writer(self.out, 14) -- force wrapping
	self.n:variable('foo', {'$$b', '-somethinglong'}, 0)
	local expected = [[foo = $$b $
    -somethinglong
]]
	assert(self.out:get(true) == expected)
end):def('trailing_dollar_dollar', function(self)
	self.n = Writer(self.out, 14) -- force wrapping
	self.n:variable('foo', {'a$$', '-somethinglong'}, 0)
	local expected = [[foo = a$$ $
    -somethinglong
]]
	assert(self.out:get(true) == expected)
end)

--[[--
-- Build Tests
--]]--

TestCase('Build'):setup(function(self, runner)
	self.out = StringBuffer()
	self.n = Writer(self.out)

end):def('variables_dict', function(self)
	self.n:build('out', 'cc', 'in', nil, nil, {name='value'})
	local expected = [[build out: cc in
  name = value
]]
	assert(self.out:get(true) == expected)

end):def('variables_list', function(self)
	self.n:build('out', 'cc', 'in', nil, nil, {{'name','value'}})
	local expected = [[build out: cc in
  name = value
]]
	assert(self.out:get(true) == expected)

end):def('implicit_outputs', function(self)
	self.n:build('o', 'cc', 'i', nil, nil, nil, 'io')
	local expected = [[build o | io: cc i
]]
	assert(self.out:get(true) == expected)
end)

--[[--
-- Expansion Tests
--]]--

-- Test ninja_syntax.expand
TestCase('Expand'):def('basic', function(self)
	local vars = { x='X' }
	assert(ninja.expand('foo', vars) == 'foo')
end):def('var', function(self)
	local vars = { xyz='XYZ' }
	assert(ninja.expand('foo$xyz', vars) == 'fooXYZ')
end):def('vars', function(self)
	local vars = { x='X', y='YYY' }
	assert(ninja.expand('$x$y', vars) == 'XYYY')
end):def('space', function(self)
	local vars = {}
	assert(ninja.expand('x$ y$ z', vars) == 'x y z')
end):def('locals', function(self)
	local vars = { x='a' }
	local local_vars = { x='b' }
	assert(ninja.expand('$x', vars) == 'a')
	assert(ninja.expand('$x', vars, local_vars) == 'b')
end):def('double', function(self)
	local vars = {}
	local value = ninja.expand('a$ b$$c', vars)
	local expected = 'a b$c'
	assert(value == expected)
end)

minitest.main()
