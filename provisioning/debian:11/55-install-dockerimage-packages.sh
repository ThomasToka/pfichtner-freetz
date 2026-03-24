# our docker entrypoint relies on gosu to switch to unprivileged user
apt-get -y install gosu libc-bin

# Freetz prerequisites run as builduser and may not have /sbin in PATH.
[ -x /sbin/ldconfig ] && ln -sf /sbin/ldconfig /usr/bin/ldconfig
[ -x /sbin/depmod ] && ln -sf /sbin/depmod /usr/bin/depmod

