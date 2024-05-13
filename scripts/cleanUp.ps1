Start-Sleep -Seconds 45
Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
Set-Service -Name wuauserv -StartupType Disabled
Set-NetFirewallProfile -Enabled False
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\TimeZoneInformation" -Name "RealTimeIsUniversal" -Value 1
Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\WinLogon" -Name "AutoAdminLogon"
Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\WinLogon" -Name "DefaultUsername"
Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\WinLogon" -Name "Defaultpassword"
Copy-Item -Path "C:\Users\workspaces_byol\Documents\BYOLChecker\OOBE_unattend.xml" -Destination "C:\Windows\panther\unattend.xml" -recurse -force


