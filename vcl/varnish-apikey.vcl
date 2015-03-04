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

	# Get variables from redis.
	call apikey_call_redis;

	# Do the work.
	if (req.http.restricted == "1") {
		call apikey_check_apikey;
	}

	# Delete the headers.
	call apikey_unset_headers;
}

# Call redis and get all keys.
sub apikey_call_redis {
	# Per api.
	# Use pipelining mode (make all calls first and then get results in bulk).

	redis.pipeline();

	redis.push("GET api:" + req.http.apiname + ":restricted");
	redis.push("GET key:" + req.http.apikey);
	redis.push("GET key:" + req.http.apikey + ":blocked");
	redis.push("GET key:" + req.http.apikey + ":api:all");
	redis.push("GET key:" + req.http.apikey + ":api:" + req.http.apiname);
	set req.http.restricted       = redis.pop();
	set req.http.apikey_exists    = redis.pop();
	set req.http.apikey_blocked   = redis.pop();
	set req.http.apikey_all       = redis.pop();
	set req.http.apikey_api       = redis.pop();
}

sub apikey_check_apikey {
	# Check if api key exists.
	if (req.http.apikey_exists != "1") {
		error 401 "Unknown api key.";
	}

	# Check if api key is blocked.
	if (req.http.apikey_blocked == "1") {
		error 401 "Api key teporarily blocked.";
	}

	# Check if is allowed to use the api.
	if (req.http.apikey_all != "1" && req.http.apikey_api != "1") {
		error 401 "Api not allowed for this api key.";
	}
}

sub apikey_unset_headers {
	unset req.http.apiname;
	unset req.http.apikey;
}
