local syntax = require("@std/syntax")
local sourcemap = require("./sourcemap")

export type ModuleName = string

export type ModuleInfo = {
	moduleName: string,
}

export type Resolver = (context: ModuleInfo?, expression: syntax.CstExpr) -> ModuleInfo?

local function resolveStringRequire(path: string, from: ModuleName): ModuleInfo?
	print("TODO: support string requires")
	return nil
end

local function getParentPath(path: string)
	local parts = string.split(path, "/")
	assert(#parts > 1)
	table.remove(parts)
	return table.concat(parts, "/")
end

local function findAncestorPath(path: string, ancestorName: string): string?
	local parts = string.split(path, "/")

	while #parts > 0 do
		table.remove(parts)
		if parts[#parts] == ancestorName then
			return table.concat(parts, "/")
		end
	end

	return nil
end

--- Creates a standard file resolver for require resolution.
--- Supports string requires, including aliases (based off luaurc), as well as Roblox style requires
local function createFileResolver(sourcemapData: sourcemap.SourcemapData?)
	return function(context: ModuleInfo?, expression: syntax.CstExpr): ModuleInfo?
		if context == nil then
			return nil
		end

		if expression.tag == "string" then
			return resolveStringRequire(expression.value.text, context.moduleName)
		elseif expression.tag == "global" then
			local globalName = expression.name.text
			if globalName == "game" then
				return { moduleName = "game" }
			elseif globalName == "script" then
				local virtualPath = if sourcemap.isVirtualPath(context.moduleName)
					then context.moduleName
					else sourcemap.realPathToVirtualPath(
						assert(sourcemapData, "sourcemapData == nil"),
						context.moduleName
					)

				if virtualPath then
					return { moduleName = virtualPath }
				end
			end
		elseif expression.tag == "indexname" then
			local indexName = expression.index.text
			if indexName == "Parent" then
				return { moduleName = getParentPath(context.moduleName) }
			else
				return { moduleName = `{context.moduleName}/{indexName}` }
			end
		elseif expression.tag == "index" then
			if expression.index.tag == "string" then
				local indexName = expression.index.value.text
				if indexName == "Parent" then
					return { moduleName = getParentPath(context.moduleName) }
				else
					return { moduleName = `{context.moduleName}/{indexName}` }
				end
			end
		elseif expression.tag == "call" and expression.self and #expression.arguments >= 1 then
			assert(expression.func.tag == "indexname")
			local functionName = expression.func.index.text

			local firstArgument = expression.arguments[1]
			if firstArgument.tag == "string" then
				local argument = firstArgument.value.text

				if functionName == "GetService" then
					assert(context.moduleName == "game")
					return { moduleName = `{context.moduleName}/{argument}` }
				elseif functionName == "WaitForChild" then
					return { moduleName = `{context.moduleName}/{argument}` }
				elseif functionName == "FindFirstChild" and #expression.arguments == 1 then
					return { moduleName = `{context.moduleName}/{argument}` }
				elseif functionName == "FindFirstAncestor" then
					local ancestorPath = findAncestorPath(context.moduleName, argument)
					if ancestorPath then
						return { moduleName = ancestorPath }
					end
				end
			end
		end
		return nil
	end
end

return {
	createFileResolver = createFileResolver,
}
