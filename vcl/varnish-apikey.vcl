#
# Authors: Wojciech Mlynarczyk
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED.  IN NO EVENT SHALL AUTHOR OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
# OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
# OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
# SUCH DAMAGE.

# Library for authorization based on api key

C{
#include <time.h>
#include <sys/time.h>
#include <stdio.h>
#include <stdlib.h>
}C

import redis;

#
# Public subroutine to be called from user code to validate the api.
#
sub validate_api {
	# This subroutine is provided by the user it should set
	# headers: apiname, apikey, token
	call recognize_apiname_apikey_token;

	# If we've recognised an api, get the apikey variables from redis.
	if (req.http.apiname) {
		call apikey_call_redis_apikey;

		# Determine how to throttle the request (by api key or client ip)
		if (req.http.throttled == "1") {
			if (req.http.apikey_exists == "1") {
				set req.http.throttle_identity = req.http.apikey;
			} else {
				set req.http.throttle_identity = client.ip;
			}
			# Get throttling variables from redis.
			call apikey_call_redis_throttling;
		}

		# Check the key
		if (req.http.restricted == "1") {
			call apikey_check_apikey;
		}

		# Check the usage
		if (req.http.throttled == "1") {
			call apikey_check_throttling;
		}
	}

	# Delete the headers.
	call apikey_unset_headers;
}

# Call redis and get all keys.
sub apikey_call_redis_apikey {
	# Per api.
	# Use pipelining mode (make all calls first and then get results in bulk).

	redis.pipeline();

	redis.push("GET api:" + req.http.apiname + ":restricted");
	redis.push("GET api:" + req.http.apiname + ":throttled");
	redis.push("GET key:" + req.http.apikey + ":api:" + req.http.apiname);

	set req.http.restricted       = redis.pop();
	set req.http.throttled        = redis.pop();
	set req.http.apikey_exists    = redis.pop();
}

# Call redis and get throttling setup
sub apikey_call_redis_throttling {
	set req.http.blocked_time   = redis.call("GET api:" + req.http.apiname + ":blocked:time");
	set req.http.counter_time   = redis.call("GET api:" + req.http.apiname + ":counter:time");
	set req.http.default_max    = redis.call("GET api:" + req.http.apiname + ":default_max");

	# Per api.
	# Use pipelining mode (make all calls first and then get results in bulk).

	redis.pipeline();
	redis.push("GET key:" + req.http.throttle_identity + ":api:" + req.http.apiname + ":blocked");
	redis.push("INCR key:" + req.http.throttle_identity + ":usage:" + req.http.apiname + ":count");
	redis.push("GET key:" + req.http.throttle_identity + ":usage:" + req.http.apiname + ":max");
	redis.push("GET key:" + req.http.throttle_identity + ":usage:" + req.http.apiname + ":reset");

	set req.http.throttle_blocked = redis.pop();
	set req.http.counter_count    = redis.pop();
	set req.http.counter_max      = redis.pop();
	set req.http.counter_reset    = redis.pop();

	# If there's no max set for this particular user (likely if there's no
	# apikey for example) set the max to the default for the api.
	if (!req.http.counter_max) {
		set req.http.counter_max = req.http.default_max;
	}
}

sub apikey_check_apikey {
	# Check if api key exists.
	if (req.http.apikey_exists != "1") {
		error 401 "Unknown api key.";
	}
}

sub apikey_check_throttling {
	# Check if should reset throttling counter.
	if (req.http.counter_reset != "1") {
		# Reset counter.
		redis.send("SET key:" + req.http.throttle_identity + ":usage:" + req.http.apiname + ":count 0");
		# Set timer to reset the counter
		redis.send("SETEX key:" + req.http.throttle_identity + ":usage:" + req.http.apiname + ":reset " + req.http.counter_time + " 1");
	} else {
		# If there's a max, and the user has exceeded the number of calls then
		# block them.
		if(req.http.counter_max) {
			if (std.integer(req.http.counter_count, 0) > std.integer(req.http.counter_max, 0)) {
				# Block api key for some time
				redis.send("SETEX key:" + req.http.throttle_identity + ":api:" + req.http.apiname + ":blocked " + req.http.blocked_time + " 1");
				# Reset timer
				redis.send("DEL key:" + req.http.throttle_identity + ":usage:" + req.http.apiname + ":reset");
				set req.http.throttle_blocked = "1";
			}
		}
	}
	if (req.http.throttle_blocked == "1") {
		error 401 "Api key temporarily blocked.";
	}
}

sub apikey_unset_headers {
	unset req.http.apiname;
	unset req.http.apikey;
	unset req.http.restricted;
	unset req.http.throttled;
	unset req.http.apikey_exists;
	if (req.http.throttled == "1") {
		unset req.http.throttle_blocked;
		unset req.http.blocked_time;
		unset req.http.counter_time;
		unset req.http.default_max;
		unset req.http.throttle_identity;
		unset req.http.counter_count;
		unset req.http.counter_max;
		unset req.http.counter_reset;
	}
}
