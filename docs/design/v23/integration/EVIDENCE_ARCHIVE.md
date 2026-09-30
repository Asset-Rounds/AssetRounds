# Historical evidence storage in Dropbox

Owner-approved destination: `/AssetRounds-Archive-20260930` in personal Dropbox namespace `719383756`. This is archival storage for original failed DEVELOPMENT-run ZIPs. It does not change their source commits, failures, collection provenance, gate status or acceptance scope.

The approved 193-file allowlist is `.codex-temp/dropbox-archive-proposal-20260930-v1/PLAN.json` (SHA-256 `6023036b013848c6036fad85259303595dc1072b4f5c72a90cb6e7b0233d2640`), totaling 22,340,199,875 bytes. Current status: 92 completed uploads totaling 9,532,369,570 bytes (91 ordinary completed receipts plus the separate 59,338-byte probe). All 43 ZIPs of run36168198155 and all 35 ZIPs of run36194519822 are copied; additional copies are in progress. Successful copy status alone does not prove raw remote bytes or authorize local removal. One later source-download transport failed; its local original is unchanged and remote target is absent. The old operation records remain intact; a fresh reconciled transport is pending. The first 24 and next 17 offloads completed once after raw remote SHA verification and separate independent prospective review. Both actual preservation reviews passed. Next17 actual nonauthor Sol6.1-xhigh approval57edb6/reviewd4b4db/seale9a83a passed9,030 checks, including481 protected pins, source/index/ref scopes, the152 untouched originals, restoredS01 and full current native/Product namespaces. One small S01 ZIP was restored, so 40 selected files are currently archive-only, 1 is restored and 152 PLAN originals were never removed. Combined offload logical bytes are 4,492,046,748 (about 4.49GB), before the 139,105-byte S01 restoration. Root's latest free-space sample is 6,192,910,336B (~6.19GB). Remaining approved transfers/removals are not complete.

Original `manifest.json`, artifact/run metadata, logs, `run-logs.zip`, ledger, attempt records and retention/cleanup receipts stay local. Current code, worktrees, owner drafts, compiler inputs/modules and current/future native Products are outside this archive plan. Original manifests and ledger entries are never rewritten to make missing bytes appear retained locally.

Before reading an archived run, inspect its immutable `ARCHIVE_LOCATION.json` and successor `ARCHIVE_LOCATION-next17-20260930-v1.json`. The latest evidence-root index is `dropbox-archive-index-v2.json` (SHA-256 `cf7fc55d4e901658dd2431cf53c3a288d74096a4000cb9f33ebd787e717ff805`), preserving all 24 rows from `dropbox-archive-index-v1.json` (SHA-256 `d8da43712e7e2de8f7c78ace39078c836480ec976fd74600511faa1c3c9438d3`) and appending 17. The index identifies exact original local paths, source commits, byte counts, SHA-256 hashes, Dropbox file IDs/revisions, remote-byte proofs and actual offload journals. A proposed or uploaded row does not mean its local copy was removed: the actual per-file removal receipt determines storage status.

Use the authenticated Dropbox connector to obtain fresh metadata and a temporary download link for the indexed file ID. Check identity, revision, path and size, then restore the entire ZIP to its original local path using the reviewed restoration utility. Download links are sensitive and single-use; do not print them or issue HEAD/Range/preview requests. Verify the raw SHA-256 against the original manifest before creating the local file. Restore only as needed and check free space first. Do not overwrite existing files or change original collection evidence.

The restoration utility restores the raw ZIP only. `artifact_state` can then inspect raw retention. Readers such as `build_shared_summary` or completed duplicate/compression readers may also require original manifest-mapped member trees and nested payloads. Restore those through a separately reviewed, bounded extraction procedure before using such readers; do not rerun completed collector, duplicate-removal or compression passes to recreate them. A restored ZIP alone does not establish that every historical reader is ready.

Tools which expect the original local ZIP must run only after restoration. Missing-local archived evidence is not a failed test, a new collection, or permission to dispatch an original again. Do not teach acceptance tooling to skip ZIP retention, trust cloud metadata instead of raw bytes, or promote old development evidence. Dropbox is storage, not a remote Xcode build disk.

Keep the cloud files and the local archive index until the merge and its retention obligations are complete. Do not delete cloud copies merely because local copies were removed. The exact raw verification, restoration and independent reviews live under the proposal directory above; future handoffs must preserve those records and this guide.

Reviewed utility files are in `.codex-temp/dropbox-archive-proposal-20260930-v1/operations-draft-v1/`. `RESTORE_FILE.py` accepts `--index`, `--index-sha256`, `--local-path`, a mode-0600 authenticated `--request`, and a new evidence-root `--receipt`. `ARCHIVE_USAGE.md` documents the request schema. The first batch journal is `~/AssetRounds-v23-review-evidence/dropbox-archive-operations-first-24-20260930-v1/`; the actual S01 retrieval receipt is `dropbox-archive-restore-S01-20260930-v1.json`. Never rerun the completed `OFFLOAD.py` batch or reuse original PLAN identities for restored files.

The successor tools are in `.codex-temp/dropbox-archive-proposal-20260930-v1/operations-next17-v1/`; `RESTORE_FILE.py` supports both row origins using the exact 41-row v2 index. Next17 journal: `~/AssetRounds-v23-review-evidence/dropbox-archive-operations-next17-20260930-v1/`, COMPLETED SHA6bad9a3affa95712305a49cc6fdb49556ed942cf34f915814b88ed358767cf66. The first24 tools/index/pointer/journal and S01 restore remain immutable. Neither offload utility may be replayed; a restored file's new identity never matches old PLAN unlink authority.

## Portable raw ZIP lookup

This exact storage lookup is intended to travel with this guide in the next Git checkpoint. It does not replace the original manifest, byte proofs, journals or authenticated fresh metadata, and this uncommitted guide is not yet a Git backup. No private download URLs are stored. All rows are historical failed DEVELOPMENT results. Use `/Users/rentamac/AssetRounds-v23-review-evidence/<runID>/<filename>` only after verified restoration. Current presence may change after restoration; removal/restore receipts remain authoritative.

```json
{
  "namespaceID": "719383756",
  "indexV2SHA256": "cf7fc55d4e901658dd2431cf53c3a288d74096a4000cb9f33ebd787e717ff805",
  "rows": [
    {
      "runID": "36168198155",
      "sourceHead": "e37ea9671d8cded2566524de32f4eb99a7de0eb3",
      "bytes": 139105,
      "knownSHA256": "676ccfb10947eccc3c213e30c1c5529c2aaee113b1905f2e50f7a37d6abb4c9b",
      "fileID": "id:GZKqoRLQ1X4AAAAAAAAAlQ",
      "revision": "65cb5e68fbb112ae0eccc",
      "dropboxPath": "/AssetRounds-Archive-20260930/36168198155-artifact-10878939852.zip"
    },
    {
      "runID": "36168198155",
      "sourceHead": "e37ea9671d8cded2566524de32f4eb99a7de0eb3",
      "bytes": 413751,
      "knownSHA256": "784e4e925c7433a81dea143755ae1ccea861dcf86923457bf6a1606d5db785c9",
      "fileID": "id:GZKqoRLQ1X4AAAAAAAAAlg",
      "revision": "65cb5e6b02c732ae0eccc",
      "dropboxPath": "/AssetRounds-Archive-20260930/36168198155-artifact-10880182878.zip"
    },
    {
      "runID": "36168198155",
      "sourceHead": "e37ea9671d8cded2566524de32f4eb99a7de0eb3",
      "bytes": 217765611,
      "knownSHA256": "70bd134e28fd5dc65b7bf990aac20216e35aefceafb8d3c8b8849e5de16e670c",
      "fileID": "id:GZKqoRLQ1X4AAAAAAAAAmA",
      "revision": "65cb5e832fffc2ae0eccc",
      "dropboxPath": "/AssetRounds-Archive-20260930/36168198155-artifact-10880249874.zip"
    },
    {
      "runID": "36168198155",
      "sourceHead": "e37ea9671d8cded2566524de32f4eb99a7de0eb3",
      "bytes": 4690426,
      "knownSHA256": "d0c06727ae99f806c400fe671a4a28b4c3857bf47c5a5ff21dfe34fde1977e49",
      "fileID": "id:GZKqoRLQ1X4AAAAAAAAAlw",
      "revision": "65cb5e78ae4c62ae0eccc",
      "dropboxPath": "/AssetRounds-Archive-20260930/36168198155-artifact-10881039590.zip"
    },
    {
      "runID": "36168198155",
      "sourceHead": "e37ea9671d8cded2566524de32f4eb99a7de0eb3",
      "bytes": 8982064,
      "knownSHA256": "da7096f0e5760d00bb88b695eedec31dc3736b78685df460ad660230fa0cf1ae",
      "fileID": "id:GZKqoRLQ1X4AAAAAAAAAmQ",
      "revision": "65cb5e85f0a0a2ae0eccc",
      "dropboxPath": "/AssetRounds-Archive-20260930/36168198155-artifact-10881570976.zip"
    },
    {
      "runID": "36168198155",
      "sourceHead": "e37ea9671d8cded2566524de32f4eb99a7de0eb3",
      "bytes": 72900,
      "knownSHA256": "0bfae83a991c1304278831235ed145308395c88c5432b7cb23d00f3eae491743",
      "fileID": "id:GZKqoRLQ1X4AAAAAAAAAmg",
      "revision": "65cb5e867c14b2ae0eccc",
      "dropboxPath": "/AssetRounds-Archive-20260930/36168198155-artifact-10882042770.zip"
    },
    {
      "runID": "36168198155",
      "sourceHead": "e37ea9671d8cded2566524de32f4eb99a7de0eb3",
      "bytes": 112675031,
      "knownSHA256": "bf9361ca4f2ce8dc2ec794a5f3c24d3f57744e1bcb814fd0ec09d66767131b32",
      "fileID": "id:GZKqoRLQ1X4AAAAAAAAAmw",
      "revision": "65cb5e97530662ae0eccc",
      "dropboxPath": "/AssetRounds-Archive-20260930/36168198155-artifact-10882467605.zip"
    },
    {
      "runID": "36168198155",
      "sourceHead": "e37ea9671d8cded2566524de32f4eb99a7de0eb3",
      "bytes": 82758572,
      "knownSHA256": "e60822e3aa6739a300ecceb2c3fc332e5fbba4532426addc5c3cfecf527f6d7f",
      "fileID": "id:GZKqoRLQ1X4AAAAAAAAAnA",
      "revision": "65cb5e9bdbf7f2ae0eccc",
      "dropboxPath": "/AssetRounds-Archive-20260930/36168198155-artifact-10882558450.zip"
    },
    {
      "runID": "36168198155",
      "sourceHead": "e37ea9671d8cded2566524de32f4eb99a7de0eb3",
      "bytes": 66753300,
      "knownSHA256": "7a070bd4b2023fb8c7a729fa30c7e6eabbb6a4e95f2d77a2df1d3c8c966b8ef3",
      "fileID": "id:GZKqoRLQ1X4AAAAAAAAAnQ",
      "revision": "65cb5ea60724e2ae0eccc",
      "dropboxPath": "/AssetRounds-Archive-20260930/36168198155-artifact-10883083809.zip"
    },
    {
      "runID": "36168198155",
      "sourceHead": "e37ea9671d8cded2566524de32f4eb99a7de0eb3",
      "bytes": 162099126,
      "knownSHA256": "14646f2f990b6f8de6c7d90ff5a324a038cf49cbc60409a55307a390311a6ba1",
      "fileID": "id:GZKqoRLQ1X4AAAAAAAAAng",
      "revision": "65cb5eb4554032ae0eccc",
      "dropboxPath": "/AssetRounds-Archive-20260930/36168198155-artifact-10883232093.zip"
    },
    {
      "runID": "36168198155",
      "sourceHead": "e37ea9671d8cded2566524de32f4eb99a7de0eb3",
      "bytes": 111559197,
      "knownSHA256": "85c5332389fa661b823ff9511b05f9cdc646a0e2eff1ee2a36d3e921b6c98245",
      "fileID": "id:GZKqoRLQ1X4AAAAAAAAAoA",
      "revision": "65cb5ec1b69252ae0eccc",
      "dropboxPath": "/AssetRounds-Archive-20260930/36168198155-artifact-10883739213.zip"
    },
    {
      "runID": "36168198155",
      "sourceHead": "e37ea9671d8cded2566524de32f4eb99a7de0eb3",
      "bytes": 7064220,
      "knownSHA256": "53d452111c4339cd999740580d7065a51ee3a18158b9dfc518c11ce4898eb9b4",
      "fileID": "id:GZKqoRLQ1X4AAAAAAAAAnw",
      "revision": "65cb5ebfbea2f2ae0eccc",
      "dropboxPath": "/AssetRounds-Archive-20260930/36168198155-artifact-10884083673.zip"
    },
    {
      "runID": "36168198155",
      "sourceHead": "e37ea9671d8cded2566524de32f4eb99a7de0eb3",
      "bytes": 131859752,
      "knownSHA256": "49ec5e7a821999a7886378c2e17b88853fdf4f008fcd46996508c84b6e176da4",
      "fileID": "id:GZKqoRLQ1X4AAAAAAAAAoQ",
      "revision": "65cb5edc665962ae0eccc",
      "dropboxPath": "/AssetRounds-Archive-20260930/36168198155-artifact-10884100988.zip"
    },
    {
      "runID": "36168198155",
      "sourceHead": "e37ea9671d8cded2566524de32f4eb99a7de0eb3",
      "bytes": 203776628,
      "knownSHA256": "922112711beea1414c11eb7e40ac67689b95790811659517787436ec1a60cfb0",
      "fileID": "id:GZKqoRLQ1X4AAAAAAAAAog",
      "revision": "65cb5eee692b32ae0eccc",
      "dropboxPath": "/AssetRounds-Archive-20260930/36168198155-artifact-10884196006.zip"
    },
    {
      "runID": "36168198155",
      "sourceHead": "e37ea9671d8cded2566524de32f4eb99a7de0eb3",
      "bytes": 187540300,
      "knownSHA256": "c32b538e24a65f73b21d05a3cda59985e519acb1a7cd18b2cf67275dfad55dfe",
      "fileID": "id:GZKqoRLQ1X4AAAAAAAAAow",
      "revision": "65cb5efaca9e72ae0eccc",
      "dropboxPath": "/AssetRounds-Archive-20260930/36168198155-artifact-10884601361.zip"
    },
    {
      "runID": "36168198155",
      "sourceHead": "e37ea9671d8cded2566524de32f4eb99a7de0eb3",
      "bytes": 158258065,
      "knownSHA256": "3dbcb8e0aedaaae67abf2963f92d70d8fa91bde0dd4a5e7d7566b053399615d4",
      "fileID": "id:GZKqoRLQ1X4AAAAAAAAApA",
      "revision": "65cb5f06ff98a2ae0eccc",
      "dropboxPath": "/AssetRounds-Archive-20260930/36168198155-artifact-10884624246.zip"
    },
    {
      "runID": "36168198155",
      "sourceHead": "e37ea9671d8cded2566524de32f4eb99a7de0eb3",
      "bytes": 116826083,
      "knownSHA256": "e1b8895527b1e21bd800307a403c8c640e07220136ee0ff2d7331ea1b4a935df",
      "fileID": "id:GZKqoRLQ1X4AAAAAAAAApQ",
      "revision": "65cb5f11a2e7b2ae0eccc",
      "dropboxPath": "/AssetRounds-Archive-20260930/36168198155-artifact-10885079215.zip"
    },
    {
      "runID": "36168198155",
      "sourceHead": "e37ea9671d8cded2566524de32f4eb99a7de0eb3",
      "bytes": 125278181,
      "knownSHA256": "60465dfb78f998b49d4977f3810ea96fe6e5778c5d71c91a78a5c668a306593c",
      "fileID": "id:GZKqoRLQ1X4AAAAAAAAApg",
      "revision": "65cb5f1a4ab912ae0eccc",
      "dropboxPath": "/AssetRounds-Archive-20260930/36168198155-artifact-10885092650.zip"
    },
    {
      "runID": "36168198155",
      "sourceHead": "e37ea9671d8cded2566524de32f4eb99a7de0eb3",
      "bytes": 96415095,
      "knownSHA256": "c91d235e18e4c726e1951bb11a9b16e628f2bdc8ba5059db0ecb588f5ef8dc5a",
      "fileID": "id:GZKqoRLQ1X4AAAAAAAAApw",
      "revision": "65cb5f21d16e42ae0eccc",
      "dropboxPath": "/AssetRounds-Archive-20260930/36168198155-artifact-10885138105.zip"
    },
    {
      "runID": "36168198155",
      "sourceHead": "e37ea9671d8cded2566524de32f4eb99a7de0eb3",
      "bytes": 126012899,
      "knownSHA256": "32c04af92feacd5a6a2792787c6ceff37c52d8dda03c468924147f68921c1549",
      "fileID": "id:GZKqoRLQ1X4AAAAAAAAAqA",
      "revision": "65cb5f317d9ba2ae0eccc",
      "dropboxPath": "/AssetRounds-Archive-20260930/36168198155-artifact-10885240208.zip"
    },
    {
      "runID": "36168198155",
      "sourceHead": "e37ea9671d8cded2566524de32f4eb99a7de0eb3",
      "bytes": 155348536,
      "knownSHA256": "865078104a71ed278baddf07b0bfd3db9fe9950f81192a9e978b475457f6cc13",
      "fileID": "id:GZKqoRLQ1X4AAAAAAAAAqQ",
      "revision": "65cb5f41f418c2ae0eccc",
      "dropboxPath": "/AssetRounds-Archive-20260930/36168198155-artifact-10885413209.zip"
    },
    {
      "runID": "36168198155",
      "sourceHead": "e37ea9671d8cded2566524de32f4eb99a7de0eb3",
      "bytes": 89338870,
      "knownSHA256": "f55d5db69e18a62a08eacae96aa9b948b058682b39630d58d22413a233a2967c",
      "fileID": "id:GZKqoRLQ1X4AAAAAAAAAqg",
      "revision": "65cb5f4a68a512ae0eccc",
      "dropboxPath": "/AssetRounds-Archive-20260930/36168198155-artifact-10885649638.zip"
    },
    {
      "runID": "36168198155",
      "sourceHead": "e37ea9671d8cded2566524de32f4eb99a7de0eb3",
      "bytes": 163668995,
      "knownSHA256": "7644cda2a77282b99a280dfb3a6b9d32743e51761dc313859564dc3b86f4da74",
      "fileID": "id:GZKqoRLQ1X4AAAAAAAAArA",
      "revision": "65cb6057b87a22ae0eccc",
      "dropboxPath": "/AssetRounds-Archive-20260930/36168198155-artifact-10885676897.zip"
    },
    {
      "runID": "36168198155",
      "sourceHead": "e37ea9671d8cded2566524de32f4eb99a7de0eb3",
      "bytes": 128647957,
      "knownSHA256": "c7bd6e5b1b793d916fc070d242225c801847fa2a154c20ac6ccd808bd3c51efb",
      "fileID": "id:GZKqoRLQ1X4AAAAAAAAAqw",
      "revision": "65cb6038f8b772ae0eccc",
      "dropboxPath": "/AssetRounds-Archive-20260930/36168198155-artifact-10886378240.zip"
    },
    {
      "runID": "36168198155",
      "sourceHead": "e37ea9671d8cded2566524de32f4eb99a7de0eb3",
      "bytes": 125466686,
      "knownSHA256": "db4453cf39da6aff752e92834894ac7427322cbab7271e2a6525b6434489bba3",
      "fileID": "id:GZKqoRLQ1X4AAAAAAAAArQ",
      "revision": "65cb6a58f98892ae0eccc",
      "dropboxPath": "/AssetRounds-Archive-20260930/36168198155-artifact-10886680736.zip"
    },
    {
      "runID": "36168198155",
      "sourceHead": "e37ea9671d8cded2566524de32f4eb99a7de0eb3",
      "bytes": 128255162,
      "knownSHA256": "8cdc728fe7810cc188b83eaeeae247060ed5df6afc499b1b20529a45a73c2e59",
      "fileID": "id:GZKqoRLQ1X4AAAAAAAAArg",
      "revision": "65cb6ae2e2d7d2ae0eccc",
      "dropboxPath": "/AssetRounds-Archive-20260930/36168198155-artifact-10886933254.zip"
    },
    {
      "runID": "36168198155",
      "sourceHead": "e37ea9671d8cded2566524de32f4eb99a7de0eb3",
      "bytes": 118738556,
      "knownSHA256": "063c1b4114b519f57e6ef4bec2ddeac8f51c2d9ad9626341fe1848df8145b228",
      "fileID": "id:GZKqoRLQ1X4AAAAAAAAArw",
      "revision": "65cb6b905036c2ae0eccc",
      "dropboxPath": "/AssetRounds-Archive-20260930/36168198155-artifact-10887290877.zip"
    },
    {
      "runID": "36168198155",
      "sourceHead": "e37ea9671d8cded2566524de32f4eb99a7de0eb3",
      "bytes": 195551522,
      "knownSHA256": "282959ca967aef5a91138cd738091efe48618e036237432ea4155df1b421ab96",
      "fileID": "id:GZKqoRLQ1X4AAAAAAAAAsA",
      "revision": "65cb6ba27020a2ae0eccc",
      "dropboxPath": "/AssetRounds-Archive-20260930/36168198155-artifact-10887934556.zip"
    },
    {
      "runID": "36168198155",
      "sourceHead": "e37ea9671d8cded2566524de32f4eb99a7de0eb3",
      "bytes": 179029623,
      "knownSHA256": "5fad7363b01dc940b729186ae4cfd6252ea12cd71f049182cf60b0ed52cb7f58",
      "fileID": "id:GZKqoRLQ1X4AAAAAAAAAsQ",
      "revision": "65cb6bba99df52ae0eccc",
      "dropboxPath": "/AssetRounds-Archive-20260930/36168198155-artifact-10887975711.zip"
    },
    {
      "runID": "36168198155",
      "sourceHead": "e37ea9671d8cded2566524de32f4eb99a7de0eb3",
      "bytes": 166659589,
      "knownSHA256": "6870160ede2645b73d06b04baa0064b5e014c76dab18ef31ad142982ad062436",
      "fileID": "id:GZKqoRLQ1X4AAAAAAAAAsg",
      "revision": "65cb6bcaf6f9b2ae0eccc",
      "dropboxPath": "/AssetRounds-Archive-20260930/36168198155-artifact-10888057501.zip"
    },
    {
      "runID": "36168198155",
      "sourceHead": "e37ea9671d8cded2566524de32f4eb99a7de0eb3",
      "bytes": 101059848,
      "knownSHA256": "e3e29f62f259fe455d4cff7834a518929ff064c7ea0928c69569ec9559f9dca9",
      "fileID": "id:GZKqoRLQ1X4AAAAAAAAAsw",
      "revision": "65cb6d70d4e9d2ae0eccc",
      "dropboxPath": "/AssetRounds-Archive-20260930/36168198155-artifact-10888067580.zip"
    },
    {
      "runID": "36168198155",
      "sourceHead": "e37ea9671d8cded2566524de32f4eb99a7de0eb3",
      "bytes": 163263754,
      "knownSHA256": "d4d817fd7afc6889e52affeede0cdb513ba76d6d9244179741a3bcfb234b836c",
      "fileID": "id:GZKqoRLQ1X4AAAAAAAAAtA",
      "revision": "65cb6d87bc3002ae0eccc",
      "dropboxPath": "/AssetRounds-Archive-20260930/36168198155-artifact-10888139142.zip"
    },
    {
      "runID": "36168198155",
      "sourceHead": "e37ea9671d8cded2566524de32f4eb99a7de0eb3",
      "bytes": 171199740,
      "knownSHA256": "932db233a6dd9f7e16441cd54db1ecddf76f484db9244986be7cf80dd42f2f4f",
      "fileID": "id:GZKqoRLQ1X4AAAAAAAAAtg",
      "revision": "65cb6df5745532ae0eccc",
      "dropboxPath": "/AssetRounds-Archive-20260930/36168198155-artifact-10888350121.zip"
    },
    {
      "runID": "36168198155",
      "sourceHead": "e37ea9671d8cded2566524de32f4eb99a7de0eb3",
      "bytes": 66730275,
      "knownSHA256": "cebdebadfe18da015f15866fd1dcb3996adaf11ddfea3fdf9aa51ec8363c513e",
      "fileID": "id:GZKqoRLQ1X4AAAAAAAAAtQ",
      "revision": "65cb6de0e3b422ae0eccc",
      "dropboxPath": "/AssetRounds-Archive-20260930/36168198155-artifact-10888596536.zip"
    },
    {
      "runID": "36168198155",
      "sourceHead": "e37ea9671d8cded2566524de32f4eb99a7de0eb3",
      "bytes": 73160953,
      "knownSHA256": "9394bdb5028ff2b6567b924cde34ae6c5a142c8375fe5c13fcf7347aef82912e",
      "fileID": "id:GZKqoRLQ1X4AAAAAAAAAtw",
      "revision": "65cb6e36ad4da2ae0eccc",
      "dropboxPath": "/AssetRounds-Archive-20260930/36168198155-artifact-10888916683.zip"
    },
    {
      "runID": "36168198155",
      "sourceHead": "e37ea9671d8cded2566524de32f4eb99a7de0eb3",
      "bytes": 66209847,
      "knownSHA256": "0fa22f558e46c68c3527afc9e1e03541da56afe2555fedd72330a07a70f48bd5",
      "fileID": "id:GZKqoRLQ1X4AAAAAAAAAuA",
      "revision": "65cb6e396db052ae0eccc",
      "dropboxPath": "/AssetRounds-Archive-20260930/36168198155-artifact-10888923520.zip"
    },
    {
      "runID": "36168198155",
      "sourceHead": "e37ea9671d8cded2566524de32f4eb99a7de0eb3",
      "bytes": 124125422,
      "knownSHA256": "843f6e7af1e1337d0351165a96a8ed2aed38ca25c0986d3851e8abb3beccb5cc",
      "fileID": "id:GZKqoRLQ1X4AAAAAAAAAuQ",
      "revision": "65cb6e55eca982ae0eccc",
      "dropboxPath": "/AssetRounds-Archive-20260930/36168198155-artifact-10888941192.zip"
    },
    {
      "runID": "36168198155",
      "sourceHead": "e37ea9671d8cded2566524de32f4eb99a7de0eb3",
      "bytes": 107139011,
      "knownSHA256": "c29806e3e553d3ab38083ec2a2440d5d7b663ebe59103f37fab5fcee21b276f0",
      "fileID": "id:GZKqoRLQ1X4AAAAAAAAAug",
      "revision": "65cb6e5a5bd722ae0eccc",
      "dropboxPath": "/AssetRounds-Archive-20260930/36168198155-artifact-10889375513.zip"
    },
    {
      "runID": "36168198155",
      "sourceHead": "e37ea9671d8cded2566524de32f4eb99a7de0eb3",
      "bytes": 147136410,
      "knownSHA256": "1d118cf675078dd712d2247c35ec7d91c4446d01e9ca3a22e9b2d8d5da3e433f",
      "fileID": "id:GZKqoRLQ1X4AAAAAAAAAvQ",
      "revision": "65cb6f4032a962ae0eccc",
      "dropboxPath": "/AssetRounds-Archive-20260930/36168198155-artifact-10889379594.zip"
    },
    {
      "runID": "36168198155",
      "sourceHead": "e37ea9671d8cded2566524de32f4eb99a7de0eb3",
      "bytes": 81197,
      "knownSHA256": "7170def43287a4c63c7a027e95ea6a92918346aa09c48969a4255dc471cc1cd6",
      "fileID": "id:GZKqoRLQ1X4AAAAAAAAAuw",
      "revision": "65cb6f2e5efd72ae0eccc",
      "dropboxPath": "/AssetRounds-Archive-20260930/36168198155-artifact-10889558496.zip"
    },
    {
      "runID": "36168198155",
      "sourceHead": "e37ea9671d8cded2566524de32f4eb99a7de0eb3",
      "bytes": 100294489,
      "knownSHA256": "fc5ae68bbf521df2b5f82cf83deb689b98e9c49a95f8423d0ee9754a8522d9db",
      "fileID": "id:GZKqoRLQ1X4AAAAAAAAAvA",
      "revision": "65cb6f3fb7d312ae0eccc",
      "dropboxPath": "/AssetRounds-Archive-20260930/36168198155-artifact-10889590580.zip"
    }
  ]
}
```

## 2026-09-30 current storage snapshot

At20:02:59Z184successful copies total21,334,381,880B; final20continuation remains active after secondFETCH_FAILED was reconciled to absentdestination/exactsource08b5. Copy success is not raw-byte/offload proof. Frozen final152selection79ef2 has131genuine new strict raw-byte-verification.v1 proofs/15,320,728,644B and matched after-stream identities/revisions;21strict proofs stilldue. Six legacy restoration proofs stay historical because strictrevision/manifest fields were not captured then. All152 selected originals remain local. Immutable41rowindex-v2cf7fc remains the current locator (40cloud-only+S01restored); the proposed193rowindex/five additivepointers are uncreated. Implementation-only review52f85/e9fb/8f91 passed224checks/64synthetic cases, but actualaggregate/renderedbinding/finalconfig/newnative-preservationguard/operationalapproval/freshquietadmission remain required before further removal.

The new diagnostic20 original is fully retained1398artifacts+268Products, manifestcec094/terminal79067f/restored0fd911/COMPLETE8340dd/HOLD_RELEASEDa8f4ab; independent actuale8c6/38b6/4948 passes17,931checks. Preserve this fifth original plus allfour prior ones, exactrun metadata/manifests/logs/ledger/attempts/recoverycontrols and compiler source/module snapshots. No completedcollector/remover is replayed; raw ZIP restoration does not reconstruct extracted/member readers automatically. Root imports separately reviewed16source677d only after actualinspection release; Gitcheckpoint audit/push remain pending, so this guide is not yet a pushed recovery checkpoint.


## 2026-09-30 final checkpoint record: verified copies and separate pending effects

The exact16 ff6dfeca source checkpoint was independently approved by nonauthor GPT-6.1 Sol xhigh (167 checks, APPROVALc61da59d/REVIEWfc8eeaac/SEALe12e5689), then imported by root after new native inspection release. Import receipt733ad057 preserves14 before-images and two new CI paths. Primary app/test/project1206 map677d1252 matches the compiled Checked Scratch candidate804545ef; seven CI paths match V6eb1bf948/2702-input85060bb6. Nine changed Swift inputs have actual DEBUG604/fresh306 and conditional nonDEBUG604 compilation; Xcode build0/64.819s and affected native20 exit65/811.207s yielded18PASS2FAIL0SKIP. CI required381+42 passed with no failure/error/skip (actual5bfc1f3d, independent7b576/aa70). The two AppAccess readiness failures remain explicit blockers. This incomplete integration checkpoint is DEVELOPMENT only; every main gate stays OPEN and releaseReady=false. Future Ledgerf698/Observer2cc diagnostics and Observer095b are excluded from these16 source paths. Six owned records complete the eventual22-path checkpoint; final record audit, staging, commit and non-force push are still pending at this record freeze.

The separate first-error4eea original is fully closed/restored/released: Xcode build0/143.438s; native20 exit65/859.260s,18PASS2FAIL0SKIP; both first stamps Observer didPerform.first.raw.deltaParent invalidAuthority then Ledger permitDidPerform. Individual false parent predicate remains unproved. All15 phases ran once; retained1398 artifactscec094/268 Products, terminal79067f/restored0fd911/COMPLETE8340dd/HOLDa8f4ab/rootclosurebe5aa. Independent nonauthor Sol6.1-xhigh e8c6/38b6/4948 passed17,931 checks; this is provenance/restoration, not functional acceptance. Minimal DEBUG captured-comparison discriminator095b/mapd92e has independent source-only721386/894d/18c42 approval,8,414 checks, but no actual compile/runtime or behavior fix. Keep allfive completed originals and current/external Products.

Dropbox PLAN6023036b now has all193 copies/22,340,199,875B and strict streamed raw-byte proofs. Counting correction: canonical transfers have192 distinct completed source receipts; the standalone legacy probe contributes one59,338B copy without a canonical transfer receipt. The earlier20:02:59Z184/21,334,381,880B snapshot was canonical-only; including the probe it was185/21,334,441,218B. No payload was lost or rewritten. Both historical FETCH_FAILED operations and their actual absence/source reconciliations remain immutable; successful final20 continuation is a distinct transport. Final152 selection79ef2 totals17,848,153,127B; actual strict proof setfe3f7b43 and finite bindingf00e4b86 validate ordered proofs/actual manifest hashes/unique IDs, with all152 local original10-field identities intact. Last21 stream completed once0/receipt603b2b21 and matching post-stream metadata retained. The old six restoration samples remain history, not upgraded strict proof controls.

Root imported exact12 reviewed final152 tools (implementation-only52f85/e9fb/8f91,224 checks/64 synthetic tests); no new index, removal intent or offload application exists. Fresh global metadata refresh was refused RATE_LIMITED; no fresh observation is invented. New preservation guard/final effect config/independent operational review/quiet admission remain due. Current immutable41-row index-v2cf7fc55d and pointer0c83224d remain authoritative:40 files archive-only, S01 restored at its new inode,152 originals local. Previous4,492,046,748B logical offload stays separate. Metadata/manifests/logs/ledger/attempts, prior indices/pointers/journals, allfive native originals, compiler snapshots and recovery controls remain local. EVIDENCE_ARCHIVE.md carries the portable41 lookup; copies and raw ZIP recovery do not establish extracted/native readability or gate credit.

Human-authorized durablechat01a0f2f6-76ae-7396-b9fb-9f07a07a10c1 retains12 reports and six reusable reports-only contexts; root alone owns effects. Future cold qualification dispatcher/payload binding gaps, six unconditional P04 unit scaffolds, source coverage3688/33 vs actual full runtime coverage, pinned UI/owner review, physical protection and full later V23 scope remain open. Never transfer development evidence into gates, weaken guards/tests/watchdogs, or replay a completed collector.
