function Start-LimitedCpuScript {
    param (
        [string]$ScriptPath,
        [int]$CpuLimit
    )

    # Define constants
    $JOB_OBJECT_LIMIT_CPU_RATE_CONTROL = 0x00000020
    $JOB_OBJECT_CPU_RATE_CONTROL_ENABLE = 0x1
    $JOB_OBJECT_CPU_RATE_CONTROL_HARD_CAP = 0x4
    $JOB_OBJECT_LIMIT_SILENT_BREAKAWAY_OK = 0x00001000
    $JOB_OBJECT_LIMIT_BREAKAWAY_OK = 0x00000800

    # Import necessary Windows API functions
    Add-Type @"
    using System;
    using System.Runtime.InteropServices;

    public class JobObject
    {
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
        public static extern IntPtr CreateJobObject(IntPtr lpJobAttributes, string lpName);

        [DllImport("kernel32.dll")]
        public static extern bool SetInformationJobObject(IntPtr hJob, int JobObjectInfoClass, IntPtr lpJobObjectInfo, uint cbJobObjectInfoLength);

        [DllImport("kernel32.dll")]
        public static extern bool AssignProcessToJobObject(IntPtr hJob, IntPtr hProcess);

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern IntPtr OpenProcess(uint dwDesiredAccess, bool bInheritHandle, int dwProcessId);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool CloseHandle(IntPtr hObject);

        [DllImport("kernel32.dll")]
        public static extern uint GetLastError();
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct JOBOBJECT_BASIC_LIMIT_INFORMATION
    {
        public long PerProcessUserTimeLimit;
        public long PerJobUserTimeLimit;
        public uint LimitFlags;
        public IntPtr MinimumWorkingSetSize;
        public IntPtr MaximumWorkingSetSize;
        public uint ActiveProcessLimit;
        public long Affinity;
        public uint PriorityClass;
        public uint SchedulingClass;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct IO_COUNTERS
    {
        public ulong ReadOperationCount;
        public ulong WriteOperationCount;
        public ulong OtherOperationCount;
        public ulong ReadTransferCount;
        public ulong WriteTransferCount;
        public ulong OtherTransferCount;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct JOBOBJECT_EXTENDED_LIMIT_INFORMATION
    {
        public JOBOBJECT_BASIC_LIMIT_INFORMATION BasicLimitInformation;
        public IO_COUNTERS IoInfo;
        public IntPtr ProcessMemoryLimit;
        public IntPtr JobMemoryLimit;
        public IntPtr PeakProcessMemoryUsed;
        public IntPtr PeakJobMemoryUsed;
    }
"@

    # Create a Job Object
    $jobHandle = [JobObject]::CreateJobObject([IntPtr]::Zero, "MyJobObject")

    # Define the JOB_OBJECT_CPU_RATE_CONTROL_INFORMATION structure
    $cpuRateControlInfo = New-Object PSObject -Property @{
        ControlFlags = $JOB_OBJECT_CPU_RATE_CONTROL_ENABLE -bor $JOB_OBJECT_CPU_RATE_CONTROL_HARD_CAP
        CpuRate = $CpuLimit * 100 # CPU rate in 100ths of a percent
    }

    $cpuRateControlInfoBytes = [System.BitConverter]::GetBytes($cpuRateControlInfo.ControlFlags) + [System.BitConverter]::GetBytes($cpuRateControlInfo.CpuRate)
    $ptrCpuRateControlInfo = [System.Runtime.InteropServices.Marshal]::AllocHGlobal($cpuRateControlInfoBytes.Length)
    [System.Runtime.InteropServices.Marshal]::Copy($cpuRateControlInfoBytes, 0, $ptrCpuRateControlInfo, $cpuRateControlInfoBytes.Length)
    [JobObject]::SetInformationJobObject($jobHandle, 15, $ptrCpuRateControlInfo, [uint32]$cpuRateControlInfoBytes.Length)
    [System.Runtime.InteropServices.Marshal]::FreeHGlobal($ptrCpuRateControlInfo)

    # Define the JOB_OBJECT_EXTENDED_LIMIT_INFORMATION structure
    $extendedLimitInfo = New-Object ([JOBOBJECT_EXTENDED_LIMIT_INFORMATION])
    $extendedLimitInfo.BasicLimitInformation.LimitFlags = $JOB_OBJECT_LIMIT_SILENT_BREAKAWAY_OK -bor $JOB_OBJECT_LIMIT_BREAKAWAY_OK -bor $JOB_OBJECT_LIMIT_CPU_RATE_CONTROL

    $extendedLimitInfoBytes = [System.BitConverter]::GetBytes($extendedLimitInfo.BasicLimitInformation.LimitFlags)
    $ptrExtendedLimitInfo = [System.Runtime.InteropServices.Marshal]::AllocHGlobal($extendedLimitInfoBytes.Length)
    [System.Runtime.InteropServices.Marshal]::Copy($extendedLimitInfoBytes, 0, $ptrExtendedLimitInfo, $extendedLimitInfoBytes.Length)
    [JobObject]::SetInformationJobObject($jobHandle, 9, $ptrExtendedLimitInfo, [uint32]$extendedLimitInfoBytes.Length)
    [System.Runtime.InteropServices.Marshal]::FreeHGlobal($ptrExtendedLimitInfo)

    # Start the specified PowerShell script
    $process = Start-Process -FilePath "powershell.exe" -ArgumentList "-File `"$ScriptPath`"" -PassThru

    # Get the process handle
    $processHandle = [JobObject]::OpenProcess(0x1F0FFF, $false, $process.Id)

    # Associate the process with the Job Object
    [JobObject]::AssignProcessToJobObject($jobHandle, $processHandle)

    # Close the process handle
    [JobObject]::CloseHandle($processHandle)

    Write-Output "CPU throttling has been applied to the script and its child processes."

    # Wait for the script to finish
    $process.WaitForExit()
}

# Usage example:
# Start-LimitedCpuScript -ScriptPath "C:\path\to\your\script.ps1" -CpuLimit 10
Start-LimitedCpuScript -ScriptPath "C:\k\debug\collect-windows-logs.ps1 -collectMinidumpOnly" -CpuLimit 5