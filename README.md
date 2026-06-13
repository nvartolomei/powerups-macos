# PowerUps

macOS window switcher, forked from [AltTab](https://github.com/lwouis/alt-tab-macos).

## Building

Prerequisites: Xcode, CocoaPods (`brew install cocoapods`), then:

```sh
pod install
```

### Debug build

```sh
xcodebuild -workspace powerups-macos.xcworkspace -scheme Debug -configuration Debug -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO build
```

### Release build (local install)

The Release config signs with a Developer ID certificate in CI; for local builds, use a self-signed "Local Self-Signed" certificate instead. Signing every local build with the same certificate keeps the app's code signature stable, so macOS permissions (Accessibility, Screen Recording) survive rebuilds.

One-time certificate setup:

```sh
CERTDIR=$(mktemp -d)
printf '[req]\ndistinguished_name = dn\n[dn]\n[ext]\nkeyUsage = critical,digitalSignature\nextendedKeyUsage = critical,codeSigning\nbasicConstraints = critical,CA:FALSE\n' > "$CERTDIR/ext.cnf"
openssl req -x509 -newkey rsa:2048 -keyout "$CERTDIR/key.pem" -out "$CERTDIR/cert.pem" -days 3650 -nodes -subj "/CN=Local Self-Signed" -config "$CERTDIR/ext.cnf" -extensions ext
openssl pkcs12 -export -out "$CERTDIR/cert.p12" -inkey "$CERTDIR/key.pem" -in "$CERTDIR/cert.pem" -passout pass:localpass -name "Local Self-Signed" -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1
security import "$CERTDIR/cert.p12" -k ~/Library/Keychains/login.keychain-db -P localpass -T /usr/bin/codesign
security add-trusted-cert -p codeSign -k ~/Library/Keychains/login.keychain-db "$CERTDIR/cert.pem"
rm -rf "$CERTDIR"
```

`Info.plist` contains a `#VERSION#` placeholder normally substituted by CI, so fill it in for the build and restore it after:

```sh
sed -i '' -e "s/#VERSION#/$(git describe --tags --abbrev=0 | tr -d v)/" Info.plist
xcodebuild -workspace powerups-macos.xcworkspace -scheme Release -derivedDataPath DerivedData CODE_SIGN_IDENTITY="Local Self-Signed" OTHER_CODE_SIGN_FLAGS="--timestamp=none --deep --options runtime" build
git checkout -- Info.plist
```

### Install

```sh
osascript -e 'quit app "PowerUps"' 2>/dev/null
rm -rf /Applications/PowerUps.app
cp -R DerivedData/Build/Products/Release/PowerUps.app /Applications/
open /Applications/PowerUps.app
```

Permissions only need to be granted once: subsequent builds carry the same signature and bundle id (`com.nvartolomei.powerups`), so macOS keeps the grants.

## License

PowerUps is a fork of [AltTab](https://github.com/lwouis/alt-tab-macos) and, like the original, is licensed under the [GNU General Public License v3.0](LICENCE.md).

- Original work — AltTab, © Louis Pontoise ([lwouis](https://github.com/lwouis)) and the AltTab contributors.

This is a modified version of AltTab; see the commit history for the changes made.
