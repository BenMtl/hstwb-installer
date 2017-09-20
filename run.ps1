# HstWB Installer Run
# -------------------
#
# Author: Henrik Noerfjand Stengaard
# Date:   2017-09-18
#
# A powershell script to run HstWB Installer automating installation of workbench, kickstart roms and packages to an Amiga HDF file.


Param(
	[Parameter(Mandatory=$true)]
	[string]$settingsDir
)


Import-Module (Resolve-Path('modules\version.psm1')) -Force
Import-Module (Resolve-Path('modules\config.psm1')) -Force
Import-Module (Resolve-Path('modules\dialog.psm1')) -Force
Import-Module (Resolve-Path('modules\data.psm1')) -Force


Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.Windows.Forms


# # http://stackoverflow.com/questions/8982782/does-anyone-have-a-dependency-graph-and-topological-sorting-code-snippet-for-pow
# function Get-TopologicalSort {
#   param(
#       [Parameter(Mandatory = $true, Position = 0)]
#       [hashtable] $edgeList
#   )

#   # Make sure we can use HashSet
#   Add-Type -AssemblyName System.Core

#   # Clone it so as to not alter original
#   $currentEdgeList = [hashtable] (Get-ClonedObject $edgeList)

#   # algorithm from http://en.wikipedia.org/wiki/Topological_sorting#Algorithms
#   $topologicallySortedElements = New-Object System.Collections.ArrayList
#   $setOfAllNodesWithNoIncomingEdges = New-Object System.Collections.Queue

#   $fasterEdgeList = @{}

#   # Keep track of all nodes in case they put it in as an edge destination but not source
#   $allNodes = New-Object -TypeName System.Collections.Generic.HashSet[object] -ArgumentList (,[object[]] $currentEdgeList.Keys)

#   foreach($currentNode in $currentEdgeList.Keys) {
#       $currentDestinationNodes = [array] $currentEdgeList[$currentNode]
#       if($currentDestinationNodes.Length -eq 0) {
#           $setOfAllNodesWithNoIncomingEdges.Enqueue($currentNode)
#       }

#       foreach($currentDestinationNode in $currentDestinationNodes) {
#           if(!$allNodes.Contains($currentDestinationNode)) {
#               [void] $allNodes.Add($currentDestinationNode)
#           }
#       }

#       # Take this time to convert them to a HashSet for faster operation
#       $currentDestinationNodes = New-Object -TypeName System.Collections.Generic.HashSet[object] -ArgumentList (,[object[]] $currentDestinationNodes )
#       [void] $fasterEdgeList.Add($currentNode, $currentDestinationNodes)        
#   }

#   # Now let's reconcile by adding empty dependencies for source nodes they didn't tell us about
#   foreach($currentNode in $allNodes) {
#       if(!$currentEdgeList.ContainsKey($currentNode)) {
#           [void] $currentEdgeList.Add($currentNode, (New-Object -TypeName System.Collections.Generic.HashSet[object]))
#           $setOfAllNodesWithNoIncomingEdges.Enqueue($currentNode)
#       }
#   }

#   $currentEdgeList = $fasterEdgeList

#   while($setOfAllNodesWithNoIncomingEdges.Count -gt 0) {        
#       $currentNode = $setOfAllNodesWithNoIncomingEdges.Dequeue()
#       [void] $currentEdgeList.Remove($currentNode)
#       [void] $topologicallySortedElements.Add($currentNode)

#       foreach($currentEdgeSourceNode in $currentEdgeList.Keys) {
#           $currentNodeDestinations = $currentEdgeList[$currentEdgeSourceNode]
#           if($currentNodeDestinations.Contains($currentNode)) {
#               [void] $currentNodeDestinations.Remove($currentNode)

#               if($currentNodeDestinations.Count -eq 0) {
#                   [void] $setOfAllNodesWithNoIncomingEdges.Enqueue($currentEdgeSourceNode)
#               }                
#           }
#       }
#   }

#   if($currentEdgeList.Count -gt 0) {
#       throw "Graph has at least one cycle!"
#   }

#   return $topologicallySortedElements
# }


# # Idea from http://stackoverflow.com/questions/7468707/deep-copy-a-dictionary-hashtable-in-powershell 
# function Get-ClonedObject {
#     param($DeepCopyObject)
#     $memStream = new-object IO.MemoryStream
#     $formatter = new-object Runtime.Serialization.Formatters.Binary.BinaryFormatter
#     $formatter.Serialize($memStream,$DeepCopyObject)
#     $memStream.Position=0
#     $formatter.Deserialize($memStream)
# }


# show folder browser dialog using WinForms
function FolderBrowserDialog($title, $directory, $showNewFolderButton)
{
    $folderBrowserDialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $folderBrowserDialog.Description = $title
    $folderBrowserDialog.SelectedPath = $directory
    $folderBrowserDialog.ShowNewFolderButton = $showNewFolderButton
    $result = $folderBrowserDialog.ShowDialog()

    if($result -ne "OK")
    {
        return $null
    }    

    return $folderBrowserDialog.SelectedPath    
}


# confirm dialog
function ConfirmDialog($title, $message)
{
    $result = [System.Windows.Forms.MessageBox]::Show($message, $title, [System.Windows.Forms.MessageBoxButtons]::OKCancel)

    if($result -eq "OK")
    {
        return $true
    }

    return $false
}


# write text file encoded for Amiga
function WriteAmigaTextLines($path, $lines)
{
	$iso88591 = [System.Text.Encoding]::GetEncoding("ISO-8859-1");
	$utf8 = [System.Text.Encoding]::UTF8;

	$amigaTextBytes = [System.Text.Encoding]::Convert($utf8, $iso88591, $utf8.GetBytes($lines -join "`n"))
	[System.IO.File]::WriteAllText($path, $iso88591.GetString($amigaTextBytes), $iso88591)
}


# start process
function StartProcess($fileName, $arguments, $workingDirectory)
{
	# start process info
	$processInfo = New-Object System.Diagnostics.ProcessStartInfo
	$processInfo.FileName = $fileName
	$processInfo.RedirectStandardError = $true
	$processInfo.RedirectStandardOutput = $true
	$processInfo.UseShellExecute = $false
	$processInfo.Arguments = $arguments
	$processInfo.WorkingDirectory = $workingDirectory

	# run process
	$process = New-Object System.Diagnostics.Process
	$process.StartInfo = $processInfo
	$process.Start() | Out-Null
    $process.BeginErrorReadLine()
    $process.BeginOutputReadLine()
	$process.WaitForExit()

	if ($process.ExitCode -ne 0)
	{
        $standardOutput = $process.StandardOutput.ReadToEnd()
        $standardError = $process.StandardError.ReadToEnd()

		if ($standardOutput)
		{
			Write-Error ("StandardOutput: " + $standardOutput)
		}

		if ($standardError)
		{
			Write-Error ("StandardError: " + $standardError)
		}
	}

	return $process.ExitCode	
}


# find packages to install
function FindPackagesToInstall($hstwb)
{
    # get package files in packages directory
    $packageFiles = @()
    $packageFiles += Get-ChildItem -Path $hstwb.Paths.PackagesPath -filter *.zip


    # get install packages defined in settings packages section
    $packageFileNames = @()
    if ($hstwb.Settings.Packages.InstallPackages -and $hstwb.Settings.Packages.InstallPackages -ne '')
    {
        $packageFileNames += $hstwb.Settings.Packages.InstallPackages.ToLower() -split ',' | Where-Object { $_ }
    }


    $packageDetails = @{}
    $packageDependencies = @()

    foreach ($packageFileName in $packageFileNames)
    {
        # get package file for package
        $packageFile = $packageFiles | Where-Object { $_.Name -eq ($packageFileName + ".zip") } | Select-Object -First 1


        # write warning and skip, if package file doesn't exist
        if (!$packageFile)
        {
            Fail $hstwb ("Package '$packageFileName' doesn't exist in packages directory '$packagesPath'")
        }


        # read package ini text file from package file
        $packageIniText = ReadZipEntryTextFile $packageFile.FullName 'package.ini$'

        # return, if harddrives uae text doesn't exist
        if (!$packageIniText)
        {
            Fail $hstwb("Package '" + $packageFile.FullName + "' doesn't contain a package.ini file")
        }


        # read package ini file
        $packageIni = ReadIniText $packageIniText


        # fail, if package name doesn't exist
        if (!$packageIni.Package.Name -or $packageIni.Package.Name -eq '')
        {
            Fail $hstwb ("Package '$packageFileName' doesn't contain name in package.ini file")
        }


        # package name
        $packageName = $packageIni.Package.Name


        $priority = if ($packageIni.Package.Priority) { [Int32]$packageIni.Package.Priority } else { 9999 }


        # package full name
        $packageFullName = "{0} v{1}" -f $packageIni.Package.Name, $packageIni.Package.Version


        # add package details
        $packageDetails.Set_Item($packageName, @{ "Name" = $packageName; "Priority" = $priority; "FullName" = $packageFullName; "PackageFileName" = $packageFileName; "PackageFile" = $packageFile.FullName; "Package" = $packageIni.Package })


        # add package dependencies
        $dependencies = @()
        $dependencies += $packageIni.Package.Dependencies -split ',' | Where-Object { $_ }
        $packageDependencies += @{ 'Name'= $packageName; 'Dependencies' = $dependencies }
    }


    $installPackages = @()


    # write install packages script, if there are any packages to install
    if ($packageFileNames.Count -gt 0)
    {
        # sort packages by priority and name
        $packagesSortedByPriorityAndName = @()
        $packagesSortedByPriorityAndName += ,$packageDependencies | Sort-Object @{expression={$packageDetails[$_.Name].Priority};Ascending=$true}, @{expression={$_.Name};Ascending=$true}

        # sort packages by dependencies
        $packagesSortedByDependencies = TopologicalSort $packagesSortedByPriorityAndName

        foreach($packageName in $packagesSortedByDependencies)
        {
            # skip package from dependencies, if not part of packages that should be installed
            if (!$packageDetails.ContainsKey($packageName))
            {
                continue
            }

            $installPackages += $packageDetails.Get_Item($packageName)
        }
    }

    return $installPackages
}


# build assign hstwb installer script lines
function BuildAssignHstwbInstallerScriptLines($hstwb, $createDirectories)
{
    $globalAssigns = $hstwb.Assigns.Get_Item('Global')

    $assignHstwbInstallerScriptLines = @()

    foreach ($assignName in $globalAssigns.keys)
    {
        # skip, if assign name is 'HstWBInstallerDir' and installer mode is build package installation
        if ($assignName -match 'HstWBInstallerDir' -and $hstwb.Settings.Installer.Mode -eq "BuildPackageInstallation")
        {
            continue
        }

        # get assign path and drive
        $assignPath = $globalAssigns.Get_Item($assignName)
        $assignDrive = $assignPath -replace '^([^:]+:).*', '$1'

        # add package assign lines
        $assignHstwbInstallerScriptLines += "; Add assign for '$assignName' to '$assignPath'"
        $assignHstwbInstallerScriptLines += "Assign >NIL: EXISTS ""$assignDrive"""
        $assignHstwbInstallerScriptLines += "IF WARN"
        $assignHstwbInstallerScriptLines += "  echo ""Error: Drive '$assignDrive' doesn't exist for assign '$assignPath'!"""
        $assignHstwbInstallerScriptLines += "  ask ""Press ENTER to exit"""
        $assignHstwbInstallerScriptLines += "  QUIT 5"
        $assignHstwbInstallerScriptLines += "ELSE"

        # create directory for assignpath or check if path exist
        if ($createDirectories)
        {
            # add makedir dir each directory in assign path
            $assignDirs = @()
            $assignDirs += ($assignPath -replace '^[^:]+:(.*)', '$1') -split '/' | Where-Object { $_ }
            $currentAssignPath = $assignDrive
            foreach ($assignDir in $assignDirs)
            {
                if ($currentAssignPath -notmatch ':$')
                {
                    $currentAssignPath += '/'
                }
                $currentAssignPath += $assignDir
                $assignHstwbInstallerScriptLines += ("  IF NOT EXISTS """ + $currentAssignPath + """")
                $assignHstwbInstallerScriptLines += ("    MakeDir >NIL: """ + $currentAssignPath + """")
                $assignHstwbInstallerScriptLines += ("  ENDIF")
            }

            $assignHstwbInstallerScriptLines += ("  Assign " + $assignName + ": """ + $assignPath + """")
        }
        else
        {
            $assignHstwbInstallerScriptLines += ("  IF EXISTS """ + $assignPath + """")
            $assignHstwbInstallerScriptLines += ("    Assign " + $assignName + ": """ + $assignPath + """")
            $assignHstwbInstallerScriptLines += "  ELSE"
            $assignHstwbInstallerScriptLines += "    echo ""Error: Path '$assignPath' doesn't exist for assign!"""
            $assignHstwbInstallerScriptLines += "    ask ""Press ENTER to exit"""
            $assignHstwbInstallerScriptLines += "    QUIT 5"
            $assignHstwbInstallerScriptLines += "  ENDIF"
        }

        $assignHstwbInstallerScriptLines += "ENDIF"
    }

    return $assignHstwbInstallerScriptLines
}


# build assign path script lines
function BuildAssignPathScriptLines($assignId, $assignPath)
{
    $assignPathScriptLines = @()
    $assignPathScriptLines += ("IF EXISTS ""T:{0}""" -f $assignId)
    $assignPathScriptLines += ("  Set assignpath ""``type ""T:{0}""``""" -f $assignId)
    $assignPathScriptLines += "ELSE"
    $assignPathScriptLines += ("  Set assignpath ""{0}""" -f $assignPath)
    $assignPathScriptLines += "ENDIF"

    return $assignPathScriptLines
}


# build add assign script lines
function BuildAddAssignScriptLines($assignId, $assignName, $assignPath)
{
    $addAssignScriptLines = @()
    $addAssignScriptLines += ("; Add assign and set variable for assign '{0}'" -f $assignName)
    $addAssignScriptLines += BuildAssignPathScriptLines $assignId $assignPath
    $addAssignScriptLines += "Assign >NIL: EXISTS ""`$assignpath"""
    $addAssignScriptLines += "IF WARN"
    $addAssignScriptLines += "  MakePath ""`$assignpath"""
    $addAssignScriptLines += "ENDIF"
    $addAssignScriptLines += ("SetEnv {0} ""`$assignpath""" -f $assignName)
    $addAssignScriptLines += ("Assign {0}: ""`$assignpath""" -f $assignName)

    return $addAssignScriptLines
}


# build remove assign script lines
function BuildRemoveAssignScriptLines($assignId, $assignName, $assignPath)
{
    $removeAssignScriptLines = @()
    $removeAssignScriptLines += ("; Remove assign and unset variable for assign '{0}'" -f $assignName)
    $removeAssignScriptLines += BuildAssignPathScriptLines $assignId $assignPath
    $removeAssignScriptLines += ("Assign {0}: ""`$assignpath"" REMOVE" -f $assignName)
    $removeAssignScriptLines += ("IF EXISTS ""ENV:{0}""" -f $assignName)
    $removeAssignScriptLines += ("  delete >NIL: ""ENV:{0}""" -f $assignName)
    $removeAssignScriptLines += "ENDIF"

    return $removeAssignScriptLines
}


# build install package script lines
function BuildInstallPackageScriptLines($hstwb, $packageNames)
{
    $globalAssigns = $hstwb.Assigns.Get_Item('Global')

    $installPackageScripts = @()
 
    foreach ($packageName in $packageNames)
    {
        # get package
        $package = $hstwb.Packages.Get_Item($packageName.ToLower())

        # package name
        $name = ($package.Package.Name + " v" + $package.Package.Version)

        # add package installation lines to install packages script
        $installPackageLines = @()
        $installPackageLines += ("; Install package "+ $name)
        $installPackageLines += "echo """""
        $installPackageLines += ("echo ""Package '" + $name + "'""")

        $removePackageAssignLines = @()

        # get package assign names
        $packageAssignNames = @()
        if ($package.Package.Assigns)
        {
           $packageAssignNames += $package.Package.Assigns -split ',' | Where-Object { $_ }
        }

        # package assigns
        if ($hstwb.Assigns.ContainsKey($package.Package.Name))
        {
            $packageAssigns = $hstwb.Assigns.Get_Item($package.Package.Name)
        }
        else
        {
            $packageAssigns = @{}
        }

        # build and and remove package assigns
        foreach ($assignName in $packageAssignNames)
        {
            # get matching global and package assign name (case insensitive)
            $matchingGlobalAssignName = $globalAssigns.Keys | Where-Object { $_ -like $assignName } | Select-Object -First 1
            $matchingPackageAssignName = $packageAssigns.Keys | Where-Object { $_ -like $assignName } | Select-Object -First 1

            # fail, if package assign name doesn't exist in either global or package assigns
            if (!$matchingGlobalAssignName -and !$matchingPackageAssignName)
            {
                Fail $hstwb ("Error: Package '" + $package.Package.Name + "' doesn't have assign defined for '$assignName' in either global or package assigns!")
            }

            # skip, if package assign name is global
            if ($matchingGlobalAssignName)
            {
                continue
            }

            # get assign path and drive
            $assignId = CalculateMd5FromText (("{0}.{1}" -f $package.Package.Name, $assignName).ToLower())
            $assignPath = $packageAssigns.Get_Item($matchingPackageAssignName)

            # append add package assign
            $installPackageLines += ""
            $installPackageLines += BuildAddAssignScriptLines $assignId $assignName $assignPath

            # append ini file set for package assignm, if installer mode is build self install or build package installation
            if ($hstwb.Settings.Installer.Mode -eq "BuildSelfInstall" -or $hstwb.Settings.Installer.Mode -eq "BuildPackageInstallation")
            {
                $installPackageLines += 'execute PACKAGESDIR:IniFileSet "{0}/{1}" "{2}" "{3}" "$assignpath"' -f $hstwb.Paths.EnvArcDir, 'HstWB-Installer.Assigns.ini', $package.Package.Name, $assignName
            }

            # append remove package assign
            $removePackageAssignLines += BuildRemoveAssignScriptLines $assignId $assignName $assignPath
        }


        # add package dir assign, execute package install script and remove package dir assign
        $installPackageLines += ""
        $installPackageLines += "; Add package dir assign"
        $installPackageLines += ("Assign PACKAGEDIR: ""PACKAGESDIR:" + $packageName + """")
        $installPackageLines += ""
        $installPackageLines += "; Execute package install script"
        $installPackageLines += "execute ""PACKAGEDIR:Install"""
        $installPackageLines += ""
        $installPackageLines += "; Remove package dir assign"
        $installPackageLines += ("Assign PACKAGEDIR: ""PACKAGESDIR:" + $packageName + """ REMOVE")


        # add remove package assign lines, if there are any
        if ($removePackageAssignLines.Count -gt 0)
        {
            $installPackageLines += ""
            $installPackageLines += $removePackageAssignLines
        }


        $installPackageScripts += @{ "Id" = [guid]::NewGuid().ToString().Replace('-',''); "Name" = $name; "Lines" = $installPackageLines; "PackageName" = $packageName; "Package" = $package.Package }
    }

    return $installPackageScripts
}


# build reset assigns script lines
function BuildResetAssignsScriptLines($hstwb)
{
    $resetAssignsScriptLines = @()

    # reset assigns settings and get existing assign value, if present in prefs assigns ini file
    foreach ($assignSectionName in $hstwb.Assigns.keys)
    {
        $sectionAssigns = $hstwb.Assigns[$assignSectionName]

        foreach ($assignName in ($sectionAssigns.keys | Sort-Object | Where-Object { $_ -notlike 'HstWBInstallerDir' }))
        {
            $assignId = CalculateMd5FromText (("{0}.{1}" -f $assignSectionName, $assignName).ToLower())

            $resetAssignsScriptLines += ''
            $resetAssignsScriptLines += ("; Reset assign path setting for package '{0}' and assign '{1}'" -f $assignSectionName, $assignName)
            $resetAssignsScriptLines += '; Get assign path from ini'
            $resetAssignsScriptLines += 'set assignpath ""'
            $resetAssignsScriptLines += 'set assignpath "`execute PACKAGESDIR:IniFileGet "{0}/{1}" "{2}" "{3}"`"' -f $hstwb.Paths.EnvArcDir, 'HstWB-Installer.Assigns.ini', $assignSectionName, $assignName
            $resetAssignsScriptLines += ''
            $resetAssignsScriptLines += '; Create assign path setting, if assign path exists in ini. Otherwise delete assign path setting'
            $resetAssignsScriptLines += 'IF NOT "$assignpath" eq ""'
            $resetAssignsScriptLines += ('  echo "$assignpath" >"T:{0}"' -f $assignId)
            $resetAssignsScriptLines += 'ELSE'
            $resetAssignsScriptLines += ('  IF EXISTS "T:{0}"' -f $assignId)
            $resetAssignsScriptLines += ('    delete >NIL: "T:{0}"' -f $assignId)
            $resetAssignsScriptLines += '  ENDIF'
            $resetAssignsScriptLines += 'ENDIF'
        }
    }
    
    return $resetAssignsScriptLines
}


# build default assigns script lines
function BuildDefaultAssignsScriptLines($hstwb)
{
    $defaultAssignsScriptLines = @()

    # default assigns settings
    foreach ($assignSectionName in $hstwb.Assigns.keys)
    {
        $sectionAssigns = $hstwb.Assigns[$assignSectionName]

        foreach ($assignName in ($sectionAssigns.keys | Sort-Object | Where-Object { $_ -notlike 'HstWBInstallerDir' }))
        {
            $assignId = CalculateMd5FromText (("{0}.{1}" -f $assignSectionName, $assignName).ToLower())

            $defaultAssignsScriptLines += ''
            $defaultAssignsScriptLines += ("; Default assign path setting for package '{0}' and assign '{1}'" -f $assignSectionName, $assignName)
            $defaultAssignsScriptLines += ('IF EXISTS "T:{0}"' -f $assignId)
            $defaultAssignsScriptLines += ('  delete >NIL: "T:{0}"' -f $assignId)
            $defaultAssignsScriptLines += 'ENDIF'
        }
    }

    return $defaultAssignsScriptLines
}


# build install packages script lines
function BuildInstallPackagesScriptLines($hstwb, $installPackages)
{
    $installPackagesScriptLines = @()
    $installPackagesScriptLines += ""

    # append skip reset settings or install packages depending on installer mode
    if (($hstwb.Settings.Installer.Mode -eq "BuildSelfInstall" -or $hstwb.Settings.Installer.Mode -eq "BuildPackageInstallation") -and $installPackages.Count -gt 0)
    {
        $installPackagesScriptLines += "SKIP reset"
    }
    else
    {
        $installPackagesScriptLines += "SKIP installpackages"
    }

    $installPackagesScriptLines += ""
    $installPackagesScriptLines += ""
    $installPackagesScriptLines += "; Select assign path function"
    $installPackagesScriptLines += "; ---------------------------"
    $installPackagesScriptLines += "LAB functionselectassignpath"
    $installPackagesScriptLines += ""
    $installPackagesScriptLines += "; Set assign path to SYS:, if not defined"
    $installPackagesScriptLines += "IF ""`$assignpath"" eq """""
    $installPackagesScriptLines += "  set assignpath ""SYS:"""
    $installPackagesScriptLines += "ENDIF"
    $installPackagesScriptLines += ""
    $installPackagesScriptLines += "; Set assign path to SYS:, if path doesn't exist"
    $installPackagesScriptLines += "Assign >NIL: EXISTS ""`$assignpath"""
    $installPackagesScriptLines += "IF WARN"
    $installPackagesScriptLines += "  set assignpath ""SYS:"""
    $installPackagesScriptLines += "ENDIF"
    $installPackagesScriptLines += ""
    $installPackagesScriptLines += "; Show select path for assign dialog"
    $installPackagesScriptLines += "set newassignpath """""
    $installPackagesScriptLines += "set newassignpath ``REQUESTFILE DRAWER ""`$assignpath"" TITLE ""Select '`$assignname' assign"" NOICONS DRAWERSONLY``"
    $installPackagesScriptLines += ""
    $installPackagesScriptLines += "; Return, if select path for assign dialog is cancelled"
    $installPackagesScriptLines += "IF ""`$newassignpath"" eq """""
    $installPackagesScriptLines += "  SKIP `$returnlab"
    $installPackagesScriptLines += "ENDIF"
    $installPackagesScriptLines += ""
    $installPackagesScriptLines += "; Write new assign for assign id"
    $installPackagesScriptLines += "echo ""`$newassignpath"" >""T:`$assignid"""
    $installPackagesScriptLines += ""
    $installPackagesScriptLines += "; Strip tailing slash from assign path"
    $installPackagesScriptLines += "sed ""s/\/$//"" ""T:`$assignid"" >""T:_assignpath"""
    $installPackagesScriptLines += "copy >NIL: ""T:_assignpath"" ""T:`$assignid"""
    $installPackagesScriptLines += "delete >NIL: ""T:_assignpath"""
    $installPackagesScriptLines += ""
    $installPackagesScriptLines += "SKIP `$returnlab"
    $installPackagesScriptLines += ""


    # globl assigns
    $globalAssigns = $hstwb.Assigns.Get_Item('Global')


    # build global package assigns
    $addGlobalAssignScriptLines = @()
    $removeGlobalAssignScriptLines = @()
    foreach ($assignName in ($globalAssigns.keys | Sort-Object | Where-Object { $_ -notlike 'HstWBInstallerDir' }))
    {
        $assignId = CalculateMd5FromText (("{0}.{1}" -f 'Global', $assignName).ToLower())
        $assignPath = $globalAssigns.Get_Item($assignName)

        $addGlobalAssignScriptLines += BuildAddAssignScriptLines $assignId $assignName.ToUpper() $assignPath

        # append ini file set for global assign, if installer mode is build self install or build package installation
        if ($hstwb.Settings.Installer.Mode -eq "BuildSelfInstall" -or $hstwb.Settings.Installer.Mode -eq "BuildPackageInstallation")
        {
            $addGlobalAssignScriptLines += 'execute PACKAGESDIR:IniFileSet "{0}/{1}" "{2}" "{3}" "$assignpath"' -f $hstwb.Paths.EnvArcDir, 'HstWB-Installer.Assigns.ini', 'Global', $assignName
        }
        
        $removeGlobalAssignScriptLines += BuildRemoveAssignScriptLines $assignId $assignName.ToUpper() $assignPath
    }


    # build install package script lines
    $installPackageScripts = @()
    $installPackageScripts += BuildInstallPackageScriptLines $hstwb ($installPackages | ForEach-Object { $_.PackageFileName })

    if (($hstwb.Settings.Installer.Mode -eq "BuildSelfInstall" -or $hstwb.Settings.Installer.Mode -eq "BuildPackageInstallation") -and $installPackages.Count -gt 0)
    {
        # get install package name padding
        $installPackageNamesPadding = ($installPackages | ForEach-Object { $_.FullName } | Sort-Object @{expression={$_.Length};Ascending=$false} | Select-Object -First 1).Length

        # reset
        $installPackagesScriptLines += ''
        $installPackagesScriptLines += '; Reset'
        $installPackagesScriptLines += '; -----'
        $installPackagesScriptLines += 'LAB reset'

        # reset packages
        foreach ($installPackageScript in $installPackageScripts)
        {
            $installPackagesScriptLines += ''
            $installPackagesScriptLines += ("; Reset package '{0}'" -f $installPackageScript.Package.Name)
            $installPackagesScriptLines += ("IF EXISTS ""T:{0}""" -f $installPackageScript.Id)
            $installPackagesScriptLines += ("  delete >NIL: ""T:{0}""" -f $installPackageScript.Id)
            $installPackagesScriptLines += "ENDIF"
        }

        $installPackagesScriptLines += ''
        $installPackagesScriptLines += BuildResetAssignsScriptLines $hstwb
        $installPackagesScriptLines += ''
        $installPackagesScriptLines += 'SKIP installpackagesmenu'
        $installPackagesScriptLines += ''

        # reset assigns
        $installPackagesScriptLines += ''
        $installPackagesScriptLines += '; Reset assigns'
        $installPackagesScriptLines += '; -------------'
        $installPackagesScriptLines += 'LAB resetassigns'
        $installPackagesScriptLines += ''
        $installPackagesScriptLines += BuildResetAssignsScriptLines $hstwb
        $installPackagesScriptLines += ''
        $installPackagesScriptLines += 'SKIP editassignsmenu'

        # default assigns
        $installPackagesScriptLines += ''
        $installPackagesScriptLines += '; Default assigns'
        $installPackagesScriptLines += '; ---------------'
        $installPackagesScriptLines += 'LAB defaultassigns'
        $installPackagesScriptLines += ''
        $installPackagesScriptLines += BuildDefaultAssignsScriptLines $hstwb
        $installPackagesScriptLines += ''
        $installPackagesScriptLines += 'SKIP editassignsmenu'

        # install packages menu label
        $installPackagesScriptLines += ""
        $installPackagesScriptLines += "; Install packages menu"
        $installPackagesScriptLines += "; ---------------------"
        $installPackagesScriptLines += "LAB installpackagesmenu"
        $installPackagesScriptLines += ""
        $installPackagesScriptLines += "echo """" NOLINE >T:installpackagesmenu"

        # add package options to menu
        foreach ($installPackageScript in $installPackageScripts)
        {
            $installPackagesScriptLines += (("echo ""{0,-" + $installPackageNamesPadding + "} : "" NOLINE >>T:installpackagesmenu") -f $installPackageScript.Name)
            $installPackagesScriptLines += ("IF EXISTS ""T:{0}""" -f $installPackageScript.Id)
            $installPackagesScriptLines += "  echo ""YES"" >>T:installpackagesmenu"
            $installPackagesScriptLines += "ELSE"
            $installPackagesScriptLines += "  echo ""NO "" >>T:installpackagesmenu"
            $installPackagesScriptLines += "ENDIF"
        }

        # add install package option and show install packages menu
        $installPackagesScriptLines += "echo """ + (new-object System.String('=', ($installPackageNamesPadding + 6))) + """ >>T:installpackagesmenu"
        $installPackagesScriptLines += "echo ""View Readme"" >>T:installpackagesmenu"
        $installPackagesScriptLines += "echo ""Edit assigns"" >>T:installpackagesmenu"
        $installPackagesScriptLines += "echo ""Install packages"" >>T:installpackagesmenu"

        if ($hstwb.Settings.Installer.Mode -eq "BuildPackageInstallation")
        {
            $installPackagesScriptLines += "echo ""Quit"" >>T:installpackagesmenu"
        }

        $installPackagesScriptLines += ""
        $installPackagesScriptLines += "set installpackagesmenu """""
        $installPackagesScriptLines += "set installpackagesmenu ""``ReqList CLONERT I=T:installpackagesmenu H=""Select packages to install"" PAGE=18``"""
        $installPackagesScriptLines += "delete >NIL: T:installpackagesmenu"

        # switch package options
        for($i = 0; $i -lt $installPackageScripts.Count; $i++)
        {
            $installPackageScript = $installPackageScripts[$i]

            $installPackagesScriptLines += ""
            $installPackagesScriptLines += ("IF ""`$installpackagesmenu"" eq """ + ($i + 1) + """")
            $installPackagesScriptLines += ("  IF EXISTS ""T:{0}""" -f $installPackageScript.Id)
            $installPackagesScriptLines += ("    delete >NIL: ""T:{0}""" -f $installPackageScript.Id)
            $installPackagesScriptLines += "  ELSE"
            $installPackagesScriptLines += ("    echo """" NOLINE >""T:{0}""" -f $installPackageScript.Id)
            $installPackagesScriptLines += "  ENDIF"
            $installPackagesScriptLines += "ENDIF"
        }

        # install packages option and skip back to install packages menu 
        $installPackagesScriptLines += ""
        $installPackagesScriptLines += ("IF ""`$installpackagesmenu"" eq """ + ($installPackageScripts.Count + 2) + """")
        $installPackagesScriptLines += "  SKIP viewreadmemenu"
        $installPackagesScriptLines += "ENDIF"
        $installPackagesScriptLines += ""
        $installPackagesScriptLines += ("IF ""`$installpackagesmenu"" eq """ + ($installPackageScripts.Count + 3) + """")
        $installPackagesScriptLines += "  SKIP editassignsmenu"
        $installPackagesScriptLines += "ENDIF"
        $installPackagesScriptLines += ""
        $installPackagesScriptLines += ("IF ""`$installpackagesmenu"" eq """ + ($installPackageScripts.Count + 4) + """")
        $installPackagesScriptLines += "  set confirm ``RequestChoice ""Confirm"" ""Install selected packages?"" ""Yes|No""``"
        $installPackagesScriptLines += "  IF ""`$confirm"" EQ ""1"""
        $installPackagesScriptLines += "    SKIP installpackages"
        $installPackagesScriptLines += "  ENDIF"
        $installPackagesScriptLines += "ENDIF"

        if ($hstwb.Settings.Installer.Mode -eq "BuildPackageInstallation")
        {
            $installPackagesScriptLines += ""
            $installPackagesScriptLines += ("IF ""`$installpackagesmenu"" eq """ + ($installPackageScripts.Count + 5) + """")
            $installPackagesScriptLines += "  quit"
            $installPackagesScriptLines += "ENDIF"
        }

        $installPackagesScriptLines += ""
        $installPackagesScriptLines += "SKIP BACK installpackagesmenu"


        # view readme
        # -----------
        $installPackagesScriptLines += ""
        $installPackagesScriptLines += "; View readme menu"
        $installPackagesScriptLines += "; ----------------"
        $installPackagesScriptLines += ""
        $installPackagesScriptLines += "LAB viewreadmemenu"
        $installPackagesScriptLines += "echo """" NOLINE >T:viewreadmemenu"

        # add package options to view readme menu
        foreach ($installPackageScript in $installPackageScripts)
        {
            $installPackagesScriptLines += (("echo ""{0,-" + $installPackageNamesPadding + "}"" >>T:viewreadmemenu") -f $installPackageScript.Name)
        }

        # add back option to view readme menu
        $installPackagesScriptLines += "echo """ + (new-object System.String('=', $installPackageNamesPadding)) + """ >>T:viewreadmemenu"
        $installPackagesScriptLines += "echo ""Back"" >>T:viewreadmemenu"

        $installPackagesScriptLines += "set viewreadmemenu ````"
        $installPackagesScriptLines += "set viewreadmemenu ``ReqList CLONERT I=T:viewreadmemenu H=""View Readme"" PAGE=18``"
        $installPackagesScriptLines += "delete >NIL: T:viewreadmemenu"

        # switch package options
        for($i = 0; $i -lt $installPackageScripts.Count; $i++)
        {
            $installPackageScript = $installPackageScripts[$i]

            $installPackagesScriptLines += ""
            $installPackagesScriptLines += ("IF ""`$viewreadmemenu"" eq """ + ($i + 1) + """")
            $installPackagesScriptLines += ("  IF EXISTS ""PACKAGESDIR:{0}/README.guide""" -f $installPackageScript.PackageName)
            $installPackagesScriptLines += ("    cd ""PACKAGESDIR:{0}""" -f $installPackageScript.PackageName)
            $installPackagesScriptLines += "    multiview README.guide"
            $installPackagesScriptLines += "    cd ""PACKAGESDIR:"""
            $installPackagesScriptLines += "  ELSE"
            $installPackagesScriptLines += ("    REQUESTCHOICE ""No Readme"" ""Package '{0}' doesn't have a readme file!"" ""OK"" >NIL:" -f $installPackageScript.Name)
            $installPackagesScriptLines += "  ENDIF"
            $installPackagesScriptLines += "ENDIF"
        }

        $installPackagesScriptLines += ""
        $installPackagesScriptLines += ("IF ""`$viewreadmemenu"" eq """ + ($installPackageScripts.Count + 2) + """")
        $installPackagesScriptLines += "  SKIP BACK installpackagesmenu"
        $installPackagesScriptLines += "ENDIF"
        $installPackagesScriptLines += ""
        $installPackagesScriptLines += "SKIP BACK viewreadmemenu"


        # edit assigns
        # ------------
        $installPackagesScriptLines += ""
        $installPackagesScriptLines += "; Edit assigns menu"
        $installPackagesScriptLines += ";------------------"
        $installPackagesScriptLines += "LAB editassignsmenu"
        $installPackagesScriptLines += ""
        $installPackagesScriptLines += "echo """" NOLINE >T:editassignsmenu"

        $assignSectionNames = @('Global')
        $assignSectionNames += $hstwb.Assigns.keys | Where-Object { $_ -notlike 'Global' } | Sort-Object


        $editAssignsMenuOption = 0
        $editAssignsMenuOptionScriptLines = @()

        foreach($assignSectionName in $assignSectionNames)
        {
            # add menu option to show assign section name
            $installPackagesScriptLines += ("echo ""| {0} |"" >>T:editassignsmenu" -f $assignSectionName)

            # increase menu option
            $editAssignsMenuOption += 1

            # get section assigns
            $sectionAssigns = $hstwb.Assigns[$assignSectionName]

            foreach ($assignName in ($sectionAssigns.keys | Sort-Object))
            {
                # skip hstwb installer assign name for global assigns
                if ($assignSectionName -like 'Global' -and $assignName -like 'HstWBInstallerDir')
                {
                    continue
                }

                # increase menu option
                $editAssignsMenuOption++

                $assignId = CalculateMd5FromText (("{0}.{1}" -f $assignSectionName, $assignName).ToLower())
                $assignPath = $sectionAssigns[$assignName]

                # add menu option showing and editing assign witnin section
                $installPackagesScriptLines += ""
                $installPackagesScriptLines += ("IF EXISTS ""T:{0}""" -f $assignId)
                $installPackagesScriptLines += ("  echo ""{0}: = '``type ""T:{1}""``'"" >>T:editassignsmenu" -f $assignName, $assignId)
                $installPackagesScriptLines += "ELSE"
                $installPackagesScriptLines += ("  Assign >NIL: EXISTS ""{0}""" -f $assignPath)
                $installPackagesScriptLines += "  IF WARN"
                $installPackagesScriptLines += ("    echo ""{0}: = ?"" >>T:editassignsmenu" -f $assignName)
                $installPackagesScriptLines += "  ELSE"
                $installPackagesScriptLines += ("    echo ""{0}: = '{1}'"" >>T:editassignsmenu" -f $assignName, $assignPath)
                $installPackagesScriptLines += "  ENDIF"
                $installPackagesScriptLines += "ENDIF"

                $editAssignsMenuOptionScriptLines += ""
                $editAssignsMenuOptionScriptLines += ("IF ""`$editassignsmenu"" eq """ + $editAssignsMenuOption + """")
                $editAssignsMenuOptionScriptLines += ("  set assignid ""{0}""" -f $assignId)
                $editAssignsMenuOptionScriptLines += ("  set assignname ""{0}""" -f $assignName)
                $editAssignsMenuOptionScriptLines += ("  IF EXISTS ""T:{0}""" -f $assignId)
                $editAssignsMenuOptionScriptLines += ("    set assignpath ""``type ""T:{0}""``""" -f $assignId)
                $editAssignsMenuOptionScriptLines += "  ELSE"
                $editAssignsMenuOptionScriptLines += ("    set assignpath ""{0}""" -f $assignPath)
                $editAssignsMenuOptionScriptLines += "  ENDIF"
                $editAssignsMenuOptionScriptLines += "  set returnlab ""editassignsmenu"""
                $editAssignsMenuOptionScriptLines += "  SKIP BACK functionselectassignpath"
                $editAssignsMenuOptionScriptLines += "ENDIF"
            }
        }

        # add back option to view readme menu
        $installPackagesScriptLines += "echo ""========================================"" >>T:editassignsmenu"
        $installPackagesScriptLines += "echo ""Reset assigns"" >>T:editassignsmenu"
        $installPackagesScriptLines += "echo ""Default assigns"" >>T:editassignsmenu"
        $installPackagesScriptLines += "echo ""Back"" >>T:editassignsmenu"

        $installPackagesScriptLines += "set editassignsmenu ````"
        $installPackagesScriptLines += "set editassignsmenu ``ReqList CLONERT I=T:editassignsmenu H=""Edit assigns"" PAGE=18``"
        $installPackagesScriptLines += "delete >NIL: T:editassignsmenu"

        # add edit assigns menu options script lines
        $editAssignsMenuOptionScriptLines | ForEach-Object { $installPackagesScriptLines += $_ }

        # add back option to edit assigns menu
        $installPackagesScriptLines += ""
        $installPackagesScriptLines += ("IF ""`$editassignsmenu"" eq """ + ($editAssignsMenuOption + 2) + """")
        $installPackagesScriptLines += "  set confirm ``RequestChoice ""Confirm"" ""Are you sure you want to reset assigns?"" ""Yes|No""``"
        $installPackagesScriptLines += "  IF ""`$confirm"" EQ ""1"""
        $installPackagesScriptLines += "    SKIP BACK resetassigns"
        $installPackagesScriptLines += "  ENDIF"
        $installPackagesScriptLines += "ENDIF"
        $installPackagesScriptLines += ""
        $installPackagesScriptLines += ("IF ""`$editassignsmenu"" eq """ + ($editAssignsMenuOption + 3) + """")
        $installPackagesScriptLines += "  set confirm ``RequestChoice ""Confirm"" ""Are you sure you want to use default assigns?"" ""Yes|No""``"
        $installPackagesScriptLines += "  IF ""`$confirm"" EQ ""1"""
        $installPackagesScriptLines += "    SKIP BACK defaultassigns"
        $installPackagesScriptLines += "  ENDIF"
        $installPackagesScriptLines += "ENDIF"
        $installPackagesScriptLines += ""
        $installPackagesScriptLines += ("IF ""`$editassignsmenu"" eq """ + ($editAssignsMenuOption + 4) + """")
        $installPackagesScriptLines += "  SKIP BACK installpackagesmenu"
        $installPackagesScriptLines += "ENDIF"
        $installPackagesScriptLines += ""
        $installPackagesScriptLines += "SKIP BACK editassignsmenu"


        # install packages
        # ----------------
        $installPackagesScriptLines += ""
        $installPackagesScriptLines += "; Install packages"
        $installPackagesScriptLines += "; ----------------"
        $installPackagesScriptLines += "LAB installpackages"
        $installPackagesScriptLines += ""
        $installPackagesScriptLines += "echo ""*ec"""
        $installPackagesScriptLines += "echo ""Package Installation"""
        $installPackagesScriptLines += "echo ""--------------------"""
        $installPackagesScriptLines += ''
        $installPackagesScriptLines += '; Create env-archive directory, if it doesn''t exist and ini file set for package assign'
        $installPackagesScriptLines += 'IF NOT EXISTS "{0}"' -f $hstwb.Paths.EnvArcDir
        $installPackagesScriptLines += '  makepath "{0}"' -f $hstwb.Paths.EnvArcDir
        $installPackagesScriptLines += 'ENDIF'


        # get assign section names
        $assignSectionNames = @('Global')
        $assignSectionNames += $hstwb.Assigns.keys | Where-Object { $_ -notlike 'Global' } | Sort-Object

        # build validate assigns
        foreach($assignSectionName in $assignSectionNames)
        {
            # get section assigns
            $sectionAssigns = $hstwb.Assigns[$assignSectionName]

            foreach ($assignName in ($sectionAssigns.keys | Sort-Object))
            {
                # skip hstwb installer assign name for global assigns
                if ($assignSectionName -like 'Global' -and $assignName -like 'HstWBInstallerDir')
                {
                    continue
                }

                $assignId = CalculateMd5FromText (("{0}.{1}" -f $assignSectionName, $assignName).ToLower())
                $assignPath = $sectionAssigns[$assignName]

                $installPackagesScriptLines += ""
                $installPackagesScriptLines += ("; Validate assign '{0}'" -f $assignName)
                $installPackagesScriptLines += BuildAssignPathScriptLines $assignId $assignPath
                $installPackagesScriptLines += "IF ""`$assignpath"" eq """""
                $installPackagesScriptLines += ("  REQUESTCHOICE ""Error"" ""No path is defined*Nfor assign '{0}'*Nin section '{1}'!"" ""OK"" >NIL:" -f $assignName, $assignSectionName)
                $installPackagesScriptLines += "  SKIP BACK installpackagesmenu"
                $installPackagesScriptLines += "ENDIF"
                $installPackagesScriptLines += "IF NOT EXISTS ""`$assignpath"""
                $installPackagesScriptLines += ("  REQUESTCHOICE ""Error"" ""Path '`$assignpath' doesn't exist*Nfor assign '{0}'*Nin section '{1}'!"" ""OK"" >NIL:" -f $assignName, $assignSectionName)
                $installPackagesScriptLines += "  SKIP BACK installpackagesmenu"
                $installPackagesScriptLines += "ENDIF"
            }
        }

        # append add global assign script lines
        if ($addGlobalAssignScriptLines.Count -gt 0)
        {
            $installPackagesScriptLines += ""
            $installPackagesScriptLines += $addGlobalAssignScriptLines
        }

        # add install package script for each package
        foreach ($installPackageScript in $installPackageScripts)
        {
            $installPackagesScriptLines += ""
            $installPackagesScriptLines += ("; Install package '{0}', if it's selected" -f $installPackageScript.Name)
            $installPackagesScriptLines += ("IF EXISTS T:" + $installPackageScript.Id)
            $installPackagesScriptLines += 'execute PACKAGESDIR:IniFileSet "{0}/{1}" "{2}" "{3}" "{4}"' -f $hstwb.Paths.EnvArcDir, 'HstWB-Installer.Packages.ini', $installPackageScript.Package.Name, 'Version', $installPackageScript.Package.Version
            $installPackageScript.Lines | ForEach-Object { $installPackagesScriptLines += ("  " + $_) }
            $installPackagesScriptLines += "ENDIF"
        }

        # append remove global assign script lines
        if ($removeGlobalAssignScriptLines.Count -gt 0)
        {
            $installPackagesScriptLines += ""
            $installPackagesScriptLines += $removeGlobalAssignScriptLines
        }
    }
    else 
    {
        # install packages
        # ----------------
        $installPackagesScriptLines += ""
        $installPackagesScriptLines += "; Install packages"
        $installPackagesScriptLines += "; ----------------"
        $installPackagesScriptLines += "LAB installpackages"
        $installPackagesScriptLines += ""
        $installPackagesScriptLines += "echo ""*ec"""
        $installPackagesScriptLines += "echo ""Package Installation"""
        $installPackagesScriptLines += "echo ""--------------------"""


        # append add global assign script lines
        if ($addGlobalAssignScriptLines.Count -gt 0)
        {
            $installPackagesScriptLines += ""
            $installPackagesScriptLines += $addGlobalAssignScriptLines
        }

        # add install package script for each package
        foreach ($installPackageScript in $installPackageScripts)
        {
            $installPackageScript.Lines | ForEach-Object { $installPackagesScriptLines += $_ }
        }

        # append remove global assign script lines
        if ($removeGlobalAssignScriptLines.Count -gt 0)
        {
            $installPackagesScriptLines += ""
            $installPackagesScriptLines += $removeGlobalAssignScriptLines
        }
    }

    return $installPackagesScriptLines
}


# build winuae image harddrives config text
function BuildFsUaeHarddrivesConfigText($hstwb, $disableBootableHarddrives)
{
    # winuae image harddrives config file
    $winuaeImageHarddrivesUaeConfigFile = [System.IO.Path]::Combine($hstwb.Settings.Image.ImageDir, "harddrives.uae")

    # fail, if winuae image harddrives config file doesn't exist
    if (!(Test-Path -Path $winuaeImageHarddrivesUaeConfigFile))
    {
        Fail $hstwb ("Error: Image harddrives config file '" + $winuaeImageHarddrivesUaeConfigFile + "' doesn't exist!")
    }

    # read winuae image harddrives config text
    $winuaeImageHarddrivesConfigText = [System.IO.File]::ReadAllText($winuaeImageHarddrivesUaeConfigFile)

    # replace imagedir placeholders
    $winuaeImageHarddrivesConfigText = $winuaeImageHarddrivesConfigText.Replace('[$ImageDir]', $hstwb.Settings.Image.ImageDir)
    $winuaeImageHarddrivesConfigText = $winuaeImageHarddrivesConfigText.Replace('[$ImageDirEscaped]', $hstwb.Settings.Image.ImageDir)
    $winuaeImageHarddrivesConfigText = $winuaeImageHarddrivesConfigText.Replace('\\', '\').Replace('\', '/')
    $winuaeImageHarddrivesConfigText = $winuaeImageHarddrivesConfigText.Trim()

    $uaehfs = @()
    $winuaeImageHarddrivesConfigText -split "`r`n" | ForEach-Object { $_ | Select-String -Pattern '^uaehf\d+=(.*)' -AllMatches | ForEach-Object { $_.Matches } | ForEach-Object { $uaehfs += $_.Groups[1].Value.Trim() } }
    $harddrives = @()
    
    foreach ($uaehf in $uaehfs)
    {
        $uaehf | Select-String -Pattern '^hdf,[^,]*,([^,:]*):"?([^"]*)"?,[^,]*,[^,]*,[^,]*,[^,]*,([^,]*)' -AllMatches | ForEach-Object { $_.Matches } | ForEach-Object { $harddrives += @{ 'Label' = $_.Groups[1].Value.Trim(); 'Path' = $_.Groups[2].Value.Trim(); 'Priority' = $_.Groups[3].Value.Trim() } }
        $uaehf | Select-String -Pattern '^dir,[^,]*,([^,:]*):[^,:]*:([^,]*),([^,]*)' -AllMatches | ForEach-Object { $_.Matches } | ForEach-Object { $harddrives += @{ 'Label' = $_.Groups[1].Value.Trim(); 'Path' = $_.Groups[2].Value.Trim(); 'Priority' = $_.Groups[3].Value.Trim() } }
    }

    $fsUaeImageHarddrives = @()
    
    for($i = 0; $i -lt $harddrives.Count; $i++)
    {
        $harddrive = $harddrives[$i]
        $fsUaeImageHarddrives += "hard_drive_{0} = {1}" -f $i, ($harddrive.Path.Replace('\', '/'))
        $fsUaeImageHarddrives += "hard_drive_{0}_label = {1}" -f $i, ($harddrive.Label)
        
        if ($disableBootableHarddrives)
        {
            $fsUaeImageHarddrives += "hard_drive_{0}_priority = -128" -f $i
        }
        else
        {
            $fsUaeImageHarddrives += "hard_drive_{0}_priority = {1}" -f $i, $harddrive.Priority
        }
    }

    return $fsUaeImageHarddrives -join "`r`n"
}


# build fs-uae install harddrives config text
function BuildFsUaeInstallHarddrivesConfigText($hstwb, $installDir, $packagesDir, $os39Dir, $boot)
{
    # build fs-uae image harddrives config
    $fsUaeImageHarddrivesConfigText = BuildFsUaeHarddrivesConfigText $hstwb $boot

    # get harddrive index of last hard drive config from fs-uae image harddrives config
    $harddriveIndex = 0
    $fsUaeImageHarddrivesConfigText -split "`r`n" | ForEach-Object { $_ | Select-String -Pattern '^hard_drive_(\d+)' -AllMatches | ForEach-Object { $_.Matches } | ForEach-Object { $harddriveIndex = $_.Groups[1].Value.Trim() } }

    # fs-uae  harddrives config file
    if ($boot)
    {
        $fsUaeHarddrivesConfigFile = Join-Path $hstwb.Paths.FsUaePath -ChildPath "harddrives_boot.fs-uae"
    }
    else
    {
        $fsUaeHarddrivesConfigFile = Join-Path $hstwb.Paths.FsUaePath -ChildPath "harddrives_noboot.fs-uae"
    }

    # fail, if fs-uae harddrives config file doesn't exist
    if (!(Test-Path -Path $fsUaeHarddrivesConfigFile))
    {
        Fail $hstwb ("Error: FS-UAE harddrives config file '" + $fsUaeHarddrivesConfigFile + "' doesn't exist!")
    }
    
    # read fs-uae harddrives config file
    $fsUaeHarddrivesConfigText = [System.IO.File]::ReadAllText($fsUaeHarddrivesConfigFile)
    
    # replace winuae install harddrives placeholders
    $fsUaeHarddrivesConfigText = $fsUaeHarddrivesConfigText.Replace('[$InstallDir]', $installDir)
    $fsUaeHarddrivesConfigText = $fsUaeHarddrivesConfigText.Replace('[$InstallHarddriveIndex]', [int]$harddriveIndex + 1)
    $fsUaeHarddrivesConfigText = $fsUaeHarddrivesConfigText.Replace('[$PackagesDir]', $packagesDir)
    $fsUaeHarddrivesConfigText = $fsUaeHarddrivesConfigText.Replace('[$PackagesHarddriveIndex]', [int]$harddriveIndex + 2)
    $fsUaeHarddrivesConfigText = $fsUaeHarddrivesConfigText.Replace('[$Os39Dir]', $os39Dir)
    $fsUaeHarddrivesConfigText = $fsUaeHarddrivesConfigText.Replace('[$Os39HarddriveIndex]', [int]$harddriveIndex + 3)
    $fsUaeHarddrivesConfigText = $fsUaeHarddrivesConfigText.Trim()
    
    # return winuae image and install harddrives config
    return $fsUaeImageHarddrivesConfigText + "`r`n" + $fsUaeHarddrivesConfigText    
}


# build fs-uae self install harddrives config text
function BuildFsUaeSelfInstallHarddrivesConfigText($hstwb, $workbenchDir, $kickstartDir, $os39Dir)
{
    # build fs-uae image harddrives config
    $fsUaeImageHarddrivesConfigText = BuildFsUaeHarddrivesConfigText $hstwb $false

    # get harddrive index of last hard drive config from fs-uae image harddrives config
    $harddriveIndex = 0
    $fsUaeImageHarddrivesConfigText -split "`r`n" | ForEach-Object { $_ | Select-String -Pattern '^hard_drive_(\d+)' -AllMatches | ForEach-Object { $_.Matches } | ForEach-Object { $harddriveIndex = $_.Groups[1].Value.Trim() } }

    $fsUaeSelfInstallHarddrivesConfigFile = [System.IO.Path]::Combine($fsUaePath, "harddrives_selfinstall.fs-uae")

    # fail, if fs-uae self install harddrives config file doesn't exist
    if (!(Test-Path -Path $fsUaeSelfInstallHarddrivesConfigFile))
    {
        Fail $hstwb ("Error: Self install harddrives config file '" + $fsUaeSelfInstallHarddrivesConfigFile + "' doesn't exist!")
    }

    # read fs-uae self install harddrives config file
    $fsUaeSelfInstallHarddrivesConfigText = [System.IO.File]::ReadAllText($fsUaeSelfInstallHarddrivesConfigFile)

    # replace winuae self install harddrives placeholders
    $fsUaeSelfInstallHarddrivesConfigText = $fsUaeSelfInstallHarddrivesConfigText.Replace('[$WorkbenchDir]', $workbenchDir.Replace('\', '/'))
    $fsUaeSelfInstallHarddrivesConfigText = $fsUaeSelfInstallHarddrivesConfigText.Replace('[$WorkbenchHarddriveIndex]', [int]$harddriveIndex + 1)
    $fsUaeSelfInstallHarddrivesConfigText = $fsUaeSelfInstallHarddrivesConfigText.Replace('[$KickstartDir]', $kickstartDir.Replace('\', '/'))
    $fsUaeSelfInstallHarddrivesConfigText = $fsUaeSelfInstallHarddrivesConfigText.Replace('[$KickstartHarddriveIndex]', [int]$harddriveIndex + 2)
    $fsUaeSelfInstallHarddrivesConfigText = $fsUaeSelfInstallHarddrivesConfigText.Replace('[$Os39Dir]', $os39Dir.Replace('\', '/'))
    $fsUaeSelfInstallHarddrivesConfigText = $fsUaeSelfInstallHarddrivesConfigText.Replace('[$Os39HarddriveIndex]', [int]$harddriveIndex + 3)
    $fsUaeSelfInstallHarddrivesConfigText = $fsUaeSelfInstallHarddrivesConfigText.Trim()

    # return fs-uae image and self install harddrives config
    return $fsUaeImageHarddrivesConfigText + "`r`n" + $fsUaeSelfInstallHarddrivesConfigText
}


# build winuae image harddrives config text
function BuildWinuaeImageHarddrivesConfigText($hstwb, $disableBootableHarddrives)
{
    # winuae image harddrives config file
    $winuaeImageHarddrivesUaeConfigFile = [System.IO.Path]::Combine($hstwb.Settings.Image.ImageDir, "harddrives.uae")

    # fail, if winuae image harddrives config file doesn't exist
    if (!(Test-Path -Path $winuaeImageHarddrivesUaeConfigFile))
    {
        Fail $hstwb ("Error: Image harddrives config file '" + $winuaeImageHarddrivesUaeConfigFile + "' doesn't exist!")
    }

    # read winuae image harddrives config text
    $winuaeImageHarddrivesConfigText = [System.IO.File]::ReadAllText($winuaeImageHarddrivesUaeConfigFile)

    # replace imagedir placeholders
    $winuaeImageHarddrivesConfigText = $winuaeImageHarddrivesConfigText.Replace('[$ImageDir]', $hstwb.Settings.Image.ImageDir)
    $winuaeImageHarddrivesConfigText = $winuaeImageHarddrivesConfigText.Replace('[$ImageDirEscaped]', $hstwb.Settings.Image.ImageDir.Replace('\', '\\'))
    $winuaeImageHarddrivesConfigText = $winuaeImageHarddrivesConfigText.Trim()

    if ($disableBootableHarddrives)
    {
        $winuaeImageHarddrivesConfigText = ($winuaeImageHarddrivesConfigText -split "`r`n" | ForEach-Object { $_ -replace ',-?\d+$', ',-128' -replace ',-?\d+,,uae$', ',-128,,uae' }) -join "`r`n"
    }

    return $winuaeImageHarddrivesConfigText
}


# build winuae install harddrives config text
function BuildWinuaeInstallHarddrivesConfigText($hstwb, $installDir, $packagesDir, $os39Dir, $boot)
{
    # build winuae image harddrives config
    $winuaeImageHarddrivesConfigText = BuildWinuaeImageHarddrivesConfigText $hstwb $boot

    # get uaehf index of last uaehf config from winuae image harddrives config
    $uaehfIndex = 0
    $winuaeImageHarddrivesConfigText -split "`r`n" | ForEach-Object { $_ | Select-String -Pattern '^uaehf(\d+)=' -AllMatches | ForEach-Object { $_.Matches } | ForEach-Object { $uaehfIndex = $_.Groups[1].Value.Trim() } }

    # winuae install harddrives config file
    if ($boot)
    {
        $winuaeInstallHarddrivesConfigFile = [System.IO.Path]::Combine($hstwb.Paths.WinuaePath, "harddrives_boot.uae")
    }
    else
    {
        $winuaeInstallHarddrivesConfigFile = [System.IO.Path]::Combine($hstwb.Paths.WinuaePath, "harddrives_noboot.uae")
    }

    # fail, if winuae install harddrives config file doesn't exist
    if (!(Test-Path -Path $winuaeInstallHarddrivesConfigFile))
    {
        Fail $hstwb ("Error: Install harddrives config file '" + $winuaeInstallHarddrivesConfigFile + "' doesn't exist!")
    }

    # read winuae install harddrives config file
    $winuaeInstallHarddrivesConfigText = [System.IO.File]::ReadAllText($winuaeInstallHarddrivesConfigFile)

    # replace winuae install harddrives placeholders
    $winuaeInstallHarddrivesConfigText = $winuaeInstallHarddrivesConfigText.Replace('[$InstallDir]', $installDir)
    $winuaeInstallHarddrivesConfigText = $winuaeInstallHarddrivesConfigText.Replace('[$InstallUaehfIndex]', [int]$uaehfIndex + 1)
    $winuaeInstallHarddrivesConfigText = $winuaeInstallHarddrivesConfigText.Replace('[$PackagesDir]', $packagesDir)
    $winuaeInstallHarddrivesConfigText = $winuaeInstallHarddrivesConfigText.Replace('[$PackagesUaehfIndex]', [int]$uaehfIndex + 2)
    $winuaeInstallHarddrivesConfigText = $winuaeInstallHarddrivesConfigText.Replace('[$Os39Dir]', $os39Dir)
    $winuaeInstallHarddrivesConfigText = $winuaeInstallHarddrivesConfigText.Replace('[$Os39UaehfIndex]', [int]$uaehfIndex + 3)
    $winuaeInstallHarddrivesConfigText = $winuaeInstallHarddrivesConfigText.Replace('[$Cd0UaehfIndex]', [int]$uaehfIndex + 4)
    $winuaeInstallHarddrivesConfigText = $winuaeInstallHarddrivesConfigText.Trim()

    # return winuae image and install harddrives config
    return $winuaeImageHarddrivesConfigText + "`r`n" + $winuaeInstallHarddrivesConfigText
}


# build winuae self install harddrives config text
function BuildWinuaeSelfInstallHarddrivesConfigText($hstwb, $workbenchDir, $kickstartDir, $os39Dir)
{
    # build winuae image harddrives config
    $winuaeImageHarddrivesConfigText = BuildWinuaeImageHarddrivesConfigText $hstwb $false

    # get uaehf index of last uaehf config from winuae image harddrives config
    $uaehfIndex = 0
    $winuaeImageHarddrivesConfigText -split "`r`n" | ForEach-Object { $_ | Select-String -Pattern '^uaehf(\d+)=' -AllMatches | ForEach-Object { $_.Matches } | ForEach-Object { $uaehfIndex = $_.Groups[1].Value.Trim() } }

    $winuaeSelfInstallHarddrivesConfigFile = [System.IO.Path]::Combine($hstwb.Paths.WinuaePath, "harddrives_selfinstall.uae")

    # fail, if winuae self install harddrives config file doesn't exist
    if (!(Test-Path -Path $winuaeSelfInstallHarddrivesConfigFile))
    {
        Fail $hstwb ("Error: Self install harddrives config file '" + $winuaeSelfInstallHarddrivesConfigFile + "' doesn't exist!")
    }

    # read winuae self install harddrives config file
    $winuaeSelfInstallHarddrivesConfigText = [System.IO.File]::ReadAllText($winuaeSelfInstallHarddrivesConfigFile)

    # replace winuae self install harddrives placeholders
    $winuaeSelfInstallHarddrivesConfigText = $winuaeSelfInstallHarddrivesConfigText.Replace('[$WorkbenchDir]', $workbenchDir)
    $winuaeSelfInstallHarddrivesConfigText = $winuaeSelfInstallHarddrivesConfigText.Replace('[$WorkbenchUaehfIndex]', [int]$uaehfIndex + 1)
    $winuaeSelfInstallHarddrivesConfigText = $winuaeSelfInstallHarddrivesConfigText.Replace('[$KickstartDir]', $kickstartDir)
    $winuaeSelfInstallHarddrivesConfigText = $winuaeSelfInstallHarddrivesConfigText.Replace('[$KickstartUaehfIndex]', [int]$uaehfIndex + 2)
    $winuaeSelfInstallHarddrivesConfigText = $winuaeSelfInstallHarddrivesConfigText.Replace('[$Os39Dir]', $os39Dir)
    $winuaeSelfInstallHarddrivesConfigText = $winuaeSelfInstallHarddrivesConfigText.Replace('[$Os39UaehfIndex]', [int]$uaehfIndex + 3)
    $winuaeSelfInstallHarddrivesConfigText = $winuaeSelfInstallHarddrivesConfigText.Replace('[$Cd0UaehfIndex]', [int]$uaehfIndex + 4)
    $winuaeSelfInstallHarddrivesConfigText = $winuaeSelfInstallHarddrivesConfigText.Trim()

    # return winuae image and self install harddrives config
    return $winuaeImageHarddrivesConfigText + "`r`n" + $winuaeSelfInstallHarddrivesConfigText
}


# build winuae run harddrives config text
function BuildWinuaeRunHarddrivesConfigText($hstwb)
{
    # build winuae image harddrives config
    $winuaeImageHarddrivesConfigText = BuildWinuaeImageHarddrivesConfigText $hstwb $false

    # get uaehf index of last uaehf config from winuae image harddrives config
    $uaehfIndex = 0
    $winuaeImageHarddrivesConfigText -split "`r`n" | ForEach-Object { $_ | Select-String -Pattern '^uaehf(\d+)=' -AllMatches | ForEach-Object { $_.Matches } | ForEach-Object { $uaehfIndex = $_.Groups[1].Value.Trim() } }

    $winuaeRunHarddrivesConfigFile = [System.IO.Path]::Combine($hstwb.Paths.WinuaePath, "harddrives_run.uae")

    # fail, if winuae run harddrives config file doesn't exist
    if (!(Test-Path -Path $winuaeRunHarddrivesConfigFile))
    {
        Fail $hstwb ("Error: Run harddrives config file '" + $winuaeRunHarddrivesConfigFile + "' doesn't exist!")
    }

    # read winuae run harddrives config file
    $winuaeRunHarddrivesConfigText = [System.IO.File]::ReadAllText($winuaeRunHarddrivesConfigFile)

    # replace winuae self install harddrives placeholders
    $winuaeRunHarddrivesConfigText = $winuaeRunHarddrivesConfigText.Replace('[$Cd0UaehfIndex]', [int]$uaehfIndex + 1)
    $winuaeRunHarddrivesConfigText = $winuaeRunHarddrivesConfigText.Trim()

    # return winuae image and self install harddrives config
    return $winuaeImageHarddrivesConfigText + "`r`n" + $winuaeRunHarddrivesConfigText
}


# run test
function RunTest($hstwb)
{
    # Build and set emulator config file
    # ----------------------------------
    $emulatorArgs = ''
    if ($hstwb.Settings.Emulator.EmulatorFile -match 'fs-uae\.exe$')
    {
        # build fs-uae harddrives config
        $fsUaeHarddrivesConfigText = BuildFsUaeHarddrivesConfigText $hstwb $false
        
        # read fs-uae hstwb installer config file
        $fsUaeHstwbInstallerConfigFile = [System.IO.Path]::Combine($hstwb.Paths.FsUaePath, "hstwb-installer.fs-uae")
        $fsUaeHstwbInstallerConfigText = [System.IO.File]::ReadAllText($fsUaeHstwbInstallerConfigFile)

        # replace hstwb installer fs-uae configuration placeholders
        $fsUaeHstwbInstallerConfigText = $fsUaeHstwbInstallerConfigText.Replace('[$KICKSTARTROMFILE]', $hstwb.Paths.KickstartRomFile.Replace('\', '/'))
        $fsUaeHstwbInstallerConfigText = $fsUaeHstwbInstallerConfigText.Replace('[$WORKBENCHADFFILE]', '')
        $fsUaeHstwbInstallerConfigText = $fsUaeHstwbInstallerConfigText.Replace('[$HARDDRIVES]', $fsUaeHarddrivesConfigText)
        $fsUaeHstwbInstallerConfigText = $fsUaeHstwbInstallerConfigText.Replace('[$ISOFILE]', '')
        $fsUaeHstwbInstallerConfigText = $fsUaeHstwbInstallerConfigText.Replace('[$ImageDir]', $hstwb.Settings.Image.ImageDir.Replace('\', '/'))
        
        # write fs-uae hstwb installer config file to temp dir
        $tempFsUaeHstwbInstallerConfigFile = [System.IO.Path]::Combine($hstwb.Paths.TempPath, "hstwb-installer.fs-uae")
        [System.IO.File]::WriteAllText($tempFsUaeHstwbInstallerConfigFile, $fsUaeHstwbInstallerConfigText)
    
        # emulator args for fs-uae
        $emulatorArgs = """$tempFsUaeHstwbInstallerConfigFile"""
    }
    elseif ($hstwb.Settings.Emulator.EmulatorFile -match '(winuae\.exe|winuae64\.exe)$')
    {
        # build winuae image harddrives config text
        $winuaeImageHarddrivesConfigText = BuildWinuaeImageHarddrivesConfigText $hstwb $false

        # read winuae hstwb installer config file
        $winuaeHstwbInstallerConfigFile = [System.IO.Path]::Combine($hstwb.Paths.WinuaePath, "hstwb-installer.uae")
        $winuaeHstwbInstallerConfigText = [System.IO.File]::ReadAllText($winuaeHstwbInstallerConfigFile)

        # replace winuae test config placeholders
        $winuaeHstwbInstallerConfigText = $winuaeHstwbInstallerConfigText.Replace('[$KICKSTARTROMFILE]', $hstwb.Paths.KickstartRomFile)
        $winuaeHstwbInstallerConfigText = $winuaeHstwbInstallerConfigText.Replace('[$WORKBENCHADFFILE]', '')
        $winuaeHstwbInstallerConfigText = $winuaeHstwbInstallerConfigText.Replace('[$HARDDRIVES]', $winuaeImageHarddrivesConfigText)
        $winuaeHstwbInstallerConfigText = $winuaeHstwbInstallerConfigText.Replace('[$ISOFILE]', '')
    
        # write winuae hstwb installer config file to temp dir
        $tempWinuaeHstwbInstallerConfigFile = [System.IO.Path]::Combine($hstwb.Paths.TempPath, "hstwb-installer.uae")
        [System.IO.File]::WriteAllText($tempWinuaeHstwbInstallerConfigFile, $winuaeHstwbInstallerConfigText)

        # emulator args for winuae
        $emulatorArgs = "-f ""$tempWinuaeHstwbInstallerConfigFile"""
    }
    else
    {
        Fail $hstwb ("Emulator file '{0}' is not supported" -f $hstwb.Settings.Emulator.EmulatorFile)
    }


    # print starting emulator message
    Write-Host ""
    Write-Host "Starting emulator to test image..."

    # fail, if emulator doesn't return error code 0
    $emulatorProcess = Start-Process $hstwb.Settings.Emulator.EmulatorFile $emulatorArgs -Wait -NoNewWindow
    if ($emulatorProcess -and $emulatorProcess.ExitCode -ne 0)
    {
        Fail $hstwb ("Failed to run '" + $hstwb.Settings.Emulator.EmulatorFile + "' with arguments '$emulatorArgs'")
    }
}


# run install
function RunInstall($hstwb)
{
    # print preparing install message
    Write-Host ""
    Write-Host "Preparing install..."


    # copy amiga install dir
    $amigaInstallDir = Join-Path $hstwb.Paths.AmigaPath -ChildPath "install"
    Copy-Item -Path $amigaInstallDir $hstwb.Paths.TempPath -recurse -force


    # set temp install and packages dir
    $tempInstallDir = Join-Path $hstwb.Paths.TempPath -ChildPath "install"
    $tempWorkbenchDir = Join-Path $tempInstallDir -ChildPath "Workbench"
    $tempKickstartDir = Join-Path $tempInstallDir -ChildPath "Kickstart"
    $tempPackagesDir = Join-Path $hstwb.Paths.TempPath -ChildPath "packages"

    # create temp workbench path
    if(!(test-path -path $tempWorkbenchDir))
    {
        mkdir $tempWorkbenchDir | Out-Null
    }

    # create temp kickstart path
    if(!(test-path -path $tempKickstartDir))
    {
        mkdir $tempKickstartDir | Out-Null
    }

    # create temp packages path
    if(!(test-path -path $tempPackagesDir))
    {
        mkdir $tempPackagesDir | Out-Null
    }


    # copy large harddisk to install directory
    $largeHarddiskDir = Join-Path $hstwb.Paths.AmigaPath -ChildPath "largeharddisk\Install-LargeHarddisk"
    Copy-Item -Path "$largeHarddiskDir\*" $tempInstallDir -recurse -force
    $largeHarddiskDir = Join-Path $hstwb.Paths.AmigaPath -ChildPath "largeharddisk"
    Copy-Item -Path "$largeHarddiskDir\*" $tempInstallDir -recurse -force

    # copy amiga shared dir
    $amigaSharedDir = [System.IO.Path]::Combine($hstwb.Paths.AmigaPath, "shared")
    Copy-Item -Path "$amigaSharedDir\*" $tempInstallDir -recurse -force

    # copy workbench to install directory
    $amigaWorkbenchDir = [System.IO.Path]::Combine($hstwb.Paths.AmigaPath, "workbench")
    Copy-Item -Path "$amigaWorkbenchDir\*" $tempInstallDir -recurse -force

    # copy kickstart to install directory
    $amigaKickstartDir = [System.IO.Path]::Combine($hstwb.Paths.AmigaPath, "kickstart")
    Copy-Item -Path "$amigaKickstartDir\*" $tempInstallDir -recurse -force

    # copy generic to install directory
    $amigaGenericDir = [System.IO.Path]::Combine($hstwb.Paths.AmigaPath, "generic")
    Copy-Item -Path "$amigaGenericDir\*" $tempInstallDir -recurse -force
    
    # copy amiga packages dir
    $amigaPackagesDir = [System.IO.Path]::Combine($hstwb.Paths.AmigaPath, "packages")
    Copy-Item -Path "$amigaPackagesDir\*" $tempPackagesDir -recurse -force


    # create prefs directory
    $prefsDir = [System.IO.Path]::Combine($tempInstallDir, "Prefs")
    if(!(test-path -path $prefsDir))
    {
        mkdir $prefsDir | Out-Null
    }


    # create uae prefs file
    $uaePrefsFile = Join-Path $prefsDir -ChildPath 'UAE'
    Set-Content $uaePrefsFile -Value ""


    # prepare install workbench
    if ($hstwb.Settings.Workbench.InstallWorkbench -eq 'Yes' -and $hstwb.WorkbenchAdfSetHashes.Count -gt 0)
    {
        # create install workbench prefs file
        $installWorkbenchFile = Join-Path $prefsDir -ChildPath 'Install-Workbench'
        Set-Content $installWorkbenchFile -Value ""
        

        # copy workbench adf set files to temp install dir
        Write-Host "Copying Workbench adf files to temp install dir"
        $hstwb.WorkbenchAdfSetHashes | Where-Object { $_.File } | ForEach-Object { [System.IO.File]::Copy($_.File, (Join-Path $tempWorkbenchDir -ChildPath $_.Filename), $true) }
    }


    # prepare install kickstart
    if ($hstwb.Settings.Kickstart.InstallKickstart -eq 'Yes' -and $hstwb.KickstartRomSetHashes.Count -gt 0)
    {
        # create install kickstart prefs file
        $installKickstartFile = Join-Path $prefsDir -ChildPath 'Install-Kickstart'
        Set-Content $installKickstartFile -Value ""
        

        # copy kickstart rom set files to temp install dir
        Write-Host "Copying Kickstart rom files to temp install dir"
        $hstwb.KickstartRomSetHashes | Where-Object { $_.File } | ForEach-Object { [System.IO.File]::Copy($_.File, (Join-Path $tempKickstartDir -ChildPath $_.Filename), $true) }


        # get first kickstart rom hash
        $installKickstartRomHash = $hstwb.KickstartRomSetHashes | Select-Object -First 1


        # kickstart rom key
        $installKickstartRomKeyFile = [System.IO.Path]::Combine([System.IO.Path]::GetDirectoryName($installKickstartRomHash.File), "rom.key")


        # copy kickstart rom key file to temp install dir, if kickstart roms are encrypted
        if ($installKickstartRomHash.Encrypted -eq 'Yes' -and (test-path -path $installKickstartRomKeyFile))
        {
            Copy-Item -Path $installKickstartRomKeyFile -Destination ([System.IO.Path]::Combine($tempKickstartDir, "rom.key"))
        }
    }


    # find packages to install
    $installPackages = FindPackagesToInstall $hstwb


    # build assign hstwb installers script lines
    $assignHstwbInstallerScriptLines = BuildAssignHstwbInstallerScriptLines $hstwb $true

    # write assign hstwb installer to install dir
    $userAssignFile = [System.IO.Path]::Combine($tempInstallDir, "S\Assign-HstWB-Installer")
    WriteAmigaTextLines $userAssignFile $assignHstwbInstallerScriptLines 


    $hstwbInstallerPackagesIni = @{}


    # extract packages and write install packages script, if there's packages to install
    if ($installPackages.Count -gt 0)
    {
        # create install packages prefs file
        $installPackagesFile = Join-Path $prefsDir -ChildPath 'Install-Packages'
        Set-Content $installPackagesFile -Value ""


        # extract packages to package directory
        foreach($installPackage in $installPackages)
        {
            # extract package file to package directory
            Write-Host ("Extracting '" + $installPackage.PackageFileName + "' package to temp install dir")
            $packageDir = [System.IO.Path]::Combine($tempPackagesDir, $installPackage.PackageFileName)

            if(!(test-path -path $packageDir))
            {
                mkdir $packageDir | Out-Null
            }

            [System.IO.Compression.ZipFile]::ExtractToDirectory($installPackage.PackageFile, $packageDir)

            $hstwbInstallerPackagesIni.Set_Item($installPackage.Package.Name, @{ 'Version' = $installPackage.Package.Version })
        }


        # build install package script lines
        $installPackagesScriptLines = @()
        $installPackagesScriptLines += "; Install Packages Script"
        $installPackagesScriptLines += "; -----------------------"
        $installPackagesScriptLines += "; Author: Henrik Noerfjand Stengaard"
        $installPackagesScriptLines += ("; Date: {0}" -f (Get-Date -format "yyyy.MM.dd"))
        $installPackagesScriptLines += ";"
        $installPackagesScriptLines += "; An install packages script generated by HstWB Installer to install configured packages."
        $installPackagesScriptLines += ""
        $installPackagesScriptLines += "; Clear screen"
        $installPackagesScriptLines += "echo ""*ec"""
        $installPackagesScriptLines += ""
        $installPackagesScriptLines += BuildInstallPackagesScriptLines $hstwb $installPackages
        $installPackagesScriptLines += "echo """""
        $installPackagesScriptLines += "echo ""Package installation is complete."""
        $installPackagesScriptLines += "echo """""
        $installPackagesScriptLines += "ask ""Press ENTER to continue"""


        # write install packages script
        $installPackagesFile = [System.IO.Path]::Combine($tempInstallDir, "S\Install-Packages")
        WriteAmigaTextLines $installPackagesFile $installPackagesScriptLines 
    }


    $installBoingBags = $false

    if ($hstwb.Settings.AmigaOS39.InstallAmigaOS39 -eq 'Yes' -and $hstwb.Settings.AmigaOS39.AmigaOS39IsoFile)
    {
        # create install amiga os 3.9 prefs file
        $installAmigaOs39File = Join-Path $prefsDir -ChildPath 'Install-AmigaOS3.9'
        Set-Content $installAmigaOs39File -Value ""


        # get amiga os 3.9 directory and filename
        $amigaOs39IsoDir = Split-Path $hstwb.Settings.AmigaOS39.AmigaOS39IsoFile -Parent
        $amigaOs39IsoFileName = Split-Path $hstwb.Settings.AmigaOS39.AmigaOS39IsoFile -Leaf


        $boingBag1File = Join-Path $amigaOs39IsoDir -ChildPath 'BoingBag39-1.lha'

        if ((Test-Path $boingBag1File) -and $hstwb.Settings.AmigaOS39.InstallBoingBags -eq 'Yes')
        {
            $installBoingBags = $true
            $installBoingBagsPrefsFile = Join-Path $prefsDir -ChildPath 'Install-BoingBags'
            Set-Content $installBoingBagsPrefsFile -Value ""
        }

        # copy amiga os 3.9 dir
        $amigaOs39Dir = [System.IO.Path]::Combine($hstwb.Paths.AmigaPath, "amigaos3.9")
        Copy-Item -Path "$amigaOs39Dir\*" $tempInstallDir -recurse -force


        $mountlistFile = Join-Path -Path $tempInstallDir -ChildPath "Devs\Mountlist"
        $mountlistText = [System.IO.File]::ReadAllText($mountlistFile)

        $mountlistText = $mountlistText.Replace('[$OS39IsoFileName]', $amigaOs39IsoFileName)
        $mountlistText = [System.IO.File]::WriteAllText($mountlistFile, $mountlistText)


        #
        $os39Dir = $amigaOs39IsoDir
        $isoFile = $hstwb.Settings.AmigaOS39.AmigaOS39IsoFile
    }
    else
    {
        $os39Dir = $tempInstallDir
        $isoFile = ''
    }


    # write hstwb installer packages ini file
    $hstwbInstallerPackagesIniFile = Join-Path $tempInstallDir -ChildPath 'HstWB-Installer.Packages.ini'
    WriteIniFile $hstwbInstallerPackagesIniFile $hstwbInstallerPackagesIni


    # build hstwb installer assigns ini
    $hstwbInstallerAssignsIni = @{}

    foreach ($assignSectionName in $hstwb.Assigns.keys)
    {
        $sectionAssigns = $hstwb.Assigns[$assignSectionName]

        foreach ($assignName in ($sectionAssigns.keys | Sort-Object | Where-Object { $_ -notlike 'HstWBInstallerDir' }))
        {
            if ($hstwbInstallerAssignsIni.ContainsKey($assignSectionName))
            {
                $hstwbInstallerAssignsSection = $hstwbInstallerAssignsIni.Get_Item($assignSectionName)
            }
            else
            {
                $hstwbInstallerAssignsSection = @{}
            }

            $hstwbInstallerAssignsSection.Set_Item($assignName, $sectionAssigns.Get_Item($assignName))
            $hstwbInstallerAssignsIni.Set_Item($assignSectionName, $hstwbInstallerAssignsSection)
        }
    }


    # write hstwb installer assigns ini file
    $hstwbInstallerAssignsIniFile = Join-Path $tempInstallDir -ChildPath 'HstWB-Installer.Assigns.ini'
    WriteIniFile $hstwbInstallerAssignsIniFile $hstwbInstallerAssignsIni

    # read winuae hstwb installer config file
    $winuaeHstwbInstallerConfigFile = [System.IO.Path]::Combine($hstwb.Paths.WinuaePath, "hstwb-installer.uae")
    $hstwbInstallerUaeWinuaeConfigText = [System.IO.File]::ReadAllText($winuaeHstwbInstallerConfigFile)

    # build winuae run harddrives config
    $winuaeRunHarddrivesConfigText = BuildWinuaeRunHarddrivesConfigText $hstwb

    # replace hstwb installer configuration placeholders
    $hstwbInstallerUaeWinuaeConfigText = $hstwbInstallerUaeWinuaeConfigText.Replace('use_gui=no', 'use_gui=yes')
    $hstwbInstallerUaeWinuaeConfigText = $hstwbInstallerUaeWinuaeConfigText.Replace('[$KICKSTARTROMFILE]', $hstwb.Paths.KickstartRomFile)
    $hstwbInstallerUaeWinuaeConfigText = $hstwbInstallerUaeWinuaeConfigText.Replace('[$WORKBENCHADFFILE]', '')
    $hstwbInstallerUaeWinuaeConfigText = $hstwbInstallerUaeWinuaeConfigText.Replace('[$HARDDRIVES]', $winuaeRunHarddrivesConfigText)
    $hstwbInstallerUaeWinuaeConfigText = $hstwbInstallerUaeWinuaeConfigText.Replace('[$ISOFILE]', '')

    # write hstwb installer configuration file to image dir
    $hstwbInstallerUaeConfigFile = Join-Path $hstwb.Settings.Image.ImageDir -ChildPath "hstwb-installer.uae"
    [System.IO.File]::WriteAllText($hstwbInstallerUaeConfigFile, $hstwbInstallerUaeWinuaeConfigText)
    
    # read fs-uae hstwb installer config file
    $fsUaeHstwbInstallerConfigFile = [System.IO.Path]::Combine($hstwb.Paths.FsUaePath, "hstwb-installer.fs-uae")
    $fsUaeHstwbInstallerConfigText = [System.IO.File]::ReadAllText($fsUaeHstwbInstallerConfigFile)

    # build fs-uae install harddrives config
    $hstwbInstallerFsUaeInstallHarddrivesConfigText = BuildFsUaeHarddrivesConfigText $hstwb
    
    # replace hstwb installer fs-uae configuration placeholders
    $fsUaeHstwbInstallerConfigText = $fsUaeHstwbInstallerConfigText.Replace('[$KICKSTARTROMFILE]', $hstwb.Paths.KickstartRomFile.Replace('\', '/'))
    $fsUaeHstwbInstallerConfigText = $fsUaeHstwbInstallerConfigText.Replace('[$WORKBENCHADFFILE]', '')
    $fsUaeHstwbInstallerConfigText = $fsUaeHstwbInstallerConfigText.Replace('[$HARDDRIVES]', $hstwbInstallerFsUaeInstallHarddrivesConfigText)
    $fsUaeHstwbInstallerConfigText = $fsUaeHstwbInstallerConfigText.Replace('[$ISOFILE]', '')
    $fsUaeHstwbInstallerConfigText = $fsUaeHstwbInstallerConfigText.Replace('[$ImageDir]', $hstwb.Settings.Image.ImageDir.Replace('\', '/'))
    
    # write hstwb installer fs-uae configuration file to image dir
    $hstwbInstallerFsUaeConfigFile = Join-Path $hstwb.Settings.Image.ImageDir -ChildPath "hstwb-installer.fs-uae"
    [System.IO.File]::WriteAllText($hstwbInstallerFsUaeConfigFile, $fsUaeHstwbInstallerConfigText)
    

    # copy install uae config to image dir
    $installUaeConfigDir = [System.IO.Path]::Combine($hstwb.Paths.ScriptsPath, "install_uae-config")
    Copy-Item -Path "$installUaeConfigDir\*" $hstwb.Settings.Image.ImageDir -recurse -force
    

    #
    $emulatorArgs = ''
    if ($hstwb.Settings.Emulator.EmulatorFile -match 'fs-uae\.exe$')
    {
        # build fs-uae install harddrives config
        $fsUaeInstallHarddrivesConfigText = BuildFsUaeInstallHarddrivesConfigText $hstwb $tempInstallDir $tempPackagesDir $os39Dir $true

        # read fs-uae hstwb installer config file
        $fsUaeHstwbInstallerConfigFile = [System.IO.Path]::Combine($hstwb.Paths.FsUaePath, "hstwb-installer.fs-uae")
        $fsUaeHstwbInstallerConfigText = [System.IO.File]::ReadAllText($fsUaeHstwbInstallerConfigFile)

        # replace hstwb installer fs-uae configuration placeholders
        $fsUaeHstwbInstallerConfigText = $fsUaeHstwbInstallerConfigText.Replace('[$KICKSTARTROMFILE]', $hstwb.Paths.KickstartRomFile.Replace('\', '/'))
        $fsUaeHstwbInstallerConfigText = $fsUaeHstwbInstallerConfigText.Replace('[$WORKBENCHADFFILE]', $hstwb.Paths.WorkbenchAdfFile.Replace('\', '/'))
        $fsUaeHstwbInstallerConfigText = $fsUaeHstwbInstallerConfigText.Replace('[$HARDDRIVES]', $fsUaeInstallHarddrivesConfigText)
        $fsUaeHstwbInstallerConfigText = $fsUaeHstwbInstallerConfigText.Replace('[$ISOFILE]', $isoFile.Replace('\', '/'))
        $fsUaeHstwbInstallerConfigText = $fsUaeHstwbInstallerConfigText.Replace('[$ImageDir]', $hstwb.Settings.Image.ImageDir.Replace('\', '/'))
        
        # write fs-uae hstwb installer config file to temp dir
        $tempFsUaeHstwbInstallerConfigFile = [System.IO.Path]::Combine($hstwb.Paths.TempPath, "hstwb-installer.fs-uae")
        [System.IO.File]::WriteAllText($tempFsUaeHstwbInstallerConfigFile, $fsUaeHstwbInstallerConfigText)
    
        # emulator args for fs-uae
        $emulatorArgs = """$tempFsUaeHstwbInstallerConfigFile"""
    }
    elseif ($hstwb.Settings.Emulator.EmulatorFile -match '(winuae\.exe|winuae64\.exe)$')
    {
        # build winuae install harddrives config
        $winuaeInstallHarddrivesConfigText = BuildWinuaeInstallHarddrivesConfigText $hstwb $tempInstallDir $tempPackagesDir $os39Dir $true
    
        # read winuae hstwb installer config file
        $winuaeHstwbInstallerConfigFile = [System.IO.Path]::Combine($hstwb.Paths.WinuaePath, "hstwb-installer.uae")
        $winuaeHstwbInstallerConfigText = [System.IO.File]::ReadAllText($winuaeHstwbInstallerConfigFile)
    
        # replace winuae hstwb installer config placeholders
        $winuaeHstwbInstallerConfigText = $winuaeHstwbInstallerConfigText.Replace('[$KICKSTARTROMFILE]', $hstwb.Paths.KickstartRomFile)
        $winuaeHstwbInstallerConfigText = $winuaeHstwbInstallerConfigText.Replace('[$WORKBENCHADFFILE]', $hstwb.Paths.WorkbenchAdfFile)
        $winuaeHstwbInstallerConfigText = $winuaeHstwbInstallerConfigText.Replace('[$HARDDRIVES]', $winuaeInstallHarddrivesConfigText)
        $winuaeHstwbInstallerConfigText = $winuaeHstwbInstallerConfigText.Replace('[$ISOFILE]', $isoFile)
    
        # write winuae hstwb installer config file to temp install dir
        $tempWinuaeHstwbInstallerConfigFile = [System.IO.Path]::Combine($hstwb.Paths.TempPath, "hstwb-installer.uae")
        [System.IO.File]::WriteAllText($tempWinuaeHstwbInstallerConfigFile, $winuaeHstwbInstallerConfigText)

        # emulator args for winuae
        $emulatorArgs = "-f ""$tempWinuaeHstwbInstallerConfigFile"""
    }
    else
    {
        Fail $hstwb ("Emulator file '{0}' is not supported" -f $hstwb.Settings.Emulator.EmulatorFile)
    }

    # print preparing installation done message
    Write-Host "Done."
    

    # print start emulator message
    Write-Host ""
    Write-Host "Starting emulator to run install..."
    
    # fail, if emulator doesn't return error code 0
    $emulatorProcess = Start-Process $hstwb.Settings.Emulator.EmulatorFile $emulatorArgs -Wait -NoNewWindow
    if ($emulatorProcess -and $emulatorProcess.ExitCode -ne 0)
    {
        Fail $hstwb ("Failed to run '" + $hstwb.Settings.Emulator.EmulatorFile + "' with arguments '$emulatorArgs'")
    }


    # fail, if install complete prefs file doesn't exists
    $installCompletePrefsFile = Join-Path $prefsDir -ChildPath 'Install-Complete'
    if (!(Test-Path -path $installCompletePrefsFile))
    {
        Fail $hstwb "Installation failed"
    }

    
    if (!$installBoingBags)
    {
        return
    }


    #
    $emulatorArgs = ''
    if ($hstwb.Settings.Emulator.EmulatorFile -match 'fs-uae\.exe$')
    {
        # build fs-uae install harddrives config
        $fsUaeInstallHarddrivesConfigText = BuildFsUaeInstallHarddrivesConfigText $hstwb $tempInstallDir $tempPackagesDir $os39Dir $false
        
        # read fs-uae hstwb installer config file
        $fsUaeHstwbInstallerConfigFile = [System.IO.Path]::Combine($hstwb.Paths.FsUaePath, "hstwb-installer.fs-uae")
        $fsUaeHstwbInstallerConfigText = [System.IO.File]::ReadAllText($fsUaeHstwbInstallerConfigFile)

        # replace hstwb installer fs-uae configuration placeholders
        $fsUaeHstwbInstallerConfigText = $fsUaeHstwbInstallerConfigText.Replace('[$KICKSTARTROMFILE]', $hstwb.Paths.KickstartRomFile.Replace('\', '/'))
        $fsUaeHstwbInstallerConfigText = $fsUaeHstwbInstallerConfigText.Replace('[$WORKBENCHADFFILE]', '')
        $fsUaeHstwbInstallerConfigText = $fsUaeHstwbInstallerConfigText.Replace('[$HARDDRIVES]', $fsUaeInstallHarddrivesConfigText)
        $fsUaeHstwbInstallerConfigText = $fsUaeHstwbInstallerConfigText.Replace('[$ISOFILE]', $isoFile.Replace('\', '/'))
        $fsUaeHstwbInstallerConfigText = $fsUaeHstwbInstallerConfigText.Replace('[$ImageDir]', $hstwb.Settings.Image.ImageDir.Replace('\', '/'))
        
        # write fs-uae hstwb installer config file to temp dir
        $tempFsUaeHstwbInstallerConfigFile = [System.IO.Path]::Combine($hstwb.Paths.TempPath, "hstwb-installer.fs-uae")
        [System.IO.File]::WriteAllText($tempFsUaeHstwbInstallerConfigFile, $fsUaeHstwbInstallerConfigText)
    
        # emulator args for fs-uae
        $emulatorArgs = """$tempFsUaeHstwbInstallerConfigFile"""
    }
    elseif ($hstwb.Settings.Emulator.EmulatorFile -match '(winuae\.exe|winuae64\.exe)$')
    {
        # build winuae install harddrives config with boot
        $winuaeInstallHarddrivesConfigText = BuildWinuaeInstallHarddrivesConfigText $hstwb $tempInstallDir $tempPackagesDir $os39Dir $false
        
        # read winuae hstwb installer config file
        $winuaeHstwbInstallerConfigFile = [System.IO.Path]::Combine($hstwb.Paths.WinuaePath, "hstwb-installer.uae")
        $winuaeHstwbInstallerConfigText = [System.IO.File]::ReadAllText($winuaeHstwbInstallerConfigFile)

        # replace winuae hstwb installer config placeholders
        $winuaeHstwbInstallerConfigText = $winuaeHstwbInstallerConfigText.Replace('[$KICKSTARTROMFILE]', $hstwb.Paths.KickstartRomFile)
        $winuaeHstwbInstallerConfigText = $winuaeHstwbInstallerConfigText.Replace('[$WORKBENCHADFFILE]', '')
        $winuaeHstwbInstallerConfigText = $winuaeHstwbInstallerConfigText.Replace('[$HARDDRIVES]', $winuaeInstallHarddrivesConfigText)
        $winuaeHstwbInstallerConfigText = $winuaeHstwbInstallerConfigText.Replace('[$ISOFILE]', $isoFile)

        # write winuae hstwb installer config file to temp dir
        $tempWinuaeHstwbInstallerConfigFile = [System.IO.Path]::Combine($hstwb.Paths.TempPath, "hstwb-installer.uae")
        [System.IO.File]::WriteAllText($tempWinuaeHstwbInstallerConfigFile, $winuaeHstwbInstallerConfigText)

        # emulator args for winuae
        $emulatorArgs = "-f ""$tempWinuaeHstwbInstallerConfigFile"""
    }
    else
    {
        Fail $hstwb ("Emulator file '{0}' is not supported" -f $hstwb.Settings.Emulator.EmulatorFile)
    }
        
    
    # print start emulator message
    Write-Host ""
    Write-Host "Starting emulator to run install boing bags..."

    # fail, if emulator doesn't return error code 0
    $emulatorProcess = Start-Process $hstwb.Settings.Emulator.EmulatorFile $emulatorArgs -Wait -NoNewWindow
    if ($emulatorProcess -and $emulatorProcess.ExitCode -ne 0)
    {
        Fail $hstwb ("Failed to run '" + $hstwb.Settings.Emulator.EmulatorFile + "' with arguments '$emulatorArgs'")
    }
}


# run build self install
function RunBuildSelfInstall($hstwb)
{
    # print preparing self install message
    Write-Host ""
    Write-Host "Preparing build self install..."    


    # create temp install path
    $tempInstallDir = [System.IO.Path]::Combine($hstwb.Paths.TempPath, "install")
    if(!(test-path -path $tempInstallDir))
    {
        mkdir $tempInstallDir | Out-Null
    }

    # create temp licenses path
    $tempLicensesDir = Join-Path $tempInstallDir -ChildPath "Licenses"
    if(!(test-path -path $tempLicensesDir))
    {
        mkdir $tempLicensesDir | Out-Null
    }

    # create temp packages path
    $tempPackagesDir = [System.IO.Path]::Combine($hstwb.Paths.TempPath, "packages")
    if(!(test-path -path $tempPackagesDir))
    {
        mkdir $tempPackagesDir | Out-Null
    }


    # create install prefs directory
    $prefsDir = [System.IO.Path]::Combine($tempInstallDir, "Prefs")
    if(!(test-path -path $prefsDir))
    {
        mkdir $prefsDir | Out-Null
    }


    # copy licenses dir
    Copy-Item -Path "$licensesPath\*" $tempLicensesDir -recurse -force
    
    # copy self install to install directory
    $amigaSelfInstallBuildDir = [System.IO.Path]::Combine($hstwb.Paths.AmigaPath, "selfinstall")
    Copy-Item -Path "$amigaSelfInstallBuildDir\*" $tempInstallDir -recurse -force

    # copy generic to install directory
    $amigaGenericDir = [System.IO.Path]::Combine($hstwb.Paths.AmigaPath, "generic")
    Copy-Item -Path "$amigaGenericDir\*" "$tempInstallDir\Install-SelfInstall" -recurse -force
    
    # copy large harddisk
    $installLargeHarddiskDir = Join-Path $hstwb.Paths.AmigaPath -ChildPath "largeharddisk\Install-LargeHarddisk"
    Copy-Item -Path "$installLargeHarddiskDir\*" $tempInstallDir -recurse -force
    Copy-Item -Path "$installLargeHarddiskDir\*" "$tempInstallDir\Boot-SelfInstall" -recurse -force
    $largeHarddiskDir = Join-Path $hstwb.Paths.AmigaPath -ChildPath "largeharddisk"
    Copy-Item -Path "$largeHarddiskDir\*" "$tempInstallDir\Install-SelfInstall" -recurse -force

    # copy large harddisk to self install directory
    $selfInstallLargeHarddiskDir = Join-Path "$tempInstallDir\Install-SelfInstall" -ChildPath "Large-Harddisk"
    if(!(test-path -path $selfInstallLargeHarddiskDir))
    {
        mkdir $selfInstallLargeHarddiskDir | Out-Null
    }
    Copy-Item -Path "$largeHarddiskDir\*" $selfInstallLargeHarddiskDir -recurse -force

    # copy shared to install directory
    $sharedDir = [System.IO.Path]::Combine($hstwb.Paths.AmigaPath, "shared")
    Copy-Item -Path "$sharedDir\*" $tempInstallDir -recurse -force
    Copy-Item -Path "$sharedDir\*" "$tempInstallDir\Install-SelfInstall" -recurse -force
    
    # copy amiga os 3.9 to install directory
    $amigaOs39Dir = [System.IO.Path]::Combine($hstwb.Paths.AmigaPath, "amigaos3.9")
    Copy-Item -Path "$amigaOs39Dir\*" $tempInstallDir -recurse -force

    # copy workbench to install directory
    $amigaWorkbenchDir = [System.IO.Path]::Combine($hstwb.Paths.AmigaPath, "workbench")
    Copy-Item -Path "$amigaWorkbenchDir\*" "$tempInstallDir\Install-SelfInstall" -recurse -force

    # copy kickstart to install directory
    $amigaKickstartDir = [System.IO.Path]::Combine($hstwb.Paths.AmigaPath, "kickstart")
    Copy-Item -Path "$amigaKickstartDir\*" "$tempInstallDir\Install-SelfInstall" -recurse -force
    
    # copy amiga packages dir
    $amigaPackagesDir = [System.IO.Path]::Combine($hstwb.Paths.AmigaPath, "packages")
    Copy-Item -Path "$amigaPackagesDir\*" $tempPackagesDir -recurse -force
  

    # create self install prefs file
    $uaePrefsFile = Join-Path $prefsDir -ChildPath 'Self-Install'
    Set-Content $uaePrefsFile -Value ""


    # build assign hstwb installers script lines
    $assignHstwbInstallerScriptLines = @()
    $assignHstwbInstallerScriptLines += BuildAssignHstwbInstallerScriptLines $hstwb $true


    # write assign hstwb installer script for building self install
    $userAssignFile = [System.IO.Path]::Combine($tempInstallDir, "S\Assign-HstWB-Installer")
    WriteAmigaTextLines $userAssignFile $assignHstwbInstallerScriptLines


    # write assign hstwb installer script for self install
    $assignHstwbInstallerScriptLines +="Assign INSTALLDIR: ""HstWBInstallerDir:Install"""
    $assignHstwbInstallerScriptLines +="Assign PACKAGESDIR: ""HstWBInstallerDir:Packages"""
    $userAssignFile = [System.IO.Path]::Combine($tempInstallDir, "Boot-SelfInstall\S\Assign-HstWB-Installer")
    WriteAmigaTextLines $userAssignFile $assignHstwbInstallerScriptLines


    # find packages to install
    $installPackages = FindPackagesToInstall $hstwb


    # extract packages and write install packages script, if there's packages to install
    if ($installPackages.Count -gt 0)
    {
        # create install packages prefs file
        $installPackagesFile = Join-Path $prefsDir -ChildPath 'Install-Packages'
        Set-Content $installPackagesFile -Value ""


        # extract packages to package directory
        foreach($installPackage in $installPackages)
        {
            # extract package file to package directory
            Write-Host ("Extracting '" + $installPackage.PackageFileName + "' package to temp install dir")
            $packageDir = [System.IO.Path]::Combine($tempPackagesDir, $installPackage.PackageFileName)

            if(!(test-path -path $packageDir))
            {
                mkdir $packageDir | Out-Null
            }

            [System.IO.Compression.ZipFile]::ExtractToDirectory($installPackage.PackageFile, $packageDir)
        }
    }


    # build install package script lines
    $installPackagesScriptLines = @()
    $installPackagesScriptLines += "; Install Packages Script"
    $installPackagesScriptLines += "; -----------------------"
    $installPackagesScriptLines += "; Author: Henrik Noerfjand Stengaard"
    $installPackagesScriptLines += ("; Date: {0}" -f (Get-Date -format "yyyy.MM.dd"))
    $installPackagesScriptLines += ";"
    $installPackagesScriptLines += "; An install packages script generated by HstWB Installer to install configured packages."
    $installPackagesScriptLines += BuildInstallPackagesScriptLines $hstwb $installPackages
    $installPackagesScriptLines += "echo """""
    $installPackagesScriptLines += "echo ""Package installation is complete."""
    $installPackagesScriptLines += "echo """""
    $installPackagesScriptLines += "ask ""Press ENTER to continue"""


    # write install packages script
    $installPackagesScriptFile = [System.IO.Path]::Combine($tempInstallDir, "Install-SelfInstall\S\Install-Packages")
    WriteAmigaTextLines $installPackagesScriptFile $installPackagesScriptLines 


    $globalAssigns = $hstwb.Assigns.Get_Item('Global')

    if (!$globalAssigns)
    {
        Fail $hstwb ("Failed to run install. Global assigns doesn't exist!")
    }

    $removeHstwbInstallerScriptLines = @()
    $removeHstwbInstallerScriptLines += "; Remove INSTALLDIR: assign"
    $removeHstwbInstallerScriptLines += "Assign INSTALLDIR: ""HstWBInstallerDir:Install"" REMOVE"
    $removeHstwbInstallerScriptLines += "; Remove PACKAGESDIR: assign"
    $removeHstwbInstallerScriptLines += "Assign PACKAGESDIR: ""HstWBInstallerDir:Packages"" REMOVE"

    foreach ($assignName in $globalAssigns.keys)
    {
        # get assign path and drive
        $assignPath = $globalAssigns.Get_Item($assignName)
        
        $removeHstwbInstallerScriptLines += ("; Remove {0}: assign, if it exists" -f $assignName)
        $removeHstwbInstallerScriptLines += ("Assign >NIL: EXISTS ""{0}:""" -f $assignName)
        $removeHstwbInstallerScriptLines += "IF NOT WARN"
        $removeHstwbInstallerScriptLines += ("  Assign >NIL: {0}: ""{1}"" REMOVE" -f $assignName, $assignPath)
        $removeHstwbInstallerScriptLines += "ENDIF"
    }
    
    $hstwbInstallDirAssignName = $globalAssigns.keys | Where-Object { $_ -match 'HstWBInstallerDir' } | Select-Object -First 1

    if (!$hstwbInstallDirAssignName)
    {
        Fail $hstwb ("Failed to run install. Global assigns doesn't containassign for 'HstWBInstallerDir' exist!")
    }

    $hstwbInstallDir = $globalAssigns.Get_Item($hstwbInstallDirAssignName)

    $removeHstwbInstallerScriptLines += "; Delete hstwb installer dir, if it exists"
    $removeHstwbInstallerScriptLines += "IF EXISTS ""$hstwbInstallDir"""
    $removeHstwbInstallerScriptLines += "  Delete >NIL: ""$hstwbInstallDir"" ALL"
    $removeHstwbInstallerScriptLines += "ENDIF"

    
    # write remove hstwb installer script
    $removeHstwbInstallerScriptFile = [System.IO.Path]::Combine($tempInstallDir, "Install-SelfInstall\S\Remove-HstWBInstaller")
    WriteAmigaTextLines $removeHstwbInstallerScriptFile $removeHstwbInstallerScriptLines 


    # copy prefs to install self install
    $selfInstallDir = Join-Path $tempInstallDir -ChildPath "Install-SelfInstall"
    Copy-Item -Path $prefsDir $selfInstallDir -recurse -force




    # hstwb uae run workbench dir
    $workbenchDir = ''
    if ($hstwb.Settings.Workbench.WorkbenchAdfPath -and (Test-Path -Path $hstwb.Settings.Workbench.WorkbenchAdfPath))
    {
        $workbenchDir = $hstwb.Settings.Workbench.WorkbenchAdfPath
    }
    
    # hstwb uae kickstart dir
    $kickstartDir = ''
    if ($hstwb.Settings.Kickstart.KickstartRomPath -and (Test-Path -Path $hstwb.Settings.Kickstart.KickstartRomPath))
    {
        $kickstartDir = $hstwb.Settings.Kickstart.KickstartRomPath
    }



    # read winuae hstwb installer config file
    $winuaeHstwbInstallerConfigFile = [System.IO.Path]::Combine($hstwb.Paths.WinuaePath, "hstwb-installer.uae")
    $hstwbInstallerUaeWinuaeConfigText = [System.IO.File]::ReadAllText($winuaeHstwbInstallerConfigFile)

    # build winuae self install harddrives config
    $hstwbInstallerWinuaeSelfInstallHarddrivesConfigText = BuildWinuaeSelfInstallHarddrivesConfigText $hstwb $workbenchDir $kickstartDir ''


    # replace hstwb installer uae winuae configuration placeholders
    $hstwbInstallerUaeWinuaeConfigText = $hstwbInstallerUaeWinuaeConfigText.Replace('use_gui=no', 'use_gui=yes')
    $hstwbInstallerUaeWinuaeConfigText = $hstwbInstallerUaeWinuaeConfigText.Replace('[$KICKSTARTROMFILE]', $hstwb.Paths.KickstartRomFile)
    $hstwbInstallerUaeWinuaeConfigText = $hstwbInstallerUaeWinuaeConfigText.Replace('[$WORKBENCHADFFILE]', '')
    $hstwbInstallerUaeWinuaeConfigText = $hstwbInstallerUaeWinuaeConfigText.Replace('[$HARDDRIVES]', $hstwbInstallerWinuaeSelfInstallHarddrivesConfigText)
    $hstwbInstallerUaeWinuaeConfigText = $hstwbInstallerUaeWinuaeConfigText.Replace('[$ISOFILE]', '')
    
    # write hstwb installer uae winuae configuration file to image dir
    $hstwbInstallerUaeConfigFile = Join-Path $hstwb.Settings.Image.ImageDir -ChildPath "hstwb-installer.uae"
    [System.IO.File]::WriteAllText($hstwbInstallerUaeConfigFile, $hstwbInstallerUaeWinuaeConfigText)


    # read fs-uae hstwb installer config file
    $fsUaeHstwbInstallerConfigFile = [System.IO.Path]::Combine($hstwb.Paths.FsUaePath, "hstwb-installer.fs-uae")
    $fsUaeHstwbInstallerConfigText = [System.IO.File]::ReadAllText($fsUaeHstwbInstallerConfigFile)

    # build fs-uae self install harddrives config
    $hstwbInstallerFsUaeSelfInstallHarddrivesConfigText = BuildFsUaeSelfInstallHarddrivesConfigText $hstwb $workbenchDir $kickstartDir $hstwb.Settings.Image.ImageDir
    
    # replace hstwb installer fs-uae configuration placeholders
    $fsUaeHstwbInstallerConfigText = $fsUaeHstwbInstallerConfigText.Replace('[$KICKSTARTROMFILE]', $hstwb.Paths.KickstartRomFile.Replace('\', '/'))
    $fsUaeHstwbInstallerConfigText = $fsUaeHstwbInstallerConfigText.Replace('[$WORKBENCHADFFILE]', '')
    $fsUaeHstwbInstallerConfigText = $fsUaeHstwbInstallerConfigText.Replace('[$HARDDRIVES]', $hstwbInstallerFsUaeSelfInstallHarddrivesConfigText)
    $fsUaeHstwbInstallerConfigText = $fsUaeHstwbInstallerConfigText.Replace('[$ISOFILE]', '')
    $fsUaeHstwbInstallerConfigText = $fsUaeHstwbInstallerConfigText.Replace('[$ImageDir]', $hstwb.Settings.Image.ImageDir.Replace('\', '/'))
    
    # write hstwb installer fs-uae configuration file to image dir
    $hstwbInstallerFsUaeConfigFile = Join-Path $hstwb.Settings.Image.ImageDir -ChildPath "hstwb-installer.fs-uae"
    [System.IO.File]::WriteAllText($hstwbInstallerFsUaeConfigFile, $fsUaeHstwbInstallerConfigText)
    

    # copy install uae config to image dir
    $installUaeConfigDir = [System.IO.Path]::Combine($hstwb.Paths.ScriptsPath, "install_uae-config")
    Copy-Item -Path "$installUaeConfigDir\*" $hstwb.Settings.Image.ImageDir -recurse -force


    #
    $emulatorArgs = ''
    if ($hstwb.Settings.Emulator.EmulatorFile -match 'fs-uae\.exe$')
    {
        # build fs-uae install harddrives config
        $fsUaeInstallHarddrivesConfigText = BuildFsUaeInstallHarddrivesConfigText $hstwb $tempInstallDir $tempPackagesDir $tempInstallDir $true

        # read fs-uae hstwb installer config file
        $fsUaeHstwbInstallerConfigFile = [System.IO.Path]::Combine($hstwb.Paths.FsUaePath, "hstwb-installer.fs-uae")
        $fsUaeHstwbInstallerConfigText = [System.IO.File]::ReadAllText($fsUaeHstwbInstallerConfigFile)

        # replace hstwb installer fs-uae configuration placeholders
        $fsUaeHstwbInstallerConfigText = $fsUaeHstwbInstallerConfigText.Replace('[$KICKSTARTROMFILE]', $hstwb.Paths.KickstartRomFile.Replace('\', '/'))
        $fsUaeHstwbInstallerConfigText = $fsUaeHstwbInstallerConfigText.Replace('[$WORKBENCHADFFILE]', $hstwb.Paths.WorkbenchAdfFile.Replace('\', '/'))
        $fsUaeHstwbInstallerConfigText = $fsUaeHstwbInstallerConfigText.Replace('[$HARDDRIVES]', $fsUaeInstallHarddrivesConfigText)
        $fsUaeHstwbInstallerConfigText = $fsUaeHstwbInstallerConfigText.Replace('[$ISOFILE]', '')
        $fsUaeHstwbInstallerConfigText = $fsUaeHstwbInstallerConfigText.Replace('[$ImageDir]', $hstwb.Settings.Image.ImageDir.Replace('\', '/'))
        
        # write fs-uae hstwb installer config file to temp dir
        $tempFsUaeHstwbInstallerConfigFile = [System.IO.Path]::Combine($hstwb.Paths.TempPath, "hstwb-installer.fs-uae")
        [System.IO.File]::WriteAllText($tempFsUaeHstwbInstallerConfigFile, $fsUaeHstwbInstallerConfigText)
    
        # emulator args for fs-uae
        $emulatorArgs = """$tempFsUaeHstwbInstallerConfigFile"""
    }
    elseif ($hstwb.Settings.Emulator.EmulatorFile -match '(winuae\.exe|winuae64\.exe)$')
    {
        # build winuae install harddrives config
        $winuaeInstallHarddrivesConfigText = BuildWinuaeInstallHarddrivesConfigText $hstwb $tempInstallDir $tempPackagesDir $tempInstallDir $true
    
        # read winuae hstwb installer config file
        $winuaeHstwbInstallerConfigFile = [System.IO.Path]::Combine($hstwb.Paths.WinuaePath, "hstwb-installer.uae")
        $winuaeHstwbInstallerConfigText = [System.IO.File]::ReadAllText($winuaeHstwbInstallerConfigFile)
    
        # replace winuae hstwb installer config placeholders
        $winuaeHstwbInstallerConfigText = $winuaeHstwbInstallerConfigText.Replace('[$KICKSTARTROMFILE]', $hstwb.Paths.KickstartRomFile)
        $winuaeHstwbInstallerConfigText = $winuaeHstwbInstallerConfigText.Replace('[$WORKBENCHADFFILE]', $hstwb.Paths.WorkbenchAdfFile)
        $winuaeHstwbInstallerConfigText = $winuaeHstwbInstallerConfigText.Replace('[$HARDDRIVES]', $winuaeInstallHarddrivesConfigText)
        $winuaeHstwbInstallerConfigText = $winuaeHstwbInstallerConfigText.Replace('[$ISOFILE]', '')
        
        # write winuae hstwb installer config file to temp install dir
        $tempWinuaeHstwbInstallerConfigFile = [System.IO.Path]::Combine($hstwb.Paths.TempPath, "hstwb-installer.uae")
        [System.IO.File]::WriteAllText($tempWinuaeHstwbInstallerConfigFile, $winuaeHstwbInstallerConfigText)
    
        # emulator args for winuae
        $emulatorArgs = "-f ""$tempWinuaeHstwbInstallerConfigFile"""
    }
    else
    {
        Fail $hstwb ("Emulator file '{0}' is not supported" -f $hstwb.Settings.Emulator.EmulatorFile)
    }

    # print preparing installation done message
    Write-Host "Done."
        

    # print starting emulator message
    Write-Host ""
    Write-Host "Starting emulator to build self install image..."


    # fail, if emulator doesn't return error code 0
    $emulatorProcess = Start-Process $hstwb.Settings.Emulator.EmulatorFile $emulatorArgs -Wait -NoNewWindow
    if ($emulatorProcess -and $emulatorProcess.ExitCode -ne 0)
    {
        Fail $hstwb ("Failed to run '" + $hstwb.Settings.Emulator.EmulatorFile + "' with arguments '$emulatorArgs'")
    }


    # fail, if install complete prefs file doesn't exists
    $installCompletePrefsFile = Join-Path $prefsDir -ChildPath 'Install-Complete'
    if (!(Test-Path -path $installCompletePrefsFile))
    {
        Fail $hstwb "WinUAE installation failed"
    }
}

# run build package installation
function RunBuildPackageInstallation($hstwb)
{
    $outputPackageInstallationPath = FolderBrowserDialog "Select new directory for package installation" ${Env:USERPROFILE} $true

    # return, if package installation directory is null
    if ($outputPackageInstallationPath -eq $null)
    {
        Write-Host ""
        Write-Host "Cancelled, no package installation directory selected!" -ForegroundColor Yellow
        return
    }

    # show confirm overwrite dialog, if package installation directory is not empty
    if ((Get-ChildItem -Path $outputPackageInstallationPath -Recurse).Count -gt 0)
    {
        if (!(ConfirmDialog "Overwrite files" ("Package installation directory '" + $outputPackageInstallationPath + "' is not empty.`r`n`r`nDo you want to overwrite files?")))
        {
            Write-Host ""
            Write-Host "Cancelled, package installation directory is not empty!" -ForegroundColor Yellow
            return
        }
    }

    # delete package installation directory, if it exists
    if (Test-Path $outputPackageInstallationPath)
    {
        Remove-Item -Path $outputPackageInstallationPath -Recurse -Force
    }

    # create package installation directory
    mkdir $outputPackageInstallationPath | Out-Null

    # print building package installation message
    Write-Host ""
    Write-Host "Building package installation to '$outputPackageInstallationPath'..."    


    # find packages to install
    $installPackages = FindPackagesToInstall $hstwb | Sort-Object -Property 'Name'


    # extract packages and write install packages script, if there's packages to install
    if ($installPackages.Count -gt 0)
    {
        foreach($installPackage in $installPackages)
        {
            # extract package file to package directory
            Write-Host ("Extracting '" + $installPackage.PackageFileName + "' package to package installation")
            $packageDir = [System.IO.Path]::Combine($outputPackageInstallationPath, $installPackage.PackageFileName)

            if(!(test-path -path $packageDir))
            {
                mkdir $packageDir | Out-Null
            }

            [System.IO.Compression.ZipFile]::ExtractToDirectory($installPackage.PackageFile, $packageDir)
        }
    }


    # build install package script lines
    $packageInstallationScriptLines = @()
    $packageInstallationScriptLines += "; Package Installation Script"
    $packageInstallationScriptLines += "; ---------------------------"
    $packageInstallationScriptLines += "; Author: Henrik Noerfjand Stengaard"
    $packageInstallationScriptLines += ("; Date: {0}" -f (Get-Date -format "yyyy.MM.dd"))
    $packageInstallationScriptLines += ";"
    $packageInstallationScriptLines += "; An package installation script generated by HstWB Installer to install selected packages."
    $packageInstallationScriptLines += ""
    $packageInstallationScriptLines += "; Add assigns and set environment variables for package installation"
    $packageInstallationScriptLines += "SetEnv Packages ""``CD``"""
    $packageInstallationScriptLines += "Assign PACKAGESDIR: ""`$Packages"""
    $packageInstallationScriptLines += 'Assign SYSTEMDIR: SYS:'
    $packageInstallationScriptLines += "SetEnv TZ MST7"
    $packageInstallationScriptLines += ""
    $packageInstallationScriptLines += "; Copy reqtools prefs to env, if it doesn't exist"
    $packageInstallationScriptLines += "IF NOT EXISTS ""ENV:ReqTools.prefs"""
    $packageInstallationScriptLines += "  copy >NIL: ""ReqTools.prefs"" ""ENV:"""
    $packageInstallationScriptLines += "ENDIF"
    $packageInstallationScriptLines += ""
    $packageInstallationScriptLines += BuildInstallPackagesScriptLines $hstwb $installPackages
    $packageInstallationScriptLines += ""
    $packageInstallationScriptLines += "; Remove assigns for package installation"
    $packageInstallationScriptLines += "Assign PACKAGESDIR: ""`$Packages"" REMOVE"
    $packageInstallationScriptLines += "Assign >NIL: EXISTS ""SYSTEMDIR:"""
    $packageInstallationScriptLines += "IF NOT WARN"
    $packageInstallationScriptLines += "  Assign SYSTEMDIR: SYS: REMOVE"
    $packageInstallationScriptLines += "ENDIF"
    $packageInstallationScriptLines += ""
    $packageInstallationScriptLines += "echo """""
    $packageInstallationScriptLines += "echo ""Package installation is complete."""
    $packageInstallationScriptLines += "echo """""
    $packageInstallationScriptLines += "ask ""Press ENTER to continue"""


    # write install packages script
    $installPackagesScriptFile = [System.IO.Path]::Combine($outputPackageInstallationPath, "Package Installation")
    WriteAmigaTextLines $installPackagesScriptFile $packageInstallationScriptLines 


    # copy amiga package installation files
    $amigaPackageInstallationDir = [System.IO.Path]::Combine($hstwb.Paths.AmigaPath, "packageinstallation")
    Copy-Item -Path "$amigaPackageInstallationDir\*" $outputPackageInstallationPath -recurse -force


    # copy amiga packages dir
    $amigaPackagesDir = [System.IO.Path]::Combine($hstwb.Paths.AmigaPath, "packages")
    Copy-Item -Path "$amigaPackagesDir\*" $outputPackageInstallationPath -recurse -force

    read-host
}


# fail
function Fail($hstwb, $message)
{
    if(test-path -path $hstwb.Paths.TempPath)
    {
        Remove-Item -Recurse -Force $hstwb.Paths.TempPath
    }

    Write-Error $message
    Write-Host ""
    Write-Host "Press enter to continue"
    Read-Host
    exit 1
}


# resolve paths
$kickstartRomHashesFile = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath("Kickstart\kickstart-rom-hashes.csv")
$workbenchAdfHashesFile = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath("Workbench\workbench-adf-hashes.csv")
$packagesPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath("packages")
$winuaePath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath("winuae")
$fsUaePath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath("fs-uae")
$amigaPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath("amiga")
$licensesPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath("licenses")
$scriptsPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath("scripts")
$tempPath = [System.IO.Path]::Combine($env:TEMP, "HstWB-Installer_" + [System.IO.Path]::GetRandomFileName())
$settingsDir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($settingsDir)

$settingsFile = Join-Path $settingsDir -ChildPath "hstwb-installer-settings.ini"
$assignsFile = Join-Path $settingsDir -ChildPath "hstwb-installer-assigns.ini"

$host.ui.RawUI.WindowTitle = "HstWB Installer Run v{0}" -f (HstwbInstallerVersion)

try
{
    $hstwb = @{
        'Version' = HstwbInstallerVersion;
        'Paths' = @{
            'KickstartRomHashesFile' = $kickstartRomHashesFile;
            'WorkbenchAdfHashesFile' = $workbenchAdfHashesFile;
            'AmigaPath' = $amigaPath;
            'WinuaePath' = $winuaePath;
            'FsUaePath' = $fsUaePath;
            'LicensesPath' = $licensesPath;
            'PackagesPath' = $packagesPath;
            'SettingsFile' = $settingsFile;
            'ScriptsPath' = $scriptsPath;
            'TempPath' = $tempPath;
            'AssignsFile' = $assignsFile;
            'SettingsDir' = $settingsDir;
            'EnvArcDir' = 'SYSTEMDIR:Prefs/Env-Archive'
        };
        'Images' = ReadImages $imagesPath;
        'Packages' = ReadPackages $packagesPath;
        'Settings' = ReadIniFile $settingsFile;
        'Assigns' = ReadIniFile $assignsFile
    }


    # fail, if settings file doesn't exist
    if (!(test-path -path $settingsFile))
    {
        Fail $hstwb ("Error: Settings file '$settingsFile' doesn't exist!")
    }


    # fail, if assigns file doesn't exist
    if (!(test-path -path $assignsFile))
    {
        Fail $hstwb ("Error: Assigns file '$assignsFile' doesn't exist!")
    }


    # set default installer mode, if not present
    if (!$hstwb.Settings.Installer -or !$hstwb.Settings.Installer.Mode)
    {
        $hstwb.Settings.Installer = @{}
        $hstwb.Settings.Installer.Mode = "Install"
    }


    # print title and settings 
    $versionPadding = new-object System.String('-', ($hstwb.Version.Length + 2))
    Write-Host ("-------------------{0}" -f $versionPadding) -foregroundcolor "Yellow"
    Write-Host ("HstWB Installer Run v{0}" -f $hstwb.Version) -foregroundcolor "Yellow"
    Write-Host ("-------------------{0}" -f $versionPadding) -foregroundcolor "Yellow"
    Write-Host ""
    PrintSettings $hstwb
    Write-Host ""


    # validate settings
    if (!(ValidateSettings $hstwb.Settings))
    {
        Fail $hstwb "Validate settings failed"
    }


    # validate assigns
    if (!(ValidateAssigns $hstwb.Assigns))
    {
        Fail $hstwb "Validate assigns failed"
    }


    # find workbench adf set hashes 
    $workbenchAdfSetHashes = FindWorkbenchAdfSetHashes $hstwb.Settings $hstwb.Paths.WorkbenchAdfHashesFile

    # find workbench 3.1 workbench disk
    $workbenchAdfHash = $workbenchAdfSetHashes | Where-Object { $_.Name -eq 'Workbench 3.1 Workbench Disk' -and $_.File } | Select-Object -First 1

    # fail, if workbench adf hash doesn't exist
    if (!$workbenchAdfHash)
    {
        Fail $hstwb ("Workbench set '" + $hstwb.Settings.Workbench.WorkbenchAdfSet + "' doesn't have Workbench 3.1 Workbench Disk!")
    }


    # set workbench adf set hashes workbench adf file
    $hstwb.WorkbenchAdfSetHashes = $workbenchAdfSetHashes
    $hstwb.Paths.WorkbenchAdfFile = $workbenchAdfHash.File


    # print workbench adf hash file
    Write-Host ("Using Workbench 3.1 Workbench Disk adf: '" + $workbenchAdfHash.File + "'")


    # find kickstart rom set hashes
    $kickstartRomSetHashes = FindKickstartRomSetHashes $hstwb.Settings $hstwb.Paths.KickstartRomHashesFile


    # find kickstart 3.1 a1200 rom
    $kickstartRomHash = $kickstartRomSetHashes | Where-Object { $_.Name -eq 'Kickstart 3.1 (40.068) (A1200) Rom' -and $_.File } | Select-Object -First 1


    # fail, if kickstart rom hash doesn't exist
    if (!$kickstartRomHash)
    {
        Fail $hstwb ("Kickstart set '" + $hstwb.Settings.Kickstart.KickstartRomSet + "' doesn't have Kickstart 3.1 (40.068) (A1200) rom!")
    }


    # set kickstart rom set hashes kickstart rom file
    $hstwb.KickstartRomSetHashes = $kickstartRomSetHashes
    $hstwb.Paths.KickstartRomFile = $kickstartRomHash.File


    # print kickstart rom hash file
    Write-Host ("Using Kickstart 3.1 (40.068) (A1200) rom: '" + $kickstartRomHash.File + "'")


    # kickstart rom key
    $kickstartRomKeyFile = [System.IO.Path]::Combine([System.IO.Path]::GetDirectoryName($kickstartRomHash.File), "rom.key")

    # fail, if kickstart rom hash is encrypted and kickstart rom key file doesn't exist
    if ($kickstartRomHash.Encrypted -eq 'Yes' -and !(test-path -path $kickstartRomKeyFile))
    {
        Fail $hstwb ("Kickstart set '" + $hstwb.Settings.Kickstart.KickstartRomSet + "' doesn't have rom.key!")
    }


    # create temp path
    if(!(test-path -path $hstwb.Paths.TempPath))
    {
        mkdir $hstwb.Paths.TempPath | Out-Null
    }


    # installer mode
    switch ($hstwb.Settings.Installer.Mode)
    {
        "Test" { RunTest $hstwb }
        "Install" { RunInstall $hstwb }
        "BuildSelfInstall" { RunBuildSelfInstall $hstwb }
        "BuildPackageInstallation" { RunBuildPackageInstallation $hstwb }
    }


    # remove temp path
    Remove-Item -Recurse -Force $hstwb.Paths.TempPath


    # print done message 
    Write-Host ""
    Write-Host "Done."
    Write-Host ""
    Write-Host "Press enter to continue"
    Read-Host
}
catch
{
    # remove temp path
    Remove-Item -Recurse -Force $hstwb.Paths.TempPath

    $errorFormatingString = "{0} : {1}`n{2}`n" +
    "    + CategoryInfo          : {3}`n" +
    "    + FullyQualifiedErrorId : {4}`n"

    $errorFields = $_.InvocationInfo.MyCommand.Name,
    $_.ErrorDetails.Message,
    $_.InvocationInfo.PositionMessage,
    $_.CategoryInfo.ToString(),
    $_.FullyQualifiedErrorId

    $message = $errorFormatingString -f $errorFields
    $logFile = Join-Path $settingsDir -ChildPath "hstwb_installer.log"
    Add-Content $logFile ("{0} | ERROR | {1}" -f (Get-Date -Format s), $message) -Encoding UTF8
    Write-Host ""
    Write-Error "HstWB Installer Setup Failed: $message"
    Write-Host ""
    Write-Host "Press enter to continue"
    Read-Host
}