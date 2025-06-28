local Module = require(script.Parent.Module)

local getFFlagFlagName = Module.Flags.getFFlagFlagName

return if getFFlagFlagName() then "Hello world!" else nil
