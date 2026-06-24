use Test::Nginx::Socket::Lua;
use Cwd qw(cwd);

our $pwd = cwd();

our $HttpConfig = qq{
	lua_package_path "$pwd/lib/?.lua;;";
	lua_package_cpath "$pwd/lib/?.lua;;";
};

repeat_each(3);
plan tests => repeat_each() * 3 * blocks();

no_shuffle();
run_tests();

__DATA__

=== TEST 1: ARGS sieve still matches a default-ruleset var using "all" parse mode
--- http_config eval
$::HttpConfig . qq#
	init_worker_by_lua_block {
		local waf = require "resty.waf"
		waf.init()
	}
#
--- config
	location /t {
		access_by_lua_block {
			local lua_resty_waf = require "resty.waf"
			local waf           = lua_resty_waf:new()

			-- rule 40001 (40000_generic_attack.json) targets REQUEST_ARGS
			-- with parse = {"all", 1}, the convention used throughout the
			-- shipped default rulesets
			waf:sieve_rule("40001", {
				{ type = "ARGS", elts = "bar", action = "ignore" }
			})

			local var = waf.target_update_map["40001"][1]
			if var.ignore then
				ngx.say(var.ignore[1][1] .. "," .. var.ignore[1][2])
			else
				ngx.say("NOT SIEVED")
			end
		}
	}
--- request
GET /t
--- error_code: 200
--- response_body
ignore,bar
--- no_error_log
[error]

=== TEST 2: sieve_rule on an unknown id does not error
--- http_config eval: $::HttpConfig
--- config
	location /t {
		access_by_lua_block {
			local lua_resty_waf = require "resty.waf"
			local waf           = lua_resty_waf:new()

			local ok = pcall(function()
				waf:sieve_rule("99999999", {
					{ type = "ARGS", elts = "bar", action = "ignore" }
				})
			end)

			ngx.say(ok and "survived" or "crashed")
		}
	}
--- request
GET /t
--- error_code: 200
--- response_body
survived
--- no_error_log
[error]
