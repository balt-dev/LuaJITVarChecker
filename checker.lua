local lex_setup = require('lang.lexer')
local parse = require('lang.parser')
local lua_ast = require('lang.lua_ast')
local reader = require('lang.reader')

local forbidden_vars = { "_G", "_ENV", "getfenv", "os", "debug", "ffi", "jit", "io", "loadstring", "load" }
local forbidden_strlist = table.concat(forbidden_vars, ', '):gsub("^(.*),", "%1, or")

local ffi = ({}).debug

-- See lang/ast_validate.lua for reference on what I'm doing here.
local function walk(ast_tree, line)
    if type(ast_tree) ~= "table" then return end
    if ast_tree.line then line = ast_tree.line end
    if ast_tree.kind == "Chunk" then
        for i, stmt in pairs(ast_tree.body) do
            walk(stmt, line)
        end
    elseif ast_tree.kind == "BinaryExpression" then
        walk(ast_tree.left, line)
        walk(ast_tree.right, line)
    elseif ast_tree.kind == "ConcatenateExpression" then
        for i, stmt in pairs(ast_tree.terms) do
            walk(stmt, line)
        end
    elseif ast_tree.kind == "UnaryExpression" then
        walk(ast_tree.argument, line)
    elseif ast_tree.kind == "ExpressionValue" then
        walk(ast_tree.value, line)
    elseif ast_tree.kind == "AssignmentExpression" then
        walk(ast_tree.left, line)
        walk(ast_tree.right, line)
    elseif ast_tree.kind == "LogicalExpression" then
        walk(ast_tree.left, line)
        walk(ast_tree.right, line)
    elseif ast_tree.kind == "MemberExpression" then
        walk(ast_tree.object, line)
        walk(ast_tree.property, line)
    elseif ast_tree.kind == "Identifier" then
        -- We're at an actual variable name now!
        for _, var in ipairs(forbidden_vars) do
            if ast_tree.name == var then
                error("Suspicious usage of " .. ast_tree.name .. " (" .. forbidden_strlist .. ") on line " .. line, 0)
            end
        end
    elseif ast_tree.kind == "CallExpression" then
        walk(ast_tree.callee, line)
        for i, stmt in pairs(ast_tree.arguments) do
            walk(stmt, line)
        end
    elseif ast_tree.kind == "SendExpression" then
        walk(ast_tree.receiver, line)
        for i, stmt in pairs(ast_tree.arguments) do
            walk(stmt, line)
        end
    elseif ast_tree.kind == "Table" then
        if ast_tree.array_entries then
            for i, stmt in pairs(ast_tree.array_entries) do
                walk(stmt, line)
            end
        end
        if ast_tree.hash_keys then
            for i, stmt in pairs(ast_tree.hash_keys) do
                walk(stmt, line)
            end
        end
        if ast_tree.hash_values then
            for i, stmt in pairs(ast_tree.hash_values) do
                walk(stmt, line)
            end
        end
    elseif ast_tree.kind == "ExpressionStatement" then
        walk(ast_tree.expression, line)
    elseif ast_tree.kind == "StatementsGroup" then
        for i, stmt in pairs(ast_tree.statements) do
            walk(stmt, line)
        end
    elseif ast_tree.kind == "DoStatement" then
        for i, stmt in pairs(ast_tree.body) do
            walk(stmt, line)
        end
    elseif ast_tree.kind == "IfStatement" then
        for i, stmt in pairs(ast_tree.tests) do
            walk(stmt, line)
        end
        for i, stmts in pairs(ast_tree.cons) do
            for i, stmt in pairs(stmts) do
                walk(stmt, line)
            end
        end
        if ast_tree.alternate then
            for i, stmt in pairs(ast_tree.alternate) do
                walk(stmt, line)
            end
        end
    elseif ast_tree.kind == "ReturnStatement" then
        for i, stmt in pairs(ast_tree.arguments) do
            walk(stmt, line)
        end
    elseif ast_tree.kind == "WhileStatement" then
        walk(ast_tree.test, line)
        for i, stmt in pairs(ast_tree.body) do
            walk(stmt, line)
        end
    elseif ast_tree.kind == "RepeatStatement" then
        walk(ast_tree.test, line)
        for i, stmt in pairs(ast_tree.body) do
            walk(stmt, line)
        end
    elseif ast_tree.kind == "ForInit" then
        walk(ast_tree.value, line)
    elseif ast_tree.kind == "ForStatement" then
        walk(ast_tree.init, line)
        walk(ast_tree.last, line)
        if ast_tree.step then
            walk(ast_tree.step, line)
        end
        for i, stmt in pairs(ast_tree.body) do
            walk(stmt, line)
        end
    elseif ast_tree.kind == "ForInStatement" then
        for i, stmt in pairs(ast_tree.explist) do
            walk(stmt, line)
        end
        for i, stmt in pairs(ast_tree.body) do
            walk(stmt, line)
        end
    elseif ast_tree.kind == "LocalDeclaration" then
        for i, stmt in pairs(ast_tree.expressions) do
            walk(stmt, line)
        end
    elseif ast_tree.kind == "FunctionDeclaration" then
        walk(ast_tree.id, line)
        for i, stmt in pairs(ast_tree.body) do
            walk(stmt, line)
        end
    elseif ast_tree.kind == "FunctionExpression" then
        for i, stmt in pairs(ast_tree.body) do
            walk(stmt, line)
        end
    end
end

local function run(filename)
    if filename == nil then error("No filename specified!") end
    local ls = lex_setup(reader.file(filename), filename)
    local ast_builder = lua_ast.New()
    local parse_success, ast_tree = pcall(parse, ast_builder, ls)
    if not parse_success then error(ast_tree, 0) end -- holds error message

    -- We walk the generated ast tree to look for any accesses to the forbidden variables
    walk(ast_tree)
end

local res, msg = pcall(run, ...)
print(([[{ "success": %s, message: %q }]]):format((res and "true") or "false", tostring(msg or "")))
