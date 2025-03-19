local parser = require("@batteries/syntax/parser")
local printer = require("@batteries/syntax/printer")

return function(ctx)
	local block = parser.parse(ctx.source)

	-- TODO: this is cheating! we should handle trivia on the EOF properly
	return printer.print(block) .. "\n"
end
