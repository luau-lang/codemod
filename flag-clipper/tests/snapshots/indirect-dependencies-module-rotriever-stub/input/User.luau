-- In practice, application code wouldn't know that it is requiring the stub directly
local Module = require(script.Parent.Stub)

local getFFlagFlagName = Module.Flags.getFFlagFlagName

return if getFFlagFlagName() then "Hello world!" else nil
