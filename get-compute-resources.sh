#!/bin/bash
# expects:
# - TripleO based deployment of Train with containerised Nova
# - SSH access to Overcloud nodes via ControlPlane network
#
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
for comp in $available_computes; do 
  
  # set aggregates
  comp_aggs=`grep $comp /tmp/th-agg-lst | cut -d "]" -f2 | xargs | sed "s/ /;/g"`

  # get resource info
  cpu_dedicated_set=`ssh ${thisoverclouduser}@${comp}.ctlplane "sudo grep ^cpu_dedicated_set /var/lib/config-data/puppet-generated/nova_libvirt/etc/nova/nova.conf | cut -d '=' -f 2"` 
  vm_in_use_cpus=$(ssh ${thisoverclouduser}@${comp}.ctlplane "sudo podman exec nova_libvirt virsh list | grep instance | awk '{print \$2}' | xargs -I % sudo podman exec nova_libvirt virsh vcpuinfo % | grep ^CPU: | awk '{print \$2}' | sort") 
  numa_info=`ssh ${thisoverclouduser}@${comp}.ctlplane "numactl -H"` 
  hugepages_info=`ssh ${thisoverclouduser}@${comp}.ctlplane "grep ' HugePages' /sys/devices/system/node/node*/meminfo"`
  all_cpus_for_vms=`echo $cpu_dedicated_set | sed 's/,/\n/g' | sed 's/-/ /g' | xargs -n 2 seq` 
  
  count_all_cpus_for_vms=`echo $all_cpus_for_vms | wc -w` 
  count_vm_in_use_cpus=`echo $vm_in_use_cpus | wc -w` 
  count_total_free_cpus_for_vms=$(($count_all_cpus_for_vms-$count_vm_in_use_cpus)) 
  
  echo "$comp, $comp_aggs, Total CPUs for VMs, $count_all_cpus_for_vms" 
  echo "$comp, $comp_aggs, Total CPUs free for VMs, $count_total_free_cpus_for_vms" 
  
  # Calculate used vcpus per NUMA
  #numa_nodes=`numactl -H | grep available | cut -d ":" -f 2 | awk '{print $1}'` 
  numa_nodes=`echo "$numa_info" | grep available | cut -d ":" -f 2 | awk '{print $1}'` 
  if [ $numa_nodes -ge 2 ]; then 
    i=0 
    while [ $i -lt $numa_nodes ]; do 
      #declare "numa${i}_all_cpus=$(numactl -H | grep "node $i cpus" | cut -d ":" -f 2)" 
      declare "numa${i}_all_cpus=$(echo "$numa_info" | grep "node $i cpus" | cut -d ":" -f 2)" 
      declare "numa${i}_for_vms" 
      declare "numa${i}_used" 
      varname=numa${i}_all_cpus 
      for c in ${!varname}; do  
        # echo -n $c 
        for a in $all_cpus_for_vms; do  
          if [ $c == $a ]; then 
            vmcpulist=numa${i}_for_vms 
            declare "numa${i}_for_vms=${!vmcpulist} $c";  
            # echo -n " is for VMs" 
          fi 
        done 
  
        for u in $vm_in_use_cpus; do  
          if [ $c == $u ]; then 
            usedcpulist=numa${i}_used 
            declare "numa${i}_used=${!usedcpulist} $c";  
            # echo -n " and is in use (equals $u)" 
          fi 
        done 
        #echo 
      done 
  
      vmcpulist=numa${i}_for_vms 
      usedcpulist=numa${i}_used 
      echo "$comp, $comp_aggs, NUMA $i CPUs for VMs, `echo ${!vmcpulist} | wc -w`" 
      #echo "$comp, $comp_aggs, NUMA $i CPUs used by VMs, `echo ${!usedcpulist} | wc -w`" 
      echo "$comp, $comp_aggs, NUMA $i CPUs free for VMs, $((`echo ${!vmcpulist} | wc -w`-`echo ${!usedcpulist} | wc -w`))" 
      #echo "$comp, $comp_aggs, NUMA $i RAM free, `numactl -H | grep "node $i free" | cut -d ":" -f 2`" 
      echo "$comp, $comp_aggs, NUMA $i HugePages Total, `echo "$hugepages_info" | grep "Node $i HugePages_Total" | cut -d ":" -f 3 | xargs`" 
      echo "$comp, $comp_aggs, NUMA $i HugePages Free, `echo "$hugepages_info" | grep "Node $i HugePages_Free" | cut -d ":" -f 3 | xargs`" 
  
      declare "numa${i}_for_vms=" 
      declare "numa${i}_used=" 
  
      i=$(($i+1)) 
    done 
  fi 
  
done 

exit 0
