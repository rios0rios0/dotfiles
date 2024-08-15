#!/bin/bash

# those commands below can not be used as Chezmoi templates
alias dip='dip(){ docker inspect --format="{{ .Name }}: {{ range .NetworkSettings.Networks }}{{ .IPAddress }}{{ end }}" $(docker ps -q); unset -f dip; }; dip'
alias dip='dip(){ docker inspect --format="{{ .Name }}: {{ range .NetworkSettings.Networks }}{{ .IPAddress }} - {{ end }}" $(docker ps -q); unset -f dip; }; dip'
alias dreset='docker container stop $(docker container ls -aq) && docker container prune --force && docker volume prune --force && docker network prune --force && docker builder prune -f'
