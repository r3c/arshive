#!/bin/sh -e

basedir="$(dirname $(readlink -m "$0"))"

# Command line options
opt_config="$basedir"/mysync.conf
opt_quiet=

while getopts :c:hq opt; do
	case "$opt" in
		c)
			opt_config="$(readlink -m "$OPTARG")"
			;;

		h)
			echo >&2 "$(basename $0) [-c <path>] [-h] [-q]"
			echo >&2 '  -c <path>: use specified configuration file'
			echo >&2 '  -h: display help and exit'
			echo >&2 '  -q: quiet mode'
			exit
			;;

		q)
			opt_quiet=1
			;;

		:)
			echo >&2 "missing argument for option -$OPTARG"
			exit 1
			;;

		*)
			echo >&2 "unknown option -$OPTARG"
			exit 1
			;;
	esac
done

shift "$((OPTIND - 1))"

# Read configuration file and verify settings
if [ ! -r "$opt_config" ]; then
	echo >&2 "error: missing or unreadable configuration file: '$opt_config'"
	exit 1
fi

. "$opt_config"

filemode="${filemode:-0644}"
logerr="$(cd "$basedir" && readlink -m "${logerr:-/tmp/mysync.log.err}")"
logout="$(cd "$basedir" && readlink -m "${logout:-/tmp/mysync.log.out}")"
target="$(cd "$basedir" && readlink -m "$target")"

if ! echo "$filemode" | grep -qE '^[0-7]{3,4}$'; then
	echo >&2 "error: invalid file mode '$filemode' in configuration file"
	exit 1
elif [ ! -n "$sources" ]; then
	echo >&2 "error: no source files defined in configuration file"
	exit 1
elif [ ! -d "$target" -o ! -w "$target" ]; then
	echo >&2 "error: non-writable or missing target path in configuration file: '$target'"
	exit 1
fi

# Parse each rules file defined in "sources" setting
stderr="$(mktemp)"
stdout="$(mktemp)"

for source in $(cd "$basedir" && echo $sources ); do
	if [ ! -r "$source" ]; then
		echo >&2 "error: missing or unreadable rule file: '$source'"
		continue
	fi

	i=0

	cat "$source" | while read rule; do
		i=$((i + 1))

		if echo "$rule" | grep -Eq '^(#|$)'; then
			continue
		fi

		name="$(echo "$rule" | sed -nr 's/^[[:blank:]]*([^[:blank:]]+).*$/\1/p')"
		rule="$(echo "$rule" | sed -nr 's/^[[:blank:]]*[^[:blank:]]+(.*)$/\1/p')"
		time="$(echo "$rule" | sed -nr 's/^[[:blank:]]*([^[:blank:]]+).*$/\1/p')"
		rule="$(echo "$rule" | sed -nr 's/^[[:blank:]]*[^[:blank:]]+(.*)$/\1/p')"
		keep="$(echo "$rule" | sed -nr 's/^[[:blank:]]*([^[:blank:]]+).*$/\1/p')"
		rule="$(echo "$rule" | sed -nr 's/^[[:blank:]]*[^[:blank:]]+(.*)$/\1/p')"
		exec="$(echo "$rule" | sed -nr 's/^[[:blank:]]*(.*)$/\1/p')"

		if ! echo "$name" | grep -Eq '^[-0-9A-Za-z_.]+$'; then
			echo >&2 "error: invalid or undefined name at line $i ($name)"
			continue
		elif ! echo "$time" | grep -Eq '^[0-9]+$'; then
			echo >&2 "error: time is not an integer at line $i ($time)"
			continue
		elif ! echo "$keep" | grep -Eq '^[0-9]+$'; then
			echo >&2 "error: keep is not an integer at line $i ($time)"
			continue
		elif ! echo "$exec" | grep -Eq '{}'; then
			echo >&2 "error: missing '{}' placeholder at line $i ($exec)"
			continue
		elif [ "$keep" -lt "$time" ]; then
			echo >&2 "error: keep time lower than exec time at line $i"
			continue
		else
			# Scan existing backups in target path
			newest=-1
			now="$(date '+%s')"

			for file in "$target/$name."*; do
				this="${file#$target/$name.}"

				if echo "$this" | grep -Eq '^[0-9]+$'; then
					diff="$((now - this))"

					if [ "$keep" -lt "$diff" ]; then
						rm -f "$file"
					elif [ "$newest" -lt 0 -o "$newest" -gt "$diff" ]; then
						newest="$diff"
					fi
				fi
			done

			# Check if a backup is required
			if [ "$newest" -ge 0 -a "$newest" -le "$time" ]; then
				if [ -z "$opt_quiet" ]; then
					echo "$name: up to date"
				fi

				continue
			fi

			# Create a new backup
			file="$target/$name.$now"
			rm -f "$file"

			# Execute backup command
			command="$(echo "$exec" | sed "s:{}:$file:")"

			if ! sh -c "$command" < /dev/null 1> "$stdout" 2> "$stderr"; then
				echo >&2 "error: $name: exit with error code, see logs for details"
			fi

			if [ "$(stat -c %s "$stderr")" -ne 0 ]; then
				echo "=== $name: $(date '+%Y-%m-%d %H:%M:%S'): stderr ===" >> "$logerr"
				cat "$stderr" >> "$logerr"

				echo >&2 "error: $name: got data on stderr, see logs for details"
			fi

			if [ "$(stat -c %s "$stdout")" -ne 0 ]; then
				echo "=== $name: $(date '+%Y-%m-%d %H:%M:%S'): stdout ===" >> "$logout"
				cat "$stdout" >> "$logout"
			fi

			if ! [ -r "$file" ]; then
				echo >&2 "error: $name: command didn't create expected backup archive"
			elif ! chmod "$filemode" "$file"; then
				echo >&2 "error: $name: couldn't change file mode on archive"
			elif [ -z "$opt_quiet" ]; then
				echo "$name: saved as '$file'"
			fi
		fi
	done
done

# Cleanup temporary files
rm -f "$stderr" "$stdout"
