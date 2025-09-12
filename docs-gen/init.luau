local FileVisitor = require("./docs-gen/file-visitor/FileVisitor")
local codemod = require("./lib/types")
local path = require("./lib/path")
local strings = require("./lib/strings")
local commonHelpers = require("./docs-gen/commonHelpers")
local functionUtils = require("./docs-gen/functionUtils")
local tableUtils = require("./docs-gen/tableUtils")

type VarMap = FileVisitor.VarMap
type TypeMap = FileVisitor.TypeMap

type Options = {
	sourcemap: string,
	luauRc: string,
}

-- for testing empirical test runs...
local function documentVar(value: luau.AstExpr | luau.AstStat): string
	if commonHelpers.isFunction(value) then
		return functionUtils.getFunctionSignature(value)
	elseif value.tag and value.tag == "table" then
		return tableUtils.getAnonymousTableSignature(value)
	end
	return "No signature for this var"
end

local function getRelativeLocation(subPath: string, basePath: string)
	basePath = path.dirname(basePath) or ""
	local relativePath = subPath:gsub("^" .. basePath .. "/", "")
	-- Remove "src/" if present
	relativePath = relativePath:gsub("^src/", "")
	return relativePath:split("/")
end

local function buildModuleTree(
	pathComponents: { string },
	tree: { [string]: any },
	returnedVars: { any },
	anonymousReturns: { any }
)
	local current = tree
	for i, component in pathComponents do
		if i == #pathComponents then
			-- This is a file, determine if it's an init file or regular file
			local filename = component
			local isInitFile = filename:match("^init%.")
			if isInitFile then
				-- For init files, don't add them as separate entries
				-- They represent the directory itself
				current._isModule = true
				current._initFile = filename
			else
				-- Regular file - add it to the current level
				-- local cleanName = filename:gsub("%.luau?$", "")
				current[filename] = {}
				for varName, val in returnedVars do
					current[filename][varName] = documentVar(val)
				end
				local anonymousInd = 1
				for _, val in anonymousReturns do
					current[filename][`anonymous{anonymousInd}`] = documentVar(val)
				end
			end
		else
			-- This is a directory component
			current[component] = current[component] or {}
			current = current[component]
		end
	end
end

local function printModuleTree(tree: { [string]: any }, indent: number, name: string?)
	local indicator = string.rep("  ", indent)
	if name then
		-- check if file (.lua or .luau)
		if name:match("^lua%.") or name:match("^luau%.") then
			print(`{indicator} 📄 {name}`)
		else
			print(`{indicator}📁 {name}/`)
		end
	end

	-- First pass: print directories / files
	for key, value in tree do
		if tostring(key):sub(1, 1) ~= "_" and typeof(value) == "table" then -- Directory / file
			printModuleTree(value, indent + 1, key)
		end
	end

	-- Second pass: print return vars
	for key, value in tree do
		if tostring(key):sub(1, 1) ~= "_" and typeof(value) == "string" then -- returned vars
			print(`{indicator} 🏷️  {key}: {value}`)
		end
	end
end

local function transform(ctx: codemod.Context<Options>)
	local prototypeVisitor = FileVisitor.new(ctx.options.luauRc, ctx.options.sourcemap)
	local fileStack: { string } = { ctx.path }
	local basePath = ctx.path
	local moduleTree = {}
	local processedFiles = {}

	while #fileStack > 0 do
		local curFile = table.remove(fileStack, #fileStack)

		if not curFile or processedFiles[curFile] then
			continue
		end
		processedFiles[curFile] = true

		local filename = path.basename(curFile) or ""
		local isInit = strings.startsWith(filename, "init.")
		prototypeVisitor:analyzeFile(curFile :: string)
		local curFileRelative = getRelativeLocation(curFile :: string, basePath)

		-- Build the module tree (no export message for the file itself)
		buildModuleTree(curFileRelative, moduleTree, prototypeVisitor.returnedVars, prototypeVisitor.anonymousReturns)

		if isInit then
			for exportPath, _ in prototypeVisitor.reExports do
				if not processedFiles[exportPath :: string] then
					table.insert(fileStack, exportPath :: string)
				end
			end
		end
		print()
	end

	-- Print the organized module tree
	print("\n📁 Project Structure:")
	printModuleTree(moduleTree, 0)
	return ctx.source
end

return {
	options = {
		{ name = "sourcemap", kind = "string", default = "" },
		{ name = "luauRc", kind = "string", default = "" },
	},
	transform = transform,
}

--[[
getClassSignature(tableNode: AstState): string
much trickier; we kinda need to scrape an entire file for this, and can't just extract from the initial declaration...
hmmmm
]]
