#! /bin/bash
#
# This script automaitcally disable all terracotta caches

PRG="$0"
while [ -h "$PRG" ]; do
    ls=`ls -ld "$PRG"`
    link=`expr "$ls" : '.*-> \(.*\)$'`
    if expr "$link" : '/.*' > /dev/null; then
    PRG="$link"
    else
    PRG=`dirname "$PRG"`/"$link"
    fi
done
PRGDIR=`dirname "$PRG"`
BASEDIR=`cd "$PRGDIR" > /dev/null; pwd`

$BASEDIR/tmcRestClient.sh -o enable -a all -m all -c all "$@"
