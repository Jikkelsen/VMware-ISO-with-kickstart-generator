
# Check physical machine

# Make IP Reservation



# Build the base ISO file

# Build the final Kickstart file

Write-Host "#---------------------------------| Generate Bare ISO |---------------------------------------#"
#New-CustomBaseESXIso -UsingOnlineImage "ESXi-8.0U3-24022510-standard"
New-CustomBaseESXIso -UsingLocalImage ".\ProgramFiles\BaseImages\ESXi-8.0U3-24022510-standard.zip"

Write-Host "#---------------------------------| Inject KS |---------------------------------------#"
Write-KickstartToESXIso -InputBaseImage "ESXi-8.0U3-24022510-standard_with_net-community.iso" #-OutputIsoName "New-ISO-6"

