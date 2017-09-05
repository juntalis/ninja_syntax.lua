# Ninja Build Generator

[ninja_syntax.py](https://github.com/ninja-build/ninja/blob/master/misc/ninja_syntax.py) reimplemented in Lua.

Rewording the description from the original script: 

> it's just a helpful utility for build-file-generation systems that already
> use Lua.

## Tests / Documentation

Tests can be run with:

```bash
lua ninja_syntax_test.lua
```

Documentation can be generated with [LDoc](https://github.com/stevedonovan/LDoc).

```bash
ldoc .
```
