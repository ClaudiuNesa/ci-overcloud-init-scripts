exec_with_retry2 () {
    MAX_RETRIES=$1
    INTERVAL=$2

    COUNTER=0
    while [ $COUNTER -lt $MAX_RETRIES ]; do
        EXIT=0
        eval '${@:3}' || EXIT=$?
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

exec_with_retry () {
    CMD=$1
    MAX_RETRIES=${2-10}
    INTERVAL=${3-0}

    exec_with_retry2 $MAX_RETRIES $INTERVAL $CMD
}

run_wsmancmd_with_retry () {
    HOST=$1
    USERNAME=$2
    PASSWORD=$3
    CMD=$4

    exec_with_retry "python /var/lib/jenkins/jenkins-master/wsman.py -U https://$HOST:5986/wsman -u $USERNAME -p $PASSWORD $CMD"
}

set +e

source /var/lib/jenkins/jenkins-master/keystonerc_admin

LOGS_SSH_KEY=/var/lib/jenkins/jenkins-master/norman.pem
export LOGS_SSH_KEY=$LOGS_SSH_KEY

echo "Collecting logs"
ssh -o "UserKnownHostsFile /dev/null" -o "StrictHostKeyChecking no" -i $DEVSTACK_SSH_KEY ubuntu@$FLOATING_IP "/home/ubuntu/bin/collect_logs.sh"

echo "Creating logs destination folder"
ssh -o "UserKnownHostsFile /dev/null" -o "StrictHostKeyChecking no" -i $LOGS_SSH_KEY logs@logs.openstack.tld "if [ ! -d /srv/logs/cinder/$ZUUL_CHANGE/$ZUUL_PATCHSET ]; then mkdir -p /srv/logs/cinder/$ZUUL_CHANGE/$ZUUL_PATCHSET; else rm -rf /srv/logs/cinder/$ZUUL_CHANGE/$ZUUL_PATCHSET/*; fi"

echo "Downloading logs"
scp -o "UserKnownHostsFile /dev/null" -o "StrictHostKeyChecking no" -i $DEVSTACK_SSH_KEY ubuntu@$FLOATING_IP:/home/ubuntu/aggregate.tar.gz "aggregate-$NAME.tar.gz"

echo "Uploading logs"
scp -o "UserKnownHostsFile /dev/null" -o "StrictHostKeyChecking no" -i $LOGS_SSH_KEY "aggregate-$NAME.tar.gz" logs@logs.openstack.tld:/srv/logs/cinder/$ZUUL_CHANGE/$ZUUL_PATCHSET/aggregate-logs.tar.gz
gzip -9 /var/lib/jenkins/jenkins-master/logs/console-$NAME.log
scp -o "UserKnownHostsFile /dev/null" -o "StrictHostKeyChecking no" -i $LOGS_SSH_KEY "/var/lib/jenkins/jenkins-master/logs/console-$NAME.log.gz" logs@logs.openstack.tld:/srv/logs/cinder/$ZUUL_CHANGE/$ZUUL_PATCHSET/console.log.gz && rm -f /var/lib/jenkins/jenkins-master/logs/console-$NAME.log.gz
gzip -9 /var/lib/jenkins/jenkins-master/logs/console-$CINDER_VM_NAME.log
scp -o "UserKnownHostsFile /dev/null" -o "StrictHostKeyChecking no" -i $LOGS_SSH_KEY "/var/lib/jenkins/jenkins-master/logs/console-$CINDER_VM_NAME.log.gz" logs@logs.openstack.tld:/srv/logs/cinder/$ZUUL_CHANGE/$ZUUL_PATCHSET/console-cinder.log.gz && rm -f /var/lib/jenkins/jenkins-master/logs/console-$$CINDER_VM_NAME.log.gz
echo "Extracting logs"
ssh -o "UserKnownHostsFile /dev/null" -o "StrictHostKeyChecking no" -i $LOGS_SSH_KEY logs@logs.openstack.tld "tar -xzf /srv/logs/cinder/$ZUUL_CHANGE/$ZUUL_PATCHSET/aggregate-logs.tar.gz -C /srv/logs/cinder/$ZUUL_CHANGE/$ZUUL_PATCHSET/"

echo "Fixing permissions on all log files"
ssh -o "UserKnownHostsFile /dev/null" -o "StrictHostKeyChecking no" -i $LOGS_SSH_KEY logs@logs.openstack.tld "chmod a+rx -R /srv/logs/cinder/$ZUUL_CHANGE/$ZUUL_PATCHSET/"

echo "Releasing devstack floating IP"
nova remove-floating-ip "$NAME" "$FLOATING_IP"
echo "Removing devstack VM"
nova delete "$NAME"
echo "Deleting devstack floating IP"
nova floating-ip-delete "$FLOATING_IP"
echo "Releasing cinder floating ip"
nova remove-floating-ip "$CINDER_VM_NAME" "$CINDER_FLOATING_IP"
echo "Removing cinder VM"
nova delete "$CINDER_VM_NAME"
echo "Deleting cinder floating ip"
nova floating-ip-delete "$CINDER_FLOATING_IP"

set -e