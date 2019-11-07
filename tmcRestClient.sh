#!/bin/bash

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

TMC_URL="http://localhost:9889/tmc"
#for ease of use and deployment, let's try to parse a "TMC_URL" file with the right TMC url
if [ -f "$BASEDIR/TMC_URL" ] ; then
    TMC_URL=`cat $BASEDIR/TMC_URL`
fi

DEBUG="false"
JQ="$BASEDIR/jq"
TMC_LOGIN_PATH="/login.jsp"
TMC_LOGOUT_PATH="/logout"
TMC_API_BASE="/api"
TMC_AGENT_INFO="$TMC_API_BASE/agents/info"

HTTP_JSON_HEADERS="Content-Type: application/json; charset=utf-8"
CURL_OPTIONS="-s" #-s
COOKIE_PATH="$HOME/.tmcrestclientcookie"

NULLVALUE="null"
ALLVALUE="all"

function login()
{
    URL=$TMC_URL$TMC_LOGIN_PATH
    POSTPARAMS="username=$1&password=$2"
    HTTP_HEADERS="Accept: text/html,application/xml; Content-Type:application/x-www-form-urlencoded; charset=utf-8"
    OUTPUT=$(curl $CURL_OPTIONS -w "%{http_code}" -o /dev/null -H "$HTTP_HEADERS" -d $POSTPARAMS -c $COOKIE_PATH -X POST $URL)
    RETVAL=$?
    if [ $RETVAL -eq 0 ] && [ "$OUTPUT" == "403" ] ; then
        RETVAL=403
    fi
    return $RETVAL
}

function logout()
{
    URL=$TMC_URL$TMC_LOGOUT_PATH
    HTTP_HEADERS="Accept: text/html,application/xml;"
    OUTPUT=$(curl $CURL_OPTIONS -H "$HTTP_HEADERS" -b $COOKIE_PATH -c $COOKIE_PATH -X GET $URL)
    RETVAL=$?
    return $RETVAL
}

function retrieveAllCacheAgents()
{
    URL=$TMC_URL$TMC_AGENT_INFO
    OUTPUT=$(curl $CURL_OPTIONS -H "$HTTP_JSON_HEADERS" -b $COOKIE_PATH $URL)
    RETVAL=$?
    
    echo $OUTPUT | $JQ '.[] | select(.agencyOf == "Ehcache") | .agentId' | tr "\\n" "," | sed 's/"//g' | sed 's/,$//'; echo ''
    return $RETVAL
}

function retrieveAllCacheManagers()
{
    CACHEFILTER=$(constructCacheURL "$1")
    URL=$TMC_URL$TMC_API_BASE$CACHEFILTER
    OUTPUT=$(curl $CURL_OPTIONS -H "$HTTP_JSON_HEADERS" -b $COOKIE_PATH $URL)
    RETVAL=$?

    echo $OUTPUT | $JQ 'unique_by(.cacheManagerName)|.[].cacheManagerName' | tr "\\n" "," | sed 's/"//g' | sed 's/,$//'; echo ''
    return $RETVAL
}

function retrieveAllCacheManagerCaches()
{
    CACHEFILTER=$(constructCacheURL "$1" "$2")
    URL=$TMC_URL$TMC_API_BASE$CACHEFILTER
    OUTPUT=$(curl $CURL_OPTIONS -H "$HTTP_JSON_HEADERS" -b $COOKIE_PATH $URL)
    RETVAL=$?

    echo $OUTPUT | $JQ 'unique_by(.name)|.[].name' | tr "\\n" "," | sed 's/"//g' | sed 's/,$//'; echo ''
    return $RETVAL
}

function constructCacheURL()
{
    AGENTFILTER=$1
    CACHEMANAGERFILTER=$2
    CACHEFILTER=$3
    
    FULLFILTER="/agents"
    if [ "x$AGENTFILTER" != "x" ] && [ "x$AGENTFILTER" != "x$NULLVALUE" ] ; then
        FULLFILTER="$FULLFILTER;ids=$AGENTFILTER"
    fi

    FULLFILTER="$FULLFILTER/cacheManagers"
    if [ "x$CACHEMANAGERFILTER" != "x" ] && [ "x$CACHEMANAGERFILTER" != "x$NULLVALUE" ] ; then
        FULLFILTER="$FULLFILTER;names=$CACHEMANAGERFILTER"
    fi

    FULLFILTER="$FULLFILTER/caches"
    if [ "x$CACHEFILTER" != "x" ] && [ "x$CACHEFILTER" != "x$NULLVALUE" ] ; then
        FULLFILTER="$FULLFILTER;names=$CACHEFILTER"
    fi

    echo $FULLFILTER
    return 0 
}

# Takes 4 params:
# - agents (comma separated string)
# - cache managers (comma separated string)
# - caches (comma separated string)
# - "true" for enable, "false" for disable
function changeCacheState()
{
    AGENTIDS=$1
    CACHEMGRS=$2
    CACHES=$3   
    ENABLE=$4
    
    echo "Begin changeCacheState('$AGENTIDS', '$CACHEMGRS', '$CACHES', '$ENABLE')"
    
    if [ "x$AGENTIDS" == "x" ]; then
        AGENTIDS=("$NULLVALUE")
    elif [ "$AGENTIDS" == "$ALLVALUE" ]; then
        AGENTIDS=$(retrieveAllCacheAgents)
    fi
    print_debug "Agents: $AGENTIDS"
    IFS=',' read -a arrAgentIds <<< "$AGENTIDS"
    
    for agentid in "${arrAgentIds[@]}"
    do
        if [ "x$CACHEMGRS" == "x" ]; then
            CACHEMGRS=("$NULLVALUE")
        elif [ "$CACHEMGRS" == "$ALLVALUE" ]; then
            CACHEMGRS=$(retrieveAllCacheManagers $agentid)
        fi
        print_debug "Cache Managers: $CACHEMGRS"
        IFS=',' read -a arrCacheMgr <<< "$CACHEMGRS"
        
        for cacheMgr in "${arrCacheMgr[@]}"
        do
            if [ "x$CACHES" == "x" ]; then
                CACHES=("$NULLVALUE")
            elif [ "$CACHES" == "$ALLVALUE" ]; then
                CACHES=$(retrieveAllCacheManagerCaches $agentid $cacheMgr)
            fi
            print_debug "Caches: $CACHES"
            IFS=',' read -a arrCaches <<< "$CACHES"
            
            for cache in "${arrCaches[@]}"
            do
                CACHEFILTER=$(constructCacheURL "$agentid" "$cacheMgr" "$cache")
                URL="$TMC_URL$TMC_API_BASE$CACHEFILTER"
                BODY="{\"attributes\":{\"Enabled\":$ENABLE}}"
                
                echo "----------------------"
                echo "Submitting PUT $URL"
                OUTPUT=$(curl $CURL_OPTIONS -H "$HTTP_JSON_HEADERS" -b $COOKIE_PATH -d $BODY -X PUT $URL)
                echo "Output: $OUTPUT"
                
                RETVAL=$?
            done
        done
    done

    return $RETVAL
}

function clearCache()
{
    AGENTIDS=$1
    CACHEMGRS=$2
    CACHES=$3

    echo "Begin clearCache('$AGENTIDS', '$CACHEMGRS', '$CACHES')"
    
    if [ "x$AGENTIDS" == "x" ]; then
        AGENTIDS=("$NULLVALUE")
    elif [ "$AGENTIDS" == "$ALLVALUE" ]; then
        AGENTIDS=$(retrieveAllCacheAgents)
    fi
    print_debug "Agents: $AGENTIDS"
    IFS=',' read -a arrAgentIds <<< "$AGENTIDS"
    
    #getting only 1 agent because the remove operation does not require to submit to all agents
    agentid="${arrAgentIds[0]}"
    
    print_debug "Single Agent chosen: $agentid"
    if [ "x$CACHEMGRS" == "x" ]; then
        CACHEMGRS=("$NULLVALUE")
    elif [ "$CACHEMGRS" == "$ALLVALUE" ]; then
        CACHEMGRS=$(retrieveAllCacheManagers $agentid)
    fi
    print_debug "Cache Managers: $CACHEMGRS"
    IFS=',' read -a arrCacheMgr <<< "$CACHEMGRS"
    
    for cacheMgr in "${arrCacheMgr[@]}"
    do
        if [ "x$CACHES" == "x" ]; then
            CACHES=("$NULLVALUE")
        elif [ "$CACHES" == "$ALLVALUE" ]; then
            CACHES=$(retrieveAllCacheManagerCaches $agentid $cacheMgr)
        fi
        print_debug "Caches: $CACHES"
        IFS=',' read -a arrCaches <<< "$CACHES"
        
        for cache in "${arrCaches[@]}"
        do
            CACHEFILTER=$(constructCacheURL "$agentid" "$cacheMgr" "$cache")
            URL="$TMC_URL$TMC_API_BASE$CACHEFILTER/elements"
            
            echo "----------------------"
            echo "Submitting DELETE $URL"
            OUTPUT=$(curl $CURL_OPTIONS -H "$HTTP_JSON_HEADERS" -b $COOKIE_PATH -X DELETE $URL)
            echo "Output: $OUTPUT"
            
            RETVAL=$?
        done
    done

    return $RETVAL
}

function print_debug()
{
    if [ "x$DEBUG" == "xtrue" ]; then
        echo "$1"
    fi
}

function print_success()
{
    echo "      [Success]"
}

function print_failure()
{
    echo "      [failure]"
}

while [[ $# > 1 ]]
do
key="$1"
shift

case $key in
    -a|--agentids)
        AGENTIDS="$1"
        shift
    ;;
    -m|--cachemgrs)
        CACHEMGRS="$1"
        shift
    ;;
    -c|--caches)
        CACHES="$1"
        shift
    ;;
    -o|--operation)
        OPS="$1"
        shift
    ;;
    -u|--user)
        TMC_USER="$1"
        shift
    ;;
    -p|--password)
        TMC_PASSWORD="$1"
        shift
    ;;
    --default)
        DEFAULT=YES
        shift
    ;;
    *)
        echo "Unknown Option"
        exit 1
    ;;
esac
done

echo "==============================="
echo "OPERATION = ${OPS}"
echo "AGENTS = ${AGENTIDS}"
echo "CACHE MANAGERS = ${CACHEMGRS}"
echo "CACHES = ${CACHES}"
echo "==============================="
echo

CMD=""
case "$OPS" in
    "enable")
        CMD="changeCacheState $AGENTIDS $CACHEMGRS $CACHES true"
    ;;
    "disable")
        CMD="changeCacheState $AGENTIDS $CACHEMGRS $CACHES false"
    ;;
    "clear")
        CMD="clearCache $AGENTIDS $CACHEMGRS $CACHES"
    ;;
    *)
        echo "Unknown Option"
        echo "Syntax:"
        echo "$0 -o {enable,disable,clear}"
        exit 1
    ;;
esac

dt=`date +%Y%m%d_%H%M%S`
if [ "x$CMD" != "x" ] ; then
    if [ "x$TMC_USER" == "x" ] ; then
        TMC_USER=""
        TMC_PASSWORD=""
        read -p "TMC Username: " TMC_USER
        read -s -p "TMC Password: " TMC_PASSWORD
        echo ""
    fi
    login "$TMC_USER" "$TMC_PASSWORD"
    RETVAL=$?
    if [ $RETVAL -eq 0 ]; then
        $CMD
        RETVAL=$?
        logout
    else
        echo "Could not login. Verify you have the right user / password"
    fi
fi

echo -n "$dt - Operation:"
if [ $RETVAL -eq 0 ]; then
    print_success
else
    print_failure
fi

exit $RETVAL
