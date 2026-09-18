use Test::Nginx::Socket::Lua;
use Cwd qw(cwd);

our $pwd = cwd();

our $HttpConfig = qq{
	lua_package_path "$pwd/lib/?.lua;$pwd/t/?.lua;;";
	lua_package_cpath "$pwd/lib/?.lua;;";
};

repeat_each(3);
# TESTS 1-3 and 5-6 have 3 assertions each, TEST 4 has 4
plan tests => repeat_each() * (3 + 3 + 3 + 4 + 3 + 3);

no_shuffle();
run_tests();

__DATA__

=== TEST 1: Log the flattened path of a matching JSON body field
--- http_config eval: $::HttpConfig
--- config
	location /t {
		access_by_lua_block {
			local lua_resty_waf = require "resty.waf"
			local waf           = lua_resty_waf:new()

			waf:set_option("debug", true)
			waf:set_option("mode", "ACTIVE")
			waf:set_option("allow_json_content_type", true)
			waf:set_option("add_ruleset", "12000_mvk")
			waf:exec()
		}

		content_by_lua_block {ngx.exit(ngx.HTTP_OK)}

		log_by_lua_block {
			local lua_resty_waf = require "resty.waf"
			local waf           = lua_resty_waf:new()

			waf:write_log_events()
		}
	}
--- more_headers
Content-Type: application/json
--- request eval
q#POST /t# . qq#\n{"params":{"arguments":{"html":"<p>test</p>"}}}#
--- error_code: 403
--- error_log
"match_var_key":"params.arguments.html"
--- no_error_log
[error]

=== TEST 2: Log the argument name of a matching post argument
--- http_config eval: $::HttpConfig
--- config
	location /t {
		access_by_lua_block {
			local lua_resty_waf = require "resty.waf"
			local waf           = lua_resty_waf:new()

			waf:set_option("debug", true)
			waf:set_option("mode", "ACTIVE")
			waf:set_option("add_ruleset", "12000_mvk")
			waf:exec()
		}

		content_by_lua_block {ngx.exit(ngx.HTTP_OK)}

		log_by_lua_block {
			local lua_resty_waf = require "resty.waf"
			local waf           = lua_resty_waf:new()

			waf:write_log_events()
		}
	}
--- more_headers
Content-Type: application/x-www-form-urlencoded
--- request
POST /t
html=%3Cp%3Etest%3C%2Fp%3E
--- error_code: 403
--- error_log
"match_var_key":"html"
--- no_error_log
[error]

=== TEST 3: match_var_name still carries the collection type
--- http_config eval: $::HttpConfig
--- config
	location /t {
		access_by_lua_block {
			local lua_resty_waf = require "resty.waf"
			local waf           = lua_resty_waf:new()

			waf:set_option("debug", true)
			waf:set_option("mode", "ACTIVE")
			waf:set_option("add_ruleset", "12000_mvk")
			waf:exec()
		}

		content_by_lua_block {ngx.exit(ngx.HTTP_OK)}

		log_by_lua_block {
			local lua_resty_waf = require "resty.waf"
			local waf           = lua_resty_waf:new()

			waf:write_log_events()
		}
	}
--- more_headers
Content-Type: application/x-www-form-urlencoded
--- request
POST /t
html=%3Cp%3Etest%3C%2Fp%3E
--- error_code: 403
--- error_log
"match_var_name":"REQUEST_ARGS"
--- no_error_log
[error]

=== TEST 4: Omit match_var_key when the parse yields no source key
--- http_config eval: $::HttpConfig
--- config
	location /t {
		access_by_lua_block {
			local lua_resty_waf = require "resty.waf"
			local waf           = lua_resty_waf:new()

			waf:set_option("debug", true)
			waf:set_option("mode", "ACTIVE")
			waf:set_option("add_ruleset", "12000_mvk")
			waf:exec()
		}

		content_by_lua_block {ngx.exit(ngx.HTTP_OK)}

		log_by_lua_block {
			local lua_resty_waf = require "resty.waf"
			local waf           = lua_resty_waf:new()

			waf:write_log_events()
		}
	}
--- more_headers
Content-Type: application/x-www-form-urlencoded
--- request
POST /t
attackkey=1
--- error_code: 403
--- error_log
"msg":"mvk keys parse"
--- no_error_log
match_var_key
[error]

=== TEST 5: A rule matching the JSON field, with nothing sieved
--- http_config eval
$::HttpConfig . qq#
	init_worker_by_lua_block {
		local waf = require "resty.waf"
		waf.load_secrules("$::pwd/t/rules/12000_mvk.rules")
		waf.init()
	}
#
--- config
	location /t {
		access_by_lua_block {
			local lua_resty_waf = require "resty.waf"
			local waf           = lua_resty_waf:new()

			waf:set_option("debug", true)
			waf:set_option("mode", "ACTIVE")
			waf:set_option("allow_json_content_type", true)
			waf:set_option("add_ruleset", "12000_mvk.rules")
			waf:exec()
		}

		content_by_lua_block {ngx.exit(ngx.HTTP_OK)}

		log_by_lua_block {
			local lua_resty_waf = require "resty.waf"
			local waf           = lua_resty_waf:new()

			waf:write_log_events()
		}
	}
--- more_headers
Content-Type: application/json
--- request eval
q#POST /t# . qq#\n{"params":{"arguments":{"html":"<p>test</p>"}}}#
--- error_code: 403
--- error_log
"match_var_key":"params.arguments.html"
--- no_error_log
[error]

=== TEST 6: The logged key is what an ignore directive takes
--- http_config eval
$::HttpConfig . qq#
	init_worker_by_lua_block {
		local waf = require "resty.waf"
		waf.load_secrules("$::pwd/t/rules/12000_mvk.rules")
		waf.init()
	}
#
--- config
	location /t {
		access_by_lua_block {
			local lua_resty_waf = require "resty.waf"
			local waf           = lua_resty_waf:new()

			-- the value TEST 5 logs as match_var_key, verbatim
			local sieves = {
				{
					type   = "ARGS",
					elts   = "params.arguments.html",
					action = "ignore"
				}
			}

			waf:set_option("debug", true)
			waf:set_option("mode", "ACTIVE")
			waf:set_option("allow_json_content_type", true)
			waf:set_option("add_ruleset", "12000_mvk.rules")
			waf:sieve_rule("12011", sieves)
			waf:exec()
		}

		content_by_lua_block {ngx.exit(ngx.HTTP_OK)}

		log_by_lua_block {
			local lua_resty_waf = require "resty.waf"
			local waf           = lua_resty_waf:new()

			waf:write_log_events()
		}
	}
--- more_headers
Content-Type: application/json
--- request eval
q#POST /t# . qq#\n{"params":{"arguments":{"html":"<p>test</p>"}}}#
--- error_code: 403
--- no_error_log
Match of rule 12011
[error]
