local parser = require("@std/syntax/parser")
local printer = require("@std/syntax/printer")

return function(ctx)
	local result = parser.parsefile(ctx.source)
	return printer.printfile(result)
end
