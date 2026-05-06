#!/bin/bash
set -e

cd /home/jackson-databind
git reset --hard
bash /home/check_git_changes.sh
git checkout 5d4eb514820a7cfc7135e4b515dd9531ebdd523a

# apply metamorphic patch (if present)
cat > /home/metamorphic_base.patch << 'EOF_METAMORPHIC_PATCH'
diff --git a/src/main/java/com/fasterxml/jackson/databind/deser/BeanDeserializerFactory.java b/src/main/java/com/fasterxml/jackson/databind/deser/BeanDeserializerFactory.java
index b462c0c74..8fff81400 100644
--- a/src/main/java/com/fasterxml/jackson/databind/deser/BeanDeserializerFactory.java
+++ b/src/main/java/com/fasterxml/jackson/databind/deser/BeanDeserializerFactory.java
@@ -12,7 +12,7 @@ import com.fasterxml.jackson.databind.deser.impl.*;
 import com.fasterxml.jackson.databind.deser.std.ThrowableDeserializer;
 import com.fasterxml.jackson.databind.introspect.*;
 import com.fasterxml.jackson.databind.jsontype.TypeDeserializer;
-import com.fasterxml.jackson.databind.jsontype.impl.SubTypeValidator;
+import com.fasterxml.jackson.databind.jsontype.impl.SubtypeValidator;
 import com.fasterxml.jackson.databind.util.ArrayBuilders;
 import com.fasterxml.jackson.databind.util.ClassUtil;
 import com.fasterxml.jackson.databind.util.SimpleBeanPropertyDefinition;
@@ -846,6 +846,6 @@ public class BeanDeserializerFactory
             BeanDescription beanDesc)
         throws JsonMappingException
     {
-        SubTypeValidator.instance().validateSubType(ctxt, type);
+        SubtypeValidator.getInstance().validateSubtype(ctxt, type);
     }
 }
diff --git a/src/main/java/com/fasterxml/jackson/databind/jsontype/impl/SubTypeValidator.java b/src/main/java/com/fasterxml/jackson/databind/jsontype/impl/SubtypeValidator.java
similarity index 77%
rename from src/main/java/com/fasterxml/jackson/databind/jsontype/impl/SubTypeValidator.java
rename to src/main/java/com/fasterxml/jackson/databind/jsontype/impl/SubtypeValidator.java
index 45a76169f..e4bf3525f 100644
--- a/src/main/java/com/fasterxml/jackson/databind/jsontype/impl/SubTypeValidator.java
+++ b/src/main/java/com/fasterxml/jackson/databind/jsontype/impl/SubtypeValidator.java
@@ -16,7 +16,7 @@ import com.fasterxml.jackson.databind.JsonMappingException;
  *
  * @since 2.8.11
  */
-public class SubTypeValidator
+public class SubtypeValidator
 {
     protected final static String PREFIX_STRING = "org.springframework.";
     /**
@@ -58,34 +58,34 @@ public class SubTypeValidator
      */
     protected Set<String> _cfgIllegalClassNames = DEFAULT_NO_DESER_CLASS_NAMES;
 
-    private final static SubTypeValidator instance = new SubTypeValidator();
+    private final static SubtypeValidator DEFAULT_VALIDATOR = new SubtypeValidator();
 
-    protected SubTypeValidator() { }
+    protected SubtypeValidator() { }
 
-    public static SubTypeValidator instance() { return instance; }
+    public static SubtypeValidator getInstance() { return DEFAULT_VALIDATOR; }
 
-    public void validateSubType(DeserializationContext ctxt, JavaType type) throws JsonMappingException
+    public void validateSubtype(DeserializationContext deserializationContext, JavaType javaRepresentation) throws JsonMappingException
     {
         // There are certain nasty classes that could cause problems, mostly
         // via default typing -- catch them here.
-        final Class<?> raw = type.getRawClass();
-        String full = raw.getName();
+        final Class<?> baseClass = javaRepresentation.getRawClass();
+        String fullyQualifiedName = baseClass.getName();
 
         main_check:
         do {
-            if (_cfgIllegalClassNames.contains(full)) {
+            if (_cfgIllegalClassNames.contains(fullyQualifiedName)) {
                 break;
             }
 
             // 18-Dec-2017, tatu: As per [databind#1855], need bit more sophisticated handling
             //    for some Spring framework types
-            if (full.startsWith(PREFIX_STRING)) {
-                for (Class<?> cls = raw; cls != Object.class; cls = cls.getSuperclass()) {
-                    String name = cls.getSimpleName();
+            if (fullyQualifiedName.startsWith(PREFIX_STRING)) {
+                for (Class<?> targetClass = baseClass; targetClass != Object.class; targetClass = targetClass.getSuperclass()) {
+                    String simpleIdentifier = targetClass.getSimpleName();
                     // looking for "AbstractBeanFactoryPointcutAdvisor" but no point to allow any is there?
-                    if ("AbstractPointcutAdvisor".equals(name)
+                    if ("AbstractPointcutAdvisor".equals(simpleIdentifier)
                             // ditto  for "FileSystemXmlApplicationContext": block all ApplicationContexts
-                            || "AbstractApplicationContext".equals(name)) {
+                            || "AbstractApplicationContext".equals(simpleIdentifier)) {
                         break main_check;
                     }
                 }
@@ -93,7 +93,7 @@ public class SubTypeValidator
             return;
         } while (false);
 
-        throw JsonMappingException.from(ctxt,
-                String.format("Illegal type (%s) to deserialize: prevented for security reasons", full));
+        throw JsonMappingException.from(deserializationContext,
+                String.format("Illegal type (%s) to deserialize: prevented for security reasons", fullyQualifiedName));
     }
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
