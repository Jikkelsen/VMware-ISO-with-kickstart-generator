<#
  _   _                       _____          _                  ____                 ______  _______   ___           
 | \ | |                     / ____|        | |                |  _ \               |  ____|/ ____\ \ / (_)          
 |  \| | _____      ________| |    _   _ ___| |_ ___  _ __ ___ | |_) | __ _ ___  ___| |__  | (___  \ V / _ ___  ___  
 | . ` |/ _ \ \ /\ / /______| |   | | | / __| __/ _ \| '_ ` _ \|  _ < / _` / __|/ _ \  __|  \___ \  > < | / __|/ _ \ 
 | |\  |  __/\ V  V /       | |___| |_| \__ \ || (_) | | | | | | |_) | (_| \__ \  __/ |____ ____) |/ . \| \__ \ (_) |
 |_| \_|\___| \_/\_/         \_____\__,_|___/\__\___/|_| |_| |_|____/ \__,_|___/\___|______|_____//_/ \_\_|___/\___/ 
                                                                                                                     
#>
function New-CustomBaseESXIso {
    
    [CmdletBinding()]
    param 
    (
        [Parameter()]
        [String]
        $UsingLocalImage,

        [Parameter()]
        [String]
        $UsingOnlineImage
    )
    # Exit if both are populated

    if ((-not [String]::IsNullOrEmpty($UsingOnlineImage)) -and (-not [String]::IsNullOrEmpty($UsingLocalImageo)))
    {
        Write-Host "Cannot use both a local and an online image"
        throw
    }
    
    # Static Varialbes
    $BaseIsoFolder      = "$pwd\Output\BaseCustomISOs"
    $BaseImageFolder    = "$pwd\ProgramFiles\BaseImages"
    $CustomDriverFolder = "$pwd\Drivers\*"
    $OnlineDepot        = "https://hostupdate.vmware.com/software/VUM/PRODUCTION/main/vmw-depot-index.xml"
     
    #region-----------------------------------| PYTHON REQUIREMENT |-----------------------------------------#
    # Make sure Python is installed. This is needed for the .iso generation
    $PythonInstall = python --version 2>&1

    # Python is not installed
    if ($PythonInstall -is [System.Management.Automation.ErrorRecord])
    {
        Write-Host "Python is not installed. Attempting install"
        Winget install python3.7 --accept-package-agreements

        Write-Host "Installing dependencies"
        #$HOME\AppData\Local\Programs\Python\Python37\python.exe -m pip install -U pip
        #pip install six psutil lxml pyopenssl
        throw
    }
    else
    {
        Write-Debug "Python install validated; version $PythonInstall"
    }
    #endregion

    #region---------------------------------| POWERCLI CONFIGURATION |---------------------------------------#
    # Check if the VMware.PowerCLI module is imported
    if ($null -eq (Get-InstalledModule | Where-Object Name -match "Vmware.PowerCLI"))
    {
        Write-Host "Installing missing module 'VMware.PowerCLI'"
        Install-Module -Name "VMware.PowerCLI" -SkipPublisherCheck -confirm:$false
    }

    Write-Debug "Configuring PowerCLI"
    try
    {   # Don't make PowerCLI make noise
        [void]::(Set-PowerCLIConfiguration -Scope "User" -ParticipateInCEIP:$false -confirm:$false)

        # Set the path to the Python 3.7 executable (this specific version is required per VMware PowerCLI Compatibility Matrixes)
        # You may have to manually change the python.exe path, but this is the path that chocolately installs it to by default
        [void]::(Set-PowerCLIConfiguration -PythonPath "$env:LOCALAPPDATA\Programs\Python\Python37\python.exe" -Scope User -confirm:$false)

        # Remove lingering software depots from old runs
        #Get-EsxSoftwareDepot | Remove-EsxSoftwareDepot
    }
    catch
    {
        Write-Host "FAIL"
        throw
    }
    #Endregion

    #region-----------------------| PROMT FOR DEPOT IF NOT ALREADY DOWNLOADED |-----------------------------#
    
    if ([String]::IsNullOrEmpty($UsingLocalImage))
    {
        Write-Host "Adding online depot ... " -NoNewline
        [void]::(Add-EsxSoftwareDepot $OnlineDepot)
        Write-Host "OK"

        # Prompt the user to choose image from online depot if not supplied
        if ([String]::IsNullOrEmpty($UsingOnlineImage))
        {
            Write-Host "Retrieving online Images ... " -NoNewline
            $AvailableOnlineProfiles = Get-EsxImageProfile
            Write-Host "OK"
    
            Write-Host "Available Image Profiles:"
            $List = ($AvailableOnlineProfiles | Where-Object {$_.Name -match "standard"} | Sort-object -Property "CreationTime" -Descending).Name
    
            Write-Host "Please choose a Base Image:"
            For ($i=0; $i -lt $List.Count; $i++)  {
                Write-Host "`t$($i+1) | $($List[$i])"
            }
    
            Start-sleep -seconds 1
            [System.Int32]$Number  = Read-Host "Press a number to select depot"
            $BaseImage             = $List[$Number-1]
            
            Write-Host "You've selected $($List[$Number-1])."
        }
        else 
        {
            # No need to choose image; initiate download
            $BaseImage = $UsingOnlineImage
        }
        
        # Create folder if not exist
        if (-not (Test-Path $BaseImageFolder))
        {
            [void]::(New-Item -ItemType "Directory" -Path $BaseImageFolder)
        }

        # Don't download if already found locally
        if (Test-Path "$BaseImageFolder\$BaseImage.zip")
        {
            Write-Host "The base image $BaseImage is already found locally, using that"
        }
        else 
        {
            # Download desired image
            $Params = @{
                ImageProfile   = $BaseImage
                filepath       = "$BaseImageFolder\$BaseImage.zip"
                ExportToBundle = $true
                Force          = $true
            }   

            Write-Host "Exporting $BaseImage to local .zip file ... " -NoNewline
            [void]::(Export-ESXImageProfile @Params)
            Write-Host "OK"
        }

        Write-Host "Removing online depot again ... " -NoNewline
        [void]::(Remove-EsxSoftwareDepot $OnlineDepot)
        Write-Host "OK"

        $BaseImagePath = "$BaseImageFolder\$BaseImage.zip"
        #endregion
    }
    else 
    {
        $BaseImagePath = $UsingLocalImage
    }

    Write-Host "Importing local Base Image file as software depot ... " -NoNewline
    [void]::(Add-EsxSoftwareDepot $BaseImagePath)
    $ImageName = ((Get-Item $BaseImagePath).Name -split ".zip")[0]
    Write-Host "OK"

    #region-----------------------------------| ADDITIONAL DRIVERS |-----------------------------------------#
    $AllCustomDrivers = Get-Item $CustomDriverFolder
    $NewCustomName    = $ImageName

    # Drivers get added to local depot, so they can be injected into image profile
    if ($AllCustomDrivers)
    {
        Write-Host "Adding drivers to depot"

        $NewCustomName += "_with"
        foreach ($Driver in $AllCustomDrivers)
        {
            try 
            {
                $DriverRelativePath = ([io.compression.zipfile]::OpenRead($Driver).Entries | Where-Object FullName -match ".vib").FullName
                $DriverName         = ($DriverRelativePath -split "/")[1]
                
                Write-Host "  $DriverName ... " -NoNewline
                [void]::(Add-EsxSoftwareDepot $Driver)
                $NewCustomName += "_" + $DriverName
                Write-Host "OK"
            }
            catch
            {
                Write-Host "FAIL!" -BackgroundColor Red
                Write-Host "`tCould not add $Driver to bundle"
                throw
            }
        }
        Write-Host "All drivers injected"
        #endregion
    }
    #---------------------------------------------| Create iso |---------------------------------------------#

    Write-Host "Creating new image profile ... " -NoNewline
    $NewProfileParams = @{
        CloneProfile = $ImageName
        Name         = $NewCustomName
        Vendor       = "PowerShellCustomCreation"
    }
    [void]::(New-EsxImageProfile @NewProfileParams)
    Write-Host "OK"

    # Allows to read .zip archives
    Add-Type -assembly "system.IO.compression.filesystem"

    # And now inject the drivers into image profile
    if ($AllCustomDrivers)
    {
        Write-Host "Injecting drivers to image profile"
        Foreach ($Driver in $AllCustomDrivers)
        {
            try 
            {
                $DriverRelativePath = ([io.compression.zipfile]::OpenRead($Driver).Entries | Where-Object FullName -match ".vib").FullName
                $DriverName         = ($DriverRelativePath -split "/")[1]
            
                Write-Host "  $DriverName ... " -NoNewline
                [void]::(Add-EsxSoftwarePackage -ImageProfile $NewCustomName -SoftwarePackage $DriverName)
                Write-Host "OK"
            }
            catch
            {
                Write-Host "FAIL!" 
                Write-Host "`tCould not add driver"
                throw
            }
        }
    }

    #---------------------------------------------| Export iso |---------------------------------------------#

    # Create folder if not exist
    if (-not (Test-Path $BaseIsoFolder))
    {
        [void]::(New-Item -ItemType "Directory" -Path $BaseIsoFolder)
    }

    Write-Host "Creating customized .iso file ... " -NoNewline
    $Params = @{
        ImageProfile = $NewCustomName 
        filepath     = "$BaseIsoFolder\$NewCustomName.iso"
        ExportToIso  = $true
        Force        = $true
    }
    [void]::(Export-ESXImageProfile @Params)
    Write-Host "OK"

    #-----------------------------------------------| Cleanup |----------------------------------------------#
    # Kill the lingering process from image generation
    #Get-process | Where-Object "Name" -match "python" | Stop-Process
}