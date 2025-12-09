#!/usr/bin/env bash
scriptVersion="1.1"
scriptName="Radarr-Invalid-Movie-Auto-Cleaner"
dockerLogPath="/config/logs"

settings () {
  log "Import Script Settings..."
  source /config/settings.conf
  arrUrl="$radarrUrl"
  arrApiKey="$radarrApiKey"
}

logfileSetup () {
  logFileName="$scriptName-$(date +"%Y_%m_%d_%I_%M_%p").txt"

  if [ ! -d "$dockerLogPath" ]; then
    mkdir -p "$dockerLogPath"
    chmod 777 "$dockerLogPath"
  fi

  if find "$dockerLogPath" -type f -iname "$scriptName-*.txt" | read; then
    # Keep only the last 5 log files for 6 active log files at any given time...
    rm -f $(ls -1t $dockerLogPath/$scriptName-* | tail -n +5)
    # delete log files older than 5 days
    find "$dockerLogPath" -type f -iname "$scriptName-*.txt" -mtime +5 -delete
  fi
  
  if [ ! -f "$dockerLogPath/$logFileName" ]; then
    echo "" > "$dockerLogPath/$logFileName"
    chmod 666 "$dockerLogPath/$logFileName"
  fi
}

log () {
  m_time=`date "+%F %T"`
  echo $m_time" :: $scriptName (v$scriptVersion) :: "$1
  echo $m_time" :: $scriptName (v$scriptVersion) :: "$1 >> "$dockerLogPath/$logFileName"
}

verifyConfig () {

  if [ "$enableInvalidMoviesAutoCleaner" != "true" ]; then
	log "Script is not enabled, enable by setting enableInvalidMoviesAutoCleaner to \"true\" by modifying the \"/config/extended.conf\" config file..."
	log "Sleeping (infinity)"
	sleep infinity
  fi

}

InvalidMovieAutoCleanerProcess () {
  
    # Get invalid series tmdbid id's
    movieTmdbid="$(curl -s --header "X-Api-Key:"$arrApiKey --request GET  "$arrUrl/api/v3/health" | jq -r '.[] | select(.source=="RemovedMovieCheck") | select(.type=="error")' | grep -o 'tmdbid [0-9]*' | grep -o '[[:digit:]]*')"
   
    if [ -z "$movieTmdbid" ]; then
        log "No invalid movies (tmdbid) reported by Radarr health check, skipping..."
        return
    fi

  
    # Process each invalid series tmdb id
    moviesData="$(curl -s --header "X-Api-Key:"$arrApiKey --request GET  "$arrUrl/api/v3/movie")"
    for tmdbid in $(echo $movieTmdbid); do
        movieData="$(echo "$moviesData" | jq -r ".[] | select(.tmdbId==$tmdbid)")"
        movieId="$(echo "$movieData" | jq -r .id)"
        movieTitle="$(echo "$movieData" | jq -r .title)"
        moviePath="$(echo "$movieData" | jq -r .path)"
      
        log "$movieId :: $movieTitle :: $moviePath :: Removing and deleting invalid movie (tmdbid: $tmdbid) based on Radarr Health Check error..."
        # Send command to Sonarr to delete series and files
        arrCommand=$(curl -s --header "X-Api-Key:"$arrApiKey --request DELETE "$arrUrl/api/v3/movie/$movieId?deleteFiles=true")
      
    done

}

for (( ; ; )); do
	let i++
	logfileSetup
  log "Starting..."
  settings
  verifyConfig
  if [ ! -z "$radarrUrl" ]; then
    if [ ! -z "$radarrApiKey" ]; then
	    InvalidMovieAutoCleanerProcess
    else
      log "ERROR :: Skipping Radarr, missing API Key..."
    fi
  else
    log "ERROR :: Skipping Radarr, missing URL..."
  fi
	log "Script sleeping for $invalidMoviesAutoCleanerScriptInterval..."
	sleep $invalidMoviesAutoCleanerScriptInterval
done

exit
