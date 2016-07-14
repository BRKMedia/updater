#!/bin/bash

JAVA_ARGS="-ea -Xmx512m"

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
#RUNELITE_REPOSITORY_URL=

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

# update deobfuscated client repository
cd $RS_CLIENT_REPO/runescape-client
git rm src/main/java/*.java
mkdir -p src/main/java/
cp /tmp/dest/*.java src/main/java/
git add src/main/java/

# bump versions
find $RS_CLIENT_REPO -name pom.xml -exec sed -i "s/<version>.*<\/version>.*rs version.*/<version>$VANILLA_VER.1-SNAPSHOT<\/version> <!-- rs version -->/" {} \;

cd $RS_CLIENT_REPO/runescape-client-injector
# update vanilla jar version for injector, which was deployed above
mvn --settings $BASEDIR/travis/settings.xml -U versions:use-latest-versions -DincludesList=net.runelite.rs:vanilla:jar
if [ $? -ne 0 ] ; then
	exit 1
fi

cd $RS_CLIENT_REPO

git config user.name "Runelite auto updater"
git config user.email runelite@runelite.net

find $RS_CLIENT_REPO -name pom.xml -exec git add {} \;
git commit -m "Update $VANILLA_VER"
echo "Commited update $VANILLA_VER to $RS_CLIENT_REPO"
git pull --no-edit
git push

# Perform release
cd $RS_CLIENT_REPO
mvn --settings $BASEDIR/travis/settings.xml clean install -DskipTests
if [ $? -ne 0 ] ; then
	exit 1
fi

cp ~/.ssh/runelite ~/.ssh/github # copy key for maven plugin, as it pushes to mavens configured <scm> repo
mvn --settings $BASEDIR/travis/settings.xml release:clean release:prepare release:perform -Darguments="-DskipTests" -B
if [ $? -ne 0 ] ; then
	exit 1
fi
rm -f ~/.ssh/github

# Install now that theres a new SNAPSHOT version, for below versions:use-latest-versions
mvn --settings $BASEDIR/travis/settings.xml clean install -DskipTests
if [ $? -ne 0 ] ; then
	exit 1
fi

# I couldn't figure out a better way to do this
RELEASED_VER=$(git show `git describe --abbrev=0`:runelite-client/pom.xml | grep version | head -n3 | tail -n1 | sed 's/[a-z<>/\t]*//g')

# Now update our version, for the next game update
cd $BASEDIR
find $BASEDIR -name pom.xml -exec sed -i "s/<version>.*<\/version>.*rs version.*/<version>$VANILLA_VER.1-SNAPSHOT<\/version> <!-- rs version -->/" {} \;

# Bump versions from above install
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
echo '{"client":{"groupId":"net.runelite","artifactId":"client","version":"VERSION","classifier":"","extension":"jar","properties":{}},"clientJvmArguments":["-Xmx256m","-Xss2m","-Dsun.java2d.noddraw\u003dtrue","-XX:CompileThreshold\u003d1500","-Xincgc","-XX:+UseConcMarkSweepGC","-XX:+UseParNewGC"]}' | sed "s/VERSION/$RELEASED_VER/" > bootstrap.json
git add bootstrap.json

git config user.name "Runelite auto updater"
git config user.email runelite@runelite.net

git commit -m "Release $RELEASED_VER"
git pull --no-edit
git push
