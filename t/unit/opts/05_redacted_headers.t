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

=== TEST 1: The option is registered in options.lookup
--- http_config eval: $::HttpConfig
--- config
	location /t {
		content_by_lua_block {
			local options = require "resty.waf.options"
			ngx.say(type(options.lookup.event_log_redacted_headers))
		}
	}
--- request
GET /t
--- error_code: 200
--- response_body
function
--- no_error_log
[error]

=== TEST 2: Names accumulate across calls and are lowercased
--- http_config eval: $::HttpConfig
--- config
	location /t {
		content_by_lua_block {
			local lua_resty_waf = require "resty.waf"
			local waf           = lua_resty_waf:new()

			waf:set_option("event_log_redacted_headers", { "X-Api-Key", "Authorization" })
			waf:set_option("event_log_redacted_headers", "Cookie")

			local t = {}
			for name in pairs(waf._event_log_redacted_headers) do
				t[#t + 1] = name
			end
			table.sort(t)

			ngx.say(table.concat(t, " "))
		}
	}
--- request
GET /t
--- error_code: 200
--- response_body
authorization cookie x-api-key
--- no_error_log
[error]

=== TEST 3: The set is empty by default
--- http_config eval: $::HttpConfig
--- config
	location /t {
		content_by_lua_block {
			local lua_resty_waf = require "resty.waf"
			local waf           = lua_resty_waf:new()

			ngx.say(tostring(next(waf._event_log_redacted_headers)))
		}
	}
--- request
GET /t
--- error_code: 200
--- response_body
nil
--- no_error_log
[error]
