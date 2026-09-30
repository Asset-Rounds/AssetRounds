#!/usr/bin/env python3
"""Materialize the explicit completed-file/report contract release.

The field/enum tables below are a reviewed wire description, not reflected
sample values or a source-regex generator. Swift custom encoders were inspected:
WorkspaceID/ReplicaID are keyed; MutationID/physical-episode/public-request IDs
are scalar; associated-value enums retain the actual keyed payload shapes;
ExactMeasurementV1 emits an explicit nullable uncertainty field.

This compiler publishes schema shape, not catalog authenticity, state-machine,
cross-field, privacy, hash, resource, source-capture or production admission.
Published V1 definitions are retained unchanged. New definitions are explicit.
Some arrays lack a local count predicate: their bound is a sound consequence of
the enforced 8,388,608-byte completed-file / rendered-OpenJSON canonical budget.
An n-element JSON array needs at least 2*n+1 bytes, so n <= (budget-1)//2.
Tighter source-defined local ceilings are retained. This is not a claim that a
constructor has that count limit or that JSON Schema checks total encoded size.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import importlib.util
import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any

sys.dont_write_bytecode = True
SOURCE_HEAD = "90304b1802296dca7a56f85ce96787f341bd8f03"
COMPLETED_TYPE_SOURCE = "FieldEvidenceApp/Domain/Activities/ActivityCompletedFileContractsV1.swift"
COMPLETED_TYPE_LF_SHA256 = "cb1ce4b63c954cbb1b38c2a52362c10c886700995904b7b38939b5bca2c31fd4"
MANIFEST_ID = "activity-completed-contract-manifest-v1"
FILE_ROOT = "activity-completed-file-v1"
REPORT_ROOT = "activity-completed-report-v1"
INT64_MIN = -(1 << 63)
INT64_MAX = (1 << 63) - 1
UINT64_MAX = (1 << 64) - 1
CANONICAL_BYTE_BUDGET = 8_388_608
ARRAY_WIRE_CEILING = (CANONICAL_BYTE_BUDGET - 1) // 2
PUBLISHED_PATH = "docs/design/v23/tooling/V23P03C06ContractManifestV1.json"
PUBLISHED_CANONICAL_SHA256 = "9590179fd1a6e1c90a5ba6c81c000940901e5629eb77a90880ef69d09600c1ad"

# These tables are explicit encoded fields. ? means omitted when nil; ! means
# required and nullable. New String fields preserve source Unicode; individual
# constructor normalization/control/trim checks remain semantic obligations.
SHAPES = json.loads(r'''{
  "ActivityCompletedFileV1": "family:ActivityCompletedFileFamilyV1 formatVersion:Int outputID:UUID snapshot:CompletedActivitySnapshotV2 capture:ActivityCompletionCaptureV1 installation:ActivityCompletedInstallationV1? punchReview:ActivityCompletedPunchV1? packageRelease:InspectionPackageReleaseV1 shopProfile:ShopReportProfileV1 manifest:ContractManifestV1 supplemental:ActivityCompletionSupplementalV1 completedPredecessor:ActivityCompletedPredecessorV1? unfinishedAmendmentPredecessor:ActivitySessionEnvelopeV2?",
  "ReportSemanticProjectionV1": "schemaVersion:Int projectionVersion:String snapshotID:String snapshotSHA256:SHA256 manifestSHA256:SHA256 profileBindingSHA256:SHA256 nodes:[ReportSemanticNodeV1] semanticSHA256:SHA256",
  "CompletedActivitySnapshotV2": "schemaVersion:Int payload:CompletedActivitySnapshotPayloadV2 snapshotSHA256:SHA256",
  "ActivityCompletionCaptureV1": "version:Int source:MutationPortableExpectedRevisionV1 predecessor:ActivitySessionEnvelopeV2 transitionHistory:[ActivityStateTransitionV2] completionTransition:ActivityStateTransitionV2 resultingActivityRevision:UInt64 capturedAt:Date generatedAt:Date",
  "ActivityCompletedInstallationV1": "sourceRelease:InstallationWorkflowDefinitionReleaseV1 release:InstallationWorkflowDefinitionReleaseV1 basisHistory:[InstallationBasisSnapshotV1] taskHistory:[InstallationTaskResultV1] asBuilt:InstallationAsBuiltSnapshotV1 placementSources:ActivityCompletionPlacementSourcesV1 closeout:InstallationCloseoutV1 planCapability:ActivityCompletedInstallationPlanV1 scanCapability:ActivityCompletedInstallationScanV1 findings:[FindingV1] sourceEnvelopes:[ActivitySessionEnvelopeV2] correctiveActionEvents:[CorrectiveActionEventV1] verifiedRechecks:[VerifiedRecheckV1]",
  "ActivityCompletedPunchV1": "sourceRelease:PunchReviewWorkflowDefinitionReleaseV1 release:PunchReviewWorkflowDefinitionReleaseV1 basisHistory:[PunchReviewBasisSnapshotV1] scopeDecisions:[PunchItemProjectionV1] closeout:PunchReviewCloseoutV1 planCapability:ActivityCompletedPunchPlanV1 findings:[FindingV1] sourceEnvelopes:[ActivitySessionEnvelopeV2] correctiveActionEvents:[CorrectiveActionEventV1] verifiedRechecks:[VerifiedRecheckV1] installation:ActivityCompletedInstallationAssociationV1?",
  "InspectionPackageReleaseV1": "schemaVersion:Int packageReleaseID:String packageID:String packageContentVersion:Int packageSHA256:SHA256 canonicalPackageBytes:Data workflowSHA256:SHA256 canonicalWorkflowBytes:Data state:InspectionPackageReleaseStateV1",
  "ShopReportProfileV1": "schemaVersion:Int persistentKind:String workspaceID:WorkspaceID profileID:UUID revision:UInt64 predecessor:ShopReportProfileReferenceV1? mutationID:MutationIDV1 activation:ShopReportProfileActivationV1 brand:ShopReportBrandV1 reportLayoutProfile:ReportLayoutProfileV1 exportProfile:ExportProfileV1 evidenceDetailProfile:EvidenceDetailCardProfileV1 sectionRegistry:ReportSectionRegistryV1 sectionRegistryID:String sectionRegistryVersion:Int sectionRegistrySHA256:SHA256 rendererVersion:String packaging:ShopOpenEvidencePackagingV1 recordedBy:ActorSnapshotV1 recordedAt:Date profileSHA256:SHA256",
  "ContractManifestV1": "schemaVersion:Int manifestID:String manifestVersion:Int persistentContractSchema:String codec:ContractCodecRuleV1 compatibility:ContractCompatibilityRuleV1 objects:[ContractObjectDefinitionV1] enums:[ContractEnumDefinitionV1] reportSectionRegistry:ReportSectionRegistryV1",
  "ActivityCompletionSupplementalV1": "accountability:CompletedAccountabilitySnapshotV1 authorityCriterion:CompletedAuthorityCriterionSnapshotV1? relationshipScopes:[ActivityCompletionRelationshipScopeV1] serviceHistory:ActivityCompletionServiceHistoryV1 evidence:ActivityCompletionEvidenceV1 explicitSelection:ActivityCompletionExplicitSelectionV1? queries:[ActivityCompletionQueryV1]",
  "ActivityCompletedPredecessorV1": "activityFrontier:ActivitySessionEnvelopeV2 snapshot:CompletedActivitySnapshotV2 owner:ActivityCompletedPredecessorOwnerV1 reason:String",
  "ActivitySessionEnvelopeV2": "schemaVersion:Int activityID:UUID workspaceID:WorkspaceID kind:ActivityKindV2 state:ActivityStateV2 reviewState:ActivityReviewStateV2 subjectID:UUID title:String readiness:[ActivityReadinessFacetV1] readinessPolicy:ActivityReadinessPolicyBindingV2? variations:[ActivityVariationV1] amendment:ActivityAmendmentLinkV1? currentBasisReference:ActivityBasisHeadReferenceV2? installationCloseout:InstallationCloseoutV1? punchReviewCloseout:PunchReviewCloseoutV1? completedSnapshotReference:CompletedActivitySnapshotV2CompatibilityReferenceV1? completedFileReference:ActivityCompletedFileReferenceV1? startedAt:Date? finalizedAt:Date? revision:UInt64 mutationID:MutationIDV1 predecessorEnvelopeSHA256:SHA256? envelopeSHA256:SHA256",
  "ReportSemanticNodeV1": "semanticID:String sectionID:String role:String label:String value:String outputReferenceID:String?",
  "CompletedActivitySnapshotPayloadV2": "schemaVersion:Int activity:CompletedActivitySnapshotPayloadV1 assetID:UUID locationComposition:CompletedLocationCompositionSnapshotV1",
  "MutationPortableExpectedRevisionV1": "workspaceID:WorkspaceID generationID:UUID workspaceRevision:UInt64 entityRevisions:[WorkspaceEntityRevisionV1]",
  "ActivityStateTransitionV2": "schemaVersion:Int transitionID:UUID workspaceID:WorkspaceID activityID:UUID kind:ActivityKindV2 fromState:ActivityStateV2 toState:ActivityStateV2 reason:String? actor:ActorSnapshotV1 occurredAt:Date revision:UInt64 mutationID:MutationIDV1 transitionSHA256:SHA256",
  "InstallationWorkflowDefinitionReleaseV1": "schemaVersion:Int releaseID:UUID workspaceID:WorkspaceID tasks:[InstallationTaskDefinitionV1] bundledRelease:ActivityBundledWorkflowReleaseV1 readinessPolicy:InstallationReadinessPolicyV1 revision:UInt64 mutationID:MutationIDV1 releaseSHA256:SHA256",
  "InstallationBasisSnapshotV1": "basisID:UUID workspaceID:WorkspaceID activityID:UUID subjectID:UUID workflowReleaseReference:ActivityWorkflowReleaseReferenceV2 source:ActivityBasisSourceV1 capturedAt:Date revision:UInt64 mutationID:MutationIDV1 predecessorBasisID:UUID? predecessorBasisSHA256:SHA256? basisSHA256:SHA256",
  "InstallationTaskResultV1": "resultID:UUID workspaceID:WorkspaceID activityID:UUID taskID:String outcome:InstallationTaskOutcomeV1 deferredReason:InstallationDeferredReasonV1? unableReason:InstallationUnableReasonV1? note:String? evidenceReferences:[ContentReferenceV1] revision:UInt64 mutationID:MutationIDV1 predecessorResultID:UUID? predecessorResultSHA256:SHA256? resultSHA256:SHA256",
  "InstallationAsBuiltSnapshotV1": "snapshotID:UUID workspaceID:WorkspaceID activityID:UUID basisReference:InstallationBasisReferenceV1 taskResultSHA256s:[SHA256] placementReferences:[InstallationPlacementReferenceV2] completion:InstallationCompletionDispositionV1 limitation:String? revision:UInt64 mutationID:MutationIDV1 snapshotSHA256:SHA256",
  "InstallationCloseoutV1": "completion:InstallationCompletionDispositionV1 asBuiltSnapshotSHA256:SHA256 openFindings:[PunchFindingLinkV1] limitation:String? closeoutSHA256:SHA256",
  "ActivityCompletedInstallationPlanV1": "disposition:InstallationOptionalCapabilityDispositionV1 planReference:InstallationPlanReferenceV1? noPlanFallback:NoPlanFallbackV1? availabilityReceipt:TypedAvailabilityAndFallbackReceiptV1?",
  "ActivityCompletedInstallationScanV1": "disposition:InstallationOptionalCapabilityDispositionV1 scanReceipt:InstallationScanEntryReceiptV1? manualFallback:ManualLookupFallbackV1? availabilityReceipt:TypedAvailabilityAndFallbackReceiptV1?",
  "FindingV1": "schemaVersion:Int findingID:String revision:Int severity:FindingSeverityBindingV1 categoryID:String subject:FindingSubjectV1 source:FindingSourceV1 summary:String",
  "CorrectiveActionEventV1": "schemaVersion:Int eventID:UUID actionID:UUID workspaceID:WorkspaceID source:ChangeRequestItemReferenceV1 policy:CorrectiveActionPolicyReferenceV1 priority:CorrectiveActionPriorityV1 state:CorrectiveActionStateV1 assignee:LocalActorReferenceV1? recorder:ActorSnapshotV1 due:CorrectiveActionDueCalculationV1 closureEvidence:[ReviewEvidenceReferenceV1] verifier:ActorSnapshotV1? reopenTrigger:CorrectiveActionReopenTriggerV1? reason:String occurredAt:Date recordedAt:Date predecessorEventID:UUID? revision:UInt64 mutationID:MutationIDV1 eventSHA256:SHA256",
  "VerifiedRecheckV1": "schemaVersion:Int recheckID:String findingID:String findingRevision:Int correctiveWorkID:String correctiveWorkRevision:Int priorRecheckID:String? evidenceRevisionIDs:[String] expectedRecheckRevision:Int resultingRecheckRevision:Int mutationID:String outcome:VerifiedRecheckOutcomeV1 verifierActorID:String verifierAuthority:String reason:String effectiveAt:String",
  "PunchReviewWorkflowDefinitionReleaseV1": "schemaVersion:Int releaseID:UUID workspaceID:WorkspaceID scope:[PunchReviewScopeItemV1] bundledRelease:ActivityBundledWorkflowReleaseV1 readinessPolicy:PunchReviewReadinessPolicyV1 revision:UInt64 mutationID:MutationIDV1 releaseSHA256:SHA256",
  "PunchReviewBasisSnapshotV1": "basisID:UUID workspaceID:WorkspaceID activityID:UUID subjectID:UUID workflowReleaseReference:ActivityWorkflowReleaseReferenceV2 source:ActivityBasisSourceV1 scopeLimitation:String capturedAt:Date revision:UInt64 mutationID:MutationIDV1 predecessorBasisID:UUID? predecessorBasisSHA256:SHA256? basisSHA256:SHA256",
  "PunchItemProjectionV1": "scopeItemID:String disposition:PunchReviewItemDispositionV1 findingLinks:[PunchFindingLinkV1] deferredReason:PunchReviewDeferredReasonV1? unableReason:PunchReviewUnableReasonV1?",
  "PunchReviewCloseoutV1": "completion:PunchReviewCompletionDispositionV1 basisSHA256:SHA256 scope:[PunchItemProjectionV1] scopeAndTimeLimitation:String closeoutSHA256:SHA256",
  "ActivityCompletedPunchPlanV1": "disposition:PunchReviewPlanDispositionV1 planReference:PunchPlanReferenceV1? noPlanFallback:NoPlanFallbackV1? externalReference:ActivityExternalReferenceV1? availabilityReceipt:TypedAvailabilityAndFallbackReceiptV1?",
  "ActivityCompletedInstallationAssociationV1": "envelope:ActivitySessionEnvelopeV2 asBuilt:InstallationAsBuiltSnapshotV1 snapshot:CompletedActivitySnapshotV2 fileReference:ActivityCompletedFileReferenceV1?",
  "ShopReportProfileReferenceV1": "profileID:UUID revision:UInt64 profileSHA256:SHA256",
  "ShopReportBrandV1": "shopDisplayName:String orderedBrandLines:[String] accentHexRGB:String? logo:OutputScopedContentReferenceV1?",
  "ReportLayoutProfileV1": "schemaVersion:Int profileID:String profileRelease:Int audience:ReportAudienceV1 detail:ReportDetailLevelV1 sectionIDs:[String] mediaLayout:ReportMediaLayoutV1 orientation:ReportOrientationV1 localeIdentifier:String unitsProfileID:String displayProfileID:String",
  "ExportProfileV1": "schemaVersion:Int exportProfileID:String exportProfileRelease:Int formats:[ReportProjectionFormatV1] packaging:ReportPackagingV1 privacyTransformID:String maximumMediaItems:Int maximumArchiveBytes:Int64",
  "EvidenceDetailCardProfileV1": "schemaVersion:Int profileID:String profileRelease:Int audience:ReportAudienceV1 outputScopeID:String privacyTransformID:String privacyTransformVersion:Int markupProfileID:String markupProfileVersion:Int localeIdentifier:String displayProfileID:String rendererVersion:String audiencePrivacyPolicy:AudiencePrivacyPolicyV1 includedFieldIDs:[String] limitationsText:String",
  "ReportSectionRegistryV1": "schemaVersion:Int registryID:String registryVersion:Int sections:[ReportSectionDefinitionV1]",
  "ActorSnapshotV1": "schemaVersion:Int snapshotID:UUID workspaceID:WorkspaceID actor:LocalActorReferenceV1 responsibility:ResponsibilityKindV1 displayNameAtTime:String capturedAt:Date snapshotSHA256:SHA256",
  "ContractCodecRuleV1": "codecVersion:Int canonicalJSON:String integerEncoding:String timeEncoding:String nullEncoding:String binaryEncoding:String stringNormalization:String formatAssertion:Bool",
  "ContractCompatibilityRuleV1": "minimumReaderVersion:Int maximumReaderVersion:Int unknownObjectFields:ContractUnknownFieldPolicyV1 publishedVersionsImmutable:Bool",
  "ContractObjectDefinitionV1": "typeID:String version:Int unknownFieldPolicy:ContractUnknownFieldPolicyV1 fields:[ContractFieldDefinitionV1]",
  "ContractEnumDefinitionV1": "typeID:String version:Int policy:ContractEnumPolicyV1 knownValues:[String] knownIntegerValues:[Int64]?",
  "CompletedAccountabilitySnapshotV1": "schemaVersion:Int workspaceID:WorkspaceID parties:[ServicePartyReferenceV1] roleEvents:[SitePartyRoleEventV1] actors:[ActorSnapshotV1] qualifications:[QualificationSnapshotV1] signoffs:[SignoffSnapshotV1] snapshotSHA256:SHA256",
  "CompletedAuthorityCriterionSnapshotV1": "schemaVersion:Int workspaceID:WorkspaceID aggregate:AuthorityCriterionAggregateV1 snapshotSHA256:SHA256",
  "ActivityCompletionRelationshipScopeV1": "scope:WorkSubjectScopeSnapshotV1 relationships:CompletedFunctionalRelationshipSnapshotV1",
  "ActivityCompletionServiceHistoryV1": "records:[ServiceRequestRecordV1] dispositions:[ServiceRequestDispositionEventV1] workLinks:[ServiceRequestWorkLinkEventV1] sourceWorkEnvelopes:[ActivitySessionEnvelopeV2] factSources:[ActivityCompletionServiceFactSourceV1]",
  "ActivityCompletionEvidenceV1": "selectedOriginals:[ContentReferenceV1] associationHistory:[EvidenceAssociationV1] sequenceHistory:[EvidenceSequenceV1] cards:[EvidenceDetailCardV1] reviewedMarkupPlans:[EvidenceReviewedMarkupPlanV1] privacyProjections:[PrivacyTransformReportProjectionV1] outputMedia:[ActivityCompletionMediaV1] omittedEvidenceIDs:[String] omissionLimitations:[String]",
  "ActivityCompletionExplicitSelectionV1": "activityID:UUID activityRevision:UInt64 activitySHA256:SHA256 selectedBy:ActorSnapshotV1 selectedAt:Date siteRoleEvents:[ActivityCompletionSelectedObjectV1] qualificationSnapshots:[ActivityCompletionSelectedObjectV1] signoffSnapshots:[ActivityCompletionSelectedObjectV1] workScopes:[WorkSubjectScopeSnapshotV1] derivedProvenance:[ActivityCompletionSelectedObjectV1] additionalServiceRecords:[ServiceRequestRevisionReferenceV1] additionalEvidence:[ContentReferenceV1]",
  "ActivityCompletionQueryV1": "family:ActivityCompletionSupplementalFamilyV1 disposition:ActivityCompletionQueryDispositionV1 sourceWorkspaceRevision:UInt64 rootIdentities:[String] capturedValueSHA256:SHA256",
  "ActivityCompletedPredecessorOwnerV1": "kind:ActivityCompletedPredecessorOwnerKindV1 fileVersion:Int outputID:UUID relativePath:String fileSHA256:SHA256",
  "ActivityReadinessFacetV1": "facetID:String kind:ActivityReadinessFacetKindV1 disposition:ActivityReadinessDispositionV1 reason:String?",
  "ActivityVariationV1": "variationID:UUID workspaceID:WorkspaceID revision:UInt64 kind:ActivityVariationKindV1 predecessorBasisSHA256:SHA256 successorBasisSHA256:SHA256 reason:String actor:ActorSnapshotV1 occurredAt:Date mutationID:MutationIDV1 variationSHA256:SHA256",
  "ActivityAmendmentLinkV1": "predecessorActivityID:UUID predecessorRevision:UInt64 predecessorSHA256:SHA256 reason:String",
  "CompletedActivitySnapshotV2CompatibilityReferenceV1": "workspaceID:WorkspaceID activityID:UUID sourceWorkspaceID:WorkspaceID sourceActivityID:UUID sourceActivityRevision:Int sourceSubjectID:UUID sourceCloseoutSHA256:SHA256 targetCloseoutSHA256:SHA256 snapshotID:String snapshotRevision:Int snapshotSHA256:SHA256",
  "ActivityCompletedFileReferenceV1": "schemaVersion:Int outputID:UUID fileFormat:ActivityCompletedFileFamilyV1 fileVersion:Int relativePath:String fileSHA256:SHA256",
  "CompletedActivitySnapshotPayloadV1": "schemaVersion:Int workspaceID:String snapshotID:String snapshotRevision:Int sourceActivityID:String sourceRevision:Int reportID:String packageReleaseID:String generatedAt:String completedAt:String supersedesSnapshotID:String? supersededSnapshotSHA256:SHA256? amendmentReason:String? profileBinding:FinalizedReportProfileBindingV1 serviceFacts:[CompletedServiceFactV1] evidenceCards:[EvidenceDetailCardV1] limitations:[String]",
  "CompletedLocationCompositionSnapshotV1": "schemaVersion:Int workspaceID:WorkspaceID assetID:UUID locationPath:LocationPathSnapshotV1 placementTips:[AssetPlacementTipBindingV1] compositionEdges:[AssetCompositionEdgeV1] frozenAtRevision:UInt64 snapshotSHA256:SHA256",
  "WorkspaceEntityRevisionV1": "identity:WorkspaceEntityIdentityV1 revision:UInt64",
  "InstallationTaskDefinitionV1": "taskID:String ordinal:Int title:String evidencePurposes:[InstallationEvidencePurposeV1]",
  "InstallationReadinessPolicyV1": "requiredFacets:[ActivityReadinessFacetKindV1]",
  "ActivityWorkflowReleaseReferenceV2": "bundledRelease:ActivityBundledWorkflowReleaseV1 sourceWorkspaceID:WorkspaceID sourceReleaseID:UUID sourceReleaseRevision:UInt64 sourceReleaseSHA256:SHA256 targetWorkspaceID:WorkspaceID targetReleaseID:UUID targetReleaseRevision:UInt64 targetReleaseSHA256:SHA256 packageID:String packageContentVersion:Int packageSHA256:SHA256 releaseCompatibilitySHA256:SHA256 referenceSHA256:SHA256",
  "ContentReferenceV1": "schemaVersion:Int workspaceID:String contentID:String byteLength:Int64 mediaType:String digests:ContentDigestSetV1 byteRole:ContentByteRoleV1 createdAt:String",
  "InstallationBasisReferenceV1": "workspaceID:WorkspaceID activityID:UUID basisID:UUID revision:UInt64 basisSHA256:SHA256",
  "PunchFindingLinkV1": "findingID:UUID findingRevision:Int findingSHA256:SHA256 sourceContext:FindingSourceContextV1 supportingRecords:[ActivitySupportingRecordReferenceV2]",
  "InstallationPlanReferenceV1": "workspaceID:WorkspaceID planID:UUID planVersion:UInt64 planSHA256:SHA256 measurementSubjectID:UUID measurementSubjectRevision:UInt64 measurementSubjectSHA256:SHA256",
  "NoPlanFallbackV1": "schemaVersion:Int manualSubjectSelectionRequired:Bool planRequired:Bool scanRequired:Bool limitation:String fallbackSHA256:SHA256",
  "TypedAvailabilityAndFallbackReceiptV1": "schemaVersion:Int candidateHead:String candidateTree:String providerID:String providerSliceDigest:SHA256 consumerID:String capabilityID:CapabilityIDV1 availabilityReason:FeatureAvailabilityReasonV1 mandatoryCoreComplete:Bool visibleFallback:ManualFallbackActionV1 persistenceDisposition:FallbackPersistenceDispositionV1 dataDisposition:FallbackDataDispositionV1 reentryTrigger:FallbackReentryTriggerV1 localizedVisibleStateKey:String localizedVisibleCopyKey:String localizedNextActionKey:String fallbackTestArtifactIDs:[String] evidenceArtifactIDs:[String] zeroUnsupportedPublicClaim:Bool",
  "InstallationScanEntryReceiptV1": "workspaceID:WorkspaceID previewSHA256:SHA256 assetID:UUID assetBinding:ScanToWorkAssetBindingV1 policy:ScanToWorkStartPolicyV1 roundMutationReceipt:RoundSessionMutationReceiptV1 receiptSHA256:SHA256",
  "ManualLookupFallbackV1": "workspaceID:WorkspaceID inputSHA256:SHA256 reason:ScanToWorkResolutionOutcomeV1 explicitEntryRequired:Bool automaticNetworkLookup:Bool fallbackSHA256:SHA256",
  "FindingSeverityBindingV1": "severityID:String severityScaleReleaseID:String severityScaleSHA256:SHA256",
  "FindingSubjectV1": "subjectKindID:String subjectID:String subjectRevision:Int",
  "FindingSourceV1": "kind:FindingSourceKindV1 sourceID:String sourceRevision:Int evidenceRevisionIDs:[String]",
  "ChangeRequestItemReferenceV1": "kind:ChangeRequestItemKindV1 itemID:String itemRevision:UInt64 itemSHA256:SHA256",
  "CorrectiveActionPolicyReferenceV1": "releaseID:UUID policyID:UUID revision:UInt64 sha256:SHA256",
  "LocalActorReferenceV1": "schemaVersion:Int actorReferenceID:UUID workspaceID:WorkspaceID partyID:UUID? displayName:String",
  "CorrectiveActionDueCalculationV1": "openedAt:Date timeZoneIdentifier:String? dueAt:Date? graceEndsAt:Date? resolvedUTCOffsetSeconds:Int? calculationSHA256:SHA256",
  "ReviewEvidenceReferenceV1": "kind:ReviewEvidenceKindV1 referenceID:String revision:UInt64 sha256:SHA256",
  "PunchReviewScopeItemV1": "scopeItemID:String ordinal:Int title:String",
  "PunchReviewReadinessPolicyV1": "requiredFacets:[ActivityReadinessFacetKindV1]",
  "PunchPlanReferenceV1": "workspaceID:WorkspaceID planID:UUID planVersion:UInt64 planSHA256:SHA256 measurementSubjectID:UUID measurementSubjectRevision:UInt64 measurementSubjectSHA256:SHA256",
  "ActivityExternalReferenceV1": "referenceID:String revision:UInt64 sha256:SHA256",
  "OutputScopedContentReferenceV1": "outputScopeID:String outputReferenceID:String workspaceBindingSHA256:SHA256 contentSHA256:SHA256 mediaType:String byteRole:ContentByteRoleV1",
  "AudiencePrivacyPolicyV1": "schemaVersion:Int policyID:String policyVersion:Int audience:ReportAudienceV1 prohibitedCanaries:[String] policySHA256:SHA256",
  "ReportSectionDefinitionV1": "sectionID:String version:Int required:Bool supportedFormats:[ReportProjectionFormatV1] privacyClass:ReportPrivacyClassV1 requiresHeading:Bool requiresTextAlternative:Bool order:Int",
  "ContractFieldDefinitionV1": "fieldID:String jsonName:String kind:ContractScalarKindV1 arrayElementKind:ContractScalarKindV1? required:Bool nullable:Bool referencedTypeID:String? minimumInteger:Int64? maximumInteger:Int64? minimumUnsignedInteger:UInt64? maximumUnsignedInteger:UInt64? maximumUTF8Bytes:Int? maximumItems:Int? ordered:Bool uniqueItems:Bool maximumKeyUTF8Bytes:Int?",
  "ServicePartyReferenceV1": "schemaVersion:Int partyID:UUID workspaceID:WorkspaceID kind:ServicePartyKindV1 displayName:String profileDescriptor:String? provenance:ServicePartyProvenanceV1 privacyClass:ServicePartyPrivacyClassV1 state:ServicePartyStateV1 effectiveAt:Date retiredAt:Date? revision:UInt64 mutationID:MutationIDV1 receiptSHA256:SHA256",
  "SitePartyRoleEventV1": "schemaVersion:Int eventID:UUID workspaceID:WorkspaceID siteID:UUID partyID:UUID role:SitePartyRoleV1 effectiveFrom:Date effectiveUntil:Date? source:SitePartyRoleSourceV1 supersedesEventID:UUID? revision:UInt64 mutationID:MutationIDV1 recordedAt:Date receiptSHA256:SHA256",
  "QualificationSnapshotV1": "schemaVersion:Int snapshotID:UUID workspaceID:WorkspaceID declaredScope:String issuerDisplay:String? credentialLocator:String? effectiveAt:Date? expiresAt:Date? provenance:QualificationProvenanceV1 capturedAt:Date snapshotSHA256:SHA256",
  "SignoffSnapshotV1": "schemaVersion:Int snapshotID:UUID workspaceID:WorkspaceID purpose:String subjectID:UUID subjectRevision:UInt64 disposition:SignoffDispositionV1 method:SignoffMethodV1 roleAssertion:SignoffRoleAssertionV1? qualification:QualificationSnapshotV1? externalEvidenceID:UUID? occurredAt:Date? recordedAt:Date supersedesSnapshotID:UUID? mutationID:MutationIDV1 snapshotSHA256:SHA256",
  "AuthorityCriterionAggregateV1": "sourceReleases:[AuthoritySourceReleaseV1] basisBindings:[RequirementBasisBindingV1] applicabilityContexts:[ApplicabilityContextSnapshotV1] assessmentScopes:[AssessmentScopeSnapshotV1] severityScaleReleases:[SeverityScaleReleaseV1] severityMappingReleases:[SeverityScaleMappingReleaseV1] classificationBindings:[FindingClassificationBindingV1] measurementProtocolReleases:[MeasurementProtocolReleaseV1] evaluatorDescriptors:[DerivedFactEvaluatorDescriptorV1] derivedFacts:[DerivedFactProvenanceV1]",
  "WorkSubjectScopeSnapshotV1": "schemaVersion:Int snapshotID:UUID workspaceID:WorkspaceID siteID:UUID subjects:[WorkSubjectReferenceV1] semanticBindings:[WorkSubjectSemanticBindingSnapshotV1] workspaceRevision:UInt64 recordedAt:Date snapshotSHA256:SHA256",
  "CompletedFunctionalRelationshipSnapshotV1": "schemaVersion:Int snapshotID:UUID workspaceID:WorkspaceID capturedAt:Date descriptorReleases:[FunctionalRelationshipTypeDescriptorV1] relationships:[AssetFunctionalRelationshipEventV1] frozenReferences:[FrozenFunctionalRelationshipReferenceV1] snapshotSHA256:SHA256",
  "ServiceRequestRecordV1": "schemaVersion:Int recordID:UUID workspaceID:WorkspaceID submissionPublicID:ServiceRequestSubmissionPublicIDV1? invitationPublicID:ServiceRequestInvitationPublicIDV1? source:ServiceRequestSourceKindV1 scope:ServiceRequestScopeSnapshotV1 body:ServiceRequestSubmissionBodyV1 mediaManifest:ServiceRequestMediaManifestV1 acceptedSourceBytes:CanonicalServiceRequestSourceBytesV1? capabilityAssessment:ServiceRequestCapabilityAssessmentV1 supersedes:ServiceRequestRevisionReferenceV1? revision:UInt64 mutationID:MutationIDV1 recordedAt:Date recordSHA256:SHA256",
  "ServiceRequestDispositionEventV1": "schemaVersion:Int eventID:UUID workspaceID:WorkspaceID request:ServiceRequestRevisionReferenceV1 disposition:ServiceRequestImportDispositionV1 resultingState:ServiceRequestStateV1 reason:String? duplicateRecord:ServiceRequestRevisionReferenceV1? predecessorEventID:UUID? predecessorEventSHA256:SHA256? revision:UInt64 mutationID:MutationIDV1 recordedAt:Date eventSHA256:SHA256",
  "ServiceRequestWorkLinkEventV1": "schemaVersion:Int eventID:UUID workspaceID:WorkspaceID request:ServiceRequestRevisionReferenceV1 target:WorkSubjectReferenceV1 choice:ServiceRequestWorkChoiceV1 canonicalWorkID:UUID canonicalWorkRevision:UInt64 canonicalWorkSHA256:SHA256 kind:ServiceRequestWorkLinkKindV1 reversesEventID:UUID? predecessorEventID:UUID? predecessorEventSHA256:SHA256? revision:UInt64 mutationID:MutationIDV1 recordedAt:Date eventSHA256:SHA256",
  "ActivityCompletionServiceFactSourceV1": "fact:CompletedServiceFactV1 request:ServiceRequestRevisionReferenceV1 dispositionEventIDs:[UUID] workLinkEventIDs:[UUID]",
  "EvidenceAssociationV1": "schemaVersion:Int associationEventID:String workspaceID:String evidenceID:String expectedEvidenceRevision:Int resultingEvidenceRevision:Int mutationID:String action:EvidenceAssociationActionV1 contentID:String? target:EvidenceAssociationTargetV1? previousContentID:String? previousTarget:EvidenceAssociationTargetV1? supersedesAssociationEventID:String? actorID:String reason:String effectiveAt:String",
  "EvidenceSequenceV1": "schemaVersion:Int sequenceID:UUID workspaceID:WorkspaceID target:EvidenceAssociationTargetV1 policy:EvidenceCurationPolicyV1 orderedItems:[EvidenceSequenceItemV1] predecessor:EvidenceSequenceReferenceV1? revision:UInt64 mutationID:MutationIDV1 sequenceSHA256:SHA256",
  "EvidenceDetailCardV1": "schemaVersion:Int cardID:String workspaceID:String evidenceID:String outputScopeID:String profileID:String profileSHA256:SHA256 profile:EvidenceDetailCardProfileV1 audience:ReportAudienceV1 privacyTransformID:String privacyTransformVersion:Int localeIdentifier:String displayProfileID:String rendererVersion:String audiencePrivacyPolicyID:String audiencePrivacyPolicyVersion:Int audiencePrivacyPolicySHA256:SHA256 audiencePrivacyPolicy:AudiencePrivacyPolicyV1 privacyTransformedSHA256:SHA256 reviewedMarkupID:String reviewedMarkupSHA256:SHA256 reviewedMarkup:ReviewedEvidenceMarkupV1 fields:[EvidenceDetailFieldV1] outputReferences:[OutputScopedContentReferenceV1] annotations:[String] referenceLabels:[String] limitationsText:String",
  "ActivityCompletionMediaV1": "reference:OutputScopedContentReferenceV1 byteLength:Int64 bytes:Data",
  "ActivityCompletionSelectedObjectV1": "recordID:UUID canonicalSHA256:SHA256",
  "ServiceRequestRevisionReferenceV1": "recordID:UUID revision:UInt64 recordSHA256:SHA256",
  "PunchReviewBasisReferenceV1": "workspaceID:WorkspaceID activityID:UUID basisID:UUID revision:UInt64 basisSHA256:SHA256",
  "FinalizedReportProfileBindingV1": "schemaVersion:Int workspaceID:String snapshotID:String outputScopeID:String reportProfileID:String reportProfileRelease:Int reportProfileSHA256:SHA256 exportProfileID:String exportProfileRelease:Int exportProfileSHA256:SHA256 sectionRegistryID:String sectionRegistryVersion:Int sectionRegistrySHA256:SHA256 contractManifestID:String contractManifestVersion:Int contractManifestSHA256:SHA256 sectionIDs:[String] audience:ReportAudienceV1 detail:ReportDetailLevelV1 privacyTransformID:String localeIdentifier:String unitsProfileID:String displayProfileID:String orientation:ReportOrientationV1 mediaLayout:ReportMediaLayoutV1 rendererVersion:String projectionVersion:String",
  "CompletedServiceFactV1": "factID:String kind:CompletedServiceFactKindV1 privacyClass:ReportPrivacyClassV1 label:String value:String effectiveAt:String?",
  "LocationPathSnapshotV1": "schemaVersion:Int siteID:UUID siteDisplay:String nodes:[LocationPathComponentV1] pathSHA256:SHA256",
  "AssetPlacementTipBindingV1": "assetID:UUID placement:AssetPlacementEventV1",
  "AssetCompositionEdgeV1": "schemaVersion:Int id:UUID workspaceID:WorkspaceID parentAssetID:UUID childAssetID:UUID relationship:AssetCompositionRelationshipV1 isActive:Bool revision:UInt64 edgeSHA256:SHA256",
  "WorkspaceEntityIdentityV1": "kind:WorkspaceEntityKindV1 id:UUID",
  "ContentDigestSetV1": "values:[ContentDigestV1]",
  "PlanPlacementReferenceV1": "placementID:UUID revision:UInt64 placementSHA256:SHA256",
  "AssetPoseEventReferenceV1": "eventID:UUID workspaceID:WorkspaceID assetID:UUID axisID:PoseAxisID revision:UInt64 eventSHA256:SHA256",
  "FindingSourceContextV1": "workspaceID:WorkspaceID activityID:UUID activityKind:ActivityKindV2 activityRevision:UInt64 activitySHA256:SHA256 taskOrScopeID:String?",
  "ActivitySupportingRecordReferenceV2": "kind:ActivitySupportingRecordKindV2 recordID:UUID revision:UInt64 recordSHA256:SHA256",
  "ScanToWorkAssetBindingV1": "workspaceID:WorkspaceID assetID:UUID siteID:UUID label:String assetRevision:UInt64 assetSHA256:SHA256 locator:AssetLocatorReferenceV1 readiness:ScanToWorkOfflineReadinessProofV1 qualifiedPose:AssetPoseEventReferenceV1? bindingSHA256:SHA256",
  "ScanToWorkStartPolicyV1": "workspaceID:WorkspaceID policyID:String revision:UInt64 policySHA256:SHA256 startAllowed:Bool evaluatedAt:Date evaluationSHA256:SHA256",
  "RoundSessionMutationReceiptV1": "mutationSHA256:SHA256 mutationReceiptSHA256:SHA256 sessionFrontier:RoundSessionReferenceV1 mutation:RoundSessionMutationV1 mutationReceipt:MutationReceiptV1",
  "SignoffRoleAssertionV1": "schemaVersion:Int claimedRole:String claimedRelationship:SitePartyRoleV1? actor:ActorSnapshotV1 disclosureRelease:SignoffIntentDisclosureReleaseV1",
  "AuthoritySourceReleaseV1": "schemaVersion:Int releaseID:UUID workspaceID:WorkspaceID sourceID:UUID sourceType:AuthoritySourceTypeV1 designation:String editionOrRevision:String publisherDisplay:String? publicationAt:Date? effectiveFrom:Date? effectiveUntil:Date? addenda:String? corrigenda:String? sourceURL:String? retrievedAt:Date sourceDigestSHA256:SHA256? licenseStorageDisposition:LicenseStorageDispositionV1 lawfulContentReference:ContentReferenceV1? contentLocator:ContentLocatorV1? supersedesReleaseID:UUID? retiredAt:Date? recordedAt:Date revision:UInt64 mutationID:MutationIDV1 releaseSHA256:SHA256",
  "RequirementBasisBindingV1": "schemaVersion:Int bindingID:UUID workspaceID:WorkspaceID basisKind:RequirementBasisKindV1 authorityReleaseID:UUID criterionID:String clauseLocator:String? selectedBy:ActorSnapshotV1 selectedAt:Date supersedesBindingID:UUID? revision:UInt64 mutationID:MutationIDV1 bindingSHA256:SHA256",
  "ApplicabilityContextSnapshotV1": "schemaVersion:Int snapshotID:UUID workspaceID:WorkspaceID siteID:UUID activityID:UUID workSubjectScope:WorkSubjectScopeSnapshotV1 packageReleases:[PackageReleaseIdentityV1] actor:ActorSnapshotV1 qualification:QualificationSnapshotV1? effectiveAt:Date basisBindings:[RequirementBasisBindingV1] disposition:ApplicabilityDispositionV1 dispositionReason:String? supersedesSnapshotID:UUID? recordedAt:Date revision:UInt64 mutationID:MutationIDV1 snapshotSHA256:SHA256",
  "AssessmentScopeSnapshotV1": "schemaVersion:Int snapshotID:UUID workspaceID:WorkspaceID applicabilityContextID:UUID workSubjectScope:WorkSubjectScopeSnapshotV1 includedCriterionIDs:[String] excludedCriterionReasons:[String:String] supersedesSnapshotID:UUID? recordedAt:Date revision:UInt64 mutationID:MutationIDV1 snapshotSHA256:SHA256",
  "SeverityScaleReleaseV1": "schemaVersion:Int releaseID:UUID workspaceID:WorkspaceID scaleID:UUID designation:String levels:[SeverityLevelDefinitionV1] supersedesReleaseID:UUID? recordedAt:Date revision:UInt64 mutationID:MutationIDV1 releaseSHA256:SHA256",
  "SeverityScaleMappingReleaseV1": "schemaVersion:Int releaseID:UUID workspaceID:WorkspaceID sourceScaleReleaseID:UUID destinationScaleReleaseID:UUID entries:[SeverityScaleMappingEntryV1] recordedAt:Date supersedesReleaseID:UUID? revision:UInt64 mutationID:MutationIDV1 releaseSHA256:SHA256",
  "FindingClassificationBindingV1": "schemaVersion:Int bindingID:UUID workspaceID:WorkspaceID findingID:UUID criterionID:String result:ScreeningCriterionResultV1 severityScaleReleaseID:UUID? severityLevelID:String? applicabilityContextID:UUID assessmentScopeID:UUID recordedAt:Date supersedesBindingID:UUID? revision:UInt64 mutationID:MutationIDV1 bindingSHA256:SHA256",
  "MeasurementProtocolReleaseV1": "schemaVersion:Int releaseID:UUID workspaceID:WorkspaceID protocolID:UUID designation:String dimension:MeasurementDimensionV1 normativeUnitID:String samplingPolicy:MeasurementSamplingPolicyV1 minimumSampleCount:Int maximumSampleCount:Int missingSamplePolicy:MeasurementMissingSamplePolicyV1 outlierPolicy:MeasurementOutlierPolicyV1 duplicatePolicy:MeasurementDuplicatePolicyV1 requiresUncertainty:Bool roundingPolicyVersion:String evaluatorDescriptorID:UUID supersedesReleaseID:UUID? recordedAt:Date revision:UInt64 mutationID:MutationIDV1 releaseSHA256:SHA256",
  "DerivedFactEvaluatorDescriptorV1": "schemaVersion:Int descriptorID:UUID workspaceID:WorkspaceID evaluatorID:String evaluatorVersion:String implementationSHA256:SHA256 kind:DerivedFactEvaluatorKindV1 inputDimension:MeasurementDimensionV1 outputDimension:MeasurementDimensionV1 supersedesDescriptorID:UUID? recordedAt:Date revision:UInt64 mutationID:MutationIDV1 descriptorSHA256:SHA256",
  "DerivedFactProvenanceV1": "schemaVersion:Int provenanceID:UUID workspaceID:WorkspaceID protocolReleaseID:UUID evaluatorDescriptorID:UUID inputs:[DerivedFactInputV1] result:ExactMeasurementV1? disposition:DerivedFactDispositionV1 uncertaintyCanonical:ExactDecimalV1? predecessorProvenanceID:UUID? recordedAt:Date revision:UInt64 mutationID:MutationIDV1 provenanceSHA256:SHA256",
  "WorkSubjectReferenceV1": "kind:WorkSubjectKindV1 subjectID:UUID revision:UInt64 ownerAssetID:UUID? functionalRelationship:FrozenFunctionalRelationshipReferenceV1?",
  "WorkSubjectSemanticBindingSnapshotV1": "assetID:UUID kindBindingEventID:UUID kindBindingRevision:UInt64 catalogRelease:AssetSemanticCatalogReleaseReferenceV1 semanticID:String workflowPackageReleases:[PackageReleaseIdentityV1]",
  "FunctionalRelationshipTypeDescriptorV1": "schemaVersion:Int descriptorReleaseID:UUID workspaceID:WorkspaceID packageRelease:PackageReleaseIdentityV1 semanticID:String sourceCatalogRelease:AssetSemanticCatalogReleaseReferenceV1 targetCatalogRelease:AssetSemanticCatalogReleaseReferenceV1 sourceSemanticIDs:[String] targetSemanticIDs:[String] requiredSourceCapabilityIDs:[AssetSemanticCapabilityIDV1] requiredTargetCapabilityIDs:[AssetSemanticCapabilityIDV1] direction:FunctionalRelationshipDirectionV1 symmetry:FunctionalRelationshipSymmetryV1 sourceCardinality:FunctionalRelationshipCardinalityV1 targetCardinality:FunctionalRelationshipCardinalityV1 selfEdgePolicy:FunctionalRelationshipSelfEdgePolicyV1 cyclePolicy:FunctionalRelationshipCyclePolicyV1 maximumTraversalDepth:Int maximumHardEdges:Int sitePolicy:FunctionalRelationshipSitePolicyV1 workspacePolicy:FunctionalRelationshipWorkspacePolicyV1 minimumCardinalityBoundaries:[FunctionalRelationshipReadinessBoundaryV1] displayNameLocalizationKey:String descriptionLocalizationKey:String? sourceRoleLocalizationKey:String targetRoleLocalizationKey:String releasedAt:Date supersedesDescriptorReleaseID:UUID? revision:UInt64 mutationID:MutationIDV1 descriptorSHA256:SHA256",
  "AssetFunctionalRelationshipEventV1": "schemaVersion:Int eventID:UUID relationshipID:UUID workspaceID:WorkspaceID action:AssetFunctionalRelationshipEventActionV1 sourceAssetID:UUID targetAssetID:UUID sourceAssetRevision:UInt64 targetAssetRevision:UInt64 descriptor:FunctionalRelationshipDescriptorReferenceV1 effectiveAt:Date recordedAt:Date actor:LocalActorReferenceV1 provenance:String predecessorEventID:UUID? expectedRelationshipRevision:UInt64 revision:UInt64 mutationID:MutationIDV1 eventSHA256:SHA256",
  "FrozenFunctionalRelationshipReferenceV1": "relationshipID:UUID relationshipRevision:UInt64 descriptorReleaseID:UUID descriptorReleaseRevision:UInt64 packageRelease:PackageReleaseIdentityV1 semanticCatalogRelease:AssetSemanticCatalogReleaseReferenceV1 semanticID:String",
  "ServiceRequestScopeSnapshotV1": "siteID:UUID siteExpectedRevision:UInt64 siteSemanticSHA256:SHA256 assets:[ServiceRequestAssetScopeSnapshotV1] scopeSHA256:SHA256",
  "ServiceRequestSubmissionBodyV1": "requestText:String statedDate:Date? urgency:ServiceRequestUrgencyAssertionV1 requester:ServiceRequestRequesterAssertionV1 contact:ServiceRequestContactAssertionV1 category:String?",
  "ServiceRequestMediaManifestV1": "entries:[ServiceRequestMediaEntryV1] totalByteCount:UInt64 manifestSHA256:SHA256",
  "CanonicalServiceRequestSourceBytesV1": "bytes:Data byteCount:Int sha256:SHA256",
  "ServiceRequestCapabilityAssessmentV1": "proofValidity:ServiceRequestProofValidityV1 importEligibility:ServiceRequestImportEligibilityV1",
  "EvidenceAssociationTargetV1": "workspaceID:String kind:EvidenceTargetKindV1 targetID:String targetRevision:Int",
  "EvidenceCurationPolicyV1": "schemaVersion:Int policyID:UUID workspaceID:WorkspaceID maximumSequenceItems:Int maximumCaptionBytes:Int maximumAccessibilityDescriptionBytes:Int",
  "EvidenceSequenceItemV1": "evidenceID:String contentID:String role:EvidenceRoleV1 caption:EvidenceReviewedCaptionV1 accessibilityDescription:EvidenceAccessibilityDescriptionV1? ordinal:Int target:EvidenceAssociationTargetV1 associationBinding:EvidenceAssociationBindingV1",
  "EvidenceSequenceReferenceV1": "sequenceID:UUID revision:UInt64 sequenceSHA256:SHA256",
  "ReviewedEvidenceMarkupV1": "markupID:String sourcePrivacyDigest:String orderedAnnotations:[String] orderedReferenceLabels:[String]",
  "EvidenceDetailFieldV1": "fieldID:String label:String value:String sensitivity:EvidenceDetailSensitivityV1",
  "LocationPathComponentV1": "nodeID:UUID kind:LocationKindV1 label:String shortCode:String? revision:UInt64",
  "AssetPlacementEventV1": "schemaVersion:Int id:UUID workspaceID:WorkspaceID assetID:UUID siteID:UUID locationNodeID:UUID? predecessorEventID:UUID? source:AssetPlacementSourceV1 physicalEpisodeID:PhysicalPlacementEpisodeIDV1 continuity:PhysicalContinuityDispositionV1 pathSnapshot:LocationPathSnapshotV1 mutationID:MutationIDV1 occurredAt:Date eventSHA256:SHA256",
  "ContentDigestV1": "algorithm:ContentDigestAlgorithmV1 hexadecimalValue:String",
  "PoseAxisID": "rawValue:String",
  "AssetLocatorReferenceV1": "locatorID:UUID revision:UInt64 locatorSHA256:SHA256",
  "ScanToWorkOfflineReadinessProofV1": "workspaceID:WorkspaceID session:RoundSessionReferenceV1 assetID:UUID manifestSHA256:SHA256 sourceSnapshotSHA256:SHA256 status:OfflineReadinessStatusV1 checkedAt:Date proofSHA256:SHA256",
  "RoundSessionReferenceV1": "workspaceID:WorkspaceID sessionID:UUID revision:UInt64 sessionSHA256:SHA256",
  "RoundSessionMutationV1": "workspaceID:WorkspaceID expectedRevision:UInt64 mutationID:MutationIDV1 session:RoundSessionV1",
  "MutationReceiptV1": "schemaVersion:Int identity:MutationReceiptIdentityV1 mutationID:MutationIDV1 envelopeSHA256:SHA256 commandBodySHA256:SHA256 expectedRevision:MutationPortableExpectedRevisionV1 resultingRevision:MutationPortableExpectedRevisionV1 postImages:[MutationPostImageV1] contentDependencyIDs:[String] resultSHA256:SHA256 sourceKind:MutationSourceKindV1 causationMutationID:MutationIDV1? correlationID:UUID? reversesMutationID:MutationIDV1? committedAt:Date",
  "SignoffIntentDisclosureReleaseV1": "schemaVersion:Int releaseID:String disclosureText:String statesLocalAssertionOnly:Bool disclaimsIdentityVerification:Bool disclaimsLegalSignature:Bool",
  "ContentLocatorV1": "schemaVersion:Int locatorID:String workspaceID:String contentID:String locatorRevision:Int contentDigest:ContentDigestV1 expectedByteLength:Int64",
  "PackageReleaseIdentityV1": "packageID:String schemaVersion:Int contentVersion:Int",
  "SeverityLevelDefinitionV1": "levelID:String localizedLabelKey:String descriptionKey:String",
  "SeverityScaleMappingEntryV1": "sourceLevelID:String destinationLevelID:String",
  "DerivedFactInputV1": "sampleID:UUID sampleOrdinal:Int state:DerivedFactSampleStateV1 measurement:ExactMeasurementV1?",
  "ExactMeasurementV1": "schemaVersion:Int enteredValue:ExactDecimalV1 enteredUnitID:String canonicalValue:ExactDecimalV1 canonicalUnitID:String dimension:MeasurementDimensionV1 precisionScale:Int uncertaintyCanonical:ExactDecimalV1! source:MeasurementSourceV1 captureMethodID:String conversionPolicyVersion:String roundingReceipt:ExactRoundingReceiptV1",
  "ExactDecimalV1": "mantissa:Int64 scale:Int",
  "AssetSemanticCatalogReleaseReferenceV1": "releaseID:UUID packageRelease:PackageReleaseIdentityV1 catalogSHA256:SHA256",
  "AssetSemanticCapabilityIDV1": "rawValue:String",
  "FunctionalRelationshipCardinalityV1": "minimum:Int maximum:Int",
  "FunctionalRelationshipDescriptorReferenceV1": "descriptorReleaseID:UUID revision:UInt64 descriptorSHA256:SHA256 packageRelease:PackageReleaseIdentityV1 semanticID:String",
  "ServiceRequestAssetScopeSnapshotV1": "assetID:UUID expectedRevision:UInt64 semanticSHA256:SHA256",
  "ServiceRequestRequesterAssertionV1": "displayName:String? organization:String?",
  "ServiceRequestContactAssertionV1": "value:String? wording:String",
  "ServiceRequestMediaEntryV1": "mediaID:String format:ServiceRequestMediaFormatV1 byteCount:UInt64 pixelWidth:Int pixelHeight:Int sha256:SHA256 orientationBaked:Bool metadataStripped:Bool provenance:ServiceRequestMediaProvenanceV1",
  "EvidenceReviewedCaptionV1": "text:String provenance:EvidenceReviewedTextProvenanceV1 reviewer:ActorSnapshotV1 reviewedAt:Date",
  "EvidenceAccessibilityDescriptionV1": "text:String provenance:EvidenceReviewedTextProvenanceV1 reviewer:ActorSnapshotV1 reviewedAt:Date",
  "EvidenceAssociationBindingV1": "associationEventID:String resultingEvidenceRevision:Int associationSHA256:SHA256",
  "RoundSessionV1": "schemaVersion:Int persistentKind:String workspaceID:WorkspaceID sessionID:UUID revision:UInt64 predecessor:RoundSessionReferenceV1? mutationID:MutationIDV1 state:RoundSessionStateV1 transition:RoundSessionTransitionV1 transitionItemID:UUID? items:[RoundItemV1] counts:RoundSessionCountsV1 recordedBy:ActorSnapshotV1 recordedAt:Date sessionSHA256:SHA256",
  "MutationReceiptIdentityV1": "workspaceID:WorkspaceID replicaID:ReplicaID localSequence:UInt64",
  "ExactRoundingReceiptV1": "schemaVersion:Int policy:String sourceNumerator:Int64 sourceDenominator:Int64 targetScale:Int truncatedMantissa:Int64 remainder:Int64 roundedMantissa:Int64 disposition:TiesToEvenRoundingDispositionV1",
  "RoundItemV1": "itemID:UUID order:Int selection:RoundAssetSelectionV1 requirement:RoundPackageContentRequirementV1 disposition:RoundItemDispositionV1 visit:RoundItemVisitV1? reason:RoundItemReasonV1? completion:RoundItemCompletionReferenceV1?",
  "RoundSessionCountsV1": "expected:Int visited:Int completed:Int inaccessible:Int skipped:Int deferred:Int undispositioned:Int",
  "RoundAssetSelectionV1": "assetID:UUID siteID:UUID labelAtSelection:String",
  "RoundPackageContentRequirementV1": "packageRelease:RoundPackageReleaseReferenceV1 requiredContent:[ContentReferenceV1] requirementSHA256:SHA256",
  "RoundItemVisitV1": "visitedAt:Date recordedBy:ActorSnapshotV1",
  "RoundItemCompletionReferenceV1": "completionID:UUID revision:UInt64 completionSHA256:SHA256",
  "RoundPackageReleaseReferenceV1": "packageReleaseID:String packageID:String packageContentVersion:Int packageSHA256:SHA256 workflowSHA256:SHA256",
  "WorkspaceID": "rawValue:UUID",
  "ReplicaID": "rawValue:UUID",
  "ActivityReadinessPolicyBindingV2": "tag:ActivityReadinessPolicyTagV2 installation:InstallationReadinessPolicyV1? punchReview:PunchReviewReadinessPolicyV1?",
  "ActivityBasisSourceV1": "noPlan:NoPlanFallbackV1? optionalPlan:ActivityExternalReferenceV1? externalLocal:ActivityExternalReferenceV1?",
  "ActivityBasisHeadReferenceV2": "installation:ActivityBasisHeadInstallationV2? punchReview:ActivityBasisHeadPunchReviewV2?",
  "ActivityBasisHeadInstallationV2": "_0:InstallationBasisReferenceV1",
  "ActivityBasisHeadPunchReviewV2": "_0:PunchReviewBasisReferenceV1",
  "InstallationPlacementReferenceV2": "plan:InstallationPlacementPlanV2? pose:InstallationPlacementPoseV2?",
  "InstallationPlacementPlanV2": "_0:PlanPlacementReferenceV1",
  "InstallationPlacementPoseV2": "_0:AssetPoseEventReferenceV1",
  "ServiceRequestWorkChoiceV1": "package:ServiceRequestWorkChoicePackageV1? activity:ServiceRequestWorkChoiceActivityV1?",
  "ServiceRequestWorkChoicePackageV1": "_0:PackageReleaseIdentityV1",
  "ServiceRequestWorkChoiceActivityV1": "activityID:UUID expectedRevision:UInt64 semanticSHA256:SHA256",
  "MutationPostImageV1": "importMappingProfile:MutationPostImagePayload1V1? bulkSession:MutationPostImagePayload1V1? bulkCommitReceipt:MutationPostImagePayload1V1? site:MutationPostImagePayload1V1? asset:MutationPostImagePayload1V1? locationNode:MutationPostImagePayload1V1? assetPlacementEvent:MutationPostImagePayload1V1? assetCompositionEdge:MutationPostImagePayload1V1? assetCompositionEvent:MutationPostImagePayload1V1? savedSmartView:MutationPostImagePayload1V1? serviceParty:MutationPostImagePayload1V1? sitePartyRoleEvent:MutationPostImagePayload1V1? actorSnapshot:MutationPostImagePayload1V1? qualificationSnapshot:MutationPostImagePayload1V1? signoffSnapshot:MutationPostImagePayload1V1? authoritySourceRelease:MutationPostImagePayload2V1? requirementBasisBinding:MutationPostImagePayload2V1? applicabilityContextSnapshot:MutationPostImagePayload2V1? assessmentScopeSnapshot:MutationPostImagePayload2V1? severityScaleRelease:MutationPostImagePayload2V1? findingClassificationBinding:MutationPostImagePayload2V1? measurementProtocolRelease:MutationPostImagePayload2V1? derivedFactEvaluatorDescriptor:MutationPostImagePayload2V1? derivedFactProvenance:MutationPostImagePayload2V1? functionalRelationshipTypeDescriptor:MutationPostImagePayload2V1? assetFunctionalRelationshipEvent:MutationPostImagePayload3V1? evidenceVisibility:MutationPostImagePayload2V1? claimEvidenceLink:MutationPostImagePayload2V1? assuranceManifest:MutationPostImagePayload2V1? attestation:MutationPostImagePayload2V1? inspectionReviewTransition:MutationPostImagePayload2V1? reviewDisposition:MutationPostImagePayload2V1? changeRequest:MutationPostImagePayload2V1? correctiveActionPolicy:MutationPostImagePayload2V1? correctiveActionEvent:MutationPostImagePayload2V1? workPacketManifest:MutationPostImagePayload2V1? workItemClaim:MutationPostImagePayload2V1? workLease:MutationPostImagePayload2V1? workRelease:MutationPostImagePayload2V1? workHandoff:MutationPostImagePayload2V1? fieldDraftCheckpoint:MutationPostImagePayload2V1? attachmentStagingItem:MutationPostImagePayload2V1? draftCommitSaga:MutationPostImagePayload2V1? draftContentReservation:MutationPostImagePayload2V1? draftCommitReceipt:MutationPostImagePayload2V1? draftDiscardReceipt:MutationPostImagePayload2V1? promotedPackageRelease:MutationPostImagePayload2V1? packageSandboxRun:MutationPostImagePayload2V1? packagePromotionReceipt:MutationPostImagePayload2V1? activePackageRegistryPointer:MutationPostImagePayload2V1? instrumentReference:MutationPostImagePayload2V1? calibrationStatusSnapshot:MutationPostImagePayload2V1? measurementCapture:MutationPostImagePayload2V1? measurementSeries:MutationPostImagePayload2V1? measurementQualityAssessment:MutationPostImagePayload2V1? privacyTransformPolicy:MutationPostImagePayload2V1? privacyRegion:MutationPostImagePayload2V1? privacyTransformManifest:MutationPostImagePayload2V1? privacyReviewReceipt:MutationPostImagePayload2V1? evidenceAssociationEvent:MutationPostImagePayload2V1? evidenceSequenceRevision:MutationPostImagePayload2V1? shopReportProfile:MutationPostImagePayload2V1? roundSession:MutationPostImagePayload2V1? evidenceQuality:MutationPostImagePayload4V1? fastSurveyInbox:MutationPostImagePayload4V1? reinspectionException:MutationPostImagePayload4V1? entityIdentityResolution:MutationPostImagePayload4V1? workspaceExperience:MutationPostImagePayload2V1? clientCapabilityProfile:MutationPostImagePayload2V1? clientCapabilityAdmissionDecision:MutationPostImagePayload2V1? packageLifecyclePolicy:MutationPostImagePayload2V1? packageLifecycleDisposition:MutationPostImagePayload2V1? fieldReferenceRelease:MutationPostImagePayload2V1? fieldReferenceBinding:MutationPostImagePayload2V1? accessibleDocumentAssessmentReceipt:MutationPostImagePayload2V1? surveyDefinitionIdentity:MutationPostImagePayload2V1? surveyDefinitionRelease:MutationPostImagePayload2V1? surveySession:MutationPostImagePayload2V1? factCapture:MutationPostImagePayload2V1? provisionalSubject:MutationPostImagePayload2V1? subjectPromotionReceipt:MutationPostImagePayload2V1? surveyPublicationSnapshot:MutationPostImagePayload2V1? assetLocator:MutationPostImagePayload2V1? locatorBindingReceipt:MutationPostImagePayload2V1? scheduleDefinitionRelease:MutationPostImagePayload2V1? occurrenceHistoryEvent:MutationPostImagePayload2V1? exceptionCalendarRelease:MutationPostImagePayload2V1? scheduleOverrideEvent:MutationPostImagePayload2V1? planDocument:MutationPostImagePayload2V1? planRevision:MutationPostImagePayload2V1? planPlacement:MutationPostImagePayload2V1? planRebaseReceipt:MutationPostImagePayload2V1? myDayPlan:MutationPostImagePayload2V1? myDayCarryoverReceipt:MutationPostImagePayload2V1? assetPoseEvent:MutationPostImagePayload2V1? spatialAnchorObservation:MutationPostImagePayload2V1? evidenceContext:MutationPostImagePayload2V1? pairedObservationLink:MutationPostImagePayload2V1? lightingSystem:MutationPostImagePayload2V1? lightingObservation:MutationPostImagePayload2V1? lightingIssue:MutationPostImagePayload2V1? lightingMeasurementPlan:MutationPostImagePayload2V1? lightingClaimState:MutationPostImagePayload2V1? lightingDayInventoryWorkflow:MutationPostImagePayload2V1? lightingNightWorkflow:MutationPostImagePayload2V1? temporalEvidenceClip:MutationPostImagePayload2V1? timecodedEvidenceAnchor:MutationPostImagePayload2V1? acceptedLabelGenerationSnapshot:MutationPostImagePayload2V1? serviceContactPoint:MutationPostImagePayload2V1? systemHandoffIntent:MutationPostImagePayload2V1? activitySessionEnvelope:MutationPostImagePayload2V1? activityStateTransition:MutationPostImagePayload2V1? installationTaskResult:MutationPostImagePayload2V1? installationAsBuiltSnapshot:MutationPostImagePayload2V1? punchReviewBasisSnapshot:MutationPostImagePayload2V1? workResourceEntry:MutationPostImagePayload2V1? serviceRequestRecord:MutationPostImagePayload2V1? serviceRequestDispositionEvent:MutationPostImagePayload2V1? serviceRequestWorkLinkEvent:MutationPostImagePayload2V1? assetServiceIncident:MutationPostImagePayload2V1? serviceImpactSegment:MutationPostImagePayload2V1? serviceCauseAssertion:MutationPostImagePayload2V1? serviceRemedyAssertion:MutationPostImagePayload2V1? serviceRepairInterval:MutationPostImagePayload2V1? serviceRestorationAssertion:MutationPostImagePayload2V1? qualifiedServiceExposure:MutationPostImagePayload2V1? partsStock:MutationPostImagePayload4V1? workflowRecord:MutationPostImagePayload1V1? evidenceFile:MutationPostImagePayload1V1? issue:MutationPostImagePayload1V1? packet:MutationPostImagePayload1V1? report:MutationPostImagePayload1V1? deletionLedgerEntry:MutationPostImagePayload1V1? tombstone:MutationPostImagePayload5V1?",
  "MutationPostImagePayload1V1": "id:UUID revision:UInt64 semanticSHA256:SHA256",
  "MutationPostImagePayload2V1": "id:UUID concurrencyIdentity:WorkspaceEntityIdentityV1 revision:UInt64 semanticSHA256:SHA256",
  "MutationPostImagePayload3V1": "id:UUID relationshipID:UUID concurrencyIdentity:WorkspaceEntityIdentityV1 revision:UInt64 semanticSHA256:SHA256",
  "MutationPostImagePayload4V1": "id:UUID kind:WorkspaceEntityKindV1 concurrencyIdentity:WorkspaceEntityIdentityV1 revision:UInt64 semanticSHA256:SHA256",
  "MutationPostImagePayload5V1": "identity:WorkspaceEntityIdentityV1 revision:UInt64 semanticSHA256:SHA256",
  "PlanDocumentV1": "schemaVersion:Int planDocumentID:UUID workspaceID:WorkspaceID stablePlanKey:String displayName:String state:PlanDocumentStateV1 supersedesDocumentSHA256:SHA256? revision:UInt64 mutationID:MutationIDV1 recordedAt:Date documentSHA256:SHA256",
  "PlanRevisionV1": "schemaVersion:Int planRevisionID:UUID workspaceID:WorkspaceID planDocument:PlanDocumentReferenceV1 contentBinding:PlanContentBindingV1 pages:[PlanPageReferenceV1] spatialFrames:[SpatialReferenceFrameV1] state:PlanRevisionStateV1 supersedesPlanRevisionID:UUID? supersedesRevisionSHA256:SHA256? revision:UInt64 mutationID:MutationIDV1 recordedBy:ActorSnapshotV1 recordedAt:Date revisionSHA256:SHA256",
  "PlanPlacementV1": "schemaVersion:Int placementID:UUID workspaceID:WorkspaceID subjectKind:PlanPlacementSubjectKindV1 subjectID:UUID planRevision:PlanRevisionReferenceV1 spatialFrameID:UUID x:NormalizedPlanCoordinateV1 y:NormalizedPlanCoordinateV1 assetLocatorBinding:PlanAssetLocatorBindingV1? disposition:PlanPlacementDispositionV1 supersedesPlacementSHA256:SHA256? revision:UInt64 mutationID:MutationIDV1 recordedAt:Date placementSHA256:SHA256",
  "AssetPoseEventV1": "schemaVersion:Int eventID:UUID workspaceID:WorkspaceID assetID:UUID axisDescriptor:PoseAxisDescriptorV1 placementEpisodeID:PhysicalPlacementEpisodeIDV1 placementEventID:UUID locationPathSnapshot:LocationPathSnapshotV1 pose:PlacementPoseV1 source:PoseCaptureSourceV1 rootObservationEventID:UUID rootObservedAt:Date predecessor:AssetPoseEventReferenceV1? revision:UInt64 mutationID:MutationIDV1 recordedBy:ActorSnapshotV1 occurredAt:Date recordedAt:Date eventSHA256:SHA256",
  "EvidenceReviewedMarkupPlanV1": "schemaVersion:Int markupID:String workspaceID:WorkspaceID source:ContentReferenceV1 privacyPolicy:PrivacyTransformPolicyV1 privacyManifest:PrivacyTransformManifestV1 privacyReview:PrivacyReviewReceiptV1 orderedAnnotations:[EvidenceAnnotationV1] reviewedMarkup:ReviewedEvidenceMarkupV1 planSHA256:SHA256",
  "PlanDocumentReferenceV1": "planDocumentID:UUID revision:UInt64 documentSHA256:SHA256",
  "PlanContentBindingV1": "contentID:String byteLength:Int64 mediaType:String contentSHA256:SHA256 locatorID:String locatorRevision:Int fieldReferenceReleaseID:UUID fieldReferenceReleaseRevision:UInt64 fieldReferenceReleaseSHA256:SHA256 fieldReferenceManifestSHA256:SHA256",
  "PlanPageReferenceV1": "pageID:UUID sourcePageOrdinal:Int presentedPageOrdinal:Int pixelWidth:Int pixelHeight:Int crop:PlanCropRectV1 rotation:PlanPageRotationV1 sourcePageSHA256:SHA256",
  "SpatialReferenceFrameV1": "frameID:UUID pageID:UUID coordinateConvention:String calibrationMicrometresPerNormalizedUnit:Int64? calibrationProvenanceSHA256:SHA256? frameSHA256:SHA256",
  "PlanRevisionReferenceV1": "planRevisionID:UUID planDocumentID:UUID revision:UInt64 revisionSHA256:SHA256",
  "NormalizedPlanCoordinateV1": "millionths:Int64",
  "PlanAssetLocatorBindingV1": "workspaceID:WorkspaceID locator:AssetLocatorReferenceV1 bindingReceiptID:UUID bindingReceiptRevision:UInt64 bindingReceiptSHA256:SHA256 assetID:UUID",
  "PoseAxisDescriptorV1": "schemaVersion:Int axisID:PoseAxisID localizedLabelKey:String semanticRole:PoseAxisSemanticRoleV1 requiredComponents:PoseRequiredComponentsV1 observationRequirement:PoseObservationRequirementV1 applicability:PoseAxisApplicabilityV1 descriptorVersion:UInt64 descriptorSHA256:SHA256",
  "PlacementPoseV1": "disposition:PoseObservationDispositionV1 referenceFrame:PoseReferenceFrameV1 azimuth:PoseAngleMilliDegreesV1? elevation:PoseAngleMilliDegreesV1? horizontalUncertainty:PoseUncertaintyV1? verticalUncertainty:PoseUncertaintyV1? notObservedReason:PoseNotObservedReasonV1?",
  "PlanCropRectV1": "minX:NormalizedPlanCoordinateV1 minY:NormalizedPlanCoordinateV1 maxX:NormalizedPlanCoordinateV1 maxY:NormalizedPlanCoordinateV1",
  "PoseAngleMilliDegreesV1": "kind:PoseAngleKindV1 milliDegrees:Int32",
  "PlanRelativePoseFrameBindingV1": "planRevision:PlanRevisionReferenceV1 pageID:UUID spatialFrameID:UUID acceptedTransformSHA256:SHA256",
  "PrivacyTransformPolicyV1": "schemaVersion:Int policyID:UUID workspaceID:WorkspaceID purpose:String audience:EvidenceAudienceV1 allowedTransformKinds:[PrivacyTransformKindV1] allowedReasons:[PrivacyTransformReasonV1] metadataSanitationRequired:Bool reviewRequired:Bool maximumAgeSeconds:UInt64? denyByDefault:Bool effectiveAt:Date supersedesPolicyID:UUID? revision:UInt64 mutationID:MutationIDV1 policySHA256:SHA256",
  "PrivacyTransformManifestV1": "schemaVersion:Int manifestID:UUID workspaceID:WorkspaceID original:ContentReferenceV1 sourceRevision:UInt64 sourceSHA256:SHA256 derivative:ContentReferenceV1 derivativeSHA256:SHA256 policyID:UUID policyRevision:UInt64 policySHA256:SHA256 audience:EvidenceAudienceV1 orderedRegions:[PrivacyRegionV1] overlapBehavior:PrivacyRegionOverlapBehaviorV1 rendererID:String rendererVersion:String metadataSanitation:PrivacyMetadataSanitationEvidenceV1 staleState:PrivacyTransformStaleStateV1 renderedAt:Date supersedesManifestID:UUID? revision:UInt64 mutationID:MutationIDV1 manifestSHA256:SHA256",
  "PrivacyReviewReceiptV1": "schemaVersion:Int receiptID:UUID workspaceID:WorkspaceID manifestID:UUID manifestRevision:UInt64 manifestSHA256:SHA256 derivativeContentID:String derivativeSHA256:SHA256 policyID:UUID policyRevision:UInt64 policySHA256:SHA256 audience:EvidenceAudienceV1 sourceContentID:String sourceRevision:UInt64 sourceSHA256:SHA256 reviewer:ActorSnapshotV1 decision:PrivacyReviewDecisionV1 rationale:String reviewedAt:Date supersedesReceiptID:UUID? revision:UInt64 mutationID:MutationIDV1 receiptSHA256:SHA256",
  "EvidenceAnnotationV1": "schemaVersion:Int annotationID:String action:EvidenceAnnotationActionV1 text:String supersedesAnnotationID:String?",
  "PrivacyRegionV1": "schemaVersion:Int regionID:UUID workspaceID:WorkspaceID sourceContentID:String sourceRevision:UInt64 sourceSHA256:SHA256 coordinateSpace:PrivacyCoordinateSpaceV1 orientation:PrivacyImageOrientationV1 pixelWidth:Int32? pixelHeight:Int32? coordinateScale:PrivacyCoordinateScaleV1 sourceBounds:PrivacyIntegerRectV1 bounds:PrivacyNormalizedRectV1 transformKind:PrivacyTransformKindV1 reason:PrivacyTransformReasonV1 author:ActorSnapshotV1 order:UInt32 authoredAt:Date revision:UInt64 mutationID:MutationIDV1 regionSHA256:SHA256",
  "PrivacyMetadataSanitationEvidenceV1": "sanitizerID:String sanitizerVersion:String result:PrivacyMetadataSanitationResultV1 retainedSourceMetadataKeys:[String]",
  "PrivacyCoordinateScaleV1": "numerator:UInt32 denominator:UInt32",
  "PrivacyIntegerRectV1": "x:Int32 y:Int32 width:Int32 height:Int32",
  "PrivacyNormalizedRectV1": "x:Int32 y:Int32 width:Int32 height:Int32",
  "ActivityCompletionPlacementSourcesV1": "planDocuments:[PlanDocumentV1] planRevisions:[PlanRevisionV1] planPlacements:[PlanPlacementV1] poseEvents:[AssetPoseEventV1] placementHistory:[AssetPlacementEventV1]",
  "PrivacyTransformReportProjectionV1": "schemaVersion:Int projectionVersion:String workspaceID:WorkspaceID manifestID:UUID reviewReceiptID:UUID policyID:UUID audience:EvidenceAudienceV1 derivativeContentID:String derivativeSHA256:SHA256 sourceRevision:UInt64 sourceSHA256:SHA256 policyRevision:UInt64 policySHA256:SHA256 reviewRevision:UInt64 reviewSHA256:SHA256 reviewDecision:PrivacyReviewDecisionV1 staleState:PrivacyTransformStaleStateV1 metadataSanitized:Bool redactionDeclared:Bool derivativeOnly:Bool originalReferenceExcluded:Bool transformKinds:[PrivacyTransformKindV1] regionCount:Int projectionSHA256:SHA256",
  "PoseReferenceFrameV1": "unknown:EmptyAssociatedPayloadV1? planRelative:PosePlanRelativePayloadV1? trueBearing:EmptyAssociatedPayloadV1? magneticBearing:EmptyAssociatedPayloadV1?",
  "PoseUncertaintyV1": "known:PoseKnownUncertaintyPayloadV1? unknown:EmptyAssociatedPayloadV1?",
  "PosePlanRelativePayloadV1": "_0:PlanRelativePoseFrameBindingV1",
  "PoseKnownUncertaintyPayloadV1": "_0:PoseAngleMilliDegreesV1",
  "EmptyAssociatedPayloadV1": ""
}''')

ENUM_VALUES = json.loads(r'''{
  "InspectionPackageReleaseStateV1": [
    "DRAFT",
    "PUBLISHED",
    "TESTED"
  ],
  "ShopReportProfileActivationV1": [
    "OFF",
    "ON"
  ],
  "ShopOpenEvidencePackagingV1": [
    "COMBINED_ARCHIVE",
    "SEPARATE_FILES"
  ],
  "ActivityStateV2": [
    "CANCELLED",
    "CHANGES_REQUESTED",
    "DEFERRED",
    "DRAFT",
    "FIELD_COMPLETE",
    "FINALIZED",
    "IN_PROGRESS",
    "PAUSED",
    "PREFLIGHT_REQUIRED",
    "READY",
    "READY_FOR_REVIEW",
    "SUPERSEDED",
    "UNABLE_TO_COMPLETE"
  ],
  "ActivityReviewStateV2": [
    "ACCEPTED_RECORDED_FACTS",
    "CHANGES_REQUESTED",
    "NOT_REQUESTED",
    "PENDING"
  ],
  "ActivityBundledWorkflowReleaseV1": [
    "BUNDLED_INSTALLATION_V1",
    "BUNDLED_PUNCH_REVIEW_V1"
  ],
  "InstallationTaskOutcomeV1": [
    "COMPLETED",
    "DEFERRED",
    "IN_PROGRESS",
    "NOT_APPLICABLE",
    "NOT_STARTED",
    "UNABLE"
  ],
  "InstallationDeferredReasonV1": [
    "ACCESS_UNAVAILABLE",
    "AWAITING_RECORDED_DECISION",
    "EQUIPMENT_UNAVAILABLE",
    "MATERIAL_UNAVAILABLE",
    "OTHER_RECORDED",
    "SITE_NOT_READY",
    "WEATHER"
  ],
  "InstallationUnableReasonV1": [
    "IRRECOVERABLE_ACCESS",
    "OTHER_RECORDED",
    "SUBJECT_MISMATCH",
    "UNSAFE_RECORDED_CONDITION",
    "UNSUPPORTED_INSTRUCTION"
  ],
  "InstallationCompletionDispositionV1": [
    "CANCELLED",
    "COMPLETED_AS_RECORDED",
    "COMPLETED_WITH_OPEN_ITEMS",
    "PARTIALLY_COMPLETED",
    "UNABLE_ATTEMPT_RECORDED"
  ],
  "InstallationOptionalCapabilityDispositionV1": [
    "AVAILABLE",
    "MANUAL_FALLBACK",
    "UNAVAILABLE"
  ],
  "CorrectiveActionPriorityV1": [
    "HIGH",
    "LOW",
    "NORMAL",
    "URGENT"
  ],
  "CorrectiveActionStateV1": [
    "AWAITING_VERIFICATION",
    "CLOSED",
    "IN_PROGRESS",
    "OPEN",
    "REOPENED",
    "SUPERSEDED"
  ],
  "CorrectiveActionReopenTriggerV1": [
    "FAILED_VERIFIED_RECHECK",
    "MANUAL_RECORDED_REASON",
    "NEW_EVIDENCE_DIGEST",
    "SUBJECT_AMENDED"
  ],
  "VerifiedRecheckOutcomeV1": [
    "FAILED",
    "INCONCLUSIVE",
    "PASSED"
  ],
  "PunchReviewItemDispositionV1": [
    "DEFERRED",
    "NOT_APPLICABLE",
    "NOT_REVIEWED",
    "REVIEWED_NO_ITEM_RECORDED",
    "REVIEWED_WITH_ITEMS",
    "UNABLE"
  ],
  "PunchReviewDeferredReasonV1": [
    "ACCESS_UNAVAILABLE",
    "AWAITING_RECORDED_DECISION",
    "OTHER_RECORDED",
    "SITE_NOT_READY",
    "WEATHER"
  ],
  "PunchReviewUnableReasonV1": [
    "IRRECOVERABLE_ACCESS",
    "OTHER_RECORDED",
    "SUBJECT_MISMATCH",
    "UNSAFE_RECORDED_CONDITION"
  ],
  "PunchReviewCompletionDispositionV1": [
    "CANCELLED",
    "COMPLETED_NO_PUNCH_ITEMS_RECORDED_IN_SCOPE",
    "COMPLETED_WITH_PUNCH_ITEMS_RECORDED",
    "PARTIALLY_REVIEWED",
    "UNABLE_ATTEMPT_RECORDED"
  ],
  "PunchReviewPlanDispositionV1": [
    "AVAILABLE",
    "EXTERNAL_LOCAL",
    "MANUAL_FALLBACK",
    "UNAVAILABLE"
  ],
  "ReportAudienceV1": [
    "CUSTOMER_SAFE",
    "INTERNAL"
  ],
  "ReportDetailLevelV1": [
    "COMPLETE",
    "SUMMARY"
  ],
  "ReportMediaLayoutV1": [
    "COMPACT_GRID",
    "FULL_WIDTH",
    "NONE",
    "STANDARD_GRID"
  ],
  "ReportOrientationV1": [
    "LANDSCAPE",
    "PORTRAIT"
  ],
  "ReportProjectionFormatV1": [
    "FORMULA_SAFE_CSV",
    "MANIFEST",
    "MEDIA",
    "OPEN_JSON",
    "PDF",
    "STRUCTURED_TEXT"
  ],
  "ReportPackagingV1": [
    "COMBINED",
    "SEPARATE_PER_WORK_ITEM"
  ],
  "ResponsibilityKindV1": [
    "ACKNOWLEDGED_BY",
    "APPROVED_BY",
    "ASSIGNED_TO",
    "OBSERVED_BY",
    "PERFORMED_BY",
    "RECORDED_BY",
    "REVIEWED_BY",
    "VERIFIED_BY",
    "WITNESSED_BY"
  ],
  "ContractUnknownFieldPolicyV1": [
    "PRESERVE",
    "REJECT"
  ],
  "ContractEnumPolicyV1": [
    "CLOSED",
    "PRESERVE_UNKNOWN"
  ],
  "ActivityCompletionSupplementalFamilyV1": [
    "AUTHORITY_CRITERION",
    "EVIDENCE",
    "FUNCTIONAL_RELATIONSHIPS",
    "OPTIONAL_ACCOUNTABILITY",
    "SERVICE_HISTORY"
  ],
  "ActivityCompletionQueryDispositionV1": [
    "CAPTURED",
    "CHECKED_NO_APPLICABLE_SOURCE"
  ],
  "ActivityCompletedPredecessorOwnerKindV1": [
    "COMPLETED_FILE",
    "LEGACY_V2"
  ],
  "ActivityReadinessFacetKindV1": [
    "ACCESS",
    "EQUIPMENT",
    "MATERIAL",
    "OTHER_RECORDED",
    "REFERENCE",
    "SITE",
    "SUBJECT",
    "WEATHER"
  ],
  "ActivityReadinessDispositionV1": [
    "BLOCKED",
    "DEFERRED",
    "NOT_APPLICABLE",
    "READY"
  ],
  "ActivityVariationKindV1": [
    "BASIS_CORRECTED",
    "OPTIONAL_PLAN_REFERENCE_CHANGED",
    "OTHER_RECORDED",
    "PHYSICAL_PLACEMENT_REFERENCE_CHANGED",
    "RECORDED_SCOPE_CHANGED"
  ],
  "InstallationEvidencePurposeV1": [
    "AS_BUILT_DETAIL",
    "AS_BUILT_OVERVIEW",
    "COMPLETION_CONTEXT",
    "MEASUREMENT_CONTEXT",
    "OPEN_EXCEPTION",
    "PLACEMENT_CONTEXT",
    "PRE_INSTALL_CONTEXT",
    "SUBJECT_IDENTITY",
    "TASK_EXECUTION"
  ],
  "ContentByteRoleV1": [
    "DERIVATIVE",
    "IMMUTABLE_ORIGINAL"
  ],
  "CapabilityIDV1": [
    "AUDIO_CAPTURE",
    "CAMERA",
    "DIAGNOSTICS",
    "ENCRYPTED_BACKUP",
    "FILES_AND_SHARE",
    "HAPTICS",
    "LOCATION",
    "MICROPHONE",
    "NOTIFICATIONS",
    "PHOTO_LIBRARY",
    "REMINDERS",
    "SCAN_OCR",
    "SPEECH_DICTATION",
    "VIDEO_CAPTURE"
  ],
  "FeatureAvailabilityReasonV1": [
    "AVAILABLE",
    "NOT_ENTITLED",
    "OFFLINE_CONTENT_MISSING",
    "PACKAGE_NOT_ENABLED",
    "PACKAGE_RETIRED",
    "PERMISSION_DENIED",
    "PERMISSION_LIMITED",
    "PERMISSION_NOT_DETERMINED",
    "PERMISSION_RESTRICTED",
    "RECOVERY_BLOCKED",
    "TEMPORARILY_UNAVAILABLE",
    "UNSUPPORTED_OS_OR_DEVICE",
    "WORKSPACE_POLICY_DISABLED"
  ],
  "ManualFallbackActionV1": [
    "CHOOSE_EXISTING_PHOTO",
    "IMPORT_FILE",
    "LEAVE_INCOMPLETE_AND_RESUME",
    "NO_FALLBACK",
    "OPEN_SYSTEM_SETTINGS",
    "SAVE_LOCALLY",
    "TYPE_MANUALLY"
  ],
  "FallbackPersistenceDispositionV1": [
    "DEVICE_LOCAL_ONLY",
    "NO_CANONICAL_EFFECT_UNTIL_ACCEPTANCE",
    "WORKSPACE_CANONICAL_AFTER_ACCEPTANCE"
  ],
  "FallbackDataDispositionV1": [
    "ACCEPTED_IMMUTABLE_CONTENT",
    "PRIOR_HISTORY_PRESERVED",
    "SCRATCH_DELETED_NO_CANONICAL_EFFECT"
  ],
  "FallbackReentryTriggerV1": [
    "CAPABILITY_STATE_CHANGED",
    "MANUAL_PATH_SELECTED",
    "PERMISSION_CHANGED",
    "USER_INITIATED_RETRY"
  ],
  "ScanToWorkResolutionOutcomeV1": [
    "ALREADY_IN_ROUND",
    "AMBIGUOUS",
    "DUPLICATE_IN_SELECTION",
    "FOREIGN",
    "NOT_FOUND",
    "NOT_OFFLINE_READY",
    "READY",
    "RETIRED_OR_REPLACED",
    "STALE"
  ],
  "FindingSourceKindV1": [
    "HUMAN_OBSERVATION",
    "IMPORTED_RECORD",
    "INSPECTION_OBSERVATION",
    "INSPECTION_RESPONSE"
  ],
  "ChangeRequestItemKindV1": [
    "CRITERION",
    "EVIDENCE",
    "FINDING",
    "FUNCTIONAL_RELATIONSHIP",
    "REVIEW"
  ],
  "ReviewEvidenceKindV1": [
    "CLAIM_EVIDENCE_LINK",
    "COMPLETED_ACTIVITY_SNAPSHOT",
    "EXTERNAL_EVIDENCE_REFERENCE",
    "FUNCTIONAL_RELATIONSHIP_SNAPSHOT",
    "REQUIREMENT_EVALUATION",
    "VERIFIED_RECHECK"
  ],
  "ReportPrivacyClassV1": [
    "AUDIENCE_SAFE",
    "INTERNAL_ONLY",
    "MANDATORY_PUBLIC_TRUTH"
  ],
  "ContractScalarKindV1": [
    "ARRAY",
    "BASE64_BYTES",
    "BOOLEAN",
    "ENUM",
    "INTEGER",
    "OBJECT",
    "PRESERVED_STRING",
    "REFERENCE_DATE_SECONDS",
    "SHA256",
    "STRING",
    "STRING_MAP",
    "UNSIGNED_INTEGER",
    "UTC_INSTANT"
  ],
  "ServicePartyKindV1": [
    "ORGANIZATION",
    "PERSON"
  ],
  "ServicePartyProvenanceV1": [
    "IMPORTED_EXTERNAL_EVIDENCE",
    "LOCALLY_RECORDED",
    "MIGRATED_BASELINE"
  ],
  "ServicePartyPrivacyClassV1": [
    "WORKSPACE_CUSTOMER_DATA"
  ],
  "ServicePartyStateV1": [
    "EFFECTIVE",
    "RETIRED"
  ],
  "SitePartyRoleV1": [
    "CLIENT",
    "CONTACT",
    "OPERATOR",
    "OWNER",
    "SERVICE_PROVIDER"
  ],
  "SitePartyRoleSourceV1": [
    "IMPORTED_EXTERNAL_EVIDENCE",
    "LOCALLY_RECORDED",
    "MIGRATED_BASELINE"
  ],
  "QualificationProvenanceV1": [
    "IMPORTED_EXTERNAL_EVIDENCE",
    "SELF_DECLARED"
  ],
  "SignoffDispositionV1": [
    "EXTERNAL_EVIDENCE_ATTACHED",
    "NOT_APPLICABLE",
    "NOT_RECORDED",
    "RECORDED_LOCAL_ASSERTION"
  ],
  "SignoffMethodV1": [
    "EXPLICIT_LOCAL_ACKNOWLEDGEMENT",
    "EXTERNAL_EVIDENCE_REFERENCE",
    "NO_ASSERTION",
    "TYPED_LOCAL_ASSERTION"
  ],
  "ServiceRequestSourceKindV1": [
    "EMAIL",
    "IN_PERSON",
    "OTHER",
    "PAPER",
    "PHONE",
    "PORTABLE_SUBMISSION",
    "TEXT"
  ],
  "ServiceRequestImportDispositionV1": [
    "ACCEPT_AND_LINK_DUPLICATE",
    "ACCEPT_AS_NEW",
    "DECLINE_WITH_REASON",
    "DISCARD_UNIMPORTED",
    "KEEP_QUARANTINED",
    "RECORD_HISTORY_ONLY"
  ],
  "ServiceRequestStateV1": [
    "CLOSED_NO_WORK",
    "DECLINED",
    "HANDLED_BY_LINKED_WORK",
    "OPEN_ACCEPTED",
    "OPEN_UNTRIAGED",
    "SUPERSEDED"
  ],
  "ServiceRequestWorkLinkKindV1": [
    "LINK",
    "UNLINK_REVERSAL"
  ],
  "EvidenceAssociationActionV1": [
    "ASSIGNED",
    "REASSIGNED",
    "REMOVED"
  ],
  "AssetCompositionRelationshipV1": [
    "COMPONENT_OF"
  ],
  "WorkspaceEntityKindV1": [
    "acceptedLabelGenerationSnapshot",
    "accessibleDocumentAssessmentReceipt",
    "activePackageRegistryPointer",
    "activitySessionEnvelope",
    "activityStateTransition",
    "actorSnapshot",
    "applicabilityContextSnapshot",
    "assessmentScopeSnapshot",
    "asset",
    "assetCompositionEdge",
    "assetCompositionEvent",
    "assetFunctionalRelationshipEvent",
    "assetLocator",
    "assetPlacementEvent",
    "assetPoseEvent",
    "assetServiceIncident",
    "assuranceManifest",
    "attachmentStagingItem",
    "attestation",
    "authoritySourceRelease",
    "bulkCommitReceipt",
    "bulkSession",
    "calibrationStatusSnapshot",
    "captureInboxItem",
    "capturePromotion",
    "changeRequest",
    "claimEvidenceLink",
    "clientCapabilityAdmissionDecision",
    "clientCapabilityProfile",
    "correctiveActionEvent",
    "correctiveActionPolicy",
    "deletionLedgerEntry",
    "derivedFactEvaluatorDescriptor",
    "derivedFactProvenance",
    "draftCommitReceipt",
    "draftCommitSaga",
    "draftContentReservation",
    "draftDiscardReceipt",
    "entityAliasLink",
    "entityConsolidationReceipt",
    "evidenceAssociationEvent",
    "evidenceContext",
    "evidenceFile",
    "evidenceQualityAssessment",
    "evidenceQualityRuleSet",
    "evidenceQualityWaiverEvent",
    "evidenceSequenceRevision",
    "evidenceVisibility",
    "exceptionCalendarRelease",
    "exceptionQueueAcknowledgement",
    "factCapture",
    "fieldDraftCheckpoint",
    "fieldReferenceBinding",
    "fieldReferenceRelease",
    "findingClassificationBinding",
    "functionalRelationshipTypeDescriptor",
    "importMappingProfile",
    "inspectionReviewTransition",
    "installationAsBuiltSnapshot",
    "installationTaskResult",
    "instrumentReference",
    "issue",
    "lightingClaimState",
    "lightingDayInventoryWorkflow",
    "lightingIssue",
    "lightingMeasurementPlan",
    "lightingNightWorkflow",
    "lightingObservation",
    "lightingSystem",
    "localPartDefinition",
    "locationNode",
    "locatorBindingReceipt",
    "measurementCapture",
    "measurementProtocolRelease",
    "measurementQualityAssessment",
    "measurementSeries",
    "myDayCarryoverReceipt",
    "myDayPlan",
    "occurrenceHistoryEvent",
    "packageLifecycleDisposition",
    "packageLifecyclePolicy",
    "packagePromotionReceipt",
    "packageSandboxRun",
    "packet",
    "pairedObservationLink",
    "planDocument",
    "planPlacement",
    "planRebaseReceipt",
    "planRevision",
    "practiceWorkspaceProvenance",
    "privacyRegion",
    "privacyReviewReceipt",
    "privacyTransformManifest",
    "privacyTransformPolicy",
    "promotedPackageRelease",
    "provisionalSubject",
    "punchReviewBasisSnapshot",
    "qualificationSnapshot",
    "qualifiedServiceExposure",
    "reinspectionPlan",
    "report",
    "requirementBasisBinding",
    "reviewDisposition",
    "roundSession",
    "savedSmartView",
    "scheduleDefinitionRelease",
    "scheduleOverrideEvent",
    "serviceCauseAssertion",
    "serviceContactPoint",
    "serviceImpactSegment",
    "serviceParty",
    "serviceRemedyAssertion",
    "serviceRepairInterval",
    "serviceRequestDispositionEvent",
    "serviceRequestRecord",
    "serviceRequestWorkLinkEvent",
    "serviceRestorationAssertion",
    "severityScaleRelease",
    "shopReportProfile",
    "signoffSnapshot",
    "site",
    "sitePartyRoleEvent",
    "snippet",
    "snippetInsertion",
    "spatialAnchorObservation",
    "stockAbandonment",
    "stockBalanceStream",
    "stockMovementEvent",
    "stockReturnReceipt",
    "stockStorageLocation",
    "stockUseReceipt",
    "stockUseReversalReceipt",
    "subjectPromotionReceipt",
    "surveyDefinitionIdentity",
    "surveyDefinitionRelease",
    "surveyPublicationSnapshot",
    "surveySession",
    "systemHandoffIntent",
    "temporalEvidenceClip",
    "timecodedEvidenceAnchor",
    "unchangedAttestation",
    "workHandoff",
    "workItemClaim",
    "workLease",
    "workPacketManifest",
    "workRelease",
    "workResourceEntry",
    "workflowRecord"
  ],
  "ActivitySupportingRecordKindV2": [
    "CORRECTIVE_ACTION",
    "OPERATIONAL_RECHECK"
  ],
  "AuthoritySourceTypeV1": [
    "ADOPTED_RULE",
    "CONTRACT_OR_INSURER",
    "GUIDANCE",
    "MANUFACTURER_INSTRUCTION",
    "OWNER_POLICY",
    "VOLUNTARY_STANDARD"
  ],
  "LicenseStorageDispositionV1": [
    "EXTERNAL_LOCATOR_ONLY",
    "LAWFUL_CONTENT_REFERENCE",
    "METADATA_AND_LOCATOR_ONLY",
    "NOT_STORED"
  ],
  "RequirementBasisKindV1": [
    "ADOPTED_REQUIREMENT",
    "CONTRACT_REQUIREMENT",
    "DECLARED_SCREENING_BASIS",
    "OWNER_POLICY"
  ],
  "ApplicabilityDispositionV1": [
    "APPLICABLE",
    "CONFLICT_REVIEW_REQUIRED",
    "NOT_APPLICABLE_WITH_REASON",
    "UNKNOWN",
    "UNSUPPORTED"
  ],
  "ScreeningCriterionResultV1": [
    "DOES_NOT_MEET",
    "INCONCLUSIVE",
    "MEETS_SCREENING_CRITERION",
    "NOT_EVALUATED"
  ],
  "MeasurementDimensionV1": [
    "DIMENSIONLESS",
    "DURATION",
    "ELECTRIC_CURRENT",
    "ELECTRIC_POTENTIAL",
    "ELECTRIC_RESISTANCE",
    "ILLUMINANCE",
    "LENGTH",
    "PRESSURE",
    "TEMPERATURE"
  ],
  "MeasurementSamplingPolicyV1": [
    "BOUNDED_SET",
    "ORDERED_SERIES",
    "SINGLE"
  ],
  "MeasurementMissingSamplePolicyV1": [
    "FAIL_CLOSED",
    "INCONCLUSIVE"
  ],
  "MeasurementOutlierPolicyV1": [
    "REJECT_EVALUATION",
    "RETAIN_ALL"
  ],
  "MeasurementDuplicatePolicyV1": [
    "REJECT",
    "RETAIN_DISTINCT_IDENTITIES"
  ],
  "DerivedFactEvaluatorKindV1": [
    "ARITHMETIC_MEAN_CANONICAL",
    "IDENTITY_CANONICAL",
    "RATIO_PERCENT"
  ],
  "DerivedFactDispositionV1": [
    "EVALUATED",
    "INCONCLUSIVE",
    "NOT_EVALUATED"
  ],
  "WorkSubjectKindV1": [
    "ASSET",
    "COMPOSITION_COMPONENT",
    "FUNCTIONAL_RELATIONSHIP",
    "LOCATION_NODE",
    "SITE"
  ],
  "FunctionalRelationshipDirectionV1": [
    "DIRECTED",
    "UNDIRECTED"
  ],
  "FunctionalRelationshipSymmetryV1": [
    "ASYMMETRIC",
    "SYMMETRIC"
  ],
  "FunctionalRelationshipSelfEdgePolicyV1": [
    "ALLOWED",
    "FORBIDDEN"
  ],
  "FunctionalRelationshipCyclePolicyV1": [
    "BOUNDED",
    "FORBIDDEN"
  ],
  "FunctionalRelationshipSitePolicyV1": [
    "CROSS_SITE_LOCAL_ALLOWED",
    "SAME_SITE_REQUIRED"
  ],
  "FunctionalRelationshipWorkspacePolicyV1": [
    "SAME_WORKSPACE_REQUIRED"
  ],
  "FunctionalRelationshipReadinessBoundaryV1": [
    "ATOMIC_CREATION_BUNDLE",
    "FINALIZATION",
    "READINESS"
  ],
  "AssetFunctionalRelationshipEventActionV1": [
    "ADDED",
    "ENDED",
    "SUPERSEDED"
  ],
  "ServiceRequestUrgencyAssertionV1": [
    "ROUTINE",
    "SOON",
    "UNSPECIFIED",
    "URGENT_SELF_ASSERTED"
  ],
  "ServiceRequestProofValidityV1": [
    "INVALID",
    "UNAVAILABLE",
    "VALID"
  ],
  "ServiceRequestImportEligibilityV1": [
    "CLONED_OR_FORKED",
    "ELIGIBLE",
    "INVITATION_TERMINAL",
    "STALE_SCOPE",
    "TARGET_DELETED",
    "TARGET_MOVED",
    "TARGET_RETIRED",
    "UNAVAILABLE"
  ],
  "EvidenceTargetKindV1": [
    "ASSET",
    "CORRECTIVE_WORK",
    "FINDING",
    "INSPECTION_NODE",
    "INSPECTION_RESPONSE",
    "WORK_RECORD"
  ],
  "EvidenceRoleV1": [
    "AFTER",
    "BEFORE",
    "CONTEXT",
    "DETAIL",
    "OTHER"
  ],
  "EvidenceDetailSensitivityV1": [
    "AUDIENCE_SAFE",
    "CAPABILITY_SECRET",
    "CONTACT_DATA",
    "DIAGNOSTIC",
    "DIRECT_COST",
    "LOCAL_IDENTIFIER",
    "ORIGINAL_MEDIA",
    "PRIVATE_NOTE"
  ],
  "LocationKindV1": [
    "AREA",
    "BUILDING",
    "CAMPUS",
    "EXTERIOR_AREA",
    "LEVEL",
    "OTHER",
    "ZONE"
  ],
  "AssetPlacementSourceV1": [
    "HIERARCHY_REBASE",
    "IMPORT",
    "MANUAL",
    "MIGRATED_BASELINE",
    "SEMANTIC_REVERSAL",
    "SURVEY_PROMOTION"
  ],
  "PhysicalContinuityDispositionV1": [
    "PHYSICAL_MOVE",
    "SAME_PHYSICAL_INSTALLATION",
    "UNKNOWN_REVIEW_REQUIRED"
  ],
  "ContentDigestAlgorithmV1": [
    "SHA256",
    "SHA512"
  ],
  "OfflineReadinessStatusV1": [
    "BLOCKED",
    "READY",
    "STALE",
    "WARNING"
  ],
  "MutationSourceKindV1": [
    "IMPORTED_HISTORY",
    "LOCAL_RECOVERY",
    "LOCAL_USER",
    "SEMANTIC_REVERSAL"
  ],
  "DerivedFactSampleStateV1": [
    "MISSING",
    "OUTLIER",
    "PRESENT"
  ],
  "MeasurementSourceV1": [
    "DERIVED",
    "IMPORTED",
    "INSTRUMENT_OBSERVED",
    "MANUAL_ENTRY"
  ],
  "ServiceRequestMediaFormatV1": [
    "HEIC",
    "JPEG",
    "PNG"
  ],
  "ServiceRequestMediaProvenanceV1": [
    "RECIPIENT_SUPPLIED_DERIVATIVE"
  ],
  "EvidenceReviewedTextProvenanceV1": [
    "IMPORTED_THEN_REVIEWED",
    "USER_AUTHORED"
  ],
  "RoundSessionStateV1": [
    "ACTIVE",
    "ARCHIVED",
    "COMPLETED",
    "DRAFT",
    "PAUSED"
  ],
  "RoundSessionTransitionV1": [
    "ARCHIVE",
    "CLOSE",
    "COMPLETE_ITEM",
    "CREATE",
    "DEFER_ITEM",
    "MARK_INACCESSIBLE",
    "PAUSE",
    "RESUME",
    "RETRY_ITEM",
    "REVISE_SELECTION",
    "SKIP_ITEM",
    "START",
    "VISIT_ITEM"
  ],
  "TiesToEvenRoundingDispositionV1": [
    "EXACT",
    "NEAREST_AWAY_FROM_ZERO",
    "NEAREST_TOWARD_ZERO",
    "TIE_EVEN_ADJUSTED",
    "TIE_EVEN_UNCHANGED"
  ],
  "RoundItemDispositionV1": [
    "COMPLETED",
    "DEFERRED",
    "INACCESSIBLE",
    "PENDING",
    "SKIPPED",
    "VISITED"
  ],
  "RoundItemReasonV1": [
    "ASSET_DELETED_DURING_SESSION",
    "ASSET_RETIRED_OR_REPLACED",
    "DUPLICATE_SELECTION",
    "EXPLICITLY_OUT_OF_SCOPE",
    "FOLLOW_UP_REQUIRED",
    "INTERRUPTION",
    "NOT_REQUIRED",
    "PERMISSION_UNAVAILABLE",
    "PHYSICAL_ACCESS_UNAVAILABLE",
    "PROTECTED_DATA_UNAVAILABLE",
    "REQUIRED_CONTENT_UNAVAILABLE",
    "REQUIRED_PACKAGE_UNAVAILABLE",
    "USER_DEFERRED"
  ],
  "ActivityKindV2": [
    "INSPECTION",
    "INSTALLATION",
    "OPERATIONAL_RECHECK",
    "PREVENTIVE_MAINTENANCE",
    "PUNCH_REVIEW",
    "REPAIR",
    "SURVEY"
  ],
  "CompletedServiceFactKindV1": [
    "SERVICE_HISTORY",
    "SERVICE_REQUEST",
    "SERVICE_STATUS"
  ],
  "ActivityReadinessPolicyTagV2": [
    "INSTALLATION",
    "PUNCH_REVIEW"
  ],
  "ActivityCompletedFileFamilyV1": [
    "ACTIVITY_COMPLETED_FILE_V1"
  ],
  "PlanDocumentStateV1": [
    "ACTIVE",
    "RETIRED"
  ],
  "PlanRevisionStateV1": [
    "DRAFT",
    "RELEASED",
    "WITHDRAWN"
  ],
  "PlanPlacementSubjectKindV1": [
    "ASSET",
    "OBSERVATION",
    "LOCATION"
  ],
  "PlanPlacementDispositionV1": [
    "ACCEPTED",
    "REVIEW_REQUIRED",
    "ORPHANED",
    "OUT_OF_BOUNDS"
  ],
  "PoseAxisSemanticRoleV1": [
    "ASSET_FORWARD_AXIS",
    "SIGN_FACE_NORMAL",
    "LIGHT_BEAM_CENTERLINE",
    "OTHER_DECLARED_AXIS"
  ],
  "PoseRequiredComponentsV1": [
    "AZIMUTH_ONLY",
    "AZIMUTH_AND_ELEVATION"
  ],
  "PoseObservationRequirementV1": [
    "REQUIRED_FOR_COMPLETION",
    "OPTIONAL"
  ],
  "PoseAxisApplicabilityV1": [
    "APPLICABLE",
    "NOT_APPLICABLE"
  ],
  "PoseObservationDispositionV1": [
    "OBSERVED",
    "NOT_OBSERVED"
  ],
  "PoseNotObservedReasonV1": [
    "NOT_YET_OBSERVED",
    "PHYSICAL_MOVE_REOBSERVATION_REQUIRED",
    "PLAN_FRAME_LOST_REOBSERVATION_REQUIRED",
    "OBSCURED_OR_UNSAFE",
    "SOURCE_UNAVAILABLE",
    "USER_DECLINED"
  ],
  "PoseAngleKindV1": [
    "AZIMUTH",
    "ELEVATION",
    "HORIZONTAL_UNCERTAINTY",
    "VERTICAL_UNCERTAINTY"
  ],
  "PoseCaptureSourceV1": [
    "MANUAL",
    "DEVICE_HEADING_PROPOSAL_ACCEPTED",
    "PLAN_GESTURE",
    "IMPORT",
    "SURVEY_PROMOTION",
    "PLAN_REBASE",
    "PLACEMENT_CARRY_FORWARD",
    "SEMANTIC_REVERSAL"
  ],
  "PrivacyTransformKindV1": [
    "SOLID_FILL",
    "PIXELATE",
    "BLUR"
  ],
  "PrivacyTransformReasonV1": [
    "PERSON",
    "IDENTIFYING_MARK",
    "VEHICLE_IDENTIFIER",
    "CONFIDENTIAL_INFORMATION",
    "UNRELATED_PRIVATE_DETAIL"
  ],
  "PrivacyRegionOverlapBehaviorV1": [
    "APPLY_IN_ASCENDING_ORDER"
  ],
  "PrivacyTransformStaleStateV1": [
    "CURRENT",
    "SOURCE_CHANGED",
    "POLICY_CHANGED",
    "EXPIRED"
  ],
  "PrivacyReviewDecisionV1": [
    "APPROVED",
    "REJECTED"
  ],
  "EvidenceAnnotationActionV1": [
    "ADD",
    "REMOVE"
  ],
  "PrivacyCoordinateSpaceV1": [
    "NORMALIZED_IMAGE_V1",
    "PIXEL_IMAGE_V1"
  ],
  "PrivacyImageOrientationV1": [
    "UP",
    "UP_MIRRORED",
    "DOWN",
    "DOWN_MIRRORED",
    "LEFT",
    "LEFT_MIRRORED",
    "RIGHT",
    "RIGHT_MIRRORED"
  ],
  "PrivacyMetadataSanitationResultV1": [
    "COMPLETE",
    "FAILED"
  ],
  "EvidenceAudienceV1": [
    "INTERNAL_REVIEW",
    "CUSTOMER_REPORT",
    "EXTERNAL_COLLABORATOR"
  ]
}''')

# Equality of encoded fields/custom encoders was checked before each reuse.
INTEGER_ENUM_VALUES = {"PlanPageRotationV1": [0, 90, 180, 270]}

PUBLISHED_OBJECT_REUSE = json.loads(r'''{
  "ReportSemanticNodeV1": "report-semantic-node-v1",
  "ReportLayoutProfileV1": "report-layout-profile-v1",
  "ExportProfileV1": "export-profile-v1",
  "EvidenceDetailCardProfileV1": "evidence-detail-card-profile-v1",
  "ReportSectionRegistryV1": "report-section-registry-v1",
  "ContractCompatibilityRuleV1": "contract-compatibility-rule-v1",
  "CompletedActivitySnapshotPayloadV1": "completed-activity-snapshot-payload-v1",
  "OutputScopedContentReferenceV1": "output-scoped-content-reference-v1",
  "AudiencePrivacyPolicyV1": "audience-privacy-policy-v1",
  "ReportSectionDefinitionV1": "report-section-definition-v1",
  "EvidenceDetailCardV1": "evidence-detail-card-v1",
  "FinalizedReportProfileBindingV1": "finalized-report-profile-binding-v1",
  "CompletedServiceFactV1": "completed-service-fact-v1",
  "ReviewedEvidenceMarkupV1": "reviewed-evidence-markup-v1",
  "EvidenceDetailFieldV1": "evidence-detail-field-v1"
}''')

TYPE_IDS = {
    "ContractManifestV1": "contract-manifest-v2",
    "ContractFieldDefinitionV1": "contract-field-definition-v2",
    "ContractObjectDefinitionV1": "contract-object-definition-v2",
    "ContractCodecRuleV1": "contract-codec-rule-v2",
    "ContractEnumDefinitionV1": "contract-enum-definition-v2",
    "ContractScalarKindV1": "contract-scalar-kind-v2",
    "ReportSemanticProjectionV1": REPORT_ROOT,
}
SINGLE_VALUE_TYPES = {
    "MutationIDV1": "UUID",
    "PhysicalPlacementEpisodeIDV1": "UUID",
    "ServiceRequestSubmissionPublicIDV1": "PublicRequestID",
    "ServiceRequestInvitationPublicIDV1": "PublicRequestID",
}
ENUM_POLICIES = {"ActivityKindV2": "PRESERVE_UNKNOWN"}

# Explicit local count predicates from the bound source files. No inferred
# uniqueness from an ID-keyed collection is substituted for full object equality.
ARRAY_LIMITS = {
    "ActivityCompletionPlacementSourcesV1.planDocuments": 1024,
    "ActivityCompletionPlacementSourcesV1.planRevisions": 1024,
    "ActivityCompletionPlacementSourcesV1.planPlacements": 1024,
    "ActivityCompletionPlacementSourcesV1.poseEvents": 1024,
    "ActivityCompletionPlacementSourcesV1.placementHistory": 1024,
    "ActivityCompletionEvidenceV1.reviewedMarkupPlans": 1024,
    "ActivityCompletionEvidenceV1.privacyProjections": 1024,
    "PlanRevisionV1.pages": 512,
    "PlanRevisionV1.spatialFrames": 512,
    "EvidenceReviewedMarkupPlanV1.orderedAnnotations": 64,
    "PrivacyTransformManifestV1.orderedRegions": 512,
    "PrivacyTransformPolicyV1.allowedTransformKinds": 3,
    "PrivacyTransformPolicyV1.allowedReasons": 5,
    "PrivacyTransformReportProjectionV1.transformKinds": 3,
    "ActivitySessionEnvelopeV2.readiness": 32,
    "ActivitySessionEnvelopeV2.variations": 1024,
    "InstallationWorkflowDefinitionReleaseV1.tasks": 512,
    "InstallationTaskResultV1.evidenceReferences": 1024,
    "PunchReviewWorkflowDefinitionReleaseV1.scope": 512,
    "PunchReviewCloseoutV1.scope": 512,
    "ShopReportBrandV1.orderedBrandLines": 8,
    "CompletedAccountabilitySnapshotV1.parties": 256,
    "CompletedAccountabilitySnapshotV1.roleEvents": 512,
    "CompletedAccountabilitySnapshotV1.actors": 512,
    "CompletedAccountabilitySnapshotV1.qualifications": 512,
    "CompletedAccountabilitySnapshotV1.signoffs": 512,
    "FindingSourceV1.evidenceRevisionIDs": 32,
    "VerifiedRecheckV1.evidenceRevisionIDs": 32,
    "TypedAvailabilityAndFallbackReceiptV1.fallbackTestArtifactIDs": 128,
    "TypedAvailabilityAndFallbackReceiptV1.evidenceArtifactIDs": 128,
    "WorkSubjectScopeSnapshotV1.subjects": 1024,
    "WorkSubjectScopeSnapshotV1.semanticBindings": 1024,
    "LocationPathSnapshotV1.nodes": 8,
    "ContentDigestSetV1.values": 2,
    "SeverityScaleReleaseV1.levels": 64,
    "SeverityScaleMappingReleaseV1.entries": 64,
    "WorkSubjectSemanticBindingSnapshotV1.workflowPackageReleases": 32,
    "FunctionalRelationshipTypeDescriptorV1.sourceSemanticIDs": 64,
    "FunctionalRelationshipTypeDescriptorV1.targetSemanticIDs": 64,
    "FunctionalRelationshipTypeDescriptorV1.requiredSourceCapabilityIDs": 64,
    "FunctionalRelationshipTypeDescriptorV1.requiredTargetCapabilityIDs": 64,
    "ServiceRequestScopeSnapshotV1.assets": 16,
    "ServiceRequestMediaManifestV1.entries": 16,
    "MutationReceiptV1.postImages": 1024,
    "MutationReceiptV1.contentDependencyIDs": 256,
    "RoundSessionV1.items": 512,
    "RoundPackageContentRequirementV1.requiredContent": 256,
    "ActivityCompletionCaptureV1.transitionHistory": 1024,
    "ActivityCompletedInstallationV1.basisHistory": 1024,
    "ActivityCompletedInstallationV1.taskHistory": 1024,
    "ActivityCompletedPunchV1.basisHistory": 1024,
    "ActivityCompletionQueryV1.rootIdentities": 1024,
    "EvidenceSequenceV1.orderedItems": 32,
    "ActivityCompletedInstallationV1.findings": 1024,
    "ActivityCompletedInstallationV1.sourceEnvelopes": 1024,
    "ActivityCompletedInstallationV1.correctiveActionEvents": 1024,
    "ActivityCompletedInstallationV1.verifiedRechecks": 1024,
    "ActivityCompletedPunchV1.findings": 1024,
    "ActivityCompletedPunchV1.sourceEnvelopes": 1024,
    "ActivityCompletedPunchV1.correctiveActionEvents": 1024,
    "ActivityCompletedPunchV1.verifiedRechecks": 1024,
    "ActivityCompletionExplicitSelectionV1.siteRoleEvents": 1024,
    "ActivityCompletionExplicitSelectionV1.qualificationSnapshots": 1024,
    "ActivityCompletionExplicitSelectionV1.signoffSnapshots": 1024,
    "ActivityCompletionExplicitSelectionV1.derivedProvenance": 1024,
    "ActivityCompletionExplicitSelectionV1.workScopes": 1024,
    "ActivityCompletionExplicitSelectionV1.additionalServiceRecords": 1024,
    "ActivityCompletionExplicitSelectionV1.additionalEvidence": 1024,
    "ActivityCompletionServiceHistoryV1.records": 1024,
    "ActivityCompletionServiceHistoryV1.dispositions": 1024,
    "ActivityCompletionServiceHistoryV1.workLinks": 1024,
    "ActivityCompletionServiceHistoryV1.sourceWorkEnvelopes": 1024,
    "ActivityCompletionServiceHistoryV1.factSources": 1024,
    "ActivityCompletionEvidenceV1.selectedOriginals": 1024,
    "ActivityCompletionEvidenceV1.associationHistory": 1024,
    "ActivityCompletionEvidenceV1.sequenceHistory": 1024,
    "ActivityCompletionEvidenceV1.cards": 1024,
    "ActivityCompletionEvidenceV1.outputMedia": 1024,
}

# Exact widths/limits already established by the constructors; the global byte
# ceiling remains a conservative bound for other preserved source text fields.
TEXT_LIMITS = {
    "PlanDocumentV1.stablePlanKey": 512,
    "PlanDocumentV1.displayName": 512,
    "PlanContentBindingV1.contentID": 512,
    "PlanContentBindingV1.locatorID": 512,
    "PlanContentBindingV1.mediaType": 512,
    "PoseAxisDescriptorV1.localizedLabelKey": 128,
    "PoseAxisID.rawValue": 128,
    "EvidenceAnnotationV1.text": 1024,
    "PrivacyTransformPolicyV1.purpose": 512,
    "PrivacyReviewReceiptV1.rationale": 512,
    "PrivacyRegionV1.sourceContentID": 512,
    "PrivacyMetadataSanitationEvidenceV1.sanitizerID": 512,
    "PrivacyMetadataSanitationEvidenceV1.sanitizerVersion": 512,
    "PrivacyTransformManifestV1.rendererID": 512,
    "PrivacyTransformManifestV1.rendererVersion": 512,
    "ReportSemanticProjectionV1.projectionVersion": 128,
    "ReportSemanticProjectionV1.snapshotID": 128,
    "ShopReportBrandV1.shopDisplayName": 512,
    "ShopReportBrandV1.accentHexRGB": 7,
    "ContentReferenceV1.workspaceID": 128,
    "ContentReferenceV1.contentID": 128,
    "ContentReferenceV1.mediaType": 127,
    "ContentReferenceV1.createdAt": 32,
    "ContentDigestV1.hexadecimalValue": 128,
    "EvidenceAssociationV1.effectiveAt": 32,
    "VerifiedRecheckV1.effectiveAt": 32,
    "VerifiedRecheckV1.reason": 1024,
    "VerifiedRecheckV1.verifierAuthority": 1024,
    "FindingV1.summary": 2048,
    "AssetSemanticCapabilityIDV1.rawValue": 120,
}

# Literal schema tags are source facts, not inferred from a type name.
SCHEMA_VERSIONS = json.loads(r'''{
  "PlanDocumentV1": 1,
  "PlanRevisionV1": 1,
  "PlanPlacementV1": 1,
  "AssetPoseEventV1": 1,
  "PoseAxisDescriptorV1": 1,
  "EvidenceReviewedMarkupPlanV1": 1,
  "EvidenceAnnotationV1": 1,
  "PrivacyTransformPolicyV1": 1,
  "PrivacyTransformManifestV1": 1,
  "PrivacyReviewReceiptV1": 1,
  "PrivacyRegionV1": 1,
  "PrivacyTransformReportProjectionV1": 1,
  "ReportSemanticProjectionV1": 1,
  "CompletedActivitySnapshotV2": 2,
  "InspectionPackageReleaseV1": 1,
  "ShopReportProfileV1": 1,
  "ContractManifestV1": 2,
  "CompletedActivitySnapshotPayloadV2": 2,
  "ActivityStateTransitionV2": 2,
  "InstallationWorkflowDefinitionReleaseV1": 1,
  "FindingV1": 1,
  "CorrectiveActionEventV1": 1,
  "VerifiedRecheckV1": 1,
  "PunchReviewWorkflowDefinitionReleaseV1": 1,
  "ReportLayoutProfileV1": 1,
  "ExportProfileV1": 1,
  "EvidenceDetailCardProfileV1": 1,
  "ReportSectionRegistryV1": 1,
  "ActorSnapshotV1": 1,
  "CompletedAccountabilitySnapshotV1": 1,
  "CompletedAuthorityCriterionSnapshotV1": 1,
  "ActivityCompletedFileReferenceV1": 1,
  "CompletedActivitySnapshotPayloadV1": 1,
  "CompletedLocationCompositionSnapshotV1": 1,
  "ContentReferenceV1": 1,
  "NoPlanFallbackV1": 1,
  "TypedAvailabilityAndFallbackReceiptV1": 1,
  "LocalActorReferenceV1": 1,
  "AudiencePrivacyPolicyV1": 1,
  "ServicePartyReferenceV1": 1,
  "SitePartyRoleEventV1": 1,
  "QualificationSnapshotV1": 1,
  "SignoffSnapshotV1": 1,
  "WorkSubjectScopeSnapshotV1": 1,
  "CompletedFunctionalRelationshipSnapshotV1": 1,
  "ServiceRequestRecordV1": 1,
  "ServiceRequestDispositionEventV1": 1,
  "ServiceRequestWorkLinkEventV1": 1,
  "EvidenceAssociationV1": 1,
  "EvidenceSequenceV1": 1,
  "EvidenceDetailCardV1": 1,
  "FinalizedReportProfileBindingV1": 1,
  "LocationPathSnapshotV1": 1,
  "AssetCompositionEdgeV1": 1,
  "SignoffRoleAssertionV1": 1,
  "AuthoritySourceReleaseV1": 1,
  "RequirementBasisBindingV1": 1,
  "ApplicabilityContextSnapshotV1": 1,
  "AssessmentScopeSnapshotV1": 1,
  "SeverityScaleReleaseV1": 1,
  "SeverityScaleMappingReleaseV1": 1,
  "FindingClassificationBindingV1": 1,
  "MeasurementProtocolReleaseV1": 1,
  "DerivedFactEvaluatorDescriptorV1": 1,
  "DerivedFactProvenanceV1": 1,
  "FunctionalRelationshipTypeDescriptorV1": 1,
  "AssetFunctionalRelationshipEventV1": 1,
  "EvidenceCurationPolicyV1": 1,
  "AssetPlacementEventV1": 1,
  "MutationReceiptV1": 1,
  "SignoffIntentDisclosureReleaseV1": 1,
  "ContentLocatorV1": 1,
  "ExactMeasurementV1": 1,
  "RoundSessionV1": 1,
  "ExactRoundingReceiptV1": 1
}''')
INTEGER_RANGES = {
    "NormalizedPlanCoordinateV1.millionths": (0, 1_000_000),
    "PlanPageReferenceV1.sourcePageOrdinal": (0, 511),
    "PlanPageReferenceV1.presentedPageOrdinal": (0, 511),
    "PlanPageReferenceV1.pixelWidth": (1, (1 << 31) - 1),
    "PlanPageReferenceV1.pixelHeight": (1, (1 << 31) - 1),
    "PlanContentBindingV1.byteLength": (1, INT64_MAX),
    "PlanContentBindingV1.locatorRevision": (0, INT64_MAX),
    "SpatialReferenceFrameV1.calibrationMicrometresPerNormalizedUnit": (1, INT64_MAX),
    "PoseAngleMilliDegreesV1.milliDegrees": (-90_000, 359_999),
    "PrivacyRegionV1.pixelWidth": (1, 16_384),
    "PrivacyRegionV1.pixelHeight": (1, 16_384),
    "PrivacyCoordinateScaleV1.numerator": (1, 16_384),
    "PrivacyCoordinateScaleV1.denominator": (1, 16_384),
    "PrivacyIntegerRectV1.x": (0, (1 << 31) - 1),
    "PrivacyIntegerRectV1.y": (0, (1 << 31) - 1),
    "PrivacyIntegerRectV1.width": (1, (1 << 31) - 1),
    "PrivacyIntegerRectV1.height": (1, (1 << 31) - 1),
    "PrivacyNormalizedRectV1.x": (0, 999_999),
    "PrivacyNormalizedRectV1.y": (0, 999_999),
    "PrivacyNormalizedRectV1.width": (1, 1_000_000),
    "PrivacyNormalizedRectV1.height": (1, 1_000_000),
    "PrivacyTransformReportProjectionV1.regionCount": (1, 512),
    "ActivitySessionEnvelopeV2.schemaVersion": (2, 3),
    "ActivityCompletedFileV1.formatVersion": (1, 1),
    "ActivityCompletionCaptureV1.version": (1, 1),
    "ActivityCompletedFileReferenceV1.fileVersion": (1, 1),
    "ActivityCompletedPredecessorOwnerV1.fileVersion": (1, 2),
    "ContractCodecRuleV1.codecVersion": (2, 2),
    "ActivityCompletionMediaV1.byteLength": (1, CANONICAL_BYTE_BUDGET),
    "ContentReferenceV1.byteLength": (0, INT64_MAX),
}

# Freeze source pins after root finalizes its remaining wire additions.
SOURCE_PINS = json.loads(r'''{
  "FieldEvidenceApp/Domain/Evidence/EvidenceCurationContractsV1.swift": {
    "gitBlob": "dc8315a06646cef4560c6083388b64af6776a956",
    "rawSHA256": "0f6c185b2555336cdfa3d9a15ae11ba79d8ea5422f522d327501040fd68e8ce0",
    "lfSHA256": "0f6c185b2555336cdfa3d9a15ae11ba79d8ea5422f522d327501040fd68e8ce0"
  },
  "FieldEvidenceApp/Domain/Content/PrivacyTransformContractsV1.swift": {
    "gitBlob": "c46e0c605149702485dfd9a21981a8b14b514ddd",
    "rawSHA256": "8e21f1f6e8fa3785e8047957d034f41c6296ea73a6521a916c13fcbb5be4df31",
    "lfSHA256": "8e21f1f6e8fa3785e8047957d034f41c6296ea73a6521a916c13fcbb5be4df31"
  },
  "FieldEvidenceApp/Domain/Reporting/EvidenceAssuranceContractsV1.swift": {
    "gitBlob": "3a4c0f2a6b2096f456d0a7ca608c26efb346c914",
    "rawSHA256": "760027bcc7d709f4ff1e581fe28debe3a689891df64c76d80d650ec420ae397a",
    "lfSHA256": "760027bcc7d709f4ff1e581fe28debe3a689891df64c76d80d650ec420ae397a"
  },
  "FieldEvidenceApp/Infrastructure/Reporting/DeterministicOpenJSONRendererV1.swift": {
    "gitBlob": "6612ed6f986d855184e7fd4d585ac98d1038079f",
    "rawSHA256": "ca06e93ed4f99a3e944033dda86f6719b6feee7c08b21c060bf7e4f775485215",
    "lfSHA256": "ca06e93ed4f99a3e944033dda86f6719b6feee7c08b21c060bf7e4f775485215"
  },
  "FieldEvidenceApp/Domain/InspectionKernel/CompletedActivitySnapshotContractsV1.swift": {
    "gitBlob": "ebe27917fef168cf05bddf2ed6b870bbbaac845c",
    "rawSHA256": "f4c038fcb1cb350695b3fd615dd603b67d33c347663d2e6eaa3aa2ce8620e321",
    "lfSHA256": "f4c038fcb1cb350695b3fd615dd603b67d33c347663d2e6eaa3aa2ce8620e321"
  },
  "FieldEvidenceApp/Domain/InspectionKernel/InspectionPackageReleaseV1.swift": {
    "gitBlob": "82d3ff831935dce93bb86b007544e5f794f0fccc",
    "rawSHA256": "6631262ac7afdf5ab1cfbf345299052fb8cee323d20323977dc1cb5cf57abd10",
    "lfSHA256": "6631262ac7afdf5ab1cfbf345299052fb8cee323d20323977dc1cb5cf57abd10"
  },
  "FieldEvidenceApp/Domain/Reporting/ShopReportProfileContractsV1.swift": {
    "gitBlob": "80ad73241e7a0c8275e6610f42548a3b6416c146",
    "rawSHA256": "a3c6036fdeef02933cdaa06010ed3d7da3387d34a5b67c8e4fe035f73f72a9fd",
    "lfSHA256": "a3c6036fdeef02933cdaa06010ed3d7da3387d34a5b67c8e4fe035f73f72a9fd"
  },
  "FieldEvidenceApp/Domain/Reporting/ContractManifestV1.swift": {
    "gitBlob": "257937f934e564f29e55b667f4c31edc343db09f",
    "rawSHA256": "dd339a00cb4b6148b523d40c6b6eb3ad6f98191cb8fbfb59fb116674552faa37",
    "lfSHA256": "dd339a00cb4b6148b523d40c6b6eb3ad6f98191cb8fbfb59fb116674552faa37"
  },
  "FieldEvidenceApp/Domain/Activities/ActivityContractFamiliesV2.swift": {
    "gitBlob": "8c59a1b3c8f9c6e468f54bd082f3f3b24db9b576",
    "rawSHA256": "6f16938f32e289e760a7be5150d8c721a0b122cdb9e67a0970a214db104d0e0f",
    "lfSHA256": "6f16938f32e289e760a7be5150d8c721a0b122cdb9e67a0970a214db104d0e0f"
  },
  "FieldEvidenceApp/Domain/Mutation/MutationEnvelopeV1.swift": {
    "gitBlob": "dbb77a2ab3f5b7f283588c60c1109cd886c67d2e",
    "rawSHA256": "1db1d3b671d04785d2dd23df1f315ed509e0e1d1bed56fb4c99f59eb5d356c6a",
    "lfSHA256": "1db1d3b671d04785d2dd23df1f315ed509e0e1d1bed56fb4c99f59eb5d356c6a"
  },
  "FieldEvidenceApp/Domain/InspectionKernel/FindingContractsV1.swift": {
    "gitBlob": "0d47f34b0b28c32984fa6dc2152063dd3601236e",
    "rawSHA256": "fad7e34b1ad278c6a0ba1c16dae6c36ecd871b977ea58642b906b80b218f354e",
    "lfSHA256": "fad7e34b1ad278c6a0ba1c16dae6c36ecd871b977ea58642b906b80b218f354e"
  },
  "FieldEvidenceApp/Domain/InspectionKernel/InspectionReviewContractsV1.swift": {
    "gitBlob": "33ba5617cea85603e1a1520be574504a93f664d3",
    "rawSHA256": "4931c075f15409a04457e87e429ebe594540680455138a76fb3834bab312170d",
    "lfSHA256": "4931c075f15409a04457e87e429ebe594540680455138a76fb3834bab312170d"
  },
  "FieldEvidenceApp/Domain/InspectionKernel/VerifiedRecheckContractsV1.swift": {
    "gitBlob": "25ee3c8f0c34f312ad704dc07e6a71b655c18cf4",
    "rawSHA256": "50ebf39c41f36fdc4bc1a462a02c9841b30ccc9090faae7d309e853230800faf",
    "lfSHA256": "50ebf39c41f36fdc4bc1a462a02c9841b30ccc9090faae7d309e853230800faf"
  },
  "FieldEvidenceApp/Domain/Reporting/ReportProjectionContractsV1.swift": {
    "gitBlob": "a36327aff2529fd5b5a85db6ae83a40773c3023d",
    "rawSHA256": "e732ee46de551c894c61457b73f50efe05ba20247bfb2d3ba1373a8f6a3c2bf8",
    "lfSHA256": "e732ee46de551c894c61457b73f50efe05ba20247bfb2d3ba1373a8f6a3c2bf8"
  },
  "FieldEvidenceApp/Domain/Reporting/EvidenceDetailCardContractsV1.swift": {
    "gitBlob": "4052874506faad6117241389590453bd10f81121",
    "rawSHA256": "825fa5024f4b0249368916a819394277aeb1185862542f782acb7362d4ad8354",
    "lfSHA256": "825fa5024f4b0249368916a819394277aeb1185862542f782acb7362d4ad8354"
  },
  "FieldEvidenceApp/Domain/Accountability/PartyAccountabilityContractsV1.swift": {
    "gitBlob": "313e0cd2291f87e5ebc18a7e8d1b0fc8b68da624",
    "rawSHA256": "7f4d599e5b33bc45f4d0a5e3fb95077b95fb7885061d51779ae4f0cd1bf036c0",
    "lfSHA256": "7f4d599e5b33bc45f4d0a5e3fb95077b95fb7885061d51779ae4f0cd1bf036c0"
  },
  "FieldEvidenceApp/Domain/Location/CompletedLocationCompositionSnapshotV1.swift": {
    "gitBlob": "8479ee90890e98f3a9a819c937c7f71cb0b244ac",
    "rawSHA256": "17b961b947de9a279532d24ca6320993b761ba342918452562c6124755d26b7a",
    "lfSHA256": "17b961b947de9a279532d24ca6320993b761ba342918452562c6124755d26b7a"
  },
  "FieldEvidenceApp/Domain/Mutation/WorkspaceMutationContractsV1.swift": {
    "gitBlob": "e6b3f701b99b620c90318eaf5c6c0e62dca85dda",
    "rawSHA256": "e412e7194717a47a101832ee007038b4f0fcf1a70672db52c8e64d2d5a1b996b",
    "lfSHA256": "e412e7194717a47a101832ee007038b4f0fcf1a70672db52c8e64d2d5a1b996b"
  },
  "FieldEvidenceApp/Domain/Content/ContentReferenceContractsV1.swift": {
    "gitBlob": "620b4aee089e87def37d9a9ed79f48724e186ee1",
    "rawSHA256": "18fa19a402f9568a640d283860117bc5ff46991681af4a902b1021df811a7fe5",
    "lfSHA256": "18fa19a402f9568a640d283860117bc5ff46991681af4a902b1021df811a7fe5"
  },
  "FieldEvidenceApp/Domain/InspectionKernel/MeasurementIntegrityContractsV1.swift": {
    "gitBlob": "6844e6ca01fcb7e7534db71fd817bd8373c644e2",
    "rawSHA256": "a007e396f2d7d0f1ffc1f82938180b4c3c1f4f3b2f07482aae33e63a1a844c5f",
    "lfSHA256": "a007e396f2d7d0f1ffc1f82938180b4c3c1f4f3b2f07482aae33e63a1a844c5f"
  },
  "FieldEvidenceApp/Domain/Capability/CapabilityAvailabilityContractsV1.swift": {
    "gitBlob": "c77b5a7f8f07bd6a4501ac1aafa8a16027c05f49",
    "rawSHA256": "9f5a02ea8b3886a9cce19513357071a8349999da388a0e9bbf50f39951ac8834",
    "lfSHA256": "9f5a02ea8b3886a9cce19513357071a8349999da388a0e9bbf50f39951ac8834"
  },
  "FieldEvidenceApp/Domain/Workflow/ScanToWorkContractsV1.swift": {
    "gitBlob": "6aef6f6ce7da464b68ede6de21619bb5185052e8",
    "rawSHA256": "2ea257cf6e965732f8269ee3e4e361f645f64822a80fe3b76a85d02ea4658da2",
    "lfSHA256": "2ea257cf6e965732f8269ee3e4e361f645f64822a80fe3b76a85d02ea4658da2"
  },
  "FieldEvidenceApp/Domain/InspectionKernel/AuthorityCriterionContractsV1.swift": {
    "gitBlob": "cb2b84c3dd11a268073a6b3817634a03da00c549",
    "rawSHA256": "cce394aac8c51900f19802337bc3ea1591e079383b1eb3db3b4bb488d75b77cd",
    "lfSHA256": "cce394aac8c51900f19802337bc3ea1591e079383b1eb3db3b4bb488d75b77cd"
  },
  "FieldEvidenceApp/Domain/AssetSemantics/AssetSemanticContractsV1.swift": {
    "gitBlob": "f62e8bd2eb31eb14de8ed38bc2722f2c218de7c3",
    "rawSHA256": "dafb6384564cc77f6648cbd881774bed4bf9d412614e520f23abf9d7c4f3e1ba",
    "lfSHA256": "dafb6384564cc77f6648cbd881774bed4bf9d412614e520f23abf9d7c4f3e1ba"
  },
  "FieldEvidenceApp/Domain/FunctionalRelationships/FunctionalRelationshipContractsV1.swift": {
    "gitBlob": "07e34a86787852ca0a068ac3db9e2d369263841e",
    "rawSHA256": "3750b74f263d661eb0e82085f21bd16b07c7a3f06b46a5f05fad87d7125c1dce",
    "lfSHA256": "3750b74f263d661eb0e82085f21bd16b07c7a3f06b46a5f05fad87d7125c1dce"
  },
  "FieldEvidenceApp/Domain/ServiceRequests/PortableServiceRequestContractsV1.swift": {
    "gitBlob": "ba80d21e291b6981d0558746160b22c43a3068ef",
    "rawSHA256": "eac9a7ecbfddb8bbeb28fc387c52dcbf16f1e9b23b58781c279666c1f642edc1",
    "lfSHA256": "eac9a7ecbfddb8bbeb28fc387c52dcbf16f1e9b23b58781c279666c1f642edc1"
  },
  "FieldEvidenceApp/Domain/Evidence/EvidenceAssociationContractsV1.swift": {
    "gitBlob": "6cb9704e971efb883626a30952994a5876ef3771",
    "rawSHA256": "5be8cc83f38c3a361c9df5c906515c2e3aa480d234890d237b1764f14b19f99a",
    "lfSHA256": "5be8cc83f38c3a361c9df5c906515c2e3aa480d234890d237b1764f14b19f99a"
  },
  "FieldEvidenceApp/Domain/Location/LocationHierarchyContractsV1.swift": {
    "gitBlob": "531418dc2150f25cf77273b706d0e036325ba017",
    "rawSHA256": "7554370dbff3602708963b7dd705c08acb78461acec8365bedcaf9a041edfb53",
    "lfSHA256": "7554370dbff3602708963b7dd705c08acb78461acec8365bedcaf9a041edfb53"
  },
  "FieldEvidenceApp/Domain/Location/AssetCompositionContractsV1.swift": {
    "gitBlob": "238dac6be79641a58421569b73cb1c1307513c75",
    "rawSHA256": "ea826f02fda61436fc1a47cdbf7137b92d309ffb38103e8f160984f89beae3e1",
    "lfSHA256": "ea826f02fda61436fc1a47cdbf7137b92d309ffb38103e8f160984f89beae3e1"
  },
  "FieldEvidenceApp/Domain/Plans/PlanContractsV1.swift": {
    "gitBlob": "0a3219dda3dd426ae0d2cc5fc80d920d760d51ec",
    "rawSHA256": "3e18be1059bfb273c91e3d70fd72eb06ca582446ed888eac4e4c10a39439a89c",
    "lfSHA256": "3e18be1059bfb273c91e3d70fd72eb06ca582446ed888eac4e4c10a39439a89c"
  },
  "FieldEvidenceApp/Domain/Pose/PlacementPoseContractsV1.swift": {
    "gitBlob": "d49a5af3f68f741b7aee6c15b518e5c03cde111b",
    "rawSHA256": "992d23dfcd7418b9f4288d87faef3eb7574144195af6e76552cad0c4e6869e82",
    "lfSHA256": "992d23dfcd7418b9f4288d87faef3eb7574144195af6e76552cad0c4e6869e82"
  },
  "FieldEvidenceApp/Domain/Mutation/MutationReceiptV1.swift": {
    "gitBlob": "59792353e33e40732d29759d0100e48fa10ac777",
    "rawSHA256": "6b5f641d1859c7e02436461d24fc458f059656b68b462971eb2c5926bf7d991b",
    "lfSHA256": "6b5f641d1859c7e02436461d24fc458f059656b68b462971eb2c5926bf7d991b"
  },
  "FieldEvidenceApp/Domain/Location/AssetPlacementContractsV1.swift": {
    "gitBlob": "7e0fd470efdaa38d283498f89f77f99a057e72b5",
    "rawSHA256": "9b9efa39765219af7312476fb3450410b5a963453e2d297d94540e93bd2ce7c5",
    "lfSHA256": "9b9efa39765219af7312476fb3450410b5a963453e2d297d94540e93bd2ce7c5"
  },
  "FieldEvidenceApp/Domain/AssetSemantics/AssetLocatorContractsV1.swift": {
    "gitBlob": "d9f57106dd47b64e1ac5384cce673168c498852a",
    "rawSHA256": "1a51283a70fc41fe678ae0aebee4f388a70b7c4304c0d037f1d3183b2cf94ce9",
    "lfSHA256": "1a51283a70fc41fe678ae0aebee4f388a70b7c4304c0d037f1d3183b2cf94ce9"
  },
  "FieldEvidenceApp/Domain/Rounds/RoundSessionContractsV1.swift": {
    "gitBlob": "8977d24e70c2c732c85f1b89fa1becaa6a8833a5",
    "rawSHA256": "b77c0d1ea6ff3ad9a2566adea536465fb96c8ae7405e735d4f7c5251cfc16596",
    "lfSHA256": "b77c0d1ea6ff3ad9a2566adea536465fb96c8ae7405e735d4f7c5251cfc16596"
  },
  "FieldEvidenceApp/Domain/Content/ContentLocatorManifestContractsV1.swift": {
    "gitBlob": "79da5f2b30aa1e3dfd3e286230f3eb3d0863b31b",
    "rawSHA256": "65b90192c8f123c3b7dfc8edaa0652844b0e602694ae0c87756fee32b6504bbb",
    "lfSHA256": "65b90192c8f123c3b7dfc8edaa0652844b0e602694ae0c87756fee32b6504bbb"
  },
  "FieldEvidenceApp/Domain/InspectionKernel/ExactMeasurementSemanticsV1.swift": {
    "gitBlob": "f14cae32c41694fc944713ea41ffd066402d46bb",
    "rawSHA256": "edf177f94ae31981cb4461cf368e103b8d091be59206a7b216e2984c14dafd9c",
    "lfSHA256": "edf177f94ae31981cb4461cf368e103b8d091be59206a7b216e2984c14dafd9c"
  },
  "FieldEvidenceApp/Domain/OfflineReadiness/OfflineReadinessManifestContractsV1.swift": {
    "gitBlob": "1e98c09481e564459ab34664e1f2c968a95ca723",
    "rawSHA256": "9b3b4952a7dbda0931a1d83be2c2fbf19ab598f7ae1af3fd3c8071a1d8a5da42",
    "lfSHA256": "9b3b4952a7dbda0931a1d83be2c2fbf19ab598f7ae1af3fd3c8071a1d8a5da42"
  }
}''')


def repository_root() -> Path:
    for parent in Path(__file__).resolve().parents:
        if (parent / "Scripts/v23/p03_c06_contracts.py").is_file():
            return parent
    raise ValueError("repository root is unavailable")


def canonical(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True,
                      separators=(",", ":"), allow_nan=False).encode("utf-8")


def kebab(value: str) -> str:
    value = re.sub(r"(.)([A-Z][a-z]+)", r"\1-\2", value)
    return re.sub(r"([a-z0-9])([A-Z])", r"\1-\2", value).replace("_", "-").lower()


def type_id(swift_name: str) -> str:
    return TYPE_IDS.get(swift_name, kebab(swift_name))


def field(swift_name: str, name: str, representation: str) -> dict[str, Any]:
    optional = representation.endswith("?")
    nullable = representation.endswith("!")
    if optional or nullable:
        representation = representation[:-1]
    result: dict[str, Any] = {
        "fieldID": kebab(name), "jsonName": name, "required": not optional,
        "nullable": nullable, "ordered": False, "uniqueItems": False,
    }
    path = swift_name + "." + name
    if representation == "[String:String]":
        result.update(kind="STRING_MAP", maximumKeyUTF8Bytes=256, maximumUTF8Bytes=512)
        return result
    array = representation.startswith("[") and representation.endswith("]")
    if array:
        representation = representation[1:-1]
    representation = SINGLE_VALUE_TYPES.get(representation, representation)
    metadata: dict[str, Any] = {}
    if representation in {"UUID", "PublicRequestID"}:
        kind = "STRING"
        metadata["maximumUTF8Bytes"] = 36 if representation == "UUID" else 160
    elif representation == "String":
        kind = "PRESERVED_STRING"
        metadata["maximumUTF8Bytes"] = TEXT_LIMITS.get(path, CANONICAL_BYTE_BUDGET)
    elif representation == "SHA256":
        kind = "SHA256"
    elif representation in {"Int", "Int64", "Int32", "UInt32"}:
        kind = "INTEGER"
        if name == "schemaVersion" and swift_name in SCHEMA_VERSIONS:
            lower = upper = SCHEMA_VERSIONS[swift_name]
        else:
            width = {"Int32": (-(1 << 31), (1 << 31) - 1),
                     "UInt32": (0, (1 << 32) - 1)}.get(representation, (INT64_MIN, INT64_MAX))
            lower, upper = INTEGER_RANGES.get(path, width)
        metadata.update(minimumInteger=lower, maximumInteger=upper)
    elif representation == "UInt64":
        kind = "UNSIGNED_INTEGER"
        metadata.update(minimumUnsignedInteger=0, maximumUnsignedInteger=UINT64_MAX)
    elif representation == "Bool":
        kind = "BOOLEAN"
    elif representation == "Date":
        kind = "REFERENCE_DATE_SECONDS"
    elif representation == "Data":
        kind = "BASE64_BYTES"
        metadata["maximumUTF8Bytes"] = CANONICAL_BYTE_BUDGET
    elif representation in SHAPES:
        kind = "OBJECT"
        metadata["referencedTypeID"] = type_id(representation)
    elif representation in ENUM_VALUES or representation in INTEGER_ENUM_VALUES:
        kind = "ENUM"
        metadata["referencedTypeID"] = type_id(representation)
    else:
        raise ValueError(f"unresolved wire type: {path}: {representation}")
    if array:
        result.update(kind="ARRAY", arrayElementKind=kind, ordered=True,
                      maximumItems=ARRAY_LIMITS.get(path, ARRAY_WIRE_CEILING))
        # The manifest grammar has only outer-field metadata. Do not claim these
        # scalar limits apply to array elements without an explicit grammar rule.
        if "referencedTypeID" in metadata:
            result["referencedTypeID"] = metadata["referencedTypeID"]
    else:
        result["kind"] = kind
        result.update(metadata)
    return result


def explicit_objects() -> list[dict[str, Any]]:
    objects = []
    for name, description in SHAPES.items():
        if name in PUBLISHED_OBJECT_REUSE:
            continue
        fields = []
        for item in description.split():
            field_name, representation = item.split(":", 1)
            fields.append(field(name, field_name, representation))
        objects.append({"typeID": type_id(name),
                        "version": 2 if type_id(name).endswith("-v2") else 1,
                        "unknownFieldPolicy": "REJECT",
                        "fields": sorted(fields, key=lambda value: value["fieldID"])})
    return objects


def explicit_enums() -> list[dict[str, Any]]:
    strings = [{"typeID": type_id(name), "version": 2 if type_id(name).endswith("-v2") else 1,
             "policy": ENUM_POLICIES.get(name, "CLOSED"), "knownValues": sorted(values)}
            for name, values in ENUM_VALUES.items()]
    integers = [{"typeID": type_id(name), "version": 1, "policy": "CLOSED",
                 "knownValues": [], "knownIntegerValues": values}
                for name, values in INTEGER_ENUM_VALUES.items()]
    return strings + integers


def build_manifest(published: dict[str, Any]) -> dict[str, Any]:
    if (hashlib.sha256(canonical(published)).hexdigest() != PUBLISHED_CANONICAL_SHA256
            or published.get("manifestID") != "v23-p03-c06-contract-manifest-v1"
            or published.get("schemaVersion") != 1 or len(published.get("objects", [])) != 29):
        raise ValueError("genuine published V1 manifest is required")
    objects = {value["typeID"]: copy.deepcopy(value) for value in published["objects"]}
    enums = {value["typeID"]: copy.deepcopy(value) for value in published["enums"]}
    for name, identity in PUBLISHED_OBJECT_REUSE.items():
        expected = {item.split(":", 1)[0] for item in SHAPES[name].split()}
        if identity not in objects or {item["jsonName"] for item in objects[identity]["fields"]} != expected:
            raise ValueError("published field set changed: " + name)
    for value in explicit_objects():
        if value["typeID"] in objects:
            raise ValueError("refusing to rewrite a published object: " + value["typeID"])
        objects[value["typeID"]] = value
    for value in explicit_enums():
        prior = enums.get(value["typeID"])
        if prior is not None and prior != value:
            raise ValueError("refusing to rewrite a published enum: " + value["typeID"])
        enums[value["typeID"]] = value
    codec = copy.deepcopy(published["codec"])
    codec.update(codecVersion=2,
                 timeEncoding="PER_FIELD_UTC_RFC3339_MILLISECONDS_Z_OR_FINITE_APPLE_REFERENCE_SECONDS",
                 stringNormalization="PER_FIELD_NFC_WITH_C0_C1_BIDI_CONTROLS_AND_NONCHARACTERS_REJECTED_OR_PRESERVED_SOURCE_UNICODE")
    return {"schemaVersion": 2, "manifestID": MANIFEST_ID, "manifestVersion": 1,
            "persistentContractSchema": "KERNEL_SNAPSHOT_V1", "codec": codec,
            "compatibility": {"minimumReaderVersion": 2, "maximumReaderVersion": 2,
                              "unknownObjectFields": "REJECT", "publishedVersionsImmutable": True},
            "objects": sorted(objects.values(), key=lambda value: value["typeID"]),
            "enums": sorted(enums.values(), key=lambda value: value["typeID"]),
            "reportSectionRegistry": copy.deepcopy(published["reportSectionRegistry"])}


def load_compiler(path: Path):
    spec = importlib.util.spec_from_file_location("completed_schema_compiler", path)
    if spec is None or spec.loader is None:
        raise ValueError("schema compiler cannot be loaded")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def validate_with_compiler(manifest: dict[str, Any], compiler) -> dict[str, dict[str, Any]]:
    return {root: compiler.compile_product_schema(
        manifest, root, "https://schemas.assetrounds.local/tests/completed-manifest-release/" + root)
        for root in (FILE_ROOT, REPORT_ROOT)}


def verify_source_pins(root: Path) -> None:
    """Verify retained Git inputs, without reading/replacing protected drafts."""
    for path, pin in SOURCE_PINS.items():
        raw = subprocess.check_output(["git", "show", SOURCE_HEAD + ":" + path], cwd=root)
        blob = subprocess.check_output(["git", "rev-parse", SOURCE_HEAD + ":" + path],
                                       cwd=root, text=True).strip()
        if (blob != pin["gitBlob"] or hashlib.sha256(raw).hexdigest() != pin["rawSHA256"]
                or hashlib.sha256(raw.replace(b"\r\n", b"\n")).hexdigest() != pin["lfSHA256"]):
            raise ValueError("retained source pin differs: " + path)


def verify_completed_type_source(path: Path) -> None:
    normalized = path.read_bytes().replace(b"\r\n", b"\n")
    if hashlib.sha256(normalized).hexdigest() != COMPLETED_TYPE_LF_SHA256:
        raise ValueError("completed type source pin differs: " + str(path))


def self_test(root: Path, published: dict[str, Any], manifest: dict[str, Any],
              schemas: dict[str, dict[str, Any]], compiler_path: Path,
              completed_type_source: Path) -> list[str]:
    """Actual CLI/independent schema checks; fixtures here are shape probes only.

    These are not authentic completed-file corpus or native Swift executions.
    Root owns paired producer/native source-authenticity evidence separately.
    """
    checks: list[str] = []

    def require(condition: bool, message: str) -> None:
        if not condition:
            raise ValueError("self-test: " + message)

    def run(script: Path, *arguments: Any) -> subprocess.CompletedProcess[str]:
        return subprocess.run([sys.executable, "-B", str(script), *(str(arg) for arg in arguments)],
                              cwd=root, text=True, encoding="utf-8", capture_output=True, timeout=60)

    # Check the current authored wire before any nested test invocations. The
    # historical pins below intentionally refer to retained committed sources.
    verify_completed_type_source(completed_type_source)
    checks.append("completed-type-source-pin")
    verify_source_pins(root)
    checks.append(f"retained-{len(SOURCE_PINS)}-source-pins")
    for collection in ("objects", "enums"):
        retained = {value["typeID"]: value for value in manifest[collection]}
        require(all(retained[value["typeID"]] == value for value in published[collection]),
                "published definition changed")
    require(manifest["reportSectionRegistry"] == published["reportSectionRegistry"],
            "genuine registry changed")
    require(canonical(build_manifest(copy.deepcopy(published))) == canonical(manifest),
            "in-process generation is nondeterministic")
    checks.append("published-definitions-registry-immutable")

    definitions = schemas[FILE_ROOT]["$defs"]
    require(set(definitions[FILE_ROOT]["properties"]) == {
        "family", "formatVersion", "outputID", "snapshot", "capture", "installation",
        "punchReview", "packageRelease", "shopProfile", "manifest", "supplemental",
        "completedPredecessor", "unfinishedAmendmentPredecessor"}, "actual file CodingKeys differ")
    require(set(definitions[REPORT_ROOT]["properties"]) == {
        "schemaVersion", "projectionVersion", "snapshotID", "snapshotSHA256", "manifestSHA256",
        "profileBindingSHA256", "nodes", "semanticSHA256"}, "actual semantic projection CodingKeys differ")
    require(definitions[FILE_ROOT]["properties"]["snapshot"]["$ref"] == "#/$defs/completed-activity-snapshot-v2",
            "file lost actual nested V2")
    require(set(definitions["activity-completion-selected-object-v1"]["properties"]) ==
            {"recordID", "canonicalSHA256"}, "explicit selection lost exact selected-value binding")
    require("uncertaintyCanonical" in definitions["exact-measurement-v1"]["required"],
            "ExactMeasurement custom encoder requires explicit uncertainty key")
    require(definitions["exact-measurement-v1"]["properties"]["uncertaintyCanonical"]["anyOf"][1]
            == {"type": "null"}, "explicit nil uncertainty lost")
    require(definitions["contract-manifest-v2"]["properties"]["schemaVersion"]["minimum"] == 2,
            "nested manifest schema2 lost")
    require("maximumKeyUTF8Bytes" in definitions["contract-field-definition-v2"]["properties"],
            "meta-manifest omitted typed map key limit")
    require("knownIntegerValues" in definitions["contract-enum-definition-v2"]["properties"],
            "meta-manifest omitted genuine numeric enum values")
    require(definitions["plan-page-rotation-v1"]["enum"] == [0, 90, 180, 270],
            "PlanPageRotation numeric enum membership changed")
    require(definitions[REPORT_ROOT]["properties"]["nodes"]["maxItems"] == ARRAY_WIRE_CEILING,
            "new report accidentally retained historical512 ceiling")
    require("placementSources" in definitions["activity-completed-installation-v1"]["required"],
            "installation omitted its actual plan/pose source closure")
    require(set(definitions["activity-completion-placement-sources-v1"]["properties"]) == {
        "planDocuments", "planRevisions", "planPlacements", "poseEvents", "placementHistory"},
        "placement source CodingKeys differ")
    require({"reviewedMarkupPlans", "privacyProjections"}.issubset(
        definitions["activity-completion-evidence-v1"]["required"]),
        "evidence omitted actual reviewed markup/privacy source closure")
    require(definitions["empty-associated-payload-v1"]["properties"] == {}
            and definitions["empty-associated-payload-v1"]["additionalProperties"] is False,
            "synthesized no-payload Swift enum case must be an empty closed object")
    checks.append("actual-root-wrapper-null-and-metadata-shapes")

    validator = root / "Scripts/v21-contracts/portable_contract_validator_v1.py"
    lock = root / "Scripts/v21-contracts/portable-contract-validator.lock.json"
    require(hashlib.sha256(validator.read_bytes()).hexdigest() ==
            "7a6ce17a71e55933a121e60ee11c373b77720f33eddc9d55d4597c19452f0173", "validator pin differs")
    require(hashlib.sha256(lock.read_bytes()).hexdigest() ==
            "69e23865c4114792f9f62d2eab73a06ed85623e01e68c96fcccb79dfdb913862", "validator lock differs")
    admission = run(root / "Scripts/v21-contracts/check-portable-contract-lock.py")
    require(admission.returncode == 0 and json.loads(admission.stdout)["valid"], "validator registry admission failed")
    with tempfile.TemporaryDirectory(prefix="completed-manifest-release-") as directory:
        temporary = Path(directory)
        # Exercise the actual CLI after installing the real tools into their
        # normal repository-relative locations. No author-runtime paths or
        # compiler/published/source overrides are used by these invocations.
        normal_root = temporary / "normal-repository"
        normal_script = normal_root / "Scripts/v23/activity_completed_manifest_release.py"
        normal_script.parent.mkdir(parents=True)
        normal_script.write_bytes(Path(__file__).read_bytes())
        normal_script.with_name("activity_completed_contracts.py").write_bytes(compiler_path.read_bytes())
        normal_script.with_name("p03_c06_contracts.py").write_bytes(
            (root / "Scripts/v23/p03_c06_contracts.py").read_bytes())
        normal_published = normal_root / PUBLISHED_PATH
        normal_published.parent.mkdir(parents=True)
        normal_published.write_bytes(canonical(published) + b"\n")
        normal_source = normal_root / COMPLETED_TYPE_SOURCE
        normal_source.parent.mkdir(parents=True)
        source_lf = completed_type_source.read_bytes().replace(b"\r\n", b"\n")
        normal_source.write_bytes(source_lf.replace(b"\n", b"\r\n"))
        verify_completed_type_source(normal_source)
        normal_output = normal_root / "completed-manifest.json"
        invocation = run(normal_script, "--output", normal_output)
        require(invocation.returncode == 0 and normal_output.read_bytes() == canonical(manifest) + b"\n",
                "normal repository CLI defaults failed: " + invocation.stdout + invocation.stderr)
        checks.append("normal-repository-cli-defaults")

        # A real source mutation must fail before rewriting even an unrelated
        # existing output; CRLF normalization alone was accepted above.
        normal_source.write_bytes(source_lf + b"\n// source drift probe\n")
        normal_output.write_bytes(b"preserve-existing-output")
        invocation = run(normal_script, "--output", normal_output, "--self-test")
        require(invocation.returncode != 0
                and "completed type source pin differs:" in invocation.stderr
                and normal_output.read_bytes() == b"preserve-existing-output",
                "completed type source drift changed output or failed for an unrelated reason")
        checks.append("completed-type-drift-zero-output-effect")

        first = temporary / "manifest-first.json"
        second = temporary / "manifest-second.json"
        for output in (first, second):
            invocation = run(Path(__file__), "--output", output, "--compiler", compiler_path)
            require(invocation.returncode == 0, invocation.stdout + invocation.stderr)
        require(first.read_bytes() == second.read_bytes() == canonical(manifest) + b"\n",
                "real CLI outputs differ")
        invocation = run(Path(__file__), "--output", first, "--compiler", compiler_path, "--check")
        require(invocation.returncode == 0, "real CLI check rejected its output")
        checks.append("actual-cli-byte-determinism-and-check")

        schema_path = temporary / "schema.json"
        instance_path = temporary / "shape-probe.json"

        def validate(schema: dict[str, Any], value: Any = None, *, expected: bool = True,
                     meta_only: bool = False) -> None:
            schema_path.write_bytes(canonical(schema) + b"\n")
            arguments: list[Any] = ["--schema", schema_path]
            if meta_only:
                arguments.append("--meta-only")
            else:
                instance_path.write_bytes(canonical(value) + b"\n")
                arguments.extend(["--instance", instance_path])
            result = run(validator, *arguments)
            receipt = json.loads(result.stdout)
            require(receipt["valid"] == expected and (result.returncode == 0) == expected,
                    "independent validator disagreement: " + result.stdout[:2000] + result.stderr[:1000])

        for schema in schemas.values():
            validate(schema, meta_only=True)
        checks.append("both-actual-roots-official-meta-schema")

        def at(pointer: str) -> dict[str, Any]:
            return {**schemas[FILE_ROOT], "$ref": "#/$defs/" + pointer}

        uuid = "00000000-0000-4000-8000-000000000001"
        validate(at("workspace-id"), {"rawValue": uuid})
        validate(at("workspace-id"), uuid, expected=False)
        mutation = at("activity-state-transition-v2/properties/mutationID")
        validate(mutation, uuid)
        validate(mutation, {"rawValue": uuid}, expected=False)
        validate(at("exact-measurement-v1/properties/uncertaintyCanonical"), None)
        validate(at("shop-report-profile-v1/properties/revision"), UINT64_MAX)
        validate(at("shop-report-profile-v1/properties/revision"), UINT64_MAX + 1, expected=False)
        validate(at("shop-report-profile-v1/properties/recordedAt"), -0.125)
        validate(at("shop-report-profile-v1/properties/recordedAt"), "2001-01-01T00:00:00.000Z", expected=False)
        validate(at("shop-report-brand-v1/properties/shopDisplayName"), "A\u0001B")
        reasons = at("assessment-scope-snapshot-v1/properties/excludedCriterionReasons")
        validate(reasons, {"criterion\u0001": "reason\u202a"})
        validate(reasons, {"criterion": 3}, expected=False)
        basis = {"workspaceID": {"rawValue": uuid}, "activityID": uuid,
                 "basisID": uuid, "revision": 1, "basisSHA256": "a" * 64}
        validate(at("activity-basis-head-reference-v2"), {"installation": {"_0": basis}})
        validate(at("activity-basis-head-reference-v2"), {"installation": basis}, expected=False)
        validate(at("pose-reference-frame-v1"), {"trueBearing": {}})
        validate(at("pose-reference-frame-v1"), {"trueBearing": {"value": 1}}, expected=False)
        validate(at("pose-reference-frame-v1"), {"trueBearing": "TRUE_BEARING"}, expected=False)
        validate(at("pose-uncertainty-v1"), {"unknown": {}})
        validate(at("pose-uncertainty-v1"), {
            "known": {"_0": {"kind": "HORIZONTAL_UNCERTAINTY", "milliDegrees": 1000}}})
        validate(at("pose-uncertainty-v1"), {
            "known": {"kind": "HORIZONTAL_UNCERTAINTY", "milliDegrees": 1000}}, expected=False)
        validate(at("plan-page-reference-v1/properties/rotation"), 90)
        validate(at("plan-page-reference-v1/properties/rotation"), 45, expected=False)
        validate(at("plan-page-reference-v1/properties/rotation"), "90", expected=False)
        validate(at("privacy-region-v1/properties/order"), (1 << 32) - 1)
        validate(at("privacy-region-v1/properties/order"), 1 << 32, expected=False)
        checks.append("independent-real-field-positive-hostile-shape-probes")

        nodes = [{"semanticID": f"n-{index:04d}", "sectionID": "identity", "role": "fact",
                  "label": "Label", "value": "Value"} for index in range(513)]
        projection = {"schemaVersion": 1, "projectionVersion": "activity-completed-report-v1",
                      "snapshotID": "snapshot", "snapshotSHA256": "a" * 64,
                      "manifestSHA256": "b" * 64, "profileBindingSHA256": "c" * 64,
                      "nodes": nodes, "semanticSHA256": "d" * 64}
        validate(schemas[REPORT_ROOT], projection)
        validate(at("report-semantic-projection-v1"), projection, expected=False)
        checks.append("new-report513-shape-with-historical512-preserved")

        hostile = copy.deepcopy(published)
        hostile["codec"]["formatAssertion"] = True
        hostile_path = temporary / "hostile-published.json"
        hostile_path.write_bytes(canonical(hostile))
        sentinel = temporary / "must-remain.json"
        sentinel.write_bytes(b"preserve-existing-output")
        result = run(Path(__file__), "--output", sentinel, "--compiler", compiler_path,
                     "--published-manifest", hostile_path)
        require(result.returncode != 0 and sentinel.read_bytes() == b"preserve-existing-output",
                "unauthentic published input changed output")
        checks.append("tampered-published-input-zero-output-effect")
    return checks


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--published-manifest", type=Path)
    parser.add_argument("--compiler", type=Path)
    parser.add_argument("--completed-type-source", type=Path,
                        help="Swift wire source for --self-test; defaults to the repository production source")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args(argv)
    try:
        root = repository_root()
        published_path = args.published_manifest or root / PUBLISHED_PATH
        compiler_path = args.compiler or Path(__file__).with_name("activity_completed_contracts.py")
        completed_type_source = args.completed_type_source or root / COMPLETED_TYPE_SOURCE
        if args.output.resolve() == published_path.resolve():
            raise ValueError("output must not overwrite the published V1 manifest")
        published = json.loads(published_path.read_text(encoding="utf-8"))
        manifest = build_manifest(published)
        schemas = validate_with_compiler(manifest, load_compiler(compiler_path))
        checks = self_test(root, published, manifest, schemas, compiler_path,
                           completed_type_source) if args.self_test else []
        output = canonical(manifest) + b"\n"
        if args.check:
            if args.output.read_bytes() != output:
                raise ValueError("generated manifest is stale")
        else:
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_bytes(output)
        print(json.dumps({"manifestID": MANIFEST_ID, "manifestVersion": 1,
                          "canonicalSHA256": hashlib.sha256(canonical(manifest)).hexdigest(),
                          "objects": len(manifest["objects"]), "enums": len(manifest["enums"]),
                          "rootTypeIDs": sorted(schemas),
                          "checks": checks,
                          "scope": "EXPLICIT_WIRE_SHAPE_NOT_PRODUCTION_ADMISSION"}, sort_keys=True))
        return 0
    except (OSError, ValueError, TypeError) as error:
        print("completed manifest generation failed: " + str(error), file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
