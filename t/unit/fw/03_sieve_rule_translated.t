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

=== TEST 1: sieve_rule finds a SecRule-translated rule by (string) id
--- http_config eval
$::HttpConfig . qq#
	init_worker_by_lua_block {
		local waf = require "resty.waf"
		waf.load_secrules("$::pwd/t/rules/sieve.rules")
	}
#
--- config
	location /t {
		access_by_lua_block {
			local lua_resty_waf = require "resty.waf"
			local waf           = lua_resty_waf:new()

			waf:sieve_rule("12345", {
				{ type = "ARGS", elts = "bar", action = "ignore" }
			})

			local var = waf.target_update_map["12345"] and waf.target_update_map["12345"][1]
			if var and var.ignore then
				ngx.say(var.ignore[1][1] .. "," .. var.ignore[1][2])
			else
				ngx.say("NOT FOUND")
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

=== TEST 2: sieving ARGS_NAMES does not leak onto a sibling ARGS var
--- http_config eval
$::HttpConfig . qq#
	init_worker_by_lua_block {
		local waf = require "resty.waf"
		waf.load_secrules("$::pwd/t/rules/sieve_multi.rules")
	}
#
--- config
	location /t {
		access_by_lua_block {
			local lua_resty_waf = require "resty.waf"
			local waf           = lua_resty_waf:new()

			waf:sieve_rule("22222", {
				{ type = "ARGS_NAMES", elts = "bar", action = "ignore" }
			})

			local vars = waf.target_update_map["22222"]
			local args_ignore       = vars[1].ignore and (vars[1].ignore[1][1] .. "," .. vars[1].ignore[1][2]) or "NONE"
			local args_names_ignore = vars[2].ignore and (vars[2].ignore[1][1] .. "," .. vars[2].ignore[1][2]) or "NONE"

			ngx.say("ARGS=" .. args_ignore .. " ARGS_NAMES=" .. args_names_ignore)
		}
	}
--- request
GET /t
--- error_code: 200
--- response_body
ARGS=NONE ARGS_NAMES=ignore,bar
--- no_error_log
[error]

=== TEST 3: sieve_ruleset also disambiguates ARGS from ARGS_NAMES
--- http_config eval
$::HttpConfig . qq#
	init_worker_by_lua_block {
		local waf = require "resty.waf"
		waf.load_secrules("$::pwd/t/rules/sieve_multi.rules")
	}
#
--- config
	location /t {
		access_by_lua_block {
			local lua_resty_waf = require "resty.waf"
			local waf           = lua_resty_waf:new()

			waf:sieve_ruleset("sieve_multi.rules", {
				{ type = "ARGS_NAMES", elts = "bar", action = "ignore" }
			})

			local vars = waf.target_update_map["22222"]
			local args_ignore       = vars[1].ignore and (vars[1].ignore[1][1] .. "," .. vars[1].ignore[1][2]) or "NONE"
			local args_names_ignore = vars[2].ignore and (vars[2].ignore[1][1] .. "," .. vars[2].ignore[1][2]) or "NONE"
			local key_on_right_var  = vars[2].collection_key and string.find(vars[2].collection_key, "ignore,bar", 1, true) and "yes" or "no"

			ngx.say("ARGS=" .. args_ignore .. " ARGS_NAMES=" .. args_names_ignore .. " collection_key_updated=" .. key_on_right_var)
		}
	}
--- request
GET /t
--- error_code: 200
--- response_body
ARGS=NONE ARGS_NAMES=ignore,bar collection_key_updated=yes
--- no_error_log
[error]
