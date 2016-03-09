#!/bin/bash
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

if [ "$TERM" != "unknown" ]; then
  reset=$(tput sgr0)
  blue=$(tput setaf 4)
  red=$(tput setaf 1)
  green=$(tput setaf 2)
else
  reset=""
  blue=""
  red=""
  green=""
fi

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
      echo "Unable to find shard name for ${controller}. May be down..."
      continue
    fi

    if curl --silent -u admin:admin http://${controller}:8181/jolokia/read/org.opendaylight.controller:Category=Shards,\
name=${shard_name},type=DistributedConfigDatastore | grep -Eo 'RaftState":"Leader"'; then
      echo "Shutting down ODL Leader: ${controller} Shard: $shard_name"
      ssh -T -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no "heat-admin@$controller" "sudo systemctl stop opendaylight"
      return
    fi
  done

  echo "Unable to find Leader...exiting"
  exit 1

}

function start_odl_all() {
  source /home/stack/stackrc
  controllers=$(nova list | grep controller | grep -Eo "[0-9]+\.[0-9]\.[0-9]\.[0-9]")

  for controller in $controllers; do
    ssh -T -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no "heat-admin@$controller" << EOI
if ! sudo systemctl status opendaylight > /dev/null; then
sudo systemctl start opendaylight
echo "OpenDaylight started on ${controller}"
fi
EOI
    ssh -T -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no "heat-admin@$controller" "sudo systemctl start opendaylight"
  done

}

function prompt_user() {
  read -p "Press any key to continue..."
}

#arg: message to print
function pprint() {
  echo -e "${blue}######################################${reset}"
  echo -e "${blue}${1}${reset}"
  echo -e "${blue}######################################${reset}"

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
pprint "Ready to shutdown ODL Leader"
prompt_user
shutdown_odl_leader
sleep 5
pprint "Ready to run Leader Down Ping Test"
prompt_user
run_test
pprint "Leader Down Ping Test Complete"
sleep 5
pprint "Ready to restart downed ODL Node"
prompt_user
start_odl_all
pprint "Waiting 30 seconds for ODL to start"
sleep 30
pprint "Ready to run Bounced ODL Ping Test"
prompt_user
run_test
pprint "Bounced ODL Ping Test Complete"
