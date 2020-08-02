#!/bin/sh

# used this shit to find out Clickhouse-deps trash
# to generate GH_TAG for FreeBSD CH port
# ( which is not interesting to the vendor )
# notes: SQLite3 deps
#
# git clone https://github.com/ClickHouse/ClickHouse.git
# cd ClickHouse
# git submodule update --init --recursive 2>&1 > output.txt
# cp output.txt into current dir
# ./submodule.sh > out.txt
# cat out.txt

sqllist()
{
	local _i _str IFS _key _T

	_str="$1"
	if [ -n "${sqllistdelimer}" ]; then
		IFS="${sqllistdelimer}"
	else
		IFS="|"
	fi
	_i=2

	for _key in ${_str}; do
		eval _T="\${${_i}}"
		_i=$((_i + 1))
		export ${_T}="${_key}"
	done
}

rm -f base.sqlite
sqlite3 base.sqlite < sqlite.schema
sqllistdelimer=" "
submod=0

# first loop: get all submodules and path
grep "^Submodule '" output.txt | egrep '(||)'| grep "registered for path" | tr -d "'()" | while read _line; do
	# sample line
	# Submodule 'thirdparty/gtest' (https://github.com/google/googletest.git) registered for path 'contrib/simdjson/dependencies/rapidjson/thirdparty/gtest'
	sqllist "${_line}" nop name url nop nop nop path
	str="INSERT INTO modulelist ( name,url,path ) VALUES ( \"${name}\",\"${url}\",\"${path}\" )"
	sqlite3 base.sqlite "${str}"
	ret=$?
	if [ ${ret} -ne 0 ]; then
		echo "Failed: ${str}"  1>&2
	fi
done

unset sqllistdelimer

submod_count=$( sqlite3 base.sqlite "SELECT COUNT(name) FROM modulelist" )
echo "Submodules: ${submod_count}"  1>&2

# second loop: get revision for submodules
all_name=$( sqlite3 base.sqlite "SELECT name,url,path FROM modulelist" )

a=0
b=0
c=0
next=0
cur=0
cp -a output.txt tmp.output.0.txt
tmpfile_new="tmp.output.${c}.txt"

for pair in  ${all_name}; do
	tmpfile_old="tmp.output.${c}.txt"
	c=$(( c + 1 ))
	tmpfile_new="tmp.output.${c}.txt"
	truncate -s0 ${tmpfile_new}

	sqllist ${pair} name url path

	find_str_start="Submodule '${name}' (${url}) registered for path '${path}'"
	#find_str_end="Submodule path '${name}': checked out"
	find_str_end="Submodule path '${path}': checked out"

	cur=$(( cur + 1 ))

	echo "Find: ${cur}/${submod_count}: ${tmpfile_old} ( $find_str_end )"  1>&2

	next=0
	a=0
	b=0

	cat ${tmpfile_old} | while read _line; do

		if [ ${next} -eq 0 ]; then
			if [ "${_line}" = "${find_str_start}" ]; then
				echo "OK a"  1>&2
				a=1
				continue
			fi

			if [ ${a} -eq 1 ]; then
				echo "${_line}" | egrep -q "${find_str_end}"  1>&2
				if [ $? -eq 0 ]; then
					# sample:
					# Submodule path 'contrib/aws': checked out '45dd8552d3c492defca79d2720bcc809e35654da'"
					sqllistdelimer=" "
					sqllist "${_line}" nop nop nop nop nop rev
					unset sqllistdelimer
					rev=$( echo $rev | tr -d "'" | cut -c -7 )
					vendor=$( echo "${url}" | tr "/" " " |awk '{printf $3}' )
					project=$( echo "${url}" | tr "/" " " |sed 's:.git::g' |awk '{printf $4}' )
					sqlite3 base.sqlite "UPDATE modulelist SET vendor=\"${vendor}\",project=\"${project}\",rev=\"${rev}\" WHERE name=\"${name}\" AND path=\"${path}\""
					next=1
					echo "OK b" 1>&2
					continue
				fi
			fi
		fi

		echo "${_line}" >> ${tmpfile_new}
	done
done

# debug
rm -f tmp.output.*.txt

# final ouput
# third loop: concat all
all_stuff=$( sqlite3 base.sqlite "SELECT vendor,project,name,url,path,rev FROM modulelist" )
# sample output:
# google:flatbuffers:bf9eb67:google_flatbuffers/contrib/flatbuffers \
# ClickHouse-Extras:grpc:c1d1765:ClickHouse_Extras_grpc/contrib/grpc \

echo "GH_TUPLE=		\\"

for pair in  ${all_stuff}; do
	sqllist "${pair}" vendor project name url path rev
	venproj=$( echo "${vendor}_${project}" | tr "-" "_" )
	echo "		${vendor}:${project}:${rev}:${venproj}/${path}	\\"
done
