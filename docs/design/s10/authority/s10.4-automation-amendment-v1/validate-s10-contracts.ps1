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

$manifest = Read-JsonFile $manifestPath
$visual = Read-JsonFile $visualPath
$accessibility = Read-JsonFile $accessibilityPath
$inventory = Read-JsonFile $inventoryPath
$token = Read-JsonFile $tokenPath
$stage = Read-JsonFile $stagePath
$activation = Read-JsonFile $activationPath
$shardContract = Read-JsonFile $shardContractPath

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
Assert-ExactSet @($manifest.product_delta_allowlist) $expectedProductDeltaAllowlist "S10.4 product delta allowlist"
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
foreach ($changedPath in $evidenceDelta) {
    if (-not (($evidenceDocumentPaths -ccontains $changedPath) -or $changedPath -ceq "docs/execution/CURRENT_TASK.md")) {
        Add-ValidationError "E..K contains non-evidence path '$changedPath'."
    }
}
foreach ($path in $evidenceDocumentPaths) {
    Assert-Equal (Get-GitBlobSha256 $EvidenceHead $path) (Get-Sha256 (Join-Path $RepositoryRoot $path)) "working document equals K blob $path"
}

# Bind each successful shard receipt and all 938 state-by-requirement candidate cells.
Assert-ExactSet @($visual.shard_receipts.shard_id) @($manifest.shards.shard_id) "visual shard receipt IDs"
Assert-Equal @($visual.shard_receipts).Count 14 "shard receipt count"
$receiptByShard = @{}
$bitriseReceiptCount = 0
$payloadFingerprints = [System.Collections.Generic.List[string]]::new()
$githubEquivalenceReceipts = if ($visual.PSObject.Properties.Name -ccontains "github_equivalence_receipts") { @($visual.github_equivalence_receipts) } else { @() }
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
foreach ($receipt in $visual.shard_receipts) {
    $receiptByShard[$receipt.shard_id] = $receipt
    $shard = @($manifest.shards | Where-Object shard_id -CEQ $receipt.shard_id)[0]
    Assert-Equal $receipt.requirement_id $shard.requirement_id "$($receipt.shard_id) receipt requirement"
    Assert-Equal $receipt.device_profile_id $shard.device_profile_id "$($receipt.shard_id) receipt profile"
    Assert-Equal $receipt.accessibility_feature $shard.accessibility_feature "$($receipt.shard_id) receipt feature"
    Assert-Equal $receipt.source_product_head $ProductHead "$($receipt.shard_id) receipt E"
    $provider = if ([string]::IsNullOrWhiteSpace([string]$receipt.runner_provider)) { "github_actions" } else { [string]$receipt.runner_provider }
    if ($provider -ceq "github_actions") {
        Assert-Equal $receipt.runner_label $activation.toolchain.runner_label "$($receipt.shard_id) GitHub runner label"
        Assert-Equal $receipt.runner_image $activation.toolchain.runner_image "$($receipt.shard_id) GitHub runner image"
    }
    elseif ($provider -ceq "bitrise_build_hub") {
        $bitriseReceiptCount++
        Assert-Contains $expectedBitriseShards $receipt.shard_id "$($receipt.shard_id) Bitrise eligibility"
        Assert-Equal $receipt.runner_label "bitrise-m4-pro" "$($receipt.shard_id) Bitrise runner label"
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
    Assert-Equal $receipt.xcode_version $activation.toolchain.xcode_version "$($receipt.shard_id) Xcode version"
    Assert-Equal $receipt.xcode_build $activation.toolchain.xcode_build "$($receipt.shard_id) Xcode build"
    Assert-Equal $receipt.sdk_name $activation.toolchain.sdk_name "$($receipt.shard_id) SDK"
    Assert-Equal $receipt.sdk_build $activation.toolchain.sdk_build "$($receipt.shard_id) SDK build"
    Assert-Equal $receipt.simulator_runtime $shard.simulator_runtime "$($receipt.shard_id) runtime"
    Assert-Equal $receipt.simulator_name $shard.simulator_name "$($receipt.shard_id) simulator"
    Assert-Equal $receipt.simulator_os_build $shard.os_build "$($receipt.shard_id) OS build"
    Assert-Equal $receipt.selector "FieldEvidenceAppUITests/S10_4AutomatedBrandLabUITests" "$($receipt.shard_id) selector"
    Assert-Equal $receipt.conclusion "success" "$($receipt.shard_id) conclusion"
    Assert-Equal $receipt.state_count 67 "$($receipt.shard_id) state count"
    Assert-Equal $receipt.accessibility_task_count 6 "$($receipt.shard_id) task count"
    Assert-Equal $receipt.state_set_sha256 $manifest.matrix_contract.state_set_sha256 "$($receipt.shard_id) state digest"
    if ($null -ne $receipt.build_payload) {
        $payload = $receipt.build_payload
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
    $receipt = $receiptByShard[$shard.shard_id]
    $receiptProvider = if ([string]::IsNullOrWhiteSpace([string]$receipt.runner_provider)) { "github_actions" } else { [string]$receipt.runner_provider }
    Assert-Equal $cell.baseline_id $baselineByState[$cell.screen_state_id] "$($cell.cell_id) baseline"
    Assert-Equal $cell.shard_id $shard.shard_id "$($cell.cell_id) shard"
    Assert-Equal $cell.source_product_head $ProductHead "$($cell.cell_id) E"
    Assert-Equal $cell.source_test $expectedSourceTest "$($cell.cell_id) source test"
    foreach ($field in @("device_profile_id", "os_build", "appearance", "contrast", "content_size_category", "locale_profile_id", "layout_direction", "differentiate_without_color", "reduce_motion", "reduce_transparency")) {
        Assert-Equal $cell.$field $shard.$field "$($cell.cell_id) $field"
    }
    foreach ($field in @("run_id", "job_id", "artifact_id", "artifact_name", "artifact_digest")) {
        Assert-Equal $cell.$field $receipt.$field "$($cell.cell_id) $field"
    }
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
        $receipt = $receiptByShard[$shard.shard_id]
        Assert-Equal $row.automation_shard_id $shard.shard_id "$tuple shard"
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
Assert-Equal $visualAggregate.all_shards_success $true "all shards success"
Assert-Equal $visualAggregate.human_review_complete $true "human review complete"
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
Assert-Equal $accessAggregate.all_automated_rows_closed ($automatedClosed -eq 84) "all automated rows closed"
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
            foreach ($evidenceID in @("s10.4-shard-count-14", "s10.4-visual-cell-count-938", "s10.4-accessibility-row-count-84")) {
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
    Write-Host "PASS: S10.4 automation overlay AuthorityH: 14 shards, 938 derived candidate cells, 84 derived accessibility rows, manual NOT_RUN preserved."
}
else {
    Write-Host "PASS: S10.4 automation overlay ($LifecycleMode): 14 receipts, 938 candidate cells, 84 closed automated accessibility rows, 84 manual NOT_RUN rows."
}
