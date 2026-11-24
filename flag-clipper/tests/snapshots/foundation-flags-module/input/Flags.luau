local SafeFlags = require(script.Parent.SafeFlags)

return {
	-- Key intentionally differs from the flag name, like bumped Foundation flags
	Bumped = SafeFlags.createGetFFlag("FlagName")(),
	Unrelated = SafeFlags.createGetFFlag("OtherFlag")(),
}
