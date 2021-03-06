function getabspath {
	typeset t i=0 IFS=/

	case $1 in
	/*)
		__=${1#/}
		;;
	*)
		__=${PWD#/}/$1
		;;
	esac

	case $- in
	*f*)
		set -- $__
		;;
	*)
		set -f
		set -- $__
		set +f
		;;
	esac

	for __; do
		case $__ in
		..)
			(( i )) && unset 't[--i]'
			continue
			;;
		.|'')
			continue
			;;
		esac

		t[i++]=$__
	done

	case $1 in
	*/)
		(( i )) && __="/${t[*]}/" || __=/
		;;
	*)
		(( i )) && __="/${t[*]}" || __=/.
		;;
	esac
}
