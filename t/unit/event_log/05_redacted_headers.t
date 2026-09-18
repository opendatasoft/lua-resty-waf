use Test::Nginx::Socket::Lua;
use Cwd qw(cwd);

my $pwd = cwd();

our $HttpConfig = qq{
	lua_package_path "$pwd/lib/?.lua;$pwd/t/?.lua;;";
	lua_package_cpath "$pwd/lib/?.lua;;";
};

repeat_each(3);
# TEST 1 has 3 assertions, TEST 2 has 6, TEST 3 has 4, TEST 4 has 5
plan tests => repeat_each() * (3 + 6 + 4 + 5);

no_shuffle();
run_tests();

__DATA__

=== TEST 1: Log headers in full when no redaction is configured
--- http_config eval: $::HttpConfig
--- config
	location /t {
		access_by_lua_block {
			local lua_resty_waf = require "resty.waf"
			local waf           = lua_resty_waf:new()

			waf:set_option("debug", true)
			waf:set_option("event_log_altered_only", false)
			waf:set_option("event_log_request_headers", true)
			waf:exec()
		}

		content_by_lua_block {ngx.exit(ngx.HTTP_OK)}

		log_by_lua_block {
			local lua_resty_waf = require "resty.waf"
			local waf           = lua_resty_waf:new()

			waf:write_log_events()
		}
	}
--- request
GET /t
--- more_headers
User-Agent: lua-resty-waf Dummy
X-Api-Key: 0123456789abcdef
--- error_code: 200
--- error_log
"x-api-key":"0123456789abcdef"
--- no_error_log
[error]

=== TEST 2: Truncate the named headers and leave the others alone
--- http_config eval: $::HttpConfig
--- config
	location /t {
		access_by_lua_block {
			local lua_resty_waf = require "resty.waf"
			local waf           = lua_resty_waf:new()

			waf:set_option("debug", true)
			waf:set_option("event_log_altered_only", false)
			waf:set_option("event_log_request_headers", true)
			waf:set_option("event_log_redacted_headers", { "X-Api-Key", "authorization" })
			waf:exec()
		}

		content_by_lua_block {ngx.exit(ngx.HTTP_OK)}

		log_by_lua_block {
			local lua_resty_waf = require "resty.waf"
			local waf           = lua_resty_waf:new()

			waf:write_log_events()
		}
	}
--- request
GET /t
--- more_headers
User-Agent: lua-resty-waf Dummy
X-Api-Key: 0123456789abcdef
Authorization: Bearer sometoken
X-Foo: Bar
--- error_code: 200
--- error_log eval
[
qr/"x-api-key":"01234567"/,
qr/"authorization":"Bearer s"/,
qr/"x-foo":"Bar"/
]
--- no_error_log
"x-api-key":"0123456789abcdef"
[error]

=== TEST 3: Leave the header collection itself untouched
--- http_config eval: $::HttpConfig
--- config
	location /t {
		access_by_lua_block {
			local lua_resty_waf = require "resty.waf"
			local waf           = lua_resty_waf:new()

			waf:set_option("debug", true)
			waf:set_option("event_log_altered_only", false)
			waf:set_option("event_log_request_headers", true)
			waf:set_option("event_log_redacted_headers", { "x-api-key" })
			waf:exec()
		}

		content_by_lua_block {ngx.exit(ngx.HTTP_OK)}

		log_by_lua_block {
			local lua_resty_waf = require "resty.waf"
			local waf           = lua_resty_waf:new()

			waf:write_log_events()

			local headers = ngx.ctx.lua_resty_waf.collections["REQUEST_HEADERS"]
			ngx.log(ngx.WARN, "collection x-api-key: ", headers["x-api-key"])
		}
	}
--- request
GET /t
--- more_headers
User-Agent: lua-resty-waf Dummy
X-Api-Key: 0123456789abcdef
--- error_code: 200
--- error_log eval
[
qr/"x-api-key":"01234567"/,
qr/collection x-api-key: 0123456789abcdef/
]
--- no_error_log
[error]

=== TEST 4: A later phase inspecting a redacted header still sees the full value
--- http_config eval: $::HttpConfig
--- config
	location /t {
		access_by_lua_block {
			local lua_resty_waf = require "resty.waf"
			local waf           = lua_resty_waf:new()

			waf:set_option("debug", true)
			waf:set_option("event_log_altered_only", false)
			waf:set_option("event_log_request_headers", true)
			waf:set_option("event_log_redacted_headers", { "x-api-key" })
			waf:set_option("add_ruleset", "12000_redact")
			waf:exec()

			-- write while the transaction is still running, so a redaction
			-- done in place would reach the header_filter rule below
			waf:write_log_events()
		}

		content_by_lua_block {ngx.exit(ngx.HTTP_OK)}

		header_filter_by_lua_block {
			local lua_resty_waf = require "resty.waf"
			local waf           = lua_resty_waf:new()

			waf:exec()
		}

		log_by_lua_block {
			local lua_resty_waf = require "resty.waf"
			local waf           = lua_resty_waf:new()

			waf:write_log_events()
		}
	}
--- request
GET /t
--- more_headers
User-Agent: lua-resty-waf Dummy
X-Api-Key: 0123456789abcdef
--- error_code: 200
--- error_log eval
[
qr/"x-api-key":"01234567"/,
qr/Match of rule 12021/,
qr/"msg":"redact header check"/
]
--- no_error_log
[error]
