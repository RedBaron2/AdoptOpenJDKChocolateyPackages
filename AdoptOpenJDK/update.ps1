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
    }

    return ( $hotspot )
}


function global:au_GetLatest {
    $i = 8; $x = 0; $y = 0; $z = 0; $numbers = @("8", "9", "10", "11", "12"); $types = @("jre", "jdk")
    # Optionally add "nightly" to $builds
    $jvms = @("hotspot", "openj9"); $builds = @("releases")

    $streams = [ordered] @{ }
    # First
    foreach ( $j in $numbers ) {

        if ( $j -eq 12 ) { $name = "AdoptOpenJDK$($types[$x])" } elseif (( $j -eq 8 ) -or ( $j -eq 11 )) { $name = "AdoptOpenJDK${j}$($types[$x])" } else { $name = ""; }

        $streams.Add( "$($types[$x])${j}_$($jvms[$y])_$($builds[$z])" , ( Get-AdoptOpenJDK -number $j -type "$($types[$x])" -jvm "$($jvms[$y])" -build "$($builds[$z])" -dev_name "${name}" ) )

    }
    $z++; $i--; $name = ""
    # Second
    foreach ( $j in $numbers ) {

        $streams.Add( "$($types[$x])${j}_$($jvms[$y])_$($builds[$z])" , ( Get-AdoptOpenJDK -number $j -type "$($types[$x])" -jvm "$($jvms[$y])" -build "$($builds[$z])" -dev_name "${name}" ) )

    }
    $y++; $z--; $i--; $name = ""
    # Third
    foreach ( $j in $numbers ) {

        if ( $j -eq 12 ) { $name = "AdoptOpenJDK$($jvms[$y])$($types[$x])" } else { $name = ""; }

        $streams.Add( "$($types[$x])${j}_$($jvms[$y])_$($builds[$z])" , ( Get-AdoptOpenJDK -number $j -type "$($types[$x])" -jvm "$($jvms[$y])" -build "$($builds[$z])" -dev_name "${name}" ) )
    }
    $z++; $i--; $name = ""
    # Fourth
    foreach ( $j in $numbers ) {

        $streams.Add( "$($types[$x])${j}_$($jvms[$y])_$($builds[$z])" , ( Get-AdoptOpenJDK -number $j -type "$($types[$x])" -jvm "$($jvms[$y])" -build "$($builds[$z])" -dev_name "${name}" ) )

    }
    $x++; $y--; $z--; $i--; $name = ""
    # Fifth
    foreach ( $j in $numbers ) {

        if ( $j -eq 12 ) { $name = "AdoptOpenJDK" } elseif (( $j -eq 8 ) -or ( $j -eq 11 )) { $name = "AdoptOpenJDK${j}" } else { $name = ""; }
        $streams.Add( "$($types[$x])${j}_$($jvms[$y])_$($builds[$z])" , ( Get-AdoptOpenJDK -number $j -type "$($types[$x])" -jvm "$($jvms[$y])" -build "$($builds[$z])" -dev_name "${name}" ) )

    }
    $y++; $i--; $name = ""
    # Sixth
    foreach ( $j in $numbers ) {

        if ( $j -eq 12 ) { $name = "AdoptOpenJDK$($jvms[$y])$($types[$x])" } else { $name = ""; }

        $streams.Add( "$($types[$x])${j}_$($jvms[$y])_$($builds[$z])" , ( Get-AdoptOpenJDK -number $j -type "$($types[$x])" -jvm "$($jvms[$y])" -build "$($builds[$z])" -dev_name "${name}" ) )

    }
    $z++; $i--; $name = ""
    # Seventh
    foreach ( $j in $numbers ) {

        $streams.Add( "$($types[$x])${j}_$($jvms[$y])_$($builds[$z])" , ( Get-AdoptOpenJDK -number $j -type "$($types[$x])" -jvm "$($jvms[$y])" -build "$($builds[$z])" -dev_name "${name}" ) )

    }
    $y--; $i--; $name = ""
    # Eighth
    foreach ( $j in $numbers ) {

        $streams.Add( "$($types[$x])${j}_$($jvms[$y])_$($builds[$z])" , ( Get-AdoptOpenJDK -number $j -type "$($types[$x])" -jvm "$($jvms[$y])" -build "$($builds[$z])" -dev_name "${name}" ) )

    }

    return @{ Streams = $streams }
 
}

update -ChecksumFor none