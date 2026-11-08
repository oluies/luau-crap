--!strict
-- Runs every tests/*.spec.luau. Usage, from the project root: lune run tests/run

local fs = require("@lune/fs")
local process = require("@lune/process")

local Check = require("./Check")

local specs = {}
for _, name in ipairs(fs.readDir("tests")) do
	if string.match(name, "%.spec%.luau$") then
		table.insert(specs, name)
	end
end
table.sort(specs)

for _, name in ipairs(specs) do
	(require :: any)(`./{string.gsub(name, "%.luau$", "")}`)
end

process.exit(Check.report())
