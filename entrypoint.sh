#!/usr/bin/env bash
set -e

[ "${COMMAND_NOT_FOUND_AUTOINSTALL}" = 'n' ] && unset COMMAND_NOT_FOUND_AUTOINSTALL || export COMMAND_NOT_FOUND_AUTOINSTALL=y

DEFAULT_BUILD_USER='builduser'

setToDefaults() {
	BUILD_USER="$DEFAULT_BUILD_USER" && BUILD_USER_HOME='/workspace'
}


autoInstallPrerequisites() {
	TOOL=tools/prerequisites

	[ -x "$TOOL" ] || return
	grep -qE 'Usage:.*(check.*install|install.*check)' "$TOOL" || return

	"$TOOL" check || "$TOOL" install -y
}

applyLegacyCompilerCompatibility() {
	# Only patch checked-out Freetz-NG workspaces.
	[ -f "make/host-tools/patchelf-host/patchelf-host.mk" ] || return
	LEGACY_MARKER=".freetz-legacy-compat-applied"
	[ -f "$LEGACY_MARKER" ] && return

	# Older compilers (e.g. Ubuntu 16.04) do not support C++17.
	tmp_cpp17="/tmp/cpp17-test-$$"
	if echo 'int main(){return 0;}' | g++ -x c++ -std=c++17 - -o "$tmp_cpp17" >/dev/null 2>&1; then
		rm -f "$tmp_cpp17"
		return
	fi
	rm -f "$tmp_cpp17"

	# Host-tools with -std=gnu17 must be lowered for old GCC.
	find make/host-tools -maxdepth 2 -name '*.mk' -type f -exec sed -i 's/-std=gnu17/-std=gnu11/g' {} +

	# Force patchelf host tools to legacy variant and always apply abandon patches.
	PATCHELF_HOST_MK="make/host-tools/patchelf-host/patchelf-host.mk"
	PATCHELF_TARGET_HOST_MK="make/host-tools/patchelf-target-host/patchelf-target-host.mk"
	LZMA2_HOST_MK="make/host-tools/lzma2-host/lzma2-host.mk"
	KCONFIG_HOST_MK="make/host-tools/kconfig-host/kconfig-host.mk"

	[ -f "$PATCHELF_HOST_MK" ] && sed -i 's#$(call TOOLS_INIT, $(if $(FREETZ_TOOLS_PATCHELF_VERSION_ABANDON),0.14.5,b49de1b33))#$(call TOOLS_INIT, 0.14.5)#' "$PATCHELF_HOST_MK"
	[ -f "$PATCHELF_HOST_MK" ] && sed -i 's#$(PKG)_CONDITIONAL_PATCHES+=$(if $(FREETZ_TOOLS_PATCHELF_VERSION_ABANDON),abandon,current)#$(PKG)_CONDITIONAL_PATCHES+=abandon#' "$PATCHELF_HOST_MK"
	[ -f "$PATCHELF_TARGET_HOST_MK" ] && sed -i 's#$(call TOOLS_INIT, $(if $(FREETZ_TOOLS_PATCHELF_VERSION_ABANDON),0.14.5,0.15.0))#$(call TOOLS_INIT, 0.14.5)#' "$PATCHELF_TARGET_HOST_MK"
	[ -f "$PATCHELF_TARGET_HOST_MK" ] && sed -i 's#$(PKG)_CONDITIONAL_PATCHES+=$(if $(FREETZ_TOOLS_PATCHELF_VERSION_ABANDON),abandon,current)#$(PKG)_CONDITIONAL_PATCHES+=abandon#' "$PATCHELF_TARGET_HOST_MK"

	# Ubuntu 16.04 arm64 headers miss HWCAP_CRC32: disable that optimization.
	if [ -f "$LZMA2_HOST_MK" ] && ! grep -q '^$(PKG)_CONFIGURE_OPTIONS += --disable-arm64-crc32$' "$LZMA2_HOST_MK"; then
		sed -i '/^$(PKG)_CONFIGURE_OPTIONS += --disable-rpath/a $(PKG)_CONFIGURE_OPTIONS += --disable-arm64-crc32' "$LZMA2_HOST_MK"
	fi

	# kconfig v6.x needs C99 for declarations in for-loops on old GCC defaults.
	if [ -f "$KCONFIG_HOST_MK" ] && ! grep -q 'HOST_EXTRACFLAGS="-Iscripts/include -std=gnu99"' "$KCONFIG_HOST_MK"; then
		sed -i 's/HOST_EXTRACFLAGS="-Iscripts\/include"/HOST_EXTRACFLAGS="-Iscripts\/include -std=gnu99"/' "$KCONFIG_HOST_MK"
	fi

	# Keep required legacy options enabled when a config already exists.
	if [ -f ".config" ]; then
		grep -q '^FREETZ_ANCIENT_SYSTEM=' .config \
			&& sed -i 's/^FREETZ_ANCIENT_SYSTEM=.*/FREETZ_ANCIENT_SYSTEM=y/' .config \
			|| echo 'FREETZ_ANCIENT_SYSTEM=y' >> .config
		grep -q '^FREETZ_TOOLS_PATCHELF_VERSION_ABANDON=' .config \
			&& sed -i 's/^FREETZ_TOOLS_PATCHELF_VERSION_ABANDON=.*/FREETZ_TOOLS_PATCHELF_VERSION_ABANDON=y/' .config \
			|| echo 'FREETZ_TOOLS_PATCHELF_VERSION_ABANDON=y' >> .config
	fi

	# Recover from interrupted uClibc locale builds on old systems.
	find source -type f -path '*/uClibc-ng-*/extra/locale/c8tables.h' -size 0 -delete 2>/dev/null || true
	find source -type f -path '*/uClibc-ng-*/extra/locale/gen_locale' -delete 2>/dev/null || true

	touch "$LEGACY_MARKER"
}



# for backwards compatibility
if [ -z "$BUILD_USER" ] && [ -z "$BUILD_USER_HOME" ] && [ -z "$BUILD_USER_UID" ]; then
	setToDefaults
	[ -z "$USE_UID_FROM" ] && USE_UID_FROM="$BUILD_USER_HOME"
	[ "$PWD" == "/" ] && cd "$BUILD_USER_HOME"
fi

# ignore PARAMS BUILD_USER and BUILD_USER_HOME (use defaults) if not root
[ `id -u` -eq 0 ] || setToDefaults

[ -z "$BUILD_USER" ] && BUILD_USER="$DEFAULT_BUILD_USER"
[ -n "$USE_UID_FROM" ] && BUILD_USER_UID=`stat -c "%u" $USE_UID_FROM`

if [ `id -u` -eq 0 ]; then
	# better read HOME/DHOME from /etc/default/useradd /etc/adduser.conf
	[ -z "$BUILD_USER_HOME" ] && BUILD_USER_HOME=/home/$BUILD_USER

	USERADD="useradd -G sudo -s /bin/bash -d $BUILD_USER_HOME"
	[ -d "$BUILD_USER_HOME" ] && USERADD="$USERADD -M" || USERADD="$USERADD -m"
	if [ -n "$BUILD_USER_UID" ]; then
		USERADD="$USERADD -u $BUILD_USER_UID"
		# delete a user if there is already a user with that UID
		TMP_DEL_USER=`getent passwd $BUILD_USER_UID | cut -d':' -f1` && [ -n "$TMP_DEL_USER" ] && [ "$DEFAULT_BUILD_USER" != "$TMP_DEL_USER" ] && userdel $TMP_DEL_USER >/dev/null 2>/dev/null
	fi

	[ -n "$BUILD_USER_GID" ] && USERADD="$USERADD -g $BUILD_USER_GID" && (getent group "$BUILD_USER_GID" || groupadd "$BUILD_USER_GID" "$BUILD_USER")

	USERADD="$USERADD $BUILD_USER"
	# remove the default builduser created in Dockerfile that exists in image
	userdel "$DEFAULT_BUILD_USER"
	eval "$USERADD"
fi

# if there are missing prerequisites we try to install them via tools/prerequisites
if [ "${AUTOINSTALL_PREREQUISITES}" != 'n' ]; then
	export -f autoInstallPrerequisites
	export -f applyLegacyCompilerCompatibility
	if [ `id -u` -eq 0 ]; then
		su "$BUILD_USER" -c applyLegacyCompilerCompatibility || true
		su "$BUILD_USER" -c autoInstallPrerequisites || true
	else
		applyLegacyCompilerCompatibility || true
		autoInstallPrerequisites || true
	fi
	unset autoInstallPrerequisites
	unset applyLegacyCompilerCompatibility
fi

DEFAULT_SHELL=`getent passwd $BUILD_USER | cut -f 7 -d':'`
if [ `id -u` -eq 0 ]; then
	[ "$#" -gt 0 ] && exec gosu "$BUILD_USER" "$@" || exec gosu "$BUILD_USER" "$DEFAULT_SHELL"
else
	[ "$#" -gt 0 ] && exec "$@" || exec "$DEFAULT_SHELL"
fi

