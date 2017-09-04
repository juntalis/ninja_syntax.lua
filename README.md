# Ninja Build Generator

[ninja_syntax.py](https://github.com/ninja-build/ninja/blob/master/misc/ninja_syntax.py) reimplemented in LUA.

Rewording the description from the original script: 

> it's just a helpful utility for build-file-generation systems that already
> use Lua.

#### TODO

* Finish translating (and verifying) the unit tests I was too lazy to implement from [ninja_syntax_test.py](https://github.com/ninja-build/ninja/blob/master/misc/ninja_syntax_test.py):
  * `TestLineWordWrap.test_leading_space`
  * `TestLineWordWrap.test_embedded_dollar_dollar`
  * `TestLineWordWrap.test_two_embedded_dollar_dollars`
  * `TestLineWordWrap.test_leading_dollar_dollar`
  * `TestLineWordWrap.test_trailing_dollar_dollar`
  * `TestBuild.test_variables_list`
  * `TestBuild.test_implicit_outputs`

## Tests / Documentation

Tests can be run with:

```bash
lua ninja_syntax_test.lua
```

Documentation can be generated with [LDoc](https://github.com/stevedonovan/LDoc).

```bash
ldoc .
```
