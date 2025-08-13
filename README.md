# PowerShellNugetPackagesUpdate
A PowerShell script to update NuGet packages to the latest compatible version. 

The script tries to update to the latest available version. If it's not compatible with TargetFramework, then it updates to the latest available minor version. 

## Usage

```powershell
.\Update-NuGetPackages.ps1
```

If we want to update *.csproj from a specific folder, then we can execute below command. 
```powershell
.\Update-NuGetPackages.ps1 -Path "C:\Projects\MyApp"
```
