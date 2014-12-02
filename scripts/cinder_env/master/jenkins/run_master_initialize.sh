exec_with_retry2 () {
    MAX_RETRIES=$1
    INTERVAL=$2

    COUNTER=0
    while [ $COUNTER -lt $MAX_RETRIES ]; do
        EXIT=0
        eval '${@:3} >> /var/lib/jenkins/jenkins-master/logs/console-$NAME.log 2>&1' || EXIT=$?
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

wait_for_listening_port () {
    HOST=$1
    PORT=$2
    TIMEOUT=$3
    exec_with_retry "nc -z -w$TIMEOUT $HOST $PORT" 50 5
}

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

join_cinder(){
    set +e
    WIN_USER=$1
    WIN_PASS=$2
    URL=$3

    set -e
    run_wsmancmd_with_retry $URL $WIN_USER $WIN_PASS "powershell -ExecutionPolicy RemoteSigned \$env:Path += ';C:\Python27;C:\Python27\Scripts;C:\OpenSSL-Win32\bin;C:\Program Files (x86)\Git\cmd;C:\MinGW\mingw32\bin;C:\MinGW\msys\1.0\bin;C:\MinGW\bin;C:\qemu-img'; setx PATH \$env:Path;"
    run_wsmancmd_with_retry $URL $WIN_USER $WIN_PASS "powershell -ExecutionPolicy RemoteSigned git clone https://github.com/ClaudiuNesa/ci-overcloud-init-scripts.git C:\ci-overcloud-init-scripts"
    run_wsmancmd_with_retry $URL $WIN_USER $WIN_PASS "powershell -ExecutionPolicy RemoteSigned cd C:\ci-overcloud-init-scripts; git checkout cinder"
    run_wsmancmd_with_retry $URL $WIN_USER $WIN_PASS "powershell -ExecutionPolicy RemoteSigned C:\ci-overcloud-init-scripts\scripts\cinder_env\master\Cinder\scripts\create-master-environment.ps1 -devstackIP $FIXED_IP -branchName $BRANCH -buildFor $OPENSTACK_PROJECT"
}

source /var/lib/jenkins/jenkins-master/keystonerc_admin

FLOATING_IP=$(nova floating-ip-create public | awk '{print $2}' | sed '/^$/d' | tail -n 1 ) || echo "Failed to allocate floating IP" >> /var/lib/jenkins/jenkins-master/logs/console-$NAME.log 2>&1
if [ -z "$FLOATING_IP" ]
then
    exit 1
fi
export BRANCH=$BRANCH
export OPENSTACK_PROJECT=$OPENSTACK_PROJECT
export FLOATING_IP=$FLOATING_IP
echo FLOATING_IP=$FLOATING_IP > devstack_cinder_master_params.txt
echo BRANCH=$BRANCH >> devstack_cinder_master_params.txt
echo OPENSTACK_PROJECT=$OPENSTACK_PROJECT >> devstack_cinder_master_params.txt

export DEVSTACK_SSH_KEY=$DEVSTACK_SSH_KEY
echo $DEVSTACK_SSH_KEY

UUID=$(python -c "import uuid; print uuid.uuid4().hex")
export NAME="devstack-cinder-master-$UUID"
echo NAME=$NAME >> devstack_cinder_master_params.txt

NET_ID=$(nova net-list | grep 'private' | awk '{print $2}')
echo NET_ID=$NET_ID >> devstack_cinder_master_params.txt

echo FLOATING_IP=$FLOATING_IP > /var/lib/jenkins/jenkins-master/logs/console-$NAME.log 2>&1
echo NAME=$NAME >> /var/lib/jenkins/jenkins-master/logs/console-$NAME.log 2>&1
echo NET_ID=$NET_ID >> /var/lib/jenkins/jenkins-master/logs/console-$NAME.log 2>&1

echo "Deploying devstack $NAME" >> /var/lib/jenkins/jenkins-master/logs/console-$NAME.log 2>&1
nova boot --availability-zone cinder --flavor m1.medium --image devstack --key-name default --security-groups devstack --nic net-id="$NET_ID" "$NAME" --poll >> /var/lib/jenkins/jenkins-master/logs/console-$NAME.log 2>&1

if [ $? -ne 0 ]
then
    echo "Failed to create devstack VM: $NAME" >> /var/lib/jenkins/jenkins-master/logs/console-$NAME.log 2>&1
    nova show "$NAME" >> /var/lib/jenkins/jenkins-master/logs/console-$NAME.log 2>&1
    exit 1
fi

echo "Fetching devstack VM fixed IP address" >> /var/lib/jenkins/jenkins-master/logs/console-$NAME.log 2>&1
export FIXED_IP=$(nova show "$NAME" | grep "private network" | awk '{print $5}')

COUNT=0
while [ -z "$FIXED_IP" ]
do
    if [ $COUNT -ge 10 ]
    then
        echo "Failed to get fixed IP" >> /var/lib/jenkins/jenkins-master/logs/console-$NAME.log 2>&1
        echo "nova show output:" >> /var/lib/jenkins/jenkins-master/logs/console-$NAME.log 2>&1
        nova show "$NAME" >> /var/lib/jenkins/jenkins-master/logs/console-$NAME.log 2>&1
        echo "nova console-log output:" >> /var/lib/jenkins/jenkins-master/logs/console-$NAME.log 2>&1
        nova console-log "$NAME" >> /var/lib/jenkins/jenkins-master/logs/console-$NAME.log 2>&1
        echo "neutron port-list output:" >> /var/lib/jenkins/jenkins-master/logs/console-$NAME.log 2>&1
        neutron port-list -D -c device_id -c fixed_ips | grep $VM_ID >> /var/lib/jenkins/jenkins-master/logs/console-$NAME.log 2>&1
        exit 1
    fi
    sleep 15
    export FIXED_IP=$(nova show "$NAME" | grep "private network" | awk '{print $5}') 
    COUNT=$(($COUNT + 1))
done

echo FIXED_IP=$FIXED_IP >> devstack_cinder_master_params.txt

export VMID=`nova show $NAME | awk '{if (NR == 16) {print $4}}'`

echo VM_ID=$VMID >> devstack_cinder_master_params.txt
echo VM_ID=$VMID >> /var/lib/jenkins/jenkins-master/logs/console-$NAME.log 2>&1

exec_with_retry "nova add-floating-ip $NAME $FLOATING_IP" 15 5

nova show "$NAME" >> /var/lib/jenkins/jenkins-master/logs/console-$NAME.log 2>&1

wait_for_listening_port $FLOATING_IP 22 5 || { nova console-log "$NAME" >> /var/lib/jenkins/jenkins-master/logs/console-$NAME.log 2>&1; exit 1; }
sleep 5

scp -v -r -o "StrictHostKeyChecking no" -o "UserKnownHostsFile /dev/null" -i $DEVSTACK_SSH_KEY /usr/local/src/ci-overcloud-init-scripts/scripts/cinder_env/master/devstack_vm/* ubuntu@$FLOATING_IP:/home/ubuntu/ >> /var/lib/jenkins/jenkins-master/logs/console-$NAME.log 2>&1

run_ssh_cmd_with_retry ubuntu@$FLOATING_IP $DEVSTACK_SSH_KEY "/home/ubuntu/bin/update_devstack_repos.sh --branch $BRANCH --build-for $OPENSTACK_PROJECT" 1

scp -v -r -o "StrictHostKeyChecking no" -o "UserKnownHostsFile /dev/null" -i $DEVSTACK_SSH_KEY /usr/local/src/ci-overcloud-init-scripts/scripts/cinder_env/master/devstack_vm/devstack/* ubuntu@$FLOATING_IP:/home/ubuntu/devstack >> /var/lib/jenkins/jenkins-master/logs/console-$NAME.log 2>&1

# run devstack
run_ssh_cmd_with_retry ubuntu@$FLOATING_IP $DEVSTACK_SSH_KEY 'source /home/ubuntu/keystonerc; /home/ubuntu/bin/run_devstack.sh' 5  

# run post_stack
run_ssh_cmd_with_retry ubuntu@$FLOATING_IP $DEVSTACK_SSH_KEY "source /home/ubuntu/keystonerc && /home/ubuntu/bin/post_stack.sh" 5

export CINDER_VM_NAME="cinder-master-$UUID"
echo CINDER_VM_NAME=$CINDER_VM_NAME >> devstack_cinder_master_params.txt

echo "Deploying cinder $CINDER_VM_NAME" > /var/lib/jenkins/jenkins-master/logs/console-$CINDER_VM_NAME.log 2>&1
nova boot --availability-zone cinder --flavor m1.cinder --image cinder --key-name default --security-groups default --nic net-id="$NET_ID" "$CINDER_VM_NAME" --poll >> /var/lib/jenkins/jenkins-master/logs/console-$CINDER_VM_NAME.log 2>&1

if [ $? -ne 0 ]
then
    echo "Failed to create cinder VM: $CINDER_VM_NAME" >> /var/lib/jenkins/jenkins-master/logs/console-$CINDER_VM_NAME.log 2>&1
    nova show "$CINDER_VM_NAME" >> /var/lib/jenkins/jenkins-master/logs/console-$CINDER_VM_NAME.log 2>&1
    exit 1
fi

#work around restart issue
echo "Fetching cinder VM status " >> /var/lib/jenkins/jenkins-master/logs/console-$CINDER_VM_NAME.log 2>&1
export CINDER_STATUS=$(nova show $CINDER_VM_NAME | grep "status" | awk '{print $4}')
COUNT=0
while [ $CINDER_STATUS != "SHUTOFF" ]
do
    if [ $COUNT -ge 15 ]
    then
        echo "Failed to get $CINDER_VM_NAME status" >> /var/lib/jenkins/jenkins-master/logs/console-$CINDER_VM_NAME.log 2>&1
        nova show "$CINDER_VM_NAME" >> /var/lib/jenkins/jenkins-master/logs/console-$CINDER_VM_NAME.log 2>&1
        exit 1
    fi
    sleep 20
    export CINDER_STATUS=$(nova show $CINDER_VM_NAME | grep "status" | awk '{print $4}')
    COUNT=$(($COUNT + 1))
done
echo "Starting $CINDER_VM_NAME" >> /var/lib/jenkins/jenkins-master/logs/console-$CINDER_VM_NAME.log 2>&1
nova start $CINDER_VM_NAME >> /var/lib/jenkins/jenkins-master/logs/console-$CINDER_VM_NAME.log 2>&1


echo "Fetching cinder VM fixed IP address" >> /var/lib/jenkins/jenkins-master/logs/console-$CINDER_VM_NAME.log 2>&1
export CINDER_FIXED_IP=$(nova show "$CINDER_VM_NAME" | grep "private network" | awk '{print $5}')
echo $CINDER_FIXED_IP 
COUNT=0
while [ -z "$CINDER_FIXED_IP" ]
do
    if [ $COUNT -ge 10 ]
    then
        echo "Failed to get fixed IP" >> /var/lib/jenkins/jenkins-master/logs/console-$CINDER_VM_NAME.log 2>&1
        echo "nova show output:" >> /var/lib/jenkins/jenkins-master/logs/console-$CINDER_VM_NAME.log 2>&1
        nova show "$CINDER_FIXED_IP" >> /var/lib/jenkins/jenkins-master/logs/console-$CINDER_VM_NAME.log 2>&1
        echo "nova console-log output:" >> /var/lib/jenkins/jenkins-master/logs/console-$CINDER_VM_NAME.log 2>&1
        nova console-log "$CINDER_FIXED_IP" >> /var/lib/jenkins/jenkins-master/logs/console-$CINDER_VM_NAME.log 2>&1
        echo "neutron port-list output:" >> /var/lib/jenkins/jenkins-master/logs/console-$CINDER_VM_NAME.log 2>&1
        neutron port-list -D -c device_id -c fixed_ips | grep $VM_ID >> /var/lib/jenkins/jenkins-master/logs/console-$CINDER_VM_NAME.log 2>&1
        exit 1
    fi
    sleep 15
    export FIXED_IP=$(nova show "$CINDER_VM_NAME" | grep "private network" | awk '{print $5}') 
    COUNT=$(($COUNT + 1))
done

CINDER_FLOATING_IP=$(nova floating-ip-create public | awk '{print $2}' | sed '/^$/d' | tail -n 1 ) || echo "Failed to allocate floating IP" >> /var/lib/jenkins/jenkins-master/logs/console-$CINDER_VM_NAME.log 2>&1
if [ -z "$CINDER_FLOATING_IP" ]
then
    exit 1
fi
echo CINDER_FLOATING_IP=$CINDER_FLOATING_IP >> devstack_cinder_master_params.txt
export CINDER_FLOATING_IP=$CINDER_FLOATING_IP >> /var/lib/jenkins/jenkins-master/logs/console-$CINDER_VM_NAME.log

export WINDOWS_PASSWORD=$(nova get-password $CINDER_VM_NAME $DEVSTACK_SSH_KEY) 
echo $WINDOWS_PASSWORD
COUNT=0
while [ -z "$WINDOWS_PASSWORD" ]
do
    if [ $COUNT -ge 20 ]
    then
        echo "Failed to get password" >> /var/lib/jenkins/jenkins-master/logs/console-$CINDER_VM_NAME.log 2>&1
        exit 1
    fi
    sleep 20
    export WINDOWS_PASSWORD=$(nova get-password $CINDER_VM_NAME $DEVSTACK_SSH_KEY)
    COUNT=$(($COUNT + 1))
done

export WINDOWS_USER=$WINDOWS_USER >> /var/lib/jenkins/jenkins-master/logs/console-$CINDER_VM_NAME.log 2>&1
export WINDOWS_PASSWORD=$(nova get-password $CINDER_VM_NAME $DEVSTACK_SSH_KEY) >> /var/lib/jenkins/jenkins-master/logs/console-$CINDER_VM_NAME.log 2>&1

nova add-floating-ip $CINDER_VM_NAME $CINDER_FLOATING_IP

echo WINDOWS_USER=$WINDOWS_USER >> devstack_cinder_master_params.txt
echo WINDOWS_PASSWORD=$WINDOWS_PASSWORD >> devstack_cinder_master_params.txt
echo CINDER_FIXED_IP=$CINDER_FIXED_IP >> devstack_cinder_master_params.txt

wait_for_listening_port $CINDER_FLOATING_IP 5986 10 || { nova console-log "$CINDER_VM_NAME" >> /var/lib/jenkins/jenkins-master/logs/console-$CINDER_VM_NAME.log 2>&1; exit 1; }
sleep 5

#join cinder host
join_cinder $WINDOWS_USER $WINDOWS_PASSWORD $CINDER_FLOATING_IP

# check cinder-volume status
run_ssh_cmd_with_retry ubuntu@$FLOATING_IP $DEVSTACK_SSH_KEY 'source /home/ubuntu/keystonerc; CINDER_COUNT=$(cinder service-list | grep cinder-volume | grep -c -w up); if [ "$CINDER_COUNT" == 1 ];then cinder service-list; else cinder service-list; exit 1;fi' 20