#!/bin/bash

if [ -z "$1" ] && [ -z "$2" ]; then
  echo "Please provide font_urls separated with comma"
  exit -1
fi

font_urls=$1
patched_font_urls=$2

font_dir=$HOME/.fonts
download_dir=$font_dir/downloads
download_start_time_file=$download_dir/.downloaded
host_font_dir=/vagrant/data/fonts

download_font_url () {
  url=$1
  output_dir=$2
  if [ -z "$output_dir" ]; then output_dir=$download_dir; fi
  #echo Downloading $url to $download_dir
  pushd $download_dir > /dev/null
  curl -OJL "$url"
  popd > /dev/null
  downloaded=`find $download_dir -cnewer $download_start_time_file -type f`
  if [[ "$downloaded" == *.zip ]]; then
    #echo Unzipping $downloaded
    unzip $downloaded -d $download_dir
    downloaded=`find $download_dir -cnewer $download_start_time_file -type f -name "*.ttf"`
  fi
  if [ "$download_dir" = "$output_dir" ]; then
    return
  fi
  echo "$downloaded" | while read file; do
  if [ "$file" ]; then cp "$file" $output_dir; fi
  done
  downloaded=`find $output_dir -maxdepth 1 -cnewer $download_start_time_file -type f -name "*.ttf"`
  return
}

mkdir -p $host_font_dir
mkdir -p $download_dir

#### install fonts
if [ "$font_urls" ]; then
  touch $download_start_time_file
  echo "$font_urls" | tr ',' '\n' | while read url; do
    download_font_url $url
    fontfiles=$downloaded
    if [ -z "$fontfiles" ]; then
      echo "Could not find any newly downloaded font files"
      continue
    fi
    echo "$fontfiles" | while read file; do
      echo Downloaded $file
    done
    # patching nerdfonts
    docker run --rm -v $download_dir:/in -v $font_dir:/out nerdfonts/patcher --powerline
    patchedfiles=`find $font_dir -maxdepth 1 -cnewer $download_start_time_file -type f -name "*.ttf"`
    echo "$patchedfiles" | while read file; do
      echo Patched $file
      cp "$file" $host_font_dir
    done
  done
fi
if [ "$patched_font_urls" ]; then
  touch $download_start_time_file
  echo "$patched_font_urls" | tr ',' '\n' | while read url; do
    download_font_url $url $font_dir
    fontfiles=$downloaded
    if [ -z "$fontfiles" ]; then
      echo "Could not find any newly downloaded font files"
      continue
    fi
    echo "$fontfiles" | while read file; do
      echo Downloaded $file
      cp "$file" $host_font_dir
    done
  done
fi
