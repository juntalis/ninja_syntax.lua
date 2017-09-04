------------
-- Minimal unit test framework I threw together for this.
-- @module minitest
-- @author Charles Grunwald (Juntalis) <ch@rles.rocks>
----

-- Cache builtin functions.
local getmetatable = getmetatable
local _s, _t, io = string, table, io
local _len = function(o) return #o end
local type, pairs, ipairs = type, pairs, ipairs
local pcall, error, assert = pcall, error, assert
local stdout, insert, rep = io.stdout, _t.insert, _s.rep
local pack =  table.pack or function(...)
	return {...}
end

-- Module table
local minitest = {}

--- Report formatting
minitest.format = {
	indent='  ',
	prefix={
		failure='- ',
		success='+ '
	}
}

local function prefixalign(prefix)
	local prelen = _len(prefix)
	return string.rep(' ', prelen)
end

minitest.format.prefix.failure_align = prefixalign(minitest.format.prefix.failure)
minitest.format.prefix.success_align = prefixalign(minitest.format.prefix.success)

--- TestCase stage.
-- @local
local STAGE = {
	['SETUP']=0,
	['SCENARIO']=1,
	['TEARDOWN']=2,
	[0]='SETUP',
	[1]='SCENARIO',
	[2]='TEARDOWN'
}

-- Used internally for report formatting
local function status_prefix(status)
	local prefixes = minitest.format.prefix
	if status == true then
		return prefixes.success, prefixes.success_align
	else
		return prefixes.failure, prefixes.failure_align
	end
end

-- Used internally for report formatting
local function status_label(status)
	if status == true then
		return 'SUCCESS'
	else
		return 'FAILURE'
	end
end

--- Tests if `obj` is a table.
-- @param obj Object to test
-- @return boolean
local function istable(obj)
	return type(obj) == 'table'
end

local function _len(obj)
	return #obj
end

--- Merge other tables into the first non-destructively
-- @tparam ?table T The table to merge into. (can be nil)
-- @tparam table ... Variable number of other tables to merge in, from left to right.
-- @treturn table Returns the reference to T or a new table if T is nil.
local function defaults(T, ...)
	local result = T or {}
	local others = pack(...)
	for _,other in ipairs(others) do
		for key, value in pairs(other) do
			if not result[key] then
				result[key] = value
			end
		end
	end
	return result
end

--- Tests if `T` contains `search`.
-- @tparam table T table to search
-- @param search Value to search for
-- @return boolean
local function contains(T, search)
	if istable(T) then
		for _, value in pairs(T) do
			if value == search then
				return true
			end
		end
	end
	return false
end

--- Inner iterator for `popping`.
-- @local
local function popping_iter(T)
	local idx, value = next(T)
	if idx == nil then
		idx, value = nil, nil
	else
		table.remove(T, idx)
	end
	return idx, value
end

--- Iterates a table's entries, popping the entries
-- as it goes
-- @tparam table T table to iterate
-- @treturn function iterator() -> index_or_key,value
local function popping(T)
	return popping_iter, (T or {}), nil
end

local function klass_ctor(cls, ...)
	local self = setmetatable({}, cls.prototype)
	self:init(...)
	return self
end

--- Class creator
-- @tparam ?table clsmt Class metatable (or nil)
-- @tparam ?table proto Class instance metatable (or nil)
-- @treturn table Callable class
function minitest.klass(clsmt, proto)
	local cls = {}
	clsmt = defaults(clsmt, { __call = klass_ctor })
	cls.prototype = defaults(proto, {
		__index = cls,
		__class = cls
	})
	return setmetatable(cls, clsmt)
end

local klass = minitest.klass

--- Test if a table is tied to a declared class.
-- @table obj Table to check
-- @table cls Class to check for
-- @treturn boolean
function minitest.isklass(obj, cls)
	local mt = getmetatable(obj)
	return mt.__class == cls
end

--- StringBuffer
-- Provides an API comparable to a standard lua file that's being used
-- for only output.
-- @section StringBuffer
do
	-- StringBuffer implementation
	local StringBuffer = klass()

	--- StringBuffer constructor.
	-- @tparam[opt=''] initial Initial contents of the buffer.
	function StringBuffer:init(initial)
		self.closed = false
		self.buffer = initial or ''
	end

	--- file:write interface to the backing string.
	-- @param ... Data to write
	--
	function StringBuffer:write(...)
		local params = pack(...)
		if self.closed then
			error('Bad StringBuffer:write call: already closed.')
		end

		for _, param in ipairs(params) do
			self.buffer = self.buffer .. param
		end
	end

	--- Provided for API compatibility with file instance
	function StringBuffer:flush()
		if self.closed then
			error('Bad StringBuffer:flush call: already closed.')
		end
	end

	--- Provided for API compatibility with file instance
	function StringBuffer:close()
		if self.closed then
			error('Bad StringBuffer:close call: already closed.')
		end
		self.closed = true
	end

	--- Resets the buffer and returns what was in it.
	-- @bool[opt=false] clear Whether or not to clear the buffer after getting.
	-- @treturn string
	function StringBuffer:get(clear)
		local buffer = self.buffer
		if clear == true then
			self.buffer = ''
		end
		return buffer
	end

	-- Export class as module member.
	minitest.StringBuffer = StringBuffer
end

--- TestRunner
-- Runs the test cases. Singleton for the time being.
-- @section testrunner
do
	local function report_case(case, status)
		return {
			label=case.label,
			scenarios=case:report(),
			status=status or false
		}
	end

	-- TestRunner implementation
	local TestRunner = klass()
	
	TestRunner.options = {
		abort_on_failure=false
	}
	
	function TestRunner:init(options)
		self.cases = {}
		self.options = defaults(options, TestRunner.options)
	end
	
	function TestRunner:register(case)
		insert(self.cases, case)
	end
	
	--- Execute all registered tests.
	function TestRunner:run()
		local report = { status=true, cases={} }
		local should_abort = self.options.abort_on_failure
		for _, case in ipairs(self.cases) do
			local status = case:run(self)
			insert(report.cases, report_case(case, status))
			if not status then
				report.status = status
				if should_abort then
					return report
				end
			end
		end
		return report
	end
	
	minitest.runner = TestRunner()
end

--- TestCase
-- Provides a labeled container for any number of scenarios written for the
-- purpose of testing a common criteria.
-- @section testcase
do
	-- TestCase implementation
	local TestCase = klass()

	local function report_stage(stage, label, status, message)
		local entry ={
			stage=stage,
			label=label or STAGE[stage], 
			status=status or false
		}
		if status then
			entry.message = 'Successfully completed.'
		else
			entry.message = message or 'Skipped'
		end
		return entry
	end
	
	local function report_scenario(scenario)
		return report_stage(
			STAGE.SCENARIO,
			scenario.label,
			scenario.status,
			scenario.error
		)
	end

	--- `TestCase` constructor.
	-- @string label Test case label  
	function TestCase:init(label)
		self.label = label
		self._scenarios = {}
		minitest.runner:register(self)
	end

	--- Bind or remove this `TestCase`'s setup handler.
	-- @function[opt] handler Instance's setup handler. 
	-- @treturn TestCase self
	function TestCase:setup(handler)
		self._setup = handler
		return self
	end

	--- Bind or remove this `TestCase`'s teardown handler.
	-- @function[opt] handler Instance's teardown handler. 
	-- @treturn TestCase self
	function TestCase:teardown(handler)
		self._teardown = handler
		return self
	end

	--- Attach a new test scenario to this `TestCase`.
	-- @string label Scenario's label
	-- @function handler Scenario handler
	-- @treturn TestCase self
	function TestCase:scenario(label, handler)
		-- Maintain order of definition
		insert(self._scenarios, { label=label, handler=handler })
		return self
	end
	
	--- Pass-through to TestCase.scenario
	-- @string label Scenario's label
	-- @function handler Scenario handler
	-- @treturn TestCase self
	function TestCase:def(label, handler)
		return self:scenario(label, handler)
	end
	
	--- Should probably be merged into `TestCase:run`.
	function TestCase:report()
		local report = {}
		insert(report, report_stage(
			STAGE.SETUP,
			nil,
			self._setup_status, 
			self._setup_error
		))
		
		if self._setup_status then
			for _, scenario in pairs(self._scenarios) do
				insert(report, report_scenario(scenario))
			end
			insert(report, report_stage(
				STAGE.TEARDOWN,
				nil,
				self._setup_status,
				self._setup_error
			))
		end
		return report
	end
	
	--- Reset an executed test case to its original state.
	function TestCase:reset()
		self._setup_status, self._setup_error = nil, nil
		for _, scenario in ipairs(self._scenarios) do
			scenario.status, scenario.error = nil, nil
		end
		self._teardown_status, self._teardown_error = nil, nil
	end
	
	--- Run this test case.
	-- @todo Too much state shit in this.
	function TestCase:run(runner)
		self:reset()
		local status, result = true, nil

		-- Run any registered setup handler.
		if self._setup ~= nil then
			status, result = pcall(self._setup, self, runner)
			self._setup_status = status
		else
			self._setup_status = true
		end

		-- Run through all our registered scenarios
		if self._setup_status then
			for _, scenario in pairs(self._scenarios) do
				scenario.status, scenario.error = pcall(scenario.handler, self)
				if not scenario.status then
					status = scenario.status
				end
			end

			-- Run any registered teardown handler.
			if self._teardown ~= nil then
				self._teardown_status, result = pcall(self._teardown, self, 
				                                      runner)
				if not self._teardown_status then
					status = self._teardown_status
					self._teardown_error = result
				end
			else
				self._teardown_status = true
			end
		else
			self._setup_error = result
		end

		return status
	end
	
	minitest.TestCase = TestCase
end

local function write(stream, ...)
	local params = pack(...)
	local paramc = _len(params)
	if paramc == 1 then
		stream:write(params[1])
	elseif paramc > 1 then
		stream:write(string.format(...))
	end
end

local function writeline(stream, ...)
	write(stream, ...)
	write(stream, '\n')
end

local function indentline(stream, level, ...)
	write(stream, rep(minitest.format.indent, level))
	write(stream, ...)
	write(stream, '\n')
end

function minitest.dump_report(stream, report)
	-- Write header with overall status
	writeline(stream, 'Overall Status: %s', status_label(report.status))
	
	-- Iterate through test cases, reporting on them and their scenarios.
	for _c, case in ipairs(report.cases) do
		local case_prefix = status_prefix(case.status)
		indentline(
			stream, 1, '%sCase: %s [Status=%s]',
			case_prefix, case.label, status_label(case.status)
		)
		for _s, scenario in ipairs(case.scenarios) do
			local scenario_prefix, scenario_align = status_prefix(scenario.status)
			indentline(
				stream, 2, '%sScenario: %s [Status=%s]',
				scenario_prefix, scenario.label, status_label(scenario.status) 
			)
			if not scenario.status then
				indentline(
					stream, 2, '%sDetails: %s',
					scenario_align, scenario.message
				)
			end
		end
	end
end

function minitest.dumps_report(report)
	local stream = minitest.StringBuffer()
	minitest.dump_report(stream, report)
	return stream:get()
end


function minitest.main()
	minitest.dump_report(stdout, minitest.runner:run())
end

return minitest
