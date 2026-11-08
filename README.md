# luau-crap

CRAP scores for [Luau](https://luau.org): cyclomatic complexity combined with how little of each
function the tests reach. It runs on [Lune](https://lune-org.github.io/docs) and needs nothing
else (`mise install` picks up the pinned version).

CRAP = CC² × (1 − coverage)³ + CC, per function. Fully tested, a function scores its complexity;
untested, it scores about the square of it. The usual gate is under 10, and a function with
complexity 10 or more can only pass by being split.

## Use

From the root of the project to score:

```bash
/path/to/luau-crap/bin/luau-crap                                # src, tests from lune run tests/run
/path/to/luau-crap/bin/luau-crap src/shared --exclude Vendor    # just these, without vendored code
/path/to/luau-crap/bin/luau-crap --test 'lune run spec/all'     # another test command
/path/to/luau-crap/bin/luau-crap --threshold 10                 # exit 2 if anything scores 10 or more
/path/to/luau-crap/bin/luau-crap --no-coverage                  # complexity only, as if 0% covered
```

Or symlink `bin/luau-crap` onto your PATH. Exit codes: 0 fine, 1 usage or analysis error (finding
no source files is an error, not a pass), 2 over the threshold, 3 the tests failed.

## How it works

- **Complexity** is 1 per function, plus 1 per `if`, `elseif`, `while`, `for`, `repeat`, `and`
  and `or`, if-expressions included. Nested functions are scored on their own, and each file's
  top-level code is scored as `<chunk>`. Test files (`tests/`, `test/`, `*.spec.luau`,
  `*.test.luau`) are skipped.
- **Coverage** is the share of a function's blocks that ran: its body and every `then`, `else`,
  `do` and `repeat` block. The project is copied to a temporary directory, the scored files get
  a counter at the start of each block, and the tests run there. The project itself isn't changed.
- A counter prints a marker line to stdout the first time its block runs, so any test runner
  works, including one that ends with `process.exit`.

## Limits

- Code that needs a Roblox instance can't run under Lune, so server and client scripts show as
  never loaded and score as 0% covered. Score what your tests can load, such as `src/shared`.
- Coverage counts blocks, not lines or branch outcomes: `if x then ... end` with `x` always true
  is fully covered, and code after an early `return` in the same block counts as reached.
- The test command must let the scored code call `print`, and must leave its stdout captured
  rather than discarding it.
- The parser reads tokens, not a full syntax tree. Code it can't balance is reported as an error
  rather than scored wrongly; if-expressions after `;` inside a table constructor are the known
  case that trips it.

## Develop

```bash
lune run tests/run
lune run src/main.luau --threshold 10    # the tool's own gate
```
