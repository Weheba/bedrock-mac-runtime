# Latest package acquisition verification — 2026-10-18

The experimental download used to require a working HTTPS endpoint when the
Microsoft metadata did not supply a strong package digest. The official legacy
Xbox asset hostname failed that condition, so new packages could be discovered
but could not be downloaded (`SECURE_DOWNLOAD_UNAVAILABLE`).

The installer now supports these public encrypted payloads using the Microsoft
retail signing anchor documented in [trust provenance](../NativeHelper/src/trust/README.md).
It verifies RSA-PSS/SHA256 before trusting header lengths, binds the signed content
ID and numeric version to authenticated service metadata, and checks the complete
hash tree and every stored content page before any XVD parser or decryptor runs.
Only credential-free, query-free assets1/2 Xbox URLs can use the legacy transport;
game download redirects are disabled. Account/license/component traffic retains
validated HTTPS. The tested revision pins and experimental status are unchanged.

## Local acceptance

- 13 native tests passed, including signature mutation, header identity/version,
  unsupported layouts, root/intermediate/leaf/content corruption, data-unit
  mutation, truncation/trailing bytes and transport boundaries.
- 55 Swift/layout tests completed with no failures; 2 existing live tests skipped.
- Release packaging rebuilt the helper, verified compatibility artifact hashes,
  and passed strict deep ad-hoc signature verification.
- Dungeons II 1.1.2.0: all 9,805,545,472 encrypted bytes downloaded through
  the signature-verification path. Retail signature and full tree/content passed.
  SHA256: `5af8ccaf853f8db4c86a1f041701af54a0f1a08d224ddcd5273fdf07202f3b98`.
- Bedrock 1.26.5203.0: all 2,069,975,040 encrypted bytes downloaded through the
  signature-verification path. Retail signature and full tree/content passed.
  SHA256: `af5a72dab1a6e72fb63f931f5d80961b85090142994b93d60d8cd7a3d5a5f6c4`.

The read-only `package-probe <game> <new-output-path> full` command requires an
existing signed-in account and a real license. It downloads and verifies the
encrypted container without decrypting, installing, launching, or changing the
library, selected version or CrossOver environments. Diagnostics emit fixed
stages and public version/size/digest information, never credentials or URLs.

These checks prove acquisition and container authenticity, not gameplay or the
compatibility of an untested game release. The built application remains a local,
ad-hoc signed preview; it has not been published or installed over /Applications.
