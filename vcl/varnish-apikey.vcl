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
import std;

#
# Public subroutine to be called from user code to validate the api.
#
sub validate_api {
	# This subroutine is provided by the user it should set
	# headers: apiname, apikey, token
	call recognize_apiname_apikey_token;

	# Get apikey variables from redis.
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
	redis.push("GET key:" + req.http.apikey);
	redis.push("GET key:" + req.http.apikey + ":api:all");
	redis.push("GET key:" + req.http.apikey + ":api:" + req.http.apiname);

	set req.http.restricted       = redis.pop();
	set req.http.throttled        = redis.pop();
	set req.http.apikey_exists    = redis.pop();
	set req.http.apikey_all       = redis.pop();
	set req.http.apikey_api       = redis.pop();
}

# Call redis and get throttling setup
sub apikey_call_redis_throttling {
	# Settings. Hardcoded for a moment. Will be read from database in the future.

	set req.http.blocked_time   = "60"; #redis.call("GET settings:blocked:time");
	set req.http.counter_time   = "60"; #redis.call("GET key:" + req.http.apikey + ":usage:" + req.http.apiname + ":time");

	# Per api.
	# Use pipelining mode (make all calls first and then get results in bulk).

	redis.pipeline();
	redis.push("GET key:" + req.http.throttle_identity + ":blocked");
	redis.push("INCR key:" + req.http.throttle_identity + ":usage:" + req.http.apiname + ":count");
	redis.push("GET key:" + req.http.throttle_identity + ":usage:" + req.http.apiname + ":max");
	redis.push("GET key:"  + req.http.throttle_identity + ":usage:" + req.http.apiname + ":reset");

	set req.http.throttle_blocked = redis.pop();
	set req.http.counter_count    = redis.pop();
	set req.http.counter_max      = redis.pop();
	set req.http.counter_reset    = redis.pop();
}

sub apikey_check_apikey {
	# Check if api key exists.
	if (req.http.apikey_exists != "1") {
		error 401 "Unknown api key.";
	}

	# Check if is allowed to use the api.
	if (req.http.apikey_all != "1" && req.http.apikey_api != "1") {
		error 401 "Api not allowed for this api key.";
	}
}

sub apikey_check_throttling {
	# Check if should reset throttling counter.
	if (req.http.counter_reset != "1") {
		redis.pipeline();
		# Reset counter.
		redis.push("SET key:" + req.http.throttle_identity + ":usage:" + req.http.apiname + ":count 0");
		# Set timer to reset the counter
		redis.push("SETEX key:" + req.http.throttle_identity + ":usage:" + req.http.apiname + ":reset " + req.http.counter_time + " 1");
		# Ignore results
		redis.pop2();
		redis.pop2();
	} else {
		# If exceeded number of calls then block.
		if (std.integer(req.http.counter_count, 0) > std.integer(req.http.counter_max, 0)) {
			redis.pipeline();
			# Block api key for some time
			redis.push("SETEX key:" + req.http.throttle_identity + ":blocked " + req.http.blocked_time + " 1");
			# Reset timer
			redis.push("DEL key:" + req.http.throttle_identity + ":usage:" + req.http.apiname + ":reset");
			# Ignore results
			redis.pop2();
			redis.pop2();
		}
	}
	# Check if user is blocked.
	if (req.http.throttle_blocked == "1") {
		error 401 "Api key teporarily blocked.";
	}
}

sub apikey_unset_headers {
	unset req.http.apiname;
	unset req.http.apikey;
	unset req.http.restricted;
	unset req.http.throttled;
	unset req.http.apikey_exists;
	unset req.http.apikey_all;
	unset req.http.apikey_api;
	if (req.http.throttled == "1") {
		unset req.http.throttle_blocked;
		unset req.http.blocked_time;
		unset req.http.counter_time;
		unset req.http.throttle_identity;
		unset req.http.counter_count;
		unset req.http.counter_max;
		unset req.http.counter_reset;
	}
}
