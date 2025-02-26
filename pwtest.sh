#!/bin/bash

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration parameters
PASSWORDS_DIR="/snap/seclists/current/Passwords"
USER="root"  # Test username
SERVER=""     # Server address (to be filled)
PORT="22"     # SSH port
TIMEOUT=5     # Connection timeout (seconds)
MAX_TRIES=100000000   # Maximum number of failed attempts (to avoid locking)

# Clear screen function
clear_screen() {
    clear
}

# Display header
show_header() {
    clear_screen
    echo -e "${CYAN}======================================${NC}"
    echo -e "${CYAN}       SSH Security Testing Tool      ${NC}"
    echo -e "${CYAN}======================================${NC}"
    echo -e "${YELLOW}Target: ${USER}@${SERVER}:${PORT}${NC}"
    echo -e "${CYAN}--------------------------------------${NC}"
    echo
}

# Validate SSH connection
test_ssh_password() {
    local password="$1"
    
    # Use sshpass for non-interactive SSH password attempts
    if command -v sshpass >/dev/null 2>&1; then
        sshpass -p "$password" ssh -o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=$TIMEOUT $USER@$SERVER -p $PORT exit 2>/dev/null
        return $?
    else
        # If sshpass is not available, use expect script
        if command -v expect >/dev/null 2>&1; then
            expect -c "
                set timeout $TIMEOUT
                spawn ssh -o StrictHostKeyChecking=no $USER@$SERVER -p $PORT
                expect {
                    \"*?assword:*\" { send \"$password\r\"; exp_continue }
                    \"*?denied*\" { exit 1 }
                    \"*\$ \" { exit 0 }
                    timeout { exit 2 }
                }
            " >/dev/null 2>&1
            return $?
        else
            echo -e "${RED}Error: sshpass or expect is required to run this script${NC}"
            echo -e "${YELLOW}You can install them using the following commands:${NC}"
            echo -e "${GREEN}sudo apt-get install sshpass${NC} or ${GREEN}sudo apt-get install expect${NC}"
            exit 1
        fi
    fi
}

# Main function
main() {
    show_header
    
    # Check server address
    if [ -z "$SERVER" ]; then
        read -p "Please enter the target server IP address: " SERVER
        if [ -z "$SERVER" ]; then
            echo -e "${RED}Error: Server address is required${NC}"
            exit 1
        fi
    fi
    
    echo -e "${YELLOW}Warning: This script is only for authorized security testing!${NC}"
    echo -e "${YELLOW}Excessive failed attempts may result in account lockout or trigger alarms.${NC}"
    echo
    read -p "Do you want to continue? (y/n): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${RED}Operation canceled${NC}"
        exit 0
    fi
    
    echo
    echo -e "${BLUE}Starting common weak password testing...${NC}"
    
    # Common weak passwords quick test
    common_passwords=("password" "123456" "admin" "root" "123" "Password" "P@ssw0rd" "admin123" "root123" "qwerty" "password123" "1234" "12345" "$USER")
    
    for password in "${common_passwords[@]}"; do
        printf "${YELLOW}%-60s${NC}\r" "Trying password: ${password}"
        
        if test_ssh_password "$password"; then
            echo -e "\n${RED}Insecure password found: [${password}]${NC}"
            echo -e "${RED}It is recommended to change the SSH password immediately!${NC}"
            exit 0
        fi
    done
    
    echo -e "\n${GREEN}Common weak password testing completed, no matches found${NC}"
    echo
    
    # Ask if to continue with dictionary testing
    read -p "Do you want to continue with dictionary-based detailed testing? (y/n): " continue_test
    if [[ ! "$continue_test" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Testing completed${NC}"
        exit 0
    fi
    
    echo
    echo -e "${BLUE}Starting dictionary-based password testing...${NC}"
    echo -e "${YELLOW}Note: This may take a long time, testing will automatically stop after ${MAX_TRIES} attempts to avoid account lockout${NC}"
    echo
    
    # Recursively find all dictionary files
    echo -e "${BLUE}Searching for all available password dictionaries...${NC}"
    dict_files=$(find "$PASSWORDS_DIR" -type f -name "*.txt" | sort)
    
    # Count the number of dictionary files found
    dict_count=$(echo "$dict_files" | wc -l)
    echo -e "${GREEN}Found ${dict_count} password dictionary files${NC}"
    echo
    
    tries=0
    found=0
    
    for dict_path in $dict_files; do
        # Extract relative path for display
        relative_path=${dict_path#$PASSWORDS_DIR/}
        
        echo -e "${BLUE}Using dictionary: ${relative_path}${NC}"
        
        while IFS= read -r password || [ -n "$password" ]; do
            # Skip empty lines and comments
            if [ -z "$password" ] || [[ "$password" == \#* ]]; then
                continue
            fi
            
            # Clear current line and display the password being tried
            printf "${YELLOW}%-60s${NC}\r" "Trying password: ${password}"
            
            if test_ssh_password "$password"; then
                echo -e "\n${RED}Insecure password found: [${password}]${NC}"
                echo -e "${RED}It is recommended to change the SSH password immediately!${NC}"
                found=1
                break 2
            fi
            
            ((tries++))
            
            # Display current progress
            if [ $((tries % 10)) -eq 0 ]; then
                printf "${YELLOW}%-60s${NC}\r" "Attempted ${tries}/${MAX_TRIES} passwords"
            fi
            
            # Limit the number of attempts
            if [ $tries -ge $MAX_TRIES ]; then
                echo -e "\n${YELLOW}Reached maximum attempts (${MAX_TRIES}), stopping testing to avoid account lockout${NC}"
                break 2
            fi
            
            # Short delay after each attempt to avoid triggering anti-brute-force mechanisms
            sleep 0.01
        done < "$dict_path"
    done
    
    if [ $found -eq 0 ]; then
        echo -e "\n${GREEN}Testing completed, no weak passwords found${NC}"
        echo -e "${GREEN}Your SSH password is relatively secure${NC}"
    fi
}

# Capture Ctrl+C
trap 'echo -e "\n${YELLOW}Testing interrupted${NC}"; exit 0' INT

# Check dependencies
if ! command -v ssh >/dev/null 2>&1; then
    echo -e "${RED}Error: SSH client is not installed${NC}"
    exit 1
fi

if ! command -v sshpass >/dev/null 2>&1 && ! command -v expect >/dev/null 2>&1; then
    echo -e "${RED}Error: sshpass or expect is required to run this script${NC}"
    echo -e "${YELLOW}You can install them using the following commands:${NC}"
    echo -e "${GREEN}sudo apt-get install sshpass${NC} or ${GREEN}sudo apt-get install expect${NC}"
    exit 1
fi

# Execute main function
main
