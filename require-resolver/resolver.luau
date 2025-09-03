local luau = require("@lute/luau")
local sourcemap = require("./sourcemap")

export type ModuleName = string

export type ModuleInfo = {
	moduleName: string,
}

export type Resolver = (context: ModuleInfo?, expression: luau.AstExpr) -> ModuleInfo?

local function resolveAliasRequire(path: string, aliasMap: { [string]: string }, isInit: boolean): string | nil
	-- to resolve "@" syntax, we need to use alias map from .luaurc
	-- @self is same as ".", indicates at same level
	-- rest of aliases need to be resolved via .luaurc
	-- if contains @, resolve, else return as is
	if path:find("@") then
		if aliasMap then
			local alias = path:gsub("@", "")
			if alias == "self" then
				return "."
			elseif aliasMap[alias] then
				return aliasMap[alias]
			end
			return nil
		end
	end
	-- if from init file, "." is actually ".." in absolute path
	if isInit and path == "." then
		return ".."
	end
	return path
end

local function resolveStringRequire(path: string, from: ModuleName, aliasMap: { [string]: string }): ModuleInfo?
	-- path is relative to "from", indicates the file in which we are resolving requires
	local split = from:split("/")
	local isInit = split[#split] == "init.lua" or split[#split] == "init.luau"
	table.remove(split, #split)
	local parent = table.concat(split, "/")
	-- resolve each piece of the required path
	local childPath = path:split("/")
	for ind, entry in childPath do
		local resolved = resolveAliasRequire(entry, aliasMap, isInit)
		if not resolved then
			return nil
		end
		childPath[ind] = resolved
	end
	-- alias paths are scoped at project root, so don't concat with parent
	local completeChildPath = table.concat(childPath, "/")
	return {
		moduleName = if path:find("@") then completeChildPath else `{parent}/{completeChildPath}`,
	}
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
local function createFileResolver(sourcemapData: sourcemap.SourcemapData?, aliasMap: { [string]: string }?)
	return function(context: ModuleInfo?, expression: luau.AstExpr): ModuleInfo?
		if context == nil then
			print("missing context")
			return nil
		end

		if expression.tag == "string" then
			return resolveStringRequire(expression.text, context.moduleName, aliasMap or {})
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
				local indexName = expression.index.text
				if indexName == "Parent" then
					return { moduleName = getParentPath(context.moduleName) }
				else
					return { moduleName = `{context.moduleName}/{indexName}` }
				end
			end
		elseif expression.tag == "call" and expression.self and #expression.arguments >= 1 then
			assert(expression.func.tag == "indexname")
			local functionName = expression.func.index.text

			if expression.arguments[1].node.tag == "string" then
				local argument = expression.arguments[1].node.text

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
