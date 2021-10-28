#!/usr/bin/env lua

--[[
chc.lua

the Lua can_has_closure implementation

a thin wrapper around Google's Closure JS Minifier API
--]]

local DEBUG = false

require 'localizer'
local json = require 'dkjson'
-- The functionality used from both of these modules should probably be
-- copy-pasted into this script, if it's going to be distributed.
-- Then the requirement of 'localizer' could be removed, too.
local misc = require 'sysmisc'
local args = require 'dargs'

local CFG = {
    curl = "/usr/bin/curl",
    rm   = "/bin/rm",
    temp = "/dev/shm",
}

local FORM_DATA = {
    "compilation_level=SIMPLE_OPTIMIZATIONS",
    "output_info=compiled_code",
    "output_info=errors",
    "output_info=warnings",
    "output_info=statistics",
    "output_format=json",
}
local TAIL_ARGS = {
    "--header", "Content-type: application/x-www-form-urlencoded",
    --"--trace-ascii", "dump.txt",
    "-s", "https://closure-compiler.appspot.com/compile",
}

local TEMP_FNAME = string.format("%s/chc-%d.js", CFG.temp, misc.getpid())

local function dbg(...)
    if DEBUG then
        misc.errpt(unpack(arg))
    end
end

-- Remove the temporary file `TEMP_FNAME if it exists.
local function cleanup()
    local f = io.open(TEMP_FNAME)
    if f then
        f:close()
        os.execute(misc.shell_escape({CFG.rm, TEMP_FNAME}))
    end
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
        misc.die("Unable to open temp file %q for writing: %s", TEMP_FNAME, err)
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
if code ~= 0 then
    cleanup()
    misc.die("curl reports error %d", code)
end

-- Load the curl output.
local curl_output = nil
do
    local f, err = io.open(TEMP_FNAME, "r")
    if not f then
        misc.die("Unable to open temp file with curl output %q: %s", temp_fname, err)
    end
    curl_output = f:read("*all")
    f:close()
end
dbg("curl output:\n%s", curl_output)

-- Decode the curl output.
local r, err = json.decode(curl_output)
if not r then
    cleanup()
    misc.die("Unable to decode returned data: %s", err)
end

-- Stop and show errors, if present.
if r.errors then
    for _, e in ipairs(r.errors) do
        misc.errpt("ERROR line %d, (pos %d): %s", e.lineno, e.charno, e.error)
        misc.errpt("%d %s", e.lineno, e.line)
    end
    cleanup()
    misc.die("No output generated.")
end

-- I don't know the structure of warnings yet, so I don't know how to
-- display them.
if r.warnings then
    misc.errpt("%d warnings (undisplayed)", #r.warnings)
end

-- If output should be written to a file, do it, otherwise dump to stdout.
if output_fname then
    local f, err = io.open(output_fname, "w")
    if not f then
        cleanup()
        misc.die("Unable to open %q for writing: %s", output_fname, err)
    end
    f:write(r["compiledCode"])
    f:flush()
    f:close()
else
    io.stdout:write(r["compiledCode"])
end

-- Ensure the temp file is deleted.
cleanup()