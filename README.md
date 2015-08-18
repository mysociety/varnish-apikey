varnish-apikey
==============

Originally from https://code.google.com/p/varnish-apikey/, forked from
https://github.com/thecodeassassin/varnish-apikey and simplified.

This is mostly as per the original varnish-apikey (so far), but with lots of
the unfinished features removed and some changes to the way throttling works.
This means we've removed http referrer checking, user groups and token
checking.

This removes some of the more complicated dependencies, to the point
that the whole Makefile and bundled libraries could also be removed.

This also updates the Redis Varnish module used to a better supported version,
which can be installed independently from Github.

Usage
-----
This provides a set of library functions that can be included into your
Varnish .vcl file. A basic example is included, but you probably want to
customise this to suit. Essentially, you include our VCL file, define a
subroutine to identify requests to your api and extract the api key, then call
our provided method `validate_api` in order to check the key is allowed
access.

Said access is controlled by special keys in Redis database. You have two main
options, which you can enable independently or together. (The following
examples use the direct Redis commands for simplicity, but there is also a
command-line tool that gives access to these various functions with a slightly
simpler interface).

## Restricting access
To only allow users with valid api keys to access your api:

`SET api:<your-api-identifier>:restricted 1`

After this, enable access for specific keys via:

`SET key:<the-key>:api:<your-api-identifier> 1`

## Throttling users
To enable throttling (rate limiting) of your api:

`SET api:<your-api-identifier>:throttle 1`

With this option, you also need to set a few more keys in order to define how
people should be throttled:

First define the acceptable limit for how many hits in how many seconds, e.g.
60 hits in 60 seconds is 1 hit per second, but counted over rolling 60 second
periods.

```
SET api:<your-api-identifier>:counter:time <seconds>
SET api:<your-api-identifier>:default_max <number-of-hits>
```

Next define how long people should be blocked for after they've gone over the
allowed number of hits.

`SET api:<your-api-identifier>:blocked:time <seconds>`

Users will be identified by their api key if they provide a valid one, or
their IP address if not.

Optionally, you can also set per-user throttle limits:

`SET key:<user-identity>:usage:<your-api-identifier>:max <number-of-hits>`

In this case `<user-identity>` can be either their api key, or an IP address.


Dependencies
------------
(For Ubuntu/Debian)
```
sudo apt-get install redis-server varnish libhiredis-dev
```

**Redis**
* redis-server
* libhiredis-dev - [hiredis](https://github.com/redis/hiredis) - minimalistic C client for Redis

**Varnish and Varnish modules**
* varnish
* [libvmod-redis](https://github.com/carlosabalde/libvmod-redis)

Installation
------------
Install the [libvmod-redis](https://github.com/carlosabalde/libvmod-redis)
module as per their instructions.

Copy `vcl/varnish-apikey.vcl` to wherever the rest of your Varnish .vcl files
live, probably `/etc/varnish/varnish-apikey.vcl`.

Run the example
---------------
1. Run varnish

    ```
    cd example
    sudo killall varnishd
    sudo varnishd -a :81 -f example.vcl -s malloc,1G -n example -F
    ```
    Varnish will run in the foreground and listen on port 81

2. Run redis

   ```
   redis-server
   ```

4. Check in browser

    Open the the web browser and check the urls
    - http://localhost:81/tomato
    - http://localhost:81/potato
    They should load articles from Wikipedia on Tomatoes and Potatoes respectively.

5. Restrict api

    Add apikeys and restrict access to api using the command tool:
    ```
    cd ../commandline
    ./apikeys.sh restrict-api tomato
    ./apikeys.sh add-api myapikey tomato
    ```

6. Check in browser again

    Open the browser and verify that api can only be accessed using an apikey:
    - http://localhost:81/tomato (Should return a 401)
    - http://localhost:81/tomato?apikey=myapikey (Should work as before)

(To see what's happening with redis during this, start a redis monitor
connection in a new shell window: `redis-cli monitor`).

Testing
-------
Standard varnish tests of the .vcl file are included in the `tests` directory
along with a shell script that takes care of setting up a redis server for the
tests and cleaning up after it.

You can use this with the standard `varnishtest` utility included with varnish
but wee recommend you use [vtctrans](https://github.com/xcir/vtctrans) to make
the output more understandable.

For example, to run the tests with varnishtest
```
tests/runner.sh varnishtest tests/*.vtc
```

Or with vtctrans:
For example, to run the tests with varnishtest
```
tests/runner.sh python <path-to-vtctrans>/vtctrans.py tests/*.vtc
```

Because of the way `varnishtest` does includes, you must run this from the
project root directory, otherwise it won't find the .vcl file to test.
