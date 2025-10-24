#!/bin/bash

API_URL="https://start.spring.io/metadata/client"
DOWNLOAD_BASE_URL="https://start.spring.io/starter.zip?"
METADATA_FILE="initializr_metadata.json"

# --- Variables ---
QUERY_PARAMS=""
DEPENDENCIES=""
EXIT_KEYWORD="0" # press this key to exit the program
SUCCESS_OR_ERROR_MESSAGE="" # Global variable for temporary success/error messages

# --- Color Codes ---
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
CYAN=$'\033[0;36m'
RED=$'\033[0;31m'
NC=$'\033[0m' # No Color

GROUP_ID=""
ARTIFACT_ID=""
BUILD_TYPE=""
LANGUAGE=""
BOOT_VERSION=""
JAVA_VERSION=""
PACKAGING=""
NAME_VALUE=""
PACKAGE_NAME=""
DESCRIPTION_VALUE="Demo project for Spring Boot"

# Function to safely URL-encode a string using jq
url_encode() {
  # Documentation: jq -sRr @uri reliably URL-encodes a string read from standard input.
  echo -n "$1" | jq -sRr @uri
}

# Function to fetch and validate metadata
fetch_metadata() {
  echo -e "${CYAN}Fetching Spring Initializr metadata from ${API_URL}...${NC}"
  if ! curl -s "$API_URL" >"$METADATA_FILE"; then
    echo -e "${RED}Error: Failed to download metadata. Check internet connection.${NC}" >&2
    rm -f "$METADATA_FILE" 2>/dev/null
    exit 1
  fi

  if [ ! -s "$METADATA_FILE" ]; then
    echo -e "${RED}Error: Downloaded metadata file is empty. Check API status.${NC}" >&2
    rm -f "$METADATA_FILE"
    exit 1
  fi
}

# Function to display the current project configuration
show_current_state() {
  echo -e "${YELLOW}====================================================${NC}"
  echo -e "${YELLOW}  CURRENT PROJECT CONFIGURATION ${NC}"
  echo -e "${YELLOW}====================================================${NC}"
  # Display collected fields with friendly labels
  [[ -n "$BUILD_TYPE" ]]    && echo -e "  ${CYAN}Build System: ${GREEN}${BUILD_TYPE}${NC}"
  [[ -n "$LANGUAGE" ]]      && echo -e "  ${CYAN}Language:     ${GREEN}${LANGUAGE}${NC}"
  [[ -n "$BOOT_VERSION" ]]  && echo -e "  ${CYAN}Spring Boot:  ${GREEN}${BOOT_VERSION}${NC}"
  [[ -n "$JAVA_VERSION" ]]  && echo -e "  ${CYAN}Java Version: ${GREEN}${JAVA_VERSION}${NC}"
  [[ -n "$PACKAGING" ]]     && echo -e "  ${CYAN}Packaging:    ${GREEN}${PACKAGING}${NC}"
  [[ -n "$GROUP_ID" ]]      && echo -e "  ${CYAN}Group ID:     ${GREEN}${GROUP_ID}${NC}"
  [[ -n "$ARTIFACT_ID" ]]   && echo -e "  ${CYAN}Artifact ID:  ${GREEN}${ARTIFACT_ID}${NC}"
  [[ -n "$NAME_VALUE" ]]    && echo -e "  ${CYAN}Name:         ${GREEN}${NAME_VALUE}${NC}"
  [[ -n "$PACKAGE_NAME" ]]  && echo -e "  ${CYAN}Package Name: ${GREEN}${PACKAGE_NAME}${NC}"
  # Dependency display is dynamic based on global variable
  [[ -n "$DEPENDENCIES" ]]  && echo -e "  ${CYAN}Dependencies: ${GREEN}${DEPENDENCIES//,/, }${NC}"
  echo -e "${YELLOW}====================================================${NC}\n"
}

# Function to clear screen, show current state, show transient message, and clear message
clear_screen_and_show_state() {
  clear
  show_current_state
  # Display error message if set
  if [[ -n "$SUCCESS_OR_ERROR_MESSAGE" ]]; then
    echo -e "$SUCCESS_OR_ERROR_MESSAGE\n" # Print the message with a newline after it
    SUCCESS_OR_ERROR_MESSAGE=""          # Clear the message for the next loop
  fi
}

# Function to convert variable name (e.g., javaVersion) to human-readable format (Java Version)
format_key() {
  local key="$1"
  # Use awk to insert space before capital letters and capitalize the first letter of the result
  # The substitution s/([A-Z])/ &/g adds a space before every uppercase letter.
  # The substr(toupper($0), 1, 1) toupper(substr($0, 2)) capitalizes the first letter of the whole string.
  echo "$key" | awk '{
        gsub(/([A-Z])/, " &", $0);
        print toupper(substr($0, 1, 1)) substr($0, 2);
    }' | sed 's/ / /g' # Clean up potential extra spaces (e.g., after the first word)
}

# Function to get description
get_description() {
  local field_key="$1"
  local description
  description=$(jq -r ".${field_key}.description" "$METADATA_FILE" 2>/dev/null)

  if [[ "$description" == "null" ]] || [[ -z "$description" ]]; then
    case "$field_key" in
    "type") description="Choose your build system." ;;
    "packaging") description="Select the format for the final executable (Jar or War)." ;;
    "javaVersion") description="The Java version to use for the project." ;;
    "bootVersion") description="The version of Spring Boot to use." ;;
    "language") description="The programming language for the project (Java, Kotlin, or Groovy)." ;;
    *) description="No official description available." ;;
    esac
  fi
  echo "$description"
}

# Function to handle textual fields (e.g., groupId, artifactId)
collect_text_field() {
  local field_key="$1"
  local default_value="$2"
  local description
  description=$(get_description "$field_key")
  local display_key
  display_key=$(format_key "$field_key")

  while true; do
    clear_screen_and_show_state
    echo -e "\n${YELLOW}--- ${display_key} ---${NC}"
    echo -e "${CYAN}Description: ${description}${NC}"
    read -r -p "Enter ${display_key} ${CYAN}(default: $default_value)${NC}: " user_input

    local value="${user_input:-$default_value}"

    # Regex validation for allowed characters (a-z, A-Z, 0-9, ., _, -)
    if [[ "$value" =~ ^[a-zA-Z0-9._-]+$ ]]; then
      if [ "$field_key" == "groupId" ]; then GROUP_ID="$value"; fi
      if [ "$field_key" == "artifactId" ]; then ARTIFACT_ID="$value"; fi
      QUERY_PARAMS+="${field_key}=$(url_encode "$value")&"
      SUCCESS_OR_ERROR_MESSAGE="${GREEN}${display_key} set to: $value${NC}"
      break
    else
      SUCCESS_OR_ERROR_MESSAGE="${RED}Invalid input. Please use letters, numbers, dots, dashes, or underscores only.${NC}"
    fi
  done
}

# Function to handle choice fields with numerical selection
collect_choice_field_numeric() {
  local field_key="$1"
  local description
  description=$(get_description "$field_key")
  local display_key
  display_key=$(format_key "$field_key")

  local options
  options=$(jq -c ".${field_key}.values[]" "$METADATA_FILE" 2>/dev/null)
  local default_id
  default_id=$(jq -r ".${field_key}.default" "$METADATA_FILE")

  # Display options and create an index-to-id mapping
  local index=1
  local id_map=()

  while IFS= read -r value_obj; do
    local id
    local name
    id=$(echo "$value_obj" | jq -r '.id')
    name=$(echo "$value_obj" | jq -r '.name')
    id_map[index]="$id"
    index=$((index + 1))
  done <<<"$options"

  local default_index
  # Find the index of the default value
  for i in "${!id_map[@]}"; do
    if [[ "${id_map[i]}" == "$default_id" ]]; then
      default_index="$i"
      break
    fi
  done

  local selected_id=""
  while true; do
    clear_screen_and_show_state
    echo -e "\n${YELLOW}--- ${display_key} Selection ---${NC}"
    echo -e "${CYAN}Description: ${description}${NC}"
    echo -e "Available options (Select by number):"

    # Re-display options with default marker
    for i in "${!id_map[@]}"; do
      if [[ "${id_map[i]}" == "$default_id" ]]; then
        echo -e "  ${CYAN}${i}) ${id_map[i]} [DEFAULT]${NC}"
      else
        echo -e "  ${i}) ${id_map[i]}"
      fi
    done

    read -r -p "Select option by number (default: $default_index): " user_choice

    local selection="${user_choice:-$default_index}"

    if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -lt "$index" ]; then
      selected_id="${id_map[$selection]}"
    else
      SUCCESS_OR_ERROR_MESSAGE="${RED}Invalid selection. Please enter a number between 1 and $((index - 1)).${NC}"
      continue
    fi

    if [[ -n "$selected_id" ]]; then
      # Store the selected ID in the appropriate state variable
      case "$field_key" in
        "type") BUILD_TYPE="$selected_id" ;;
        "language") LANGUAGE="$selected_id" ;;
        "bootVersion") BOOT_VERSION="$selected_id" ;;
        "javaVersion") JAVA_VERSION="$selected_id" ;;
        "packaging") PACKAGING="$selected_id" ;;
      esac

      QUERY_PARAMS+="${field_key}=$(url_encode "$selected_id")&"
      SUCCESS_OR_ERROR_MESSAGE="${GREEN}${display_key} set to: $selected_id${NC}"
      break
    fi
  done
}

# Function to handle dependency selection loop
collect_dependencies() {
  local groups
  groups=$(jq -c '.dependencies.values[]' "$METADATA_FILE")

  # Outer loop for category selection
  while true; do
    clear_screen_and_show_state

    echo -e "\n${YELLOW}====================================================${NC}"
    echo -e "${YELLOW}  Dependency Selection${NC}"
    echo -e "${YELLOW}====================================================${NC}"
    echo -e "\n${YELLOW}--- Dependency Categories ---${NC}"
    echo -e "  ${CYAN}${EXIT_KEYWORD}) Done (Exit dependency selection)${NC}"

    local cat_index=1
    local cat_map=()

    # Display categories and map index to group object
    while IFS= read -r group_obj; do
      local name
      name=$(echo "$group_obj" | jq -r '.name')
      echo -e "  ${cat_index}) ${name}"
      cat_map[cat_index]="$group_obj"
      cat_index=$((cat_index + 1))
    done <<<"$groups"

    # Ask for category selection
    local cat_choice
    read -r -p "Select a category number (1-$((cat_index - 1))) or $EXIT_KEYWORD to finish: " cat_choice

    if [ "$cat_choice" == "$EXIT_KEYWORD" ]; then
      break # Exit the dependency loop
    fi

    if [[ "$cat_choice" =~ ^[0-9]+$ ]] && [ "$cat_choice" -ge 1 ] && [ "$cat_choice" -lt "$cat_index" ]; then

      local selected_group="${cat_map[$cat_choice]}"
      local group_name
      group_name=$(echo "$selected_group" | jq -r '.name')
      local dependencies_in_group
      dependencies_in_group=$(echo "$selected_group" | jq -c '.values[]')

      # Inner loop for dependency selection within a category
      while true; do
        clear_screen_and_show_state
        echo -e "\n${YELLOW}--- Dependencies in ${group_name} ---${NC}"
        echo -e "  ${CYAN}${EXIT_KEYWORD}) Back to Categories${NC}"

        local dep_index=1
        local dep_map=()

        # Display dependencies and map index to ID
        while IFS= read -r dep_obj; do
          local id
          local name
          id=$(echo "$dep_obj" | jq -r '.id')
          name=$(echo "$dep_obj" | jq -r '.name')
          echo -e "  ${dep_index}) ${name} (${id})"
          dep_map[dep_index]="$id"
          dep_index=$((dep_index + 1))
        done <<<"$dependencies_in_group"

        echo -e "\nType dependency IDs (comma-separated), or select by number."
        local dep_prompt="Select ID(s) or $EXIT_KEYWORD to go back: "
        read -r -p "$dep_prompt" user_input

        if [ "$user_input" == "$EXIT_KEYWORD" ]; then
          break # Back to categories
        fi

        local deps_input="$user_input"
        local process_list=""

        # Check if input is a number that corresponds to an index
        if [[ "$deps_input" =~ ^[0-9]+$ ]] && [ "$deps_input" -ge 1 ] && [ "$deps_input" -lt "$dep_index" ]; then
          # Process as a single numerical selection
          process_list="${dep_map[$deps_input]}"
        else
          # Process as a comma-separated list of IDs
          process_list="$deps_input"
        fi

        # Process the dependency list (from numbers or IDs)
        if [[ -n "$process_list" ]]; then
          local IFS=','
          local valid_deps=""
          local invalid_or_duplicate=""

          for dep_item in $process_list; do
            local trimmed_dep="${dep_item// /}" # Remove spaces
            if [[ -z "$trimmed_dep" ]]; then continue; fi

            # Check if numerical selection is used for a single item
            if [[ "$trimmed_dep" =~ ^[0-9]+$ ]] && [ "$trimmed_dep" -ge 1 ] && [ "$trimmed_dep" -lt "$dep_index" ]; then
              trimmed_dep="${dep_map[$trimmed_dep]}"
            fi

            # Check validity against global metadata AND if it's not already added
            local is_valid
            is_valid=$(jq -r --arg td "$trimmed_dep" '.dependencies.values[] | .values[] | select(.id == $td) | .id' "$METADATA_FILE" 2>/dev/null)

            if [[ -n "$is_valid" ]]; then
              if ! grep -q "\<$trimmed_dep\>" <<<"$DEPENDENCIES"; then
                valid_deps+="${trimmed_dep},"
              else
                invalid_or_duplicate+="${trimmed_dep} (duplicate),"
              fi
            else
              invalid_or_duplicate+="${trimmed_dep} (invalid),"
            fi
          done

          unset IFS

          # Update the global DEPENDENCIES variable
          if [[ -n "$valid_deps" ]]; then
            valid_deps="${valid_deps%,}"
            if [[ -n "$DEPENDENCIES" ]]; then
              DEPENDENCIES+=",${valid_deps}"
            else
              DEPENDENCIES="${valid_deps}"
            fi
            SUCCESS_OR_ERROR_MESSAGE+="${GREEN}Added dependencies: ${valid_deps}${NC}\n"
          fi

          if [[ -n "$invalid_or_duplicate" ]]; then
            invalid_or_duplicate="${invalid_or_duplicate%,}"
            SUCCESS_OR_ERROR_MESSAGE+="${RED}Warning: Skipped dependencies: ${invalid_or_duplicate}${NC}\n"
          fi
        fi
      done
    else
      SUCCESS_OR_ERROR_MESSAGE="${RED}Invalid category selection. Please try again.${NC}"
    fi
  done

  # Add final dependencies to query string
  if [[ -n "$DEPENDENCIES" ]]; then
    QUERY_PARAMS+="dependencies=$(url_encode "$DEPENDENCIES")&"
  fi
}

# Function to ask for final confirmation before download
confirm_download() {
  clear_screen_and_show_state
  echo -e "\n${YELLOW}====================================================${NC}"
  echo -e "${GREEN}PROJECT CONFIGURATION COMPLETE!${NC}"
  echo -e "You are about to download the project with the configuration shown above."
  echo -e "${YELLOW}====================================================${NC}"

  while true; do
    read -r -p "Do you want to proceed with the download? (y/n, default: y): " confirmation
    local choice="${confirmation:-y}"
    case "$choice" in
      [Yy]* ) return 0 ;; # Proceed
      [Nn]* ) return 1 ;; # Cancel
      * )
          SUCCESS_OR_ERROR_MESSAGE="${RED}Please answer 'y' or 'n'.${NC}"
          clear_screen_and_show_state # Re-show immediately
          ;;
    esac
  done
}

# --- Main Execution ---

# Ensure cleanup on exit
trap 'rm -f "$METADATA_FILE" 2>/dev/null' EXIT

fetch_metadata

clear_screen_and_show_state

echo -e "${YELLOW}====================================================${NC}"
echo -e "${YELLOW}  Spring Initializr Bash Project Generator (V3)${NC}"
echo -e "${YELLOW}====================================================${NC}"

# 1. Collect choice fields with numerical selection
collect_choice_field_numeric "type"        # Build Type
collect_choice_field_numeric "language"    # Language
collect_choice_field_numeric "bootVersion" # Spring Boot Version
collect_choice_field_numeric "javaVersion" # Java Version
collect_choice_field_numeric "packaging"   # Packaging Type

# 2. Collect textual fields
collect_text_field "groupId" "com.example"
collect_text_field "artifactId" "demo"

# 3. Auto-generate dependent fields
if [[ -n "$ARTIFACT_ID" ]]; then
  NAME_VALUE="$ARTIFACT_ID" # Store in state variable
  QUERY_PARAMS+="name=$(url_encode "$NAME_VALUE")&"
fi

if [[ -n "$GROUP_ID" ]] && [[ -n "$ARTIFACT_ID" ]]; then
  PACKAGE_NAME="${GROUP_ID}.${ARTIFACT_ID}" # Store in state variable
  QUERY_PARAMS+="packageName=$(url_encode "$PACKAGE_NAME")&"
fi

# Set Description
QUERY_PARAMS+="description=$(url_encode "$DESCRIPTION_VALUE")&"

# 4. Collect dependencies
collect_dependencies

# 5. Final Confirmation and Download
if ! confirm_download; then
  echo -e "\n${CYAN}Download cancelled by user. Exiting.${NC}"
  exit 0
fi

# Remove the trailing '&' from QUERY_PARAMS
FINAL_QUERY="${QUERY_PARAMS%&}"
DOWNLOAD_URL="${DOWNLOAD_BASE_URL}${FINAL_QUERY}"

clear_screen_and_show_state

echo -e "\n${YELLOW}====================================================${NC}"
echo -e "${GREEN}Initiating Download...${NC}"
echo -e "Final Download URL: ${CYAN}${DOWNLOAD_URL}${NC}"
echo -e "${YELLOW}====================================================${NC}"

PROJECT_ZIP="${ARTIFACT_ID:-starter}.zip"
echo -e "\n${CYAN}Downloading project to ${PROJECT_ZIP}...${NC}"

if curl -L -s -o "$PROJECT_ZIP" "$DOWNLOAD_URL"; then
  # Removed success message, only printing final instruction
  echo -e "${GREEN}Success! Project downloaded as ${PROJECT_ZIP} in the current directory.${NC}"
  echo -e "To extract: unzip ${PROJECT_ZIP}"
else
  # Keeping final fatal error print, but modified for conciseness
  echo -e "\n${RED}Download Error! Failed to fetch starter project from ${DOWNLOAD_URL}.${NC}" >&2
  exit 1
fi

exit 0

