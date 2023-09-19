#!/bin/bash
# expects: TripleO based deployment of Train with containerised Nova
# note: There is no support for this script.

# variables
thisoverclouduser='cloud-admin'
tmpaggfile='/tmp/th-agg-lst'

# source overcloud environment vars if needed
#source /home/stack/overcloudrc

echo "Retrieving list of available computes (compute service enabled and up)"
available_computes=`openstack compute service list -f value --sort-column Host | grep nova-compute | grep enabled | grep up | awk '{print $3}' | cut -d "." -f1`

# Grab aggregate info
openstack aggregate list -f value -c ID | xargs -I % sh -c "openstack aggregate show % -f value -c name -c hosts | xargs"  > $tmpaggfile

echo "Pulling resource data for available computes"
echo "Compute, Aggregates, VM, vRAM (MiB), vCPU, Numa Mode, Numa Node Set"
for comp in $available_computes; do

  # set aggregates
  comp_aggs=`grep $comp /tmp/th-agg-lst | cut -d "]" -f2 | xargs | sed "s/ /;/g"`

  # get vm resource info
  this_vms=$(ssh ${thisoverclouduser}@${comp}.ctlplane "sudo podman exec nova_libvirt virsh list | grep instance | awk '{print \$2}'")

  if [ -z "${this_vms}" ]; then
    echo "$comp, $comp_aggs, , , , ,"
  else
    for vm in $this_vms; do
    echo -n "$comp, $comp_aggs, "
    (
    ssh ${thisoverclouduser}@${comp}.ctlplane "sudo podman exec nova_libvirt virsh dumpxml $vm | grep 'nova:name\|nova:vcpus\|nova:memory' | cut -d '>' -f2 | cut -d '<' -f1 | xargs";
    ssh ${thisoverclouduser}@${comp}.ctlplane "sudo podman exec nova_libvirt virsh dumpxml $vm | grep 'memory mode' | grep -o 'mode.* ' | cut -d '=' -f2";
    ssh ${thisoverclouduser}@${comp}.ctlplane "sudo podman exec nova_libvirt virsh dumpxml $vm | grep 'memory mode' | grep -o 'nodeset.*/' | cut -d '=' -f2 | sed 's/\///g'";
    ) | xargs | sed "s/ /, /g"
    done
  fi
done

exit 0
