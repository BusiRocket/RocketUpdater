#!/bin/bash

# A machine with no Helm plugins has nothing to verify. Helm does not create
# its plugin directory until the first install, so the old order reported
# "plugin directory could not be located; checksums not verified" on every run
# of the Mac mini, a warning about nothing that taught the reader to skip it.

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

FIXTURE_DIR=$(mktemp -d "$ROOT_DIR/.plugin-fixture-helm-none.XXXXXX")
trap '/bin/rm -rf -- "$FIXTURE_DIR"' EXIT
mkdir -p "$FIXTURE_DIR/bin"

cat >"$FIXTURE_DIR/bin/helm" <<EOF
#!/bin/bash
case "\$1 \$2" in
"plugin list") printf 'NAME\tVERSION\tTYPE\tAPIVERSION\tPROVENANCE\tSOURCE\n' ;;
"env HELM_PLUGINS") printf '"%s"\n' "$FIXTURE_DIR/missing-plugins-dir" ;;
esac
exit 0
EOF
chmod +x "$FIXTURE_DIR/bin/helm"

set +e
OUTPUT=$(PATH="$FIXTURE_DIR/bin:/usr/bin:/bin" /bin/bash -c '
    set -u
    source "'"$ROOT_DIR"'/lib/print_message.sh"
    source "'"$ROOT_DIR"'/lib/echo_info.sh"
    source "'"$ROOT_DIR"'/lib/echo_success.sh"
    source "'"$ROOT_DIR"'/lib/echo_warning.sh"
    source "'"$ROOT_DIR"'/lib/echo_error.sh"
    source "'"$ROOT_DIR"'/lib/echo_skip.sh"
    source "'"$ROOT_DIR"'/lib/echo_note.sh"
    source "'"$ROOT_DIR"'/lib/command_exists.sh"
    source "'"$ROOT_DIR"'/plugins/helm.sh"
    update_helm
' 2>&1)
STATUS=$?
set -e

if [ "$STATUS" -ne 0 ]; then
    printf '%s\n' "$OUTPUT"
    echo "RED helm plugin: no plugins returned $STATUS"
    exit 1
fi
if printf '%s\n' "$OUTPUT" | grep -qi 'could not be located\|warning'; then
    printf '%s\n' "$OUTPUT"
    echo "RED helm plugin: no installed plugins still produced a warning"
    exit 1
fi
if ! printf '%s\n' "$OUTPUT" | grep -q 'No Helm plugins installed'; then
    printf '%s\n' "$OUTPUT"
    echo "RED helm plugin: an empty inventory was not stated"
    exit 1
fi

echo "helm no-plugins contract passed"
