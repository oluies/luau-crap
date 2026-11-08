--!strict
-- Turns Luau source into tokens, dropping comments. Byte offsets are kept so the instrumenter
-- can insert code without disturbing anything else on the line. An interpolated string becomes
-- `interp` segments (each ending at a `{`), the tokens of each expression, and a final `string`.

local Lexer = {}

export type Kind = "name" | "keyword" | "number" | "string" | "interp" | "op" | "eof"
export type Token = {
	kind: Kind,
	text: string,
	first: number,
	last: number,
	line: number,
}

local KEYWORDS = table.freeze({
	["and"] = true,
	["break"] = true,
	["do"] = true,
	["else"] = true,
	["elseif"] = true,
	["end"] = true,
	["false"] = true,
	["for"] = true,
	["function"] = true,
	["if"] = true,
	["in"] = true,
	["local"] = true,
	["nil"] = true,
	["not"] = true,
	["or"] = true,
	["repeat"] = true,
	["return"] = true,
	["then"] = true,
	["true"] = true,
	["until"] = true,
	["while"] = true,
})

-- Longest first within each length
local OPERATORS = table.freeze({
	"//=",
	"...",
	"..=",
	"..",
	"::",
	"->",
	"==",
	"~=",
	"<=",
	">=",
	"+=",
	"-=",
	"*=",
	"/=",
	"%=",
	"^=",
	"//",
})

local function fail(line: number, message: string): never
	error(`line {line}: {message}`, 0)
end

-- The position after a [[ or [==[ string or comment opening at `first`; nil if it isn't one
local function longBracketEnd(source: string, first: number, line: number): number?
	local equals = string.match(source, "^%[(=*)%[", first)
	if not equals then
		return nil
	end
	local closer = `]{equals}]`
	local _, last = string.find(source, closer, first + #equals + 2, true)
	if not last then
		fail(line, "unterminated long string")
	end
	return (last :: number) + 1
end

local function skipEscape(source: string, slash: number): number
	if string.sub(source, slash + 1, slash + 1) == "z" then
		local _, spaces = string.find(source, "^%s*", slash + 2)
		return (spaces :: number) + 1
	end
	return slash + 2
end

local function quotedEnd(source: string, first: number, line: number): number
	local quote = string.sub(source, first, first)
	local at = first + 1
	while true do
		local found = string.find(source, `[\\\n{quote}]`, at)
		local char = found and string.sub(source, found, found)
		if not found or char == "\n" then
			fail(line, "unterminated string")
		elseif char == "\\" then
			at = skipEscape(source, found :: number)
		else
			return (found :: number) + 1
		end
	end
end

-- From just after a backtick or a closing }: where the segment stops, and whether at a `{`
local function interpSegmentEnd(source: string, from: number, line: number): (number, boolean)
	local at = from
	while true do
		local found = string.find(source, "[\\`{]", at)
		if not found then
			fail(line, "unterminated interpolated string")
		end
		local char = string.sub(source, found :: number, found :: number)
		if char == "\\" then
			at = skipEscape(source, found :: number)
		else
			return (found :: number) + 1, char == "{"
		end
	end
end

local function numberEnd(source: string, first: number): number
	local _, based = string.find(source, "^0[xXbB][%x_]+", first)
	if based then
		return based + 1
	end
	local _, digits = string.find(source, "^[%d_]*", first)
	local at = (digits :: number) + 1
	if string.find(source, "^%.[^%.]", at) or (at == #source and string.sub(source, at, at) == ".") then
		local _, fraction = string.find(source, "^[%d_]*", at + 1)
		at = (fraction :: number) + 1
	end
	local _, exponent = string.find(source, "^[eE][%+%-]?[%d_]+", at)
	return if exponent then exponent + 1 else at
end

local function operatorEnd(source: string, first: number): number
	for _, operator in ipairs(OPERATORS) do
		if string.sub(source, first, first + #operator - 1) == operator then
			return first + #operator
		end
	end
	return first + 1
end

-- Past whitespace and comments, from `from`
local function skipTrivia(source: string, from: number, line: number): number
	local at = from
	while true do
		local _, spaces = string.find(source, "^%s*", at)
		at = (spaces :: number) + 1
		if string.sub(source, at, at + 1) ~= "--" then
			return at
		end
		local long = longBracketEnd(source, at + 2, line)
		if long then
			at = long
		else
			at = string.find(source, "\n", at, true) or #source + 1
		end
	end
end

local function countLines(source: string, first: number, stop: number): number
	local count, at = 0, first
	while true do
		local found = string.find(source, "\n", at, true)
		if not found or found >= stop then
			return count
		end
		count += 1
		at = found + 1
	end
end

local function classifyStart(source: string, at: number, line: number): (Kind, number)
	local char = string.sub(source, at, at)
	if string.find(char, "[%a_]") then
		local _, last = string.find(source, "^[%w_]+", at)
		local stop = (last :: number) + 1
		return if KEYWORDS[string.sub(source, at, stop - 1)] then "keyword" else "name", stop
	elseif string.find(source, "^%.?%d", at) then
		return "number", numberEnd(source, at)
	elseif char == '"' or char == "'" then
		return "string", quotedEnd(source, at, line)
	end
	local long = longBracketEnd(source, at, line)
	if long then
		return "string", long
	end
	return "op", operatorEnd(source, at)
end

local function trackBrace(depths: { number }, char: string)
	if #depths > 0 and char == "{" then
		depths[#depths] += 1
	elseif #depths > 0 and char == "}" then
		depths[#depths] -= 1
	end
end

function Lexer.tokenize(source: string): { Token }
	local tokens: { Token } = {}
	local depths: { number } = {} -- open braces inside each interpolated expression
	local line, at = 1, 1

	local function push(kind: Kind, stop: number)
		table.insert(tokens, {
			kind = kind,
			text = string.sub(source, at, stop - 1),
			first = at,
			last = stop - 1,
			line = line,
		})
		line += countLines(source, at, stop)
		at = stop
	end

	local function pushSegment(from: number)
		local stop, opens = interpSegmentEnd(source, from, line)
		if opens then
			table.insert(depths, 0)
		end
		push(if opens then "interp" else "string", stop)
	end

	while true do
		local nextAt = skipTrivia(source, at, line)
		line += countLines(source, at, nextAt)
		at = nextAt
		if at > #source then
			push("eof", at)
			return tokens
		end
		local char = string.sub(source, at, at)
		local depth = depths[#depths]
		if char == "`" then
			pushSegment(at + 1)
		elseif char == "}" and depth == 0 then
			table.remove(depths)
			pushSegment(at + 1)
		else
			trackBrace(depths, char)
			local kind, stop = classifyStart(source, at, line)
			push(kind, stop)
		end
	end
end

return table.freeze(Lexer)
