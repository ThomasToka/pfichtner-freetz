#!/usr/bin/env bash
set -e

command -v locale-gen >/dev/null 2>&1 || apt-get -y install locales

for entry in \
	"en_US.UTF-8 UTF-8" \
	"de_DE.UTF-8 UTF-8"
do
	grep -q "^${entry}$" /etc/locale.gen || echo "$entry" >> /etc/locale.gen
done

locale-gen
update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 || true

locale -a | grep -qi '^en_US\.utf8$' || localedef -i en_US -f UTF-8 en_US.UTF-8 || true
locale -a | grep -qi '^de_DE\.utf8$' || localedef -i de_DE -f UTF-8 de_DE.UTF-8 || true

