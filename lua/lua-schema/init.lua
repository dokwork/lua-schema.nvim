local M = {}

-- const = <any not reserved string> | { const = <any not reserved string> }
-- type = 'string' | 'number' | 'boolean' | 'function' | 'any' | 'nil' | const
--      | { list = type }
--      | { oneof = [ type ] }
--      | { table = { keys = type, values = type } | [ { key = const, value = type} ] }

--- Schema of constant values.
--- Example:
---```lua
--- assert(lua_schema.validate(5, '5'))
---```
--- Or:
---```lua
--- assert(lua_schema.validate(5, { const = '5' }))
---```
M.const = { oneof = { 'string', { table = { key = 'const', value = 'string' } } } }

--- Schema of homogeneus lists.
--- Example:
---```lua
--- assert(lua_schema.validate({ 'a', 'b', 'c' }, { list = 'string' }))
---```
--- By default, the list can be empty:
---```lua
--- assert(lua_schema.validate({}, { list = 'string' }))
---```
--- But you can describe non empty list:
---```lua
--- -- this assertion will be failed
--- assert(lua_schema.validate({}, { list = 'string', non_empty = true }))
---```
M.list = function()
    return {
        table = {
            { key = 'list', value = M.type, required = true },
            { key = 'non_empty', value = 'boolean' },
        },
    }
end

--- Schema of coproducts.
--- Example:
---```lua
--- assert(lua_schema.validate('a string', { oneof = { 'string', 'number' } }))
---```
--- Or:
---```lua
--- assert(lua_schema.validate(12345, { oneof = { 'string', 'number' } }))
---```
M.oneof = function()
    return {
        table = { key = 'oneof', value = { list = M.type } },
    }
end

--- Schema of tables.
--- Example:
---```lua
--- assert(lua_schema.validate(
---     { some_key = 'some_value' },
---     { table = { key = 'string', value = 'string' } }
--- ))
---```
--- Or you can provide more different options for key-value pairs:
---```lua
--- assert(lua_schema.validate(
---     { some_key = 'some_value', [1] = true },
---     { table = { { key = 'string', value = 'string' }, { key = 'number', value = 'boolean' } }
--- ))
---```
--- By default, every key-value pair is optional. You can change it with 'required' property:
---```lua
--- -- valid, because sutisfies to the required key-value pair
--- assert(lua_schema.validate(
---     { [1] = true },
---     { table = { { key = 'string', value = 'string' }, { key = 'number', value = 'boolean', required = true } }
--- ))
--- -- invalid, because do not sutisfy to the required key-value pair
--- assert(lua_schema.validate(
---     { some_key = 'some_value' },
---     { table = { { key = 'string', value = 'string' }, { key = 'number', value = 'boolean', required = true } }
--- ))
---```
M.table = function()
    return {
        table = {
            key = 'table',
            value = {
                oneof = {
                    {
                        table = {
                            { key = 'key', value = M.type, required = true },
                            { key = 'value', value = M.type, required = true },
                        },
                    },
                    {
                        list = {
                            table = {
                                { key = 'key', value = M.type, required = true },
                                { key = 'value', value = M.type, required = true },
                            },
                        },
                        non_empty = true,
                    },
                },
            },
        },
    }
end

--- Schema of the primitives types.
--- Example:
---```lua
--- assert(lua_schema.validate(nil, 'nil'))
---```
--- Or:
---```lua
--- assert(lua_schema.validate(true, 'boolean'))
---```
--- Or:
---```lua
--- assert(lua_schema.validate('a string', 'string'))
---```
--- Or:
---```lua
--- assert(lua_schema.validate(12345, 'number'))
---```
--- Or:
---```lua
--- local f = function()
---     -- do something
--- end
--- assert(lua_schema.validate(f, 'function'))
---```
M.primirives = {
    'boolean',
    'string',
    'number',
    'function',
    'nil',
}

M.type = function()
    local oneof = vim.tbl_extend('keep', {}, M.primirives)
    table.insert(oneof, M.const)
    table.insert(oneof, M.list())
    table.insert(oneof, M.table())
    table.insert(oneof, M.oneof())

    return {
        oneof = oneof,
    }
end

---@return boolean # true if the object has a primitive type, else false.
M.is_primitive = function(object)
    return vim.tbl_contains(M.primirives, object)
end

---@return boolean # true if the object is constant, else false.
M.is_const = function(object)
    if M.is_primitive(object) then
        return false
    end
    if type(object) == 'table' then
        return object[1] == 'const'
    end
    return true
end

---@return string # a name of the type `t` or nil with error message.
M.name_of_type = function(t)
    if type(t) == 'string' then
        return t
    end
    if type(t) == 'table' then
        return next(t)
    end
    if M.is_const(t) then
        return string.format('const `%s`', t)
    end
    return nil, 'Unsupported type ' .. vim.inspect(t)
end

local Stacktrace = {}

Stacktrace.new = function()
    local x = {}
    setmetatable(x, {
        __index = Stacktrace,
        __tostring = function(t)
            local result = 'Stacktrace:'
            for i, err in ipairs(t) do
                result = string.format('%s\n[%d] %s', result, i, err)
            end
            return result
        end,
    })
    return x
end

function Stacktrace:wrong_type(expected_type, obj)
    table.insert(
        self,
        string.format(
            'Wrong type. Expected <%s>, but actual was <%s>.',
            M.name_of_type(expected_type),
            type(obj)
        )
    )
    return self
end

function Stacktrace:wrong_type_in_schema(type_name, schema)
    table.insert(
        self,
        string.format('Unknown type `%s` in the schema: %s', type_name, vim.inspect(schema))
    )
    return self
end

function Stacktrace:wrong_value(expected, actual)
    table.insert(
        self,
        string.format('Wrong value "%s". Expected "%s".', tostring(actual), tostring(expected))
    )
    return self
end

function Stacktrace:wrong_oneof(value, options)
    table.insert(
        self,
        string.format(
            'Wrong oneof value: %s. Expected values %s.',
            vim.inspect(value),
            vim.inspect(options)
        )
    )
    return self
end

function Stacktrace:empty_list_of(el_type)
    table.insert(
        self,
        string.format('No one element in the none empty list of %s', M.name_of_type(el_type))
    )
    return self
end

function Stacktrace:wrong_kv_types_schema(kv_types)
    table.insert(
        self,
        string.format(
            "Wrong schema. It should have description for 'key' and 'value', but it doesn't: `%s`",
            vim.inspect(kv_types)
        )
    )
    return self
end

function Stacktrace:wrong_schema_of(typ, type_schema)
    table.insert(
        self,
        string.format('Wrong schema of the %s. Expected table, but was %s.', typ, type(type_schema))
    )
    return self
end

function Stacktrace:required_key_not_found(kv_types, orig_table)
    table.insert(
        self,
        string.format(
            'Required key `%s` was not found.\nKeys in the original table were:\n%s',
            vim.inspect(kv_types.key),
            vim.inspect(vim.tbl_keys(orig_table))
        )
    )
    return self
end

function Stacktrace:required_pair_not_found(kv_types, orig_table)
    table.insert(
        self,
        string.format(
            'Required pair with key = `%s` and value = `%s` was not found.\nOriginal table was:\n%s',
            vim.inspect(kv_types.key),
            vim.inspect(kv_types.value),
            vim.inspect(orig_table)
        )
    )
    return self
end

-- Validators --

local function validate_const(value, schema, stacktrace)
    if value ~= schema then
        return false, stacktrace:wrong_value(schema, value)
    end
    return true
end

local function validate_list(list, el_type, non_empty, stacktrace)
    if type(list) ~= 'table' then
        return false, stacktrace:wrong_type('table', list)
    end

    if non_empty and #list == 0 then
        return false, stacktrace:empty_list_of(el_type)
    end

    for i, el in ipairs(list) do
        local _, err = M.validate(el, el_type, stacktrace)
        if err then
            return false, err
        end
    end
    return true
end

local function validate_oneof(value, options, stacktrace)
    if type(options) ~= 'table' then
        return nil, stacktrace:wrong_schema_of('oneof', options)
    end
    for _, opt in ipairs(options) do
        if M.validate(value, opt, stacktrace) then
            return true
        end
    end
    return false, stacktrace:wrong_oneof(value, options)
end

local function validate_table(orig_tbl, kvs_schema, stacktrace)
    if type(kvs_schema) ~= 'table' then
        return false, stacktrace:wrong_schema_of('table', kvs_schema)
    end

    if type(orig_tbl) ~= 'table' then
        return false, stacktrace:wrong_type('table', orig_tbl)
    end

    local function split_list(list)
        local required = {}
        local optional = {}
        for _, v in ipairs(list) do
            if type(v) == 'table' and v.required then
                table.insert(required, v)
            else
                table.insert(optional, v)
            end
        end
        return required, optional
    end

    local function validate_key_value(unvalidated_tbl, kv_types, is_strict)
        if not (kv_types.key and kv_types.value) then
            return false, stacktrace:wrong_kv_types_schema(kv_types)
        end

        local at_least_one_key_passed = false
        local at_least_one_pair_passed = false

        for k, v in pairs(unvalidated_tbl) do
            local _, err = M.validate(k, kv_types.key, stacktrace)
            if not err then
                at_least_one_key_passed = true

                _, err = M.validate(v, kv_types.value, stacktrace)
                -- if key is valid, but value is not,
                -- then validation must be failed regadles of is_strict
                if err then
                    return false, err
                end

                at_least_one_pair_passed = true

                -- remove validated key
                unvalidated_tbl[k] = nil

                -- constant can be checked only once
                if M.is_const(kv_types.key) then
                    return true
                end
            end
        end

        if is_strict and not at_least_one_key_passed then
            return false, stacktrace:required_key_not_found(kv_types, unvalidated_tbl)
        end

        if is_strict and not at_least_one_pair_passed then
            return false, stacktrace:required_pair_not_found(kv_types, unvalidated_tbl)
        end

        return true
    end

    local function validate_keys(unvalidated_tbl, kv_schemas, is_strict)
        for _, kv_schema in ipairs(kv_schemas) do
            local _, err = validate_key_value(unvalidated_tbl, kv_schema, is_strict)
            if err then
                return false, err
            end
        end
        return true
    end

    -- this instance will be changed on validation
    local unvalidated_tbl = vim.tbl_extend('error', {}, orig_tbl)
    if kvs_schema.key and kvs_schema.value then
        return validate_key_value(unvalidated_tbl, kvs_schema, true)
    else
        local required, optional = split_list(kvs_schema)
        local _, err = validate_keys(unvalidated_tbl, required, true)
        if err then
            return false, err
        end
        return validate_keys(unvalidated_tbl, optional, false)
    end
end

---@type fun(object: any, schema: table)
--- Checks that the {object} is sutisfied to the {schema}.
---@return boolean, string? # only true in successful case, or false and error message.
M.validate = function(object, schema, stacktrace)
    local stacktrace = stacktrace or Stacktrace.new()
    local type_name, type_schema, type_value
    if type(schema) == 'function' then
        return M.validate(object, schema())
    elseif type(schema) == 'table' then
        type_name, type_schema = next(schema)
        type_value = type_name == 'const' and type_schema or nil
    elseif M.is_const(schema) then
        type_name = 'const'
        type_value = schema
    elseif type(schema) == 'string' then
        type_name = schema
    else
        return false, string.format('Unexpected type of the schema %s.', type(schema))
    end

    if type_name == 'table' then
        return validate_table(object, type_schema, stacktrace)
    end
    if type_name == 'oneof' then
        return validate_oneof(object, type_schema, stacktrace)
    end
    if type_name == 'list' or type_name == 'non_empty' then
        return validate_list(object, schema.list, schema.non_empty, stacktrace)
    end
    if type_name == 'const' then
        return validate_const(object, type_value, stacktrace)
    end

    if not M.is_primitive(type_name) then
        return false, stacktrace:wrong_type_in_schema(type_name, schema)
    end
    -- flat constants or primitives
    local ok = type(object) == type_name or object == type_value
    if not ok then
        return false, stacktrace:wrong_type(type_name, object)
    end
    return true
end

return M
