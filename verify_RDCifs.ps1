
#This user needs full Admin rights on the target boxes
$UserName = "DOMAIN\test.user"

function get-currentdirectory {
    $thisName = $MyInvocation.MyCommand.Name
    [IO.Path]::GetDirectoryName((Get-Content function:$thisName).File)
}

function log ($color, $string ) {
    #if ($color -eq $null) { $color = "Black" }
    #if (Test-Path ".\logs") {} else { new-item ".\logs" -type directory | out-null }
    Write-Host "$(Get-Date -format 's') - $($string)" -ForegroundColor $color
    #"$(Get-Date -format 's') - $($string)" | Out-File .\logs\$(Get-Date -Format dd-MM-yyyy).log -Append -Encoding ASCII 
}


cls

Function Test-PSRemoting($computer, $credential)
{
	try
	{
		#Enter-PSSession -ComputerName $computer -Credential $credential -ErrorAction Stop | Out-Null
		
		Invoke-Command -Credential $credential -ComputerName $computer -ErrorAction Stop -ScriptBlock {}
		return $true
	}
	catch 
	{
		return $false
	}

}
Function Copy-ItemUNC($SourcePath, $TargetPath, $FileName)
{
   New-PSDrive -Name source -PSProvider FileSystem -Root $SourcePath | Out-Null
   New-PSDrive -Name target -PSProvider FileSystem -Root $TargetPath | Out-Null
   
   foreach($name in $FileName)
   {
   	Copy-Item -Path source:\$name -Destination target:
   }
   Remove-PSDrive source
   Remove-PSDrive target
}

$cwd = get-currentdirectory

$CSVName = get-childitem $cwd | Where-Object {$_.Name -like "*installRDCifs.csv"} | Select-Object -First 1
$CSVLocation = Join-Path $cwd $CSVName

if (!( test-path $CSVLocation ))
{
	log -color "Red" -string "FATAL: Unable to find installRDCifs.csv to read. Path '$($CSVLocation)' doesn't seem valid."
	Break
}
else
{
	log -color "DarkBlue" -string "Found installRDCifs.csv to deploy at read  '$($CSVLocation)'."

}

$machineList = import-csv $CSVLocation
$credential = Get-Credential -Message "enter password" -UserName $UserName


foreach ($computer in $machineList)
{
	if ($computer.State -eq "Enable")
	{

		log -color Blue -string $computer.HostName
		
		if (!(Test-PSRemoting $computer.HostName $credential))
		{
			log -color Red -string "PSRemoting not enabled on $($computer.HostName)"
			continue
		}
		
		$destinationFolder =  '\\' + $computer.HostName + '\C$\Program Files\Dell\Rapid CIFS'

		if (!(Test-Path -path $destinationFolder))
		{
			log -color Red -string "$($destinationFolder) Test Fail" 
			continue
		}
	
		$files = 'rdcifsctl.exe','rdcifsfd.cat','rdcifsfd.inf','rdcifsfd.sys'
		
		foreach($name in $files)
		{
		   	if (!(Test-Path -path (Join-Path -Path $destinationFolder -ChildPath $name) ))
			{
				log -color Red -string "$($name) Test Fail" 
				continue
			}
		}
	

		Invoke-Command -Verbose -Credential $credential -ComputerName $computer.HostName -ScriptBlock {
			$pinfo = New-Object System.Diagnostics.ProcessStartInfo
			$pinfo.FileName = "c:\Program Files\Dell\Rapid CIFS\rdcifsctl.exe "
			$pinfo.Arguments = " stats -s"
			$pinfo.RedirectStandardError = $true
			$pinfo.RedirectStandardOutput = $true
			$pinfo.UseShellExecute = $false
			$p = New-Object System.Diagnostics.Process
			$p.StartInfo = $pinfo
			$p.Start() | Out-Null
			$p.WaitForExit()
			$output = $p.StandardOutput.ReadToEnd()
			$output += $p.StandardError.ReadToEnd()
			$output
		}
		

	}

}