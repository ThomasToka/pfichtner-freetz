#!/usr/bin/env bash
set -e

cat >/usr/local/bin/freetz-apply-compat <<'EOF'
#!/usr/bin/env bash
set -e

WORKSPACE=/workspace/freetz-ng
MARKER="$WORKSPACE/.freetz-debian13-arm64-compat-applied"
LIBDTC_HOST_MK="$WORKSPACE/make/host-tools/libdtc-host/libdtc-host.mk"
YF_AKCAREA_HOST_MK="$WORKSPACE/make/host-tools/yf-akcarea-host/yf-akcarea-host.mk"
YF_AKCAREA_SRC_MK="$WORKSPACE/make/host-tools/yf-akcarea-host/src/Makefile"

# Only apply on arm64/aarch64 and only when a checkout is present.
case "$(uname -m)" in
	aarch64|arm64) ;;
	*) exit 0 ;;
esac

[ -f "$WORKSPACE/make/host-tools/Makefile.in" ] || exit 0
[ -f "$MARKER" ] && exit 0

if [ -f "$LIBDTC_HOST_MK" ] && grep -q '^$(PKG)_BUILD_PREREQ += $(if $(HOST_RUN32BIT),,32bit-capable-cpu)$' "$LIBDTC_HOST_MK"; then
	sed -i '/^$(PKG)_BUILD_PREREQ += $(if $(HOST_RUN32BIT),,32bit-capable-cpu)$/d' "$LIBDTC_HOST_MK"
	sed -i '/^$(PKG)_BUILD_PREREQ_HINT := You have to use a 32-bit capable cpu to compile this$/d' "$LIBDTC_HOST_MK"
fi

if [ -f "$YF_AKCAREA_HOST_MK" ] && grep -q '^$(PKG)_BUILD_PREREQ += $(if $(HOST_RUN32BIT),,32bit-capable-cpu)$' "$YF_AKCAREA_HOST_MK"; then
	sed -i '/^$(PKG)_BUILD_PREREQ += $(if $(HOST_RUN32BIT),,32bit-capable-cpu)$/d' "$YF_AKCAREA_HOST_MK"
	sed -i '/^$(PKG)_BUILD_PREREQ_HINT := You have to use a 32-bit capable cpu to compile this$/d' "$YF_AKCAREA_HOST_MK"
fi

if [ -f "$YF_AKCAREA_SRC_MK" ] && grep -q '^BITNESS = -m32$' "$YF_AKCAREA_SRC_MK"; then
	sed -i 's/^BITNESS = -m32$/BITNESS ?=/' "$YF_AKCAREA_SRC_MK"
fi

touch "$MARKER"
EOF

chmod +x /usr/local/bin/freetz-apply-compat

if ! grep -q 'freetz-apply-compat' /etc/bash.bashrc; then
	cat >>/etc/bash.bashrc <<'EOF'

# Apply Debian 13 arm64 Freetz host-tool compatibility tweaks.
/usr/local/bin/freetz-apply-compat >/dev/null 2>&1 || true
EOF
fi
