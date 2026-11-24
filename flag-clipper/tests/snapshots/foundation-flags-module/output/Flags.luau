local SafeFlags = require(script.Parent.SafeFlags)

return {
	Unrelated = SafeFlags.createGetFFlag("OtherFlag")(),
}
