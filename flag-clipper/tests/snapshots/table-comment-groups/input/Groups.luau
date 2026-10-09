local onlyFieldInGroup = {
	first = 1,

	-- Removed along with its only field
	flagged = game:GetFastFlag("FlagName"),

	-- Kept with its field
	last = 2,
}

local fieldWithItsOwnComment = {
	-- Heads the group
	flagged = game:GetFastFlag("FlagName"),
	-- Describes the field below
	kept = 1,
}

local middleOfGroup = {
	-- Heads the group
	first = 1,
	flagged = game:GetFastFlag("FlagName"),
	last = 2,
}

local newGroupAfterRemoval = {
	-- Heads a group that empties
	flagged = game:GetFastFlag("FlagName"),

	-- Heads the next group
	removedValue = if game:GetFastFlag("FlagName") then nil else 1,
	kept = 2,
}

local firstGroupRemoved = {
	-- Heads a group that empties
	flagged = game:GetFastFlag("FlagName"),

	-- Heads the next group
	kept = 1,
}

return {
	onlyFieldInGroup = onlyFieldInGroup,
	fieldWithItsOwnComment = fieldWithItsOwnComment,
	middleOfGroup = middleOfGroup,
	newGroupAfterRemoval = newGroupAfterRemoval,
	firstGroupRemoved = firstGroupRemoved,
}
