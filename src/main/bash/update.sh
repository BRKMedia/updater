#!/bin/bash

JAVA_ARGS="-ea -Xmx512m"
FERNFLOWER_JAR=/home/runelite/fernflower/fernflower.jar

echo RS API at $RS_API_PATH
echo RS client $RS_CLIENT_PATH
echo Deobfuscator at $DEOB_PATH

JAV_CONFIG=/tmp/jav_config.ws
VANILLA=/tmp/vanilla.jar
DEOBFUSCATED=/tmp/deobfuscated.jar
DEOBFUSCATED_WITH_MAPPINGS=/tmp/deobfuscated_with_mappings.jar
VANILLA_INJECTED=/tmp/vanilla_injected.jar
RS_CLIENT_REPO=/home/runelite/runelite

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

# step 1. deobfuscate vanilla jar. store in $DEOBFUSCATED.
rm -f $DEOBFUSCATED
java $JAVA_ARGS -cp $DEOB_PATH net.runelite.deob.Deob $VANILLA $DEOBFUSCATED

# step 2. map old deob (which has the mapping annotations) -> new client
rm -f $DEOBFUSCATED_WITH_MAPPINGS
java $JAVA_ARGS -cp $DEOB_PATH net.runelite.deob.updater.UpdateMappings $RS_CLIENT_PATH $DEOBFUSCATED $DEOBFUSCATED_WITH_MAPPINGS

# step 5. decompile deobfuscated mapped client.
rm -rf /tmp/dest
mkdir /tmp/dest
java -Xmx1024m -jar $FERNFLOWER_JAR $DEOBFUSCATED_WITH_MAPPINGS /tmp/dest/

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
find $RS_CLIENT_REPO -name pom.xml -exec git add {} \;

git config user.name "Runelite auto updater"
git config user.email runelite@runelite.net

git commit -m "Update $VANILLA_VER"
#git push

# Now update our version
cd $BASEDIR
find $BASEDIR -name pom.xml -exec sed -i "s/<version>.*<\/version>.*rs version.*/<version>$VANILLA_VER.1-SNAPSHOT<\/version> <!-- rs version -->/" {} \;

git config user.name "Runelite auto updater"
git config user.email runelite@runelite.net

git commit -m "Update $VANILLA_VER"
#git push
