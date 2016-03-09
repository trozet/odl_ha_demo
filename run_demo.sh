#!/bin/bash
set -e
#
# Author: Jose Lausuch (jose.lausuch@ericsson.com)
#         Morgan Richomme (morgan.richomme@orange.com)
# Installs the Functest framework within the Docker container
# and run the tests automatically
#
#
# All rights reserved. This program and the accompanying materials
# are made available under the terms of the Apache License, Version 2.0
# which accompanies this distribution, and is available at
# http://www.apache.org/licenses/LICENSE-2.0
#

SSH_OPTIONS=(-o StrictHostKeyChecking=no -o GlobalKnownHostsFile=/dev/null -o UserKnownHostsFile=/dev/null -o LogLevel=error)

usage="Script to trigger the tests automatically.

usage:
    bash $(basename "$0") [-h|--help] [-t <test_name>]

where:
    -h|--help         show this help text
    -r|--report       push results to database (false by default)
    -n|--no-clean     do not clean OpenStack resources after test run
    -s|--serial       run tests in one thread
    -t|--test         run specific set of tests
      <test_name>     one or more of the following separated by comma:
                            vping_ssh,vping_userdata,odl,onos,tempest,rally,vims,promise,doctor


examples:
    $(basename "$0")
    $(basename "$0") --test vping_ssh,odl
    $(basename "$0") -t tempest,rally"


# Support for Functest offline
# NOTE: Still not 100% working when running the tests
offline=false
report=""
clean=true
serial=false

# Get the list of runnable tests
# Check if we are in CI mode


function clean_openstack(){
    if [ $clean == true ]; then
        echo -e "\n\nCleaning Openstack environment..."
        python ${FUNCTEST_REPO_DIR}/testcases/VIM/OpenStack/CI/libraries/clean_openstack.py \
            --debug
        echo -e "\n\n"
    fi
}

function run_test(){
    echo -e "\n\n\n\n"
    echo "----------------------------------------------"
    echo "  Running test case: vPing"
    echo "----------------------------------------------"
    echo ""
    echo "Running vPing-userdata test... "
    source /home/stack/overcloudrc
    python ./vPing_userdata.py --debug

}


function ensure_resources() {
  if [ ! -e ./cirros-0.3.4-x86_64-disk.img ]; then
    wget http://download.cirros-cloud.net/0.3.4/cirros-0.3.4-x86_64-disk.img
  fi
}

function shutdown_odl_leader() {
  # figure out ODL leader
  source /home/stack/stackrc
  controllers=$(nova list | grep controller | grep -Eo "[0-9]+\.[0-9]\.[0-9]\.[0-9]")

  for controller in $controllers; do
    shard_name=$(curl --silent -u admin:admin http://${controller}:8181/jolokia/read/org.opendaylight.controller:\
Category=ShardManager,name=shard-manager-config,type=DistributedConfigDatastore | grep -Eo "member-[0-9]-shard-topology-config")
    echo "shard name is $shard_name"

    if [ -z $shard_name ]; then
      echo "unable to find shard name for ${controller}"
      exit 1
    fi

    if curl --silent -u admin:admin http://${controller}:8181/jolokia/read/org.opendaylight.controller:Category=Shards,\
name=${shard_name},type=DistributedConfigDatastore | grep -Eo 'RaftState":"Leader"'; then
      echo "Shutting down ODL Leader: ${controller} Shard: $shard_name"
      ssh -T -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no "heat-admin@$controller" "sudo systemctl stop opendaylight"
      return
    fi
  done

  echo "Unable to find Leader...exiting"
  return 1

}

function start_odl_all() {
  source /home/stack/stackrc
  controllers=$(nova list | grep controller | grep -Eo "[0-9]+\.[0-9]\.[0-9]\.[0-9]")

  for controller in $controllers; do
    ssh -T -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no "heat-admin@$controller" "sudo systemctl start opendaylight"
  done

}
# Parse parameters
while [[ $# > 0 ]]
    do
    key="$1"
    case $key in
        -h|--help)
            echo "$usage"
            exit 0
            shift
        ;;
        -o|--offline)
            offline=true
        ;;
        -r|--report)
            report="-r"
        ;;
        -n|--no-clean)
            clean=false
        ;;
        -s|--serial)
            serial=true
        ;;
        -t|--test|--tests)
            TEST="$2"
            shift
        ;;
        *)
            echo "unknown option $1 $2"
            exit 1
        ;;
    esac
    shift # past argument or value
done

ensure_resources
run_test
echo "Initial Ping Test Complete"
shutdown_odl_leader
sleep 5
run_test
echo "Leader Down Ping Test Complete"
sleep 5
start_all_odl
sleep 30
run_test
echo "Bounced ODL Ping Test Complete"
