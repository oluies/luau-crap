--!strict
local T = require("./Check")
local Analyze = require("../src/Analyze")
local Lexer = require("../src/Lexer")

local function analyze(source: string)
	return Analyze.analyze(Lexer.tokenize(source))
end

local function named(source: string, name: string)
	for _, func in ipairs(analyze(source).functions) do
		if func.name == name then
			return func
		end
	end
	error(`no function {name}`)
end

local function complexity(body: string): number
	return named(`local function f(a, b, c)\n{body}\nend`, "f").complexity
end

T.it("scores 1 for a straight-line function", function()
	T.equal(complexity("return a"), 1)
end)
T.it("counts each decision", function()
	T.equal(complexity("if a then return 1 elseif b then return 2 else return 3 end"), 3)
	T.equal(complexity("while a do end"), 2)
	T.equal(complexity("for i = 1, 3 do end"), 2)
	T.equal(complexity("for _, v in a do end"), 2)
	T.equal(complexity("repeat a() until b"), 2)
	T.equal(complexity("return a and b or c"), 3)
end)
T.it("counts if-expressions without taking them for statements", function()
	T.equal(complexity("local x = if a then 1 elseif b then 2 else 3\nreturn x"), 3)
	T.equal(complexity("return if a then 1 else 2"), 2)
	T.equal(complexity("return g(if a then 1 else 2, if b then 3 else 4)"), 3)
	T.equal(complexity("return if a then if b then 1 else 2 else 3"), 3)
	T.equal(complexity("return if a then 1 else if b then 2 else 3"), 3)
	T.equal(complexity("if if a then b else c then return 1 end"), 3)
	T.equal(complexity("return `x{if a then 1 else 2}y`"), 2)
end)
T.it("finds no block in an if-expression", function()
	T.equal(#named("local function f(a) return if a then 1 else 2 end", "f").blocks, 1)
end)
T.it("gives if-statements a block per branch", function()
	T.equal(#named("local function f(a) if a then g() else h() end end", "f").blocks, 3)
end)
T.it("tells a statement after a value from an if-expression", function()
	T.equal(#named("local function f(a)\nlocal x = a\nif x then g() end\nend", "f").blocks, 2)
	T.equal(#named("local function f(...)\nlocal x = ...\nif x then g() end\nend", "f").blocks, 2)
end)
T.it("scores a nested function on its own", function()
	local source = "local function outer(a)\nreturn function() if a then end end\nend"
	T.equal(named(source, "outer").complexity, 1)
	T.equal(named(source, "<anonymous:2>").complexity, 2)
end)
T.it("names functions the way they were written", function()
	local names = {}
	local source = [[
local function a() end
function M.b() end
function M.n.c() end
function M:d() end
local e = function() end
M.f = function() end
g(function() end)
]]
	for _, func in ipairs(analyze(source).functions) do
		table.insert(names, func.name)
	end
	T.equal(table.concat(names, " "), "<chunk> a M.b M.n.c M:d e M.f <anonymous:7>")
end)
T.it("starts a function's body after its return type", function()
	local cases = {
		"local function f(): number return 1 end",
		"local function f(a: { x: number }, b: (number) -> ()): (number, string) return 1, 'a' end",
		"local function f(): (a: number) -> string? return g end",
		"local function f<T>(a: T): { T } | nil return nil end",
		"local function f(): Foo.Bar<string>? return nil end",
		"local function f(): typeof(g()) return nil end",
		"local function f(): ...number return 1 end",
		"local function f(): 'a' | 'b' return 'a' end",
		"local function f<T...>(): T... return end",
		"local function f(): <T>(T) -> T return g end",
	}
	for _, source in ipairs(cases) do
		local position = analyze(source).inserts[2].position
		T.equal(string.sub(source, position + 2, position + 7), "return", source)
	end
end)
T.it("ignores keywords in strings and comments", function()
	T.equal(complexity("-- if a then\n--[[ and or ]]\nlocal s = 'if and' .. [[or]] .. [==[while]==]\nreturn s"), 1)
end)
T.it("refuses unbalanced code rather than scoring it wrongly", function()
	T.equal(pcall(analyze, "if a then"), false)
	T.equal(pcall(analyze, "end"), false)
	T.equal(pcall(analyze, "repeat a() end"), false)
	T.equal(pcall(analyze, "local t = { 1; if a then 2 else 3 }"), false, "the known parser limit")
end)
