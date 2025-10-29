local fs = require("@lute/fs")
local process = require("@lute/process")

local codemod = require("../")
local files = require("../../lib/files")
local path = require("../../lib/path")
local types = require("../../lib/types")

local function apply(source: string, flagName: string?, value: boolean?)
	flagName = flagName or "FlagName"
	value = if value == nil then true else value
	return codemod.transform({
		path = "",
		source = source,
		options = { flag = flagName, value = value, sourcemap = "" },
	})
end

local function test_markFlagModuleForDeletion()
	local source = [[
		return function()
			return game:GetFastFlag("FlagName")
		end
	]]

	assert(apply(source) == types.DELETION_MARKER)
end

local function test_overallSingleFile()
	local source = [[
		print("Example Module")

		-- Remove references to the flag
		game:DefineFastFlag("FlagName")
		local flagValue = game:GetFastFlag("FlagName")

		-- Leave other flags alone
		game:DefineFastFlag("OtherFlagName")
		local otherFlagValue = game:GetFastFlag("OtherFlagName")

		-- Remove flag getter functions
		local function getFlagValueLocal()
			return game:GetFastFlag("FlagName")
		end

		function getFlagValueGlobal()
			return game:GetFastFlag("FlagName")
		end

		-- But leave unrelated functions alone, and keep the comments!
		local function getOtherFlagValueLocal()
			return game:GetFastFlag("OtherFlagName")
		end

		function getOtherFlagValueGlobal()
			return game:GetFastFlag("OtherFlagName")
		end

		-- Simplify if blocks
		print("Simplify code")

		if game:GetFastFlag("FlagName") then
			print("Fast flag enabled! Direct access")
		else
			print("Fast flag disabled. Direct access")
		end

		if flagValue then
			print("Fast flag enabled! Variable access")
		else
			print("Fast flag disabled. Variable access")
		end

		if getFlagValueLocal() then
			print("Fast flag enabled! Local call access")
		else
			print("Flag value disabled. Local call access")
		end

		if getFlagValueGlobal() then
			print("Fast flag enabled! Global call access")
		else
			print("Fast flag disabled. Global call access")
		end

		if not flagValue then
			print("Flag value disabled. Unary check")
		else
			print("Fast flag enabled! Unary check")
		end

		if flagValue and otherFlagValue then
			print("Both fast flags are enabled")
		else
			print("Both fast flags are not enabled")
		end

		if flagValue or randomFunctionCall() then
			print("Either the fast flag was enabled, or some other expression passed")
		else
			print("Neither the flag was enabled, nor did the other expression pass")
		end
	]]

	local expected = [[
		print("Example Module")

		-- Leave other flags alone
		game:DefineFastFlag("OtherFlagName")
		local otherFlagValue = game:GetFastFlag("OtherFlagName")

		-- But leave unrelated functions alone, and keep the comments!
		local function getOtherFlagValueLocal()
			return game:GetFastFlag("OtherFlagName")
		end

		function getOtherFlagValueGlobal()
			return game:GetFastFlag("OtherFlagName")
		end

		-- Simplify if blocks
		print("Simplify code")

			print("Fast flag enabled! Direct access")

			print("Fast flag enabled! Variable access")

			print("Fast flag enabled! Local call access")

			print("Fast flag enabled! Global call access")

			print("Fast flag enabled! Unary check")

		if otherFlagValue then
			print("Both fast flags are enabled")
		else
			print("Both fast flags are not enabled")
		end

			print("Either the fast flag was enabled, or some other expression passed")
	]]

	assert(apply(source) == expected)
end

local function test_simplifyUseOfCompoundFlagReference()
	local source = [[
		local x = not game:GetFastFlag("FlagName")
		local y = game:GetFastFlag("FlagName") or arbitraryCondition
		local z = game:GetFastFlag("FlagName") and arbitraryCondition
		local zz = not game:GetFastFlag("FlagName") or arbitraryCondition

		if x then
			print("a")
		end
		if not x then
			print("b")
		end
		if y then
			print("c")
		end
		if not y then
			print("d")
		end
		if z then
			print("e")
		end
		if zz then
			print("f")
		end
	]]
	local expected = [[
		local z = arbitraryCondition
		local zz = arbitraryCondition
			print("b")
			print("c")
		if z then
			print("e")
		end
		if zz then
			print("f")
		end
	]]
	assert(apply(source, "FlagName", true) == expected)
end

local function test_simplifyCompoundReferenceTableEntry()
	local source = [[
		local x = { myProp = game:GetFastFlag('FlagName') and someCondition }
		local y = { myProp = game:GetFastFlag('FlagName') or someCondition }
		local z = { myProp = not game:GetFastFlag('FlagName') or someCondition }
		local zz = { myProp = not game:GetFastFlag('FlagName') and someCondition }
	]]
	local expected = [[
		local x = { myProp = someCondition }
		local y = { }
		local z = { myProp = someCondition }
		local zz = { myProp = false }
	]]

	assert(apply(source, "FlagName", true) == expected)
end

--[[
only reallllyyyy problematic edge case I can see with the new logic is where he vars = to compound flag bools are used thereafter
Buttttt, we only simplify if they will be simplified to a constant? and I can't imagine they will be used for many things?
Ways to handle:
	- if used in a call, replace w/ the constant evaluation
	- if re-assigned... tricky, we might have to not remove these :/ (but that is such weird logic to include...)
	- how else to handle? what other cases...
]]

local function test_compoundCondition()
	local source = [[
		if game:GetFastFlag("FlagName") or value then
			local x = 1
		else
			local x = 2
		end
	]]

	local expected = [[
			local x = 1
	]]

	assert(apply(source, "FlagName", true) == expected)
end

local function test_compoundConditionWithUnary()
	local source = [[
		if value and not game:GetFastFlag("FlagName") then
			local x = 1
		else
			local x = 2
		end
	]]

	local expected = [[
			local x = 2
	]]

	assert(apply(source, "FlagName", true) == expected)
end

local function test_callWithPseudoTernary()
	local source = [[
		Instance.new(game:GetFastFlag("FlagName") and 'ImageButton' or 'Frame')
	]]

	local expected = [[
		Instance.new('ImageButton' )
	]]

	print(apply(source))

	assert(apply(source, "FlagName", true) == expected)
end

local function test_callWithPseudoTernaryInverse()
	local source = [[
		Instance.new(not game:GetFastFlag("FlagName") and 'ImageButton' or 'Frame')
	]]

	local expected: string = [[
		Instance.new('Frame')
	]]

	print(apply(source))

	assert(apply(source, "FlagName", true) == expected)
end

local function test_cleanupFastFlagsForTesting()
	local source = [[
		describe("old school", function()
			beforeAll(function()
				game:SetFastFlagForTesting("FlagName", true)
			end)
			afterAll(function()
				game:SetFastFlagForTesting("FlagName", false)
			end)
		end)

		describe("a bit newer", function()
			local oldFlagValue
			beforeAll(function()
				oldFlagValue = game:SetFastFlagForTesting("FlagName", true)
			end)
			afterAll(function()
				game:SetFastFlagForTesting("FlagName", oldFlagValue)
			end)
		end)

		describe("newest", function()
			setScopedFFlag("FlagName", true)
		end)
	]]

	local expected = [[
		describe("old school", function()
			beforeAll(function()
			end)
			afterAll(function()
			end)
		end)

		describe("a bit newer", function()
			local oldFlagValue
			beforeAll(function()
				oldFlagValue = true
			end)
			afterAll(function()
			end)
		end)

		describe("newest", function()
		end)
	]]

	assert(apply(source, "FlagName", true) == expected)
end

local function test_cleanupEntriesFromTable()
	local source = [[
		local tbl = {
			value = if game:GetFastFlag("FlagName") then nil else DEPRECATED_VALUE
		}

		local dependencies = { if game:GetFastFlag("FlagName") then nil else DEPRECATED_DEPENDENCY }
	]]

	local expected = [[
		local tbl = {
		}

		local dependencies = { }
	]]

	print(apply(source))

	assert(apply(source, "FlagName", true) == expected)
end

local function test_earlyLoopTermination()
	local source = [[
			local i = 0
			while i < 5 do
				i += 1
				if game:GetFastFlag("FlagName") then
					print(i + 1)
					break
				end
				print(i)
			end
		]]
	local expected = [[
			local i = 0
			while i < 5 do
				i += 1
					print(i + 1)
					break
			end
		]]
	assert(apply(source) == expected)
end

local function test_snapshots()
	local baseDirectory = path.joinPath(process.cwd(), "flag-clipper/tests/snapshots")

	local function getOutputLocation(outputDirectory: string, filepath: string)
		-- TODO: get proper output path using "relative" path apis
		local relativePath = filepath:sub(filepath:find("/input/") :: number + string.len("/input/"))
		return path.joinPath(outputDirectory, relativePath)
	end

	for _, test in fs.listdir(baseDirectory) do
		assert(test.type == "dir")
		print("Running", test.name)

		local testDirectory = path.joinPath(baseDirectory, test.name)
		local inputDirectory = path.joinPath(testDirectory, "input")
		local outputDirectory = path.joinPath(testDirectory, "output")

		local sources = files.getSourceFiles({ inputDirectory })

		local options = {
			flag = "FlagName",
			value = true,
			sourcemap = "",
		}

		local sourcemapPath = path.joinPath(testDirectory, "sourcemap.json")
		local hasSourcemap = pcall(fs.readfiletostring, sourcemapPath)
		if hasSourcemap then
			options.sourcemap = sourcemapPath
		end

		codemod.initialize({ options = options })

		for _, filepath in sources do
			local source = fs.readfiletostring(filepath)
			local ctx = {
				path = filepath,
				source = source,
				options = options,
			}
			local result = codemod.transform(ctx)

			local outputPath = getOutputLocation(outputDirectory, filepath)
			local outputExists, expectedContents = pcall(fs.readfiletostring, outputPath)
			if outputExists then
				assert(result == expectedContents)
			else
				local hasOutputDirectory = pcall(fs.type, outputDirectory)
				if not hasOutputDirectory then
					fs.mkdir(outputDirectory)
				end

				fs.writestringtofile(outputPath, result)
			end
		end
	end
end

return function()
	test_markFlagModuleForDeletion()
	test_simplifyUseOfCompoundFlagReference()
	test_simplifyCompoundReferenceTableEntry()
	test_compoundCondition()
	test_compoundConditionWithUnary()
	test_callWithPseudoTernary()
	test_callWithPseudoTernaryInverse()
	test_cleanupFastFlagsForTesting()
	test_cleanupEntriesFromTable()
	test_earlyLoopTermination()
	test_snapshots()
end
