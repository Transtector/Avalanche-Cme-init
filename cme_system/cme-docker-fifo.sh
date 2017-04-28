#!/bin/bash

IN=/tmp/cmehostinput
OUT=/tmp/cmehostoutput

function cleanup {
	rm -f $IN
	rm -f $OUT
}
trap cleanup EXIT

if [[ ! -p $IN ]]; then
	mkfifo $IN
fi

if [[ ! -p $OUT ]]; then
	mkfifo $OUT
fi

cleanup

while true
do
	if read line <$IN; then
		args=(${line})

		case ${args[0]} in

			quit) break ;;

			date|shutdown|reboot|systemctl|ntpq) ${args[@]} | tee $OUT ;;

			*) printf "unknown: %s" "${args[0]}" | tee $OUT ;;
		esac
	fi
done

