--!strict
local T = require("./Check")
local luau = require("@lune/luau")
local Analyze = require("../src/Analyze")
local Instrument = require("../src/Instrument")
local Lexer = require("../src/Lexer")

local SOURCE = [[
--!strict
local function pick(a: number): (number, string)
	local label = if a > 0 then "up" else "down"
	if a > 10 then
		return 10, label
	end
	for i = 1, 2 do
		a += i
	end
	repeat a -= 1 until a < 0
	return a, label
end
return pick
]]

local function instrumented(source: string): string
	return Instrument.instrument(source, Analyze.analyze(Lexer.tokenize(source)).inserts, 7)
end

T.it("leaves behaviour and line numbers alone", function()
	local output = instrumented(SOURCE)
	T.equal(select(2, string.gsub(output, "\n", "")), select(2, string.gsub(SOURCE, "\n", "")))
	local pick = luau.load(output, { environment = { print = function() end } })()
	local value, label = luau.load(SOURCE)()(20)
	local newValue, newLabel = pick(20)
	T.equal(newValue, value)
	T.equal(newLabel, label)
end)
T.it("reports each block once, the first time it runs", function()
	local printed = {}
	local pick = luau.load(instrumented(SOURCE), {
		environment = {
			print = function(line)
				table.insert(printed, line)
			end,
		},
	})()
	pick(20)
	pick(20)
	local hits = Instrument.parseHits(table.concat(printed, "\n"))[7]
	T.equal(#printed, 3, "chunk, function, the taken branch")
	T.equal(hits[1] and hits[2] and hits[3], true)
end)
T.it("ignores other output", function()
	T.equal(next(Instrument.parseHits("hello\n3 4\n")), nil)
end)
