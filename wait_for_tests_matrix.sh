#!/bin/bash
# env need to be set
# $DRONE_TOKEN
# $DRONE_SERVER

OFFSET_TIME=${START_TIME:-0}
SLEEP_TIME=${SLEEP_TIME:-15}
TIMEOUT=${TIMEOUT:-600}
DRONE_TOKEN=${DRONE_TOKEN}
DRONE_SERVER=${DRONE_SERVER}

CURL_CMD="curl -s ${DRONE_SERVER}/api/repos/${DRONE_REPO_OWNER}/${DRONE_REPO_NAME}/builds/${DRONE_BUILD_NUMBER} -H \"Authorization: Bearer ${DRONE_TOKEN}\""

# JSON extractor utilities
GET_STATE="jq -c '[.procs[] | select(.environ.BATCH?) | . as \$pa | .children[] |select(.name == \"test\") |{id:\$pa.environ.BATCH,state}]'"
GET_LENGTH="jq 'length'"
GET_SUCCESS="jq -c '.[] | select(.state == \"success\") | .id'"
GET_FAILURE="jq -c '.[] | select(.state == \"failure\") | .id'"
GET_PENDING="jq -c '.[] | select(.state == \"pending\") | .id'"
GET_RUNNING="jq -c '.[] | select(.state == \"running\") | .id'"

# function utilities
api_call () {
    RESULT_API=''
    local retry=0

    while [ "${retry}" -lt "3" ]; do
        retry=$((${retry} + 1))
        RESULT_API=$(eval "$CURL_CMD")

        if [ $? -eq 0 ]; then
            # try to parse json
            echo ${RESULT_API} | jq -e . >/dev/null 2>&1
            rst=$?
            if [ -n "${RESULT_API}" ] && [ "$rst" -eq "0" ] ; then
                return
            else
                echo "no build result from drone server (${retry}/3)"
            fi
        else
            echo "api request failed (${retry}/3)"
        fi
        sleep 3
    done
    echo "Fail to query test progress ! ABORTING with exit 1"
    exit 1
}

update_status () {
    api_call
    CURR_STATE=$(eval "echo '$RESULT_API' | $GET_STATE")
    SUCCESS=($(eval "echo '$CURR_STATE' | $GET_SUCCESS"))
    FAILURE=($(eval "echo '$CURR_STATE' | $GET_FAILURE"))
    PENDING=($(eval "echo '$CURR_STATE' | $GET_PENDING"))
    RUNNING=($(eval "echo '$CURR_STATE' | $GET_RUNNING"))
}

RESULT_API=''
api_call
TOTAL_NB_TEST=($(eval "echo '$RESULT_API' | $GET_STATE | $GET_LENGTH"))
SUCCESS=()
FAILURE=()
PENDING=()
RUNNING=()
PREV_STATE=''
CURR_STATE=''

# main loop
echo "total test batch: ${TOTAL_NB_TEST}"
sleep $OFFSET_TIME
START_TIME=$(date +%s)
END_TIME=$((${START_TIME} + ${TIMEOUT}))
if [ "$TOTAL_NB_TEST" -gt "0" ]; then
    update_status

    while [ "${#SUCCESS[@]}" -lt "$TOTAL_NB_TEST" ]; do
        if [ "$CURR_STATE" != "$PREV_STATE" ]; then
            echo "------------------------------------ $(($(date +%s) - ${START_TIME}))/${TIMEOUT} s ---------------------------------------------------"
            echo -e "pending: ${PENDING[@]}\nrunning: ${RUNNING[@]}\nsuccess: ${SUCCESS[@]}\nfailure: ${FAILURE[@]}"
            PREV_STATE=$CURR_STATE

            # abort on failure
            if [ "${#FAILURE[@]}" -gt "0" ]; then
                echo "FAIL TEST DETECTED ! ABORTING with exit 1"
                exit 1
            fi
        fi

        # check if it is not timeout
        if [ "$(date +%s)" -gt "${END_TIME}" ]; then
            echo "TIMING OUT ! ABORTING with exit 1"
            exit 1
        fi

        sleep $SLEEP_TIME
        update_status
    done
    echo -e "----------SUMMARY--------:\nsuccess: ${SUCCESS[@]}\nfailure: ${FAILURE[@]}"

fi
