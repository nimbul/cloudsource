#!/bin/bash
#set -x
#
# role.sh - Apply a Cloudsource role
#
# $Id: role.sh 8134 2010-06-21 23:35:05Z alistair.lewars $
#

# store command args for later use
export COMMAND_ARGS="$@"

function include()
{
	local FILENAME="$1"

	# Look in a path relative to scriptdir.
	local SCRIPTDIR=`dirname $0`

	local FILE="$SCRIPTDIR/$FILENAME"
	if [ ! -f "$FILE" ]; then 
		echo "Could not include file: $FILE"; 
		exit 1;
	fi

	. "$FILE"
}

# reusable functions
include 'deploy.sh'

function role_main()
{

	need_help=0
	if [ $# -eq 0 ];      then need_help=1; fi
	if [ "$1" = "?" ];    then need_help=1; fi
	if [ "$1" = "help" ]; then need_help=1; fi
	if [ $need_help -eq 1 ]; then
		show_help
		exit 0
	fi

	init_env

	# check for the --force option. 
	FORCE="n"
	if [ "$1" == "--force" ]; then
		FORCE="y"
		shift
	fi

	# check for "update-cs" command before we check if cloudsource is up-to-date. :p
	if [ "$1" == "update-cs" ]; then
		update-cs
		exit
	fi

	check_cloudsource #is up to date

	state="SUCCESSFUL"

	# Parse command:
	case "$1" in
		init)
			sysinit
			;;
		apply)
			shift
			apply_role $@
			[ $? -eq 1 ] && state='UNSUCCESSFUL' 
			email_notification "CloudSource apply operation $state. role: $1, version: $(test ! -z "$2" && echo $2 || echo 'HEAD')"
			;;
		reapply-all)
			reapply_all
			email_notification "CloudSource reapply-all operation executed."
			;;
		update)
			shift
			update_role $@
			[ $? -eq 1 ] && state='UNSUCCESSFUL' 
			email_notification "CloudSource update operation $state. role: $1, version: $(test ! -z "$2" && echo $2 || echo 'HEAD')"
			;;
		version|versions)
			role_versions
			;;
		params)
			show_params
			;;
		list)
			list_roles
			;;
		status)
			role_status
			;;
		log)
			shift 
			role_log $@
			;;
		revert-all)
			revert_all
			email_notification "CloudSource revert-all operation executed."
			;;
		revert)
			shift
			revert_role $@
			email_notification "CloudSource revert operation executed. role: $1"
			;;
		external|externals)
			shift
			cmd_externals $@
			;;
		link|relink)
			shift
			cmd_link $@
			email_notification "CloudSource [re]link operation executed. role: $1"
			;;
		unlink)
			shift
			cmd_unlink $@
			email_notification "CloudSource unlink operation executed. role: $1"
			;;
		help|*)
			show_help
			;;
	esac
}

function show_help()
{
	cat <<END
Description:
	role.sh is used to install ("apply") and manage "roles" that may apply to a system. 

Sample:
	$0 [--force] command [arg1] [arg2] [...]

Commands for $0:

	help
		Show this help"

	init
		Initialize the system. (You shouldn't have to run this.) 

	update-cs
		Update Cloudsource scripts from SVN.

	apply role1[,role2][...]
		Apply or re-apply a role by name.

	apply role1 1234
		Applies version 1234 of role 'role1'

	reapply-all
		Runs 'apply role' on all installed roles, updating them to the latest version.

	update role1[,role2][...]
		Update role along with externals without any conditions.

	version
		Show the versions of installed roles. 

	list
		Show all roles defined in the SVN repository.

	status 
		Run 'svn status' on all roles to make sure no changes have 
		been made locally.

	log role
		Runs svn log on role 'role'.  

	revert role
		runs 'svn revert' on the role to undo local changes.  

	revert-all
		runs 'svn revert' on all roles to undo all local changes. 

	link role
		Link (or re-link) files from a role into their deploy location.

	unlink role
		Remove links for a role.

	externals [role]
		show all svn externals for 'role' (if defined) or all roles.

Options for $0:
	
	--force
		Ignore safety checks (up-to-date, no local modifications) and proceed
		anyway
	
	
END
}


# Initialize the Cloudsource install:
# (called after bootstrapping)
function sysinit 
{
	for i in role.sh linkprop.sh; do
		chmod ug+x "$CS_BIN"/$i
	done

    if [ ! -d "$CS_ROLES" ]; then
        mkdir -p "$CS_ROLES"
    fi
}

# SVN with default arguments as used by Cloudsource
function sm_svn()
{
	local CMD="$1"
	shift 

	svn $CMD --no-auth-cache --username $SVNUSER --password $SVNPASS $@
}

# Update Cloudsource itself.
function update-cs 
{
	sm_svn up "$CS_BIN"
	for i in role.sh linkprop.sh; do
		chmod ug+x "$CS_BIN"/$i
	done
}

# apply the latest version of all installed roles:
function reapply_all()
{
	pushd "$CS_ROLES" >/dev/null

	for role in *; do
	    apply_role $role
	done

	popd >/dev/null
}

# list all roles available from svn
function list_roles()
{
	echo "(*=installed)"
	local STATUS=" "
	OICF=$ICF
	ICF="$CR"
	for role in $(sm_svn ls $SVNURL/roles); do
		if [ -d "$CS_ROLES/$role" ]; then
			STATUS="*"
		else
			STATUS=" "
		fi
		echo "$STATUS" $role
	done

	ICF="$OICF"
}


CR="
"

# cmd: role.sh apply ...
function apply_role 
{
	local ROLE="$1"
	local ROLE_VERSION="$2" # optional, the rev. # we want to upgrade to:

	# Check if $ROLE_VERSION is a valid value
	if [ -n "$ROLE_VERSION" ]; then
		if ! role_version_valid "$ROLE_VERSION"; then
			echo "Bad role version"
			show_help
			exit 1
		fi
	fi

        # Check that a role has been specified:
	if [ "$ROLE" == "" ]; then
		echo "please specify a role"
		exit 1
	fi

	# if it's a comma-separated list of roles - apply one-by-one
	if [[ "$ROLE" =~ ',' ]]; then
		roles=(`echo $ROLE | tr ',' ' '`)
		for role in ${roles[@]}; do
			apply_role "$role"
		done		
		return;
	fi

	if ! role_exists "$ROLE"; then
		echo "Role '$ROLE' does not exist."
		exit 1
	fi

	# get working copy revision
	local current_revision=$(current_role_version $ROLE)

	# get svn revision
	if [ "$ROLE_VERSION" == "" ]; then
		ROLE_VERSION=$(latest_role_version $ROLE);
	fi

	# return, if the current working revision is the same as the
	# specified revision by the user
	if [ $ROLE_VERSION -eq $current_revision ]; then
		echo "Role '$ROLE' is already at revision $ROLE_VERSION.";
		return
	fi

	# Update, if it exists:
	if [ -d "$CS_ROLES/$ROLE" ]; then
		if wc_is_modified "$CS_ROLES/$ROLE" && [ "$FORCE" != "y" ]; then
			die "Role '$ROLE' has been locally modified.  You must revert it or use --force."
		fi
		echo "Updating role '$ROLE' from revision $current_revision to revision $ROLE_VERSION ..."
		echo ""
		sm_svn up -r $ROLE_VERSION "$CS_ROLES/$ROLE"
	else  
		# check out for the first time
		echo "Checking out role '$ROLE' revision $ROLE_VERSION ..."
		echo ""
		sm_svn co -r $ROLE_VERSION "$SVNURL/roles/$ROLE" "$CS_ROLES/$ROLE"
	fi

	cmd_link "$ROLE"

	run_install_sh "$ROLE";
}

# update role and its external
function update_role()
{
	local ROLE="$1"
	local ROLE_VERSION="$2" # optional, the rev. # we want to upgrade to:

	# Check if $ROLE_VERSION is a valid value
	if [ -n "$ROLE_VERSION" ]; then
		if ! role_version_valid "$ROLE_VERSION"; then
			echo "Bad role version"
			show_help
			exit 1
		fi
	fi

        # Check that a role has been specified:
	if [ "$ROLE" == "" ]; then
		echo "please specify a role"
		exit 1
	fi

	# if it's a comma-separated list of roles - update one-by-one
	if [[ "$ROLE" =~ ',' ]]; then
		roles=(`echo $ROLE | tr ',' ' '`)
		for role in ${roles[@]}; do
			update_role "$role"
		done		
		return;
	fi

	if ! role_exists "$ROLE"; then
          echo "Role '$ROLE' does not exist."
		  exit 1
	fi

	# get working copy revision
	local current_revision=$(current_role_version $ROLE)

	# get svn revision
	if [ "$ROLE_VERSION" == "" ]; then
		ROLE_VERSION=$(latest_role_version $ROLE);
	fi

	# update role no matter what
	if [ -d "$CS_ROLES/$ROLE" ]; then
		if wc_is_modified "$CS_ROLES/$ROLE" && [ "$FORCE" != "y" ]; then
			die "Role '$ROLE' has been locally modified.  You must revert it or use --force."
		fi
		echo "Updating role '$ROLE' from revision $current_revision to revision $ROLE_VERSION ..."
		echo ""
		sm_svn up -r $ROLE_VERSION "$CS_ROLES/$ROLE"
	else  
		# check out for the first time
		echo "Checking out role '$ROLE' revision $ROLE_VERSION ..."
		echo ""
		sm_svn co -r $ROLE_VERSION "$SVNURL/roles/$ROLE" "$CS_ROLES/$ROLE"
	fi

	cmd_link "$ROLE"

	run_install_sh "$ROLE";
}

function run_install_sh()
{
	local ROLE="$1"

	local INSTALL_SCRIPT="$CS_ROLES/$ROLE/scripts/install.sh"
	if [ -f "$INSTALL_SCRIPT" -a -z "$CS_NO_INSTALL_SH" ]; then
		echo "Running $INSTALL_SCRIPT ..."
		/bin/bash "$INSTALL_SCRIPT"
	elif [  -f "$INSTALL_SCRIPT" -a -n "$CS_NO_INSTALL_SH" ]; then
		echo "WARNING: Skipping execution of install.sh: $INSTALL_SCRIPT ..."
		echo "WARNING: The \$CS_NO_INSTALL_SH is set."
	fi
}

# (Re)link the files for a role into $CS_TARGET.
function cmd_link()
{ 
	local ROLE="$1"
	if [ "$ROLE" == "" ]; then 
		die "Must specify role name!"
	elif [ ! -d "$CS_ROLES/$ROLE" ]; then
		die "Role '$ROLE' is not installed."
	fi

	echo "Linking files for role '$ROLE'..."
	"$CS_BIN/linkprop.sh" "$CS_ROLES/$ROLE/files" "$CS_TARGET"
}

# Remove symbolic links to ROLE from the filesystem.  
function cmd_unlink()
{
	local ROLE="$1"
	if [ "$ROLE" == "" ]; then 
		die "Must specify role name!"
	fi

	if [ ! -d "${CS_ROLES}/${ROLE}/files" ]; then
		if [ ! -d "${CS_ROLES}/${ROLE}" ]; then
			die "Role '${ROLE}' is not installed!"
		else
			die "Missing files path for role '${ROLE}' !!"
		fi
	fi
	
	echo "Removing symlinks for role '$ROLE'."

	local PATTERN="$CS_ROLES/$ROLE/files"

	# -mount - don't cross mount points. 
	for filename in $(find "${PATTERN}" | grep -v \.svn | egrep -v "${PATTERN}/$" | sed "s|${PATTERN}||g" ); do
		target_file="$(echo -n ${CS_TARGET}/${filename} | perl -pi -e 's|/+|/|g')"
		if [ -h "${target_file}" ]; then
			# if it's a symbolic link /and/ the link points to the role we're unlinking, proceed
			if [ $(readlink "${target_file}" | egrep -c "^$PATTERN" ) -ge 1 ]; then
				rm "${target_file}"
			else
				echo "Found linked file but doesn't point to role '$ROLE'"
				echo "    TARGET FILE: ${target_file}"
				echo "      LINK PATH: $(readlink $target_file)"
				echo "   TEST PATTERN: $PATTERN"
			fi
		fi
	done
}

# Get the current version of the role checked out on disk.
function current_role_version()
{
	local ROLE="$1"

	if [ ! -d $CS_ROLES/$ROLE ]; then
		echo -n 0
		return
	fi

	# else, return:
	get_wc_revision "$CS_ROLES/$ROLE"
}

# Get the revision # of a SVN working copy:
function get_wc_revision()
{
	local SVN_WC="$1"
	svn info "$SVN_WC"  | grep -i "revision:" | awk '{ print $2 }'
}

# return true (0) if the SVN working-copy has been locally modified: 
function wc_is_modified()
{
	local SVN_WC="$1"

	# you would think you could just check the return code of `svn status`...
	# ... but you can't.  (It's true whether or not WC is locally modified.)
	# Instead, run `svn status` and parse its output.
	# We might care about M or C or any other strange SVN statuses.  
	# Easier to filter out the statuses we don't care about: 


	local OUT=$(svn status "$SVN_WC" \
		| grep -v "^Performing status on external item at " \
		| grep -v "^X "  \
		| egrep -v '^[ 	]*$'
	)

	#return:
	[ "$OUT" != "" ]
}

# Get the SVN URL of a svn working copy.  
function get_svn_url() 
{
	local SVN_WC="$1"
	svn info "$SVN_WC" | grep "^URL:" | awk '{ print $2 }'
}

# check that cloudsource is up-to-date and pointing to the correct repo:
function check_cloudsource()
{
	if [ "$FORCE" == "y" ]; then
		true; return
	fi

	local CURRENT=$(get_wc_revision "$CS_BIN")
	local BINURL=$(get_svn_url "$CS_BIN")
	local LATEST=$(get_repo_revision "$BINURL")

	# FIXME: make sure to strip '/' from the end of SVNURL or it will 
	# cause the condition to fail. This should be tested against Solaris
	# and Linux systems prior to use.
	# if [ "${SVNURL%/}/bin" != "$BINURL" ]; then
	if [ "$SVNURL/bin" != "$BINURL" ]; then
		die "ERROR: $CS_BIN points to $BINURL but the environment points to $SVNURL."
	fi

	if [ "$CURRENT" -lt "$LATEST" ]; then
		die "WARNING: Cloudsource is out of date.  Run $0 update-cs. "
	fi
}

# like PHP's die().  Print an error message then exit. 
function die()
{
	echo >&2 "$*"
	exit 1
}

function latest_role_version()
{
	local ROLE="$1"

	if ! role_exists "$ROLE"; then 
		echo -n 0
		return
	fi

	#return:
	get_repo_revision "$SVNURL/roles/$ROLE"
}

# Find the latest version of a SVN tree (in the repo)
function get_repo_revision()
{
	local SVN_URL="$1"  
	
	# grep `svn log` for the first revision number and return (print) it
	sm_svn log "$SVN_URL" --limit 1 | egrep '^r[0-9]+ ' | tr -d 'r' | awk '{ print $1 }' | head -1
}

function role_log()
{
	local ROLE="$1"
	shift
	sm_svn log "$SVNURL/roles/$ROLE" $@
}

# cmd 'versions' -- list current & latest versions of applied roles:
function role_versions()
{
	echo "   (O=Out-of-date, M=locally modified)"
	echo
	local STATUS=" "

	sm_svn ls $SVNURL/roles \
	| while read role; do
		if [ ! -d "$CS_ROLES/$role" ]; then
			continue
		fi


		STATUS=" "
		CURRENT=$(get_wc_revision "$CS_ROLES/$role")
		LATEST=$(get_repo_revision "$SVNURL/roles/$role")
		if [ "$CURRENT" != "$LATEST" ]; then
			STATUS="O"
		fi

		if wc_is_modified "$CS_ROLES/$role"; then 
			MODIFIED="M"
		else
			MODIFIED=" "
		fi

		local OUT="$STATUS$MODIFIED $role"
		OUT="$(_pad "$OUT" 30 right) version: [$(_pad $CURRENT 5 left)]"
		if [ "$STATUS" == "O" ]; then
			OUT="$OUT svn: [$(_pad $LATEST 5 left)]"
		fi

		echo "$OUT"
	done

}

# cmd 'status' -- show 'svn status' for each role
function role_status()
{
	for role_dir in "$CS_ROLES"/*; do 
		echo "Performing status for $role_dir:"
		svn status "$role_dir"
	done
}

# Return true if the role exists in SVN
function role_exists()
{
	local ROLE="$1"
	sm_svn ls "$SVNURL/roles/$ROLE" > /dev/null
}

# Return true if the role version is valid
function role_version_valid()
{
	local ROLE_VERSION="$1"
	echo $ROLE_VERSION | egrep ^[0-9]+$
	return $?
}

# run a SVN revert on a role: 
function revert_role()
{
	local ROLE="$1"

	if [ "$ROLE" == "" ]; then
		die "must specify a role to revert!"
	fi

	local ROLEDIR="$CS_ROLES/$ROLE"

	if [ ! -d "$ROLEDIR" ]; then 
		die "Role '$ROLE' is not applied to this host!"
	fi

	echo "Reverting role '$ROLE'..."

	svn revert -R "$ROLEDIR" || die


	# revert -R does not recurse into externals. Need to do that ourselves.  
	# Note: I assume you're not massochistic enough to have nested externals.
	find_external_dirs "$ROLEDIR" | \
	while read EXT_DIR; do
		if [ ! -d "$EXT_DIR" ]; then
			continue # It has been moved/deleted.  our later svn up will fix that.
		fi
		echo "Reverting external dir: $EXT_DIR ..."
		svn revert -R "$EXT_DIR"
	done
	
	# revert can restore locally modified/removed *files*, but can't restore directories
	# that have been removed/renamed.  For that we have to svn-up. 
	local CURRENT=$(current_role_version "$ROLE")
	sm_svn up -r $CURRENT "$ROLEDIR" 

}

# revert all roles.
function revert_all()
{
	for roledir in "$CS_ROLES"/*; do
		local ROLE=$(basename "$roledir")
		revert_role "$ROLE"
	done
}

# Get the paths to external checkouts
function find_external_dirs()
{
	local SVN_WC="$1"

	find_svn_externals "$SVN_WC" | \
	while read PROPDIR; do
		# PROPDIR is where the svn:externals is SET.
		# We want where the external is actually checked out:
		svn propget svn:externals "$PROPDIR" | \
		while read EXT_DEF; do
			if echo "$EXT_DEF" | grep $'^[ \t]*$' >/dev/null; then
				continue #skip empty line
			fi
			# External definition:  destination [-rXXXX] svn_source
			local REL_DEST=$(echo "$EXT_DEF" | cut -d " " -f 1)
			# we want the full path: 
			echo "$PROPDIR/$REL_DEST"
		done
	done
}

# Find all directories that have an svn:externals definitions.  Echo them out one per line. 
function find_svn_externals()
{
	local SVN_WC="$1"

	svn proplist -R "$SVN_WC" | \
	while read LINE; do
		if echo "$LINE" | grep '^Properties on ' >/dev/null; then 
			# Properties on 'DIR':
			# Remember DIR
			local DIR=$(echo "$LINE" | cut -d "'" -f 2)

		elif [ "$LINE" == "svn:externals" ]; then
			echo "$DIR"
		fi
	done;
}

# show externals
function cmd_externals()
{
	local ROLE="$1"

	if [ "$ROLE" != "" ]; then
		show_role_externals "$ROLE"
	else
		for roledir in "$CS_ROLES"/*; do 
			ROLE=$(basename "$roledir")
			show_role_externals "$ROLE"
		done
	fi
}

# Output a nice list of svn externals.  
function show_role_externals()
{
	local ROLE="$1"

	local ROLEDIR="$CS_ROLES/$ROLE"

	if [ ! -d "$ROLEDIR" ]; then
		die "Role '$ROLE' is not applied to this machine."
	fi

	find_svn_externals "$CS_ROLES/$ROLE" | \
	while read ext_dir; do 
		echo "Externals at: $ext_dir"
		echo
		svn propget svn:externals "$ext_dir"
	done

}

# string padding
function _pad()
{
	local STR="$1"
	local SIZE="$2"
	local SIDE="$3"
	if [ "$SIDE" != "right" ]; then SIDE=left ; fi

	local DELTA=$(($SIZE - ${#STR}))
	while [ $DELTA -gt 0 ]; do
		DELTA=$((DELTA - 1))
		case "$SIDE" in
			left)
				STR=" $STR"
				;;
			right)
				STR="$STR "
				;;
		esac
	done

	#return
	echo "$STR"
}




role_main $@
