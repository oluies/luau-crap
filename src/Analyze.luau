--!strict
-- Finds every function in a token stream with its cyclomatic complexity and its blocks: the
-- places a coverage counter can go. Complexity is 1, plus 1 per if, elseif, while, for, repeat,
-- `and` and `or`, if-expressions included. A nested function is scored on its own, and the file's
-- top-level code is scored as "<chunk>".

local Lexer = require("./Lexer")

local Analyze = {}

export type Func = { name: string, line: number, complexity: number, blocks: { number } }
export type Insert = { position: number, block: number } -- goes after byte `position`
export type Result = { functions: { Func }, inserts: { Insert }, blockCount: number }

type Token = Lexer.Token
type Frame = "function" | "if" | "ifexpr" | "do" | "repeat"
type State = {
	tokens: { Token },
	index: number,
	frames: { Frame },
	functions: { Func },
	current: { Func }, -- innermost last
	inserts: { Insert },
	blockCount: number,
	exprBranch: number, -- the last `then` or `else` that belonged to an if-expression
}

-- What can come right before an if-expression. Before an if-statement comes the end of the
-- previous statement instead, or the start of a block.
local EXPRESSION_KEYWORDS = table.freeze({
	["return"] = true,
	["and"] = true,
	["or"] = true,
	["not"] = true,
	["in"] = true,
	["if"] = true,
	["elseif"] = true,
	["while"] = true,
	["until"] = true,
})
local EXPRESSION_OPERATORS = table.freeze({
	["="] = true,
	["+="] = true,
	["-="] = true,
	["*="] = true,
	["/="] = true,
	["//="] = true,
	["%="] = true,
	["^="] = true,
	["..="] = true,
	["+"] = true,
	["-"] = true,
	["*"] = true,
	["/"] = true,
	["//"] = true,
	["%"] = true,
	["^"] = true,
	[".."] = true,
	["#"] = true,
	["=="] = true,
	["~="] = true,
	["<"] = true,
	["<="] = true,
	[">"] = true,
	[">="] = true,
	["("] = true,
	["["] = true,
	["{"] = true,
	[","] = true,
})

local function fail(token: Token, message: string): never
	error(`line {token.line}: {message}`, 0)
end

local function bump(state: State)
	local func = state.current[#state.current]
	func.complexity += 1
end

local function addBlock(state: State, position: number)
	state.blockCount += 1
	local func = state.current[#state.current]
	table.insert(func.blocks, state.blockCount)
	table.insert(state.inserts, { position = position, block = state.blockCount })
end

local function pushFunction(state: State, name: string, line: number)
	local func = { name = name, line = line, complexity = 1, blocks = {} }
	table.insert(state.functions, func)
	table.insert(state.current, func)
end

local function closer(tokens: { Token }, index: number, opener: string, close: string): number
	local depth = 0
	local at = index
	while tokens[at].kind ~= "eof" do
		local text = tokens[at].text
		if tokens[at].kind == "op" and text == opener then
			depth += 1
		elseif tokens[at].kind == "op" and text == close then
			depth -= 1
			if depth == 0 then
				return at
			end
		end
		at += 1
	end
	fail(tokens[index], `no closing {close}`)
end

local skipType: (tokens: { Token }, index: number) -> number

local function skipTypeName(tokens: { Token }, index: number): number
	local at = index
	if tokens[at].text == "typeof" and tokens[at + 1].text == "(" then
		return closer(tokens, at + 1, "(", ")")
	end
	while tokens[at + 1].text == "." do
		at += 2
	end
	if tokens[at + 1].text == "<" then
		at = closer(tokens, at + 1, "<", ">")
	end
	return if tokens[at + 1].text == "..." then at + 1 else at
end

local function skipSimpleType(tokens: { Token }, index: number): number
	local text = tokens[index].text
	if text == "(" then
		local close = closer(tokens, index, "(", ")")
		return if tokens[close + 1].text == "->" then skipType(tokens, close + 2) else close
	elseif text == "<" then
		return skipSimpleType(tokens, closer(tokens, index, "<", ">") + 1)
	elseif text == "{" then
		return closer(tokens, index, "{", "}")
	elseif text == "..." then
		return skipType(tokens, index + 1)
	elseif tokens[index].kind == "name" then
		return skipTypeName(tokens, index)
	end
	return index -- a singleton: nil, true, false or a string
end

-- The index of the last token of the type starting at `index`
function skipType(tokens: { Token }, index: number): number
	local first = if tokens[index].text == "|" or tokens[index].text == "&" then index + 1 else index
	local last = skipSimpleType(tokens, first)
	while tokens[last + 1].text == "?" do
		last += 1
	end
	if tokens[last + 1].text == "|" or tokens[last + 1].text == "&" then
		return skipType(tokens, last + 2)
	end
	return last
end

-- The index of the last token before the body of the function whose keyword is at `index`
local function signatureEnd(tokens: { Token }, index: number): number
	local at = index + 1
	while tokens[at].text ~= "(" and tokens[at].text ~= "<" do
		if tokens[at].kind == "eof" then
			fail(tokens[index], "function with no parameters")
		end
		at += 1
	end
	if tokens[at].text == "<" then
		at = closer(tokens, at, "<", ">") + 1
	end
	local close = closer(tokens, at, "(", ")")
	return if tokens[close + 1].text == ":" then skipType(tokens, close + 2) else close
end

local function dottedNameBefore(tokens: { Token }, index: number): string?
	if tokens[index].kind ~= "name" then
		return nil
	end
	local name, at = tokens[index].text, index
	while at > 2 and tokens[at - 1].text == "." and tokens[at - 2].kind == "name" do
		name = `{tokens[at - 2].text}.{name}`
		at -= 2
	end
	return name
end

local function statementName(tokens: { Token }, index: number): string
	local parts, at = {}, index + 1
	while tokens[at].kind == "name" or tokens[at].text == "." or tokens[at].text == ":" do
		table.insert(parts, tokens[at].text)
		at += 1
	end
	return table.concat(parts)
end

local function functionName(tokens: { Token }, index: number): string
	if tokens[index + 1].kind == "name" then
		return statementName(tokens, index)
	end
	local assigned = index > 2 and tokens[index - 1].text == "=" and dottedNameBefore(tokens, index - 2)
	return assigned or `<anonymous:{tokens[index].line}>`
end

local function isExpressionIf(state: State, index: number): boolean
	local previous = state.tokens[index - 1]
	if not previous then
		return false
	elseif state.exprBranch == index - 1 or previous.kind == "interp" then
		return true
	elseif previous.kind == "keyword" then
		return EXPRESSION_KEYWORDS[previous.text] == true
	end
	return previous.kind == "op" and EXPRESSION_OPERATORS[previous.text] == true
end

local function top(state: State): Frame?
	return state.frames[#state.frames]
end

local function popExpecting(state: State, token: Token, allowed: { [string]: boolean })
	local frame = table.remove(state.frames)
	if not frame or not allowed[frame] then
		fail(token, `unexpected '{token.text}'`)
	end
	if frame == "function" then
		table.remove(state.current)
	end
end

local CLOSED_BY_END = table.freeze({ ["function"] = true, ["if"] = true, ["do"] = true })
local CLOSED_BY_UNTIL = table.freeze({ ["repeat"] = true })

local HANDLERS: { [string]: (state: State, token: Token) -> () } = {
	["and"] = bump,
	["or"] = bump,
	["while"] = bump,
	["for"] = bump,
	["elseif"] = bump,
	["if"] = function(state, _)
		bump(state)
		table.insert(state.frames, if isExpressionIf(state, state.index) then "ifexpr" else "if")
	end,
	["then"] = function(state, token)
		if top(state) == "ifexpr" then
			state.exprBranch = state.index
		else
			addBlock(state, token.last)
		end
	end,
	["else"] = function(state, token)
		if top(state) == "ifexpr" then
			table.remove(state.frames) -- the else branch is an expression with no closing token
			state.exprBranch = state.index
		else
			addBlock(state, token.last)
		end
	end,
	["do"] = function(state, token)
		table.insert(state.frames, "do")
		addBlock(state, token.last)
	end,
	["repeat"] = function(state, token)
		bump(state)
		table.insert(state.frames, "repeat")
		addBlock(state, token.last)
	end,
	["until"] = function(state, token)
		popExpecting(state, token, CLOSED_BY_UNTIL)
	end,
	["end"] = function(state, token)
		popExpecting(state, token, CLOSED_BY_END)
	end,
	["function"] = function(state, token)
		local tokens, index = state.tokens, state.index
		pushFunction(state, functionName(tokens, index), token.line)
		table.insert(state.frames, "function")
		local last = signatureEnd(tokens, index)
		addBlock(state, tokens[last].last)
		state.index = last
	end,
}

function Analyze.analyze(tokens: { Token }): Result
	local state: State = {
		tokens = tokens,
		index = 1,
		frames = {},
		functions = {},
		current = {},
		inserts = {},
		blockCount = 0,
		exprBranch = 0,
	}
	pushFunction(state, "<chunk>", 1)
	addBlock(state, 0)
	while tokens[state.index].kind ~= "eof" do
		local token = tokens[state.index]
		local handler = if token.kind == "keyword" then HANDLERS[token.text] else nil
		if handler then
			handler(state, token)
		end
		state.index += 1
	end
	if #state.frames > 0 then
		fail(tokens[state.index], `unclosed {state.frames[#state.frames]}`)
	end
	return table.freeze({ functions = state.functions, inserts = state.inserts, blockCount = state.blockCount })
end

return table.freeze(Analyze)
