#!/usr/bin/env bash
set -e

cat >/usr/local/bin/freetz-apply-compat <<'EOF'
#!/usr/bin/env bash
set -e

WORKSPACE=/workspace/freetz-ng
MARKER="$WORKSPACE/.freetz-legacy-compat-applied"
KCONFIG_MK="$WORKSPACE/make/host-tools/kconfig-host/kconfig-host.mk"
PATCHELF_HOST_MK="$WORKSPACE/make/host-tools/patchelf-host/patchelf-host.mk"
PATCHELF_TARGET_HOST_MK="$WORKSPACE/make/host-tools/patchelf-target-host/patchelf-target-host.mk"
LZMA2_HOST_MK="$WORKSPACE/make/host-tools/lzma2-host/lzma2-host.mk"
PSEUDO_HOST_MK="$WORKSPACE/make/host-tools/pseudo-host/pseudo-host.mk"
UBOOT_HOST_MK="$WORKSPACE/make/host-tools/uboot-host/uboot-host.mk"
PATCHELF_CPP17_PATCH="$WORKSPACE/make/host-tools/patchelf-host/patches/abandon/010-avoid_dependency_on_cpp17.patch"
PATCHELF_TARGET_CPP17_PATCH="$WORKSPACE/make/host-tools/patchelf-target-host/patches/abandon/010-avoid_dependency_on_cpp17.patch"

[ -f "$KCONFIG_MK" ] || exit 0

# Clean stale locale artifacts on every run so interrupted builds recover.
find "$WORKSPACE/source" -type f -path '*/uClibc-ng-*/extra/locale/c8tables.h' -size 0 -delete 2>/dev/null || true

[ -f "$MARKER" ] && exit 0

# Patchelf 0.14.5 git snapshots don't ship src/Makefile.in.
# Remove that hunk from the abandon patch to avoid patch apply failures.
sanitize_patch_file() {
	local patch_file="$1"
	[ -f "$patch_file" ] || return
	grep -q '^--- src/Makefile.in$' "$patch_file" || return 0
	awk '
		BEGIN { skip = 0 }
		/^--- src\/Makefile\.in$/ { skip = 1; next }
		skip && /^--- / { skip = 0 }
		!skip { print }
	' "$patch_file" > "$patch_file.tmp"
	mv "$patch_file.tmp" "$patch_file"
}

sanitize_patch_file "$PATCHELF_CPP17_PATCH"
sanitize_patch_file "$PATCHELF_TARGET_CPP17_PATCH"

find "$WORKSPACE/make/host-tools" -maxdepth 2 -name '*.mk' -type f -exec sed -i 's/-std=gnu17/-std=gnu11/g' {} +

[ -f "$PATCHELF_HOST_MK" ] && sed -i 's#$(call TOOLS_INIT, $(if $(FREETZ_TOOLS_PATCHELF_VERSION_ABANDON),0.14.5,b49de1b33))#$(call TOOLS_INIT, 0.14.5)#' "$PATCHELF_HOST_MK"
[ -f "$PATCHELF_HOST_MK" ] && sed -i 's#$(PKG)_CONDITIONAL_PATCHES+=$(if $(FREETZ_TOOLS_PATCHELF_VERSION_ABANDON),abandon,current)#$(PKG)_CONDITIONAL_PATCHES+=abandon#' "$PATCHELF_HOST_MK"
[ -f "$PATCHELF_TARGET_HOST_MK" ] && sed -i 's#$(call TOOLS_INIT, $(if $(FREETZ_TOOLS_PATCHELF_VERSION_ABANDON),0.14.5,0.15.0))#$(call TOOLS_INIT, 0.14.5)#' "$PATCHELF_TARGET_HOST_MK"
[ -f "$PATCHELF_TARGET_HOST_MK" ] && sed -i 's#$(PKG)_CONDITIONAL_PATCHES+=$(if $(FREETZ_TOOLS_PATCHELF_VERSION_ABANDON),abandon,current)#$(PKG)_CONDITIONAL_PATCHES+=abandon#' "$PATCHELF_TARGET_HOST_MK"

if [ -f "$LZMA2_HOST_MK" ] && ! grep -q '^$(PKG)_CONFIGURE_OPTIONS += --disable-arm64-crc32$' "$LZMA2_HOST_MK"; then
	sed -i '/^$(PKG)_CONFIGURE_OPTIONS += --disable-rpath/a $(PKG)_CONFIGURE_OPTIONS += --disable-arm64-crc32' "$LZMA2_HOST_MK"
fi

if ! grep -q 'HOST_EXTRACFLAGS="-Iscripts/include -std=gnu99"' "$KCONFIG_MK"; then
	sed -i 's/HOST_EXTRACFLAGS="-Iscripts\/include"/HOST_EXTRACFLAGS="-Iscripts\/include -std=gnu99"/' "$KCONFIG_MK"
fi

# Ubuntu 14.04 gnutls headers do not provide gnutls/pkcs7.h.
# Disable mkeficapsule in tools-only config to avoid host build failure.
if [ -f "$UBOOT_HOST_MK" ] && ! grep -q 'TOOLS_MKEFICAPSULE' "$UBOOT_HOST_MK"; then
	awk '
		{ print }
		/tools-only_defconfig$/ {
			print "\t(cd $(UBOOT_HOST_DIR); [ -x scripts/config ] && scripts/config --disable TOOLS_MKEFICAPSULE || true; $(MAKE) olddefconfig)"
		}
	' "$UBOOT_HOST_MK" > "$UBOOT_HOST_MK.tmp"
	mv "$UBOOT_HOST_MK.tmp" "$UBOOT_HOST_MK"
fi

# If uboot-host was already configured before this workaround existed,
# force reconfigure so CONFIG_TOOLS_MKEFICAPSULE gets disabled.
if [ ! -f /usr/include/gnutls/pkcs7.h ]; then
	find "$WORKSPACE/source/host-tools" -maxdepth 2 -type f -path '*/uboot-*/.configured' -delete 2>/dev/null || true
fi

# pseudo 1.9.x openat2 header uses preprocessor constructs unsupported on Ubuntu 14.04.
# Force the fallback struct branch to avoid __has_include parsing entirely.
if [ -f "$PSEUDO_HOST_MK" ] && ! grep -q 'find arch biarch -path '\''*/ports/linux/openat2/portdefs.h'\''' "$PSEUDO_HOST_MK"; then
	sed -i '/^$(PKG)_PATCH_POST_CMDS += cp -a \$(\$(PKG)_MAINARCH_NAME) \$(\$(PKG)_BIARCH_NAME);/a $(PKG)_PATCH_POST_CMDS += find arch biarch -path '\''*\/ports\/linux\/openat2\/portdefs.h'\'' -type f -exec sed -i '\''s|^\\#if .*__has_include.*linux/openat2.h.*|\\#if 0|'\'' {} +' "$PSEUDO_HOST_MK"
fi

if [ -f "$WORKSPACE/.config" ]; then
	grep -q '^FREETZ_ANCIENT_SYSTEM=' "$WORKSPACE/.config" \
		&& sed -i 's/^FREETZ_ANCIENT_SYSTEM=.*/FREETZ_ANCIENT_SYSTEM=y/' "$WORKSPACE/.config" \
		|| echo 'FREETZ_ANCIENT_SYSTEM=y' >> "$WORKSPACE/.config"
	grep -q '^FREETZ_TOOLS_PATCHELF_VERSION_ABANDON=' "$WORKSPACE/.config" \
		&& sed -i 's/^FREETZ_TOOLS_PATCHELF_VERSION_ABANDON=.*/FREETZ_TOOLS_PATCHELF_VERSION_ABANDON=y/' "$WORKSPACE/.config" \
		|| echo 'FREETZ_TOOLS_PATCHELF_VERSION_ABANDON=y' >> "$WORKSPACE/.config"
fi

touch "$MARKER"
EOF

chmod +x /usr/local/bin/freetz-apply-compat

if ! grep -q 'freetz-apply-compat' /etc/bash.bashrc; then
	cat >>/etc/bash.bashrc <<'EOF'

# Apply Freetz compatibility tweaks in interactive shells.
/usr/local/bin/freetz-apply-compat >/dev/null 2>&1 || true
EOF
fi
