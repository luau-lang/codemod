local fs = require("@lute/fs")
local parser = require("@batteries/syntax/parser")
local T = require("@batteries/syntax/ast_types")

local isFlagModule = require("./isFlagModule")

local isRequire = require("../../require-resolver/isRequire")
local requireTracer = require("../../require-resolver/tracer")
local sourcemap = require("../../require-resolver/sourcemap")

--- Global cache of 'file path' -> 'is flag module' mapping
local FlagModuleFileCache: { [string]: boolean } = {}

local function isRequiredFlagModule(
	expression: T.AstExpr,
	flagName: string,
	requireInfo: requireTracer.RequireTracerResult,
	sourcemapData: sourcemap.SourcemapData?
)
	if not isRequire(expression) then
		return false
	end

	assert(expression.tag == "call")

	local requireCallInfo = requireInfo[expression]
	if not requireCallInfo then
		return false
	end

	local requirePath = requireCallInfo.moduleName
	if sourcemap.isVirtualPath(requirePath) then
		assert(sourcemapData, "Encountered a virtual path, but no sourcemap information was available")
		requirePath = sourcemap.virtualPathToRealPath(sourcemapData, requirePath)
	end

	if not requirePath then
		return false
	end

	if FlagModuleFileCache[requirePath] ~= nil then
		return FlagModuleFileCache[requirePath]
	end

	local contents = fs.readfiletostring(requirePath)
	local block = parser.parse(contents)
	assert(block)

	local isFlagModuleResult = isFlagModule(block, flagName)
	FlagModuleFileCache[requirePath] = isFlagModuleResult
	return isFlagModuleResult
end

return isRequiredFlagModule
