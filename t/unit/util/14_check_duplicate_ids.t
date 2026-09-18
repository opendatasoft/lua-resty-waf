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

=== TEST 1: Unique rule ids across two rulesets register cleanly
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
			local util = require "resty.waf.util"
			local registry = {}

			local rs1 = { access = { { id = 1001 } }, log = { { id = 1002 } } }
			local rs2 = { access = { { id = 1003 } } }

			local ok1, err1 = util.check_duplicate_ids("first", rs1, registry)
			local ok2, err2 = util.check_duplicate_ids("second", rs2, registry)

			ngx.say(ok1)
			ngx.say(err1)
			ngx.say(ok2)
			ngx.say(err2)
		}
	}
--- request
GET /t
--- error_code: 200
--- response_body
true
nil
true
nil
--- no_error_log
[error]

=== TEST 2: A duplicate rule id within a single ruleset is rejected
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
			local util = require "resty.waf.util"
			local registry = {}

			local rs = { access = { { id = 2001 }, { id = 2002 }, { id = 2001 } } }

			local ok, err = util.check_duplicate_ids("myruleset", rs, registry)

			ngx.say(ok)
			ngx.say(err)
		}
	}
--- request
GET /t
--- error_code: 200
--- response_body
nil
rule id 2001 is defined more than once in ruleset myruleset
--- no_error_log
[error]

=== TEST 3: A rule id duplicated across two rulesets is rejected
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
			local util = require "resty.waf.util"
			local registry = {}

			local rs1 = { access = { { id = 3001 } } }
			local rs2 = { access = { { id = 3001 } } }

			local ok1 = util.check_duplicate_ids("first", rs1, registry)
			local ok2, err2 = util.check_duplicate_ids("second", rs2, registry)

			ngx.say(ok1)
			ngx.say(ok2)
			ngx.say(err2)
		}
	}
--- request
GET /t
--- error_code: 200
--- response_body
true
nil
rule id 3001 in ruleset second is already defined in ruleset first
--- no_error_log
[error]

=== TEST 4: A chain's non-head links may share the chain head's id
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
			local util = require "resty.waf.util"
			local registry = {}

			local rs = { access = {
				{ id = 4001, actions = { disrupt = "CHAIN" } },
				{ id = 4001, actions = { disrupt = "CHAIN" } },
				{ id = 4001, actions = { disrupt = "DENY" } },
				{ id = 4002 },
			} }

			local ok, err = util.check_duplicate_ids("chained", rs, registry)

			ngx.say(ok)
			ngx.say(err)
		}
	}
--- request
GET /t
--- error_code: 200
--- response_body
true
nil
--- no_error_log
[error]

=== TEST 5: A rule with no id is reported but does not fail the check
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
			local util = require "resty.waf.util"
			local registry = {}

			local rs = { access = { { id = 5001 }, {}, { id = 5002 } } }

			local ok, err = util.check_duplicate_ids("noid", rs, registry)

			ngx.say(ok)
			ngx.say(err)
		}
	}
--- request
GET /t
--- error_code: 200
--- response_body
true
nil
--- error_log
lua-resty-waf: 1 rule(s) in ruleset noid have no id and cannot be referenced by ignore_rule, sieve_rule or skip_after (access offset 2)

=== TEST 6: An id-less chain is reported once, not per link
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
			local util = require "resty.waf.util"
			local registry = {}

			local rs = { access = {
				{ actions = { disrupt = "CHAIN" } },
				{ actions = { disrupt = "DENY" } },
			} }

			local ok, err = util.check_duplicate_ids("noid_chain", rs, registry)

			ngx.say(ok)
			ngx.say(err)
		}
	}
--- request
GET /t
--- error_code: 200
--- response_body
true
nil
--- error_log
lua-resty-waf: 1 rule(s) in ruleset noid_chain have no id and cannot be referenced by ignore_rule, sieve_rule or skip_after (access offset 1)
