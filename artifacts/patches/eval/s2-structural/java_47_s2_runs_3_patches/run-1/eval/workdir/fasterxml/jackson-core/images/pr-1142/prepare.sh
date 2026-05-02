#!/bin/bash
set -e

cd /home/jackson-core
git reset --hard
bash /home/check_git_changes.sh
git checkout f1dc3c512d211ae3e14fb59af231caebf037d510

# apply metamorphic patch (if present)
cat > /home/metamorphic_base.patch << 'EOF_METAMORPHIC_PATCH'
diff --git a/src/main/java/com/fasterxml/jackson/core/Version.java b/src/main/java/com/fasterxml/jackson/core/Version.java
index d70e5e19..ce6af390 100644
--- a/src/main/java/com/fasterxml/jackson/core/Version.java
+++ b/src/main/java/com/fasterxml/jackson/core/Version.java
@@ -36,32 +36,6 @@ public class Version
      */
     protected final String _snapshotInfo;
 
-    /**
-     * @param major Major version number
-     * @param minor Minor version number
-     * @param patchLevel patch level of version
-     * @param snapshotInfo Optional additional string qualifier
-     *
-     * @since 2.1
-     * @deprecated Use variant that takes group and artifact ids
-     */
-    @Deprecated
-    public Version(int major, int minor, int patchLevel, String snapshotInfo)
-    {
-        this(major, minor, patchLevel, snapshotInfo, null, null);
-    }
-
-    public Version(int major, int minor, int patchLevel, String snapshotInfo,
-            String groupId, String artifactId)
-    {
-        _majorVersion = major;
-        _minorVersion = minor;
-        _patchLevel = patchLevel;
-        _snapshotInfo = snapshotInfo;
-        _groupId = (groupId == null) ? "" : groupId;
-        _artifactId = (artifactId == null) ? "" : artifactId;
-    }
-
     /**
      * Method returns canonical "not known" version, which is used as version
      * in cases where actual version information is not known (instead of null).
@@ -71,6 +45,21 @@ public class Version
      */
     public static Version unknownVersion() { return UNKNOWN_VERSION; }
 
+    @Override public String toString() {
+        StringBuilder sb = new StringBuilder();
+        sb.append(_majorVersion).append('.');
+        sb.append(_minorVersion).append('.');
+        sb.append(_patchLevel);
+        if (isSnapshot()) {
+            sb.append('-').append(_snapshotInfo);
+        }
+        return sb.toString();
+    }
+
+    public String toFullString() {
+        return _groupId + '/' + _artifactId + '/' + toString();
+    }
+
     /**
      * @return {@code True} if this instance is the one returned by
      *    call to {@link #unknownVersion()}
@@ -79,8 +68,6 @@ public class Version
      */
     public boolean isUnknownVersion() { return (this == UNKNOWN_VERSION); }
 
-    public boolean isSnapshot() { return (_snapshotInfo != null && _snapshotInfo.length() > 0); }
-
     /**
      * @return {@code True} if this instance is the one returned by
      *    call to {@link #unknownVersion()}
@@ -90,33 +77,23 @@ public class Version
     @Deprecated
     public boolean isUknownVersion() { return isUnknownVersion(); }
 
-    public int getMajorVersion() { return _majorVersion; }
-    public int getMinorVersion() { return _minorVersion; }
-    public int getPatchLevel() { return _patchLevel; }
-
-    public String getGroupId() { return _groupId; }
-    public String getArtifactId() { return _artifactId; }
-
-    public String toFullString() {
-        return _groupId + '/' + _artifactId + '/' + toString();
-    }
-
-    @Override public String toString() {
-        StringBuilder sb = new StringBuilder();
-        sb.append(_majorVersion).append('.');
-        sb.append(_minorVersion).append('.');
-        sb.append(_patchLevel);
-        if (isSnapshot()) {
-            sb.append('-').append(_snapshotInfo);
-        }
-        return sb.toString();
-    }
+    public boolean isSnapshot() { return (_snapshotInfo != null && _snapshotInfo.length() > 0); }
 
     @Override public int hashCode() {
         return _artifactId.hashCode() ^ _groupId.hashCode() ^ _snapshotInfo.hashCode()
             + _majorVersion - _minorVersion + _patchLevel;
     }
 
+    public int getPatchLevel() { return _patchLevel; }
+
+    public int getMinorVersion() { return _minorVersion; }
+
+    public int getMajorVersion() { return _majorVersion; }
+
+    public String getGroupId() { return _groupId; }
+
+    public String getArtifactId() { return _artifactId; }
+
     @Override
     public boolean equals(Object o)
     {
@@ -167,4 +144,30 @@ public class Version
         }
         return diff;
     }
+
+    /**
+     * @param major Major version number
+     * @param minor Minor version number
+     * @param patchLevel patch level of version
+     * @param snapshotInfo Optional additional string qualifier
+     *
+     * @since 2.1
+     * @deprecated Use variant that takes group and artifact ids
+     */
+    @Deprecated
+    public Version(int major, int minor, int patchLevel, String snapshotInfo)
+    {
+        this(major, minor, patchLevel, snapshotInfo, null, null);
+    }
+
+    public Version(int major, int minor, int patchLevel, String snapshotInfo,
+                   String groupId, String artifactId)
+    {
+        _majorVersion = major;
+        _minorVersion = minor;
+        _patchLevel = patchLevel;
+        _snapshotInfo = snapshotInfo;
+        _groupId = (groupId == null) ? "" : groupId;
+        _artifactId = (artifactId == null) ? "" : artifactId;
+    }
 }

EOF_METAMORPHIC_PATCH
git apply /home/metamorphic_base.patch
git add -A && git -c user.email='mswe-agent@metamorphic.py' -c user.name='metamorphic-transformation-patch' commit -m 'Apply `metamorphic_base_patch` transformation to base commit'


bash /home/check_git_changes.sh

file="/home/jackson-core/pom.xml"
old_version="2.15.0-rc2-SNAPSHOT"
new_version="2.15.5-SNAPSHOT"
sed -i "s/$old_version/$new_version/g" "$file"

mvn clean test -Dmaven.test.skip=false -DfailIfNoTests=false || true
