# can_has_closure
A thin wrapper around Google's Closure JS Minifier API

Currently there is a Lua implementation; there will be at least a Rust
implementation eventually.

### Lua Implementation

` $ lua chc.lua [ -o, --output OUTPUT FILENAME ] [ INPUT_FILENAME ]`

Huffs up a Javascript source file, pumps it through Google's Closure JS
Minifier, and spits it back out. If there are errors, they will be reported
but no other output will be produced.

If no `INPUT_FILENAME` is specified, will read from the standard input.

If `-o` or `--output` is specified, will use that as the output file;
otherwise will write to standard output if no input file is specified,
or, for specified input file of `source_file.js`, will write to the file
`source_file.min.js`.

Require's David Kolf's excellent
[dkjson](http://dkolf.de/src/dkjson-lua.fsl/home) module
([also on GitHub](https://github.com/LuaDist/dkjson)). Works with Lua 5.1,
but probably also with 5.2 and 5.3.