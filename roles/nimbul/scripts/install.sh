#!/bin/bash -e

# should probably move it to ENV as well
export NIMBUL_HOME='/opt/nyt/nimbul'
export NIMBUL_CONFIGS='/opt/nyt/nimbul-configs'

function init_crontab {
  echo "Setting up crontab for nightly restarts..."

  # command to execute
  COMMAND="${NIMBUL_HOME}/restart"

  # Entry we are adding to the crontab.
  ENTRY="0 23 * * * ${COMMAND}"

  # add it to cron but, make sure it's only added once
  (crontab -l | perl -pe '$entry = quotemeta("'"${ENTRY}"'"); s/$entry\s*\n//g'; echo "${ENTRY}") | crontab
}

function update_cloudmaster {
	rm -rf /opt/cloudmaster
	yum install -y git
	git clone http://github.com/vadimj/cloudmaster.git /opt/cloudmaster --quiet
	yum remove git -y
}

function handle_services {
	# MAIL
	chkconfig --level 12345 postfix on
	/etc/init.d/postfix start

	# Disable HTTP
	echo "Make sure apache is turned off"
	chkconfig --level 123456 httpd off

	echo "Make sure apache is down"
	/sbin/service httpd stop

	# HTTPS via STUNNEL
	if [ $(rpm -qav | grep stunnel -ic) -le 0 ]; then
		yum install -y stunnel
	fi

	echo "Make sure the key is secure enough"
	chmod 600 /etc/httpd/conf/ssl.keys/*.key

	echo "Create chroot directory for stunnel"
	mkdir -p /var/run/stunnel && chown nobody:nobody /var/run/stunnel

	echo "Start stunnel"
	/usr/sbin/stunnel
}

function bring_up_nimbul {
	if [ $(gem list  mongrel_cluster | grep -c mongrel_cluster) -ge 1 ]; then
		echo "Make sure mongrel_cluster is removed"
		echo y | gem uninstall mongrel_cluster
	fi

	# facter is required for determining the total # of cpu's.
	# used by daemons for spawning subprocesses
	gem install facter

	echo "Setting events password"
	local events_password="$(ruby -ruri -e "puts URI.decode('${EVENTS_PASSWORD}')")"
	sed -i -re "s|%%EVENTS_PASSWORD%%|${events_password}|g" "${NIMBUL_HOME}/config/broker.yml"

	echo "Creating ${NIMBUL_HOME}/log"
	mkdir -p ${NIMBUL_HOME}/log

	echo "Linking configs"
	if [ -e "${NIMBUL_CONFIGS}" ]; then
		for config in "${NIMBUL_CONFIGS}"/*.yml; do
			ln -snf "${config}" "${NIMBUL_HOME}/config"
		done
	fi

	echo "Start Nimbul"
	${NIMBUL_HOME}/start

}

echo "Install script for role 'nimbul'"

update_cloudmaster
handle_services
bring_up_nimbul
init_crontab

echo "Install script for role 'nimbul' - done"

exit 0
