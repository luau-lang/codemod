-- local visitor = require("@std/syntax/visitor")
-- local parser = require("@std/syntax/parser")
-- local fs = require("@lute/fs")
-- local luau = require("@lute/luau")
-- local commonHelpers = require("./commonHelpers")
-- local getTokenText, findReferencedVariables =
-- 	commonHelpers.getTokenText,
-- 	commonHelpers.findReferencedVariables
local FileVisitor = require("./fileUtils").FileVisitor
local getFunctionSignature = require("./functionUtils").getFunctionSignature
local getTypeSignature = require("./typeUtils").getTypeSignature

--[[
getClassSignature(tableNode: AstState): string
much trickier; we kinda need to scrape an entire file for this, and can't just extract from the initial declaration...
hmmmm
]]

return {
	FileVisitor = FileVisitor,
	getFunctionSignature = getFunctionSignature,
	getTypeSignature = getTypeSignature,
}

--[[
THE PLANNING COMMENT
- call docs-gen script on root of project
- use "init.lua" as entry point for a module
- keep track of current modules (kinda scopish, push module onto stack when we see init, pop from stack after traversing all of current module's exports)

- general module procedure (which we can hopefully use to recur thru an entire project)
    - init.lua is entry point
    - parse init.lua, determine exports (and their file-paths...)
    - for each export:
        - if directory (sub-module):
            - repeat module process
        - if file:
            - document based on filename under the current tracked module
    
- parsing/discovery phase described above, goal is to build map of ['module'] : { { types }, { sub-modules }, { files } }
  - { types }, table of "typeName" : type documentation string
  - { sub-modules }, table of "moduleName" :  { { types }, { sub-modules }, { files } }
  - { files }, table of "fileName" : { { functions }, { types }, ... (what else...) }
    - { functions }, table of "functionName" : function documentation string

eventually, can add support for using various comment conventions for specific/fancy documentation but just want to nail discovery phase first
also, will have to figure out how to document each type of documentable code (type, function, etc), but can do that later as well

File parsing:
    - use lute's parser and visitor to easily 

For resolving variable values, we'll need to keep track map variable/functionName : value node
    - for locals, can use localRef : value
    - for globals, can use globalName
    - (edge case), value is require

For resolving return, iterate over returnNode.expressions, handle:
    -  global
    -  local
    -  not-variable just direct value
]]

--[[
Level 1 (Basic Generation): Early tools focused on simply extracting comments and code signatures and rendering them as static HTML pages. 
JSDoc in its initial forms exemplified this.

Level 2 (Structural Analysis): Tools like Doxygen introduced more advanced static analysis, capable of generating not just API lists but
 also complex diagrams like call graphs, caller graphs, and dependency graphs, providing a deeper structural view of the codebase.   

Level 3 (Integrated Experience): godoc represents a shift towards a more integrated developer experience. 
While syntactically simple, its integration with the Go toolchain for displaying verifiable examples and its built-in web server for local browsing created a more seamless workflow.   

Level 4 (Verifiable & Rich): rustdoc sits at the high end of this spectrum. Its compiler integration, rich Markdown formatting, and, most importantly, 
its built-in doctest mechanism represent a paradigm where documentation is a live, verifiable, and integral part of the software itself.   

Level 5 (Interactive Specification): A parallel track of evolution is seen in API documentation tools like Swagger UI and Redoc. These tools consume
 a formal, language-agnostic specification (like OpenAPI) and produce not just static documentation but an interactive console where users can make live API calls. While they document an API's interface rather than its source code, they inform the concept of "live" or "executable" documentation.
]]
