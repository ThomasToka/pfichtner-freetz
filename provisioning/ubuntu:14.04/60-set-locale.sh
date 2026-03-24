#!/usr/bin/env bash
set -e

command -v locale-gen >/dev/null 2>&1 || apt-get -y install locales

entries='en_US.UTF-8 UTF-8
de_DE.UTF-8 UTF-8
en_US ISO-8859-1
de_DE ISO-8859-1'

if [ -f /etc/locale.gen ]; then
	while IFS= read -r entry; do
		[ -z "$entry" ] && continue
		grep -q "^${entry}$" /etc/locale.gen || echo "$entry" >> /etc/locale.gen
	done <<EOF
$entries
EOF
fi

if [ -d /var/lib/locales/supported.d ]; then
	touch /var/lib/locales/supported.d/local
	while IFS= read -r entry; do
		[ -z "$entry" ] && continue
		grep -q "^${entry}$" /var/lib/locales/supported.d/local || echo "$entry" >> /var/lib/locales/supported.d/local
	done <<EOF
$entries
EOF
fi

locale-gen || true
locale-gen en_US.UTF-8 de_DE.UTF-8 || true

locale -a | grep -qi '^en_US\.utf8$' || localedef -i en_US -f UTF-8 en_US.UTF-8 || true
locale -a | grep -qi '^de_DE\.utf8$' || localedef -i de_DE -f UTF-8 de_DE.UTF-8 || true
