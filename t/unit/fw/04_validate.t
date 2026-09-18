use Test::Nginx::Socket::Lua;
use Cwd qw(cwd);

my $pwd = cwd();

our $HttpConfig = qq{
	lua_package_path "$pwd/lib/?.lua;$pwd/t/?.lua;;";
	lua_package_cpath "$pwd/lib/?.lua;;";
};

repeat_each(3);
plan tests => repeat_each() * 3 * blocks();

no_shuffle();
run_tests();

__DATA__

=== TEST 1: The distributed rulesets validate cleanly
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
			local waf = require "resty.waf"

			local ok, errors = waf.validate()

			ngx.say(ok)
			ngx.say(#errors)
		}
	}
--- request
GET /t
--- error_code: 200
--- response_body
true
0
--- no_error_log
[error]

=== TEST 2: Every missing ruleset is reported, not just the first
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
			local waf = require "resty.waf"

			local ok, errors = waf.validate({"dne_one", "dne_two"})

			ngx.say(ok)
			ngx.say(#errors)

			for i = 1, #errors do
				ngx.say(errors[i])
			end
		}
	}
--- request
GET /t
--- error_code: 200
--- response_body
false
2
dne_one: could not find dne_one
dne_two: could not find dne_two
--- no_error_log
[error]

=== TEST 3: Unparseable JSON is reported against the ruleset that holds it
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
			local waf = require "resty.waf"

			local ok, errors = waf.validate({"extra_broken"})

			ngx.say(ok)
			ngx.say(#errors)
			ngx.say(errors[1]:match("^[^:]+: could not decode"))
		}
	}
--- request
GET /t
--- error_code: 200
--- response_body
false
1
extra_broken: could not decode
--- no_error_log
[error]

=== TEST 4: A duplicate id within one ruleset is reported
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
			local waf = require "resty.waf"

			local ok, errors = waf.validate({"dup_ids"})

			ngx.say(ok)
			ngx.say(#errors)
			ngx.say(errors[1])
		}
	}
--- request
GET /t
--- error_code: 200
--- response_body
false
1
dup_ids: rule id 90001 is defined more than once in ruleset dup_ids
--- no_error_log
[error]

=== TEST 5: An id reused between two rulesets in the same call is reported
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
			local waf = require "resty.waf"

			local ok, errors = waf.validate({"dup_across_a", "dup_across_b"})

			ngx.say(ok)
			ngx.say(#errors)
			ngx.say(errors[1])
		}
	}
--- request
GET /t
--- error_code: 200
--- response_body
false
1
dup_across_b: rule id 90002 in ruleset dup_across_b is already defined in ruleset dup_across_a
--- no_error_log
[error]

=== TEST 6: init() logs each invalid ruleset and raises, so a reload is refused
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
			local waf = require "resty.waf"

			-- init() reads the module-level list; put it back afterwards so
			-- that repeat_each() runs see the same starting state
			local rulesets = waf.global_rulesets
			rulesets[#rulesets + 1] = "dne_init"

			local ok, err = pcall(waf.init)

			table.remove(rulesets)

			ngx.say(ok)
			ngx.say(err)
		}
	}
--- request
GET /t
--- error_code: 200
--- response_body
false
lua-resty-waf: refusing to start with 1 invalid default ruleset(s), see error log for details
--- error_log
lua-resty-waf: invalid default ruleset - dne_init: could not find dne_init
