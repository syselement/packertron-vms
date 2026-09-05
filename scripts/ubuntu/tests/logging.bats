#!/usr/bin/env bats
# ShellCheck cannot infer function calls made through sourced code and Bats.
# shellcheck disable=SC1091

setup() {
  # shellcheck source=../lib/logging.sh
  source "$BATS_TEST_DIRNAME/../lib/logging.sh"
}

@test "carriage-return progress keeps only its final state" {
  local filtered

  filtered="$(printf 'Progress: [ 5%%]\rProgress: [ 50%%]\rProgress: [100%%]\n' |
    filter_log_output)"

  [[ "$filtered" == "Progress: [100%]" ]]
}

@test "a progress line that ends in a carriage return leaves no blank line" {
  local filtered

  # This is the shape that filled the real logs: dpkg repaints the counter and
  # the last repaint is followed directly by the newline, so stripping through
  # the final \r leaves an empty line behind.
  filtered="$(printf 'real line\n(Reading database ... 5%%\r(Reading database ... 100%%\r\nnext line\n' |
    filter_log_output)"

  [[ "$filtered" == $'real line\nnext line' ]]
}

@test "blank lines the scripts print between sections are preserved" {
  local filtered

  filtered="$(printf 'first section\n\nsecond section\n' | filter_log_output)"

  [[ "$filtered" == $'first section\n\nsecond section' ]]
}

@test "ANSI colour escapes are removed" {
  local filtered

  filtered="$(printf '\e[1m\e[36mSTEP\e[0m  Repositories\n' | filter_log_output)"

  [[ "$filtered" == "STEP  Repositories" ]]
  [[ "$filtered" != *$'\e['* ]]
}

@test "hundreds of dpkg repaints collapse to nothing rather than blank lines" {
  local filtered
  local percent

  {
    printf 'installing packages\n'
    for percent in $(seq 1 200); do
      printf 'Progress: [ %s%%]\r\n' "$percent"
    done
    printf 'done\n'
  } >"$BATS_TEST_TMPDIR/raw"

  filtered="$(filter_log_output <"$BATS_TEST_TMPDIR/raw")"

  [[ "$filtered" == $'installing packages\ndone' ]]
}

@test "both logging scripts route their log file through the shared filter" {
  # 02 and 03 must not grow private copies of the filter.
  local script

  for script in 02-provision-system.sh 03-customize-system.sh; do
    grep -Fq 'filter_log_output >"$LOG_FILE"' "$BATS_TEST_DIRNAME/../$script"
    grep -Fq '. "$SCRIPT_DIR/lib/logging.sh"' "$BATS_TEST_DIRNAME/../$script"
    ! grep -Fq 's/.*\r//' "$BATS_TEST_DIRNAME/../$script"
  done
}
