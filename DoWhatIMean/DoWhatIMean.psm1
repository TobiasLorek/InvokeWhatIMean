# A global variable to store the API key securely
$script:DoWhatIMeanAPIKey = $null

# A global variable to store the function information
$script:DoWhatIMeanFunctions = @{}

function Set-DoWhatIMeanAPIKey {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$APIKey
    )
    
    # Convert the provided API key to secure string and store it in global scope
    $script:DoWhatIMeanAPIKey = $APIKey
}

function Set-DoWhatIMeanFunctions {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string[]]$FunctionList
    )
    
    # Replace the current list with the provided FunctionInfo objects or strings
    $script:DoWhatIMeanFunctions = $FunctionList.Clone()
    foreach ($func in $FunctionList) {
        $script:DoWhatIMeanFunctions[$func] = Get-FunctionMetadata $func
    }
}

function Invoke-DoWhatIMean {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Input
        [Parameter(Mandatory = $false)]
        [string[]]$FunctionsToUse
    )
    if ($FunctionsToUse) {
        $functions = $FunctionsToUse |% {Get-FunctionMetadata $_}
    }
    else {
        $functions = $script:DoWhatIMeanFunctions
    }
    $response = Invoke-OpenAICall $input $functions
    Invoke-SelectedTool response.choices[0].message.tool_calls $function
}

function Get-FunctionMetadata {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$FunctionName
    )

    # Get the function or cmdlet details
    $functionDetails = Get-Command $FunctionName -ErrorAction SilentlyContinue

    if ($functionDetails -eq $null) {
        Write-Error "Function or cmdlet '$FunctionName' not found."
        return
    }

    # Start building the JSON representation
    $functionMetadata = @{
        type = "function"
        function = @{
            name = $FunctionName
            description = ""
            parameters = @{
                type = "object"
                properties = @{}
                required = @()
            }
        }
    }

    # Attempt to get the help description of the function/cmdlet
    $help = Get-Help $FunctionName -ErrorAction SilentlyContinue

    if ($help.Description -ne $null) {
        $functionMetadata.function.description = $help.Description.Text
    }

    # Adding parameters info
    foreach ($param in $functionDetails.Parameters.parameter) {
        $parameterDetails = @{
            name = $parameterName
        }
        $props = @(
            "name", "description", "defaultValue", "type", "required"
        )
        foreach ($prop in $props) {
            if ($param.$prop) {
                $paramDetails.$prop = $param.$prop
            }

        }
    }
}

function Invoke-OpenAICall {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Input
        [Parameter(Mandatory = $true)]
        [hashtable[]]$tools
    )

    # Ensure that the API key has been set
    if (-not $script:DoWhatIMeanAPIKey) {
        throw "API key has not been set. Use Set-DoWhatIMeanAPIKey to set the API key first."
    }

    # Convert the secure API key back to plaintext
    $OpenAI_API_Key = $script:DoWhatIMeanAPIKey

    # Prepare the body of the POST request
    $body = @{
        "model" = "gpt-3.5-turbo"
        "messages" = @(
            @{
                "role" = "user"
                "content" = $Input
            }
        )
        "tools" = $tools
        "tool_choise" = "auto"

    } | ConvertTo-Json -Depth 20 -Compress

    # Prepare the header with content type and authorization
    $headers = @{
        "Content-Type" = "application/json"
        "Authorization" = "Bearer $OpenAI_API_Key"
    }

    # Make the POST request to OpenAI endpoint
    try {
        $response = Invoke-RestMethod -Uri 'https://api.openai.com/v1/chat/completions' -Method 'POST' -Headers $headers -Body $body
        Write-Output $response
    }
    catch {
        Write-Error "Failed to invoke OpenAI API: $_"
    }
}

<#
.SYNOPSIS
Invokes a set of predefined tools/functions based on the input object.

.DESCRIPTION
The Invoke-SelectedTool function takes a PSCustomObject parameter that represents an array of tool call definitions.
Each tool call includes an ID, a type, and details of the function to be called.
For each entry, it will dynamically invoke the specified function with the arguments provided.

.PARAMETER toolCalls
A PSCustomObject that holds an array of tool call information with function names and their arguments.

.EXAMPLE
$jsonInput = @"
{
  "tool_calls": [
    {
      "id": "call_abc123",
      "type": "function",
      "function": {
        "name": "get_current_weather",
        "arguments": "{\\"location\\": \\"Boston, MA\\"}"
      }
    }
  ]
}
"@

$toolCalls = ConvertFrom-Json -InputObject $jsonInput

Invoke-SelectedTool -toolCalls $toolCalls.tool_calls

This example will invoke the get_current_weather function with the argument location set to "Boston, MA".

#>
function Invoke-SelectedTool {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$toolCalls
    )

    # Process each tool call in the input object
    foreach ($call in $toolCalls) {
        # Check if the type of call is a 'function' before proceeding
        if ($call.type -eq 'function') {
            $functionName = $call.function.name
            $jsonArguments = $call.function.arguments | ConvertFrom-Json

            # Prepare an argument hashtable for splatting
            $argumentList = @{}
            foreach ($key in $jsonArguments.PSObject.Properties.Name) {
                $argumentList[$key] = $jsonArguments.$key
            }

            # Dynamically invoke the function with the arguments
            try {
                & $functionName @argumentList
            }
            catch {
                Write-Error "An error occurred while invoking function '$functionName': $_"
            }
        }
    }
}

# Export the functions so they are available to users of the module
Export-ModuleMember -Function Set-DoWhatIMeanAPIKey, Set-DoWhatIMeanFunctions, Invoke-DoWhatIMean
