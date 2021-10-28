#!/usr/bin/env lua

--[[
chc.lua

the Lua can_has_closure implementation

a thin wrapper around Google's Closure JS Minifier API

Dan Hill
2021-10-28
--]]

local DEBUG = false

-- David Kolf's excellent JSON parser, found at one of the following:
-- * http://dkolf.de/src/dkjson-lua.fsl/home
-- * https://github.com/LuaDist/dkjson
local json = require 'dkjson'

local CFG = {
    curl = "/usr/bin/curl",
    rm   = "/bin/rm",
    temp = "/dev/shm",
}

-- Arguments to be added to the curl command with --data-urlencode.
local FORM_DATA = {
    "compilation_level=SIMPLE_OPTIMIZATIONS",
    "output_info=compiled_code",
    "output_info=errors",
    "output_info=warnings",
    "output_info=statistics",
    "output_format=json",
}

-- Other arguments to curl.
local TAIL_ARGS = {
    "--header", "Content-type: application/x-www-form-urlencoded",
    "-s", "https://closure-compiler.appspot.com/compile",
}

-- This is functionality copy-pasted in from my "sysmisc" module. This is
-- undoubtedly more convenient than distributing it separately.
local misc = {
    -- Get the process ID of the current process.
    ["getpid"] = function()
        local f, err = io.open('/proc/self/stat', 'r')
        if not f then return nil, err end
        d = f:read('*number')
        f:close()
        return d, nil
    end,
    
    -- Escape the array of provided arguments and concatenate them into a
    -- single line one could pass to bash.
    ["shell_escape"] = function(args)
        local ret = {}
        for _,a in pairs(args) do
            s = tostring(a)
            if (s == '<') or (s == '>') or (s == '&') then
                -- don't escape this
            elseif s:match("[^A-Za-z0-9_/:=-]") then
                s = "'"..s:gsub("'", "'\\''").."'"
            end
            table.insert(ret,s)
        end
        return table.concat(ret, " ")
    end,
    
    -- Print, printf()-style, to stderr. Ensures output is newline-terminated.
    ["errpt"] = function(format_str, ...)
        local msg = string.format(format_str, unpack(arg))
        io.stderr:write(msg)
        local n = #msg
        if msg:sub(n, n) ~= '\n' then io.stderr:write('\n') end
    end,
}

-- This argument parser is copy-pasted in from my "dargs" module. Having it
-- here is more convenient than distributing it separately.
local function dargs()
    local FLAG_PATTERN = '^%-%-?(.+)$'
    local FLAG, VALUE = 0, 1
    local a = {}
    for _, x in ipairs(arg) do
        local m = x:match(FLAG_PATTERN)
        if m then table.insert(a, {FLAG, m}) else table.insert(a, {VALUE, x}) end
    end

    local r, n = {}, 1
    while true do
        if a[n] == nil then break end
        if a[n][1] == VALUE then
            table.insert(r, a[n][2])
            n = n + 1
        else
            local k = a[n][2]
            n = n + 1
            if a[n] then
                if a[n][1] == VALUE then
                    r[k] = a[n][2]
                    n = n + 1
                else r[k] = ""
                end
            else r[k] = ""
            end
        end
    end
    return r
end

-- The temporary filename to use for input, output, or both if necessary.
local TEMP_FNAME = string.format("%s/chc-%d.js", CFG.temp, misc.getpid())

-- Emit a debut message if DEBUG == true.
local function dbg(...)
    if DEBUG then misc.errpt(unpack(arg)) end
end

-- Remove the temporary file `TEMP_FNAME if it exists.
local function cleanup()
    local f = io.open(TEMP_FNAME)
    if f then
        f:close()
        os.execute(misc.shell_escape({CFG.rm, TEMP_FNAME}))
    end
end

-- Ensure the temp file is cleaned up, scream, and die.
local function die(format_str, ...)
    cleanup()
    misc.errpt(format_str, unpack(arg))
    os.exit(1)
end

-- If the filename has an extension, insert an extra ".min" before the
-- extension; otherwise just append a ".min".
local function fname_mangle(fname)
    local rest, ext = fname:match("^(.-)%.([^.]+)$")
    if rest and ext then
        return string.format("%s.min.%s", rest, ext)
    else
        if fname:sub(#fname, #fname) == "." then
            return fname .. "min"
        else
            return fname .. ".min"
        end
    end
end

dbg("TEMP_FNAME: %q", TEMP_FNAME)

local args = dargs()

-- Input filename should be the first positional arg. If there's no first
-- positional arg, the program will read from stdin.
local input_fname  = args[1]

-- If the `-o` or `--output` option is set, that'll be the output filename.
-- Otherwise, if there's no input filename (reading from stdin), then the
-- output filename will be nil (writing to stdout), otherwise, the output
-- filename will be the `fname_mangle()`ed version of the input filename.
local output_fname = args['o'] or args['output']
if not output_fname then
    if input_fname then
        output_fname = fname_mangle(input_fname)
    end
end

dbg("input_fname: %q", input_fname or nil)
dbg("output_fname: %q", output_fname or nil)

-- If there's no input filename, read input from stdin, write that to the
-- temporary file, and set that temporary file to be in the input file.
if not input_fname then
    local js_text = io.stdin:read("*all")
    local f, err = io.open(TEMP_FNAME, "w")
    if not f then
        die("Unable to open temp file %q for writing: %s", TEMP_FNAME, err)
    end
    f:write(js_text)
    f:flush()
    f:close()
    input_fname = TEMP_FNAME
end

dbg("input_fname: %q", input_fname or nil)

-- Build a command line for calling curl.
local cmd = { CFG.curl }
for _, arg in ipairs(FORM_DATA) do
    table.insert(cmd,"--data-urlencode")
    table.insert(cmd, arg)
end
table.insert(cmd, "--data-urlencode")
table.insert(cmd, "js_code@" .. input_fname)

table.insert(cmd, "--output")
table.insert(cmd, TEMP_FNAME)

for _, arg in ipairs(TAIL_ARGS) do
    table.insert(cmd, arg)
end

dbg("command: %s", misc.shell_escape(cmd))

-- Call curl; if it returns an error code, say so, clean up, and die.
local code = os.execute(misc.shell_escape(cmd))
if code ~= 0 then die("curl reports error %d", code) end

-- Load the curl output.
local curl_output = nil
do
    local f, err = io.open(TEMP_FNAME, "r")
    if not f then
        die("Unable to open temp file with curl output %q: %s", temp_fname, err)
    end
    curl_output = f:read("*all")
    f:close()
end
dbg("curl output:\n%s", curl_output)

-- Decode the curl output.
local r, err = json.decode(curl_output)
if not r then die("Unable to decode returned data: %s", err) end

-- Stop and show errors, if present.
if r.errors then
    for _, e in ipairs(r.errors) do
        misc.errpt("ERROR line %d, (pos %d): %s", e.lineno, e.charno, e.error)
        misc.errpt("%d %s", e.lineno, e.line)
    end
    die("No output generated.")
end

-- I don't know the structure of warnings yet, so I don't know how to
-- display them.
if r.warnings then
    misc.errpt("%d warnings (undisplayed)", #r.warnings)
end

-- If output should be written to a file, do it, otherwise dump to stdout.
if output_fname then
    local f, err = io.open(output_fname, "w")
    if not f then die("Unable to open %q for writing: %s", output_fname, err) end
    
    f:write(r["compiledCode"])
    f:flush()
    f:close()
else
    io.stdout:write(r["compiledCode"])
end

-- Ensure the temp file is deleted.
cleanup()