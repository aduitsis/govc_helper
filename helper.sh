#!/bin/sh -

# This will only work on a FreeBSD system
# to use this, just include it from your script

. /usr/share/bsdconfig/dialog.subr

DIALOG="dialog --ascii-lines"
DATE=$(date +%Y%m%dZ%H%M%S)
BASENAME=$(basename $0)
DIRNAME=$(dirname $0)
STATE=$DIRNAME/state.txt
SYSRC="sysrc -f $STATE"
touch $STATE
$SYSRC last_run=$DATE
. $STATE
UNAME=$(uname -r)

: ${DIALOG_TERMINAL_PASSTHRU_FD:=${TERMINAL_STDOUT_PASSTHRU:-3}}

# gets a variable name, checks whether the value is defined
# if not, dies
defined_or_die() {
	local val
	f_getvar $1 val
	if test -z "$val"; then
		f_die 1 "variable $1 is undefined or empty"
	fi
}

# retrieves a variable from a sh-styled file, if not present
# a default is returned
sysrc_or_default() {
	local val
	if $SYSRC -q "$1" >/dev/null ; then
		val="`$SYSRC -n "$1"`"
	else
		val="$2"
	fi
	setvar $1 "$val"
}

# ask user for a string, with a pre-filled initial value
# remembers old value across invocations
# initial value is default if there's no previous invocation
# stores result in variable name
# example: get_str_rmbr "message" var_name default_value
get_str_rmbr() {
	local init
	local val
	sysrc_or_default $2 $3
	f_getvar $2 init
	f_dialog_input $2 "$1" $init
	defined_or_die $2
	f_getvar $2 val
	$SYSRC "$2"="$val"
	. $STATE
}

# same as get_str_rmbr above, but for a password
# no default password here
# old one is not displayed
# if the user just presses enter, the old password is used
get_pass_rmbr() {
	local password
	message="$1"
	sysrc_or_default $2 ""
	f_getvar $2 password
	if ! test -z "$password"; then
		message="$1 (press enter to keep old password)"
	fi
	# copied from f_become_root_via_sudo in mustberoot.subr (thanks!!)
	password=$( $DIALOG --insecure --passwordbox "$message" 0 0 2>&1 >&$DIALOG_TERMINAL_PASSTHRU_FD )
	if ! test -z "$password"; then
		$SYSRC "$2"="$password" >/dev/null 2>&1
		setvar $2 "$password"
	else
		echo no change, keeping old password
	fi
	. $STATE
}

# example present_menu var_name [govc subcommand]
# invokes a govc subcommand, converts it into a list,
# then presents the results for the user to choose
present_menu() {
	local varname=$1
	shift
	local descr=$1
	shift
	$DIRNAME/govc $@
	LIST=$($DIRNAME/govc $@ | perl -nlE 'say "$_ $_"')
	cmd="dialog --ascii-lines --menu \"please select $descr\" 0 0 0 $LIST 2>&1 >&$DIALOG_TERMINAL_PASSTHRU_FD"	
	val=$(eval $cmd)
	setvar $varname "$val"
}

# invoke this function to be able to successfully authenticate to an esxi or vsphere server
activate_credentials() {
	get_str_rmbr "What is the address of the vpshere server?" GOVC_URL my_vsphere_server.local.domain
	get_str_rmbr "User for $GOVC_URL?" GOVC_USERNAME root
	get_pass_rmbr "Password for $GOVC_USERNAME @ $GOVC_URL?" GOVC_PASSWORD

	export GOVC_INSECURE=1
	export GOVC_URL
	export GOVC_USERNAME
	export GOVC_PASSWORD
}

get_datacenter() {
	present_menu GOVC_DATACENTER "datacenter" find -type d
	export GOVC_DATACENTER
}

get_host() {
	get_datacenter
	present_menu GOVC_HOST "physical host in $GOVC_DATACENTER" find -type h $GOVC_DATACENTER
	export GOVC_HOST
}

get_datastore() {
	get_host
	present_menu GOVC_DATASTORE "datastore in $GOVC_HOST" ls -t Datastore $GOVC_HOST
	export GOVC_DATASTORE
}

