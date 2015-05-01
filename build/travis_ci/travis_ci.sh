#!/bin/bash

# Constants
srcdir="$(readlink -e "$(dirname "$0")"/../..)"
objdir="$(readlink -f "$srcdir/../pmbuild")"
logfile="$srcdir/travis.log"

make_swap () {
	set -e

	swap_img_file=$(mktemp --dry-run /tmp/swapXXXXXXXXX.img)
	dd if=/dev/zero of="$swap_img_file" bs=1M count=6144
	sudo mkswap "$swap_img_file"
	sudo swapon "$swap_img_file"
}	

install_deps () {
	set -e

	sudo apt-get update -y --force-yes
	sudo apt-get install -y --force-yes	zip unzip g++ make autoconf2.13 yasm libgtk2.0-dev libglib2.0-dev libdbus-1-dev libdbus-glib-1-dev libasound2-dev libiw-dev libxt-dev mesa-common-dev libgstreamer0.10-dev libgstreamer-plugins-base0.10-dev libpulse-dev m4 flex
}

build_palemoon () {
	set -e

	case $(uname -m) in
		i*86)
			optflags='-msse2 -mfpmath=sse'
			;;
		*)
			optflags=''
			;;
	esac
	echo \
"
mk_add_options MOZ_CO_PROJECT=browser
ac_add_options --enable-application=browser

mk_add_options MOZ_OBJDIR=\"$objdir\"

ac_add_options --disable-installer
ac_add_options --disable-updater

ac_add_options --disable-tests
ac_add_options --disable-mochitests

ac_add_options --enable-jemalloc
ac_add_options --enable-optimize='$optflags'

ac_add_options --x-libraries=/usr/lib
" > "$srcdir/.mozconfig"

	make -f client.mk build
	cd "$objdir"
	make package
}

cd "$srcdir"

if [[ -z "$1" ]]; then
	echo "Action to be performed was not given."
	exit 1
fi

if [[ -z $CONTINUOUS_INTEGRATION ]]; then
	echo "This build is not running in a CI environment. To force the build, use CONTINUOUS_INTEGRATION=true $0"
	exit 1
fi

if [[ -z $palemoon_ci_logging ]]; then
	# Invoke a background process with the the variable defined.
	palemoon_ci_logging=true "$srcdir/build/travis_ci/travis_ci.sh" "$1" &> "$logfile" &
	ps_pid=$!
	echo -n "Started job $1"

	# Keep Travis-CI from killing the build process, by writing something to the screen.
	while kill -0 $ps_pid &>/dev/null; do
		echo -n ' .'
		sleep 30
	done

	wait $ps_pid
	exitstat=$?

	echo -e "\n\nJob '$1' completed with exit status $exitstat"

	if [[ "$(wc -l < "$logfile")" -ge 0 ]]; then
		# There's a maximum logging limit too (4 MB at the time of this writing.)
		echo "Last 200 lines of output from the log:"
		tail -n 200 "$logfile"
	fi
	exit $exitstat
fi

case "$1" in
	deps)
		install_deps
		;;
	build)
		build_palemoon
		;;
	swap)
		make_swap
		;;
	*)
		echo "Unknown job type: $1"
		exit 2
esac
