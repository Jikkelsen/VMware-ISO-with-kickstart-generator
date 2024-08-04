
<#
 __          __   _ _              _  ___      _        _             _ _______    ______  _______   _______            
 \ \        / /  (_) |            | |/ (_)    | |      | |           | |__   __|  |  ____|/ ____\ \ / /_   _|           
  \ \  /\  / / __ _| |_ ___ ______| ' / _  ___| | _____| |_ __ _ _ __| |_ | | ___ | |__  | (___  \ V /  | |  ___  ___   
   \ \/  \/ / '__| | __/ _ \______|  < | |/ __| |/ / __| __/ _` | '__| __|| |/ _ \|  __|  \___ \  > <   | | / __|/ _ \  
    \  /\  /| |  | | ||  __/      | . \| | (__|   <\__ \ || (_| | |  | |_ | | (_) | |____ ____) |/ . \ _| |_\__ \ (_) | 
     \/  \/ |_|  |_|\__\___|      |_|\_\_|\___|_|\_\___/\__\__,_|_|   \__||_|\___/|______|_____//_/ \_\_____|___/\___/  
                                                                                                                       
#>
function Write-KickstartToESXIso 
{
    
    [CmdletBinding()]
    param 
    (
        [Parameter()]
        [String]
        $InputBaseImage,

        [Parameter()]
        [String]
        $OutputIsoName = "KS_" + $InputBaseImage
    )
    
    # Static Variables
    $IterationTick     = ("Iteration_" + (Get-Date).Ticks)
    $BaseIsoLocation   = "$pwd\Output\BaseCustomISOs"
    $KickstartLocation = "$pwd\ProgramFiles\"
    $TempLocation      = "$pwd\.TempFiles\$IterationTick\InputIsoRawFile"
    $TempISODirectory  = "$pwd\.TempFiles\$IterationTick\InputIsoContents"
    

    if (($False -eq (Test-Path $TempLocation)) -or ($False -eq (Test-Path $TempISODirectory)))
    {
        Write-Host "Creating missing directories"
        [void]::(New-Item -ItemType "Directory" -Path $TempLocation     -Force)
        [void]::(New-Item -ItemType "Directory" -Path $TempISODirectory -Force)
    }

    # Copy contents to tempmorary folder
    Copy-Item -path "$BaseISOLocation\$InputBaseImage" -Destination $TempLocation -Force

    # Get current mounted drives
    Write-Host "Mounting ISO ... " -NoNewline
    try 
    {
        $PreMountVolumes = (Get-Volume).Where({$_.DriveLetter}).DriveLetter
        
        $MountParams = @{
            ImagePath   = "$TempLocation\$InputBaseImage"
            Access      = "ReadOnly"
            StorageType = "ISO"
        }
        $MountedISO = (Mount-DiskImage @MountParams)

        #Start-Sleep -seconds 5

        Write-Verbose "Detemrining the Drive Letter of the Mounted ISO ..."
        $PostMountVolumes = (Get-Volume).Where({$_.DriveLetter}).DriveLetter
        $ISO              = (Compare-Object -ReferenceObject $PreMountVolumes -DifferenceObject $PostMountVolumes).InputObject
        Write-Host "OK. Mounted to"$ISO":\"
    }
    catch 
    {
        Write-Host "FAIL!"
        throw
    }

    Write-Host "Copying contents of iso to folder ... " -NoNewline
    [void]::(New-Item -ItemType "Directory" -Force -Path $TempISODirectory)
    Copy-Item -Path "$($ISO):\*" -Destination $TempISODirectory\ -Recurse -Force
    Write-Host "OK"

    Write-Host "Injecting KickstartFile ... " -NoNewline
    #$KickstartDirectory = New-Item -Name "KS" -ItemType "Directory" -Path $TempISODirectory\
    [void]::(Copy-Item -Path "$KickstartLocation\KS.CFG" -Destination $TempISODirectory)
    Start-Sleep -Seconds 1
    [void]::(Rename-Item -Path "$TempISODirectory\KS.CFG" -NewName "$TempISODirectory\KS_CUST.CFG" -Force) 
    Write-Host "OK"

    Write-Host 'Configuring "BOOT.CFG" files ... ' -NoNewline
    # First get location of the files
    $BIOSFile = "$TempISODirectory\boot.cfg"
    $UEFIFile = "$TempISODirectory\efi\boot\boot.cfg"

    # Replace content
    [Void]::((get-content $BIOSFile -Raw) -replace "kernelopt=runweasel cdromBoot", "kernelopt=runweasel ks=cdrom:/KS_CUST.CFG" | Set-Content $BIOSFile -Force)
    [Void]::((get-content $UEFIFile -Raw) -replace "kernelopt=runweasel cdromBoot", "kernelopt=runweasel ks=cdrom:/KS_CUST.CFG" | Set-Content $UEFIFile -Force)
    Write-Host "OK"

    # Check output dir
    if ($False -eq (Test-Path ".\Output\KickstartISOs"))
    {
        [void]::(New-Item -ItemType "Directory" -Path .\Output\KickstartISOs  -Force)
    }

    Write-Host "Cleanup"
    if ((Get-DiskImage -ImagePath $MountedISO.ImagePath -ErrorAction SilentlyContinue).Attached -eq $True)
    {
        [void]::(Dismount-DiskImage -ImagePath $MountedISO.ImagePath -Confirm:$false)
    }

    ####
    # Inline Ubuntu
    wsl.exe ./ProgramFiles/FolderToISO.sh $IterationTick $OutputIsoName

    ####

    #if (Test-Path -Path  $TempLocation\File.Iso)
    #{
    #    [void]::(Remove-Item "$TempLocation\File.iso" -Force)
    #}
    #
    #if ((Test-Path -Path $TempISODirectory) -or (Test-Path -Path $TempLocation))
    #{
    #    [void]::(Remove-Item $TempISODirectory -Recurse -Force)
    #    [void]::(Remove-Item $TempLocation -Recurse -Force)
    #    [void]::(Remove-Item "$pwd\$IterationTick")
    #}
}