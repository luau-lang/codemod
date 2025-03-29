local fs = require("@lute/fs")
local types = require("./types")

local DRY_RUN = false

local function extend<T>(tbl: { T }, other: { T })
	for _, entry in other do
		table.insert(tbl, entry)
	end
end

local function endsWith(str: string, suffix: string): boolean
	return str:sub(-#suffix) == suffix
end

local function traverseDirectoryRecursive(path: string): { string }
	local results = {}

	for _, entry in fs.listdir(path) do
		local fullPath = `{path}/{entry.name}` -- TODO: os specific path join?

		if entry.type == "dir" then
			extend(results, traverseDirectoryRecursive(fullPath))
		else
			-- TODO: allow customisation of the filter when traversing a directory. e.g., globs? file endings? ignore paths?
			if endsWith(entry.name, ".luau") or endsWith(entry.name, ".lua") then
				table.insert(results, fullPath)
			end
		end
	end

	return results
end

local function getSourceFiles(paths: { string })
	local files = {}

	for _, path in paths do
		if fs.type(path) == "dir" then
			extend(files, traverseDirectoryRecursive(path))
		else
			table.insert(files, path)
		end
	end

	return files
end

local function loadTransformer(path: string)
	local success, loaded = pcall(require, path)
	assert(success, `{path} failed to require: {loaded}`)
	assert(loaded, `{path} is missing a return`)
	assert(typeof(loaded) == "function", `{path} must return a function`)

	return loaded
end

local function applyTransform(transform: (types.Context) -> string, paths: { string })
	for _, path in paths do
		print(`Applying to {path}`)

		local source = fs.readfiletostring(path)

		local ctx = {
			path = path,
			source = source,
		}

		-- TODO: should we wrap in pcall? For now we don't do this to preserve stack trace
		local result = transform(ctx)
		-- local success, result = pcall(transform, ctx)
		-- if not success then
		-- 	error(`Failed to apply to {path}: {result}`)
		-- end

		assert(typeof(result) == "string", `Transformed expected to return string, but got {typeof(result)}`)

		if not DRY_RUN then
			fs.writestringtofile(path, result)
		end
	end
end

local function main(...: string)
	local arguments = { ... }

	-- TODO: replace with proper CLI system
	-- For now, first argument is the transformer script, whilst the rest are files to apply it on

	if #arguments < 2 then
		error("Usage: main.luau <transformer script> <files...>")
	end

	local transformer = table.remove(arguments, 1)
	assert(transformer, "ASSERTION FAILED: transformer ~= nil")

	local files = getSourceFiles(arguments)
	if #files == 0 then
		error("error: no source files provided")
	end

	print(`Loading transformer '{transformer}'`)
	local transformerFunction = loadTransformer(transformer)

	print("Applying transformer")
	applyTransform(transformerFunction, files)
end

main(...)
