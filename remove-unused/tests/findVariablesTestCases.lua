local testCases = {
	-- Basic Unused Variable
	[ [[
        local unusedVar = 10
    ]] ] = { ["unusedVar_1"] = 0 },

	-- Multiple Variable Declaration
	[ [[
        local x, y = 1, grow-2
    ]] ] = { ["x_1"] = 0, ["y_1"] = 0 },

	-- Basic Used Variable
	[ [[
        local usedVar = 20
        print(usedVar)
    ]] ] = { ["usedVar_1"] = 1 },

	-- Variable Used in Simple Assignment (User's Rule: assign-to does not increment)
	[ [[
        local x = 1
        x = 2
    ]] ] = { ["x_1"] = 0 },

	-- Variable Used in Compound Assignment (Linter's Rule: *is* a use)
	[ [[
        local y = 5
        y += 10
    ]] ] = { ["y_1"] = 1 },

	-- Variable Used in Expression and Simple Assignment
	[ [[
        local z = 1
        local a = z
        z = 2
    ]] ] = { ["z_1"] = 1, ["a_2"] = 0 },

	-- Function Parameter Used (NOT tracked for removal by linter's rule)
	[ [[
        local function foo(param)
            print(param)
        end
        foo(1)
    ]] ] = { ["foo_1"] = 1 }, -- Only 'foo' (the function itself) is tracked and used

	-- Function Parameter Unused (NOT tracked for removal by linter's rule)
	[ [[
        local function bar(unusedParam)
            local temp = 1
        end
        bar(2)
    ]] ] = { ["temp_2"] = 0, ["bar_1"] = 1 },

	-- Nested Scope & Shadowing
	[ [[
        local x = 1 -- line 0
        local function nested() -- line 1
            local x = 2 -- line 2
            print(x) -- line 3
        end -- line 4
        nested() -- line 6
    ]] ] = { ["x_1"] = 0, ["x_3"] = 1, ["nested_2"] = 1 },

	-- `do..end` Block Scope
	[ [[
        local a = 1 -- line 0
        do -- line 1
            local b = 2 -- line 2
            print(b) -- line 3
        end -- line 4
        print(a) -- line 5
    ]] ] = { ["a_1"] = 1, ["b_3"] = 1 },

	-- `for` Numeric Loop Variable (NOT tracked for removal by linter's rule)
	[ [[
        local total = 0 -- line 0
        for i = 1, 5 do -- line 1
            total = total + i
        end
    ]] ] = { ["total_1"] = 1 },

	-- `for in` Loop Variables (NOT tracked for removal by linter's rule)
	[ [[
        local data = {a=1, b=2} -- line 0
        for key, val in pairs(data) do -- line 1
            print(key)
        end
    ]] ] = { ["data_1"] = 1 },

	-- Interpolated String Reference
	[ [[
        local name = "Alice" -- line 0
        print(`Hello, {name}!`) -- line 1
    ]] ] = { ["name_1"] = 1 },

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
	[ [[
        local _, value = 1, 2 -- line 0
        print(value) -- line 1
    ]] ] = { ["value_1"] = 1 },

	-- Multiple Uses of a Variable
	[ [[
        local counter = 0 -- line 0
        counter = counter + 1 -- line 1
        print(counter) -- line 2
    ]] ] = { ["counter_1"] = 2 },

	-- Variable with No References (but complex initialization)
	[ [[
        local complex = (1 + 2) * 3 -- line 0
        local unused = complex -- line 1
    ]] ] = { ["complex_1"] = 1, ["unused_2"] = 0 },

	-- Nested Anonymous Function (closure over 'x')
	[ [[
        local run = function() -- line 0
            local x = 1 -- line 1
            return function() print(x) end -- line 2
        end -- line 3
        run()() -- line 4
    ]] ] = { ["run_1"] = 1, ["x_2"] = 1 },

	-- Variables with identical names in different scopes (distinct AstLocal objects)
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
    ]] ] = { ["a_1"] = 0, ["fn1_2"] = 1, ["b_3"] = 1, ["fn2_6"] = 1, ["b_7"] = 1 },

	-- Variables used in table literals/access
	[ [[
        local myTable = { ["test"] = 1 } -- line 0
        myTable.field = 10 -- line 1
        local val = myTable.field -- line 2
        print(myTable.field) -- line 3
        local t = "test"
        print(`hmm {myTable[t]}`)
    ]] ] = { ["myTable_1"] = 4, ["val_3"] = 0, ["t_5"] = 1 },

	-- Complex expression with multiple local references
	[ [[
        local a = 10 -- line 0
        local b = 20 -- line 1
        local res = a * (b + 5) -- line 2
        print(res) -- line 3
    ]] ] = { ["a_1"] = 1, ["b_2"] = 1, ["res_3"] = 1 },

	-- Multiple Declarations on One Line with Mixed Usage
	[ [[
        local a, b, c = 1, 2, 3 -- line 0
        print(a, c) -- line 1
    ]] ] = { ["a_1"] = 1, ["b_1"] = 0, ["c_1"] = 1 },

	-- Recursive Function Calls (self-reference)
	[ [[
        local function fib(n) -- line 0
            if n < 2 then return n end -- line 1
            return fib(n-1) + fib(n-2) -- line 2 (fib called twice)
        end -- line 3
        print(fib(5)) -- line 4 (fib called once)
    ]] ] = { ["fib_1"] = 3 }, -- 1 for initial call, 2 for recursive calls

	-- Local References in Table Constructor Keys and Values
	[ [[
        local key_name = "test" -- line 0
        local val_data = 10 -- line 1
        local t = { [key_name] = val_data, field = key_name } -- line 2
        print(t) -- line 3
    ]] ] = { ["key_name_1"] = 2, ["val_data_2"] = 1, ["t_3"] = 1 },

	-- Local variable within an 'if' expression branch that gets assigned to another local
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
    ]] ] = { ["cond_1"] = 1, ["outer_y_2"] = 1, ["inner_x_4"] = 1 },

	-- Upvalue used in nested function where inner function is returned
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
		["upvalue_var_1"] = 1,
		["outer_func_2"] = 1,
		["local_to_outer_3"] = 1,
		["inner_func_4"] = 1,
	},

	-- Global function declaration
	[ [[
        function n()
            print(1)
        end
        n()
    ]] ] = {
		["n_1"] = 1,
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
		["s_1"] = 1,
		["abc_2"] = 1,
		["cba_5"] = 1,
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
		["x_1"] = 1,
		["a_2"] = 2,
		["b_5"] = 1,
	},

	[ [[
        local x = 1
        return x
    ]] ] = {
		["x_1"] = 1,
	},

	-- edge case: global function is used before it is defined; still needs to be picked up as use
	[ [[
        local function a()
            print(b())
        end
        function b()
            return 1
        end
     ]] ] = {
		["a_1"] = 0,
		["b_4"] = 1,
	},
}

return testCases
