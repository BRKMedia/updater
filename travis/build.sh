#!/bin/bash

openssl aes-256-cbc -d -in travis/runelite.key.enc -out ~/.ssh/runelite -k $SECRET_KEY
openssl aes-256-cbc -d -in travis/runelite-updater.key.asc -out ~/.ssh/runelite-updater -k $SECRET_KEY
openssl aes-256-cbc -d -in travis/static.runelite.net.key.enc -out ~/.ssh/static.runelite.net -k $SECRET_KEY
cp travis/ssh-config ~/.ssh/config
chmod 600 ~/.ssh/runelite ~/.ssh/runelite-updater ~/.ssh/static.runelite.net ~/.ssh/config

set -o pipefail
mvn clean package --settings travis/settings.xml | sed "s/$RUNELITE_BACKEND/REDACTED/g"
exit
