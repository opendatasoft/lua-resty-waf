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

=== TEST 1: Setting an unknown option warns
--- http_config eval: $::HttpConfig
--- config
	location /t {
		access_by_lua_block {
			local lua_resty_waf = require "resty.waf"
			local waf           = lua_resty_waf:new()

			waf:set_option("event_log_taget", "typo")

			ngx.say("ok")
		}

		content_by_lua_block { ngx.exit(ngx.HTTP_OK) }
	}
--- request
GET /t
--- error_code: 200
--- response_body
ok
--- error_log
tried to set unknown option 'event_log_taget'

=== TEST 2: Setting a known option does not warn
--- http_config eval: $::HttpConfig
--- config
	location /t {
		access_by_lua_block {
			local lua_resty_waf = require "resty.waf"
			local waf           = lua_resty_waf:new()

			waf:set_option("debug", true)
			waf:set_option("score_threshold", 10)

			ngx.say("ok")
		}

		content_by_lua_block { ngx.exit(ngx.HTTP_OK) }
	}
--- request
GET /t
--- error_code: 200
--- response_body
ok
--- no_error_log
tried to set unknown option

=== TEST 3: Options defaulting to nil are not mistaken for typos
--- http_config eval: $::HttpConfig
--- config
	location /t {
		access_by_lua_block {
			local lua_resty_waf = require "resty.waf"
			local waf           = lua_resty_waf:new()

			-- these leave no key in the defaults table, so they are the
			-- case most likely to regress into a false warning
			waf:set_option("event_log_target_host", "10.10.10.10")
			waf:set_option("event_log_target_port", 9001)
			waf:set_option("event_log_target_path", "/tmp/waf.log")
			waf:set_option("event_log_periodic_flush", 30)
			waf:set_option("event_log_ssl_sni_host", "log.example.com")

			ngx.say("ok")
		}

		content_by_lua_block { ngx.exit(ngx.HTTP_OK) }
	}
--- request
GET /t
--- error_code: 200
--- response_body
ok
--- no_error_log
tried to set unknown option
