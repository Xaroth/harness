# shellcheck shell=bash
# container is started with KEYRING=1 in CI; login shell picks up the bus address from /etc/profile.d
# shellcheck disable=SC2016 # expands inside the container
check "Secret Service store and lookup" ux bash -lc '
  printf x | secret-tool store --label=smoke harness smoke &&
  test "$(secret-tool lookup harness smoke)" = x'
