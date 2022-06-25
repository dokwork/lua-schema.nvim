local s = require('lua-schema')

describe('validation the schema', function()
    it('should be passed for every type', function()
        assert(s.validate(s.const, s.type()), 'Wrong schema for the const')
        assert(s.validate(s.list(), s.type()), 'Wrong schema for the list')
        assert(s.validate(s.oneof(), s.type()), 'Wrong schema for the oneof')
        assert(s.validate(s.table(), s.type()), 'Wrong schema for the table')
        assert(s.validate(s.type(), s.type()), 'Wrong schema for the type')
    end)

    it('should be failed for invalide schema', function()
        assert(not s.validate({ oNNeof = { 1, 2, 3 } }, s.type()))
        assert(not s.validate({ lst = 'string' }, s.type()))
        assert(not s.validate({ tbl = { key = true, value = true } }, s.type()))
        assert(not s.validate({ table = { ky = true, value = true } }, s.type()))
        assert(not s.validate({ table = { key = true, val = true } }, s.type()))
        assert(not s.validate({ table = { key = true } }, s.type()))
        assert(not s.validate({ cnst = 123 }, s.type()))
    end)

    describe('of the constants', function()
        it('should be passed for both syntax of constants', function()
            -- when:
            assert(s.validate('123', s.const))
            assert(s.validate({ const = '123' }, s.const))
        end)

        it('should be passed for particular value by the short schema', function()
            -- given:
            local schema = '123'

            -- then:
            assert(s.validate('123', schema))
            assert(not s.validate('12', schema))
            assert(not s.validate(123, schema))
        end)

        it('should be passed for particular value by the full schema', function()
            -- given:
            local schema = { const = '123' }

            -- then:
            assert(s.validate('123', schema))
            assert(not s.validate('12', schema))
            assert(not s.validate(123, schema))
        end)
    end)

    describe('of the oneof', function()
        it('should be passed for every option', function()
            -- given:
            local schema = {
                oneof = { '123', 456, 'function', true, { table = { key = 'a', value = 1 } } },
            }

            -- then:
            assert(s.validate('123', schema))
            assert(s.validate(456, schema))
            assert(s.validate(true, schema))
            assert(s.validate({ a = 1 }, schema))
            assert(s.validate(it, schema))
        end)

        it('should be failed when value is not in the list, or has wwrong type', function()
            -- given:
            local schema = { oneof = { '123', 456, true, { table = { key = 'a', value = 1 } } } }

            -- then:
            assert(not s.validate('!123', schema))
            assert(not s.validate('true', schema))
        end)
    end)

    describe('of the list', function()
        it('should be passed for list with elements with valid type', function()
            -- given:
            local schema = { list = 'number' }

            -- when:
            local ok, err = s.validate({ 1, 2, 3 }, schema)

            -- then:
            assert(ok, tostring(err))
        end)

        it('should be passed for empty list', function()
            -- given:
            local schema = { list = 'number' }

            -- then:
            assert(s.validate({}, schema))
        end)

        it('should not be passed for empty list', function()
            -- given:
            local schema = { list = 'number', non_empty = true }

            -- when:
            local ok, err = s.validate({}, schema)

            -- then:
            assert(not ok)
            assert.are.same({}, err.object)
            assert.are.same(schema, err.schema)
        end)

        it('should be failed for list with element with wrong type', function()
            -- given:
            local schema = { list = 'number' }

            -- when:
            local ok, err = s.validate({ 1, 2, '3' }, schema)

            -- then:
            assert(not ok)
            assert.are.same({ 1, 2, '3' }, err.object)
            assert.are.same(schema, err.schema)
        end)
    end)

    describe('of the table', function()
        it('should be passed for a valid table', function()
            -- given:
            local schema = { table = { key = 'string', value = 'string' } }

            -- when:
            local ok, err = s.validate({ a = 'b' }, schema)

            -- then:
            assert(ok, tostring(err))
        end)

        it('should validate type of keys', function()
            -- given:
            local schema = { table = { key = 'string', value = 'number' } }

            -- then:
            assert(not s.validate({ 1, 2 }, schema))
        end)

        it('should validate type of values', function()
            -- given:
            local schema = { table = { key = 'string', value = 'number' } }

            -- when:
            local ok, err = s.validate({ a = 'str' }, schema)

            -- then:
            assert(not ok)
            assert.are.same({ a = 'str' }, err.object)
            assert.are.same({ table = { { key = 'string', value = 'number' } } }, err.schema)
        end)

        it('should support oneof as a type of keys', function()
            -- given:
            local schema = { table = { key = { oneof = { 'a', 'b' } }, value = 'string' } }

            -- then:
            assert(s.validate({ a = 'a' }, schema))
            assert(s.validate({ b = 'b' }, schema))
            assert(not s.validate({ c = 'c' }, schema))
        end)

        it('should check other key options if oneof failed', function()
            -- given:
            local schema = {
                table = {
                    { key = { oneof = { 'a', 'b' } }, value = 'string' },
                    { key = 'string', value = 'boolean' },
                },
            }

            -- when:
            local ok, err = s.validate({ c = true }, schema)

            -- then:
            assert(ok, tostring(err))
        end)

        it('should not be passed when required oneof was not satisfied', function()
            -- given:
            local schema = {
                table = {
                    { key = { oneof = { 'a', 'b' } }, value = 'string', required = true },
                    { key = 'string', value = 'boolean' },
                },
            }

            -- when:
            local ok, err = s.validate({ c = true }, schema)

            -- then:
            assert(not ok)

            assert.are.same({ c = '?' }, err.object)
            assert.are.same({
                table = { { key = { oneof = { 'a', 'b' } } } },
            }, err.schema)
        end)

        it('should support oneof as a type of values', function()
            -- given:
            local schema = { table = { key = 'string', value = { oneof = { 'a', 'b' } } } }

            -- then:
            assert(s.validate({ a = 'a' }, schema))
            assert(s.validate({ a = 'b' }, schema))
            assert(not s.validate({ a = 'c' }, schema))
        end)

        it('should support const as a type of keys', function()
            -- given:
            local schema = {
                table = {
                    { key = 'a', value = 'number' },
                    { key = 'b', value = 'boolean' },
                },
            }

            -- when:
            local ok, err = s.validate({ a = 1, b = true }, schema)

            -- then:
            assert(ok, tostring(err))
            assert(not s.validate({ a = 'str', b = true }, schema))
            assert(not s.validate({ a = 1, b = 1 }, schema))
        end)

        it('should be passed for missed optional keys', function()
            -- given:
            local schema = {
                table = {
                    { key = 'a', value = 'number' },
                    { key = 'b', value = 'boolean', required = true },
                },
            }

            -- then:
            assert(s.validate({ b = true }, schema))
        end)

        it('should be failed for missed required keys', function()
            -- given:
            local schema = {
                table = {
                    { key = 'a', value = 'number' },
                    { key = 'b', value = 'boolean', required = true },
                },
            }

            -- then:
            assert(not s.validate({ a = 1 }, schema))
        end)

        it('should support mix of const and other types', function()
            -- given:
            local schema = {
                table = {
                    { key = 'a', value = 'number' },
                    { key = 'string', value = 'boolean' },
                },
            }

            -- when:
            local ok, err = s.validate({ a = 1, str = true }, schema)

            -- then:
            assert(ok, tostring(err))
        end)

        it('should support table as a value', function()
            -- given:
            local schema = {
                table = {
                    {
                        key = 'a',
                        value = {
                            table = { key = 'b', value = 'number' },
                        },
                    },
                },
            }

            -- when:
            local ok, err = s.validate({ a = { b = 1 } }, schema)

            -- then:
            assert(ok, tostring(err))
        end)

        it('should correctly compose error for nested tables', function()
            -- given:
            local schema = {
                table = {
                    {
                        key = 'a',
                        value = {
                            table = { key = 'b', value = 'number' },
                        },
                    },
                },
            }

            -- when:
            local ok, err = s.validate({ a = { c = 1 } }, schema)

            -- then:
            assert(not ok)
            assert.are.same({ a = { c = '?' } }, err.object)
            assert.are.same(
                { table = { { key = 'a', value = { table = { { key = 'b' } } } } } },
                err.schema
            )
        end)
    end)
end)
