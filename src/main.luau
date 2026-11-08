--!strict
-- The command line: finds the files, scores them and, unless told not to, measures coverage by
-- running the tests in an instrumented copy of the project. The project itself is never touched.

local fs = require("@lune/fs")
local process = require("@lune/process")

local Analyze = require("./Analyze")
local Args = require("./Args")
local Instrument = require("./Instrument")
local Lexer = require("./Lexer")
local Report = require("./Report")
local Score = require("./Score")

local DEFAULT_TEST = "lune run tests/run"
local DEFAULT_THRESHOLD = 10
local NOT_COPIED = table.freeze({ [".git"] = true, ["node_modules"] = true, [".metrics"] = true })
local EXIT_ERROR, EXIT_THRESHOLD, EXIT_TESTS_FAILED = 1, 2, 3

type Source = { path: string, source: string, analysis: Analyze.Result }

local function isSource(path: string): boolean
	return string.find(path, "%.luau?$") ~= nil and string.find(path, "%.spec%.luau?$") == nil
		and string.find(path, "%.test%.luau?$") == nil
end

local function isTestDir(name: string): boolean
	return name == "tests" or name == "test"
end

local function excluded(path: string, exclude: { string }): boolean
	for _, text in ipairs(exclude) do
		if string.find(path, text, 1, true) then
			return true
		end
	end
	return false
end

local function walk(path: string, exclude: { string }, found: { string })
	if excluded(path, exclude) then
		return
	elseif fs.isFile(path) then
		if isSource(path) then
			table.insert(found, path)
		end
	elseif fs.isDir(path) then
		for _, name in ipairs(fs.readDir(path)) do
			if not isTestDir(name) then
				walk(`{path}/{name}`, exclude, found)
			end
		end
	else
		error(`{path}: no such file or directory`, 0)
	end
end

local function load(paths: { string }, exclude: { string }): { Source }
	local found = {}
	for _, path in ipairs(paths) do
		walk(string.gsub(path, "/+$", ""), exclude, found)
	end
	table.sort(found)
	local sources = {}
	for _, path in ipairs(found) do
		local source = fs.readFile(path)
		local ok, result = pcall(function()
			return Analyze.analyze(Lexer.tokenize(source))
		end)
		if not ok then
			error(`{path}: {result}`, 0)
		end
		table.insert(sources, { path = path, source = source, analysis = result })
	end
	return sources
end

local function freshDir(): string
	local base = string.gsub(process.env.TMPDIR or "/tmp", "/+$", "")
	local dir = `{base}/luau-crap-{os.time()}-{math.random(1e9)}`
	fs.writeDir(dir)
	return dir
end

local function copyProject(destination: string)
	for _, name in ipairs(fs.readDir(".")) do
		if not NOT_COPIED[name] then
			fs.copy(name, `{destination}/{name}`)
		end
	end
end

-- Runs the tests in an instrumented copy; the hits, or nil and the output if they failed
local function measure(sources: { Source }, command: string): ({ [number]: { [number]: boolean } }?, string)
	local copy = freshDir()
	local ok, result = pcall(function()
		copyProject(copy)
		for fileIndex, file in ipairs(sources) do
			fs.writeFile(`{copy}/{file.path}`, Instrument.instrument(file.source, file.analysis.inserts, fileIndex))
		end
		return process.exec("sh", { "-c", command }, { cwd = copy })
	end)
	fs.removeDir(copy)
	if not ok then
		error(result, 0)
	end
	local output = result.stdout .. result.stderr
	return if result.ok then Instrument.parseHits(output) else nil, output
end

local function withoutMarkers(output: string): string
	local lines = {}
	for line in string.gmatch(output, "[^\n]+") do
		if not string.find(line, "@@luau-crap@@", 1, true) then
			table.insert(lines, line)
		end
	end
	return table.concat(lines, "\n")
end

local function defaultTestCommand(): string
	if not (fs.isFile("tests/run.luau") or fs.isFile("tests/run.lua")) then
		error("no tests/run.luau here: say how to run the tests with --test, or use --no-coverage", 0)
	end
	return DEFAULT_TEST
end

-- Prints the scores; the exit code
local function report(sources: { Source }, hits: { [number]: { [number]: boolean } }?, options: Args.Options): number
	local files: { Score.File } = table.create(#sources)
	for index, source in ipairs(sources) do
		files[index] = { path = source.path, analysis = source.analysis }
	end
	local rows = Score.rows(files, hits)
	print(Report.format(rows, {
		top = options.top,
		threshold = options.threshold or DEFAULT_THRESHOLD,
		unloaded = if hits then Score.unloaded(files, hits) else nil,
		fileCount = #files,
	}))
	local failing = options.threshold and Score.countAtOrAbove(rows, options.threshold) > 0
	return if failing then EXIT_THRESHOLD else 0
end

local function run(args: { string }): number
	local options = Args.parse(args)
	if options.help then
		print(Args.USAGE)
		return 0
	end
	local sources = load(options.paths, options.exclude)
	if #sources == 0 then
		error("no Luau source files found: nothing was scored", 0)
	end
	if not options.coverage then
		return report(sources, nil, options)
	end
	local hits, output = measure(sources, options.test or defaultTestCommand())
	if not hits then
		print(withoutMarkers(output))
		print("luau-crap: the tests failed, so coverage can't be trusted")
		return EXIT_TESTS_FAILED
	end
	return report(sources, hits, options)
end

local ok, result = pcall(run, process.args)
if not ok then
	print(`luau-crap: {result}`)
	process.exit(EXIT_ERROR)
end
process.exit(result)
