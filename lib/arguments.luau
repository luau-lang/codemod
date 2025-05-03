export type Config = {
	--- Path to the codemod module to execute
	codemodPath: string,
	--- Configuration flags to pass to the codemod
	codemodOptions: { [string]: string },
	--- List of file paths to process
	--- Note: no directory traversal or filtering has been applied on this list
	filePaths: { string },
}

local function startsWith(str: string, prefix: string): boolean
	if #prefix > #str then
		return false
	end

	return str:sub(1, #prefix) == prefix
end

local function removePrefix(str: string, prefix: string): string
	if not startsWith(str, prefix) then
		return str
	end

	return str:sub(#prefix + 1)
end

local function parse(arguments: { string }): Config
	-- TODO: replace with proper CLI system
	-- For now, first argument is the transformer script, whilst the rest are either flags or files to apply it on

	if #arguments < 2 then
		error("Usage: main.luau <transformer script> [options...] <files...>")
	end

	local codemodPath: string? = nil
	local codemodOptions = {}
	local filePaths = {}

	local i = 1
	while i <= #arguments do
		local argument = arguments[i]

		if startsWith(argument, "--") then
			local name = removePrefix(argument, "--")
			i += 1
			assert(i <= #arguments, `Missing value for '{name}'`)
			local value = arguments[i]

			if codemodPath == nil then
				-- Options before the codemod file are parsed as options for the tool itself
				error("TODO")
			else
				codemodOptions[name] = value
			end
		else
			if codemodPath == nil then
				codemodPath = argument
			else
				table.insert(filePaths, argument)
			end
		end

		i += 1
	end

	assert(codemodPath, "ASSERTION FAILED: codemodPath ~= nil")

	return {
		codemodPath = codemodPath,
		codemodOptions = codemodOptions,
		filePaths = filePaths,
	}
end

return {
	parse = parse,
}
