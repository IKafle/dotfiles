#!/bin/bash

readonly ENVIRONMENT=$1

declare SHOW_LOGS=$2

readonly SHOW_LOGS=${SHOW_LOGS:-0}

readonly USER="tms"
readonly PASS_PHRASE="yco@nepse777+"

readonly QA_1="192.168.50.70"
readonly QA_2="192.168.50.61"

readonly DUMP_LOG='tail -f /opt/wildfly/standalone/log/server.log; bash -l'

declare -A ENVIRONMENTS=( ["QA-1"]="$QA_1" ["QA-2"]="$QA_2")

readonly IP="${ENVIRONMENTS["${ENVIRONMENT}"]}"
echo -e "Connecting to server ... $IP (${ENVIRONMENT}) \n"


if [ "$SHOW_LOGS" -eq 1 ]; then
    sshpass -p "${PASS_PHRASE}" ssh -o StrictHostKeyChecking=no "${USER}@${IP}" "$DUMP_LOG"
else
    sshpass -p "${PASS_PHRASE}" ssh -o StrictHostKeyChecking=no "${USER}@${IP}"
fi
