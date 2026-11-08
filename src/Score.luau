--!strict
-- The CRAP metric, and turning analysed files plus coverage hits into a sorted list of scores.

local Analyze = require("./Analyze")

local Score = {}

export type File = { path: string, analysis: Analyze.Result }
export type Row = {
	path: string,
	name: string,
	line: number,
	complexity: number,
	coverage: number?, -- 0..1; nil when coverage wasn't measured
	crap: number,
}
type Hits = { [number]: { [number]: boolean } }

-- CC^2 * (1 - coverage)^3 + CC. With no coverage measured, the worst case
function Score.crap(complexity: number, coverage: number?): number
	return complexity ^ 2 * (1 - (coverage or 0)) ^ 3 + complexity
end

local function coverageOf(func: Analyze.Func, hits: { [number]: boolean }): number
	local reached = 0
	for _, block in ipairs(func.blocks) do
		if hits[block] then
			reached += 1
		end
	end
	return reached / #func.blocks
end

-- Worst first; `hits` is nil when coverage wasn't measured
function Score.rows(files: { File }, hits: Hits?): { Row }
	local rows: { Row } = {}
	for fileIndex, file in ipairs(files) do
		for _, func in ipairs(file.analysis.functions) do
			local coverage = if hits then coverageOf(func, hits[fileIndex] or {}) else nil
			table.insert(rows, {
				path = file.path,
				name = func.name,
				line = func.line,
				complexity = func.complexity,
				coverage = coverage,
				crap = Score.crap(func.complexity, coverage),
			})
		end
	end
	table.sort(rows, function(a, b)
		if a.crap ~= b.crap then
			return a.crap > b.crap
		elseif a.path ~= b.path then
			return a.path < b.path
		end
		return a.line < b.line
	end)
	return rows
end

-- The paths of files no test loaded: their top-level code never ran
function Score.unloaded(files: { File }, hits: Hits): { string }
	local paths = {}
	for fileIndex, file in ipairs(files) do
		if not hits[fileIndex] then
			table.insert(paths, file.path)
		end
	end
	return paths
end

function Score.countAtOrAbove(rows: { Row }, threshold: number): number
	local count = 0
	for _, row in ipairs(rows) do
		if row.crap >= threshold then
			count += 1
		end
	end
	return count
end

return table.freeze(Score)
