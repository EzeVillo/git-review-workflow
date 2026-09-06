#!/bin/sh
set -eu
platform_version=$(sed -n 's/^platformVersion *= *//p' /work/jetbrains-plugin/gradle.properties | tr -d '\r')
plugin_version=$(sed -n 's/^pluginVersion *= *//p' /work/jetbrains-plugin/gradle.properties | tr -d '\r')
IDE=$(find /root/.gradle/caches -type f -path "*/idea-$platform_version/bin/idea.sh" -print -quit)
if [ -z "$IDE" ]; then
    echo "IDE $platform_version was not found in the Gradle cache. Build the capture plugin first." >&2
    exit 1
fi
IDE=${IDE%/bin/idea.sh}
rm -f /tmp/jb-ready /tmp/jb-command /tmp/jb-done /tmp/jb-error
mkdir -p /film/plugins /film/config/options /film/system
cd /film/plugins
/opt/openjdk/bin/jar xf "/work/jetbrains-plugin/build/distributions/git-review-workflow-$plugin_version.zip"
cat > /film/idea.properties <<'PROP'
idea.config.path=/film/config
idea.system.path=/film/system
idea.plugins.path=/film/plugins
idea.log.path=/film/log
ide.show.tips.on.startup.default.value=false
idea.trust.all.projects=true
idea.initially.ask.config=false
PROP
cat > /film/config/options/other.xml <<'XML'
<application><component name="PropertiesComponent"><property name="ide.mac.file.chooser.native" value="false"/><property name="ide.mac.message.dialogs.as.sheets" value="false"/></component><component name="NotRoamableUiSettings"><option name="fontSize" value="16"/></component></application>
XML
cat > /film/config/options/ide.general.xml <<'XML'
<application><component name="GeneralSettings"><option name="showTipsOnStartup" value="false"/></component></application>
XML
cat > /film/config/disabled_plugins.txt <<'PLUGINS'
com.intellij.ml.llm
com.jetbrains.ai
PLUGINS
Xvfb :99 -screen 0 1440x900x24 -ac > /tmp/xvfb.log 2>&1 &
export DISPLAY=:99
export IDEA_PROPERTIES=/film/idea.properties
export PATH="/work/bin:$PATH"
exec "$IDE/bin/idea.sh" /film/rate-limit > /tmp/idea.log 2>&1
