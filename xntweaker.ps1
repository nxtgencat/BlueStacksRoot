# Define the paths
$BlueStacksHome = (Get-ItemProperty "HKLM:\SOFTWARE\BlueStacks_nxt").UserDefinedDir
$BlueStacksConfig = Join-Path $BlueStacksHome "bluestacks.conf"
$BlueStacksEngine = Join-Path $BlueStacksHome "Engine"

# Define the possible instances
$Instances = @("Rvc64", "Pie64", "Nougat64")

# Function to log messages
function Log-Message {
    param([string]$message)
    Write-Host $message
    Add-Content -Path "xntweaker.log" -Value "$(Get-Date) - $message"
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
    
    # Trim trailing empty lines
    $content = $content.TrimEnd()
    
    Set-Content -Path $BlueStacksConfig -Value $content
    Log-Message "Modified BlueStacks config for $instance"
}

function Unmodify-InstanceConfigFiles {
    param($instancePath, $masterInstancePath)
    
    $configFiles = @("Android.bstk.in", "$($masterInstancePath.Split('\')[-1]).bstk")
    foreach ($file in $configFiles) {
        $filePath = Join-Path $masterInstancePath $file
        if (Test-Path $filePath) {
            $content = Get-Content $filePath -Raw
            # Reverse the modification for 'Readonly' to 'Normal'
            $content = $content -replace '(location="fastboot\.vdi".*?type=")Normal(")', '$1Readonly$2'
            $content = $content -replace '(location="Root\.vhd".*?type=")Normal(")', '$1Readonly$2'
            Set-Content -Path $filePath -Value $content
            Log-Message "Unmodified $file for $($masterInstancePath.Split('\')[-1])"
        } else {
            Log-Message "Warning: Config file $file not found for $($masterInstancePath.Split('\')[-1])"
        }
    }
}

function Unmodify-BlueStacksConfig {
    param($instance, $masterInstance)
    
    $content = Get-Content $BlueStacksConfig -Raw
    # Reverse the modification for rooting and enable root access
    $content = $content -replace '(bst\.feature\.rooting=")1(")', '${1}0${2}'
    $content = $content -replace "(bst\.instance\.$masterInstance\.enable_root_access=)""?1""?", '$1"0"'
    
    if ($instance -ne $masterInstance) {
        $content = $content -replace "(bst\.instance\.$instance\.enable_root_access=)""?1""?", '$1"0"'
    }
    
    # Trim trailing empty lines
    $content = $content.TrimEnd()
    
    Set-Content -Path $BlueStacksConfig -Value $content
    Log-Message "Unmodified BlueStacks config for $instance"
}


function Clear-AndShowTitle {
    Clear-Host
    Write-Host "=== BlueStacks Root Manager ===" -ForegroundColor Cyan
    Write-Host ""
}

# Function to display menu and get user selection
function Show-Menu {
    param($availableInstances)
    
    while ($true) {
        Clear-AndShowTitle
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

        Write-Host "`n0. Exit"

        Write-Host "`nSelect an instance or exit:"
        $selection = Read-Host "Enter the number"
        
        if ($selection -eq "0") {
            return "Exit"
        } elseif ($menuItems.ContainsKey([int]$selection)) {
            return $menuItems[[int]$selection]
        } else {
            Write-Host "Invalid selection. Please try again."
            Start-Sleep -Seconds 2
        }
    }
}

# Function to display action menu (root/unroot)
function Show-ActionMenu {
    while ($true) {
        Write-Host "`n1. Root"
        Write-Host "2. Unroot"
        Write-Host "0. Return to Main Menu"
        $action = Read-Host "Enter the number"
        
        switch ($action) {
            "1" { return "root" }
            "2" { return "unroot" }
            "0" { return "back" }
            default {
                Write-Host "Invalid action. Please try again."
            }
        }
    }
}

# Main script loop
while ($true) {
    Clear-AndShowTitle
    $availableInstances = Get-AvailableInstances
    $selectedInstance = Show-Menu $availableInstances

    if ($selectedInstance -eq "Exit") {
        break
    }

    $masterInstance = $availableInstances[$selectedInstance].MasterInstance
    $instancePath = Join-Path $BlueStacksEngine $selectedInstance
    $masterInstancePath = Join-Path $BlueStacksEngine $masterInstance

    Log-Message "Selected instance: $selectedInstance (Master: $masterInstance)"

    # Show action menu (root/unroot)
    $action = Show-ActionMenu

    if ($action -eq "back") {
        continue
    }

    # Perform the action
    if ($action -eq "root") {
        # Modify instance config files
        Modify-InstanceConfigFiles $instancePath $masterInstancePath

        # Modify BlueStacks config
        Modify-BlueStacksConfig $selectedInstance $masterInstance

        Log-Message "Rooting process completed for $selectedInstance"
    } elseif ($action -eq "unroot") {
        # Modify instance config files
        Unmodify-InstanceConfigFiles $instancePath $masterInstancePath

        # Modify BlueStacks config
        Unmodify-BlueStacksConfig $selectedInstance $masterInstance

        Log-Message "Unrooting process completed for $selectedInstance"
    }

    Write-Host "`nProcess completed. Press Enter to continue..."
    Read-Host
}

Write-Host "Exiting script. Press Enter to close..."
Read-Host

