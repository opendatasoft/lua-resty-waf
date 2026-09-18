local _M = {}

local base   = require "resty.waf.base"
local cjson  = require "cjson"
local logger = require "resty.waf.log"
-- util must be imported from https://github.com/mozilla-services/lua_sandbox_extensions/blob/main/heka/modules/heka/util.lua
local util = require("util")

local re_find       = ngx.re.find
local string_byte   = string.byte
local string_char   = string.char
local string_find   = string.find
local string_format = string.format
local string_gmatch = string.gmatch
local string_gsub   = string.gsub
local string_match  = string.match
local string_sub    = string.sub
local string_upper  = string.upper
local table_concat  = table.concat

_M.version = base.version

-- duplicate a table using recursion if necessary for multi-dimensional tables
-- useful for getting a local copy of a table
function _M.table_copy(orig)
	local orig_type = type(orig)
	local copy

	if orig_type == 'table' then
		copy = {}

		for orig_key, orig_value in next, orig, nil do
			copy[_M.table_copy(orig_key)] = _M.table_copy(orig_value)
		end

		setmetatable(copy, _M.table_copy(getmetatable(orig)))
	else
		copy = orig
	end
	return copy
end

-- return a table containing the keys of the provided table
function _M.table_keys(table)
	if type(table) ~= "table" then
		logger.fatal_fail(type(table) .. " was given to table_keys!")
	end

	local t = {}
	local n = 0

	for key, _ in pairs(table) do
		n = n + 1
		t[n] = tostring(key)
	end

	return t
end

-- return a table containing the values of the provided table
function _M.table_values(table)
	if type(table) ~= "table" then
		logger.fatal_fail(type(table) .. " was given to table_values!")
	end

	local t = {}
	local n = 0

	for _, value in pairs(table) do
		-- if a table as a table of values, we need to break them out and add them individually
		-- request_url_args is an example of this, e.g. ?foo=bar&foo=bar2
		if type(value) == "table" then
			for _, values in pairs(value) do
				n = n + 1
				t[n] = tostring(values)
			end
		else
			n = n + 1
			t[n] = tostring(value)
		end
	end

	return t
end

-- return true if the table key exists
function _M.table_has_key(needle, haystack)
	if type(haystack) ~= "table" then
		logger.fatal_fail("Cannot search for a needle when haystack is type " .. type(haystack))
	end

	return haystack[needle] ~= nil
end

-- determine if the haystack table has a needle for a key
function _M.table_has_value(needle, haystack)
	if type(haystack) ~= "table" then
		logger.fatal_fail("Cannot search for a needle when haystack is type " .. type(haystack))
	end

	for _, value in pairs(haystack) do
		if value == needle then
			return true
		end
	end

	return false
end

-- append the contents of (array-like) table b into table a
function _M.table_append(a, b)
	-- handle some ugliness
	local c = type(b) == 'table' and b or { b }

	local a_count = #a

	for i = 1, #c do
		a_count = a_count + 1
		a[a_count] = c[i]
	end
end

-- pick out dynamic data from storage key definitions
function _M.parse_dynamic_value(waf, key, collections)
	local lookup = function(macro)
		local val, specific
		-- cheat on the start index
		local dot = string_find(macro, "%.", 5)
		if dot then
			val = string_sub(macro, 3, dot - 1)
			specific = string_sub(macro, dot + 1, -2)
		else
			val = string_sub(macro, 3, -2)
		end

		local lval = collections[val]

		if type(lval) == "table" then
			if specific then
				return lval[specific] and tostring(lval[specific]) or
					tostring(lval[string.lower(specific)])
			else
				return val
			end
		else
			return lval
		end
	end

	local str = string_gsub(key, "%%%b{}", lookup)

	--_LOG_"Parsed dynamic value is " .. str

	return tonumber(str) and tonumber(str) or str
end

-- strip harmless trailing commas, e.g. ["aaa","bbb",] or {"aaa":1,}.
-- string contents are left untouched, so this can't change a rule's
-- meaning, only tolerate a stray comma between elements.
local function _strip_trailing_commas(data)
	local out = {}
	local out_n = 0
	local n = #data
	local i = 1
	local in_string = false

	while i <= n do
		local c = string_sub(data, i, i)

		if in_string then
			out_n = out_n + 1
			out[out_n] = c

			if c == "\\" and i < n then
				-- copy the escaped char without interpreting it,
				-- so an escaped quote doesn't end the string early
				i = i + 1
				out_n = out_n + 1
				out[out_n] = string_sub(data, i, i)
			elseif c == '"' then
				in_string = false
			end
		elseif c == '"' then
			in_string = true
			out_n = out_n + 1
			out[out_n] = c
		elseif c == "," then
			local j = i + 1
			while j <= n and string_find(string_sub(data, j, j), "%s") do
				j = j + 1
			end

			local nextc = j <= n and string_sub(data, j, j)

			if nextc == "]" or nextc == "}" then
				-- drop the comma, resume before the closing bracket
				i = j - 1
			else
				out_n = out_n + 1
				out[out_n] = c
			end
		else
			out_n = out_n + 1
			out[out_n] = c
		end

		i = i + 1
	end

	return table_concat(out)
end

-- check that no rule ID in this ruleset is already in the registry.
-- rule IDs are used as lookup keys (ignore_rule, sieve_rule, skip_after,
-- the msg/tag exception table), so a duplicate is a hard error -- except
-- a chain's non-head links, which legitimately repeat the chain head's
-- id (see rule_calc._M.calculate, which threads a chain via consecutive
-- rules where every link but the last has actions.disrupt == "CHAIN")
--
-- a rule with no id at all is not an error: ModSecurity does not require
-- one, so SecRule-translated rulesets carry id-less rules through, and
-- such a rule cannot be the target of an id lookup in the first place.
-- it is only reported, and left out of the registry (indexing it would
-- raise "table index is nil")
function _M.check_duplicate_ids(name, ruleset, registry)
	local errors, errors_n = {}, 0
	local missing, missing_n = {}, 0

	for phase, rules in pairs(ruleset) do
		local prev_rule

		for offset, rule in ipairs(rules) do
			local id = rule.id
			local is_chain_link = prev_rule and prev_rule.id == id and
				prev_rule.actions and prev_rule.actions.disrupt == "CHAIN"

			if is_chain_link then
				-- nothing to register; the chain head already did
			elseif id == nil then
				missing_n = missing_n + 1
				missing[missing_n] = phase .. " offset " .. offset
			else
				local seen_in = registry[id]

				if seen_in == name then
					errors_n = errors_n + 1
					errors[errors_n] = "rule id " .. tostring(id) ..
						" is defined more than once in ruleset " .. name
				elseif seen_in then
					errors_n = errors_n + 1
					errors[errors_n] = "rule id " .. tostring(id) .. " in ruleset " ..
						name .. " is already defined in ruleset " .. seen_in
				else
					registry[id] = name
				end
			end

			prev_rule = rule
		end
	end

	if missing_n > 0 then
		ngx.log(ngx.WARN, "lua-resty-waf: ", missing_n, " rule(s) in ruleset ",
			name, " have no id and cannot be referenced by ignore_rule, ",
			"sieve_rule or skip_after (", table_concat(missing, ", "), ")")
	end

	if errors_n > 0 then
		return nil, table_concat(errors, "; ")
	end

	return true
end

-- safely attempt to parse a JSON string as a ruleset
function _M.parse_ruleset(data)
	local jdata
	local cleaned = _strip_trailing_commas(data)

	if pcall(function() jdata = cjson.decode(cleaned) end) then
		return jdata, nil
	else
		return nil, "could not decode " .. data
	end
end

-- find a rule file with a .json suffix, read it, and return a JSON string
function _M.load_ruleset_file(name)
	for k, v in string_gmatch(package.path, "[^;]+") do
		local path = string_match(k, "(.*/)")

		local full_name = path .. "rules/" .. name .. ".json"

		local f = io.open(full_name)
		if f ~= nil then
			local data = f:read("*all")

			f:close()

			return _M.parse_ruleset(data)
		end
	end

	return nil, "could not find " .. name
end

-- encode a given string as hex
function _M.hex_encode(str)
	return (str:gsub('.', function (c)
		return string_format('%02x', string_byte(c))
	end))
end

-- decode a given hex string
function _M.hex_decode(str)
	local value

	if (pcall(function()
		value = str:gsub('..', function (cc)
			return string_char(tonumber(cc, 16))
		end)
	end)) then
		return value
	else
		return str
	end
end

-- build an RBLDNS query by reversing the octets of an IPv4 address and prepending that to the rbl server name
function _M.build_rbl_query(ip, rbl_srv)
	if type(ip) ~= 'string' then
		return false
	end

	local o1, o2, o3, o4 = ip:match("(%d%d?%d?)%.(%d%d?%d?)%.(%d%d?%d?)%.(%d%d?%d?)")

	if not o1 and not o2 and not o3 and not o4 then
		return false
	end

	local t = { o4, o3, o2, o1, rbl_srv }

	return table_concat(t, '.')
end

-- parse collection elements based on a given directive
-- handlers return the parsed collection and, where its elements can be
-- attributed to a source key, a parallel array where origin_keys[i] names
-- collection[i]. handlers that cannot attribute an element return nil.
_M.parse_collection = {
	specific = function(waf, collection, value)
		--_LOG_"Parse collection is getting a specific value: " .. value
		return collection[value]
	end,
	regex = function(waf, collection, value)
		--_LOG_"Parse collection is geting the regex: " .. value
		local v
		local n = 0
		local _collection = {}
		local origin_keys = {}
		for k, _ in pairs(collection) do
			--_LOG_"checking " .. k
			if ngx.re.find(k, value, waf._pcre_flags) then
				v = collection[k]
				if type(v) == "table" then
					for __, _v in pairs(v) do
						n = n + 1
						_collection[n] = _v
						origin_keys[n] = k
					end
				else
					n = n + 1
					_collection[n] = v
					origin_keys[n] = k
				end
			end
		end
		return _collection, origin_keys
	end,
	keys = function(waf, collection)
		--_LOG_"Parse collection is getting the keys"
		return _M.table_keys(collection)
	end,
	values = function(waf, collection)
		--_LOG_"Parse collection is getting the values"
		local n = 0
		local _collection = {}
		local origin_keys = {}

		for k, v in pairs(collection) do
			local key = tostring(k)

			-- repeated args arrive as a table of values, e.g. ?foo=bar&foo=bar2
			if type(v) == "table" then
				for _, _v in pairs(v) do
					n = n + 1
					_collection[n] = tostring(_v)
					origin_keys[n] = key
				end
			else
				n = n + 1
				_collection[n] = tostring(v)
				origin_keys[n] = key
			end
		end

		return _collection, origin_keys
	end,
	all = function(waf, collection)
		local n, m = 0, 0
		local _collection = {}
		local origin_keys = {}
		local values, value_keys = {}, {}

		-- one pass, but emitted keys first and values second, as callers
		-- have always seen it
		for k, v in pairs(collection) do
			local key = tostring(k)

			n = n + 1
			_collection[n] = key
			origin_keys[n] = key

			if type(v) == "table" then
				for _, _v in pairs(v) do
					m = m + 1
					values[m] = tostring(_v)
					value_keys[m] = key
				end
			else
				m = m + 1
				values[m] = tostring(v)
				value_keys[m] = key
			end
		end

		for i = 1, m do
			n = n + 1
			_collection[n] = values[i]
			origin_keys[n] = value_keys[i]
		end

		return _collection, origin_keys
	end
}

_M.sieve_collection = {
	ignore = function(waf, collection, value)
		--_LOG_"Sieveing specific value " .. value
		collection[value] = nil
	end,
	regex = function(waf, collection, value)
		--_LOG_"Sieveing regex value " .. value
		for k, _ in pairs(collection) do
			--_LOG_"Checking " .. k
			if ngx.re.find(k, value, waf._pcre_flags) then
				--_LOG_"Removing " .. k
				collection[k] = nil
			end
		end
	end,
}

-- build the msg/tag exception table for a given rule
function _M.rule_exception(exception_table, rule)
	if not rule.exceptions then
		return
	end

	local ids   = {}
	local count = 0

	for i, exception in ipairs(rule.exceptions) do
		for key, rules in pairs(exception_table.msgs) do
			if re_find(key, exception, 'jo') then
				for j, id in ipairs(rules) do
					count = count + 1
					ids[count] = id
				end
			end
		end

		for key, rules in pairs(exception_table.tags) do
			if re_find(key, exception, 'jo') then
				for j, id in ipairs(rules) do
					count = count + 1
					ids[count] = id
				end
			end
		end
	end

	if count > 0 then
		exception_table.meta_ids[rule.id] = ids
	end
end

-- function to unpack a nested json array into a single array
function _M.unpack_json(waf, json_object)
    local flat = {}
    util.table_to_fields(json_object, flat, nil, ".", waf._max_json_depth)
    return flat
end

return _M
