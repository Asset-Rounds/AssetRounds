# Cold continuation v2.2 scope addendum

GPT-6.1 Sol xhigh, source contract only. Preserves v2 e275b2d2 and frozen v2.1 6bd86d68 unchanged. Router EraseSchema2ColdScratchLifecyclePermitV1 now requires a separate privately supplied c16ObservationBinding:(String,Int)throws->Void and exposes requireC16ObservationBinding(planSHA256:ordinal:)throws. It brackets that actual check with the nonrecursive same-operation EX/G/root proof. Ledger private current scope issuer and every scope boundary consume this exact API.

The actual issuer must compare canonical fixed plan SHA and requested ordinal with the current authenticated Store mixed progress. During active PREPARING/PREPARING_CAPTURED it is the exact activeC16Ordinal; outside active execution only the defined fixed inspection ordinal min(completedC16PrefixCount,lastStep) is admitted. An empty plan has no C16 scope. An in-range future/old ordinal or a different plan rejects. The actual fresh Store source/progress readback plus same EX/activity/G/root and memory uncertainty/revocation must be rechecked on every scope boundary. A lexical lifetime flag or closure declaration alone proves none of that.

This API addition closes the interface omission only. The central real issuer and complete tail are still unimplemented and no installability, compilation, runtime or review approval is claimed.
