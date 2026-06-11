 ------------
-- TODO: Description
-- @alias util
-- @module ninja_util
-- @author Charles Grunwald (Juntalis) <ch@rles.rocks>
----
local io, crc32 = require('io'), require('crc32')

local _len = function(o) return #o end
local tcount, strlen = table.maxn or _len, string.len or _len
local tinsert, tconcat, tsort = table.insert, table.concat, table.sort
local sprintf, strfind, substr = string.format, string.find, string.sub
local _unlink, _getenv, _open, _lines = os.remove, os.getenv, io.open, io.lines
local tunpack, tpack = _G.unpack or table.unpack, table.pack or function(...)
	return {...}
end

local util = {}

-- Extract the directory separator from the package module.
if _G.package then
	if _G.package.config then
		util.SEP = substr(_G.package.config, 1, 1)
		util.PATHSEP = substr(_G.package.config, 3, 3)
	else
		local idx = strfind(_G.package.cpath, '[;:][^\\]')
		util.SEP = substr(_G.package.cpath, strfind(package.cpath, '[\\/]'))
		util.PATHSEP = substr(_G.package.cpath, idx, idx)
	end
elseif _G._SEP and _G._PATHSEP then
	util.SEP = _G._SEP
	util.PATHSEP = _G._PATHSEP
else
	error('Failed to determine system/path seperators.')
end

if _G._PLATFORM then
	util.OS = _G._PLATFORM
elseif util.SEP == '\\' then
	util.OS = 'windows'
else
	util.OS = 'posix'
end

if util.OS == 'windows' then
	util.NL = '\r\n'
	util.SHELL = _getenv('ComSpec') or 'cmd.exe'
	util.SHELLEXEC = '%s /C "%s"'
else
	util.NL = '\n'
	util.SHELL = _getenv('SHELL') or _getenv('SH') or '/bin/sh'
	util.SHELLEXEC = '%s -f "%s"'
end

--- Read temporary file and then remove it.
-- @local
local function readtmp(filepath)
	local content = util.readfile(filepath)
	_unlink(filepath)
	return content
end

--- Read and parse environment dump, then remove it.
-- @local
local function readenv(filepath, remove)
	local env = {}
	remove = remove or false
	for line in _lines(filepath) do
		local key, value = select(3, strfind(line, '^([^=]-)=(.+)$'))
		env[key] = value
	end
	if remove then
		_unlink(filepath)
	end
	return env
end

--- Builtin Utilities
-- @section builtins

--- Given a filepath, open the file, read the contents, close it, and return
-- the contents.
-- @tparam string filepath Filepath to open
-- @treturn string|nil Contents or nil if the file cannot be opened.
function util.readfile(filepath)
	local result
	local fp = _open(filepath)
	if fp ~= nil then
		result = fp:read('*a')
		assert(fp:close())
	end
	return result
end

--- Inner iterator for `util.values`.
-- @local
local function values_iter(_S)
	local value
	_S.i, value = next(_S.t, _S.i)
	if _S.i == nil then
		value, _S.t, _S = nil, nil, nil
	end
	return value
end

--- Iterator for a table's values
-- @tparam table T table to iterate
-- @treturn function iterator() -> value
function util.values(T)
	return values_iter, {t=T}, nil
end

--- Check if a table contains a key/index.
-- @tparam table T table to search
-- @tparam string|number key_or_index key or index to search for
-- @treturn bool Whether or not the key/index was found.
function util.hasentry(T, key_or_index)
	for entry in pairs(T) do
		if entry == key_or_index then
			return true
		end
	end
	return false
end

--- Check if a table contains a value
-- @tparam table T table to search
-- @param value the value to search for
-- @treturn bool Whether or not the value was found.
function util.hasval(T, value)
	--if type(T) == 'table' then return false end
	for check in util.values(T) do
		if check == value then
			return true
		end
	end
	return false
end

--- Copies a table, filtering out all duplicate values.
-- Note: Does not preserve or care about table keys. Unless the nosort param has
-- been specified, the resulting table will be sorted after copying.
-- @tparam table T table to filter
-- @bool[opt=false] nosort optional parameter to suppress the standard sorting
-- @treturn table New sorted (maybe) table with the duplicates removed
function util.uniq(T, nosort)
	local uniq = {}
	for value in util.values(T) do
		if not util.hasval(uniq, value) then
			tinsert(uniq, value)
		end
	end
	if nosort ~= true then
		tsort(uniq)
	end
	return uniq
end

--- Reverse search a string for a raw substring.
-- @string text text to search
-- @string search substring to search for
-- @int[opt=1] start the search's lower bound (index to stop the search at)
-- @int[opt] finish the search's upper bound (index to start the search at)
-- @treturn int The starting index for the substring or 0 if not found.
function util.rfind(text, search, start, finish)
	local searchlen = strlen(search)
	if not start or start == 0 then
		start = 1
	end
	finish = (finish or strlen(text)) - searchlen
	for idx = finish, start, -1 do
		local part = substr(text, idx, idx + searchlen - 1)
		if part == search then
			return idx
		end
	end
	return 0
end

--- Filepath/Filesystem Manipulation
-- @section filesystem

--- Get the user/system temp folder.
-- @treturn string temp folder
function util.tmpdir()
	return _getenv('TEMP') or _getenv('TMP') or '/tmp'
end

local tmpname_count = 0

--- `os.tmpname` with more control of the generated filename.
-- @tparam[opt=''] string ext File extension. (with or without preceding '.' char)
-- @tparam[opt='t'] string prefix Prefix to add to the generated filename.
-- @tparam[opt] string suffix Suffix to add to the generated filename.
-- @treturn string Randomly generated filename (for tmpname usage)
function util.tmpname(ext, prefix, suffix)
	-- prefix defaults to 't'
	prefix = prefix or 't'
	-- if suffix is no specified, we'll use an auto-incrementing number
	if not suffix then
		suffix = tostring(tmpname_count)
		tmpname_count = tmpname_count + 1
	end

	-- If ext is nil, set it to an empty string.
	if ext == nil then
		ext = ''
	elseif strlen(ext) > 0 and substr(ext, 1, 1) ~= '.' then
		-- Add the missing '.' to the start of ext.
		ext = '.' .. ext
	end

	return prefix .. os.tmpname():gsub('[%.\\/%s]','-') .. suffix .. ext
end

--- Combines `ninja_util.tmpdir` and `ninja_util.tmpname`.
-- @tparam[opt=''] string ext File extension. (with or without preceding '.' char)
-- @tparam[opt='t'] string prefix Prefix to add to the generated filename.
-- @tparam[opt] string suffix Suffix to add to the generated filename.
-- @treturn string Randomly generated temporary filepath
function util.tmppath(ext, prefix, suffix)
	return util.join(util.tmpdir(), util.tmpname(ext, prefix, suffix))
end

--- Generate a temporary shell script and return its filepath.
-- @tparam {string,...} lines Lines to add to the shell script
-- @treturn string Absolute filepath of the newly generated shell script.
function util.tmpsh(lines)
	if type(lines) == 'table' then
		lines = tconcat(lines, util.NL)
	end
	local batfile = util.tmppath('.cmd', 'sh')
	local fbat = _open(batfile, 'w')
	fbat:write('@echo off\n')
	fbat:write(lines)
	fbat:write(util.NL)
	fbat:flush()
	fbat:close()
	return batfile
end

--- Join two or more filepath segments by the directory seperator character.
-- @param ... Filepath segments
-- @treturn string Joined filepath
function util.join(...)
	local parts = {...}
	return tconcat(parts, util.SEP)
end

--- Split a filepath into the filename and parent dirname.
-- @tparam string filepath Filepath to split
-- @treturn string parent folder path
-- @treturn string filename
function util.splitpath(filepath)
	local idx = util.rfind(filepath, util.SEP)
	if idx == 0 then
		return '.', filepath
	else
		return substr(filepath, 1, idx - 1), substr(filepath, idx + 1)
	end
end

--- Given a filepath, return the parent dirname.
-- @tparam string filepath Filepath to operate on
-- @treturn string parent folder path
function util.dirname(filepath)
	local dirname = util.splitpath(filepath)
	return dirname
end

--- Given a filepath, return the filename without the parent folder path.
-- @tparam string filepath Filepath to operate on
-- @treturn string Filename without leading folder path.
function util.basename(filepath)
	return select(2, util.splitpath(filepath))
end

--- Tests if a path exists. (as a file or folder)
-- @tparam string path The file/folder path to test.
-- @treturn boolean `true` if it exists - `false` otherwise
function util.exists(path)
	local exists = false
	local ftest,err = _open(path, 'r')
	if ftest ~= nil then
		exists = true
		ftest:close()
	elseif not strfind(err, 'No such file or directory', 1, true) then
		exists = true
	end
	return exists
end

--- Test if a filepath can be opened. Uses the built-in `io.open`.
-- @tparam ?string filepath the filepath to check
-- @string[opt='rb'] mode optional open mode parameter
-- @treturn bool `true` if we were able to open the filepath - `false` otherwise
function util.canopen(filepath, mode)
	local ftest = _open(filepath, mode or 'rb')
	if ftest then
		ftest:close()
	end
	return filepath and ftest ~= nil
end

--- Process/Shell Command Execution
-- @section execution

--- Executes a shell script by path.
-- @internal
local function execshcmd(filepath)
	return sprintf(util.SHELLEXEC, util.SHELL, filepath)
end

--- Simple execution of a bunch of shell commands
-- Returns the filehandle and a cleanup function, or nil and the error message.
-- @tparam string|table lines - shell commands
-- @return[1] file handle returned by popen
-- @return[1] close() function that handles additional cleanup
-- @return[2] nil
-- @return[2] error message
function util.execsh(lines)
	local tmpsh = util.tmpsh(lines)
	local cmdline = execshcmd(tmpsh)
	print(cmdline)
	local psh, err_or_close = io.popen(cmdline, 'r')
	if psh ~= nil then
		-- Create a suitable cleanup function that closes the file handle
		-- and removes the temporary shell script
		err_or_close = function()
			psh:close()
			_unlink(tmpsh)
		end
	else
		-- go ahead and cleanup the temporary shell script
		_unlink(tmpsh)
	end
	return psh, err_or_close
end

--- Simple execution of a bunch of shell commands - return output or nil
-- @tparam {string,...} lines Lines of shell commands.
-- @treturn string|nil Output on success. `nil` on failure.
function util.execshs(lines)
	local output
	local tmpsh = util.tmpsh(lines)
	local psh = io.popen(execshcmd(tmpsh), 'r')
	if psh ~= nil then
		output = psh:read('*a')
		psh:close()
	end
	_unlink(tmpsh)
	return output
end

local function execshls_iter(_S)
	local line = _S.psh:read('*l')
	if line == nil then
		_S.psh:close()
		_unlink(_S.path)
		_S.psh, _S.path, _S = nil, nil, nil
	end
	return line
end

--- Simple execution of a bunch of shell commands - iterate over output lines
function util.execshls(lines)
	local tmpsh = util.tmpsh(lines)
	local psh = io.popen(execshcmd(tmpsh), 'r')
	local state = { psh=psh, path=tmpsh }
	return execshls_iter, state, nil
end

--- Simple execution of a bunch of shell commands - returns the exit code
function util.execshr(lines)
	local tmpsh = util.tmpsh(lines..NL..'if errorlevel 1 exit /B %ERRORLEVEL%')
	return os.execute(execshcmd(tmpsh))
end

--- Extended version of execsh
function util.execshenv(batfile)
	local basename = util.tmppath(nil, 'execshenv')
	local outfile, errfile, envfile =
	      basename .. '.stdout',
	      basename .. '.stderr',
	      basename .. '.env'
	local tmpsh = util.tmpsh(sprintf([[
(call "%s">"%s" 2>"%s") & (set>"%s")
if errorlevel 1 goto exit /B %%ERRORLEVEL%%
goto :EOF
]], batfile, outfile, errfile, envfile))

	-- Build our result object
	local result = {}
	result.retcode = os.execute(execshcmd(tmpsh))
	result.stdout = readtmp(outfile)
	result.stderr = readtmp(errfile)
	result.env = readenv(envfile, true)
	return result -- All done
end

function util.lsdir(matchspec)
	local lsdircmd = sprintf('for %%%%F in ("%s") do @echo %%%%F',
		matchspec)
	return util.execshls(lsdircmd)
end

function util.rmdir(dirpath)
	local rmdircmd = sprintf('rmdir /S /Q "%s"', dirpath)
	return util.execshr(rmdircmd)
end

function util.rm(filespec)
	local delcmd = sprintf('if exist "%s" del /F /Q "%s"', filespec,
		filespec)
	return util.execshr(delcmd)
end

--[[--
Microsoft (R) 32-bit C/C++ Optimizing Compiler Version 16.00.40219.01 for 80x86
Microsoft (R) C/C++ Optimizing Compiler Version 16.00.40219.01 for x64
Microsoft (R) C/C++ Optimizing Compiler Version 18.00.40629 for x86
Microsoft (R) C/C++ Optimizing Compiler Version 18.00.40629 for x64
]]
function util.ccverinfo(cc)
	cc = cc or 'cl.exe'
	local psh, closefn = util.execsh(cc .. ' 2>&1')
	assert(psh, 'error = ' .. tostring(closefn))

	-- Search for the compiler's logo
	local line = psh:read('*l')
	while line and line:sub(1, 9) ~= 'Microsoft' do
		line = psh:read('*l')
	end

	-- Cleanup file handle and temporary files
	closefn()

	-- Verify line has a non-nil value
	if not line then
		return {
			major = 0,
			arch = 'unknown',
			full = 'Unknown',
		}
	end

	-- Begin parsing and building cc version info
	local verinfo = {}

	-- simplify parsing by lowercasing line
	line = string.lower(line)

	-- Locate version numbers
	verinfo.full = select(3, strfind(line, ' version ([^%s]+) ', 10))
	if verinfo.full then
		local major = select(3, strfind(verinfo.full, '(%d+)%.'))
		verinfo.major = tonumber(major or '0')
	else
		verinfo.full = 'Unknown'
		verinfo.major = 0
	end

	-- Parse the compiler's target architecture
	local idx = util.rfind(line, 'x')
	if idx == 0 then
		verinfo.arch = 'unknown'
	else
		verinfo.arch = line:sub(idx)
	end

	return verinfo
end

function util.buildhash(toolset, verinfo, config, modules, exts)
	-- If verinfo is a string, shift all params left
	if type(verinfo) == 'string' then
		exts = modules
		modules = config
		config = verinfo
		verinfo = nil
	end

	verinfo = verinfo or util.ccverinfo()
	local parts = {
		toolset,
		'P=' .. verinfo.arch,
		-- 'V=' .. verinfo.full,
		'V=' .. tostring(verinfo.major),
		'C=' .. (config or 'ndebug'),
	}

	if modules then
		tinsert(parts, 'M=' .. tconcat(util.uniq(modules), ','))
	end

	if exts then
		tinsert(parts, 'E=' .. tconcat(util.uniq(exts), ','))
	end

	return sprintf('%08x', crc32.hash(toolset .. ';' .. tconcat(parts, ';')))
end

util.crc32 = crc32.hash

return util
