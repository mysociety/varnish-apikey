varnish-apikey
==============

Originally from https://code.google.com/p/varnish-apikey/, forked from
https://github.com/thecodeassassin/varnish-apikey and simplified.

Dependencies
------------
(For Ubuntu/Debian)
sudo apt-get install redis-server varnish libhiredis-dev

**Redis**
* redis-server - [redis](https://github.com/redis/hiredis)
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

