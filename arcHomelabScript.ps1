#Azure Arc Homelab healthcheck, startup, and shutdown script

#Requires -Version 5.1
#Requires -Modules GoogleCloud, Az.Compute, Az.ConnectedMachine

Param(
    [Parameter(Mandatory = $true)] [string] $googleProjectName,
    [Parameter(Mandatory = $true)] [string] $azureResourceGroupName
)

function Get-Status 
{
    $arc_homelab_resources = @()
    $jobs = @()

    #Parallelized calls for Azure VMs, Azre Arc Machines, and Google Cloud VMs
    Write-Host 'Getting Machine Statuses from Azure and Google Cloud...'
    $jobs += Start-ThreadJob {Get-GceInstance -Project $using:googleProjectName}
    $jobs += Start-ThreadJob {Get-AzVM -ResourceGroupName $using:azureResourceGroupName}
    $jobs += Start-ThreadJob {Get-AzConnectedMachine -ResourceGroupName $using:azureResourceGroupName}
    Wait-Job -Job $jobs | Out-Null

    $Global:gceinstances = Receive-Job -Job $jobs[0]
    $Global:azurevms = Receive-Job -Job $jobs[1]
    $Global:arcmachines = Receive-Job -Job $jobs[2]
    
    #Write-Host 'Getting VM status from Google Cloud...'
    #$gceinstances = Get-GceInstance -Project $googleProjectName
    foreach($gceinstance in $gceinstances)
    {
        $gceinstance | Add-Member -MemberType NoteProperty -Name 'HomelabResourceType' -Value 'GcVM'
        $gceinstance | Add-Member -MemberType NoteProperty -Name 'HomelabResourceStatus' -Value $gceinstance.status
        $arc_homelab_resources += $gceinstance
    }
    #Write-Host 'Done!' -ForegroundColor Green

    #Write-Host 'Getting VM status from Azure...'
    #$azurevms = Get-AzVM -ResourceGroupName $azureResourceGroupName
    foreach($azurevm in $azurevms)
    {
        $azurevmInstanceView = Get-AzVM -ResourceGroupName $azureResourceGroupName -Name $azurevm.Name -Status
        $azurevmInstanceView | Add-Member -MemberType NoteProperty -Name 'HomelabResourceType' -Value 'AzVM'
        $azurevmInstanceView | Add-Member -MemberType NoteProperty -Name 'HomelabResourceStatus' -Value $azurevmInstanceView.Statuses[1].Code
        $arc_homelab_resources += $azurevmInstanceView
    }
    #Write-Host 'Done!' -ForegroundColor Green

    #Write-host 'Getting Arc Machine Status from Azure...'
    #$arcmachines = Get-AzConnectedMachine -ResourceGroupName $azureResourceGroupName
    foreach ($arcmachine in $arcmachines)
    {
        $arcmachine | Add-Member -MemberType NoteProperty -Name 'HomelabResourceType' -Value 'ArcMachine'
        $arcmachine | Add-Member -MemberType NoteProperty -Name 'HomelabResourceStatus' -Value $arcmachine.Status
        $arc_homelab_resources += $arcmachine
    }
    Write-Host 'Done!' -ForegroundColor Green

    #From https://stackoverflow.com/questions/20705102/how-to-colorise-powershell-output-of-format-table and https://learn.microsoft.com/en-us/windows/console/console-virtual-terminal-sequences#span-idtextformattingspanspan-idtextformattingspanspan-idtextformattingspantext-formatting

    $arc_homelab_resources | Format-Table Name, @{
        Label = "Resource Type"
        Expression = {$_.HomelabResourceType}
        }, 
        @{
        Label = "Status"
        Expression =
        {
            switch ($_.HomelabResourceStatus)
            {
                'RUNNING' { $color = "32"; break }
                'PowerState/running' { $color = '32'; break }
                'Connected' { $color = "32"; break }
                default { $color = "31" }
            }
            $e = [char]27
            "$e[${color}m$($_.HomelabResourceStatus)${e}[0m"
        }
    }
}

function Start-VMs
{
    $jobs = @()
    Write-Host 'Starting Google Cloud VM(s)...'
    #$gceinstances = Get-GceInstance -Project $googleProjectName
    
    foreach($gceinstance in $gceinstances)
    {
            $jobs += Start-ThreadJob {Start-GceInstance $using:gceinstance}
    }

    #Write-Host 'Done!' -ForegroundColor Green

    Write-Host 'Starting Azure VM(s)...'
    #$azurevms = Get-AzVM -ResourceGroupName $azureResourceGroupName

    foreach($azurevm in $azurevms)
    {
        $azurevmname = $azurevm.Name
        $jobs += Start-ThreadJob {Start-AzVM -ResourceGroupName $using:azureResourceGroupName -Name $using:azurevmname}
    }
    
    #Write-Host 'Done!' -ForegroundColor Green
    Wait-Job -Job $jobs | Out-Null
    Write-Host 'Done!' -ForegroundColor Green

}

function Stop-VMs
{
    $jobs = @()
    Write-Host 'Stopping Google Cloud VM(s)...'
    #$gceinstances = Get-GceInstance -Project $googleProjectName
    foreach($gceinstance in $gceinstances)
    {
        $jobs += Start-ThreadJob {Stop-GceInstance $using:gceinstance}
    }
    #Write-Host 'Done!' -ForegroundColor Green

    Write-Host 'Stopping Azure VM(s)...'
    #$azurevms = Get-AzVM -ResourceGroupName $azureResourceGroupName
    foreach($azurevm in $azurevms)
    {
        $azurevmname = $azurevm.Name
        $jobs += Start-ThreadJob {Stop-AzVM -ResourceGroupName $using:azureResourceGroupName -Name $using:azurevmname -Force}
    }
    
    Wait-Job -Job $jobs | Out-Null
    Write-Host 'Done!' -ForegroundColor Green
}

 function Show-Menu 
 {
    Write-Host "1: Refresh Status"
    Write-Host "2: Start Google and Azure VMs"
    Write-Host "3: Stop Google and Azure VMs"
    Write-Host "4: Exit"
}

function Select-Menu 
{
    param (
        [int]$choice
    )
    switch ($choice) {
        1 { Get-Status }
        2 { Start-VMs }
        3 { Stop-VMs }
        4 { Write-Host "Exiting..."; exit }
        default { Write-Host "Invalid selection, please try again." }
    }
}

Get-Status
do 
{
    Show-Menu
    $choice = Read-Host "Enter your choice"
    Select-Menu -choice $choice
} 
while ($true)