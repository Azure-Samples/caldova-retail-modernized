#Requires -Version 7.0

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [string]$SubscriptionId,

    [ValidateNotNullOrEmpty()]
    [string]$BootstrapResourceGroup = 'rg-caldova-lab04-bootstrap',

    [ValidateNotNullOrEmpty()]
    [string]$PrimaryResourceGroup = 'rg-caldova-lab04-primary',

    [ValidateNotNullOrEmpty()]
    [string]$SecondaryResourceGroup = 'rg-caldova-lab04-secondary',

    [ValidatePattern('^[a-zA-Z0-9._()\-]+$')]
    [string]$BootstrapDeploymentName,

    [ValidatePattern('^[a-zA-Z0-9._()\-]+$')]
    [string]$PrimaryDeploymentName,

    [ValidatePattern('^[a-zA-Z0-9._()\-]+$')]
    [string]$SecondaryDeploymentName,

    [string]$ExpectedFailingPrincipalId,

    [switch]$RepairSystemIdentityPull = $true,

    [switch]$Apply
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$readerRoleId = 'acdd72a7-3385-48ef-bd42-f606fba81ae7'
$acrPushRoleId = '8311e382-0749-4cb8-b61a-304f252e45ec'
$acrPullRoleId = '7f951dda-4ed3-4680-a7ca-43fe172d538d'
$readRoleIds = @(
    $readerRoleId,
    'b24988ac-6180-42a0-ab88-20f7382dd24c',
    '8e3af657-a8ff-443c-a75c-2fe8c4bcb635'
)

function Invoke-AzJson {
    param([Parameter(Mandatory)][string[]]$Arguments)

    $response = & az @Arguments --only-show-errors --output json
    if ($LASTEXITCODE -ne 0) {
        throw "Azure CLI failed ($($Arguments[0]) $($Arguments[1])). Stop and resolve the error; any earlier successful assignments are retained."
    }
    if ($response) {
        $response | ConvertFrom-Json -AsHashtable
    }
}

function Assert-GuidValue {
    param(
        [AllowNull()][string]$Value,
        [Parameter(Mandatory)][string]$Name
    )

    $parsed = [guid]::Empty
    if (-not [guid]::TryParse($Value, [ref]$parsed) -or $parsed -eq [guid]::Empty) {
        throw "$Name must be a nonempty GUID."
    }
}

function Get-LabDeployment {
    param(
        [Parameter(Mandatory)][string]$ResourceGroup,
        [Parameter(Mandatory)][string[]]$RequiredOutputs,
        [string]$DeploymentName
    )

    $summaries = if ($DeploymentName) {
        @(@{ name = $DeploymentName })
    }
    else {
        @(Invoke-AzJson -Arguments @(
            'deployment', 'group', 'list', '--resource-group', $ResourceGroup,
            '--subscription', $SubscriptionId,
            '--query', "[?properties.provisioningState=='Succeeded'].{name:name}"
        ))
    }
    $outputFields = ($RequiredOutputs | ForEach-Object {
        "${_}:properties.outputs.${_}.value"
    }) -join ','
    $query = '{name:name,state:properties.provisioningState,timestamp:properties.timestamp,' +
        'prefix:properties.parameters.prefix.value,suffix:properties.parameters.suffix.value,' +
        'values:{' + $outputFields + '}}'
    $candidates = @(
        foreach ($summary in $summaries) {
            $deployment = Invoke-AzJson -Arguments @(
                'deployment', 'group', 'show', '--resource-group', $ResourceGroup,
                '--name', $summary['name'], '--subscription', $SubscriptionId,
                '--query', $query
            )
            if ($deployment['state'] -ne 'Succeeded') {
                continue
            }
            $valid = $true
            foreach ($name in $RequiredOutputs) {
                if ([string]::IsNullOrWhiteSpace([string]$deployment['values'][$name])) {
                    $valid = $false
                }
            }
            if ($valid) {
                $deployment
            }
        }
    )
    if ($candidates.Count -eq 0) {
        throw "No successful matching deployment in '$ResourceGroup' provides: $($RequiredOutputs -join ', '). Check deployment history or specify a deployment-name override."
    }
    $selected = @($candidates | Sort-Object -Property @{
        Expression = { [datetime]$_['timestamp'] }; Descending = $true
    }, @{
        Expression = { $_['name'] }; Descending = $true
    })[0]
    Write-Host "Selected deployment '$($selected['name'])' in '$ResourceGroup'."
    return $selected
}

function Get-RegistryAssignments {
    param([Parameter(Mandatory)][string]$PrincipalId)

    $assignments = @(Invoke-AzJson -Arguments @(
        'role', 'assignment', 'list', '--assignee-object-id', $PrincipalId,
        '--scope', $registryId, '--include-inherited',
        '--fill-principal-name', 'false', '--fill-role-definition-name', 'false',
        '--subscription', $SubscriptionId,
        '--query', '[].{id:id,principalId:principalId,roleDefinitionId:roleDefinitionId,scope:scope,condition:condition}'
    ))
    foreach ($assignment in $assignments) {
        $scope = [string]$assignment['scope']
        if ($assignment['principalId'] -eq $PrincipalId -and $scope -and (
            $scope -eq $registryId -or
            $registryId.StartsWith($scope.TrimEnd('/') + '/', [StringComparison]::OrdinalIgnoreCase)
        )) {
            $assignment
        }
    }
}

function Test-RegistryReadAccess {
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Assignments)

    foreach ($assignment in $Assignments) {
        $roleId = ([string]$assignment['roleDefinitionId'] -split '/')[-1]
        if ($roleId -in $readRoleIds -and -not $assignment['condition']) {
            return $true
        }
    }
    return $false
}

function Test-RegistryPullAccess {
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Assignments)

    return @($Assignments | Where-Object {
        $_['roleDefinitionId'] -like "*/$acrPullRoleId" -and -not $_['condition']
    }).Count -gt 0
}

function ConvertTo-CanonicalJson {
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) {
        return 'null'
    }
    if ($Value -is [System.Collections.IDictionary]) {
        $fields = foreach ($key in @($Value.Keys | Sort-Object)) {
            ($key | ConvertTo-Json -Compress) + ':' + (ConvertTo-CanonicalJson -Value $Value[$key])
        }
        return '{' + ($fields -join ',') + '}'
    }
    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        $items = foreach ($item in $Value) {
            ConvertTo-CanonicalJson -Value $item
        }
        return '[' + ($items -join ',') + ']'
    }
    return ConvertTo-Json -InputObject $Value -Depth 100 -Compress
}

function Get-RetailApp {
    return Invoke-AzJson -Arguments @(
        'containerapp', 'show', '--name', $appName, '--resource-group', $SecondaryResourceGroup,
        '--subscription', $SubscriptionId
    )
}

function Get-PreservedAppConfiguration {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$App)

    $configuration = $App['properties']['configuration'] |
        ConvertTo-Json -Depth 100 | ConvertFrom-Json -AsHashtable
    $targetRegistries = @($configuration['registries'] | Where-Object {
        $_['server'] -eq $registry['loginServer']
    })
    if ($targetRegistries.Count -ne 1) {
        throw 'Expected exactly one matching ACR registry entry on the retail Container App.'
    }
    $targetRegistries[0]['identity'] = 'system'
    $targetRegistries[0].Remove('username') | Out-Null
    $targetRegistries[0].Remove('passwordSecretRef') | Out-Null
    return ConvertTo-CanonicalJson -Value @{
        identity = $App['identity']
        configuration = $configuration
        template = $App['properties']['template']
        environmentId = $App['properties']['environmentId']
        managedEnvironmentId = $App['properties']['managedEnvironmentId']
        workloadProfileName = $App['properties']['workloadProfileName']
        latestRevisionName = $App['properties']['latestRevisionName']
    }
}

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw 'Azure CLI is required. Install it and sign in as an authorized platform operator before running this script.'
}
$accountArguments = @('account', 'show', '--query', '{id:id,tenantId:tenantId}')
if ($SubscriptionId) {
    Assert-GuidValue -Value $SubscriptionId -Name SubscriptionId
    $accountArguments += @('--subscription', $SubscriptionId)
}
$account = Invoke-AzJson -Arguments $accountArguments
Assert-GuidValue -Value $account['id'] -Name 'Resolved subscription ID'
Assert-GuidValue -Value $account['tenantId'] -Name 'Resolved tenant ID'
if ($SubscriptionId -and $account['id'] -ne $SubscriptionId) {
    throw 'Azure CLI returned a different subscription than requested.'
}
$SubscriptionId = [string]$account['id']
Write-Host "Subscription: $SubscriptionId; tenant: $($account['tenantId'])"

$bootstrapOutputs = @(
        'codeBuildIdentityName', 'codeBuildClientId', 'codeBuildPrincipalId',
        'codeDeploymentIdentityName', 'codeDeploymentClientId', 'codeDeploymentPrincipalId'
)
if ($RepairSystemIdentityPull) {
    $bootstrapOutputs += @('runtimeIdentityId', 'runtimeIdentityClientId')
}
$bootstrap = Get-LabDeployment -ResourceGroup $BootstrapResourceGroup `
    -DeploymentName $BootstrapDeploymentName -RequiredOutputs $bootstrapOutputs
$primary = Get-LabDeployment -ResourceGroup $PrimaryResourceGroup `
    -DeploymentName $PrimaryDeploymentName -RequiredOutputs @('containerRegistryName')
foreach ($boundary in @('prefix', 'suffix')) {
    if ([string]::IsNullOrWhiteSpace([string]$bootstrap[$boundary]) -or
        [string]::IsNullOrWhiteSpace([string]$primary[$boundary]) -or
        $bootstrap[$boundary] -ne $primary[$boundary]) {
        throw "Bootstrap and primary deployments must have matching, nonempty '$boundary' parameters. Use the deployment-name overrides to select one lab boundary."
    }
}

$registryName = [string]$primary['values']['containerRegistryName']
$registry = Invoke-AzJson -Arguments @(
    'acr', 'show', '--name', $registryName, '--resource-group', $PrimaryResourceGroup,
    '--subscription', $SubscriptionId, '--query', '{id:id,loginServer:loginServer}'
)
$registryId = "/subscriptions/$SubscriptionId/resourceGroups/$PrimaryResourceGroup/providers/Microsoft.ContainerRegistry/registries/$registryName"
if ($registry['id'] -ne $registryId -or [string]::IsNullOrWhiteSpace([string]$registry['loginServer'])) {
    throw 'The discovered registry does not match the deployment output and resource scope.'
}
Write-Host "Registry scope: $registryId"

$identities = @(
    foreach ($definition in @(
        @{ Environment = 'lab06'; OutputPrefix = 'codeBuild' },
        @{ Environment = 'lab06-deploy'; OutputPrefix = 'codeDeployment' }
    )) {
        $outputPrefix = $definition['OutputPrefix']
        $name = [string]$bootstrap['values']["${outputPrefix}IdentityName"]
        $clientId = [string]$bootstrap['values']["${outputPrefix}ClientId"]
        $principalId = [string]$bootstrap['values']["${outputPrefix}PrincipalId"]
        Assert-GuidValue -Value $clientId -Name "$name client ID"
        Assert-GuidValue -Value $principalId -Name "$name principal ID"
        $identity = Invoke-AzJson -Arguments @(
            'identity', 'show', '--name', $name, '--resource-group', $BootstrapResourceGroup,
            '--subscription', $SubscriptionId,
            '--query', '{id:id,clientId:clientId,principalId:principalId}'
        )
        $identityId = "/subscriptions/$SubscriptionId/resourceGroups/$BootstrapResourceGroup/providers/Microsoft.ManagedIdentity/userAssignedIdentities/$name"
        if ($identity['id'] -ne $identityId -or $identity['clientId'] -ne $clientId -or
            $identity['principalId'] -ne $principalId) {
            throw "Managed identity '$name' does not match its trusted deployment outputs. No roles will be added."
        }
        [pscustomobject]@{
            Environment = $definition['Environment']
            IdentityName = $name
            PrincipalId = $principalId
            RegistryId = $registryId
            Status = 'Preview'
            CreatedAssignmentId = $null
        }
    }
)
if ($identities[0].PrincipalId -eq $identities[1].PrincipalId) {
    throw 'Build and deployment principals must be separate.'
}
if ($ExpectedFailingPrincipalId) {
    Assert-GuidValue -Value $ExpectedFailingPrincipalId -Name ExpectedFailingPrincipalId
    if ($ExpectedFailingPrincipalId -notin $identities.PrincipalId) {
        throw 'The reported failing principal is not either discovered workflow identity. Check the GitHub environment client ID mappings.'
    }
}

foreach ($identity in $identities) {
    $assignments = @(Get-RegistryAssignments -PrincipalId $identity.PrincipalId)
    if ($identity.Environment -eq 'lab06') {
        $pushAssignments = @($assignments | Where-Object {
            $_['roleDefinitionId'] -like "*/$acrPushRoleId" -and -not $_['condition']
        })
        if ($pushAssignments.Count -eq 0) {
            throw 'The build identity has no verifiable existing AcrPush assignment. Request platform-owner review; Reader cannot replace image-push permission.'
        }
    }
    if (Test-RegistryReadAccess -Assignments $assignments) {
        $identity.Status = 'ExistingReadAccess'
    }
}

$pullRepair = $null
if ($RepairSystemIdentityPull) {
    $secondary = Get-LabDeployment -ResourceGroup $SecondaryResourceGroup `
        -DeploymentName $SecondaryDeploymentName -RequiredOutputs @('containerAppName')
    foreach ($boundary in @('prefix', 'suffix')) {
        if ([string]::IsNullOrWhiteSpace([string]$secondary[$boundary]) -or
            $secondary[$boundary] -ne $bootstrap[$boundary]) {
            throw "Secondary deployment has a different or empty '$boundary'. Select matching lab deployments before any repair."
        }
    }
    $appName = [string]$secondary['values']['containerAppName']
    $retailApp = Get-RetailApp
    $appId = "/subscriptions/$SubscriptionId/resourceGroups/$SecondaryResourceGroup/providers/Microsoft.App/containerApps/$appName"
    if ($retailApp['id'] -ne $appId) {
        throw 'The discovered retail Container App does not match the deployment output and scope.'
    }
    $systemPrincipalId = [string]$retailApp['identity']['principalId']
    if ($retailApp['identity']['type'] -notlike '*SystemAssigned*') {
        throw 'The Container App has no existing system-assigned identity. Request platform-owner provisioning; this script does not add or replace identities.'
    }
    Assert-GuidValue -Value $systemPrincipalId -Name 'Container App system principal ID'
    if ($systemPrincipalId -in $identities.PrincipalId) {
        throw 'The application system principal must not be a workflow principal.'
    }
    $runtimeIdentityId = [string]$bootstrap['values']['runtimeIdentityId']
    $runtimeClientId = [string]$bootstrap['values']['runtimeIdentityClientId']
    Assert-GuidValue -Value $runtimeClientId -Name 'Application runtime client ID'
    if ($runtimeIdentityId -notin @($retailApp['identity']['userAssignedIdentities'].Keys)) {
        throw 'The expected user-assigned runtime identity is not attached. Refusing to alter application authentication.'
    }
    $containers = @($retailApp['properties']['template']['containers'])
    if ($containers.Count -ne 1) {
        throw 'Expected one retail container; refusing an ambiguous registry repair.'
    }
    $runtimeClientSettings = @($containers[0]['env'] | Where-Object { $_['name'] -eq 'AZURE_CLIENT_ID' })
    if ($runtimeClientSettings.Count -ne 1 -or $runtimeClientSettings[0]['value'] -ne $runtimeClientId) {
        throw 'Application AZURE_CLIENT_ID does not match its user-assigned runtime identity. It will not be changed by this repair.'
    }
    $targetRegistries = @($retailApp['properties']['configuration']['registries'] | Where-Object {
        $_['server'] -eq $registry['loginServer']
    })
    if ($targetRegistries.Count -ne 1 -or $targetRegistries[0]['username'] -or
        $targetRegistries[0]['passwordSecretRef'] -or
        $targetRegistries[0]['identity'] -notin @('system', $runtimeIdentityId)) {
        throw 'Expected one managed-identity ACR entry using system or the known runtime identity. Refusing to replace unknown registry authentication.'
    }
    $originalRegistryIdentity = [string]$targetRegistries[0]['identity']
    $appConfigurationBefore = Get-PreservedAppConfiguration -App $retailApp
    $pullAssignments = @(Get-RegistryAssignments -PrincipalId $systemPrincipalId)
    $pullRepair = [pscustomobject]@{
        ContainerApp = $appName
        SystemPrincipalId = $systemPrincipalId
        PullRoleStatus = $(if (Test-RegistryPullAccess -Assignments $pullAssignments) { 'ExistingAcrPull' } else { 'Preview' })
        RegistryIdentityStatus = $(if ($originalRegistryIdentity -eq 'system') { 'AlreadySystem' } else { 'Preview' })
        CreatedAssignmentId = $null
    }
    $pullRepair | Format-List | Out-Host
}

$identities | Format-Table Environment, IdentityName, PrincipalId, Status | Out-Host
if (-not $Apply) {
    Write-Host 'Preview only. No changes made. Use -Apply to perform the selected repairs; use -Apply -WhatIf for a ShouldProcess preview.'
    $identities
    if ($pullRepair) { $pullRepair }
    return
}

foreach ($identity in $identities) {
    if ($identity.Status -eq 'ExistingReadAccess') {
        continue
    }
    $assignments = @(Get-RegistryAssignments -PrincipalId $identity.PrincipalId)
    if (Test-RegistryReadAccess -Assignments $assignments) {
        $identity.Status = 'ExistingReadAccess'
        continue
    }
    if (-not $PSCmdlet.ShouldProcess(
        "$($identity.Environment): $($identity.PrincipalId) on $registryId",
        'Add registry-scoped Reader role'
    )) {
        $identity.Status = 'NotApplied'
        continue
    }
    $assignment = Invoke-AzJson -Arguments @(
        'role', 'assignment', 'create', '--assignee-object-id', $identity.PrincipalId,
        '--assignee-principal-type', 'ServicePrincipal', '--role', $readerRoleId,
        '--scope', $registryId, '--subscription', $SubscriptionId,
        '--query', '{id:id,principalId:principalId,roleDefinitionId:roleDefinitionId,scope:scope}'
    )
    if (-not $assignment['id'] -or $assignment['principalId'] -ne $identity.PrincipalId -or
        $assignment['scope'] -ne $registryId -or $assignment['roleDefinitionId'] -notlike "*/$readerRoleId") {
        throw 'Azure did not return the expected Reader assignment. Inspect registry IAM before proceeding; earlier successful assignments are retained.'
    }
    $identity.Status = 'Created'
    $identity.CreatedAssignmentId = $assignment['id']
    Write-Host "Created Reader for $($identity.Environment): $($assignment['id'])"
}

foreach ($identity in $identities | Where-Object Status -EQ 'Created') {
    $assignments = @(Get-RegistryAssignments -PrincipalId $identity.PrincipalId)
    if (-not (Test-RegistryReadAccess -Assignments $assignments)) {
        throw "Reader assignment was created for $($identity.Environment), but is not visible on readback. Allow RBAC propagation and rerun. No automatic deletion was attempted."
    }
}

if ($RepairSystemIdentityPull) {
    $pullAssignments = @(Get-RegistryAssignments -PrincipalId $systemPrincipalId)
    $hasPullAccess = Test-RegistryPullAccess -Assignments $pullAssignments
    if (-not $hasPullAccess -and $PSCmdlet.ShouldProcess(
        "$systemPrincipalId on $registryId", 'Add AcrPull for the existing Container App system identity'
    )) {
        $assignment = Invoke-AzJson -Arguments @(
            'role', 'assignment', 'create', '--assignee-object-id', $systemPrincipalId,
            '--assignee-principal-type', 'ServicePrincipal', '--role', $acrPullRoleId,
            '--scope', $registryId, '--subscription', $SubscriptionId,
            '--query', '{id:id,principalId:principalId,roleDefinitionId:roleDefinitionId,scope:scope}'
        )
        if (-not $assignment['id'] -or $assignment['principalId'] -ne $systemPrincipalId -or
            $assignment['scope'] -ne $registryId -or $assignment['roleDefinitionId'] -notlike "*/$acrPullRoleId") {
            throw 'Azure did not return the expected system-identity AcrPull assignment. Registry authentication has not been switched.'
        }
        $pullRepair.CreatedAssignmentId = $assignment['id']
        $pullRepair.PullRoleStatus = 'Created'
        Write-Host "Created system-identity AcrPull: $($assignment['id'])"
        $pullAssignments = @(Get-RegistryAssignments -PrincipalId $systemPrincipalId)
        $hasPullAccess = Test-RegistryPullAccess -Assignments $pullAssignments
        if (-not $hasPullAccess) {
            throw 'System AcrPull grant is not visible yet. Allow propagation and rerun; the registry identity was not switched and the grant is retained.'
        }
    }
    elseif ($hasPullAccess) {
        $pullRepair.PullRoleStatus = 'ExistingAcrPull'
    }
    else {
        $pullRepair.PullRoleStatus = 'NotApplied'
    }

    if ($originalRegistryIdentity -ne 'system' -and $PSCmdlet.ShouldProcess(
        "$appId registry $($registry['loginServer'])", 'Switch only this registry entry to the existing system identity'
    )) {
        if (-not $hasPullAccess) {
            throw 'System-identity AcrPull was not approved or verified. Refusing to switch registry authentication.'
        }
        $currentApp = Get-RetailApp
        $currentRegistries = @($currentApp['properties']['configuration']['registries'] | Where-Object {
            $_['server'] -eq $registry['loginServer']
        })
        if ((Get-PreservedAppConfiguration -App $currentApp) -cne $appConfigurationBefore -or
            $currentRegistries[0]['identity'] -ne $originalRegistryIdentity) {
            throw 'Container App configuration changed during repair. Stop concurrent releases and retry; no registry update was attempted.'
        }
        Invoke-AzJson -Arguments @(
            'containerapp', 'registry', 'set', '--name', $appName,
            '--resource-group', $SecondaryResourceGroup, '--subscription', $SubscriptionId,
            '--server', $registry['loginServer'], '--identity', 'system',
            '--query', 'null'
        ) | Out-Null
        $pullRepair.RegistryIdentityStatus = 'UpdatedToSystem'
    }
    elseif ($originalRegistryIdentity -ne 'system') {
        $pullRepair.RegistryIdentityStatus = 'NotApplied'
    }

    $verifiedApp = Get-RetailApp
    if ((Get-PreservedAppConfiguration -App $verifiedApp) -cne $appConfigurationBefore) {
        throw 'Container App configuration drift detected. Inspect images, environment, identities, scaling, and ingress; no broad rollback or configuration replacement was attempted.'
    }
    if ($pullRepair.RegistryIdentityStatus -in @('AlreadySystem', 'UpdatedToSystem')) {
        $verifiedRegistries = @($verifiedApp['properties']['configuration']['registries'] | Where-Object {
            $_['server'] -eq $registry['loginServer']
        })
        if ($verifiedRegistries[0]['identity'] -ne 'system' -or $verifiedRegistries[0]['username'] -or
            $verifiedRegistries[0]['passwordSecretRef']) {
            throw 'The matching registry entry is not using credential-free system-identity authentication after repair.'
        }
    }
    $pullRepair
}

Write-Host 'Review the results below. Allow RBAC propagation, then use a fresh OIDC workflow session when authorized. No image release was performed.'
$identities