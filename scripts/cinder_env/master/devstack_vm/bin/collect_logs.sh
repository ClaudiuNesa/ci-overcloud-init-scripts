#!/bin/bash

TAR=$(which tar)
GZIP=$(which gzip)

DEVSTACK_LOGS="/opt/stack/logs/screen"
CINDER_LOGS="/openstack"
TEMPEST_LOGS="/home/ubuntu/tempest"

LOG_DST="/home/ubuntu/aggregate"
LOG_DST_DEVSTACK="$LOG_DST/devstack_logs"
LOG_DST_CINDER="$LOG_DST/cinder_logs"
CONFIG_DST_DEVSTACK="$LOG_DST/devstack_config"
CONFIG_DST_CINDER="$LOG_DST/cinder_config"

function emit_error() {
    echo "ERROR: $1"
    exit 1
}

function emit_warning() {
    echo "WARNING: $1"
    return 0
}

function archive_devstack() {
    if [ ! -d "$LOG_DST_DEVSTACK" ]
    then
        mkdir -p "$LOG_DST_DEVSTACK" || emit_error "Failed to create $LOG_DST_DEVSTACK"
    fi

    for i in `ls -A $DEVSTACK_LOGS`
    do
        if [ -h "$DEVSTACK_LOGS/$i" ]
        then
                REAL=$(readlink "$DEVSTACK_LOGS/$i")
                $GZIP -c "$REAL" > "$LOG_DST_DEVSTACK/$i.gz" || emit_warning "Failed to archive devstack logs"
        fi
    done
    for i in ceilometer cinder glance keystone neutron nova openvswitch openvswitch-switch
    do
        mkdir -p $CONFIG_DST_DEVSTACK/$i
        for j in `ls -A /etc/$i`
        do
            if [ -d /etc/$i/$j ]
            then
                $TAR cvzf "$CONFIG_DST_DEVSTACK/$i/$j.tar.gz" "/etc/$i/$j"
            else
                $GZIP -c "/etc/$i/$j" > "$CONFIG_DST_DEVSTACK/$i/$j.gz"
            fi
        done
    done
    $GZIP -c /home/ubuntu/devstack/localrc > "$CONFIG_DST_DEVSTACK/localrc.txt.gz"
    df -h > "$CONFIG_DST_DEVSTACK/df.txt" 2>&1 && $GZIP "$CONFIG_DST_DEVSTACK/df.txt"
    iptables-save > "$CONFIG_DST_DEVSTACK/iptables.txt" 2>&1 && $GZIP "$CONFIG_DST_DEVSTACK/iptables.txt"
    dpkg-query -l > "$CONFIG_DST_DEVSTACK/dpkg-l.txt" 2>&1 && $GZIP "$CONFIG_DST_DEVSTACK/dpkg-l.txt"
    pip freeze > "$CONFIG_DST_DEVSTACK/pip-freeze.txt" 2>&1 && $GZIP "$CONFIG_DST_DEVSTACK/pip-freeze.txt"
    ps axwu > "$CONFIG_DST_DEVSTACK/pidstat.txt" 2>&1 && $GZIP "$CONFIG_DST_DEVSTACK/pidstat.txt"
    #/var/log/kern.log
    #/var/log/rabbitmq/
    #/var/log/syslog
}

function archive_cinder_logs() {
    if [ ! -d "$LOG_DST_CINDER" ]
    then
        mkdir -p "$LOG_DST_CINDER"
    fi
    COUNT=1
    for i in `ls -A "$CINDER_LOGS"`
    do
        if [ -d "$CINDER_LOGS/$i" ]
        then
            NAME=`echo $i | sed 's/^hv-compute\([0-9]*\)/hv-compute'$COUNT'/g'`
            mkdir -p "$LOG_DST_CINDER/$NAME"
            COUNT=$(($COUNT + 1))

            for j in `ls -A "$CINDER_LOGS/$i"`;
            do
                $GZIP -c "$CINDER_LOGS/$i/$j" > "$LOG_DST_CINDER/$NAME/$j.gz" || emit_warning "Failed to archive $CINDER_LOGS/$i/$j"
            done
        else
            $GZIP -c "$CINDER_LOGS/$i" > "$LOG_DST_CINDER/$i.gz" || emit_warning "Failed to archive $CINDER_LOGS/$i"
        fi
    done
}

function archive_tempest_files() {
    for i in `ls -A $TEMPEST_LOGS`
    do
        $GZIP "$TEMPEST_LOGS/$i" -c > "$LOG_DST/$i.gz" || emit_error "Failed to archive tempest logs"
    done
}

# Clean
[ -d "$LOG_DST" ] && rm -rf "$LOG_DST"
mkdir -p "$LOG_DST"

archive_devstack
archive_cinder_logs
archive_tempest_files

pushd "$LOG_DST"
$TAR -czf "$LOG_DST.tar.gz" . || emit_error "Failed to archive aggregate logs"
popd

exit 0