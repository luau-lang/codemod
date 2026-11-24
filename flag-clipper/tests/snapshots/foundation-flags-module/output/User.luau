local Flags = require(script.Parent.Flags)

-- Flags.Bumped is tracked via the Flags module's table entry.
-- policy.FlagName is an unrelated table with a field named like the flag, and must be left alone.
local function getValues(policy)
	print("on" )
	local fromPolicy = policy.FlagName or false
	return fromPolicy, Flags.Unrelated
end

return getValues
