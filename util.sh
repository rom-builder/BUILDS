#!/bin/bash

prefix="device"

resolve_dependencies() {
  sudo apt-get install git-core gnupg flex bison build-essential zip curl zlib1g-dev libc6-dev-i386 libncurses5 lib32ncurses5-dev x11proto-core-dev libx11-dev lib32z1-dev libgl1-mesa-dev libxml2-utils xsltproc unzip openssl libssl-dev fontconfig jq $@ -y
}

git_setup() {
  declare -r name="$1"
  declare -r email="$2"
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
    cd "$dir"
    git checkout "$branch"
    git pull
    cd - > /dev/null
    return
  else # Clone the repo into the directory
    # If branch is specified, clone with branch
    if [ -n "$branch" ]; then
      echo "Cloning $repo into $dir with branch $branch..."
      git clone -b "$branch" "$repo" "$dir"
    else
      echo "Cloning $repo into $dir..."
      git clone "$repo" "$dir"
    fi
  fi

  # Clear variables
  unset repo dir branch
}

git_clone_json() {
   local json_file="$1"
  for repo in $(jq -r '.repos[].repo' $json_file); do
    dir=$(jq -r --arg repo "$repo" '.repos[] | select(.repo == $repo) | .dir' $json_file)
    branch=$(jq -r --arg repo "$repo" '.repos[] | select(.repo == $repo) | .branch' $json_file)

    # if branch is not specified
    if [ "$branch" == "null" ]; then
      echo "Cloning $repo into $dir..."
      git_clone -r "$repo" -d "$dir"
    else
      echo "Cloning $repo into $dir with branch $branch..."
      git_clone -r "$repo" -d "$dir" -b "$branch"
    fi
  done
}

clean_build() {
  declare -r dir="$1"
  echo "Cleaning build directory: $dir"
  if [ -d "$dir" ]; then
    rm -rf "$dir"
  else
    echo "Build directory does not exist."
  fi
}

# release() {
#   while [[ "$#" -gt 0 ]]; do
#     case $1 in
#       -p | --pattern) pattern="$2"; shift ;;
#       -tk | --token) token="$2"; shift ;;
#       -t | --tag) tag="$2"; shift ;;
#       -d | --dir) dir="$2"; shift ;;
#       -r | --repo) repo="$2"; shift ;;
#       *) echo "Unknown parameter passed: $1"; exit 1 ;;
#     esac
#     shift
#   done

#   # From github-release
#   # 1. Create a new release with tag and name with the provided token
#   # 2. Upload all files matching the pattern to the release 
#   # 3. Publish the release

#   # Create a new release with github api
#   echo "Creating a new release with tag: $tag"
  
# }
