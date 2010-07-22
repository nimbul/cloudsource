#!/usr/bin/env bash

#
# NOTE: the amqp.pem file located in files/etc/stunnel MUST be removed
# when this role becomes production worthy and replaced with some other
# means for adding a real legitimate key+cert pem file for SSL via Stunnel
#  -- Carl

export PATH=${PATH}:/usr/local/bin

# just to make sure we have it...
source /etc/cloudrc
source /etc/cloudrc.private

gem install escape
yum install -y rabbitmq-server ejabberd stunnel

while ! ec2-metadata -o | grep ': 10\.' >/dev/null; do
	echo "Waiting for local IP address to become available...";
	sleep 1s
done

/etc/init.d/rabbitmq-server start

sed -i -e "s|%%MY-IP%%|$(ec2-metadata -o | awk '{ print $2 }')|" /etc/stunnel/stunnel.conf

# add stunnel user
groupadd stunnel
useradd -d /chroot/stunnel -g stunnel -m -r -s /bin/false stunnel
chmod go-rwx,u+r-wx /etc/stunnel/amqp.pem

mkdir -p /chroot/stunnel/var/run/stunnel
chown -R stunnel:stunnel /chroot/stunnel

if [ $(rabbitmqctl list_vhosts | grep -ic /nimbul) -le 0 ]; then
    # configure
    rabbitmqctl add_vhost /nimbul
    rabbitmqctl add_user nimbul "$(ruby -ruri -e "puts URI.decode('${EVENTS_PASSWORD}')")"
    rabbitmqctl set_permissions -p /nimbul nimbul '.*' '.*' '.*'
fi

if [ $(rabbitmqctl list_vhosts | grep -ic /infra) -le 0 ]; then
    rabbitmqctl add_vhost /infra
    rabbitmqctl add_user infra "$(ruby -ruri -e "puts URI.decode('${INFRA_PASSWORD}')")"
    rabbitmqctl set_permissions -p /infra infra '.*' '.*' '.*'
fi

# delete anonymous guest user
rabbitmqctl delete_user guest

sed -i -e "s|%%PASSWORD%%|${EVENTS_PASSWORD}|" /etc/emissary/config.ini

# and now start up stunnel
stunnel
