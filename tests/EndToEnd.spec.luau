--!strict
local T = require("./Check")
local fs = require("@lune/fs")
local process = require("@lune/process")

local ROOT = process.cwd
local CLI = `{ROOT}src/main.luau`
local SAMPLE = `{ROOT}tests/fixtures/sample`

local function crap(...: string)
	local result = process.exec("lune", { "run", CLI, ... }, { cwd = SAMPLE })
	-- When luau-crap measures itself, the coverage of this child run has to reach the parent
	for line in string.gmatch(result.stdout, "[^\n]+") do
		if string.find(line, "@@luau-crap@@", 1, true) then
			print(line)
		end
	end
	return result
end

local function has(text: string, wanted: string): boolean
	return string.find(text, wanted, 1, true) ~= nil
end

T.it("measures coverage by running the tests", function()
	local result = crap()
	T.equal(result.code, 0, result.stdout)
	T.equal(has(result.stdout, "Covered.sign"), true)
	local covered = string.match(result.stdout, "(%d+)%s+Covered%.sign")
	T.equal(covered, "100", "every block of sign ran")
	T.equal(string.match(result.stdout, "(%d+)%s+Covered%.neverCalled"), "0")
	T.equal(has(result.stdout, "src/lib/unloaded.luau"), true, "names the file no test loaded")
end)
T.it("leaves the project alone", function()
	local before = fs.readFile(`{SAMPLE}/src/covered.luau`)
	crap()
	T.equal(fs.readFile(`{SAMPLE}/src/covered.luau`), before)
end)
T.it("fails the gate at the threshold", function()
	T.equal(crap("--threshold", "5").code, 2)
	T.equal(crap("--threshold", "500").code, 0)
end)
T.it("needs to be told how to test a project with no tests/run", function()
	local result = process.exec("lune", { "run", CLI, "." }, { cwd = `{SAMPLE}/src` })
	T.equal(result.code, 1)
	T.equal(has(result.stdout, "--test"), true)
end)
T.it("reports a file it can't parse, and bad options, as errors", function()
	T.equal(crap("--nope").code, 1)
	T.equal(has(crap("--help").stdout, "Usage"), true)
end)
T.it("stops if the tests fail", function()
	local result = crap("--test", "echo broken; exit 1")
	T.equal(result.code, 3)
	T.equal(has(result.stdout, "broken"), true)
end)
T.it("scores complexity alone with --no-coverage", function()
	local result = crap("--no-coverage")
	T.equal(result.code, 0)
	T.equal(has(result.stdout, "n/a"), true)
end)
T.it("is an error, not a pass, when there is nothing to score", function()
	T.equal(crap("--exclude", "src").code, 1)
	T.equal(crap("nonexistent").code, 1)
end)
