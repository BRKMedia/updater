#!/bin/bash

BASEDIR=`pwd`
RS_CLIENT_REPO=/tmp/runelite
STATIC_RUNELITE_NET=/tmp/static.runelite.net

# travis docs say git version is too old to do shallow pushes
cd /tmp
rm -rf runelite static.runelite.net
git clone git@githubrunelite:runelite/runelite -b 1.3.0.1
git clone git@githubstatic:runelite/static.runelite.net

cd $RS_CLIENT_REPO
git config user.name "Runelite auto updater"
git config user.email runelite@runelite.net

# Perform release
cp ~/.ssh/runelite ~/.ssh/github # copy key for maven plugin, as it pushes to mavens configured <scm> repo
mvn --settings $BASEDIR/travis/settings.xml release:clean release:prepare release:perform -Darguments="-DskipTests" -B
if [ $? -ne 0 ] ; then
	exit 1
fi
rm -f ~/.ssh/github

# Upload release to github
mvn --settings $BASEDIR/travis/settings.xml de.jutzig:github-release-plugin:release --pl runelite-client -B

rm -rf $STATIC_RUNELITE_NET/api
mkdir -p $STATIC_RUNELITE_NET/api
cp -r runelite-api/target/apidocs $STATIC_RUNELITE_NET/api/runelite-api
cp -r runelite-client/target/apidocs $STATIC_RUNELITE_NET/api/runelite-client

# I couldn't figure out a better way to do this
RELEASED_VER=$(git describe --abbrev=0 | sed 's/runelite-parent-//')

# Update static.runelite.net

cd $STATIC_RUNELITE_NET
sed "s/RELEASE/$RELEASED_VER/" $BASEDIR/bootstrap.json > bootstrap.json
git add bootstrap.json
git add -A api

git config user.name "Runelite auto updater"
git config user.email runelite@runelite.net

git commit -m "Release $RELEASED_VER"
git pull --no-edit
git push
