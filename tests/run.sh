#!/usr/bin/env bash
# =============================================================================
# BADASS automated checks - run INSIDE the VM (user in the docker group)
#   tests/run.sh p1 | p2s | p2g | p3 | all
# Each part: close other labs -> import/open its GNS3 project -> start nodes
# through the GNS3 API -> apply the part's scripts -> assert -> summary.
# Exit code = number of failed checks (0 = everything passed).
# =============================================================================
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"

# shellcheck source=tests/assert.sh
source "$DIR/assert.sh"
# shellcheck source=tests/test_p1.sh
source "$DIR/test_p1.sh"
# shellcheck source=tests/test_p2.sh
source "$DIR/test_p2.sh"
# shellcheck source=tests/test_p3.sh
source "$DIR/test_p3.sh"

case "${1:-}" in
    p1)      test_p1 ;;
    p2s|p2)  test_p2s ;;
    p2g|p2m) test_p2g ;;
    p3)      test_p3 ;;
    all)     test_p1; test_p2s; test_p2g; test_p3
             $CTL down >/dev/null ;;   # free the VM after a full run
    *)       echo "usage: $0 {p1|p2s|p2g|p3|all}"; exit 2 ;;
esac

summary
exit "$FAIL"
