#!/usr/bin/env bash

# This script uploads a selected ISO file from a local directory to a
# VMware vSphere datastore. It can be run interactively or with command-line arguments.
#
# Requires:
#   - govc (https://github.com/vmware/govmomi/tree/master/govc)
#   - yq (https://github.com/mikefarah/yq)
#   - A vSphere user with Datastore.File.Upload privileges.

# --- Global Variables and Configuration ---
LOCAL_ISO_DIR="iso"
DEFAULT_DATASTORE_FOLDER="iso"

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Utility Functions ---

# Function to display messages with colors.
print_message() {
    local color=""
    local message="$2"
    case "$1" in
        info) color="\033[32m" ;; # Green
        error) color="\033[31m" ;; # Red
        warn) color="\033[33m" ;; # Yellow
        *) color="\033[0m" ;; # Reset
    esac
    printf "${color}%b\033[0m\n" "$message"
}

# Function to check for required dependencies.
check_dependencies() {
    local dep="$1"
    if ! command -v "$dep" &> /dev/null; then
        print_message error "Error: The required tool '$dep' is not installed."
        print_message info "Please install it and try again."
        if [ "$dep" == "govc" ]; then
            print_message info "Installation instructions for govc: https://github.com/vmware/govmomi/releases"
        fi
        exit 1
    fi
}

# Function to get user input with a prompt.
get_input() {
    local prompt="$1"
    local default_val="$2"
    local input_var_name="$3"
    local input=""

    read -rp "$(print_message info "$prompt [Default: $default_val]: ")" input
    if [[ -z "$input" ]]; then
        input="$default_val"
    fi
    # Use a dynamic variable name to assign the input value.
    eval "$input_var_name=\"$input\""
}

# Function to list and select an ISO file.
select_iso() {
    # Check if the local ISO directory exists.
    if [[ ! -d "$LOCAL_ISO_DIR" ]]; then
        print_message error "Error: The local ISO directory '$LOCAL_ISO_DIR' was not found."
        print_message info "Please ensure your ISO files are in a directory named 'iso'."
        exit 1
    fi

    # Find all ISO files in the specified directory.
    # Use 'find' to recursively locate files.
    local isos=()
    while IFS= read -r -d '' iso; do
        isos+=("$iso")
    done < <(find "$LOCAL_ISO_DIR" -type f -name "*.iso" -print0)


    if [ ${#isos[@]} -eq 0 ]; then
        print_message error "Error: No ISO files found in '$LOCAL_ISO_DIR'."
        print_message info "Please place the ISO files you wish to upload into this directory."
        exit 1
    fi

    # Display a numbered list of ISOs.
    print_message info "Found the following ISO files:"
    for i in "${!isos[@]}"; do
        printf "  %s) %s\n" $((i+1)) "$(basename "${isos[$i]}")"
    done

    # Prompt user to select an ISO.
    local selection
    while true; do
        read -rp "$(print_message info "Please select an ISO to upload (1-${#isos[@]}): ")" selection
        if [[ "$selection" =~ ^[0-9]+$ ]] && (( selection >= 1 && selection <= ${#isos[@]} )); then
            ISO_FILE_PATH="${isos[$((selection-1))]}"
            break
        else
            print_message error "Invalid selection. Please enter a number between 1 and ${#isos[@]}."
        fi
    done
}

# --- Main Script Logic ---

# Check for govc dependency.
check_dependencies govc

# --- Parse command-line arguments and set variables ---
ISO_FILE_PATH=""
DATASTORE_NAME=""
URL=""
USERNAME=""
PASSWORD=""
DATASTORE_FOLDER=""

# Parse command-line flags.
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --iso-file)
            ISO_FILE_PATH="$2"
            shift 2
            ;;
        --datastore)
            DATASTORE_NAME="$2"
            shift 2
            ;;
        --url)
            URL="$2"
            shift 2
            ;;
        -U|--username)
            USERNAME="$2"
            shift 2
            ;;
        -P|--password)
            PASSWORD="$2"
            shift 2
            ;;
        --folder)
            DATASTORE_FOLDER="$2"
            shift 2
            ;;
        *)
            print_message error "Unknown parameter passed: $1"
            exit 1
            ;;
    esac
done

# --- Interactive Prompts (if arguments or env vars are not provided) ---

# Check for ISO file path.
if [[ -z "$ISO_FILE_PATH" ]]; then
    select_iso
fi

# Set variables from environment variables if not set by flags.
if [[ -z "$URL" ]] && [[ -n "$GOVC_URL" ]]; then URL="$GOVC_URL"; fi
if [[ -z "$USERNAME" ]] && [[ -n "$GOVC_USERNAME" ]]; then USERNAME="$GOVC_USERNAME"; fi
if [[ -z "$PASSWORD" ]] && [[ -n "$GOVC_PASSWORD" ]]; then PASSWORD="$GOVC_PASSWORD"; fi
if [[ -z "$DATASTORE_NAME" ]] && [[ -n "$GOVC_DATASTORE" ]]; then DATASTORE_NAME="$GOVC_DATASTORE"; fi
if [[ -z "$DATASTORE_FOLDER" ]] && [[ -n "$GOVC_DATASTORE_FOLDER" ]]; then DATASTORE_FOLDER="$GOVC_DATASTORE_FOLDER"; fi


# Prompt for values if they are still not set.
if [[ -z "$URL" ]]; then
    read -rp "$(print_message info "Enter the vCenter URL [Default: https://vcenter.example.com]: ")" URL
    if [[ -z "$URL" ]]; then URL="https://vcenter.example.com"; fi
fi

if [[ -z "$USERNAME" ]]; then
    read -rp "$(print_message info "Enter your vCenter username: ")" USERNAME
fi

if [[ -z "$PASSWORD" ]]; then
    read -rsp "$(print_message info "Enter your vCenter password: ")" PASSWORD
    echo
fi

# Set the GOVC environment variables.
export GOVC_URL="$URL"
export GOVC_USERNAME="$USERNAME"
export GOVC_PASSWORD="$PASSWORD"
export GOVC_DATASTORE="$DATASTORE_NAME"
export GOVC_INSECURE="true"

# Check for datastore folder.
if [[ -z "$DATASTORE_FOLDER" ]]; then
    get_input "Enter the target folder in the datastore" "$DEFAULT_DATASTORE_FOLDER" "DATASTORE_FOLDER"
fi

# --- Execution ---

print_message info "Validating credentials and connection to vCenter at $URL..."

# Use a simple govc command to test the connection and credentials.
govc about &> /dev/null

print_message info "Connection successful. Proceeding with upload..."

# Check if the target folder exists on the datastore and create it if not.
print_message info "Checking for datastore folder '$DATASTORE_FOLDER' and creating if necessary..."
govc datastore.mkdir -ds "$DATASTORE_NAME" "$DATASTORE_FOLDER" &>/dev/null || true

# Construct the full datastore path for the upload.
UPLOAD_PATH="$DATASTORE_FOLDER/$(basename "$ISO_FILE_PATH")"

print_message info "Uploading '$(basename "$ISO_FILE_PATH")' to vSphere datastore '$DATASTORE_NAME'..."
print_message info "Target path: '$UPLOAD_PATH'"

# Perform the upload using govc.
govc datastore.upload -ds "$DATASTORE_NAME" "$ISO_FILE_PATH" "$UPLOAD_PATH"

print_message info "Upload complete!"
