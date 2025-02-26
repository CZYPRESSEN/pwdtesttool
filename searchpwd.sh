#!/bin/bash

# Colored output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

PASSWORDS_DIR="/snap/seclists/current/Passwords"
FIRST_RUN=1
HISTORY_FILE="$HOME/.password_finder_history"

# Clear screen function
clear_screen() {
    clear
}

# Display header
show_header() {
    clear_screen
    echo -e "${CYAN}======================================${NC}"
    echo -e "${CYAN}       Password Dictionary Tool        ${NC}"
    echo -e "${CYAN}======================================${NC}"
    echo -e "${YELLOW}Directory: ${PASSWORDS_DIR}${NC}"
    echo -e "${CYAN}--------------------------------------${NC}"
    echo
}

# Search password function
search_password() {
    local PASSWORD="$1"
    local FOUND=0

    echo -e "${BLUE}Searching for password: \"${PASSWORD}\"${NC}"
    echo

    # Get list of all files
    local FILE_LIST=$(find "$PASSWORDS_DIR" -type f)
    
    # Iterate through all files
    for file in $FILE_LIST; do
        # Show progress
        echo -ne "${YELLOW}Checking file: ${file}${NC}\r"
        
        # Check if the file is readable
        if [ -r "$file" ]; then
            # Check file extension
            if [[ "$file" == *.bz2 ]]; then
                # Use bzgrep for bz2 files
                if bzgrep -q -x "$PASSWORD" "$file" 2>/dev/null; then
                    echo -e "\n${GREEN}Password matched! In file: ${YELLOW}$file${NC}"
                    echo -e "${GREEN}Result: yes${NC}"
                    return 0
                fi
            else
                # Try using grep for regular files
                if grep -q -x "$PASSWORD" "$file" 2>/dev/null; then
                    echo -e "\n${GREEN}Password matched! In file: ${YELLOW}$file${NC}"
                    echo -e "${GREEN}Result: yes${NC}"
                    return 0
                fi
            fi
        fi
    done

    # If execution reaches here, no match was found
    echo -e "\n${RED}Password \"${PASSWORD}\" not found${NC}"
    echo -e "${RED}Result: no${NC}"
    return 1
}

# Main loop
main_loop() {
    show_header
    
    # Ensure history file exists
    touch "$HISTORY_FILE"
    
    # Enable readline functionality
    if [ -n "$BASH_VERSION" ]; then
        # If using bash, use built-in history functionality
        HISTFILE="$HISTORY_FILE"
        history -c
        history -r
        set -o emacs  # Use emacs-style line editing
    fi
    
    # Infinite loop for queries
    while true; do
        # Use read's -e option to enable readline functionality
        read -e -p "Enter the password to search for: " password
        
        # Add command to history
        if [ -n "$password" ]; then
            history -s "$password"
            history -w
        else
            echo -e "${RED}Error: Password cannot be empty${NC}"
            continue
        fi
        
        search_password "$password"
        
        # Show exit hint only after the first query
        if [ $FIRST_RUN -eq 1 ]; then
            echo -e "\n${YELLOW}Hint: Use the up/down arrows to browse history, press Ctrl+C to exit at any time${NC}"
            FIRST_RUN=0
        fi
        
        echo
    done
}

# Trap Ctrl+C
trap 'echo -e "\n${YELLOW}Thank you for using the Password Dictionary Tool! Goodbye!${NC}"; exit 0' INT

# Check if readline is supported
if ! read -e </dev/null 2>/dev/null; then
    echo -e "${RED}Warning: Your system does not support command line editing. Basic mode will be used.${NC}"
    sleep 2
fi

# Start the main loop
main_loop
