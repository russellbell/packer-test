# The default script execution is set to Form Based Interactive option $AMIAutomation = $false, the same script is executed in the Ami Automation framework set to $true
Param (
    $AMIAutomation = $false,
    $productCode = $null
)

$ScriptVersion = "2.13.25"
# placeholder for index of the failed functions $failedIndexList. The -fix parameter will call only functions that were marked/indexed as failed
$global:failedIndexList = @()
$global:PASSED = "PASSED"
$global:WARNING = "WARNING"
$global:FAILED = "FAILED"
$global:ImageInfo = @{ }
$global:FreeSpaceMinimumGB = 10
$global:FreeSpaceMinimumGBOffice = 20
$global:MinRearmCount = 1
$global:MaxDriveSize = 80
$global:MinPSVersion = 4
$global:SuccessLabel = "[SUCCESS]"
$global:FailureLabel = "[FAIL]"
$global:FailureText = "Unable to resolve the issue, please click on the info button for more detailed information"
$global:SupportedOS = @("10.0.10586", "10.0.14393", "10.0.15063", "10.0.16299", "10.0.17134", "10.0.17763", "10.0.18362", "10.0.18363", "10.0.19041","10.0.19042","10.0.19043","10.0.19044","10.0.19045","10.0.22000","10.0.22621","10.0.22631")
$officeLink = 'https://docs.aws.amazon.com/workspaces/latest/adminguide/byol-windows-images.html'
$officeMessage = 'The BYOL Checker has detected that Microsoft Office is installed on this virtual machine (VM). During the BYOL image ingestion process, you can choose to subscribe to Microsoft Office Professional 2016 or 2019 through AWS. If you plan to subscribe to Office through AWS, you must uninstall Office from this VM, and then run BYOL Checker again.'
$officeTitle = 'Microsoft Office detected'
$officeRegistryPattern = "0FF1CE"
$officeFreeSpacemessage='The BYOL Checker has detected that there is less than 20 GB of free disk space on your virtual machine (VM). During the BYOL image ingestion process, you can choose to subscribe to Microsoft Office Professional 2016 or 2019 through AWS. If you plan to subscribe to Office through AWS, make sure you have at least 20 GB of free disk space on your VM, and then run BYOL Checker again.'


# Placeholder for Functions/Tests Exemptions that will be excluded from the execution
$WIN7ExemptedFunctions = @("Test-BYOL_AzureDomainJoined", "Test-BYOL_OfficeInstalled","Test-BYOL_FreeDiskSpace")
$WIN10ExemptedFunctions = @("Test-BYOL_FreeDiskSpaceW7")
$AutomationExemptFunctions = @("Test-BYOL_DriveLessThan80GB")
$warningExemptedFunctions = @("Test-BYOL_OfficeInstalled","Test-BYOL_FreeDiskSpace")

# placeholder for script variables
$CurrentWorkingDirectory = $PSScriptRoot
$fileTimestamp = get-Date -f yyyy'-'MM'-'dd'_'hhmmss
$LogFileName = "BYOLPrevalidationlog" + $fileTimeStamp
$Logfile = "$currentWorkingDirectory\$LogFileName.txt"
$Infofile = "$currentWorkingDirectory\ImageInfo.txt"
$scriptName = $($MyInvocation.MyCommand.Name)
$appName = $scriptName # is used in IMS
$global:sysprepTimeRun = 300 # run time sysprep
$global:OSCheck = (Get-CimInstance win32_operatingsystem).Caption
[PsCustomObject]$global:FunctionList = @()

# Get all functions that start with "Test-BYOL_*" . This function will dynamically create a list of functions that will be executed to validate the BYOL.
function Get-BYOLFunctions {
    $allFunctions = Get-ChildItem function:\
    $global:BYOLFunctions = $allFunctions | Where-Object Name -like "Test-BYOL_*" | Select-Object Name
    return $global:BYOLFunctions
}
function Test-BYOL_PowershellVersion {
    switch ($AMIAutomation) {
        false {
            $obj = [PsCustomObject]@{
                Name        = $($MyInvocation.MyCommand.Name)
                TextLabel   = "PowerShell version installed is 4.0 or higher"
                FailureText = "Upgrade to PowerShell version 4.0 or higher."
            }
            $global:FunctionList += $obj
        }
        true {
            $log1 = $PSVersionTable.PSVersion.Major
            Write-LogFile "Powershell version is $log1"
            if ($PSVersionTable.psversion.major -ge $global:MinPSVersion) {
                Write-LogFile " $global:SuccessLabel PowerShell Version is greater than $global:MinPSVersion "
                return [tuple]::Create($global:PASSED)
            }
            else {
                $ErrorCode = "OutdatedPowershellVersion"
                Write-LogFile " $global:FailureLabel PowerShell Version is less than $global:MinPSVersion"
                return [tuple]::Create($global:FAILED, $ErrorCode)
            }

        }
        fix {
            $global:OutputBox.AppendText($global:FailureText)
        }
    }
}
function Test-OfficeInstalled {
    # This function return true if Microsoft Office is detected on the machine
    $apps = Get-ItemProperty @('hklm:\software\microsoft\windows\currentversion\uninstall\*', 'hklm:\software\Wow6432Node\microsoft\windows\currentversion\uninstall\*') | Where { $_.PSChildName -match $officeRegistryPattern }
    if ($apps) {
        return $true
    }
    else {
        return $false
    }
}
function Test-BYOL_OfficeInstalled {
    switch ($AMIAutomation) {
        false {
            $obj = [PsCustomObject]@{
                Name        = $($MyInvocation.MyCommand.Name)
                TextLabel   = "Microsoft Office check"
                FailureText = "$officeMessage Learn more: $officeLink"
            }
            $global:FunctionList += $obj
        }
        true {
            # Init Office configuration (Installed apps, SkipOfficePopup registry value)
            $officeDetected = Test-OfficeInstalled
            $skipOfficePopup = Get-ItemProperty -path "HKLM:\Software\Amazon\BYOLChecker\" -Name SkipOfficePopup -ErrorAction SilentlyContinue | Select-Object -ExpandProperty SkipOfficePopup

            # Display Popup during Interactive Run of BYOLChecker. The SkipOfficePopup registry key will be automatically removed when running BYOLChecker in interactive mode to force the display of the Popup.
            if ((-not $skipOfficePopup) -and $officeDetected) {
                Write-LogFile "Microsoft Office detected [interactiveMode]"
                [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")
                [System.Windows.Forms.MessageBox]::Show("$officeMessage Click on the help button to learn more.", $officeTitle, [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning, 'button3', 0, $officeLink)
                $skipOfficePopup = (New-ItemProperty -Path "HKLM:\Software\Amazon\BYOLChecker" -Name SkipOfficePopup -Value 1 -Force).skipOfficePopup
            }

            # Adding the value of the regitry in the logs for troubleshooting
            Write-LogFile "HKLM:\Software\Amazon\BYOLChecker\SkipOfficePopup = $skipOfficePopup"

            if ($officeDetected) {
                # If Microsoft Office is detected, we will try to determine if this causes an issue.
                switch ($interactiveMode) {
                    $true {
                        # Microsoft Office is detected during an interactive run of BYOLChecker. Returning WARNING in the tool.
                        Write-LogFile "$global:FailureLabel $officeMessage Learn more:$officeLink"
                        return $global:WARNING
                    }
                    default {
                        # Microsoft Office is detected during an automated run of BYOLChecker.
                        if ($productCode -match "_OFFICE_") {
                            # Failing the check if the product code is related to Microsoft Office
                            $ErrorCode = "OfficeInstalled"
                            Write-LogFile "$global:FailureLabel Unable to create BYOL image using $productCode because Microsoft Office is installed. $officeMessage Learn more: $officeLink"
                            return [tuple]::Create($global:FAILED, $ErrorCode)
                        }
                        else {
                            # Passing the check if the product code is not related to Microsoft Office.
                            Write-LogFile "$global:SuccessLabel"
                            return [tuple]::Create($global:PASSED)
                        }
                    }
                }
            }
            else {
                # Passing the check if Microsoft Office is not detected on the machine.
                Write-LogFile "$global:SuccessLabel"
                return [tuple]::Create($global:PASSED)
            }
        }
        fix {
            # No automated fix for this check.
            $global:OutputBox.AppendText($global:FailureText)
        }
    }
}
function Test-BYOL_PCoIP_Check {
    switch ($AMIAutomation) {
        false {
            $obj = [PsCustomObject]@{
                Name        = $($MyInvocation.MyCommand.Name)
                TextLabel   = "PCoIP Agent is not installed"
                FailureText = "PCoIP Agent is installed. Uninstall PCoIP Agent. "
            }
            $global:FunctionList += $obj
            $global:PCoIP_del_try = $false
        }
        true {
            # Tipacally all three Checks must be false to properly install new PCoIP Agent
            $global:PCoIP_uninstaller = "C:\Program Files (x86)\Teradici\PCoIP Agent\uninst.exe"
            $Check1 = Test-Path "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\PCoIP*"
            $Check2 = Test-Path $PCoIP_uninstaller
            $Check3 = Get-Service | Where-Object { $_.Name -eq "PCoIPAgent" }
            $ErrorCode = "PCoIPAgentInstalled"
            if (!($Check1) -and !($Check2) -and !($Check3)) {
                # All Checks are false, no PCoIP agent artifacts
                Write-LogFile "$global:SuccessLabel PCoIP agent is not present"
                return [tuple]::Create($global:PASSED)
            }
            elseif (!($global:PCoIP_del_try) -and !($Check2)) {
                # If uninst.exe is missing it will mark as Failed at first run, because we cannot uninstall the agent
                Write-LogFile " $global:FailureLabel PCoIP uninstaller failed"
                return [tuple]::Create($global:FAILED, $ErrorCode)

            }
            elseif ($Check1 -or $Check2 -or $Check3 -or !($global:PCoIP_del_try)) {
                # If any of the Checks fail, than the PCoIP was present and an uninstall can be initiated
                Write-LogFile " $global:FailureLabel Detected PCoIP Agent installed"
                return [tuple]::Create($global:WARNING, $ErrorCode)
            }
            else {
                Write-LogFile " $global:FailureLabel Unexpected PCoIP check failure"
                return [tuple]::Create($global:FAILED, $ErrorCode)
            }
        }
        fix {
            $global:OutputBox.AppendText("Uninstalling PCoIP Agent. It can take several minutes. Please wait ...")
            $ExitCode = (Start-Process -FilePath $global:PCoIP_uninstaller -ArgumentList "/S /NoPostReboot '_?=C:\Program Files (x86)\Teradici\PCoIP Agent'" -Wait -PassThru).ExitCode
            if ($ExitCode -eq 0) {
                $global:OutputBox.AppendText("`nPCoIP Agent has been uninstalled successfullly")
                Write-LogFile "$global:SuccessLabel PCoIP Agent has been uninstalled successfullly"
            }
            else {
                $global:OutputBox.AppendText("`nFailed to uninstall PCoIP Agent with ExitCode: $ExitCode")
                Write-LogFile "$global:FailureLabel Failed to uninstall PCoIP Agent with ExitCode: $ExitCode"
                $global:PCoIP_del_try = $true
                $global:OutputBox.AppendText("$global:FailureText `nFailed to auto uninstall PCoIP Agent. Try uninstalling it manually.")
            }
        }
    }
}
function Test-BYOL_Disable_Updates {
    switch ($AMIAutomation) {
        false {
            $obj = [PsCustomObject]@{
                Name        = $($MyInvocation.MyCommand.Name)
                TextLabel   = "Windows updates is disabled"
                FailureText = "Windows updates is enabled. Disable Windows updates and try again."
            }
            $global:FunctionList += $obj
        }
        true {
            # Desired Service Name and its StartType Mode
            $global:GoodService = @(
                [PsCustomObject]@{
                    Name      = "wuauserv"
                    StartMode = "Disabled"
                }
                ,
                [PsCustomObject]@{
                    Name      = "TrustedInstaller"
                    StartMode = "Manual"
                }
            )

            $ServiceStateList = @()
            foreach ($svc in $global:GoodService) {
                $ServiceState = Get-WmiObject -ClassName Win32_Service | Where-Object Name -eq $svc.Name | Select-Object Name, StartMode
                $ServiceStateList = $ServiceStateList + $ServiceState
            }
            $global:BadService = @()
            $global:BadService = Compare-Object $global:GoodService $ServiceStatelist -Property StartMode, Name | Select-Object Name -Unique -ExpandProperty Name
            if ($global:BadService -eq $null) {
                Write-LogFile "$global:SuccessLabel Update service status has passed the check"
                return [tuple]::Create($global:PASSED)
            }
            else {
                $ErrorCode = "WindowsUpdatesEnabled"
                Write-LogFile "$global:FailureLabel Update service status failed. Service(s): $global:BadService did not meet the startup criteria."
                return [tuple]::Create($global:WARNING, $ErrorCode)
            }
        }
        fix {
            foreach ($service in $global:BadService) {
                try {
                    # Stopping the process, if it is running, before disabling it
                    $ServicePID = (get-wmiobject win32_service | Where-Object { $_.name -eq $service }).processID
                    if ($ServicePID -ne 0) {
                        Write-LogFile "$global:FailureLabel $service processID is $ServicePID. Stopping the service"
                        taskkill /pid $ServicePID /f /t
                    }
                    else {
                        Write-LogFile "$global:SuccessLabel $service processID is 0 (null)"
                    }
                    # Disabling the service
                    Stop-Service -Name $service -Force -ErrorAction SilentlyContinue
                    Set-Service -Name $service -StartupType ($global:GoodService | Where-Object { $_.Name -eq $service }).StartMode
                }
                catch {
                    $global:OutputBox.AppendText("$global:FailureText `nFailed to Auto disable Windows Updates. Please try to manualy disable Windows Updates.")
                }
            }
        }
    }
}
function Test-BYOL_AutoMount {
    switch ($AMIAutomation) {
        false {
            $obj = [PsCustomObject]@{
                Name        = $($MyInvocation.MyCommand.Name)
                TextLabel   = "Automount is enabled"
                FailureText = "Automount is disabled. Enable Automount."
            }
            $global:FunctionList += $obj
        }
        true {
            $RegKey = "HKLM:\SYSTEM\CurrentControlSet\services\mountmgr"

            if ((Get-ItemProperty $RegKey).NoAutoMount -eq 1) {
                $ErrorCode = "AutoMountDisabled"
                Write-LogFile " $global:FailureLabel Automount is Disabled."
                return [tuple]::Create($global:WARNING, $ErrorCode)
            }
            else {
                Write-LogFile " $global:SuccessLabel Automount is Enabled"
                return [tuple]::Create($global:PASSED)
            }
        }
        fix {
            "automount enable" | diskpart
        }
    }
}
function Test-BYOL_Workspaces_BYOLAccountExist {
    switch ($AMIAutomation) {
        false {
            $obj = [PsCustomObject]@{
                Name        = $($MyInvocation.MyCommand.Name)
                TextLabel   = "WorkSpaces_BYOL account exists"
                FailureText = "WorkSpaces_BYOL account not found in the SAM database. Create an account with this username and add it to local administrators group."
            }
            $global:FunctionList += $obj
        }
        true {
            if (Get-WMIObject Win32_UserAccount -Filter "LocalAccount='true' and Name='WorkSpaces_BYOL'") {

                Write-LogFile " Workspaces_BYOL Exists"
                Write-LogFile "$global:SuccessLabel Workspaces_BYOL Account Exists"
                return [tuple]::Create($global:PASSED)
            }
            else {
                $ErrorCode = "WorkspacesBYOLAccountNotFound"
                Write-LogFile " $global:FailureLabel Workspaces_BYOL Account Does Not Exist"
                return [tuple]::Create($global:WARNING, $ErrorCode)
            }
        }
        fix {
            New-WorkSpaces_BYOL_User
        }
    }
}
function Test-BYOL_Workspaces_BYOLAccountDisabled {
    switch ($AMIAutomation) {
        false {
            $obj = [PsCustomObject]@{
                Name        = $($MyInvocation.MyCommand.Name)
                TextLabel   = "WorkSpaces_BYOL account is enabled"
                FailureText = "WorkSpaces_BYOL account is disabled. Please enable it."
            }
            $global:FunctionList += $obj
        }
        true {
            $script:workspaces_BYOLAccount = Get-WmiObject -Class Win32_UserAccount -Filter  "LocalAccount='True'" | Where-Object { $_.Name -eq "WorkSpaces_BYOL" }
            $log14 = $workspaces_BYOLAccount.Disabled
            Write-LogFile "WorkSpaces_BYOL Disabled/Enabled status - $log14 (Status will be blank if this test is run on domain controller)"
            $ImageInfo["WorkSpaces_BYOLAccount.Disabled"] = $log14
            if ($workspaces_BYOLAccount.Disabled -eq $false) {
                Write-LogFile "$global:SuccessLabel WorkSpaces_BYOL Account Enabled"
                return [tuple]::Create($global:PASSED)
            }
            else {
                $ErrorCode = "WorkspacesBYOLAccountDisabled"
                Write-LogFile " $global:FailureLabel WorkSpaces_BYOL Account Disabled"
                return [tuple]::Create($global:WARNING, $ErrorCode)
            }
        }
        fix {
            net user Workspaces_BYOL /active:yes
        }
    }
}
function Test-BYOL_DHCPEnabledInterface {
    switch ($AMIAutomation) {
        false {
            $obj = [PsCustomObject]@{
                Name        = $($MyInvocation.MyCommand.Name)
                TextLabel   = "DHCP is enabled on network interface"
                FailureText = "Network interface is currently using a static IP address. Change network interface to use DHCP."
            }
            $global:FunctionList += $obj
        }
        true {
            $script:networkAdapters = Get-WmiObject -Class win32_networkadapterconfiguration -filter 'ipenabled = "true"'
            $log = $networkAdapters.DHCPEnabled
            Write-LogFile "Network Adapter using DHCP logs - $log"
            $ImageInfo["NetworkAdapterUsingDHCP"] = $log
            #should not have 2 network adapters but we want to treat this test separate and consider multiple network interfaces but will succeed if true on all interfaces.
            if ($log -eq $False) {
                $ErrorCode = "DHCPDisabled"
                Write-LogFile " $global:FailureLabel DHCP disabled on network interface"
                return [tuple]::Create($global:FAILED, $ErrorCode)
            }
            else {
                Write-LogFile "$global:SuccessLabel DHCP enabled on network interface"
                return [tuple]::Create($global:PASSED)
            }
        }
        fix {
            $global:OutputBox.AppendText($global:FailureText)
        }
    }
}
function Test-BYOL_FreeDiskSpaceW7 {
    switch ($AMIAutomation) {
        false {
            $obj = [PsCustomObject]@{
                Name        = $($MyInvocation.MyCommand.Name)
                TextLabel   = "More than ${global:FreeSpaceMinimumGB}GB of free space on C: drive"
                FailureText = "C: drive has less than ${global:FreeSpaceMinimumGB}GB of free space. Clean up C: drive to free up some space"
            }
            $global:FunctionList += $obj
        }
        true {
            $script:disk = Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='C:'" | Select-Object FreeSpace
            $currentFreeSpace = ($($disk.freespace)/1GB)
            Write-LogFile " Amount of free space on C: drive - $currentFreeSpace GB"
            $ImageInfo["FreeSpaceOnCDrive"] = $currentFreeSpace
            if ($currentFreeSpace -lt $global:FreeSpaceMinimumGB ) {
                $ErrorCode = "DiskFreeSpace"
                Write-LogFile "$global:FailureLabel Free disk space is less than minimum required $global:FreeSpaceMinimumGB"
                return [tuple]::Create($global:FAILED, $ErrorCode)
            }
            else {
                Write-LogFile "$global:SuccessLabel Free disk space is greater than minimum required $global:FreeSpaceMinimumGB"
                return [tuple]::Create($global:PASSED)
            }
        }
        fix {
            $global:OutputBox.AppendText($global:FailureText)
        }
    }
}
function Test-BYOL_FreeDiskSpace {
    switch ($AMIAutomation) {
        false {
            $obj = [PsCustomObject]@{
                Name        = $($MyInvocation.MyCommand.Name)
                TextLabel   = "More than ${global:FreeSpaceMinimumGBOffice}GB of free space on C: drive"
                FailureText = "$officeFreeSpacemessage Learn more: $officeLink"
            }
            $global:FunctionList += $obj
        }
        true {
            $script:disk = Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='C:'" | Select-Object FreeSpace
            $currentFreeSpace = [math]::Round(($($disk.freespace)/1GB),2)
            Write-LogFile "Amount of free space on C: drive - $currentFreeSpace GB"
            $ImageInfo["FreeSpaceOnCDrive"] = $currentFreeSpace
            $officeDetected = Test-OfficeInstalled
            $ErrorCode = "DiskFreeSpace"

            if ($interactiveMode) {
                if ($currentFreeSpace -lt $global:FreeSpaceMinimumGBOffice ) {
                    Write-LogFile "$global:FailureLabel Free disk space is less than minimum required to support Microsoft Office by AWS $global:FreeSpaceMinimumGBOffice GB"
                    return [tuple]::Create($global:WARNING, $ErrorCode)
                }
                elseif ($currentFreeSpace -lt $global:FreeSpaceMinimumGB ) {
                    Write-LogFile "$global:FailureLabel Free disk space is less than minimum required $global:FreeSpaceMinimumGB GB"
                    return [tuple]::Create($global:FAILED, $ErrorCode)
                }
                else {
                    Write-LogFile "$global:SuccessLabel Free disk space is greater than minimum required $global:FreeSpaceMinimumGBOffice GB"
                    return [tuple]::Create($global:PASSED)
                }
            }
            else {
                switch ($officeDetected) {
                    $true {
                        if ($productCode -match "_OFFICE_") {
                            if ($currentFreeSpace -lt $global:FreeSpaceMinimumGBOffice) {
                                Write-LogFile "$global:FailureLabel Free disk space is less than minimum required $global:FreeSpaceMinimumGBOffice GB"
                                return [tuple]::Create($global:FAILED, $ErrorCode)
                            }
                            else {
                                Write-LogFile "$global:SuccessLabel Free disk space is greater than minimum required $global:FreeSpaceMinimumGB GB"
                                return [tuple]::Create($global:PASSED)
                            }
                        }
                        else {
                            if ($currentFreeSpace -lt $global:FreeSpaceMinimumGB) {
                                Write-LogFile "$global:FailureLabel Free disk space is less than minimum required $global:FreeSpaceMinimumGB GB"
                                return [tuple]::Create($global:FAILED, $ErrorCode)
                            }
                            else {
                                Write-LogFile "$global:SuccessLabel Free disk space is greater than minimum required $global:FreeSpaceMinimumGB GB"
                                return [tuple]::Create($global:PASSED)
                            }
                        }
                    }
                    default {
                        if ($currentFreeSpace -lt $global:FreeSpaceMinimumGB) {
                            Write-LogFile "$global:FailureLabel Free disk space is less than minimum required $global:FreeSpaceMinimumGB GB"
                            return [tuple]::Create($global:FAILED, $ErrorCode)
                        }
                        else {
                            Write-LogFile "$global:SuccessLabel Free disk space is greater than minimum required $global:FreeSpaceMinimumGB GB"
                            return [tuple]::Create($global:PASSED)
                        }
                    }

                }
            }
        }
        fix {
            $global:OutputBox.AppendText($global:FailureText)
        }
    }
}
function Test-BYOL_LocalDrives {
    switch ($AMIAutomation) {
        false {
            $obj = [PsCustomObject]@{
                Name        = $($MyInvocation.MyCommand.Name)
                TextLabel   = "Only local disks are attached"
                FailureText = "Removable or network drives attached. Remove all removable, network, and CD/ISO drives."
            }
            $global:FunctionList += $obj
        }
        true {
            $script:drives = @(Get-WmiObject -class win32_logicaldisk | Select-Object DeviceID, DriveType)
            $log9 = $drives | Out-String
            Write-LogFile " Attached Drives types:"
            Write-LogFile "$log9"
            if ($drives.Count -eq "1" -and $drives.DriveType -eq "3") {
                # Only one drive should be attached and it has to be Local Drive
                Write-LogFile "$global:SuccessLabel Drives of the correct type attached."
                return [tuple]::Create($global:PASSED)
            }
            else {
                $ErrorCode = "AdditionalDrivesAttached"
                Write-LogFile " $global:FailureLabel Wrong type of drives attached."
                return [tuple]::Create($global:FAILED, $ErrorCode)
            }
        }
        fix {
            $global:OutputBox.AppendText($global:FailureText)
        }
    }
}
function Test-BYOL_OSRequirements {
    # Reference for version https://en.wikipedia.org/wiki/Ver_%28command%29
    # Reference for edition numbers https://techontip.wordpress.com/tag/operatingsystemsku/
    switch ($AMIAutomation) {
        false {
            $obj = [PsCustomObject]@{
                Name        = $($MyInvocation.MyCommand.Name)
                TextLabel   = "Supported Windows operating system"
                FailureText = "Operating System is not supported. Try again with image running supported OS."
            }
            $global:FunctionList += $obj
        }
        true {
            $OSinfo = get-wmiobject -class win32_operatingsystem
            [int]$OSType = $OSinfo.ProductType # 1 is for Workstation
            [String]$OSVersion = $OSinfo.Version
            # Only Workstations and WIN7, WIN10, WIN11 can be used for BYOL
            # ProductType --> 1 for client versions of Windows, 2 for server versions of Windows operating as domain controllers, and 3 for server versions of Windows that are not operating as domain controllers.
            if ($osType -eq 1 -and ($OSVersion -in $global:SupportedOS)) {
                Write-LogFile "$global:SuccessLabel OS type $osType is Desktop type and OS Version is $OSVersion"
                $global:OOBEfile = "$PSScriptRoot\OOBE_unattend.xml"
                return [tuple]::Create($global:PASSED)
            }
           else {
                $ErrorCode = "OSNotSupported"
                Write-LogFile " $global:FailureLabel OS type $osType is NOT Desktop type and OS Version is $OSVersion"
                return [tuple]::Create($global:FAILED, $ErrorCode)
            }
        }
        fix {
            $global:OutputBox.AppendText($global:FailureText)
        }
    }
}
function Test-BYOL_DomainJoined {
    switch ($AMIAutomation) {
        false {
            $obj = [PsCustomObject]@{
                Name        = $($MyInvocation.MyCommand.Name)
                TextLabel   = "System is not AD domain joined"
                FailureText = "System is domain joined. Unjoin from AD domain and try again."
            }
            $global:FunctionList += $obj
        }
        true {
            $script:partofDomain = (Get-WmiObject -Class win32_computersystem).partofdomain
            Write-LogFile "Computer part of domain - $script:partofDomain"
            $ImageInfo["partOfDomain"] = $script:partofDomain
            if ( $script:partofDomain -eq $true ) {
                $ErrorCode = "DomainJoined"
                Write-LogFile " $global:FailureLabel System is domain joined. Please detach the system from the domain."
                return [tuple]::Create($global:FAILED, $ErrorCode)
            }
            else {
                Write-LogFile "$global:SuccessLabel System is not domain joined."
                return [tuple]::Create($global:PASSED)
            }
        }
        fix {
            $global:OutputBox.AppendText($global:FailureText)
        }
    }
}
function Test-BYOL_AzureDomainJoined {
    switch ($AMIAutomation) {
        false {
            $obj = [PsCustomObject]@{
                Name        = $($MyInvocation.MyCommand.Name)
                TextLabel   = "System is Azure domain joined"
                FailureText = "System is Azure domain joined. Unjoin from Azure domain and try again."
            }
            $global:FunctionList += $obj
        }
        true {
            $DomainInfo = Invoke-Expression "dsregcmd /status"
            if ($DomainInfo -match "AzureAdJoined : YES") {
                $ErrorCode = "AzureDomainJoined"
                Write-LogFile " $global:FailureLabel System is AzureAdJoined joined. Please detach the system from the domain."
                return [tuple]::Create($global:FAILED, $ErrorCode)
            }
            else {
                Write-LogFile "$global:SuccessLabel System is not domain joined."
                return [tuple]::Create($global:PASSED)
            }
        }
        fix {
            $global:OutputBox.AppendText($global:FailureText)
        }
    }
}
function Test-BYOL_Firewall {
    switch ($AMIAutomation) {
        false {
            $obj = [PsCustomObject]@{
                Name        = $($MyInvocation.MyCommand.Name)
                TextLabel   = "Windows Firewall is disabled"
                FailureText = "Windows Firewall is enabled. Turn off public firewall profile and try again."
            }
            $global:FunctionList += $obj
        }
        true {
            $location = "Registry::HKLM\SYSTEM\ControlSet001\Services\SharedAccess\Parameters\FirewallPolicy"
            $publicFirewall = Get-ItemProperty -path $location\PublicProfile -ErrorAction SilentlyContinue
            $ImageInfo["Firewall"] = @{ }
            $ImageInfo["Firewall"]["Type"] = "Public"

            if ($publicFirewall.enablefirewall -eq 1) {
                $ErrorCode = "FirewallEnabled"
                Write-LogFile " $global:FailureLabel Public Firewall Profile is turned ON"
                $ImageInfo["Firewall"]["TurnedOn"] = $TRUE
                return [tuple]::Create($global:WARNING, $ErrorCode)
            }
            else {
                Write-LogFile "$global:SuccessLabel Public Firewall Profile is turned OFF"
                $ImageInfo["Firewall"]["TurnedOn"] = $FALSE
                return [tuple]::Create($global:PASSED)
            }
        }
        fix {
            netsh advfirewall set publicprofile state off
        }
    }
}
function Test-BYOL_VMWareTools {
    switch ($AMIAutomation) {
        false {
            $obj = [PsCustomObject]@{
                Name        = $($MyInvocation.MyCommand.Name)
                TextLabel   = "VMWare tools not installed"
                FailureText = "VMWare tools are currently installed. Uninstall VMWare tools and try again."
            }
            $global:FunctionList += $obj
        }
        true {
            $path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
            $installedApps = Get-ItemProperty $path | Select-Object DisplayName
            foreach ($app in $installedApps) {
                $ImageInfo["VMWareToolsInstalled"] = $app.displayname
                if ($app.displayname -eq "VMWare Tools") {
                    $ErrorCode = "VMWareToolsInstalled"
                    Write-LogFile " $global:FailureLabel VMware Tools is installed? - $VMWareToolsInstalled"
                    return [tuple]::Create($global:FAILED, $ErrorCode)
                }
                else {
                    Write-LogFile "=$global:SuccessLabel> VMware Tools is installed? - $VMWareToolsInstalled"
                }
            }
            return [tuple]::Create($global:PASSED)
        }
        fix {
            $global:OutputBox.AppendText($global:FailureText)
        }
    }
}
function Test-BYOL_DriveLessThan80GB {
    switch ($AMIAutomation) {
        false {
            $obj = [PsCustomObject]@{
                Name        = $($MyInvocation.MyCommand.Name)
                TextLabel   = "Attached Disk#0 is smaller than $MaxDriveSize GB"
                FailureText = "Attached Disk#0 is larger than $MaxDriveSize GB. Make them smaller than $MaxDriveSize GB and try again."
            }
            $global:FunctionList += $obj
        }
        true {
            $drive = Get-WmiObject -Class Win32_DiskDrive | Where-Object {$_.DeviceID -like "*PHYSICALDRIVE0*"}
            $ImageInfo["Drives"] = $drive
            if (($drive.size / 1GB) -gt $global:MaxDriveSize) {
                $ErrorCode = "DiskSizeExceeded"
                Write-LogFile "$global:FailureLabel Attached drive size is greater than $global:MaxDriveSize GB"
                return [tuple]::Create($global:FAILED, $ErrorCode)
            }
            else {
                Write-LogFile "$global:SuccessLabel Attached drive size is less than $global:MaxDriveSize GB"
                return [tuple]::Create($global:PASSED)
            }
        }
        fix {
            $global:OutputBox.AppendText($global:FailureText)
        }
    }
}
function Test-BYOL_GPTPartitions {
    switch ($AMIAutomation) {
        false {
            $obj = [PsCustomObject]@{
                Name        = $($MyInvocation.MyCommand.Name)
                TextLabel   = "MBR/GPT partitioned volumes"
                FailureText = "Volumes are not partitioned to be compatible with Operating System. Make sure all volumes MBR partitioned for Windows 10/7 and GPT partitioned for Windows 11 and try again."
            }
            $global:FunctionList += $obj
        }
        true {
            $script:partitions = Get-WmiObject -Class win32_diskpartition
            $ImageInfo["Partitions"] = $partitions
            $convertedPartitions = $partitions | Out-String
            $convertedPartitionTypes = $partitions.type | Out-String
            Write-LogFile "List of Partitions - "
            Write-LogFile "$convertedPartitions"
            Write-LogFile "(in respective order to above partition list)"
            Write-LogFile "$convertedPartitionTypes"
            foreach ($partition in $partitions) {
                $ErrorCode = "IncompatiblePartitioning"
                if ($partition.type.startswith("GPT") -and (-not (Validate-UEFIBootEnabled))) {
                    Write-LogFile "$global:FailureLabel There is a GPT (GUID Partition Table) Partition on non UEFI enabled OS"
                    return [tuple]::Create($global:FAILED, $ErrorCode)
                }
                elseif ($partition.type.startswith("MBR") -and (Validate-UEFIBootEnabled)) {
                    Write-LogFile "$global:FailureLabel There is a MBR (Master Boot Record) Partition on UEFI enabled OS"
                    return [tuple]::Create($global:FAILED, $ErrorCode)
                }
            }
            Write-LogFile "$global:SuccessLabel $($partitions.Name) are compatible with the OS"
            return [tuple]::Create($global:PASSED)
        }
        fix {
            $global:OutputBox.AppendText($global:FailureText)
        }
    }
}
function Test-BYOL_PendingReboots {
    switch ($AMIAutomation) {
        false {
            $obj = [PsCustomObject]@{
                Name        = $($MyInvocation.MyCommand.Name)
                TextLabel   = "No pending system reboot"
                FailureText = "System is pending reboot. Complete system reboot and try again."
            }
            $global:FunctionList += $obj
        }
        true {
            $RebootRequired = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
            $RebootPending = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
            if ((test-path $RebootRequired -ErrorAction SilentlyContinue) -or (test-path $RebootPending -ErrorAction SilentlyContinue)) {
                $ErrorCode = "PendingReboot"
                Write-LogFile " $global:FailureLabel There are pending updates. All updates need to be installed before the Image can be converted to BYOL AMI"
                return [tuple]::Create($global:FAILED, $ErrorCode)
            }
            else {
                Write-LogFile "$global:SuccessLabel No pending reboots detected."
                return [tuple]::Create($global:PASSED)
            }
        }
        fix {
            $global:OutputBox.AppendText($global:FailureText)
        }
    }
}
function Test-BYOL_AutoLogon {
    switch ($AMIAutomation) {
        false {
            $obj = [PsCustomObject]@{
                Name        = $($MyInvocation.MyCommand.Name)
                TextLabel   = "AutoLogon is disabled"
                FailureText = "AutoLogon is enabled. Disable AutoLogon in registry and try again."
            }
            $global:FunctionList += $obj
        }
        true {
            $path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
            $result = Get-ItemProperty -path $path
            if ($result.AutoAdminLogon -eq 1) {
                $ErrorCode = "AutoLogonEnabled"
                Write-LogFile " $global:FailureLabel AutoLogon turned on? - True"
                $ImageInfo["AutoLogonTurnedOn"] = $TRUE
                return [tuple]::Create($global:WARNING, $ErrorCode)
            }
            else {
                Write-LogFile "$global:SuccessLabel AutoLogon turned on? - False"
                $ImageInfo["AutoLogonTurnedOn"] = $FALSE
                return [tuple]::Create($global:PASSED)
            }
        }
        fix {
            Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -Name AutoAdminLogon -Value "0"
        }
    }
}
function Test-BYOL_RealTimeUniversal {
    switch ($AMIAutomation) {
        false {
            $obj = [PsCustomObject]@{
                Name        = $($MyInvocation.MyCommand.Name)
                TextLabel   = "RealTimeISUniversal registry key is enabled"
                FailureText = "RealTimeIsUniversal registry key is disabled. Enable this setting and try again. `nSee: `nhttp://docs.aws.amazon.com/AWSEC2/latest/WindowsGuide/windows-set-time.html"
            }
            $global:FunctionList += $obj
        }
        true {
            $path = 'HKLM:\System\CurrentControlSet\Control\TimeZoneInformation'
            $result = Get-ItemProperty -path $path
            if ($result.RealTimeIsUniversal) {
                Write-LogFile "$global:SuccessLabel RealTimeIsUniversal reg key installed - True"
                $ImageInfo["RealTimeIsUniversal"] = $TRUE
                return [tuple]::Create($global:PASSED)
            }
            else {
                $ErrorCode = "RealTimeUniversalDisabled"
                Write-LogFile " $global:FailureLabel RealTimeIsUniversal reg key installed - False"
                $ImageInfo["RealTimeIsUniversal"] = $FALSE
                return [tuple]::Create($global:WARNING, $ErrorCode)
            }
        }
        fix {
            reg add "HKEY_LOCAL_MACHINE\System\CurrentControlSet\Control\TimeZoneInformation" /v RealTimeIsUniversal /d 1 /t REG_DWORD /f
        }
    }
}
function Test-BYOL_MultipleBootPartition {
    switch ($AMIAutomation) {
        false {
            $obj = [PsCustomObject]@{
                Name        = $($MyInvocation.MyCommand.Name)
                TextLabel   = "Single bootable partition"
                FailureText = "System has multiple bootable partitions. Decrease the number of bootable partitions to one and try again."
            }
            $global:FunctionList += $obj
        }
        true {
            $partitions = Get-WmiObject -class win32_diskpartition
            $numberofBootable = ($partitions | Group-Object Bootable) | Where-Object { $_.Name -eq "True" } | Select-Object -ExpandProperty Count
            if ($numberofBootable -gt 1) {
                $ErrorCode = "MultipleBootPartition"
                Write-LogFile " $global:FailureLabel Number of bootable partition - $numberofBootable"
                return [tuple]::Create($global:FAILED, $ErrorCode)
            }
            else {
                Write-LogFile "$global:SuccessLabel Number of bootable partition - $numberofBootable"
                return [tuple]::Create($global:PASSED)
            }
        }
        fix {
            $global:OutputBox.AppendText($global:FailureText)
        }
    }
}
function Test-BYOL_64BitOS {
    switch ($AMIAutomation) {
        false {
            $obj = [PsCustomObject]@{
                Name        = $($MyInvocation.MyCommand.Name)
                TextLabel   = "OS is 64 bit"
                FailureText = "OS is not 64 bit. Try again with a 64 bit OS image."
            }
            $global:FunctionList += $obj
        }
        true {
            $OSArchitecture = (Get-WmiObject -Class Win32_ComputerSystem).SystemType
            Write-LogFile " OS Architecture - $OSArchitecture"
            $ImageInfo["OSArchitecture"] = $OSArchitecture
            if ($OSArchitecture -match 'x64') {
                Write-LogFile "$global:SuccessLabel This OS is a 64 bit OS. "
                return [tuple]::Create($global:PASSED)
            }
            else {
                $ErrorCode = "64BitOS"
                Write-LogFile $global:AdditionalOSRequirementsNotMet64BitLanguageLogMessage
                return [tuple]::Create($global:FAILED, $ErrorCode)
            }
        }
        fix {
            $global:OutputBox.AppendText($global:FailureText)
        }
    }
}
function Test-BYOL_RearmCount {
    switch ($AMIAutomation) {
        false {
            $obj = [PsCustomObject]@{
                Name        = $($MyInvocation.MyCommand.Name)
                TextLabel   = "Rearm count is 0"
                FailureText = "The rearm count of the image must not be 0."
            }
            $global:FunctionList += $obj
        }
        true {
            # If rearm count is greatet then 0 = passed
            if ((cscript C:\Windows\System32\slmgr.vbs /dlv | Out-String) -match "windows.+: ([1-9])") {
                Write-LogFile "$global:SuccessLabel The rearm count is sufficient for BYOL."
                return [tuple]::Create($global:PASSED)
            }
            else {
                $ErrorCode = "ZeroRearmCount"
                Write-LogFile " $global:FailureLabel The rearm count is not sufficient for BYOL."
                return [tuple]::Create($global:FAILED, $ErrorCode)
            }
        }
        fix {
            $global:OutputBox.AppendText($global:FailureText)
        }
    }
}
function Test-BYOL_InPlaceUpgrade {
    switch ($AMIAutomation) {
        false {
            $obj = [PsCustomObject]@{
                Name        = $($MyInvocation.MyCommand.Name)
                TextLabel   = "Image is not in-place upgraded"
                FailureText = "Image is in-place upgrade. Try again with fresh image."
            }
            $global:FunctionList += $obj
        }
        true {
            $upgradecheck = Get-ChildItem -Path HKLM:\SYSTEM\Setup | Where-Object { $_.PsChildName -match "Source OS" -or $_.PsChildName -match "Upgrade" }
            if ($upgradecheck -eq $null) {
                Write-LogFile "$global:SuccessLabel OS is Not Upgraded"
                return [tuple]::Create($global:PASSED)
            }
            else {
                $ErrorCode = "InPlaceUpgrade"
                Write-LogFile " $global:FailureLabel OS is Upgraded"
                return [tuple]::Create($global:FAILED, $ErrorCode)
            }
        }
        fix {
            $global:OutputBox.AppendText($global:FailureText)
        }
    }
}
function Test-BYOL_AVnotInstalled {
    switch ($AMIAutomation) {
        false {
            $obj = [PsCustomObject]@{
                Name        = $($MyInvocation.MyCommand.Name)
                TextLabel   = "Antivirus is not installed"
                FailureText = "Antivirus is installed. Uninstall Antivirus $AVname."
            }
            $global:FunctionList += $obj
        }
        true {
            # No Antivirus should be installed, exept "Windows Defender"
            $AVname = (Get-WmiObject -Namespace "root\SecurityCenter2" -Class AntiVirusProduct).displayName | Where-Object { $_ -NotLike "Windows Defender" }
            if ($AVname -eq $null) {
                Write-LogFile "$global:SuccessLabel Antivirus is not installed"
                return [tuple]::Create($global:PASSED)
            }
            else {
                $ErrorCode = "AntiVirusInstalled"
                Write-LogFile " $global:FailureLabel Antivirus is installed. Detected Antivirus name $AVname."
                return [tuple]::Create($global:FAILED, $ErrorCode)
            }
        }
        fix {
            $global:OutputBox.AppendText($global:FailureText)
        }
    }
}

function Test-BYOL_BootMode_UEFI {
    switch ($AMIAutomation) {
        false {
            $obj = [PsCustomObject]@{
                Name        = $($MyInvocation.MyCommand.Name)
                TextLabel   = "BYOL Image Import with UEFI Bootmode"
                FailureText = "Windows 10 image with UEFI Boot mode is not supported for Image Import"
            }
            $global:FunctionList += $obj
        }
        true {
            if ((Validate-UEFIBootEnabled) -and ($global:OSCheck -like "*Windows 10*")) {
                $ErrorCode = "UEFINotSupported"
                Write-LogFile " $global:FailureLabel Windows 10 image with UEFI Boot mode is not supported for BYOL Image Import"
                return [tuple]::Create($global:FAILED, $ErrorCode)
            }
            else {
                Write-LogFile "$global:SuccessLabel The image with UEFI Boot mode is supported for BYOL Image Import"
                return [tuple]::Create($global:PASSED)
            }
        }
        fix {
            $global:OutputBox.AppendText($global:FailureText)
        }
    }
}

function Init-BYOLCheckerRegkey {
    try {
        Get-Item HKLM:\Software\Amazon\BYOLChecker -ErrorAction Stop | Out-Null
    }
    catch {
        New-Item "HKLM:\Software\Amazon\BYOLChecker" -Force | Out-Null
    }
}
function Write-BYOLCheckerRegkey {
    Init-BYOLCheckerRegkey
    New-ItemProperty "HKLM:\Software\Amazon\BYOLChecker" -Name version -Value $ScriptVersion -Force
    New-ItemProperty "HKLM:\Software\Amazon\BYOLChecker" -Name status -Value $status -Force
    New-ItemProperty "HKLM:\Software\Amazon\BYOLChecker" -Name date -Value $fileTimestamp -Force
}
function Test-RegistryValue {
    param (
        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]$Path,
        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]$Value
    )
    try {
        Get-ItemProperty -Path $Path -ErrorAction Stop | Select-Object -ExpandProperty $Value -ErrorAction Stop | Out-Null
        return $true
    }
    catch {
        return $false
    }
}
function Get-BYOLCheckerRegkey {
    $BYOLCheckerRegkey = "HKLM:\Software\Amazon\BYOLChecker"

    if (Test-RegistryValue -Path $BYOLCheckerRegkey -Value 'Status') {
        $Resp = Get-ItemProperty $BYOLCheckerRegkey
        $Message = "SUCCESS : $($Resp.status) - BYOLChecker version $($Resp.version) was executed on $($Resp.date)"
    }
    else {
        $Message = "WARNING : Offline BYOLChecker has not validated the image"
    }
    Write-LogFile -Type Information -Message $Message
}
function Write-LogFile {
    Param ([string]$logstring)
    try {
        $currentTime = Get-Date
        Add-content $Logfile -Encoding Unicode -Value "$currentTime $logstring"
    }
    catch {
        # if the logs themselves give an error in logging. Simply, writing to host.
        Write-Host $_.Exception.Message
    }
}
function Get-RandomCharacters($length, $characters) {
    # function used for generating a random password
    $random = 1..$length | ForEach-Object { Get-Random -Maximum $characters.length }
    $private:ofs = ""
    return [String]$characters[$random]
}
function Optimize-String([string]$inputString) {
    # function used for generating a random password
    $characterArray = $inputString.ToCharArray()
    $OptimizedStringArray = $characterArray | Get-Random -Count $characterArray.Length
    $outputString = -join $OptimizedStringArray
    return $outputString
}
function New-Password {
    # function used for generating a random password
    $password = Get-RandomCharacters -length 10 -characters 'abcdefghiklmnoprstuvwxyz'
    $password += Get-RandomCharacters -length 1 -characters 'ABCDEFGHKLMNOPRSTUVWXYZ'
    $password += Get-RandomCharacters -length 1 -characters '1234567890'
    $password += Get-RandomCharacters -length 1 -characters '!"§$%&/()=?}][{@#*+'
    $password = Optimize-String $password
    return $password
}
function New-WorkSpaces_BYOL_User {
    $password = New-Password
    NET USER "Workspaces_BYOL" $password /add | Out-Null
    NET LOCALGROUP "Administrators" "Workspaces_BYOL" /add | Out-Null
    $global:OutputBox.AppendText("`nNew User WorkSpaces_BYOL has been Startd.`nPlease copy and retain the following `nWorkspaces_BYOL/$password `n`n")
}
function SaveImageInfo {
    $InfoInJson = $ImageInfo | ConvertTo-Json
    Set-Content $Infofile -Encoding Unicode -Value $InfoInJson
}
function Set-EC2Config {
    # Enable execution of user data on bootup
    $configPath = "C:\Program Files\Amazon\Ec2ConfigService\Settings\config.xml"
    if (Test-Path $configPath) {
        Write-LogFile -Type Information -Message "Configuring EC2Config Settings & Config"
        $configFile = Get-Item $configPath
        $configXml = [xml](Get-Content $configFile)
        $pluginList = $configXml.Ec2ConfigurationSettings.Plugins.Plugin
        foreach ($plugin in $pluginList) {
            switch ($plugin.Name) {
                "Ec2HandleUserData" { $plugin.state = "Enabled" }
                default { }
            }
        }
        $globalSettings = $configXml.Ec2ConfigurationSettings.GlobalSettings
        $globalSettings.SetDnsSuffixList = "false"
        $configXml.save($configPath)
        Write-LogFile -Type Information -Message "Deleting old UserData Scripts"
        if (Test-Path "C:\Program Files\Amazon\Ec2ConfigService\Scripts\UserScript.ps1") {
            Remove-Item "C:\Program Files\Amazon\Ec2ConfigService\Scripts\UserScript.ps1" -Force
        }
    }
    else {
        Write-LogFile -Type Information -Message "Cannot find EC2Config config file at $configPath. Skipping EC2Config"
    }
}
function Set-EC2LaunchConfig {
    #Setting the ComputerName parameter to true.
    Write-LogFile -Type Information -Message "Updating Launch config file"
    $launchPath = "C:\ProgramData\Amazon\EC2-Windows\Launch\Config\LaunchConfig.json"
    if (Test-Path $launchPath) {
      $ConfigFile = Get-Content -Path $launchPath -Raw | ConvertFrom-Json
      if ($ConfigFile.setComputerName -ne $false) {
        $ConfigFile.setComputerName = $false
      }
      if ($ConfigFile.setWallpaper -ne $false) {
        $ConfigFile.setWallpaper = $false
      }
      if ($ConfigFile.AddDnsSuffixList -ne $false) {
          $ConfigFile.AddDnsSuffixList = $false
      }
      ConvertTo-Json -InputObject $ConfigFile | Set-Content $launchPath
  }
  else {
    Write-LogFile -Type Information -Message "Cannot find EC2Launch config file at $launchPath. Skipping EC2Launch config"
  }
}
function Set-EC2Launchv2Config {
    #Setting the ComputerName parameter to true.
    Write-LogFile -Type Information -Message "Updating EC2Launch agent-config file"
    $launchv2Path = "C:\ProgramData\Amazon\EC2Launch\config\agent-config.yml"
    if (Test-Path $launchv2Path) {
        $ConfigFile = & "C:\Program Files\Amazon\EC2Launch\EC2Launch.exe" get-agent-config --format json | ConvertFrom-Json
        $Stages = $ConfigFile.config
        for($i = 0; $i -lt $Stages.Count; $i++){
            switch($Stages.stage[$i]){
            "preReady"
            {
                $task = $Stages[$i].tasks
                for($j = 0; $j -lt $task.Count; $j++){
                    if($task[$j].task -match "setDnsSuffix"){
                        $task= $task | Where-Object{$_.task -ne "setDnsSuffix"}
                    }
                    if($task[$j].task -match "setWallpaper"){
                        $task= $task | Where-Object{$_.task -ne "setWallpaper"}
                    }
                }
                $Stages[$i].tasks = @($task)
                break
            }
            "postReady"{
                $task = $Stages[$i].tasks
                for($j = 0; $j -lt $task.Count; $j++){
                    if($task[$j].task -match "setHostName"){
                        $task= $task | Where-Object{$_.task -ne "setHostName"}
                    }
                }
                $Stages[$i].tasks = @($task)
                break
            }
            }
        }
      $ConfigFile.config = $Stages
      $ConfigFile | ConvertTo-Json -Depth 6 | Out-File -encoding UTF8 -FilePath $launchv2Path
    }
    else {
        Write-LogFile -Type Information -Message "Cannot find EC2Launchv2 config file at $launchv2Path. Skipping EC2launchv2 config"
    }
}
function Validate-UEFIBootEnabled {
    #Validate if UEFI Boot is enabled on the Instance
    $Bootmode = bcdedit | Select-String "path.*efi"
    If ($Bootmode){
        return $true
    }
    else{
        return $false
    }
}
function Test-RunAsAdmin {
    $RuAsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (!($RuAsAdmin)) {
        Add-Type -AssemblyName System.Windows.Forms
        # show the MsgBox:
        $result = [System.Windows.Forms.MessageBox]::Show(
            'Administrator rights are required to run this script.
Open a PowerShell session that is running as Administrator, and rerun the script.
For more information, see https://docs.aws.amazon.com/workspaces/latest/adminguide/byol-windows-images.html
'
            , 'Error', 'OK', 16)
        exit
    }
}
function Set-OSFunctions {
    # Create Function List based on OS Version
    switch ([environment]::OSVersion.Version.Major) {
        6 { $ExemptFunct = $WIN7ExemptedFunctions }
        10 { $ExemptFunct = $WIN10ExemptedFunctions }
    }
    $global:ListFunctions = $ListFunctionsAll | Where-Object { $ExemptFunct -NotContains $_ }
}
function Disable-Hibernation {
    # Disabling Hibernations
    powercfg.exe /hibernate off
    Write-LogFile "Disabled hibernation"
}
function Reset-Ec2LaunchV2 {
    # Reset Ec2LaunchV2 so that the state files are removed and the user-data is executed on the next launch
    $stateFilePath = "C:\ProgramData\Amazon\EC2Launch\state"
    if(Test-Path -path $stateFilePath){
        $stateFiles = Get-ChildItem -Path $stateFilePath
        If($stateFiles){
            Write-LogFile "Found Ec2LaunchV2 files. Reset Ec2LaunchV2 agent."
            $Exitcode = (Start-Process -FilePath "C:\Program Files\Amazon\EC2Launch\EC2Launch.exe" -Args "reset -c" -Wait -PassThru).ExitCode
            if($Exitcode -eq 0){
                Write-LogFile  "Reset Ec2LaunchV2 completed sucessfully"
            }else{
                Write-LogFile "Reset Ec2LaunchV2 failed with exit code $($Exitcode)"
                exit;
            }
        }else{
            Write-LogFile "Ec2LaunchV2 state files does not exist. Ec2lauchv2 reset not required"
        }
    }else{
        Write-LogFile "Ec2LaunchV2 path '$stateFilePath' does not exist. Ec2lauchv2 reset not required"
    }
}
function Set-AutomationFunctions {
    # Create Function List for AMIAutomation workflow (exclude functions not needed)
    $global:ListFunctions = $global:ListFunctions | Where-Object { $AutomationExemptFunctions -NotContains $_ }
}
# Display Results of test in the form
function ClearOutputBox {
    $global:OutputBox.clear()
}
function Button_Click {
    #start writing results to log
    Write-LogFile (get-date)

    $mainPanel.Controls.Add($progressBarLabel)
    $mainPanel.Controls.Add($progressBar)

    clearOutputBox

    #Reset Office Key
    Remove-ItemProperty "HKLM:\Software\Amazon\BYOLChecker" -Name SkipOfficePopup -Force -ea SilentlyContinue

    #place holder text
    $global:OutputBox.AppendText("Running Tests... This could take a few minutes to complete.")

    $TestResults = New-Object System.Collections.ArrayList
    For ($i = 0; $i -lt $global:CHECK_COUNT; $i++) {
        $ResultLabels.Item($i).forecolor = "Black"
        $ResultLabels.Item($i).text = "Checking.."
        $CommandName = $ListFunctions.Get($i)
        Write-LogFile "Beginning test : ${CommandName}"
        try {
            if ( ${CommandName} -eq "checkHotFixesInstalled") {
                $global:OutputBox.AppendText("`n`Running Tests... UI may be unresponsive for this section.. Please Wait..")
            }
            $scriptResult = (Get-Item "function:$CommandName").ScriptBlock.Invoke();
            if ($CommandName -eq "checkHotFixesInstalled") {
                clearOutputBox
                $global:OutputBox.AppendText("Running Tests... This could take a few minutes to complete")
            }
        }
        catch {
            Write-LogFile $_
            if ($scriptResult -eq $null) {
                Write-LogFile " ${CommandName} failed with an exception"
                $scriptResult = $global:FAILED;
            }
        }
        Write-LogFile "Ending test : ${CommandName}"
        $TestResults.Add($scriptResult.Item1)
        $progressBar.value = (100 / $global:CHECK_COUNT) * ($i + 1)
        switch ($TestResults.Item($i)) {
            PASSED {
                $ResultLabels.Item($i).ForeColor = "Green"
                $ResultLabels.Item($i).Text = $global:PASSED
                $TroubleButtons.Item($i).Visible = $false
            }
            FAILED {
                $ResultLabels.Item($i).ForeColor = "Red"
                $ResultLabels.Item($i).Text = $global:FAILED
                $FailureText = $FailureLabelTexts.Get($i)
                $ClickFunction = {
                    $global:OutputBox.clear()
                    $global:OutputBox.AppendText($FailureText)
                }.GetNewClosure()
                $TroubleButtons.Item($i).Visible = $true
                $TroubleButtons.Item($i).Add_Click($ClickFunction)
                $FailedFlag ++
                Write-Host "Failed function: $CommandName"
            }
            WARNING {
                $ResultLabels.Item($i).ForeColor = "DarkOrange"
                $ResultLabels.Item($i).Text = $global:WARNING
                $FailureText = $FailureLabelTexts.Get($i)
                $ClickFunction = {
                    $global:OutputBox.clear()
                    $global:OutputBox.AppendText($FailureText)
                }.GetNewClosure()

                $ClickFunctionFix = {
                    $AMIAutomation = "fix"
                    Get-Date | Out-Host
                    $ListFunctions.Get($i) | Out-Host
                    $global:BYOLFunctions.Get($i).Name
                    $global:OutputBox.clear()
                    $global:OutputBox.AppendText("Fixing")
                }.GetNewClosure()

                $TroubleButtons.Item($i).Visible = $true
                $TroubleButtons.Item($i).Add_Click($ClickFunction)

                $global:failedIndexList = $failedIndexList + $i
                $FixButtons.Item($i).Add_Click( { button_Click2 $failedIndexList })
                $ButtonFix.Visible = $true
                if (-not ($CommandName -in $warningExemptedFunctions)) {
                    $WarningFlag ++
                }
            }
            Default {
                $global:OutputBox.AppendText("Unable to return results")
            }
        }
        $script:form.Refresh()
    }
    clearOutputBox
    $global:OutputBox.AppendText("Done")
    SaveImageInfo
    if ($FailedFlag -gt 0 -or $WarningFlag -gt 0) {
        $status = "fail"
    }
    else {
        $status = "success"
    }

    # EC2Launchv2 / EC2Launch/ EC2Config agent to be configured based on operating system
    if ($global:OSCheck -like "*Server 2016*" -and $global:OSCheck -like "*Server 2019*"){
        Set-EC2LaunchConfig
    }
    elseif ((Validate-UEFIBootEnabled) -or ($global:OSCheck -like "*Windows 11*")){
        Set-EC2Launchv2Config
    }
    else{
        Set-EC2Config
    }

    Write-BYOLCheckerRegkey

    If ($status -eq "success") {
        $mainPanel.Visible = $false
        # New Panel
        $Panel2.Controls.Add($script:TextBox2)
        $Panel2.Controls.Add($script:textBox3)
        $Panel2.Controls.Add($script:textBox4)
        $Panel2.Controls.Add($script:textBox5)
        $Panel2.Controls.Add($script:textBox6)
        $Panel2.Controls.Add($script:textBox7)
        $Panel2.Controls.Add($script:textBox8)
        $Panel2.Controls.Add($script:textBox9)
        $Panel2.Controls.Add($script:textBox10)
        $Panel2.Controls.Add($LinkLabel3)
        $Panel2.Controls.Add($LinkLabel4)
        $Panel2.Controls.Add($ButtonSys)
        $Panel2.Visible = $true
    }
    $mainPanel.Controls.Remove($progressBar)
}
function Button_Click2 {
    clearOutputBox
    $AMIAutomation = "fix"
    foreach ($failedIndex in $failedIndexList) {
        & $ListFunctions.Get($failedIndex) #-AMIAutomation fix
        $outputbox.appendtext("`nFixing $($ListFunctions.Get($failedIndex))")
    }
    $outputbox.appendtext("`nFixing Completed. `nRerun the Tests")
    $Button1.Text = "Rerun Tests"
    $ButtonFix.Visible = $false
}
function Button_Click3 {
    #clearOutputBox
    Run-Sysprep
    $script:SysprepErrorFileEntry = "Running Sysprep "
    $global:sysprepExe = "success"

    if ($global:sysprepExe -eq "success") {
        # New Panel
        $Panel2.Visible = $false
        $Text = "Sysprep started"
        $TextBox = New-TexBox 0 40 500 30 $Text "29, 129, 2" "Arial" 14 Regular "TopLeft"
        $Panel3.Controls.Add($TextBox)
        $Panel3.Visible = $true
        $script:t = 0
        $outputbox1.appendtext("$script:SysprepErrorFileEntry")
        do {
            $script:t++
            Get-SysprepLogs
            Start-Sleep 2
        }
        while ($script:t -lt $global:sysprepTimeRun)
    }
}
# Display Results of test to form
# Form section
function New-Form {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    # Changing AMIAutomation to true to run the functions
    $AMIAutomation = $true
    $TestLabelTexts = $FunctionList.TextLabel
    $FailureLabelTexts = $FunctionList.FailureText
    $global:CHECK_COUNT = $FunctionList.Count

    # Build Form
    $Form = New-Object System.Windows.Forms.Form
    $Form.Text = "Amazon WorkSpaces Image Validation"
    $Form.Size = New-Object System.Drawing.Size(550, 900)
    $Form.MaximumSize = New-Object System.Drawing.Size(550, 1000)
    $form.FormBorderStyle = "Sizable"
    $Form.StartPosition = "WindowsDefaultLocation"
    $Form.Topmost = $False
    $Form.ShowInTaskbar = $True
    $Form.AutoSizeMode = "GrowAndShrink"
    $Form.SizeGripStyle = "auto"
    $Form.AutoScroll = $True
    $iconPath = "${PSScriptRoot}\workspacesIcon.ico"
    $icon = [system.drawing.icon]::ExtractAssociatedIcon($iconPath)
    $Form.Icon = $icon
    $script:form = $Form;
    # Main Panel
    $mainPanel = new-panel mainPanel
    $Form.Controls.Add($mainPanel)

    $Panel2 = new-panel panel2
    $Form.Controls.Add($Panel2)

    $Panel3 = new-panel Panel3
    $Form.Controls.Add($Panel3)

    # Big buttons
    # Add big buttons
    $Button1 = New-Object System.Windows.Forms.Button
    $Button1.Anchor = "top" , "left"
    $locX = $mainPanel.Location.X
    $locY = $mainPanel.Location.Y + 22
    $Button1.Location = New-Object System.Drawing.Point $locX , $locY
    $Button1.Size = New-Object System.Drawing.Size(100, 30)
    $Button1.Text = "Begin Tests"
    $Font = New-Object System.Drawing.Font("Arial", 10, [System.Drawing.FontStyle]::Bold)
    $Button1.Font = $Font
    $Button1.ForeColor = "255, 255, 255"
    $Button1.BackColor = "67, 96, 140"

    $ButtonFix = New-Object System.Windows.Forms.Button
    $ButtonFix.Anchor = "top" , "left"
    $locX = $mainPanel.Location.X + 105
    $locY = $mainPanel.Location.Y + 22
    $ButtonFix.Location = New-Object System.Drawing.Point $locX , $locY
    $ButtonFix.Size = New-Object System.Drawing.Size(130, 30)
    $ButtonFix.Text = "Fix All Warnings"
    $Font = New-Object System.Drawing.Font("Arial", 10, [System.Drawing.FontStyle]::Bold)
    $ButtonFix.Font = $Font
    $ButtonFix.BackColor = "Orange"
    $ButtonFix.Visible = $false

    $ButtonSys = New-Object System.Windows.Forms.Button
    $ButtonSys.Anchor = "top" , "left"
    $locX = $Panel2.Location.X
    $locY = $Panel2.Location.Y + 325
    $ButtonSys.Location = New-Object System.Drawing.Point $locX , $locY
    $ButtonSys.Size = New-Object System.Drawing.Size(100, 30)
    $ButtonSys.Text = "Run Sysprep"
    $Font = New-Object System.Drawing.Font("Arial", 10, [System.Drawing.FontStyle]::Bold)
    $ButtonSys.Font = $Font
    $ButtonSys.ForeColor = "255, 255, 255"
    $ButtonSys.BackColor = "67, 96, 140"
    $ButtonSys.Visible = $true

    $progressBarLabel = New-Object System.Windows.Forms.label
    $progressBarLabel.Anchor = "top", "right"
    $locX = $mainPanel.Location.X + 0.55 * $mainPanel.Size.Width
    $locY = $mainPanel.Location.Y + 5
    $progressBarLabel.Location = New-Object System.Drawing.Point $locX , $locY
    $progressBarLabel.AutoSize = $True
    $progressBar = New-Object System.Windows.Forms.ProgressBar
    $progressBar.Anchor = "top", "right"
    $progressBar.Value = 0
    $progressBar.Style = "Continuous"
    $locX = $mainPanel.Location.X + 0.5 * $mainPanel.Size.Width
    $locY = $mainPanel.Location.Y + 22
    $progressBar.Location = New-Object System.Drawing.Point $locX , $locY
    $progressBar.Size = New-Object System.Drawing.Size(170, 30)

    #Add big buttons to form
    $mainPanel.Controls.Add($Button1)
    $mainPanel.Controls.Add($ButtonFix)
    $mainPanel.Controls.Add($script:textBox1)

    #Add Button event
    $Button1.Add_Click( { Button_Click })
    $ButtonFix.Add_Click( { Button_Click2 })
    $ButtonSys.Add_Click( { Button_Click3 })

    # Output Box
    $global:OutputBox = New-Object System.Windows.Forms.RichTextBox
    $locX = $mainPanel.Location.X
    $locY = $mainPanel.Location.Y + 82
    $global:OutputBox.Location = New-Object System.Drawing.Point $locX , $locY
    $global:OutputBox.Size = New-Object System.Drawing.Size(420, 60)
    $mainPanel.Controls.Add($global:OutputBox)

    # Output Box1
    $global:OutputBox1 = New-Object System.Windows.Forms.RichTextBox
    $locX = $Panel3.Location.X
    $locY = $Panel3.Location.Y + 100
    $global:OutputBox1.Location = New-Object System.Drawing.Point $locX , $locY
    $global:OutputBox1.Size = New-Object System.Drawing.Size(500, 400)
    $Panel3.Controls.Add($global:OutputBox1)

    # Test Labels
    $TestLabels = New-Object System.Collections.ArrayList

    For ($i = 0; $i -lt $global:CHECK_COUNT; $i++) {
        $TestLabel = New-Object System.Windows.Forms.label
        $TestLabel.Anchor = "top" , "left"
        $locX = $mainPanel.Location.X
        $locY = $mainPanel.Location.Y + 130 + ($i + 1) * 22
        $TestLabel.Location = New-Object System.Drawing.Point $locX, $locY
        $TestLabel.Text = $TestLabelTexts.Get($i)
        $TestLabel.AutoSize = $true
        $TestLabels.Add($TestLabel)
        $mainPanel.Controls.Add($TestLabel)
    }
    # Results Labels
    $ResultLabels = New-Object System.Collections.ArrayList
    #Add results labels
    For ($i = 0; $i -lt $global:CHECK_COUNT; $i++) {
        $ResultLabel = New-Object System.Windows.Forms.label
        $ResultLabel.Anchor = "top", "right"
        $locX = $mainPanel.Location.X + 0.65 * $mainPanel.Size.Width
        $locY = $mainPanel.Location.Y + 130 + ($i + 1) * 22
        $ResultLabel.Location = New-Object System.Drawing.Point $locX , $locY
        $ResultLabel.Text = "To be tested"
        $ResultLabel.AutoSize = $True
        $ResultLabels.Add($ResultLabel)
        $mainPanel.Controls.Add($ResultLabel)
    }
    $TroubleButtons = New-Object System.Collections.ArrayList
    # Add info buttons
    For ($i = 0; $i -lt $global:CHECK_COUNT; $i++) {
        $TroubleButton = New-Object System.Windows.Forms.Button
        $TroubleButton.Anchor = "top" , "right"
        $locX = $mainPanel.Location.X + 0.80 * $mainPanel.Size.Width
        $locY = $mainPanel.Location.Y + 130 + ($i + 1) * 22
        $TroubleButton.Location = New-Object System.Drawing.Point $locX , $locY
        $TroubleButton.Size = New-Object System.Drawing.Size(50, 20)
        $TroubleButton.Text = "Info..."
        $TroubleButton.Visible = $false
        $TroubleButtons.Add($TroubleButton)
        $mainPanel.Controls.Add($TroubleButton)
    }
    # Add fix buttons
    $FixButtons = New-Object System.Collections.ArrayList
    For ($i = 0; $i -lt $global:CHECK_COUNT; $i++) {
        $FixButton = New-Object System.Windows.Forms.Button
        $FixButton.Anchor = "top" , "right"
        $locX = $mainPanel.Location.X + 0.89 * $mainPanel.Size.Width
        $locY = $mainPanel.Location.Y + 130 + ($i + 1) * 22
        $FixButton.Location = New-Object System.Drawing.Point $locX , $locY
        $FixButton.Size = New-Object System.Drawing.Size(50, 20)
        $FixButton.Text = "Fix..."
        $FixButton.Visible = $false
        $FixButtons.Add($FixButton)
        $mainPanel.Controls.Add($FixButton)
    }
    $lastTestLocation = [System.Windows.Forms.label]$TestLabels[-1]
    # Link Labels
    # Add Link labels
    $LinkLabel1 = New-Object System.Windows.Forms.LinkLabel
    $locX = $mainPanel.Location.X
    $locY = $lastTestLocation.Location.Y + 35
    $LinkLabel1.Location = New-Object System.Drawing.Point $locX , $locY
    $LinkLabel1.AutoSize = $True
    $LinkLabel1.LinkColor = "BLUE"
    $LinkLabel1.ActiveLinkColor = "RED"
    $LinkLabel1.Text = "AWS VM Import Prerequisite Page"
    $LinkLabel1.add_Click( { [system.Diagnostics.Process]::start("http://docs.aws.amazon.com/AWSEC2/latest/UserGuide/VMImportPrerequisites.html") })

    $LinkLabel2 = New-Object System.Windows.Forms.LinkLabel
    $locX = $mainPanel.Location.X
    $locY = $lastTestLocation.Location.Y + 52
    $LinkLabel2.Location = New-Object System.Drawing.Point $locX , $locY
    $LinkLabel2.AutoSize = $True
    $LinkLabel2.LinkColor = "BLUE"
    $LinkLabel2.ActiveLinkColor = "RED"
    $LinkLabel2.Text = "Windows Management Framework 4.0 (For All Other Windows OS)"
    $LinkLabel2.add_Click( { [system.Diagnostics.Process]::start("https://www.microsoft.com/en-au/download/details.aspx?id=40855") })

    $Text = "Note: All tests must PASS for WorkSpaces image validation to succeed"
    $script:textBox1 = New-TexBox 10 62 500 20 $Text "black" "Arial" 9 Bold "TopLeft"

    $Text = "Validation successful"
    $script:textBox2 = New-TexBox 0 40 500 20 $Text "29, 129, 2" "Arial" 14 Regular "TopLeft"

    $Text = "Review the following locale settings:"
    $script:textBox3 = New-TexBox 0 70 500 20 $Text "black" "Arial" 12 Regular "TopLeft"

    $Text = "$([char]0x2022) System Locale :`n$([char]0x2022) User Locale:"
    $script:textBox4 = New-TexBox 0 95 140 50 $Text "black" "Arial" 12 Regular "TopLeft"

    $Text = "$global:SystemLocale`n$global:UserLocale"
    $script:textBox5 = New-TexBox 140 95 60 50 $Text "black" "Arial" 12 Regular "TopLeft"

    $Text = "Proceed to run the Sysprep"
    $script:textBox6 = New-TexBox 0 210 500 20 $Text "black" "Arial" 12 Bold "TopLeft"

    $Text = "Once Sysprep completes, your system will shut down"
    $script:textBox7 = New-TexBox 0 240 400 20 $Text "black" "Arial" 12 Regular "TopLeft"

    $Text = "Follow the remaining instructions to complete importing BYOL image"
    $script:textBox8 = New-TexBox 0 260 510 20 $Text "black" "Arial" 12 Regular "TopLeft"

    $LinkLabel4 = New-Object System.Windows.Forms.LinkLabel
    $locX = 0
    $locY = 280
    $LinkLabel4.Location = New-Object System.Drawing.Point $locX , $locY
    $LinkLabel4.AutoSize = $True
    $LinkLabel4.LinkColor = "BLUE"
    $LinkLabel4.ActiveLinkColor = "RED"
    $LinkLabel4.Text = "BYOL Administration Guide"
    $Font = New-Object System.Drawing.Font("Arial", 12, [System.Drawing.FontStyle]::Regular)
    $LinkLabel4.Font = $Font
    $LinkLabel4.TextAlign = "TopLeft"
    $LinkLabel4.add_Click( { [system.Diagnostics.Process]::start("https://docs.aws.amazon.com/workspaces/latest/adminguide/byol-windows-images.html") })

    $Text = "I want to change locale settings"
    $script:textBox9 = New-TexBox 0 400 500 20 $Text "black" "Arial" 12 Bold "TopLeft"

    $LinkLabel3 = New-Object System.Windows.Forms.LinkLabel
    $locX = 0
    $locY = 420
    $LinkLabel3.Location = New-Object System.Drawing.Point $locX , $locY
    $LinkLabel3.AutoSize = $True
    $LinkLabel3.LinkColor = "BLUE"
    $LinkLabel3.ActiveLinkColor = "RED"
    $LinkLabel3.Text = "View guide"
    $Font = New-Object System.Drawing.Font("Arial", 12, [System.Drawing.FontStyle]::Regular)
    $LinkLabel3.Font = $Font
    $LinkLabel3.add_Click( { [system.Diagnostics.Process]::start("https://msdn.microsoft.com/en-us/library/windows/hardware/dn965674(v=vs.85).aspx") })

    $LinkLabel5 = New-Object System.Windows.Forms.LinkLabel
    $LinkLabel5.AutoSize = $True
    $LinkLabel5.LinkColor = "BLUE"
    $LinkLabel5.ActiveLinkColor = "RED"
    $LinkLabel5.Text = "Sysprep Logs"
    $LinkLabel5.add_Click( { [system.Diagnostics.Process]::start("C:\Windows\System32\sysprep\Panther\setuperr.log") })

    # Add link labels to form
    $mainPanel.Controls.Add($LinkLabel1)
    $mainPanel.Controls.Add($LinkLabel2)
    $mainPanel.Controls.Add($script:TextBox1)

    # Show the Form (do this at the end of the function)
    $form.ShowDialog() | Out-Null
}
function New-Panel ($pannelName) {
    New-Variable -Name $pannelName -Force -Scope Global
    $global:pannelName = New-Object Windows.Forms.Panel
    $global:pannelName.Anchor = "top", "left"
    $global:pannelName.Size = New-Object System.Drawing.Size (500, 840)
    $locX = $global:pannelName.Location.X + 10
    $locY = $global:pannelName.Location.Y + 5
    $global:pannelName.Location = New-Object System.Drawing.Point $locX, $locY
    return $global:pannelName
}
Function New-TexBox ($x, $y, $sizeX, $sizeY, $text, $color, $font, $fontSize, $FontStyle, $textAlign) {
    # function to create Text Box for Form
    $TextBox = New-Object System.Windows.Forms.Label
    $locX = $Panel.Location.X + $x
    $locY = $Panel.Location.Y + $y
    $TextBox.Location = New-Object System.Drawing.Point $locX , $locY
    $TextBox.Size = New-Object System.Drawing.Size($sizeX, $sizeY)
    $Font = New-Object System.Drawing.Font($Font, $fontSize, [System.Drawing.FontStyle]::$FontStyle)
    $TextBox.Font = $Font
    $TextBox.TextAlign = $textAlign
    $TextBox.ForeColor = $color
    $TextBox.Text = $text
    return $TextBox
}
function Get-OOBE {
    $systemInfo = Get-WmiObject Win32_OperatingSystem
    $global:RegisteredOrganization = [string]$systemInfo.Organization
    $global:RegisteredOwner = [string]$systemInfo.RegisteredUser
    $global:SystemLocale = Get-Culture | Select -ExpandProperty name
    $global:UserLocale = Get-UICulture | Select -ExpandProperty name
}
function Set-OOBE {
    $xml = [xml](Get-Content $global:OOBEfile)
    $xmlElement = $xml.get_DocumentElement()
    $xmlSetting = (($xmlElement.settings | Where-Object { $_.Pass -eq "oobeSystem" }).Component | Where-Object { $_.Name -eq "Microsoft-Windows-International-Core" })
    $xmlSetting.InputLocale = "$global:SystemLocale"
    $xmlSetting.SystemLocale = "$global:SystemLocale"

    $xmlSetting.UILanguage = "$global:UserLocale"
    $xmlSetting.UserLocale = "$global:UserLocale"

    $xmlSetting = (($xmlElement.settings | Where-Object { $_.Pass -eq "oobeSystem" }).Component | Where-Object { $_.Name -eq "Microsoft-Windows-Shell-Setup" })
    $xmlSetting.RegisteredOrganization = $RegisteredOrganization
    $xmlSetting.RegisteredOwner = $RegisteredOwner
    $xmlSetting = (($xmlElement.settings | Where-Object { $_.Pass -eq "specialize" }).Component | Where-Object { $_.Name -eq "Microsoft-Windows-Shell-Setup" })
    $xmlSetting.RegisteredOrganization = $RegisteredOrganization

    $xml.save($global:OOBEfile)
}
function Run-Sysprep {
    Set-OOBE
    # Clear sysprep logs before running it
    $script:SysprepErrorFileLocation = "C:\Windows\system32\sysprep\Panther\setuperr.log"
    if (test-path $script:SysprepErrorFileLocation) {
        Remove-Item $script:SysprepErrorFileLocation -Force -ErrorAction SilentlyContinue
    }
    $script:SysprepSuccededTag = "C:\Windows\system32\sysprep\Sysprep_succeeded.tag"
    if (test-path $script:SysprepSuccededTag) {
        Remove-Item $script:SysprepSuccededTag -Force -ErrorAction SilentlyContinue
    }
    Write-host "Syspreping ..."
    if ((Get-Service -Name Schedule).Status -ne "Running") {
        Start-Service Schedule
    }
    # The task is ran once on demand to execute sysprep under system context to mimic IMS process and will delete on completion
    $argList = "/RL HIGHEST /Create /RU `"SYSTEM`" /TN `"sysprep`" /SC `"ONEVENT`" /F /EC Application /MO *[System/EventID=777777] /TR `"'C:\Windows\System32\Sysprep\sysprep.exe' /oobe /generalize /shutdown /quiet /unattend:$global:OOBEfile`""
    Start-process "C:\Windows\System32\schtasks.exe" -ArgumentList $argList -Wait -WindowStyle Hidden
    Start-process "C:\Windows\System32\schtasks.exe" -ArgumentList "/Run /tn `"sysprep`"" -Wait -WindowStyle Hidden
    Start-process "C:\Windows\System32\schtasks.exe" -ArgumentList "/Delete /tn `"sysprep`" /f" -WindowStyle Hidden
}
function Get-SysprepLogs {

    If ((Test-Path $script:SysprepErrorFileLocation) -and $null -ne (Get-Content -Path $script:SysprepErrorFileLocation)) {
        $Panel3.Controls.Remove($TextBox)
        $Text = "Sysprep failed"
        $TextBox11 = New-TexBox 0 40 200 30 $Text "red" "Arial" 14 Regular "TopLeft"
        $Panel3.Controls.Add($TextBox11)
        $Panel3.Visible = $true

        $global:OutputBox1.clear()
        $script:SysprepErrorFileEntry = ((Get-Content -Path $SysprepErrorFileLocation) | Select-String -Pattern "error", "fail" | Select-Object -Last 10)
        $outputbox1.Controls.Add($LinkLabel5)

        foreach ($line in $script:SysprepErrorFileEntry) {
            $text = "`n`n$line"
            $outputbox1.appendtext($text)
        }

        $script:t = $global:sysprepTimeRun
        $outputbox1.appendtext("`n`nOpening sysprep error log file in a separate window")
        Invoke-Item $SysprepErrorFileLocation
    }
    if (Test-Path $script:SysprepSuccededTag) {
        $Panel3.Controls.Remove($TextBox11)
        $Text = "Sysprep succeeded"
        $TextBox12 = New-TexBox 0 40 200 30 $Text "green" "Arial" 14 Regular "TopLeft"
        $Panel3.Controls.Add($TextBox12)
        $Panel3.Visible = $true
        $global:OutputBox1.clear()
        $outputbox1.appendtext("Sysprep succeeded. System will shutdown in 5 sec")
        shutdown.exe /s /f /t 5
    }
    else {
        $outputbox1.appendtext(" .")
    }
}

function main {
    # get all functions that will validate the system
    try {
        $ListFunctionsAll = (Get-BYOLFunctions).Name
        # AMI Automation condition is used for AMI Automation Workflow
        Set-OSFunctions
        if ($AMIAutomation) {
            . "${PSScriptRoot}\helper.ps1"
            Set-AutomationFunctions
            if (!([System.Diagnostics.EventLog]::SourceExists($scriptName))) {
                New-EventLog -LogName $LogName -Source $scriptname
            }
            else {
                Write-Debug "Event Log Source $scriptname exist"
            }

            Get-BYOLCheckerRegkey
            Init-BYOLCheckerRegkey
            New-ItemProperty -Path "HKLM:\Software\Amazon\BYOLChecker" -Name SkipOfficePopup -Value 1 -Force | Out-Null
            foreach ($byolFunc in $global:ListFunctions) {
                # Execute each Test BYOL function to validate the system
                # This will create a list of function objects with the function name and Text Labels needed to condtruct the Form

                $result = Invoke-Expression $byolFunc
                Write-LogFile -Type Information -Message "$result : $byolFunc"

                # Storing the results Success/Failed
                $resultList += $result.Item1
                if ($result.Item1 -like "FAILED" -or $result.Item1 -like "WARNING") {
                    $errorCodesList += @($result.Item2)
                }
            }

            # Check the string for any failure
            # A failure will be recorded in DDB with Ami Automation Workflow and will stop AMI automation build
            if ($resultList -match "FAILED" -or $resultList -match "WARNING") {
                $BYOLValue = [tuple]::Create("FAILED", $errorCodesList)
            }
            else {
                $BYOLValue = [tuple]::Create("success")
            }
            return $BYOLValue
        }
        # Manual interactive form AMIAutomation = $true
        else {
            $interactiveMode = $true
            Init-BYOLCheckerRegkey
            foreach ($byolFunc in $global:ListFunctions) {
                Invoke-Expression $byolFunc
            }
            # From the above Function Objects List Start the Interactive Form
            Write-Host "Begin Interactive Form Checker"
            Test-RunAsAdmin
            Disable-Hibernation
            if($global:OSCheck -like "*Windows 11*"){
                Reset-Ec2LaunchV2
            }
            Get-OOBE
            New-Form | Out-Null
        }
    }
    catch {
        Write-Host "Unexpected error: $_"
    }
}
# Execute
main

# SIG # Begin signature block
# MIIuBgYJKoZIhvcNAQcCoIIt9zCCLfMCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAyuTJUzT6RLSWJ
# z4cB1WlBlgdDXH72uQLmQ58t/A7xi6CCE3MwggXAMIIEqKADAgECAhAP0bvKeWvX
# +N1MguEKmpYxMA0GCSqGSIb3DQEBCwUAMGwxCzAJBgNVBAYTAlVTMRUwEwYDVQQK
# EwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xKzApBgNV
# BAMTIkRpZ2lDZXJ0IEhpZ2ggQXNzdXJhbmNlIEVWIFJvb3QgQ0EwHhcNMjIwMTEz
# MDAwMDAwWhcNMzExMTA5MjM1OTU5WjBiMQswCQYDVQQGEwJVUzEVMBMGA1UEChMM
# RGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3d3cuZGlnaWNlcnQuY29tMSEwHwYDVQQD
# ExhEaWdpQ2VydCBUcnVzdGVkIFJvb3QgRzQwggIiMA0GCSqGSIb3DQEBAQUAA4IC
# DwAwggIKAoICAQC/5pBzaN675F1KPDAiMGkz7MKnJS7JIT3yithZwuEppz1Yq3aa
# za57G4QNxDAf8xukOBbrVsaXbR2rsnnyyhHS5F/WBTxSD1Ifxp4VpX6+n6lXFllV
# cq9ok3DCsrp1mWpzMpTREEQQLt+C8weE5nQ7bXHiLQwb7iDVySAdYyktzuxeTsiT
# +CFhmzTrBcZe7FsavOvJz82sNEBfsXpm7nfISKhmV1efVFiODCu3T6cw2Vbuyntd
# 463JT17lNecxy9qTXtyOj4DatpGYQJB5w3jHtrHEtWoYOAMQjdjUN6QuBX2I9YI+
# EJFwq1WCQTLX2wRzKm6RAXwhTNS8rhsDdV14Ztk6MUSaM0C/CNdaSaTC5qmgZ92k
# J7yhTzm1EVgX9yRcRo9k98FpiHaYdj1ZXUJ2h4mXaXpI8OCiEhtmmnTK3kse5w5j
# rubU75KSOp493ADkRSWJtppEGSt+wJS00mFt6zPZxd9LBADMfRyVw4/3IbKyEbe7
# f/LVjHAsQWCqsWMYRJUadmJ+9oCw++hkpjPRiQfhvbfmQ6QYuKZ3AeEPlAwhHbJU
# KSWJbOUOUlFHdL4mrLZBdd56rF+NP8m800ERElvlEFDrMcXKchYiCd98THU/Y+wh
# X8QgUWtvsauGi0/C1kVfnSD8oR7FwI+isX4KJpn15GkvmB0t9dmpsh3lGwIDAQAB
# o4IBZjCCAWIwDwYDVR0TAQH/BAUwAwEB/zAdBgNVHQ4EFgQU7NfjgtJxXWRM3y5n
# P+e6mK4cD08wHwYDVR0jBBgwFoAUsT7DaQP4v0cB1JgmGggC72NkK8MwDgYDVR0P
# AQH/BAQDAgGGMBMGA1UdJQQMMAoGCCsGAQUFBwMDMH8GCCsGAQUFBwEBBHMwcTAk
# BggrBgEFBQcwAYYYaHR0cDovL29jc3AuZGlnaWNlcnQuY29tMEkGCCsGAQUFBzAC
# hj1odHRwOi8vY2FjZXJ0cy5kaWdpY2VydC5jb20vRGlnaUNlcnRIaWdoQXNzdXJh
# bmNlRVZSb290Q0EuY3J0MEsGA1UdHwREMEIwQKA+oDyGOmh0dHA6Ly9jcmwzLmRp
# Z2ljZXJ0LmNvbS9EaWdpQ2VydEhpZ2hBc3N1cmFuY2VFVlJvb3RDQS5jcmwwHAYD
# VR0gBBUwEzAHBgVngQwBAzAIBgZngQwBBAEwDQYJKoZIhvcNAQELBQADggEBAEHx
# qRH0DxNHecllao3A7pgEpMbjDPKisedfYk/ak1k2zfIe4R7sD+EbP5HU5A/C5pg0
# /xkPZigfT2IxpCrhKhO61z7H0ZL+q93fqpgzRh9Onr3g7QdG64AupP2uU7SkwaT1
# IY1rzAGt9Rnu15ClMlIr28xzDxj4+87eg3Gn77tRWwR2L62t0+od/P1Tk+WMieNg
# GbngLyOOLFxJy34riDkruQZhiPOuAnZ2dMFkkbiJUZflhX0901emWG4f7vtpYeJa
# 3Cgh6GO6Ps9W7Zrk9wXqyvPsEt84zdp7PiuTUy9cUQBY3pBIowrHC/Q7bVUx8ALM
# R3eWUaNetbxcyEMRoacwggawMIIEmKADAgECAhAIrUCyYNKcTJ9ezam9k67ZMA0G
# CSqGSIb3DQEBDAUAMGIxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJ
# bmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xITAfBgNVBAMTGERpZ2lDZXJ0
# IFRydXN0ZWQgUm9vdCBHNDAeFw0yMTA0MjkwMDAwMDBaFw0zNjA0MjgyMzU5NTla
# MGkxCzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5EaWdpQ2VydCwgSW5jLjFBMD8GA1UE
# AxM4RGlnaUNlcnQgVHJ1c3RlZCBHNCBDb2RlIFNpZ25pbmcgUlNBNDA5NiBTSEEz
# ODQgMjAyMSBDQTEwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQDVtC9C
# 0CiteLdd1TlZG7GIQvUzjOs9gZdwxbvEhSYwn6SOaNhc9es0JAfhS0/TeEP0F9ce
# 2vnS1WcaUk8OoVf8iJnBkcyBAz5NcCRks43iCH00fUyAVxJrQ5qZ8sU7H/Lvy0da
# E6ZMswEgJfMQ04uy+wjwiuCdCcBlp/qYgEk1hz1RGeiQIXhFLqGfLOEYwhrMxe6T
# SXBCMo/7xuoc82VokaJNTIIRSFJo3hC9FFdd6BgTZcV/sk+FLEikVoQ11vkunKoA
# FdE3/hoGlMJ8yOobMubKwvSnowMOdKWvObarYBLj6Na59zHh3K3kGKDYwSNHR7Oh
# D26jq22YBoMbt2pnLdK9RBqSEIGPsDsJ18ebMlrC/2pgVItJwZPt4bRc4G/rJvmM
# 1bL5OBDm6s6R9b7T+2+TYTRcvJNFKIM2KmYoX7BzzosmJQayg9Rc9hUZTO1i4F4z
# 8ujo7AqnsAMrkbI2eb73rQgedaZlzLvjSFDzd5Ea/ttQokbIYViY9XwCFjyDKK05
# huzUtw1T0PhH5nUwjewwk3YUpltLXXRhTT8SkXbev1jLchApQfDVxW0mdmgRQRNY
# mtwmKwH0iU1Z23jPgUo+QEdfyYFQc4UQIyFZYIpkVMHMIRroOBl8ZhzNeDhFMJlP
# /2NPTLuqDQhTQXxYPUez+rbsjDIJAsxsPAxWEQIDAQABo4IBWTCCAVUwEgYDVR0T
# AQH/BAgwBgEB/wIBADAdBgNVHQ4EFgQUaDfg67Y7+F8Rhvv+YXsIiGX0TkIwHwYD
# VR0jBBgwFoAU7NfjgtJxXWRM3y5nP+e6mK4cD08wDgYDVR0PAQH/BAQDAgGGMBMG
# A1UdJQQMMAoGCCsGAQUFBwMDMHcGCCsGAQUFBwEBBGswaTAkBggrBgEFBQcwAYYY
# aHR0cDovL29jc3AuZGlnaWNlcnQuY29tMEEGCCsGAQUFBzAChjVodHRwOi8vY2Fj
# ZXJ0cy5kaWdpY2VydC5jb20vRGlnaUNlcnRUcnVzdGVkUm9vdEc0LmNydDBDBgNV
# HR8EPDA6MDigNqA0hjJodHRwOi8vY3JsMy5kaWdpY2VydC5jb20vRGlnaUNlcnRU
# cnVzdGVkUm9vdEc0LmNybDAcBgNVHSAEFTATMAcGBWeBDAEDMAgGBmeBDAEEATAN
# BgkqhkiG9w0BAQwFAAOCAgEAOiNEPY0Idu6PvDqZ01bgAhql+Eg08yy25nRm95Ry
# sQDKr2wwJxMSnpBEn0v9nqN8JtU3vDpdSG2V1T9J9Ce7FoFFUP2cvbaF4HZ+N3HL
# IvdaqpDP9ZNq4+sg0dVQeYiaiorBtr2hSBh+3NiAGhEZGM1hmYFW9snjdufE5Btf
# Q/g+lP92OT2e1JnPSt0o618moZVYSNUa/tcnP/2Q0XaG3RywYFzzDaju4ImhvTnh
# OE7abrs2nfvlIVNaw8rpavGiPttDuDPITzgUkpn13c5UbdldAhQfQDN8A+KVssIh
# dXNSy0bYxDQcoqVLjc1vdjcshT8azibpGL6QB7BDf5WIIIJw8MzK7/0pNVwfiThV
# 9zeKiwmhywvpMRr/LhlcOXHhvpynCgbWJme3kuZOX956rEnPLqR0kq3bPKSchh/j
# wVYbKyP/j7XqiHtwa+aguv06P0WmxOgWkVKLQcBIhEuWTatEQOON8BUozu3xGFYH
# Ki8QxAwIZDwzj64ojDzLj4gLDb879M4ee47vtevLt/B3E+bnKD+sEq6lLyJsQfmC
# XBVmzGwOysWGw/YmMwwHS6DTBwJqakAwSEs0qFEgu60bhQjiWQ1tygVQK+pKHJ6l
# /aCnHwZ05/LWUpD9r4VIIflXO7ScA+2GRfS0YW6/aOImYIbqyK+p/pQd52MbOoZW
# eE4wggb3MIIE36ADAgECAhAEstNiv5tANt0f/Jc5YoS+MA0GCSqGSIb3DQEBCwUA
# MGkxCzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5EaWdpQ2VydCwgSW5jLjFBMD8GA1UE
# AxM4RGlnaUNlcnQgVHJ1c3RlZCBHNCBDb2RlIFNpZ25pbmcgUlNBNDA5NiBTSEEz
# ODQgMjAyMSBDQTEwHhcNMjMxMTIxMDAwMDAwWhcNMjQxMTIwMjM1OTU5WjB/MQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHU2VhdHRs
# ZTEZMBcGA1UEChMQQW1hem9uLmNvbSwgSW5jLjETMBEGA1UECxMKd29ya3NwYWNl
# czEZMBcGA1UEAxMQQW1hem9uLmNvbSwgSW5jLjCCAaIwDQYJKoZIhvcNAQEBBQAD
# ggGPADCCAYoCggGBALqzvPLNPRb9rs7PFxX8zKBtM6EaAM5gb8NBSmHHBwOzYr3a
# yy+u+8oe79l8YmIb7rtdCpSeYnAmPnLJiTDn8yS6z7N4hzEyQOXFyV/A2aOl8jhX
# dUvgbXGxEV8aIa5LJZdlCHqQmePBvlQAvNbpLW0yx4jgpZW7TBqy+17Hz8K8tccw
# GWO00Gz3dged92y4XuT7T4ckps6CQ/igBgB2N9284mZCtvLPSL34kd+3hS3D7DnR
# PxqyZ2MTqW4k5ph3Wp813AV9ju68DoraplKYM7m6ls3AnxpAmNKcZOaKOXsDqFEW
# PykXjzrR9bXBPzIKhyP1t8cLcMsMSmmJgetBjdLtl5+j7zNndRdk9HvcKC7zH6m1
# KgoPVVPWiojsUkQ3JE2ua8EkG0len9vYC8FFPI0rjag3A3singBygLvJTyuu8Wk5
# qLxuBfAW0brpb3ikSqSYSfHCH++k6QobfWqAZEmuQt4cklcvuyiNYiILY8bnOueR
# EGiiKhIoN9NXy/UbdQIDAQABo4ICAzCCAf8wHwYDVR0jBBgwFoAUaDfg67Y7+F8R
# hvv+YXsIiGX0TkIwHQYDVR0OBBYEFJIK7xBfSb0CZhV7RWordFZq3xQLMD4GA1Ud
# IAQ3MDUwMwYGZ4EMAQQBMCkwJwYIKwYBBQUHAgEWG2h0dHA6Ly93d3cuZGlnaWNl
# cnQuY29tL0NQUzAOBgNVHQ8BAf8EBAMCB4AwEwYDVR0lBAwwCgYIKwYBBQUHAwMw
# gbUGA1UdHwSBrTCBqjBToFGgT4ZNaHR0cDovL2NybDMuZGlnaWNlcnQuY29tL0Rp
# Z2lDZXJ0VHJ1c3RlZEc0Q29kZVNpZ25pbmdSU0E0MDk2U0hBMzg0MjAyMUNBMS5j
# cmwwU6BRoE+GTWh0dHA6Ly9jcmw0LmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydFRydXN0
# ZWRHNENvZGVTaWduaW5nUlNBNDA5NlNIQTM4NDIwMjFDQTEuY3JsMIGUBggrBgEF
# BQcBAQSBhzCBhDAkBggrBgEFBQcwAYYYaHR0cDovL29jc3AuZGlnaWNlcnQuY29t
# MFwGCCsGAQUFBzAChlBodHRwOi8vY2FjZXJ0cy5kaWdpY2VydC5jb20vRGlnaUNl
# cnRUcnVzdGVkRzRDb2RlU2lnbmluZ1JTQTQwOTZTSEEzODQyMDIxQ0ExLmNydDAJ
# BgNVHRMEAjAAMA0GCSqGSIb3DQEBCwUAA4ICAQCbx/nwj1esOGGpLH52oz6xPiGI
# cn62kSXw4qhXElN0YbskREFD61HQDwK1EhinXBvjL7Ir+xGodvR2IpPWIPb36ixy
# gCUSZDLZXK847qPbVjxb5ULu8yqJNQkFoz6KcrqLLnkyu/cg9VuC3wfbVBaR77bX
# X3KdOSUoDXiih9zSF0kg6YafxXeDyU7qjEZEyhWYQtahnc27hT4fz2pvghamhae3
# a9r+gIjSIPBryrkQiw2u6s+6dIKB1djKlYbFghkkjkg8KaEoCIlS2l8zGTzIc4er
# 1eU4p2Rd3HCPdXNxnrpJR2oFNeAHCHqlrEkIcRZV0Tz4Hf4jHy96oAYEldkvpeDl
# tVFtvpKiV6AGCPtuZMDLPMffZj42XZn7oOB+1WRtmfyO7+vQhjm7oATQNeIIm+XN
# whpPFqY08oQSUW4LQTSkeWLz579lubDfao1+Ta7kSWkMKw5fmjLzVW5C9L4qiZM7
# wA8fEaKbRMFfjFD3+F9YNorf1VZS8Yl3agB26VV7dVfR4qQtVJvAGs14Bxlfbhb4
# mIuwB1ZgjJvuqkERGYnMJ112o0zLLLoyVz2e39jOkJfdm6AnphtIXMXuLXy6tfeF
# 4nRCcypS5xVFaCIiAcVrtWC5CsYshkAux5Qm3LS9ZSRFMNjLnYDE/WsWyx8WFnwi
# iaU3ehJuEZFNjqZhhzGCGekwghnlAgEBMH0waTELMAkGA1UEBhMCVVMxFzAVBgNV
# BAoTDkRpZ2lDZXJ0LCBJbmMuMUEwPwYDVQQDEzhEaWdpQ2VydCBUcnVzdGVkIEc0
# IENvZGUgU2lnbmluZyBSU0E0MDk2IFNIQTM4NCAyMDIxIENBMQIQBLLTYr+bQDbd
# H/yXOWKEvjANBglghkgBZQMEAgEFAKB8MBAGCisGAQQBgjcCAQwxAjAAMBkGCSqG
# SIb3DQEJAzEMBgorBgEEAYI3AgEEMBwGCisGAQQBgjcCAQsxDjAMBgorBgEEAYI3
# AgEVMC8GCSqGSIb3DQEJBDEiBCDzwbaoVQ+mjJ87qHDznzgY0sZq8JX+3/9xjiKL
# W6R/lDANBgkqhkiG9w0BAQEFAASCAYAtPKUq8x0xOk3pPxDzhU14+kHikmhRwCH/
# yrRW4rDSM07PMNUZpAUx83dvbLuGzh+upcpZ7nSPdcPEET+QI6m77/n2AgYk4bTS
# B4v390jnQPHNArdu4C8wEeW+osyz6ieKrySB3a0VJFTE8EBxJwwyeC1wTvQNRCWW
# I5IC9jtSO49k0mQ0ZuXq6aOQQkVNceSLWPWIG/iAVuueyM2k+QTcZpXNDzqxUSmO
# Z2F4l9tj4hL92bUF1xEcmBhu2hyREOclbgfRRl1iYaxJO8W06DVJYWILiH7DwP4S
# 4PTMWD1W0GWa7vnBU5QntYdqINJvvj5cG7eJimzg4P+qIGPcvzmlKVkyMpchNmsN
# 3gjaxH3gtLKKlxaCk5JFk7CAmDshtcf5Aga/mUkz2nvbgaqUuTTzWuNTerkgGamZ
# PAQzgf9kiBj4ykDMmO7BkJTVMhp6z/8amUhDGD9WiccxMVuN/dfLB/Py2pSC8dbu
# FvLya+Of7UZeUVUGQ5E66AKzsRN5LMOhghc/MIIXOwYKKwYBBAGCNwMDATGCFysw
# ghcnBgkqhkiG9w0BBwKgghcYMIIXFAIBAzEPMA0GCWCGSAFlAwQCAQUAMHcGCyqG
# SIb3DQEJEAEEoGgEZjBkAgEBBglghkgBhv1sBwEwMTANBglghkgBZQMEAgEFAAQg
# SHX6ls/kLFyqGTgz51/ZYpeVjIrgmIrocePnn7rV/lcCED6XzS9EGIW2rFPJuqUo
# x7IYDzIwMjQwNTAxMTgzNTE2WqCCEwkwggbCMIIEqqADAgECAhAFRK/zlJ0IOaa/
# 2z9f5WEWMA0GCSqGSIb3DQEBCwUAMGMxCzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5E
# aWdpQ2VydCwgSW5jLjE7MDkGA1UEAxMyRGlnaUNlcnQgVHJ1c3RlZCBHNCBSU0E0
# MDk2IFNIQTI1NiBUaW1lU3RhbXBpbmcgQ0EwHhcNMjMwNzE0MDAwMDAwWhcNMzQx
# MDEzMjM1OTU5WjBIMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNlcnQsIElu
# Yy4xIDAeBgNVBAMTF0RpZ2lDZXJ0IFRpbWVzdGFtcCAyMDIzMIICIjANBgkqhkiG
# 9w0BAQEFAAOCAg8AMIICCgKCAgEAo1NFhx2DjlusPlSzI+DPn9fl0uddoQ4J3C9I
# o5d6OyqcZ9xiFVjBqZMRp82qsmrdECmKHmJjadNYnDVxvzqX65RQjxwg6seaOy+W
# ZuNp52n+W8PWKyAcwZeUtKVQgfLPywemMGjKg0La/H8JJJSkghraarrYO8pd3hkY
# hftF6g1hbJ3+cV7EBpo88MUueQ8bZlLjyNY+X9pD04T10Mf2SC1eRXWWdf7dEKEb
# g8G45lKVtUfXeCk5a+B4WZfjRCtK1ZXO7wgX6oJkTf8j48qG7rSkIWRw69XloNpj
# sy7pBe6q9iT1HbybHLK3X9/w7nZ9MZllR1WdSiQvrCuXvp/k/XtzPjLuUjT71Lvr
# 1KAsNJvj3m5kGQc3AZEPHLVRzapMZoOIaGK7vEEbeBlt5NkP4FhB+9ixLOFRr7St
# FQYU6mIIE9NpHnxkTZ0P387RXoyqq1AVybPKvNfEO2hEo6U7Qv1zfe7dCv95NBB+
# plwKWEwAPoVpdceDZNZ1zY8SdlalJPrXxGshuugfNJgvOuprAbD3+yqG7HtSOKmY
# CaFxsmxxrz64b5bV4RAT/mFHCoz+8LbH1cfebCTwv0KCyqBxPZySkwS0aXAnDU+3
# tTbRyV8IpHCj7ArxES5k4MsiK8rxKBMhSVF+BmbTO77665E42FEHypS34lCh8zrT
# ioPLQHsCAwEAAaOCAYswggGHMA4GA1UdDwEB/wQEAwIHgDAMBgNVHRMBAf8EAjAA
# MBYGA1UdJQEB/wQMMAoGCCsGAQUFBwMIMCAGA1UdIAQZMBcwCAYGZ4EMAQQCMAsG
# CWCGSAGG/WwHATAfBgNVHSMEGDAWgBS6FtltTYUvcyl2mi91jGogj57IbzAdBgNV
# HQ4EFgQUpbbvE+fvzdBkodVWqWUxo97V40kwWgYDVR0fBFMwUTBPoE2gS4ZJaHR0
# cDovL2NybDMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0VHJ1c3RlZEc0UlNBNDA5NlNI
# QTI1NlRpbWVTdGFtcGluZ0NBLmNybDCBkAYIKwYBBQUHAQEEgYMwgYAwJAYIKwYB
# BQUHMAGGGGh0dHA6Ly9vY3NwLmRpZ2ljZXJ0LmNvbTBYBggrBgEFBQcwAoZMaHR0
# cDovL2NhY2VydHMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0VHJ1c3RlZEc0UlNBNDA5
# NlNIQTI1NlRpbWVTdGFtcGluZ0NBLmNydDANBgkqhkiG9w0BAQsFAAOCAgEAgRrW
# 3qCptZgXvHCNT4o8aJzYJf/LLOTN6l0ikuyMIgKpuM+AqNnn48XtJoKKcS8Y3U62
# 3mzX4WCcK+3tPUiOuGu6fF29wmE3aEl3o+uQqhLXJ4Xzjh6S2sJAOJ9dyKAuJXgl
# nSoFeoQpmLZXeY/bJlYrsPOnvTcM2Jh2T1a5UsK2nTipgedtQVyMadG5K8TGe8+c
# +njikxp2oml101DkRBK+IA2eqUTQ+OVJdwhaIcW0z5iVGlS6ubzBaRm6zxbygzc0
# brBBJt3eWpdPM43UjXd9dUWhpVgmagNF3tlQtVCMr1a9TMXhRsUo063nQwBw3syY
# nhmJA+rUkTfvTVLzyWAhxFZH7doRS4wyw4jmWOK22z75X7BC1o/jF5HRqsBV44a/
# rCcsQdCaM0qoNtS5cpZ+l3k4SF/Kwtw9Mt911jZnWon49qfH5U81PAC9vpwqbHkB
# 3NpE5jreODsHXjlY9HxzMVWggBHLFAx+rrz+pOt5Zapo1iLKO+uagjVXKBbLafIy
# mrLS2Dq4sUaGa7oX/cR3bBVsrquvczroSUa31X/MtjjA2Owc9bahuEMs305MfR5o
# cMB3CtQC4Fxguyj/OOVSWtasFyIjTvTs0xf7UGv/B3cfcZdEQcm4RtNsMnxYL2dH
# ZeUbc7aZ+WssBkbvQR7w8F/g29mtkIBEr4AQQYowggauMIIElqADAgECAhAHNje3
# JFR82Ees/ShmKl5bMA0GCSqGSIb3DQEBCwUAMGIxCzAJBgNVBAYTAlVTMRUwEwYD
# VQQKEwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xITAf
# BgNVBAMTGERpZ2lDZXJ0IFRydXN0ZWQgUm9vdCBHNDAeFw0yMjAzMjMwMDAwMDBa
# Fw0zNzAzMjIyMzU5NTlaMGMxCzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5EaWdpQ2Vy
# dCwgSW5jLjE7MDkGA1UEAxMyRGlnaUNlcnQgVHJ1c3RlZCBHNCBSU0E0MDk2IFNI
# QTI1NiBUaW1lU3RhbXBpbmcgQ0EwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIK
# AoICAQDGhjUGSbPBPXJJUVXHJQPE8pE3qZdRodbSg9GeTKJtoLDMg/la9hGhRBVC
# X6SI82j6ffOciQt/nR+eDzMfUBMLJnOWbfhXqAJ9/UO0hNoR8XOxs+4rgISKIhjf
# 69o9xBd/qxkrPkLcZ47qUT3w1lbU5ygt69OxtXXnHwZljZQp09nsad/ZkIdGAHvb
# REGJ3HxqV3rwN3mfXazL6IRktFLydkf3YYMZ3V+0VAshaG43IbtArF+y3kp9zvU5
# EmfvDqVjbOSmxR3NNg1c1eYbqMFkdECnwHLFuk4fsbVYTXn+149zk6wsOeKlSNbw
# sDETqVcplicu9Yemj052FVUmcJgmf6AaRyBD40NjgHt1biclkJg6OBGz9vae5jtb
# 7IHeIhTZgirHkr+g3uM+onP65x9abJTyUpURK1h0QCirc0PO30qhHGs4xSnzyqqW
# c0Jon7ZGs506o9UD4L/wojzKQtwYSH8UNM/STKvvmz3+DrhkKvp1KCRB7UK/BZxm
# SVJQ9FHzNklNiyDSLFc1eSuo80VgvCONWPfcYd6T/jnA+bIwpUzX6ZhKWD7TA4j+
# s4/TXkt2ElGTyYwMO1uKIqjBJgj5FBASA31fI7tk42PgpuE+9sJ0sj8eCXbsq11G
# deJgo1gJASgADoRU7s7pXcheMBK9Rp6103a50g5rmQzSM7TNsQIDAQABo4IBXTCC
# AVkwEgYDVR0TAQH/BAgwBgEB/wIBADAdBgNVHQ4EFgQUuhbZbU2FL3MpdpovdYxq
# II+eyG8wHwYDVR0jBBgwFoAU7NfjgtJxXWRM3y5nP+e6mK4cD08wDgYDVR0PAQH/
# BAQDAgGGMBMGA1UdJQQMMAoGCCsGAQUFBwMIMHcGCCsGAQUFBwEBBGswaTAkBggr
# BgEFBQcwAYYYaHR0cDovL29jc3AuZGlnaWNlcnQuY29tMEEGCCsGAQUFBzAChjVo
# dHRwOi8vY2FjZXJ0cy5kaWdpY2VydC5jb20vRGlnaUNlcnRUcnVzdGVkUm9vdEc0
# LmNydDBDBgNVHR8EPDA6MDigNqA0hjJodHRwOi8vY3JsMy5kaWdpY2VydC5jb20v
# RGlnaUNlcnRUcnVzdGVkUm9vdEc0LmNybDAgBgNVHSAEGTAXMAgGBmeBDAEEAjAL
# BglghkgBhv1sBwEwDQYJKoZIhvcNAQELBQADggIBAH1ZjsCTtm+YqUQiAX5m1tgh
# QuGwGC4QTRPPMFPOvxj7x1Bd4ksp+3CKDaopafxpwc8dB+k+YMjYC+VcW9dth/qE
# ICU0MWfNthKWb8RQTGIdDAiCqBa9qVbPFXONASIlzpVpP0d3+3J0FNf/q0+KLHqr
# hc1DX+1gtqpPkWaeLJ7giqzl/Yy8ZCaHbJK9nXzQcAp876i8dU+6WvepELJd6f8o
# VInw1YpxdmXazPByoyP6wCeCRK6ZJxurJB4mwbfeKuv2nrF5mYGjVoarCkXJ38SN
# oOeY+/umnXKvxMfBwWpx2cYTgAnEtp/Nh4cku0+jSbl3ZpHxcpzpSwJSpzd+k1Os
# Ox0ISQ+UzTl63f8lY5knLD0/a6fxZsNBzU+2QJshIUDQtxMkzdwdeDrknq3lNHGS
# 1yZr5Dhzq6YBT70/O3itTK37xJV77QpfMzmHQXh6OOmc4d0j/R0o08f56PGYX/sr
# 2H7yRp11LB4nLCbbbxV7HhmLNriT1ObyF5lZynDwN7+YAN8gFk8n+2BnFqFmut1V
# wDophrCYoCvtlUG3OtUVmDG0YgkPCr2B2RP+v6TR81fZvAT6gt4y3wSJ8ADNXcL5
# 0CN/AAvkdgIm2fBldkKmKYcJRyvmfxqkhQ/8mJb2VVQrH4D6wPIOK+XW+6kvRBVK
# 5xMOHds3OBqhK/bt1nz8MIIFjTCCBHWgAwIBAgIQDpsYjvnQLefv21DiCEAYWjAN
# BgkqhkiG9w0BAQwFADBlMQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQg
# SW5jMRkwFwYDVQQLExB3d3cuZGlnaWNlcnQuY29tMSQwIgYDVQQDExtEaWdpQ2Vy
# dCBBc3N1cmVkIElEIFJvb3QgQ0EwHhcNMjIwODAxMDAwMDAwWhcNMzExMTA5MjM1
# OTU5WjBiMQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYD
# VQQLExB3d3cuZGlnaWNlcnQuY29tMSEwHwYDVQQDExhEaWdpQ2VydCBUcnVzdGVk
# IFJvb3QgRzQwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQC/5pBzaN67
# 5F1KPDAiMGkz7MKnJS7JIT3yithZwuEppz1Yq3aaza57G4QNxDAf8xukOBbrVsaX
# bR2rsnnyyhHS5F/WBTxSD1Ifxp4VpX6+n6lXFllVcq9ok3DCsrp1mWpzMpTREEQQ
# Lt+C8weE5nQ7bXHiLQwb7iDVySAdYyktzuxeTsiT+CFhmzTrBcZe7FsavOvJz82s
# NEBfsXpm7nfISKhmV1efVFiODCu3T6cw2Vbuyntd463JT17lNecxy9qTXtyOj4Da
# tpGYQJB5w3jHtrHEtWoYOAMQjdjUN6QuBX2I9YI+EJFwq1WCQTLX2wRzKm6RAXwh
# TNS8rhsDdV14Ztk6MUSaM0C/CNdaSaTC5qmgZ92kJ7yhTzm1EVgX9yRcRo9k98Fp
# iHaYdj1ZXUJ2h4mXaXpI8OCiEhtmmnTK3kse5w5jrubU75KSOp493ADkRSWJtppE
# GSt+wJS00mFt6zPZxd9LBADMfRyVw4/3IbKyEbe7f/LVjHAsQWCqsWMYRJUadmJ+
# 9oCw++hkpjPRiQfhvbfmQ6QYuKZ3AeEPlAwhHbJUKSWJbOUOUlFHdL4mrLZBdd56
# rF+NP8m800ERElvlEFDrMcXKchYiCd98THU/Y+whX8QgUWtvsauGi0/C1kVfnSD8
# oR7FwI+isX4KJpn15GkvmB0t9dmpsh3lGwIDAQABo4IBOjCCATYwDwYDVR0TAQH/
# BAUwAwEB/zAdBgNVHQ4EFgQU7NfjgtJxXWRM3y5nP+e6mK4cD08wHwYDVR0jBBgw
# FoAUReuir/SSy4IxLVGLp6chnfNtyA8wDgYDVR0PAQH/BAQDAgGGMHkGCCsGAQUF
# BwEBBG0wazAkBggrBgEFBQcwAYYYaHR0cDovL29jc3AuZGlnaWNlcnQuY29tMEMG
# CCsGAQUFBzAChjdodHRwOi8vY2FjZXJ0cy5kaWdpY2VydC5jb20vRGlnaUNlcnRB
# c3N1cmVkSURSb290Q0EuY3J0MEUGA1UdHwQ+MDwwOqA4oDaGNGh0dHA6Ly9jcmwz
# LmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydEFzc3VyZWRJRFJvb3RDQS5jcmwwEQYDVR0g
# BAowCDAGBgRVHSAAMA0GCSqGSIb3DQEBDAUAA4IBAQBwoL9DXFXnOF+go3QbPbYW
# 1/e/Vwe9mqyhhyzshV6pGrsi+IcaaVQi7aSId229GhT0E0p6Ly23OO/0/4C5+KH3
# 8nLeJLxSA8hO0Cre+i1Wz/n096wwepqLsl7Uz9FDRJtDIeuWcqFItJnLnU+nBgMT
# dydE1Od/6Fmo8L8vC6bp8jQ87PcDx4eo0kxAGTVGamlUsLihVo7spNU96LHc/RzY
# 9HdaXFSMb++hUD38dglohJ9vytsgjTVgHAIDyyCwrFigDkBjxZgiwbJZ9VVrzyer
# bHbObyMt9H5xaiNrIv8SuFQtJ37YOtnwtoeW/VvRXKwYw02fc7cBqZ9Xql4o4rmU
# MYIDdjCCA3ICAQEwdzBjMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNlcnQs
# IEluYy4xOzA5BgNVBAMTMkRpZ2lDZXJ0IFRydXN0ZWQgRzQgUlNBNDA5NiBTSEEy
# NTYgVGltZVN0YW1waW5nIENBAhAFRK/zlJ0IOaa/2z9f5WEWMA0GCWCGSAFlAwQC
# AQUAoIHRMBoGCSqGSIb3DQEJAzENBgsqhkiG9w0BCRABBDAcBgkqhkiG9w0BCQUx
# DxcNMjQwNTAxMTgzNTE2WjArBgsqhkiG9w0BCRACDDEcMBowGDAWBBRm8CsywsLJ
# D4JdzqqKycZPGZzPQDAvBgkqhkiG9w0BCQQxIgQg5pmWO+5w+ryoUFQ5G7iuAa7l
# bUK1or8yAvXx6LRfmsgwNwYLKoZIhvcNAQkQAi8xKDAmMCQwIgQg0vbkbe10IszR
# 1EBXaEE2b4KK2lWarjMWr00amtQMeCgwDQYJKoZIhvcNAQEBBQAEggIAcaxLVrFU
# 8vzzoi/3L6G1WlTGKctVMzsBXJxzozdpMsg13UM3x2fcrZ+QQyhQ4uEOaRcf0o+6
# hzlgbKdTfHmOiQfZ7WRLBMMUkjwDpHFafAOmBvDMn7+U2I1osbpxCCVILWcZ/GI1
# OY2ut01AwpzqbkJZR95pZaEzhyilIa1ABIZzqsP94R0TWHWg7KWLSfUeFsL1vr7Q
# 1a2bLe9maTr3PBY1wrKg0rNaEaI1wM0D9DT8vN5y4xlbDjJSTHbKctyXhjpZl+dN
# EdbBvClJvg9I8EvQjdVj149IBXC6jg40w5rie2gqlkhFpyehOC7JZ5xRXjNjiCoO
# AaHovRLA3eAyHGTyspm0dmXBpm9DezcJr0sx10Js66u22bLsngb45/Ydply8IeBK
# PP2edV6jXBxCRMmNz0v+OxfLOZm4SHB2wG2zRLKq0arUOuJLDSR83JconPSV64EL
# pbAXF+aurCDODoB/3SJiwdVtvBdAdX6NNMh1YL7sCFsbK+cM2q7KtZ5j8l2NTbYh
# SVsTtZlC3ituGt7YhLKG0J+/etgnuwR7HVgSQhXXaXdAPMpzOWd0S8pD981Vbzjz
# w6ovnxCU9HEy0YYnxAyOlUZaa+OCIbkrG/tSLkWOYzrB90j0VczRxB8K7Y1pmJkY
# eQ9QQCGgpXKvoiakRuKhmRUyxrI9Wqf9Zn4=
# SIG # End signature block
