#!/usr/bin/env bash
set -e

# When sourced by non-root login shells, just run the helper if present.
if [ "$(id -u)" -ne 0 ]; then
	if [ -x /usr/local/bin/freetz-apply-compat ]; then
		/usr/local/bin/freetz-apply-compat >/dev/null 2>&1 || true
	fi
	return 0 2>/dev/null || true
else
cat >/usr/local/bin/freetz-apply-compat <<'EOF'
#!/usr/bin/env bash
set -e

WORKSPACE=/workspace/freetz-ng
MARKER="$WORKSPACE/.freetz-debian13-arm64-compat-applied"
LIBDTC_HOST_MK="$WORKSPACE/make/host-tools/libdtc-host/libdtc-host.mk"
YF_AKCAREA_HOST_MK="$WORKSPACE/make/host-tools/yf-akcarea-host/yf-akcarea-host.mk"
YF_AKCAREA_SRC_MK="$WORKSPACE/make/host-tools/yf-akcarea-host/src/Makefile"
BASH_MK="$WORKSPACE/make/pkgs/bash/bash.mk"
FWMOD_FILE="$WORKSPACE/fwmod"
AVM_CFG_5690_0820="$WORKSPACE/make/kernel/configs/avm/config-alder-5690_08.20"
FREETZ_CFG_5690_0820="$WORKSPACE/make/kernel/configs/freetz/config-alder-5690_08.20"
FREETZ_MAIN_CONFIG="$WORKSPACE/.config"
OPENSSL_HOST_TOOLS_GLOB="$WORKSPACE/source/host-tools/openssl-*"
PRELINK_DOC_TEX="$WORKSPACE/source/host-tools/prelink-20131005/doc/prelink.tex"
LIBMULTID_DIR_GLOB="$WORKSPACE/source/target-*/libmultid-1.0"
SYMVERS_DIR="$WORKSPACE/make/kernel/configs/symvers"

# Only apply on arm64/aarch64 and only when a checkout is present.
case "$(uname -m)" in
	aarch64|arm64) ;;
	*) exit 0 ;;
esac

[ -f "$WORKSPACE/make/host-tools/Makefile.in" ] || exit 0

if [ ! -f "$MARKER" ]; then
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

	if [ -f "$BASH_MK" ] && ! grep -q '^$(PKG)_CONFIGURE_PRE_CMDS += $(call PKG_UPDATE_CONFIGS,./support)' "$BASH_MK"; then
		sed -i '/^$(PKG)_PATCH_POST_CMDS += $(call PKG_ADD_EXTRA_FLAGS,(C|LD)FLAGS)$/a $(PKG)_DEPENDS_ON += config-host\n$(PKG)_CONFIGURE_PRE_CMDS += $(call PKG_UPDATE_CONFIGS,./support)' "$BASH_MK"
	fi

	if [ -f "$BASH_MK" ] && ! grep -q "shell_version_string __P((void))" "$BASH_MK"; then
		sed -i '/^$(PKG)_PATCH_POST_CMDS += $(call PKG_ADD_EXTRA_FLAGS,(C|LD)FLAGS)$/a $(PKG)_PATCH_POST_CMDS += grep -Fq '\''shell_version_string __P((void))'\'' support/bashversion.c || { $(SED) -i '\''/conftypes.h"/a extern char *shell_version_string __P((void));'\'' support/bashversion.c; $(SED) -i '\''/shell_version_string __P((void));/a extern void show_shell_version __P((int));'\'' support/bashversion.c; };' "$BASH_MK"
	fi

	touch "$MARKER"
fi

# If 5690_08.20 freetz kernel config drifts too far from AVM config, modules can fail to load
# on stock kernels due to modversion CRC mismatches (x_tables disagrees about version of symbol).
if [ -f "$AVM_CFG_5690_0820" ] && [ -f "$FREETZ_CFG_5690_0820" ]; then
	cfg_diff_count="$(diff -u "$AVM_CFG_5690_0820" "$FREETZ_CFG_5690_0820" 2>/dev/null | grep -E '^[+-](CONFIG_|# CONFIG_)' | wc -l || true)"
	case "$cfg_diff_count" in
		''|*[!0-9]*) cfg_diff_count=0 ;;
	esac
	if [ "$cfg_diff_count" -gt 20 ]; then
		cp "$AVM_CFG_5690_0820" "$FREETZ_CFG_5690_0820"
		sed -i '/^CONFIG_CC_CAN_LINK=y$/d' "$FREETZ_CFG_5690_0820"
	fi

	# Keep selected netfilter symbols aligned with AVM config to avoid module ABI drift
	# on the vendor kernel where only shipped-compatible modules can be loaded.
	sync_kcfg_symbol_from_avm() {
		local sym="$1" avm_line
		avm_line="$(grep -E "^${sym}=|^# ${sym} is not set$" "$AVM_CFG_5690_0820" | tail -n1 || true)"
		[ -n "$avm_line" ] || return 0
		sed -i "/^${sym}=.*/d;/^# ${sym} is not set$/d" "$FREETZ_CFG_5690_0820"
		echo "$avm_line" >> "$FREETZ_CFG_5690_0820"
	}
	for sym in \
		CONFIG_NF_CONNTRACK \
		CONFIG_NF_NAT \
		CONFIG_IP_NF_NAT \
		CONFIG_IP_NF_TARGET_MASQUERADE \
		CONFIG_NETFILTER_XT_MATCH_CONNTRACK \
		CONFIG_NETFILTER_XT_NAT \
		CONFIG_IP_NF_IPTABLES \
		CONFIG_NETFILTER_XT_TARGET_TRACE; do
		sync_kcfg_symbol_from_avm "$sym"
	done
fi

if [ -f "$FWMOD_FILE" ] && ! grep -q 'auto-include nf_reject providers for REJECT targets' "$FWMOD_FILE"; then
	awk 'BEGIN{done=0} {
		print
		if (!done && index($0,"ko_install=\"$(eval \"echo \\\"$FREETZ_MODULE_$ko_symbol\\\"\")\"")>0) {
			print "                        # auto-include nf_reject providers for REJECT targets"
			print "                        if [ \"$ko_symbol\" = \"nf_reject_ipv4\" ] || [ \"$ko_symbol\" = \"nf_reject_ipv6\" ]; then"
			print "                                if [ \"$FREETZ_MODULE_ipt_REJECT\" = \"y\" ] || [ \"$FREETZ_MODULE_ip6t_REJECT\" = \"y\" ] || [ \"$FREETZ_MODULE_xt_REJECT\" = \"y\" ]; then"
			print "                                        ko_install=\"y\""
			print "                                fi"
			print "                        fi"
			print "                        # on 5690_08.20 stock kernel x_tables is built-in; avoid duplicate module only there"
			print "                        if [ \"$FREETZ_AVM_SOURCE_ID\" = \"5690_08.20\" ] && [ \"$ko_symbol\" = \"x_tables\" ]; then"
			print "                                ko_install=\"n\""
			print "                        fi"
			print "                        # in replace-kernel mode, always ship core NAT/conntrack modules"
			print "                        if [ \"$FREETZ_AVM_SOURCE_ID\" = \"5690_08.20\" ] && [ \"$FREETZ_REPLACE_KERNEL\" = \"y\" ]; then"
			print "                                case \"$ko_symbol\" in"
			print "                                        nf_conntrack|nf_nat|iptable_nat|xt_conntrack|xt_MASQUERADE|nf_reject_ipv4|nf_reject_ipv6)"
			print "                                                ko_install=\"y\""
			print "                                                ;;"
			print "                                esac"
			print "                        fi"
			done=1
		}
	}' "$FWMOD_FILE" > "$FWMOD_FILE.new" && mv "$FWMOD_FILE.new" "$FWMOD_FILE" && chmod +x "$FWMOD_FILE"
fi

# Remove previously injected NAT force-install block and keep fwmod aligned with shipped modules.
if [ -f "$FWMOD_FILE" ] && grep -q 'ship core NAT/conntrack modules needed for nat table' "$FWMOD_FILE"; then
	perl -0777 -i -pe 's@\n\s*# on 5690_08\.20 ship core NAT/conntrack modules needed for nat table\n\s*if \[ "\$FREETZ_AVM_SOURCE_ID" = "5690_08\.20" \]; then\n\s*case "\$ko_symbol" in\n\s*nf_conntrack\|nf_nat\|iptable_nat\|xt_conntrack\|xt_MASQUERADE\)\n\s*ko_install="y"\n\s*;;\n\s*esac\n\s*fi@@g' "$FWMOD_FILE"
	chmod +x "$FWMOD_FILE"
fi

# Normalize legacy injected conditions so x_tables is always skipped on 5690_08.20.
if [ -f "$FWMOD_FILE" ]; then
	perl -0777 -i -pe 's@if \[ "\$FREETZ_AVM_SOURCE_ID" = "5690_08\.20" \] && \[ "\$ko_symbol" = "x_tables" \] && \[ "\$FREETZ_REPLACE_KERNEL" != "y" \]; then@if [ "\$FREETZ_AVM_SOURCE_ID" = "5690_08.20" ] && [ "\$ko_symbol" = "x_tables" ]; then@g' "$FWMOD_FILE"
	perl -0777 -i -pe 's@if \[ "\$FREETZ_AVM_SOURCE_ID" = "5690_08\.20" \] && \[ "\$ko" = "x_tables" \] && \[ "\$FREETZ_REPLACE_KERNEL" != "y" \]; then@if [ "\$FREETZ_AVM_SOURCE_ID" = "5690_08.20" ] && [ "\$ko" = "x_tables" ]; then@g' "$FWMOD_FILE"
	chmod +x "$FWMOD_FILE"
fi

if [ -f "$FWMOD_FILE" ] && ! grep -q 'force-skip x_tables on 5690_08.20' "$FWMOD_FILE"; then
	perl -0777 -i -pe 's@\n\s*ko_install="\$\(eval "echo \\"\$FREETZ_MODULE_\$ko_symbol\\""\)"\n@\n                        ko_install="\$(eval "echo \"\$FREETZ_MODULE_\$ko_symbol\"")"\n                        # force-skip x_tables on 5690_08.20 (built into running kernel)\n                        if [ "\$FREETZ_AVM_SOURCE_ID" = "5690_08.20" ] && [ "\$ko_symbol" = "x_tables" ]; then\n                                ko_install="n"\n                        fi\n@' "$FWMOD_FILE"
	chmod +x "$FWMOD_FILE"
fi

if [ -f "$FWMOD_FILE" ] && ! grep -q 'AVM kernels ship x_tables/xt_tcpudp built-in (=y)' "$FWMOD_FILE"; then
	awk 'BEGIN{done=0} {
		print
		if (!done && index($0,"[ \"$ko\" == \"freetz\" ] && [ \"$FREETZ_MODULES_TEST\" == \"y\" ] && continue")>0) {
			print "                        # AVM kernels ship x_tables/xt_tcpudp built-in (=y), so no .ko exists."
			print "                        if [ \"$FREETZ_AVM_SOURCE_ID\" = \"5690_08.20\" ] && [ \"$ko\" = \"x_tables\" ]; then"
			print "                                continue"
			print "                        fi"
			print "                        if [ \"$FREETZ_REPLACE_KERNEL\" != \"y\" ] && [ \"$ko\" = \"xt_tcpudp\" ] && grep -q \"^CONFIG_NETFILTER_XT_MATCH_TCPUDP=y$\" \"${KERNEL_REP_DIR}/linux-${FREETZ_KERNEL_VERSION_MAJOR}/.config\"; then"
			print "                                continue"
			print "                        fi"
			done=1
		}
	}' "$FWMOD_FILE" > "$FWMOD_FILE.new" && mv "$FWMOD_FILE.new" "$FWMOD_FILE" && chmod +x "$FWMOD_FILE"
fi

# Some OpenSSL 3.x host-tool recipes may still invoke ./configure while upstream ships
# Configure/config. Ensure a compatibility symlink exists and force reconfigure when needed.
for openssl_src_dir in $OPENSSL_HOST_TOOLS_GLOB; do
	[ -d "$openssl_src_dir" ] || continue
	if [ -f "$openssl_src_dir/Configure" ] && [ ! -e "$openssl_src_dir/configure" ]; then
		ln -s Configure "$openssl_src_dir/configure"
		rm -f "$openssl_src_dir/.configured"
	fi
done

# prelink doc source still uses legacy glossary commands that are not provided by
# current TeX Live defaults. Rewrite to glossaries package/commands so host-tools
# build does not fail on PDF generation.
if [ -f "$PRELINK_DOC_TEX" ]; then
	sed -i 's/^usepackage{glossaries}$/\\usepackage{glossaries}/' "$PRELINK_DOC_TEX"
	if ! grep -q '^\\usepackage{glossaries}$' "$PRELINK_DOC_TEX"; then
		awk '{
			print
			if ($0 == "\\usepackage{nomencl}") {
				print "\\usepackage{glossaries}"
			}
		}' "$PRELINK_DOC_TEX" > "$PRELINK_DOC_TEX.new" && mv "$PRELINK_DOC_TEX.new" "$PRELINK_DOC_TEX"
	fi
	sed -i 's/^\\makeglossary$/\\makeglossaries/' "$PRELINK_DOC_TEX"
	sed -i 's/^\\printglossary$/\\printglossaries/' "$PRELINK_DOC_TEX"
fi

# On 5690_08.20 the running AVM kernel may already provide x_tables built-in.
# Shipping x_tables.ko/xt_tcpudp.ko can then trigger duplicate symbol collisions at runtime.
if [ -f "$FREETZ_MAIN_CONFIG" ] && grep -q '^FREETZ_AVM_SOURCE_5690_08_20=y$' "$FREETZ_MAIN_CONFIG"; then
	set_maincfg_symbol() {
		local sym="$1" val="$2"
		sed -i "/^${sym}=.*/d;/^# ${sym} is not set$/d" "$FREETZ_MAIN_CONFIG"
		echo "${sym}=${val}" >> "$FREETZ_MAIN_CONFIG"
	}
	unset_maincfg_symbol() {
		local sym="$1"
		sed -i "/^${sym}=.*/d;/^# ${sym} is not set$/d" "$FREETZ_MAIN_CONFIG"
		echo "# ${sym} is not set" >> "$FREETZ_MAIN_CONFIG"
	}
	set_maincfg_string() {
		local sym="$1" val="$2"
		sed -i "/^${sym}=.*/d;/^# ${sym} is not set$/d" "$FREETZ_MAIN_CONFIG"
		echo "${sym}=\"${val}\"" >> "$FREETZ_MAIN_CONFIG"
	}

	# To get NAT working reliably, kernel and modules must come from the same build.
	# Enforce kernel replacement and required NAT module package selections.
	set_maincfg_symbol FREETZ_REPLACE_KERNEL y
	set_maincfg_symbol FREETZ_PACKAGE_IPTABLES y
	set_maincfg_symbol FREETZ_PACKAGE_IPTABLES_KERNEL_MODULES y
	# nf_conntrack is built-in on this target kernel config; do not ship as .ko.
	unset_maincfg_symbol FREETZ_MODULE_nf_conntrack
	set_maincfg_symbol FREETZ_MODULE_nf_nat y
	set_maincfg_symbol FREETZ_MODULE_iptable_nat y
	set_maincfg_symbol FREETZ_MODULE_xt_conntrack y
	set_maincfg_symbol FREETZ_MODULE_ipt_MASQUERADE y
	set_maincfg_string FREETZ_MODULES_OWN "nf_nat iptable_nat xt_conntrack xt_MASQUERADE nf_reject_ipv4 nf_reject_ipv6"

	# Only suppress x_tables/xt_tcpudp when running stock AVM kernel modules.
	if ! grep -q '^FREETZ_REPLACE_KERNEL=y$' "$FREETZ_MAIN_CONFIG"; then
		sed -i 's/^FREETZ_MODULE_x_tables=y$/# FREETZ_MODULE_x_tables is not set/' "$FREETZ_MAIN_CONFIG"
		sed -i 's/^FREETZ_MODULE_xt_tcpudp=y$/# FREETZ_MODULE_xt_tcpudp is not set/' "$FREETZ_MAIN_CONFIG"
	fi
fi

# Avoid stale duplicate netfilter modules from previous builds.
rm -f "$WORKSPACE"/build/modified/filesystem/lib/modules/*/kernel/net/netfilter/x_tables.ko
rm -f "$WORKSPACE"/build/modified/filesystem/lib/modules/*/kernel/net/netfilter/nf_conntrack.ko
rm -f "$WORKSPACE"/source/kernel/ref-*/lib/modules/*/kernel/net/netfilter/nf_conntrack.ko

# Some workflows expect this directory to exist for copying generated symvers snapshots.
mkdir -p "$SYMVERS_DIR"
chown --reference="$WORKSPACE" "$SYMVERS_DIR" 2>/dev/null || true

# Recover from stale build stamps: some interrupted builds leave .compiled for libmultid
# but remove libmultid.so.*, causing later packaging to fail with missing file errors.
for libmultid_dir in $LIBMULTID_DIR_GLOB; do
	[ -d "$libmultid_dir" ] || continue
	if [ -f "$libmultid_dir/.compiled" ] && ! ls "$libmultid_dir"/libmultid.so.* >/dev/null 2>&1; then
		rm -f "$libmultid_dir/.compiled"
	fi
done

EOF

chmod +x /usr/local/bin/freetz-apply-compat

if ! command -v pdfopt >/dev/null 2>&1; then
	cat >/usr/local/bin/pdfopt <<'EOF'
#!/usr/bin/env bash
set -e

input_pdf="$1"
output_pdf="$2"

if [ -z "$input_pdf" ] || [ -z "$output_pdf" ]; then
	echo "usage: pdfopt <input.pdf> <output.pdf>" >&2
	exit 1
fi

if command -v gs >/dev/null 2>&1; then
	gs -q -dNOPAUSE -dBATCH -sDEVICE=pdfwrite -dCompatibilityLevel=1.4 \
		-dPDFSETTINGS=/printer -sOutputFile="$output_pdf" "$input_pdf" >/dev/null 2>&1 \
		|| cp -f "$input_pdf" "$output_pdf"
else
	cp -f "$input_pdf" "$output_pdf"
fi
EOF
	chmod +x /usr/local/bin/pdfopt
fi

if ! grep -q 'freetz-apply-compat' /etc/bash.bashrc; then
	cat >>/etc/bash.bashrc <<'EOF'

# Apply Debian 13 arm64 Freetz host-tool compatibility tweaks.
/usr/local/bin/freetz-apply-compat >/dev/null 2>&1 || true
EOF
fi
fi
