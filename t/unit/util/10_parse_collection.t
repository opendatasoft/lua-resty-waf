use Test::Nginx::Socket::Lua;
use Cwd qw(cwd);

my $pwd = cwd();

our $HttpConfig = qq{
	lua_package_path "$pwd/lib/?.lua;;";
	lua_package_cpath "$pwd/lib/?.lua;;";
};

repeat_each(3);
plan tests => repeat_each() * 3 * blocks();

no_shuffle();
run_tests();

__DATA__

=== TEST 1: Specific (individual)
--- http_config eval: $::HttpConfig
--- config
	location /t {
		content_by_lua_block {
			local lookup     = require "resty.waf.util"
			local collection = ngx.req.get_uri_args()
			local specific   = lookup.parse_collection["specific"]({}, collection, "foo")
			ngx.say(specific)
		}
	}
--- request
GET /t?foo=bar&baz=qux
--- error_code: 200
--- response_body
bar
--- no_error_log
[error]

=== TEST 2: Specific (table)
--- http_config eval: $::HttpConfig
--- config
	location /t {
		content_by_lua_block {
			local lookup     = require "resty.waf.util"
			local collection = ngx.req.get_uri_args()
			local specific   = lookup.parse_collection["specific"]({}, collection, "foo")
			for i in ipairs(specific) do
				ngx.say(specific[i])
			end
		}
	}
--- request
GET /t?foo=bar&foo=bat&baz=qux
--- error_code: 200
--- response_body
bar
bat
--- no_error_log
[error]

=== TEST 3: Keys (individual)
--- http_config eval: $::HttpConfig
--- config
	location /t {
		content_by_lua_block {
			local lookup     = require "resty.waf.util"
			local collection = ngx.req.get_uri_args()
			local keys       = lookup.parse_collection["keys"]({}, collection, "foo")
			-- table_keys collects via pairs(), whose iteration order
			-- isn't guaranteed, so sort before comparing
			table.sort(keys)
			for i in ipairs(keys) do
				ngx.say(keys[i])
			end
		}
	}
--- request
GET /t?foo=bar&baz=qux
--- error_code: 200
--- response_body
baz
foo
--- no_error_log
[error]

=== TEST 4: Keys (table)
--- http_config eval: $::HttpConfig
--- config
	location /t {
		content_by_lua_block {
			local lookup     = require "resty.waf.util"
			local collection = ngx.req.get_uri_args()
			local keys       = lookup.parse_collection["keys"]({}, collection, "foo")
			-- table_keys collects via pairs(), whose iteration order
			-- isn't guaranteed, so sort before comparing
			table.sort(keys)
			for i in ipairs(keys) do
				ngx.say(keys[i])
			end
		}
	}
--- request
GET /t?foo=bar&foo=bat&baz=qux
--- error_code: 200
--- response_body
baz
foo
--- no_error_log
[error]

=== TEST 5: Values (individual)
--- http_config eval: $::HttpConfig
--- config
	location /t {
		content_by_lua_block {
			local lookup     = require "resty.waf.util"
			local collection = ngx.req.get_uri_args()
			local values     = lookup.parse_collection["values"]({}, collection, "foo")
			-- table_values collects via pairs(), whose iteration order
			-- isn't guaranteed, so sort before comparing
			table.sort(values)
			for i in ipairs(values) do
				ngx.say(values[i])
			end
		}
	}
--- request
GET /t?foo=bar&baz=qux
--- error_code: 200
--- response_body
bar
qux
--- no_error_log
[error]

=== TEST 6: Values (table)
--- http_config eval: $::HttpConfig
--- config
	location /t {
		content_by_lua_block {
			local lookup     = require "resty.waf.util"
			local collection = ngx.req.get_uri_args()
			local values     = lookup.parse_collection["values"]({}, collection, "foo")
			-- table_values collects via pairs(), whose iteration order
			-- isn't guaranteed, so sort before comparing
			table.sort(values)
			for i in ipairs(values) do
				ngx.say(values[i])
			end
		}
	}
--- request
GET /t?foo=bar&foo=bat&baz=qux
--- error_code: 200
--- response_body
bar
bat
qux
--- no_error_log
[error]

=== TEST 7: All (individual)
--- http_config eval: $::HttpConfig
--- config
	location /t {
		content_by_lua_block {
			local lookup     = require "resty.waf.util"
			local collection = ngx.req.get_uri_args()
			local all        = lookup.parse_collection["all"]({}, collection, "foo")
			-- "all" concatenates table_keys()/table_values(), both
			-- collected via pairs(), whose iteration order isn't
			-- guaranteed, so sort before comparing
			table.sort(all)
			for i in ipairs(all) do
				ngx.say(all[i])
			end
		}
	}
--- request
GET /t?foo=bar&baz=qux
--- error_code: 200
--- response_body
bar
baz
foo
qux
--- no_error_log
[error]

=== TEST 8: All (table)
--- http_config eval: $::HttpConfig
--- config
	location /t {
		content_by_lua_block {
			local lookup     = require "resty.waf.util"
			local collection = ngx.req.get_uri_args()
			local all        = lookup.parse_collection["all"]({}, collection, "foo")
			-- "all" concatenates table_keys()/table_values(), both
			-- collected via pairs(), whose iteration order isn't
			-- guaranteed, so sort before comparing
			table.sort(all)
			for i in ipairs(all) do
				ngx.say(all[i])
			end
		}
	}
--- request
GET /t?foo=bar&foo=bat&baz=qux
--- error_code: 200
--- response_body
bar
bat
baz
foo
qux
--- no_error_log
[error]

=== TEST 9: Regex (individual)
--- http_config eval: $::HttpConfig
--- config
	location /t {
		content_by_lua_block {
			local lookup     = require "resty.waf.util"
			local collection = ngx.req.get_uri_args()
			local specific   = lookup.parse_collection["regex"]({ _pcre_flags = "joi" }, collection, [=[^f]=])
			ngx.say(specific)
		}
	}
--- request
GET /t?foo=bar&baz=qux
--- error_code: 200
--- response_body
bar
--- no_error_log
[error]

=== TEST 10: Regex (table)
--- http_config eval: $::HttpConfig
--- config
	location /t {
		content_by_lua_block {
			local lookup     = require "resty.waf.util"
			local collection = ngx.req.get_uri_args()
			local specific   = lookup.parse_collection["regex"]({ _pcre_flags = "joi" }, collection, [=[^f]=])
			for i in ipairs(specific) do
				ngx.say(specific[i])
			end
		}
	}
--- request
GET /t?foo=bar&foo=bat&baz=qux
--- error_code: 200
--- response_body
bar
bat
--- no_error_log
[error]

=== TEST 11: All (key/value layout is unchanged)
--- http_config eval: $::HttpConfig
--- config
	location /t {
		content_by_lua_block {
			local lookup     = require "resty.waf.util"
			local collection = ngx.req.get_uri_args()
			local all        = lookup.parse_collection["all"]({}, collection)

			-- the keys come first, then the values; within each half the
			-- order is pairs() order, so sort before comparing
			local n = 0
			for _ in pairs(collection) do n = n + 1 end

			local keys, values = {}, {}
			for i = 1, n do keys[i] = all[i] end
			for i = n + 1, #all do values[#values + 1] = all[i] end

			table.sort(keys)
			table.sort(values)

			ngx.say(table.concat(keys, ","))
			ngx.say(table.concat(values, ","))
		}
	}
--- request
GET /t?foo=bar&baz=qux
--- error_code: 200
--- response_body
baz,foo
bar,qux
--- no_error_log
[error]

=== TEST 12: All (origin keys)
--- http_config eval: $::HttpConfig
--- config
	location /t {
		content_by_lua_block {
			local lookup            = require "resty.waf.util"
			local collection        = ngx.req.get_uri_args()
			local all, origin_keys  = lookup.parse_collection["all"]({}, collection)

			local t = {}
			for i = 1, #all do t[i] = all[i] .. ":" .. origin_keys[i] end
			table.sort(t)

			ngx.say(table.concat(t, " "))
		}
	}
--- request
GET /t?foo=bar&baz=qux
--- error_code: 200
--- response_body
bar:foo baz:baz foo:foo qux:baz
--- no_error_log
[error]

=== TEST 13: All (origin keys, repeated argument)
--- http_config eval: $::HttpConfig
--- config
	location /t {
		content_by_lua_block {
			local lookup           = require "resty.waf.util"
			local collection       = ngx.req.get_uri_args()
			local all, origin_keys = lookup.parse_collection["all"]({}, collection)

			local t = {}
			for i = 1, #all do t[i] = all[i] .. ":" .. origin_keys[i] end
			table.sort(t)

			ngx.say(table.concat(t, " "))
		}
	}
--- request
GET /t?foo=bar&foo=bat&baz=qux
--- error_code: 200
--- response_body
bar:foo bat:foo baz:baz foo:foo qux:baz
--- no_error_log
[error]

=== TEST 14: Values (origin keys, repeated argument)
--- http_config eval: $::HttpConfig
--- config
	location /t {
		content_by_lua_block {
			local lookup              = require "resty.waf.util"
			local collection          = ngx.req.get_uri_args()
			local values, origin_keys = lookup.parse_collection["values"]({}, collection)

			local t = {}
			for i = 1, #values do t[i] = values[i] .. ":" .. origin_keys[i] end
			table.sort(t)

			ngx.say(table.concat(t, " "))
		}
	}
--- request
GET /t?foo=bar&foo=bat&baz=qux
--- error_code: 200
--- response_body
bar:foo bat:foo qux:baz
--- no_error_log
[error]

=== TEST 15: Regex (origin keys)
--- http_config eval: $::HttpConfig
--- config
	location /t {
		content_by_lua_block {
			local lookup              = require "resty.waf.util"
			local collection          = ngx.req.get_uri_args()
			local values, origin_keys = lookup.parse_collection["regex"]({ _pcre_flags = "joi" }, collection, [=[^f]=])

			local t = {}
			for i = 1, #values do t[i] = values[i] .. ":" .. origin_keys[i] end
			table.sort(t)

			ngx.say(table.concat(t, " "))
		}
	}
--- request
GET /t?foo=bar&foo=bat&baz=qux
--- error_code: 200
--- response_body
bar:foo bat:foo
--- no_error_log
[error]

=== TEST 16: Keys and specific report no origin keys
--- http_config eval: $::HttpConfig
--- config
	location /t {
		content_by_lua_block {
			local lookup     = require "resty.waf.util"
			local collection = ngx.req.get_uri_args()
			local _, keys_origin     = lookup.parse_collection["keys"]({}, collection)
			local _, specific_origin = lookup.parse_collection["specific"]({}, collection, "foo")

			ngx.say(tostring(keys_origin))
			ngx.say(tostring(specific_origin))
		}
	}
--- request
GET /t?foo=bar&baz=qux
--- error_code: 200
--- response_body
nil
nil
--- no_error_log
[error]
