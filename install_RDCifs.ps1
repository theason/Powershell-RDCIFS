
#This user needs full Admin rights on the target boxes
$UserName = "DOMAIN\test.user"

##The extracted files from the MSI should be here:
$msifile = "\\path\to\msi\DellRapidCIFS-3.2.0713.2a\"

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

		$destinationFolder =  '\\' + $computer.HostName + '\C$\ProgramData\Dell\DR\Log'

		if (!(Test-Path -path $destinationFolder))
		{
			New-Item $destinationFolder -Type Directory | Out-Null
		}
		
		$destinationFolder =  '\\' + $computer.HostName + '\C$\Program Files\Dell\Rapid CIFS'

		if (!(Test-Path -path $destinationFolder))
		{
			New-Item $destinationFolder -Type Directory | Out-Null
		}
		
		$files = 'rdcifsctl.exe','rdcifsfd.cat','rdcifsfd.inf','rdcifsfd.sys'
		
		Copy-ItemUNC -SourcePath $msifile -TargetPath $destinationFolder -FileName $files


		Invoke-Command -Credential $credential -ComputerName $computer.HostName -ScriptBlock {
		

			$property = "NumberOfLogicalProcessors"
			$cpuCount = Get-WmiObject -class win32_processor -Property  $property | Select-Object -Property $property -First 1
			if ($cpuCount.NumberOfLogicalProcessors -ge 2)
			{
				Write-Host "Machine has $($cpuCount.NumberOfLogicalProcessors) processors"
				$registryServicePath = "HKLM:\SYSTEM\CurrentControlSet\Services\rdcifsfd"
				$registryParamPath = "HKLM:\SYSTEM\CurrentControlSet\Services\rdcifsfd\Parameters"
				$registryLogKey = "LogPath"
				
				If (!(Test-Path $registryServicePath))
				{
					New-Item -Path $registryServicePath -Force  | Out-Null
				}
				
				If (!(Test-Path $registryParamPath))
				{
					New-Item -Path $registryParamPath -Force  | Out-Null
				}		
				
				New-ItemProperty -Path $registryParamPath -Name $registryLogKey -Value "C:\ProgramData\Dell\DR\Log" -PropertyType STRING -Force | Out-Null
				
				$filepath = "C:\Program Files\Dell\Rapid CIFS\rdcifsfd.inf"

				Start-Process -verbose -file "C:\Windows\System32\rundll32.exe" -ArgumentList " setupapi,InstallHinfSection DefaultInstall 128 $($filepath)"  -Wait

				
				$pinfo = New-Object System.Diagnostics.ProcessStartInfo
				$pinfo.FileName = "c:\Program Files\Dell\Rapid CIFS\rdcifsctl.exe "
				$pinfo.Arguments = "driver -e"
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
			else
			{
				Write-Host "Less than 2 CPU's skipping..."
			}
		
		}
		
	}


}