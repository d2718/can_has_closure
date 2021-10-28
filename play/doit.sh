#!/usr/bin/bash

curl \
    --data-urlencode "compilation_level=SIMPLE_OPTIMIZATIONS" \
    --data-urlencode "output_format=json" \
    --data-urlencode "output_info=compiled_code" \
    --data-urlencode "output_info=statistics" \
    --data-urlencode "output_info=warnings" \
    --data-urlencode "output_info=errors" \
    --data-urlencode 'js_code@body.js' \
    --header "Content-type: application/x-www-form-urlencoded" \
    --trace-ascii dump.txt \
    --output response.json \
    -X POST https://closure-compiler.appspot.com/compile

echo $?
