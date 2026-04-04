#!/usr/bin/env bash
set -e

cat >/usr/local/bin/freetz-apply-compat <<'EOF'
#!/usr/bin/env bash
set -e

workspace=""
if [ -f /workspace/freetz-ng/Makefile ]; then
	workspace=/workspace/freetz-ng
elif [ -f "$HOME/freetz-ng/Makefile" ]; then
	workspace=$HOME/freetz-ng
fi

[ -n "$workspace" ] || exit 0

MARKER="$workspace/.freetz-legacy-compat-applied"
KCONFIG_MK="$workspace/make/host-tools/kconfig-host/kconfig-host.mk"
PATCHELF_HOST_MK="$workspace/make/host-tools/patchelf-host/patchelf-host.mk"
PATCHELF_TARGET_HOST_MK="$workspace/make/host-tools/patchelf-target-host/patchelf-target-host.mk"
LZMA2_HOST_MK="$workspace/make/host-tools/lzma2-host/lzma2-host.mk"
PSEUDO_HOST_MK="$workspace/make/host-tools/pseudo-host/pseudo-host.mk"
UBOOT_HOST_MK="$workspace/make/host-tools/uboot-host/uboot-host.mk"
YF_AKCAREA_HOST_MK="$workspace/make/host-tools/yf-akcarea-host/yf-akcarea-host.mk"
YF_AKCAREA_SRC_MK="$workspace/make/host-tools/yf-akcarea-host/src/Makefile"
PATCHELF_CPP17_PATCH="$workspace/make/host-tools/patchelf-host/patches/abandon/010-avoid_dependency_on_cpp17.patch"
PATCHELF_TARGET_CPP17_PATCH="$workspace/make/host-tools/patchelf-target-host/patches/abandon/010-avoid_dependency_on_cpp17.patch"

[ -f "$KCONFIG_MK" ] || exit 0

# Clean stale locale artifacts on every run so interrupted builds recover.
find "$workspace/source" -type f -path '*/uClibc-ng-*/extra/locale/c8tables.h' -size 0 -delete 2>/dev/null || true

# Always keep kconfig in C99 mode on Ubuntu 14.04.
# Match any existing HOST_EXTRACFLAGS value and append -std=gnu99 once.
if [ -f "$KCONFIG_MK" ] && ! grep -q 'HOST_EXTRACFLAGS="[^"]* -std=gnu99"' "$KCONFIG_MK"; then
	sed -i -E 's#(HOST_EXTRACFLAGS="[^"]*)"#\1 -std=gnu99"#' "$KCONFIG_MK"
fi

# On arm64/aarch64, yf-akcarea host tool must not enforce 32-bit mode.
case "$(uname -m)" in
	aarch64|arm64)
		if [ -f "$YF_AKCAREA_HOST_MK" ] && grep -q '^$(PKG)_BUILD_PREREQ += $(if $(HOST_RUN32BIT),,32bit-capable-cpu)$' "$YF_AKCAREA_HOST_MK"; then
			sed -i '/^$(PKG)_BUILD_PREREQ += $(if $(HOST_RUN32BIT),,32bit-capable-cpu)$/d' "$YF_AKCAREA_HOST_MK"
			sed -i '/^$(PKG)_BUILD_PREREQ_HINT := You have to use a 32-bit capable cpu to compile this$/d' "$YF_AKCAREA_HOST_MK"
		fi
		if [ -f "$YF_AKCAREA_SRC_MK" ] && grep -q '^BITNESS = -m32$' "$YF_AKCAREA_SRC_MK"; then
			sed -i 's/^BITNESS = -m32$/BITNESS ?=/' "$YF_AKCAREA_SRC_MK"
		fi
		;;
esac

[ -f "$MARKER" ] && exit 0

# Patchelf 0.14.5 git snapshots do not ship src/Makefile.in.
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

# Older GCC in Ubuntu 14.04 cannot handle newer C standards used by host-tools.
find "$workspace/make/host-tools" -maxdepth 2 -name '*.mk' -type f -exec sed -i 's/-std=gnu17/-std=gnu11/g' {} +

# Force patchelf host tools to the legacy variant that does not require C++17.
[ -f "$PATCHELF_HOST_MK" ] && sed -i 's#$(call TOOLS_INIT, $(if $(FREETZ_TOOLS_PATCHELF_VERSION_ABANDON),0.14.5,b49de1b33))#$(call TOOLS_INIT, 0.14.5)#' "$PATCHELF_HOST_MK"
[ -f "$PATCHELF_HOST_MK" ] && sed -i 's#$(PKG)_CONDITIONAL_PATCHES+=$(if $(FREETZ_TOOLS_PATCHELF_VERSION_ABANDON),abandon,current)#$(PKG)_CONDITIONAL_PATCHES+=abandon#' "$PATCHELF_HOST_MK"
[ -f "$PATCHELF_TARGET_HOST_MK" ] && sed -i 's#$(call TOOLS_INIT, $(if $(FREETZ_TOOLS_PATCHELF_VERSION_ABANDON),0.14.5,0.15.0))#$(call TOOLS_INIT, 0.14.5)#' "$PATCHELF_TARGET_HOST_MK"
[ -f "$PATCHELF_TARGET_HOST_MK" ] && sed -i 's#$(PKG)_CONDITIONAL_PATCHES+=$(if $(FREETZ_TOOLS_PATCHELF_VERSION_ABANDON),abandon,current)#$(PKG)_CONDITIONAL_PATCHES+=abandon#' "$PATCHELF_TARGET_HOST_MK"

# Ubuntu 14.04 arm64 headers miss HWCAP_CRC32: disable that optimization.
if [ -f "$LZMA2_HOST_MK" ] && ! grep -q '^$(PKG)_CONFIGURE_OPTIONS += --disable-arm64-crc32$' "$LZMA2_HOST_MK"; then
	sed -i '/^$(PKG)_CONFIGURE_OPTIONS += --disable-rpath/a $(PKG)_CONFIGURE_OPTIONS += --disable-arm64-crc32' "$LZMA2_HOST_MK"
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
	find "$workspace/source/host-tools" -maxdepth 2 -type f -path '*/uboot-*/.configured' -delete 2>/dev/null || true
fi

# pseudo 1.9.x openat2 header uses preprocessor constructs unsupported on Ubuntu 14.04.
# Force the fallback struct branch with a make-safe sed rule that tolerates whitespace.
if [ -f "$PSEUDO_HOST_MK" ]; then
	# Remove previously injected workaround lines and keep one canonical variant.
	sed -i "/^\$(PKG)_PATCH_POST_CMDS += find arch biarch -path '.*ports\/linux\/openat2\/portdefs.h'.*/d" "$PSEUDO_HOST_MK"
	if ! grep -q "openat2/portdefs.h" "$PSEUDO_HOST_MK"; then
		awk '
			{ print }
			index($0, "$(PKG)_PATCH_POST_CMDS += cp -a ") == 1 {
				print "$(PKG)_PATCH_POST_CMDS += find arch biarch -path '\''*/ports/linux/openat2/portdefs.h'\'' -type f -exec sed -i -E '\''s|^[[:space:]]*\\#if[[:space:]]+.*__has_include.*linux/openat2.h.*|\\#if 0|'\'' {} +"
			}
		' "$PSEUDO_HOST_MK" > "$PSEUDO_HOST_MK.tmp"
		mv "$PSEUDO_HOST_MK.tmp" "$PSEUDO_HOST_MK"
	fi
fi

touch "$MARKER"
EOF

chmod +x /usr/local/bin/freetz-apply-compat

sed -i '/^# Apply Freetz compatibility tweaks in interactive shells\.$/,+1d' /etc/bash.bashrc

if ! grep -q 'freetz-compat-prompt-hook' /etc/bash.bashrc; then
	cat >>/etc/bash.bashrc <<'EOF'

# Apply Freetz compatibility tweaks in interactive shells.
# freetz-compat-prompt-hook
_freetz_apply_compat_prompt() {
	/usr/local/bin/freetz-apply-compat >/dev/null 2>&1 || true
}
case ";$PROMPT_COMMAND;" in
	*";_freetz_apply_compat_prompt;"*) ;;
	*) PROMPT_COMMAND="_freetz_apply_compat_prompt${PROMPT_COMMAND:+;$PROMPT_COMMAND}" ;;
esac
_freetz_apply_compat_prompt
EOF
fi
