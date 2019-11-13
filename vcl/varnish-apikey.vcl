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

#import redis;

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
            if (req.http.apikey_user && req.http.apikey_user != "") {
                set req.http.throttle_identity = req.http.apikey;
            } else {
                set req.http.throttle_identity = req.http.client_ip;
            }
            # Get throttling variables from redis.
            call apikey_call_redis_throttling;
        }

        # Check the key
        if (req.http.restricted == "1") {
            call apikey_check_apikey;
        }

        # Check the rate limit
        if (req.http.throttled == "1") {
            call apikey_check_throttling;
        }

        # Always check the quotas
        call apikey_check_quota;
    }

    # Delete the headers.
    call apikey_unset_headers;
}

# Call redis and get all keys.
sub apikey_call_redis_apikey {
    # Get the three keys we need with a multi-get
    db.command("MGET");
    db.push("api:" + req.http.apiname + ":restricted");
    db.push("api:" + req.http.apiname + ":throttled");
    db.push("key:" + req.http.apikey + ":api:" + req.http.apiname);
    db.execute();
    if ((db.reply_is_array()) &&
        (db.get_array_reply_length() == 3)) {
        set req.http.restricted    = db.get_array_reply_value(0);
        set req.http.throttled     = db.get_array_reply_value(1);
        set req.http.apikey_user = db.get_array_reply_value(2);
    }
    # Note: if we didn't get the correct reply, (i.e. it wasn't an array of
    # 3 values but was an error or something) these headers will just be unset
    # and so the request will be allowed immediately and won't be throttled.

    if (req.http.X-Forwarded-Proto == "https") {
        set req.http.client_ip = req.http.X-Real-IP;
    } else {
        set req.http.client_ip = client.ip;
    }
}

# Call redis and get throttling setup
sub apikey_call_redis_throttling {
    # Set up some default values, because we need these to be present for
    # throttling to work.
    set req.http.blocked_time = 60;
    set req.http.ratelimit_time = 60;
    set req.http.default_max  = 60;

    # Get some info about the general throttling setup for this api
    db.command("MGET");
    db.push("api:" + req.http.apiname + ":blocked:time");
    db.push("api:" + req.http.apiname + ":counter:time");
    db.push("api:" + req.http.apiname + ":default_max");
    db.execute();
    # We're extra careful about only setting these values if redis returned
    # something and the values are not nil because VMODs have some odd nil
    # handling (e.g. https://www.varnish-cache.org/lists/pipermail/varnish-misc/2014-November/024084.html)
    # that I'd rather not try to decipher.
    if ((db.reply_is_array()) &&
        (db.get_array_reply_length() == 3)) {
        if (!db.array_reply_is_nil(0)) {
            set req.http.blocked_time = db.get_array_reply_value(0);
        }
        if (!db.array_reply_is_nil(1)) {
            set req.http.ratelimit_time = db.get_array_reply_value(1);
        }
        if (!db.array_reply_is_nil(2)) {
            set req.http.default_max = db.get_array_reply_value(2);
        }
    }

    # Get the throttling details for this key specifically
    # Again, set a default in case Redis doesn't return anything (more likely
    # this time, e.g. if there's no api key at all).
    set req.http.ratelimit_max = req.http.default_max;
    db.command("MGET");
    db.push("key:" + req.http.throttle_identity + ":api:" + req.http.apiname + ":blocked");
    db.push("key:" + req.http.throttle_identity + ":ratelimit:" + req.http.apiname + ":max");
    db.push("key:" + req.http.throttle_identity + ":ratelimit:" + req.http.apiname + ":reset");
    db.execute();
    # We're extra careful about only setting these values if redis returned
    # something and the values are not nil because VMODs have some odd nil
    # handling (e.g. https://www.varnish-cache.org/lists/pipermail/varnish-misc/2014-November/024084.html)
    # that I'd rather not try to decipher.
    if ((db.reply_is_array()) &&
        (db.get_array_reply_length() == 3)) {
        if (!db.array_reply_is_nil(0)) {
            set req.http.throttle_blocked = db.get_array_reply_value(0);
        }
        if (!db.array_reply_is_nil(1)) {
            set req.http.ratelimit_max = db.get_array_reply_value(1);
        }
        if (!db.array_reply_is_nil(2)) {
            set req.http.ratelimit_reset = db.get_array_reply_value(2);
        }
    }

    # Increment this key's quota usage (just for stats, user quota used for limiting)
    db.command("INCR");
    db.push("key:" + req.http.throttle_identity + ":quota:" + req.http.apiname + ":count");
    db.execute();

    # Increment the rate limit counter (returns the new count)
    db.command("INCR");
    db.push("key:" + req.http.throttle_identity + ":ratelimit:" + req.http.apiname + ":count");
    db.execute();
    # It doesn't matter so much if this fails, we'll just assume it's 0 later
    set req.http.ratelimit_count = db.get_reply();
}

sub apikey_check_apikey {
    # Check if api key exists.
    if (!req.http.apikey_user || req.http.apikey_user == "") {
        call apikey_unset_headers;
        return(synth(401, "Unknown api key."));
    }
}

sub apikey_check_throttling {
    # Check if should reset throttling counter.
    if (req.http.ratelimit_reset != "1") {
        # Reset counter.
        db.command("SET");
        db.push("key:" + req.http.throttle_identity + ":ratelimit:" + req.http.apiname + ":count");
        db.push("0");
        db.execute();

        # Set timer to reset the counter
        db.command("SETEX");
        db.push("key:" + req.http.throttle_identity + ":ratelimit:" + req.http.apiname + ":reset");
        db.push(req.http.ratelimit_time);
        db.push("1");
        db.execute();

    } else {
        # If there's a max, and the user has exceeded the number of calls then
        # block them.
        if (std.integer(req.http.ratelimit_max, 0) > 0) {
            if (std.integer(req.http.ratelimit_count, 0) > std.integer(req.http.ratelimit_max, 0)) {
                # Block api key for some time
                db.command("SETEX");
                db.push("key:" + req.http.throttle_identity + ":api:" + req.http.apiname + ":blocked");
                db.push(req.http.blocked_time);
                db.push("1");
                db.execute();

                # Reset timer
                db.command("DEL");
                db.push("key:" + req.http.throttle_identity + ":ratelimit:" + req.http.apiname + ":reset");
                db.execute();
                set req.http.throttle_blocked = "1";
            }
        }
    }
    if (req.http.throttle_blocked == "1") {
        call apikey_unset_headers;
        return(synth(403, "Api key temporarily blocked."));
    }
}

sub apikey_check_quota {
    if (req.http.apikey_user && req.http.apikey_user != "") {
        set req.http.quota_identity = req.http.apikey_user;
    } else {
        set req.http.quota_identity = req.http.client_ip;
    }

    set req.http.X-Quota-Limit = 50;

    # Get the quota details for this key's user
    db.command("MGET");
    db.push("user:" + req.http.quota_identity + ":quota:" + req.http.apiname + ":blocked");
    db.push("user:" + req.http.quota_identity + ":quota:" + req.http.apiname + ":max");
    db.execute();
    if ((db.reply_is_array()) &&
        (db.get_array_reply_length() == 2)) {
        if (!db.array_reply_is_nil(0)) {
            set req.http.quota_blocked = db.get_array_reply_value(0);
        }
        if (!db.array_reply_is_nil(1)) {
            set req.http.X-Quota-Limit = db.get_array_reply_value(1);
        }
    }

    # Increment the quota limit counter (returns the new count)
    db.command("INCR");
    db.push("user:" + req.http.quota_identity + ":quota:" + req.http.apiname + ":count");
    db.execute();
    set req.http.X-Quota-Current = db.get_reply();

    # If the user has exceeded the maximum number of calls then block them.
    if (std.integer(req.http.X-Quota-Limit, 0) > 0) {
        if (std.integer(req.http.X-Quota-Current, 0) > std.integer(req.http.X-Quota-Limit, 0)) {
            # Block API key/IP address
            db.command("SET");
            db.push("user:" + req.http.quota_identity + ":quota:" + req.http.apiname + ":blocked");
            db.push("1");
            db.execute();
            if (!req.http.apikey_user || req.http.apikey_user == "") {
                db.command("SADD");
                db.push("api:" + req.http.apiname + ":blocked_ips");
                db.push(req.http.client_ip);
                db.execute();
            }
            set req.http.quota_blocked = "1";
        }
    }

    if (req.http.quota_blocked == "1") {
        call apikey_unset_headers;
        return(synth(403, "Usage limit reached."));
    }
}

sub apikey_unset_headers {
    # General
    unset req.http.apiname;
    unset req.http.apikey;
    unset req.http.restricted;
    unset req.http.throttled;
    unset req.http.apikey_user;
    unset req.http.client_ip;
    # Quota
    unset req.http.quota_blocked;
    # Rate limiting
    if (req.http.throttled == "1") {
        unset req.http.throttle_blocked;
        unset req.http.blocked_time;
        unset req.http.ratelimit_time;
        unset req.http.default_max;
        unset req.http.throttle_identity;
        unset req.http.ratelimit_count;
        unset req.http.ratelimit_max;
        unset req.http.ratelimit_reset;
    }
}
