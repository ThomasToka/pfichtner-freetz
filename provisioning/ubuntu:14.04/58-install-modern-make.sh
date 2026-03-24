#!/usr/bin/env bash
set -e

# Ubuntu 14.04 ships GNU make 3.81, but Freetz-NG requires >= 3.82.
current_make_version() {
	make --version 2>/dev/null | head -n1 | sed -E 's/.* ([0-9]+\.[0-9]+(\.[0-9]+)?).*/\1/'
}

ver="$(current_make_version || true)"
if [ -n "$ver" ] && dpkg --compare-versions "$ver" ge 3.82; then
	exit 0
fi

MAKE_VER=4.4.1
cd /tmp
wget -q "https://ftp.gnu.org/gnu/make/make-${MAKE_VER}.tar.gz"
tar -xzf "make-${MAKE_VER}.tar.gz"
cd "make-${MAKE_VER}"
./configure --prefix=/usr/local
make -j"$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)"
make install

# Ensure the newer make is used even when /usr/bin is preferred.
ln -sf /usr/local/bin/make /usr/bin/make
