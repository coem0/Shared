#==============================================================================
# Dell Bloatware Remediation Script for Intune
# This script removes Dell bloatware from the system
# Exit Code 0 = Success
# Exit Code 1 = Failure
#==============================================================================

# Function to uninstall apps via various methods
function UninstallAppFull {
    param (
        [string]$appName
    )
    
    Write-Output "Attempting to uninstall: $appName"
    
    # Try Win32_Product (slow but thorough)
    try {
        $product = Get-CimInstance -ClassName Win32_Product -Filter "Name LIKE '%$appName%'" -ErrorAction SilentlyContinue
        if ($product) {
            $product | Invoke-CimMethod -MethodName Uninstall | Out-Null
            Write-Output "Uninstalled $appName via Win32_Product"
            return $true
        }
    }
    catch {
        Write-Output "Win32_Product method failed for $appName : $_"
    }
    
    # Try registry-based uninstall
    try {
        $registryPaths = @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
            "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
        )
        
        foreach ($path in $registryPaths) {
            $apps = Get-ItemProperty -Path $path -ErrorAction SilentlyContinue | 
                    Where-Object { $_.DisplayName -match [regex]::Escape($appName) }
            
            foreach ($app in $apps) {
                $uninstallString = $app.QuietUninstallString
                if (-not $uninstallString) {
                    $uninstallString = $app.UninstallString
                }
                
                if ($uninstallString) {
                    if ($uninstallString -match "msiexec") {
                        if ($uninstallString -match "/I") {
                            $uninstallString = $uninstallString -replace "/I", "/X"
                        }
                        $uninstallString += " /quiet /norestart"
                        Start-Process "cmd.exe" -ArgumentList "/c $uninstallString" -Wait -NoNewWindow -ErrorAction SilentlyContinue
                    }
                    else {
                        $uninstallParts = $uninstallString -split ' ', 2
                        $uninstallExe = $uninstallParts[0].Trim('"')
                        $uninstallArgs = if ($uninstallParts.Count -gt 1) { $uninstallParts[1] } else { "" }
                        
                        if ($uninstallArgs -notmatch "/S|/silent|/quiet") {
                            $uninstallArgs += " /S /silent /quiet"
                        }
                        
                        Start-Process -FilePath $uninstallExe -ArgumentList $uninstallArgs -Wait -NoNewWindow -ErrorAction SilentlyContinue
                    }
                    Write-Output "Executed uninstall string for $appName"
                    return $true
                }
            }
        }
    }
    catch {
        Write-Output "Registry uninstall method failed for $appName : $_"
    }
    
    return $false
}

# Get manufacturer
$manufacturer = (Get-WmiObject -Class Win32_ComputerSystem).Manufacturer

# Only run on Dell devices
if ($manufacturer -notlike "*Dell*") {
    Write-Output "Not a Dell device. Exiting."
    Exit 0
}

Write-Output "Dell device detected. Starting bloatware removal..."

# Define apps to remove (you can comment out apps you want to keep)
$UninstallPrograms = @(
    "Dell Optimizer"
    "Dell Power Manager"
    "DellOptimizerUI"
    #"Dell SupportAssist OS Recovery"
    #"Dell SupportAssist"
    "Dell Optimizer Service"
    "Dell Optimizer Core"
    "DellInc.PartnerPromo"
    "DellInc.DellOptimizer"
    #"DellInc.DellCommandUpdate"
    "DellInc.DellPowerManager"
    "DellInc.DellDigitalDelivery"
    #"DellInc.DellSupportAssistforPCs"
    #"Dell Command | Update"
    #"Dell Command | Update for Windows Universal"
    #"Dell Command | Update for Windows 10"
    "Dell Command | Power Manager"
    "Dell Digital Delivery Service"
    "Dell Digital Delivery"
    "Dell Peripheral Manager"
    "Dell Power Manager Service"
    #"Dell SupportAssist Remediation"
    "SupportAssist Recovery Assistant"
    #"Dell SupportAssist OS Recovery Plugin for Dell Update"
    "Dell SupportAssistAgent"
    "Dell Update - SupportAssist Update Plugin"
    #"Dell Core Services"
    "Dell Pair"
    "Dell Display Manager 2"
    "Dell Display Manager 2.0"
    "Dell Display Manager 2.1"
    "Dell Display Manager 2.2"
    "Dell Display Manager 2.3"
    "Dell Universal Receiver Control Panel"
    "Dell PremierColor"
    
    # Add more apps here if needed:
    # "AppName"
)

# Apps to ignore (comment out to include in removal, or add apps you want to keep)
$appsToIgnore = @(
    # "Dell Command | Update"  # Example: uncomment to keep this app
)

# Filter out ignored apps
$UninstallPrograms = $UninstallPrograms | Where-Object { $appsToIgnore -notcontains $_ }

$successCount = 0
$failCount = 0

# Remove AppX packages
foreach ($app in $UninstallPrograms) {
    try {
        # Remove provisioned packages
        $provisionedPkg = Get-AppxProvisionedPackage -Online | Where-Object DisplayName -like $app -ErrorAction SilentlyContinue
        if ($provisionedPkg) {
            Remove-AppxProvisionedPackage -Online -PackageName $provisionedPkg.PackageName -ErrorAction Stop
            Write-Output "Removed provisioned package: $app"
            $successCount++
        }
        
        # Remove installed AppX packages for all users
        $appxPkg = Get-AppxPackage -AllUsers -Name $app -ErrorAction SilentlyContinue
        if ($appxPkg) {
            Remove-AppxPackage -Package $appxPkg.PackageFullName -AllUsers -ErrorAction Stop
            Write-Output "Removed AppX package: $app"
            $successCount++
        }
    }
    catch {
        Write-Output "Failed to remove AppX package $app : $_"
        $failCount++
    }
}

# Remove standard programs via registry
foreach ($app in $UninstallPrograms) {
    try {
        $registryPaths = @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
            "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
        )
        
        $matchingPackages = @()
        
        foreach ($registryPath in $registryPaths) {
            $packages = Get-ItemProperty -Path $registryPath -ErrorAction SilentlyContinue | 
                        Where-Object { $_.DisplayName -match [regex]::Escape($app) }
            $matchingPackages += $packages
        }
        
        if ($matchingPackages.Count -eq 0) {
            Write-Output "No installed packages found for: $app"
            continue
        }
        
        foreach ($package in $matchingPackages) {
            $displayName = $package.DisplayName
            $uninstallString = $package.QuietUninstallString
            if (-not $uninstallString) {
                $uninstallString = $package.UninstallString
            }
            
            if ($uninstallString) {
                try {
                    if ($uninstallString -match "msiexec") {
                        if ($uninstallString -match "/I") {
                            $uninstallString = $uninstallString -replace "/I", "/X"
                        }
                        if ($uninstallString -notmatch "/quiet") {
                            $uninstallString += " /quiet /norestart"
                        }
                        Start-Process "cmd.exe" -ArgumentList "/c $uninstallString" -Wait -NoNewWindow
                    }
                    else {
                        $uninstallParts = $uninstallString -split ' ', 2
                        $uninstallExe = $uninstallParts[0].Trim('"')
                        $uninstallArgs = if ($uninstallParts.Count -gt 1) { $uninstallParts[1] } else { "" }
                        
                        if ($uninstallArgs -notmatch "/S|/silent|/quiet") {
                            $uninstallArgs += " /S /silent /quiet"
                        }
                        
                        Start-Process -FilePath $uninstallExe -ArgumentList $uninstallArgs -Wait -NoNewWindow
                    }
                    Write-Output "Uninstalled: $displayName"
                    $successCount++
                }
                catch {
                    Write-Output "Failed to uninstall $displayName : $_"
                    $failCount++
                }
            }
        }
    }
    catch {
        Write-Output "Error processing $app : $_"
        $failCount++
    }
}

# Manual removal of specific Dell applications
Write-Output "Performing targeted removal of specific Dell applications..."

# Dell Optimizer Core
try {
    $dellOpt = Get-ChildItem -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall, HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall -ErrorAction SilentlyContinue | 
               Get-ItemProperty | Where-Object { $_.DisplayName -like "Dell*Optimizer*Core" }
    
    foreach ($opt in $dellOpt) {
        if ($opt.UninstallString) {
            cmd.exe /c "$($opt.UninstallString) -silent"
            Write-Output "Uninstalled Dell Optimizer Core"
            $successCount++
        }
    }
}
catch {
    Write-Warning "Failed to uninstall Dell Optimizer Core: $_"
    $failCount++
}

# Dell Optimizer
try {
    $dellOpti = Get-ChildItem -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall, HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall -ErrorAction SilentlyContinue | 
               Get-ItemProperty | Where-Object { $_.DisplayName -like "Dell Optimizer" }
    
    foreach ($opti in $dellOpti) {
        if ($opti.UninstallString) {
            cmd.exe /c "$($opti.UninstallString) -silent"
            Write-Output "Uninstalled Dell Optimizer"
            $successCount++
        }
    }
}
catch {
    Write-Warning "Failed to uninstall Dell Optimizer: $_"
    $failCount++
}

# Dell SupportAssist Remediation
#try {
#    $dellSA = Get-ChildItem -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall, HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall -ErrorAction SilentlyContinue | 
#              Get-ItemProperty | Where-Object { $_.DisplayName -match "Dell SupportAssist Remediation" }
#    
#    foreach ($sa in $dellSA) {
#        if ($sa.QuietUninstallString) {
#            cmd.exe /c $sa.QuietUninstallString
#            Write-Output "Uninstalled Dell SupportAssist Remediation"
#            $successCount++
#        }
#    }
#}
#catch {
#    Write-Warning "Failed to uninstall Dell SupportAssist Remediation: $_"
#    $failCount++
#}

# Dell SupportAssist OS Recovery Plugin
#try {
#    $dellPlugin = Get-ChildItem -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall, HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall -ErrorAction SilentlyContinue | 
#                  Get-ItemProperty | Where-Object { $_.DisplayName -match "Dell SupportAssist OS Recovery Plugin for Dell Update" }
#    
#    foreach ($plugin in $dellPlugin) {
#        if ($plugin.QuietUninstallString) {
#            cmd.exe /c $plugin.QuietUninstallString
#            Write-Output "Uninstalled Dell SupportAssist OS Recovery Plugin"
#            $successCount++
#        }
#    }
#}
#catch {
#    Write-Warning "Failed to uninstall Dell SupportAssist OS Recovery Plugin: $_"
#    $failCount++
#}

# Dell Display Manager
try {
    $dellDM = Get-ChildItem -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall, HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall -ErrorAction SilentlyContinue | 
              Get-ItemProperty | Where-Object { $_.DisplayName -like "Dell*Display*Manager*" }
    
    foreach ($dm in $dellDM) {
        if ($dm.UninstallString) {
            cmd.exe /c "$($dm.UninstallString) /S"
            Write-Output "Uninstalled Dell Display Manager"
            $successCount++
        }
    }
}
catch {
    Write-Warning "Failed to uninstall Dell Display Manager: $_"
    $failCount++
}

# Dell Peripheral Manager (path-based removal)
if (Test-Path "C:\Program Files\Dell\Dell Peripheral Manager\Uninstall.exe") {
    try {
        Start-Process -FilePath "C:\Program Files\Dell\Dell Peripheral Manager\Uninstall.exe" -ArgumentList "/S" -Wait -NoNewWindow
        Write-Output "Uninstalled Dell Peripheral Manager"
        $successCount++
    }
    catch {
        Write-Warning "Failed to uninstall Dell Peripheral Manager: $_"
        $failCount++
    }
}

# Dell Pair (path-based removal)
if (Test-Path "C:\Program Files\Dell\Dell Pair\Uninstall.exe") {
    try {
        Start-Process -FilePath "C:\Program Files\Dell\Dell Pair\Uninstall.exe" -ArgumentList "/S" -Wait -NoNewWindow
        Write-Output "Uninstalled Dell Pair"
        $successCount++
    }
    catch {
        Write-Warning "Failed to uninstall Dell Pair: $_"
        $failCount++
    }
}

# Summary
Write-Output "=========================================="
Write-Output "Remediation Summary:"
Write-Output "Successfully removed: $successCount items"
Write-Output "Failed to remove: $failCount items"
Write-Output "=========================================="

# Exit with appropriate code
if ($failCount -eq 0) {
    Write-Output "All bloatware successfully removed"
    Exit 0
}
else {
    Write-Output "Completed with some failures"
    Exit 0  # Still exit 0 as partial success is acceptable
}