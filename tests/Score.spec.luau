--!strict
local T = require("./Check")
local Args = require("../src/Args")
local Report = require("../src/Report")
local Score = require("../src/Score")

local function file(complexity: number)
	return {
		path = "a.luau",
		analysis = {
			functions = { { name = "f", line = 1, complexity = complexity, blocks = { 1, 2 } } },
			inserts = {},
			blockCount = 2,
		},
	}
end

T.it("computes CRAP", function()
	T.equal(Score.crap(5, 1), 5)
	T.equal(Score.crap(5, 0), 30)
	T.equal(Score.crap(4, 0.5), 6)
	T.equal(Score.crap(5, nil), 30, "worst case without coverage")
end)
T.it("takes coverage from the blocks reached", function()
	local rows = Score.rows({ file(2) }, { [1] = { [1] = true } })
	T.equal(rows[1].coverage, 0.5)
end)
T.it("counts an unloaded file as uncovered and names it", function()
	T.equal(Score.rows({ file(2) }, {})[1].coverage, 0)
	T.equal(Score.unloaded({ file(2) }, {})[1], "a.luau")
end)
T.it("sorts worst first", function()
	local rows = Score.rows({ file(2), file(9) }, nil)
	T.equal(rows[1].complexity, 9)
end)
T.it("reports a verdict", function()
	local rows = Score.rows({ file(2) }, nil)
	local text = Report.format(rows, { top = 5, threshold = 100, fileCount = 1 })
	T.equal(string.find(text, "PASS: 0 of 1", 1, true) ~= nil, true)
	T.equal(string.find(text, "worst case", 1, true) ~= nil, true)
	local failing = Report.format(rows, { top = 5, threshold = 1, fileCount = 1 })
	T.equal(string.find(failing, "FAIL: 1 of 1", 1, true) ~= nil, true)
end)
T.it("truncates long lists and names unloaded files", function()
	local rows = Score.rows({ file(2), file(9) }, {})
	local text = Report.format(rows, { top = 1, threshold = 100, fileCount = 2, unloaded = { "a.luau" } })
	T.equal(string.find(text, "and 1 more", 1, true) ~= nil, true)
	T.equal(string.find(text, "1 file(s) never loaded", 1, true) ~= nil, true)
	T.equal(string.find(text, "\n  a.luau", 1, true) ~= nil, true)
end)
T.it("parses arguments", function()
	local options = Args.parse({ "--threshold", "8", "--exclude", "Vendor", "--no-coverage", "src/shared" })
	T.equal(options.threshold, 8)
	T.equal(options.exclude[1], "Vendor")
	T.equal(options.coverage, false)
	T.equal(options.paths[1], "src/shared")
	T.equal(Args.parse({}).paths[1], "src")
end)
T.it("refuses bad arguments", function()
	T.equal(pcall(Args.parse, { "--nope" }), false)
	T.equal(pcall(Args.parse, { "--threshold", "x" }), false)
	T.equal(pcall(Args.parse, { "../elsewhere" }), false)
	T.equal(pcall(Args.parse, { "/abs" }), false)
end)
