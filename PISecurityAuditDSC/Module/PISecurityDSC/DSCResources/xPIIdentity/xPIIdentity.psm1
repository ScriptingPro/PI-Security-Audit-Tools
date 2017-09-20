function Get-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param
    (
        [parameter(Mandatory = $true)]
        [System.String]
        $PIDataArchive,

        [parameter(Mandatory = $true)]
        [System.String]
        $Name
    )

    Write-Verbose "Connecting to: $($PIDataArchive)"
    $Connection = Connect-PIDataArchive -PIDataArchiveMachineName $PIDataArchive
	Write-Verbose "Getting PI Identity: $($Name)"
    $PIIdentity = Get-PIIdentity -Connection $Connection -Name $Name  
    if($null -eq $PIIdentity)
    { $Ensure = "Absent" }
    else
    { Write-Verbose -Message "Name: $($Name). Enabled: $($PIIdentity.IsEnabled)." }
    return @{
                CanDelete = $PIIdentity.CanDelete
                IsEnabled = $PIIdentity.IsEnabled
                PIDataArchive = $PIDataArchive
                Ensure = $Ensure
                AllowUseInTrusts = $PIIdentity.AllowTrusts
                Name = $Name
                AllowExplicitLogin = $PIIdentity.AllowExplicitLogin
                AllowUseInMappings = $PIIdentity.AllowMappings
            }

    <# return @{
                CanDelete = [System.Boolean]
                IsEnabled = [System.Boolean]
                PIDataArchive = [System.String]
                Ensure = [System.String]
                AllowUseInTrusts = [System.Boolean]
                Name = [System.String]
                AllowExplicitLogin = [System.Boolean]
                AllowUseInMappings = [System.Boolean]
                } #>
}


function Set-TargetResource
{
    [CmdletBinding()]
    param
    (
        [System.Boolean]
        $CanDelete=$true,

        [System.Boolean]
        $IsEnabled=$true,

        [parameter(Mandatory = $true)]
        [System.String]
        $PIDataArchive,

        [ValidateSet("Present","Absent")]
        [System.String]
        $Ensure="Present",

        [System.Boolean]
        $AllowUseInTrusts=$true,

        [parameter(Mandatory = $true)]
        [System.String]
        $Name,

        [System.Boolean]
        $AllowExplicitLogin=$false,

        [System.Boolean]
        $AllowUseInMappings=$true
    )

    # Remove items from explicit parameter list which won't be specified when performing the write operation.
    @('Ensure','PIDataArchive','AllowExplicitLogin') | Foreach-Object { $null = $PSBoundParameters.Remove($_) }

    # Connect and get the resource
    $Connection = Connect-PIDataArchive -PIDataArchiveMachineName $PIDataArchive
    $PIIdentity = Get-TargetResource -Name $Name -PIDataArchive $PIDataArchive
    
    # If the resource is supposed to be present we will either add it or set it.
    if($Ensure -eq 'Present')
    {  
        # Load all function parameters.
        $ParametersToKeep = $MyInvocation.MyCommand.Parameters
        
        # Remove the parameters explicitly specified or not used for the write operation.
        $ParametersToChange = @('Ensure', 'PIDataArchive')
        $ParametersToChange += $PSBoundParameters.Keys
        $ParametersToChange | Foreach-Object { $null = $ParametersToKeep.Remove($_) }

        # Set the parameter values we want to keep to the current resource values.
        Foreach($Parameter in $ParametersToKeep.Keys)
        { 
            Set-Variable -Name $Parameter -Value $($PIIdentity.$Parameter) -Scope Local 
        }

        # Perform the set operation to correct the resource.
        if($PIIdentity.Ensure -eq "Present")
        {
            Write-Verbose "Setting PI Identity $($Name)"
            Set-PIIdentity -Connection $Connection -Name $Name `
                                -CanDelete:$CanDelete -Enabled:$IsEnabled `
                                -AllowUseInMappings:$AllowUseInMappings -AllowUseInTrusts:$AllowUseInTrusts `
                                -AllowExplicitLogin:$AllowExplicitLogin
        }
        else
        {
            # Add a new identity.
            Write-Verbose "Adding PI Identity $($Name)"          
            Add-PIIdentity -Connection $Connection -Name $Name `
                                -DisallowDelete:$(!$CanDelete) -Disabled:$(!$IsEnabled) `
                                -DisallowUseInMappings:$(!$AllowUseInMappings) -DisallowUseInTrusts:$(!$AllowUseInTrusts)
        }
    }
    # If the resource is supposed to be absent we remove it.
    else
    {
        Write-Verbose "Removing PI Identity $($Name)"
        Remove-PIIdentity -Connection $Connection -Name $Name   
    }
}


function Test-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [System.Boolean]
        $CanDelete,

        [System.Boolean]
        $IsEnabled,

        [parameter(Mandatory = $true)]
        [System.String]
        $PIDataArchive,

        [ValidateSet("Present","Absent")]
        [System.String]
        $Ensure,

        [System.Boolean]
        $AllowUseInTrusts,

        [parameter(Mandatory = $true)]
        [System.String]
        $Name,

        [System.Boolean]
        $AllowExplicitLogin,

        [System.Boolean]
        $AllowUseInMappings
    )
    
    # Take out parameters that are not actionable
    @('Ensure','PIDataArchive') | Foreach-Object { $null = $PSBoundParameters.Remove($_) }

    $Result = $false
    $PIIdentity = Get-TargetResource -Name $Name -PIDataArchive $PIDataArchive
    if($PIIdentity.Ensure -eq 'Absent')
    {
        Write-Verbose "$($Name) is null"
        if($Ensure -eq 'Absent')
        { $Result = $true }
        else
        { $Result = $false }
    }
    else
    {
        Write-Verbose "$($Name) is Present"
        if($Ensure -eq 'Absent')
        { $Result = $false }
        else
        {
            Foreach($Parameter in $PSBoundParameters.GetEnumerator())
            {
                # Nonrelevant fields can be skipped.
                if($PIIdentity.Keys -contains $Parameter.Key)
                {
                    # Make sure all applicable fields match.
                    if($($PIIdentity.$($Parameter.Key)) -ne $Parameter.Value)
                    {
                        return $false
                    }
                }
            } 
            $Result = $true 
        }
    }
    return $Result
}

Export-ModuleMember -Function *-TargetResource