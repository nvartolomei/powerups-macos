# [PowerUps](https://github.com/nvartolomei/powerups-macos)

A macOS productivity toolkit built for one person. Fork it, point an AI agent at it, make it yours.

## Features

- **App switcher** — switch between open windows and apps, à la `⌘`+`Tab`.
- **App & action launcher** — Spotlight-style search to launch apps and run actions.
- **Markdown Quick Look** — a Quick Look extension that renders Markdown files with a proper preview.

## Building & installing

Prerequisites: Xcode and Node.js (Node builds the Quick Look Markdown preview bundle).

### One-time certificate setup

Local builds sign with a self-signed "Local Self-Signed" certificate. Signing every build with the same certificate keeps the app's code signature stable, so macOS permissions (Accessibility, Screen Recording) survive rebuilds.

```sh
CERTDIR=$(mktemp -d)
printf '[req]\ndistinguished_name = dn\n[dn]\n[ext]\nkeyUsage = critical,digitalSignature\nextendedKeyUsage = critical,codeSigning\nbasicConstraints = critical,CA:FALSE\n' > "$CERTDIR/ext.cnf"
openssl req -x509 -newkey rsa:2048 -keyout "$CERTDIR/key.pem" -out "$CERTDIR/cert.pem" -days 3650 -nodes -subj "/CN=Local Self-Signed" -config "$CERTDIR/ext.cnf" -extensions ext
openssl pkcs12 -export -out "$CERTDIR/cert.p12" -inkey "$CERTDIR/key.pem" -in "$CERTDIR/cert.pem" -passout pass:localpass -name "Local Self-Signed" -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1
security import "$CERTDIR/cert.p12" -k ~/Library/Keychains/login.keychain-db -P localpass -T /usr/bin/codesign
security add-trusted-cert -p codeSign -k ~/Library/Keychains/login.keychain-db "$CERTDIR/cert.pem"
rm -rf "$CERTDIR"
```

### Build & install

```sh
./yolo.sh
```

`yolo.sh` builds the app and its Quick Look Markdown extension, signs them with the local certificate, installs to `/Applications`, and launches.

Permissions only need to be granted once: subsequent builds carry the same signature and bundle id (`com.nvartolomei.powerups`), so macOS keeps the grants.

## License

PowerUps is a fork of [AltTab](https://github.com/lwouis/alt-tab-macos) and, like the original, is licensed under the [GNU General Public License v3.0](LICENCE.md).

- Original work — AltTab, © Louis Pontoise ([lwouis](https://github.com/lwouis)) and the AltTab contributors.

This is a modified version of AltTab; see the commit history for the changes made.
