#!/bin/bash

set -e

start_dir="$PWD"

ref_output_dir="$PWD/doc"
ref_output_file=nim-ref-$nim_version

makeinfo=makeinfo


if [ ! type nim &> /dev/null ]
then
    export PATH=$PATH:"$nim_bin_path"
fi

if [[ -z ${nim_version+x} ]]
then # try to some nim config
    nim_version=$(grep 'Version [0-9\.]*' <(nim --version 2>&1) | grep -o '[0-9]*\.[0-9]*\.[0-9]*')
fi

if [[ -z ${nim_lib_path+x} ]]
then
    nim_lib_path=$(grep 'lib$' <(nim dump 2>&1))
fi



if [[ ! -z ${TRAVIS+x} ]]
then
    makeinfo=$texinfo_bin_path/texi2any # old makeinfos output errors
    echo 'path:"/home/travis/nre/src"' > nim.cfg # workaround for -p with abs path
fi

ulimit -n 3000

echo "building json -> texi converter"
nim c nim_texi.nim

set +e
echo "Extracting json doc from .nim's"
for file in $(find $nim_lib_path -iname '*.nim')
do
    nim jsondoc $file &> /dev/null
done
set -e

if [[ -e "$ref_output_dir/$ref_output_file.info" ]]
then
    rm "$ref_output_dir/$ref_output_file*"
elif [[ ! -d "$ref_output_dir" ]]
then
    mkdir "$ref_output_dir" ;
fi

echo "Building the texi/info docs"

cd "$ref_output_dir"
"$start_dir"/nim_texi $nim_lib_path > $ref_output_file.texi
$makeinfo --no-split $ref_output_file.texi
gzip $ref_output_file.info
cd "$start_dir"

echo DONE.
