#!/bin/bash
set -e

cd /home/jackson-core
git reset --hard
bash /home/check_git_changes.sh
git checkout f1dc3c512d211ae3e14fb59af231caebf037d510

# apply metamorphic patch (if present)
cat > /home/metamorphic_base.patch << 'EOF_METAMORPHIC_PATCH'
diff --git a/src/main/java/com/fasterxml/jackson/core/ArtifactVersion.java b/src/main/java/com/fasterxml/jackson/core/ArtifactVersion.java
new file mode 100644
index 00000000..9360ac21
--- /dev/null
+++ b/src/main/java/com/fasterxml/jackson/core/ArtifactVersion.java
@@ -0,0 +1,170 @@
+/* Jackson JSON-processor.
+ *
+ * Copyright (c) 2007- Tatu Saloranta, tatu.saloranta@iki.fi
+ */
+
+package com.fasterxml.jackson.core;
+
+/**
+ * Object that encapsulates versioning information of a component.
+ * Version information includes not just version number but also
+ * optionally group and artifact ids of the component being versioned.
+ *<p>
+ * Note that optional group and artifact id properties are new with Jackson 2.0:
+ * if provided, they should align with Maven artifact information.
+ */
+public class ArtifactVersion
+    implements Comparable<ArtifactVersion>, java.io.Serializable
+{
+    private static final long CLASS_VERSION_UID = 1L;
+
+    private final static ArtifactVersion UNDEFINED_VERSION = new ArtifactVersion(0, 0, 0, null, null, null);
+
+    protected final int _majorVersion;
+
+    protected final int _minorVersion;
+
+    protected final int _patchLevel;
+
+    protected final String _groupId;
+
+    protected final String _artifactId;
+
+    /**
+     * Additional information for snapshot versions; null for non-snapshot
+     * (release) versions.
+     */
+    protected final String _snapshotInfo;
+
+    /**
+     * @param primaryComponent Major version number
+     * @param secondaryComponent Minor version number
+     * @param revisionNumber patch level of version
+     * @param preReleaseTag Optional additional string qualifier
+     *
+     * @since 2.1
+     * @deprecated Use variant that takes group and artifact ids
+     */
+    @Deprecated
+    public ArtifactVersion(int primaryComponent, int secondaryComponent, int revisionNumber, String preReleaseTag)
+    {
+        this(primaryComponent, secondaryComponent, revisionNumber, preReleaseTag, null, null);
+    }
+
+    public ArtifactVersion(int primaryComponent, int secondaryComponent, int revisionNumber, String preReleaseTag,
+                           String organizationId, String moduleId)
+    {
+        _majorVersion = primaryComponent;
+        _minorVersion = secondaryComponent;
+        _patchLevel = revisionNumber;
+        _snapshotInfo = preReleaseTag;
+        _groupId = (organizationId == null) ? "" : organizationId;
+        _artifactId = (moduleId == null) ? "" : moduleId;
+    }
+
+    /**
+     * Method returns canonical "not known" version, which is used as version
+     * in cases where actual version information is not known (instead of null).
+     *
+     * @return Version instance to use as a placeholder when actual version is not known
+     *   (or not relevant)
+     */
+    public static ArtifactVersion getUnknownVersion() { return UNDEFINED_VERSION; }
+
+    /**
+     * @return {@code True} if this instance is the one returned by
+     *    call to {@link #getUnknownVersion()}
+     *
+     * @since 2.7 to replace misspelled {@link #isUknownVersion()}
+     */
+    public boolean isUnknownVersion() { return (this == UNDEFINED_VERSION); }
+
+    public boolean isSnapshot() { return (_snapshotInfo != null && _snapshotInfo.length() > 0); }
+
+    /**
+     * @return {@code True} if this instance is the one returned by
+     *    call to {@link #getUnknownVersion()}
+     *
+     * @deprecated Since 2.7 use correctly spelled method {@link #isUnknownVersion()}
+     */
+    @Deprecated
+    public boolean isUknownVersion() { return isUnknownVersion(); }
+
+    public int getMajorVersion() { return _majorVersion; }
+    public int getMinorVersion() { return _minorVersion; }
+    public int getPatchLevel() { return _patchLevel; }
+
+    public String getGroupId() { return _groupId; }
+    public String getArtifactId() { return _artifactId; }
+
+    public String toFullyQualifiedString() {
+        return _groupId + '/' + _artifactId + '/' + toString();
+    }
+
+    @Override public String toString() {
+        StringBuilder builder = new StringBuilder();
+        builder.append(_majorVersion).append('.');
+        builder.append(_minorVersion).append('.');
+        builder.append(_patchLevel);
+        if (isSnapshot()) {
+            builder.append('-').append(_snapshotInfo);
+        }
+        return builder.toString();
+    }
+
+    @Override public int hashCode() {
+        return _artifactId.hashCode() ^ _groupId.hashCode() ^ _snapshotInfo.hashCode()
+            + _majorVersion - _minorVersion + _patchLevel;
+    }
+
+    @Override
+    public boolean equals(Object otherObj)
+    {
+        if (otherObj == this) return true;
+        if (otherObj == null) return false;
+        if (otherObj.getClass() != getClass()) return false;
+        ArtifactVersion thatVersion = (ArtifactVersion) otherObj;
+        return (thatVersion._majorVersion == _majorVersion)
+            && (thatVersion._minorVersion == _minorVersion)
+            && (thatVersion._patchLevel == _patchLevel)
+            && thatVersion._snapshotInfo.equals(_snapshotInfo)
+            && thatVersion._artifactId.equals(_artifactId)
+            && thatVersion._groupId.equals(_groupId)
+            ;
+    }
+
+    @Override
+    public int compareToVersion(ArtifactVersion thatVersion)
+    {
+        if (thatVersion == this) return 0;
+
+        int delta = _groupId.compareTo(thatVersion._groupId);
+        if (delta == 0) {
+            delta = _artifactId.compareTo(thatVersion._artifactId);
+            if (delta == 0) {
+                delta = _majorVersion - thatVersion._majorVersion;
+                if (delta == 0) {
+                    delta = _minorVersion - thatVersion._minorVersion;
+                    if (delta == 0) {
+                        delta = _patchLevel - thatVersion._patchLevel;
+                        if (delta == 0) {
+                            // Snapshot: non-snapshot AFTER snapshot, otherwise alphabetical
+                            if (isSnapshot()) {
+                                if (thatVersion.isSnapshot()) {
+                                    delta = _snapshotInfo.compareTo(thatVersion._snapshotInfo);
+                                } else {
+                                    delta = -1;
+                                }
+                            } else if (thatVersion.isSnapshot()) {
+                                delta = 1;
+                            } else {
+                                delta = 0;
+                            }
+                        }
+                    }
+                }
+            }
+        }
+        return delta;
+    }
+}
diff --git a/src/main/java/com/fasterxml/jackson/core/JsonFactory.java b/src/main/java/com/fasterxml/jackson/core/JsonFactory.java
index 390f0eb6..45048c9e 100644
--- a/src/main/java/com/fasterxml/jackson/core/JsonFactory.java
+++ b/src/main/java/com/fasterxml/jackson/core/JsonFactory.java
@@ -738,7 +738,7 @@ public class JsonFactory
      */
 
     @Override
-    public Version version() {
+    public ArtifactVersion version() {
         return PackageVersion.VERSION;
     }
 
diff --git a/src/main/java/com/fasterxml/jackson/core/JsonGenerator.java b/src/main/java/com/fasterxml/jackson/core/JsonGenerator.java
index d524939a..acc84123 100644
--- a/src/main/java/com/fasterxml/jackson/core/JsonGenerator.java
+++ b/src/main/java/com/fasterxml/jackson/core/JsonGenerator.java
@@ -357,7 +357,7 @@ public abstract class JsonGenerator
      *   {@code jackson-core} jar that contains the class
      */
     @Override
-    public abstract Version version();
+    public abstract ArtifactVersion version();
 
     /*
     /**********************************************************************
diff --git a/src/main/java/com/fasterxml/jackson/core/JsonParser.java b/src/main/java/com/fasterxml/jackson/core/JsonParser.java
index 50f45406..033c9542 100644
--- a/src/main/java/com/fasterxml/jackson/core/JsonParser.java
+++ b/src/main/java/com/fasterxml/jackson/core/JsonParser.java
@@ -641,7 +641,7 @@ public abstract class JsonParser
      *   {@code jackson-core} jar that contains the class
      */
     @Override
-    public abstract Version version();
+    public abstract ArtifactVersion version();
 
     /*
     /**********************************************************
diff --git a/src/main/java/com/fasterxml/jackson/core/ObjectCodec.java b/src/main/java/com/fasterxml/jackson/core/ObjectCodec.java
index aa738929..f2d04f79 100644
--- a/src/main/java/com/fasterxml/jackson/core/ObjectCodec.java
+++ b/src/main/java/com/fasterxml/jackson/core/ObjectCodec.java
@@ -28,7 +28,7 @@ public abstract class ObjectCodec
 
     // Since 2.3
     @Override
-    public abstract Version version();
+    public abstract ArtifactVersion version();
 
     /*
     /**********************************************************
diff --git a/src/main/java/com/fasterxml/jackson/core/Version.java b/src/main/java/com/fasterxml/jackson/core/Version.java
deleted file mode 100644
index d70e5e19..00000000
--- a/src/main/java/com/fasterxml/jackson/core/Version.java
+++ /dev/null
@@ -1,170 +0,0 @@
-/* Jackson JSON-processor.
- *
- * Copyright (c) 2007- Tatu Saloranta, tatu.saloranta@iki.fi
- */
-
-package com.fasterxml.jackson.core;
-
-/**
- * Object that encapsulates versioning information of a component.
- * Version information includes not just version number but also
- * optionally group and artifact ids of the component being versioned.
- *<p>
- * Note that optional group and artifact id properties are new with Jackson 2.0:
- * if provided, they should align with Maven artifact information.
- */
-public class Version
-    implements Comparable<Version>, java.io.Serializable
-{
-    private static final long serialVersionUID = 1L;
-
-    private final static Version UNKNOWN_VERSION = new Version(0, 0, 0, null, null, null);
-
-    protected final int _majorVersion;
-
-    protected final int _minorVersion;
-
-    protected final int _patchLevel;
-
-    protected final String _groupId;
-
-    protected final String _artifactId;
-
-    /**
-     * Additional information for snapshot versions; null for non-snapshot
-     * (release) versions.
-     */
-    protected final String _snapshotInfo;
-
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
-    /**
-     * Method returns canonical "not known" version, which is used as version
-     * in cases where actual version information is not known (instead of null).
-     *
-     * @return Version instance to use as a placeholder when actual version is not known
-     *   (or not relevant)
-     */
-    public static Version unknownVersion() { return UNKNOWN_VERSION; }
-
-    /**
-     * @return {@code True} if this instance is the one returned by
-     *    call to {@link #unknownVersion()}
-     *
-     * @since 2.7 to replace misspelled {@link #isUknownVersion()}
-     */
-    public boolean isUnknownVersion() { return (this == UNKNOWN_VERSION); }
-
-    public boolean isSnapshot() { return (_snapshotInfo != null && _snapshotInfo.length() > 0); }
-
-    /**
-     * @return {@code True} if this instance is the one returned by
-     *    call to {@link #unknownVersion()}
-     *
-     * @deprecated Since 2.7 use correctly spelled method {@link #isUnknownVersion()}
-     */
-    @Deprecated
-    public boolean isUknownVersion() { return isUnknownVersion(); }
-
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
-
-    @Override public int hashCode() {
-        return _artifactId.hashCode() ^ _groupId.hashCode() ^ _snapshotInfo.hashCode()
-            + _majorVersion - _minorVersion + _patchLevel;
-    }
-
-    @Override
-    public boolean equals(Object o)
-    {
-        if (o == this) return true;
-        if (o == null) return false;
-        if (o.getClass() != getClass()) return false;
-        Version other = (Version) o;
-        return (other._majorVersion == _majorVersion)
-            && (other._minorVersion == _minorVersion)
-            && (other._patchLevel == _patchLevel)
-            && other._snapshotInfo.equals(_snapshotInfo)
-            && other._artifactId.equals(_artifactId)
-            && other._groupId.equals(_groupId)
-            ;
-    }
-
-    @Override
-    public int compareTo(Version other)
-    {
-        if (other == this) return 0;
-
-        int diff = _groupId.compareTo(other._groupId);
-        if (diff == 0) {
-            diff = _artifactId.compareTo(other._artifactId);
-            if (diff == 0) {
-                diff = _majorVersion - other._majorVersion;
-                if (diff == 0) {
-                    diff = _minorVersion - other._minorVersion;
-                    if (diff == 0) {
-                        diff = _patchLevel - other._patchLevel;
-                        if (diff == 0) {
-                            // Snapshot: non-snapshot AFTER snapshot, otherwise alphabetical
-                            if (isSnapshot()) {
-                                if (other.isSnapshot()) {
-                                    diff = _snapshotInfo.compareTo(other._snapshotInfo);
-                                } else {
-                                    diff = -1;
-                                }
-                            } else if (other.isSnapshot()) {
-                                diff = 1;
-                            } else {
-                                diff = 0;
-                            }
-                        }
-                    }
-                }
-            }
-        }
-        return diff;
-    }
-}
diff --git a/src/main/java/com/fasterxml/jackson/core/Versioned.java b/src/main/java/com/fasterxml/jackson/core/Versioned.java
index f6ea9562..646756cf 100644
--- a/src/main/java/com/fasterxml/jackson/core/Versioned.java
+++ b/src/main/java/com/fasterxml/jackson/core/Versioned.java
@@ -17,9 +17,9 @@ public interface Versioned {
     /**
      * Method called to detect version of the component that implements this interface;
      * returned version should never be null, but may return specific "not available"
-     * instance (see {@link Version} for details).
+     * instance (see {@link ArtifactVersion} for details).
      *
      * @return Version of the component
      */
-    Version version();
+    ArtifactVersion version();
 }
diff --git a/src/main/java/com/fasterxml/jackson/core/base/GeneratorBase.java b/src/main/java/com/fasterxml/jackson/core/base/GeneratorBase.java
index 75b87d25..3a709abf 100644
--- a/src/main/java/com/fasterxml/jackson/core/base/GeneratorBase.java
+++ b/src/main/java/com/fasterxml/jackson/core/base/GeneratorBase.java
@@ -148,7 +148,7 @@ public abstract class GeneratorBase extends JsonGenerator
      * @return Version number of the generator (version of the jar that contains
      *     generator implementation class)
      */
-    @Override public Version version() { return PackageVersion.VERSION; }
+    @Override public ArtifactVersion version() { return PackageVersion.VERSION; }
 
     @Override
     public Object getCurrentValue() {
diff --git a/src/main/java/com/fasterxml/jackson/core/base/ParserBase.java b/src/main/java/com/fasterxml/jackson/core/base/ParserBase.java
index 8188d31f..9ff8f4f1 100644
--- a/src/main/java/com/fasterxml/jackson/core/base/ParserBase.java
+++ b/src/main/java/com/fasterxml/jackson/core/base/ParserBase.java
@@ -263,7 +263,7 @@ public abstract class ParserBase extends ParserMinimalBase
         _parsingContext = JsonReadContext.createRootContext(dups);
     }
 
-    @Override public Version version() { return PackageVersion.VERSION; }
+    @Override public ArtifactVersion version() { return PackageVersion.VERSION; }
 
     @Override
     public Object getCurrentValue() {
diff --git a/src/main/java/com/fasterxml/jackson/core/json/JsonGeneratorImpl.java b/src/main/java/com/fasterxml/jackson/core/json/JsonGeneratorImpl.java
index 3c8a2923..a3a46c30 100644
--- a/src/main/java/com/fasterxml/jackson/core/json/JsonGeneratorImpl.java
+++ b/src/main/java/com/fasterxml/jackson/core/json/JsonGeneratorImpl.java
@@ -138,7 +138,7 @@ public abstract class JsonGeneratorImpl extends GeneratorBase
      */
 
     @Override
-    public Version version() {
+    public ArtifactVersion version() {
         return VersionUtil.versionFor(getClass());
     }
 
diff --git a/src/main/java/com/fasterxml/jackson/core/util/JsonGeneratorDelegate.java b/src/main/java/com/fasterxml/jackson/core/util/JsonGeneratorDelegate.java
index 5879063d..587897e1 100644
--- a/src/main/java/com/fasterxml/jackson/core/util/JsonGeneratorDelegate.java
+++ b/src/main/java/com/fasterxml/jackson/core/util/JsonGeneratorDelegate.java
@@ -59,7 +59,7 @@ public class JsonGeneratorDelegate extends JsonGenerator
 
     @Override public void setSchema(FormatSchema schema) { delegate.setSchema(schema); }
     @Override public FormatSchema getSchema() { return delegate.getSchema(); }
-    @Override public Version version() { return delegate.version(); }
+    @Override public ArtifactVersion version() { return delegate.version(); }
     @Override public Object getOutputTarget() { return delegate.getOutputTarget(); }
     @Override public int getOutputBuffered() { return delegate.getOutputBuffered(); }
 
diff --git a/src/main/java/com/fasterxml/jackson/core/util/JsonParserDelegate.java b/src/main/java/com/fasterxml/jackson/core/util/JsonParserDelegate.java
index 2ea888bb..92317ab5 100644
--- a/src/main/java/com/fasterxml/jackson/core/util/JsonParserDelegate.java
+++ b/src/main/java/com/fasterxml/jackson/core/util/JsonParserDelegate.java
@@ -72,7 +72,7 @@ public class JsonParserDelegate extends JsonParser
     @Override public FormatSchema getSchema() { return delegate.getSchema(); }
     @Override public void setSchema(FormatSchema schema) { delegate.setSchema(schema); }
     @Override public boolean canUseSchema(FormatSchema schema) {  return delegate.canUseSchema(schema); }
-    @Override public Version version() { return delegate.version(); }
+    @Override public ArtifactVersion version() { return delegate.version(); }
     @Override public Object getInputSource() { return delegate.getInputSource(); }
 
     /*
diff --git a/src/main/java/com/fasterxml/jackson/core/util/VersionUtil.java b/src/main/java/com/fasterxml/jackson/core/util/VersionUtil.java
index d8f830eb..60c3eb83 100644
--- a/src/main/java/com/fasterxml/jackson/core/util/VersionUtil.java
+++ b/src/main/java/com/fasterxml/jackson/core/util/VersionUtil.java
@@ -4,11 +4,11 @@ import java.io.*;
 import java.util.Properties;
 import java.util.regex.Pattern;
 
-import com.fasterxml.jackson.core.Version;
+import com.fasterxml.jackson.core.ArtifactVersion;
 import com.fasterxml.jackson.core.Versioned;
 
 /**
- * Functionality for supporting exposing of component {@link Version}s.
+ * Functionality for supporting exposing of component {@link ArtifactVersion}s.
  * Also contains other misc methods that have no other place to live in.
  *<p>
  * Note that this class can be used in two roles: first, as a static
@@ -36,7 +36,7 @@ public class VersionUtil
     protected VersionUtil() { }
 
     @Deprecated // since 2.9
-    public Version version() { return Version.unknownVersion(); }
+    public ArtifactVersion version() { return ArtifactVersion.getUnknownVersion(); }
 
     /*
     /**********************************************************************
@@ -49,17 +49,17 @@ public class VersionUtil
      * "PackageVersion" in the same package as the given class.
      *<p>
      * If the class could not be found or does not have a public
-     * static Version field named "VERSION", returns "empty" {@link Version}
-     * returned by {@link Version#unknownVersion()}.
+     * static Version field named "VERSION", returns "empty" {@link ArtifactVersion}
+     * returned by {@link ArtifactVersion#getUnknownVersion()}.
      *
      * @param cls Class for which to look version information
      *
      * @return Version information discovered if any;
-     *  {@link Version#unknownVersion()} if none
+     *  {@link ArtifactVersion#getUnknownVersion()} if none
      */
-    public static Version versionFor(Class<?> cls)
+    public static ArtifactVersion versionFor(Class<?> cls)
     {
-        Version v = null;
+        ArtifactVersion v = null;
         try {
             String versionInfoClassName = cls.getPackage().getName() + ".PackageVersion";
             Class<?> vClass = Class.forName(versionInfoClassName, true, cls.getClassLoader());
@@ -72,7 +72,7 @@ public class VersionUtil
         } catch (Exception e) { // ok to be missing (not good but acceptable)
             ;
         }
-        return (v == null) ? Version.unknownVersion() : v;
+        return (v == null) ? ArtifactVersion.getUnknownVersion() : v;
     }
 
     /**
@@ -81,12 +81,12 @@ public class VersionUtil
      * @param cls Class for which to look version information
      *
      * @return Version information discovered if any;
-     *  {@link Version#unknownVersion()} if none
+     *  {@link ArtifactVersion#getUnknownVersion()} if none
      *
      * @deprecated Since 2.12 simply use {@link #versionFor(Class)} instead
      */
     @Deprecated
-    public static Version packageVersionFor(Class<?> cls) {
+    public static ArtifactVersion packageVersionFor(Class<?> cls) {
         return versionFor(cls);
     }
 
@@ -106,7 +106,7 @@ public class VersionUtil
      */
     @SuppressWarnings("resource")
     @Deprecated // since 2.6
-    public static Version mavenVersionFor(ClassLoader cl, String groupId, String artifactId)
+    public static ArtifactVersion mavenVersionFor(ClassLoader cl, String groupId, String artifactId)
     {
         InputStream pomProperties = cl.getResourceAsStream("META-INF/maven/"
                 + groupId.replaceAll("\\.", "/")+ "/" + artifactId + "/pom.properties");
@@ -124,7 +124,7 @@ public class VersionUtil
                 _close(pomProperties);
             }
         }
-        return Version.unknownVersion();
+        return ArtifactVersion.getUnknownVersion();
     }
 
     /**
@@ -135,19 +135,19 @@ public class VersionUtil
      * @param artifactId Maven artifact id to include with version
      *
      * @return Version instance constructed from parsed components, if successful;
-     *    {@link Version#unknownVersion()} if parsing of components fail
+     *    {@link ArtifactVersion#getUnknownVersion()} if parsing of components fail
      */
-    public static Version parseVersion(String s, String groupId, String artifactId)
+    public static ArtifactVersion parseVersion(String s, String groupId, String artifactId)
     {
         if (s != null && (s = s.trim()).length() > 0) {
             String[] parts = V_SEP.split(s);
-            return new Version(parseVersionPart(parts[0]),
+            return new ArtifactVersion(parseVersionPart(parts[0]),
                     (parts.length > 1) ? parseVersionPart(parts[1]) : 0,
                     (parts.length > 2) ? parseVersionPart(parts[2]) : 0,
                     (parts.length > 3) ? parts[3] : null,
                     groupId, artifactId);
         }
-        return Version.unknownVersion();
+        return ArtifactVersion.getUnknownVersion();
     }
 
     protected static int parseVersionPart(String s) {
diff --git a/src/test/java/com/fasterxml/jackson/core/ParserFeatureDefaultsTest.java b/src/test/java/com/fasterxml/jackson/core/ParserFeatureDefaultsTest.java
index 92c57aab..3ea5d8f1 100644
--- a/src/test/java/com/fasterxml/jackson/core/ParserFeatureDefaultsTest.java
+++ b/src/test/java/com/fasterxml/jackson/core/ParserFeatureDefaultsTest.java
@@ -81,7 +81,7 @@ public class ParserFeatureDefaultsTest extends BaseTest
         }
 
         @Override
-        public Version version() {
+        public ArtifactVersion version() {
             return null;
         }
 
diff --git a/src/test/java/com/fasterxml/jackson/core/TestVersions.java b/src/test/java/com/fasterxml/jackson/core/TestVersions.java
index 053b66b8..41462cfa 100644
--- a/src/test/java/com/fasterxml/jackson/core/TestVersions.java
+++ b/src/test/java/com/fasterxml/jackson/core/TestVersions.java
@@ -4,7 +4,7 @@ import com.fasterxml.jackson.core.json.*;
 import com.fasterxml.jackson.core.sym.CharsToNameCanonicalizer;
 
 /**
- * Tests to verify functioning of {@link Version} class.
+ * Tests to verify functioning of {@link ArtifactVersion} class.
  */
 public class TestVersions extends com.fasterxml.jackson.core.BaseTest
 {
@@ -22,15 +22,15 @@ public class TestVersions extends com.fasterxml.jackson.core.BaseTest
     }
 
     public void testMisc() {
-        Version unk = Version.unknownVersion();
+        ArtifactVersion unk = ArtifactVersion.getUnknownVersion();
         assertEquals("0.0.0", unk.toString());
-        assertEquals("//0.0.0", unk.toFullString());
+        assertEquals("//0.0.0", unk.toFullyQualifiedString());
         assertTrue(unk.equals(unk));
 
-        Version other = new Version(2, 8, 4, "",
+        ArtifactVersion other = new ArtifactVersion(2, 8, 4, "",
                 "groupId", "artifactId");
         assertEquals("2.8.4", other.toString());
-        assertEquals("groupId/artifactId/2.8.4", other.toFullString());
+        assertEquals("groupId/artifactId/2.8.4", other.toFullyQualifiedString());
     }
 
     /*
@@ -39,7 +39,7 @@ public class TestVersions extends com.fasterxml.jackson.core.BaseTest
     /**********************************************************
      */
 
-    private void assertVersion(Version v)
+    private void assertVersion(ArtifactVersion v)
     {
         assertEquals(PackageVersion.VERSION, v);
     }
diff --git a/src/test/java/com/fasterxml/jackson/core/VersionTest.java b/src/test/java/com/fasterxml/jackson/core/VersionTest.java
index 69123265..2b3e816e 100644
--- a/src/test/java/com/fasterxml/jackson/core/VersionTest.java
+++ b/src/test/java/com/fasterxml/jackson/core/VersionTest.java
@@ -4,15 +4,15 @@ import org.junit.Test;
 import static org.junit.Assert.*;
 
 /**
- * Unit tests for class {@link Version}.
+ * Unit tests for class {@link ArtifactVersion}.
  *
  **/
 public class VersionTest
 {
     @Test
     public void testEqualsAndHashCode() {
-        Version version1 = new Version(1, 2, 3, "", "", "");
-        Version version2 = new Version(1, 2, 3, "", "", "");
+        ArtifactVersion version1 = new ArtifactVersion(1, 2, 3, "", "", "");
+        ArtifactVersion version2 = new ArtifactVersion(1, 2, 3, "", "", "");
 
         assertEquals(version1, version2);
         assertEquals(version2, version1);
@@ -22,79 +22,79 @@ public class VersionTest
 
   @Test
   public void testCompareToOne() {
-      Version version = Version.unknownVersion();
-      Version versionTwo = new Version(0, (-263), (-1820), "",
+      ArtifactVersion version = ArtifactVersion.getUnknownVersion();
+      ArtifactVersion versionTwo = new ArtifactVersion(0, (-263), (-1820), "",
               "", "");
 
-      assertEquals(263, version.compareTo(versionTwo));
+      assertEquals(263, version.compareToVersion(versionTwo));
   }
 
   @Test
   public void testCompareToReturningZero() {
-      Version version = Version.unknownVersion();
-      Version versionTwo = new Version(0, 0, 0, "",
+      ArtifactVersion version = ArtifactVersion.getUnknownVersion();
+      ArtifactVersion versionTwo = new ArtifactVersion(0, 0, 0, "",
               "", "");
 
-      assertEquals(0, version.compareTo(versionTwo));
+      assertEquals(0, version.compareToVersion(versionTwo));
   }
 
   @Test
   public void testCreatesVersionTaking6ArgumentsAndCallsCompareTo() {
-      Version version = new Version(0, 0, 0, null, null, "");
-      Version versionTwo = new Version(0, 0, 0, "", "", "//0.0.0");
+      ArtifactVersion version = new ArtifactVersion(0, 0, 0, null, null, "");
+      ArtifactVersion versionTwo = new ArtifactVersion(0, 0, 0, "", "", "//0.0.0");
 
-      assertTrue(version.compareTo(versionTwo) < 0);
+      assertTrue(version.compareToVersion(versionTwo) < 0);
   }
 
   @Test
   public void testCompareToTwo() {
-      Version version = Version.unknownVersion();
-      Version versionTwo = new Version((-1), 0, 0, "0.0.0",
+      ArtifactVersion version = ArtifactVersion.getUnknownVersion();
+      ArtifactVersion versionTwo = new ArtifactVersion((-1), 0, 0, "0.0.0",
               "", "");
 
-      assertTrue(version.compareTo(versionTwo) > 0);
+      assertTrue(version.compareToVersion(versionTwo) > 0);
   }
 
   @Test
   public void testCompareToAndCreatesVersionTaking6ArgumentsAndUnknownVersion() {
-      Version version = Version.unknownVersion();
-      Version versionTwo = new Version(0, 0, 0, "//0.0.0", "//0.0.0", "");
+      ArtifactVersion version = ArtifactVersion.getUnknownVersion();
+      ArtifactVersion versionTwo = new ArtifactVersion(0, 0, 0, "//0.0.0", "//0.0.0", "");
 
-      assertTrue(version.compareTo(versionTwo) < 0);
+      assertTrue(version.compareToVersion(versionTwo) < 0);
   }
 
   @Test
   public void testCompareToSnapshotSame() {
-      Version version = new Version(0, 0, 0, "alpha", "com.fasterxml", "bogus");
-      Version versionTwo = new Version(0, 0, 0, "alpha", "com.fasterxml", "bogus");
+      ArtifactVersion version = new ArtifactVersion(0, 0, 0, "alpha", "com.fasterxml", "bogus");
+      ArtifactVersion versionTwo = new ArtifactVersion(0, 0, 0, "alpha", "com.fasterxml", "bogus");
 
-      assertEquals(0, version.compareTo(versionTwo));
+      assertEquals(0, version.compareToVersion(versionTwo));
   }
 
   @Test
   public void testCompareToSnapshotDifferent() {
-      Version version = new Version(0, 0, 0, "alpha", "com.fasterxml", "bogus");
-      Version versionTwo = new Version(0, 0, 0, "beta", "com.fasterxml", "bogus");
+      ArtifactVersion version = new ArtifactVersion(0, 0, 0, "alpha", "com.fasterxml", "bogus");
+      ArtifactVersion versionTwo = new ArtifactVersion(0, 0, 0, "beta", "com.fasterxml", "bogus");
 
-      assertTrue(version.compareTo(versionTwo) < 0);
-      assertTrue(versionTwo.compareTo(version) > 0);
+      assertTrue(version.compareToVersion(versionTwo) < 0);
+      assertTrue(versionTwo.compareToVersion(version) > 0);
   }
 
   @Test
   public void testCompareWhenOnlyFirstHasSnapshot() {
-      Version version = new Version(0, 0, 0, "beta", "com.fasterxml", "bogus");
-      Version versionTwo = new Version(0, 0, 0, null, "com.fasterxml", "bogus");
+      ArtifactVersion version = new ArtifactVersion(0, 0, 0, "beta", "com.fasterxml", "bogus");
+      ArtifactVersion versionTwo = new ArtifactVersion(0, 0, 0, null, "com.fasterxml", "bogus");
 
-      assertTrue(version.compareTo(versionTwo) < 0);
-      assertTrue(versionTwo.compareTo(version) > 0);
+      assertTrue(version.compareToVersion(versionTwo) < 0);
+      assertTrue(versionTwo.compareToVersion(version) > 0);
   }
 
   @Test
   public void testCompareWhenOnlySecondHasSnapshot() {
-      Version version = new Version(0, 0, 0, "", "com.fasterxml", "bogus");
-      Version versionTwo = new Version(0, 0, 0, "beta", "com.fasterxml", "bogus");
+      ArtifactVersion version = new ArtifactVersion(0, 0, 0, "", "com.fasterxml", "bogus");
+      ArtifactVersion versionTwo = new ArtifactVersion(0, 0, 0, "beta", "com.fasterxml", "bogus");
 
-      assertTrue(version.compareTo(versionTwo) > 0);
-      assertTrue(versionTwo.compareTo(version) < 0);
+      assertTrue(version.compareToVersion(versionTwo) > 0);
+      assertTrue(versionTwo.compareToVersion(version) < 0);
   }
 }
diff --git a/src/test/java/com/fasterxml/jackson/core/json/JsonFactoryTest.java b/src/test/java/com/fasterxml/jackson/core/json/JsonFactoryTest.java
index e08126f6..da80c97e 100644
--- a/src/test/java/com/fasterxml/jackson/core/json/JsonFactoryTest.java
+++ b/src/test/java/com/fasterxml/jackson/core/json/JsonFactoryTest.java
@@ -14,7 +14,7 @@ public class JsonFactoryTest
 {
     static class BogusCodec extends ObjectCodec {
         @Override
-        public Version version() { return null; }
+        public ArtifactVersion version() { return null; }
 
         @Override
         public <T> T readValue(JsonParser p, Class<T> valueType) throws IOException {
diff --git a/src/test/java/com/fasterxml/jackson/core/util/TestDelegates.java b/src/test/java/com/fasterxml/jackson/core/util/TestDelegates.java
index 08ae00ce..759f9434 100644
--- a/src/test/java/com/fasterxml/jackson/core/util/TestDelegates.java
+++ b/src/test/java/com/fasterxml/jackson/core/util/TestDelegates.java
@@ -32,8 +32,8 @@ public class TestDelegates extends com.fasterxml.jackson.core.BaseTest
         public TreeNode treeWritten;
 
         @Override
-        public Version version() {
-            return Version.unknownVersion();
+        public ArtifactVersion version() {
+            return ArtifactVersion.getUnknownVersion();
         }
 
         @Override
diff --git a/src/test/java/com/fasterxml/jackson/core/util/TestVersionUtil.java b/src/test/java/com/fasterxml/jackson/core/util/TestVersionUtil.java
index 9d2774e2..3b23d7c3 100644
--- a/src/test/java/com/fasterxml/jackson/core/util/TestVersionUtil.java
+++ b/src/test/java/com/fasterxml/jackson/core/util/TestVersionUtil.java
@@ -1,6 +1,6 @@
 package com.fasterxml.jackson.core.util;
 
-import com.fasterxml.jackson.core.Version;
+import com.fasterxml.jackson.core.ArtifactVersion;
 import com.fasterxml.jackson.core.json.PackageVersion;
 import com.fasterxml.jackson.core.json.UTF8JsonGenerator;
 
@@ -15,13 +15,13 @@ public class TestVersionUtil extends com.fasterxml.jackson.core.BaseTest
 
     public void testVersionParsing()
     {
-        assertEquals(new Version(1, 2, 15, "foo", "group", "artifact"),
+        assertEquals(new ArtifactVersion(1, 2, 15, "foo", "group", "artifact"),
                 VersionUtil.parseVersion("1.2.15-foo", "group", "artifact"));
     }
 
     @SuppressWarnings("deprecation")
     public void testMavenVersionParsing() {
-        assertEquals(new Version(1, 2, 3, "SNAPSHOT", "foo.bar", "foo-bar"),
+        assertEquals(new ArtifactVersion(1, 2, 3, "SNAPSHOT", "foo.bar", "foo-bar"),
                 VersionUtil.mavenVersionFor(TestVersionUtil.class.getClassLoader(), "foo.bar", "foo-bar"));
     }
 
@@ -32,6 +32,6 @@ public class TestVersionUtil extends com.fasterxml.jackson.core.BaseTest
     // [core#248]: make sure not to return `null` but `Version.unknownVersion()`
     public void testVersionForUnknownVersion() {
         // expecting return version.unknownVersion() instead of null
-        assertEquals(Version.unknownVersion(), VersionUtil.versionFor(TestVersionUtil.class));
+        assertEquals(ArtifactVersion.getUnknownVersion(), VersionUtil.versionFor(TestVersionUtil.class));
     }
 }
diff --git a/src/test/java/com/fasterxml/jackson/core/util/VersionUtilTest.java b/src/test/java/com/fasterxml/jackson/core/util/VersionUtilTest.java
index fc666c3d..8ceed264 100644
--- a/src/test/java/com/fasterxml/jackson/core/util/VersionUtilTest.java
+++ b/src/test/java/com/fasterxml/jackson/core/util/VersionUtilTest.java
@@ -1,6 +1,6 @@
 package com.fasterxml.jackson.core.util;
 
-import com.fasterxml.jackson.core.Version;
+import com.fasterxml.jackson.core.ArtifactVersion;
 import org.junit.Test;
 
 import static org.junit.Assert.*;
@@ -14,8 +14,8 @@ public class VersionUtilTest
 {
   @Test
   public void testParseVersionSimple() {
-    Version v = VersionUtil.parseVersion("1.2.3-SNAPSHOT", "group", "artifact");
-    assertEquals("group/artifact/1.2.3-SNAPSHOT", v.toFullString());
+    ArtifactVersion v = VersionUtil.parseVersion("1.2.3-SNAPSHOT", "group", "artifact");
+    assertEquals("group/artifact/1.2.3-SNAPSHOT", v.toFullyQualifiedString());
   }
 
   @Test
@@ -25,7 +25,7 @@ public class VersionUtilTest
 
   @Test
   public void testParseVersionReturningVersionWhereGetMajorVersionIsZero() {
-    Version version = VersionUtil.parseVersion("#M&+m@569P", "#M&+m@569P", "com.fasterxml.jackson.core.util.VersionUtil");
+    ArtifactVersion version = VersionUtil.parseVersion("#M&+m@569P", "#M&+m@569P", "com.fasterxml.jackson.core.util.VersionUtil");
 
     assertEquals(0, version.getMinorVersion());
     assertEquals(0, version.getPatchLevel());
@@ -36,14 +36,14 @@ public class VersionUtilTest
 
   @Test
   public void testParseVersionWithEmptyStringAndEmptyString() {
-    Version version = VersionUtil.parseVersion("", "", "\"g2AT");
+    ArtifactVersion version = VersionUtil.parseVersion("", "", "\"g2AT");
 
     assertTrue(version.isUnknownVersion());
   }
 
   @Test
   public void testParseVersionWithNullAndEmptyString() {
-    Version version = VersionUtil.parseVersion(null, "/nUmRN)3", "");
+    ArtifactVersion version = VersionUtil.parseVersion(null, "/nUmRN)3", "");
 
     assertFalse(version.isSnapshot());
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
