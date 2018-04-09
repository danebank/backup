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

# Variable Constants
$config = Get-Content -Raw -Path 'C:\Scripts\backup\config.json' | ConvertFrom-Json
$source = 'Y:\'
[string]$emailBody = ""

Initialize-AWSDefaultConfiguration -AccessKey $config.AKey -SecretKey $config.SKey -Region $config.region
Set-Location $source

$emailBody = $emailBody + $(Get-Date -Format o) + "`tStart Backup Job`n"

$backupFolders = Get-ChildItem -Directory | Select-Object -Property FullName
foreach($folder in $backupFolders) {
    Set-Location $folder.FullName
    $files = Get-ChildItem '*.vbk' | Sort-Object CreationTime | Select-Object -Last 1 | Select-Object -Property FullName
    foreach($file in $files){
        # check if file already exists in S3
        if(!(Get-S3Object -BucketName $config.bucket -Key $file.FullName)) { 
            try {
                # upload the latest file
                $emailBody = $emailBody + $(Get-Date -Format o) + "`tUploading file: " + $file.FullName + "`n"
                Write-S3Object -BucketName $config.bucket -File $file.FullName -Key $file.FullName -CannedACLName private
            
                # if the upload was successful, delete any old files in S3
                $oldBackupFiles = Get-S3Object -BucketName $config.bucket -Key $folder.FullName | Select-Object -Property Key,LastModified
                foreach($backupFiles in $oldBackupFiles){
                    # delete old files if they don't match new filename
                    $fileName = $file.FullName -replace "\\", "/"
                    if(!($backupFiles.Key -Like $fileName)) { 
                        try {
                            $emailBody = $emailBody + $(Get-Date -Format o) + "`tDeleting S3 file: " + $backupFiles.Key + "`n"
                            Remove-S3Object -BucketName $config.bucket -Key $backupFiles.Key -Force
                        } catch {
                            $emailBody = $emailBody + $(Get-Date -Format o) + "Error deleting file from S3`n"
                        }
                    }
                }
            } catch {
                $emailBody = $emailBody + $(Get-Date -Format o) + "Error uploading file: $folder.FullName"
            }
        }
    }
}

$emailBody = $emailBody + $(Get-Date -Format o) + "`tEnd Backup Job`n"
$emailSubject = "Veeam to AWS S3 Backup Log - " + $(Get-Date -DisplayHint Date)

Send-MailMessage -To $config.emailTo -From $config.emailFrom -Subject $emailSubject -SmtpServer $config.smtpServer -Body $emailBody