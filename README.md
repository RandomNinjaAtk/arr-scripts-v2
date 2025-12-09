# arr-scripts-v2

This project is my own personal documenation for various scripts I've written to improve and further automate the usage of the ARR suite of apps. Support is not guaranteed, scripts are provided as-is...


## Installation

### Container Setup

#### docker-compose (example)
```
services:
  arr-scripts:
    image: lscr.io/linuxserver/alpine:3.23
    container_name: arr-scripts
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Etc/UTC
    volumes:
      - /path/to/arr-scripts/config:/config
      - /path/to/arr-scripts/config/custom-services.d:/custom-services.d
      - /path/to/arr-scripts/config/custom-cont-init.d:/custom-cont-init.d #optional
    restart: unless-stopped
```

### unraid (example)
<img width="777" height="605" alt="image" src="https://github.com/user-attachments/assets/da747920-57f8-42fc-b77d-26910fa9b068" />

### Script Download and Configuration

1. Download [settings.conf](https://github.com/RandomNinjaAtk/arr-scripts-v2/blob/main/settings.conf) and place it into: `/config` folder
2. Download any of the following scripts and place them into `/custom-services.d` folder
   - [Queue-Cleaner.bash](https://github.com/RandomNinjaAtk/arr-scripts-v2/blob/main/Queue-Cleaner.bash)
     - Script removes downloads that are stuck in queue because they cannot auto-import without intervention
   - [Radarr-Invalid-Movie-Auto-Cleaner.bash](https://github.com/RandomNinjaAtk/arr-scripts-v2/blob/main/Radarr-Invalid-Movie-Auto-Cleaner.bash)
     - Script removes invalid movies that are reported by Radarr... 
   - [Radarr-UnmappedFolderCleaner.bash](https://github.com/RandomNinjaAtk/arr-scripts-v2/blob/main/Radarr-UnmappedFolderCleaner.bash)
     - Script removes/deletes unmapped folders reported by Radarr...
     - Script requires mapping a volume that matches Radarr's configuration for stored files... 
   - [Sonarr-Invalid-Series-Auto-Cleaner.bash](https://github.com/RandomNinjaAtk/arr-scripts-v2/blob/main/Sonarr-Invalid-Series-Auto-Cleaner.bash)
     - Script removes invalid series that are reported by Sonarr...
   - [Sonarrr-UnmappedFolderCleaner.bash](https://github.com/RandomNinjaAtk/arr-scripts-v2/blob/main/Sonarr-UnmappedFolderCleaner.bash)
     - Script removes/deletes unmapped folders reported by Sonarr...
     - Script requires mapping a volume that matches Sonarr's configuration for stored files... 
3. Modify edit [settings.conf](https://github.com/RandomNinjaAtk/arr-scripts-v2/blob/main/settings.conf) (`/config/settings.conf`) with your appropriate settings
4. Start or Restart the container

## Monitoring
- Logs will be generated for each script and be located in the `/config/logs` folder.
- You can also monitor the contairs logs to see the scripts logging output live...

## Support Info
<strong>Scripts are provided as-is...</strong>

Generally, if a script works one time, it will work everytime, that is the nature of scripts... So if you're experiencing an issue that has not been previously reported and is more likely a technical problem of some sort, it is more than likely caused by user error...

Please note that use of arr-scripts is not supported by the Arr app's community. The scripts do not modify the software/code of the Arr app, all changes to the Arr app are implemented using publicly available API calls.
