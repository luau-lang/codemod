local testCases = {
	-- Basic Unused Variable
	[ [[
        local unusedVar = 10
    ]] ] = { ["unusedVar_0"] = 0 },

	-- Multiple Variable Declaration
	[ [[
        local x, y = 1, grow-2
    ]] ] = { ["x_0"] = 0, ["y_0"] = 0 },

	-- Basic Used Variable
	[ [[
        local usedVar = 20
        print(usedVar)
    ]] ] = { ["usedVar_0"] = 1 },

	-- Variable Used in Simple Assignment (User's Rule: assign-to does not increment)
	-- 'x = 2' uses '2' but not 'x' as a read.
	[ [[
        local x = 1
        x = 2
    ]] ] = { ["x_0"] = 0 },

	-- Variable Used in Compound Assignment (Linter's Rule: *is* a use)
	-- 'y += 10' uses 'y' (reads and writes it).
	[ [[
        local y = 5
        y += 10
    ]] ] = { ["y_0"] = 1 },

	-- Variable Used in Expression and Simple Assignment
	-- 'a = z' uses 'z' as a read. 'z = 2' uses '2' but not 'z' as a read.
	[ [[
        local z = 1
        local a = z
        z = 2
    ]] ] = { ["z_0"] = 1, ["a_1"] = 0 },

	-- Function Parameter Used (NOT tracked for removal by linter's rule)
	-- 'param' is used in 'print(param)' but not counted for removal.
	[ [[
        local function foo(param)
            print(param)
        end
        foo(1)
    ]] ] = { ["foo_0"] = 1 }, -- Only 'foo' (the function itself) is tracked and used

	-- Function Parameter Unused (NOT tracked for removal by linter's rule)
	-- 'unusedParam' is not used, but is a parameter, so not tracked. 'temp' is unused and tracked.
	[ [[
        local function bar(unusedParam)
            local temp = 1
        end
        bar(2)
    ]] ] = { ["temp_1"] = 0, ["bar_0"] = 1 },

	-- Nested Scope & Shadowing
	-- 'x_outer' and 'x_inner' are distinct variables, each used once in their respective scopes.
	[ [[
        local x = 1 -- line 0
        local function nested() -- line 1
            local x = 2 -- line 2
            print(x) -- line 3
        end -- line 4
        nested() -- line 6
    ]] ] = { ["x_0"] = 0, ["x_2"] = 1, ["nested_1"] = 1 },

	-- `do..end` Block Scope
	-- 'b' is local to the 'do' block, 'a' is outside. Both are used.
	[ [[
        local a = 1 -- line 0
        do -- line 1
            local b = 2 -- line 2
            print(b) -- line 3
        end -- line 4
        print(a) -- line 5
    ]] ] = { ["a_0"] = 1, ["b_2"] = 1 },

	-- `for` Numeric Loop Variable (NOT tracked for removal by linter's rule)
	-- 'i' is used, but not tracked. 'total' is tracked and used.
	[ [[
        local total = 0 -- line 0
        for i = 1, 5 do -- line 1
            total = total + i
        end
    ]] ] = { ["total_0"] = 1 },

	-- `for in` Loop Variables (NOT tracked for removal by linter's rule)
	-- 'key' and 'val' are used, but not tracked. 'data' is tracked and used.
	[ [[
        local data = {a=1, b=2} -- line 0
        for key, val in pairs(data) do -- line 1
            print(key)
        end
    ]] ] = { ["data_0"] = 1 },

	-- Interpolated String Reference
	-- 'name' is referenced inside the interpolated string.
	[ [[
        local name = "Alice" -- line 0
        print(`Hello, {name}!`) -- line 1
    ]] ] = { ["name_0"] = 1 },

	-- Type Reference (Qualified Name Annotation - uses scope stack for 'Lib' resolution)
	-- 'Lib' is a local variable it's used in its declaration and in the type annotation.
	-- [ [[
	--     local Lib = {} -- Simulates local variable from require
	--     type Lib.MyType = { field: string }
	--     local val: Lib.MyType = { field = "test" }
	-- ]] ] = { ["Lib"] = 2, ["val"] = 0 },

	-- -- Type Cast (Qualified Name Cast - uses scope stack for 'Helpers' resolution)
	-- -- 'Helpers' is a local variable it's used in its declaration and in the type cast.
	-- [ [[
	--     local Helpers = {} -- Simulates local variable from require
	--     type Helpers.CastType = number
	--     local item = { [1] } :: Helpers.CastType
	-- ]] ] = { ["Helpers"] = 2, ["item"] = 0 },
	-- I'm not sure how to define this syntax without actual requires...

	-- Underscore `_` Variable (NOT tracked for removal by linter's rule)
	-- '_' is explicitly not tracked for removal. 'value' is used.
	[ [[
        local _, value = 1, 2 -- line 0
        print(value) -- line 1
    ]] ] = { ["value_0"] = 1 },

	-- Multiple Uses of a Variable
	-- 'counter' is used in `counter + 1` (read) and `print(counter)` (read).
	[ [[
        local counter = 0 -- line 0
        counter = counter + 1 -- line 1
        print(counter) -- line 2
    ]] ] = { ["counter_0"] = 2 },

	-- Variable with No References (but complex initialization)
	-- 'complex' is used in 'unused = complex' (read). 'unused' is unused.
	[ [[
        local complex = (1 + 2) * 3 -- line 0
        local unused = complex -- line 1
    ]] ] = { ["complex_0"] = 1, ["unused_1"] = 0 },

	-- Nested Anonymous Function (closure over 'x')
	-- 'run' is used to call the outer function. 'x' is closed over and used by the inner function.
	[ [[
        local run = function() -- line 0
            local x = 1 -- line 1
            return function() print(x) end -- line 2
        end -- line 3
        run()() -- line 4
    ]] ] = { ["run_0"] = 1, ["x_1"] = 1 },

	-- Variables with identical names in different scopes (distinct AstLocal objects)
	-- 'a' is unused. 'fn1' and 'fn2' are functions, each called once.
	-- Each 'b' is local to its function, and each is used once.
	[ [[
        local a = 1 -- line 0
        local function fn1() -- line 1
            local b = 10 -- line 2 (b in fn1 scope)
            print(b) -- line 3
        end -- line 4
        local function fn2() -- line 5
            local b = 20 -- line 6 (b in fn2 scope)
            print(b) -- line 7
        end -- line 8
        fn1() -- line 9
        fn2() -- line 10
    ]] ] = { ["a_0"] = 0, ["fn1_1"] = 1, ["b_2"] = 1, ["fn2_5"] = 1, ["b_6"] = 1 },
	-- Note: For the 'b' variables, your 'variableInfo' map will correctly distinguish them by their
	-- unique AstLocal pointer. This output format ('b_2', 'b_6') explicitly shows that distinct
	-- variables are expected to be counted, even if their names are the same.

	-- Variables used in table literals/access
	-- 'myTable' is used in declaration, 'myTable.field = 10', 'val = myTable.field', and 'print(myTable.field)'.
	-- 'val' is unused (as its only reference is an assignment target).
	[ [[
        local myTable = { ["test"] = 1 } -- line 0
        myTable.field = 10 -- line 1
        local val = myTable.field -- line 2
        print(myTable.field) -- line 3
        local t = "test"
        print(`hmm {myTable[t]}`)
    ]] ] = { ["myTable_0"] = 4, ["val_2"] = 0, ["t_4"] = 1 },

	-- Complex expression with multiple local references
	-- 'a', 'b', and 'result' are all used once.
	[ [[
        local a = 10 -- line 0
        local b = 20 -- line 1
        local res = a * (b + 5) -- line 2
        print(res) -- line 3
    ]] ] = { ["a_0"] = 1, ["b_1"] = 1, ["res_2"] = 1 },

	-- Multiple Declarations on One Line with Mixed Usage
	-- 'b_0' is unused, 'a_0' and 'c_0' are used.
	[ [[
        local a, b, c = 1, 2, 3 -- line 0
        print(a, c) -- line 1
    ]] ] = { ["a_0"] = 1, ["b_0"] = 0, ["c_0"] = 1 },

	-- Recursive Function Calls (self-reference)
	-- 'fib_0' should be counted for its declaration and each recursive call.
	[ [[
        local function fib(n) -- line 0
            if n < 2 then return n end -- line 1
            return fib(n-1) + fib(n-2) -- line 2 (fib called twice)
        end -- line 3
        print(fib(5)) -- line 4 (fib called once)
    ]] ] = { ["fib_0"] = 3 }, -- 1 for initial call, 2 for recursive calls

	-- Local References in Table Constructor Keys and Values
	-- 'key_name_0' is used as a computed key and as a field value.
	-- 'val_data_0' is used as a field value.
	[ [[
        local key_name = "test" -- line 0
        local val_data = 10 -- line 1
        local t = { [key_name] = val_data, field = key_name } -- line 2
        print(t) -- line 3
    ]] ] = { ["key_name_0"] = 2, ["val_data_1"] = 1, ["t_2"] = 1 },

	-- Local variable within an 'if' expression branch that gets assigned to another local
	-- 'inner_x_2' is used only within its branch, 'outer_y_1' captures the result.
	[ [[
        local cond = true -- line 0
        local outer_y = if cond then -- line 1
            function() -- line 2
                local inner_x = 10 -- line 3
                return inner_x + 5 -- line 4
            end -- line 5
        else -- line 6
            function() -- line 7
                return 1 -- line 8
            end -- line 9
        print(outer_y()) -- line 10
    ]] ] = { ["cond_0"] = 1, ["outer_y_1"] = 1, ["inner_x_3"] = 1 },

	-- Upvalue used in nested function where inner function is returned
	-- 'upvalue_var_0' is used in the inner_func, 'outer_func_1' and 'inner_func_3' are also locals.
	[ [[
        local upvalue_var = "hello" -- line 0
        local function outer_func() -- line 1
            local local_to_outer = 1 -- line 2
            local function inner_func() -- line 3
                print(upvalue_var) -- line 4
                print(local_to_outer) -- line 5
            end -- line 6
            return inner_func -- line 7
        end -- line 8
        outer_func()() -- line 9
    ]] ] = {
		["upvalue_var_0"] = 1,
		["outer_func_1"] = 1,
		["local_to_outer_2"] = 1,
		["inner_func_3"] = 1,
	},

	-- Global function declaration
	[ [[
        function n()
            print(1)
        end
        n()
    ]] ] = {
		["n_0"] = 1,
	},

	-- Passing declared variables to functions
	[ [[
        local s = "test"
        function abc(var: string)
            return var
        end
        local function cba(var: string)
            print(var)
        end
        cba(abc(s))
    ]] ] = {
		["s_0"] = 1,
		["abc_1"] = 1,
		["cba_4"] = 1,
	},

	-- Referencing global functions (non-call) and referencing vars as table keys
	[ [[
        local x = 1
        local function a()
            return 2
        end
        function b()
            return 4
        end
        return {
            ['m'] = a(),
            ['b'] = x,
            ['c'] = a,
            ['d'] = b,
        }
    ]] ] = {
		["x_0"] = 1,
		["a_1"] = 2,
		["b_4"] = 1,
	},

	[ [[
        local x = 1
        return x
    ]] ] = {
		["x_0"] = 1,
	},

    -- edge sort of case: multiple varss to one value (we don't want to touch these bc will inevitably break code if we do)
    [ [[
        local function z()
            return 1, 2, 3
        end
        local a, b, c = z()
    ]] ] = {
        ["z_0"] = 1,
        ["a_3"] = 1,
        ["b_3"] = 1,
        ["c_3"] = 1,
    }
    -- hmmm, mayb better solution is to add _ to unused var name? rather than adjust behavior of findVariables to consider this a use...?? will have to think on this 


	--[[
        the only part of findVariables that uses the scopeStack is the visitTypeReference
        this would be a case where we have something like:

            local m = 1
            local function x()
                local m = require("../test")
                local n: m.testType = { "l" = 1 } 
            end

        in this case, we want m_2 (defined on line 2) to have 1 use, while m_0 should have 0
        hmmm how can i get requires to work in these test cases....
    ]]

	--[[ 
        the following is an edge case I'm not yet sure how to handle:
        local types = require(...)
        local function func()
	        local types = 1
	        local h: types.testType = { ['a'] = 1 } -- refers to types on line 0, but current implementation will count it as use for types on the line just above
        end
        hmmmm, this is tricky bc outside of these type sort of cases (using var with same name in nested scope as an outer-scope var that exports type), the interpreter will use the nearest in scope var for logic
        can save as a challenge for later
    ]]

	-- To-Do: remove redundant test cases
}

return testCases
