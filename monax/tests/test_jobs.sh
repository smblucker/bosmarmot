#!/usr/bin/env bash
# ----------------------------------------------------------
# PURPOSE

# This is the test manager for monax jobs. It will run the testing
# sequence for monax jobs referencing test fixtures in this tests directory.

# ----------------------------------------------------------
# REQUIREMENTS

# m

# ----------------------------------------------------------
# USAGE

# test_jobs.sh [appXX]

# Various required binaries locations can be provided by wrapper
bos_bin=${bos_bin:-bos}
burrow_bin=${burrow_bin:-burrow}
keys_bin=${keys_bin:-monax-keys}
# If false we will not try to start keys or Burrow and expect them to be running
boot=${boot:-true}
debug=${debug:-false}

test_exit=0
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

if [[ "$debug" = true ]]; then
    set -o xtrace
fi

# ----------------------------------------------------------
# Constants

# Ports etc must match those in burrow.toml
tendermint_port=48001
keys_port=48002
rpc_tm_port=48003
burrow_root="$script_dir/.burrow"

# Temporary logs
keys_log=keys.log
burrow_log=burrow.log
#
# ----------------------------------------------------------

# ---------------------------------------------------------------------------
# Needed functionality

goto_base(){
  cd ${script_dir}/jobs_fixtures
}

pubkey_of() {
    jq -r ".Accounts | map(select(.Name == \"$1\"))[0].PublicKey.data" genesis.json
}

address_of() {
    jq -r ".Accounts | map(select(.Name == \"$1\"))[0].Address" genesis.json
}

test_setup(){
  echo "Setting up..."
  cd "$script_dir"

  # start test chain
  if [[ "$boot" = true ]]; then
    echo "Booting keys then Burrow.."
    echo "Starting keys on port $keys_port"
    ${keys_bin} server --port ${keys_port} --dir keys > "$keys_log" 2>&1 &
    keys_pid=$!

    echo "Starting Burrow with tendermint port: $tendermint_port, tm RPC port: $rpc_tm_port"
    ${burrow_bin} 2> "$burrow_log" &
    burrow_pid=$!
  else
    echo "Not booting Burrow or keys, but expecting Burrow to be running with tm RPC on port $rpc_tm_port and keys"\
        "to be running on port $keys_port"
  fi


  key1_addr=$(address_of "Full_0")
  key2_addr=$(address_of "Participant_0")
  key2_pub=$(pubkey_of "Participant_0")

  echo -e "Default Key =>\t\t\t\t$key1_addr"
  echo -e "Backup Key =>\t\t\t\t$key2_addr"
  sleep 3 # boot time

  echo "Setup complete"
  echo ""
}

run_test(){
  # Run the jobs test
  echo ""
  echo -e "Testing $bos_bin jobs using fixture =>\t$1"
  goto_base
  cd $1
  echo
  cat readme.md
  echo
  ${bos_bin} pkgs do --keys="http://:$keys_port" --chain-url="tcp://:$rpc_tm_port" --address "$key1_addr" \
    --set "addr1=$key1_addr" --set "addr2=$key2_addr" --set "addr2_pub=$key2_pub" #--debug
  test_exit=$?

  rm -rf ./abi &>/dev/null
  rm -rf ./bin &>/dev/null
  rm ./epm.output.json &>/dev/null
  rm ./jobs_output.csv &>/dev/null

  # Reset for next run
  goto_base
  return $test_exit
}

perform_tests(){
  echo ""
  goto_base
  apps=($1*/)
  repeats=${2:-1}
  # Useful for soak testing/generating background requests to trigger concurrency issues
  for rep in `seq ${repeats}`
  do
    for app in "${apps[@]}"
    do
      echo "Test: $app, Repeat: $rep"
      run_test ${app}
      # Set exit code properly
      test_exit=$?
      if [ ${test_exit} -ne 0 ]
      then
        break
      fi
    done
  done
}

perform_tests_that_should_fail(){
  echo ""
  goto_base
  apps=($1*/)
  for app in "${apps[@]}"
  do
    run_test ${app}

    # Set exit code properly
    test_exit=$?
    if [ ${test_exit} -ne 0 ]
    then
      # actually, this test is meant to pass
      test_exit=0
    else
      break
    fi
  done
}

test_teardown(){
  echo "Cleaning up..."
  if [[ "$boot" = true ]]; then
    kill $burrow_pid
    kill $keys_pid
    rm -rf "$burrow_root"
  fi
  echo ""
  if [[ "$test_exit" -eq 0 ]]
  then
    [[ "$boot" = true ]] && rm -f "$burrow_log" "$keys_log"
    echo "Tests complete! Tests are Green. :)"
  else
    echo "Tests complete. Tests are Red. :("
    echo "Failure in: $app"
  fi
  exit $test_exit
}

# ---------------------------------------------------------------------------
# Setup


echo "Hello! I'm the marmot that tests the $bos_bin jobs tooling."
echo
echo "testing with target $bos_bin"
echo
test_setup

# ---------------------------------------------------------------------------
# Go!

if [[ "$1" != "setup" ]]
then
  if ! [ -z "$1" ]
  then
    echo "Running tests beginning with $1..."
    perform_tests "$1" "$2"
  else
    echo "Running tests that should fail"
    perform_tests_that_should_fail expected-failure

    echo "Running tests that should pass"
    perform_tests app
  fi
fi

# ---------------------------------------------------------------------------
# Cleaning up

if [[ "$1" != "setup" ]]
then
  test_teardown
fi
