# Microsoft retail public signing anchor

`microsoft-retail-games.rsa` is a 539-byte public-only CNG RSA1 blob (4096-bit
modulus and public exponent). It contains no private key or game content key.

It was independently extracted using `acquire::extract_public_signing_keys` from
the official Microsoft GDK April 2025 Update 6 archive:

- Source: https://github.com/microsoft/GDK/releases/download/April-2025-Update-6-v2504.6.4142/GDK_2504.6.4142.zip
- Archive SHA256: `b10d02d2b3619129fb5d176a762fb10961dd4a59c3a19dc64a6e38e03deb590f`
- Public blob SHA256: `183f0ae05431e4ad91554e88946967c872997227dbe6c85116f5fd2fd2d1229e`
- Upstream identification: [GreenGamesPublicKey](https://github.com/emoose/xvdtool/blob/6fc28862cc5fb711843c0e717101ce4034acf805/LibXboxOne/Keys/DurangoKeys.cs).

The same anchor was already used by this project's independent Bedrock review
script. `signed_package.rs` checks its digest, verifies RSA-PSS/SHA256 (32-byte
salt) over the signed header, binds the content ID and numeric version to
authenticated Microsoft metadata, verifies the signed hash-tree root, every
intermediate node and every stored content page before parsing or decryption.
It rejects unsupported layouts and truncated/trailing data. Mutable presence
pages are not used by the extractor; their length is part of the signed header.

HTTP is restricted to the credential-free, query-free public assets1/2 Xbox CDN.
License/metadata/component requests still use verified HTTPS. No certificate
verification is disabled. Future signing keys/layouts require a code update.
