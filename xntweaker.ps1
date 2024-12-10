# Define the paths
$BlueStacksHome = (Get-ItemProperty "HKLM:\SOFTWARE\BlueStacks_nxt").UserDefinedDir
$BlueStacksInstallDir = (Get-ItemProperty "HKLM:\SOFTWARE\BlueStacks_nxt").InstallDir
$DesktopPath = [Environment]::GetFolderPath('Desktop')
$BlueStacksConfig = Join-Path $BlueStacksHome "bluestacks.conf"
$BlueStacksEngine = Join-Path $BlueStacksHome "Engine"
$InstanceManagerProcess = "HD-MultiInstanceManager"
$BlueStacksServiceProcess = "BstkSVC"

# Define the possible instances and their colors
$Instances = @{
    "Rvc64" = @{ Color = "DarkRed"; SubColor = "Red" }
    "Pie64" = @{ Color = "DarkGreen"; SubColor = "Green" }
    "Nougat64" = @{ Color = "DarkBlue"; SubColor = "Blue" }
}

# Function to log messages
function Log-Message {
    param([string]$message)
    Write-Host $message
    Add-Content -Path "xntweaker.log" -Value "$(Get-Date) - $message"
}

# Function to get available instances and their sub-instances
function Get-AvailableInstances {
    $availableInstances = @{}
    foreach ($instance in $Instances.Keys) {
        $instancePath = Join-Path $BlueStacksEngine $instance
        if (Test-Path $instancePath) {
            $subInstances = Get-ChildItem $BlueStacksEngine -Directory | Where-Object { $_.Name -match "^${instance}(_\d+)?$" } | Select-Object -ExpandProperty Name
            $availableInstances[$instance] = @{
                "Instances" = @($subInstances)
                "MasterInstance" = $instance
                "Color" = $Instances[$instance].Color
                "SubColor" = $Instances[$instance].SubColor
            }
            foreach ($subInstance in $subInstances) {
                if ($subInstance -ne $instance) {
                    $availableInstances[$subInstance] = @{
                        "Instances" = @($subInstance)
                        "MasterInstance" = $instance
                        "Color" = $Instances[$instance].SubColor
                        "SubColor" = $Instances[$instance].SubColor
                    }
                }
            }
        }
    }
    return $availableInstances
}

function Create-BlueStacksShortcut {
    # Define the shortcut target and path
    $ShortcutTargetValue = "$BlueStacksInstallDir\HD-Player.exe --instance $selectedInstance"
    $ShortcutPath = "$DesktopPath\$selectedInstance.lnk"

    # Create a WScript Shell object
    $WScriptShell = New-Object -ComObject WScript.Shell

    # Create the shortcut
    $Shortcut = $WScriptShell.CreateShortcut($ShortcutPath)

    # Set the shortcut properties
    $Shortcut.TargetPath = "$BlueStacksInstallDir\HD-Player.exe"
    $Shortcut.Arguments = "--instance $selectedInstance"
    $Shortcut.WorkingDirectory = $BlueStacksInstallDir
    $Shortcut.Save()

    Write-Host "Desktop Shortcut created: $selectedInstance"
}

function Manage-BlueStacksProcess {
    # Array of process names to manage
    $processes = @($InstanceManagerProcess, $BlueStacksServiceProcess)

    foreach ($processName in $processes) {
        # Check if the process is running
        $process = Get-Process -Name $processName -ErrorAction SilentlyContinue

        if ($process) {
            # Display message if the process is running
            Write-Output "$processName is running."

            # Stop the process
            Stop-Process -Name $processName -Force

            # Confirm the process has been stopped
            Write-Output "$processName has been stopped."
        } else {
            # Display message if the process is not running
            Write-Output "$processName is not running."
        }
    }
}


# Function to modify instance config files
function Modify-InstanceConfigFiles {
    param($instancePath, $masterInstancePath, $action)
    
    $configFiles = @("Android.bstk.in", "$($masterInstancePath.Split('\')[-1]).bstk")
    foreach ($file in $configFiles) {
        $filePath = Join-Path $masterInstancePath $file
        if (Test-Path $filePath) {
            $content = Get-Content $filePath -Raw
            if ($action -eq "root") {
                $content = $content -replace '(location="fastboot\.vdi".*?type=")Readonly(")', '$1Normal$2'
                $content = $content -replace '(location="Root\.vhd".*?type=")Readonly(")', '$1Normal$2'
            } else {
                $content = $content -replace '(location="fastboot\.vdi".*?type=")Normal(")', '$1Readonly$2'
                $content = $content -replace '(location="Root\.vhd".*?type=")Normal(")', '$1Readonly$2'
            }
            Set-Content -Path $filePath -Value $content
            Log-Message "$action`ed $file for $($masterInstancePath.Split('\')[-1])"
        } else {
            Log-Message "Warning: Config file $file not found for $($masterInstancePath.Split('\')[-1])"
        }
    }
}

# Function to modify BlueStacks config file
function Modify-BlueStacksConfig {
    param($instance, $masterInstance, $action)
    
    $content = Get-Content $BlueStacksConfig -Raw
    $rootingValue = if ($action -eq "root") { "1" } else { "0" }
    $content = $content -replace "(bst\.feature\.rooting=)""?\d""?", "`$1""$rootingValue"""
    $content = $content -replace "(bst\.instance\.$masterInstance\.enable_root_access=)""?\d""?", "`$1""$rootingValue"""
    
    if ($instance -ne $masterInstance) {
        $content = $content -replace "(bst\.instance\.$instance\.enable_root_access=)""?\d""?", "`$1""$rootingValue"""
    }
    
    $content = $content.TrimEnd()
    Set-Content -Path $BlueStacksConfig -Value $content
    Log-Message "$action`ed BlueStacks config for $instance"
}

function Clear-AndShowTitle {
    Clear-Host
    Write-Host "=== BlueStacks Root Manager ===" -ForegroundColor Cyan
    Write-Host ""
}

function Show-SelectedInstance {
    param($selectedInstance, $masterInstance, $color)
    Clear-AndShowTitle
    Write-Host "Selected instance: $selectedInstance (Master: $masterInstance)" -ForegroundColor $color
    Write-Host ""
}

function Show-Menu {
    param($availableInstances)
    
    while ($true) {
        Clear-AndShowTitle
        $index = 1
        $menuItems = @{}

        foreach ($master in $availableInstances.Keys | Where-Object { $_ -eq $availableInstances[$_].MasterInstance }) {
            Write-Host "`n$index. $master (Master Instance)" -ForegroundColor $availableInstances[$master].Color
            $menuItems[$index] = @{
                Instance = $master
                Master = $master
                Color = $availableInstances[$master].Color
            }
            $index++

            foreach ($sub in $availableInstances[$master].Instances | Where-Object { $_ -ne $master }) {
                Write-Host "   $index. $sub (Sub Instance)" -ForegroundColor $availableInstances[$master].SubColor
                $menuItems[$index] = @{
                    Instance = $sub
                    Master = $master
                    Color = $availableInstances[$master].SubColor
                }
                $index++
            }
        }

        Write-Host "`n$index. Refresh Instances" -ForegroundColor Cyan
        $menuItems[$index] = @{ Instance = "Refresh"; Master = "Refresh"; Color = "Cyan" }
        $index++

        Write-Host "`n0. Exit" -ForegroundColor Yellow

        Write-Host "`nSelect an instance, refresh, or exit:"
        $selection = Read-Host "Enter the number"
        
        if ($selection -eq "0") {
            return @{ Instance = "Exit"; Master = "Exit"; Color = "Yellow" }
        } elseif ($menuItems.ContainsKey([int]$selection)) {
            return $menuItems[[int]$selection]
        } else {
            Write-Host "Invalid selection. Please try again." -ForegroundColor Red
            Start-Sleep -Seconds 1
        }
    }
}


function Show-ActionMenu {
    param($selectedInstance, $masterInstance, $color)
    while ($true) {
        Show-SelectedInstance $selectedInstance $masterInstance $color
        Write-Host "1. Root" -ForegroundColor Green
        Write-Host "2. Unroot" -ForegroundColor Red
        Write-Host "0. Return to Main Menu" -ForegroundColor Yellow
        $action = Read-Host "Enter the number"
        
        switch ($action) {
            "1" { return "root" }
            "2" { return "unroot" }
            "0" { return "back" }
            default {
                Write-Host "Invalid action. Please try again." -ForegroundColor Red
                Start-Sleep -Seconds 1
            }
        }
    }
}

# Main script loop
while ($true) {
    Clear-AndShowTitle
    $availableInstances = Get-AvailableInstances
    $selectedInstanceInfo = Show-Menu $availableInstances

    if ($selectedInstanceInfo.Instance -eq "Exit") {
        break
    }

    if ($selectedInstanceInfo.Instance -eq "Refresh") {
        Log-Message "Refreshing available instances..."
        $availableInstances = Get-AvailableInstances
        continue
    }
    

    $selectedInstance = $selectedInstanceInfo.Instance
    $masterInstance = $selectedInstanceInfo.Master
    $instancePath = Join-Path $BlueStacksEngine $selectedInstance
    $masterInstancePath = Join-Path $BlueStacksEngine $masterInstance

    Log-Message "Selected instance: $selectedInstance (Master: $masterInstance)"

    # Show action menu (root/unroot)
    $action = Show-ActionMenu $selectedInstance $masterInstance $selectedInstanceInfo.Color

    if ($action -eq "back") {
        continue
    }

    # Perform the action
    Show-SelectedInstance $selectedInstance $masterInstance $selectedInstanceInfo.Color
    Write-Host "$($action.ToUpper()) process started for $selectedInstance..." -ForegroundColor Cyan
    
    if ($action -eq "root") {
        Manage-BlueStacksProcess
    }

    # Modify instance config files
    Modify-InstanceConfigFiles $instancePath $masterInstancePath $action

    # Modify BlueStacks config
    Modify-BlueStacksConfig $selectedInstance $masterInstance $action

    if ($action -eq "root") {
        Create-BlueStacksShortcut
    }

    Log-Message "$($action.ToUpper()) process completed for $selectedInstance"
    Write-Host "$($action.ToUpper()) process completed for $selectedInstance" -ForegroundColor Green

    Write-Host "`nProcess completed. Press Enter to continue..."
    Read-Host
}

Write-Host "Exiting script. Press Enter to close..." -ForegroundColor Yellow
Read-Host