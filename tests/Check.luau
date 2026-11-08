--!strict
-- A minimal test API: it(name, body), equal(actual, expected, label), and a report.

local Check = {}

local passed = 0
local failures: { string } = {}

function Check.it(name: string, body: () -> ())
	local ok, err = pcall(body)
	if ok then
		passed += 1
	else
		table.insert(failures, `{name}\n    {err}`)
	end
end

function Check.equal(actual: any, expected: any, label: string?)
	if actual ~= expected then
		error(`{label or "value"}: expected {expected}, got {actual}`, 2)
	end
end

function Check.report(): number
	for _, failure in ipairs(failures) do
		print(`FAIL {failure}`)
	end
	print(`{passed} passed, {#failures} failed`)
	return if #failures == 0 then 0 else 1
end

return Check
