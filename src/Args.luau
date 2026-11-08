--!strict
-- Command-line parsing.

local Args = {}

export type Options = {
	paths: { string },
	exclude: { string },
	test: string?,
	coverage: boolean,
	threshold: number?,
	top: number,
	help: boolean,
}

Args.USAGE = [[
luau-crap: CRAP scores for Luau (complexity x untestedness, per function)

Usage: luau-crap [options] [paths...]    (run from the project root; paths default to src)

  --test <command>   Command that runs the tests, from a copy of the project
                     (default: lune run tests/run)
  --no-coverage      Complexity only: scores are the worst case, as if 0% covered
  --threshold <n>    Exit 2 if any function scores n or more (the summary always uses it; default 10)
  --exclude <text>   Skip files whose path contains this text (repeatable)
  --top <n>          Rows to print (default 30)
  --help             This text

Exit codes: 0 fine, 1 usage or analysis error, 2 over the threshold, 3 the tests failed.]]

local function positiveNumber(flag: string, text: string?): number
	local value = text and tonumber(text)
	if not value or value <= 0 then
		error(`{flag} needs a positive number`, 0)
	end
	return value
end

local function required(flag: string, text: string?): string
	if not text then
		error(`{flag} needs a value`, 0)
	end
	return text
end

local function checkedPath(path: string): string
	if string.sub(path, 1, 1) == "/" or string.find(path, "..", 1, true) then
		error(`{path}: give paths relative to the project root, inside it`, 0)
	end
	return path
end

local VALUE_FLAGS: { [string]: (options: Options, text: string?) -> () } = {
	["--test"] = function(options, text)
		options.test = required("--test", text)
	end,
	["--threshold"] = function(options, text)
		options.threshold = positiveNumber("--threshold", text)
	end,
	["--top"] = function(options, text)
		options.top = positiveNumber("--top", text)
	end,
	["--exclude"] = function(options, text)
		table.insert(options.exclude, required("--exclude", text))
	end,
}

local SWITCHES: { [string]: (options: Options) -> () } = {
	["--no-coverage"] = function(options)
		options.coverage = false
	end,
	["--help"] = function(options)
		options.help = true
	end,
}

function Args.parse(args: { string }): Options
	local options: Options =
		{ paths = {}, exclude = {}, test = nil, coverage = true, threshold = nil, top = 30, help = false }
	local index = 1
	while index <= #args do
		local arg = args[index]
		if VALUE_FLAGS[arg] then
			VALUE_FLAGS[arg](options, args[index + 1])
			index += 1
		elseif SWITCHES[arg] then
			SWITCHES[arg](options)
		elseif string.sub(arg, 1, 2) == "--" then
			error(`unknown option {arg}`, 0)
		else
			table.insert(options.paths, checkedPath(arg))
		end
		index += 1
	end
	if #options.paths == 0 then
		options.paths = { "src" }
	end
	return options
end

return table.freeze(Args)
