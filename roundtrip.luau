local parser = require("@batteries/syntax/parser")
local printer = require("@batteries/syntax/printer")

return function(ctx)
	local result = parser.parsefile(ctx.source)
	return printer.printfile(result)
end
