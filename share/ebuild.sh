#!/bin/bash
# Copyright 1999-2011 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2

EBUILD_PHASE=depend

. /usr/lib64/portage/bin/isolated-functions.sh

qa_source() {
	local shopts=$(shopt) OLDIFS="$IFS"
	local retval
	source "$@"
	retval=$?
	set +e
	[[ $shopts != $(shopt) ]] &&
		eqawarn "QA Notice: Global shell options changed and were not restored while sourcing '$*'"
	[[ "$IFS" != "$OLDIFS" ]] &&
		eqawarn "QA Notice: Global IFS changed and was not restored while sourcing '$*'"
	return $retval
}

# Prevent aliases from causing portage to act inappropriately.
# Make sure it's before everything so we don't mess aliases that follow.
unalias -a

# Unset some variables that break things.
unset GZIP BZIP BZIP2 CDPATH GREP_OPTIONS GREP_COLOR GLOBIGNORE

source "${PORTAGE_BIN_PATH}/isolated-functions.sh"  &>/dev/null


useq() {
	eqawarn "QA Notice: The 'useq' function is deprecated (replaced by 'use')"
	use ${1}
}


usev() {
	if use ${1}; then
		echo "${1#!}"
		return 0
	fi
	return 1
}

use() {
	local u=$1
	local found=0

	# if we got something like '!flag', then invert the return value
	if [[ ${u:0:1} == "!" ]] ; then
		u=${u:1}
		found=1
	fi

	if [[ $EBUILD_PHASE = depend ]] ; then
		# TODO: Add a registration interface for eclasses to register
		# any number of phase hooks, so that global scope eclass
		# initialization can by migrated to phase hooks in new EAPIs.
		# Example: add_phase_hook before pkg_setup $ECLASS_pre_pkg_setup
		#if [[ -n $EAPI ]] && ! has "$EAPI" 0 1 2 3 ; then
		#	die "use() called during invalid phase: $EBUILD_PHASE"
		#fi
		true

	# Make sure we have this USE flag in IUSE
	elif [[ -n $PORTAGE_IUSE && -n $EBUILD_PHASE ]] ; then
		[[ $u =~ $PORTAGE_IUSE ]] || \
			eqawarn "QA Notice: USE Flag '${u}' not" \
				"in IUSE for ${CATEGORY}/${PF}"
	fi

	if has ${u} ${USE} ; then
		return ${found}
	else
		return $((!found))
	fi
}

# Return true if given package is installed. Otherwise return false.
# Takes single depend-type atoms.
has_version() {
	if [ "${EBUILD_PHASE}" == "depend" ]; then
		die "portageq calls (has_version calls portageq) are not allowed in the global scope"
	fi
}

portageq() {
	if [ "${EBUILD_PHASE}" == "depend" ]; then
		die "portageq calls are not allowed in the global scope"
	fi
}

# Returns the best/most-current match.
# Takes single depend-type atoms.
best_version() {
	if [ "${EBUILD_PHASE}" == "depend" ]; then
		die "portageq calls (best_version calls portageq) are not allowed in the global scope"
	fi
}

use_with() {
	if [ -z "$1" ]; then
		echo "!!! use_with() called without a parameter." >&2
		echo "!!! use_with <USEFLAG> [<flagname> [value]]" >&2
		return 1
	fi

	if ! has "${EAPI:-0}" 0 1 2 3 ; then
		local UW_SUFFIX=${3+=$3}
	else
		local UW_SUFFIX=${3:+=$3}
	fi
	local UWORD=${2:-$1}

	if use $1; then
		echo "--with-${UWORD}${UW_SUFFIX}"
	else
		echo "--without-${UWORD}"
	fi
	return 0
}

use_enable() {
	if [ -z "$1" ]; then
		echo "!!! use_enable() called without a parameter." >&2
		echo "!!! use_enable <USEFLAG> [<flagname> [value]]" >&2
		return 1
	fi

	if ! has "${EAPI:-0}" 0 1 2 3 ; then
		local UE_SUFFIX=${3+=$3}
	else
		local UE_SUFFIX=${3:+=$3}
	fi
	local UWORD=${2:-$1}

	if use $1; then
		echo "--enable-${UWORD}${UE_SUFFIX}"
	else
		echo "--disable-${UWORD}"
	fi
	return 0
}


debug-print() {
	true
}

debug-print-function() {
	#echo "$@" >&2
	#printf 'debug: %s\n' "${@}" >&2
	true
}
debug-print-section() {
	true
}
die() {
	exit
}

# Sources all eclasses in parameters
declare -ix ECLASS_DEPTH=0
inherit() {
	ECLASS_DEPTH=$(($ECLASS_DEPTH + 1))
	if [[ ${ECLASS_DEPTH} > 1 ]]; then
		debug-print "*** Multiple Inheritence (Level: ${ECLASS_DEPTH})"
	fi

	if [[ -n $ECLASS && -n ${!__export_funcs_var} ]] ; then
		echo "QA Notice: EXPORT_FUNCTIONS is called before inherit in" \
			"$ECLASS.eclass. For compatibility with <=portage-2.1.6.7," \
			"only call EXPORT_FUNCTIONS after inherit(s)." \
			| fmt -w 75 | while read -r ; do eqawarn "$REPLY" ; done
	fi

	local location
	local olocation
	local x

	# These variables must be restored before returning.
	local PECLASS=$ECLASS
	local prev_export_funcs_var=$__export_funcs_var

	local B_IUSE
	local B_REQUIRED_USE
	local B_DEPEND
	local B_RDEPEND
	local B_PDEPEND
	while [ "$1" ]; do
		location="${ECLASSDIR}/${1}.eclass"
		olocation=""

		export ECLASS="$1"
		__export_funcs_var=__export_functions_$ECLASS_DEPTH
		unset $__export_funcs_var

		# any future resolution code goes here
		if [ -n "$PORTDIR_OVERLAY" ]; then
			local overlay
			for overlay in ${PORTDIR_OVERLAY}; do
				olocation="${overlay}/eclass/${1}.eclass"
				if [ -e "$olocation" ]; then
					location="${olocation}"
					debug-print "  eclass exists: ${location}"
				fi
			done
		fi
		debug-print "inherit: $1 -> $location"
		[ ! -e "$location" ] && die "${1}.eclass could not be found by inherit()"

		if [ "${location}" == "${olocation}" ] && \
			! has "${location}" ${EBUILD_OVERLAY_ECLASSES} ; then
				EBUILD_OVERLAY_ECLASSES="${EBUILD_OVERLAY_ECLASSES} ${location}"
		fi

		#We need to back up the value of DEPEND and RDEPEND to B_DEPEND and B_RDEPEND
		#(if set).. and then restore them after the inherit call.

		#turn off glob expansion
		set -f

		# Retain the old data and restore it later.
		unset B_IUSE B_REQUIRED_USE B_DEPEND B_RDEPEND B_PDEPEND
		[ "${IUSE+set}"       = set ] && B_IUSE="${IUSE}"
		[ "${REQUIRED_USE+set}" = set ] && B_REQUIRED_USE="${REQUIRED_USE}"
		[ "${DEPEND+set}"     = set ] && B_DEPEND="${DEPEND}"
		[ "${RDEPEND+set}"    = set ] && B_RDEPEND="${RDEPEND}"
		[ "${PDEPEND+set}"    = set ] && B_PDEPEND="${PDEPEND}"
		unset IUSE REQUIRED_USE DEPEND RDEPEND PDEPEND
		#turn on glob expansion
		set +f

		qa_source "$location" || die "died sourcing $location in inherit()"
		
		#turn off glob expansion
		set -f

		# If each var has a value, append it to the global variable E_* to
		# be applied after everything is finished. New incremental behavior.
		[ "${IUSE+set}"       = set ] && export E_IUSE="${E_IUSE} ${IUSE}"
		[ "${REQUIRED_USE+set}"       = set ] && export E_REQUIRED_USE="${E_REQUIRED_USE} ${REQUIRED_USE}"
		[ "${DEPEND+set}"     = set ] && export E_DEPEND="${E_DEPEND} ${DEPEND}"
		[ "${RDEPEND+set}"    = set ] && export E_RDEPEND="${E_RDEPEND} ${RDEPEND}"
		[ "${PDEPEND+set}"    = set ] && export E_PDEPEND="${E_PDEPEND} ${PDEPEND}"

		[ "${B_IUSE+set}"     = set ] && IUSE="${B_IUSE}"
		[ "${B_IUSE+set}"     = set ] || unset IUSE
		
		[ "${B_REQUIRED_USE+set}"     = set ] && REQUIRED_USE="${B_REQUIRED_USE}"
		[ "${B_REQUIRED_USE+set}"     = set ] || unset REQUIRED_USE

		[ "${B_DEPEND+set}"   = set ] && DEPEND="${B_DEPEND}"
		[ "${B_DEPEND+set}"   = set ] || unset DEPEND

		[ "${B_RDEPEND+set}"  = set ] && RDEPEND="${B_RDEPEND}"
		[ "${B_RDEPEND+set}"  = set ] || unset RDEPEND

		[ "${B_PDEPEND+set}"  = set ] && PDEPEND="${B_PDEPEND}"
		[ "${B_PDEPEND+set}"  = set ] || unset PDEPEND

		#turn on glob expansion
		set +f

		if [[ -n ${!__export_funcs_var} ]] ; then
			for x in ${!__export_funcs_var} ; do
				debug-print "EXPORT_FUNCTIONS: $x -> ${ECLASS}_$x"
				declare -F "${ECLASS}_$x" >/dev/null || \
					die "EXPORT_FUNCTIONS: ${ECLASS}_$x is not defined"
				eval "$x() { ${ECLASS}_$x \"\$@\" ; }" > /dev/null
			done
		fi
		unset $__export_funcs_var

		has $1 $INHERITED || export INHERITED="$INHERITED $1"

		shift
	done
	((--ECLASS_DEPTH)) # Returns 1 when ECLASS_DEPTH reaches 0.
	if (( ECLASS_DEPTH > 0 )) ; then
		export ECLASS=$PECLASS
		__export_funcs_var=$prev_export_funcs_var
	else
		unset ECLASS __export_funcs_var
	fi
	return 0
}

# Exports stub functions that call the eclass's functions, thereby making them default.
# For example, if ECLASS="base" and you call "EXPORT_FUNCTIONS src_unpack", the following
# code will be eval'd:
# src_unpack() { base_src_unpack; }
EXPORT_FUNCTIONS() {
	if [ -z "$ECLASS" ]; then
		die "EXPORT_FUNCTIONS without a defined ECLASS"
	fi
	eval $__export_funcs_var+=\" $*\"
}

		# In order to ensure correct interaction between ebuilds and
		# eclasses, they need to be unset before this process of
		# interaction begins.
		unset DEPEND RDEPEND PDEPEND IUSE REQUIRED_USE

		if [[ $PORTAGE_DEBUG != 1 || ${-/x/} != $- ]] ; then
			source "$EBUILD" || die "error sourcing ebuild"
		else
			set -x
			source "$EBUILD" || die "error sourcing ebuild"
			set +x
		fi

		[[ -n $EAPI ]] || EAPI=0

		if has "$EAPI" 0 1 2 3 3_pre2 ; then
			export RDEPEND=${RDEPEND-${DEPEND}}
			debug-print "RDEPEND: not set... Setting to: ${DEPEND}"
		fi

		# remember ebuild variables
		OIUSE="${IUSE}"
		ODEPEND="${DEPEND}"
		ORDEPEND="${RDEPEND}"
		OPDEPEND="${PDEPEND}"
		OREQUIRED_USE="${REQUIRED_USE}"

		# add in dependency info from eclasses
		IUSE="${IUSE} ${E_IUSE}"
		DEPEND="${DEPEND} ${E_DEPEND}"
		RDEPEND="${RDEPEND} ${E_RDEPEND}"
		PDEPEND="${PDEPEND} ${E_PDEPEND}"
		REQUIRED_USE="${REQUIRED_USE} ${E_REQUIRED_USE}"
		
#		unset ECLASS E_IUSE E_REQUIRED_USE E_DEPEND E_RDEPEND E_PDEPEND 

		# alphabetically ordered by $EBUILD_PHASE value
		case "$EAPI" in
			0|1)
				_valid_phases="src_compile pkg_config pkg_info src_install
					pkg_nofetch pkg_postinst pkg_postrm pkg_preinst pkg_prerm
					pkg_setup src_test src_unpack"
				;;
			2|3|3_pre2)
				_valid_phases="src_compile pkg_config src_configure pkg_info
					src_install pkg_nofetch pkg_postinst pkg_postrm pkg_preinst
					src_prepare pkg_prerm pkg_setup src_test src_unpack"
				;;
			*)
				_valid_phases="src_compile pkg_config src_configure pkg_info
					src_install pkg_nofetch pkg_postinst pkg_postrm pkg_preinst
					src_prepare pkg_prerm pkg_pretend pkg_setup src_test src_unpack"
				;;
		esac

		DEFINED_PHASES=
		for _f in $_valid_phases ; do
			if declare -F $_f >/dev/null ; then
				_f=${_f#pkg_}
				DEFINED_PHASES+=" ${_f#src_}"
			fi
		done
		[[ -n $DEFINED_PHASES ]] || DEFINED_PHASES=-

		unset _f _valid_phases
