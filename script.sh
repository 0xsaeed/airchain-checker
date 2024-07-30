#!/bin/bash

# Define service name and log search string
service_name="stationd"
restart_delay=300  # Restart delay in seconds
config_file="$HOME/.tracks/config/sequencer.toml"
# Initialize the counter
counter=0

retry_transaction_string="Retrying the transaction after 10 seconds..."  # Retry transaction string to search for
verify_pod_error_string="Error in VerifyPod transaction Error" # New VerifyPod error string to search for

gas_string="with gas used"
client_error_string="Client connection error: error while requesting node"  # Another error string to search for
balance_error_string="Error in getting sender balance : http post error: Post"  # Another error string to search for
failed_verify_string="Failed to Transact Verify pod"
vrf_validate_string="Failed to Validate VRF"
vrf_record_string="VRF record is nil"
vrf_init_string="Failed to Init VRF"
vrf_validat_tx_string="Error in ValidateVRF transaction"

# rate_limit_error_string="rpc error: code = ResourceExhausted desc = request ratelimited"  # Rate limit error string to search for
# gin_string="GIN"

error_to_restart="$verify_pod_error_string"
error_to_rollback="$gas_string|$client_error_string|$balance_error_string|$failed_verify_string|$vrf_validate_string|$vrf_record_string|$vrf_init_string|$vrf_validat_tx_string"

# List of unique RPC URLs
unique_urls=(

  "https://airchains-testnet-rpc.crouton.digital/"
  "https://airchains-rpc.sbgid.com/"
)

# Function to log a message with date and time
log_with_date() {
  local message="$1"
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $message"
}

# Function to select a random URL from the list
function select_random_url {
  local array=("$@")
  local rand_index=$(( RANDOM % ${#array[@]} ))
  echo "${array[$rand_index]}"
}

function update_rpc_url {
  # Select a random unique URL
  local random_url=$(select_random_url "${unique_urls[@]}")
  # Update the RPC URL in the config file
  sed -i -e "s|JunctionRPC = \"[^\"]*\"|JunctionRPC = \"$random_url\"|" "$config_file"  
  echo -e "\e[32mNew RPC URL: $random_url\e[0m"
}


log_with_date "Script started to monitor errors in $service_name logs..."

while true; do

  # Get the last 10 lines of service logs
  logs=$(systemctl status "$service_name" --no-pager | tail -n 5)

  # Check for restart error string in logs
  if [[ "$logs" =~ $error_to_restart ]]; then
    log_with_date "Found erorr string in logs, updating $config_file and restarting $service_name..."

    update_rpc_url

    systemctl restart "$service_name"
    log_with_date "Service $service_name restarted"


    counter=0
    # Sleep for the restart delay
    sleep "$restart_delay"

  elif [[ "$logs" =~ $retry_transaction_string ]]; then
    ((counter++))
    log_with_date "Found retry transaction string in logs. Retry attempt: $counter"
    sleep "$restart_delay"
    if [[ $counter -gt 5 ]]; then
      log_with_date "Max retry attempts reached. Restarting the service."
      update_rpc_url
      systemctl restart "$service_name"
      log_with_date "Service $service_name restarted"

      # Sleep for the restart delay
      sleep "$restart_delay"
      
      # Reset the counter
      counter=0
    fi

  # Check for rollback error string in logs
  elif [[ "$logs" =~ $error_to_rollback ]]; then
    log_with_date "Found error. A rollback is required, stopping $service_name..."
    systemctl stop "$service_name"
    update_rpc_url

    log_with_date "Service $service_name stopped,RPC updated and starting rollback..."

    cd ~/tracks
    go run cmd/main.go rollback
    log_with_date "Rollback completed, starting $service_name..."

    systemctl start "$service_name"
    log_with_date "Service $service_name started"

    counter=0
    # Sleep for the restart delay
    sleep "$restart_delay"



  else
    counter=0
    sleep "60" 
  fi

  
done
