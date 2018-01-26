# HstWB Installer Data Module
# ---------------------------
#
# Author: Henrik Noerfjand Stengaard
# Date:   2018-01-26
#
# A powershell module for HstWB Installer with data functions.


Add-Type -AssemblyName System.IO.Compression.FileSystem


# $nodes = @()
# $nodes += @{ 'Name'= 'package1'; 'Dependencies' = @() }
# $nodes += @{ 'Name'= 'package2'; 'Dependencies' = @() }
# $nodes += @{ 'Name'= 'package3'; 'Dependencies' = @('package1') }
# $nodes += @{ 'Name'= 'package4'; 'Dependencies' = @('package1') }
# $nodes += @{ 'Name'= 'package5'; 'Dependencies' = @('package3') }


# # package1
# # - package3
# #   - package5
# # - package4
# # package2

# TopologicalSort $nodes


# topological sort
function TopologicalSort {
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        $nodes
    )

    $nodesIndex = @{}
    $nodesDependencyIndex = @{}
    $currentNodes = New-Object -TypeName System.Collections.Generic.Stack[object]

    for($i = $nodes.Count - 1; $i -ge 0; $i--)
    {
        $node = $nodes[$i]

        if (!$nodesIndex.ContainsKey($node.Name))
        {
            $nodesIndex.Set_Item($node.Name, $node)
        }
        else
        {
            throw ("'{0}' is duplicate" -f $node.Name)    
        }

        if ($node.Dependencies.Count -eq 0)
        {
            [void]$currentNodes.Push($node.Name)
            continue
        }

        foreach($nodeDependency in $node.Dependencies)
        {
            if ($nodesDependencyIndex.ContainsKey($nodeDependency))
            {
                $nodeDependencies = $nodesDependencyIndex.Get_Item($nodeDependency)
            }
            else
            {
                $nodeDependencies = @()
            }

            if ($nodeDependencies.Contains($node.Name))
            {
                continue
            }

            $nodeDependencies += $node.Name
            $nodesDependencyIndex.Set_Item($nodeDependency, $nodeDependencies)
        }
    }

    # throw error, if node dependency doesn't exist or circular dependency detected between nodes
    foreach($node in $nodesIndex.keys)
    {
        foreach($nodeDependency in $nodesIndex[$node].Dependencies)
        {
            if (!$nodesIndex.ContainsKey($nodeDependency))
            {
                throw ("'{0}' dependency '{1}' doesn't exist" -f $node, $nodeDependency)
            }
            else
            {
                if ($nodesIndex[$nodeDependency].Contains($node))
                {
                    throw ("Circular dependency between '{0}' and '{1}'" -f $node, $nodeDependency)
                }
            }
        }
    }

    $topologicallySortedNodes = New-Object System.Collections.ArrayList

    while($currentNodes.Count -gt 0)
    {
        $node = $currentNodes.Pop()

        [void]$topologicallySortedNodes.Add($node)

        if ($nodesDependencyIndex.ContainsKey($node))
        {
            $nodesDependencyIndex[$node] | ForEach-Object { [void]$currentNodes.Push($_) }
        }
    }

    return $topologicallySortedNodes
}


# topological sort v2
function TopologicalSortV2 {
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [hashtable]$nodes
    )

    $nodeDependenciesIndex = @{}
    $currentNodes = New-Object -TypeName System.Collections.Generic.Stack[object]

    foreach($node in ($nodes.keys | Sort-Object @{expression={$nodes[$_].SortOrder};Ascending=$false}))
    {
        if ($nodes[$node].Dependencies.Count -eq 0)
        {
            [void]$currentNodes.Push($_)
            continue
        }

        foreach($nodeDependency in $nodes[$node].Dependencies)
        {
            if (!$nodes.ContainsKey($nodeDependency))
            {
                throw ("'{0}' dependency '{1}' doesn't exist" -f $node, $nodeDependency)
            }
            else
            {
                if ($nodes[$nodeDependency].Dependencies.Contains($node))
                {
                    throw ("Circular dependency between '{0}' and '{1}'" -f $node, $nodeDependency)
                }
            }

            if ($nodeDependenciesIndex.ContainsKey($nodeDependency))
            {
                $nodeDependencies = $nodeDependenciesIndex.Get_Item($nodeDependency)
            }
            else
            {
                $nodeDependencies = @()
            }

            if ($nodeDependencies.Contains($node))
            {
                continue
            }

            $nodeDependencies += $node
            $nodeDependenciesIndex.Set_Item($nodeDependency, $nodeDependencies)
        }
    }

    foreach($node in $currentNodes)
    {
        Write-Host $node
    }

    $topologicallySortedNodes = New-Object System.Collections.ArrayList

    while($currentNodes.Count -gt 0)
    {
        $node = $currentNodes.Pop()

        [void]$topologicallySortedNodes.Add($node)

        if ($nodeDependenciesIndex.ContainsKey($node))
        {
            $nodeDependenciesIndex[$node] | ForEach-Object { [void]$currentNodes.Push($_) }
        }
    }

    return $topologicallySortedNodes
}


# read zip entry text file
function ReadZipEntryTextFile($zipFile, $entryName)
{
    # open zip archive
    $zipArchive = [System.IO.Compression.ZipFile]::Open($zipFile,"Read")
    $zipArchiveEntry = $zipArchive.Entries | Where-Object { $_.FullName -match $entryName } | Select-Object -First 1

    # return null, if zip archive entry doesn't exist
    if (!$zipArchiveEntry)
    {
        $zipArchive.Dispose()
        return $null
    }

    # open zip archive entry stream
    $entryStream = $zipArchiveEntry.Open()
    $streamReader = New-Object System.IO.StreamReader($entryStream)

    # read text from stream
    $text = $streamReader.ReadToEnd()

    # close streams
    $streamReader.Close()
    $streamReader.Dispose()

    # close zip archive
    $zipArchive.Dispose()
    
    return $text
}


# zip file contains
function ZipFileContains($zipFile, $pattern)
{
    # open zip archive
    $zipArchive = [System.IO.Compression.ZipFile]::Open($zipFile,"Read")
    
    # get zip archive entries matching pattern
    $matchingZipArchiveEntries = @()
    $matchingZipArchiveEntries += $zipArchive.Entries | Where-Object { $_.FullName -match $pattern }

    # close zip archive
    $zipArchive.Dispose()

    return $matchingZipArchiveEntries.Count -gt 0
}


# extract files from zip file
function ExtractFilesFromZipFile($zipFile, $pattern, $outputDir)
{
    # open zip archive
    $zipArchive = [System.IO.Compression.ZipFile]::Open($zipFile,"Read")
    
    # get zip archive entries matching pattern
    $matchingZipArchiveEntries = @()
    $matchingZipArchiveEntries += $zipArchive.Entries | Where-Object { $_.FullName -match $pattern }

    # extract matching zip archive entries
    foreach($zipArchiveEntry in $matchingZipArchiveEntries)
    {
        # get output file
        $outputFile = Join-Path $outputDir -ChildPath $zipArchiveEntry.FullName

        # get output file parent dir
        $outputFileParentDir = Split-Path $outputFile -Parent

        # create entry directory, if it doesn't exist
        if (!(Test-Path $outputFileParentDir))
        {
            mkdir $outputFileParentDir | Out-Null
        }

        # open zip archive entry stream
        $zipArchiveEntryStream = $zipArchiveEntry.Open()

        # open file stream and write from entry stream
        $outputFileStream = New-Object System.IO.FileStream($outputFile, 'Create')
        $zipArchiveEntryStream.CopyTo($outputFileStream)

        # close streams
        $outputFileStream.Close()
        $outputFileStream.Dispose()
        $zipArchiveEntryStream.Close()
        $zipArchiveEntryStream.Dispose()
    }

    # close zip archive
    $zipArchive.Dispose()
}


# calculate md5 hash from file
function CalculateMd5FromFile($file)
{
	$md5 = new-object -TypeName System.Security.Cryptography.MD5CryptoServiceProvider
	return [System.BitConverter]::ToString($md5.ComputeHash([System.IO.File]::ReadAllBytes($file))).ToLower().Replace('-', '')
}


# calculate md5 hash from text
function CalculateMd5FromText($text)
{
    $encoding = [system.Text.Encoding]::UTF8
	$md5 = new-object -TypeName System.Security.Cryptography.MD5CryptoServiceProvider
	return [System.BitConverter]::ToString($md5.ComputeHash($encoding.GetBytes($text))).ToLower().Replace('-', '')
}


# get file hashes
function GetFileHashes($path)
{
    $files = Get-ChildItem -Path $path | Where-Object { ! $_.PSIsContainer }

    $fileHashes = @()

    foreach ($file in $files)
    {
        $md5Hash = CalculateMd5FromFile $file.FullName

        $fileHashes += @{ "File" = $file.FullName; "Md5Hash" = $md5Hash }
    }

    return $fileHashes
}


# find matching file hashes
function FindMatchingFileHashes($hashes, $path)
{
    # get file hashes from path
    $fileHashes = GetFileHashes $path

    # index file hashes
    $fileHashesIndex = @{}
    $fileHashes | % { $fileHashesIndex.Set_Item($_.Md5Hash, $_.File) }

    # find files with matching hashes
    foreach($hash in $hashes)
    {
        $file = $null
        if ($fileHashesIndex.ContainsKey($hash.Md5Hash))
        {
            $file = $fileHashesIndex.Get_Item($hash.Md5Hash)
        }

        $hash | Add-Member -MemberType NoteProperty -Name 'File' -Value $file -Force
    }
}


# read string from bytes
function ReadString($bytes, $offset, $length)
{
	$stringBytes = New-Object 'byte[]' $length 
	[Array]::Copy($bytes, $offset, $stringBytes, 0, $length)
	$iso88591 = [System.Text.Encoding]::GetEncoding("ISO-8859-1");
	return $iso88591.GetString($stringBytes)
}


# read adf disk name
function ReadAdfDiskName($bytes)
{
    # read disk name from offset 0x6E1B0
    $diskNameOffset = 0x6E1B0
    $diskNameLength = $bytes[$diskNameOffset]

    ReadString $bytes ($diskNameOffset + 1) $diskNameLength
}


# find matching workbench adfs
function FindMatchingWorkbenchAdfs($hashes, $path)
{
    $adfFiles = Get-ChildItem -Path $path -filter *.adf

    $validWorkbenchAdfFiles = @()

    foreach ($adfFile in $adfFiles)
    {
        # read adf bytes
        $adfBytes = [System.IO.File]::ReadAllBytes($adfFile.FullName)

        if ($adfBytes.Count -eq 901120)
        {
            $diskName = ReadAdfDiskName $adfBytes
            $validWorkbenchAdfFiles += @{ "DiskName" = $diskName; "File" = $adfFile.FullName }
        }
    }


    # find files with matching disk names
    foreach($hash in ($hashes | Where-Object { $_.DiskName -ne '' -and !$_.File }))
    {
        $matchingWorkbenchAdfFile = $validWorkbenchAdfFiles | Where-Object { $_.DiskName -eq $hash.DiskName } | Select-Object -First 1

        $workbenchAdfFile = $null 

        if ($matchingWorkbenchAdfFile)
        {
            $workbenchAdfFile = $matchingWorkbenchAdfFile.File
        }

        $hash | Add-Member -MemberType NoteProperty -Name 'File' -Value $workbenchAdfFile -Force
    }
}


# find workbench adfs
function FindWorkbenchAdfs($hstwb)
{
    # find files with hashes matching workbench adf hashes
    FindMatchingFileHashes $hstwb.WorkbenchAdfHashes $hstwb.Settings.Workbench.WorkbenchAdfDir
    
    # find files with disk names matching workbench adf hashes
    FindMatchingWorkbenchAdfs $hstwb.WorkbenchAdfHashes $hstwb.Settings.Workbench.WorkbenchAdfDir
}


# find kickstart roms
function FindKickstartRoms($hstwb)
{
    # find files with hashes matching kickstart rom hashes
    FindMatchingFileHashes $hstwb.KickstartRomHashes $hstwb.Settings.Kickstart.KickstartRomDir
}


# find best matching kickstart rom set
function FindBestMatchingKickstartRomSet($hstwb)
{
    # find kickstart roms
    FindKickstartRoms $hstwb

    # get kickstart rom sets
    $kickstartRomSets = @()
    $kickstartRomSets += $hstwb.KickstartRomHashes | Sort-Object @{expression={$_.Priority};Ascending=$false} | ForEach-Object { $_.Set } | Get-Unique
        
    # count matching kickstart rom hashes for each set
    $kickstartRomSetCount = @{}
    foreach($kickstartRomSet in $kickstartRomSets)
    {
        $kickstartRomSetFiles = @()
        $kickstartRomSetFiles += $hstwb.KickstartRomHashes | Where-Object { $_.Set -eq $kickstartRomSet -and $_.File }
        $kickstartRomSetCount.Set_Item($kickstartRomSet, $kickstartRomSetFiles.Count)
    }

    # get new kickstart rom set, which has highest number of matching kickstart rom hashes
    return $kickstartRomSets | Sort-Object @{expression={$kickstartRomSetCount.Get_Item($_)};Ascending=$false} | Select-Object -First 1    
}


# find best matching workbench adf set
function FindBestMatchingWorkbenchAdfSet($hstwb)
{
    # find workbench adfs
    FindWorkbenchAdfs $hstwb

    # get workbench rom sets
    $workbenchAdfSets = @()
    $workbenchAdfSets += $hstwb.WorkbenchAdfHashes | Sort-Object @{expression={$_.Priority};Ascending=$false} | ForEach-Object { $_.Set } | Get-Unique

    # count matching workbench adf hashes for each set
    $workbenchAdfSetCount = @{}
    foreach($workbenchAdfSet in $workbenchAdfSets)
    {
        $workbenchAdfSetFiles = @()
        $workbenchAdfSetFiles += $hstwb.WorkbenchAdfHashes | Where-Object { $_.Set -eq $workbenchAdfSet -and $_.File }
        $workbenchAdfSetCount.Set_Item($workbenchAdfSet, $workbenchAdfSetFiles.Count)
    }

    # get new workbench adf set, which has highest number of matching workbench adf hashes
    return $workbenchAdfSets | Sort-Object @{expression={$workbenchAdfSetCount.Get_Item($_)};Ascending=$false} | Select-Object -First 1
}


# sort packages to install
function SortPackageNames($hstwb)
{
    $packages = @()

    foreach ($packageName in $hstwb.Packages.Keys)
    {
        $package = $hstwb.Packages.Get_Item($packageName).Latest
        
        # get package priority, if it exists. otherwise use default priority 9999
        $priority = if ($package.Package.Priority) { [Int32]$package.Package.Priority } else { 9999 }

        $packages += @{ 'Name'= $package.Package.Name; 'Dependencies' = $package.PackageDependencies; 'Priority' = $priority }
    }

    $packageNamesSorted = @()

    # topologically sort packages, if any packages are present
    if ($packages.Count -gt 0)
    {
        # sort packages by priority and name
        $packagesSorted = @()
        $packagesSorted += $packages | Sort-Object @{expression={$_.Priority};Ascending=$true}, @{expression={$_.Name};Ascending=$true}

        # topologically sort packages and add package names sorted
        TopologicalSort $packagesSorted | ForEach-Object { $packageNamesSorted += $_ }
    }

    return $packageNamesSorted
}


# get all package dependencies
function GetDependencyPackageNames($hstwb, $package)
{
    $dependencyPackageNames = @()

    foreach ($dependencyPackageName in $package.PackageDependencies)
    {
        if (!$hstwb.Packages.ContainsKey($dependencyPackageName))
        {
            continue
        }

        $dependencyPackage = $hstwb.Packages.Get_Item($dependencyPackageName).Latest
        $dependencyPackageNames += GetDependencyPackageNames $hstwb $dependencyPackage
        $dependencyPackageNames += $dependencyPackageName
    }

    return $dependencyPackageNames
}