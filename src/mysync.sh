#!/bin/sh -e

basedir="$(dirname $(readlink -m "$0"))"

# Global options
opt_config="$basedir"/mysync.conf
opt_dryrun=
opt_log=1

log()
{
	if [ "$opt_log" -le "$1" ]; then
		case "$1" in
			2)
				echo >&2 "warning: $2"
				;;

			3)
				echo >&2 "error: $2"
				;;

			*)
				echo "$2"
				;;
		esac
	fi
}

# Command line options
while getopts :c:dhqv opt; do
	case "$opt" in
		c)
			opt_config="$(readlink -m "$OPTARG")"
			;;

		d)
			opt_dryrun=1
			;;

		h)
			echo >&2 "$(basename $0) [-c <path>] [-d] [-h] [-q] [-v]"
			echo >&2 '  -c <path>: use specified configuration file'
			echo >&2 '  -d: dry run, execute commands but do not write or delete backups'
			echo >&2 '  -h: display help and exit'
			echo >&2 '  -q: quiet mode'
			echo >&2 '  -v: verbose mode'
			exit
			;;

		q)
			opt_log=2
			;;

		v)
			opt_log=0
			;;

		:)
			log 3 "missing argument for option '-$OPTARG'"
			exit 1
			;;

		*)
			log 3 "unknown option '-$OPTARG'"
			exit 1
			;;
	esac
done

# Fail if unknown command line arguments are found
shift "$((OPTIND - 1))"

if [ $# -gt 0 ]; then
	log 3 "unrecognized command line arguments: '$@'"
	exit 1
fi

# Read configuration file and verify settings
if [ ! -r "$opt_config" ]; then
	log 3 "missing or unreadable configuration file: '$opt_config'"
	exit 1
fi

. "$opt_config"

filemode="${filemode:-0644}"
logerr="$(cd "$basedir" && readlink -m "${logerr:-/tmp/mysync.log.err}")"
logout="$(cd "$basedir" && readlink -m "${logout:-/tmp/mysync.log.out}")"
placeholder='\{([^{}]*)\}'
target="$(cd "$basedir" && readlink -m "${target:-/tmp}")"

if ! echo "$filemode" | grep -qE '^[0-7]{3,4}$'; then
	log 3 "invalid file mode '$filemode' in configuration file"
	exit 1
elif [ ! -n "$sources" ]; then
	log 3 "no source files defined in configuration file"
	exit 1
elif [ ! -d "$target" -o ! -r "$target" -o ! -w "$target" ]; then
	log 3 "missing, non-readable or non-writable target path in configuration file: '$target'"
	exit 1
fi

# Parse each rules file defined in "sources" setting
stderr="$(mktemp)"
stdout="$(mktemp)"

for source in $(cd "$basedir" && echo $sources ); do
	# Convert source path to absolute and check existence
	source="$(cd "$basedir" && readlink -m "$source")"

	if [ ! -r "$source" ]; then
		log 3 "missing or unreadable rule file '$source'"
		continue
	fi

	# Scan rules defined in current rule file
	sed -r '/^(#|$)/d;s/[[:blank:]]+/ /g' "$source" |
	while IFS=' ' read name time keep command; do
		if ! echo "$name" | grep -Eq -- '^[-0-9A-Za-z_.]+$'; then
			log 3 "invalid name '$name' in file '$source'"
		elif ! echo "$time" | grep -Eq -- '^[0-9]+$'; then
			log 3 "parameter 'time' is not an integer for rule '$name' in file '$source'"
		elif ! echo "$keep" | grep -Eq -- '^[0-9]+$'; then
			log 3 "parameter 'keep' is not an integer for rule '$name' in file '$source'"
		elif ! echo "$command" | grep -Eq -- "$placeholder"; then
			log 3 "parameter 'command' is missing placeholder for rule '$name' in file '$source'"
		else
			# Backward compatibility
			if [ "$keep" -ge 3600 ]; then
				keep="$((keep / time))"

				log 2 "parameter 'keep' was too large for rule '$name' in file '$source' and was probably a duration ; up to $keep backup files will be kept instead"
			fi

			# Browse existing backups
			create=
			now="$(date +%s)"
			suffix="$(echo "$command" | sed -nr -- "s:.*$placeholder.*:\\1:p")"

			for file in $(find -- "$target" -maxdepth 1 -type f -name "$name.*$suffix" | sort -r); do
				# Check is a new backup file is required
				if [ -z "$create" ]; then
					backup="$(echo "${file#$target/$name.}" | sed -nr -- "s:^([0-9]+)$suffix\$:\\1:p")"

					if [ -z "$backup" ]; then
						log 2 "$name: file '$file' doesn't match current rule and will be ignored"
					elif [ "$((now - backup))" -ge "$time" ]; then
						create=1
					else
						create=0
						keep="$((keep + 1))"

						log 1 "$name: up to date"
					fi
				fi

				# Delete expired backup files
				if [ "$keep" -gt 1 ]; then
					keep="$((keep - 1))"
				else
					test -n "$opt_dryrun" || rm -f -- "$file"

					log 1 "$name: old backup file '$file' deleted"
				fi
			done

			# Stop if no new backup is required
			test "${create:-1}" -ne 0 || continue

			# Prepare new backup
			if [ -z "$opt_dryrun" ]; then
				file="$target/$name.$now$suffix"
			else
				file=/dev/null
			fi

			# Execute backup command
			if ! sh -c "$(echo "$command" | sed -r "s:$placeholder:$file:")" < /dev/null 1> "$stdout" 2> "$stderr"; then
				log 2 "$name: exited with error code, see logs for details"
			fi

			if [ "$(stat -c %s "$stderr")" -ne 0 ]; then
				( echo "=== $name: $(date '+%Y-%m-%d %H:%M:%S'): stderr ===" && cat "$stderr" ) >> "$logerr"

				log 2 "$name: got data on stderr, see logs for details"
			fi

			if [ "$(stat -c %s "$stdout")" -ne 0 ]; then
				( echo "=== $name: $(date '+%Y-%m-%d %H:%M:%S'): stdout ===" && cat "$stdout" ) >> "$logout"
			fi

			if [ -n "$opt_dryrun" ]; then
				log 1 "$name: new backup required"
			elif ! [ -r "$file" ]; then
				log 2 "$name: command didn't create backup file '$file'"
			elif ! chmod -- "$filemode" "$file"; then
				log 2 "$name: couldn't change mode of backup file '$file'"
			else
				log 1 "$name: new backup file saved as '$file'"
			fi
		fi
	done
done

# Cleanup temporary files
rm -f "$stderr" "$stdout"
