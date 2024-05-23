# Purges the deleted the API Management instance.
Param(
    [string]
    [Parameter(Mandatory=$false)]
    $ApiVersion = "2021-08-01",

    [switch]
    [Parameter(Mandatory=$false)]
    $Help
)

function Show-Usage {
    Write-Output "    This permanently deletes the API Management instance

    Usage: $(Split-Path $MyInvocation.ScriptName -Leaf) ``
            [-ApiVersion <API version>] ``

            [-Help]

    Options:
        -ApiVersion     REST API version. Default is `2021-08-01`.

        -Help:          Show this message.
"

    Exit 0
}

# Show usage
$needHelp = $Help -eq $true
if ($needHelp -eq $true) {
    Show-Usage
    Exit 0
}

# List soft-deleted API Management instances
function List-DeletedAPIMs {
    param (
        [string] $ApiVersion
    )

    $account = $(az account show | ConvertFrom-Json)

    $url = "https://management.azure.com/subscriptions/$($account.id)/providers/Microsoft.ApiManagement/deletedservices?api-version=$($ApiVersion)"

    # Uncomment to debug
    # $url

    $options = ""

    $apims = $(az rest -m get -u $url --query "value" | ConvertFrom-Json)
    if ($apims -eq $null) {
        $options = "All soft-deleted API Management instances purged or no such instance found to purge"
        $returnValue = @{ apims = $apims; options = $options }
        return $returnValue
    }

    if ($apims.Count -eq 1) {
        $name = $apims.name
        $options += "    1: $name `n"
    } else {
        $apims | ForEach-Object {
            $i = $apims.IndexOf($_)
            $name = $_.name
            $options += "    $($i +1): $name `n"
        }
    }
    $options += "    a: Purge all`n"
    $options += "    q: Quit`n"

    $returnValue = @{ apims = $apims; options = $options }
    return $returnValue
}

# Purge all soft-deleted API Management instances at once.
function Purge-AllDeletedAPIMs {
    param (
        [string] $ApiVersion,
        [object[]] $Instances
    )

    Process {
        $Instances | ForEach-Object {
            Write-Output "Purging $($_.name) ..."

            $url = "https://management.azure.com$($_.id)?api-version=$($ApiVersion)"
    
            $apim = $(az rest -m get -u $url)
            if ($apim -ne $null) {
                $deleted = $(az rest -m delete -u $url)
            }

            Write-Output "... $($_.name) purged"
        }

        Write-Output "All soft-deleted API Management instances purged"
    }
}


# Purge soft-deleted API Management instances
function Purge-DeletedAPIMs {
    param (
        [string] $ApiVersion
    )

    $continue = $true
    $result = List-DeletedAPIMs -ApiVersion $ApiVersion
    if ($result.apims -eq $null) {
        $continue = $false
    }

    while ($continue -eq $true) {
        $options = $result.options

        $input = Read-Host "Select the number to purge the soft-deleted API Management instance, 'a' to purge all or 'q' to quit: `n`n$options"
        if ($input -eq "q") {
            $continue = $false
            break
        }

        if ($input -eq "a") {
            Purge-AllDeletedAPIMs -ApiVersion $ApiVersion -Instances $result.apims
            break
        }

        $parsed = $input -as [int]
        if ($parsed -eq $null) {
            Write-Output "Invalid input"
            $continue = $false
            break
        }

        $apims = $result.apims
        if ($parsed -gt $apims.Count) {
            Write-Output "Invalid input"
            $continue = $false
            break
        }

        $index = $parsed - 1

        $url = "https://management.azure.com$($apims[$index].id)?api-version=$($ApiVersion)"

        # Uncomment to debug
        # $url

        $apim = $(az rest -m get -u $url)
        if ($apim -ne $null) {
            $deleted = $(az rest -m delete -u $url)
        }

        $result = List-DeletedAPIMs -ApiVersion $ApiVersion
        if ($result.apims -eq $null) {
            $continue = $false
        }
    }

    if ($continue -eq $false) {
        return $result.options
    }
}

Purge-DeletedAPIMs -ApiVersion $ApiVersion
