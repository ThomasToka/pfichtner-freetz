#!/usr/bin/env bash
set -e

# Ubuntu 14.04 has no libzstd-dev package. Build and install zstd from source
# so pkg-config can find libzstd.pc during Freetz prerequisites checks.
ensure_runtime_linker_path() {
	echo '/usr/local/lib' >/etc/ld.so.conf.d/zz-local-libzstd.conf
	ldconfig
}

if pkg-config --exists libzstd 2>/dev/null; then
	ensure_runtime_linker_path
	exit 0
fi

ZSTD_VER=1.5.6
cd /tmp
wget -q "https://github.com/facebook/zstd/releases/download/v${ZSTD_VER}/zstd-${ZSTD_VER}.tar.gz"
tar -xzf "zstd-${ZSTD_VER}.tar.gz"
cd "zstd-${ZSTD_VER}"
make -j"$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)"
make prefix=/usr/local install
ensure_runtime_linker_path
