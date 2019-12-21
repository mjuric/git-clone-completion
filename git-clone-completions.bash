# intelligent bash completion support for 'git clone' from github
#
# Copyright (C) 2019 Mario Juric <mjuric@astro.washington.edu>
# and others, as specified.
#
# Distributed under the GNU General Public License, version 2.0.
#
# This script complements the autocompletion scripts that ship
# with git, but can be used standalone as well.
#

#############################
#                           #
#    Completion utilities   #
#                           #
#############################

####
# The following utility functions have been based on code from:
#
#   bash/zsh completion support for core Git.
#
#   Copyright (C) 2006,2007 Shawn O. Pearce <spearce@spearce.org>
#   Conceptually based on gitcompletion (http://gitweb.hawaga.org.uk/).
#   Distributed under the GNU General Public License, version 2.0.
#
# parts of which were itself based on code from:
#
#   bash_completion - programmable completion functions for bash 3.2+
#
#   Copyright © 2006-2008, Ian Macdonald <ian@caliban.org>
#             © 2009-2010, Bash Completion Maintainers
#                     <bash-completion-devel@lists.alioth.debian.org>
#
#   This program is free software; you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation; either version 2, or (at your option)
#   any later version.
#
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program; if not, see <http://www.gnu.org/licenses/>.
#
#   The latest version of this software can be obtained here:
#
#   http://bash-completion.alioth.debian.org/
#
#   RELEASE: 2.x
__mj_reassemble_comp_words_by_ref()
{
	local exclude i j first
	# Which word separators to exclude?
	exclude="${1//[^$COMP_WORDBREAKS]}"
	cword_=$COMP_CWORD
	if [ -z "$exclude" ]; then
		words_=("${COMP_WORDS[@]}")
		return
	fi
	# List of word completion separators has shrunk;
	# re-assemble words to complete.
	for ((i=0, j=0; i < ${#COMP_WORDS[@]}; i++, j++)); do
		# Append each nonempty word consisting of just
		# word separator characters to the current word.
		first=t
		while
			[ $i -gt 0 ] &&
			[ -n "${COMP_WORDS[$i]}" ] &&
			# word consists of excluded word separators
			[ "${COMP_WORDS[$i]//[^$exclude]}" = "${COMP_WORDS[$i]}" ]
		do
			# Attach to the previous token,
			# unless the previous token is the command name.
			if [ $j -ge 2 ] && [ -n "$first" ]; then
				((j--))
			fi
			first=
			words_[$j]=${words_[j]}${COMP_WORDS[i]}
			if [ $i = $COMP_CWORD ]; then
				cword_=$j
			fi
			if (($i < ${#COMP_WORDS[@]} - 1)); then
				((i++))
			else
				# Done.
				return
			fi
		done
		words_[$j]=${words_[j]}${COMP_WORDS[i]}
		if [ $i = $COMP_CWORD ]; then
			cword_=$j
		fi
	done
}

#
# copied from a version of git-completion.bash
#
_mj_get_comp_words_by_ref ()
{
	local exclude cur_ words_ cword_
	if [ "$1" = "-n" ]; then
		exclude=$2
		shift 2
	fi
	__mj_reassemble_comp_words_by_ref "$exclude"
	cur_=${words_[cword_]}
	while [ $# -gt 0 ]; do
		case "$1" in
		cur)
			cur=$cur_
			;;
		prev)
			prev=${words_[$cword_-1]}
			;;
		words)
			words=("${words_[@]}")
			;;
		cword)
			cword=$cword_
			;;
		esac
		shift
	done
}

#                                                          #
############################################################

#
# Get a list of positional arguments, and the index of the
# current word within that list, if the current word is a
# positional argument.
#
# If $cword is a positional argument sets $argidx to its index
# ignoring any options that may have been specified before it.
# If $cword is not a positional argument (e.g., it's an option
# or an option's argument), sets $argidx to empty
#
# arguments: list of options that admit an argument, suffixed by '='
#
# example:
#     * assuming competion of `git clone --test foo`
#         __arg_index --foo= --bar= --baz=
#       sets argidx=2
#     * assuming competion of `git clone --test foo`
#         __arg_index --test=
#       sets argidx=
#     * assuming competion of `git clone --test foo -k`
#         __arg_index --test=
#       sets argidx=
#     * assuming competion of `git clone --test foo -k bar`
#         __arg_index --test=
#       sets argidx=2
#
# author: mjuric@astro.washington.edu
#
__arg_index()
{
	# returned list of positional arguments
	posargs=( ${words[0]} )

	local c p i idx=0
	for i in $(seq 1 $cword); do
		p=${words[i-1]}	# previous word
		c=${words[i]}	# current word
		o=1			# was this word an option (begin by assuming it was)?

		# an option
		[[ $c == -* ]] && continue

		# an argument of a previously specified option
		[[ $p == -* && p != -*=* ]] && (echo "$@" | grep -qw -- "$p=") && continue

		# a positional argument
		o=0
		idx=$((idx+1))
		posargs+=($c)
	done

	# set $argidx only if the current word was an argument
	[[ $o == 0 ]] && argidx=$idx || argidx=
}

# find and echo the common prefix of passed arguments
# inspired by https://stackoverflow.com/a/28647824
__mj_common_prefix()
{
	[[ $# -eq 0 ]] && return 0

	local first prefix v
	first="$1"
	shift
	for ((i = 0; i < ${#first}; ++i)); do
		prefix=${first:0:i+1}
		for v; do
			if [[ ${v:0:i+1} != "$prefix" ]]; then
				echo "${first:0:i}"
				return
			fi
		done
	done

	echo "$first"
}

#
# debugging utility. set GG_DEBUG="$HOME/_completion.log" and run
# `tail -f $GG_DEBUG` to observe what's going on.
#
_dbg()
{
	[[ -n $GG_DEBUG ]] && echo "[$(date)]" "$@" >> "$GG_DEBUG"
}

#
# trim completions to the substring bash expects to see.
#
# details: bash tokenizes the input string by breaking it on characters
# found in $COMP_WORDBREAKS.  The resulting tokenized list is placed into
# the ${COMP_WORDS[@]} array for autocompletion functions to use.  This is
# fragile for our purposes as a) the user can override the characters, and
# b) is known to be horribly buggy in older versions of bash (spcifically
# v3.2 that is included with macOS). We therefore don't use this tokenization,
# but re-tokenize the line (see _mj_get_comp_words_by_ref) to get tokens
# broken up on "sane" characters (though that's not entirely foolproof).
#
# The COMPREPLY that we construct generates replies in reference to that
# re-tokenized array. For example, 'git@gi' may get suggestions such as
# COMPREPLY=('git@github.com:' 'git@gitlab.com:'). However, bash expects to 
# get suggestions to replace only the last token as *it* generated (which,
# if $COMP_WORDBREAKS included '@', would only be 'gi' in the example above.
# So we have to change COMPREPLY to return what bash expects, by removing
# the longest prefix from the input token (e.g., 'git@gi' above) that ends
# in one of the delimiters we chose to ignore when re-tokenizing (typically
# @, :, and =. So this function would change COMPREPLY to
# COMPREPLY=('github.com:' 'gitlab.com:')
#
# Notes: bash 3.2 has two rather nasty bugs we have to take care of:
#   - a) when not splitting on ':', it leaves the delimiter as a part
#        of the input string (e.g., 'git@gi' gets split into 'git' '@gi'),
#        so our suggestions must include the delimiter (i.e., example
#        above would have COMPREPLY=('@github.com:' '@gitlab.com:') ).
#   - b) to make matters more confusing, while the tokenization is done
#        on all characters it $COMP_WORDBREAKS, the ${COMP_WORDS[@]}
#        array ends up being tokenized on just the spaces! E.g., in
#        the example above COMP_WORDS=('git' 'clone' 'git@gi') on bash 3.2
#        whereas on 4.0 and newer it would (correctly) be equal to
#        COMP_WORDS=('git' 'clone' 'git' '@' 'gi')
#
# inputs and outputs are passed via environmental variables.
#
# inputs:
#   $1: the current word (as returned by _mj_get_comp_words_by_ref)
#   ${COMPREPLY[@]}: the completions relative to re-tokenized line (input)
#
# outputs:
#   ${COMPREPLY[@]}: completions that can be passed back to bash to
#                    correctly auto-complete the word.
#
# author: mjuric@astro.washington.edu
#
__mj_ltrim_completions()
{
	# characters that readline breaks on, but we don't
	local nobreak='@:='

	# find the longest prefix delimited by a char in $nobreak
	# that also appears in $COMP_WORDBREAKS
	local prefix=
	local c char
	while read -n1 c; do
		[[ "$COMP_WORDBREAKS" != *"$c"* ]] && continue

		local try=${1%"${1##*$c}"}     # "
		[[ "${#try}" -gt "${#prefix}" ]] && { prefix="$try"; char=$c; }
	done < <(echo -n "$nobreak")

	# bugfix for bash 3.2 (macOS): leave the delimiter if it's not ':'
	[[ "$char" != ':' ]] && prefix=${prefix%"$char"}

	# Remove the prefix from COMPREPLY items
	local i=${#COMPREPLY[*]}
	while [[ $((--i)) -ge 0 ]]; do
		COMPREPLY[$i]=${COMPREPLY[$i]#"$prefix"}
	done

	_dbg "input=$1 || prefix=$prefix || char=$char"
	_dbg COMPREPLY="${COMPREPLY[@]}"
}

#
# complete words that may contain $COMP_WORDBREAKS characters.
# also allows one to show human-readable completions different
# from actual completions (e.g. with extra information).
#
# inputs and outputs are passed via environmental variables.
#
# inputs:
#   ${compreply[@]}: the human-readable completions (input)
#   ${COMPREPLY[@]}: the completions as expected by bash (input)
#   $cur: the current word (as returned by _mj_get_comp_words_by_ref)
#
# outputs:
#   ${COMPREPLY[@]}: the human-readable completions (if bash
#                    will show them), or completions as expected
#                    by bash (if bash will complete them)
#
# author: mjuric@astro.washington.edu
#
_fancy_autocomplete()
{

	# a single or no completions: bash will autocomplete
	[[ ${#COMPREPLY[@]} -le 1 ]] && return

	# check if the completions share a common prefix, and if
	# that prefix is longer than what's been typed so far. if so,
	# bash will autocomplete up to that prefix and not show the
	# suggestions (so send it the autocompletion text).
	local prefix=$(__mj_common_prefix "${COMPREPLY[@]}")
	[[ "$prefix" != "${cur#*[$COMP_WORDBREAKS]}" ]] && return

	# Not possible to autocomplete beyond what's currently been
	# typed, so bash will show suggestions. Send the human-readable
	# form.
	#
	# Note: the appended character is the UTF-8 non-breaking space,
	# which sorts to the end.  It's needed to prevent bash from trying
	# to autocomplete a common prefix in the human-readable options, if
	# any.
	COMPREPLY=("${compreply[@]}" " ")
}

#
# complete words that may contain $COMP_WORDBREAKS characters.
#
# inputs and outputs are passed via environmental variables.
#
# inputs:
#   ${COMPREPLY[@]}: the completions  (input)
#   $cur: the current word (as returned by _mj_get_comp_words_by_ref)
#
# outputs:
#   ${COMPREPLY[@]}: the completions with $COMP_WORDBREAKS characters (if
#                    bash will show them to the user), or completions as
#                    expected by bash (if bash will complete them)
#
# author: mjuric@astro.washington.edu
#
_colon_autocomplete()
{
	# save the human form
	local compreply=("${COMPREPLY[@]}")
	__mj_ltrim_completions "$cur"
	_fancy_autocomplete
}



#######################################
#                                     #
#         REST Call Utilities         #
#                                     #
#######################################

# configuration
GG_CFGDIR=${XDG_CONFIG_HOME:-$HOME/.config/git-clone-completions}
GG_CACHEDIR=${XDG_CACHE_HOME:-$HOME/.cache/git-clone-completions}

# call an endpoint and retrieve the full result.
# reads all pages if the result is paginated and has the
# standard Link: header.
#
# _rest_call <curl_with_auth> <url>
#
_rest_call()
{
	local curl="$1"
	local url="$2"

	local tmp=$(mktemp)

	while [[ -n "$url" ]]; do
		# download page
		$curl -f -s -D "$tmp" "$url" || { rm -f "$tmp"; return 1; }

		# find the next URL
		url=$(cat "$tmp" | sed -En 's/^Link: (.*)/\1/p' |tr ',' '\n' | grep 'rel="next"' | sed -nE 's/^.*<(.*)>.*$/\1/p')
	done
	rm -f "$tmp"
}

########################################################################
#
# Repository hosting services
#
########################################################################

__SERVICES=()

##########################
#
# GitLab support
#
##########################

__SERVICES+=( gitlab )
__gitlab_PREFIXES="https://gitlab.com/ git@gitlab.com:"
GG_AUTH_gitlab="$GG_CFGDIR/gitlab.auth.curl"
GG_CANONICAL_HOST_gitlab="gitlab.com"

#
# acquire credentials for GitLab API access. the user
# is prompted to call this from the command line.
#
init-gitlab-completion()
{
	echo "Logging into GitLab so we can list repositories..."
	echo "Please visit:"
	echo
	echo "    https://gitlab.com/profile/personal_access_tokens"
	echo
	echo "and generate a new personal access token:"
	echo
	echo "    1. Under 'Name', write 'git-clone-completions access for $USER@$(hostname)'"
	echo "    2. Leave 'Expires at' empty"
	echo "    3. Under 'Scopes', check 'api' and leave others unchecked."
	echo
	echo "Then click the 'Create personal access token' button (below the form)."
	echo
	echo "The PAT is equivalent to a password we can use to list repositories in your GitLab account."
	echo "Copy the newly generated token and paste it here."
	echo ""
	read -sp "Token (note: the typed characters won't show): " TOKEN; echo
	read -p  "Your GitLab username: " GLUSER

	# securely store the token and user to a netrc-formatted file
	mkdir -p "$(dirname $GG_AUTH_gitlab)"
	rm -f "$GG_AUTH_gitlab"
	touch "$GG_AUTH_gitlab"
	chmod 600 "$GG_AUTH_gitlab"
	# note: echo is a builtin so this is secure (https://stackoverflow.com/a/15229498)
	echo "header \"Authorization: Bearer $TOKEN\"" >> "$GG_AUTH_gitlab"

	# verify that the token works
	if ! _gitlab_call users/$GLUSER/projects >/dev/null; then
		_gitlab_curl -s "https://gitlab.com/api/v4/users/$GLUSER/projects"; echo
		echo
		echo "Hmm, something went wrong -- check the token for typos and/or proper scope. Then try again."
		rm -f "$GG_AUTH_gitlab"
		return 1
	else
		echo
		echo "Authentication setup complete; token stored to '$GG_AUTH_gitlab'"
	fi
}

# curl call with github authentication
_gitlab_curl()
{
	curl --config "$GG_AUTH_gitlab" "$@"
}

# _gitlab_call <endpoint> <options>
#
# example: _gitlab_call groups/gitlab-org/projects simple=true
#
_gitlab_call()
{
	local endpoint="$1"
	local options="$2"

	_rest_call _gitlab_curl "https://gitlab.com/api/v4/$endpoint?per_page=100&$options"
}

# download the repository list of <user|org>
_gitlab_repo_list()
{
	# GitLab doesn't have a unified API for both users and orgs
	# ('groups' in GitLab parlance). We try users then groups.

	( _gitlab_call users/"$1"/projects simple=true || _gitlab_call groups/"$1"/projects simple=true ) | jq -r '.[].path'
}

##########################
#
# GitHub support
#
##########################

__SERVICES+=( github )
__github_PREFIXES="https://github.com/ git@github.com:"
GG_AUTH_github="$GG_CFGDIR/github.auth.netrc"
GG_CANONICAL_HOST_github="github.com"

#
# acquire credentials for GitHub API access. the user
# is prompted to call this from the command line.
#
init-github-completion()
{
	echo "Logging into github so we can list repositories..."
	echo "Please visit:"
	echo
	echo "    https://github.com/settings/tokens/new"
	echo
	echo "and generate a new personal access token:"
	echo
	echo "    1. Under 'Note', write 'git-clone-completions access for $USER@$(hostname)'"
	echo "    2. Under 'Select scopes', check 'repo:status' and leave otherwise unchecked."
	echo
	echo "Then click the 'Generate Token' green button (bottom of the page)."
	echo
	echo "The PAT is equivalent to a password we can use to list repositories in your github account."
	echo "Copy the newly generated token and paste it here."
	echo ""
	read -sp "Token (note: the typed characters won't show): " TOKEN; echo
	read -p "Your GitHub username: " GHUSER

	# securely store the token and user to a netrc-formatted file
	mkdir -p "$(dirname $GG_AUTH_github)"
	rm -f "$GG_AUTH_github"
	touch "$GG_AUTH_github"
	chmod 600 "$GG_AUTH_github"
	# note: echo is a builtin so this is secure (https://stackoverflow.com/a/15229498)
	echo "machine api.github.com login $GHUSER password $TOKEN" >> "$GG_AUTH_github"

	# verify that the token works
	if ! curl -I -f -s --netrc-file "$GG_AUTH_github" "https://api.github.com/user" >/dev/null; then
		curl -s "https://api.github.com/user"
		echo "Hmm, something went wrong -- most likely you've typed the token incorretly. Rerun and try again."
		rm -f "$GG_AUTH_github"
		return 1
	else
		echo
		echo "Authentication setup complete; token stored to '$GG_AUTH_github'"
	fi
}

# curl call with github authentication
_github_curl()
{
	curl --netrc-file "$GG_AUTH_github" "$@"
}

# _github_call <endpoint> <options>
#
# example: _github_call groups/github-org/projects simple=true
#
_github_call()
{
	local endpoint="$1"
	local options="$2"

	_rest_call _github_curl "https://api.github.com/$endpoint?per_page=100&$options"
}

# download the repository list of <user|org>
_github_repo_list()
{
	_github_call users/"$1"/repos | jq -r '.[].name'
}

##########################
#
# Bitbucket support
#
##########################

__SERVICES+=( bitbucket )
__bitbucket_PREFIXES="https://bitbucket.org/ git@bitbucket.org:"
GG_AUTH_bitbucket="$GG_CFGDIR/bitbucket.auth.curl"
GG_CANONICAL_HOST_bitbucket="bitbucket.org"

#
# acquire credentials for Bitbucket API access. the user
# is prompted to call this from the command line.
#
init-bitbucket-completion()
{
	local BBUSER BBPASS

	echo "Logging into Bitbucket so we can list repositories..."
	echo
	read -p "Your Bitbucket username: " BBUSER
	echo
	echo "Now please visit:"
	echo
	echo "    https://bitbucket.org/account/user/$BBUSER/app-passwords/new"
	echo
	echo "to generate a new 'app password':"
	echo
	echo "    1. Under 'Label', write 'git-clone-completions access for $USER@$(hostname)'"
	echo "    2. Under 'Permissions', check:"
	echo "       a) 'Read' under 'Account'"
	echo "       b) 'Read' under 'Projects'"
	echo
	echo "and leave others unchecked. Then click the 'Create' button."
	echo
	echo "This is an app-specific password which we will use to list repositories"
	echo "in your GitLab account."
	echo
	echo "Copy the newly generated password and paste it here."
	echo ""
	read -sp "Password (note: the typed characters won't show): " BBPASS; echo

	# securely store the token and user to a netrc-formatted file
	mkdir -p "$(dirname $GG_AUTH_bitbucket)"
	rm -f "$GG_AUTH_bitbucket"
	touch "$GG_AUTH_bitbucket"
	chmod 600 "$GG_AUTH_bitbucket"
	# note: echo is a builtin so this is secure (https://stackoverflow.com/a/15229498)
	echo "user \"$BBUSER:$BBPASS\"" >> "$GG_AUTH_bitbucket"

	# verify that the token works
	if ! _bitbucket_call "2.0/repositories/$BBUSER" >/dev/null; then
		echo
		echo "Hmm, something went wrong -- check the token for typos and/or proper scope. Then try again."
		rm -f "$GG_AUTH_bitbucket"
		return 1
	else
		echo
		echo "Authentication setup complete; token stored to '$GG_AUTH_bitbucket'"
	fi
}

# curl call with bitbucket authentication
_bitbucket_curl()
{
	curl --config "$GG_AUTH_bitbucket" "$@"
}

# _bitbucket_call <endpoint> <options>
#
# example: _bitbucket_call 2.0/repositories/atlassian simple=true
#
_bitbucket_call()
{
	local endpoint="$1"
	local options="$2"

	local url="https://api.bitbucket.org/$endpoint?pagelen=100&$options"

	local tmp=$(mktemp)
	while [[ -n "$url" ]]; do
		# download page
		_bitbucket_curl -f -s "$url" > "$tmp" || { rm -f "$tmp"; return 1; }

		# echo the content
		cat "$tmp" | jq -r '.values'

		# find next page (jq trick from https://github.com/stedolan/jq/issues/354#issuecomment-43147898)
		url=$(cat "$tmp" | jq -r '.next // empty')
	done
	rm -f "$tmp"
}

# download the repository list of <user|org>
_bitbucket_repo_list()
{
	_bitbucket_call 2.0/repositories/"$1" | jq -r '.[].name'
}

############################
#
# Remote host via ssh
#
############################

# things we want to backslash escape in scp paths
_scp_path_esc='[][(){}<>",:;^&!$=?`|\\'"'"'[:space:]]'

# this will be our shortened path to SSH ControlMaster socket. See the comment
# in _scp_remote_files(), where it's initialized on first use.
__ssh_sockdir=

# Complete remote files with ssh.  If the first arg is -d, complete on dirs
# only.  Returns paths escaped with three backslashes.
_ssh_list_files()
{
	local IFS=$'\n'

	# should we only return dirs?
	local dirs_only
	[[ $1 == -d ]] && { dirs_only=1; shift; }

	# split url
	local userhost=${1%%:*}
	local path=${1#*:}
	local sockdir="${2:-$HOME/.ssh}"

	#_dbg "cur=[$1] userhost=[$userhost] path=[$path] sockdir=[$sockdir]"

	# construct our ssh invocation
	local ssh=(ssh -o 'Batchmode yes' -o "ControlMaster auto" -o "ControlPath $sockdir/%C" -o "ControlPersist 90s" "$userhost")

	local files
	if [[ $dirs_only == 1 ]]; then
		# escape problematic characters; remove non-dirs
		files=$("${ssh[@]}"  \
			command ls -aF1dL "$path*" 2>/dev/null | \
			command sed -e 's/'$_scp_path_esc'/\\&/g' -e '/[^\/]$/d')

		# if only one dir remains, and it has no subdirs, append a space
		# rather than a slash
		local f=( $files )
		if [[ ${#f[@]} == 1 ]]; then
			#_dbg "checking subdir"
			if [[ -z $("${ssh[@]}" command ls -aF1dL "$f*" 2>/dev/null | sed -e '/[^\/]$/d' ) ]]; then
				files="${f%/} "
				#_dbg "end of hierarchy: files=[[$files]]"
			fi
		fi
	else
		# escape problematic characters; remove executables, aliases, pipes
		# and sockets; add space at end of file names
		files=$("${ssh[@]}"  \
			command ls -aF1dL "$path*" 2>/dev/null | \
			command sed -e 's/'$_scp_path_esc'/\\&/g' -e 's/[*@|=]$//g' \
			-e 's/[^\/]$/& /g')
	fi

	COMPREPLY=($files)
	#echo "$files"
}

_ssh_list_files_w_progress()
{
	# set up ssh multiplexing, for faster path browsing
	local sockdir0="$GG_CACHEDIR/ssh-sockets"
	mkdir -p "$sockdir0"
	chmod 700 "$sockdir0"

	# for ssh multiplexing to work, we need to make the path to the control socket
	# shorter than 104 chars (https://unix.stackexchange.com/a/367012). Otherwise
	# you'll see myterious 'unix_listener: path "..." too long for Unix domain socket'
	# messages pop up. So instead of passing the real path, we'll create a shorter
	# symlink to the path in /tmp (/tmp must exist; see https://superuser.com/a/332616)
	# unfortunately, we can't just `mktemp -d` because macOS is weird and doesn't
	# respect TMPDIR (https://unix.stackexchange.com/a/555214), so we try to emulate
	# it's secure path creation.
	while [[ -z $__ssh_sockdir ]]; do
		__ssh_sockdir="/tmp/git-comp-$USER.$$.$RANDOM"
		if mkdir "$__ssh_sockdir" 2>/dev/null; then
			chmod 700 "$__ssh_sockdir";
			ln -s "$sockdir0" "$__ssh_sockdir/s"
			break;
		fi
	done
	local sockdir="$__ssh_sockdir/s"

	# get the file listing in the background, returning the
	# results in file $results (atomically)
	local results="$GG_CACHEDIR/ssh-listing.$$.$RANDOM.tmp"
	( (
		mkdir -p $(basename "$results")
		_ssh_list_files "$@" "$sockdir"
		printf "%s\n" "${COMPREPLY[@]}" > "$results.2"
		mv "$results.2" "$results"
	  ) &
	)

	# wait for "$results" to become available, showing the
	# spinner if it's taking awhile
	#_dbg "about to spin-wait"
	spin_wait "[[ -f \"$results\" ]]" 1>&2
	#_dbg "spin-wait done."

	IFS=$'\n' read -d '' -r -a COMPREPLY <"$results"
	#_dbg "COMPREPLY=""${COMPREPLY[@]}"
	rm -f "$results"
}

#
# Show a fancy spinner until `eval "$1"` becomes true
#
spin_wait()
{
	cond="$1"

	# wait with spinner (pattern from https://github.com/swelljoe/spinner/blob/master/spinner.sh)
	local -a marks=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
	local i=0
	local spinstart=10
	while ! eval "$cond"; do
		if [[ $i -ge $spinstart ]]; then
			# show the spinner if we've waited for longer than a second
			[[ $i -eq $spinstart ]] && printf '  '
			printf '\b\b%s ' "${marks[i % ${#marks[@]}]}"
		fi
		sleep 0.1
		let i++
	done
	[[ $i -gt $spinstart ]] && printf '\b\b  \b\b'
}

# test if we're completing a generic SSH URL, complete it if so, return 1
# otherwise and the URL prefix to watch for in __PREFIXES
#
# args:
#       $cur
#
# returns:
#	COMPREPLY
#	Adds own prefixes to __PREFIXES
#
# author: mjuric@astro.washington.edu
#
_complete_ssh_url()
{
	local cur="$1"
	local recent="$GG_CACHEDIR/ssh.recent"

	# $cur may be [foo@]example.com:[dir]; check if that's the case
	if [[ $cur != *:* ]]; then
		local offers=( $(cut -d ' ' -f 2 "$recent" 2>/dev/null) )
		offers=( "${offers[@]/%/:}" )
		#_dbg "offers=[${offers[*]}]"
		__PREFIXES="$__PREFIXES ${offers[*]}"
		return 1
	fi

	# autocomplete the path
	_ssh_list_files_w_progress -d "$cur"

	# remember last few successful completions to offer to
	# autocomplete them.
	if [[ ${#COMPREPLY[@]} != 0 ]]; then
		#_dbg "recent=[$recent]"
		mkdir -p $(dirname "$recent")

		local tmp="$recent.$$.$RANDOM.tmp"
		cat "$recent" >"$tmp" 2>/dev/null
		local userhost=${cur%%:*}
		echo "$(date +%s) $userhost" >> "$tmp"

		# keep 5 most recently used unique entries
		# algorithm: sort desc by hostname, time | keep first of each hosts | sort desc by time | keep first 5
		sort -k2,2 -k1,1 -r "$tmp" | uniq -f 1 | sort -rn -k1,1 | head -n 5 > "$tmp.2"
		mv "$tmp.2" "$recent"

		rm -f "$tmp" "$tmp.2"
	fi

	return 0
}

######################

#
# Return a list of repositories from github.com/<org> as cached in <dest_cache_fn>,
# automatically refreshing it if necessary. If a refresh is needed, <dest_cache_fn>
# will be `touch`ed as soon as the download begins (so subsequent calls to this
# function will _not_ see the cache as stale). This is intentional and allows the
# cache to be refreshed in the background (see _get_repo_list)
#
# _refresh_repo_cache <service_slug> <org> <dest_cache_fn>
#
# author: mjuric@astro.washington.edu
#
_refresh_repo_cache()
{
	local service="$1"
	local ORG="$2"
	local CACHE="$3"

	# create a temp file on the same filesystem as the destination file
	mkdir -p $(dirname "$CACHE")
	local TMP="$CACHE.$$.$RANDOM.tmp"

	_${service}_repo_list "$ORG" > "$TMP"

	# atomic update
	mv "$TMP" "$CACHE"
}

# get list of repositories from organization $1
# cache the list in $GG_CACHEDIR/github.com.$1.cache"
#
# _get_repo_list <service_slug> <org>
#
# author: mjuric@astro.washington.edu
#
_get_repo_list()
{
	local service="$1"
	local org="$2"
	local CACHE="$GG_CACHEDIR/$service.$org.cache"

	# fire off a background cache update if the cache is stale or non-existant
	if [[ -z $(find "$CACHE" -newermt '-15 seconds' 2>/dev/null) ]]; then
		( _refresh_repo_cache "$service" "$org" "$CACHE" & )
	fi

	# this is the first time we're asking for the list of repos
	# in this organization, wait for the result
	if [[ ! -f "$CACHE" ]]; then
		# wait with spinner (pattern from https://github.com/swelljoe/spinner/blob/master/spinner.sh)
		local -a marks=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
		local i=0
		local spinstart=10
		while ! test -f "$CACHE"; do
			if [[ $i -ge $spinstart ]]; then
				# show the spinner if we've waited for longer than a second
				[[ $i -eq $spinstart ]] && printf '  '
				printf '\b\b%s ' "${marks[i % ${#marks[@]}]}"
			fi
			sleep 0.1
			let i++
		done
		[[ $i -gt $spinstart ]] && printf '\b\b  \b\b'
	fi

	# return the list of repos
	REPOS=( $( cat "$CACHE" 2>/dev/null ) )
}

#
# Return completions (in COMPREPLY) for a github URL fragmend
# of the form <urlbase><org>/<repo>, where urlbase is any of
# the allowed github prefixes (e.g., http://github.com/ or
# git@github.com:), <org> is the organization, and <repo>
# is the repository.
#
# If the <org> is being completed, possible completions are taken
# from "$PROJECTS/github.com" path (w. $PROJECTS defaulting to
# ~/projects)
#
# If the <repo> is being completed, possible completions are taken from the
# list of repositories downloaded using the GitHub API.
#
# _complete_github_fragment <urlbase> "org_repo_fragment"
#
#  arg(s):
#    service slug (github or gitlab)
#    URL base (e.g., https://github.com/ or git@github.com:)
#    The (partial) 'org/repo' github URL fragment
#
#  returns:
#    Completions in ${COMPREPLY[@]}
#    In case of error, the COMPREPLY has the error message
#
# author: mjuric@astro.washington.edu
#
_resolve_var() { echo "${!1}"; }

_complete_fragment()
{
	local service="$1"
	local urlbase="$2"
	local URL="$3"

	local chost=$(_resolve_var "GG_CANONICAL_HOST_$service")
	local GG_AUTH=$(_resolve_var "GG_AUTH_$service")

#	echo service=$service urlbase=$urlbase URL=$URL chost=$chost GG_AUTH=$GG_AUTH

	# if more than one '/' character. this is not a valid URL; stop.
	[[ $URL == */*/* ]] && return 1

	# are we're completing the org or the repo part?
	if [[ $URL != */* ]]; then
		#
		# completing the org: show a list of already cloned orgs
		#
		local PROJECTS="${PROJECTS:-$HOME/projects}"
		PROJECTS="$PROJECTS/$chost"

		WORDS=( $(ls "$PROJECTS" 2>/dev/null) )
		WORDS=( "${WORDS[@]/%//}" )
	else
		#
		# completing the repo: offer a list of repos available on the service
		#
		IFS='/' read -ra arr <<< "$URL"
		ORG=${arr[0]}
		REPO=${arr[1]}

		if [[ ! -f "$GG_AUTH" ]]; then
			# short-circuit if we haven't authenticated, with
			# a helpful message
			COMPREPLY=("error: run \`init-$service-completion\` to authenticate for repository completion." "completion currently disabled.")
			return
		elif ! hash jq 2>/dev/null; then
			# short-circuit if we haven't authenticated, with
			# a helpful message
			COMPREPLY=("Error: need the \`jq\` utility for git clone completion." "see https://stedolan.github.io/jq/ or your package manager")
			return
		fi

		_get_repo_list "$service" "$ORG"
		WORDS=( "${REPOS[@]/#/$ORG/}" )		# prepend the org name
		WORDS=( "${WORDS[@]/%/ }" )		# append a space (so the suggestion completes the argument)
	fi

	# only return completions matching the typed prefix
	COMPREPLY=()
	for i in "${!WORDS[@]}"; do
		if [[ ${WORDS[i]} == "$URL"* ]]; then
			COMPREPLY+=("${WORDS[i]}")
		fi
	done

	# user-friendly completions and colon handling
	compreply=( ${COMPREPLY[@]} )			# this is to be shown to the user
	COMPREPLY=("${COMPREPLY[@]/#/$urlbase}")
	__mj_ltrim_completions "$cur"			# these are the actual completions
	_fancy_autocomplete
}

# test if we're completing a fully qualified URL of $service, complete it
# if so, return 1 otherwise and the URL prefix to watch for in __PREFIXES
#
# args:  $service
#        $cur
#        <...> additional prefixes to compare to; pass "" to compare just the fragment
#
# expects:
#        A list of URL prefixes in ${__${service}_PREFIXES}.  See
#        __github_PREFIXES for an example.
#
# returns:
#	COMPREPLY
#	Adds own prefixes to __PREFIXES
#
# author: mjuric@astro.washington.edu
#
_complete_url()
{
	local service="$1"
	local cur="$2"
	shift; shift

	local prefixes=$(_resolve_var __${service}_PREFIXES)

	local urlbase=
	for urlbase in $prefixes "$@"; do
		[[ $cur != "$urlbase"* ]] && continue

		_complete_fragment $service "$urlbase" "${cur#"$urlbase"}"
		return
	done

	__PREFIXES="$__PREFIXES $prefixes"
	return 1
}

#################
#               #
# Update checks #
#               #
#################

GG_NO_UPDATE_MARKER="$GG_CFGDIR/no-update-checks"
GG_NEW_VERSION="$GG_CACHEDIR/git-clone-completions.bash"
GG_SELF="${BASH_SOURCE[0]}"
#GG_UPDATE_CHECK_INTERVAL='-1 weeks'
#GG_UPDATE_NAG_INTERVAL='-1 weeks'
GG_UPDATE_CHECK_INTERVAL='-30 seconds'
GG_UPDATE_NAG_INTERVAL='-2 minutes'

__check_and_download_update()
{
	# don't check if we've checked within the last week
	if [[ -n $(find "$GG_NEW_VERSION" -newermt "$GG_UPDATE_CHECK_INTERVAL" 2>/dev/null) ]]; then
		return
	fi

	# to avoid having multiple instances downloading the same file
	mkdir -p $(dirname "$GG_NEW_VERSION")
	touch "$GG_NEW_VERSION"

	# download the current version
	local tmp="$GG_NEW_VERSION.$$.$RANDOM.tmp"

	if curl -f -s "https://raw.githubusercontent.com/mjuric/git-utils/master/git-clone-completions.bash" -o "$tmp" >/dev/null 1>&2 &&	# download
	   [[ -s "$tmp" ]] &&				# continue if not empty
	   ! cmp -s "$GG_SELF" "$tmp" 2>/dev/null &&	# continue if not the same
	   bash -n "$tmp" 2>/dev/null;			# continue if not malformed
	then
		# we have a new update ready to install!
		mv "$tmp" "$GG_NEW_VERSION"
	else
		rm -f "$tmp"
	fi
}

gg-update()
{
	if [[ ! -f "$GG_NEW_VERSION" ]]; then
		echo "git-clone-completions: no new version available for update." 1>&2
		return
	fi

	# save a backup
	local backup="$GG_CACHEDIR/git-clone-completions.bash.$(date)"
	cp -a "$GG_SELF" "$backup"

	echo
	echo "saved the current version to:"
	echo "    $backup"
	echo

	# replace self with the new version
	echo "Now run: "
	echo
	echo "   mv '$GG_NEW_VERSION' '$GG_SELF'"
	echo
	echo "to update."
	#echo "git-clone-completions: update complete! source $SELF to activate."
}

gg-stop()
{
	rm -f "$GG_NEW_VERSION"

	mkdir -p $(dirname "$GG_NO_UPDATE_MARKER")
	touch "$GG_NO_UPDATE_MARKER"

	echo "git-clone-completions: won't check for updates going forward."
}

__check_update()
{
	# don't check if the user told us not to
	[[ -f $GG_NO_UPDATE_MARKER ]] && return

	# asynchronously check for updates
	( __check_and_download_update & )

	# if an update is ready to be installed, let the user know (but don't nag too much)
	nagfile="$GG_CACHEDIR/last_update_nag"
	if [[
	      -s "$GG_NEW_VERSION" &&
	      -z $(find "$nagfile" -newermt "$GG_UPDATE_NAG_INTERVAL" 2>/dev/null)
	]]; then
		mkdir -p $(basename "$nagfile")
		touch "$nagfile"

		echo "message: new git-clone-completions available; run gg-update to update. run gg-stop to stop update checks." 1>&2
	fi
}

# Enable for everyone once we're happy with how well this works
: __check_update

#######################
#                     #
# Install completions #
#                     #
#######################

#
# This block must come _before_ redefining _git_clone (and possibly other functions)
#
_msg=1

if ! hash jq 2>/dev/null; then
	[[ _msg -ne 1 ]] && echo
	echo "error $_msg: *** git clone completion disabled because you're missing 'jq'  ***" 1>&2
	echo "error $_msg: ***   if using brew, run:   \`brew install jq\`                  ***" 1>&2
	echo "error $_msg: ***   if using conda, run:  \`conda install jq\`                 ***" 1>&2
	echo "error $_msg: ***   on Ubuntu, run:       \`sudo apt-get install jq\`          ***" 1>&2
	echo "error $_msg: ***   on Fedora, run:       \`sudo dnf install jq\`              ***" 1>&2
	echo "error $_msg: *** or download a pre-built binary from:                       ***" 1>&2
	echo "error $_msg: ***   https://stedolan.github.io/jq/download/                  ***" 1>&2
	let _msg++
fi

# Enable completion for:
#  git clone
#  git get
if declare -F _git > /dev/null; then
	# yes, we have git's autocomplete.

	# Have we already monkey-patched `_git_clone`?
	if  ! declare -F _mj_git_clone_orig > /dev/null; then
		# We haven't. duplicate and rename it to '_mj_git_clone_orig'
		eval "$(declare -f _git_clone | sed 's/_git_clone/_mj_git_clone_orig/')"
	fi
else
	[[ _msg -ne 1 ]] && echo
	echo "warning $_msg: *** no git autocompletion found; installing standalone one for git clone" 1>&2
	echo "warning $_msg: *** a) ensure that git completion scripts are sourced _after_ this script, and/or..." 1>&2
	echo "warning $_msg: *** b) see https://stackoverflow.com/questions/12399002/how-to-configure-git-bash-command-line-completion" 1>&2
	echo "warning $_msg: ***    for how to set up git completion." 1>&2
	let _msg++

	# no git autocompletions; add shims and declare we'll autocomplete 'git'
	_mj_git_clone_orig() { : ; }

	_git()
	{
		# get a sane decomposition of the command line,
		local cur words cword prev
		_mj_get_comp_words_by_ref -n "=:@" cur words cword prev

#		echo
#		echo cur=$cur
#		echo words="${words[@]}"
#		echo cword="${cword}"
#		echo prev="$prev"
#		echo
#		echo COMP_WORDS="${COMP_WORDS[@]}"
#		echo COMP_CWORD="$COMP_CWORD"
#		echo

		# find the second argument (the git subcommand)
		__arg_index -C= -c= --exec-path= --git-dir= --work-tree= --namespace=

		[[ ${posargs[1]} == "clone" ]] && _git_clone && return
		[[ ${posargs[1]} == "get" ]] && _git_get && return
	}

	# Enable completion for git
	complete -o bashdefault -o default -o nospace -F _git git 2>/dev/null || complete -o default -o nospace -F _git git
fi

# Enable completion for `git-get` when not called as a git subcommand
complete -o bashdefault -o default -o nospace -F _git_get git-get 2>/dev/null \
	|| complete -o default -o nospace -F _git_get git-get


#########################################
#                                       #
# _git_clone enhancements / overrides   #
#                                       #
#########################################

# redefine _git_clone to auto-complete the first positional argument
_git_clone()
{
	# try standard completions, return if successful
	_mj_git_clone_orig
	[[ ${#COMPREPLY[@]} -gt 0 ]] && return

	# ensure a sane decomposition of the command line,
	# we have to do this again here as Ubuntu puts @ into $COMP_WORDBREAKS (sigh...)
	local cur words cword prev
	_mj_get_comp_words_by_ref -n "=:@" cur words cword prev

	# see if we're completing the second positional argument ('git clone <URL>')
	__arg_index $(git clone --git-completion-helper 2>/dev/null)
	[[ $argidx -ne 2 ]] && return

	# Try to complete service URLs
	local __PREFIXES=()
	local service
	for service in ${__SERVICES[@]}; do
		_complete_url $service "$cur" && return
	done

	# Try SSH autocomplete
	_complete_ssh_url "$cur" && return

	# Begin autocompleting towards a fully qualified http[s]://github.com/org/repo and git@github.com:org/repo forms
	COMPREPLY=($(compgen -W "$__PREFIXES" "$cur"))
	_colon_autocomplete
}

# git's autocompletion scripts will automatically invoke _git_get() for 'get' subcommand
_git_get()
{
	# ensure a sane decomposition of the command line,
	local cur words cword prev
	_mj_get_comp_words_by_ref -n "=:@" cur words cword prev

	# see if we're completing the apropriate positional argument
	__arg_index $(git clone --git-completion-helper 2>/dev/null)

	local prog=$(basename ${words[0]})

	# 'git-get <URL>'
	[[ $prog == "git-get" && $argidx -eq 1 ]] && { _complete_url github "$cur" ""; return; }

	# 'git get <URL>'
	[[ $prog != "git-get" && $argidx -eq 2 ]] && { _complete_url github "$cur" ""; return; }
}

###############
#             #
# Unit tests  #
#             #
###############

_git_get_unit_test()
{
	for cmd in "git-get" "git get"; do
		for opts in "" "-s --long"; do
			# test succesful completions
			COMPREPLY_TRUE=( "mjuric/lsd" "mjuric/lsd-setup" " ")
			for url in "mjuric/lsd" "git@github.com:mjuric/lsd" "https://github.com/mjuric/lsd" "http://github.com/mjuric/lsd"; do
				COMPREPLY=()
				COMP_WORDS=($cmd $opts $url)
				COMP_CWORD=$(( ${#COMP_WORDS[@]} - 1)) _git_get
				# compare the output vs expectation
				diff=$(diff <(printf "%s\n" "${COMPREPLY_TRUE[@]}") <(printf "%s\n" "${COMPREPLY[@]}"))
				[[ -n "$diff" ]] && { echo "[🛑] error: ${COMP_WORDS[@]} returned wrong completions" $'\n' "$diff"; return; }
				echo "[✔] ${COMP_WORDS[@]}"
			done

			# test completions that should fail
			for url in "./mjuric/lsd" "a/b/c" "git@github.com"; do
				COMPREPLY=()
				COMP_WORDS=($cmd $opts $url)
				COMP_CWORD=$(( ${#COMP_WORDS[@]} - 1)) _git_get
				[[ ${#COMPREPLY[@]} == 0 ]] || { echo "[🛑] error: ${COMP_WORDS[@]} should've returned zero completions"; printf "%s\n" "${COMPREPLY[@]}"; return; }
				echo "[✔] ${COMP_WORDS[@]}"
			done
		done
	done
}

_arg_index_unit_test()
{
	COMP_WORDS=(git clone --test foo)
	COMP_CWORD=$(( ${#COMP_WORDS[@]} - 1))
	__arg_index "--foo= --bar= --baz="; [[ $argidx == 2 ]] || { echo "test failed at line $LINENO"; return; }
	__arg_index --test=;                [[ -z $argidx ]]   || { echo "test failed at line $LINENO"; return; }

	COMP_WORDS=(git clone --test foo -k)
	COMP_CWORD=$(( ${#COMP_WORDS[@]} - 1))
	__arg_index --foo= --bar= --baz=;   [[ -z $argidx ]]   || { echo "test failed at line $LINENO"; return; }

	COMP_WORDS=(git clone --test foo -k bar)
	COMP_CWORD=$(( ${#COMP_WORDS[@]} - 1))
	__arg_index --test=;                [[ $argidx == 2 ]] || { echo "test failed at line $LINENO"; return; }
	
	echo "[✔] __arg_index unit tests succeeded."
}

