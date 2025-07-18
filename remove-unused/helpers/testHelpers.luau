--[[
    Module containing various helper functions for unit tests and/or debugging
]]

local function printTable(table, indent: number, result: boolean?)
	for k, v in pairs(table) do
		local indentString = string.rep("  ", indent)
		if not result then
			if type(v) == "table" and not tostring(k):find("Trivia") then
				print(indentString .. tostring(k) .. ": (table)")
				printTable(v, indent + 1, false)
			else
				print(indentString .. tostring(k) .. ": " .. tostring(v))
			end
		else
			if type(k) == "table" then
				print(
					indentString
						.. tostring((k.name and (k.name.text or k.text)) or k)
						.. ", line "
						.. tostring(if k.name and k.name.position then k.name.position.line else "")
						.. ": "
						.. tostring(v)
				)
			else
				print(
					indentString
						.. tostring((v.name and (v.name.text or v.text)) or v)
						.. ", line "
						.. tostring(if v.name and v.name.position then v.name.position.line else "")
				)
			end
		end
	end
end

--[[
    Normalizes a source code string to make comparisons reliable.
    Essentially just used to make sure the formatting of our test cases doesn't affect the results we care about.
]]
local function normalizeString(s)
	if not s then
		return ""
	end

	-- 1. Unify line endings to LF (\n)
	s = s:gsub("\r\n", "\n")
	-- 2. Unify indentation to use 4 spaces instead of tabs
	s = s:gsub("\t", "    ")
	-- 3. Replace non-breaking spaces (and other weird Unicode spaces)
	--    with standard spaces. The byte representation for non-breaking space
	--    in UTF-8 is 194, 160.
	s = s:gsub("\194\160", " ")
	-- 4. (Optional but recommended) Trim trailing whitespace from each line
	s = s:gsub("[ \t]+(\n)", "\n")
	-- 5. (Optional but recommended) Trim leading whitespace from each line
	--    but only for comment lines (lines that start with optional whitespace then --)
	s = s:gsub("\n[ \t]+", "\n")
	-- 6. Trim leading/trailing whitespace from block
	s = s:match("^%s*(.-)%s*$")

	return s
end

return {
	normalizeString = normalizeString,
	printTable = printTable,
}
