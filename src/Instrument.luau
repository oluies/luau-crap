--!strict
-- Adds coverage counters to Luau source. The first time a block runs it prints a marker line, so
-- coverage reaches us through stdout however the tests end, even from process.exit or a crash,
-- and needs nothing from the test runner. Everything goes on existing lines, so line numbers in
-- errors stay true.

local Analyze = require("./Analyze")

local Instrument = {}

local MARKER = "@@luau-crap@@"
local MARKER_PATTERN = "@@luau%-crap@@"

local function header(fileIndex: number): string
	return "local __crapHit do local hits = {} __crapHit = function(block) if not hits[block] then "
		.. `hits[block] = true print("{MARKER} {fileIndex} " .. block) end end end `
end

function Instrument.instrument(source: string, inserts: { Analyze.Insert }, fileIndex: number): string
	local pieces = { header(fileIndex) }
	local at = 1
	for _, insert in ipairs(inserts) do
		table.insert(pieces, string.sub(source, at, insert.position))
		table.insert(pieces, ` __crapHit({insert.block}); `)
		at = insert.position + 1
	end
	table.insert(pieces, string.sub(source, at))
	return table.concat(pieces)
end

-- { [fileIndex]: { [block]: true } } from the output of an instrumented run
function Instrument.parseHits(output: string): { [number]: { [number]: boolean } }
	local hits = {}
	for fileIndex, block in string.gmatch(output, `{MARKER_PATTERN} (%d+) (%d+)`) do
		local file = tonumber(fileIndex) :: number
		hits[file] = hits[file] or {}
		hits[file][tonumber(block) :: number] = true
	end
	return hits
end

return table.freeze(Instrument)
