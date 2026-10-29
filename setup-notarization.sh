#!/bin/zsh
set -euo pipefail
profile_name="${1:-quota-pup-notary}"
echo 'Create an app-specific password at https://account.apple.com if needed.'
echo 'Enter credentials here in your own terminal, not in chat.'
read 'notary_apple_id?Apple ID email: '
read 'notary_team_id?Apple Developer Team ID: '
# notarytool prompts for the app-specific password without displaying it.
xcrun notarytool store-credentials "$profile_name" \
  --apple-id "$notary_apple_id" --team-id "$notary_team_id"
