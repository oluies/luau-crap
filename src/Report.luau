--!strict
-- Formats scores as a table, worst first.

local Score = require("./Score")

local Report = {}

export type Options = { top: number, threshold: number, unloaded: { string }?, fileCount: number }

local function coverageText(coverage: number?): string
	return if coverage then string.format("%.0f", coverage * 100) else "n/a"
end

local function rowText(row: Score.Row): string
	local location = `{row.path}:{row.line}`
	local coverage = coverageText(row.coverage)
	return string.format("%8.1f %4d %5s  %-36s %s", row.crap, row.complexity, coverage, row.name, location)
end

local function unloadedText(paths: { string }): { string }
	local lines = { `{#paths} file(s) never loaded by the tests, so counted as 0% covered:` }
	for _, path in ipairs(paths) do
		table.insert(lines, `  {path}`)
	end
	return lines
end

local function summaryText(rows: { Score.Row }, options: Options): string
	local failing = Score.countAtOrAbove(rows, options.threshold)
	local verdict = if failing == 0 then "PASS" else "FAIL"
	return `{verdict}: {failing} of {#rows} functions in {options.fileCount} file(s) score {options.threshold} or more`
end

function Report.format(rows: { Score.Row }, options: Options): string
	local lines = { string.format("%8s %4s %5s  %-36s %s", "CRAP", "CC", "COV%", "FUNCTION", "LOCATION") }
	for index = 1, math.min(options.top, #rows) do
		table.insert(lines, rowText(rows[index]))
	end
	if #rows > options.top then
		table.insert(lines, `... and {#rows - options.top} more (--top N to show them)`)
	end
	if rows[1] and rows[1].coverage == nil then
		table.insert(lines, "Coverage not measured: scores are the worst case, as if 0% covered.")
	end
	if options.unloaded and #options.unloaded > 0 then
		table.move(unloadedText(options.unloaded), 1, #options.unloaded + 1, #lines + 1, lines)
	end
	table.insert(lines, summaryText(rows, options))
	return table.concat(lines, "\n")
end

return table.freeze(Report)
