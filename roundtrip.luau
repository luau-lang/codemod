local parser = require("@std/syntax/parser")
local printer = require("@std/syntax/printer")

return function(ctx)
	local result = parser.parse(ctx.source)
	return printer.printFile(result)
end
