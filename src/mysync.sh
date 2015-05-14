#!/bin/sh -e

# Read configuration file and verify settings
config=`dirname "$0"`'/mysync.conf'

if [ ! -r "$config" ]; then
	echo >&2 "error: missing or unreadable configuration file: '$config'"

	exit 1
fi

. "$config"

filemode=${filemode:-644}
logerr=${logerr:-mysync.log.err}
logout=${logout:-mysync.log.out}

if ! echo "$filemode" | grep -qE '^[0-7]{3}$'; then
	echo >&2 "error: invalid file mode in configuration file"

	exit 1
elif [ ! -n "$sources" ]; then
	echo >&2 "error: no source files defined in configuration file"

	exit 1
elif [ ! -d "$target" -o ! -w "$target" ]; then
	echo >&2 "error: non-writable or missing target path in configuration file: '$target'"

	exit 1
fi

# Parse each rules file defined in "sources" setting
stderr=`mktemp`
stdout=`mktemp`

for rules in $sources; do
	if [ ! -r "$rules" ]; then
		echo >&2 "error: missing or unreadable rules files: '$rules'"

		continue
	fi

	i=0

	cat "$rules" | while read rule; do
		i=$((i + 1))

		if echo "$rule" | grep -Eq '^(#|$)'; then
			continue
		fi

		name=`echo "$rule" | sed -nr 's/^[[:blank:]]*([^[:blank:]]+).*$/\1/p'`
		rule=`echo "$rule" | sed -nr 's/^[[:blank:]]*[^[:blank:]]+(.*)$/\1/p'`
		time=`echo "$rule" | sed -nr 's/^[[:blank:]]*([^[:blank:]]+).*$/\1/p'`
		rule=`echo "$rule" | sed -nr 's/^[[:blank:]]*[^[:blank:]]+(.*)$/\1/p'`
		keep=`echo "$rule" | sed -nr 's/^[[:blank:]]*([^[:blank:]]+).*$/\1/p'`
		rule=`echo "$rule" | sed -nr 's/^[[:blank:]]*[^[:blank:]]+(.*)$/\1/p'`
		exec=`echo "$rule" | sed -nr 's/^[[:blank:]]*(.*)$/\1/p'`

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
			now=`date '+%s'`

			for file in "$target/$name."*; do
				this="${file#$target/$name.}"

				if echo "$this" | grep -Eq '^[0-9]+$'; then
					diff=$((now - this))

					if [ "$keep" -lt "$diff" ]; then
						rm -f "$file"
					elif [ "$newest" -lt 0 -o "$newest" -gt "$diff" ]; then
						newest=$diff
					fi
				fi
			done

			# Check if a backup is required
			if [ "$newest" -ge 0 -a "$newest" -le "$time" ]; then
				echo "$name: up to date"

				continue
			fi

			# Create a new backup
			file="$target/$name.$now"
			rm -f "$file"

			# Execute backup command
			command=$(echo "$exec" | sed "s:{}:$file:")
			sh -c "$command" < /dev/null 1> "$stdout" 2> "$stderr"

			code="$?"
			err=0

			if [ "$(stat -c %s "$stderr")" -ne 0 ]; then
				echo "=== $name: "`date '+%Y-%m-%d %H:%M:%S'`": stderr ===" >> "$logerr"
				cat "$stderr" >> "$logerr"

				err=1
			fi

			if [ "$(stat -c %s "$stdout")" -ne 0 ]; then
				echo "=== $name: "`date '+%Y-%m-%d %H:%M:%S'`": stdout ===" >> "$logout"
				cat "$stdout" >> "$logout"
			fi

			if [ "$code" -ne 0 ]; then
				echo >&2 "error: $name: exit code $code, see logs for details"
			elif [ "$err" -ne 0 ]; then
				echo >&2 "error: $name: got data on stderr, see logs for details"
			fi

			if ! [ -r "$file" ]; then
				echo >&2 "error: $name: command didn't create expected backup archive"
			elif ! chmod "$filemode" "$file"; then
				echo >&2 "error: $name: couldn't change file mode on archive"
			else
				echo "$name: saved as '$file'"
			fi
		fi
	done
done

# Cleanup temporary files
rm -f "$stderr"
rm -f "$stdout"
