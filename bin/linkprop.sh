#!/bin/bash

# This script recursively creates symlinks in $2 which point to files in $1.  
# $1 and $2 must be absolute directories. 

CR="
"

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

function linkprop()
{
	local DST_DIR="$1" # The dir that the symlinks should reference.
	local SRC_DIR="$2" # the place to create symlinks
	
	check_absolute "$DST_DIR"
	check_absolute "$SRC_DIR"

	if [ ! -d "$DST_DIR" ]; then
		"'$DST_DIR' does not exist."
	    exit 0
	fi


	# Set IFS to use CR as a word separator so we can use 'for' w/ `find`:
	IFS=$CR

	# use this to remove first N chars in find
	REPL=$(echo -n "$DST_DIR" | $AWK '{ gsub(/\/$/, ""); gsub(/./, "."); print }')

	for rel_file in $(find "$DST_DIR"| grep -v '/\.svn' | sed "s%^$REPL%%"); do
		local abs_file="$DST_DIR$rel_file"
		# don't symlink directories
		if [ -d "$abs_file" ]; then
			continue
		fi


		local link="$SRC_DIR/$rel_file" # the link to be created.
		local link_dir=$(dirname "$link") #

		if [ ! "$link_dir" = "" ]; then
		    mkdir -p "$link_dir"
		fi

		if [ -h "$link" ]; then
			local old_dest=$(readlink "$link")
			if [ "$old_dest" != "$abs_file" ]; then
				echo "Symlink already exists at $link."
				echo "   pointed to: $old_dest"
				echo "now points to: $abs_file"
				echo ""
			fi
		elif [ -f "$link" ]; then
			echo "File exists at: $link"
			mv "$link" "$link.original"
			echo "Backed up to: $link.original"
			echo ""
		fi

		ln -sf "$abs_file" "$link" 
	done
}

function check_absolute()
{
	local DIR="$1"
	local FOUND=$(echo "$DIR" | egrep -v '^[^/]')
	if [ "$FOUND" == "" ]; then
		echo "'$DIR' is not an absolute path."
		exit 1
	fi
}

SCRIPTNAME=$(basename "$0")
if [ "$SCRIPTNAME" == "linkprop.sh" ]; then
	linkprop $@
fi
