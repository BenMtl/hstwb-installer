# HstWB Installer Dialog Module
# -----------------------------
#
# Author: Henrik Noerfjand Stengaard
# Date:   2017-09-18
#
# A powershell module for HstWB Installer with dialog functions.


# print settings
function PrintSettings($hstwb)
{
    Write-Host "Settings"
    Write-Host "  Settings File         : " -NoNewline -foregroundcolor "Gray"
    Write-Host ("'" + $hstwb.Paths.SettingsFile + "'")
    Write-Host "  Assigns File          : " -NoNewline -foregroundcolor "Gray"
    Write-Host ("'" + $hstwb.Paths.AssignsFile + "'")
    Write-Host "Image"
    Write-Host "  Image Dir             : " -NoNewline -foregroundcolor "Gray"
    Write-Host ("'" + $hstwb.Settings.Image.ImageDir + "'")
    Write-Host "Workbench"
    Write-Host "  Install Workbench     : " -NoNewline -foregroundcolor "Gray"
    Write-Host ("'" + $hstwb.Settings.Workbench.InstallWorkbench + "'")
    Write-Host "  Workbench Adf Dir     : " -NoNewline -foregroundcolor "Gray"
    Write-Host ("'" + $hstwb.Settings.Workbench.WorkbenchAdfDir + "'")
    Write-Host "  Workbench Adf Set     : " -NoNewline -foregroundcolor "Gray"
    Write-Host ("'" + $hstwb.Settings.Workbench.WorkbenchAdfSet + "'")
    Write-Host "Amiga OS 3.9"
    Write-Host "  Install Amiga OS 3.9  : " -NoNewline -foregroundcolor "Gray"
    Write-Host ("'" + $hstwb.Settings.AmigaOS39.InstallAmigaOS39 + "'")
    Write-Host "  Install Boing Bags    : " -NoNewline -foregroundcolor "Gray"
    Write-Host ("'" + $hstwb.Settings.AmigaOS39.InstallBoingBags + "'")
    Write-Host "  Amiga OS 3.9 Iso File : " -NoNewline -foregroundcolor "Gray"
    Write-Host ("'" + $hstwb.Settings.AmigaOS39.AmigaOS39IsoFile + "'")
    Write-Host "Kickstart"
    Write-Host "  Install Kickstart     : " -NoNewline -foregroundcolor "Gray"
    Write-Host ("'" + $hstwb.Settings.Kickstart.InstallKickstart + "'")
    Write-Host "  Kickstart Rom Dir     : " -NoNewline -foregroundcolor "Gray"
    Write-Host ("'" + $hstwb.Settings.Kickstart.KickstartRomDir + "'")
    Write-Host "  Kickstart Rom Set     : " -NoNewline -foregroundcolor "Gray"
    Write-Host ("'" + $hstwb.Settings.Kickstart.KickstartRomSet + "'")
    Write-Host "Packages"

    # get install packages
    $installPackageNames = @{}
    foreach($installPackageKey in ($hstwb.Settings.Packages.Keys | Where-Object { $_ -match 'InstallPackage\d+' }))
    {
        $installPackageNames.Set_Item($hstwb.Settings.Packages.Get_Item($installPackageKey.ToLower()), $true)
    }

    $packageNames = @()
    $packageNames += SortPackageNames $hstwb | ForEach-Object { $_.ToLower() }
    
    Write-Host "  Install Packages      : " -NoNewline -foregroundcolor "Gray"
    if ($installPackageNames.Count -gt 0)
    {
        $installPackages = @()

        foreach ($packageName in ($packageNames | Where-Object { $installPackageNames.ContainsKey($_) }))
        {
            $package = $hstwb.Packages.Get_Item($packageName).Latest
            $installPackages += $package.PackageFullName
        }

        Write-Host ("'" + ($installPackages -Join ', ') + "'")
    }
    else
    {
        Write-Host "None" -foregroundcolor "Yellow"
    }

    Write-Host "User Packages"
    Write-Host "  User Packages Dir     : " -NoNewline -foregroundcolor "Gray"

    if ($hstwb.Settings.UserPackages.UserPackagesDir -and (Test-Path -Path $hstwb.Settings.UserPackages.UserPackagesDir))
    {
        Write-Host ("'{0}'" -f $hstwb.Settings.UserPackages.UserPackagesDir)
    }
    else
    {
        Write-Host "''"
    }

    # get install user packages
    $installUserPackageNames = @()
    foreach($installUserPackageKey in ($hstwb.Settings.UserPackages.Keys | Where-Object { $_ -match 'InstallUserPackage\d+' }))
    {
        $userPackageName = $hstwb.Settings.UserPackages.Get_Item($installUserPackageKey.ToLower())
        $userPackage = $hstwb.UserPackages.Get_Item($userPackageName)
        $installUserPackageNames += $userPackage.Name
    }
    
    Write-Host "  Install User Packages : " -NoNewline -foregroundcolor "Gray"
    if ($installUserPackageNames.Count -gt 0)
    {
        Write-Host ("'" + (($installUserPackageNames | Sort-Object) -Join ', ') + "'")
    }
    else
    {
        Write-Host "None" -foregroundcolor "Yellow"
    }
    

    Write-Host "Emulator"
    Write-Host "  Emulator File         : " -NoNewline -foregroundcolor "Gray"

    if ($hstwb.Settings.Emulator.EmulatorFile -and (Test-Path -Path $hstwb.Settings.Emulator.EmulatorFile))
    {
        $emulatorName = DetectEmulatorName $hstwb.Settings.Emulator.EmulatorFile

        if ($emulatorName)
        {
            Write-Host ("'{0} ({1})'" -f $emulatorName, $hstwb.Settings.Emulator.EmulatorFile)
        }
        else
        {
            Write-Host ("'{0}'" -f $hstwb.Settings.Emulator.EmulatorFile)
        }
    }
    else
    {
        Write-Host "''"
    }
    
    Write-Host "Installer"
    Write-Host "  Mode                  : " -NoNewline -foregroundcolor "Gray"
    switch ($hstwb.Settings.Installer.Mode)
    {
        "Test" { Write-Host "'Test'" }
        "Install" { Write-Host "'Install'" }
        "BuildSelfInstall" { Write-Host "'Build Self Install'" }
        "BuildPackageInstallation" { Write-Host "'Build Package Installation'" }
    }
}


# enter path
function EnterPath($prompt)
{
    do
    {
        $path = Read-Host $prompt

        if ($path -ne '')
        {
            $path = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($path)
        }
        
        if (!(test-path -path $path))
        {
            Write-Error "Path '$path' doesn't exist"
        }
    }
    until ($path -eq '' -or (test-path -path $path))
    return $path
}


# enter choice
function EnterChoice($prompt, $options)
{
    $optionPadding = $options.Count.ToString().Length

    for ($i = 0; $i -lt $options.Count; $i++)
    {
        Write-Host (("{0," + $optionPadding + "}: ") -f ($i + 1)) -NoNewline -foregroundcolor "Gray"
        Write-Host $options[$i]
    }
    Write-Host ""

    do
    {
        Write-Host ("{0}: " -f $prompt) -NoNewline -foregroundcolor "Cyan"
        $choice = (Read-Host) -as [int]
    }
    until ($choice -ne '' -and $choice -ge 1 -and $choice -le $options.Count)

    return $options[$choice - 1]
}