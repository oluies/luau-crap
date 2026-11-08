local process = require("@lune/process")
local Covered = require("../src/covered")

assert(Covered.sign(5) == 1)
assert(Covered.sign(-5) == -1)
assert(Covered.sign(0) == 0)
process.exit(0)
