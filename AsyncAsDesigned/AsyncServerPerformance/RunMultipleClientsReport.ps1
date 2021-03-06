# Gather data for Report
# Run repeatedly with a different number of clients each time and record the times



function startProcess ($dir, $cmdArgs) {
 $ProcessInfo = New-Object System.Diagnostics.ProcessStartInfo
 $ProcessInfo.FileName = "dotnet"
 $ProcessInfo.WorkingDirectory = (Resolve-Path -Path $dir)
 $ProcessInfo.Arguments = $cmdArgs
 $ProcessInfo.UseShellExecute = $False
 $ProcessInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
 $newProcess = [System.Diagnostics.Process]::Start($ProcessInfo)
 $newProcess.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::RealTime
 $newProcess
}

#Set the working directory to the location of the script
$path = $MyInvocation.MyCommand.Path
$dir = Split-Path $path
Push-Location $dir
[Environment]::CurrentDirectory = $PWD


#dotnet build --project .\AsyncAsDesigned.PerfClient\AsyncAsDesigned.PerfClient.csproj --"configuration Debug"


Stop-Process -Name "dotnet" -ErrorAction SilentlyContinue


  
(startProcess -dir "AsyncAsDesigned.PerfDataServer" -cmdArgs "build", "--configuration Release").WaitForExit();
(startProcess -dir "AsyncAsDesigned.PerfClient" -cmdArgs "build", "--configuration Release").WaitForExit();
(startProcess -dir "AsyncAsDesigned.PerfAppServer" -cmdArgs "build", "--configuration Release").WaitForExit();


$count = 0;
$processes = @();

while($true){

    $syncGuid = New-Guid;
    $asyncGuid = New-Guid;

    for($num = 2; $num -le 20; $num = $num + 2){

        $processes = @();
    
        For($i=1; $i -le $num; $i++)
        {
            $processes += startProcess -dir .\AsyncAsDesigned.PerfClient -cmdArgs "run", "--configuration Release", "--no-build", "25", "$i", "$syncGuid"
            Start-Sleep -Milliseconds 25
            $processes += startProcess -dir .\AsyncAsDesigned.PerfDataServer -cmdArgs "run", "--configuration Release", "--no-build", "$i", "$syncGuid"
            Start-Sleep -Milliseconds 25
        }

        # Wait for everything to startup (Probably unneccessary)
        Start-Sleep 1

        $appProcess = startProcess -dir .\AsyncAsDesigned.PerfAppServer -cmdArgs "run", "--configuration Release", "--no-build", "sync", "$num", "$syncGuid"
        $success = $appProcess.WaitForExit(600000);

        foreach($b in $processes){ $success = $success -and $b.WaitForExit(1000); }

        if(!$success)
        {
            Write-Output "App Process Timeout $num";
            Stop-Process -Name "dotnet" -ErrorAction SilentlyContinue
            Add-Content ".\Results.txt" "Failure $num"
        }

        Write-Output "$num sync is done"

        # Wait for everything to startup (Probably unneccessary)
        Start-Sleep 2

        $processes = @();

        For($i=1; $i -le $num; $i++)
        {
            $processes += startProcess -dir .\AsyncAsDesigned.PerfClient -cmdArgs "run", "--configuration Release", "--no-build", "25", "$i", "$asyncGuid"
            Start-Sleep -Milliseconds 25
            $processes += startProcess -dir .\AsyncAsDesigned.PerfDataServer -cmdArgs "run", "--configuration Release", "--no-build", "$i", "$asyncGuid"
            Start-Sleep -Milliseconds 25
        }

        # Wait for everything to startup (Probably unneccessary)
        Start-Sleep 1

        $appProcess = startProcess -dir .\AsyncAsDesigned.PerfAppServer -cmdArgs "run", "--configuration Release", "--no-build", "async", "$num", "$asyncGuid"
        $success = $appProcess.WaitForExit(600000);

        foreach($b in $processes){ $success = $success -and $b.WaitForExit(1000); }

        if(!$success)
        {
            Write-Output "App Process Timeout $num";
            Stop-Process -Name "dotnet" -ErrorAction SilentlyContinue
            Add-Content ".\Results.txt" "Failure $num"
        }


        Write-Output "$num async is done"

        # Wait for everything to startup (Probably unneccessary)
        Start-Sleep 2
        

    }

    $count++;

    Write-Output "Full Set is done $count"

}


