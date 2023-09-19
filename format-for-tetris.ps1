<#
  This script takes a CSV formatted input containing a list
  of OpenStack computes, the Aggregate(s) they belong to,
  and the compute resource allocations for the VMs on that
  compute, including NUMA node set. It then formats that data
  into a tetris style CSV format so the output can then be 
  copied into a spreadsheet to show the per NUMA vCPU usage
  by compute node.

  This script is intended to be used in an environment where
  CPU pinning is used for the instances (hw:cpu_policy='dedicated')
  and VMs are scheduled within a single NUMA node only.

  The input data can be generated with this script:
  https://github.com/tmatofa/osp-reports/blob/main/get-instance-numa.sh

  Ensure $slots and $numas is set according to your environment

  NOTE: This script is provided without any warranties or
  support.
#>
$slots = 46   # Usable vCPU per NUMA on the computes 
$numas = (0,1)

# data from openstack cli script 
# example:
<#
$data = @"
Compute, Aggregates, VM, vRAM (MiB), vCPU, Numa Mode, Numa Node Set
compute1, agg1, vm1, 24576, 6, strict, 0
compute1, agg1, vm2, 24576, 6, strict, 0
compute1, agg1, vm3, 24576, 6, strict, 1
compute2, agg1, vm4, 24576, 6, strict, 1
compute3, agg2, vm5, 24576, 6, strict, 0
compute4, agg2, vm6, 24576, 6, strict, 0
"@ | ConvertFrom-Csv
#>
$data = @"
Compute, Aggregates, VM, vRAM (MiB), vCPU, Numa Mode, Numa Node Set
"@ | ConvertFrom-Csv

# Write Headings
Write-Host -NoNewLine ",NUMA,"
foreach ($numa in $numas){
    $counter = 1
    while ($counter -le $slots) {
        Write-Host -NoNewLine "$numa,"
        $counter++
    }
    Write-Host -NoNewLine "$numa,"
}
Write-Host ""

Write-Host -NoNewLine "Compute,Aggregate(s),"
foreach ($numa in $numas){
    $counter = 1
    while ($counter -le $slots) {
        Write-Host -NoNewLine "$counter,"
        $counter++
    }
    Write-Host -NoNewLine "COUNT FREE,"
}
Write-Host ""


# Write VM usage
$comps = $data | Sort Aggregates,Compute  | Select -Expand Compute -Unique
foreach ($comp in $comps) {
    $thisComp = $data | ?{$_.Compute -eq $comp}
    Write-Host -NoNewLine "$comp,$($thisComp[0].Aggregates),"
    foreach ($numa in $numas){
        $thisNuma = $thisComp | ?{$_.'Numa Node Set' -eq $numa}
        $cpuCounter = 0

        foreach ($vm in $thisNuma){
            $cpu = 1
            while ($cpu -le $vm.vCPU){
                Write-Host -NoNewLine "$($vm.VM),"
                $cpu++
                $cpuCounter++
            }
        }
        $numaFree = $slots - $cpuCounter
        $fillers=1
        while ($fillers -le $numaFree){
            Write-Host -NoNewLine "x,"
            $fillers++
        }
        Write-Host -NoNewLine "$numaFree,"
    }
    Write-Host ""
}
