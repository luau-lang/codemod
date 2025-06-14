local dependencies = require(game.Dependencies)
local SharedFlags = dependencies.SharedFlags
local FFlagFlagName = SharedFlags.FFlagFlagName

if FFlagFlagName then
	print("Flags on!")
else
	print("Flags off!")
end
