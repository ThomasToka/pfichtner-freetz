command -v locale-gen >/dev/null 2>&1 || apt-get -y install locales

for entry in \
	"en_US.UTF-8 UTF-8" \
	"de_DE.UTF-8 UTF-8" \
	"en_US ISO-8859-1" \
	"de_DE ISO-8859-1"
do
	grep -q "^${entry}$" /etc/locale.gen || echo "$entry" >> /etc/locale.gen
done

locale-gen
