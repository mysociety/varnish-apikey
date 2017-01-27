#!/bin/bash
#
# Authors: Wojciech Mlynarczyk, Sami Kerola
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

# Default settings, do not touch.
SCRIPT_INVOCATION_SHORT_NAME=$(basename ${0})
set -e # exit on errors
trap 'echo "${SCRIPT_INVOCATION_SHORT_NAME}: exit on error"; exit 1' ERR
set -u # disallow usage of unset variables
RETVAL=0

msg() {
	echo "${SCRIPT_INVOCATION_SHORT_NAME}: ${@}"
}

usage() {
	echo "Usage:"
	echo " ${SCRIPT_INVOCATION_SHORT_NAME} functionality [arguments]"
	echo ""
	echo "The functionalities are:"
	echo " restrict-api             api-name"
	echo " unrestrict-api           api-name"
	echo " throttle-api             api-name counter-time blocked-time"
	echo " unthrottle-api           api-name"
	echo " set-api-limit         	api-name limit"
	echo " remove-api-limit      	api-name"
	echo " add-api                  apikey api-name"
	echo " delete-api               apikey api-name"
	echo " block-apikey             apikey api-name time"
	echo " unblock-apikey           apikey api-name"
	echo " set-apikey-limit         apikey api-name limit"
	echo " remove-apikey-limit      apikey api-name"
	echo " clear-database"

	exit ${1}
}

number_of_args() {
	if [ "x${1}" != "x${2}" ]; then
		msg "incorrect number of arguments"
		msg "try \"${SCRIPT_INVOCATION_SHORT_NAME} help\" for information."
		exit 1
	fi
}

restrict-api() {
	redis-cli set api:${1}:restricted 1
}

unrestrict-api() {
	redis-cli del api:${1}:restricted
}

throttle-api() {
	redis-cli set api:${1}:throttled 1
	redis-cli set api:${1}:counter:time ${2}
	redis-cli set api:${1}:blocked:time ${3}
}

unthrottle-api() {
	redis-cli del api:${1}:throttled
	redis-cli del api:${1}:counter:time
	redis-cli del api:${1}:blocked:time
}

set-apikey-limit() {
	redis-cli set api:${1}:default_max ${2}
}

remove-apikey-limit() {
	redis-cli del api:${1}:default_max
}

add-api() {
	redis-cli set key:${1}:api:${2} 1
}

delete-api() {
	redis-cli del key:${1}:api:${2}
}

block-apikey() {
	redis-cli set key:${1}:api:${2}:blocked ${3} 1
}

unblock-apikey() {
	redis-cli del key:${1}:api:${2}:blocked
}

set-apikey-limit() {
	redis-cli set key:${1}:ratelimit:${2}:max ${3}
}

remove-apikey-limit() {
	redis-cli del key:${1}:ratelimit:${2}:max
}

clear-database() {
	redis-cli flushdb
}


# There must be at least one argument.
if [ ${#} -eq 0 ]; then
	usage 1
fi
case "${1}" in
	restrict-api)
		number_of_args ${#} 2
		restrict-api ${2}
		;;
	unrestrict-api)
		number_of_args ${#} 2
		unrestrict-api ${2}
		;;
	throttle-api)
		number_of_args ${#} 4
		throttle-api ${2} ${3} ${4}
		;;
	unthrottle-api)
		number_of_args ${#} 2
		unthrottle-api ${2}
		;;
	add-api)
		number_of_args ${#} 3
		add-api ${2} ${3}
		;;
	delete-api)
		number_of_args ${#} 3
		delete-api ${2} ${3}
		;;
	block-apikey)
		number_of_args ${#} 4
		block-apikey ${2} ${3} ${4}
		;;
	unblock-apikey)
		number_of_args ${#} 3
		unblock-apikey ${2} ${3}
		;;
	set-apikey-limit)
		number_of_args ${#} 4
		block-apikey ${2} ${3} ${4}
		;;
	remove-apikey-limit)
		number_of_args ${#} 3
		block-apikey ${2} ${3}
		;;
	clear-database)
		number_of_args ${#} 1
		clear-database
		;;
	help)
		usage 0
		;;
	*)
		usage 1
		;;
esac

msg "success"

exit ${RETVAL}
# EOF
