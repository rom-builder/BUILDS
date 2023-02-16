#!/bin/bash

telegram_send_message() {
  # use environment variables
  local token=$TG_TOKEN
  local chat=$TG_CHAT
  local message=$1
  local disable_web_page_preview=$2

  if [ -z "$token" ] || [ -z "$chat" ]; then
    return
  fi

  if [ -z "$message" ]; then
    echo "No message passed. Aborting."
    exit 1
  fi

  local send_message_response=$(curl -s "https://api.telegram.org/bot$token/sendMessage" -d chat_id="$chat" -d text="$message" -d parse_mode=MARKDOWN -d disable_web_page_preview="$disable_web_page_preview")
  if [ "$(echo "$send_message_response" | jq -r '.ok')" == "true" ]; then
    echo "Message sent to Telegram."
  else
    echo "Error sending message to Telegram."
  fi
}

telegram_send_file() {
  # use environment variables
  local token=$TG_TOKEN
  local chat=$TG_CHAT
  local file=$1
  local caption=$2

  if [ -z "$token" ] || [ -z "$chat" ]; then
    return
  fi

  if [ -z "$file" ]; then
    echo "No file passed. Aborting."
    exit 1
  fi

  local send_file_response=$(curl -s "https://api.telegram.org/bot$token/sendDocument" -F chat_id="$chat" -F document=@"$file" -F caption="$caption")
  if [ "$(echo "$send_file_response" | jq -r '.ok')" == "true" ]; then
    echo "File $file sent to Telegram."
  else
    echo "Error sending file $file to Telegram."
  fi
}

update_tg() {
  local message="$1"
  telegram_send_message "*$message*" true
}

logt() {
  local message="$1"
  update_tg "$message"
  echo "$message"
}

resolve_dependencies() {
  local packages=('repo' 'git-core' 'gnupg' 'flex' 'bison' 'build-essential' 'zip' 'curl' 'zlib1g-dev' 'libc6-dev-i386' 'libncurses5' 'lib32ncurses5-dev' 'x11proto-core-dev' 'libx11-dev' 'lib32z1-dev' 'libgl1-mesa-dev' 'libxml2-utils' 'xsltproc' 'unzip' 'openssl' 'libssl-dev' 'fontconfig' 'jq')
  echo "Updating package lists..."
  sudo apt-get update -y 
  echo "Installing dependencies..."
  sudo apt-get install -y "${packages[@]}"
  echo "Dependencies check complete."
}

git_setup() {
  local name="$1"
  local email="$2"
  echo "Setting up git with email: $email and name: $name"
  git config --global user.email "$email"
  git config --global user.name "$name"
  git config --global pull.rebase true
}

git_clone() {
  # take arguments as -r repo -d dir -b branch
  while [[ "$#" -gt 0 ]]; do
    case $1 in
      -r|--repo) repo="$2"; shift ;;
      -d|--dir) dir="$2"; shift ;;
      -b|--branch) branch="$2"; shift ;;
      *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
  done

  # Check if the directory exists
  if [ -d "$dir" ]; then
    echo "Already cloned $repo into $dir."
    echo "Pulling latest changes..."
    (
      cd "$dir" || exit
      git pull
    )
    return
  else # Clone the repo into the directory
    # If branch is not null
    if [ "$branch" != "null" ]; then
      echo "Cloning $repo into $dir with branch $branch..."
      git clone "$repo" -b "$branch" "$dir"
    else
      echo "Cloning $repo into $dir..."
      git clone "$repo" "$dir"
    fi
  fi

  # Clear variables
  unset repo dir branch
}

repo_exists() {
  local repo="$1"
  local token="$2"
  local response=$(curl -s -H "Authorization: Bearer $token" "https://api.github.com/repos/$repo")
  if [[ $response == *"\"message\": \"Not Found\""* ]]; then
    return 1 # repo does not exist
  else
    return 0 # repo exists
  fi
}

create_repo() {
  local repo="$1"
  local token="$2"
  #  split repo from owner/repo
  local repo_name=$(echo "$repo" | cut -d'/' -f2)
  local org=$(echo "$repo" | cut -d'/' -f1)
  local response=$(curl -s -H "Authorization: Bearer $token" -d "{\"name\":\"$repo_name\",\"private\":false, \"description\": \"Builds for $repo_name\", \"auto_init\": true}" "https://api.github.com/orgs/$org/repos")
  echo $response
  if [[ $response == *"\"message\": \"Validation Failed\""* ]]; then
    echo "Failed to create repository: $response"
    return 1
  else
    echo "Repository created: $owner/$repo"
    return 0
  fi
}


git_clone_json() {
  local json_file="$1"
  # Check if the file exists
  if [ ! -f "$json_file" ]; then
    logt "File $json_file does not exist. Aborting."
    exit 1
  fi
  for repo in $(jq -r '.repos[].repo' $json_file); do
    dir=$(jq -r --arg repo "$repo" '.repos[] | select(.repo == $repo) | .dir' $json_file)
    branch=$(jq -r --arg repo "$repo" '.repos[] | select(.repo == $repo) | .branch' $json_file)
    pre_command=$(jq -r --arg repo "$repo" '.repos[] | select(.repo == $repo) | .pre_command' $json_file)
    post_command=$(jq -r --arg repo "$repo" '.repos[] | select(.repo == $repo) | .post_command' $json_file)

    # If pre_command is not null
    if [ "$pre_command" != "null" ]; then
      echo "Running pre_commands for $repo..."
      eval "$pre_command"
    fi
    
    # if branch is not specified
    if [ "$branch" == "null" ]; then
      echo "Repo: $repo Dir: $dir"
      git_clone -r "$repo" -d "$dir"
    else
      echo "Repo: $repo Dir: $dir Branch: $branch"
      git_clone -r "$repo" -d "$dir" -b "$branch"
    fi

    # If post_commands is not null
    if [ "$post_command" != "null" ]; then
      echo "Running post_commands for $repo..."
      eval "$post_command"
    fi
  done
}

clean_build() {
  local dir="$1"
  echo "Cleaning build directory: $dir"
  if [ -d "$dir" ]; then
    rm -rf "$dir"
  else
    echo "Build directory does not exist."
  fi
}

github_release() {
  while [[ "$#" -gt 0 ]]; do
    case $1 in
      -tk|--token) token="$2"; shift ;;
      -r|--repo) repo="$2"; shift ;;
      -tg|--tag) tag="$2"; shift ;;
      -p|--pattern) pattern="$2"; shift ;;
      *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
  done

  # check if all variables are set
  required_vars=(token repo tag pattern)
  for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
      echo "Variable $var is not set. Aborting."
      return
    fi
  done

  # Check if $RELEASE_OUT_DIR is set
  if [ -z "$RELEASE_OUT_DIR" ]; then
    logt "RELEASE_OUT_DIR is not set. Aborting upload."
    exit 1
  fi

  # Check if files exist
  echo "Checking if files exist..."
  if [ -z "$(ls -A $RELEASE_OUT_DIR | grep -E "$pattern")" ]; then
    echo $(ls -A $RELEASE_OUT_DIR | grep -E "$pattern")
    update_tg "Build had no files to upload."
    echo "No files found matching pattern $pattern. Aborting upload."
    return
  else
    echo "Files found matching pattern $pattern."
  fi

  # Check if repo exists
  echo "Checking if repo exists..."
  if repo_exists "$repo" "$token"; then
    echo "Repository already exists: $owner/$repo"
  else
    echo "Creating repository: $owner/$repo"
    create_repo "$repo" "$token"
  fi

  # Get the SHA of the latest commit in the repository
  echo "Gethering latest commit SHA..."
  local fetch_latest_sha_response=$(curl -s -H "Authorization: Bearer $token" "https://api.github.com/repos/$repo/commits")
  local latest_sha=$(echo $fetch_latest_sha_response | jq -r '.[0].sha')
  # if latest_sha is null
  if [ -z "$latest_sha" ]; then
    echo "Fetch latest SHA response: $fetch_latest_sha_response"
    echo "Latest SHA: $latest_sha"
    logt "Failed to get latest commit SHA for $repo. Aborting upload."
    return
  fi

  # Create the new tag
  echo "Creating tag $tag..."
  local tag_response=$(curl -s -H "Authorization: Bearer $token" "https://api.github.com/repos/$repo/git/tags" -d "{\"tag\":\"$tag\",\"message\":\"Release $tag\",\"object\":\"$latest_sha\",\"type\":\"commit\",\"tagger\":{\"name\":\"$GIT_NAME\",\"email\":\"$GIT_EMAIL\"}}")
  local tag_sha=$(echo $tag_response | jq -r '.sha')
  if [ -z "$tag_sha" ]; then
    logt "Tag SHA is null. Aborting upload."
    echo "Tag response: $tag_response"
    return
  else
    echo "Tag SHA $tag_sha"
  fi

  # Create the release
  echo "Creating release $tag..."
  local release_response=$(curl -s -H "Authorization: Bearer $token" "https://api.github.com/repos/$repo/releases" -d "{\"tag_name\":\"$tag\",\"name\":\"$tag\"}")
  local release_url=$(echo $release_response | jq -r '.html_url')
  if [ -z "$release_url" ]; then
    logt "Release URL is null. Some error occured when creating the release. Aborting upload."
    echo "Release response: $release_response"
    return
  else
    echo "Release URL: $release_url"
  fi
  telegram_send_message "Created [Release]($release_url)" true
  echo "Release created at $release_url"

  # Upload each file that matches the pattern
  for file in $(ls -A $RELEASE_OUT_DIR | grep -E "$pattern"); do
    logt "Uploading $file..."
    filename=$(basename "$file")
    file_release=$(curl -X POST -H "Authorization: Bearer $token" -H "Content-Type: application/octet-stream" -T "$RELEASE_OUT_DIR/$file" "https://uploads.github.com/repos/$repo/releases/$release_id/assets?name=$filename" --compressed --output -)
    file_url=$(echo $file_release | jq -r '.browser_download_url')
    # if file_url is null or empty
    if [ -z "$file_url" ]; then
      logt "File URL is null. Some error occured when uploading the file. Aborting upload."
      echo "File release response: $file_release"
      return
    else
      echo "File URL: $file_url"
    fi
    telegram_send_message "[$file]($file_url)"
  done

  logt "Uploaded files to release $tag in $repo."
  
}

compute_build_time() {
  local start_time="$1"
  local end_time="$2"
  local build_time=$((end_time - start_time))
  local hours=$((build_time / 3600))
  local minutes=$((build_time % 3600 / 60))
  local seconds=$((build_time % 60))
  if [ "$hours" -gt 0 ]; then
    echo "$hours h $minutes m $seconds s"
  elif [ "$minutes" -gt 0 ]; then
    echo "$minutes m $seconds s"
  else
    echo "$seconds s"
  fi
}

# Export functions
export -f resolve_dependencies git_setup git_clone git_clone_json clean_build github_release telegram_send_message telegram_send_file update_tg logt
