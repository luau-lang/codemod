local aliases = require("../aliases")

function test_computeBestAliases()
	local availableAliases = {
		["project"] = { path = "project", originalName = "Project", configLocation = "." },
		["packages"] = { path = "packages", originalName = "Packages", configLocation = "." },
		["nestedproject"] = { path = "project/nested", originalName = "NestedProject", configLocation = "." },
	}

	assert(aliases.computeBestAliasesPath("./project/user.luau", availableAliases) == "@Project/user")
	assert(aliases.computeBestAliasesPath("./packages/React.luau", availableAliases) == "@Packages/React")
	assert(
		aliases.computeBestAliasesPath("./packages/nested/library/React.luau", availableAliases)
			== "@Packages/nested/library/React"
	)
	assert(aliases.computeBestAliasesPath("./project/nested/lib.luau", availableAliases) == "@NestedProject/lib")
	assert(aliases.computeBestAliasesPath("./random/test.luau", availableAliases) == nil)
end

test_computeBestAliases()
