local onlyFieldInGroup = {
	first = 1,

	-- Kept with its field
	last = 2,
}

local fieldWithItsOwnComment = {
	-- Heads the group
	-- Describes the field below
	kept = 1,
}

local middleOfGroup = {
	-- Heads the group
	first = 1,
	last = 2,
}

local newGroupAfterRemoval = {
	-- Heads the next group
	kept = 2,
}

local firstGroupRemoved = {
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
