local fs = require("@lute/fs")
local luau = require("@lute/luau")
local parser = require("@batteries/syntax/parser")

local isFlagModule = require("./matchers/isFlagModule")

local isRequire = require("../require-resolver/isRequire")
local fileResolver = require("../require-resolver/resolver")
local requireTracer = require("../require-resolver/tracer")
local sourcemap = require("../require-resolver/sourcemap")
local isFlagAccess = require("./matchers/isFlagAccess")
local isFlagFunction = require("./matchers/isFlagFunction")

export type ModuleInfo = {
	isFlagModule: boolean,
	tableData: TableData?,
}

--- Global cache of 'file path' -> moduleInfo mapping
local FlagModuleFileCache: { [string]: ModuleInfo } = {}

-- TODO: duplicated from TrackReferences.luau
type TableData = {
	flagProperties: { string },
	nestedTableData: { [string]: TableData },
}

local function resolveRotrieverPackageLink(
	body: luau.AstStatBlock,
	flagName: string,
	requireInfo: requireTracer.RequireTracerResult,
	sourcemapData: sourcemap.SourcemapData?,
	repo: string?
): ModuleInfo?
	-- Follow through rotriever package links
	-- For now, we hardcode the detection and resolution specifically for these links.
	-- Package links are specifically of the form:

	--	local Index = ...
	-- 	local Package = require(Index[...])
	--	return Package

	if #body.statements ~= 3 then
		return nil
	end

	local lastStmt = body.statements[3]
	if lastStmt.tag ~= "return" then
		return nil
	end

	if #lastStmt.expressions ~= 1 then
		return nil
	end

	local expression = lastStmt.expressions[1].node

	if expression.tag ~= "local" or expression.token.text ~= "Package" then
		return nil
	end

	local packageLink = body.statements[2]
	if
		packageLink.tag ~= "local"
		or #packageLink.variables ~= 1
		or #packageLink.values ~= 1
		or packageLink.variables[1].node.name.text ~= "Package"
	then
		return nil
	end

	local linkedPackageCall = packageLink.values[1].node
	if linkedPackageCall.tag ~= "call" then
		return nil
	end

	return getModuleInfo(linkedPackageCall, flagName, requireInfo, sourcemapData, repo)
end

local function getModuleTableInfo(
	body: luau.AstStatBlock,
	flagName: string,
	requireInfo: requireTracer.RequireTracerResult,
	sourcemapData: sourcemap.SourcemapData?,
	repo: string?
): TableData?
	if #body.statements == 0 then
		return nil
	end

	local lastStmt = body.statements[#body.statements]
	if lastStmt.tag ~= "return" then
		return nil
	end

	if #lastStmt.expressions ~= 1 then
		return nil
	end

	local expression = lastStmt.expressions[1].node
	if expression.tag ~= "table" then
		return nil
	end

	local tableData = { flagProperties = {}, nestedTableData = {} }

	for _, entry in expression.entries do
		if entry.kind == "record" then
			if isFlagFunction.isExprFlagFunction(entry.value, flagName, repo) then
				table.insert(tableData.flagProperties, entry.key.text)
			elseif isFlagAccess(entry.value, flagName, repo) then
				table.insert(tableData.flagProperties, entry.key.text)
			elseif isRequire(entry.value) then
				local moduleInfo = getModuleInfo(entry.value, flagName, requireInfo, sourcemapData, repo)
				if moduleInfo then
					if moduleInfo.isFlagModule then
						table.insert(tableData.flagProperties, entry.key.text)
					elseif moduleInfo.tableData then
						tableData.nestedTableData[entry.key.text] = moduleInfo.tableData
					end
				end
			end
		end
	end

	return tableData
end

function getModuleInfo(
	expression: luau.AstExpr,
	flagName: string,
	requireInfo: requireTracer.RequireTracerResult,
	sourcemapData: sourcemap.SourcemapData?,
	repo: string?
): ModuleInfo?
	if not isRequire(expression) then
		return nil
	end

	assert(expression.tag == "call")

	local requireCallInfo = requireInfo[expression]
	if not requireCallInfo then
		return nil
	end

	local requirePath = requireCallInfo.moduleName
	if sourcemap.isVirtualPath(requirePath) then
		assert(sourcemapData, "Encountered a virtual path, but no sourcemap information was available")
		requirePath = sourcemap.virtualPathToRealPath(sourcemapData, requirePath)
	end

	if not requirePath then
		return nil
	end

	if FlagModuleFileCache[requirePath] ~= nil then
		return FlagModuleFileCache[requirePath]
	end

	local contents = fs.readfiletostring(requirePath)
	local block = parser.parse(contents)
	assert(block)

	local result: ModuleInfo = { isFlagModule = false, tableData = nil }
	if isFlagModule(block, flagName, repo) then
		result.isFlagModule = true
	else
		requireInfo = requireTracer.traceRequires(block, requirePath, fileResolver.createFileResolver(sourcemapData))

		local packageLink = resolveRotrieverPackageLink(block, flagName, requireInfo, sourcemapData, repo)
		if packageLink then
			result = packageLink
		else
			local tableData = getModuleTableInfo(block, flagName, requireInfo, sourcemapData, repo)
			if tableData then
				result.tableData = tableData
			end
		end
	end

	FlagModuleFileCache[requirePath] = result
	return result
end

return getModuleInfo
