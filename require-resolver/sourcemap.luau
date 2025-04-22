local fs = require("@lute/fs")
local json = require("@batteries/json")

export type SourcemapNode = {
	name: string,
	className: string,
	filePaths: { string }?,
	children: { SourcemapNode }?,
}

export type SourcemapData = {
	root: SourcemapNode,
	sourcemapLocation: string,
	realToVirtualPathMap: { [string]: string },
	virtualToRealPathMap: { [string]: string },
}

local function startsWith(str: string, prefix: string): boolean
	if #prefix > #str then
		return false
	end

	return str:sub(1, #prefix) == prefix
end

local function endsWith(str: string, suffix: string): boolean
	return str:sub(-#suffix) == suffix
end

local function isAbsolute(path: string)
	-- TODO: use a proper path library here
	return startsWith(path, "/")
end

local function getRealPath(data: SourcemapData, node: SourcemapNode): string?
	local scriptFilePath = nil

	if node.filePaths then
		for _, path in node.filePaths do
			if endsWith(path, ".luau") or endsWith(path, ".lua") then
				scriptFilePath = path
				break
			end
		end
	end

	if not scriptFilePath then
		return nil
	end

	if isAbsolute(scriptFilePath) then
		return scriptFilePath
	else
		-- TODO: use a proper path library here
		return `{data.sourcemapLocation}/{scriptFilePath}`
	end
end

local function isVirtualPath(path): boolean
	return path == "game" or path == "ProjectRoot" or startsWith(path, "game/") or startsWith(path, "ProjectRoot/")
end

local function realPathToVirtualPath(data: SourcemapData, path: string): string?
	return data.realToVirtualPathMap[path]
end

local function virtualPathToRealPath(data: SourcemapData, path: string): string?
	return data.virtualToRealPathMap[path]
end

local function writePaths(data: SourcemapData, node: SourcemapNode, virtualPath: string)
	local realPath = getRealPath(data, node)

	if realPath then
		data.realToVirtualPathMap[realPath] = virtualPath
		data.virtualToRealPathMap[virtualPath] = realPath
	end

	if node.children then
		for _, child in node.children do
			writePaths(data, child, `{virtualPath}/{child.name}`)
		end
	end
end

local function parseSourcemap(path: string): SourcemapData
	local contents = fs.readfiletostring(path)
	local root = json.deserialize(contents) :: SourcemapNode
	local data: SourcemapData = {
		root = root,
		sourcemapLocation = path,
		realToVirtualPathMap = {},
		virtualToRealPathMap = {},
	}

	local base = if root.className == "DataModel" then "game" else "ProjectRoot"
	writePaths(data, root, base)

	return data
end

return {
	parseSourcemap = parseSourcemap,
	isVirtualPath = isVirtualPath,
	realPathToVirtualPath = realPathToVirtualPath,
	virtualPathToRealPath = virtualPathToRealPath,
}
