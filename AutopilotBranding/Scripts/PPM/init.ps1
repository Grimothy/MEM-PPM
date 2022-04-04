######################################################################
#                                                                    #
# Download and Unzip GitHub Repository                               #
# Author: Sandro Pereira\CJ COulter                                  #
#                                                                    #
######################################################################

New-Item -ItemType File -Path "$($env:ProgramData)\Microsoft\AutopilotBranding\PPM.log" -Force


Start-Transcript -Path "$($env:ProgramData)\Microsoft\AutopilotBranding\PPM.log"

function DownloadGitHubRepository 
{ 
    param( 
       [Parameter(Mandatory=$False)] 
       [string] $Name = "MEM-PPM",
         
       [Parameter(Mandatory=$False)] 
       [string] $Author = "Grimothy" ,
         
       [Parameter(Mandatory=$False)] 
       [string] $Branch = "Dev", 
         
       [Parameter(Mandatory=$False)] 
       [string] $Location = "$($env:ProgramData)\Microsoft\AutopilotBranding\scripts\PPM\_Extractions",
       
       [Parameter(Mandatory=$False)]
       [string] $weburi = "https://github.com/Grimothy/MEM-PPM/tree/main/_actions"
       
    ) 
     
   $RepositoryZipUrl = "https://api.github.com/repos/$Author/$Name/zipball/$Branch"
   
   If ($(Invoke-WebRequest -Uri $weburi).StatusDescription -like "OK") 
   {
        
        Write-Host -ForegroundColor Green "$weburi is Healthy"
        Start-Sleep -Seconds 2
        # Force to create a zip file 
        $ZipFile = "$location\$Name.zip"
        New-Item $ZipFile -ItemType File -Force
 
    
    
        # download the zip 
        Write-Host 'Starting downloading the GitHub Repository'
        Invoke-RestMethod -Uri $RepositoryZipUrl -OutFile $ZipFile
        Write-Host 'Download finished'
 
        #Extract Zip File
        Write-Host 'Starting unzipping the GitHub Repository locally'
        Expand-Archive -Path $ZipFile -DestinationPath $location -Force
        Write-Host 'Unzip finished'
     
        # remove the zip file
        Remove-Item -Path $ZipFile -Force
    
        #Copy extracted items
        $foldersource = Get-ChildItem -Recurse $Location | Where-Object {$_.BaseName -like "_actions"} -Verbose
        #Copy-Item -Recurse $foldersource.FullName "$($env:ProgramData)\Microsoft\AutopilotBranding\scripts\PPM\_actions" -Force
        Robocopy $foldersource.FullName "$($env:ProgramData)\Microsoft\AutopilotBranding\scripts\PPM\_actions" /MIR /FFT /Z /XA:H /W:5
        #Remove extracted files
        Remove-Item $Location -Recurse -Force

    

    
    }else{

        exit
    }
}
DownloadGitHubRepository

#Beging processing Actions
Write-Host "Starting to process items in _actions folder"
$scripts = Get-ChildItem -Recurse "$($env:ProgramData)\Microsoft\AutopilotBranding\scripts\PPM\_actions\" |
Where-Object {($_.Extension -like "*ps1" -or $_.Extension -like "*bat") }
Set-ExecutionPolicy -ExecutionPolicy Bypass

Foreach ($i in $scripts) {

Write-Host "Processing script $i"
Start-Process powershell -WindowStyle Hidden $i.FullName

}

Stop-Transcript

