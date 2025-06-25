# Movie Organizer

A shell script that monitors SMB share download folders and automatically organizes movies using `mnamer` for proper naming conventions.

## Features

- Monitors SMB share download folder for new movie files
- Uses `mnamer` for intelligent movie renaming and metadata lookup
- Organizes movies into folders by title and year
- Handles multiple versions of the same movie
- Runs as a Linux daemon process
- Comprehensive logging

## Prerequisites

- `mnamer` - Install with `pip install mnamer`
- Access to SMB share with download and movies folders
- Linux environment for daemon operation

## Configuration

Edit the following variables in `movie_organizer.sh`:

```bash
SMB_DOWNLOAD_FOLDER="/mnt/smb-share/downloads"
MOVIES_DESTINATION="/mnt/smb-share/movies"
LOG_FILE="/var/log/movie_organizer.log"
```

## Usage

```bash
# Run once to process current files
./movie_organizer.sh

# Test mode (show what would be done)
./movie_organizer.sh -t

# Watch mode (continuous monitoring)
./movie_organizer.sh -w

# Show configuration
./movie_organizer.sh -c

# Show help
./movie_organizer.sh -h
```

## Installation as Linux Service

1. Copy script to `/usr/local/bin/`
2. Create systemd service file
3. Enable and start the service

## File Structure

```
Movie Title (Year)/
├── Movie Title (Year).mp4
├── Movie Title (Year) - ver2.mkv  # If multiple versions exist
└── ...
```

## Supported Formats

- mp4, mkv, avi, mov, wmv, flv, webm, m4v
- mp2, mpg, mpeg, m2v

## Logging

All operations are logged to the configured log file with timestamps.
