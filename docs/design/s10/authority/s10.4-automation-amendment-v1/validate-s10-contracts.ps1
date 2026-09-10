#requires -Version 7.0

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("AuthorityH", "EvidenceK", "ReceiptC")]
    [string]$LifecycleMode,

    [ValidatePattern("^$|^[0-9a-f]{40}$")]
    [string]$ProductHead = "",

    [ValidatePattern("^$|^[0-9a-f]{40}$")]
    [string]$EvidenceHead = "",

    [ValidatePattern("^$|^[0-9a-f]{40}$")]
    [string]$ReceiptHead = "",

    [string]$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot "../../../../..")).Path,
    [string]$PythonCommand = "python"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$overlayRoot = $PSScriptRoot
$manifestPath = Join-Path $overlayRoot "manifest.json"
$visualSchemaPath = Join-Path $overlayRoot "s10-visual-regression.schema.json"
$accessibilitySchemaPath = Join-Path $overlayRoot "s10-accessibility-common-tasks.schema.json"
$visualPath = Join-Path $RepositoryRoot "docs/design/s10/s10-visual-regression.json"
$accessibilityPath = Join-Path $RepositoryRoot "docs/design/s10/s10-accessibility-common-tasks.json"
$inventoryPath = Join-Path $RepositoryRoot "docs/design/s10/s10-screen-state-inventory.json"
$tokenPath = Join-Path $RepositoryRoot "docs/design/s10/s10-token-coverage.json"
$stagePath = Join-Path $RepositoryRoot "docs/design/s10/s10-stage-checkpoints.json"
$activationPath = Join-Path $RepositoryRoot "docs/design/s10/s10-activation.json"
$packagePath = Join-Path $RepositoryRoot "docs/design/s10/authority/assetrounds-brand-assets-v4.1-20260815.zip"
$shardContractPath = Join-Path $RepositoryRoot "Scripts/s10-4-shards.json"
$errors = [System.Collections.Generic.List[string]]::new()
$h413ValidatorPath = $PSCommandPath

function Add-ValidationError {
    param([string]$Message)
    $script:errors.Add($Message)
}

function Read-JsonFile {
    param([string]$Path)
    return Get-Content -LiteralPath $Path -Raw -Encoding utf8 | ConvertFrom-Json -Depth 100
}

function Get-Sha256 {
    param([string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Get-StringSetSha256 {
    param([object[]]$Values)
    $items = [string[]]@($Values | ForEach-Object { [string]$_ })
    [Array]::Sort($items, [StringComparer]::Ordinal)
    $text = [string]::Join("`n", $items)
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($text)
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
}

function Assert-Equal {
    param($Actual, $Expected, [string]$Label)
    if ([string]$Actual -cne [string]$Expected) {
        Add-ValidationError "${Label}: expected '$Expected', found '$Actual'."
    }
}

function Assert-ExactSet {
    param([object[]]$Actual, [object[]]$Expected, [string]$Label)
    $actualStrings = @($Actual | ForEach-Object { [string]$_ })
    $expectedStrings = @($Expected | ForEach-Object { [string]$_ })
    $actualDistinct = @($actualStrings | Sort-Object -CaseSensitive -Unique)
    $expectedDistinct = @($expectedStrings | Sort-Object -CaseSensitive -Unique)
    if ($actualStrings.Count -ne $actualDistinct.Count) {
        Add-ValidationError "$Label contains duplicates."
    }
    $delta = @(Compare-Object -ReferenceObject $expectedDistinct -DifferenceObject $actualDistinct -CaseSensitive)
    if ($delta.Count -ne 0) {
        Add-ValidationError "$Label is not the exact frozen set."
    }
}

function Assert-Contains {
    param([object[]]$Values, [string]$Expected, [string]$Label)
    if (-not (@($Values | ForEach-Object { [string]$_ }) -ccontains $Expected)) {
        Add-ValidationError "$Label must contain '$Expected'."
    }
}

# H411_SHARED_RELATIONAL_BEGIN
# The frozen schema subset cannot express conditional required fields or cross-run
# equality. These checks supplement it; neither replaces original hosted receipts.
function Get-H411Field {
    param($Value, [string]$Name)
    if ($null -ne $Value -and $null -ne $Value.PSObject.Properties[$Name]) { return $Value.$Name }
    return $null
}
function Assert-H411Ordered {
    param($Actual, $Expected, [string]$Label)
    Assert-Equal (ConvertTo-Json -InputObject @($Actual) -Compress -Depth 60) (ConvertTo-Json -InputObject @($Expected) -Compress -Depth 60) $Label
}
function Read-H411Evidence {
    param($Reference, [string]$Label)
    $relative = [string](Get-H411Field $Reference 'path')
    if ($relative -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._/-]+$' -or @($relative.Split('/') | Where-Object { $_ -in @('', '.', '..') }).Count -ne 0) {
        Add-ValidationError "$Label invalid evidence path"; return $null
    }
    $path = $RepositoryRoot
    foreach ($part in $relative.Split('/')) {
        $path = Join-Path $path $part
        if (-not (Test-Path -LiteralPath $path) -or ((Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            Add-ValidationError "$Label missing or linked evidence"; return $null
        }
    }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { Add-ValidationError "$Label is not a file"; return $null }
    Assert-Equal (Get-Sha256 $path) $Reference.sha256 "$Label original bytes"
    return Read-JsonFile $path
}
function Get-H411CanonicalSHA256 {
    param($Value)
    $json = ConvertTo-Json -InputObject $Value -Depth 100 -Compress
    $result = $json | & $PythonCommand -c 'import sys,json,hashlib; o=json.load(sys.stdin); print(hashlib.sha256(json.dumps(o,sort_keys=True,separators=(",",":"),ensure_ascii=True,allow_nan=False).encode()).hexdigest().upper())'
    if ($LASTEXITCODE -ne 0) { throw 'H411 canonical hashing failed' }
    return [string]$result
}
function Get-H411OriginalCanonicalSHA256 {
    param($Reference, [string]$Member = '', [string]$Exclude = '')
    # Hash original JSON with the producer's Python canonicalizer. PowerShell's
    # JSON date/number conversions must never rewrite an identity before hashing.
    $path = Join-Path $RepositoryRoot $Reference.path
    $result = & $PythonCommand -c 'import sys,json,hashlib; o=json.load(open(sys.argv[1],encoding="utf-8")); o=o[sys.argv[2]] if sys.argv[2] else o; o={k:v for k,v in o.items() if k not in sys.argv[3].split(",")} if sys.argv[3] else o; print(hashlib.sha256(json.dumps(o,sort_keys=True,separators=(",",":"),ensure_ascii=True,allow_nan=False).encode()).hexdigest().upper())' $path $Member $Exclude
    if ($LASTEXITCODE -ne 0) { throw 'H411 original canonical hashing failed' }
    return [string]$result
}
function ConvertTo-H411DateTimeOffset {
    param($Value)
    # ConvertFrom-Json may return DateTime. Preserve its instant without an
    # implicit culture-sensitive string conversion that discards the UTC kind.
    if ($Value -is [DateTimeOffset]) { return $Value }
    if ($Value -is [DateTime]) {
        if ($Value.Kind -eq [DateTimeKind]::Unspecified) { throw 'H411 timestamp has no time zone' }
        return [DateTimeOffset]::new($Value)
    }
    return [DateTimeOffset]::Parse([string]$Value, [Globalization.CultureInfo]::InvariantCulture)
}
function Assert-H411API {
    param($Run, $Artifact, $Identity, [string]$Label)
    Assert-Equal $Run.id $Identity.run_id "$Label original run ID"
    Assert-Equal $Run.run_attempt $Identity.run_attempt "$Label original attempt"
    Assert-Equal $Run.head_sha $ProductHead "$Label original run head"
    Assert-Equal $Run.head_branch 'phase/s10-brand-refresh' "$Label original ref"
    Assert-Equal $Run.status 'completed' "$Label original terminal"
    Assert-Equal $Run.conclusion 'success' "$Label original success"
    Assert-Equal $Run.event 'workflow_dispatch' "$Label original event"
    Assert-Equal $Artifact.id $Identity.artifact_id "$Label original artifact ID"
    Assert-Equal $Artifact.name $Identity.artifact_name "$Label original artifact name"
    Assert-Equal $Artifact.digest $Identity.artifact_digest "$Label original artifact digest"
    Assert-Equal $Artifact.expired $false "$Label original artifact retained"
    Assert-Equal $Artifact.workflow_run.id $Identity.run_id "$Label artifact source run"
    Assert-Equal $Artifact.workflow_run.head_sha $ProductHead "$Label artifact source head"
    if ([long]$Artifact.size_in_bytes -le 0) { Add-ValidationError "$Label empty original artifact" }
    $created = (ConvertTo-H411DateTimeOffset $Artifact.created_at)
    $expires = (ConvertTo-H411DateTimeOffset $Artifact.expires_at)
    if ($expires -le $created -or $expires -le [DateTimeOffset]::UtcNow -or $created -gt [DateTimeOffset]::UtcNow) { Add-ValidationError "$Label invalid/expired artifact lifetime" }
}
function Assert-H411NativeReceipt {
    param($Receipt, $Shard, [string]$Label)
    foreach ($field in @('runner_label','runner_image','xcode_version','xcode_build','sdk_name','sdk_build','simulator_runtime','simulator_name','simulator_os_build','simulator_udid')) {
        if ($null -eq (Get-H411Field $Receipt $field)) { Add-ValidationError "$Label missing native $field" }
    }
    Assert-Equal $Receipt.runner_label $activation.toolchain.runner_label "$Label runner label"
    Assert-GitHubReceiptEnvironment $Receipt $Label
    foreach ($field in @('xcode_version','xcode_build','sdk_name','sdk_build')) { Assert-Equal $Receipt.$field $activation.toolchain.$field "$Label $field" }
    Assert-Equal $Receipt.simulator_runtime $Shard.simulator_runtime "$Label runtime"
    Assert-Equal $Receipt.simulator_name $Shard.simulator_name "$Label model"
    Assert-Equal $Receipt.simulator_os_build $Shard.os_build "$Label OS build"
}
function Assert-H411SharedReceipt {
    param($Receipt, $Shard)
    $label = [string]$Receipt.shard_id
    $shared = $Receipt.shared_execution
    Assert-Equal $Receipt.runner_provider 'github_actions' "$label shared provider admission"
    Assert-Equal $shared.source_product_head $ProductHead "$label shared source"
    Assert-Equal $shared.local_unit_test_count 0 "$label no local units"
    Assert-Equal $shared.producer_unit_test_count 5 "$label original producer units"
    Assert-ExactSet @($shared.producer_unit_test_selectors) @($manifest.shared_execution_contract.producer_unit_test_selectors) "$label exact five producer methods"
    Assert-Equal $shared.unit_evidence_origin 'shared-producer' "$label unit origin"
    Assert-Equal $shared.consumer_execution_mode 'test-without-building' "$label execution mode"
    foreach ($field in @('build_payload','same_shard_github_equivalence')) {
        if ($null -ne (Get-H411Field $Receipt $field)) { Add-ValidationError "$label mixes legacy and shared provenance" }
    }
    $seal = Read-H411Evidence $shared.seal "$label seal"
    $qualification = Read-H411Evidence $shared.qualification "$label qualification"
    $producerAPI = Read-H411Evidence $shared.producer_api "$label producer API"
    $producerArtifactAPI = Read-H411Evidence $shared.producer_artifact_api "$label producer artifact API"
    $native = Read-H411Evidence $shared.producer_native_tests "$label original native unit tests"
    $executed = Read-H411Evidence $shared.producer_executed_tests "$label original executed tests"
    # Identity hashes are canonical producer hashes, not a re-serialized overlay hash.
    Assert-Equal $seal.sharedBuildIdentitySHA256 $shared.shared_build_identity_sha256 "$label sealed payload identity"
    Assert-Equal $seal.producerQualificationSHA256 $shared.producer_qualification_sha256 "$label sealed qualification identity"
    Assert-Equal (Get-H411OriginalCanonicalSHA256 $shared.seal 'sharedBuildIdentity') $shared.shared_build_identity_sha256 "$label recomputed payload identity"
    Assert-Equal (Get-H411OriginalCanonicalSHA256 $shared.qualification) $shared.producer_qualification_sha256 "$label recomputed qualification identity"
    Assert-Equal $seal.contractID 's10.4.shared-build.v1' "$label typed seal contract"
    Assert-Equal $seal.recordType 'shared-build-seal' "$label typed seal"
    Assert-Equal $qualification.contractID 's10.4.shared-build.v1' "$label typed qualification contract"
    Assert-Equal $qualification.recordType 'producer-qualification' "$label typed qualification"
    Assert-Equal $qualification.source.head $ProductHead "$label original qualification head"
    Assert-H413NativeSource $qualification.source "$label qualification"
    Assert-H413NativeSource $seal.sharedBuildIdentity.source "$label seal"
    Assert-H413SelectedProducer $shared $label
    Assert-Equal $seal.sharedBuildIdentity.source.head $ProductHead "$label original sealed head"
    Assert-Equal (Get-H411CanonicalSHA256 $qualification.source) (Get-H411CanonicalSHA256 $seal.sharedBuildIdentity.source) "$label exact source bindings"
    Assert-Equal (Get-H411CanonicalSHA256 $qualification.products) (Get-H411CanonicalSHA256 $seal.sharedBuildIdentity.products) "$label exact product closure"
    Assert-Equal (Get-H411CanonicalSHA256 $qualification.archive) (Get-H411CanonicalSHA256 $seal.sharedBuildIdentity.archive) "$label exact archive"
    Assert-Equal (Get-H411CanonicalSHA256 $qualification.producer) (Get-H411CanonicalSHA256 $seal.sharedBuildIdentity.producer) "$label exact producer"
    Assert-Equal $qualification.producer.runID $shared.producer_run_id "$label qualification run"
    Assert-Equal $qualification.producer.runAttempt $shared.producer_run_attempt "$label qualification attempt"
    Assert-Equal $qualification.producer.jobID $shared.producer_job_id "$label qualification job"
    Assert-Equal $qualification.producer.runnerProvider 'bitrise' "$label actual producer provider"
    Assert-Equal $seal.sharedBuildIdentity.payloadArtifact.id $producerArtifactAPI.id "$label sealed original artifact ID"
    Assert-Equal $seal.sharedBuildIdentity.payloadArtifact.bytes $producerArtifactAPI.size_in_bytes "$label sealed original artifact size"
    Assert-Equal $seal.sharedBuildIdentity.payloadArtifact.sha256 $producerArtifactAPI.digest.Replace('sha256:','').ToUpperInvariant() "$label sealed original artifact digest"
    Assert-Equal $seal.sharedBuildIdentity.payloadArtifact.createdAtUTC $producerArtifactAPI.created_at "$label original creation"
    Assert-Equal $seal.sharedBuildIdentity.payloadArtifact.expiresAtUTC $producerArtifactAPI.expires_at "$label original expiry"

    Assert-Equal $producerAPI.id $shared.producer_run_id "$label producer run"
    Assert-Equal $producerAPI.run_attempt $shared.producer_run_attempt "$label producer attempt"
    Assert-Equal $producerAPI.head_sha $ProductHead "$label producer head"
    Assert-Equal $producerAPI.head_branch 'phase/s10-brand-refresh' "$label producer ref"
    Assert-Equal $producerAPI.conclusion 'success' "$label producer qualification success"
    Assert-Equal $producerAPI.status 'completed' "$label producer terminal"
    Assert-Equal $producerArtifactAPI.expired $false "$label producer artifact available"
    Assert-Equal $producerArtifactAPI.workflow_run.id $shared.producer_run_id "$label producer artifact run"
    Assert-Equal $producerArtifactAPI.workflow_run.head_sha $ProductHead "$label producer artifact head"
    if ((ConvertTo-H411DateTimeOffset $producerArtifactAPI.expires_at) -le [DateTimeOffset]::UtcNow) { Add-ValidationError "$label producer artifact expired" }
    $cases = [System.Collections.Generic.List[object]]::new()
    function Visit-H411NativeNode($node) {
        if ($node.nodeType -ceq 'Test Case') { $cases.Add($node) }
        foreach ($child in @(Get-H411Field $node 'children')) { if ($null -ne $child) { Visit-H411NativeNode $child } }
    }
    foreach ($node in $native.testNodes) { Visit-H411NativeNode $node }
    $nativeIDs = @($cases | ForEach-Object { ([string]$_.nodeIdentifierURL).Replace('test://com.apple.xcode/FieldEvidenceApp/','').Replace('()','') })
    Assert-ExactSet $nativeIDs @($shared.producer_unit_test_selectors) "$label native five unit identities"
    Assert-Equal $cases.Count 5 "$label native unit count"
    foreach ($case in $cases) {
        Assert-Equal $case.result 'Passed' "$label native unit pass"
        if ((Get-H411Field $case 'isExpectedFailure') -eq $true) { Add-ValidationError "$label expected-failure unit forbidden" }
    }
    Assert-ExactSet @($executed | ForEach-Object { ([string]$_.identifier).Replace('()','') }) @($shared.producer_unit_test_selectors) "$label executed five unit identities"
    foreach ($method in $executed) { Assert-Equal $method.result 'Passed' "$label executed unit pass" }
    Assert-ExactSet @($qualification.nativeTests.identifier) @($shared.producer_unit_test_selectors) "$label qualified native identities"
    foreach ($method in $qualification.nativeTests) { Assert-Equal $method.result 'Passed' "$label qualified native pass" }

    if ($Receipt.execution_model -ceq 'shared-native-v1') {
        if ($null -ne (Get-H411Field $Receipt 'segmented_execution')) { Add-ValidationError "$label native receipt contains assembly" }
        $reference = Read-H411Evidence (Get-H411Field $Receipt 'consumer_build_reference') "$label consumer build reference"
        Assert-Equal $reference.sharedBuildIdentitySHA256 $shared.shared_build_identity_sha256 "$label consumer payload"
        Assert-Equal $reference.producerQualificationSHA256 $shared.producer_qualification_sha256 "$label consumer qualification"
        Assert-Equal $reference.contractID 's10.4.shared-build.v1' "$label consumer reference type"
        Assert-Equal $reference.recordType 'consumer-build-reference' "$label consumer reference record"
        Assert-Equal $reference.source.head $ProductHead "$label consumer reference head"
        Assert-H413NativeSource $reference.source "$label consumer reference"
        Assert-Equal $reference.unitTestCount 0 "$label consumer original local units"
        Assert-Equal $reference.producerUnitTestCount 5 "$label consumer original producer units"
        Assert-Equal $reference.diagnosticOnly $false "$label diagnostic promotion forbidden"
        Assert-Equal $reference.productsUnchanged $true "$label immutable consumer products"
        Assert-Equal $reference.consumer.purpose 'acceptance' "$label original consumer purpose"
        Assert-Equal $reference.consumer.runnerProvider 'github' "$label original consumer provider"
        foreach ($pair in @(@('runID','run_id'),@('runAttempt','run_attempt'),@('jobID','job_id'),@('shardID','shard_id'),@('simulatorUDID','simulator_udid'))) { Assert-Equal $reference.consumer.($pair[0]) $Receipt.($pair[1]) "$label consumer $($pair[0])" }
        Assert-Equal $reference.consumer.segmentID 'none' "$label full native segment mode"
        Assert-Equal (Get-H411CanonicalSHA256 $reference.products) (Get-H411CanonicalSHA256 $qualification.products) "$label consumer product closure"
        Assert-Equal @($reference.uiCommand | Where-Object { $_ -ceq 'test-without-building' }).Count 1 "$label consumer exact command"
        if (@($reference.uiCommand | Where-Object { $_ -in @('test','build','build-for-testing') -or $_ -like '-skip-testing*' }).Count -ne 0) { Add-ValidationError "$label forbidden build/test fallback" }

        return
    }
    if ($null -ne (Get-H411Field $Receipt 'consumer_build_reference')) { Add-ValidationError "$label assembly claims local consumer build" }
    $assembly = $Receipt.segmented_execution
    foreach ($field in @('runner_label','runner_image','xcode_version','xcode_build','sdk_name','sdk_build','simulator_runtime','simulator_name','simulator_os_build','simulator_udid','github_environment')) {
        if ($null -ne (Get-H411Field $Receipt $field)) { Add-ValidationError "$label assembly falsely carries native $field" }
    }
    $minimum = $Receipt.device_profile_id -ceq 'iphone-se-3-ios-18.0-minimum'
    if (-not $minimum -and $label -cne 's10.4.current.ax-text') { Add-ValidationError "$label unadmitted segmented profile" }
    $expectedSegments = if ($minimum) { @($manifest.shared_execution_contract.minimum_segment_ids) } else { @($manifest.shared_execution_contract.current_ax_segment_ids) }
    Assert-H411Ordered @($assembly.consumers.segment_id) $expectedSegments "$label ordered source segments"
    Assert-Equal @($assembly.consumers).Count 3 "$label source consumer count"
    Assert-ExactSet @($assembly.consumers | ForEach-Object { "$($_.run_id)|$($_.job_id)|$($_.simulator_udid)|$($_.ui_identity_sha256)" }) @($assembly.consumers | ForEach-Object { "$($_.run_id)|$($_.job_id)|$($_.simulator_udid)|$($_.ui_identity_sha256)" }) "$label unique native sessions"
    Assert-ExactSet @($assembly.consumers.simulator_udid) @($assembly.consumers.simulator_udid) "$label fresh distinct simulators"
    $plan = Read-H411Evidence $assembly.segment_plan "$label frozen segment plan"
    Assert-Equal $assembly.segment_plan.sha256 (Get-GitBlobSha256 $ProductHead 'Scripts/s10-4-segment-plan.json') "$label exact E committed segment plan"
    $definitions = if ($minimum) { @($plan.minimumVerification.segments) } else { @($plan.segments) }
    $matrix = Read-H411Evidence $assembly.matrix_binding "$label original matrix"
    Assert-Equal $matrix.matrixID $assembly.matrix_id "$label matrix identity"
    Assert-Equal $matrix.productHead $ProductHead "$label matrix head"
    Assert-Equal $matrix.shardID $label "$label matrix shard"
    Assert-Equal $matrix.deviceProfileID $Receipt.device_profile_id "$label matrix profile"
    Assert-Equal $matrix.sharedBuildIdentitySHA256 $shared.shared_build_identity_sha256 "$label matrix payload"
    Assert-Equal $matrix.producerQualificationSHA256 $shared.producer_qualification_sha256 "$label matrix qualification"
    $aggregate = Read-H411Evidence $assembly.assembly_receipt "$label original assembly receipt"
    Assert-Equal $aggregate.productHead $ProductHead "$label assembly head"
    Assert-Equal $aggregate.shardID $label "$label assembly shard"
    Assert-Equal $aggregate.matrixID $assembly.matrix_id "$label assembly matrix"
    Assert-Equal $aggregate.sharedBuildIdentitySHA256 $shared.shared_build_identity_sha256 "$label assembly payload"
    Assert-Equal $aggregate.producerQualificationSHA256 $shared.producer_qualification_sha256 "$label assembly qualification"
    $logical = Read-H411Evidence $assembly.logical_shard_receipt "$label original logical shard receipt"
    Assert-Equal $logical.candidateCount 67 "$label assembly states"
    Assert-Equal $logical.accessibilityRowCount 6 "$label assembly tasks"
    Assert-Equal $aggregate.complete $true "$label logical assembly complete"
    Assert-Equal $aggregate.finalAcceptanceEligible $true "$label qualified assembly"
    Assert-Equal $aggregate.assemblyIsNativeExecution $false "$label assembly does not claim native execution"
    Assert-Equal $aggregate.assemblyRunID $Receipt.run_id "$label original assembly run"
    Assert-Equal $aggregate.assemblyRunAttempt $Receipt.run_attempt "$label original assembly attempt"
    Assert-Equal $aggregate.distinctSessionCount 3 "$label original distinct sessions"
    Assert-H411Ordered @($aggregate.selectedConsumers) @($matrix.selectedConsumers) "$label aggregate original consumer selections"
    Assert-Equal $aggregate.dependencyResolution.immutableSelectionsVerified $true "$label immutable predecessor resolution"
    Assert-H411Ordered @($aggregate.dependencyResolution.selectedPredecessors) @($matrix.selectedConsumers | Select-Object -First 2) "$label exact predecessor resolution"
    Assert-Equal $aggregate.journeyResolution.sourceNativeSuccessRequired $true "$label native journey requirement"
    $expectedJourneyIDs = @(if ($minimum) { @($plan.minimumVerification.journeys.journeyID) } else { @() })
    Assert-H411Ordered @($aggregate.journeyResolution.minimumJourneyIDs) $expectedJourneyIDs "$label complete source journeys"

    Assert-Equal $aggregate.humanVisualReviewStatus 'NOT_RUN' "$label assembly cannot synthesize human review"
    foreach ($pair in @(@('productHead',$ProductHead),@('shardID',$label),@('matrixID',$assembly.matrix_id),@('sharedBuildIdentitySHA256',$shared.shared_build_identity_sha256),@('producerQualificationSHA256',$shared.producer_qualification_sha256),@('localUnitExecutedTestCount',0),@('producerUnitExecutedTestCount',5))) { Assert-Equal (Get-H411Field $logical $pair[0]) $pair[1] "$label logical $($pair[0])" }
    Assert-Equal $logical.complete $true "$label logical closure"
    Assert-H411Ordered @($aggregate.sourceSegmentReceiptSHA256s) @($assembly.consumers | ForEach-Object { $_.receipt.sha256 }) "$label aggregate original receipt bytes"

    Assert-Equal $logical.stateAXRowCount 67 "$label strict AX closure"
    Assert-Equal $logical.contrastRowCount 67 "$label strict contrast closure"
    $immutableMatrix = [ordered]@{}
    foreach ($property in $matrix.PSObject.Properties) { if ($property.Name -cnotin @('matrixID','selectedConsumers')) { $immutableMatrix[$property.Name] = $property.Value } }
    Assert-Equal (Get-H411OriginalCanonicalSHA256 $assembly.matrix_binding '' 'matrixID,selectedConsumers') $assembly.matrix_id "$label derived immutable matrix"

    $allOwned = [System.Collections.Generic.List[string]]::new()
    foreach ($consumer in $assembly.consumers) {
        $clabel = "$label/$($consumer.segment_id)"
        Assert-H411NativeReceipt $consumer $Shard $clabel
        Assert-Equal $consumer.source_product_head $ProductHead "$clabel head"
        Assert-Equal $consumer.shard_id $label "$clabel shard"
        Assert-Equal $consumer.device_profile_id $Receipt.device_profile_id "$clabel profile"
        Assert-Equal $consumer.shared_build_identity_sha256 $shared.shared_build_identity_sha256 "$clabel payload"
        Assert-Equal $consumer.producer_qualification_sha256 $shared.producer_qualification_sha256 "$clabel qualification"
        Assert-Equal $consumer.matrix_id $assembly.matrix_id "$clabel matrix"
        $definition = @($definitions | Where-Object { $_.segmentID -ceq $consumer.segment_id })
        Assert-Equal $definition.Count 1 "$clabel definition"
        if ($definition.Count -ne 1) { continue }
        $definition = $definition[0]
        foreach ($pair in @(@('owned_state_ids','ownedStateIDs'),@('replay_state_ids','replayStateIDs'),@('dependency_segment_ids','dependencySegmentIDs'))) {
            Assert-H411Ordered $consumer.($pair[0]) $definition.($pair[1]) "$clabel $($pair[0])"
        }
        foreach ($state in $consumer.owned_state_ids) { $allOwned.Add($state) }
        $run = Read-H411Evidence $consumer.original_api "$clabel original run API"
        $artifact = Read-H411Evidence $consumer.artifact_api "$clabel original artifact API"
        Assert-H411API $run $artifact $consumer $clabel
        $original = Read-H411Evidence $consumer.receipt "$clabel original receipt"
        foreach ($pair in @(@('productHead',$ProductHead),@('shardID',$label),@('matrixID',$assembly.matrix_id),@('sharedBuildIdentitySHA256',$shared.shared_build_identity_sha256),@('producerQualificationSHA256',$shared.producer_qualification_sha256),@('localUnitExecutedTestCount',0),@('producerUnitExecutedTestCount',5),@('unitEvidenceOrigin','shared-producer'),@('buildMode','shared-test-without-building'),@('complete',$false),@('nativeEvidenceComplete',$true),@('terminalAPIRequired',$true))) {
            Assert-Equal (Get-H411Field $original $pair[0]) $pair[1] "$clabel original $($pair[0])"
        }
        Assert-H411Ordered $original.segment.ownedStateIDs $consumer.owned_state_ids "$clabel original owned states"
        Assert-Equal $original.segment.segmentID $consumer.segment_id "$clabel original segment"
        Assert-Equal $original.uiIdentitySHA256 $consumer.ui_identity_sha256 "$clabel original native identity"
        foreach ($pair in @(@('runID','run_id'),@('runAttempt','run_attempt'),@('jobID','job_id'),@('simulatorUDID','simulator_udid'),@('shardID','shard_id'),@('segmentID','segment_id'))) { Assert-Equal $original.consumer.($pair[0]) $consumer.($pair[1]) "$clabel original consumer $($pair[0])" }
        Assert-Equal $original.uiExecutedTestCount 1 "$clabel one original native UI method"
        Assert-H411Ordered @($original.uiTestSelectors) @('S10_4AutomatedBrandLabUITests/testAutomatedBrandLabShard()') "$clabel exact native UI method"
        $jobs = @(Read-H411Evidence $consumer.original_jobs_api "$clabel original jobs API")
        $job = @($jobs | Where-Object { [string]$_.id -ceq $consumer.job_id })
        Assert-Equal $job.Count 1 "$clabel original job identity"
        if ($job.Count -eq 1) {
            foreach ($pair in @(@('run_id',$consumer.run_id),@('run_attempt',$consumer.run_attempt),@('head_sha',$ProductHead),@('head_branch','phase/s10-brand-refresh'),@('status','completed'),@('conclusion','success'),@('runner_name',$original.consumer.runnerName))) { Assert-Equal $job[0].($pair[0]) $pair[1] "$clabel original job $($pair[0])" }
        }
        $buildReference = Read-H411Evidence $consumer.consumer_build_reference "$clabel original consumer build reference"
        Assert-Equal (Get-H411OriginalCanonicalSHA256 $consumer.consumer_build_reference) $original.consumerBuildReferenceSHA256 "$clabel original build reference hash"
        Assert-Equal $buildReference.sharedBuildIdentitySHA256 $shared.shared_build_identity_sha256 "$clabel original build payload"
        Assert-Equal $buildReference.producerQualificationSHA256 $shared.producer_qualification_sha256 "$clabel original build qualification"
        Assert-Equal $buildReference.diagnosticOnly $false "$clabel original diagnostic rejection"
        Assert-Equal $buildReference.productsUnchanged $true "$clabel original frozen closure"
        Assert-Equal (Get-H411CanonicalSHA256 $buildReference.consumer) (Get-H411CanonicalSHA256 $original.consumer) "$clabel original consumer equality"

        $selected = @($matrix.selectedConsumers | Where-Object { $_.segmentID -ceq $consumer.segment_id })
        Assert-Equal $selected.Count 1 "$clabel selected original"
        if ($selected.Count -eq 1) {
            foreach ($pair in @(@('runID','run_id'),@('runAttempt','run_attempt'),@('jobID','job_id'),@('artifactID','artifact_id'),@('artifactName','artifact_name'))) { Assert-Equal $selected[0].($pair[0]) $consumer.($pair[1]) "$clabel selected $($pair[0])" }
            Assert-Equal $selected[0].receiptSHA256 $consumer.receipt.sha256 "$clabel selected receipt bytes"
            Assert-Equal $selected[0].sessionIdentitySHA256 $original.sessionIdentitySHA256 "$clabel selected native session"
            Assert-Equal $selected[0].matrixID $assembly.matrix_id "$clabel selected matrix"

            Assert-Equal $selected[0].artifactSHA256 $consumer.artifact_digest.Replace('sha256:','').ToUpperInvariant() "$clabel selected archive bytes"
        }
        $allJourneys = @(Read-H411Evidence $consumer.journey_rows "$clabel original native journeys")
        $journeys = @($allJourneys | Where-Object { (Get-H411Field $_ 'setupOnly') -ne $true })
        Assert-H411Ordered @($journeys | ForEach-Object { $_.journeyID }) @($consumer.journey_ids) "$clabel journey identity"
        if ($minimum) {
            Assert-H411Ordered @($consumer.journey_ids) @($definition.journeyIDs) "$clabel frozen journeys"
            foreach ($journey in $journeys) {
                $expected = @($plan.minimumVerification.journeys | Where-Object { $_.journeyID -ceq $journey.journeyID })
                Assert-Equal $expected.Count 1 "$clabel frozen journey"
                Assert-Equal $journey.completed $true "$clabel native journey complete"
                Assert-Equal $journey.shardID $label "$clabel journey shard"
                Assert-Equal $journey.segmentID $consumer.segment_id "$clabel journey segment"
                if ($expected.Count -eq 1) {
                    foreach ($field in @('entryStateID','exitStateID')) { Assert-Equal $journey.$field $expected[0].$field "$clabel journey $field" }
                    Assert-H411Ordered @($journey.assertionIDs) @($expected[0].assertionIDs) "$clabel actual public assertions"
                }
            }
        }
    }
    $expectedOwnedStateIDs = @($definitions | ForEach-Object { $_.ownedStateIDs })
    Assert-H411Ordered @($allOwned) $expectedOwnedStateIDs "$label complete ordered source state ownership"
    Assert-ExactSet @($allOwned) @($stateIDs) "$label complete inventory state ownership"
}
# H411_SHARED_RELATIONAL_END

function Assert-Commit {
    param([string]$Commit, [string]$Label)
    & git -C $RepositoryRoot cat-file -e "$Commit^{commit}" 2>$null
    if ($LASTEXITCODE -ne 0) {
        Add-ValidationError "$Label '$Commit' is not a repository commit."
    }
}

function Assert-Ancestor {
    param([string]$Ancestor, [string]$Descendant, [string]$Label)
    & git -C $RepositoryRoot merge-base --is-ancestor $Ancestor $Descendant 2>$null
    if ($LASTEXITCODE -ne 0) {
        Add-ValidationError "${Label}: '$Ancestor' is not an ancestor of '$Descendant'."
    }
}

function Get-GitJson {
    param([string]$Commit, [string]$Path)
    $lines = @(& git -C $RepositoryRoot show "$Commit`:$Path" 2>$null)
    if ($LASTEXITCODE -ne 0) {
        throw "Cannot read $Path from $Commit."
    }
    return ($lines -join "`n") | ConvertFrom-Json -Depth 100
}

function Get-GitBlobSha256 {
    param([string]$Commit, [string]$Path)
    $program = "import hashlib,subprocess,sys; print(hashlib.sha256(subprocess.check_output(['git','-C',sys.argv[1],'show',sys.argv[2]+':'+sys.argv[3]])).hexdigest().upper())"
    $value = & $PythonCommand -c $program $RepositoryRoot $Commit $Path 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "Cannot hash $Path from $Commit."
    }
    return ([string]$value).Trim()
}

function Assert-GitHubEnvironmentContract {
    param($Contract)
    if ($Contract -isnot [System.Management.Automation.PSCustomObject]) {
        Add-ValidationError "GitHub environment contract must be an object."
        return
    }
    $expected = [ordered]@{
        contract_version = "s10.4-github-image-adoption-v3"
        authority_head = "af107f2edf76202e2f1764efdab01fd973043e04"
        image_os = "macos26"
        macos_product_name = "macOS"
        macos_product_version = "26.6.2"
        macos_build_version = "25G83"
        architecture = "arm64"
    }
    $stringFields = @(@($expected.Keys) + "worker_source_sha256")
    Assert-ExactSet @($Contract.PSObject.Properties.Name) @($stringFields + "image_versions") "GitHub environment contract fields"
    foreach ($field in $stringFields) {
        if (-not ($Contract.PSObject.Properties.Name -ccontains $field) -or $Contract.$field -isnot [string]) {
            Add-ValidationError "GitHub environment contract $field must be a string."
            return
        }
    }
    if (-not ($Contract.PSObject.Properties.Name -ccontains "image_versions") -or
        $Contract.image_versions -isnot [System.Array] -or
        @($Contract.image_versions).Count -ne 2 -or
        @($Contract.image_versions | Where-Object { $_ -isnot [string] }).Count -ne 0) {
        Add-ValidationError "GitHub environment image_versions must be exactly two strings."
        return
    }
    Assert-H411Ordered $Contract.image_versions @("20260831.0337.3", "20260907.0351.1") "GitHub exact ordered image allowlist"
    foreach ($field in $expected.Keys) {
        Assert-Equal $Contract.$field $expected[$field] "GitHub environment contract $field"
    }
    if ([string]$Contract.worker_source_sha256 -cnotmatch '^[0-9A-F]{64}$') {
        Add-ValidationError "GitHub environment worker source digest is malformed."
    }
    Assert-Equal (Get-Sha256 (Join-Path $RepositoryRoot ".github/workflows/ios-ci-worker.yml")) $Contract.worker_source_sha256 "GitHub reviewed worker source"
    Assert-Commit $Contract.authority_head "GitHub image authority"
    $parents = @(& git -C $RepositoryRoot rev-list --parents -n 1 $Contract.authority_head 2>$null)
    if ($LASTEXITCODE -ne 0) { throw "Cannot resolve GitHub image authority parent." }
    Assert-Equal ($parents -join "") "$($Contract.authority_head) f838d508f1aa4630f299b937d4db775b12824c91" "GitHub image allowlist authority direct parent"
    $paths = @(& git -C $RepositoryRoot diff-tree --no-commit-id --name-only -r $Contract.authority_head 2>$null)
    if ($LASTEXITCODE -ne 0) { throw "Cannot resolve GitHub image authority paths." }
    Assert-ExactSet $paths @("docs/execution/CURRENT_TASK.md", "docs/execution/S10_4_CI_OPERATING_BRIEF.md") "GitHub image authority-only paths"
}

function Assert-GitHubReceiptEnvironment {
    param($Receipt, [string]$Label)
    # Original raw receipt projection, API identity and checksum authenticity remain
    # mandatory terminal-audit evidence, not claims made by this offline validator.
    if (-not ($Receipt.PSObject.Properties.Name -ccontains "github_environment")) {
        Add-ValidationError "$Label is missing the prospective GitHub environment."
        return
    }
    $environment = $Receipt.github_environment
    $contract = $manifest.github_environment_contract
    if ($environment -isnot [System.Management.Automation.PSCustomObject]) {
        Add-ValidationError "$Label GitHub environment must be an object."
        return
    }
    $invariantFields = @($contract.PSObject.Properties.Name | Where-Object { $_ -cne "image_versions" })
    $receiptFields = @($invariantFields + "image_version")
    Assert-ExactSet @($environment.PSObject.Properties.Name) $receiptFields "$Label GitHub environment fields"
    foreach ($field in $receiptFields) {
        if (-not ($environment.PSObject.Properties.Name -ccontains $field) -or $environment.$field -isnot [string]) {
            Add-ValidationError "$Label GitHub environment $field must be a string."
            return
        }
        if ($field -cne "image_version") {
            Assert-Equal $environment.$field $contract.$field "$Label GitHub environment $field"
        }
    }
    Assert-Contains @($contract.image_versions) $environment.image_version "$Label actual approved GitHub image"
    # Native receipt callers/schema require runner_image; the existing equivalence
    # receipt shape records the actual image only inside github_environment.
    if ($Receipt.PSObject.Properties.Name -ccontains "runner_image") {
        if ($Receipt.runner_image -isnot [string]) {
            Add-ValidationError "$Label runner_image must be a string."
            return
        }
        Assert-Equal $Receipt.runner_image "$($environment.image_os)-$($environment.image_version)" "$Label actual GitHub runner image"
    }
    Assert-Equal $Receipt.source_product_head $ProductHead "$Label GitHub source head"
    if ($Receipt.source_product_head -ceq $contract.authority_head) {
        Add-ValidationError "$Label requires a strict post-authority source head."
    }
    Assert-Ancestor $contract.authority_head $Receipt.source_product_head "$Label prospective GitHub ancestry"
    Assert-Equal (Get-GitBlobSha256 $Receipt.source_product_head ".github/workflows/ios-ci-worker.yml") $contract.worker_source_sha256 "$Label run-head GitHub producer"
    $sourceManifest = Get-GitJson $Receipt.source_product_head "docs/design/s10/authority/s10.4-automation-amendment-v1/manifest.json"
    if (-not ($sourceManifest.PSObject.Properties.Name -ccontains "github_environment_contract")) {
        Add-ValidationError "$Label source head lacks the prospective GitHub contract."
        return
    }
    if ($sourceManifest.github_environment_contract -isnot [System.Management.Automation.PSCustomObject]) {
        Add-ValidationError "$Label source contract must be an object."
        return
    }
    Assert-ExactSet @($sourceManifest.github_environment_contract.PSObject.Properties.Name) @($contract.PSObject.Properties.Name) "$Label source contract fields"
    foreach ($field in $invariantFields) {
        if (-not ($sourceManifest.github_environment_contract.PSObject.Properties.Name -ccontains $field) -or $sourceManifest.github_environment_contract.$field -isnot [string]) {
            Add-ValidationError "$Label source contract $field must be a string."
            return
        }
        Assert-Equal $sourceManifest.github_environment_contract.$field $contract.$field "$Label source contract $field"
    }
    $sourceContract = $sourceManifest.github_environment_contract
    if (-not ($sourceContract.PSObject.Properties.Name -ccontains "image_versions") -or
        $sourceContract.image_versions -isnot [System.Array] -or
        @($sourceContract.image_versions).Count -ne 2 -or
        @($sourceContract.image_versions | Where-Object { $_ -isnot [string] }).Count -ne 0) {
        Add-ValidationError "$Label source image_versions must be exactly two strings."
        return
    }
    Assert-H411Ordered $sourceContract.image_versions $contract.image_versions "$Label source image allowlist"
}

function Get-ZipEntryText {
    param([string]$ZipPath, [string]$Suffix)
    Add-Type -AssemblyName System.IO.Compression
    $archive = [IO.Compression.ZipFile]::OpenRead($ZipPath)
    try {
        $entry = @($archive.Entries | Where-Object { $_.FullName.EndsWith($Suffix, [StringComparison]::Ordinal) })
        if ($entry.Count -ne 1) {
            throw "Expected one ZIP entry ending '$Suffix'; found $($entry.Count)."
        }
        $reader = [IO.StreamReader]::new($entry[0].Open(), [Text.UTF8Encoding]::new($false), $true)
        try { return $reader.ReadToEnd() } finally { $reader.Dispose() }
    }
    finally {
        $archive.Dispose()
    }
}

function Invoke-SchemaValidation {
    param([string]$ValidatorText, [string]$SchemaPath, [string]$InstancePath)
    $output = $ValidatorText | & $PythonCommand - --schema $SchemaPath --instance $InstancePath 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Schema validation failed for $InstancePath`n$($output -join "`n")"
    }
    Write-Host ($output -join "`n")
}

function Invoke-SchemaAudit {
    param([string]$ValidatorText, [string]$SchemaPath)
    $output = $ValidatorText | & $PythonCommand - --schema $SchemaPath --instance $manifestPath 2>&1
    $schemaErrors = @($output | Where-Object { ([string]$_).Contains('ERROR: $schema', [StringComparison]::Ordinal) })
    if ($schemaErrors.Count -ne 0) {
        throw "Schema subset audit failed for $SchemaPath`n$($schemaErrors -join "`n")"
    }
    Write-Host "PASS: schema subset audit $SchemaPath"
}

function Invoke-FrozenSchemaValidation {
    param(
        [string]$ValidatorText,
        [string]$SchemaSuffix,
        [string]$InstancePath,
        [string]$InstanceSuffix = ""
    )

    $temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) "assetrounds-s10-$([Guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Path $temporaryRoot | Out-Null
    try {
        $schemaPath = Join-Path $temporaryRoot "schema.json"
        [IO.File]::WriteAllText($schemaPath, (Get-ZipEntryText $packagePath $SchemaSuffix), [Text.UTF8Encoding]::new($false))
        $resolvedInstancePath = $InstancePath
        if (-not [string]::IsNullOrWhiteSpace($InstanceSuffix)) {
            $resolvedInstancePath = Join-Path $temporaryRoot "instance.json"
            [IO.File]::WriteAllText($resolvedInstancePath, (Get-ZipEntryText $packagePath $InstanceSuffix), [Text.UTF8Encoding]::new($false))
        }
        elseif ($SchemaSuffix -ceq "/Handoff/s10-activation.schema.json" -and $InstancePath -ceq $activationPath) {
            # H420 adds one separately checked policy object; every original
            # activation field still passes the unchanged closed V4.1 schema.
            $activationProjection = Read-JsonFile $InstancePath
            $activationPolicy = Get-H411Field $activationProjection 's10_4_acceptance_policy'
            if ($activationPolicy -isnot [pscustomobject]) {
                Add-ValidationError 'H420 activation acceptance policy must be an object.'
            }
            else {
                Assert-Equal (Get-H411CanonicalSHA256 $activationPolicy) (Get-H411CanonicalSHA256 $h413Policy) 'H420 complete activation policy equals manifest policy'
            }
            $activationProjection.PSObject.Properties.Remove('s10_4_acceptance_policy')
            $resolvedInstancePath = Join-Path $temporaryRoot "activation-original-fields.json"
            [IO.File]::WriteAllText($resolvedInstancePath, ($activationProjection | ConvertTo-Json -Depth 100), [Text.UTF8Encoding]::new($false))
        }
        Invoke-SchemaValidation $ValidatorText $schemaPath $resolvedInstancePath
    }
    finally {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
    }
}

function Get-TaskIdentityJson {
    param($Task)
    return [ordered]@{
        task_id = $Task.task_id
        title = $Task.title
        critical = $Task.critical
        screen_state_ids = @($Task.screen_state_ids)
    } | ConvertTo-Json -Depth 10 -Compress
}

function Get-ComponentIdentityJson {
    param($Component)
    return [ordered]@{
        component_id = $Component.component_id
        native_control = $Component.native_control
        source_paths = @($Component.source_paths)
        token_ids = @($Component.token_ids)
        isolated_test_selectors = @($Component.isolated_test_selectors)
        status = $Component.status
    } | ConvertTo-Json -Depth 20 -Compress
}

function Get-CoverageIdentityJson {
    param($Coverage)
    return [ordered]@{
        screen_state_id = $Coverage.screen_state_id
        component_ids = @($Coverage.component_ids)
        token_ids = @($Coverage.token_ids)
        status = $Coverage.status
    } | ConvertTo-Json -Depth 20 -Compress
}

# H413_REQUIRED_PROFILE_FUNCTIONS_BEGIN
# This is an evidence-policy layer. Native execution remains bound to E.
function Get-H413EvidencePolicyPaths {
    return @(
        'Scripts/s10-4-ci.py',
        'Scripts/test-s10-4-ci.py',
        'AGENTS.md',
        'docs/product/BUILD_PLAN_V4.md',
        'docs/execution/CODEX_EXECUTION_CONTRACT_V4.md',
        'docs/execution/V4_IMPLEMENTATION_RUNBOOK.md',
        'docs/execution/S10_4_CI_OPERATING_BRIEF.md',
        'docs/execution/CURRENT_TASK.md',
        'docs/design/s10/s10-activation.json',
        'docs/design/s10/authority/s10.4-automation-amendment-v1/manifest.json',
        'docs/design/s10/authority/s10.4-automation-amendment-v1/s10-visual-regression.schema.json',
        'docs/design/s10/authority/s10.4-automation-amendment-v1/s10-accessibility-common-tasks.schema.json',
        'docs/design/s10/authority/s10.4-automation-amendment-v1/validate-s10-contracts.ps1',
        'docs/design/s10/s10-accessibility-common-tasks.json',
        'docs/design/s10/s10-token-coverage.json',
        'docs/design/s10/s10-visual-regression.json'
    )
}

function Assert-H413Policy {
    param($Policy, $NativeManifest, [string]$ExpectedProductHead)
    $commonKeys = @('policy_id','authority_id','native_evidence_head','native_manifest_sha256',
        'required_shard_ids','deferred_shard_ids','required_visual_cell_count','deferred_visual_cell_count',
        'required_accessibility_row_count','deferred_accessibility_row_count','minimum_core_smoke','evidence_policy_path_allowlist')
    $finalKeys = @($commonKeys) + @('selected_producer_run_id','selected_shared_build_identity_sha256','selected_producer_qualification_sha256')
    $preparationKeys = @($commonKeys) + @('producer_binding_status','observed_own_head_producer_run_id','observed_own_head_producer_request_id')
    $isPreparation = @($Policy.PSObject.Properties.Name) -ccontains 'producer_binding_status'
    Assert-ExactSet @($Policy.PSObject.Properties.Name) $(if ($isPreparation) { $preparationKeys } else { $finalKeys }) 'H413 policy fields'
    Assert-Equal $Policy.policy_id 's10.4.current-seven-with-minimum-verification-deferred.v1' 'H420 policy ID'
    Assert-Equal $Policy.authority_id 'H420' 'H420 authority ID'
    $h420ExpectedSmokePolicy = '{"schema_version":1,"contract_id":"s10.4.minimum-core-smoke.v1","acceptance_scope":"DEFERRED","shard_id":"s10.4.minimum.minimum-os","segment_id":"none","execution_lane":"github-xcode-26.6-shared-build-acceptance","runner_provider":"github","device_profile_id":"iphone-se-3-ios-18.0-minimum","simulator_runtime":"iOS 18.0","simulator_os_build":"22A3351","appearance":"light","contrast":"standard","locale_profile_id":"en-US-release","layout_direction":"left_to_right","content_size_category":"UICTContentSizeCategoryL","checkpoint_count":6,"checkpoint_ids":["launch","sign-saved","capture-review","report-saved","report-reopened","settings"],"attachment_count":7,"catalog_visual_cell_credit":0,"catalog_accessibility_row_credit":0,"full_matrix_eligible":false,"full_shard_complete":false,"full_segment_complete":false,"human_review_required":false,"native_pass_required":false,"complete_original_integrity_required":true}' | ConvertFrom-Json
    Assert-Equal (Get-H411CanonicalSHA256 $Policy.minimum_core_smoke) (Get-H411CanonicalSHA256 $h420ExpectedSmokePolicy) 'H420 exact deferred smoke policy; six checkpoints/seven attachments and original integrity preserved'
    if ([string]$Policy.native_evidence_head -cnotmatch '^[0-9a-f]{40}$') { Add-ValidationError 'H413 malformed native head' }
    if (-not [string]::IsNullOrWhiteSpace($ExpectedProductHead)) {
        Assert-Equal $Policy.native_evidence_head $ExpectedProductHead 'H413 native evidence E'
    }
    if ([string]$Policy.native_manifest_sha256 -cnotmatch '^[0-9A-F]{64}$') { Add-ValidationError 'H413 malformed native_manifest_sha256' }
    if ($isPreparation) {
        Assert-Equal $Policy.producer_binding_status 'PENDING_COMPLETE_ORIGINAL_AUDIT_AND_ROOT_SELECTION' 'H413 preparation producer status'
        Assert-Equal $Policy.observed_own_head_producer_run_id 34477382489 'H418 observed own-head producer'
        Assert-Equal $Policy.observed_own_head_producer_request_id '3a0af74cfb9349dd9a4d645bd5eeda57' 'H418 observed own-head producer request'
        Add-ValidationError 'H418 producer qualification and root selection remain pending; preparation cannot pass final AuthorityH.'
    } else {
        foreach ($field in @('selected_shared_build_identity_sha256','selected_producer_qualification_sha256')) {
            if ([string]$Policy.$field -cnotmatch '^[0-9A-F]{64}$') { Add-ValidationError "H413 malformed $field" }
        }
        if ([string]$Policy.selected_producer_run_id -cnotmatch '^[1-9][0-9]*$') { Add-ValidationError 'H413 malformed producer run ID' }
    }
    $required = @($NativeManifest.shards | Where-Object {
        $_.device_profile_id -ceq 'iphone-17-ios-26.2-current'
    } | ForEach-Object { $_.shard_id })
    $deferred = @($NativeManifest.shards | Where-Object {
        $_.device_profile_id -ceq 'iphone-se-3-ios-18.0-minimum'
    } | ForEach-Object { $_.shard_id })
    Assert-Equal $required.Count 7 'H418 required profile count'
    Assert-Equal $deferred.Count 7 'H418 deferred profile count'
    Assert-ExactSet @($Policy.required_shard_ids) $required 'H413 required profiles'
    Assert-ExactSet @($Policy.deferred_shard_ids) $deferred 'H413 deferred profiles'
    Assert-ExactSet @(@($Policy.required_shard_ids) + @($Policy.deferred_shard_ids)) @($NativeManifest.shards.shard_id) 'H413 exact disjoint catalog partition'
    Assert-Equal $Policy.required_visual_cell_count ($required.Count * $NativeManifest.matrix_contract.state_count) 'H413 required visual count'
    Assert-Equal $Policy.deferred_visual_cell_count ($deferred.Count * $NativeManifest.matrix_contract.state_count) 'H413 deferred visual count'
    Assert-Equal $Policy.required_accessibility_row_count ($required.Count * $NativeManifest.required_task_ids.Count) 'H413 required accessibility count'
    Assert-Equal $Policy.deferred_accessibility_row_count ($deferred.Count * $NativeManifest.required_task_ids.Count) 'H413 deferred accessibility count'
    Assert-ExactSet @($Policy.evidence_policy_path_allowlist) @(Get-H413EvidencePolicyPaths) 'H413 finite authorized evidence-policy paths'
}

function Assert-H413EvidenceDelta {
    param([object[]]$Paths, $Policy)
    Assert-ExactSet @($Policy.evidence_policy_path_allowlist) @(Get-H413EvidencePolicyPaths) 'H413 immutable evidence-policy path envelope'
    foreach ($path in $Paths) {
        if ([string]$path -cnotin @(Get-H413EvidencePolicyPaths)) {
            Add-ValidationError "E..K contains non-evidence-policy path '$path'."
        }
    }
}

# H419_APPROVED_ORIGINAL_LOADER_BEGIN
function Get-H419ApprovedOriginalLoader {
    # Final K stores canonical pair bytes, but operational 0306 is intentionally
    # executable only from its independently reviewed original physical path.
    return @'
import hashlib
def checked_pair_bytes(binding,relative,expected):
 if binding!={'path':relative,'sha256':expected}:raise ValueError('closed original loader binding differs')
 path=root
 for part in pathlib.PurePosixPath(relative).parts:
  path=path/part
  if path.is_symlink() or (hasattr(path,'is_junction') and path.is_junction()):raise ValueError('linked original loader path')
 if not path.is_file() or path.stat().st_nlink!=1:raise ValueError('original loader file missing or aliased')
 raw=path.read_bytes()
 if hashlib.sha256(raw).hexdigest().upper()!=expected:raise ValueError('original loader bytes differ')
 return path,raw
pair={'controller':('s10-4-ci.py','0306E6BC8F4F89AFA6E983259A612481BC9807AEB911FB2C3AE0103673B0F6A0'),'protocol':('test-s10-4-ci.py','1FC4EC83DB296C1BE54533D21C95E13D8FF0FBCD355D01ADC4FC247919D24632')}
if set(c['final_pair'])!=set(pair):raise ValueError('final canonical pair fields differ')
for role,(file,expected) in pair.items():checked_pair_bytes(c['final_pair'][role],'Scripts/'+file,expected)
review_path,review_raw=checked_pair_bytes(c['operational_review'],'Temp/S10_4_CI/unacquired-hosted-worker/independent-review/OPERATIONAL_REVIEW_0306.json','91B229BB01B767639D93CBE76CFA6EBD7E4B6545DD816F5A6D4BD51B94C4A025')
original_review=json.loads(review_raw)
if set(original_review['operational'])!=set(pair):raise ValueError('reviewed original pair fields differ')
for role,(file,expected) in pair.items():
 relative='Temp/S10_4_CI/unacquired-hosted-worker/controller-draft/'+file;binding=original_review['operational'][role]
 if set(binding)!={'path','sha256'} or pathlib.Path(binding['path']).resolve()!=(root/relative).resolve() or binding['sha256']!=expected:raise ValueError('approved original physical path/hash differs')
 original_path,_=checked_pair_bytes({'path':relative,'sha256':expected},relative,expected)
 if role=='controller':p=original_path
s=importlib.util.spec_from_file_location('h419_approved_original_controller',p);m=importlib.util.module_from_spec(s);sys.modules[s.name]=m;s.loader.exec_module(m)
'@
}
# H419_APPROVED_ORIGINAL_LOADER_END

# H419_OPERATIONAL_EVIDENCE_BEGIN
function Assert-H419ReviewShape {
    param($Review, $Contract)
    if ($null -eq $Review) { Add-ValidationError 'H419 final review missing'; return }
    Assert-ExactSet @($Review.PSObject.Properties.Name) @('schemaVersion','recordType','decision','reviewer','reviewedAtUTC','unresolvedIssues','proposal','ownerApproval','policyScopeReview','classifierReview','baseline','operational','fixed','lineages','tests','diff','inverse') 'H419 original review fields'
    Assert-Equal $Review.schemaVersion 1 'H419 review version'
    Assert-Equal $Review.recordType 'S10_4_OPERATIONAL_CONTROLLER_REVIEW' 'H419 review kind'
    Assert-Equal $Review.decision 'GO' 'H419 independent GO'
    if ([string]::IsNullOrWhiteSpace([string]$Review.reviewer) -or [string]$Review.reviewer -cin @('author','root','task owner')) { Add-ValidationError 'H419 independent reviewer required' }
    Assert-Equal @($Review.unresolvedIssues).Count 0 'H419 unresolved findings'
    Assert-Equal $Review.fixed.head $Contract.native_evidence_head 'H419 review E'
    Assert-Equal $Review.fixed.sourceIdentitySHA256 $Contract.source_identity_sha256 'H419 review source'
    Assert-Equal $Review.ownerApproval.sha256 $Contract.owner_approval.sha256 'H419 review approval'
    Assert-Equal $Review.proposal.sha256 $Contract.proposal_sha256 'H419 review proposal'
    Assert-Equal (Get-H411CanonicalSHA256 $Review.baseline.files) (Get-H411CanonicalSHA256 $Contract.baseline_files) 'H419 review Git baseline'
    Assert-Equal $Review.baseline.protocolReviewSHA256 $Contract.baseline_review_sha256 'H419 original baseline review'
}

function Invoke-H419OriginalGuard {
    param($Contract)
    # Only original offline guards: no fresh(), operation_guard(), provider or collector mutation.
    $program = @'
import importlib.util,json,pathlib,sys
sys.dont_write_bytecode=True
root=pathlib.Path(sys.argv[1]);c=json.loads(sys.argv[2]);final=c['final_pair']
__H419_APPROVED_ORIGINAL_LOADER__
matrix=m.Matrix(root/c['matrix']['path'],root/c['operational_review']['path'],c['operational_review']['sha256']);review=matrix.review()
m.require(review['files']=={'Scripts/s10-4-ci.py':final['controller']['sha256'],'Scripts/test-s10-4-ci.py':final['protocol']['sha256']},'final pair differs')
rows=m.records(matrix,True);by_request={r['intent']['requestID']:r for r in rows}
def required_history(rows,c):
 required={r['requestID'] for r in m.LINEAGE_ROOTS if not r['conditional']};witness_requests=set()
 required.update(r['intent']['requestID'] for r in rows if r['intent'].get('protocolReview',{}).get('operationalException') is True)
 conditional_tuples={(r['kind'],r['shardID'],r['segmentID']) for r in m.LINEAGE_ROOTS if r['conditional']}
 for row in rows:
  intent=row['intent']
  if intent['head']!=c['native_evidence_head'] or (intent['kind'],intent['shardID'],intent['segmentID']) not in conditional_tuples:continue
  for ap in sorted((row['path']/'audits').glob('*.json')):
   a=m.load(ap)
   if a.get('completeOriginalAudit') is True and a.get('unacquiredHostedWorkers'):
    m.require(row['resolution'] and a['runID']==row['resolution']['runID'] and a['head']==c['native_evidence_head'] and a['collectorSHA256']==c['final_pair']['controller']['sha256'],'conditional witness audit identity/collector differs')
    required.add(intent['requestID']);witness_requests.add(intent['requestID'])
 return required,witness_requests
def require_history_items(items,required):
 m.require(type(items) is list and len({x['request_id'] for x in items})==len(items) and {x['request_id'] for x in items}==required,'operational history omitted/foreign/duplicate')
def expected_collector(lineage,a,c):
 return c['baseline_files']['Scripts/s10-4-ci.py'] if lineage['conditional'] and not a.get('unacquiredHostedWorkers') else c['final_pair']['controller']['sha256']
def require_collector(lineage,a,cache,c):
 expected=expected_collector(lineage,a,c)
 m.require(a['collectorSHA256']==expected and cache['toolSHA256']==expected,'audit/cache collector routing differs')
required,witness_requests=required_history(rows,c)
items=c['operational_records'];require_history_items(items,required)
def validate_intent_binding(intent,c):
 m.require(intent['sourceIdentitySHA256']==c['source_identity_sha256'] and intent['mainSHA']==c['main_sha'],'operational intent source/main differs')
 proof=intent['producerProof'];expected=dict(c['producer'],sourceIdentitySHA256=c['source_identity_sha256'],producerUnitCount=5,productsPOSIXModesVerifiedFromOriginalTAR=True)
 m.require(proof==expected,'operational intent producer/source/five-unit/POSIX proof differs')
results=[]
for item in items:
 m.require(set(item)=={'request_id','audit','original_cache'},'record fields differ')
 row=by_request[item['request_id']];intent=row['intent'];rid=row['resolution']['runID'];originals=m.original_root(row)
 validate_intent_binding(intent,c)
 lineage=matrix.lineage(intent,conditional_level='audited')
 ap=m.sealed_binding({'path':str(root/item['audit']['path']),'sha256':item['audit']['sha256']},parent=row['path']/'audits');a=m.load(ap)
 m.require(a['head']==matrix.head and a['runID']==rid and a['completeOriginalAudit'] is True and a['allAvailableOriginalsVerified'] is True,'incomplete/foreign audit')
 m.require(item['request_id'] not in witness_requests or bool(a.get('unacquiredHostedWorkers')),'conditional activating witness omitted')
 cp=m.sealed_binding({'path':str(root/item['original_cache']['path']),'sha256':item['original_cache']['sha256']},parent=matrix.registry/'verified-originals'/str(rid));cache=m.load(cp)
 m.require(cp.stem.split('-')[-1]==m.sha(cp),'cache seal differs')
 require_collector(lineage,a,cache,c)
 m.require(cache['binding']=={'runID':rid,'head':matrix.head,'sourceIdentitySHA256':intent['sourceIdentitySHA256']} and cache['root']==str(m.wide(originals)) and cache['excludeAudits'] is True,'cache source differs')
 m.require(m.cache_inventory(originals,True)=={n:{k:v for k,v in e.items() if k!='sha256'} for n,e in cache['files'].items()},'original metadata changed; original owner must reverify')
 m.require(cache['facts']['originalFilesSHA256']==a['originalFilesSHA256'],'original set differs')
 run=m.load(originals/'run.json');jobs=m.load(originals/'jobs.json')['jobs'];arts=m.load(originals/'artifacts.json')['artifacts'];witnesses=[]
 for w in a.get('unacquiredHostedWorkers',[]):
  actual=m.retained_unacquired(originals,run,next(j for j in jobs if j['id']==w['jobID']),intent,arts,jobs);m.require(actual==w,'unavailable-log witness differs');witnesses.append(actual)
 if witnesses:
  m.require(all(a.get(k) is False for k in ('nativeUIExecuted','fullSegmentComplete','fullShardComplete','formalAcceptance','humanReviewGranted')),'unacquired native/acceptance claim')
  m.require(all(a.get(k,0)==0 for k in ('strictOwnedCount','checkpointCount','candidatePNGCount','ownedJourneyCount')) and all(w['gap'] in a['gaps'] for w in witnesses),'unacquired coverage/gap differs')
 if intent.get('protocolReview',{}).get('operationalException') is True:
  m.require(intent['protocolReview']==review,'dispatch review differs');retry=intent['retry'];prior=next(r for r in rows if r['resolution'] and r['resolution']['runID']==retry['runID'])
  pa=[p for p in (prior['path']/'audits').glob('*.json') if m.sha(p)==retry['auditSHA256']]
  m.require(len(pa)==1 and m.load(pa[0])['completeOriginalAudit'] is True and not m.load(pa[0]).get('knownDeterministicFailure',False) and retry['reason'].strip(),'retry predecessor/reason differs')
 results.append({'requestID':item['request_id'],'runID':rid,'lineage':lineage,'auditSHA256':item['audit']['sha256']})
m.require(matrix.review()==review,'review changed')
print(json.dumps({'review':review,'records':results,'formalAcceptance':False},separators=(',',':')))
'@
    $program = $program.Replace('__H419_APPROVED_ORIGINAL_LOADER__', (Get-H419ApprovedOriginalLoader))
    $output = @(& $PythonCommand -c $program $RepositoryRoot (ConvertTo-Json $Contract -Depth 100 -Compress) 2>&1)
    if ($LASTEXITCODE -ne 0 -or $output.Count -ne 1) { Add-ValidationError ('H419 original offline guard failed: ' + ($output -join ' ')); return }
    $value = $output[0] | ConvertFrom-Json -Depth 100
    Assert-Equal $value.review.sha256 $Contract.operational_review.sha256 'H419 executed original review'
    Assert-Equal $value.formalAcceptance $false 'H419 no acceptance from operational guard'
}

function Assert-H419OperationalEvidence {
    param($Contract)
    $script:h419WorkingPair = $null
    if ($null -eq $Contract) { return } # Ordinary path still requires working pair equal E.
    $before = $script:errors.Count
    Assert-ExactSet @($Contract.PSObject.Properties.Name) @('contract_id','binding_status','native_evidence_head','repository','ref','main_sha','source_identity_sha256','producer','baseline_files','baseline_review_sha256','owner_approval','proposal_sha256','preserved_human_receipts','matrix','final_pair','operational_review','operational_records') 'H419 contract fields'
    Assert-Equal $Contract.contract_id 's10.4.operational-controller-evidence.v1' 'H419 contract ID'
    Assert-Equal $Contract.native_evidence_head '0adebd72ae0226a80e14eaf515ca133072fb1c76' 'H419 fixed native E'
    Assert-Equal $Contract.repository 'Asset-Rounds/AssetRounds' 'H419 repository'
    Assert-Equal $Contract.ref 'phase/s10-brand-refresh' 'H419 phase ref'
    Assert-Equal $Contract.main_sha '01233f789b1cef5a6f56c7ff4caa9271409cd3bc' 'H419 main/P'
    Assert-Equal $Contract.source_identity_sha256 'FA2E57BD20754B0E9844D8939B7BB4887448DC02D026F5EB635189B80C8E5F7A' 'H419 source identity'
    Assert-Equal (Get-H411CanonicalSHA256 $Contract.producer) (Get-H411CanonicalSHA256 ([pscustomobject]@{runID=34477382489;sharedBuildIdentitySHA256='0BE9475570B1F0B9CC5C9520DA4F2D11308D034033ABD17C4F6E61F1901DADAE';producerQualificationSHA256='A1A9BF1B92B4CABFD150702EF3F2E218590C290B52B685E598926CF5D158542B'})) 'H419 exact selected producer'
    $baseline = [ordered]@{'Scripts/s10-4-ci.py'='58BFD7988C9A4DDD847D96532BBE5A9BB617ADDC5C3B1521F9FEE06F28228354';'Scripts/test-s10-4-ci.py'='857AA47537D225FE2DF7AFAAD0C0EF4DB60509CCCE910E334920927571FB74B0'}
    Assert-Equal (Get-H411CanonicalSHA256 $Contract.baseline_files) (Get-H411CanonicalSHA256 $baseline) 'H419 fixed Git pair'
    foreach ($path in $baseline.Keys) { Assert-Equal (Get-GitBlobSha256 $Contract.native_evidence_head $path) $baseline[$path] "H419 immutable E Git $path" }
    Assert-Equal $Contract.baseline_review_sha256 '407A261A82F058D4AFF040DA7E0C4356FBE8DF1A5DA2CD2C87B36AFA447DB7FF' 'H419 baseline review'
    Assert-Equal $Contract.owner_approval.path 'Temp/S10_4_CI/unacquired-hosted-worker/owner-exception-proposal/OWNER_APPROVAL_20260910.json' 'H419 owner path'
    Assert-Equal $Contract.owner_approval.sha256 'CB0CC46E78EFF32439B7A1D8A430D68C1130051AC960D74F90C8F5AD6D673116' 'H419 owner hash'
    Assert-Equal $Contract.proposal_sha256 '917509BAC9D40A572C04AFC9880B51A79E5C17CD272BADDA79583AEE4CFDC51A' 'H419 proposal'
    $owner = Read-H411Evidence $Contract.owner_approval 'H419 owner approval'
    Assert-Equal $owner.approved $true 'H419 explicit approval'
    Assert-Equal $owner.nativeEvidenceHead $Contract.native_evidence_head 'H419 approved native E'
    Assert-Equal $owner.proposalSHA256 $Contract.proposal_sha256 'H419 approved proposal'
    Assert-ExactSet @($Contract.preserved_human_receipts.sha256) @('E26B264BAD7A8EA35AC1428F3CA0637839257BD92E0F665BF32F61D4828632AF','0879B2C35AFC4FE548329B9D0D3E2038B37F10D165FA7ACA6D78CA4CFF29BE58') 'H419 immutable human receipts'
    $cellIDs = @()
    foreach ($binding in $Contract.preserved_human_receipts) {
        $human = Read-H411Evidence $binding 'H419 human receipt'
        Assert-Equal $human.candidateHead $Contract.native_evidence_head 'H419 human E'
        foreach ($profile in $human.profiles) { foreach ($cell in $profile.approvedCells) { Assert-Equal $cell.reviewStatus 'APPROVED' 'H419 original decision'; $cellIDs += $cell.cellID } }
    }
    Assert-Equal $cellIDs.Count 335 'H419 original approval count'
    Assert-Equal @($cellIDs | Sort-Object -Unique).Count 335 'H419 unique original approvals'
    if ($Contract.binding_status -cne 'READY' -or $null -eq $Contract.final_pair -or $null -eq $Contract.operational_review -or $null -eq $Contract.operational_records) {
        Add-ValidationError 'H419 pair/review/records pending; every accepting lifecycle rejects'; return
    }
    Assert-Equal $Contract.operational_review.sha256 '91B229BB01B767639D93CBE76CFA6EBD7E4B6545DD816F5A6D4BD51B94C4A025' 'H419 final independent review seal'
    Assert-ExactSet @($Contract.final_pair.PSObject.Properties.Name) @('controller','protocol') 'H419 final pair fields'
    foreach ($name in @('controller','protocol')) {
        $binding = $Contract.final_pair.$name
        Assert-ExactSet @($binding.PSObject.Properties.Name) @('path','sha256') 'H419 pair fields'
        $file = if ($name -ceq 'controller') {'s10-4-ci.py'} else {'test-s10-4-ci.py'}
        Assert-Equal $binding.path ('Scripts/' + $file) 'H419 final canonical pair path'
        $expectedHash = if ($name -ceq 'controller') {'0306E6BC8F4F89AFA6E983259A612481BC9807AEB911FB2C3AE0103673B0F6A0'} else {'1FC4EC83DB296C1BE54533D21C95E13D8FF0FBCD355D01ADC4FC247919D24632'}
        Assert-Equal $binding.sha256 $expectedHash 'H419 final independently reviewed pair hash'
        if ([string]$binding.sha256 -cnotmatch '^[0-9A-F]{64}$') { Add-ValidationError 'H419 pair hash missing/malformed' }
        $physical = $RepositoryRoot
        foreach ($part in ([string]$binding.path).Split('/')) {
            $physical = Join-Path $physical $part
            if (-not (Test-Path -LiteralPath $physical) -or ((Get-Item -LiteralPath $physical -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { Add-ValidationError 'H419 physical pair missing or linked'; return }
        }
        if (-not (Test-Path -LiteralPath $physical -PathType Leaf)) { Add-ValidationError 'H419 physical pair not ordinary file'; return }
        Assert-Equal (Get-Sha256 (Join-Path $RepositoryRoot $binding.path)) $binding.sha256 'H419 physical reviewed bytes before import'
    }
    $review = Read-H411Evidence $Contract.operational_review 'H419 actual independent review'
    Assert-H419ReviewShape $review $Contract
    $matrix = Read-H411Evidence $Contract.matrix 'H419 selected matrix'
    Assert-Equal $matrix.head $Contract.native_evidence_head 'H419 matrix E'
    if ($script:errors.Count -ne $before) { return }
    Invoke-H419OriginalGuard $Contract
    if ($script:errors.Count -eq $before) { $script:h419WorkingPair = $Contract.final_pair }
}
# H419_OPERATIONAL_EVIDENCE_END

function Assert-H413CollectorCorrection {
    param($Correction)
    $keys = @('contract_id','native_evidence_head','scope','ordinary_archive_limit_bytes','assembly_archive_limit_bytes',
        'expanded_archive_limit_bytes','member_limit','collector_ceiling_review_sha256','failed_marker_release_id',
        'owner_approval_receipt_sha256','owner_approval_recorded_at_utc','owner_approval_answer','proposal_sha256',
        'failed_marker_independent_review_sha256','implementation_report_sha256','first_request_id','first_run_id',
        'original_rejected_audit_sha256','original_files_sha256','preexecution_sha256','supplemental_audit_status',`
        'supplemental_audit_path','supplemental_audit_sha256','postexecution_result_sha256','postexecution_report_sha256','files')
    Assert-ExactSet @($Correction.PSObject.Properties.Name) $keys 'H413 collector/audit correction fields'
    Assert-Equal $Correction.contract_id 's10.4.collector-assembly-bound-and-failed-start-audit.v2' 'H413 collector/audit correction ID'
    Assert-Equal $Correction.native_evidence_head '2927b049bfdd8d5219a70e4d7e2f877ffb9b4000' 'H413 historical collector/audit native E'
    Assert-Equal $Correction.scope 'Original collection plus the exact approved failed-original factual audit only; native dispatch, successful marker parsing, segment/full-shard qualification and ProductHead E remain unchanged.' 'H413 collector/audit scope'
    Assert-Equal $Correction.ordinary_archive_limit_bytes 2147483648 'H413 unchanged ordinary/payload/TAR bound'
    Assert-Equal $Correction.assembly_archive_limit_bytes 8589934592 'H413 original aggregate transport bound'
    Assert-Equal $Correction.expanded_archive_limit_bytes 8589934592 'H413 unchanged expansion bound'
    Assert-Equal $Correction.member_limit 100000 'H413 unchanged member bound'
    Assert-Equal $Correction.collector_ceiling_review_sha256 '11D1214D3E68EBA239935EF7CCD9E625AF1014F5800159C0AF4B76C159503CD3' 'H413 collector-ceiling review'
    Assert-Equal $Correction.failed_marker_release_id 's10.4-failed-segment-start-audit-v1' 'H413 failed-marker release'
    Assert-Equal $Correction.owner_approval_receipt_sha256 '96C08778A13C985088CEF00905C16C7F2F6641A39523638D89F99A9126CCB75D' 'H413 owner approval receipt'
    if ($Correction.owner_approval_recorded_at_utc -isnot [DateTime]) { Add-ValidationError 'H413 owner approval time is not an ISO timestamp.' }
    else { Assert-Equal $Correction.owner_approval_recorded_at_utc.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.ffffffZ') '2026-09-10T02:19:12.853808Z' 'H413 owner approval time' }
    Assert-Equal $Correction.owner_approval_answer 'Approve audit-only exception' 'H413 exact owner approval answer'
    Assert-Equal $Correction.proposal_sha256 'B2D6134CD82B6D0E10121D15C6B7AFE7E5AC369B36E48178381A9412483BBEA9' 'H413 approved proposal'
    Assert-Equal $Correction.failed_marker_independent_review_sha256 'AAA9AFEC53B0F7369C0C8BF5338C3E90C01B2D079BC5D5854D6B9CE2BADD04E9' 'H413 failed-marker review'
    Assert-Equal $Correction.implementation_report_sha256 '078C373E87EC9A413B03CEC487497CD3023B7E808234DA6F9C4EE56E28FC001C' 'H413 failed-marker implementation report'
    Assert-Equal $Correction.first_request_id '25ca31a0246643f7b2b26d6391369f99' 'H413 first approved request'
    Assert-Equal $Correction.first_run_id 34423087881 'H413 first approved run'
    Assert-Equal $Correction.original_rejected_audit_sha256 '07D154CC4BD80B3CADA568336657FC35E04FDD68F13AAF699153FA2FBF22D806' 'H413 retained rejected audit'
    Assert-Equal $Correction.original_files_sha256 'C0D561BF488B3D88B3947FDB788D31BF1DD0CC81BB33A4545DAB83048BDD5EAD' 'H413 retained original inventory'
    Assert-Equal $Correction.preexecution_sha256 '82E3C5CE6EA958F9562C37E5E3CF3A9C364ED92B6E75823B40D6E361CAB62ABE' 'H413 audit preexecution provenance'
    Assert-Equal $Correction.supplemental_audit_status 'COMPLETE_REVIEWED_NONACCEPTING' 'H413 supplemental audit factual status'
    Assert-Equal $Correction.supplemental_audit_path 'audits/20260910T022225-bb30a942fa544361a96737625ce6d971.json' 'H413 supplemental audit path'
    Assert-Equal $Correction.supplemental_audit_sha256 '664DD9460540564E73755CECD3D8066C3B31E94F572F33142AC86D326ED44684' 'H413 supplemental audit hash'
    Assert-Equal $Correction.postexecution_result_sha256 'C464BE1085B8F851A9CF36302BA3330B89AE72CEB44EDE700E90D7733451A30A' 'H413 audit postexecution result'
    Assert-Equal $Correction.postexecution_report_sha256 '37555147E1C427AE3F47FD0DBC6F0E01D5050524806829665892052E4A24FD29' 'H413 audit postexecution review'
    Assert-ExactSet @($Correction.files.path) @('Scripts/s10-4-ci.py','Scripts/test-s10-4-ci.py') 'H413 exact collector/audit correction files'
    foreach ($entry in $Correction.files) {
        Assert-ExactSet @($entry.PSObject.Properties.Name) @('path','native_sha256','collector_ceiling_sha256','audit_release_sha256','actual_native_e_sha256') 'H418 collector/audit file fields'
        Assert-Equal (Get-GitBlobSha256 $h413Policy.native_evidence_head $entry.path) $entry.actual_native_e_sha256 "H418 actual-E collector $($entry.path)"
        if ($null -eq (Get-H411Field $manifest 'operational_evidence_contract')) {
        Assert-Equal (Get-Sha256 (Join-Path $RepositoryRoot $entry.path)) $entry.actual_native_e_sha256 "H418 working actual-E collector $($entry.path)"
        } elseif ($null -eq $script:h419WorkingPair) {
            Add-ValidationError 'H419 no qualified operational pair; physical-E check cannot be waived'
        } else {
            $role = if ($entry.path -ceq 'Scripts/s10-4-ci.py') { 'controller' } else { 'protocol' }
            Assert-Equal (Get-Sha256 (Join-Path $RepositoryRoot $entry.path)) $script:h419WorkingPair.$role.sha256 "H419 working K pair $($entry.path)"
        }
        if ($entry.path -ceq 'Scripts/s10-4-ci.py') {
            Assert-Equal $entry.collector_ceiling_sha256 'BD06609A78B77F3B4BA3CBB568FB8EB61D8D6655A41529E39C44F48DFD9C93AF' 'H413 preserved collector-ceiling controller'
            Assert-Equal $entry.audit_release_sha256 'E34BC9924C1F6AA650509184A1C66B2F7D4AB7E014DFF7BB2998FC5A1B80CCE0' 'H413 historical final audit controller'
        } else {
            Assert-Equal $entry.collector_ceiling_sha256 '898CDC2F2514CE363187D06A6CDA6E576E547F019DB9B804CC4D89E69EDA98EC' 'H413 preserved collector-ceiling tests'
            Assert-Equal $entry.audit_release_sha256 '303DCF4558A2BBCF6CCD7D425DC31A5A78F2E8620338557204DBDCCB8C3547E3' 'H413 historical final audit tests'
        }
    }
}

function Get-H413ConsumedPolicyPath {
    param([string]$RelativePath)
    # Bind the files actually consumed, including a separately invoked validator.
    switch -CaseSensitive ($RelativePath) {
        'docs/design/s10/authority/s10.4-automation-amendment-v1/manifest.json' { return $manifestPath }
        'docs/design/s10/authority/s10.4-automation-amendment-v1/s10-visual-regression.schema.json' { return $visualSchemaPath }
        'docs/design/s10/authority/s10.4-automation-amendment-v1/s10-accessibility-common-tasks.schema.json' { return $accessibilitySchemaPath }
        'docs/design/s10/authority/s10.4-automation-amendment-v1/validate-s10-contracts.ps1' { return $h413ValidatorPath }
        default { return Join-Path $RepositoryRoot $RelativePath }
    }
}

function Assert-H413WorkingPolicyBindings {
    param([string]$Mode, [string]$K, [string]$C)
    if ($Mode -ceq 'AuthorityH') { return }
    if ($Mode -cnotin @('EvidenceK','ReceiptC') -or $K -cnotmatch '^[0-9a-f]{40}$') {
        Add-ValidationError 'H413 working policy binding requires EvidenceK/ReceiptC and an exact K.'
        return
    }
    if ($Mode -ceq 'ReceiptC' -and $C -cnotmatch '^[0-9a-f]{40}$') {
        Add-ValidationError 'H413 ReceiptC policy binding requires an exact C.'
        return
    }
    foreach ($path in @(Get-H413EvidencePolicyPaths)) {
        # ReceiptC may append authorized CURRENT_TASK receipt pins. All other
        # policy/evidence bytes remain the immutable K bytes; K..C scope is
        # checked separately by the existing receipt lifecycle validation.
        $boundHead = if ($Mode -ceq 'ReceiptC' -and $path -ceq 'docs/execution/CURRENT_TASK.md') { $C } else { $K }
        $usedPath = Get-H413ConsumedPolicyPath $path
        Assert-Equal (Get-Sha256 $usedPath) (Get-GitBlobSha256 $boundHead $path) "H413 consumed $path equals $boundHead"
    }
}

function Get-H413HistoricalNativePaths {
    # Historical path provenance independently reviewed before this H413 repair.
    # This list never extends the separate E..K evidence-policy envelope.
    return @(
        '.github/workflows/bitrise-build-hub-probe.yml',
        '.github/workflows/ios-ci-worker.yml',
        'AGENTS.md',
        'FieldEvidenceApp.xcodeproj/xcshareddata/xcschemes/FieldEvidenceApp.xcscheme',
        'FieldEvidenceApp/Infrastructure/Commerce/StoreKitTransactionProcessor.swift',
        'Scripts/build-smoke.sh',
        'Scripts/s10-4-build-payload.py',
        'Scripts/s10-4-ci.py',
        'Scripts/s10-4-segment-assembler.sh',
        'Scripts/s10-4-segment-plan.json',
        'Scripts/s10-4-source-preflight.py',
        'Scripts/test-s10-4-ci.py',
        'Scripts/test-smoke.sh',
        'docs/design/s10/s10-activation.json',
        'docs/execution/CODEX_EXECUTION_CONTRACT_V4.md',
        'docs/execution/S10_4_CI_OPERATING_BRIEF.md',
        'docs/execution/V4_IMPLEMENTATION_RUNBOOK.md',
        'docs/product/BUILD_PLAN_V4.md'
    )
}

function Assert-H413HistoricalNativeRepair {
    param($Repair, $Policy)
    Assert-Equal $Repair.authority_id 'H413' 'H413 historical repair authority'
    Assert-Equal $Repair.native_evidence_head '2927b049bfdd8d5219a70e4d7e2f877ffb9b4000' 'H413 historical repair native E'
    Assert-Equal $Repair.native_original_manifest_sha256 '1F26E7392E4EB2446DD03DBF09A6ACFF945FEC00B55AC0C80D870315BD3E6F08' 'H413 historical original manifest'
    $historicalK503 = 'bba048eb06ecd97945b7f8cd4bede55371c41257'
    & git -C $RepositoryRoot merge-base --is-ancestor '2927b049bfdd8d5219a70e4d7e2f877ffb9b4000' $historicalK503 2>$null
    if ($LASTEXITCODE -ne 0) { throw 'H413 candidate native E is not a descendant of preserved H417/K500 E.' }
    $k503Parents = @(& git -C $RepositoryRoot rev-list --parents -n 1 $historicalK503 2>$null)
    if ($LASTEXITCODE -ne 0) { throw 'Cannot resolve H413 K503 candidate native E.' }
    Assert-Equal ($k503Parents -join "") 'bba048eb06ecd97945b7f8cd4bede55371c41257 b87eef579f8170100598172e9710d69fd1255a9a' 'H413 K503 direct parent'
    $k503Paths = @(& git -C $RepositoryRoot diff-tree --no-commit-id --name-only -r $historicalK503 2>$null)
    if ($LASTEXITCODE -ne 0) { throw 'Cannot resolve H413 K503 candidate paths.' }
    Assert-ExactSet $k503Paths @('FieldEvidenceAppTests/S10_4AutomatedBrandLabTests.swift','Scripts/ui-smoke.sh','docs/execution/CURRENT_TASK.md') 'H413 exact K503 paths'
    Assert-Equal (Get-GitBlobSha256 $historicalK503 'FieldEvidenceAppTests/S10_4AutomatedBrandLabTests.swift') 'EB5D3C7B9B0457048D7C5687F4452DDB608EB8BDA190678102CA5E63D8376EC1' 'H413 K503 complete native unit bytes'
    Assert-Equal (Get-GitBlobSha256 $historicalK503 'Scripts/ui-smoke.sh') '50EE2448001D787D157677C38CF1F6E36B73656DDBD4770A447ABD27FAF1DE6C' 'H413 K503 complete native shell bytes'
    Assert-Equal (Get-GitBlobSha256 $historicalK503 'docs/execution/CURRENT_TASK.md') '1587A4A226033A6C7693BCAC76E0A42E931D136DB2BBBD86FC6B81F7CDEFE10F' 'H413 K503 native recovery record bytes'
    Assert-Equal (Get-GitBlobSha256 $historicalK503 'FieldEvidenceAppUITests/S10_3BrandMigrationUITests.swift') '5B5DB6CED7E85AD60BCB851C02E017E88BD14CCB2A3D8B9DAE8D5D63E4E54E46' 'H413 K503 retained complete UI bytes'
    Assert-Equal (Get-GitBlobSha256 $historicalK503 'Scripts/s10-4-ci.py') '57F0254A7DE734C1A10F7E7A21EF4075E173E3C13341DEC6D840BCD757513ECA' 'H413 K503 protected canonical controller'
    Assert-Equal (Get-GitBlobSha256 $historicalK503 'Scripts/test-s10-4-ci.py') '2519145431287A2F13EDBBA8A0739C73EB1CB58F6223D210088B47B4077D8FF7' 'H413 K503 protected canonical protocol tests'
    $k502Head = 'b87eef579f8170100598172e9710d69fd1255a9a'
    $k502Parents = @(& git -C $RepositoryRoot rev-list --parents -n 1 $k502Head 2>$null)
    if ($LASTEXITCODE -ne 0) { throw 'Cannot resolve preserved H413 K502 native head.' }
    Assert-Equal ($k502Parents -join "") 'b87eef579f8170100598172e9710d69fd1255a9a 1f1a6321e644b5e500fc40bb43d76436deb8b1bd' 'H413 K502 direct parent'
    $k502Paths = @(& git -C $RepositoryRoot diff-tree --no-commit-id --name-only -r $k502Head 2>$null)
    if ($LASTEXITCODE -ne 0) { throw 'Cannot resolve preserved H413 K502 paths.' }
    Assert-ExactSet $k502Paths @('FieldEvidenceAppTests/S10_4AutomatedBrandLabTests.swift','docs/execution/CURRENT_TASK.md') 'H413 exact K502 paths'
    Assert-Equal (Get-GitBlobSha256 $k502Head 'FieldEvidenceAppTests/S10_4AutomatedBrandLabTests.swift') '97A3340F1CF44C22415C52FDB3640127E5B895CEBAC1A85414833752A025641B' 'H413 K502 complete native unit bytes'
    Assert-Equal (Get-GitBlobSha256 $k502Head 'FieldEvidenceAppUITests/S10_3BrandMigrationUITests.swift') '5B5DB6CED7E85AD60BCB851C02E017E88BD14CCB2A3D8B9DAE8D5D63E4E54E46' 'H413 K502 retained complete UI bytes'
    Assert-Equal (Get-GitBlobSha256 $k502Head 'docs/execution/CURRENT_TASK.md') 'C2D75373787AFFB8E30C93937F3196CC686EA39F96AD0F548B2B48EB7C5B5BDD' 'H413 K502 native recovery record bytes'
    $k501Parents = @(& git -C $RepositoryRoot rev-list --parents -n 1 '1f1a6321e644b5e500fc40bb43d76436deb8b1bd' 2>$null)
    if ($LASTEXITCODE -ne 0) { throw 'Cannot resolve preserved H413 K501 native head.' }
    Assert-Equal ($k501Parents -join "") '1f1a6321e644b5e500fc40bb43d76436deb8b1bd 2927b049bfdd8d5219a70e4d7e2f877ffb9b4000' 'H413 K501 direct parent'
    $k501Paths = @(& git -C $RepositoryRoot diff-tree --no-commit-id --name-only -r '1f1a6321e644b5e500fc40bb43d76436deb8b1bd' 2>$null)
    if ($LASTEXITCODE -ne 0) { throw 'Cannot resolve preserved H413 K501 paths.' }
    Assert-ExactSet $k501Paths @('FieldEvidenceAppTests/S10_4AutomatedBrandLabTests.swift','FieldEvidenceAppUITests/S10_3BrandMigrationUITests.swift','docs/execution/CURRENT_TASK.md') 'H413 exact K501 paths'
    Assert-Equal (Get-GitBlobSha256 '1f1a6321e644b5e500fc40bb43d76436deb8b1bd' 'FieldEvidenceAppTests/S10_4AutomatedBrandLabTests.swift') '9C388B957362EE87F226A5EFC15E7760592B334F1BF9D10EC146B1690EAFD78B' 'H413 K501 complete native unit bytes'
    Assert-Equal (Get-GitBlobSha256 '1f1a6321e644b5e500fc40bb43d76436deb8b1bd' 'FieldEvidenceAppUITests/S10_3BrandMigrationUITests.swift') '5B5DB6CED7E85AD60BCB851C02E017E88BD14CCB2A3D8B9DAE8D5D63E4E54E46' 'H413 K501 complete UI bytes'
    Assert-Equal (Get-GitBlobSha256 '1f1a6321e644b5e500fc40bb43d76436deb8b1bd' 'docs/execution/CURRENT_TASK.md') '5BB2CD091591D7545386E0736B699FE32035E25371CFD6760BA5C5EA519DFD44' 'H413 K501 native recovery record bytes'
    $nativeParents = @(& git -C $RepositoryRoot rev-list --parents -n 1 'f838d508f1aa4630f299b937d4db775b12824c91' 2>$null)
    if ($LASTEXITCODE -ne 0) { throw 'Cannot resolve H413 native E parent.' }
    Assert-Equal ($nativeParents -join "") 'f838d508f1aa4630f299b937d4db775b12824c91 7facdb5902ea14d8fdd72e25e510dc58fe833422' 'H413 K499 direct parent'
    $nativePaths = @(& git -C $RepositoryRoot diff-tree --no-commit-id --name-only -r 'f838d508f1aa4630f299b937d4db775b12824c91' 2>$null)
    if ($LASTEXITCODE -ne 0) { throw 'Cannot resolve H413 native E paths.' }
    $h416Paths = @(
        '.github/workflows/bitrise-build-hub-probe.yml',
        '.github/workflows/ios-ci-worker.yml',
        '.github/workflows/ios-ci.yml',
        'FieldEvidenceAppTests/S10_4AutomatedBrandLabTests.swift',
        'Scripts/build-smoke.sh',
        'Scripts/s10-4-segment-plan.json',
        'Scripts/test-smoke.sh',
        'Scripts/ui-smoke.sh',
        'docs/design/s10/authority/s10.4-automation-amendment-v1/manifest.json',
        'docs/design/s10/authority/s10.4-automation-amendment-v1/s10-visual-regression.schema.json',
        'docs/design/s10/authority/s10.4-automation-amendment-v1/validate-s10-contracts.ps1',
        'docs/execution/CURRENT_TASK.md',
        'docs/execution/S10_4_CI_OPERATING_BRIEF.md'
    )
    Assert-ExactSet $nativePaths $h416Paths 'H413 exact H416/K499 paths'
    $k498Parents = @(& git -C $RepositoryRoot rev-list --parents -n 1 '7facdb5902ea14d8fdd72e25e510dc58fe833422' 2>$null)
    if ($LASTEXITCODE -ne 0) { throw 'Cannot resolve H413 K498 parent.' }
    Assert-Equal ($k498Parents -join "") '7facdb5902ea14d8fdd72e25e510dc58fe833422 de6ec602b60be275b6a881f7be8cb619b5e8c925' 'H413 K498 direct parent'
    $k498Paths = @(& git -C $RepositoryRoot diff-tree --no-commit-id --name-only -r '7facdb5902ea14d8fdd72e25e510dc58fe833422' 2>$null)
    if ($LASTEXITCODE -ne 0) { throw 'Cannot resolve H413 K498 paths.' }
    Assert-ExactSet $k498Paths @('.github/workflows/ios-ci-worker.yml','FieldEvidenceAppTests/S10_4AutomatedBrandLabTests.swift','docs/design/s10/authority/s10.4-automation-amendment-v1/manifest.json','docs/design/s10/authority/s10.4-automation-amendment-v1/s10-visual-regression.schema.json','docs/design/s10/authority/s10.4-automation-amendment-v1/validate-s10-contracts.ps1','docs/execution/CURRENT_TASK.md') 'H413 exact H415/K498 implementation paths'
    $authorityParents = @(& git -C $RepositoryRoot rev-list --parents -n 1 'de6ec602b60be275b6a881f7be8cb619b5e8c925' 2>$null)
    if ($LASTEXITCODE -ne 0) { throw 'Cannot resolve H413 H415 authority parent.' }
    Assert-Equal ($authorityParents -join "") 'de6ec602b60be275b6a881f7be8cb619b5e8c925 2ce166c2196d90b9d7fdd255e2453bcbed3af1cc' 'H413 H415 authority direct parent'
    $authorityPaths = @(& git -C $RepositoryRoot diff-tree --no-commit-id --name-only -r 'de6ec602b60be275b6a881f7be8cb619b5e8c925' 2>$null)
    if ($LASTEXITCODE -ne 0) { throw 'Cannot resolve H413 H415 authority paths.' }
    Assert-ExactSet $authorityPaths @('docs/execution/CURRENT_TASK.md','docs/execution/S10_4_CI_OPERATING_BRIEF.md') 'H413 exact H415 authority paths'
    Assert-Equal $Repair.provenance_report_sha256 '257BDE095858ED35BE46BFDAF5E56E172F3F76730366753CD2F4B8DF237FC005' 'H413 independently reviewed historical provenance report'
    Assert-Equal $Repair.h416_exact_commit 'f838d508f1aa4630f299b937d4db775b12824c91' 'H413 recorded H416 commit'
    Assert-Equal $Repair.h416_exact_parent '7facdb5902ea14d8fdd72e25e510dc58fe833422' 'H413 recorded H416 parent'
    Assert-Equal $Repair.h416_verified_path_count 13 'H413 recorded H416 path count'
    Assert-ExactSet @($Repair.h416_verified_paths.path) $h416Paths 'H413 recorded H416 paths'
    foreach ($row in $Repair.h416_verified_paths) {
        Assert-Equal (Get-GitBlobSha256 $Repair.h416_exact_parent $row.path) $row.parentSHA256 "H413 H416 parent bytes $($row.path)"
        Assert-Equal (Get-GitBlobSha256 $Repair.h416_exact_commit $row.path) $row.headSHA256 "H413 H416 head bytes $($row.path)"
        if (-not $row.changed) { Add-ValidationError "H413 unchanged H416 row $($row.path)" }
    }
    $h417Paths = @(
        '.github/workflows/ios-ci-worker.yml',
        'FieldEvidenceAppTests/S10_4AutomatedBrandLabTests.swift',
        'Scripts/s10-4-ci.py',
        'Scripts/test-s10-4-ci.py',
        'docs/design/s10/authority/s10.4-automation-amendment-v1/manifest.json',
        'docs/design/s10/authority/s10.4-automation-amendment-v1/s10-visual-regression.schema.json',
        'docs/design/s10/authority/s10.4-automation-amendment-v1/validate-s10-contracts.ps1',
        'docs/execution/CURRENT_TASK.md'
    )
    $h417AuthorityPaths = @('docs/execution/CURRENT_TASK.md','docs/execution/S10_4_CI_OPERATING_BRIEF.md')
    Assert-Equal $Repair.h417_exact_commit '2927b049bfdd8d5219a70e4d7e2f877ffb9b4000' 'H413 recorded historical H417 implementation'
    Assert-Equal $Repair.h417_exact_parent 'af107f2edf76202e2f1764efdab01fd973043e04' 'H413 recorded H417 implementation parent'
    Assert-Equal $Repair.h417_authority_commit 'af107f2edf76202e2f1764efdab01fd973043e04' 'H413 recorded H417 authority'
    Assert-Equal $Repair.h417_authority_parent 'f838d508f1aa4630f299b937d4db775b12824c91' 'H413 recorded H417 authority parent'
    Assert-Equal $Repair.h417_verified_path_count 8 'H413 recorded H417 implementation path count'
    Assert-Equal $Repair.h417_authority_path_count 2 'H413 recorded H417 authority path count'
    foreach ($stage in @(
        @{ Commit=$Repair.h417_exact_commit; Parent=$Repair.h417_exact_parent; Expected=$h417Paths; Rows=$Repair.h417_verified_paths },
        @{ Commit=$Repair.h417_authority_commit; Parent=$Repair.h417_authority_parent; Expected=$h417AuthorityPaths; Rows=$Repair.h417_authority_paths }
    )) {
        $parents = @(& git -C $RepositoryRoot rev-list --parents -n 1 $stage.Commit 2>$null)
        if ($LASTEXITCODE -ne 0) { throw 'Cannot resolve H413 H417 parent.' }
        Assert-Equal ($parents -join '') "$($stage.Commit) $($stage.Parent)" 'H413 H417 exact direct parent'
        $paths = @(& git -C $RepositoryRoot diff-tree --no-commit-id --name-only -r $stage.Commit 2>$null)
        if ($LASTEXITCODE -ne 0) { throw 'Cannot resolve H413 H417 paths.' }
        Assert-ExactSet $paths $stage.Expected 'H413 H417 exact source paths'
        Assert-ExactSet @($stage.Rows.path) $stage.Expected 'H413 H417 recorded source paths'
        foreach ($row in $stage.Rows) {
            Assert-Equal (Get-GitBlobSha256 $stage.Parent $row.path) $row.parentSHA256 "H413 H417 parent bytes $($row.path)"
            Assert-Equal (Get-GitBlobSha256 $stage.Commit $row.path) $row.headSHA256 "H413 H417 head bytes $($row.path)"
            if (-not $row.changed) { Add-ValidationError "H413 unchanged H417 row $($row.path)" }
        }
    }
    Assert-Equal $Repair.original_path_count 40 'H413 original historical path count'
    Assert-Equal $Repair.verified_added_path_count 18 'H413 reviewed historical path count'
    Assert-Equal $Repair.total_authorized_native_ancestry_paths 58 'H413 complete historical path count'
    Assert-ExactSet @($Repair.verified_added_paths) @(Get-H413HistoricalNativePaths) 'H413 exact reviewed historical additions'
    Assert-ExactSet @($Repair.authority_rows.path) @(Get-H413HistoricalNativePaths) 'H413 one provenance row per historical addition'
    foreach ($row in $Repair.authority_rows) {
        Assert-Equal (Get-GitBlobSha256 '2927b049bfdd8d5219a70e4d7e2f877ffb9b4000' $row.path) $row.nativeHeadFileSHA256 "H413 frozen historical native bytes $($row.path)"
        if (@($row.authorityKeys).Count -eq 0 -or [string]::IsNullOrWhiteSpace([string]$row.purposeAndPreservedInvariant) -or [string]::IsNullOrWhiteSpace([string]$row.certainty)) {
            Add-ValidationError "H413 incomplete historical provenance $($row.path)"
        }
    }
}

function Get-H413NativeSourceIdentity {
    param([string]$Head)
    # Parse source-owned constant expressions; never execute the historical helper.
    $program = @'
import ast, hashlib, json, re, subprocess, sys
root, head = sys.argv[1:]
def blob(path):
    return subprocess.check_output(['git','-C',root,'show',head+':'+path])
tree = ast.parse(blob('Scripts/s10-4-build-payload.py').decode('utf-8'))
definitions = {}
for node in tree.body:
    if isinstance(node, ast.Assign):
        for name in node.targets:
            if isinstance(name, ast.Name):
                definitions[name.id] = node.value
def literal(node, seen=()):
    if isinstance(node, ast.Constant) and isinstance(node.value, str):
        return node.value
    if isinstance(node, (ast.Tuple, ast.List)):
        return [literal(item, seen) for item in node.elts]
    if isinstance(node, ast.Name) and node.id not in seen:
        return literal(definitions[node.id], seen+(node.id,))
    if (isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)
            and isinstance(node.func.value, ast.Constant) and node.func.value.value == '/'
            and node.func.attr == 'join' and len(node.args) == 1 and not node.keywords):
        values = literal(node.args[0], seen)
        if not isinstance(values, list) or not all(isinstance(v,str) for v in values):
            raise ValueError('invalid source path expression')
        return '/'.join(values)
    raise ValueError('unsupported source-owned constant expression')
paths = literal(definitions['SOURCE_PATHS'])
if len(paths) != len(set(paths)) or not paths:
    raise ValueError('invalid source path set')
for path in paths:
    if not re.fullmatch(r'[A-Za-z0-9._/-]+', path) or any(p in ('','.','..') for p in path.split('/')):
        raise ValueError('invalid source path')
methods = literal(definitions['METHODS'])
unit_path = literal(definitions['PILOT_UNIT_SOURCE_PATH'])
declared = re.findall(r'^    func (test\w+)\(', blob(unit_path).decode('utf-8'), re.M)
if len(methods) != 5 or len(set(methods)) != 5 or sorted(declared) != sorted(methods):
    raise ValueError('native five methods differ from original source contract')
unit_class = literal(definitions['TEST_CLASS'])
result = {'source': {'head': head, 'gitTree': subprocess.check_output(
    ['git','-C',root,'rev-parse',head+'^{tree}'], text=True).strip(),
    'files': {path: hashlib.sha256(blob(path)).hexdigest().upper() for path in paths}},
    'unit_ids': [unit_class+'/'+method for method in methods]}
print(json.dumps(result, sort_keys=True, separators=(',',':')))
'@
    $value = $program | & $PythonCommand - $RepositoryRoot $Head
    if ($LASTEXITCODE -ne 0) { throw 'Cannot derive H413 immutable native source identity from E.' }
    return ([string]$value) | ConvertFrom-Json -Depth 100
}

function Assert-H413NativeSource {
    param($Source, [string]$Label)
    Assert-Equal (Get-H411CanonicalSHA256 $Source) (Get-H411CanonicalSHA256 $h413NativeIdentity.source) "$Label exact E source/tree/file identities"
}

function Assert-H413SelectedProducer {
    param($Shared, [string]$Label)
    Assert-Equal $Shared.producer_run_id $h413Policy.selected_producer_run_id "$Label H413 selected producer"
    Assert-Equal $Shared.shared_build_identity_sha256 $h413Policy.selected_shared_build_identity_sha256 "$Label H413 selected payload"
    Assert-Equal $Shared.producer_qualification_sha256 $h413Policy.selected_producer_qualification_sha256 "$Label H413 selected qualification"
}

function Assert-H413DeferredVisual {
    param($Cell)
    $label = [string]$Cell.cell_id
    Assert-Equal $Cell.acceptance_scope 'DEFERRED' "$label deferred scope"
    Assert-Equal $Cell.result 'DEFERRED' "$label deferred result"
    Assert-Equal $Cell.review_status 'NOT_REVIEWED' "$label deferred review"
    if ([string]::IsNullOrWhiteSpace([string]$Cell.deferral_reason)) { Add-ValidationError "$label missing deferral reason" }
    foreach ($field in @('source_product_head','source_test','run_id','job_id','artifact_id','artifact_name','artifact_digest',
        'attachment_name','attachment_locator','candidate_sha256','ax_evidence_id','ax_evidence_locator','ax_evidence_sha256',
        'contrast_evidence_id','contrast_evidence_locator','contrast_evidence_sha256','comparison_method','reviewer')) {
        Assert-Equal $Cell.$field '' "$label deferred no $field"
    }
    foreach ($field in @('source_segment_id','runner_provider')) {
        if ($null -ne (Get-H411Field $Cell $field)) { Add-ValidationError "$label deferred native $field forbidden" }
    }
    Assert-Equal $Cell.candidate_byte_length 0 "$label deferred no candidate bytes"
    Assert-Equal @($Cell.intended_change_ids).Count 0 "$label deferred no accepted changes"
    Assert-Equal @($Cell.evidence_ids).Count 0 "$label deferred no acceptance evidence"
}

function Assert-H413DeferredAccessibility {
    param($Row, [string]$Label)
    Assert-Equal $Row.acceptance_scope 'DEFERRED' "$Label deferred scope"
    Assert-Equal $Row.automated_status 'DEFERRED' "$Label deferred automated status"
    foreach ($field in @('source_product_head','run_id','job_id','artifact_id','artifact_digest','ax_evidence_id','ax_evidence_locator',
        'ax_evidence_sha256','focus_order_evidence_id','target_size_evidence_id','contrast_evidence_id','automated_reviewer',
        'exception_issue_id','exception_owner','exception_expires_at','exception_rationale')) {
        Assert-Equal $Row.$field '' "$Label deferred no $field"
    }
    Assert-Equal @($Row.automated_evidence_ids).Count 0 "$Label deferred no acceptance evidence"
    Assert-Equal $Row.manual_status 'NOT_RUN' "$Label deferred manual status"
    Assert-Equal @($Row.manual_evidence_ids).Count 0 "$Label deferred manual evidence"
    Assert-Equal $Row.manual_reviewer '' "$Label deferred manual reviewer"
    if ([string]::IsNullOrWhiteSpace([string]$Row.rationale)) { Add-ValidationError "$Label missing deferral rationale" }
}

function Invoke-H413RequiredRecordSchemas {
    param([string]$ValidatorText)
    # Strip only H413 metadata. All original native fields use E's unchanged schemas.
    $visualRecords = @($visual.candidate_cells | Where-Object { $_.acceptance_scope -ceq 'REQUIRED' } | ForEach-Object {
        $copy = [ordered]@{}
        foreach ($property in $_.PSObject.Properties) {
            if ($property.Name -cnotin @('acceptance_scope','deferral_reason')) { $copy[$property.Name] = $property.Value }
        }
        $copy
    })
    $accessRecords = @($accessibility.tasks | ForEach-Object { $_.feature_results } | Where-Object { $_.acceptance_scope -ceq 'REQUIRED' } | ForEach-Object {
        $copy = [ordered]@{}
        foreach ($property in $_.PSObject.Properties) {
            if ($property.Name -cne 'acceptance_scope') { $copy[$property.Name] = $property.Value }
        }
        $copy
    })
    $nativeVisualSchema = Get-GitJson $h413Policy.native_evidence_head 'docs/design/s10/authority/s10.4-automation-amendment-v1/s10-visual-regression.schema.json'
    $nativeAccessSchema = Get-GitJson $h413Policy.native_evidence_head 'docs/design/s10/authority/s10.4-automation-amendment-v1/s10-accessibility-common-tasks.schema.json'
    $temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ('s10-h413-record-schema-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $temporaryRoot | Out-Null
    try {
        foreach ($pair in @(
            @{ Name = 'visual'; Count = $h413Policy.required_visual_cell_count; Item = $nativeVisualSchema.properties.candidate_cells.items; Records = $visualRecords },
            @{ Name = 'accessibility'; Count = $h413Policy.required_accessibility_row_count; Item = $nativeAccessSchema.properties.tasks.items.properties.feature_results.items; Records = $accessRecords }
        )) {
            $schema = [ordered]@{ type = 'array'; minItems = $pair.Count; maxItems = $pair.Count; items = $pair.Item }
            $schemaFile = Join-Path $temporaryRoot ($pair.Name + '-schema.json')
            $instanceFile = Join-Path $temporaryRoot ($pair.Name + '-records.json')
            [IO.File]::WriteAllText($schemaFile, (ConvertTo-Json -InputObject $schema -Depth 100), [Text.UTF8Encoding]::new($false))
            [IO.File]::WriteAllText($instanceFile, (ConvertTo-Json -InputObject @($pair.Records) -Depth 100), [Text.UTF8Encoding]::new($false))
            Invoke-SchemaValidation $ValidatorText $schemaFile $instanceFile
        }
    }
    finally {
        # This path is created above from a fixed temp root and a generated UUID.
        $resolvedRoot = [IO.Path]::GetFullPath($temporaryRoot)
        $expectedParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar)
        if ([IO.Path]::GetDirectoryName($resolvedRoot) -ceq $expectedParent -and [IO.Path]::GetFileName($resolvedRoot) -cmatch '^s10-h413-record-schema-[0-9a-f]{32}$') {
            Remove-Item -LiteralPath $resolvedRoot -Recurse -Force
        }
    }
}


function Assert-H418MinimumCoreSmoke {
    param($Smoke, $Policy)
    $label = 'H418 minimum core smoke'
    if ($null -eq $Smoke) { Add-ValidationError "$label missing"; return }
    $proof = $Smoke.smoke_proof
    Assert-Equal $Smoke.source_product_head $ProductHead "$label E"
    Assert-Equal $proof.source.head $ProductHead "$label proof E"
    Assert-H413NativeSource $proof.source "$label proof source"
    Assert-Equal $Smoke.producer_run_id $Policy.selected_producer_run_id "$label selected producer"
    Assert-Equal $proof.sharedBuildIdentitySHA256 $Policy.selected_shared_build_identity_sha256 "$label selected payload"
    Assert-Equal $proof.producerQualificationSHA256 $Policy.selected_producer_qualification_sha256 "$label selected qualification"
    Assert-Equal $Smoke.shared_execution.producer_run_id $Smoke.producer_run_id "$label shared producer"
    Assert-Equal $Smoke.shared_execution.shared_build_identity_sha256 $proof.sharedBuildIdentitySHA256 "$label shared payload"
    Assert-Equal $Smoke.shared_execution.producer_qualification_sha256 $proof.producerQualificationSHA256 "$label shared qualification"

    $consumer = $proof.consumer
    foreach ($pair in @(
        @('nativeMode','s10.4.minimum-core-smoke.v1'), @('runnerProvider','github'),
        @('shardID','s10.4.minimum.minimum-os'), @('segmentID','none'), @('purpose','acceptance'),
        @('simulatorName','iPhone SE (3rd generation)'), @('simulatorRuntime','iOS 18.0'),
        @('simulatorRuntimeBuild','22A3351'), @('runAttempt',1)
    )) { Assert-Equal (Get-H411Field $consumer $pair[0]) $pair[1] "$label consumer $($pair[0])" }
    Assert-Equal $Smoke.original_run_id $consumer.runID "$label original consumer run"
    $expectedToolchain = [ordered]@{ xcodeVersion='Xcode 26.6'; xcodeBuild='17F113'; sdkName='iphonesimulator26.5'; sdkBuild='23F81a'; architecture='arm64'; project='FieldEvidenceApp.xcodeproj'; scheme='FieldEvidenceApp'; configuration='Debug' }
    Assert-Equal (Get-H411CanonicalSHA256 $consumer.toolchain) (Get-H411CanonicalSHA256 $expectedToolchain) "$label exact toolchain"
    $environmentReceipt = [pscustomobject]@{ source_product_head=$proof.source.head; github_environment=$proof.github_environment }
    Assert-GitHubReceiptEnvironment $environmentReceipt "$label original environment"

    $expectedCheckpoints = @('launch','sign-saved','capture-review','report-saved','report-reopened','settings')
    $expectedNames = @($expectedCheckpoints | ForEach-Object { 'S10.4 minimum core smoke ' + $_ }) + 'S10.4 minimum core smoke terminal'
    Assert-H411Ordered @($proof.checkpointIDs) $expectedCheckpoints "$label ordered checkpoints"
    Assert-H411Ordered @($proof.attachments.attachmentName) $expectedNames "$label ordered attachments"
    Assert-ExactSet @($proof.attachments.attachmentName) $expectedNames "$label unique attachment names"
    Assert-ExactSet @($proof.attachments.exportedFileName) @($proof.attachments.exportedFileName) "$label unique exported files"
    Assert-ExactSet @($proof.attachments.nativeUUID) @($proof.attachments.nativeUUID) "$label unique native UUIDs"
    Assert-ExactSet @($proof.attachments.nativePayloadReference) @($proof.attachments.nativePayloadReference) "$label unique native payload references"
    foreach ($attachment in $proof.attachments) {
        Assert-Equal $attachment.exportedFileName ($attachment.nativeUUID + '.png') "$label native/export UUID"
    }

    $original = $Smoke.original_evidence
    Assert-ExactSet @($original.PSObject.Properties.Name) @('intent','resolution','audit','run_api','jobs_api','artifacts_api','artifact_root') "$label original reference fields"
    $intent = Read-H411Evidence $original.intent "$label intent"
    $resolution = Read-H411Evidence $original.resolution "$label resolution"
    $audit = Read-H411Evidence $original.audit "$label complete original audit"
    $run = Read-H411Evidence $original.run_api "$label original run API"
    $jobs = Read-H411Evidence $original.jobs_api "$label original jobs API"
    $artifacts = Read-H411Evidence $original.artifacts_api "$label original artifacts API"
    $intentPath = [string]$original.intent.path
    if ($intentPath -cnotmatch '/intent\.json$') { Add-ValidationError "$label intent path is not canonical"; return }
    $requestRoot = $intentPath.Substring(0, $intentPath.Length - '/intent.json'.Length)
    Assert-Equal $requestRoot ("Temp/S10_4_CI/registry/requests/" + [string]$Smoke.original_request_id) "$label canonical request root"
    Assert-Equal $original.resolution.path ($requestRoot + '/resolution.json') "$label resolution path"
    Assert-Equal $original.run_api.path ($requestRoot + '/originals/run.json') "$label run API path"
    Assert-Equal $original.jobs_api.path ($requestRoot + '/originals/jobs.json') "$label jobs API path"
    Assert-Equal $original.artifacts_api.path ($requestRoot + '/originals/artifacts.json') "$label artifacts API path"
    if ([string]$original.audit.path -cnotmatch ('^' + [regex]::Escape($requestRoot) + '/audits/[0-9]{8}T[0-9]{6}-[0-9a-f]{32}\.json$')) { Add-ValidationError "$label audit path outside canonical request" }
    if ([string]$original.artifact_root.path -cnotmatch ('^' + [regex]::Escape($requestRoot) + '/originals/([1-9][0-9]*)/artifact$')) { Add-ValidationError "$label artifact root outside canonical request"; return }
    $consumerArtifactID = [long]$Matches[1]
    $artifactRoot = $RepositoryRoot
    foreach ($part in ([string]$original.artifact_root.path).Split('/')) {
        $artifactRoot = Join-Path $artifactRoot $part
        if (-not (Test-Path -LiteralPath $artifactRoot) -or ((Get-Item -LiteralPath $artifactRoot -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            Add-ValidationError "$label artifact root missing or linked"; return
        }
    }
    if (-not (Test-Path -LiteralPath $artifactRoot -PathType Container)) { Add-ValidationError "$label artifact root is not a directory"; return }

    Assert-Equal $intent.requestID $Smoke.original_request_id "$label request ID"
    Assert-Equal $intent.head $ProductHead "$label intent E"
    Assert-Equal $intent.kind 'consumer' "$label intent kind"
    Assert-Equal $intent.shardID 's10.4.minimum.minimum-os' "$label intent shard"
    Assert-Equal $intent.segmentID 'none' "$label intent segment"
    Assert-Equal $intent.inputs.s10_4_minimum_core_smoke_id 's10.4.minimum-core-smoke.v1' "$label intent smoke opt-in"
    Assert-Equal $intent.inputs.s10_4_shared_payload_run_id $Policy.selected_producer_run_id "$label intent selected producer"
    Assert-Equal $resolution.intentSHA256 $original.intent.sha256 "$label immutable intent"
    Assert-Equal $resolution.runID $Smoke.original_run_id "$label resolved run"

    $consumerArtifactName = "ios-ci-shared-$($Smoke.original_run_id)-1-s10.4.minimum.minimum-os-none"
    $artifactRows = @($artifacts.artifacts | Where-Object { $_.id -eq $consumerArtifactID -and $_.name -ceq $consumerArtifactName })
    Assert-Equal $artifactRows.Count 1 "$label exact consumer artifact"
    $jobRows = @($jobs.jobs | Where-Object { $_.id -eq $consumer.jobID })
    Assert-Equal $jobRows.Count 1 "$label exact consumer job"
    if ($jobRows.Count -eq 1) {
        Assert-Equal $jobRows[0].conclusion 'success' "$label consumer job success"
        Assert-Equal $jobRows[0].runner_name $consumer.runnerName "$label consumer runner"
    }
    if ($artifactRows.Count -eq 1) {
        $identity = [pscustomobject]@{ run_id=$consumer.runID; run_attempt=$consumer.runAttempt; artifact_id=$artifactRows[0].id; artifact_name=$artifactRows[0].name; artifact_digest=$artifactRows[0].digest }
        Assert-H411API $run $artifactRows[0] $identity "$label consumer API"
    }

    foreach ($pair in @(
        @('head',$ProductHead), @('runID',$Smoke.original_run_id), @('conclusion','success'),
        @('allAvailableOriginalsVerified',$true), @('completeOriginalAudit',$true),
        @('smokeComplete',$true), @('nativeUIExecuted',$true), @('formalAcceptance',$false),
        @('humanReviewGranted',$false)
    )) { Assert-Equal (Get-H411Field $audit $pair[0]) $pair[1] "$label audit $($pair[0])" }
    Assert-Equal @($audit.gaps).Count 0 "$label audit gaps"
    Assert-Equal $Smoke.original_audit_sha256 $original.audit.sha256 "$label audit bytes"
    Assert-Equal $Smoke.original_files_sha256 $audit.originalFilesSHA256 "$label original closure digest"
    Assert-Equal $Smoke.original_file_count $audit.originalFileCount "$label original closure count"
    Assert-Equal (Get-H411CanonicalSHA256 $audit.smokeProof) (Get-H411CanonicalSHA256 $proof) "$label audited proof"
    Assert-Equal (Get-H411CanonicalSHA256 $audit.consumer) (Get-H411CanonicalSHA256 $consumer) "$label audited consumer"
    Assert-Equal $audit.producerProof.runID $Policy.selected_producer_run_id "$label audited producer"
    Assert-Equal $audit.producerProof.producerUnitCount 5 "$label audited five units"
    Assert-Equal $audit.producerProof.sharedBuildIdentitySHA256 $Policy.selected_shared_build_identity_sha256 "$label audited payload"
    Assert-Equal $audit.producerProof.producerQualificationSHA256 $Policy.selected_producer_qualification_sha256 "$label audited qualification"
    Assert-Equal @($audit.nativeTests).Count 1 "$label one native test"
    if (@($audit.nativeTests).Count -eq 1) {
        Assert-Equal ([string]$audit.nativeTests[0].nodeIdentifier).Replace('()','') 'S10_4AutomatedBrandLabUITests/testAutomatedBrandLabShard' "$label native test identity"
        Assert-Equal $audit.nativeTests[0].result 'Passed' "$label native test pass"
    }
    Assert-Equal @($audit.nativeFailures).Count 0 "$label native failures"

    $originalsRoot = Join-Path $RepositoryRoot ($requestRoot + '/originals')
    $closureProgram = 'import hashlib,json,pathlib,sys; r=pathlib.Path(sys.argv[1]); f={p.relative_to(r).as_posix():hashlib.sha256(p.read_bytes()).hexdigest().upper() for p in r.rglob("*") if p.is_file() and not p.relative_to(r).parts[0].startswith("AUDIT") and p.name!="integrity.json"}; b=json.dumps(f,sort_keys=True,separators=(",",":"),ensure_ascii=True).encode(); print(str(len(f))+"|"+hashlib.sha256(b).hexdigest().upper())'
    $closure = @(& $PythonCommand -c $closureProgram $originalsRoot 2>$null)
    if ($LASTEXITCODE -ne 0 -or $closure.Count -ne 1) { throw "$label original closure recomputation failed" }
    Assert-Equal $closure[0] ("$($Smoke.original_file_count)|$($Smoke.original_files_sha256)") "$label recomputed original closure"

    $proofPath = Join-Path $artifactRoot 's10-4-minimum-core-smoke-proof.json'
    $referencePath = Join-Path $artifactRoot 'shared-consumer/consumer-build-reference.json'
    $commandPath = Join-Path $artifactRoot 's10-4-shared-ui-command.json'
    $databasePath = Join-Path $artifactRoot 'UISmoke.xcresult/database.sqlite3'
    foreach ($path in @($proofPath,$referencePath,$commandPath,$databasePath,(Join-Path $artifactRoot 's10-4-smoke-environment.json'),(Join-Path $artifactRoot 'ui-test-results.json'),(Join-Path $artifactRoot 'ui-executed-tests.json'))) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or ((Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { Add-ValidationError "$label missing/linked original $path"; return }
    }
    Assert-Equal (Get-Sha256 $proofPath) $Smoke.smoke_proof_sha256 "$label original proof bytes"
    Assert-Equal (Get-Sha256 $referencePath) $proof.consumerBuildReferenceSHA256 "$label original build-reference bytes"
    Assert-Equal (Get-Sha256 $databasePath) $proof.nativeDatabaseSHA256 "$label original database bytes"
    Assert-Equal (Get-Sha256 $commandPath) $Smoke.command_sha256 "$label original command bytes"
    $originalProof = Read-JsonFile $proofPath
    $reference = Read-JsonFile $referencePath
    $command = Read-JsonFile $commandPath
    Assert-Equal (Get-H411CanonicalSHA256 $originalProof) (Get-H411CanonicalSHA256 $proof) "$label original proof equality"
    Assert-Equal (Get-H411CanonicalSHA256 $audit.uiCommand) (Get-H411CanonicalSHA256 $command) "$label audited command"
    Assert-Equal (Get-H411CanonicalSHA256 $reference.uiCommand) (Get-H411CanonicalSHA256 $command) "$label reference command"
    Assert-Equal (Get-H411CanonicalSHA256 (Read-JsonFile (Join-Path $artifactRoot 's10-4-smoke-environment.json'))) (Get-H411CanonicalSHA256 $proof.github_environment) "$label original environment equality"

    $syntheticReceipt = [pscustomobject]@{ shard_id='s10.4.minimum.minimum-os'; runner_provider='github_actions'; execution_model='shared-native-v1'; shared_execution=$Smoke.shared_execution; consumer_build_reference=[pscustomobject]@{ path=([string]$original.artifact_root.path + '/shared-consumer/consumer-build-reference.json'); sha256=$proof.consumerBuildReferenceSHA256 }; run_id=[string]$consumer.runID; run_attempt=$consumer.runAttempt; job_id=[string]$consumer.jobID; simulator_udid=$consumer.simulatorUDID }
    $minimumShard = @($manifest.shards | Where-Object { $_.shard_id -ceq 's10.4.minimum.minimum-os' })[0]
    Assert-H411SharedReceipt $syntheticReceipt $minimumShard
    $producerArtifact = Read-H411Evidence $Smoke.shared_execution.producer_artifact_api "$label selected producer artifact"
    Assert-Equal $Smoke.payload_expiry_utc $producerArtifact.expires_at "$label payload expiry"
    if ((ConvertTo-H411DateTimeOffset $Smoke.payload_expiry_utc) -le [DateTimeOffset]::UtcNow) { Add-ValidationError "$label payload expired" }

    $proofProgram = 'import importlib.util,json,pathlib,sys; p=pathlib.Path(sys.argv[1])/"Scripts/s10-4-build-payload.py"; s=importlib.util.spec_from_file_location("h418_payload",p); m=importlib.util.module_from_spec(s); s.loader.exec_module(m); v=m.smoke_proof(pathlib.Path(sys.argv[1]),pathlib.Path(sys.argv[2]),json.load(open(sys.argv[3],encoding="utf-8"))); print(json.dumps(v,sort_keys=True,separators=(",",":"),ensure_ascii=True))'
    $recomputedText = @(& $PythonCommand -c $proofProgram $RepositoryRoot $artifactRoot $referencePath 2>$null)
    if ($LASTEXITCODE -ne 0 -or $recomputedText.Count -ne 1) { throw "$label source-defined proof recomputation failed" }
    $recomputed = $recomputedText[0] | ConvertFrom-Json -Depth 100
    Assert-Equal (Get-H411CanonicalSHA256 $recomputed) (Get-H411CanonicalSHA256 $proof) "$label source-defined proof equality"
}

# H420_MINIMUM_DEFERRAL_BEGIN
function Assert-H420DeferralShape {
    param($Contract, $Policy)
    $label = 'H420 minimum verification deferral'
    if ($null -eq $Contract) { Add-ValidationError "$label missing"; return }
    Assert-ExactSet @($Contract.PSObject.Properties.Name) @('contract_id','authority_id','binding_status','owner_instruction','native_evidence_head','source_identity_sha256','main_sha','producer','boundary_request_id','boundary_run_id','attempt_request_ids','original_history','quarantine_ledger','ios_deployment_target','follow_up','functional_pass_claimed','catalog_visual_cell_credit','catalog_accessibility_row_credit') "$label fields"
    Assert-Equal $Contract.contract_id 's10.4.minimum-verification-deferred.v1' "$label contract"
    Assert-Equal $Contract.authority_id 'H420' "$label authority"
    Assert-Equal $Contract.native_evidence_head $Policy.native_evidence_head "$label unchanged E"
    Assert-Equal $Contract.source_identity_sha256 'FA2E57BD20754B0E9844D8939B7BB4887448DC02D026F5EB635189B80C8E5F7A' "$label unchanged source"
    Assert-Equal $Contract.main_sha '01233f789b1cef5a6f56c7ff4caa9271409cd3bc' "$label main/P"
    Assert-ExactSet @($Contract.producer.PSObject.Properties.Name) @('runID','sharedBuildIdentitySHA256','producerQualificationSHA256') "$label producer fields"
    Assert-Equal $Contract.producer.runID $Policy.selected_producer_run_id "$label producer"
    Assert-Equal $Contract.producer.sharedBuildIdentitySHA256 $Policy.selected_shared_build_identity_sha256 "$label payload"
    Assert-Equal $Contract.producer.producerQualificationSHA256 $Policy.selected_producer_qualification_sha256 "$label qualification"
    Assert-Equal $Contract.boundary_request_id '36b252570bb743b09f53b1d4ce282976' "$label pre-instruction boundary request"
    Assert-Equal $Contract.boundary_run_id 34502909462 "$label pre-instruction boundary run"
    Assert-Equal $Contract.ios_deployment_target '18.0' "$label unchanged product target"
    Assert-Equal $Contract.follow_up 'PENDING_HANDOFF_ONLY' "$label pending follow-up only"
    Assert-Equal $Contract.functional_pass_claimed $false "$label no functional PASS"
    if ($Contract.functional_pass_claimed -isnot [bool]) { Add-ValidationError "$label functional PASS flag must be boolean" }
    Assert-Equal $Contract.catalog_visual_cell_credit 0 "$label no visual credit"
    Assert-Equal $Contract.catalog_accessibility_row_credit 0 "$label no accessibility credit"
    Assert-Equal $Contract.binding_status 'ACTIVE_OWNER_DIRECTED' "$label direct owner decision"
    $attempts = @($Contract.attempt_request_ids)
    Assert-Equal $attempts.Count 1 "$label actual completed additional attempt"
    Assert-Equal $attempts[0] '2c2d366f683f42a6b4df8ee6da2e5c1e' "$label exact completed additional request"
    Assert-ExactSet $attempts $attempts "$label unique attempts"
    foreach ($request in $attempts) { if ([string]$request -cnotmatch '^[0-9a-f]{32}$') { Add-ValidationError "$label malformed request" } }
    if ($null -eq $Contract.original_history -or @($Contract.original_history).Count -eq 0) { Add-ValidationError "$label original history pending" }
}

function Invoke-H420DeferralOriginalGuard {
    param($Contract, $Operational)
    # Reuse the unchanged reviewed controller's read-only original primitives.
    # No dispatch, provider call, collection, audit creation, or evidence minting.
    $program = @'
import importlib.util,json,pathlib,sys
sys.dont_write_bytecode=True
root=pathlib.Path(sys.argv[1]);d=json.loads(sys.argv[2]);c=json.loads(sys.argv[3])
__H419_APPROVED_ORIGINAL_LOADER__
matrix=m.Matrix(root/c['matrix']['path'],root/c['operational_review']['path'],c['operational_review']['sha256']);review=matrix.review()
rows=m.records(matrix,True);by_request={r['intent']['requestID']:r for r in rows}

def smoke_history(rows,head):
 return [r for r in rows if r['intent']['head']==head and r['intent'].get('inputs',{}).get('s10_4_minimum_core_smoke_id')=='s10.4.minimum-core-smoke.v1']

def require_smoke_history(items,smokes):
 m.require(type(items) is list and len({x['request_id'] for x in items})==len(items) and {x['request_id'] for x in items}=={r['intent']['requestID'] for r in smokes},'complete smoke history omitted/foreign/duplicate')

def require_nonpassing_original(run,a,audits):
 m.require(run['status']=='completed' and a['conclusion']==run['conclusion'] and a.get('smokeComplete') is not True,'complete or unfinished smoke cannot activate deferral')
 m.require(not any(v.get('smokeComplete') is True for p,v in audits),'known complete smoke PASS cannot be deferred')

def assert_activation(d,smokes,facts):
 requests=d['attempt_request_ids'];boundaries=[r for r in smokes if r['intent']['requestID']==d['boundary_request_id']]
 m.require(len(boundaries)==1,'deferral boundary absent or duplicate');boundary=boundaries[0]
 m.require(boundary['resolution']['runID']==d['boundary_run_id'],'deferral boundary run differs')
 later=sorted([r for r in smokes if m.utc(r['intent']['recordedAt'])>m.utc(boundary['intent']['recordedAt'])],key=lambda r:m.utc(r['intent']['recordedAt']))
 m.require([r['intent']['requestID'] for r in later]==requests,'new attempt history omitted/foreign/out of order')
 m.require(len(requests)==len(set(requests)) and requests==['2c2d366f683f42a6b4df8ee6da2e5c1e'],'owner-directed completed attempt differs')
 predecessor=boundary
 for row in later:
  retry=row['intent'].get('retry');prior=facts[predecessor['intent']['requestID']]
  m.require(type(retry) is dict and retry['runID']==predecessor['resolution']['runID'] and retry['auditSHA256'] in prior['completeAuditHashes'] and type(retry['reason']) is str and len(retry['reason'].strip())>=20,'new attempt has no exact complete predecessor/reason')
  m.require(not prior['knownDeterministicFailure'],'new unchanged attempt followed a known deterministic failure')
  m.require(prior['completedAt']<=m.utc(row['intent']['recordedAt']),'new attempts were not sequential')
  predecessor=row
 m.require(d['binding_status']=='ACTIVE_OWNER_DIRECTED','direct owner deferral activation differs')
 return requests

smokes=smoke_history(rows,d['native_evidence_head']);items=d['original_history']
require_smoke_history(items,smokes)
facts={};result=[];selected_audits={}
for item in items:
 m.require(set(item)=={'request_id','audit','original_cache'},'deferral original record fields differ')
 row=by_request[item['request_id']];i=row['intent'];m.require(row['resolution'] is not None,'unresolved smoke request cannot defer as a completed attempt');rid=row['resolution']['runID'];originals=m.original_root(row)
 m.require(i['kind']=='consumer' and i['provider']=='github' and i['shardID']=='s10.4.minimum.minimum-os' and i['segmentID']=='none' and i['inputs']['execution_lane']==m.CONSUMER and i['sourceIdentitySHA256']==d['source_identity_sha256'] and i['mainSHA']==d['main_sha'],'smoke exact route/source/main differs')
 expected=dict(d['producer'],sourceIdentitySHA256=d['source_identity_sha256'],producerUnitCount=5,productsPOSIXModesVerifiedFromOriginalTAR=True)
 m.require(i['producerProof']==expected,'smoke producer/five-unit/source/POSIX proof differs')
 ap=m.sealed_binding({'path':str(root/item['audit']['path']),'sha256':item['audit']['sha256']},parent=row['path']/'audits');a=m.load(ap)
 cp=m.sealed_binding({'path':str(root/item['original_cache']['path']),'sha256':item['original_cache']['sha256']},parent=matrix.registry/'verified-originals'/str(rid));cache=m.load(cp)
 m.require(cp.stem.split('-')[-1]==m.sha(cp),'original cache seal differs')
 collector=c['final_pair']['controller']['sha256'] if a.get('unacquiredHostedWorkers') else c['baseline_files']['Scripts/s10-4-ci.py']
 m.require(a['collectorSHA256']==cache['toolSHA256']==collector,'smoke original collector differs')
 m.require(a['head']==d['native_evidence_head'] and a['runID']==rid and a['completeOriginalAudit'] is True and a['allAvailableOriginalsVerified'] is True and a['formalAcceptance'] is False and a['humanReviewGranted'] is False,'incomplete/foreign/accepting smoke audit')
 m.require(cache['binding']=={'runID':rid,'head':d['native_evidence_head'],'sourceIdentitySHA256':i['sourceIdentitySHA256']} and cache['root']==str(m.wide(originals)) and cache['excludeAudits'] is True,'smoke cache source differs')
 m.require(m.cache_inventory(originals,True)=={n:{k:v for k,v in e.items() if k!='sha256'} for n,e in cache['files'].items()},'original metadata changed; original owner must reverify')
 m.require(cache['facts']['originalFilesSHA256']==a['originalFilesSHA256'],'original closure differs')
 run=m.run_identity(m.load(originals/'run.json'),i,rid);jobs=m.load(originals/'jobs.json')['jobs'];arts=m.load(originals/'artifacts.json')['artifacts']
 for witness in a.get('unacquiredHostedWorkers',[]):
  actual=m.retained_unacquired(originals,run,next(j for j in jobs if j['id']==witness['jobID']),i,arts,jobs);m.require(actual==witness,'unacquired original witness differs')
  m.require(all(a.get(k) is False for k in ('nativeUIExecuted','fullSegmentComplete','fullShardComplete','formalAcceptance','humanReviewGranted')) and all(a.get(k,0)==0 for k in ('strictOwnedCount','checkpointCount','candidatePNGCount','ownedJourneyCount')),'unacquired evidence claimed native credit')
 audits=[(p,m.load(p)) for p in sorted((row['path']/'audits').glob('*.json'))]
 m.require(all(v['runID']==rid and v['head']==d['native_evidence_head'] and v['originalFilesSHA256']==a['originalFilesSHA256'] for p,v in audits),'append-only audit history binding differs')
 require_nonpassing_original(run,a,audits)
 completed=[m.utc(j['completed_at']) for j in jobs if j.get('completed_at')]
 m.require(completed,'terminal original job times missing')
 facts[item['request_id']]={'completeAuditHashes':{m.sha(p) for p,v in audits if v.get('completeOriginalAudit') is True},'knownDeterministicFailure':any(v.get('knownDeterministicFailure') is True for p,v in audits),'completedAt':max(completed)}
 selected_audits[item['request_id']]=dict(a,selectedAuditSHA256=item['audit']['sha256'])
 result.append({'requestID':item['request_id'],'runID':rid,'conclusion':run['conclusion'],'auditSHA256':item['audit']['sha256']})
assert_activation(d,smokes,facts)
m.require(matrix.review()==review,'review changed')
print(json.dumps({'history':result,'attemptRequestIDs':d['attempt_request_ids'],'activationStatus':d['binding_status'],'functionalPassClaimed':False,'formalAcceptance':False},separators=(',',':')))
'@
    $program = $program.Replace('__H419_APPROVED_ORIGINAL_LOADER__', (Get-H419ApprovedOriginalLoader))
    $output = @(& $PythonCommand -c $program $RepositoryRoot (ConvertTo-Json $Contract -Depth 100 -Compress) (ConvertTo-Json $Operational -Depth 100 -Compress) 2>&1)
    if ($LASTEXITCODE -ne 0 -or $output.Count -ne 1) { Add-ValidationError ('H420 original deferral guard failed: ' + ($output -join ' ')); return }
    $value = $output[0] | ConvertFrom-Json -Depth 100
    Assert-Equal $value.activationStatus $Contract.binding_status 'H420 original activation status'
    Assert-Equal $value.functionalPassClaimed $false 'H420 no functional PASS from deferral'
    Assert-Equal $value.formalAcceptance $false 'H420 no acceptance from original guard'
}

function Assert-H420MinimumDeferral {
    param($Contract, $Policy, $Operational)
    Assert-H420DeferralShape $Contract $Policy
    if ($null -eq $Contract -or [string]$Contract.binding_status -cne 'ACTIVE_OWNER_DIRECTED') { return }
    Assert-Equal $Contract.owner_instruction.path 'Temp/S10_4_CI/minimum-core-smoke/owner-final-minimum-decision/OWNER_DIRECT_DEFERRAL_20260910.json' 'H420 instruction path'
    Assert-Equal $Contract.owner_instruction.sha256 '2ECB823298BEA8716A7A358F9C69D37FDA36BB824077D6DC8F688A06BB03FA43' 'H420 instruction seal'
    $owner = Read-H411Evidence $Contract.owner_instruction 'H420 actual owner instruction'
    Assert-Equal $owner.recordType 'S10_4_OWNER_DIRECT_MINIMUM_VERIFICATION_DEFERRAL' 'H420 direct owner instruction'
    Assert-Equal $owner.approved $true 'H420 approved owner decision'
    Assert-Equal $owner.decision 'DEFER_MINIMUM_VERIFICATION_NOW_AFTER_COMPLETED_FIRST_ADDITIONAL_ATTEMPT' 'H420 exact direct decision'
    Assert-Equal $owner.nativeEvidenceHead $Policy.native_evidence_head 'H420 instruction E'
    Assert-Equal $owner.mainP $Contract.main_sha 'H420 instruction main/P'
    Assert-Equal $owner.sourceIdentitySHA256 $Contract.source_identity_sha256 'H420 instruction source'
    Assert-Equal $owner.supersedesRootSelectedTwoAdditionalAttemptRequirement $true 'H420 earlier root interpretation superseded'
    Assert-Equal $owner.furtherMinimumRetriesAuthorized $false 'H420 no further minimum retry'
    Assert-Equal $owner.firstAdditionalAttempt.requestID $Contract.attempt_request_ids[0] 'H420 exact completed request'
    Assert-Equal $owner.firstAdditionalAttempt.runID 34511363515 'H420 exact completed run'
    Assert-Equal $owner.firstAdditionalAttempt.conclusion 'failure' 'H420 actual failed outcome'
    Assert-Equal $owner.firstAdditionalAttempt.completeOriginalAudit $true 'H420 complete first original audit'
    Assert-Equal $owner.firstAdditionalAttempt.selectedTestBodyStarted $false 'H420 selected body not reached'
    Assert-Equal $owner.firstAdditionalAttempt.smokePass $false 'H420 no smoke pass'
    Assert-Equal $owner.firstAdditionalAttempt.deterministicRepositoryCauseProved $false 'H420 no invented repository diagnosis'
    $first = @($Contract.original_history | Where-Object { $_.request_id -ceq $owner.firstAdditionalAttempt.requestID })
    Assert-Equal $first.Count 1 'H420 owner attempt original present once'
    Assert-Equal (Get-H411CanonicalSHA256 $first[0].audit) (Get-H411CanonicalSHA256 $owner.firstAdditionalAttempt.audit) 'H420 owner original audit binding'
    Assert-Equal $owner.secondAdditionalAttempt.dispatched $false 'H420 second attempt not dispatched'
    Assert-Equal $owner.secondAdditionalAttempt.requestID $null 'H420 no second request'
    Assert-Equal $owner.secondAdditionalAttempt.runID $null 'H420 no second run'
    Assert-Equal $owner.secondAdditionalAttempt.providerPOSTCount 0 'H420 no second provider POST'
    $prior = Read-H411Evidence $owner.originalConditionalInstruction 'H420 preserved prior instruction'
    Assert-Equal $prior.lastPreSteeringSmokeRequestID $Contract.boundary_request_id 'H420 preserved boundary'
    Assert-Equal $Contract.quarantine_ledger.path 'Temp/S10_4_CI/registry/quarantine-ledger.json' 'H420 unchanged quarantine path'
    Assert-Equal $Contract.quarantine_ledger.sha256 '2E78CC48AFD74E883F0808FF04E1624BCD87DCFA7615AAA63EB67F8AC6D09246' 'H420 unchanged quarantine seal'
    $ledger = Read-H411Evidence $Contract.quarantine_ledger 'H420 original quarantine'
    Assert-Equal $ledger.dispatchDeliveryHistoryComplete $false 'H420 unknown delivery retained'
    Assert-Equal @($ledger.quarantinedDispatches).Count 1 'H420 original quarantine reservation'
    $unknown = @($ledger.quarantinedDispatches)[0]
    Assert-Equal $unknown.requestID '3df9f1f463b549499a2a503886fa9517' 'H420 exact unknown request'
    Assert-Equal $unknown.runID $null 'H420 null unknown run'
    Assert-Equal $unknown.providerNonCreationProved $false 'H420 no noncreation inference'
    Assert-Equal $unknown.runnerReservation.githubUnknown 1 'H420 reserved slot'
    Assert-Equal $unknown.runnerReservation.maximumKnownPlusProposedGitHub 4 'H420 known capacity'
    Assert-Equal $unknown.runnerReservation.maximumTotalGitHub 5 'H420 total capacity'
    Invoke-H420DeferralOriginalGuard $Contract $Operational
}

function Assert-H420DeferredSmokeRecord {
    param($Smoke, $Policy, $Contract)
    $label = 'H420 deferred minimum smoke record'
    if ($null -eq $Smoke) { Add-ValidationError "$label missing"; return }
    $fields = @('contract_id','acceptance_scope','source_product_head','verification_status','native_passed','catalog_visual_cell_credit','catalog_accessibility_row_credit','full_matrix_eligible','full_shard_complete','full_segment_complete','human_review_required','deferral_contract_id','deferral_contract_sha256')
    if (@($Smoke.PSObject.Properties.Name) -ccontains 'provided_receipt') { $fields += 'provided_receipt' }
    Assert-ExactSet @($Smoke.PSObject.Properties.Name) $fields "$label fields"
    Assert-Equal $Smoke.contract_id 's10.4.minimum-core-smoke.v1' "$label contract"
    Assert-Equal $Smoke.acceptance_scope 'DEFERRED' "$label deferred scope"
    Assert-Equal $Smoke.verification_status 'DEFERRED' "$label deferred status"
    Assert-Equal $Smoke.source_product_head $Policy.native_evidence_head "$label unchanged E"
    foreach ($field in @('native_passed','full_matrix_eligible','full_shard_complete','full_segment_complete','human_review_required')) { Assert-Equal $Smoke.$field $false "$label $field" }
    foreach ($field in @('catalog_visual_cell_credit','catalog_accessibility_row_credit')) { Assert-Equal $Smoke.$field 0 "$label $field" }
    Assert-Equal $Smoke.deferral_contract_id $Contract.contract_id "$label deferral contract"
    Assert-Equal $Smoke.deferral_contract_sha256 (Get-H411CanonicalSHA256 $Contract) "$label exact deferral binding"
    if (@($Smoke.PSObject.Properties.Name) -ccontains 'provided_receipt') {
        Assert-H418MinimumCoreSmoke $Smoke.provided_receipt $Policy
    }
}
# H420_MINIMUM_DEFERRAL_END

# H413_REQUIRED_PROFILE_FUNCTIONS_END

$manifest = Read-JsonFile $manifestPath
$visual = Read-JsonFile $visualPath
$accessibility = Read-JsonFile $accessibilityPath
$inventory = Read-JsonFile $inventoryPath
$token = Read-JsonFile $tokenPath
$stage = Read-JsonFile $stagePath
$activation = Read-JsonFile $activationPath
$shardContract = Read-JsonFile $shardContractPath

# H413_SOURCE_POLICY_BINDING_BEGIN
$h413Policy = Get-H411Field $manifest 'required_profile_acceptance_policy'
Assert-Equal $h413Policy.native_evidence_head '0adebd72ae0226a80e14eaf515ca133072fb1c76' 'H418 observed native E'
Assert-Equal $h413Policy.native_manifest_sha256 'F29BB5F29C0876BEAE1C32C7D6A418BC29AB43C8882CCDC0F622922FD042238C' 'H418 native manifest identity'
Assert-Equal $h413Policy.selected_producer_run_id 34477382489 'H418 selected producer run'
Assert-Equal $h413Policy.selected_shared_build_identity_sha256 '0BE9475570B1F0B9CC5C9520DA4F2D11308D034033ABD17C4F6E61F1901DADAE' 'H418 selected shared identity'
Assert-Equal $h413Policy.selected_producer_qualification_sha256 'A1A9BF1B92B4CABFD150702EF3F2E218590C290B52B685E598926CF5D158542B' 'H418 selected producer qualification'
$h418Parents = @(& git -C $RepositoryRoot rev-list --parents -n 1 '0adebd72ae0226a80e14eaf515ca133072fb1c76' 2>$null)
Assert-Equal ($h418Parents -join '') '0adebd72ae0226a80e14eaf515ca133072fb1c76 7d33a206bcf9ff4c5e767549f9db7632d15fbc4a' 'H418 E direct parent'
$h418Paths = @(& git -C $RepositoryRoot diff-tree --no-commit-id --name-only -r '0adebd72ae0226a80e14eaf515ca133072fb1c76' 2>$null)
Assert-ExactSet $h418Paths @('Scripts/s10-4-ci.py','Scripts/test-s10-4-ci.py','docs/execution/CURRENT_TASK.md') 'H418 exact K506 correction paths'
Assert-Equal (Get-GitBlobSha256 '0adebd72ae0226a80e14eaf515ca133072fb1c76' '.github/workflows/ios-ci-worker.yml') 'DA888041E1743303935415DD6BEE50D185E892784FC9570C123B888290E4EE25' 'H418 E .github/workflows/ios-ci-worker.yml'
Assert-Equal (Get-GitBlobSha256 '0adebd72ae0226a80e14eaf515ca133072fb1c76' '.github/workflows/ios-ci.yml') '64BEB60B465EB71B708FB19FEC2061E6F05FFA74A3D93955A88BB3CADC9D3A85' 'H418 E .github/workflows/ios-ci.yml'
Assert-Equal (Get-GitBlobSha256 '0adebd72ae0226a80e14eaf515ca133072fb1c76' 'FieldEvidenceAppTests/S10_4AutomatedBrandLabTests.swift') 'BAEC9FFF843F9EA6D8B2E6AEF7B76B9A371376BAE8CC7A671A5F5AD27B03ED23' 'H418 E FieldEvidenceAppTests/S10_4AutomatedBrandLabTests.swift'
Assert-Equal (Get-GitBlobSha256 '0adebd72ae0226a80e14eaf515ca133072fb1c76' 'FieldEvidenceAppUITests/S10_3BrandMigrationUITests.swift') 'C19ED97AAB748D6CB6115A742BB555E4841B21B24E7CEE94C2341C2827308D46' 'H418 E FieldEvidenceAppUITests/S10_3BrandMigrationUITests.swift'
Assert-Equal (Get-GitBlobSha256 '0adebd72ae0226a80e14eaf515ca133072fb1c76' 'Scripts/s10-4-build-payload.py') 'EA731FD64278D3AB242956BF2F36D486254903A10F5F8BC17C65DE3D10397521' 'H418 E Scripts/s10-4-build-payload.py'
Assert-Equal (Get-GitBlobSha256 '0adebd72ae0226a80e14eaf515ca133072fb1c76' 'Scripts/s10-4-ci.py') '58BFD7988C9A4DDD847D96532BBE5A9BB617ADDC5C3B1521F9FEE06F28228354' 'H418 E Scripts/s10-4-ci.py'
Assert-Equal (Get-GitBlobSha256 '0adebd72ae0226a80e14eaf515ca133072fb1c76' 'Scripts/s10-4-segment-plan.json') 'AA85594BB6EB09DB9AE4A2D3C22C0B8D106F4A209A9A7ACF445BCC51C4D8B074' 'H418 E Scripts/s10-4-segment-plan.json'
Assert-Equal (Get-GitBlobSha256 '0adebd72ae0226a80e14eaf515ca133072fb1c76' 'Scripts/test-s10-4-ci.py') '857AA47537D225FE2DF7AFAAD0C0EF4DB60509CCCE910E334920927571FB74B0' 'H418 E Scripts/test-s10-4-ci.py'
Assert-Equal (Get-GitBlobSha256 '0adebd72ae0226a80e14eaf515ca133072fb1c76' 'Scripts/ui-smoke.sh') 'A8DE01614F20B8C8187D62F4B0D4E489344F4E10EE65DE31C3A679E8196E1FF7' 'H418 E Scripts/ui-smoke.sh'
Assert-Equal (Get-GitBlobSha256 '0adebd72ae0226a80e14eaf515ca133072fb1c76' 'docs/design/s10/authority/s10.4-automation-amendment-v1/manifest.json') 'F29BB5F29C0876BEAE1C32C7D6A418BC29AB43C8882CCDC0F622922FD042238C' 'H418 E docs/design/s10/authority/s10.4-automation-amendment-v1/manifest.json'
Assert-Equal (Get-GitBlobSha256 '0adebd72ae0226a80e14eaf515ca133072fb1c76' 'docs/execution/CURRENT_TASK.md') 'BA94BF300DF4EF279CF5B7A12FF20C4FBDAC554FD267F121A86C55355545C56F' 'H418 E docs/execution/CURRENT_TASK.md'
Assert-Equal $manifest.github_environment_contract.worker_source_sha256 'DA888041E1743303935415DD6BEE50D185E892784FC9570C123B888290E4EE25' 'H418 E manifest worker'
if ((Get-H411Field $h413Policy 'composition_status') -ceq 'PENDING_NATIVE_E_AND_QUALIFIED_PRODUCER') {
    throw 'H418 preparation is intentionally nonaccepting until actual native E and root-selected producer are composed.'
}
if ($null -eq $h413Policy) { throw 'H413 required-profile acceptance policy is missing.' }
$nativeManifestRelativePath = 'docs/design/s10/authority/s10.4-automation-amendment-v1/manifest.json'
$h413NativeManifest = Get-GitJson $h413Policy.native_evidence_head $nativeManifestRelativePath
Assert-H413Policy $h413Policy $h413NativeManifest $ProductHead
Assert-Equal (Get-GitBlobSha256 $h413Policy.native_evidence_head $nativeManifestRelativePath) $h413Policy.native_manifest_sha256 'H413 original E manifest bytes'
foreach ($field in @('runtime_contract','github_environment_contract','hybrid_execution_contract','shared_execution_contract',
    'matrix_contract','shards','required_requirement_ids','required_task_ids','required_accessibility_features')) {
    Assert-Equal (Get-H411CanonicalSHA256 $manifest.$field) (Get-H411CanonicalSHA256 $h413NativeManifest.$field) "H413 unchanged native $field"
}
foreach ($name in @('s10-visual-regression.schema.json','s10-accessibility-common-tasks.schema.json','validate-s10-contracts.ps1')) {
    $entry = @($h413NativeManifest.overlay_files | Where-Object { $_.path -ceq $name })
    Assert-Equal $entry.Count 1 "H413 original overlay entry $name"
    if ($entry.Count -eq 1) {
        Assert-Equal (Get-GitBlobSha256 $h413Policy.native_evidence_head ('docs/design/s10/authority/s10.4-automation-amendment-v1/' + $name)) $entry[0].sha256 "H413 original E overlay bytes $name"
    }
}
$h413NativeIdentity = Get-H413NativeSourceIdentity $h413Policy.native_evidence_head
Assert-H419OperationalEvidence (Get-H411Field $manifest 'operational_evidence_contract')
Assert-H420MinimumDeferral (Get-H411Field $manifest 'minimum_verification_deferral_contract') $h413Policy (Get-H411Field $manifest 'operational_evidence_contract')
Assert-H413CollectorCorrection $manifest.collector_correction_contract
Assert-ExactSet @($h413NativeIdentity.unit_ids) @($h413NativeManifest.shared_execution_contract.producer_unit_test_selectors) 'H413 unchanged native five identities'
$h413RequiredShards = @($manifest.shards | Where-Object { $_.shard_id -cin @($h413Policy.required_shard_ids) })
$h413DeferredShards = @($manifest.shards | Where-Object { $_.shard_id -cin @($h413Policy.deferred_shard_ids) })
# H413_SOURCE_POLICY_BINDING_END

Assert-GitHubEnvironmentContract $manifest.github_environment_contract

$expectedFrozenSchemaDocuments = @(
    "s10-activation",
    "s10-stage-checkpoints",
    "s10-screen-state-inventory",
    "s10-token-coverage",
    "s10-experience-validation",
    "s10-store-readiness",
    "s10-evidence-lock.template"
)
$expectedOverlaySchemaDocuments = @(
    "s10-accessibility-common-tasks",
    "s10-visual-regression"
)
$expectedCompositeValidationRule = "The unchanged V4.1 schema subset validator validates every unaffected canonical contract plus the frozen evidence-lock template; the audited amendment schemas validate only the intentionally expanded accessibility and visual evidence documents."
$expectedProductDeltaAllowlist = @(
    ".github/workflows/ios-ci.yml",
    "FieldEvidenceApp/DesignSystem/DesignTokens.swift",
    "FieldEvidenceApp/DesignSystem/WorklightComponents.swift",
    "FieldEvidenceApp/Features/Backup/BackupRestoreProgressView.swift",
    "FieldEvidenceApp/Features/CheckRunner/CaptureStepView.swift",
    "FieldEvidenceApp/Features/CheckRunner/OutcomeReviewView.swift",
    "FieldEvidenceApp/Features/CheckRunner/PreflightView.swift",
    "FieldEvidenceApp/Features/CheckRunner/ValueReceiptView.swift",
    "FieldEvidenceApp/Features/Issues/IssueDetailView.swift",
    "FieldEvidenceApp/Features/Issues/RecordWorkView.swift",
    "FieldEvidenceApp/Features/Reports/ReportCorrectionView.swift",
    "FieldEvidenceApp/Features/Reports/ReportDetailView.swift",
    "FieldEvidenceApp/Features/Reports/ReportFailureView.swift",
    "FieldEvidenceApp/Features/Reports/ReportsRootView.swift",
    "FieldEvidenceApp/Features/Sample/PackSampleView.swift",
    "FieldEvidenceApp/Features/Settings/DiagnosticExportView.swift",
    "FieldEvidenceApp/Features/Settings/EraseAllView.swift",
    "FieldEvidenceApp/Features/Settings/FeedbackView.swift",
    "FieldEvidenceApp/Features/Shell/AppShellView.swift",
    "FieldEvidenceApp/Features/Signs/NewSignView.swift",
    "FieldEvidenceApp/Features/Signs/SignDetailView.swift",
    "FieldEvidenceApp/Features/Signs/SignsRootView.swift",
    "FieldEvidenceApp/Features/Subscription/PaywallView.swift",
    "FieldEvidenceApp/Features/Subscription/SubscriptionStatusView.swift",
    "FieldEvidenceAppTests/S10_3BrandMigrationTests.swift",
    "FieldEvidenceAppTests/S10_4AutomatedBrandLabTests.swift",
    "FieldEvidenceAppUITests/S10_3BrandMigrationUITests.swift",
    "Scripts/ci-selection.json",
    "Scripts/s10-4-shards.json",
    "Scripts/ui-smoke.sh",
    "docs/design/s10/authority/s10.4-automation-amendment-v1/manifest.json",
    "docs/design/s10/authority/s10.4-automation-amendment-v1/s10-accessibility-common-tasks.schema.json",
    "docs/design/s10/authority/s10.4-automation-amendment-v1/s10-visual-regression.schema.json",
    "docs/design/s10/authority/s10.4-automation-amendment-v1/validate-s10-contracts.ps1",
    "docs/design/s10/s10-experience-validation.json",
    "docs/design/s10/s10-screen-state-inventory.json",
    "docs/design/s10/s10-stage-checkpoints.json",
    "docs/design/s10/s10-token-coverage.json",
    "docs/execution/CURRENT_TASK.md",
    "docs/execution/HANDOFF.md"
)
Assert-ExactSet @($manifest.composite_validation_contract.frozen_schema_documents) $expectedFrozenSchemaDocuments "composite frozen-schema documents"
Assert-ExactSet @($manifest.composite_validation_contract.overlay_schema_documents) $expectedOverlaySchemaDocuments "composite overlay-schema documents"
Assert-Equal $manifest.composite_validation_contract.rule $expectedCompositeValidationRule "composite validation rule"
Assert-ExactSet @($h413NativeManifest.product_delta_allowlist) $expectedProductDeltaAllowlist "H413 unchanged original E historical path declaration"
Assert-H413HistoricalNativeRepair $manifest.historical_native_ancestry_authorization_repair $h413Policy
$expectedProductDeltaAllowlist = @($expectedProductDeltaAllowlist) + @(Get-H413HistoricalNativePaths)
Assert-ExactSet @($manifest.product_delta_allowlist) $expectedProductDeltaAllowlist "S10.4 exact reviewed historical product delta allowlist"
Assert-Equal $manifest.runtime_contract.shard_contract_path "Scripts/s10-4-shards.json" "runtime shard-contract path"
Assert-Equal $manifest.runtime_contract.shard_contract_sha256 (Get-Sha256 $shardContractPath) "runtime shard-contract hash"
Assert-Equal $manifest.runtime_contract.screen_state_inventory_path "docs/design/s10/s10-screen-state-inventory.json" "runtime inventory path"
Assert-Equal $manifest.runtime_contract.screen_state_inventory_sha256 (Get-Sha256 $inventoryPath) "runtime inventory hash"
Assert-Equal $manifest.runtime_contract.minimum_runtime "iOS 18.0" "minimum runtime"
Assert-Equal $manifest.runtime_contract.minimum_runtime_build "22A3351" "minimum runtime build"
Assert-Equal $manifest.runtime_contract.minimum_simulator_name "iPhone SE (3rd generation)" "minimum simulator"

$expectedHarnessCorrectionAllowlist = @(
    ".github/workflows/ios-ci.yml",
    ".github/workflows/ios-ci-worker.yml",
    "Scripts/build-smoke.sh",
    "Scripts/test-smoke.sh",
    "Scripts/ui-smoke.sh",
    "Scripts/run-with-timeout.sh",
    "FieldEvidenceAppTests/S10_4AutomatedBrandLabTests.swift",
    "docs/execution/CURRENT_TASK.md"
)
$expectedBitriseShards = @("s10.4.current.default-light", "s10.4.current.default-dark")
$expectedGitHubMinimumShards = @(
    "s10.4.minimum.minimum-os",
    "s10.4.minimum.double-length",
    "s10.4.minimum.rtl",
    "s10.4.minimum.rtl-string",
    "s10.4.minimum.tall",
    "s10.4.minimum.accented",
    "s10.4.minimum.bounded"
)
$expectedComparisonMethod = "Exact provider-local PNG-byte XCT attachment exported from UISmoke.xcresult and reconstructed byte-for-byte at evidence K; cross-provider equivalence is receipt-bound and does not require PNG byte equality"
# H411_SHARED_AUTHORITY_BEGIN
$sharedContract = $manifest.shared_execution_contract
Assert-Equal $sharedContract.contract_version "s10.4-shared-logical-shards-v1" "shared logical shard version"
Assert-ExactSet @($sharedContract.shard_ids) @($manifest.shards.shard_id) "shared fourteen shard identities"
foreach ($pair in @(@('logical_shard_count',14),@('states_per_logical_shard',67),@('visual_cell_count',938),@('accessibility_row_count',84),@('common_task_count',6),@('local_unit_test_count',0),@('producer_unit_test_count',5))) {
    Assert-Equal $sharedContract.($pair[0]) $pair[1] "shared $($pair[0])"
}
foreach ($field in @('one_exact_head_and_payload','human_visual_review_required','diagnostic_promotion_forbidden','legacy_hybrid_gate_unchanged')) { Assert-Equal $sharedContract.$field $true "shared $field" }
Assert-Equal $sharedContract.initial_consumer_provider 'github_actions' 'shared initial provider'
Assert-Equal $sharedContract.producer_provider 'bitrise_build_hub' 'shared producer provider'
Assert-Equal $sharedContract.consumer_execution_mode 'test-without-building' 'shared command mode'
Assert-Equal $sharedContract.unit_evidence_origin 'shared-producer' 'shared unit origin'
Assert-H411Ordered @($sharedContract.minimum_segment_ids) @('minimum-segment-1','minimum-segment-2','minimum-segment-3') 'minimum segment IDs'
Assert-H411Ordered @($sharedContract.current_ax_segment_ids) @('segment-1','segment-2','segment-3') 'current AX segment IDs'
# H411_SHARED_AUTHORITY_END

$hybrid = $manifest.hybrid_execution_contract
Assert-Equal $hybrid.profile_id "s10.4-hybrid-exact-head-xctestrun-v1" "hybrid profile ID"
Assert-Equal $hybrid.github_toolchain_baseline "docs/design/s10/s10-activation.json#toolchain" "hybrid GitHub baseline"
Assert-Equal $hybrid.github_runner_provider "github_actions" "hybrid GitHub provider"
Assert-ExactSet @($hybrid.github_required_minimum_shard_ids) $expectedGitHubMinimumShards "hybrid GitHub minimum shards"
Assert-Equal $hybrid.github_minimum_device_profile.device_profile_id "iphone-se-3-ios-18.0-minimum" "hybrid minimum profile"
Assert-Equal $hybrid.github_minimum_device_profile.simulator_runtime "iOS 18.0" "hybrid minimum runtime"
Assert-Equal $hybrid.github_minimum_device_profile.simulator_os_build "22A3351" "hybrid minimum OS build"
Assert-Equal $hybrid.github_minimum_device_profile.simulator_name "iPhone SE (3rd generation)" "hybrid minimum simulator"
Assert-Equal $hybrid.bitrise_provider "bitrise_build_hub" "hybrid Bitrise provider"
Assert-ExactSet @($hybrid.bitrise_eligible_current_shard_ids) $expectedBitriseShards "hybrid Bitrise shards"
Assert-Equal $hybrid.bitrise_current_device_profile.device_profile_id "iphone-17-ios-26.2-current" "hybrid Bitrise profile"
Assert-Equal $hybrid.bitrise_current_device_profile.simulator_runtime "iOS 26.2" "hybrid Bitrise runtime"
Assert-Equal $hybrid.bitrise_current_device_profile.simulator_os_build "23C54" "hybrid Bitrise OS build"
Assert-Equal $hybrid.bitrise_current_device_profile.simulator_name "iPhone 17" "hybrid Bitrise simulator"
Assert-Equal $hybrid.payload_profile.profile_id "s10.4-exact-head-xctestrun-build-products-v1" "payload profile ID"
Assert-ExactSet @($hybrid.payload_profile.required_members) @("relocatable .xctestrun", "complete Build/Products closure") "payload required members"
foreach ($field in @("one_exact_head_payload_required", "checksummed_immutable", "consumer_rebuild_forbidden", "consumer_fallback_forbidden", "mixed_head_forbidden")) {
    Assert-Equal $hybrid.payload_profile.$field $true "payload $field"
}
Assert-Equal $hybrid.payload_profile.producer_provider "bitrise_build_hub" "payload producer provider"
Assert-Equal $hybrid.payload_profile.artifact_transport_provider "github_actions" "payload artifact transport provider"
Assert-Equal $hybrid.payload_profile.consumer_execution_mode "test-without-building" "payload consumer execution"
Assert-Equal $hybrid.equivalence_gate.same_shard_github_to_bitrise_required_before_bitrise_receipt_counts $true "same-shard equivalence gate"
Assert-Equal $hybrid.equivalence_gate.exact_head_required $true "equivalence exact head"
Assert-Equal $hybrid.equivalence_gate.xcode_version "Xcode 26.6" "equivalence Xcode version"
Assert-Equal $hybrid.equivalence_gate.xcode_build "17F113" "equivalence Xcode build"
Assert-Equal $hybrid.equivalence_gate.selector "FieldEvidenceAppUITests/S10_4AutomatedBrandLabUITests" "equivalence selector"
Assert-Equal $hybrid.equivalence_gate.state_count 67 "equivalence state count"
Assert-Equal $hybrid.equivalence_gate.accessibility_task_count 6 "equivalence task count"
Assert-Equal $hybrid.equivalence_gate.provider_local_screenshot_bytes_must_be_checksummed $true "provider-local screenshots checksummed"
Assert-Equal $hybrid.equivalence_gate.cross_provider_screenshot_byte_equality_required $false "cross-provider screenshot byte equality"
foreach ($watchdog in @{
    requirement_count = 14; state_count = 67; candidate_cell_count = 938; accessibility_row_count = 84; task_count = 6;
    simulator_readiness_seconds = 900; setup_seconds = 420; build_seconds = 900; test_seconds = 1200; ui_seconds = 2520; total_seconds = 4500; job_watchdog_seconds = 5400
}.GetEnumerator()) {
    Assert-Equal $hybrid.unchanged_matrix_and_watchdogs.$($watchdog.Key) $watchdog.Value "hybrid invariant $($watchdog.Key)"
}
Assert-ExactSet @($manifest.harness_correction_allowlist) $expectedHarnessCorrectionAllowlist "harness correction allowlist"
Assert-Equal $manifest.harness_correction_scope "Only the listed S10.4 execution-harness paths may implement this profile; no product, project, test selector, fixture, asset, matrix, or watchdog expansion is authorized." "harness correction scope"
Assert-Contains @($activation.repository_authority.allowed_remote_operations) "dispatch_bitrise_s10_4_equivalence_workflow" "activation Bitrise equivalence dispatch"
Assert-Equal $activation.repository_authority.pinned_plan_sha256 (Get-Sha256 (Join-Path $RepositoryRoot $activation.repository_authority.pinned_plan_path)) "activation plan repin"
Assert-Equal $activation.repository_authority.pinned_runbook_sha256 (Get-Sha256 (Join-Path $RepositoryRoot $activation.repository_authority.pinned_runbook_path)) "activation runbook repin"
# The V4.1 ZIP, external package manifest, and base runbook remain immutable;
# activation is schema-frozen and may carry only the separately validated pin/dispatch amendment.
$baseFiles = @(
    @{ Path = $manifest.base_authority.activation_path; Sha = $manifest.base_authority.activation_sha256 },
    @{ Path = $manifest.base_authority.package_path; Sha = $manifest.base_authority.package_sha256 },
    @{ Path = $manifest.base_authority.asset_manifest_path; Sha = $manifest.base_authority.asset_manifest_sha256 },
    @{ Path = $manifest.base_authority.runbook_path; Sha = $manifest.base_authority.runbook_sha256 }
)
foreach ($baseFile in $baseFiles) {
    $fullPath = Join-Path $RepositoryRoot $baseFile.Path
    Assert-Equal (Get-Sha256 $fullPath) $baseFile.Sha "immutable base hash $($baseFile.Path)"
}

$expectedOverlayNames = @(
    "manifest.json",
    "s10-visual-regression.schema.json",
    "s10-accessibility-common-tasks.schema.json",
    "validate-s10-contracts.ps1"
)
Assert-ExactSet @(Get-ChildItem -LiteralPath $overlayRoot -File | ForEach-Object { $_.Name }) $expectedOverlayNames "overlay file names"
Assert-ExactSet @($manifest.overlay_files.path) @($expectedOverlayNames | Where-Object { $_ -cne "manifest.json" }) "manifest overlay_files"
foreach ($entry in $manifest.overlay_files) {
    $filePath = Join-Path $overlayRoot $entry.path
    Assert-Equal (Get-Sha256 $filePath) $entry.sha256 "overlay hash $($entry.path)"
    Assert-Equal (Get-Item -LiteralPath $filePath).Length $entry.byte_length "overlay byte length $($entry.path)"
}

# Use the unchanged V4.1 subset validator for the six unaffected canonical
# contracts and the frozen evidence-lock template. The two documents whose
# evidence cardinality is intentionally superseded by this amendment use only
# the audited overlay schemas. Post-E modes validate their populated instances.
$schemaValidator = Get-ZipEntryText $packagePath "/Tools/validate-json-schema-subset.py"
$frozenSchemaInstances = @(
    @{ Name = "s10-activation"; Instance = $activationPath },
    @{ Name = "s10-stage-checkpoints"; Instance = $stagePath },
    @{ Name = "s10-screen-state-inventory"; Instance = $inventoryPath },
    @{ Name = "s10-token-coverage"; Instance = $tokenPath },
    @{ Name = "s10-experience-validation"; Instance = (Join-Path $RepositoryRoot "docs/design/s10/s10-experience-validation.json") },
    @{ Name = "s10-store-readiness"; Instance = (Join-Path $RepositoryRoot "docs/design/s10/s10-store-readiness.json") }
)
foreach ($contract in $frozenSchemaInstances) {
    Invoke-FrozenSchemaValidation $schemaValidator "/Handoff/$($contract.Name).schema.json" $contract.Instance
}
Invoke-FrozenSchemaValidation $schemaValidator "/Handoff/s10-evidence-lock.schema.json" "" "/Handoff/s10-evidence-lock.template.json"
Invoke-SchemaAudit $schemaValidator $visualSchemaPath
Invoke-SchemaAudit $schemaValidator $accessibilitySchemaPath
if ($LifecycleMode -cne "AuthorityH") {
    Invoke-SchemaValidation $schemaValidator $visualSchemaPath $visualPath
    Invoke-SchemaValidation $schemaValidator $accessibilitySchemaPath $accessibilityPath
    Invoke-H413RequiredRecordSchemas $schemaValidator
}

# Preserve the unaffected V4.1 AutomatedLab semantics that are not expressible
# as schema alone. The first three accepted receipts are immutable history; only
# ReceiptC may append the fourth ordered AutomatedLab row.
$historicalStage = Get-GitJson $manifest.base_authority.accepted_migration_receipt_head "docs/design/s10/s10-stage-checkpoints.json"
$expectedStageCount = if ($LifecycleMode -ceq "ReceiptC") { 4 } else { 3 }
Assert-Equal $stage.receipt_model "E_product_K_evidence_C_receipt" "stage receipt model"
Assert-Equal $stage.document_status "tracking" "stage document status"
Assert-Equal @($stage.checkpoints).Count $expectedStageCount "$LifecycleMode stage count"
$expectedStageOrder = @("Inventory", "ComponentSystem", "Migration", "AutomatedLab")
for ($stageIndex = 0; $stageIndex -lt [Math]::Min(@($stage.checkpoints).Count, $expectedStageCount); $stageIndex++) {
    Assert-Equal $stage.checkpoints[$stageIndex].stage $expectedStageOrder[$stageIndex] "stage order $stageIndex"
}
for ($stageIndex = 0; $stageIndex -lt [Math]::Min(@($historicalStage.checkpoints).Count, @($stage.checkpoints).Count); $stageIndex++) {
    Assert-Equal ($stage.checkpoints[$stageIndex] | ConvertTo-Json -Depth 100 -Compress) ($historicalStage.checkpoints[$stageIndex] | ConvertTo-Json -Depth 100 -Compress) "immutable historical checkpoint $stageIndex"
}
foreach ($checkpoint in @($stage.checkpoints)) {
    Assert-Equal $checkpoint.evidence_head_role "K" "$($checkpoint.stage) evidence-head role"
    if (@($checkpoint.documents).Count -eq 0 -or @($checkpoint.evidence_ids).Count -eq 0) {
        Add-ValidationError "$($checkpoint.stage) checkpoint lacks documents or evidence IDs."
    }
    Assert-Commit $checkpoint.product_head "$($checkpoint.stage) product head"
    Assert-Commit $checkpoint.evidence_head "$($checkpoint.stage) evidence head"
    Assert-Ancestor $checkpoint.product_head $checkpoint.evidence_head "$($checkpoint.stage) E to K lineage"
    foreach ($document in @($checkpoint.documents)) {
        Assert-Equal $document.sha256 (Get-GitBlobSha256 $document.blob_commit $document.path) "$($checkpoint.stage) historical blob $($document.path)"
    }
}

$historicalToken = Get-GitJson $manifest.base_authority.accepted_migration_evidence_head "docs/design/s10/s10-token-coverage.json"
Assert-Equal $token.document_status "migrated" "token document status"
Assert-Equal $token.component_system_product_head $stage.checkpoints[1].product_head "token component-system head"
Assert-Equal $token.migration_product_head $manifest.base_authority.accepted_migration_product_head "token migration head"
Assert-Equal $token.migration_product_head $stage.checkpoints[2].product_head "token/checkpoint migration head"
Assert-Equal $token.untracked_visual_constant_count 0 "untracked visual constants"
Assert-Equal @($token.components).Count 9 "token component count"
Assert-Equal @($token.coverage).Count 67 "token coverage count"
foreach ($component in @($token.components)) { Assert-Equal $component.status "PASS" "$($component.component_id) component status" }
foreach ($coverage in @($token.coverage)) { Assert-Equal $coverage.status "PASS" "$($coverage.screen_state_id) coverage status" }
Assert-Equal @($token.components).Count @($historicalToken.components).Count "historical component count"
for ($componentIndex = 0; $componentIndex -lt [Math]::Min(@($token.components).Count, @($historicalToken.components).Count); $componentIndex++) {
    Assert-Equal (Get-ComponentIdentityJson $token.components[$componentIndex]) (Get-ComponentIdentityJson $historicalToken.components[$componentIndex]) "immutable component identity $componentIndex"
    foreach ($evidenceID in @($historicalToken.components[$componentIndex].evidence_ids)) {
        Assert-Contains @($token.components[$componentIndex].evidence_ids) $evidenceID "component $componentIndex historical evidence"
    }
}
Assert-Equal @($token.coverage).Count @($historicalToken.coverage).Count "historical coverage count"
for ($coverageIndex = 0; $coverageIndex -lt [Math]::Min(@($token.coverage).Count, @($historicalToken.coverage).Count); $coverageIndex++) {
    Assert-Equal (Get-CoverageIdentityJson $token.coverage[$coverageIndex]) (Get-CoverageIdentityJson $historicalToken.coverage[$coverageIndex]) "immutable coverage identity $coverageIndex"
    foreach ($evidenceID in @($historicalToken.coverage[$coverageIndex].evidence_ids)) {
        Assert-Contains @($token.coverage[$coverageIndex].evidence_ids) $evidenceID "coverage $coverageIndex historical evidence"
    }
}

$experiencePath = Join-Path $RepositoryRoot "docs/design/s10/s10-experience-validation.json"
$experience = Read-JsonFile $experiencePath
$historicalExperience = Get-GitJson $manifest.base_authority.accepted_migration_receipt_head "docs/design/s10/s10-experience-validation.json"
Assert-Equal ($experience | ConvertTo-Json -Depth 100 -Compress) ($historicalExperience | ConvertTo-Json -Depth 100 -Compress) "immutable planned experience contract"
Assert-Equal $experience.product_head $manifest.base_authority.accepted_migration_product_head "experience migration anchor"

$expectedSourceTest = "FieldEvidenceAppUITests/S10_3BrandMigrationUITests.swift::S10_4AutomatedBrandLabUITests.testAutomatedBrandLabShard"
Assert-Equal $manifest.matrix_contract.source_test $expectedSourceTest "source test"
Assert-Equal $manifest.matrix_contract.comparison_method $expectedComparisonMethod "provider-local comparison method"

# Freeze the corrected seven-current/seven-minimum shard map.
$expectedShardMap = [ordered]@{
    "s10.4.current.default-light" = @("default_light", "iphone-17-ios-26.2-current", "voiceover")
    "s10.4.current.default-dark" = @("default_dark", "iphone-17-ios-26.2-current", "dark_interface")
    "s10.4.current.increased-contrast" = @("increased_contrast", "iphone-17-ios-26.2-current", "sufficient_contrast")
    "s10.4.current.ax-text" = @("ax_text", "iphone-17-ios-26.2-current", "larger_text")
    "s10.4.current.differentiate-without-color" = @("differentiate_without_color", "iphone-17-ios-26.2-current", "differentiate_without_color")
    "s10.4.current.reduce-motion" = @("reduce_motion", "iphone-17-ios-26.2-current", "reduced_motion")
    "s10.4.current.reduce-transparency" = @("reduce_transparency", "iphone-17-ios-26.2-current", "voice_control")
    "s10.4.minimum.minimum-os" = @("minimum_os", "iphone-se-3-ios-18.0-minimum", "voiceover")
    "s10.4.minimum.double-length" = @("double_length", "iphone-se-3-ios-18.0-minimum", "larger_text")
    "s10.4.minimum.rtl" = @("rtl", "iphone-se-3-ios-18.0-minimum", "dark_interface")
    "s10.4.minimum.rtl-string" = @("rtl_string", "iphone-se-3-ios-18.0-minimum", "voice_control")
    "s10.4.minimum.tall" = @("tall", "iphone-se-3-ios-18.0-minimum", "reduced_motion")
    "s10.4.minimum.accented" = @("accented", "iphone-se-3-ios-18.0-minimum", "sufficient_contrast")
    "s10.4.minimum.bounded" = @("bounded", "iphone-se-3-ios-18.0-minimum", "differentiate_without_color")
}
Assert-ExactSet @($manifest.shards.shard_id) @($expectedShardMap.Keys) "shard IDs"
Assert-ExactSet @($manifest.shards.requirement_id) @($manifest.required_requirement_ids) "shard requirement IDs"
Assert-Equal @($manifest.shards | Where-Object device_profile_id -CEQ "iphone-17-ios-26.2-current").Count 7 "current shard count"
Assert-Equal @($manifest.shards | Where-Object device_profile_id -CEQ "iphone-se-3-ios-18.0-minimum").Count 7 "minimum shard count"
foreach ($profile in @("iphone-17-ios-26.2-current", "iphone-se-3-ios-18.0-minimum")) {
    Assert-ExactSet @($manifest.shards | Where-Object device_profile_id -CEQ $profile | ForEach-Object accessibility_feature) @($manifest.required_accessibility_features) "$profile accessibility feature map"
}
$currentProfile = @($shardContract.deviceProfiles | Where-Object deviceProfileID -CEQ "iphone-17-ios-26.2-current")[0]
$minimumProfile = @($shardContract.deviceProfiles | Where-Object deviceProfileID -CEQ "iphone-se-3-ios-18.0-minimum")[0]
Assert-Equal $currentProfile.provisionRuntime $false "current runtime provisioning"
Assert-Equal $currentProfile.runtimeDownloadVersion "" "current runtime download version"
Assert-Equal $minimumProfile.provisionRuntime $true "minimum runtime provisioning"
Assert-Equal $minimumProfile.runtimeDownloadVersion "18.0" "minimum runtime download version"
for ($index = 0; $index -lt $manifest.shards.Count; $index++) {
    $shard = $manifest.shards[$index]
    Assert-Equal $shard.ordinal ($index + 1) "shard ordinal $($shard.shard_id)"
    if (-not $expectedShardMap.Contains($shard.shard_id)) {
        continue
    }
    $mapping = $expectedShardMap[$shard.shard_id]
    Assert-Equal $shard.requirement_id $mapping[0] "$($shard.shard_id) requirement"
    Assert-Equal $shard.device_profile_id $mapping[1] "$($shard.shard_id) profile"
    Assert-Equal $shard.accessibility_feature $mapping[2] "$($shard.shard_id) feature"
}

Assert-Equal $shardContract.taskID "S10.4" "shard contract task"
Assert-Equal $shardContract.expectedStateCount $manifest.matrix_contract.state_count "shard contract state count"
Assert-Equal $shardContract.expectedVisualCellCount $manifest.matrix_contract.candidate_cell_count "shard contract visual count"
Assert-Equal $shardContract.expectedAccessibilityRowCount $manifest.matrix_contract.accessibility_row_count "shard contract accessibility count"
Assert-Equal $shardContract.commonTaskCount $manifest.matrix_contract.task_count "shard contract task count"
Assert-ExactSet @($shardContract.shards.shardID) @($manifest.shards.shard_id) "Scripts/s10-4-shards.json shard IDs"
foreach ($manifestShard in $manifest.shards) {
    $contractRows = @($shardContract.shards | Where-Object shardID -CEQ $manifestShard.shard_id)
    if ($contractRows.Count -ne 1) {
        Add-ValidationError "Scripts/s10-4-shards.json must contain one row for $($manifestShard.shard_id)."
        continue
    }
    $contractShard = $contractRows[0]
    $contractProfiles = @($shardContract.deviceProfiles | Where-Object deviceProfileID -CEQ $manifestShard.device_profile_id)
    if ($contractProfiles.Count -ne 1) {
        Add-ValidationError "Scripts/s10-4-shards.json must contain one profile for $($manifestShard.device_profile_id)."
        continue
    }
    $contractProfile = $contractProfiles[0]
    Assert-Equal $contractShard.ordinal $manifestShard.ordinal "$($manifestShard.shard_id) contract ordinal"
    Assert-Equal $contractShard.requirementID $manifestShard.requirement_id "$($manifestShard.shard_id) contract requirement"
    Assert-Equal $contractShard.deviceProfileID $manifestShard.device_profile_id "$($manifestShard.shard_id) contract profile"
    Assert-ExactSet @($contractShard.accessibilityFeatures) @($manifestShard.accessibility_feature) "$($manifestShard.shard_id) contract feature"
    Assert-Equal $contractProfile.simulatorRuntime $manifestShard.simulator_runtime "$($manifestShard.shard_id) contract runtime"
    Assert-Equal $contractProfile.simulatorRuntimeBuild $manifestShard.os_build "$($manifestShard.shard_id) contract OS build"
    Assert-Equal $contractProfile.simulatorName $manifestShard.simulator_name "$($manifestShard.shard_id) contract simulator"
    $environmentMap = @{
        appearance = "appearance"
        contrast = "contrast"
        contentSizeCategory = "content_size_category"
        locale = "locale_profile_id"
        layoutDirection = "layout_direction"
        differentiateWithoutColor = "differentiate_without_color"
        reduceMotion = "reduce_motion"
        reduceTransparency = "reduce_transparency"
    }
    foreach ($contractField in $environmentMap.Keys) {
        $manifestField = $environmentMap[$contractField]
        Assert-Equal $contractShard.environment.$contractField $manifestShard.$manifestField "$($manifestShard.shard_id) contract $contractField"
    }
}

# Derive the authoritative state set and immutable legacy baseline rows.
$states = @($inventory.routes | ForEach-Object { $_.states } | ForEach-Object { $_ })
$stateIDs = @($states.state_id)
Assert-Equal $stateIDs.Count $manifest.matrix_contract.state_count "inventory state count"
Assert-ExactSet $stateIDs $stateIDs "inventory state IDs"
Assert-Equal (Get-StringSetSha256 $stateIDs) $manifest.matrix_contract.state_set_sha256 "inventory state digest"
Assert-ExactSet @($token.coverage.screen_state_id) $stateIDs "token coverage state IDs"
Assert-ExactSet @($visual.baselines.screen_state_id) $stateIDs "visual baseline state IDs"
Assert-Equal @($visual.baselines).Count 67 "legacy baseline count"

$inventoryCheckpoint = @($stage.checkpoints | Where-Object stage -CEQ "Inventory")
if ($inventoryCheckpoint.Count -ne 1) {
    Add-ValidationError "Exactly one Inventory checkpoint is required."
}
else {
    $oldVisualRecord = @($inventoryCheckpoint[0].documents | Where-Object document_type -CEQ "visual_regression")
    $oldAccessRecord = @($inventoryCheckpoint[0].documents | Where-Object document_type -CEQ "accessibility_common_tasks")
    if ($oldVisualRecord.Count -ne 1 -or $oldAccessRecord.Count -ne 1) {
        Add-ValidationError "Inventory checkpoint must identify one historical visual and accessibility blob."
    }
    else {
        $oldVisual = Get-GitJson $oldVisualRecord[0].blob_commit $oldVisualRecord[0].path
        $oldAccess = Get-GitJson $oldAccessRecord[0].blob_commit $oldAccessRecord[0].path
        Assert-Equal ($visual.baselines | ConvertTo-Json -Depth 100 -Compress) ($oldVisual.baselines | ConvertTo-Json -Depth 100 -Compress) "immutable legacy visual baselines"
        Assert-Equal @($accessibility.tasks).Count @($oldAccess.tasks).Count "accessibility task identity count"
        for ($taskIndex = 0; $taskIndex -lt $oldAccess.tasks.Count; $taskIndex++) {
            Assert-Equal (Get-TaskIdentityJson $accessibility.tasks[$taskIndex]) (Get-TaskIdentityJson $oldAccess.tasks[$taskIndex]) "accessibility task identity $taskIndex"
        }
    }
}

# AuthorityH proves the complete matrix cardinalities without requiring evidence
# that can truthfully exist only after the accepted product head and shard runs.
Assert-Equal @($manifest.required_requirement_ids).Count 14 "manifest requirement count"
Assert-Equal @($manifest.required_task_ids).Count 6 "manifest task count"
Assert-Equal @($manifest.required_accessibility_features).Count 7 "manifest accessibility feature count"
Assert-Equal ($stateIDs.Count * $manifest.required_requirement_ids.Count) $manifest.matrix_contract.candidate_cell_count "derived visual cell count"
Assert-Equal ($manifest.required_task_ids.Count * 2 * $manifest.required_accessibility_features.Count) $manifest.matrix_contract.accessibility_row_count "derived accessibility row count"
Assert-Equal (Get-StringSetSha256 @($manifest.required_requirement_ids)) $manifest.matrix_contract.requirement_set_sha256 "requirement set digest"
Assert-Equal (Get-StringSetSha256 @($manifest.required_task_ids)) $manifest.matrix_contract.task_set_sha256 "task set digest"
$authorityAccessibilityTuples = [System.Collections.Generic.List[string]]::new()
foreach ($task in $accessibility.tasks) {
    foreach ($row in $task.feature_results) {
        $authorityAccessibilityTuples.Add("$($task.task_id)|$($row.device_profile_id)|$($row.feature)")
        Assert-Equal $row.manual_status "NOT_RUN" "$($task.task_id) $($row.device_profile_id) $($row.feature) pre-E manual status"
        Assert-Equal @($row.manual_evidence_ids).Count 0 "$($task.task_id) $($row.device_profile_id) $($row.feature) pre-E manual evidence"
        Assert-Equal $row.manual_reviewer "" "$($task.task_id) $($row.device_profile_id) $($row.feature) pre-E manual reviewer"
    }
}
$authorityExpectedTuples = foreach ($taskID in $manifest.required_task_ids) {
    foreach ($profileID in @("iphone-17-ios-26.2-current", "iphone-se-3-ios-18.0-minimum")) {
        foreach ($feature in $manifest.required_accessibility_features) {
            "$taskID|$profileID|$feature"
        }
    }
}
Assert-ExactSet @($authorityAccessibilityTuples) $authorityExpectedTuples "pre-E accessibility tuples"
Assert-Equal (Get-StringSetSha256 @($authorityAccessibilityTuples)) $manifest.matrix_contract.accessibility_tuple_set_sha256 "pre-E accessibility tuple digest"

if ($LifecycleMode -cne "AuthorityH") {
    if ([string]::IsNullOrWhiteSpace($ProductHead) -or [string]::IsNullOrWhiteSpace($EvidenceHead)) {
        throw "$LifecycleMode requires both -ProductHead and -EvidenceHead."
    }

# Bind E, K, protected product scope, and the three K evidence documents.
Assert-Commit $ProductHead "product head E"
Assert-Commit $EvidenceHead "evidence head K"
Assert-H413WorkingPolicyBindings $LifecycleMode $EvidenceHead $ReceiptHead
Assert-H420DeferredSmokeRecord $visual.minimum_core_smoke $h413Policy (Get-H411Field $manifest 'minimum_verification_deferral_contract')
Assert-Ancestor $manifest.base_authority.accepted_migration_receipt_head $ProductHead "S10.3 C to S10.4 E lineage"
Assert-Ancestor $ProductHead $EvidenceHead "E to K lineage"
$migrationToProductDelta = @(& git -C $RepositoryRoot diff --name-only "$($manifest.base_authority.accepted_migration_product_head)..$ProductHead")
Assert-ExactSet $migrationToProductDelta @($manifest.product_delta_allowlist) "S10.3 E..S10.4 E paths"

$evidenceDocumentPaths = @(
    "docs/design/s10/s10-accessibility-common-tasks.json",
    "docs/design/s10/s10-token-coverage.json",
    "docs/design/s10/s10-visual-regression.json"
)
$evidenceDelta = @(& git -C $RepositoryRoot diff --name-only "$ProductHead..$EvidenceHead")
foreach ($requiredPath in $evidenceDocumentPaths) {
    Assert-Contains $evidenceDelta $requiredPath "E..K evidence paths"
}
Assert-H413EvidenceDelta $evidenceDelta $h413Policy
foreach ($path in $evidenceDocumentPaths) {
    Assert-Equal (Get-GitBlobSha256 $EvidenceHead $path) (Get-Sha256 (Join-Path $RepositoryRoot $path)) "working document equals K blob $path"
}

# Bind nine required original receipts; retain all 938 slots with explicit deferral.
Assert-Equal $visual.acceptance_policy_id $h413Policy.policy_id "visual acceptance policy"
Assert-Equal $accessibility.acceptance_policy_id $h413Policy.policy_id "accessibility acceptance policy"
Assert-ExactSet @($visual.shard_receipts.shard_id) @($h413Policy.required_shard_ids) "required visual shard receipt IDs"
Assert-Equal @($visual.shard_receipts).Count $h413RequiredShards.Count "required shard receipt count"
$receiptByShard = @{}
$bitriseReceiptCount = 0
$payloadFingerprints = [System.Collections.Generic.List[string]]::new()
$githubEquivalenceReceipts = @(if ($visual.PSObject.Properties.Name -ccontains "github_equivalence_receipts") { @($visual.github_equivalence_receipts) } else { @() })
$githubEquivalenceByID = @{}
$githubEquivalenceByShard = @{}
foreach ($githubReceipt in $githubEquivalenceReceipts) {
    $githubReceiptID = [string]$githubReceipt.receipt_id
    $githubShardID = [string]$githubReceipt.shard_id
    if ($githubEquivalenceByID.ContainsKey($githubReceiptID)) {
        Add-ValidationError "Duplicate GitHub equivalence receipt ID '$githubReceiptID'."
    }
    else {
        $githubEquivalenceByID[$githubReceiptID] = $githubReceipt
    }
    if ($githubEquivalenceByShard.ContainsKey($githubShardID)) {
        Add-ValidationError "Duplicate GitHub equivalence receipt shard '$githubShardID'."
    }
    else {
        $githubEquivalenceByShard[$githubShardID] = $githubReceipt
    }
    Assert-Contains $expectedBitriseShards $githubShardID "$githubShardID GitHub equivalence eligibility"
    $githubRequirementID = $githubShardID.Replace("s10.4.current.", "")
    Assert-Equal $githubReceiptID "s10.4-github-equivalence-$githubRequirementID" "$githubShardID GitHub equivalence receipt ID"
    $githubRunEvidenceID = "github-actions-run-$($githubReceipt.run_id)-job-$($githubReceipt.job_id)-artifact-$($githubReceipt.artifact_id)"
    Assert-Equal $githubReceipt.receipt_evidence_id $githubRunEvidenceID "$githubShardID GitHub equivalence evidence ID"
    Assert-Contains @($githubReceipt.evidence_ids) $githubRunEvidenceID "$githubShardID GitHub equivalence evidence"
    Assert-Equal $githubReceipt.source_product_head $ProductHead "$githubShardID GitHub equivalence head"
    Assert-GitHubReceiptEnvironment $githubReceipt "$githubShardID GitHub equivalence"
    Assert-Equal $githubReceipt.xcode_version $activation.toolchain.xcode_version "$githubShardID GitHub equivalence Xcode version"
    Assert-Equal $githubReceipt.xcode_build $activation.toolchain.xcode_build "$githubShardID GitHub equivalence Xcode build"
    Assert-Equal $githubReceipt.simulator_runtime $hybrid.bitrise_current_device_profile.simulator_runtime "$githubShardID GitHub equivalence runtime"
    Assert-Equal $githubReceipt.simulator_name $hybrid.bitrise_current_device_profile.simulator_name "$githubShardID GitHub equivalence simulator"
    Assert-Equal $githubReceipt.simulator_os_build $hybrid.bitrise_current_device_profile.simulator_os_build "$githubShardID GitHub equivalence OS build"
    Assert-Equal $githubReceipt.selector $hybrid.equivalence_gate.selector "$githubShardID GitHub equivalence selector"
    Assert-Equal $githubReceipt.state_set_sha256 $manifest.matrix_contract.state_set_sha256 "$githubShardID GitHub equivalence state digest"
    Assert-Equal $githubReceipt.unit_test_count 5 "$githubShardID GitHub equivalence unit count"
    Assert-Equal $githubReceipt.unit_result "PASS" "$githubShardID GitHub equivalence unit result"
    Assert-Equal $githubReceipt.ax_state_count 67 "$githubShardID GitHub equivalence AX count"
    Assert-Equal $githubReceipt.ax_result "PASS" "$githubShardID GitHub equivalence AX result"
    Assert-Equal $githubReceipt.contrast_state_count 67 "$githubShardID GitHub equivalence contrast count"
    Assert-Equal $githubReceipt.contrast_result "PASS" "$githubShardID GitHub equivalence contrast result"
    Assert-Equal $githubReceipt.accessibility_task_count 6 "$githubShardID GitHub equivalence task count"
    Assert-Equal $githubReceipt.task_result "PASS" "$githubShardID GitHub equivalence task result"
    Assert-Equal $githubReceipt.watchdog_result "PASS" "$githubShardID GitHub equivalence watchdog result"
    Assert-Equal $githubReceipt.receipt_result "PASS" "$githubShardID GitHub equivalence receipt result"
}
# H411_SHARED_MATRIX_BEGIN
$sharedReceipts = @($visual.shard_receipts | Where-Object { $null -ne (Get-H411Field $_ 'execution_model') })
Assert-Equal $sharedReceipts.Count $h413RequiredShards.Count 'complete required shared logical matrix'
if ($sharedReceipts.Count -eq $h413RequiredShards.Count) {
    Assert-Equal @($sharedReceipts | ForEach-Object { "$($_.shared_execution.shared_build_identity_sha256)|$($_.shared_execution.producer_qualification_sha256)|$($_.source_product_head)" } | Sort-Object -Unique).Count 1 'one selected head/payload/qualification'
}
# H411_SHARED_MATRIX_END

foreach ($receipt in $visual.shard_receipts) {
    $receiptByShard[$receipt.shard_id] = $receipt
    $shard = @($manifest.shards | Where-Object shard_id -CEQ $receipt.shard_id)[0]
    Assert-Equal $receipt.requirement_id $shard.requirement_id "$($receipt.shard_id) receipt requirement"
    Assert-Equal $receipt.device_profile_id $shard.device_profile_id "$($receipt.shard_id) receipt profile"
    Assert-Equal $receipt.accessibility_feature $shard.accessibility_feature "$($receipt.shard_id) receipt feature"
    Assert-Equal $receipt.source_product_head $ProductHead "$($receipt.shard_id) receipt E"
    # H411_SHARED_RECEIPT_BEGIN
    $model = Get-H411Field $receipt 'execution_model'
    $isAssembly = $model -ceq 'shared-segment-assembly-v1'
    if ($null -ne $model) {
        if ($null -eq (Get-H411Field $receipt 'shared_execution')) { Add-ValidationError "$($receipt.shard_id) missing shared execution" }
        else { Assert-H411SharedReceipt $receipt $shard }
    } else {
        foreach ($field in @('shared_execution','segmented_execution','consumer_build_reference')) {
            if ($null -ne (Get-H411Field $receipt $field)) { Add-ValidationError "$($receipt.shard_id) orphan $field" }
        }
        foreach ($field in @('runner_label','runner_image','xcode_version','xcode_build','sdk_name','sdk_build','simulator_runtime','simulator_name','simulator_os_build','simulator_udid')) {
            if ($null -eq (Get-H411Field $receipt $field)) { Add-ValidationError "$($receipt.shard_id) missing native $field" }
        }
    }
    # H411_SHARED_RECEIPT_END
    $provider = if ($null -eq $receipt.PSObject.Properties["runner_provider"] -or [string]::IsNullOrWhiteSpace([string]$receipt.runner_provider)) { "github_actions" } else { [string]$receipt.runner_provider }
    if ($provider -ceq "github_actions") {
        if (-not $isAssembly) {
        Assert-Equal $receipt.runner_label $activation.toolchain.runner_label "$($receipt.shard_id) GitHub runner label"
        Assert-GitHubReceiptEnvironment $receipt "$($receipt.shard_id) GitHub receipt"
        }
    }
    elseif ($provider -ceq "bitrise_build_hub") {
        if ($receipt.PSObject.Properties.Name -ccontains "github_environment") {
            Add-ValidationError "$($receipt.shard_id) Bitrise receipt must not carry GitHub environment fields."
        }
        $bitriseReceiptCount++
        Assert-Contains $expectedBitriseShards $receipt.shard_id "$($receipt.shard_id) Bitrise eligibility"
        Assert-Equal $receipt.runner_label "bitrise-runner-Asset Roundddd" "$($receipt.shard_id) Bitrise runner label"
        Assert-Equal $receipt.simulator_runtime $hybrid.bitrise_current_device_profile.simulator_runtime "$($receipt.shard_id) Bitrise runtime"
        Assert-Equal $receipt.simulator_name $hybrid.bitrise_current_device_profile.simulator_name "$($receipt.shard_id) Bitrise simulator"
        Assert-Equal $receipt.simulator_os_build $hybrid.bitrise_current_device_profile.simulator_os_build "$($receipt.shard_id) Bitrise OS build"
        foreach ($field in @("build_payload", "same_shard_github_equivalence", "provider_local_screenshot_checksum_manifest_path", "provider_local_screenshot_checksum_manifest_sha256")) {
            if ($null -eq $receipt.$field -or [string]::IsNullOrWhiteSpace([string]$receipt.$field)) {
                Add-ValidationError "$($receipt.shard_id) Bitrise receipt lacks $field."
            }
        }
        if ($null -ne $receipt.same_shard_github_equivalence) {
            $equivalence = $receipt.same_shard_github_equivalence
            Assert-Equal $equivalence.equivalent $true "$($receipt.shard_id) same-shard equivalence"
            Assert-Equal $equivalence.github_shard_id $receipt.shard_id "$($receipt.shard_id) equivalence shard"
            $githubReceiptEvidenceID = "github-actions-run-$($equivalence.github_run_id)-job-$($equivalence.github_job_id)-artifact-$($equivalence.github_artifact_id)"
            Assert-Equal $equivalence.github_receipt_evidence_id $githubReceiptEvidenceID "$($receipt.shard_id) equivalence receipt evidence ID"
            $githubReceipt = if ($githubEquivalenceByID.ContainsKey([string]$equivalence.github_receipt_id)) { $githubEquivalenceByID[[string]$equivalence.github_receipt_id] } else { $null }
            if ($null -eq $githubReceipt) {
                Add-ValidationError "$($receipt.shard_id) equivalence does not resolve a unique GitHub receipt '$($equivalence.github_receipt_id)'."
            }
            else {
                Assert-Equal $githubReceipt.shard_id $receipt.shard_id "$($receipt.shard_id) resolved GitHub receipt shard"
                Assert-Equal $equivalence.github_run_id $githubReceipt.run_id "$($receipt.shard_id) equivalence GitHub run"
                Assert-Equal $equivalence.github_job_id $githubReceipt.job_id "$($receipt.shard_id) equivalence GitHub job"
                Assert-Equal $equivalence.github_artifact_id $githubReceipt.artifact_id "$($receipt.shard_id) equivalence GitHub artifact"
                Assert-Equal $equivalence.github_artifact_digest $githubReceipt.artifact_digest "$($receipt.shard_id) equivalence GitHub artifact digest"
                Assert-Equal $equivalence.github_receipt_evidence_id $githubReceipt.receipt_evidence_id "$($receipt.shard_id) equivalence GitHub evidence ID"
                Assert-Equal $equivalence.github_receipt_sha256 $githubReceipt.receipt_sha256 "$($receipt.shard_id) equivalence GitHub receipt hash"
                Assert-Equal $equivalence.github_artifact_checksum_manifest_sha256 $githubReceipt.artifact_checksum_manifest_sha256 "$($receipt.shard_id) equivalence GitHub checksum-manifest hash"
                Assert-Equal $equivalence.shared_build_archive_sha256 $githubReceipt.shared_build_archive_sha256 "$($receipt.shard_id) equivalence GitHub payload archive"
                Assert-Equal $equivalence.shared_build_xctestrun_sha256 $githubReceipt.shared_build_xctestrun_sha256 "$($receipt.shard_id) equivalence GitHub xctestrun"
                Assert-Equal $equivalence.shared_build_products_sha256 $githubReceipt.shared_build_products_sha256 "$($receipt.shard_id) equivalence GitHub Build/Products"
            }
            Assert-Equal $equivalence.source_product_head $ProductHead "$($receipt.shard_id) equivalence head"
            Assert-Equal $equivalence.xcode_version $activation.toolchain.xcode_version "$($receipt.shard_id) equivalence Xcode version"
            Assert-Equal $equivalence.xcode_build $activation.toolchain.xcode_build "$($receipt.shard_id) equivalence Xcode build"
            Assert-Equal $equivalence.simulator_runtime $receipt.simulator_runtime "$($receipt.shard_id) equivalence runtime"
            Assert-Equal $equivalence.simulator_name $receipt.simulator_name "$($receipt.shard_id) equivalence simulator"
            Assert-Equal $equivalence.simulator_os_build $receipt.simulator_os_build "$($receipt.shard_id) equivalence OS build"
            Assert-Equal $equivalence.selector $receipt.selector "$($receipt.shard_id) equivalence selector"
            Assert-Equal $equivalence.state_set_sha256 $receipt.state_set_sha256 "$($receipt.shard_id) equivalence state digest"
            Assert-Equal $equivalence.shared_build_archive_sha256 $receipt.build_payload.archive_sha256 "$($receipt.shard_id) equivalence payload archive"
            Assert-Equal $equivalence.shared_build_xctestrun_sha256 $receipt.build_payload.xctestrun_sha256 "$($receipt.shard_id) equivalence xctestrun"
            Assert-Equal $equivalence.shared_build_products_sha256 $receipt.build_payload.build_products_sha256 "$($receipt.shard_id) equivalence Build/Products"
            Assert-Equal $equivalence.unit_test_count 5 "$($receipt.shard_id) equivalence unit count"
            Assert-Equal $equivalence.unit_result "PASS" "$($receipt.shard_id) equivalence unit result"
            Assert-Equal $equivalence.ax_state_count 67 "$($receipt.shard_id) equivalence AX count"
            Assert-Equal $equivalence.ax_result "PASS" "$($receipt.shard_id) equivalence AX result"
            Assert-Equal $equivalence.contrast_state_count 67 "$($receipt.shard_id) equivalence contrast count"
            Assert-Equal $equivalence.contrast_result "PASS" "$($receipt.shard_id) equivalence contrast result"
            Assert-Equal $equivalence.accessibility_task_count 6 "$($receipt.shard_id) equivalence task count"
            Assert-Equal $equivalence.task_result "PASS" "$($receipt.shard_id) equivalence task result"
            Assert-Equal $equivalence.watchdog_result "PASS" "$($receipt.shard_id) equivalence watchdog result"
            Assert-Equal $equivalence.receipt_result "PASS" "$($receipt.shard_id) equivalence receipt result"
            Assert-Equal $equivalence.cross_provider_screenshot_byte_equality_required $false "$($receipt.shard_id) equivalence screenshot policy"
        }
    }
    else {
        Add-ValidationError "$($receipt.shard_id) has unsupported runner provider '$provider'."
    }
    if (-not $isAssembly) {
    Assert-Equal $receipt.xcode_version $activation.toolchain.xcode_version "$($receipt.shard_id) Xcode version"
    Assert-Equal $receipt.xcode_build $activation.toolchain.xcode_build "$($receipt.shard_id) Xcode build"
    Assert-Equal $receipt.sdk_name $activation.toolchain.sdk_name "$($receipt.shard_id) SDK"
    Assert-Equal $receipt.sdk_build $activation.toolchain.sdk_build "$($receipt.shard_id) SDK build"
    Assert-Equal $receipt.simulator_runtime $shard.simulator_runtime "$($receipt.shard_id) runtime"
    Assert-Equal $receipt.simulator_name $shard.simulator_name "$($receipt.shard_id) simulator"
    Assert-Equal $receipt.simulator_os_build $shard.os_build "$($receipt.shard_id) OS build"
    }
    Assert-Equal $receipt.selector "FieldEvidenceAppUITests/S10_4AutomatedBrandLabUITests" "$($receipt.shard_id) selector"
    Assert-Equal $receipt.conclusion "success" "$($receipt.shard_id) conclusion"
    Assert-Equal $receipt.state_count 67 "$($receipt.shard_id) state count"
    Assert-Equal $receipt.accessibility_task_count 6 "$($receipt.shard_id) task count"
    Assert-Equal $receipt.state_set_sha256 $manifest.matrix_contract.state_set_sha256 "$($receipt.shard_id) state digest"
    $payload = Get-H411Field $receipt 'build_payload'
    if ($null -ne $payload) {
        Assert-Equal $payload.profile_id $hybrid.payload_profile.profile_id "$($receipt.shard_id) payload profile"
        Assert-Equal $payload.producer_provider $hybrid.payload_profile.producer_provider "$($receipt.shard_id) payload producer provider"
        Assert-Equal $payload.source_product_head $ProductHead "$($receipt.shard_id) payload head"
        Assert-Equal $payload.complete_build_products_closure $true "$($receipt.shard_id) payload Build/Products closure"
        Assert-Equal $payload.immutable $true "$($receipt.shard_id) payload immutable"
        Assert-Equal $payload.relocatable $true "$($receipt.shard_id) payload relocatable"
        Assert-Equal $payload.consumer_execution_mode "test-without-building" "$($receipt.shard_id) payload execution mode"
        Assert-Equal $payload.consumer_rebuild_forbidden $true "$($receipt.shard_id) payload rebuild prohibition"
        Assert-Equal $payload.consumer_fallback_forbidden $true "$($receipt.shard_id) payload fallback prohibition"
        Assert-Equal $payload.mixed_head_forbidden $true "$($receipt.shard_id) payload mixed-head prohibition"
        $payloadFingerprints.Add("$($payload.archive_sha256)|$($payload.xctestrun_sha256)|$($payload.build_products_sha256)|$($payload.source_product_head)")
    }
    $runEvidenceID = "github-actions-run-$($receipt.run_id)-job-$($receipt.job_id)-artifact-$($receipt.artifact_id)"
    Assert-Contains @($receipt.evidence_ids) $runEvidenceID "$($receipt.shard_id) receipt evidence"
}
if ($bitriseReceiptCount -ne 0) {
    Assert-Equal $githubEquivalenceReceipts.Count $bitriseReceiptCount "one unique GitHub equivalence receipt per Bitrise receipt"
    Assert-Equal $payloadFingerprints.Count @($visual.shard_receipts).Count "all consumers carry shared build payload"
    Assert-Equal @($payloadFingerprints | Select-Object -Unique).Count 1 "one exact-head build payload"
}
else {
    Assert-Equal $githubEquivalenceReceipts.Count 0 "no unused GitHub equivalence receipts without Bitrise receipts"
}

$expectedCandidateTuples = foreach ($stateID in $stateIDs) {
    foreach ($requirementID in $manifest.required_requirement_ids) {
        "$stateID|$requirementID"
    }
}
$candidateTuples = @($visual.candidate_cells | ForEach-Object { "$($_.screen_state_id)|$($_.requirement_id)" })
Assert-Equal @($visual.candidate_cells).Count 938 "candidate cell count"
Assert-ExactSet $candidateTuples $expectedCandidateTuples "candidate state-requirement tuples"
Assert-Equal (Get-StringSetSha256 $candidateTuples) $manifest.matrix_contract.candidate_tuple_set_sha256 "candidate tuple digest"
Assert-ExactSet @($visual.candidate_cells.cell_id) @($visual.candidate_cells.cell_id) "candidate cell IDs"

$baselineByState = @{}
foreach ($baseline in $visual.baselines) { $baselineByState[$baseline.screen_state_id] = $baseline.baseline_id }
$changeIDs = @($visual.change_records.change_id)
foreach ($cell in $visual.candidate_cells) {
    $shard = @($manifest.shards | Where-Object requirement_id -CEQ $cell.requirement_id)[0]
    Assert-Equal $cell.baseline_id $baselineByState[$cell.screen_state_id] "$($cell.cell_id) baseline"
    Assert-Equal $cell.shard_id $shard.shard_id "$($cell.cell_id) catalog shard"
    foreach ($field in @("device_profile_id", "os_build", "appearance", "contrast", "content_size_category", "locale_profile_id", "layout_direction", "differentiate_without_color", "reduce_motion", "reduce_transparency")) {
        Assert-Equal $cell.$field $shard.$field "$($cell.cell_id) catalog $field"
    }
    if ($shard.shard_id -cin @($h413Policy.deferred_shard_ids)) {
        Assert-H413DeferredVisual $cell
        continue
    }
    Assert-Equal $cell.acceptance_scope 'REQUIRED' "$($cell.cell_id) mandatory scope"
    Assert-Equal $cell.deferral_reason '' "$($cell.cell_id) required no deferral"
    $receipt = $receiptByShard[$shard.shard_id]
    $receiptProvider = if ([string]::IsNullOrWhiteSpace([string]$receipt.runner_provider)) { "github_actions" } else { [string]$receipt.runner_provider }
    Assert-Equal $cell.shard_id $shard.shard_id "$($cell.cell_id) shard"
    Assert-Equal $cell.source_product_head $ProductHead "$($cell.cell_id) E"
    Assert-Equal $cell.source_test $expectedSourceTest "$($cell.cell_id) source test"
    foreach ($field in @("device_profile_id", "os_build", "appearance", "contrast", "content_size_category", "locale_profile_id", "layout_direction", "differentiate_without_color", "reduce_motion", "reduce_transparency")) {
        Assert-Equal $cell.$field $shard.$field "$($cell.cell_id) $field"
    }
    # H411_CELL_SOURCE_BEGIN
    $cellReceipt = $receipt
    if ((Get-H411Field $receipt 'execution_model') -ceq 'shared-segment-assembly-v1') {
        $segmentID = Get-H411Field $cell 'source_segment_id'
        $sources = @($receipt.segmented_execution.consumers | Where-Object { $_.segment_id -ceq $segmentID -and @($_.owned_state_ids) -ccontains $cell.screen_state_id })
        Assert-Equal $sources.Count 1 "$($cell.cell_id) original owned consumer"
        if ($sources.Count -eq 1) { $cellReceipt = $sources[0] }
    } elseif ($null -ne (Get-H411Field $cell 'source_segment_id')) { Add-ValidationError "$($cell.cell_id) orphan source segment" }
    foreach ($field in @("run_id", "job_id", "artifact_id", "artifact_name", "artifact_digest")) {
        Assert-Equal $cell.$field $cellReceipt.$field "$($cell.cell_id) $field"
    }
    # H411_CELL_SOURCE_END
    if ($receiptProvider -ceq "bitrise_build_hub" -and [string]::IsNullOrWhiteSpace([string]$cell.runner_provider)) {
        Add-ValidationError "$($cell.cell_id) Bitrise candidate lacks runner_provider."
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$cell.runner_provider)) {
        Assert-Equal $cell.runner_provider $receiptProvider "$($cell.cell_id) runner provider"
    }
    $expectedAttachmentName = "S10.4 candidate $($cell.shard_id) $($cell.screen_state_id)"
    $artifactRoot = "https://github.com/palatis3/AssetRounds/actions/runs/$($cell.run_id)/artifacts/$($cell.artifact_id)"
    $expectedLocator = "$artifactRoot :: attachment=$expectedAttachmentName"
    $expectedAXID = "s10.4-ax-$($cell.shard_id)-$($cell.screen_state_id)"
    $expectedAXLocator = "$artifactRoot :: entry=ax/$($cell.shard_id)/$($cell.screen_state_id).json"
    $expectedContrastID = "s10.4-contrast-$($cell.shard_id)-$($cell.screen_state_id)"
    $expectedContrastLocator = "$artifactRoot :: entry=contrast/$($cell.shard_id)/$($cell.screen_state_id).json"
    $expectedReviewID = "owner-review-$($cell.shard_id)-$($cell.screen_state_id)"
    Assert-Equal $cell.attachment_name $expectedAttachmentName "$($cell.cell_id) attachment name"
    Assert-Equal $cell.attachment_locator $expectedLocator "$($cell.cell_id) attachment locator"
    Assert-Equal $cell.ax_evidence_id $expectedAXID "$($cell.cell_id) AX evidence ID"
    Assert-Equal $cell.ax_evidence_locator $expectedAXLocator "$($cell.cell_id) AX evidence locator"
    Assert-Equal $cell.contrast_evidence_id $expectedContrastID "$($cell.cell_id) contrast evidence ID"
    Assert-Equal $cell.contrast_evidence_locator $expectedContrastLocator "$($cell.cell_id) contrast evidence locator"
    Assert-Equal $cell.comparison_method $expectedComparisonMethod "$($cell.cell_id) comparison method"
    Assert-Equal $cell.tolerance 0 "$($cell.cell_id) tolerance"
    Assert-Equal $cell.result "PASS" "$($cell.cell_id) result"
    Assert-Equal $cell.review_status "APPROVED" "$($cell.cell_id) review status"
    foreach ($changeID in $cell.intended_change_ids) {
        Assert-Contains $changeIDs $changeID "$($cell.cell_id) intended changes"
    }
    $runEvidenceID = "github-actions-run-$($cell.run_id)-job-$($cell.job_id)-artifact-$($cell.artifact_id)"
    foreach ($evidenceID in @($runEvidenceID, $cell.ax_evidence_id, $cell.contrast_evidence_id)) {
        Assert-Contains @($cell.evidence_ids) $evidenceID "$($cell.cell_id) evidence"
    }
    Assert-Contains @($cell.evidence_ids) $expectedReviewID "$($cell.cell_id) review evidence"
}

# Recompute all 84 task-by-profile-by-feature rows; automated evidence is closed while manual is explicitly unclaimed.
Assert-ExactSet @($accessibility.device_profile_ids) @("iphone-17-ios-26.2-current", "iphone-se-3-ios-18.0-minimum") "accessibility profiles"
Assert-ExactSet @($accessibility.features) @($manifest.required_accessibility_features) "accessibility feature list"
Assert-ExactSet @($accessibility.tasks.task_id) @($manifest.required_task_ids) "accessibility task IDs"
$accessibilityTuples = [System.Collections.Generic.List[string]]::new()
$automatedClosed = 0
$manualOpen = 0
$h413DeferredAX = 0
foreach ($task in $accessibility.tasks) {
    Assert-Equal @($task.feature_results).Count 14 "$($task.task_id) result count"
    foreach ($row in $task.feature_results) {
        $tuple = "$($task.task_id)|$($row.device_profile_id)|$($row.feature)"
        $accessibilityTuples.Add($tuple)
        $matchingShards = @($manifest.shards | Where-Object { $_.device_profile_id -ceq $row.device_profile_id -and $_.accessibility_feature -ceq $row.feature })
        if ($matchingShards.Count -ne 1) {
            Add-ValidationError "$tuple does not map to exactly one shard."
            continue
        }
        $shard = $matchingShards[0]
        Assert-Equal $row.automation_shard_id $shard.shard_id "$tuple shard"
        if ($shard.shard_id -cin @($h413Policy.deferred_shard_ids)) {
            Assert-H413DeferredAccessibility $row $tuple
            $h413DeferredAX++
            $manualOpen++
            continue
        }
        Assert-Equal $row.acceptance_scope 'REQUIRED' "$tuple mandatory scope"
        $receipt = $receiptByShard[$shard.shard_id]
        Assert-Equal $row.source_product_head $ProductHead "$tuple E"
        foreach ($field in @("run_id", "job_id", "artifact_id", "artifact_digest")) {
            Assert-Equal $row.$field $receipt.$field "$tuple $field"
        }
        $artifactRoot = "https://github.com/palatis3/AssetRounds/actions/runs/$($row.run_id)/artifacts/$($row.artifact_id)"
        $expectedAXID = "s10.4-ax-$($row.automation_shard_id)-$($task.task_id)"
        $expectedAXLocator = "$artifactRoot :: entry=accessibility/$($row.automation_shard_id)/$($task.task_id).json"
        $expectedFocusID = "s10.4-focus-order-$($row.automation_shard_id)-$($task.task_id)"
        $expectedTargetID = "s10.4-target-size-$($row.automation_shard_id)-$($task.task_id)"
        $expectedContrastID = "s10.4-contrast-$($row.automation_shard_id)-$($task.task_id)"
        Assert-Equal $row.ax_evidence_id $expectedAXID "$tuple AX evidence ID"
        Assert-Equal $row.ax_evidence_locator $expectedAXLocator "$tuple AX evidence locator"
        Assert-Equal $row.focus_order_evidence_id $expectedFocusID "$tuple focus evidence ID"
        Assert-Equal $row.target_size_evidence_id $expectedTargetID "$tuple target evidence ID"
        Assert-Equal $row.contrast_evidence_id $expectedContrastID "$tuple contrast evidence ID"
        $runEvidenceID = "github-actions-run-$($row.run_id)-job-$($row.job_id)-artifact-$($row.artifact_id)"
        foreach ($evidenceID in @($runEvidenceID, $row.ax_evidence_id, $row.focus_order_evidence_id, $row.target_size_evidence_id, $row.contrast_evidence_id)) {
            Assert-Contains @($row.automated_evidence_ids) $evidenceID "$tuple automated evidence"
        }
        if ($row.automated_status -cin @("PASS", "NOT_APPLICABLE", "EXCEPTION")) { $automatedClosed++ }
        if ($row.automated_status -ceq "EXCEPTION") {
            foreach ($field in @("exception_issue_id", "exception_owner", "exception_expires_at", "exception_rationale")) {
                if ([string]::IsNullOrWhiteSpace([string]$row.$field)) { Add-ValidationError "$tuple exception lacks $field." }
            }
            if ([string]$row.exception_expires_at -notmatch '^\d{4}-\d{2}-\d{2}$') { Add-ValidationError "$tuple exception expiry is not an ISO date." }
        }
        else {
            foreach ($field in @("exception_issue_id", "exception_owner", "exception_expires_at", "exception_rationale")) {
                Assert-Equal $row.$field "" "$tuple nonexception $field"
            }
        }
        Assert-Equal $row.manual_status "NOT_RUN" "$tuple manual status"
        Assert-Equal @($row.manual_evidence_ids).Count 0 "$tuple manual evidence count"
        Assert-Equal $row.manual_reviewer "" "$tuple manual reviewer"
        $manualOpen++
    }
}
$expectedAccessibilityTuples = foreach ($taskID in $manifest.required_task_ids) {
    foreach ($profileID in @("iphone-17-ios-26.2-current", "iphone-se-3-ios-18.0-minimum")) {
        foreach ($feature in $manifest.required_accessibility_features) {
            "$taskID|$profileID|$feature"
        }
    }
}
Assert-ExactSet @($accessibilityTuples) $expectedAccessibilityTuples "accessibility tuples"
Assert-Equal (Get-StringSetSha256 @($accessibilityTuples)) $manifest.matrix_contract.accessibility_tuple_set_sha256 "accessibility tuple digest"

# Recompute both aggregates rather than trusting recorded totals.
$visualAggregate = $visual.aggregate
Assert-Equal $visualAggregate.source_product_head $ProductHead "visual aggregate E"
Assert-Equal $visualAggregate.shard_count @($visual.shard_receipts).Count "aggregate shard count"
Assert-Equal $visualAggregate.candidate_cell_count @($visual.candidate_cells).Count "aggregate candidate count"
Assert-Equal $visualAggregate.accessibility_row_count $accessibilityTuples.Count "aggregate accessibility row count"
Assert-Equal $visualAggregate.state_count $stateIDs.Count "aggregate state count"
Assert-Equal $visualAggregate.requirement_count @($manifest.required_requirement_ids).Count "aggregate requirement count"
Assert-Equal $visualAggregate.device_profile_count 2 "aggregate profile count"
Assert-Equal $visualAggregate.all_shards_success $false "full catalog deliberately not accepted"
Assert-Equal $visualAggregate.human_review_complete $false "full catalog deliberately not human reviewed"
Assert-Equal $visualAggregate.available_shard_count @($manifest.shards).Count "available shard count"
Assert-Equal $visualAggregate.required_shard_count $h413RequiredShards.Count "required shard count"
Assert-Equal $visualAggregate.deferred_shard_count $h413DeferredShards.Count "deferred shard count"
Assert-Equal $visualAggregate.required_visual_cell_count @($visual.candidate_cells | Where-Object { $_.acceptance_scope -ceq 'REQUIRED' }).Count "required visual cell count"
Assert-Equal $visualAggregate.deferred_visual_cell_count @($visual.candidate_cells | Where-Object { $_.acceptance_scope -ceq 'DEFERRED' }).Count "deferred visual cell count"
Assert-Equal $visualAggregate.required_accessibility_row_count $automatedClosed "required accessibility row count"
Assert-Equal $visualAggregate.deferred_accessibility_row_count $h413DeferredAX "deferred accessibility row count"
Assert-Equal $visualAggregate.all_required_shards_success $true "all required shards success"
Assert-Equal $visualAggregate.all_required_human_reviews_complete $true "all required human reviews complete"
Assert-Equal $visualAggregate.state_set_sha256 $manifest.matrix_contract.state_set_sha256 "aggregate state digest"
Assert-Equal $visualAggregate.requirement_set_sha256 $manifest.matrix_contract.requirement_set_sha256 "aggregate requirement digest"
Assert-Equal $visualAggregate.candidate_tuple_set_sha256 $manifest.matrix_contract.candidate_tuple_set_sha256 "aggregate candidate digest"
Assert-Equal $visualAggregate.accessibility_tuple_set_sha256 $manifest.matrix_contract.accessibility_tuple_set_sha256 "aggregate accessibility digest"

$accessAggregate = $accessibility.aggregate
Assert-Equal $accessibility.source_product_head $ProductHead "accessibility document E"
Assert-Equal $accessAggregate.source_product_head $ProductHead "accessibility aggregate E"
Assert-Equal $accessAggregate.task_count @($accessibility.tasks).Count "accessibility aggregate tasks"
Assert-Equal $accessAggregate.device_profile_count 2 "accessibility aggregate profiles"
Assert-Equal $accessAggregate.feature_count 7 "accessibility aggregate features"
Assert-Equal $accessAggregate.automated_row_count $accessibilityTuples.Count "accessibility aggregate automated rows"
Assert-Equal $accessAggregate.manual_open_row_count $manualOpen "accessibility aggregate manual rows"
Assert-Equal $accessAggregate.task_set_sha256 $manifest.matrix_contract.task_set_sha256 "accessibility aggregate task digest"
Assert-Equal $accessAggregate.accessibility_tuple_set_sha256 $manifest.matrix_contract.accessibility_tuple_set_sha256 "accessibility aggregate tuple digest"
Assert-Equal $accessAggregate.all_automated_rows_closed $false "full accessibility catalog deliberately not closed"
Assert-Equal $accessAggregate.required_automated_row_count $automatedClosed "required automated row count"
Assert-Equal $accessAggregate.deferred_automated_row_count $h413DeferredAX "deferred automated row count"
Assert-Equal $automatedClosed $h413Policy.required_accessibility_row_count "all required automated rows evidenced"
Assert-Equal $h413DeferredAX $h413Policy.deferred_accessibility_row_count "all deferred rows explicit"
Assert-Equal $accessAggregate.all_required_automated_rows_closed ($automatedClosed -eq $h413Policy.required_accessibility_row_count) "all required automated rows closed"
Assert-Equal $accessAggregate.manual_results_unclaimed $true "manual results unclaimed"

# ReceiptC additionally proves the later checkpoint receipt without rewriting K evidence.
if ($LifecycleMode -ceq "ReceiptC") {
    if ([string]::IsNullOrWhiteSpace($ReceiptHead)) {
        Add-ValidationError "ReceiptC requires -ReceiptHead."
    }
    else {
        Assert-Commit $ReceiptHead "receipt head C"
        Assert-Ancestor $EvidenceHead $ReceiptHead "K to C lineage"
        $receiptDelta = @(& git -C $RepositoryRoot diff --name-only "$EvidenceHead..$ReceiptHead")
        Assert-Contains $receiptDelta "docs/design/s10/s10-stage-checkpoints.json" "K..C receipt paths"
        foreach ($changedPath in $receiptDelta) {
            if ($changedPath -cnotin @("docs/design/s10/s10-stage-checkpoints.json", "docs/execution/HANDOFF.md", "docs/execution/CURRENT_TASK.md")) {
                Add-ValidationError "K..C contains non-receipt path '$changedPath'."
            }
        }
        $receiptStage = Get-GitJson $ReceiptHead "docs/design/s10/s10-stage-checkpoints.json"
        $automatedRows = @($receiptStage.checkpoints | Where-Object stage -CEQ "AutomatedLab")
        if ($automatedRows.Count -ne 1) {
            Add-ValidationError "Receipt C must contain exactly one AutomatedLab checkpoint."
        }
        else {
            $automated = $automatedRows[0]
            Assert-Equal $automated.product_head $ProductHead "AutomatedLab receipt E"
            Assert-Equal $automated.evidence_head $EvidenceHead "AutomatedLab receipt K"
            Assert-Equal $automated.evidence_head_role "K" "AutomatedLab K role"
            $expectedReceiptDocuments = @{
                "accessibility_common_tasks" = "docs/design/s10/s10-accessibility-common-tasks.json"
                "token_coverage" = "docs/design/s10/s10-token-coverage.json"
                "visual_regression" = "docs/design/s10/s10-visual-regression.json"
                "release_evidence" = "docs/design/s10/authority/s10.4-automation-amendment-v1/manifest.json"
            }
            Assert-ExactSet @($automated.documents.document_type) @($expectedReceiptDocuments.Keys) "AutomatedLab receipt document types"
            foreach ($documentType in $expectedReceiptDocuments.Keys) {
                $records = @($automated.documents | Where-Object document_type -CEQ $documentType)
                if ($records.Count -ne 1) {
                    Add-ValidationError "AutomatedLab receipt requires one $documentType document."
                    continue
                }
                $record = $records[0]
                Assert-Equal $record.path $expectedReceiptDocuments[$documentType] "AutomatedLab $documentType path"
                Assert-Equal $record.blob_commit $EvidenceHead "AutomatedLab $documentType blob commit"
                Assert-Equal $record.sha256 (Get-GitBlobSha256 $EvidenceHead $record.path) "AutomatedLab $documentType hash"
            }
            foreach ($evidenceID in @("s10.4-required-shard-count-7", "s10.4-required-visual-cell-count-469", "s10.4-required-accessibility-row-count-42", "s10.4-deferred-shard-count-7", "s10.4-deferred-visual-cell-count-469", "s10.4-deferred-accessibility-row-count-42", "s10.4.current-seven-with-minimum-verification-deferred.v1", "s10.4.minimum-verification-deferred.v1")) {
                Assert-Contains @($automated.evidence_ids) $evidenceID "AutomatedLab receipt evidence"
            }
            foreach ($receipt in $visual.shard_receipts) {
                $runEvidenceID = "github-actions-run-$($receipt.run_id)-job-$($receipt.job_id)-artifact-$($receipt.artifact_id)"
                Assert-Contains @($automated.evidence_ids) $runEvidenceID "AutomatedLab shard evidence"
            }
        }
    }
}
}

if ($errors.Count -gt 0) {
    foreach ($validationError in $errors) { Write-Error $validationError }
    throw "S10.4 automation overlay validation failed with $($errors.Count) error(s)."
}

if ($LifecycleMode -ceq "AuthorityH") {
    Write-Host "PASS: S10.4 H413 AuthorityH: available 14 profiles/938 slots/84 rows; required 7 profiles/469 cells/42 rows; deferred 7 profiles/469 slots/42 rows and separate minimum core smoke. Native E bindings verified; no native completion or human approval claimed."
}
else {
    Write-Host "PASS: S10.4 H420 ($LifecycleMode): 7 required E receipts/469 evidenced and human-reviewed cells/42 closed automated rows; minimum verification DEFERRED (no functional PASS); 469 visual slots/42 automated rows explicitly DEFERRED; all 84 manual rows NOT_RUN. Available 14-profile catalog retained."
}
