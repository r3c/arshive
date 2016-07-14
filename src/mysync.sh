#!/bin/sh -e

basedir="$(dirname $(readlink -m "$0"))"

# Command line options
opt_config="$basedir"/mysync.conf
opt_dryrun=
opt_quiet=

while getopts :c:dhq opt; do
	case "$opt" in
		c)
			opt_config="$(readlink -m "$OPTARG")"
			;;

		d)
			opt_dryrun=1
			;;

		h)
			echo >&2 "$(basename $0) [-c <path>] [-h] [-q]"
			echo >&2 '  -c <path>: use specified configuration file'
			echo >&2 '  -d: dry run, execute commands but do not write or delete backups'
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

# Fail if unknown command line arguments are found
shift "$((OPTIND - 1))"

if [ $# -gt 0 ]; then
	echo >&2 "error: unrecognized command line arguments: '$@'"
	exit 1
fi

# Read configuration file and verify settings
if [ ! -r "$opt_config" ]; then
	echo >&2 "error: missing or unreadable configuration file: '$opt_config'"
	exit 1
fi

. "$opt_config"

filemode="${filemode:-0644}"
logerr="$(cd "$basedir" && readlink -m "${logerr:-/tmp/mysync.log.err}")"
logout="$(cd "$basedir" && readlink -m "${logout:-/tmp/mysync.log.out}")"
placeholder='{}'
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
	# Convert source path to absolute and check existence
	source="$(cd "$basedir" && readlink -m "$source")"

	if [ ! -r "$source" ]; then
		echo >&2 "error: missing or unreadable rule file '$source'"
		continue
	fi

	# Scan rules defined in current rule file
	sed -r '/^(#|$)/d;s/[[:blank:]]+/ /g' "$source" |
	while IFS=' ' read name time keep command; do
		if ! echo "$name" | grep -Eq '^[-0-9A-Za-z_.]+$'; then
			echo >&2 "error: invalid name '$name' in file '$source'"
			continue
		elif ! echo "$time" | grep -Eq '^[0-9]+$'; then
			echo >&2 "error: time is not an integer for rule '$name' in file '$source'"
			continue
		elif ! echo "$keep" | grep -Eq '^[0-9]+$'; then
			echo >&2 "error: keep is not an integer for rule '$name' in file '$source'"
			continue
		elif ! echo "$command" | grep -Eq "$placeholder"; then
			echo >&2 "error: missing '$placeholder' placeholder for rule '$name' in file '$source'"
			continue
		elif [ "$keep" -lt "$time" ]; then
			echo >&2 "warning: keep duration lower than backup interval for rule '$name' in file '$source'"
		else
			# Scan existing backups in target path
			newest=-1
			now="$(date '+%s')"

			for file in "$target/$name."*; do
				this="${file#$target/$name.}"

				if echo "$this" | grep -Eq '^[0-9]+$'; then
					diff="$((now - this))"

					if [ "$keep" -lt "$diff" ]; then
						if [ -z "$opt_dryrun" ]; then
							rm -f "$file"
						fi
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
			if [ -n "$opt_dryrun" ]; then
				file=/dev/null
			else
				file="$target/$name.$now"
				rm -f "$file"
			fi

			# Execute backup command
			if ! sh -c "$(echo "$command" | sed "s:$placeholder:$file:")" < /dev/null 1> "$stdout" 2> "$stderr"; then
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

			if [ -n "$opt_dryrun" ]; then
				echo "$name: should be saved"
			elif ! [ -r "$file" ]; then
				echo >&2 "warning: $name: command didn't create backup file"
			elif ! chmod "$filemode" "$file"; then
				echo >&2 "warning: $name: couldn't change backup file mode"
			elif [ -z "$opt_quiet" ]; then
				echo "$name: saved as '$file'"
			fi
		fi
	done
done

# Cleanup temporary files
rm -f "$stderr" "$stdout"
