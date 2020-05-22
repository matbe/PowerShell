  
<#
.SYNOPSIS
  Creates a backup of a category from technet gallery which will be discontinues in June 2020.

.NOTES
  Version:        1.0
  Author:         Mattias Benninge
  Creation Date:  2020-05-22
  Purpose/Change: Initial script development
  Based on a script by Damien van Robaeys
  https://github.com/damienvanrobaeys/Backup_Technet_Gallery_Contrib
  
  - Damiens script exported everything for a specific user, my version exports everthing in a category
  - This version also exports the full description of the project.
  - Added User and last updated date to summary.txt file
  - Exports any powershell code in the description into a file called PowerShell.ps1
  - Updates all folders created/last changedate based on the projects last updated date.

#>


#output folder (must already exist)
$Backup_output_Folder = "c:\temp\TechnetGallery"

# The link of the category/user you want to backup, this link downloads everything in the "configmanager" catagory
$link = 'https://gallery.technet.microsoft.com/site/search?f%5B0%5D.Type=RootCategory&f%5B0%5D.Value=SystemCenter&f%5B0%5D.Text=System%20Center&f%5B1%5D.Type=SubCategory&f%5B1%5D.Value=configmanager&f%5B1%5D.Text=Configuration%20Manager'

#Base url for the technet gallery
$Basic_Technet_Link = "https://gallery.technet.microsoft.com"

$parse_profile = Invoke-WebRequest -Uri $link | select *

$Get_Last_Character = $parse_profile.ParsedHtml.body.getElementsByClassName("Link")| Where {$_.innertext -like "*Last*"} 

$Get_Last_Page = ($Get_Last_Character  | select -expand href).Split("=")[-1] 
$Contrib_Array = $null
$Contrib_Array = @()
for ($i=1; $i -le $Get_Last_Page; $i++)
	{
		$Percent_Progress = [math]::Round($i / $Get_Last_Page * 100)
        Write-Progress -Activity "Retriving Technet Gallery contributions" -status "Page $i / $Get_Last_Page - $Percent_Progress %"
        $Current_Link = $link +  "&pageIndex=$i"	
		$Parse_Current_Page = Invoke-WebRequest -Uri $Current_Link | select *
		$Current_Page_Content = $Parse_Current_Page.links | Foreach {$_.href }
		$Current_Page_Links = $Current_Page_Content | Select-String -Pattern 'about:' | Select-String -Pattern "/site/" -NotMatch  | Select-String -Pattern "about:blank#" -NotMatch | Select-String -Pattern "about:/Account/" -NotMatch	
		$Contrib_Obj = New-Object PSObject
		$Contrib_Obj | Add-Member NoteProperty -Name "Link" -Value $Current_Page_Links	
		$Contrib_Array += $Contrib_Obj	
	}

$Number_of_contributions = ($parse_profile.ParsedHtml.body.getElementsByClassName("browseBreadcrumb") | select -expand textContent).split(" ")[0]
for ($i = 0; $i -lt $Number_of_contributions;)
{ 
ForEach($Contrib in $Contrib_Array.link)
	{
			$i++
			$Percent_Progress = [math]::Round($i / $Number_of_contributions * 100)
			Write-Progress -Activity "Backup Technet Gallery contributions" -status "Contribution $i / $Number_of_contributions - $Percent_Progress %"
					
			$Contrib_Sring = [string]$Contrib
			$Contrib_To_Get = $Basic_Technet_Link + $Contrib_Sring.split(':')[1]
			$Parse_Contrib_Link = Invoke-WebRequest -Uri $Contrib_To_Get | select *
					
			$Parse_Contrib_Body = $Parse_Contrib_Link.ParsedHtml.body
			$Get_Contrib_Title_NoFormat = ($Parse_Contrib_Body.getElementsByClassName("projectTitle")) |  select -expand innertext
			$Get_Contrib_Summary = ($Parse_Contrib_Body.getElementsByClassName("projectSummary")) |  select -expand innerHTML
			$Get_Contrib_Summary_HTML = ($Parse_Contrib_Body.getElementsByClassName("projectSummary")) |  select -expand outerHTML

            $Get_Lastupdate = ((($Parse_Contrib_Body.getElementsByClassName("section").item(3)) | select -expand textContent)  -split "License")[0]
            
            #Get username from link
            $username_link = $Parse_Contrib_Body.getElementsByClassName("unified-baseball-card") | select -expand outerHTML
            $pattern = 'f\%5B0\%5D\.Value=(.*?)","text":'
            $User_Name_Complete = [regex]::Match($username_link,$pattern).Groups[1].Value
            $User_Name = $User_Name_Complete.Replace("%20"," ")	

			$Get_Contrib_Link = $Parse_Contrib_Body.getElementsByClassName("button") | select -expand pathname
			$Get_Contrib_Download_File = $Parse_Contrib_Body.getElementsByClassName("button") | select -expand textContent -ErrorAction silentlycontinue
					
			$full_link = "$Basic_Technet_Link/$Get_Contrib_Link"
					
			$Get_Contrib_Title = ($Get_Contrib_Title_NoFormat -Replace'[\/:*?"<>|()]'," ").replace("]","").replace(" ","_")
					
			write-host ""
			write-host "Working on the contribution $Get_Contrib_Title" -foreground "cyan"
					
			$Contrib_Folder = "$Backup_output_Folder\$Get_Contrib_Title" 				
					
			New-Item $Contrib_Folder -Type Directory -Force | out-null

			write-host "Folder $Contrib_Folder has been created" 
						
			$Contrib_File_Summary = "$Contrib_Folder\Summary.txt"
			$User_Name + "`r`n" + $Get_Lastupdate + "`r`n" + $Get_Contrib_Summary | out-file $Contrib_File_Summary				
					
			$Contrib_File_Summary_HTML = "$Contrib_Folder\Summary_HTML.txt"
			$Get_Contrib_Summary_HTML | out-file $Contrib_File_Summary_HTML				
			write-host "A summary.txt file has been created in the folder with the description of the contribution."

			If($Get_Contrib_Download_File -ne $null)
				{
					Invoke-WebRequest -Uri $full_link -OutFile "$Contrib_Folder\$Get_Contrib_Download_File"		
					write-host "The file $Get_Contrib_Download_File has been downloaded in the folder"
				}
			Else
				{
					write-host "There is no uploaded file to backup"			
				}

            #Get Long Description and PowerShell script if it is in description rather than a downloadable file
            $Description_To_Get = $Contrib_To_Get + "/description"
            $Parse_Description_Link = Invoke-WebRequest -Uri $Description_To_Get | select *
					
			$Parse_Description_Body = $Parse_Description_Link.ParsedHtml.body
            $Get_LongDescription_Text = $Parse_Description_Body |  select -expand outerText
			$Get_PowerShell_Script = ($Parse_Description_Body.getElementsByClassName("powershell")) |  select -expand outerText
            
            $Get_LongDescription_Text | out-file "$Contrib_Folder\LongDescription.txt"

			If($null -ne $Get_PowerShell_Script)
				{
					$Get_PowerShell_Script | out-file "$Contrib_Folder\PowerShell.ps1"	
					write-host "PowerShell.ps1 has been created in the folder"
				}
			Else
				{
					write-host "There is no PowerShell on project page"			
				}
			
	}
}

#Update the folder create and change dates to match the projects last updated date
$createdfolders = Get-ChildItem -Path $Backup_output_Folder -Directory

foreach($folder in $createdfolders)
{
    try{
    $summaryfile = Get-Content -Path "$($folder.FullName)\Summary.txt"
    $updateDate = Get-date ($summaryfile[1] -split " ")[1]
    $folder.CreationTime = $updateDate
    $folder.LastWriteTime = $updateDate
    }
    catch {}
}

