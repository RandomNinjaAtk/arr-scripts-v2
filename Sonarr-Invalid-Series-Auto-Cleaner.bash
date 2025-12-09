#!/usr/bin/env bash
scriptVersion="1.0"
scriptName="Sonarr-Invalid-Series-Auto-Cleaner"
dockerLogPath="/config/logs"

settings () {
  log "Import Script Settings..."
  source /config/settings.conf
  arrUrl="$sonarrUrl"
  arrApiKey="$sonarrApiKey"
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

  if [ "$enableInvalidSeriesAutoCleaner" != "true" ]; then
	log "Script is not enabled, enable by setting enableInvalidSeriesAutoCleaner to \"true\" by modifying the \"/config/extended.conf\" config file..."
	log "Sleeping (infinity)"
	sleep infinity
  fi

  if [ -z "$invalidSeriesAutoCleanerScriptInterval" ]; then
    invalidSeriesAutoCleanerScriptInterval="1h"
  fi
}


InvalidAutoCleanerProcess () {
  
  # Get invalid series tvdb id's
  seriesTvdbId="$(curl -s --header "X-Api-Key:"$arrApiKey --request GET  "$arrUrl/api/v3/health" | jq -r '.[] | select(.source=="RemovedSeriesCheck") | select(.type=="error")' | grep "message" | grep -o '[[:digit:]]*')"
  
  if [ -z "$seriesTvdbId" ]; then
    log "No invalid series (tvdbid) reported by Sonarr health check, skipping..."
    return
  fi
  
  # Process each invalid series tvdb id
  for tvdbId in $(echo $seriesTvdbId); do
      seriesData="$(curl -s --header "X-Api-Key:"$arrApiKey --request GET  "$arrUrl/api/v3/series" | jq -r ".[] | select(.tvdbId==$tvdbId)")"
      seriesId="$(echo "$seriesData" | jq -r .id)"
      seriesTitle="$(echo "$seriesData" | jq -r .title)"
      seriesPath="$(echo "$seriesData" | jq -r .path)"
      
      log "$seriesId :: $seriesTitle :: $seriesPath :: Removing and deleting invalid Series (tvdbId: $tvdbId) based on Sonarr Health Check error..."
  
      # Send command to Sonarr to delete series and files
      arrCommand=$(curl -s --header "X-Api-Key:"$arrApiKey --request DELETE "$arrUrl/api/v3/series/$seriesId?deleteFiles=true")
      
  done
}

for (( ; ; )); do
	let i++
	logfileSetup
    log "Starting..."
    settings
    verifyConfig
    if [ ! -z "$arrUrl" ]; then
        if [ ! -z "$arrApiKey" ]; then
            InvalidAutoCleanerProcess
        else
            log "ERROR :: Skipping Sonarr, missing API Key..."
        fi
    else
        log "ERROR :: Skipping Sonarr, missing URL..."
    fi
	log "Script sleeping for $invalidSeriesAutoCleanerScriptInterval..."
	sleep $invalidSeriesAutoCleanerScriptInterval
done

exit
