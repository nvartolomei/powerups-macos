set -ex

scripts/l10n/extract_l10n_strings.sh
#pod install

git status
git --no-pager diff
git diff-files --name-only --exit-code
