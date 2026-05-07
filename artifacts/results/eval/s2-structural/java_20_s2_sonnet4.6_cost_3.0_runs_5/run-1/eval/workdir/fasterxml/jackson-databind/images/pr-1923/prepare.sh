#!/bin/bash
set -e

cd /home/jackson-databind
git reset --hard
bash /home/check_git_changes.sh
git checkout 5d4eb514820a7cfc7135e4b515dd9531ebdd523a

# apply metamorphic patch (if present)
cat > /home/metamorphic_base.patch << 'EOF_METAMORPHIC_PATCH'
diff --git a/src/main/java/com/fasterxml/jackson/databind/deser/BeanDeserializerFactory.java b/src/main/java/com/fasterxml/jackson/databind/deser/BeanDeserializerFactory.java
index b462c0c74..1bce4be98 100644
--- a/src/main/java/com/fasterxml/jackson/databind/deser/BeanDeserializerFactory.java
+++ b/src/main/java/com/fasterxml/jackson/databind/deser/BeanDeserializerFactory.java
@@ -12,7 +12,7 @@ import com.fasterxml.jackson.databind.deser.impl.*;
 import com.fasterxml.jackson.databind.deser.std.ThrowableDeserializer;
 import com.fasterxml.jackson.databind.introspect.*;
 import com.fasterxml.jackson.databind.jsontype.TypeDeserializer;
-import com.fasterxml.jackson.databind.jsontype.impl.SubTypeValidator;
+import com.fasterxml.jackson.databind.util.SubTypeValidator;
 import com.fasterxml.jackson.databind.util.ArrayBuilders;
 import com.fasterxml.jackson.databind.util.ClassUtil;
 import com.fasterxml.jackson.databind.util.SimpleBeanPropertyDefinition;
diff --git a/src/main/java/com/fasterxml/jackson/databind/jsontype/impl/SubTypeValidator.java b/src/main/java/com/fasterxml/jackson/databind/util/SubTypeValidator.java
similarity index 98%
rename from src/main/java/com/fasterxml/jackson/databind/jsontype/impl/SubTypeValidator.java
rename to src/main/java/com/fasterxml/jackson/databind/util/SubTypeValidator.java
index 45a76169f..d8cfc8957 100644
--- a/src/main/java/com/fasterxml/jackson/databind/jsontype/impl/SubTypeValidator.java
+++ b/src/main/java/com/fasterxml/jackson/databind/util/SubTypeValidator.java
@@ -1,4 +1,4 @@
-package com.fasterxml.jackson.databind.jsontype.impl;
+package com.fasterxml.jackson.databind.util;
 
 import java.util.Collections;
 import java.util.HashSet;
@@ -60,10 +60,6 @@ public class SubTypeValidator
 
     private final static SubTypeValidator instance = new SubTypeValidator();
 
-    protected SubTypeValidator() { }
-
-    public static SubTypeValidator instance() { return instance; }
-
     public void validateSubType(DeserializationContext ctxt, JavaType type) throws JsonMappingException
     {
         // There are certain nasty classes that could cause problems, mostly
@@ -96,4 +92,8 @@ public class SubTypeValidator
         throw JsonMappingException.from(ctxt,
                 String.format("Illegal type (%s) to deserialize: prevented for security reasons", full));
     }
+
+    public static SubTypeValidator instance() { return instance; }
+
+    protected SubTypeValidator() { }
 }

EOF_METAMORPHIC_PATCH
git apply /home/metamorphic_base.patch
git add -A && git -c user.email='mswe-agent@metamorphic.py' -c user.name='metamorphic-transformation-patch' commit -m 'Apply `metamorphic_base_patch` transformation to base commit'


bash /home/check_git_changes.sh

file="/home/jackson-databind/pom.xml"
old_version="2.15.0-rc2-SNAPSHOT"
new_version="2.15.5-SNAPSHOT"
sed -i "s/$old_version/$new_version/g" "$file"

mvn clean test -Dmaven.test.skip=false -DfailIfNoTests=false || true
