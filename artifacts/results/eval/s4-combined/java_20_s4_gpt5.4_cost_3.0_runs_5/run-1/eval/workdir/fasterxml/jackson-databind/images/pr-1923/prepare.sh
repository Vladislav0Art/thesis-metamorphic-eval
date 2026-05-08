#!/bin/bash
set -e

cd /home/jackson-databind
git reset --hard
bash /home/check_git_changes.sh
git checkout 5d4eb514820a7cfc7135e4b515dd9531ebdd523a

# apply metamorphic patch (if present)
cat > /home/metamorphic_base.patch << 'EOF_METAMORPHIC_PATCH'
diff --git a/src/main/java/com/fasterxml/jackson/databind/deser/BeanDeserializerFactory.java b/src/main/java/com/fasterxml/jackson/databind/deser/BeanDeserializerFactory.java
index b462c0c74..351ece3c4 100644
--- a/src/main/java/com/fasterxml/jackson/databind/deser/BeanDeserializerFactory.java
+++ b/src/main/java/com/fasterxml/jackson/databind/deser/BeanDeserializerFactory.java
@@ -12,7 +12,7 @@ import com.fasterxml.jackson.databind.deser.impl.*;
 import com.fasterxml.jackson.databind.deser.std.ThrowableDeserializer;
 import com.fasterxml.jackson.databind.introspect.*;
 import com.fasterxml.jackson.databind.jsontype.TypeDeserializer;
-import com.fasterxml.jackson.databind.jsontype.impl.SubTypeValidator;
+import com.fasterxml.jackson.databind.util.SubTypeNameValidator;
 import com.fasterxml.jackson.databind.util.ArrayBuilders;
 import com.fasterxml.jackson.databind.util.ClassUtil;
 import com.fasterxml.jackson.databind.util.SimpleBeanPropertyDefinition;
@@ -846,6 +846,6 @@ public class BeanDeserializerFactory
             BeanDescription beanDesc)
         throws JsonMappingException
     {
-        SubTypeValidator.instance().validateSubType(ctxt, type);
+        SubTypeNameValidator.getInstance().validateSubTypeName(ctxt, type);
     }
 }
diff --git a/src/main/java/com/fasterxml/jackson/databind/jsontype/impl/SubTypeValidator.java b/src/main/java/com/fasterxml/jackson/databind/util/SubTypeNameValidator.java
similarity index 75%
rename from src/main/java/com/fasterxml/jackson/databind/jsontype/impl/SubTypeValidator.java
rename to src/main/java/com/fasterxml/jackson/databind/util/SubTypeNameValidator.java
index 45a76169f..e67e2fb2b 100644
--- a/src/main/java/com/fasterxml/jackson/databind/jsontype/impl/SubTypeValidator.java
+++ b/src/main/java/com/fasterxml/jackson/databind/util/SubTypeNameValidator.java
@@ -1,4 +1,4 @@
-package com.fasterxml.jackson.databind.jsontype.impl;
+package com.fasterxml.jackson.databind.util;
 
 import java.util.Collections;
 import java.util.HashSet;
@@ -16,7 +16,7 @@ import com.fasterxml.jackson.databind.JsonMappingException;
  *
  * @since 2.8.11
  */
-public class SubTypeValidator
+public class SubTypeNameValidator
 {
     protected final static String PREFIX_STRING = "org.springframework.";
     /**
@@ -58,34 +58,30 @@ public class SubTypeValidator
      */
     protected Set<String> _cfgIllegalClassNames = DEFAULT_NO_DESER_CLASS_NAMES;
 
-    private final static SubTypeValidator instance = new SubTypeValidator();
+    private final static SubTypeNameValidator SUBTYPE_NAME_VALIDATOR = new SubTypeNameValidator();
 
-    protected SubTypeValidator() { }
-
-    public static SubTypeValidator instance() { return instance; }
-
-    public void validateSubType(DeserializationContext ctxt, JavaType type) throws JsonMappingException
+    public void validateSubTypeName(DeserializationContext deserializationContext, JavaType javaRepresentation) throws JsonMappingException
     {
         // There are certain nasty classes that could cause problems, mostly
         // via default typing -- catch them here.
-        final Class<?> raw = type.getRawClass();
-        String full = raw.getName();
+        final Class<?> underlyingClass = javaRepresentation.getRawClass();
+        String qualifiedName = underlyingClass.getName();
 
         main_check:
         do {
-            if (_cfgIllegalClassNames.contains(full)) {
+            if (_cfgIllegalClassNames.contains(qualifiedName)) {
                 break;
             }
 
             // 18-Dec-2017, tatu: As per [databind#1855], need bit more sophisticated handling
             //    for some Spring framework types
-            if (full.startsWith(PREFIX_STRING)) {
-                for (Class<?> cls = raw; cls != Object.class; cls = cls.getSuperclass()) {
-                    String name = cls.getSimpleName();
+            if (qualifiedName.startsWith(PREFIX_STRING)) {
+                for (Class<?> targetClass = underlyingClass; targetClass != Object.class; targetClass = targetClass.getSuperclass()) {
+                    String identifier = targetClass.getSimpleName();
                     // looking for "AbstractBeanFactoryPointcutAdvisor" but no point to allow any is there?
-                    if ("AbstractPointcutAdvisor".equals(name)
+                    if ("AbstractPointcutAdvisor".equals(identifier)
                             // ditto  for "FileSystemXmlApplicationContext": block all ApplicationContexts
-                            || "AbstractApplicationContext".equals(name)) {
+                            || "AbstractApplicationContext".equals(identifier)) {
                         break main_check;
                     }
                 }
@@ -93,7 +89,11 @@ public class SubTypeValidator
             return;
         } while (false);
 
-        throw JsonMappingException.from(ctxt,
-                String.format("Illegal type (%s) to deserialize: prevented for security reasons", full));
+        throw JsonMappingException.from(deserializationContext,
+                String.format("Illegal type (%s) to deserialize: prevented for security reasons", qualifiedName));
     }
+
+    public static SubTypeNameValidator getInstance() { return SUBTYPE_NAME_VALIDATOR; }
+
+    protected SubTypeNameValidator() { }
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
