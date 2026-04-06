#!/usr/bin/with-contenv bash
scriptVersion="2.2"
scriptName="Lidarr-MusicVideoAutomator"
dockerPath="/config"
arrApp="Lidarr"
InstallDependencies () {
  if apk --no-cache list | grep installed | grep ffmpeg | read; then
    log "Dependencies already installed, skipping..."
  else
    log "Installing script dependencies...."
    apk add  -U --update --no-cache \
        tidyhtml \
        ffmpeg \
        jq \
        xq \
		git \
		opus-tools \
		python3 \
		py3-pip
        libstdc++ \
        mkvtoolnix
    log "done"
    apk add atomicparsley --repository=https://dl-cdn.alpinelinux.org/alpine/edge/testing
    python3 -m pip install tidaler --upgrade --break-system-packages
  fi
}

ConfigureTidalDl () {
    log "Configuring tidal-dl-ng client"
    tidal-dl-ng cfg quality_video 1080
    tidal-dl-ng cfg format_video "{track_title}"
    tidal-dl-ng cfg path_binary_ffmpeg /usr/bin/ffmpeg
    tidal-dl-ng cfg download_base_path "$lidarrMusicVideoTempDownloadPath"
    if [ -f /root/.config/tidal_dl_ng-dev/token.json ]; then
        if cat "/root/.config/tidal_dl_ng-dev/token.json" | grep "null" | read;  then 
            log "tidal-dl-ng requires authentication, authenticate now:"
            log "login manually using the following command: tidal-dl-ng login"
            tidalFailure="true"
            exit
        fi
    else
        log "tidal-dl-ng requires authentication, authenticate now:"
        log "login manually using the following command: tidal-dl-ng login"
        tidalFailure="true"
        exit
    fi
}

verifyConfig () {

	if [ "$lidarrMusicVideoAutomator" != "true" ]; then
		log "Script is not enabled, enable by setting lidarrMusicVideoAutomator to \"true\" by modifying the \"/config/<filename>.conf\" config file..."
		log "Sleeping (infinity)"
		sleep infinity
	fi

}

settings () {
  log "Import Script $1 Settings..."
  source "$1"
  arrUrl="$lidarrUrl"
  arrApiKey="$lidarrApiKey"
}

logfileSetup () {
  logFileName="$scriptName-$(date +"%Y_%m_%d_%I_%M_%p").txt"

  if find "$dockerPath/logs" -type f -iname "$scriptName-*.txt" | read; then
    # Keep only the last 2 log files for 3 active log files at any given time...
    rm -f $(ls -1t $dockerPath/logs/$scriptName-* | tail -n +5)
    # delete log files older than 5 days
    find "$dockerPath/logs" -type f -iname "$scriptName-*.txt" -mtime +5 -delete
  fi
  
  if [ ! -f "$dockerPath/logs/$logFileName" ]; then
    echo "" > "$dockerPath/logs/$logFileName"
  chown ${PUID:-1000}:${PGID:-1000} "$dockerPath/logs/$logFileName"
    chmod 666 "$dockerPath/logs/$logFileName"
  fi
}

log () {
  m_time=`date "+%F %T"`
  echo $m_time" :: $scriptName (v$scriptVersion) :: "$1
}

TagMP4 () {
    find "$lidarrMusicVideoTempDownloadPath" -type f -iname "*.mp4" -print0 | while IFS= read -r -d '' file; do
        fileName="$(basename "$file")"
        fileNameNoExt="${fileName%.*}"
        completedFileNameNoExt="$fileNameNoExt-$videoTypeFileName"

        mv "$file" "$lidarrMusicVideoTempDownloadPath/temp.mp4"

        ThumbnailDownloader

        genre=""
        if [ ! -z "$lidarrArtistGenres" ]; then
            for genre in ${!lidarrArtistGenres[@]}; do
                artistGenre="${lidarrArtistGenres[$genre]}"
                OUT=$OUT"$artistGenre / "
            done
            genre="${OUT%???}"
        else
            genre=""
        fi

        AtomicParsley "$lidarrMusicVideoTempDownloadPath/temp.mp4" \
            --title "${videoTitle}${explicitTitleTag}" \
            --year "$videoYear" \
            --artist "$lidarrArtistName" \
            --albumArtist "$lidarrArtistName" \
            --genre "$genre" \
            --advisory "$advisory" \
            --artwork "$thumbnailFile" \
            -o "$lidarrMusicVideoTempDownloadPath/$completedFileNameNoExt.mp4" 

        if [ -f "$lidarrMusicVideoTempDownloadPath/$completedFileNameNoExt.mp4" ]; then
            rm "$lidarrMusicVideoTempDownloadPath/temp.mp4"
        fi
        NfoWriter
        CompletedFileMover
    done
}

RemuxToMKV () {
    find "$lidarrMusicVideoTempDownloadPath" -type f -iname "*.mp4" -print0 | while IFS= read -r -d '' file; do
        fileName="$(basename "$file")"
        fileNameNoExt="${fileName%.*}"
        completedFileNameNoExt="$fileNameNoExt-$videoTypeFileName"
        
        if [ -f "$lidarrlidarrMusicVideoLibrary/$completedFileNameNoExt.mkv" ]; then
            log "$processCount/$lidarrArtistCount :: $lidarrArtistName :: $videoIdProcess/$videoIdsCount :: $videoArtist :: $videoYear :: $videoType :: $videoTitle :: Alreday in library, performing cleanup"
            rm "$file"
            continue
        fi
        
        log "$processCount/$lidarrArtistCount :: $lidarrArtistName :: $videoIdProcess/$videoIdsCount :: $videoArtist :: $videoYear :: $videoType :: $videoTitle :: Detecting video quality..."
        videoData=$(mkvmerge -J "$file")
        videoTrackDimensions=$(echo "${videoData}" | jq -r '.tracks[] | select(.type=="video") | .properties.pixel_dimensions')
        if echo "$videoTrackDimensions" | grep -i "1920x" | read; then
            videoQaulity="FHD"
        elif echo "$videoTrackDimensions" | grep -i "1280x" | read; then
            videoQaulity="HD"
        else
            videoQaulity="SD"
        fi

        log "$processCount/$lidarrArtistCount :: $lidarrArtistName :: $videoIdProcess/$videoIdsCount :: $videoArtist :: $videoYear :: $videoType :: $videoTitle :: Video quality is: $videoQaulity"

        if [ "$requireMinimumVideoQaulity" = "FHD" ]; then
            if [ "$videoQaulity" = "HD" ] || [ "$videoQaulity" = "SD" ]; then
                log "$processCount/$lidarrArtistCount :: $lidarrArtistName :: $videoIdProcess/$videoIdsCount :: $videoArtist :: $videoYear :: $videoType :: $videoTitle :: ERROR :: Video does not meet required minimum quality: $requireMinimumVideoQaulity"
                rm "$file"
                continue
            fi
        elif [ "$requireMinimumVideoQaulity" = "HD" ]; then
            if [ "$videoQaulity" = "SD" ]; then
                log "$processCount/$lidarrArtistCount :: $lidarrArtistName :: $videoIdProcess/$videoIdsCount :: $videoArtist :: $videoYear :: $videoType :: $videoTitle :: ERROR :: Video does not meet required minimum quality: $requireMinimumVideoQaulity"
                rm "$file"
                continue
            fi
        fi


        ThumbnailDownloader

        genre=""
        if [ ! -z "$lidarrArtistGenres" ]; then
            for genre in ${!lidarrArtistGenres[@]}; do
                artistGenre="${lidarrArtistGenres[$genre]}"
                OUT=$OUT"$artistGenre / "
            done
            genre="${OUT%???}"
        else
            genre=""
        fi

        log "$processCount/$lidarrArtistCount :: $lidarrArtistName :: $videoIdProcess/$videoIdsCount :: $videoArtist :: $videoYear :: $videoType :: $videoTitle :: Remuxing file to MKV and Tagging"
        ffmpeg -y \
            -i "$file" \
            -c copy \
            -metadata TITLE="${videoTitle}${explicitTitleTag}" \
            -metadata DATE_RELEASE="$videoDate" \
            -metadata DATE="$videoDate" \
            -metadata YEAR="$videoYear" \
            -metadata GENRE="$genre" \
            -metadata ARTIST="$lidarrArtistName" \
            -metadata ARTISTS="$lidarrArtistName" \
            -metadata ALBUMARTIST="$lidarrArtistName" \
            -metadata ENCODED_BY="tidal" \
            -attach "$thumbnailFile" -metadata:s:t mimetype=image/jpeg \
            "$lidarrMusicVideoTempDownloadPath/$completedFileNameNoExt.mkv"
            chmod 666 "$lidarrMusicVideoTempDownloadPath/$completedFileNameNoExt.mkv"

        if [ -f "$lidarrMusicVideoTempDownloadPath/$completedFileNameNoExt.mkv" ]; then
            log "$processCount/$lidarrArtistCount :: $lidarrArtistName :: $videoIdProcess/$videoIdsCount :: $videoArtist :: $videoYear :: $videoType :: $videoTitle :: Removing source file for remuxing..."
            rm "$file"
        fi

        NfoWriter
        CompletedFileMover

    done

}

CompletedFileMover () {
    if [ ! -d "$lidarrMusicVideoLibrary" ]; then
        log "$processCount/$lidarrArtistCount :: $lidarrArtistName :: $videoIdProcess/$videoIdsCount :: $videoArtist :: $videoYear :: $videoType :: $videoTitle :: Creating Library Folder"
        mkdir -p "$lidarrMusicVideoLibrary"
        chown ${PUID:-1000}:${PGID:-1000} "$lidarrMusicVideoLibrary"
        chmod 777 "$lidarrMusicVideoLibrary"
    fi

    if [ ! -d "$lidarrMusicVideoLibrary/$lidarrArtistFolder" ]; then
        log "$processCount/$lidarrArtistCount :: $lidarrArtistName :: $videoIdProcess/$videoIdsCount :: $videoArtist :: $videoYear :: $videoType :: $videoTitle :: Creating Artist Folder: $lidarrArtistFolder"
        mkdir -p "$lidarrMusicVideoLibrary/$lidarrArtistFolder"
        chown ${PUID:-1000}:${PGID:-1000} "$lidarrMusicVideoLibrary/$lidarrArtistFolder"
        chmod 777 "$lidarrMusicVideoLibrary/$lidarrArtistFolder"
    fi

    if [ -f "$lidarrMusicVideoTempDownloadPath/$completedFileNameNoExt.mp4" ]; then
        if [ ! -f "$lidarrMusicVideoLibrary/$lidarrArtistFolder/$completedFileNameNoExt.mp4" ]; then
            log "$processCount/$lidarrArtistCount :: $lidarrArtistName :: $videoIdProcess/$videoIdsCount :: $videoArtist :: $videoYear :: $videoType :: $videoTitle :: Moving compeleted video file to libary"
            mv "$lidarrMusicVideoTempDownloadPath/$completedFileNameNoExt.mp4" "$lidarrMusicVideoLibrary/$lidarrArtistFolder/$completedFileNameNoExt.mp4"
            chmod 666 "$lidarrMusicVideoLibrary/$lidarrArtistFolder/$completedFileNameNoExt.mp4"
        else
            log "$processCount/$lidarrArtistCount :: $lidarrArtistName :: $videoIdProcess/$videoIdsCount :: $videoArtist :: $videoYear :: $videoType :: $videoTitle :: ERROR :: Video Previously Imported"
        fi
    fi

    if [ -f "$lidarrMusicVideoTempDownloadPath/$completedFileNameNoExt.mkv" ]; then
        if [ ! -f "$lidarrMusicVideoLibrary/$lidarrArtistFolder/$completedFileNameNoExt.mkv" ]; then
            log "$processCount/$lidarrArtistCount :: $lidarrArtistName :: $videoIdProcess/$videoIdsCount :: $videoArtist :: $videoYear :: $videoType :: $videoTitle :: Moving compeleted video file to libary"
            mv "$lidarrMusicVideoTempDownloadPath/$completedFileNameNoExt.mkv" "$lidarrMusicVideoLibrary/$lidarrArtistFolder/$completedFileNameNoExt.mkv"
            chmod 666 "$lidarrMusicVideoLibrary/$lidarrArtistFolder/$completedFileNameNoExt.mkv"
        else
            log "$processCount/$lidarrArtistCount :: $lidarrArtistName :: $videoIdProcess/$videoIdsCount :: $videoArtist :: $videoYear :: $videoType :: $videoTitle :: ERROR :: Video Previously Imported"
        fi
    fi

    if [ -f "$lidarrMusicVideoTempDownloadPath/$completedFileNameNoExt.jpg" ]; then
        if [ ! -f "$lidarrMusicVideoLibrary/$lidarrArtistFolder/$completedFileNameNoExt.jpg" ]; then
            log "$processCount/$lidarrArtistCount :: $lidarrArtistName :: $videoIdProcess/$videoIdsCount :: $videoArtist :: $videoYear :: $videoType :: $videoTitle :: Moving compeleted thumbnail file to libary"
            mv "$lidarrMusicVideoTempDownloadPath/$completedFileNameNoExt.jpg" "$lidarrMusicVideoLibrary/$lidarrArtistFolder/$completedFileNameNoExt.jpg"
            chmod 666 "$lidarrMusicVideoLibrary/$lidarrArtistFolder/$completedFileNameNoExt.jpg"
        else
            log "$processCount/$lidarrArtistCount :: $lidarrArtistName :: $videoIdProcess/$videoIdsCount :: $videoArtist :: $videoYear :: $videoType :: $videoTitle :: ERROR :: Thumbnail Previously Imported"
        fi
    fi

    if [ -f "$lidarrMusicVideoTempDownloadPath/$completedFileNameNoExt.nfo" ]; then
        if [ ! -f "$lidarrMusicVideoLibrary/$lidarrArtistFolder/$completedFileNameNoExt.nfo" ]; then
            log "$processCount/$lidarrArtistCount :: $lidarrArtistName :: $videoIdProcess/$videoIdsCount :: $videoArtist :: $videoYear :: $videoType :: $videoTitle :: Moving compeleted NFO file to libary"
            mv "$lidarrMusicVideoTempDownloadPath/$completedFileNameNoExt.nfo" "$lidarrMusicVideoLibrary/$lidarrArtistFolder/$completedFileNameNoExt.nfo"
            chmod 666 "$lidarrMusicVideoLibrary/$lidarrArtistFolder/$completedFileNameNoExt.nfo"
        else
            log "$processCount/$lidarrArtistCount :: $lidarrArtistName :: $videoIdProcess/$videoIdsCount :: $videoArtist :: $videoYear :: $videoType :: $videoTitle :: ERROR :: NFO Previously Imported"
        fi
    fi

}

DownloadVideo () {
    videoUnavailable="false"
    if [ -d "$lidarrMusicVideoTempDownloadPath" ]; then
        rm -rf "$lidarrMusicVideoTempDownloadPath"/*
    fi
    log "$processCount/$lidarrArtistCount :: $lidarrArtistName :: $videoIdProcess/$videoIdsCount :: $videoArtist :: $videoYear :: $videoType :: $videoTitle :: Downloading Video..."
    if tidal-dl-ng dl "$1" | grep "Media not found" | read; then
        log "$processCount/$lidarrArtistCount :: $lidarrArtistName :: $videoIdProcess/$videoIdsCount :: $videoArtist :: $videoYear :: $videoType :: $videoTitle :: ERROR :: Media Unavailable!"
        failedDownloadCount=$(($failedDownloadCount-1))
        videoUnavailable="true"
    fi

    if find "$lidarrMusicVideoTempDownloadPath" -type f -iname "*.mp4" | read; then
        log "$processCount/$lidarrArtistCount :: $lidarrArtistName :: $videoIdProcess/$videoIdsCount :: $videoArtist :: $videoYear :: $videoType :: $videoTitle :: Download Complete!"
        failedDownloadCount=0
    else
        log "$processCount/$lidarrArtistCount :: $lidarrArtistName :: $videoIdProcess/$videoIdsCount :: $videoArtist :: $videoYear :: $videoType :: $videoTitle :: ERROR :: Download Failed!"
        failedDownloadCount=$(($failedDownloadCount+1))
    fi

}

ThumbnailDownloader () {
    thumbnailFile="$lidarrMusicVideoTempDownloadPath/${completedFileNameNoExt}.jpg"
    if [ ! -f "$thumbnailFile" ]; then
        log "$processCount/$lidarrArtistCount :: $lidarrArtistName :: $videoIdProcess/$videoIdsCount :: $videoArtist :: $videoYear :: $videoType :: $videoTitle :: Downloading Thumbnail"
        curl -s "$videoThumbnailUrl" -o "$thumbnailFile"
    fi
}

NfoWriter () {
    log "$processCount/$lidarrArtistCount :: $lidarrArtistName :: $videoIdProcess/$videoIdsCount :: $videoArtist :: $videoYear :: $videoType :: $videoTitle :: Writing NFO"
    nfo="$lidarrMusicVideoTempDownloadPath/${completedFileNameNoExt}.nfo"
    if [ -f "$nfo" ]; then
        rm "$nfo"
    fi
    echo "<musicvideo>" >> "$nfo"
    echo "	<title>${videoTitle}${explicitTitleTag}</title>" >> "$nfo"
    echo "	<userrating/>" >> "$nfo"
    echo "	<track/>" >> "$nfo"
    echo "	<studio/>" >> "$nfo"
    if [ ! -z "$lidarrArtistGenres" ]; then
        for genre in ${!lidarrArtistGenres[@]}; do
            artistGenre="${lidarrArtistGenres[$genre]}"
            echo "	<genre>$artistGenre</genre>" >> "$nfo"
        done
    else
        echo "	<genre>$videoType</genre>" >> "$nfo"
    fi
    echo "	<genre>$videoType</genre>" >> "$nfo"
    echo "	<premiered/>" >> "$nfo"
    echo "	<year>$videoYear</year>" >> "$nfo"
    for videoArtistId in $(echo "$videoArtistsIds"); do
        videoArtistData=$(echo "$videoArtists" | jq -r "select(.id==$videoArtistId)")
        videoArtistName=$(echo "$videoArtistData" | jq -r .name)
        videoArtistType=$(echo "$videoArtistData" | jq -r .type)
        echo "	<artist>$videoArtistName</artist>" >> "$nfo"
    done
    echo "	<albumArtistCredits>" >> "$nfo"
    echo "		<artist>$lidarrArtistName</artist>" >> "$nfo"
    echo "		<musicBrainzArtistID>$lidarrArtistMusicbrainzId</musicBrainzArtistID>" >> "$nfo"
    echo "	</albumArtistCredits>" >> "$nfo"
    echo "	<thumb>${completedFileNameNoExt}.jpg</thumb>" >> "$nfo"
    echo "	<source>tidal</source>" >> "$nfo"
    echo "</musicvideo>" >> "$nfo"
    tidy -w 2000 -i -m -xml "$nfo" &>/dev/null
    chmod 666 "$nfo"

}

tidalProcess () {
    tidalArtistId=$1
    # curl -s "https://api.tidal.com/v1/artists/14123/videos?countryCode=US&offset=0&limit=1000" -H "x-tidal-token: CzET4vdadNUFQ5JU" | jq -r
    vidoesData=$(curl -s "https://api.tidal.com/v1/artists/${tidalArtistId}/videos?countryCode=${tidalCountryCode}&offset=0&limit=1000" -H "x-tidal-token: CzET4vdadNUFQ5JU")
    videoIds="$(echo "$vidoesData" | jq -r ".items | sort_by(.releaseDate) | reverse | .[].id")"
    videoIdsCount=$(echo "$videoIds" | wc -l)
    videoIdProcess=0
    for videoId in $(echo "$videoIds"); do 
        videoIdProcess=$(($videoIdProcess+1))
        videoData="$(echo "$vidoesData" | jq -r ".items[] | select(.id==$videoId)")"
        videoTitle="$(echo "$videoData" | jq -r .title)"
        videoArtist="$(echo "$videoData" | jq -r .artist.name)"
        videoMainArtistId="$(echo "$videoData" | jq -r .artist.id)"
        videoExplicit=$(echo $videoData | jq -r .explicit)
        videoDate="$(echo "$videoData" | jq -r ".releaseDate")"
        videoDate="${videoDate:0:10}"
        videoYear="${videoDate:0:4}"
        videoImageId="$(echo "$videoData" | jq -r ".imageId")"
        videoImageIdFix="$(echo "$videoImageId" | sed "s/-/\//g")"
        videoThumbnailUrl="https://resources.tidal.com/images/$videoImageIdFix/750x500.jpg"
        videoSource="tidal"
        videoArtists="$(echo "$videoData" | jq -r ".artists[]")"
        videoArtistsIds="$(echo "$videoArtists" | jq -r ".id")"

        # Detect video type
        videoType="Music Video"
        videoTypeFileName="video"
        if echo "$videoTitle" | grep -i "Visualizer" | read; then
            videoType="Visualizer"
            if [ "$enableLiveVideos" = "false"  ]; then
                log "$processCount/$lidarrArtistCount :: $lidarrArtistName :: $videoIdProcess/$videoIdsCount :: $videoArtist :: $videoYear :: $videoType :: $videoTitle :: Visualizer Video detected, skipping..."
                continue
            fi
        elif echo "$videoTitle" | grep -i "Visualiser" | read; then
            videoType="Visualiser"
            if [ "$enableVisualizerVideos" = "false"  ]; then
                log "$processCount/$lidarrArtistCount :: $lidarrArtistName :: $videoIdProcess/$videoIdsCount :: $videoArtist :: $videoYear :: $videoType :: $videoTitle :: Visualizer Video detected, skipping..."
                continue
            fi
        elif echo "$videoTitle" | grep -i "video" | grep -i "lyric" | read; then
            videoType="Lyric"
            videoTypeFileName="lyrics"
            if [ "$enableLyricVideos" = "false"  ]; then
                log "$processCount/$lidarrArtistCount :: $lidarrArtistName :: $videoIdProcess/$videoIdsCount :: $videoArtist :: $videoYear :: $videoType :: $videoTitle :: Lyric Video detected, skipping..."
                continue
            fi
        elif echo "$videoTitle" | grep -i "\(.*live.*\)" | read; then
            videoType="Live"
            videoTypeFileName="live"
            if [ "$enableLiveVideos" = "false"  ]; then
                log "$processCount/$lidarrArtistCount :: $lidarrArtistName :: $videoIdProcess/$videoIdsCount :: $videoArtist :: $videoYear :: $videoType :: $videoTitle :: Live Video detected, skipping..."
                continue
            fi
        elif echo "$videoTitle" | grep -i "behind the scenes" | read; then
            videoType="Behind the Scenes"
            videoTypeFileName="behindthescenes"
            if [ "$enableBehindTheScenesVideos" = "false"  ]; then
                log "$processCount/$lidarrArtistCount :: $lidarrArtistName :: $videoIdProcess/$videoIdsCount :: $videoArtist :: $videoYear :: $videoType :: $videoTitle :: Lyric Video detected, skipping..."
                continue
            fi
        elif echo "$videoTitle" | grep -i "making of" | read; then
            videoType="Behind the Scenes"
            videoTypeFileName="behindthescenes"
            if [ "$enableBehindTheScenesVideos" = "false"  ]; then
                log "$processCount/$lidarrArtistCount :: $lidarrArtistName :: $videoIdProcess/$videoIdsCount :: $videoArtist :: $videoYear :: $videoType :: $videoTitle :: Behind The Scenes Video detected, skipping..."
                continue
            fi
        elif echo "$videoTitle" | grep -i "intreview" | read; then
            videoType="Interview"
            videoTypeFileName="interview"
            if [ "$enableInterviewVideos" = "false"  ]; then
                log "$processCount/$lidarrArtistCount :: $lidarrArtistName :: $videoIdProcess/$videoIdsCount :: $videoArtist :: $videoYear :: $videoType :: $videoTitle :: Interview Video detected, skipping..."
                continue
            fi
        elif echo "$videoTitle" | grep -i "episode [[:digit:]]" | read; then
            videoType="Episode"
            videoTypeFileName="behindthescenes"
            if [ "$enableEpisodeVideos" = "false"  ]; then
                log "$processCount/$lidarrArtistCount :: $lidarrArtistName :: $videoIdProcess/$videoIdsCount :: $videoArtist :: $videoYear :: $videoType :: $videoTitle :: Episode Video detected, skipping..."
                continue
            fi
        fi

        if [ -f "$logFolder/video-$videoId" ]; then
            log "$processCount/$lidarrArtistCount :: $lidarrArtistName :: $videoIdProcess/$videoIdsCount :: $videoArtist :: $videoYear :: $videoType :: $videoTitle :: Previously downloaded, skipping..."
            continue
        fi        

        if [ $tidalArtistId -ne $videoMainArtistId ]; then
            log "$processCount/$lidarrArtistCount :: $lidarrArtistName :: $videoIdProcess/$videoIdsCount :: $videoArtist :: $videoYear :: $videoType :: $videoTitle :: ERROR :: Video Main Artist ID ($videoMainArtistId) does not match requested Artist ID ($tidalArtistId), skippping..."
            continue
        fi

        if [ "$videoExplicit" = "true" ]; then
            explicitTitleTag=" 🅴"
            advisory="explicit"
        else
            explicitTitleTag=""
            advisory="clean"
        fi        
        
        log "$processCount/$lidarrArtistCount :: $lidarrArtistName :: $videoIdProcess/$videoIdsCount :: $videoArtist :: $videoYear :: $videoType :: $videoTitle :: Processing..."
        #echo "$videoThumbnailUrl"
        #echo "$videoArtists"
        #echo "$videoData" | jq -r
        
        DownloadVideo "https://tidal.com/video/$videoId"
        

        if [ $failedDownloadCount -ge 3 ]; then
            log "$processCount/$lidarrArtistCount :: $lidarrArtistName :: $videoIdProcess/$videoIdsCount :: $videoArtist :: $videoYear :: $videoType :: $videoTitle :: ERROR :: Too many failed download attemps, exiting..."
            exit
        fi
        
        if find "$lidarrMusicVideoTempDownloadPath" -type f -iname "*.mp4" | read; then

            if [ "$musicVideoFormat" = "mkv" ]; then
                RemuxToMKV
            else
                TagMP4
            fi
        elif [ "$videoUnavailable" = "false" ]; then
            continue
        fi
    
        if [ ! -d "$logFolder" ]; then
            log "$processCount/$lidarrArtistCount :: $lidarrArtistName :: $videoIdProcess/$videoIdsCount :: $videoArtist :: $videoYear :: $videoType :: $videoTitle :: Creating log folder: $logFolder"
            mkdir -p "$logFolder"
            chown ${PUID:-1000}:${PGID:-1000} "$logFolder"
            chmod 777 "$logFolder"
        fi

        if [ ! -f "$logFolder/video-$videoId" ]; then
            log "$processCount/$lidarrArtistCount :: $lidarrArtistName :: $videoIdProcess/$videoIdsCount :: $videoArtist :: $videoYear :: $videoType :: $videoTitle :: Writing log file: $logFolder/video-$videoId"
            touch "$logFolder/video-$videoId"
            chmod 666 "$logFolder/video-$videoId"
        fi
    done
}

for (( ; ; )); do
  let i++
  logfileSetup
  touch "$dockerPath/logs/$logFileName"
  exec &> >(tee -a "$dockerPath/logs/$logFileName")
  log "Starting..."
  InstallDependencies
  confFiles=$(find /config -mindepth 1 -type f -name "*.conf")
  confFileCount=$(echo "$confFiles" | wc -l)

  if [ -z "$confFiles" ]; then
      log "ERROR :: No config files found, exiting..."
      exit
  fi

  for f in $confFiles; do
    count=$(($count+1))
    SECONDS=0   
    log "Processing \"$f\" config file"
    settings "$f"
    verifyConfig
    ConfigureTidalDl
    if [ "$tidalFailure" = "true" ]; then
        exit
    fi
    if [ ! -z "$arrUrl" ]; then
      if [ ! -z "$arrApiKey" ]; then
        lidarrArtists=$(wget --timeout=0 -q -O - "$arrUrl/api/v1/artist?apikey=$arrApiKey" | jq -r .[])
        lidarrArtistIds=$(echo $lidarrArtists | jq -r .id)
        lidarrArtistCount=$(echo "$lidarrArtistIds" | wc -l)
        processCount=0
        for lidarrArtistId in $(echo $lidarrArtistIds); do
            processCount=$(( $processCount + 1))
            lidarrArtistData=$(wget --timeout=0 -q -O - "$arrUrl/api/v1/artist/$lidarrArtistId?apikey=$arrApiKey")
            lidarrArtistName=$(echo $lidarrArtistData | jq -r .artistName)
            lidarrArtistMusicbrainzId=$(echo $lidarrArtistData | jq -r .foreignArtistId)
            lidarrArtistPath="$(echo "${lidarrArtistData}" | jq -r " .path")"
            lidarrArtistFolder="$(basename "${lidarrArtistPath}" | cut -d "(" -f 1)"
            lidarrArtistFolder="$(echo "$lidarrArtistFolder" | sed 's/^[ \t]*//;s/[ \t]*$//')"
            tidalArtistUrl=$(echo "${lidarrArtistData}" | jq -r ".links | .[] | select(.name==\"tidal\") | .url")
            tidalArtistIds="$(echo "$tidalArtistUrl" | grep -o '[[:digit:]]*' | sort -u)"

            # Get Genre Data
            OLDIFS="$IFS"
            IFS=$'\n'
            lidarrArtistGenres=($(echo "$lidarrArtistData" | jq -r .genres[]))
            IFS="$OLDIFS"
            
            log "$processCount/$lidarrArtistCount :: $lidarrArtistName :: Processing..."
            for id in $(echo "$tidalArtistIds"); do
                tidalProcess "$id"
            done

            
        done
      else
        log "ERROR :: Skipping $arrApp, missing API Key..."
      fi
    else
      log "ERROR :: Skipping $arrApp, missing URL..."
    fi

    duration=$SECONDS
    durationOutput="$(printf '%dd:%dh:%dm:%ds\n' $((duration/86400)) $((duration%86400/3600)) $((duration%3600/60)) $((duration%60)))"
    log "Script Completed in $durationOutput!"

  done

  log "Sleeping $lidarrMusicVideoAutomatorInterval..."
  sleep $lidarrMusicVideoAutomatorInterval
  
done

exit
