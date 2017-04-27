#!/bin/bash

mkdir -p /tmp

ssh-keyscan -t rsa github.com >> ~/.ssh/known_hosts 2>/dev/null

openssl aes-256-cbc -d -in travis/runelite.key.enc -out ~/.ssh/runelite -k $SECRET_KEY
openssl aes-256-cbc -d -in travis/runelite-updater.key.enc -out ~/.ssh/runelite-updater -k $SECRET_KEY
openssl aes-256-cbc -d -in travis/static.runelite.net.key.enc -out ~/.ssh/static.runelite.net -k $SECRET_KEY
openssl aes-256-cbc -d -in travis/runelite.keystore.enc -out /tmp/runelite.keystore -k $KEYSTORE_PASSWORD
cp travis/ssh-config ~/.ssh/config
chmod 600 ~/.ssh/runelite ~/.ssh/runelite-updater ~/.ssh/static.runelite.net ~/.ssh/config

mvn clean package --settings travis/settings.xml
