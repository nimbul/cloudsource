#!/bin/bash -e
#
# deploy.sh - Deploy necessary Cloudsource scripts on the host
#
# $Id: deploy.sh 3140 2009-11-30 22:07:15Z ccorliss $
#

# store command args for later use, but don't set
# if already set (likely by roles.sh)
[ -z $"{COMMAND_ARGS}" ] && export COMMAND_ARGS="$@"

function deploy_main()
{

	init_env

	show_params
	
	NO_ROOT=n
	if [ "$1" == "--no-root" ]; then
		NO_ROOT=y
	fi
		
	if ! svn_installed; then 
		install_svn
	fi

	OIFS=$IFS
	IFS=$(echo -e "\r\n")
	
	mkdir -p $CS_BIN
	svn co --no-auth-cache --username $SVNUSER --password $SVNPASS $SVNURL/bin/ $CS_BIN
	chmod 700 $CS_BIN
	/bin/bash $CS_BIN/role.sh init

	# apply base role but don't notify about it because we're already
	# notifying about cloudsource being deployed
	local original_email="${CS_NOTIFY_EMAIL}"
	export CS_NOTIFY_EMAIL=''
	$CS_BIN/role.sh apply base
	export CS_NOTIFY_EMAIL="${original_email}"

	# We will create symlinks into CS_ROLES.  Ensure that other accounts can list 
	# the files needed to resolve symlinks:
	local DIR="$CS_ROLES"
	while [ ! -z "$DIR"  ] && [ "$DIR" != "." ] && [ "$DIR" != "/" ]; do
		chmod a+X "$DIR"
		DIR=$(dirname "$DIR")
	done

	email_notification "Deployed CloudSource"

	echo "Cloudsource is now installed.  You may now: rm $0"
}

# if Exit On Error is activated, disable it for `type` calls
if [ $(set -o | egrep -c 'errexit.*on') -ge 1 ]; then
	function type()
	{
		set +e; builtin type $@; set -e
	}
fi

# if readlink is missing, then use perl's readlink
if [ -z "$(type -p readlink)" ]; then
	function readlink()
	{
		perl -e "print readlink '$@'"
	}
fi

# use nawk if available (only on solaris/osx)
# otherwise, use awk. Note: use nawk on solaris
# because it supports sup() wheras awk on solaris doesn't
AWK=$(type -p nawk awk | head -n 1)
if [ -z "${AWK}" ]; then
	echo "Could not find nawk or awk - bailing out..."
	exit 1
fi


# return true (0) iff svn is installed. 
function svn_installed()
{
	local SVN=$(which svn)
	# return: 
	[ "$SVN" != "" ]
}

function install_svn()
{
	if [ "$NO_ROOT" == "y" ]; then
		true #don't do any install.
		# Allows for installing as non-root user for testing.
	elif is_ubuntu; then
	  deploy-ubuntu
	else
	  deploy-centos
	fi
}

# Initialize environment variables we need:
function init_env()
{
	# Where to install/find Cloudsource binaries:
	if [ "$CS_BIN" == "" ]; then
		CS_BIN=/root/bin
	fi

	# Where to checkout/update roles:
	if [ "$CS_ROLES" == "" ]; then
		CS_ROLES=/root/roles
	fi

	# Where to install (link) files:
	if [ "$CS_TARGET" == "" ]; then
		CS_TARGET=/
	fi

	#The file where we'll look for SVN authentication variables:
	if [[ "$SVN_AUTH" == "" ]]; then 
		SVN_AUTH=~/.svnauth
	fi

	# By default, respect environment variables.
	# But if they're not set, try to set them: 
	if ! have_params; then 
		if [ -f "$SVN_AUTH" ]; then
			. "$SVN_AUTH"
		fi
	fi

	# If they're still not set, show an error.
	if ! have_params; then 
		show_param_info
		exit 1
	fi
}

function show_params()
{
cat <<EOF
Using parameters:
SVNUSER:  $SVNUSER
SVNPASS:  (hidden)
SVNURL:   $SVNURL
CS_BIN:   $CS_BIN
CS_ROLES: $CS_ROLES
CS_TARGET: $CS_TARGET
EOF
}

# Check if we have all required environment variables:
function have_params()
{
	if [ "$SVNUSER" != "" ] && [ "$SVNPASS" != "" ] && [ "$SVNURL" != "" ]
	then 
		true
	else
		false
	fi
}

show_param_info() 
{
	if [ X$SVNUSER == X ]; then echo "You must set SVNUSER env variable"; fi
	if [ X$SVNPASS == X ]; then echo "You must set SVNPASS env variable"; fi
	if [ X$SVNURL == X ]; then echo "You must set SVNURL env variable"; fi
	echo "These variables may be set in the environment, or $SVN_AUTH."
}

#
# ubuntu specific
#
function deploy-ubuntu() {
  # Hack to get rid of bad stuff in your apt sources file
  sed -i s/'^deb cdrom'/'# deb cdrom'/g /etc/apt/sources.list

  apt-get update
  for x in $(apt-get -qqfy install subversion -y)
  do 
    echo -e "\t$x"
  done

  export DEBIAN_FRONTEND=noninteractive  
}

# Assume that if we have apt-get, this is ubuntu:
function is_ubuntu()
{
	which apt-get >/dev/null 2>/dev/null
}

#
# centos specific
#
function deploy-centos() 
{
  yum install subversion -y
}

#
# email notification
#
function email_notification() {
	# don't bother if CS_NOTIFY_EMAIL not set 
	[ -z "$CS_NOTIFY_EMAIL" ] && return 0
	
	local dsc="$(hostname): $1"

	MUA="$(type -p mailx mail | head -n1)"
	if [ -z "$MUA" ]; then
		echo "WARNING: Unable to send notifications: Neither 'mailx' nor 'mail' could be found in the PATH ($PATH)"
		return 1
	fi

	cat <<EOF | $MUA -s "$dsc" $CS_NOTIFY_EMAIL
$dsc

Command Run
-----------

$0 ${COMMAND_ARGS}

Details
-------

Using parameters:
SVNUSER:  $SVNUSER
SVNPASS:  (hidden)
SVNURL:   $SVNURL
CS_BIN:   $CS_BIN
CS_ROLES: $CS_ROLES
CS_TARGET: $CS_TARGET

EOF

	echo "Sending notifications to: $(echo $CS_NOTIFY_EMAIL | sed -e 's|,|, |g')"
}

# Only execute main() if we're deploy.sh
# Allows for re-using any functions we define here in other scripts.
THIS_SCRIPT=`basename $0`
if [ "$THIS_SCRIPT" == "deploy.sh" ]; then 
	deploy_main $@
fi
