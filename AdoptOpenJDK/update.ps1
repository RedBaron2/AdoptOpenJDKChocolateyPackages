import-module au

$PreUrl = 'https://github.com'

function global:au_BeforeUpdate {
    Get-RemoteFiles -Purge -FileNameBase "$($Latest.PackageName)"
    Remove-Item ".\tools\*.zip" -Force # Removal of downloaded files
}

function global:au_SearchReplace {
    @{
        ".\tools\packageArgs.ps1" = @{
            "(?i)(^\s*PackageName\s*=\s*)('.*')"    = "`$1'$($Latest.PackageName)'"
            "(?i)(^\s*url\s*=\s*)('.*')"            = "`$1'$($Latest.URL32)'"
            "(?i)(^\s*url64bit\s*=\s*)('.*')"       = "`$1'$($Latest.URL64)'"
            "(?i)(^\s*Checksum\s*=\s*)('.*')"       = "`$1'$($Latest.Checksum32)'"
            "(?i)(^\s*ChecksumType\s*=\s*)('.*')"   = "`$1'$($Latest.ChecksumType32)'"
            "(?i)(^\s*Checksum64\s*=\s*)('.*')"     = "`$1'$($Latest.Checksum64)'"
            "(?i)(^\s*ChecksumType64\s*=\s*)('.*')" = "`$1'$($Latest.ChecksumType64)'"
        }
        ".\adoptopenjdk.nuspec"   = @{
            "(?i)(^\s*\<id\>).*(\<\/id\>)"       = "`${1}$($($Latest.PackageName).ToLower())`${2}"
            "(?i)(^\s*\<title\>).*(\<\/title\>)" = "`${1}$($Latest.Title)`${2}"
            "(?i)(^\s*\<licenseUrl\>).*(\<\/licenseUrl\>)" = "`${1}$($Latest.LicenseUrl)`${2}"
        }
    }
}

function Get-AdoptOpenJDK {
    param (
        [string]$number, # java version
        [string]$type = 'jre', # jdk or jre
        [string]$build = 'releases', # nightly for pre-releases
        [string]$jvm = 'hotspot', # hotspot or openj9
        [string]$dev_name            # orginal package name
    )

    $regex_1 = "(\d{4}\-\d{2}\-\d{2}\-\d{2}\-\d{2})"
    $regex_2 = "(OpenJDK(\d{1,2}U|\d{1,2}\.\d\.)\-(jdk|jre)_x(64|86\-32)_([wndois]+)_([htosp]+|[openj9]+))_|(_[openj9]+\-.*)|(\.zip)"
    $releases = "https://api.adoptopenjdk.net/v2/info/${build}/openjdk${number}?openjdk_impl=${jvm}&os=windows&arch=x32&arch=x64&release=latest&type=${type}"
    $t = try { 
        (Invoke-WebRequest -Uri $releases -ErrorAction Stop -UseBasicParsing).BaseResponse
    }
    catch [System.Net.WebException] { Write-Verbose "An exception was caught: $($_.Exception.Message)"; $_.Exception.Response }
    if ( $t.StatusCode -eq "OK" ) {    
        $download_page = Invoke-WebRequest -Uri $releases -UseBasicParsing | ConvertFrom-Json
        $urls = $download_page.binaries.binary_link | where { $_ -match "x64|x86" } | select -Last 6

        $url32 = $urls | where { $_ -match "x86" } | select -Last 1

        $url64 = $urls | where { $_ -match "x64" } | select -Last 1
    
    }
    else { Write-Verbose "this is a bad request"; break; }

    if ($build -eq "nightly") {
        $fN = ($download_page.binaries.binary_name | Select -First 1 )
        $version = ( $fN -split "$regex_1" | select -Last 2 | Select -First 1 )
    }
    else {
        if ($number -eq 8) {
            $name = ( $download_page.binaries.binary_name ) | Select -First 1
            $name = ( $name ) -replace (".zip", '')
            $fN = ( $name )
            if ( $jvm -eq 'openj9' ) {
                $version = (( $fN -split "$regex_2" ) )
                $version = ( $version | Select -Last 3 )
                $version = $version -replace ("(_[openj9]+(_|\-.*))", '')
                $version = ( $version ) -replace ("(`r`n\s)", 'G') | Select -First 1
            }
            else {
                $version = (( $fN -split "$regex_2" ) | Select -Last 1 )
            }
            $version = $version -replace ('[u]', '.0.') -replace ('(b)', '.')
        }
        if (( $number -eq 9 ) -or ( $number -eq 10 ) -or ( $number -eq 11 ) -or ( $number -eq 12 )) {
            $version = if ($url64 -ne $null) { ( Get-Version (($url64) -replace ('%2B', '.')) ) }
        }
    }

    $version = $version -replace ("\-", "."); if ($version -ne $null) { $version = ( Get-Version "${version}" ) }

    $JavaVM = @{$true = "${type}${number}"; $false = "${type}${number}-${jvm}" }[ ( $jvm -match "hotspot" ) ]
    $beta = @{$true = "${version}"; $false = "${version}-${build}" }[ ( $build -eq "releases" ) ]
    $PackageName = @{$true = "AdoptOpenJDK-${JavaVM}"; $false = "${dev_name}" }[ ( $dev_name -eq "" ) ]

    #build stream hashtable return
    $hotspot = @{ }
    if ($url32 -ne $null) { $hotspot.Add( 'URL32', $url32 ) }
    if ($url64 -ne $null) { $hotspot.Add( 'URL64', $url64 ) }
    if ($version -ne $null) {
        $hotspot.Add( 'Version', "$beta" )
        $hotspot.Add( 'Title', "AdoptOpenJDK ${type}${number} ${jvm} ${version}" )
        $hotspot.Add( 'PackageName', "${PackageName}" )
        $hotspot.Add( 'LicenseUrl', "https://github.com/AdoptOpenJDK/openjdk-jdk${number}u/blob/master/LICENSE" )
    }

    return ( $hotspot )
}


function global:au_GetLatest {
    $type = 0; $vm = 0; $build = 0; $numbers = @("8", "9", "10", "11", "12"); $types = @("jre", "jdk")
    # Optionally add "nightly" to $builds
    $jvms = @("hotspot", "openj9"); $builds = @("releases")

    $streams = [ordered] @{ }
    # First
    foreach ( $number in $numbers ) {

        if ( $number -eq 12 ) { $name = "AdoptOpenJDK$($types[$type])" } elseif (( $number -eq 8 ) -or ( $number -eq 11 )) { $name = "AdoptOpenJDK${number}$($types[$type])" } else { $name = ""; }

        $streams.Add( "$($types[$type])${number}_$($jvms[$vm])_$($builds[$build])" , ( Get-AdoptOpenJDK -number $number -type "$($types[$type])" -jvm "$($jvms[$vm])" -build "$($builds[$build])" -dev_name "${name}" ) )

    }
    $build++; $name = ""
    # Second
    foreach ( $number in $numbers ) {

        $streams.Add( "$($types[$type])${number}_$($jvms[$vm])_$($builds[$build])" , ( Get-AdoptOpenJDK -number $number -type "$($types[$type])" -jvm "$($jvms[$vm])" -build "$($builds[$build])" -dev_name "${name}" ) )

    }
    $vm++; $build--; $name = ""
    # Third
    foreach ( $number in $numbers ) {

        if ( $number -eq 12 ) { $name = "AdoptOpenJDK$($jvms[$vm])$($types[$type])" } else { $name = ""; }

        $streams.Add( "$($types[$type])${number}_$($jvms[$vm])_$($builds[$build])" , ( Get-AdoptOpenJDK -number $number -type "$($types[$type])" -jvm "$($jvms[$vm])" -build "$($builds[$build])" -dev_name "${name}" ) )
    }
    $build++; $name = ""
    # Fourth
    foreach ( $number in $numbers ) {

        $streams.Add( "$($types[$type])${number}_$($jvms[$vm])_$($builds[$build])" , ( Get-AdoptOpenJDK -number $number -type "$($types[$type])" -jvm "$($jvms[$vm])" -build "$($builds[$build])" -dev_name "${name}" ) )

    }
    $type++; $vm--; $build--; $name = ""
    # Fifth
    foreach ( $number in $numbers ) {

        if ( $number -eq 12 ) { $name = "AdoptOpenJDK" } elseif (( $number -eq 8 ) -or ( $number -eq 11 )) { $name = "AdoptOpenJDK${number}" } else { $name = ""; }
        $streams.Add( "$($types[$type])${number}_$($jvms[$vm])_$($builds[$build])" , ( Get-AdoptOpenJDK -number $number -type "$($types[$type])" -jvm "$($jvms[$vm])" -build "$($builds[$build])" -dev_name "${name}" ) )

    }
    $vm++; $name = ""
    # Sixth
    foreach ( $number in $numbers ) {

        if ( $number -eq 12 ) { $name = "AdoptOpenJDK$($jvms[$vm])$($types[$type])" } else { $name = ""; }

        $streams.Add( "$($types[$type])${number}_$($jvms[$vm])_$($builds[$build])" , ( Get-AdoptOpenJDK -number $number -type "$($types[$type])" -jvm "$($jvms[$vm])" -build "$($builds[$build])" -dev_name "${name}" ) )

    }
    $build++; $name = ""
    # Seventh
    foreach ( $number in $numbers ) {

        $streams.Add( "$($types[$type])${number}_$($jvms[$vm])_$($builds[$build])" , ( Get-AdoptOpenJDK -number $number -type "$($types[$type])" -jvm "$($jvms[$vm])" -build "$($builds[$build])" -dev_name "${name}" ) )

    }
    $vm--; $name = ""
    # Eighth
    foreach ( $number in $numbers ) {

        $streams.Add( "$($types[$type])${number}_$($jvms[$vm])_$($builds[$build])" , ( Get-AdoptOpenJDK -number $number -type "$($types[$type])" -jvm "$($jvms[$vm])" -build "$($builds[$build])" -dev_name "${name}" ) )

    }

    return @{ Streams = $streams }
 
}

update -ChecksumFor none
