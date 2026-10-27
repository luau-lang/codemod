return {
	-- Release 1.1.0
	FlagName = SafeFlags.createGetFFlag("FlagName")(),
	FirstGroupFlag = SafeFlags.createGetFFlag("FirstGroupFlag")(),

	-- Release 1.2.0
	SecondGroupFlag = SafeFlags.createGetFFlag("SecondGroupFlag")(),
}
