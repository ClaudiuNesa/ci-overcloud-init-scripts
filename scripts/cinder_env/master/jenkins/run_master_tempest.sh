run_ssh_cmd () {
    SSHUSER_HOST=$1
    SSHKEY=$2
    CMD=$3
    ssh -t -o 'PasswordAuthentication no' -o 'StrictHostKeyChecking no' -o 'UserKnownHostsFile /dev/null' -i $SSHKEY $SSHUSER_HOST "$CMD" >> /var/lib/jenkins/jenkins-master/logs/console-$NAME.log 2>&1
}

run_ssh_cmd_with_retry () {
    SSHUSER_HOST=$1
    SSHKEY=$2
    CMD=$3
    INTERVAL=$4
    MAX_RETRIES=10

    COUNTER=0
    while [ $COUNTER -lt $MAX_RETRIES ]; do
        EXIT=0
        run_ssh_cmd $SSHUSER_HOST $SSHKEY "$CMD" || EXIT=$?
        if [ $EXIT -eq 0 ]; then
            return 0
        fi
        let COUNTER=COUNTER+1

        if [ -n "$INTERVAL" ]; then
            sleep $INTERVAL
        fi
    done
    return $EXIT
}

export FAILURE=0
set +e
echo "Running tests"
ssh -o "UserKnownHostsFile /dev/null" -o "StrictHostKeyChecking no" -i $DEVSTACK_SSH_KEY ubuntu@$FLOATING_IP "source /home/ubuntu/keystonerc && /home/ubuntu/bin/run_tests.sh"  >> /var/lib/jenkins/jenkins-master/logs/console-$NAME.log 2>&1 || export FAILURE=$?
set -e

echo FAILURE=$FAILURE >> devstack_cinder_master_params.txt

LOGS_SSH_KEY=/var/lib/jenkins/jenkins-master/norman.pem
export LOGS_SSH_KEY=$LOGS_SSH_KEY
LOGS_DEST_FOLDER="LOG_DEST_FOLDER"
export LOGS_DEST_FOLDER=$LOGS_DEST_FOLDER
RESULT="SUCCESS"
CLASS_TYPE="pass"

if [ $FAILURE != 0 ]
then
    RESULT="FAIL"
	CLASS_TYPE="fail"
    run_ssh_cmd_with_retry logs@logs.openstack.tld $LOGS_SSH_KEY "sed -i 's/<!--tr-->/<!--tr-->\n<tr class=\\\"${CLASS_TYPE}Class\\\">\n\t<td class=\\\"testname\\\"><center>${BUILD_ID}<\/center><\/td>\n\t<td class=\\\"small\\\"><center>${RESULT}<\/center><\/td>\n\t<td class=\\\"small\\\"><a href=\\\"${LOGS_DEST_FOLDER}\/\\\">Logs<\/a><\/td>\n<\/tr>\n/g' /srv/logs/cinder/master/index.html"
    echo FAILURE=$FAILURE >> devstack_cinder_master_params.txt
    exit 1
fi

run_ssh_cmd_with_retry logs@logs.openstack.tld $LOGS_SSH_KEY "sed -i 's/<!--tr-->/<!--tr-->\n<tr class=\\\"${CLASS_TYPE}Class\\\">\n\t<td class=\\\"testname\\\"><center>${BUILD_ID}<\/center><\/td>\n\t<td class=\\\"small\\\"><center>${RESULT}<\/center><\/td>\n\t<td class=\\\"small\\\"><a href=\\\"${LOGS_DEST_FOLDER}\/\\\">Logs<\/a><\/td>\n<\/tr>\n/g' /srv/logs/cinder/master/index.html"