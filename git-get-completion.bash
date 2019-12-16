#!/bin/bash
#
# git-get autocompletion script
#
# This script can be used as standalone, or can complement the one that ships with git.
#

# configuration
GG_CFGDIR=${XDG_CONFIG_HOME:-$HOME/.config/git-get}
GG_AUTHFILE="$GG_CFGDIR/github.auth.netrc"

git-get-login()
{
	# acquire credentials
	echo "Logging into github so we can list repositories..."
	echo "Please visit https://github.com/settings/tokens/new and generate a new personal access token:"
	echo "  1. Under 'Note', write 'git-get access for $USER@$(hostname)'"
	echo "  2. Under 'Select scopes', check 'repo:status' and leave otherwise unchecked."
	echo "Then click the 'Generate Token' green button (bottom of the page)."
	echo
	echo "The PAT is equivalent to a password git-get can use to securely access your github account."
	echo "Copy the newly generated token and paste it here."
	echo ""
	read -sp "Token (note: the typed characters won't show): " TOKEN; echo
	read -p "Your GitHub username: " GHUSER

	# securely store the token and user to a netrc-formatted file
	mkdir -p "$(dirname $GG_AUTHFILE)"
	rm -f "$GG_AUTHFILE"
	touch "$GG_AUTHFILE"
	chmod 600 "$GG_AUTHFILE"
	# note: echo is a builtin so this is secure (https://stackoverflow.com/a/15229498)
	echo "machine api.github.com login $GHUSER password $TOKEN" >> "$GG_AUTHFILE"

	# verify that the token works
	if ! curl -I -f -s --netrc-file "$GG_AUTHFILE" "https://api.github.com/user" >/dev/null; then
		curl -s "https://api.github.com/user"
		echo "Hmm, something went wrong -- most likely you've typed the token incorretly. Rerun and try again."
		exit -1
	else
		echo
		echo "Authentication setup complete; token stored to '$GG_AUTHFILE'"
	fi
}


# _refresh_repo_cache <org> <dest_cache_fn>
_refresh_repo_cache()
{
	local ORG="$1"
	local CACHE="$2"

	if [[ -n $(find "$CACHE" -newermt '-15 seconds' 2>/dev/null) ]]; then
		return
	fi
	touch "$CACHE"

	# extract the number of pages
	PAGES=$(curl -I -f -s --netrc-file "$GG_AUTHFILE" "https://api.github.com/users/$ORG/repos?page=1&per_page=1000" | 
		sed -En 's/^Link: (.*)/\1/p' |tr ',' '\n' | grep 'rel="last"' |
		sed -nE 's/^.*[?&]page=([0-9]+).*/\1/p')

	# fetch all pages to tmpfile and atomically replace the current cache (if any)
	mkdir -p $(dirname "$CACHE")
	local TMP="$CACHE.$$.$RANDOM.tmp"
	for page in $(seq 1 $PAGES); do
		curl -f -s --netrc-file "$GG_AUTHFILE" "https://api.github.com/users/$ORG/repos?page=$page&per_page=1000" >> "$TMP"
	done

	# extract repository names and store into the cache
	jq -r '.[].name' "$TMP" > "$CACHE"
	rm -f "$TMP"

	#echo "update to $CACHE done."
}

# get list of repositories from organization $1
# cache the list in .repos.cache.$1
_get_repo_list()
{
	local CACHEDIR=${XDG_CACHE_HOME:-$HOME/.cache/git-get}
	local CACHE="$CACHEDIR/repos.cache.$1"

	if [[ ! -f "$CACHE" ]]; then
		# this is the first time we're asking for the list of repos
		# in this organization; do it synchronously
		_refresh_repo_cache $1 $CACHE
	else
		# return what we have and fire off a background update
		( _refresh_repo_cache $1 $CACHE & )
	fi

	# return the list of repos
	REPOS=( $( cat "$CACHE" 2>/dev/null ) )
}

_git_get_unit_test()
{
	for cmd in "git-get" "git get"; do
		for opts in "" "-s --long"; do
			# test succesful completions
			COMPREPLY_TRUE=( "mjuric/lsd " "mjuric/lsd-setup " )
			for url in "mjuric/lsd" "git@github.com:mjuric/lsd" "https://github.com/mjuric/lsd" "http://github.com/mjuric/lsd"; do
				COMP_WORDS=($cmd $opts $url)
				COMP_CWORD=$(( ${#COMP_WORDS[@]} - 1)) _git_get
				# compare the output vs expectation
				diff=$(diff <(printf "%s\n" "${COMPREPLY_TRUE[@]}") <(printf "%s\n" "${COMPREPLY[@]}"))
				[[ -n "$diff" ]] && { echo "[🛑] error: ${COMP_WORDS[@]} returned wrong completions" $'\n' "$diff"; return; }
				echo "[✔] ${COMP_WORDS[@]}"
			done

			# test completions that should fail
			for url in "./mjuric/lsd" "a/b/c" "git@github.com"; do
				COMP_WORDS=($cmd $opts $url)
				COMP_CWORD=$(( ${#COMP_WORDS[@]} - 1)) _git_get
				[[ ${#COMPREPLY[@]} == 0 ]] || { echo "[🛑] error: ${COMP_WORDS[@]} should've returned zero completions"; printf "%s\n" "${COMPREPLY[@]}"; return; }
				echo "[✔] ${COMP_WORDS[@]}"
			done
		done
	done
}

# git's autocompletion scripts will automatically invoke _git_get() for 'get' subcommand
_git_get()
{
	# are we invoked as standalone, or git subcommand?
	IARG=1
	[[ ${COMP_WORDS[0]} == "git" ]] && IARG=2

	COMPREPLY=()

	local PROJECTS="${PROJECTS:-$HOME/projects}"
	PROJECTS="$PROJECTS/github.com"

	# skip all command-line option, and make sure we're parsing the
	# repository-to-clone argument
	at=0
	for i in $(seq 1 $COMP_CWORD); do
		word=${COMP_WORDS[i]}
		[[ $word == -* ]] && continue
		at=$((at+1))
		# if IARG == 2, we're being invoked as 'git get'. If so, make sure
		# the second word truly is 'get', stop otherwise
		[[ $IARG == 2 && $at == 1 && $word != "get" ]] && return
	done
	if [[ $at != $IARG ]]; then
		return
	fi
	URL="${COMP_WORDS[COMP_CWORD]}"

	# Allow fully qualified http[s]://github.com/org/repo and git@github.com:org/repo forms
	if [[ $URL == "https://github.com/"* || $URL == "http://github.com/"* ]]; then
		URL=$(cut -d / -f 4- <<< "$URL")
	elif [[ $URL == "git@github.com:"* ]]; then
		IFS=':' read -ra A <<< "$URL"
		URL="${A[1]}"
	fi

	# more than one '/' character. this is malformed, so stop
	[[ $URL == */*/* ]] && return

	# see if we're completing the org, or the repo part
	if [[ $URL != */* ]]; then
		# completing the org: show a list of already cloned orgs
		WORDS=( $(ls $PROJECTS) )
		WORDS=( "${WORDS[@]/%//}" )
	else
		# completing the repo: offer a list of repos available on github
		IFS='/' read -ra arr <<< "$URL"
		ORG=${arr[0]}
		REPO=${arr[1]}

		if [[ -f "$GG_AUTHFILE" ]]; then
			_get_repo_list "$ORG"
			WORDS=( "${REPOS[@]/#/$ORG/}" )		# prepend the org name
			WORDS=( "${WORDS[@]/%/ }" )		# append a space (so the suggestion completes the argument)
		else
			# short-circuit if we haven't authenticated, with
			# a helpful message
			COMPREPLY=("Error: run \`git-get-login\` to activate repository completion." "completion currently disabled.")
			return
		fi
	fi

	# only return completions matching the typed prefix
	for i in "${!WORDS[@]}"; do
		if [[ ${WORDS[i]} == "$URL"* ]]; then
			COMPREPLY+=("${WORDS[i]}")
		fi
	done
}

#
# Install completions
#

if [[ ! -f "$GG_AUTHFILE" ]]; then
	echo "warning: *** git-get completion disabled because you need to log in first ***"
	echo "warning: *** run 'git-gen-login' for a quick one-time setip               ***"
fi

# If there's no git completion, at least install completion for our subcommand
if ! declare -F _git > /dev/null; then
	echo "warning: no git bash autocompletion found; installing standalone one for git-get" 1>&2
	complete -o bashdefault -o default -o nospace -F _git_get git 2>/dev/null \
		|| complete -o default -o nospace -F _git_get git
fi

# Enable completion for git-get even when not called as a git subcommand
complete -o bashdefault -o default -o nospace -F _git_get git-get 2>/dev/null \
	|| complete -o default -o nospace -F _git_get git-get
