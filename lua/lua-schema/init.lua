local M = {}

-- const = <any not reserved string> | { const = <any not reserved string> }
-- type = 'string' | 'number' | 'boolean' | 'function' | 'any' | 'nil' | const
--      | { list = type }
--      | { oneof = [ type ] }
--      | { table = { keys = type, values = type } | [ { key = const, value = type} ] }

M.const = { oneof = { 'string', { table = { key = 'const', value = 'string' } } } }

M.list = function()
    return {
        table = {
            { key = 'list', value = M.type, required = true },
            { key = 'non_empty', value = 'boolean' },
        },
    }
end

M.oneof = function()
    return {
        table = { key = 'oneof', value = { list = M.type } },
    }
end

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

M.is_primitive = function(object)
    return vim.tbl_contains(M.primirives, object)
end

M.is_const = function(object)
    if M.is_primitive(object) then
        return false
    end
    if type(object) == 'table' then
        return object[1] == 'const'
    end
    return true
end

M.name_of_type = function(typ)
    if type(typ) == 'string' then
        return typ
    end
    if type(typ) == 'table' then
        return next(typ)
    end
    if M.is_const(typ) then
        return string.format('const `%s`', typ)
    end
    error('Unsupported type ' .. vim.inspect(typ))
end

local PathToError = {}

function PathToError:new(object, schema)
    local p = {}
    -- pointer to the current validated position in the object
    p.current_object = self.current_object
    p.current_object_key = self.current_object_key
    -- pointer to the current validated position in the schema
    p.current_schema = self.current_schema
    p.current_schema_key = self.current_schema_key
    setmetatable(p, {
        __index = self,
        __tostring = function(t)
            return string.format(
                '%s\n\nValidated value: %s\n\nValidated schema: %s',
                t.error_message or '',
                vim.inspect(t.object),
                vim.inspect(t.schema)
            )
        end,
    })
    if not (object or schema) then
        return p
    end

    -- adding a new elements to the path --

    if not p.current_schema then
        p.object = object
        p.schema = schema
        p.current_object = object
        p.current_schema = schema
    elseif p.current_schema.list then
        p.current_object[p.current_object_key] = object
        p.current_object = object
        p.current_object_key = nil
    elseif p.current_schema.table then
        local kv = p.current_schema.table[p.current_schema_key]
        if not kv or kv.value then
            -- key and value are already set, we should prepare a new key-value schema now
            kv = {}
            p.current_schema.table[p.current_schema_key] = kv
        end
        if not kv.key then
            -- we should set a key
            kv.key = schema
            p.current_object[object] = '?'
            p.current_schema = schema
            p.current_object = object
            p.current_schema_key = nil
            p.current_object_key = nil
        else
            -- a key is already set, we should set a value now
            kv.value = schema
            p.current_object[p.current_object_key] = object
            p.current_schema = schema
            p.current_object = object
            p.current_schema_key = nil
            p.current_object_key = nil
        end
    else
        p.current_object = object
        p.current_schema = schema
        p.current_object_key = nil
        p.current_schema_key = nil
    end

    return p
end

function PathToError:wrong_type(expected_type, obj)
    self.error_message = string.format(
        'Wrong type. Expected <%s>, but actual was <%s>.',
        M.name_of_type(expected_type),
        type(obj)
    )
    return self
end

function PathToError:wrong_type_in_schema(type_name, schema)
    self.error_message = string.format(
        'Unknown type `%s` in the schema: %s',
        type_name,
        vim.inspect(schema)
    )
    return self
end

function PathToError:wrong_value(expected, actual)
    self.error_message = string.format(
        'Wrong value "%s". Expected "%s".',
        tostring(actual),
        tostring(expected)
    )
    return self
end

function PathToError:wrong_oneof(value, options)
    self.error_message = string.format(
        'Wrong oneof value: %s. Expected values %s.',
        vim.inspect(value),
        vim.inspect(options)
    )
    return self
end

function PathToError:empty_list_of(el_type)
    self.error_message = string.format(
        'No one element in the none empty list of %s',
        M.name_of_type(el_type)
    )
    return self
end

function PathToError:wrong_kv_types_schema(kv_types)
    self.error_message = string.format(
        "Wrong schema. It should have description for 'key' and 'value', but it doesn't: `%s`",
        vim.inspect(kv_types)
    )
    return self
end

function PathToError:wrong_schema_of(typ, type_schema)
    self.error_message = string.format(
        'Wrong schema of the %s. Expected table, but was %s.',
        typ,
        type(type_schema)
    )
    return self
end

function PathToError:required_key_not_found(kv_types, orig_table)
    self.error_message = string.format(
        'Required key `%s` was not found.\nKeys in the original table were:\n%s',
        vim.inspect(kv_types.key),
        vim.inspect(vim.tbl_keys(orig_table))
    )
    return self
end

function PathToError:required_pair_not_found(kv_types, orig_table)
    self.error_message = string.format(
        'Required pair with key = `%s` and value = `%s` was not found.\nOriginal table was:\n%s',
        vim.inspect(kv_types.key),
        vim.inspect(kv_types.value),
        vim.inspect(orig_table)
    )
    return self
end

local function validate_const(value, schema, path)
    local path = path:new(value, schema)
    if value ~= schema then
        return false, path:wrong_value(schema, value)
    end
    return true
end

local function validate_list(list, el_type, non_empty, path)
    local path = path:new({}, { list = el_type, non_empty = non_empty })
    if type(list) ~= 'table' then
        return false, path:wrong_type('table', list)
    end

    if non_empty and #list == 0 then
        return false, path:empty_list_of(el_type)
    end

    for i, el in ipairs(list) do
        path.current_object_key = i
        local _, err = M.validate(el, el_type, path)
        if err then
            return false, err
        end
    end
    return true
end

local function validate_oneof(value, options, path)
    local path = path:new(value, { oneof = options })
    if type(options) ~= 'table' then
        return nil, path:wrong_schema_of('oneof', options)
    end
    for _, opt in ipairs(options) do
        -- we do not pass any path here to avoid adding not applicable opt
        if M.validate(value, opt) then
            return true
        end
    end
    return false, path:wrong_oneof(value, options)
end

local function validate_table(orig_tbl, kvs_schema, path)
    local path = path:new({}, { table = {} })
    if type(kvs_schema) ~= 'table' then
        return false, path:wrong_schema_of('table', kvs_schema)
    end

    if type(orig_tbl) ~= 'table' then
        return false, path:wrong_type('table', orig_tbl)
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
            return false, path:wrong_kv_types_schema(kv_types)
        end

        local at_least_one_key_passed = false
        local at_least_one_pair_passed = false

        for k, v in pairs(unvalidated_tbl) do
            path.current_object_key = k
            local _, err = M.validate(k, kv_types.key, path)
            if not err then
                at_least_one_key_passed = true

                _, err = M.validate(v, kv_types.value, path)
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
            return false, path:required_key_not_found(kv_types, unvalidated_tbl)
        end

        if is_strict and not at_least_one_pair_passed then
            return false, path:required_pair_not_found(kv_types, unvalidated_tbl)
        end

        return true
    end

    local function validate_keys(unvalidated_tbl, kv_schemas, is_strict)
        for i, kv_schema in ipairs(kv_schemas) do
            path.current_schema_key = i
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
        path.current_schema_key = 1
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
--- Checks that {object} sutisfied to the {schema} or raises error.
--- You can use safe version `call_validate` to avoid error and use returned status
--- instead.
M.validate = function(object, schema, path)
    local path = path or PathToError:new()

    local type_name, type_schema, type_value
    if type(schema) == 'function' then
        return M.validate(object, schema(), path)
    elseif type(schema) == 'table' then
        type_name, type_schema = next(schema)
        type_value = type_name == 'const' and type_schema or nil
    elseif M.is_const(schema) then
        type_name = 'const'
        type_value = schema
    else
        type_name = schema
    end

    if type_name == 'table' then
        return validate_table(object, type_schema, path)
    end
    if type_name == 'oneof' then
        return validate_oneof(object, type_schema, path)
    end
    if type_name == 'list' or type_name == 'non_empty' then
        return validate_list(object, schema.list, schema.non_empty, path)
    end
    if type_name == 'const' then
        return validate_const(object, type_value, path)
    end

    if not M.is_primitive(type_name) then
        return false, path:wrong_type_in_schema(type_name, schema)
    end
    -- flat constants or primitives
    path = path:new(object, schema)
    local ok = type(object) == type_name or object == type_value
    if not ok then
        return false, path:wrong_type(type_name, object)
    end
    return true
end

return M
