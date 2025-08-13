<#
.SYNOPSIS
    Updates NuGet packages in .csproj files to their latest versions.

.DESCRIPTION
    This script scans for .csproj files in the specified directory (or current directory if not specified),
    identifies outdated NuGet packages referenced in those projects, and updates them to the latest versions.
    If updating to the latest version fails, it attempts to update to the highest compatible minor version.

.PARAMETER Path
    The directory path to scan for .csproj files. Defaults to the current directory (".")

.EXAMPLE
    .\Update-NuGetPackages.ps1
    Scans the current directory for .csproj files and updates packages

.EXAMPLE
    .\Update-NuGetPackages.ps1 -Path "C:\Projects\MyApp"
    Scans the specified directory for .csproj files and updates packages

.NOTES
    Author: Shreyas Jejurkar
    Requires: .NET SDK with dotnet CLI tools
    Date: 2025-08-13
#>
param(
    [string]$Path = "."
)

# Helper function to parse dotnet list output
function ConvertFrom-DotnetListOutput {
    param(
        [string]$JsonOutput
    )
    $packages = @{}
    if ($JsonOutput) {
        $json = $JsonOutput | Out-String | ConvertFrom-Json
        if ($json.projects) {
            foreach ($project in $json.projects) {
                if ($project.frameworks) {
                    foreach ($framework in $project.frameworks) {
                        if ($framework.topLevelPackages) {
                            foreach ($package in $framework.topLevelPackages) {
                                if ($package.latestVersion) {
                                    $packages[$package.id] = $package.latestVersion
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    return $packages
}

# Function to update outdated packages in a csproj file
function Update-OutdatedPackages {
    param(
        [string]$CsprojPath
    )

    Write-Host ("Processing {0}" -f $CsprojPath) -ForegroundColor Cyan

    try {
        # Validate that the file exists
        if (-not (Test-Path $CsprojPath)) {
            Write-Warning ("Csproj file not found: {0}" -f $CsprojPath)
            return
        }

        # Get target framework
        $xml = [xml](Get-Content $CsprojPath)
        if (-not $xml.Project) {
            Write-Warning ("Invalid .csproj file structure in {0}" -f $CsprojPath)
            return
        }
        
        $targetFramework = $xml.Project.PropertyGroup.TargetFramework
        if (-not $targetFramework) {
            Write-Warning ("No TargetFramework found in {0}" -f $CsprojPath)
            return
        }
        
        Write-Host ("Target Framework: {0}" -f $targetFramework) -ForegroundColor Cyan

        # Get latest and highest-minor package versions
        $latestListOutput = dotnet list $CsprojPath package --outdated --format json --framework $targetFramework 2>$null
        $highestMinorListOutput = dotnet list $CsprojPath package --outdated --highest-minor --format json --framework $targetFramework 2>$null

        $latestPackages = ConvertFrom-DotnetListOutput -JsonOutput $latestListOutput
        $highestMinorPackages = ConvertFrom-DotnetListOutput -JsonOutput $highestMinorListOutput

        if ($latestPackages.Count -eq 0) {
            Write-Host "No outdated packages found or all packages are up to date" -ForegroundColor Green
            return
        }

        $updatedCount = 0
        foreach ($packageName in $latestPackages.Keys) {
            $latestVersion = $latestPackages[$packageName]
            Write-Host ("Attempting to update {0} to {1}" -f $packageName, $latestVersion) -ForegroundColor Cyan
            dotnet add $CsprojPath package $packageName -v $latestVersion 2>$null

            if (-not $?) {
                Write-Warning ("Failed to update {0} to version {1}. Trying highest minor version." -f $packageName, $latestVersion)
                
                if ($highestMinorPackages.ContainsKey($packageName)) {
                    $highestMinorVersion = $highestMinorPackages[$packageName]
                    Write-Host ("Updating {0} to highest minor version {1}" -f $packageName, $highestMinorVersion) -ForegroundColor Green
                    dotnet add $CsprojPath package $packageName -v $highestMinorVersion
                    $updatedCount++
                }
                else {
                    Write-Error ("Could not find a compatible highest minor version for {0}" -f $packageName)
                }
            }
            else {
                Write-Host ("Successfully updated {0} to {1}" -f $packageName, $latestVersion) -ForegroundColor Green
                $updatedCount++
            }
        }

        if ($updatedCount -eq 0) {
            Write-Host "No packages were updated in {0}" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Error ("Error processing {0}: {1}" -f $CsprojPath, $_.Exception.Message)
    }
}

# Main script execution
Write-Host ("Scanning for .csproj files in {0}" -f $Path) -ForegroundColor Cyan

# Validate the path
if (-not (Test-Path $Path)) {
    Write-Error ("Specified path not found: {0}" -f $Path)
    return
}

$csprojFiles = Get-ChildItem -Path $Path -Recurse -Filter "*.csproj" -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notlike "*obj*" -and $_.FullName -notlike "*bin*" }

if (-not $csprojFiles) {
    Write-Warning "No .csproj files found in $Path"
    return
}

Write-Host ("Found {0} .csproj file(s)" -f $csprojFiles.Count) -ForegroundColor Cyan

foreach ($csprojFile in $csprojFiles) {
    Update-OutdatedPackages -CsprojPath $csprojFile.FullName
}

Write-Host "Package update process completed." -ForegroundColor Green
