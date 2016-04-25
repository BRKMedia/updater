#!/bin/bash

JAVA_ARGS="-ea -Xmx512m"
FERNFLOWER_JAR=/home/runelite/fernflower/fernflower.jar

DEOB_PATH=`echo $DEOB_PATH | sed 's/\.jar$/-jar-with-dependencies.jar/'`

echo RS API at $RS_API_PATH
echo RS client $RS_CLIENT_PATH
echo Deobfuscator at $DEOB_PATH

JAV_CONFIG=/tmp/jav_config.ws
VANILLA=/tmp/vanilla.jar
DEOBFUSCATED=/tmp/deobfuscated.jar
DEOBFUSCATED_WITH_MAPPINGS=/tmp/deobfuscated_with_mappings.jar
VANILLA_INJECTED=/tmp/vanilla_injected.jar

curl -L oldschool.runescape.com/jav_config.ws > $JAV_CONFIG

CODEBASE=$(grep codebase $JAV_CONFIG | cut -d'=' -f2)
INITIAL_JAR=$(grep initial_jar $JAV_CONFIG | cut -d'=' -f2)
JAR_URL=$CODEBASE$INITIAL_JAR

echo Downloading vanilla client from $JAR_URL

#rm -f $VANILLA
#wget $JAR_URL -O $VANILLA

# get version of vanilla
VANILLA_VER=$(java -cp $DEOB_PATH net.runelite.deob.clientver.ClientVersionMain $VANILLA)
echo "Vanilla client version $VANILLA_VER"

# step 1. deobfuscate vanilla jar. store in $DEOBFUSCATED.
#rm -f $DEOBFUSCATED
#java $JAVA_ARGS -cp $DEOB_PATH net.runelite.deob.Deob $VANILLA $DEOBFUSCATED

# step 2. map old deob (which has the mapping annotations) -> new client
#rm -f $DEOBFUSCATED_WITH_MAPPINGS
#java $JAVA_ARGS -cp $DEOB_PATH net.runelite.deob.updater.UpdateMappings $RS_CLIENT_PATH $DEOBFUSCATED $DEOBFUSCATED_WITH_MAPPINGS

# step 3. inject vanilla client.
#rm -f $VANILLA_INJECTED
#java $JAVA_ARGS -cp $DEOB_PATH net.runelite.deob.updater.UpdateInject $DEOBFUSCATED_WITH_MAPPINGS $VANILLA $VANILLA_INJECTED

cd src/main/resources
rm -f *.class net META-INF
jar xf $VANILLA_INJECTED
# step 4. deploy injected client.
#mvn deploy:deploy-file -DgroupId=net.runelite.rs -DartifactId=client -Dversion=$VANILLA_VER -Dpackaging=jar -Dfile=$VANILLA_INJECTED -Durl=$DEPLOY_REPO_URL

# also deploy vanilla client
#mvn deploy:deploy-file -DgroupId=net.runelite.rs -DartifactId=client-vanilla -Dversion=$VANILLA_VER -Dpackaging=jar -Dfile=$VANILLA -Durl=$DEPLOY_REPO_URL

mvn deploy

exit 0

# step 5. decompile deobfuscated mapped client.
rm -rf /tmp/dest
mkdir /tmp/dest
java -Xmx1024m -jar $FERNFLOWER_JAR $DEOBFUSCATED_WITH_MAPPINGS /tmp/dest/

# extract source
cd /tmp/dest
jar xf *.jar
cd -

# update deobfuscated client repository
cd $RS_CLIENT_REPO
git rm src/main/java/*.java
mkdir -p src/main/java/
cp /tmp/dest/*.java src/main/java/
git add src/main/java/

git config user.name "Runelite auto updater"
git config user.email runelite@runelite.net

git commit -m "Update $VANILLA_VER"
#git push

