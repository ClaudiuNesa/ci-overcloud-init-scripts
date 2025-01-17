#!/bin/bash
set -e

. ./functions-common

nova flavor-delete 42
nova flavor-create m1.nano 42 96 1 1

nova flavor-delete 84
nova flavor-create m1.micro 84 128 2 1

nova flavor-delete 451
nova flavor-create m1.heat 451 512 5 1

# Add DNS config to the private network
subnet_id=`neutron net-show private | awk '{if (NR == 13) { print $4}}'`
neutron subnet-update $subnet_id --dns_nameservers list=true 8.8.8.8 8.8.4.4

TEMPEST_CONFIG=/opt/stack/tempest/etc/tempest.conf

iniset $TEMPEST_CONFIG compute volume_device_name "sdb"
iniset $TEMPEST_CONFIG compute-feature-enabled rdp_console true
iniset $TEMPEST_CONFIG compute-feature-enabled block_migrate_cinder_iscsi False

iniset $TEMPEST_CONFIG scenario img_dir "/home/ubuntu/devstack/files/images/"
iniset $TEMPEST_CONFIG scenario img_file "cirros-0.3.3-x86_64.vhdx"
iniset $TEMPEST_CONFIG scenario img_disk_format vhd

IMAGE_REF=`iniget $TEMPEST_CONFIG compute image_ref`
iniset $TEMPEST_CONFIG compute image_ref_alt $IMAGE_REF

iniset $TEMPEST_CONFIG compute build_timeout 900
iniset $TEMPEST_CONFIG orchestration build_timeout 900
iniset $TEMPEST_CONFIG volume build_timeout 900
iniset $TEMPEST_CONFIG boto build_timeout 900

iniset $TEMPEST_CONFIG compute ssh_timeout 900
iniset $TEMPEST_CONFIG compute allow_tenant_isolation True
