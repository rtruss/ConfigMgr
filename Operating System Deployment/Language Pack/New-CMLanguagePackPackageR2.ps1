 <#
.SYNOPSIS
    Create Language Pack packages in ConfigMgr.

.DESCRIPTION
    This script will create Language Pack packages from a mounted Windows Language Pack ISO media in ConfigMgr.
    It works with Windows 10 version 1607 and forward.

.PARAMETER SiteServer
    Site server where the SMS Provider is installed.

.PARAMETER ISORootPath
    Root of the mounted Windows Language Pack ISO, e.g. F:\.

.PARAMETER PackageSourcePath
    Root path for where the Language Pack package source files will be stored.

.PARAMETER LanguagePacks
    Specify the Language Pack ID's that should be created as Packages.

.PARAMETER LanguagePackArchitecture
    Specify the Language Pack architecture. Used for creating sub-folders in the package source location and within the Language Pack package name replacing %3, e.g. Language Pack - %1 %2 %3

.PARAMETER PackageName
    This string will be included within the automatically generated package name at location %1, e.g. Language Pack - %1 %2 %3

.PARAMETER WindowsVersion
    Specify the targeted Windows version, e.g. 1709. Used for creating sub-folders in the package source location and when replacing location %2 for the Language Pack package name, e.g. Language Pack - %1 %2 %3.

.PARAMETER WindowsBuildnumber
    Specify the targeted Windows build number, e.g. 16299. Used as the Version property of the Language Pack package object.

.EXAMPLE
    .\New-CMLanguagePackPackage.ps1 -SiteServer "BCFDLCMSAPPP01" -ISORootPath "F:\" -PackageSourcePath "\\brunswick.com\ent\Apps\SCCM\OSD\OperatingSystems\WIN10\LanguagePacks" -LanguagePacks "de-DE","en-GB","es-ES","es-MX","fr-CA","fr-FR","hu-HU","it-IT","ja-JP","ko-KR","nl-NL","pt-BR","zh-CN","zh-TW" -LanguagePackArchitecture "x64" -PackageName "Windows 10" -WindowsVersion "1803" -WindowsBuildnumber "17134"

.NOTES
    FileName:    New-CMLanguagePackPackage.ps1
    Author:      Nickolaj Andersen
    Contact:     @NickolajA
    Created:     2017-10-30
    Updated:     2018-05-07
    
    Version history:
    1.0.0 - (2017-10-30) Script created
    1.0.1 - (2018-05-07) Script Updated [roger.truss@brunswick.com] to include
        A description based off the variables and msft naming for lps. (Start at line 163.)
            https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/available-language-packs-for-windows
        Creates and move the LPs to the $WindowsVersion specific package folder (Lines 223-235)
#>
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [parameter(Mandatory=$true, HelpMessage="Site server where the SMS Provider is installed.")]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({Test-Connection -ComputerName $_ -Count 1 -Quiet})]
    [string]$SiteServer,

    [parameter(Mandatory=$true, HelpMessage="Root of the mounted Windows Language Pack ISO, e.g. F:\.")]
    [ValidateNotNullOrEmpty()]
    [string]$ISORootPath,

    [parameter(Mandatory=$true, HelpMessage="Root path for where the Language Pack package source files will be stored.")]
    [ValidateNotNullOrEmpty()]
    [string]$PackageSourcePath,

    [parameter(Mandatory=$false, HelpMessage="Specify the Language Pack ID's that should be created as Packages.")]
    [ValidateNotNullOrEmpty()]
    [ValidateSet("ar-sa", "bg-bg", "cs-cz", "da-dk", "de-de", "el-gr", "en-gb", "en-us", "es-es", "es-mx", "et-ee", "fi-fi", "fr-ca", "fr-fr", "he-il", "hr-hr", "hu-hu", "it-it", "ja-jp", "ko-kr", "lt-lt", "lv-lv", "nb-no", "nl-nl", "pl-pl", "pt-br", "pt-pt", "ro-ro", "ru-ru", "sk-sk", "sl-si", "sr-latn-rs", "sv-se", "th-th", "tr-tr", "uk-ua", "zh-cn", "zh-tw")]
    [string[]]$LanguagePacks = ("ar-sa", "bg-bg", "cs-cz", "da-dk", "de-de", "el-gr", "en-gb", "en-us", "es-es", "es-mx", "et-ee", "fi-fi", "fr-ca", "fr-fr", "he-il", "hr-hr", "hu-hu", "it-it", "ja-jp", "ko-kr", "lt-lt", "lv-lv", "nb-no", "nl-nl", "pl-pl", "pt-br", "pt-pt", "ro-ro", "ru-ru", "sk-sk", "sl-si", "sr-latn-rs", "sv-se", "th-th", "tr-tr", "uk-ua", "zh-cn", "zh-tw"),

    [parameter(Mandatory=$true, HelpMessage="Specify the Language Pack architecture. Used for creating sub-folders in the package source location and within the Language Pack package name replacing %3, e.g. Language Pack - %1 %2 %3.")]
    [ValidateNotNullOrEmpty()]
    [ValidateSet("x64", "x86")]
    [string[]]$LanguagePackArchitecture = ("x64", "x86"),

    [parameter(Mandatory=$true, HelpMessage="This string will be included within the automatically generated package name at location %1, e.g. Language Pack - %1 %2 %3.")]
    [ValidateNotNullOrEmpty()]
    [string]$PackageName,

    [parameter(Mandatory=$true, HelpMessage="Specify the targeted Windows version, e.g. 1709. Used for creating sub-folders in the package source location and when replacing location %2 for the Language Pack package name, e.g. Language Pack - %1 %2 %3.")]
    [ValidateNotNullOrEmpty()]
    [ValidateLength(1,4)]
    [string]$WindowsVersion,

    [parameter(Mandatory=$true, HelpMessage="Specify the targeted Windows build number, e.g. 16299. Used as the Version property of the Language Pack package object.")]
    [ValidateNotNullOrEmpty()]
    [ValidateLength(1,5)]
    [string]$WindowsBuildnumber
)
Begin {
    # Determine SiteCode from WMI
    try {
        Write-Verbose -Message "Determining Site Code for Site server: '$($SiteServer)'"
        $SiteCodeObjects = Get-WmiObject -Namespace "root\SMS" -Class SMS_ProviderLocation -ComputerName $SiteServer -ErrorAction Stop
        foreach ($SiteCodeObject in $SiteCodeObjects) {
            if ($SiteCodeObject.ProviderForLocalSite -eq $true) {
                $SiteCode = $SiteCodeObject.SiteCode
                Write-Verbose -Message "Site Code: $($SiteCode)"
            }
        }
    }
    catch [System.UnauthorizedAccessException] {
        Write-Warning -Message "Access denied" ; break
    }
    catch [System.Exception] {
        Write-Warning -Message "Unable to determine Site Code" ; break
    }

    # Load ConfigMgr module
    try {
        $SiteDrive = $SiteCode + ":"
        Import-Module -Name (Join-Path -Path (($env:SMS_ADMIN_UI_PATH).Substring(0, $env:SMS_ADMIN_UI_PATH.Length-5)) -ChildPath "\ConfigurationManager.psd1") -Force -ErrorAction Stop -Verbose:$false
        if ((Get-PSDrive -Name $SiteCode -ErrorAction SilentlyContinue | Measure-Object).Count -ne 1) {
            New-PSDrive -Name $SiteCode -PSProvider "AdminUI.PS.Provider\CMSite" -Root $SiteServer -ErrorAction Stop -Verbose:$false | Out-Null
        }
    }
    catch [System.UnauthorizedAccessException] {
        Write-Warning -Message "Access denied" ; break
    }
    catch {
        Write-Warning -Message "$($_.Exception.Message). Line: $($_.InvocationInfo.ScriptLineNumber)" ; break
    }

    # Determine current location
    $CurrentLocation = $PSScriptRoot

    # Disable Fast parameter usage check for Lazy properties
    $CMPSSuppressFastNotUsedCheck = $true
}
Process {
    # Process each specified language pack architecture
    foreach ($Architecture in $LanguagePackArchitecture) {
        # Hash-table for Language Packs and determine the path to the current architecture
        $LanguagePackTable = @{}
        $ArchitecturePath = Join-Path -Path $ISORootPath -ChildPath $Architecture

        # Process each language pack file and add to hash-table for matching
        Write-Verbose -Message "Enumerating eligible Language Packs from media for architecture: $($Architecture)"
        foreach ($LanguagePackObject in (Get-ChildItem -Path $ArchitecturePath -Recurse -Filter "*.cab" | Where-Object { $_.Name -match $Architecture -and $_.Name -notmatch "Interface" })) {
            $LanguagePackID = $LanguagePackObject -replace "Microsoft-Windows-Client-Language-Pack_$($Architecture)_", "" -replace ".cab", ""
            $LanguagePackTable.Add($LanguagePackID, $LanguagePackObject)
        }

        try {
            # Create Windows version and architecture sub-folders
            $SubFolderPath = Join-Path -Path $PackageSourcePath -ChildPath ($WindowsVersion + "\" + $Architecture)
            if (-not(Test-Path -Path $SubFolderPath)) {
                Write-Verbose -Message "Creating folder: $($SubFolderPath)"
                New-Item -Path $SubFolderPath -ItemType Directory -Force -ErrorAction Stop -Verbose:$false | Out-Null
            }
        }
        catch [System.Exception] {
            Write-Warning -Message "Unable to create sub-folders. Error message: $($_.Exception.Message)" ; break
        }

        # Match each given language pack ID from parameter input with language packs in hash-table
        foreach ($LanguagePack in $LanguagePacks) {
            try {
                # Create language pack specific sub-folder
                $LanguagePackSubFolder = Join-Path -Path $SubFolderPath -ChildPath $LanguagePack
                if (-not(Test-Path -Path $LanguagePackSubFolder)) {
                    Write-Verbose -Message "Creating folder: $($LanguagePackSubFolder)"
                    New-Item -Path $LanguagePackSubFolder -ItemType Directory -Force -ErrorAction Stop -Verbose:$false | Out-Null
					switch -CaseSensitive ($LanguagePack) {
                        "ar-SA" {$LPDescription = "Arabic (Saudi Arabia) Language Pack for $PackageName $LanguagePackArchitecture (Release $WindowsVersion Build $WindowsBuildnumber)"}
                        "bg-BG" {$LPDescription = "Bulgarian (Bulgaria) Language Pack for $PackageName $LanguagePackArchitecture (Release $WindowsVersion Build $WindowsBuildnumber)"}
                        "zh-CN" {$LPDescription = "Chinese (PRC) Language Pack for $PackageName $LanguagePackArchitecture (Release $WindowsVersion Build $WindowsBuildnumber)"}
                        "zh-TW" {$LPDescription = "Chinese (Taiwan) Language Pack for $PackageName $LanguagePackArchitecture (Release $WindowsVersion Build $WindowsBuildnumber)"}
                        "hr-HR" {$LPDescription = "Croatian (Croatia) Language Pack for $PackageName $LanguagePackArchitecture (Release $WindowsVersion Build $WindowsBuildnumber)"}
                        "cs-CZ" {$LPDescription = "Czech (Czech Republic) Language Pack for $PackageName $LanguagePackArchitecture (Release $WindowsVersion Build $WindowsBuildnumber)"}
                        "da-DK" {$LPDescription = "Danish (Denmark) Language Pack for $PackageName $LanguagePackArchitecture (Release $WindowsVersion Build $WindowsBuildnumber)"}
                        "nl-NL" {$LPDescription = "Dutch (Netherlands) Language Pack for $PackageName $LanguagePackArchitecture (Release $WindowsVersion Build $WindowsBuildnumber)"}
                        "en-US" {$LPDescription = "English (United States) Language Pack for $PackageName $LanguagePackArchitecture (Release $WindowsVersion Build $WindowsBuildnumber)"}
                        "en-GB" {$LPDescription = "English (United Kingdom) Language Pack for $PackageName $LanguagePackArchitecture (Release $WindowsVersion Build $WindowsBuildnumber)"}
                        "et-EE" {$LPDescription = "Estonian (Estonia) Language Pack for $PackageName $LanguagePackArchitecture (Release $WindowsVersion Build $WindowsBuildnumber)"}
                        "fi-FI" {$LPDescription = "Finnish (Finland) Language Pack for $PackageName $LanguagePackArchitecture (Release $WindowsVersion Build $WindowsBuildnumber)"}
                        "fr-CA" {$LPDescription = "French (Canada) Language Pack for $PackageName $LanguagePackArchitecture (Release $WindowsVersion Build $WindowsBuildnumber)"}
                        "fr-FR" {$LPDescription = "French (France) Language Pack for $PackageName $LanguagePackArchitecture (Release $WindowsVersion Build $WindowsBuildnumber)"}
                        "de-DE" {$LPDescription = "German (Germany) Language Pack for $PackageName $LanguagePackArchitecture (Release $WindowsVersion Build $WindowsBuildnumber)"}
                        "el-GR" {$LPDescription = "Greek (Greece) Language Pack for $PackageName $LanguagePackArchitecture (Release $WindowsVersion Build $WindowsBuildnumber)"}
                        "he-IL" {$LPDescription = "Hebrew (Israel) Language Pack for $PackageName $LanguagePackArchitecture (Release $WindowsVersion Build $WindowsBuildnumber)"}
                        "hu-HU" {$LPDescription = "Hungarian (Hungary) Language Pack for $PackageName $LanguagePackArchitecture (Release $WindowsVersion Build $WindowsBuildnumber)"}
                        "it-IT" {$LPDescription = "Italian (Italy) Language Pack for $PackageName $LanguagePackArchitecture (Release $WindowsVersion Build $WindowsBuildnumber)"}
                        "ja-JP" {$LPDescription = "Japanese (Japan) Language Pack for $PackageName $LanguagePackArchitecture (Release $WindowsVersion Build $WindowsBuildnumber)"}
                        "ko-KR" {$LPDescription = "Korean (Korea) Language Pack for $PackageName $LanguagePackArchitecture (Release $WindowsVersion Build $WindowsBuildnumber)"}
                        "lv-LV" {$LPDescription = "Latvian (Latvia) Language Pack for $PackageName $LanguagePackArchitecture (Release $WindowsVersion Build $WindowsBuildnumber)"}
                        "lt-LT" {$LPDescription = "Lithuanian (Lithuania) Language Pack for $PackageName $LanguagePackArchitecture (Release $WindowsVersion Build $WindowsBuildnumber)"}
                        "nb-NO" {$LPDescription = "Norwegian, Bokmål (Norway) Language Pack for $PackageName $LanguagePackArchitecture (Release $WindowsVersion Build $WindowsBuildnumber)"}
                        "pl-PL" {$LPDescription = "Polish (Poland) Language Pack for $PackageName $LanguagePackArchitecture (Release $WindowsVersion Build $WindowsBuildnumber)"}
                        "pt-BR" {$LPDescription = "Portuguese (Brazil) Language Pack for $PackageName $LanguagePackArchitecture (Release $WindowsVersion Build $WindowsBuildnumber)"}
                        "pt-PT" {$LPDescription = "Portuguese (Portugal) Language Pack for $PackageName $LanguagePackArchitecture (Release $WindowsVersion Build $WindowsBuildnumber)"}
                        "ro-RO" {$LPDescription = "Romanian (Romania) Language Pack for $PackageName $LanguagePackArchitecture (Release $WindowsVersion Build $WindowsBuildnumber)"}
                        "ru-RU" {$LPDescription = "Russian (Russia) Language Pack for $PackageName $LanguagePackArchitecture (Release $WindowsVersion Build $WindowsBuildnumber)"}
                        "sr-Latn-RS" {$LPDescription = "Serbian (Latin, Serbia) Language Pack for $PackageName $LanguagePackArchitecture (Release $WindowsVersion Build $WindowsBuildnumber)"}
                        "sk-SK" {$LPDescription = "Slovak (Slovakia) Language Pack for $PackageName $LanguagePackArchitecture (Release $WindowsVersion Build $WindowsBuildnumber)"}
                        "sl-SI" {$LPDescription = "Slovenian (Slovenia) Language Pack for $PackageName $LanguagePackArchitecture (Release $WindowsVersion Build $WindowsBuildnumber)"}
                        "es-MX" {$LPDescription = "Spanish (Mexico) Language Pack for $PackageName $LanguagePackArchitecture (Release $WindowsVersion Build $WindowsBuildnumber)"}
                        "es-ES" {$LPDescription = "Spanish (Spain) Language Pack for $PackageName $LanguagePackArchitecture (Release $WindowsVersion Build $WindowsBuildnumber)"}
                        "sv-SE" {$LPDescription = "Swedish (Sweden) Language Pack for $PackageName $LanguagePackArchitecture (Release $WindowsVersion Build $WindowsBuildnumber)"}
                        "th-TH" {$LPDescription = "Thai (Thailand) Language Pack for $PackageName $LanguagePackArchitecture (Release $WindowsVersion Build $WindowsBuildnumber)"}
                        "tr-TR" {$LPDescription = "Turkish (Turkey) Language Pack for $PackageName $LanguagePackArchitecture (Release $WindowsVersion Build $WindowsBuildnumber)"}
                        "uk-UA" {$LPDescription = "Ukrainian (Ukraine) Language Pack for $PackageName $LanguagePackArchitecture (Release $WindowsVersion Build $WindowsBuildnumber)"}
                    } 
                }

            }
            catch [System.Exception] {
                Write-Warning -Message "Unable to create Language Pack sub-folder. Error message: $($_.Exception.Message)" ; break
            }            

            try {
                # Copy language pack files to content lilbrary source location
                Write-Verbose -Message "Copying file $($LanguagePackTable[$LanguagePack].Name) to: $($LanguagePackSubFolder)"
                Copy-Item -LiteralPath $LanguagePackTable[$LanguagePack].FullName -Destination $LanguagePackSubFolder -ErrorAction Stop -Verbose:$false
            }
            catch [System.Exception] {
                Write-Warning -Message "Unable to copy Language Pack file. Error message: $($_.Exception.Message)" ; break
            }

            try {
                # Set location to Configuration Manager drive
                Set-Location -Path $SiteDrive -ErrorAction Stop -Verbose:$false

                $NewPath = $SiteCode + ":" + "\Package\OSD" 
                if ((Test-Path -Path $NewPath) -eq $false) {New-Item -Path $NewPath}
                $NewLPPath = $NewPath + "\Language Packs"
                if ((Test-Path -Path $NewLPPath) -eq $false) {New-Item -Path $NewLPPath}
                $NewLPVerPath = $NewLPPath + "\" + $WindowsVersion
                if ((Test-Path -Path ($NewLPVerPath)) -eq $false) {New-Item -Path $NewLPVerPath}
                Set-Location -Path $NewLPVerPath

                # Create Language Pack package
                $LanguagePackPackageName = -join@("Language Pack - ", $PackageName, " ", $WindowsVersion, " ", $Architecture)
                Write-Verbose -Message "Creating Language Pack package: $($LanguagePackPackageName)"
                $LanguagePackPackage = New-CMPackage -Name $LanguagePackPackageName -Description $LPDescription -Language $LanguagePack -Version $WindowsBuildnumber -Path $LanguagePackSubFolder -ErrorAction Stop -Verbose:$false
                Move-CMObject -FolderPath $NewLPVerPath -ObjectID $LanguagePackPackage.PackageID
                
                # Set location to script home
                Set-Location -Path $PSScriptRoot
            }
            catch [System.Exception] {
                Write-Warning -Message "Unable to create Language Pack package. Error message: $($_.Exception.Message)" ; break
            }
        }
    }
} 
