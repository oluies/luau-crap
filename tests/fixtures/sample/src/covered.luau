local Covered = {}

function Covered.sign(value: number): number
	if value > 0 then
		return 1
	elseif value < 0 then
		return -1
	end
	return 0
end

function Covered.neverCalled(a: boolean, b: boolean): boolean
	if a and b then
		return true
	end
	return false
end

return Covered
