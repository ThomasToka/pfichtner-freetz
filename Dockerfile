ARG PARENT=ubuntu:24.04
FROM $PARENT

# https://stackoverflow.com/questions/44438637/arg-substitution-in-run-command-not-working-for-dockerfile/56748289#56748289
ARG PARENT
ARG PROVISION_DIR=/tmp/${PARENT}
ENV DEBIAN_FRONTEND=noninteractive

COPY provisioning/${PARENT} ${PROVISION_DIR}
COPY provisioning/files ${PROVISION_DIR}/files
COPY provisioning/scripts ${PROVISION_DIR}/scripts
WORKDIR ${PROVISION_DIR}
RUN [ -r "${PROVISION_DIR}/envs" ] && export $(cat ${PROVISION_DIR}/envs | xargs); \
	ARCH="$(dpkg --print-architecture 2>/dev/null || true)"; \
	[ -n "$ARCH" ] || ARCH="$(uname -m 2>/dev/null || true)"; \
	[ "$ARCH" = "aarch64" ] && ARCH="arm64" || true; \
	for SCRIPT in ${PROVISION_DIR}/*.sh; do \
		if [ "$ARCH" = "arm64" ]; then \
			( \
				echo 'filter_multilib_args() {'; \
				echo '  local cmd="$1"; shift'; \
				echo '  local has_install=n'; \
				echo '  for arg in "$@"; do [ "$arg" = "install" ] && has_install=y; done'; \
				echo '  [ "$has_install" = "y" ] || { command "$cmd" "$@"; return; }'; \
				echo '  local filtered=()'; \
				echo '  for arg in "$@"; do'; \
				echo '    case "$arg" in'; \
				echo '      gcc-multilib|lib32ncurses-dev|lib32ncurses5-dev|lib32stdc++6|lib32z1-dev|libc6-dev-i386|sqlite3:i386|libzstd-dev:i386) ;;'; \
				echo '      *) filtered+=("$arg") ;;'; \
				echo '    esac'; \
				echo '  done'; \
				echo '  command "$cmd" "${filtered[@]}"'; \
				echo '}'; \
				echo 'apt() { filter_multilib_args apt "$@"; }'; \
				echo 'apt-get() { filter_multilib_args apt-get "$@"; }'; \
				echo 'dnf() {'; \
				echo '  local has_install=n'; \
				echo '  for arg in "$@"; do [ "$arg" = "install" ] && has_install=y; done'; \
				echo '  [ "$has_install" = "y" ] || { command dnf "$@"; return; }'; \
				echo '  local filtered=()'; \
				echo '  for arg in "$@"; do'; \
				echo '    case "$arg" in'; \
				echo '      glibc-devel.i686) ;;'; \
				echo '      *) filtered+=("$arg") ;;'; \
				echo '    esac'; \
				echo '  done'; \
				echo '  command dnf "${filtered[@]}"'; \
				echo '}'; \
				echo set -e; \
				cat "$SCRIPT"; \
			) | bash || exit $?; \
		else \
			(echo set -e && cat "$SCRIPT") | bash || exit $?; \
		fi; \
	done && rm -rf ${PROVISION_DIR}

# if running in podman we have to create a default user in the image since we have no root priviliges to do in ENTRYPOINT
RUN useradd -G sudo -s /bin/bash -d /workspace -m builduser

WORKDIR /
COPY entrypoint.sh /usr/local/bin
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

