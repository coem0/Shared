#==============================================================================
# Dell Bloatware Detection Script for Intune
# This script detects if Dell bloatware is present on the system
# Exit Code 0 = Compliant (no bloatware found)
# Exit Code 1 = Non-Compliant (bloatware found - triggers remediation)
#==============================================================================

# Get manufacturer
$manufacturer = (Get-WmiObject -Class Win32_ComputerSystem).Manufacturer

# Only run on Dell devices
if ($manufacturer -notlike "*Dell*") {
    Write-Output "Not a Dell device. Exiting as compliant."
    Exit 0
}

Write-Output "Dell device detected. Checking for bloatware..."

# Define apps to check for (you can comment out apps you want to keep)
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
$appsToCheck = $UninstallPrograms | Where-Object { $appsToIgnore -notcontains $_ }

$foundApps = @()

# Check for AppX packages
foreach ($app in $appsToCheck) {
    if (Get-AppxProvisionedPackage -Online | Where-Object DisplayName -like $app -ErrorAction SilentlyContinue) {
        $foundApps += $app
        Write-Output "Found provisioned package: $app"
    }
    
    if (Get-AppxPackage -AllUsers -Name $app -ErrorAction SilentlyContinue) {
        $foundApps += $app
        Write-Output "Found AppX package: $app"
    }
}

# Check in registry for installed programs
$registryPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
)

foreach ($registryPath in $registryPaths) {
    foreach ($app in $appsToCheck) {
        $found = Get-ItemProperty -Path $registryPath -ErrorAction SilentlyContinue | 
                 Where-Object { $_.DisplayName -match [regex]::Escape($app) }
        
        if ($found) {
            $foundApps += $app
            Write-Output "Found installed program: $app"
        }
    }
}

# Check for specific Dell programs in common installation paths
$specificChecks = @{
    "Dell Peripheral Manager" = "C:\Program Files\Dell\Dell Peripheral Manager\Uninstall.exe"
    "Dell Pair" = "C:\Program Files\Dell\Dell Pair\Uninstall.exe"
}

foreach ($check in $specificChecks.GetEnumerator()) {
    if (Test-Path $check.Value) {
        $foundApps += $check.Key
        Write-Output "Found program at path: $($check.Key)"
    }
}

# Remove duplicates
$foundApps = $foundApps | Select-Object -Unique

# Determine compliance
if ($foundApps.Count -gt 0) {
    $appList = $foundApps -join ", "
    Write-Output "Non-Compliant: Found $($foundApps.Count) Dell bloatware application(s): $appList"
    Exit 1  # Non-compliant - triggers remediation
}
else {
    Write-Output "Compliant: No Dell bloatware found"
    Exit 0  # Compliant
}