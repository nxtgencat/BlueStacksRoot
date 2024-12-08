# Define the paths
$BlueStacksHome = "C:\ProgramData\BlueStacks_nxt"
$BlueStacksConfig = Join-Path $BlueStacksHome "bluestacks.conf"
$BlueStacksEngine = Join-Path $BlueStacksHome "Engine"

# Define the possible instances
$Instances = @("Rvc64", "Pie64", "Nougat64")

# Function to log messages
function Log-Message {
    param([string]$message)
    Write-Host $message
    Add-Content -Path "BlueStacks_Root_Log.txt" -Value "$(Get-Date) - $message"
}

# Function to get available instances and their sub-instances
function Get-AvailableInstances {
    $availableInstances = @{}
    foreach ($instance in $Instances) {
        $instancePath = Join-Path $BlueStacksEngine $instance
        if (Test-Path $instancePath) {
            $subInstances = Get-ChildItem $BlueStacksEngine -Directory | Where-Object { $_.Name -match "^${instance}(_\d+)?$" } | Select-Object -ExpandProperty Name
            $availableInstances[$instance] = @{
                "Instances" = @($subInstances)
                "MasterInstance" = $instance
            }
            foreach ($subInstance in $subInstances) {
                if ($subInstance -ne $instance) {
                    $availableInstances[$subInstance] = @{
                        "Instances" = @($subInstance)
                        "MasterInstance" = $instance
                    }
                }
            }
        }
    }
    return $availableInstances
}

# Function to display menu and get user selection
function Show-Menu {
    param($availableInstances)
    $index = 1
    $menuItems = @{}

    foreach ($master in $availableInstances.Keys | Where-Object { $_ -eq $availableInstances[$_].MasterInstance }) {
        Write-Host "`n$index. $master (Master Instance)"
        $menuItems[$index] = $master
        $index++

        foreach ($sub in $availableInstances[$master].Instances | Where-Object { $_ -ne $master }) {
            Write-Host "   $index. $sub (Sub Instance)"
            $menuItems[$index] = $sub
            $index++
        }
    }

    Write-Host "`nSelect an instance to root:"
    $selection = Read-Host "Enter the number"
    
    if ($menuItems.ContainsKey([int]$selection)) {
        return $menuItems[[int]$selection]
    } else {
        return $null
    }
}

# Function to modify instance config files
function Modify-InstanceConfigFiles {
    param($instancePath, $masterInstancePath)
    
    $configFiles = @("Android.bstk.in", "$($masterInstancePath.Split('\')[-1]).bstk")
    foreach ($file in $configFiles) {
        $filePath = Join-Path $masterInstancePath $file
        if (Test-Path $filePath) {
            $content = Get-Content $filePath -Raw
            $content = $content -replace '(location="fastboot\.vdi".*?type=")Readonly(")', '$1Normal$2'
            $content = $content -replace '(location="Root\.vhd".*?type=")Readonly(")', '$1Normal$2'
            Set-Content -Path $filePath -Value $content
            Log-Message "Modified $file for $($masterInstancePath.Split('\')[-1])"
        } else {
            Log-Message "Warning: Config file $file not found for $($masterInstancePath.Split('\')[-1])"
        }
    }
}

# Function to modify BlueStacks config file
function Modify-BlueStacksConfig {
    param($instance, $masterInstance)
    
    $content = Get-Content $BlueStacksConfig -Raw
    $content = $content -replace '(bst\.feature\.rooting=")0(")', '${1}1${2}'
    
    $content = $content -replace "(bst\.instance\.$masterInstance\.enable_root_access=)""?0""?", '$1"1"'
    if ($instance -ne $masterInstance) {
        $content = $content -replace "(bst\.instance\.$instance\.enable_root_access=)""?0""?", '$1"1"'
    }
    
    Set-Content -Path $BlueStacksConfig -Value $content
    Log-Message "Modified BlueStacks config for $instance"
}

# Main script
Log-Message "Script started"

$availableInstances = Get-AvailableInstances
$selectedInstance = Show-Menu $availableInstances

if ($null -eq $selectedInstance) {
    Log-Message "Error: Invalid selection. Exiting script."
    Write-Host "Invalid selection. Press Enter to exit..."
    Read-Host
    exit
}

$masterInstance = $availableInstances[$selectedInstance].MasterInstance
$instancePath = Join-Path $BlueStacksEngine $selectedInstance
$masterInstancePath = Join-Path $BlueStacksEngine $masterInstance

Log-Message "Selected instance: $selectedInstance (Master: $masterInstance)"

# Modify instance config files
Modify-InstanceConfigFiles $instancePath $masterInstancePath

# Modify BlueStacks config
Modify-BlueStacksConfig $selectedInstance $masterInstance

Log-Message "Rooting process completed for $selectedInstance"
Write-Host "`nRooting process completed. Press Enter to exit..."
Read-Host

