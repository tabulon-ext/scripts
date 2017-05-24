#!/bin/bash

# ----------------------------------------------------------

# rcopy
#
# Copies files along with their dependencies to a virtual
# root directory.  The resulting file's path is reproduced
# based on its source.
#
# Usage: [bash] rcopy[.sh] [options] -t directory source ...
#        [bash] rcopy[.sh] [options] source ... directory
#
# Disclaimer: This tool comes with no warranty.
#
# Author: konsolebox
# Copyright Free / Public Domain
# May 24, 2017

# ----------------------------------------------------------

# TODO: Support symbolic-link path nodes containing absolute paths,
#       by converting them to relative forms.

[[ ${BASH_VERSINFO} -ge 4 ]] || {
	echo "Bash version 4.0 or newer is needed to run this script." >&2
	exit 1
}

CONFIG_CP_OPTS=()
CONFIG_HARD_LINK_MODE=false
CONFIG_TARGET_ROOT=
CONFIG_VERBOSE=false
CONFIG_QUIET=false

declare -A PROCESSED=()

VERSION=2017-05-24

function log_message {
	[[ ${CONFIG_QUIET} == false ]] && echo "rcopy: $1"
}

function log_warning {
	echo "rcopy: Warning: $1"
}

function log_verbose {
	[[ ${CONFIG_VERBOSE} == true ]] && echo "rcopy: $1"
}

function log_error {
	echo "rcopy: Error: $1"
}

function fail {
	log_error "$1"
	exit 1
}

function show_help_info {
	echo "Copies files along with their dependencies to a virtual root directory.
The resulting file's path is reproduced based from its source.

Usage: $0 [options] -t directory source ...
       $0 [options] source ... directory

  -h, --help       Show this help info.
  -H, --hard-link  Hard-link files instead of copying.
  -q, --quiet      Show no message.
  -v, --verbose    Be verbose.
  -V, --version    Show version.

Disclaimer: This tool comes with no warranty."
}

function get_clean_path {
	local t1 t2=() i=0 IFS=/

	if [[ $1 == /* ]]; then
		read -ra t1 <<< "$1"
	else
		read -ra t1 <<< "${PWD}/$1"
	fi

	for __ in "${t1[@]}"; do
		case $__ in
		..)
			[[ i -gt 0 ]] || fail "Path tries to get the parent directory of '/': $1"
			unset 't2[--i]'
			continue
			;;
		.|'')
			continue
			;;
		esac

		t2[i++]=$__
	done

	__="/${t2[*]}"
}

function cp {
	local messages r
	messages=$(command cp "${CONFIG_CP_OPTS[@]}" "$@" 2>&1)
	r=$?

	if [[ -n ${messages} ]]; then
		local lines=()
		readarray -t lines <<< "${messages}"
		printf 'rcopy: cp: %s\n' "${lines[@]}"
	fi

	return "$r"
}

function copy_dir_structure {
	local source_tree=() dest_dir=$2 current_source= link_target __
	IFS=/ read -ra source_tree <<< "$1"

	for __ in "${source_tree[@]}"; do
		[[ -z $__ ]] && continue
		current_source+=/$__

		if [[ -L ${current_source} ]]; then
			[[ ! -d ${current_source} ]] && fail "Parent path node of a source tree is expected to be a directory but isn't: ${current_source}"

			link_target=$(readlink "${current_source}") && [[ -n ${link_target} ]] || fail "Unable to get link's target: ${current_source}"
			[[ ${link_target} == /* ]] && fail "Symbolic-link path nodes that resolve to absolute paths are not yet supported: \"${current_source}\" -> \"${link_target}\""

			if [[ -e ${dest_dir}${current_source} ]]; then
				if [[ -L ${dest_dir}${current_source} ]]; then
					log_warning "Overwriting existing link \"${dest_dir}${current_source}\" with \"${current_source}\"."
				else
					fail "Unable to copy symbolic link from \"${current_source}\" to \"${dest_dir}${current_source}\" since a file or directory already exists."
				fi
			fi

			log_message "Copying symbolic link \"${current_source}\" (-> \"${link_target}\") to \"${dest_dir}${current_source}\""
			log_verbose "Command: cp ${CONFIG_CP_OPTS[*]} -d -- \"${current_source}\" \"${dest_dir}${current_source}\""
			cp "${CONFIG_CP_OPTS[@]}" -d -- "${current_source}" "${dest_dir}${current_source}" || fail "Copy failed."

			get_clean_path "${current_source}/../${link_target}"
			copy_dir_structure "$__" "${dest_dir}"
		elif [[ -d ${current_source} ]]; then
			if [[ ! -e ${dest_dir}${current_source} ]]; then
				log_message "Creating directory \"${dest_dir}${current_source}\"."
				mkdir -- "${dest_dir}${current_source}" || fail "Unable to create directory \"${dest_dir}${current_source}\"."
			elif [[ ! -d ${dest_dir}${current_source} ]]; then
				fail "\"${dest_dir}${current_source}\" already exists but is not a directory."
			fi
		else
			fail "Parent path node of a source tree is neither a directory nor a symbolic link: ${current_source}"
		fi
	done
}

function process {
	local deps dest dest_dir __

	for __; do
		if [[ -L $__ ]]; then
			process "$(readlink -m -- "$__")"
		elif [[ -f $__ && -x $__ ]]; then
			deps=()
			readarray -t deps < <(exec ldd "$__" | grep -Po '/\S+')
			process "${deps[@]}"
		fi

		dest=${CONFIG_TARGET_ROOT}$__
		dest_dir=${dest%/*}

		if [[ ! -e ${dest_dir} ]]; then
			copy_dir_structure "${__%/*}" "${CONFIG_TARGET_ROOT}"
		elif [[ ! -d ${dest_dir} ]]; then
			fail "Destination directory \"${dest_dir}\" already exists but is not a directory."
		fi

		if [[ -z ${PROCESSED[$__]} ]]; then
			if [[ ${CONFIG_HARD_LINK_MODE} == true ]]; then
				log_message "Hard-linking \"$__\" to \"${dest_dir}/\"."
				cp -a -H -- "$__" "${dest_dir}/"
			else
				log_message "Copying \"$__\" to \"${dest_dir}/\"."
				cp -a -- "$__" "${dest_dir}/"
			fi

			[[ $? -eq 0 ]] || fail "Copy failed."
			PROCESSED[$__]=.
		fi
	done
}

function main {
	local file_args=()

	while [[ $# -gt 0 ]]; do
		case $1 in
		-h|--help)
			show_help_info
			exit 1
			;;
		-H|--hard-link)
			CONFIG_HARD_LINK_MODE=true
			;;
		-q|--quiet)
			CONFIG_QUIET=true
			CONFIG_VERBOSE=false
			;;
		-t|--target-root)
			CONFIG_TARGET_ROOT=$2
			shift
			;;
		-v|--verbose)
			CONFIG_QUIET=false
			CONFIG_VERBOSE=true
			CONFIG_CP_OPTS=("-v")
			;;
		-V|--version)
			echo "${VERSION}"
			exit 1
			;;
		--)
			shift

			for __; do
				[[ ! -e $__ ]] && fail "File or directory does not exist: $__"
				get_clean_path "$__"
				file_args+=("$__")
			done

			break
			;;
		-*)
			fail "Invalid option: $1"
			;;
		*)
			[[ ! -e $1 ]] && fail "File or directory does not exist: $1"
			get_clean_path "$1"
			file_args+=("$__")
			;;
		esac

		shift
	done

	[[ ${#file_args[@]} -eq 0 ]] && fail "No source file specified."

	if [[ -z ${CONFIG_TARGET_ROOT} ]]; then
		[[ ${#file_args[@]} -lt 2 ]] && fail "No target directory specified."
		CONFIG_TARGET_ROOT=${file_args[@]:(-1)}
		unset "file_args[${#file_args[@]} - 1]"
	fi

	[[ ${CONFIG_TARGET_ROOT} == / ]] && fail "Target root directory can't be '/'."

	process "${file_args[@]}"
}

main "$@"
