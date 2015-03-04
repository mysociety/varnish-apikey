varnish-apikey
==============

Originally from https://code.google.com/p/varnish-apikey/, forked from
https://github.com/thecodeassassin/varnish-apikey and simplified.

This is exactly as per the original varnish-apikey (so far), but with lots of
the unfinished features removed. This version only does api key checking and
blocking, no http referrer checking, throttling, user groups or token checking
.

This removes some of the more complicated dependencies, to the point
that the whole Makefile and bundled libraries could also be removed.

This also updates the Redis Varnish module used to the supported version,
which can be installed independently from Github.

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
* [libvmod-redis](https://github.com/brandonwamboldt/libvmod-redis/)

Installation
------------
Install the [libvmod-redis](https://github.com/brandonwamboldt/libvmod-redis/)
module as per their instructions.

Copy `vcl/varnish-apikey.vcl` to wherever the rest of your Varnish .vcl files
live, probably `/etc/varnish/varnish-apikey.vcl`.

Run the example
---------------
1. Run varnish
You can now run Varnish and test the example by typing:
```
cd example
sudo killall varnishd
sudo varnishd -a :81 -f example.vcl -s malloc,1G -n example -F
```
Varnish will run in the foreground and listen on port 81

2. Check in browser
Open the the web browser and check the urls
- http://localhost:81/tomato
- http://localhost:81/potato
They should load articles from Wikipedia on Tomatoes and Potatoes respectively.

3. Restrict api
Add apikeys and restrict access to api using the command tool:
```
cd ../commandline
./apikeys.sh restrict-api tomato
./apikeys.sh add-user woj myapikey
./apikeys.sh add-api woj tomato
```

4. Check in browser again
Open the browser and verify that api can only be accessed using an apikey:
- http://localhost:81/tomato (Should return a 401)
- http://localhost:81/tomato?apikey=myapikey (Should work as before)

