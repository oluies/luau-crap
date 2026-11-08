--!strict
local T = require("./Check")
local Lexer = require("../src/Lexer")

local function texts(source: string): string
	local out = {}
	for _, token in ipairs(Lexer.tokenize(source)) do
		if token.kind ~= "eof" then
			table.insert(out, token.text)
		end
	end
	return table.concat(out, " ")
end

T.it("splits names, numbers and longest operators", function()
	T.equal(texts("a.b:c(1.5e3, 0xFF) ..= ... // //="), "a . b : c ( 1.5e3 , 0xFF ) ..= ... // //=")
	T.equal(texts("1..2"), "1 .. 2")
end)
T.it("drops comments", function()
	T.equal(texts("a -- b\n--[[ c\nd ]] e --[==[ ]] ]==] f"), "a e f")
end)
T.it("keeps strings whole", function()
	local source = "\"a\\\"b\" 'c' [[d]] [=[e]]f]=]"
	T.equal(texts(source), source)
end)
T.it("follows interpolated strings into their expressions", function()
	T.equal(texts("`a{b}c{ {d} }e`"), "`a{ b }c{ { d } }e`")
	T.equal(texts("`\\{x}`"), "`\\{x}`")
	T.equal(texts("`{`{a}`}`"), "`{ `{ a }` }`")
end)
T.it("tracks lines across multi-line tokens and comments", function()
	local tokens = Lexer.tokenize("a\n--[[\n]]\n[[\n]] b")
	T.equal(tokens[1].line, 1)
	T.equal(tokens[2].line, 4)
	T.equal(tokens[3].line, 5)
end)
T.it("reports unterminated strings", function()
	T.equal(pcall(Lexer.tokenize, '"abc'), false)
	T.equal(pcall(Lexer.tokenize, "[[abc"), false)
	T.equal(pcall(Lexer.tokenize, "`abc"), false)
end)
