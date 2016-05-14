#!/bin/bash

set -e

start_dir="$PWD"

ref_output_dir="$PWD/doc"
ref_output_file=nim-ref-$nim_version

# setup for travis
if [[ ! -z ${TRAVIS+x} ]]
then
    travis_build_home=${travis_build_home:-"/home/travis/build/Lompik/nim-doc"}
    pcre_lib_path=${nre_lib_path:-"$travis_build_home/pcre/lib"}
    nim_bin_path=${nim_bin_path:-"$travis_build_home/nim-$nim_version/bin"}
    nim_lib_path=${nim_lib_path:-"$travis_build_home/nim-$nim_version/lib"}
    echo "path:\""$(readlink -f "$nim_lib_path/..")"\"" >> nim.cfg
    echo "path:\"$nim_lib_path/packages/docutils\"" >> nim.cfg
    cat nim.cfg # debug
fi

if ! type nim &> /dev/null  # outside of travis, allow customization
then
    export PATH=$PATH:"$nim_bin_path"
fi

if ! type makeinfo &> /dev/null  # outside of travis, allow customization
then
    echo "Error: makeinfo [package texinfo] required"
    exit 1
fi


if [[ -z ${nim_version+x} ]]
then # try to some nim config
    nim_version=$(grep 'Version [0-9\.]*' <(nim --version 2>&1) | grep -o '[0-9]*\.[0-9]*\.[0-9]*')
fi

if [[ -z ${nim_lib_path+x} ]]
then
    nim_lib_path=$(grep 'lib$' <(nim dump 2>&1))
fi


echo "building json -> texi converter"
nim c nim_texi.nim

# Fix ast parse error in version 0.13.0
if [[ "$nim_version" == "0.13.0" ]]
then
    sed -i 's/EntryArr\.}/EntryArr].}/' $nim_lib_path/pure/collections/LockFreeHash.nim
    sed -i "s/range[0..4611686018427387903]/range[0'i64..4611686018427387903'i64]/" $nim_lib_path/pure/collections/LockFreeHash.nim
fi

if [[ -e "$ref_output_dir/$ref_output_file.info.gz" ]]
then
    rm "$ref_output_dir/$ref_output_file"*
elif [[ ! -d "$ref_output_dir" ]]
then
    mkdir "$ref_output_dir" ;
fi

echo "Building the texi/info docs"

cd "$ref_output_dir"
if [[ ! -z ${TRAVIS+x} ]]
then ## cant compile with dynoverride yet https://github.com/nim-lang/Nim/issues/3646
    LD_LIBRARY_PATH=$pcre_lib_path "$start_dir"/nim_texi $nim_lib_path > $ref_output_file.texi
else
    "$start_dir"/nim_texi $nim_lib_path > $ref_output_file.texi
fi
makeinfo --no-split $ref_output_file.texi &> /dev/null
gzip $ref_output_file.info
cd "$start_dir"

echo $(ls -al "$ref_output_dir/$ref_output_file.info.gz")
echo DONE.
