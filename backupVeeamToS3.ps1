# Veeam to AWS S3 backup script (Offsite backup)
# 
# Description: Looks for synthetic full backup files and uploads
# the most recent ones to bucket in S3. After a successful upload,
# it will delete older backup files on S3 since archive data is 
# currently stored in tape library. Potential to use AWS Glacier
# in the future
# Created by James Davis 9/4/2018
#

Import-Module AWSPowerShell

# Constants – Amazon S3 Configuration
$config = Get-Content -Raw -Path 'C:\Scripts\config.json' | ConvertFrom-Json
$source = 'Y:\'

Initialize-AWSDefaultConfiguration -AccessKey $config.AKey -SecretKey $config.SKey -Region $config.region

Set-Location $source
$backupFolders = Get-ChildItem -Directory | Select-Object -Property FullName
foreach($folder in $backupFolders) {
    Set-Location $folder.FullName
    $files = Get-ChildItem '*.vbk' | Sort-Object CreationTime | Select-Object -Last 1 | Select-Object -Property FullName
    foreach($file in $files){
        # check if file already exists in S3
        if(!(Get-S3Object -BucketName $config.bucket -Key $file.FullName)) { 
            try {
                # upload the latest file
                Write-Host "Uploading file: $file"
                Write-S3Object -BucketName $config.bucket -File $file.FullName -Key $file.FullName -CannedACLName private
            
                # if the upload was successful, delete any old files in S3
                $oldBackupFiles = Get-S3Object -BucketName $config.bucket -Key $folder.FullName | Select-Object -Property Key,LastModified
                foreach($backupFiles in $oldBackupFiles){
                    # delete old files if they don't match new filename
                    $fileName = $file.FullName -replace "\\", "/"
                    if(!($backupFiles.Key -Like $fileName)) { 
                        try {
                            Remove-S3Object -BucketName $config.bucket -Key $backupFiles.Key -Force
                        } catch {
                            Write-Host "Error deleting file from S3"
                        }
                    }
                }
            } catch {
                Write-Host "Error uploading file: $folder.FullName"
            }
        }
    }
}
