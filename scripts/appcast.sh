#!/bin/bash
# Sign release/Cans.zip for Sparkle and write release/appcast.xml, whose one item is this release.
# The app reads it from releases/latest/download/appcast.xml, so the newest release is the feed.
# Key: $SPARKLE_ED_PRIVATE_KEY (CI secret), else the login keychain (generate_keys).
# Usage: scripts/appcast.sh <version> <build number> [zip url]
set -euo pipefail
cd "$(dirname "$0")/.."
version=$1 build=$2
url=${3:-https://github.com/unhingedpanda/cans/releases/download/v$version/Cans.zip}
SPARKLE=2.10.0  # keep in step with project.yml
tools="build/sparkle-$SPARKLE"

if [ ! -x "$tools/bin/sign_update" ]; then
  mkdir -p "$tools"
  curl -fsSL "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE/Sparkle-$SPARKLE.tar.xz" \
    | tar xJ -C "$tools" ./bin/sign_update
fi
if [ -n "${SPARKLE_ED_PRIVATE_KEY:-}" ]; then
  attributes=$(printf '%s' "$SPARKLE_ED_PRIVATE_KEY" | "$tools/bin/sign_update" --ed-key-file - release/Cans.zip)
else
  attributes=$("$tools/bin/sign_update" release/Cans.zip)
fi

cat > release/appcast.xml <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Cans</title>
    <item>
      <title>Cans $version</title>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$build</sparkle:version>
      <sparkle:shortVersionString>$version</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <sparkle:fullReleaseNotesLink>https://github.com/unhingedpanda/cans/releases/tag/v$version</sparkle:fullReleaseNotesLink>
      <enclosure url="$url" type="application/octet-stream" $attributes/>
    </item>
  </channel>
</rss>
EOF
echo "==> release/appcast.xml: Cans $version (build $build)"
