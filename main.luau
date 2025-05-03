local fs = require("@lute/fs")

local arguments = require("./lib/arguments")
local types = require("./types")

local function exhaustiveMatch(value: never): never
	error(`Unknown value in exhaustive match: {value}`)
end

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

local function getSourceFiles(paths: { string }): { string }
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

local function loadCodemod(path: string): types.Codemod
	local success, loaded = pcall(require, path)
	assert(success, `{path} failed to require: {loaded}`)
	assert(loaded, `{path} is missing a return`)

	if typeof(loaded) == "function" then
		local codemod = {}
		codemod.transform = loaded
		return codemod :: types.Codemod -- FIXME: Luau
	elseif typeof(loaded) == "table" then
		assert(typeof(loaded.transform) == "function", `{path} must contain a 'transform' property of type function`)
		if loaded.options then
			assert(typeof(loaded.options) == "table", `Expected return of {path}.options to be a table`)
			for _, option in loaded.options do
				assert(typeof(option.name) == "string", `Expected option.name to be a string`)
				assert(
					option.kind == "string" or option.kind == "boolean",
					`Expected option.kind to be either 'string' or 'boolean', got {option.kind}`
				)
				-- TODO: ensure option.name is not a built-in option
			end
		end
		return loaded
	else
		error(`Expected '{path}' to return a function or table, got {typeof(loaded)}`)
	end
end

local function processCodemodOptions(codemod: types.Codemod, options: { [string]: string }): { [string]: any }
	if codemod.options == nil then
		return table.freeze({})
	end

	local processedOptions: { [string]: string | boolean } = {}

	for _, option in codemod.options do
		local value = options[option.name]
		if value then
			if option.kind == "boolean" then
				local lowered = value:lower()
				assert(
					lowered == "true" or lowered == "false",
					`Option '--{option.name}' expects a boolean value 'true' or 'false'`
				)
				processedOptions[option.name] = lowered == "true"
			elseif option.kind == "string" then
				processedOptions[option.name] = value
			else
				exhaustiveMatch(option.kind)
			end
		else
			assert(option.default ~= nil, `Missing required option '--{option.name}'`)
			processedOptions[option.name] = option.default
		end
	end

	return table.freeze(processedOptions)
end

local function applyCodemod(
	codemod: types.Codemod,
	paths: { string },
	options: { [string]: string | boolean },
	dryRun: boolean
)
	local deletedPaths = {}

	for _, path in paths do
		print(`Applying to {path}`)

		local source = fs.readfiletostring(path)

		local ctx = {
			path = path,
			source = source,
			options = options,
		}

		-- TODO: should we wrap in pcall? For now we don't do this to preserve stack trace
		local result = codemod.transform(ctx)
		-- local success, result = pcall(transform, ctx)
		-- if not success then
		-- 	error(`Failed to apply to {path}: {result}`)
		-- end

		assert(typeof(result) == "string", `Transformed expected to return string, but got {typeof(result)}`)

		if result == types.DELETION_MARKER then
			print(`Marking {path} for deletion`)
			table.insert(deletedPaths, path)
		elseif not dryRun then
			fs.writestringtofile(path, result)
		end
	end

	if not dryRun then
		for _, path in deletedPaths do
			print(`Deleting {path}`)
			fs.remove(path)
		end
	end
end

local function main(...: string)
	local args = arguments.parse({ ... })

	if args.dryRun then
		print("Executing in dry run mode")
	end

	print(`Loading codemod '{args.codemodPath}'`)
	local codemod = loadCodemod(args.codemodPath)

	local files = getSourceFiles(args.filePaths)
	if #files == 0 then
		error("error: no source files provided")
	end

	print("Processing codemod options")
	local codemodOptions = processCodemodOptions(codemod, args.codemodOptions)

	print("Applying codemod")
	applyCodemod(codemod, files, codemodOptions, args.dryRun)
end

main(...)
