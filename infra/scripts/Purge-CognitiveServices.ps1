# Purges the deleted the Azure Cognitive Service instance.
Param(
    [string]
    [Parameter(Mandatory=$false)]
    $ApiVersion = "2021-10-01",

    [switch]
    [Parameter(Mandatory=$false)]
    $Help
)

function Show-Usage {
    Write-Output "    This permanently deletes the Azure Cognitive Service instance

    Usage: $(Split-Path $MyInvocation.ScriptName -Leaf) ``
            [-ApiVersion <API version>] ``

            [-Help]

    Options:
        -ApiVersion     REST API version. Default is `2021-10-01`.

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

# List soft-deleted Azure Cognitive Service instances
function List-DeletedCognitiveServices {
    param (
        [string] $ApiVersion
    )

    $account = $(az account show | ConvertFrom-Json)

    $url = "https://management.azure.com/subscriptions/$($account.id)/providers/Microsoft.CognitiveServices/deletedAccounts?api-version=$($ApiVersion)"

    # Uncomment to debug
    # $url

    $options = ""

    $aoais = $(az rest -m get -u $url --query "value" | ConvertFrom-Json)
    if ($aoais -eq $null) {
        $options = "All soft-deleted Azure Cognitive Service instances purged or no such instance found to purge"
        $returnValue = @{ aoais = $aoais; options = $options }
        return $returnValue
    }

    if ($aoais.Count -eq 1) {
        $name = $aoais.name
        $options += "    1: $name `n"
    } else {
        $aoais | ForEach-Object {
            $i = $aoais.IndexOf($_)
            $name = $_.name
            $options += "    $($i +1): $name `n"
        }
    }
    $options += "    a: Purge all`n"
    $options += "    q: Quit`n"

    $returnValue = @{ aoais = $aoais; options = $options }
    return $returnValue
}

# Purge all soft-deleted Azure Cognitive Service instances at once.
function Purge-AllDeletedCognitiveServices {
    param (
        [string] $ApiVersion,
        [object[]] $Instances
    )

    Process {
        $Instances | ForEach-Object {
            Write-Output "Purging $($_.name) ..."

            $url = "https://management.azure.com$($_.id)?api-version=$($ApiVersion)"
    
            $aoai = $(az rest -m get -u $url)
            if ($aoai -ne $null) {
                $deleted = $(az rest -m delete -u $url)
            }

            Write-Output "... $($_.name) purged"
        }

        Write-Output "All soft-deleted Azure Cognitive Service instances purged"
    }
}

# Purge soft-deleted Azure Cognitive Service instances
function Purge-DeletedCognitiveServices {
    param (
        [string] $ApiVersion
    )

    $continue = $true
    $result = List-DeletedCognitiveServices -ApiVersion $ApiVersion
    if ($result.aoais -eq $null) {
        $continue = $false
    }

    while ($continue -eq $true) {
        $options = $result.options

        $input = Read-Host "Select the number to purge the soft-deleted Azure Cognitive Service instance, 'a' to purge all or 'q' to quit: `n`n$options"
        if ($input -eq "q") {
            $continue = $false
            break
        }

        if ($input -eq "a") {
            Purge-AllDeletedCognitiveServices -ApiVersion $ApiVersion -Instances $result.aoais
            break
        }

        $parsed = $input -as [int]
        if ($parsed -eq $null) {
            Write-Output "Invalid input"
            $continue = $false
            break
        }

        $aoais = $result.aoais
        if ($parsed -gt $aoais.Count) {
            Write-Output "Invalid input"
            $continue = $false
            break
        }

        $index = $parsed - 1

        $url = "https://management.azure.com$($aoais[$index].id)?api-version=$($ApiVersion)"

        # Uncomment to debug
        # $url

        $apim = $(az rest -m get -u $url)
        if ($apim -ne $null) {
            $deleted = $(az rest -m delete -u $url)
        }

        $result = List-DeletedCognitiveServices -ApiVersion $ApiVersion
        if ($result.aoais -eq $null) {
            $continue = $false
        }
    }

    if ($continue -eq $false) {
        return $result.options
    }
}

Purge-DeletedCognitiveServices -ApiVersion $ApiVersion
