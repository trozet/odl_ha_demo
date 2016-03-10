> Major cleanup:
> --------------
> for each $NODE:
> 
>   ovs-vsctl del-manager
>   /usr/share/openvswitch/scripts/ovs-ctl stop
>   rm -rf /etc/openvswitch/conf.db
> 
> 
> for each $CONTROLLER_NODE:
> 
>   /opt/opendaylight/bin/stop
>   systemctl stop neutron-server
>   mysql
>   drop database neutron;     #this gave a message that neutron db wasn't there
>   create database neutron;   #this only matters on one (replicated, I assume), but it
>                              #wont hurt to run on all controller nodes
>   exit;
>   systemctl start neutron-server
>   cd /opt/opendaylight; rm -rf data snapshots journal
>   /usr/share/openvswitch/scripts/ovs-ctl start
>   systemctl restart network 
>   /opt/opendaylight/bin/start
> 
> wait for ovsdb:1 output; sleep another 10s (just for good measure)
> 
> for each $NODE:
> 
>    /usr/share/openvswitch/scripts/ovs-ctl start
>    ovs-vsctl set-manager tcp:$CTL1:6640 tcp:$CTL2:6640 tcp:$CTL3:6640
>    run jose's script
   
