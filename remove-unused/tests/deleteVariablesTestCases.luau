local testCases = {
	--- Category 1: Basic "Clean Sweep" Deletions
	--- Tests the removal of entire statements.

	-- Deleting a single unused variable statement
	[ [[
    local a = 1
    local unused = 2
    local b = 3
    ]] ] = [[
    ]],

	-- Deleting an unused local function
	[ [[
    -- This function will be called
    local function keep_me()
        print("hello")
    end

    local function unused_func()
        local x = 1
        return x
    end

    keep_me()
    ]] ] = [[
    -- This function will be called
    local function keep_me()
        print("hello")
    end

    
    keep_me()
    ]],

	--- Category 2: "Surgical Strike" on Multi-Variable Declarations
	--- This is the most complex category, testing the removal of individual
	--- variables from a single `local` statement.

	-- Deleting the middle variable
	[ [[
    local a, unused, b = 1, 2, 3
    print(a, b)
    ]] ] = [[
    local a, b = 1, 3
    print(a, b)
    ]],

	-- Deleting the first variable
	[ [[
    local unused, a, b = 1, 2, 3
    print(a, b)
    ]] ] = [[
    local a, b = 2, 3
    print(a, b)
    ]],

	-- Deleting the last variable
	[ [[
    local a, b, unused = 1, 2, 3
    print(a, b)
    ]] ] = [[
    local a, b = 1, 2
    print(a, b)
    ]],

	-- Deleting multiple, non-contiguous variables
	[ [[
    local a, unused1, b, unused2, c = "a", "u1", "b", "u2", "c"
    print(a, b, c)
    ]] ] = [[
    local a, b, c = "a", "b", "c"
    print(a, b, c)
    ]],

	-- Deleting all variables in a multi-variable declaration
	[ [[
    local a = "keep"
    local unused1, unused2 = 1, 2
    print(a)
    ]] ] = [[
    local a = "keep"
    print(a)
    ]],

	--- Category 3: Comment and Trivia Preservation
	--- Tests that comments and whitespace are handled gracefully.

	-- Deleting a variable with a trailing comment
	[ [[
    local unused = 1 -- This comment is tied to the unused var but should be preserved.
    local a = 2
    print(a)
    ]] ] = [[
    -- This comment is tied to the unused var but should be preserved.
    local a = 2
    print(a)
    ]],

	-- Deleting from a multi-line declaration with comments
	[ [[
    local a,      -- Comment for A, should be kept
        unused, -- Comment for unused, should be removed
        b       -- Comment for B, should be kept
        = 1, 2, 3
    print(a,b)
    ]] ] = [[
    local a,      -- Comment for A, should be kept
        b       -- Comment for B, should be kept
        = 1, 3
    print(a,b)
    ]],

	--- Category 4: Scope and Safety Checks
	--- Confirms the deletion pass correctly interacts with the rules from Pass 1.

	-- Scope integrity check (deleting outer `x`, keeping inner `x`)
	[ [[
    local x = "outer and unused"
    for i=1, 2 do
        local x = "inner and used"
        print(x)
    end

    ]] ] = [[
    for i=1, 2 do
        local x = "inner and used"
        print(x)
    end

    ]],

	-- "Do No Harm" Test: A file with linter-ignored variables should not be changed
	[ [[-- This file should be identical before and after, as nothing should be deleted.
    local function process(unusedParam)
        for i = 1, 5 do
            -- i is ignored
        end
    end

    local _, _result = pcall(process, 123) -- _ is ignored
    ]] ] = [[-- This file should be identical before and after, as nothing should be deleted.
    local function process(unusedParam)
        for i = 1, 5 do
            -- i is ignored
        end
    end

    local _, _result = pcall(process, 123) -- _ is ignored
    ]],

	-- Referencing declared vars as tables values
	[ [[
        local x = 1
        local function a()
            return 2
        end
        return {
            ['m'] = a(),
            ['b'] = x,
            ['c'] = a,
        }
    ]] ] = [[
        local x = 1
        local function a()
            return 2
        end
        return {
            ['m'] = a(),
            ['b'] = x,
            ['c'] = a,
        }
    ]],

	-- Vars whose only use is in an unused var (multiple pass removal)
	[ [[
        local x = 1
        local a = x
        function b()
            return a
        end
        local c = b()
    ]] ] = [[

    ]], -- should all be removed

	-- Declaration of n vars to <n val (all vars should be kept since removal is not safe)
	[ [[
        local function two()
            return 1, 2
        end
        local x, y = two()
    ]] ] = [[
        local function two()
            return 1, 2
        end
        local x, y = two()
     ]],

	-- edge case: global function is used before it is defined; still needs to be picked up as use
	[ [[
        local a = b()
        function b()
            return 1
        end
        print(a)
     ]] ] = [[
        local a = b()
        function b()
            return 1
        end
        print(a)
    ]],

	-- appending preserved trivia to various statements
	[ [[
        -- preserve me
        local a = 1 -- preserve me too
        export type t = { string }
        -- stay!
        function p()
            return 1
        end -- pls stay!
        function b()
            return "nice"
        end
        print(b())
    ]] ] = [[
        -- preserve me
        -- preserve me too
        export type t = { string }
        -- stay!
        -- pls stay!
        function b()
            return "nice"
        end
        print(b()) 
    ]],
}

return testCases
