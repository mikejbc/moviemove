#!/bin/bash

# Movie Organizer Script with mnamer
# Monitors SMB share download folder and organizes movies using mnamer
# Designed to run as a Linux daemon process

# Configuration - EDIT THESE PATHS TO MATCH YOUR SETUP
SMB_DOWNLOAD_FOLDER="/mnt/smb-share/downloads"
MOVIES_DESTINATION="/mnt/smb-share/movies"
LOG_FILE="/var/log/movie_organizer.log"
PID_FILE="/var/run/movie_organizer.pid"
LOCK_FILE="/tmp/movie_organizer.lock"

# mnamer configuration
MNAMER_CONFIG="/etc/movie_organizer/mnamer.json"
MNAMER_CACHE_DIR="/var/cache/movie_organizer"

# Movie file extensions to process
MOVIE_EXTENSIONS="mp4|mkv|avi|mov|wmv|flv|webm|m4v|mp2|mpg|mpeg|m2v"

# Daemon configuration
DAEMON_USER="movieorg"
DAEMON_GROUP="movieorg"
SCANNER_INTERVAL=60  # seconds between scans
MAX_LOG_SIZE=10485760  # 10MB in bytes

# Function to log messages
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Function to extract movie title and year from filename
extract_movie_info() {
    local filename="$1"
    
    # Remove file extension
    local basename="${filename%.*}"
    
    # Try to extract year (4 digits between 1900-2099)
    local year=$(echo "$basename" | grep -oE '\b(19|20)[0-9]{2}\b' | tail -1)
    
    # Extract title (everything before the year, cleaned up)
    local title=""
    if [[ -n "$year" ]]; then
        title=$(echo "$basename" | sed -E "s/(.*)$year.*/\1/" | sed -E 's/[._-]+/ /g' | sed 's/^ *//g' | sed 's/ *$//g')
    else
        # If no year found, use the whole basename as title
        title=$(echo "$basename" | sed -E 's/[._-]+/ /g' | sed 's/^ *//g' | sed 's/ *$//g')
        year=""
    fi
    
    # Clean up title - remove common unwanted parts
    title=$(echo "$title" | sed -E 's/\b(720p|1080p|4K|HDTV|BluRay|BRRip|DVDRip|WEBRip|YIFY|x264|x265|H264|H265)\b//gi')
    title=$(echo "$title" | sed 's/^ *//g' | sed 's/ *$//g')
    
    echo "$title|$year"
}

# Function to create proper movie name
create_movie_name() {
    local title="$1"
    local year="$2"
    local extension="$3"
    
    if [[ -n "$year" ]]; then
        echo "${title} (${year}).${extension}"
    else
        echo "${title}.${extension}"
    fi
}

# Function to create folder name
create_folder_name() {
    local title="$1"
    local year="$2"
    
    if [[ -n "$year" ]]; then
        echo "${title} (${year})"
    else
        echo "${title}"
    fi
}

# Function to find next available version number
find_next_version() {
    local folder_path="$1"
    local base_name="$2"
    local extension="$3"
    
    local version=2
    local versioned_name
    
    while true; do
        if [[ "$base_name" =~ \([0-9]{4}\)$ ]]; then
            # Has year in parentheses
            versioned_name="${base_name% (*)} (${base_name##* (} - ver${version}.${extension}"
        else
            # No year
            versioned_name="${base_name} - ver${version}.${extension}"
        fi
        
        if [[ ! -f "$folder_path/$versioned_name" ]]; then
            echo "$versioned_name"
            return
        fi
        ((version++))
    done
}

# Function to use mnamer to rename and organize movie
process_movie_with_mnamer() {
    local source_file="$1"
    local filename=$(basename "$source_file")
    
    log_message "Processing with mnamer: $filename"
    
    # Create temporary directory for mnamer processing
    local temp_dir="$MNAMER_CACHE_DIR/temp/$(date +%s)"
    mkdir -p "$temp_dir"
    
    # Copy file to temp directory for processing
    if ! cp "$source_file" "$temp_dir/"; then
        log_message "ERROR: Failed to copy $filename to temp directory"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Run mnamer on the file (use --config-path for newer versions)
    local mnamer_output
    if mnamer_output=$(mnamer --config-path="$MNAMER_CONFIG" --batch --no-overwrite "$temp_dir/$filename" 2>&1); then
        log_message "mnamer processing successful for $filename"
        log_message "mnamer output: $mnamer_output"
        
        # Find the renamed file
        local renamed_file=$(find "$temp_dir" -name "*" -type f | grep -v "$filename" | head -1)
        
        if [[ -n "$renamed_file" ]] && [[ -f "$renamed_file" ]]; then
            # mnamer successfully renamed the file
            local new_filename=$(basename "$renamed_file")
            log_message "File renamed by mnamer to: $new_filename"
            
            # Move to final destination with version handling
            if move_to_final_destination "$renamed_file" "$source_file"; then
                rm -rf "$temp_dir"
                return 0
            fi
        else
            # mnamer didn't rename, use fallback
            log_message "mnamer didn't rename file, using fallback method"
            rm -rf "$temp_dir"
            process_movie_fallback "$source_file"
            return $?
        fi
    else
        log_message "ERROR: mnamer failed for $filename: $mnamer_output"
        rm -rf "$temp_dir"
        process_movie_fallback "$source_file"
        return $?
    fi
    
    rm -rf "$temp_dir"
    return 1
}

# Function to move file to final destination with version handling
move_to_final_destination() {
    local renamed_file="$1"
    local original_file="$2"
    local filename=$(basename "$renamed_file")
    local extension="${filename##*.}"
    local basename_no_ext="${filename%.*}"
    
    # Create folder based on movie name
    local folder_name="$basename_no_ext"
    local destination_folder="$MOVIES_DESTINATION/$folder_name"
    local destination_file="$destination_folder/$filename"
    
    # Create destination folder
    mkdir -p "$destination_folder"
    log_message "Created/verified folder: $folder_name"
    
    # Handle version conflicts
    if [[ -f "$destination_file" ]]; then
        log_message "File already exists, finding version number..."
        local versioned_name=$(find_next_version "$destination_folder" "$basename_no_ext" "$extension")
        destination_file="$destination_folder/$versioned_name"
        log_message "Using versioned name: $versioned_name"
    fi
    
    # Move the renamed file to final destination
    if mv "$renamed_file" "$destination_file"; then
        # Remove original file
        rm -f "$original_file"
        log_message "SUCCESS: Moved $filename to $folder_name/$(basename "$destination_file")"
        return 0
    else
        log_message "ERROR: Failed to move $filename to final destination"
        return 1
    fi
}

# Fallback function using original logic
process_movie_fallback() {
    local source_file="$1"
    local filename=$(basename "$source_file")
    local extension="${filename##*.}"
    
    log_message "Using fallback processing for: $filename"
    
    # Extract movie info
    local movie_info=$(extract_movie_info "$filename")
    local title=$(echo "$movie_info" | cut -d'|' -f1)
    local year=$(echo "$movie_info" | cut -d'|' -f2)
    
    if [[ -z "$title" ]]; then
        log_message "ERROR: Could not extract title from $filename"
        return 1
    fi
    
    # Create folder and file names
    local folder_name=$(create_folder_name "$title" "$year")
    local movie_name=$(create_movie_name "$title" "$year" "$extension")
    local destination_folder="$MOVIES_DESTINATION/$folder_name"
    local destination_file="$destination_folder/$movie_name"
    
    # Create destination folder if it doesn't exist
    if [[ ! -d "$destination_folder" ]]; then
        mkdir -p "$destination_folder"
        log_message "Created folder: $folder_name"
    fi
    
    # Check if file already exists
    if [[ -f "$destination_file" ]]; then
        log_message "File already exists, finding version number..."
        local base_name="${movie_name%.*}"
        local versioned_name=$(find_next_version "$destination_folder" "$base_name" "$extension")
        destination_file="$destination_folder/$versioned_name"
        log_message "Using versioned name: $versioned_name"
    fi
    
    # Move the file
    if mv "$source_file" "$destination_file"; then
        log_message "SUCCESS: Moved $filename to $folder_name/$(basename "$destination_file")"
        return 0
    else
        log_message "ERROR: Failed to move $filename"
        return 1
    fi
}

# Function to scan and process new movies
scan_and_process() {
    log_message "Scanning for new movies in: $SMB_DOWNLOAD_FOLDER"
    
    if [[ ! -d "$SMB_DOWNLOAD_FOLDER" ]]; then
        log_message "ERROR: Download folder not found: $SMB_DOWNLOAD_FOLDER"
        return 1
    fi
    
    if [[ ! -d "$MOVIES_DESTINATION" ]]; then
        log_message "Creating movies destination folder: $MOVIES_DESTINATION"
        mkdir -p "$MOVIES_DESTINATION"
    fi
    
    local processed_count=0
    
    # Find movie files and process them
    while IFS= read -r -d '' file; do
        if [[ -f "$file" ]]; then
            if process_movie_with_mnamer "$file"; then
                ((processed_count++))
            fi
        fi
    done < <(find "$SMB_DOWNLOAD_FOLDER" -type f \( -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.avi" -o -iname "*.mov" -o -iname "*.wmv" -o -iname "*.flv" -o -iname "*.webm" -o -iname "*.m4v" -o -iname "*.mp2" -o -iname "*.mpg" -o -iname "*.mpeg" -o -iname "*.m2v" \) -print0)
    
    log_message "Processed $processed_count movies"
}

# Function to show usage
show_usage() {
    echo "Movie Organizer Script"
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help     Show this help message"
    echo "  -c, --config   Show current configuration"
    echo "  -t, --test     Test mode - show what would be done without moving files"
    echo "  -w, --watch    Watch mode - continuously monitor for new files"
    echo ""
    echo "Before running, edit the script to set your SMB paths:"
    echo "  SMB_DOWNLOAD_FOLDER: $SMB_DOWNLOAD_FOLDER"
    echo "  MOVIES_DESTINATION:  $MOVIES_DESTINATION"
}

# Function to show configuration
show_config() {
    echo "Current Configuration:"
    echo "  Download folder: $SMB_DOWNLOAD_FOLDER"
    echo "  Movies folder:   $MOVIES_DESTINATION"
    echo "  Log file:        $LOG_FILE"
    echo "  Supported extensions: $MOVIE_EXTENSIONS"
}

# Main script logic
case "$1" in
    -h|--help)
        show_usage
        exit 0
        ;;
    -c|--config)
        show_config
        exit 0
        ;;
    -t|--test)
        echo "TEST MODE - No files will be moved"
        # Add test mode logic here if needed
        scan_and_process
        ;;
    -w|--watch)
        echo "Starting watch mode - Press Ctrl+C to stop"
        log_message "Starting watch mode"
        while true; do
            scan_and_process
            sleep 60  # Check every minute
        done
        ;;
    "")
        # Default: single scan
        scan_and_process
        ;;
    *)
        echo "Unknown option: $1"
        show_usage
        exit 1
        ;;
esac

log_message "Script completed"
