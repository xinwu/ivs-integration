#!/bin/bash

install_bsnstacklib=%(install_bsnstacklib)s
install_ivs=%(install_ivs)s
is_controller=%(is_controller)s
openstack_release=%(openstack_release)s


controller() {

    systemctl stop neutron-l3-agent
    systemctl disable neutron-l3-agent
    puppet apply --modulepath /etc/puppet/modules %(dst_dir)s/%(hostname)s.pp

    echo 'Restart neutron-server'
    rm -rf /etc/neutron/plugins/ml2/host_certs/*
    systemctl restart neutron-server
}

compute() {

    # install ivs
    if [[ $install_ivs == true ]]; then
        rpm -ivh --force %(dst_dir)s/%(ivs_pkg)s
    fi

    # full installation
    if [[ $install_all == true ]]; then
        cp /usr/lib/systemd/system/neutron-openvswitch-agent.service /usr/lib/systemd/system/neutron-bsn-agent.service

        # stop ovs agent, otherwise, ovs bridges cannot be removed
        systemctl stop neutron-openvswitch-agent
        systemctl disable neutron-openvswitch-agent

        # remove ovs
        declare -a ovs_br=(%(ovs_br)s)
        len=${#ovs_br[@]}
        for (( i=0; i<$len; i++ )); do
            ovs-vsctl del-br ${ovs_br[$i]}
            brctl delbr ${ovs_br[$i]}
            ip link del dev ${ovs_br[$i]}
        done

        #bring down all bonds
        declare -a bonds=(%(bonds)s)
        len=${#bonds[@]}
        for (( i=0; i<$len; i++ )); do
            ip link del dev ${bonds[$i]}
        done

        # deploy bcf
        puppet apply --modulepath /etc/puppet/modules %(dst_dir)s/%(hostname)s.pp

        #reset uplinks to move them out of bond
        declare -a uplinks=(%(uplinks)s)
        len=${#uplinks[@]}
        for (( i=0; i<$len; i++ )); do
            ip link set ${uplinks[$i]} down
        done
        for (( i=0; i<$len; i++ )); do
            ip link set ${uplinks[$i]} up
        done
    fi

    systemctl restart neutron-bsn-agent
}


set +e

# Make sure only root can run this script
if [ "$(id -u)" != "0" ]; then
   echo -e "Please run as root"
   exit 1
fi

# install bsnstacklib
if [[ $install_bsnstacklib == true ]]; then
    pip install --upgrade "bsnstacklib<%(bsnstacklib_version)s"
fi

if [[ $is_controller == true ]]; then
    controller
else
    compute
fi

set -e

exit 0

