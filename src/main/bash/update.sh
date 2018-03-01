#!/bin/bash

JAVA_ARGS="-ea -Xmx2048m"

echo RS client $RS_CLIENT_PATH
echo Deobfuscator at $DEOB_PATH
echo Fernflower at $FERNFLOWER_PATH

BASEDIR=`pwd`
JAV_CONFIG=/tmp/jav_config.ws
VANILLA=/tmp/vanilla.jar
DEOBFUSCATED=/tmp/deobfuscated.jar
DEOBFUSCATED_WITH_MAPPINGS=/tmp/deobfuscated_with_mappings.jar
VANILLA_INJECTED=/tmp/vanilla_injected.jar
RS_CLIENT_REPO=/tmp/runelite
STATIC_RUNELITE_NET=/tmp/static.runelite.net
RUNELITE_REPOSITORY_URL=dav:http://repo.runelite.net

# travis docs say git version is too old to do shallow pushes
cd /tmp
rm -rf runelite static.runelite.net
git clone git@githubrunelite:runelite/runelite
git clone git@githubstatic:runelite/static.runelite.net

curl -L oldschool.runescape.com/jav_config.ws > $JAV_CONFIG

CODEBASE=$(grep codebase $JAV_CONFIG | cut -d'=' -f2)
INITIAL_JAR=$(grep initial_jar $JAV_CONFIG | cut -d'=' -f2)
JAR_URL=$CODEBASE$INITIAL_JAR

echo Downloading vanilla client from $JAR_URL

rm -f $VANILLA
wget $JAR_URL -O $VANILLA

# get version of vanilla
VANILLA_VER=$(java -cp $DEOB_PATH net.runelite.deob.clientver.ClientVersionMain $VANILLA)
echo "Vanilla client version $VANILLA_VER"

# deploy vanilla jar, used by injector
cd -
mvn --settings travis/settings.xml deploy:deploy-file -DgroupId=net.runelite.rs -DartifactId=vanilla -Dversion=$VANILLA_VER -Dfile=/tmp/vanilla.jar -DrepositoryId=runelite -Durl=$RUNELITE_REPOSITORY_URL
if [ $? -ne 0 ] ; then
	exit 1
fi
cd -

# step 1. deobfuscate vanilla jar. store in $DEOBFUSCATED.
rm -f $DEOBFUSCATED
java $JAVA_ARGS -cp $DEOB_PATH net.runelite.deob.Deob $VANILLA $DEOBFUSCATED
if [ $? -ne 0 ] ; then
	exit 1
fi

# step 2. map old deob (which has the mapping annotations) -> new client
rm -f $DEOBFUSCATED_WITH_MAPPINGS
java $JAVA_ARGS -cp $DEOB_PATH net.runelite.deob.updater.UpdateMappings $RS_CLIENT_PATH $DEOBFUSCATED $DEOBFUSCATED_WITH_MAPPINGS
if [ $? -ne 0 ] ; then
	exit 1
fi

# decompile deobfuscated mapped client.
rm -rf /tmp/dest
mkdir /tmp/dest
java -Xmx1024m -jar $FERNFLOWER_PATH $DEOBFUSCATED_WITH_MAPPINGS /tmp/dest/

# extract source
cd /tmp/dest
jar xf *.jar
cd -

# check that decompiler ran ok
grep "FF: Couldn't be decompiled" *.java
if [ $? -eq 0 ] ; then
	echo Error decompiling
	exit 1
fi

# update deobfuscated client repository
cd $RS_CLIENT_REPO/runescape-client
git rm src/main/java/*.java
mkdir -p src/main/java/net/runelite/rs
cp /tmp/dest/*.java src/main/java/
cp -r /tmp/dest/net/runelite/rs src/main/java/net/runelite/
git add src/main/java/

# add resources
mkdir -p src/main/resources
curl -L oldschool.runescape.com/jav_config.ws > src/main/resources/jav_config.ws
git add src/main/resources/jav_config.ws

# Update RS version property
cd $RS_CLIENT_REPO
sed -i "s/rs.version>[0-9]*/rs.version>$VANILLA_VER/" pom.xml
if [ $? -ne 0 ] ; then
	exit 1
fi

git config user.name "Runelite auto updater"
git config user.email runelite@runelite.net

find $RS_CLIENT_REPO -name pom.xml -exec git add {} \;
git commit -m "Update $VANILLA_VER"
echo "Commited update $VANILLA_VER to $RS_CLIENT_REPO"
git pull --no-edit

cd $RS_CLIENT_REPO
mvn -e --settings $BASEDIR/travis/settings.xml clean install -DskipTests
if [ $? -ne 0 ] ; then
	exit 1
fi

git push origin master

# Perform release
cp ~/.ssh/runelite ~/.ssh/github # copy key for maven plugin, as it pushes to mavens configured <scm> repo
mvn --settings $BASEDIR/travis/settings.xml release:clean release:prepare release:perform -Darguments="-DskipTests" -B
if [ $? -ne 0 ] ; then
	exit 1
fi
rm -f ~/.ssh/github

rm -rf $STATIC_RUNELITE_NET/api
mkdir -p $STATIC_RUNELITE_NET/api
cp -r runelite-api/target/apidocs $STATIC_RUNELITE_NET/api/runelite-api
cp -r runelite-client/target/apidocs $STATIC_RUNELITE_NET/api/runelite-client

# Install now that theres a new SNAPSHOT version, for below versions:use-latest-versions
mvn --settings $BASEDIR/travis/settings.xml clean install -DskipTests
if [ $? -ne 0 ] ; then
	exit 1
fi

# I couldn't figure out a better way to do this
RELEASED_VER=$(git describe --abbrev=0 | sed 's/runelite-parent-//')

# Bump versions from above install
cd $BASEDIR
mvn --settings $BASEDIR/travis/settings.xml -U versions:use-latest-versions -DallowSnapshots
if [ $? -ne 0 ] ; then
	exit 1
fi

find $BASEDIR -name pom.xml -exec git add {} \;

git config user.name "Runelite auto updater"
git config user.email runelite@runelite.net

git commit -m "Update $VANILLA_VER"
git pull origin master --no-edit

git remote add githubssh git@githubupdater:runelite/updater
git push githubssh HEAD:master # travis checks out a detached head on a specific commit


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
