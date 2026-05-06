#!/bin/bash
set -e

cd /home/jackson-databind
git reset --hard
bash /home/check_git_changes.sh
git checkout bfeb1fa9dc4c889f8027b80abb2f77996efd9b70

# apply metamorphic patch (if present)
cat > /home/metamorphic_base.patch << 'EOF_METAMORPHIC_PATCH'
diff --git a/src/main/java/com/fasterxml/jackson/databind/DeserializationConfig.java b/src/main/java/com/fasterxml/jackson/databind/DeserializationConfig.java
index 8867935fc..91e823ab2 100644
--- a/src/main/java/com/fasterxml/jackson/databind/DeserializationConfig.java
+++ b/src/main/java/com/fasterxml/jackson/databind/DeserializationConfig.java
@@ -22,7 +22,7 @@ import com.fasterxml.jackson.databind.util.RootNameLookup;
  * "fluent factory" methods.
  */
 public final class DeserializationConfig
-    extends MapperConfigBase<DeserializationFeature, DeserializationConfig>
+    extends MapperConfigBase<DeserializationFeatures, DeserializationConfig>
     implements java.io.Serializable // since 2.1
 {
     // since 2.9
@@ -53,7 +53,7 @@ public final class DeserializationConfig
      */
 
     /**
-     * Set of {@link DeserializationFeature}s enabled.
+     * Set of {@link DeserializationFeatures}s enabled.
      */
     protected final int _deserFeatures;
 
@@ -101,7 +101,7 @@ public final class DeserializationConfig
             ConfigOverrides configOverrides)
     {
         super(base, str, mixins, rootNames, configOverrides);
-        _deserFeatures = collectFeatureDefaults(DeserializationFeature.class);
+        _deserFeatures = collectFeatureDefaults(DeserializationFeatures.class);
         _nodeFactory = JsonNodeFactory.instance;
         _problemHandlers = null;
         _parserFeatures = 0;
@@ -316,7 +316,7 @@ public final class DeserializationConfig
      * Fluent factory method that will construct and return a new configuration
      * object instance with specified features enabled.
      */
-    public DeserializationConfig with(DeserializationFeature feature)
+    public DeserializationConfig with(DeserializationFeatures feature)
     {
         int newDeserFeatures = (_deserFeatures | feature.getMask());
         return (newDeserFeatures == _deserFeatures) ? this :
@@ -329,11 +329,11 @@ public final class DeserializationConfig
      * Fluent factory method that will construct and return a new configuration
      * object instance with specified features enabled.
      */
-    public DeserializationConfig with(DeserializationFeature first,
-            DeserializationFeature... features)
+    public DeserializationConfig with(DeserializationFeatures first,
+                                      DeserializationFeatures... features)
     {
         int newDeserFeatures = _deserFeatures | first.getMask();
-        for (DeserializationFeature f : features) {
+        for (DeserializationFeatures f : features) {
             newDeserFeatures |= f.getMask();
         }
         return (newDeserFeatures == _deserFeatures) ? this :
@@ -346,10 +346,10 @@ public final class DeserializationConfig
      * Fluent factory method that will construct and return a new configuration
      * object instance with specified features enabled.
      */
-    public DeserializationConfig withFeatures(DeserializationFeature... features)
+    public DeserializationConfig withFeatures(DeserializationFeatures... features)
     {
         int newDeserFeatures = _deserFeatures;
-        for (DeserializationFeature f : features) {
+        for (DeserializationFeatures f : features) {
             newDeserFeatures |= f.getMask();
         }
         return (newDeserFeatures == _deserFeatures) ? this :
@@ -362,7 +362,7 @@ public final class DeserializationConfig
      * Fluent factory method that will construct and return a new configuration
      * object instance with specified feature disabled.
      */
-    public DeserializationConfig without(DeserializationFeature feature)
+    public DeserializationConfig without(DeserializationFeatures feature)
     {
         int newDeserFeatures = _deserFeatures & ~feature.getMask();
         return (newDeserFeatures == _deserFeatures) ? this :
@@ -375,11 +375,11 @@ public final class DeserializationConfig
      * Fluent factory method that will construct and return a new configuration
      * object instance with specified features disabled.
      */
-    public DeserializationConfig without(DeserializationFeature first,
-            DeserializationFeature... features)
+    public DeserializationConfig without(DeserializationFeatures first,
+                                         DeserializationFeatures... features)
     {
         int newDeserFeatures = _deserFeatures & ~first.getMask();
-        for (DeserializationFeature f : features) {
+        for (DeserializationFeatures f : features) {
             newDeserFeatures &= ~f.getMask();
         }
         return (newDeserFeatures == _deserFeatures) ? this :
@@ -392,10 +392,10 @@ public final class DeserializationConfig
      * Fluent factory method that will construct and return a new configuration
      * object instance with specified features disabled.
      */
-    public DeserializationConfig withoutFeatures(DeserializationFeature... features)
+    public DeserializationConfig withoutFeatures(DeserializationFeatures... features)
     {
         int newDeserFeatures = _deserFeatures;
-        for (DeserializationFeature f : features) {
+        for (DeserializationFeatures f : features) {
             newDeserFeatures &= ~f.getMask();
         }
         return (newDeserFeatures == _deserFeatures) ? this :
@@ -641,10 +641,10 @@ public final class DeserializationConfig
         if (_rootName != null) { // empty String disables wrapping; non-empty enables
             return !_rootName.isEmpty();
         }
-        return isEnabled(DeserializationFeature.UNWRAP_ROOT_VALUE);
+        return isEnabled(DeserializationFeatures.UNWRAP_ROOT_VALUE);
     }
 
-    public final boolean isEnabled(DeserializationFeature f) {
+    public final boolean isEnabled(DeserializationFeatures f) {
         return (_deserFeatures & f.getMask()) != 0;
     }
 
@@ -677,7 +677,7 @@ public final class DeserializationConfig
     }
 
     /**
-     * Bulk access method for getting the bit mask of all {@link DeserializationFeature}s
+     * Bulk access method for getting the bit mask of all {@link DeserializationFeatures}s
      * that are enabled.
      */
     public final int getDeserializationFeatures() {
@@ -693,7 +693,7 @@ public final class DeserializationConfig
      * @since 2.9
      */
     public final boolean requiresFullValue() {
-        return DeserializationFeature.FAIL_ON_TRAILING_TOKENS.enabledIn(_deserFeatures);
+        return DeserializationFeatures.FAIL_ON_TRAILING_TOKENS.enabledIn(_deserFeatures);
     }
 
     /*
diff --git a/src/main/java/com/fasterxml/jackson/databind/DeserializationContext.java b/src/main/java/com/fasterxml/jackson/databind/DeserializationContext.java
index 53f44a5f9..2e7b04354 100644
--- a/src/main/java/com/fasterxml/jackson/databind/DeserializationContext.java
+++ b/src/main/java/com/fasterxml/jackson/databind/DeserializationContext.java
@@ -90,7 +90,7 @@ public abstract class DeserializationContext
     protected final DeserializationConfig _config;
 
     /**
-     * Bitmap of {@link DeserializationFeature}s that are enabled
+     * Bitmap of {@link DeserializationFeatures}s that are enabled
      */
     protected final int _featureFlags;
 
@@ -324,7 +324,7 @@ public abstract class DeserializationContext
      * Convenience method for checking whether specified on/off
      * feature is enabled
      */
-    public final boolean isEnabled(DeserializationFeature feat) {
+    public final boolean isEnabled(DeserializationFeatures feat) {
         /* 03-Dec-2010, tatu: minor shortcut; since this is called quite often,
          *   let's use a local copy of feature settings:
          */
@@ -332,7 +332,7 @@ public abstract class DeserializationContext
     }
 
     /**
-     * Bulk access method for getting the bit mask of all {@link DeserializationFeature}s
+     * Bulk access method for getting the bit mask of all {@link DeserializationFeatures}s
      * that are enabled.
      *
      * @since 2.6
@@ -813,7 +813,7 @@ public abstract class DeserializationContext
             h = h.next();
         }
         // Nope, not handled. Potentially that's a problem...
-        if (!isEnabled(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES)) {
+        if (!isEnabled(DeserializationFeatures.FAIL_ON_UNKNOWN_PROPERTIES)) {
             p.skipChildren();
             return true;
         }
@@ -1180,7 +1180,7 @@ targetType, goodValue.getClass()));
             h = h.next();
         }
         // 24-May-2016, tatu: Actually we may still not want to fail quite yet
-        if (!isEnabled(DeserializationFeature.FAIL_ON_INVALID_SUBTYPE)) {
+        if (!isEnabled(DeserializationFeatures.FAIL_ON_INVALID_SUBTYPE)) {
             return null;
         }
         throw invalidTypeIdException(baseType, id, extraDesc);
@@ -1389,7 +1389,7 @@ trailingToken, ClassUtil.nameOf(targetType)
             JsonDeserializer<?> deser)
         throws JsonMappingException
     {
-        if (isEnabled(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES)) {
+        if (isEnabled(DeserializationFeatures.FAIL_ON_UNKNOWN_PROPERTIES)) {
             // Do we know properties that are expected instead?
             Collection<Object> propIds = (deser == null) ? null : deser.getKnownPropertyNames();
             throw UnrecognizedPropertyException.from(_parser,
diff --git a/src/main/java/com/fasterxml/jackson/databind/DeserializationFeature.java b/src/main/java/com/fasterxml/jackson/databind/DeserializationFeatures.java
similarity index 97%
rename from src/main/java/com/fasterxml/jackson/databind/DeserializationFeature.java
rename to src/main/java/com/fasterxml/jackson/databind/DeserializationFeatures.java
index 5fd5ca48e..9191b7df3 100644
--- a/src/main/java/com/fasterxml/jackson/databind/DeserializationFeature.java
+++ b/src/main/java/com/fasterxml/jackson/databind/DeserializationFeatures.java
@@ -17,7 +17,7 @@ import com.fasterxml.jackson.databind.cfg.ConfigFeature;
  * were available in Jackson 2.0 (or earlier); only later additions
  * indicate version of inclusion.
  */
-public enum DeserializationFeature implements ConfigFeature
+public enum DeserializationFeatures implements ConfigFeature
 {
     /*
     /******************************************************
@@ -483,20 +483,20 @@ public enum DeserializationFeature implements ConfigFeature
     
     ;
 
-    private final boolean _defaultState;
-    private final int _mask;
+    private final boolean enabledByDefault;
+    private final int bitMask;
     
-    private DeserializationFeature(boolean defaultState) {
-        _defaultState = defaultState;
-        _mask = (1 << ordinal());
+    private DeserializationFeatures(boolean enabledByDefault) {
+        this.enabledByDefault = enabledByDefault;
+        bitMask = (1 << ordinal());
     }
 
     @Override
-    public boolean enabledByDefault() { return _defaultState; }
+    public boolean enabledByDefault() { return enabledByDefault; }
 
     @Override
-    public int getMask() { return _mask; }
+    public int getMask() { return bitMask; }
 
     @Override
-    public boolean enabledIn(int flags) { return (flags & _mask) != 0; }
+    public boolean enabledIn(int flagBits) { return (flagBits & bitMask) != 0; }
 }
diff --git a/src/main/java/com/fasterxml/jackson/databind/Module.java b/src/main/java/com/fasterxml/jackson/databind/Module.java
index 1fe60963e..3021fd147 100644
--- a/src/main/java/com/fasterxml/jackson/databind/Module.java
+++ b/src/main/java/com/fasterxml/jackson/databind/Module.java
@@ -137,7 +137,7 @@ public abstract class Module
         
         public boolean isEnabled(MapperFeature f);
         
-        public boolean isEnabled(DeserializationFeature f);
+        public boolean isEnabled(DeserializationFeatures f);
 
         public boolean isEnabled(SerializationFeature f);
 
diff --git a/src/main/java/com/fasterxml/jackson/databind/ObjectMapper.java b/src/main/java/com/fasterxml/jackson/databind/ObjectMapper.java
index a049ae4b1..741bfae43 100644
--- a/src/main/java/com/fasterxml/jackson/databind/ObjectMapper.java
+++ b/src/main/java/com/fasterxml/jackson/databind/ObjectMapper.java
@@ -23,8 +23,8 @@ import com.fasterxml.jackson.databind.exc.MismatchedInputException;
 import com.fasterxml.jackson.databind.introspect.*;
 import com.fasterxml.jackson.databind.jsonFormatVisitors.JsonFormatVisitorWrapper;
 import com.fasterxml.jackson.databind.jsontype.*;
+import com.fasterxml.jackson.databind.jsontype.impl.StandardTypeResolverBuilder;
 import com.fasterxml.jackson.databind.jsontype.impl.StdSubtypeResolver;
-import com.fasterxml.jackson.databind.jsontype.impl.StdTypeResolverBuilder;
 import com.fasterxml.jackson.databind.node.*;
 import com.fasterxml.jackson.databind.ser.*;
 import com.fasterxml.jackson.databind.type.*;
@@ -197,7 +197,7 @@ public class ObjectMapper
      * type information should NOT be applied to all of them.
      */
     public static class DefaultTypeResolverBuilder
-        extends StdTypeResolverBuilder
+        extends StandardTypeResolverBuilder
         implements java.io.Serializable
     {
         private static final long serialVersionUID = 1L;
@@ -775,7 +775,7 @@ public class ObjectMapper
             }
 
             @Override
-            public boolean isEnabled(DeserializationFeature f) {
+            public boolean isEnabled(DeserializationFeatures f) {
                 return ObjectMapper.this.isEnabled(f);
             }
             
@@ -2033,7 +2033,7 @@ public class ObjectMapper
      * Method for checking whether given deserialization-specific
      * feature is enabled.
      */
-    public boolean isEnabled(DeserializationFeature f) {
+    public boolean isEnabled(DeserializationFeatures f) {
         return _deserializationConfig.isEnabled(f);
     }
 
@@ -2041,7 +2041,7 @@ public class ObjectMapper
      * Method for changing state of an on/off deserialization feature for
      * this object mapper.
      */
-    public ObjectMapper configure(DeserializationFeature f, boolean state) {
+    public ObjectMapper configure(DeserializationFeatures f, boolean state) {
         _deserializationConfig = state ?
                 _deserializationConfig.with(f) : _deserializationConfig.without(f);
         return this;
@@ -2051,7 +2051,7 @@ public class ObjectMapper
      * Method for enabling specified {@link DeserializationConfig} features.
      * Modifies and returns this instance; no new object is created.
      */
-    public ObjectMapper enable(DeserializationFeature feature) {
+    public ObjectMapper enable(DeserializationFeatures feature) {
         _deserializationConfig = _deserializationConfig.with(feature);
         return this;
     }
@@ -2060,8 +2060,8 @@ public class ObjectMapper
      * Method for enabling specified {@link DeserializationConfig} features.
      * Modifies and returns this instance; no new object is created.
      */
-    public ObjectMapper enable(DeserializationFeature first,
-            DeserializationFeature... f) {
+    public ObjectMapper enable(DeserializationFeatures first,
+                               DeserializationFeatures... f) {
         _deserializationConfig = _deserializationConfig.with(first, f);
         return this;
     }
@@ -2070,7 +2070,7 @@ public class ObjectMapper
      * Method for enabling specified {@link DeserializationConfig} features.
      * Modifies and returns this instance; no new object is created.
      */
-    public ObjectMapper disable(DeserializationFeature feature) {
+    public ObjectMapper disable(DeserializationFeatures feature) {
         _deserializationConfig = _deserializationConfig.without(feature);
         return this;
     }
@@ -2079,8 +2079,8 @@ public class ObjectMapper
      * Method for enabling specified {@link DeserializationConfig} features.
      * Modifies and returns this instance; no new object is created.
      */
-    public ObjectMapper disable(DeserializationFeature first,
-            DeserializationFeature... f) {
+    public ObjectMapper disable(DeserializationFeatures first,
+                                DeserializationFeatures... f) {
         _deserializationConfig = _deserializationConfig.without(first, f);
         return this;
     }
@@ -2249,7 +2249,7 @@ public class ObjectMapper
      * 
      * @throws IOException if a low-level I/O problem (unexpected end-of-input,
      *   network error) occurs (passed through as-is without additional wrapping -- note
-     *   that this is one case where {@link DeserializationFeature#WRAP_EXCEPTIONS}
+     *   that this is one case where {@link DeserializationFeatures#WRAP_EXCEPTIONS}
      *   does NOT result in wrapping of exception even if enabled)
      * @throws JsonParseException if underlying input contains invalid content
      *    of type {@link JsonParser} supports (JSON for default case)
@@ -2273,7 +2273,7 @@ public class ObjectMapper
      * 
      * @throws IOException if a low-level I/O problem (unexpected end-of-input,
      *   network error) occurs (passed through as-is without additional wrapping -- note
-     *   that this is one case where {@link DeserializationFeature#WRAP_EXCEPTIONS}
+     *   that this is one case where {@link DeserializationFeatures#WRAP_EXCEPTIONS}
      *   does NOT result in wrapping of exception even if enabled)
      * @throws JsonParseException if underlying input contains invalid content
      *    of type {@link JsonParser} supports (JSON for default case)
@@ -2296,7 +2296,7 @@ public class ObjectMapper
      * 
      * @throws IOException if a low-level I/O problem (unexpected end-of-input,
      *   network error) occurs (passed through as-is without additional wrapping -- note
-     *   that this is one case where {@link DeserializationFeature#WRAP_EXCEPTIONS}
+     *   that this is one case where {@link DeserializationFeatures#WRAP_EXCEPTIONS}
      *   does NOT result in wrapping of exception even if enabled)
      * @throws JsonParseException if underlying input contains invalid content
      *    of type {@link JsonParser} supports (JSON for default case)
@@ -2316,7 +2316,7 @@ public class ObjectMapper
      * 
      * @throws IOException if a low-level I/O problem (unexpected end-of-input,
      *   network error) occurs (passed through as-is without additional wrapping -- note
-     *   that this is one case where {@link DeserializationFeature#WRAP_EXCEPTIONS}
+     *   that this is one case where {@link DeserializationFeatures#WRAP_EXCEPTIONS}
      *   does NOT result in wrapping of exception even if enabled)
      * @throws JsonParseException if underlying input contains invalid content
      *    of type {@link JsonParser} supports (JSON for default case)
@@ -2345,7 +2345,7 @@ public class ObjectMapper
      * 
      * @throws IOException if a low-level I/O problem (unexpected end-of-input,
      *   network error) occurs (passed through as-is without additional wrapping -- note
-     *   that this is one case where {@link DeserializationFeature#WRAP_EXCEPTIONS}
+     *   that this is one case where {@link DeserializationFeatures#WRAP_EXCEPTIONS}
      *   does NOT result in wrapping of exception even if enabled)
      * @throws JsonParseException if underlying input contains invalid content
      *    of type {@link JsonParser} supports (JSON for default case)
@@ -2574,7 +2574,7 @@ public class ObjectMapper
      * 
      * @throws IOException if a low-level I/O problem (unexpected end-of-input,
      *   network error) occurs (passed through as-is without additional wrapping -- note
-     *   that this is one case where {@link DeserializationFeature#WRAP_EXCEPTIONS}
+     *   that this is one case where {@link DeserializationFeatures#WRAP_EXCEPTIONS}
      *   does NOT result in wrapping of exception even if enabled)
      * @throws JsonParseException if underlying input contains invalid content
      *    of type {@link JsonParser} supports (JSON for default case)
@@ -2600,7 +2600,7 @@ public class ObjectMapper
      * 
      * @throws IOException if a low-level I/O problem (unexpected end-of-input,
      *   network error) occurs (passed through as-is without additional wrapping -- note
-     *   that this is one case where {@link DeserializationFeature#WRAP_EXCEPTIONS}
+     *   that this is one case where {@link DeserializationFeatures#WRAP_EXCEPTIONS}
      *   does NOT result in wrapping of exception even if enabled)
      * @throws JsonParseException if underlying input contains invalid content
      *    of type {@link JsonParser} supports (JSON for default case)
@@ -2777,7 +2777,7 @@ public class ObjectMapper
     {
         if (fromValue == null) return null;
         TokenBuffer buf = new TokenBuffer(this, false);
-        if (isEnabled(DeserializationFeature.USE_BIG_DECIMAL_FOR_FLOATS)) {
+        if (isEnabled(DeserializationFeatures.USE_BIG_DECIMAL_FOR_FLOATS)) {
             buf = buf.forceUseOfBigDecimal(true);
         }
         JsonNode result;
@@ -2876,7 +2876,7 @@ public class ObjectMapper
      * 
      * @throws IOException if a low-level I/O problem (unexpected end-of-input,
      *   network error) occurs (passed through as-is without additional wrapping -- note
-     *   that this is one case where {@link DeserializationFeature#WRAP_EXCEPTIONS}
+     *   that this is one case where {@link DeserializationFeatures#WRAP_EXCEPTIONS}
      *   does NOT result in wrapping of exception even if enabled)
      * @throws JsonParseException if underlying input contains invalid content
      *    of type {@link JsonParser} supports (JSON for default case)
@@ -2895,7 +2895,7 @@ public class ObjectMapper
      * 
      * @throws IOException if a low-level I/O problem (unexpected end-of-input,
      *   network error) occurs (passed through as-is without additional wrapping -- note
-     *   that this is one case where {@link DeserializationFeature#WRAP_EXCEPTIONS}
+     *   that this is one case where {@link DeserializationFeatures#WRAP_EXCEPTIONS}
      *   does NOT result in wrapping of exception even if enabled)
      * @throws JsonParseException if underlying input contains invalid content
      *    of type {@link JsonParser} supports (JSON for default case)
@@ -2914,7 +2914,7 @@ public class ObjectMapper
      * 
      * @throws IOException if a low-level I/O problem (unexpected end-of-input,
      *   network error) occurs (passed through as-is without additional wrapping -- note
-     *   that this is one case where {@link DeserializationFeature#WRAP_EXCEPTIONS}
+     *   that this is one case where {@link DeserializationFeatures#WRAP_EXCEPTIONS}
      *   does NOT result in wrapping of exception even if enabled)
      * @throws JsonParseException if underlying input contains invalid content
      *    of type {@link JsonParser} supports (JSON for default case)
@@ -2933,7 +2933,7 @@ public class ObjectMapper
      * 
      * @throws IOException if a low-level I/O problem (unexpected end-of-input,
      *   network error) occurs (passed through as-is without additional wrapping -- note
-     *   that this is one case where {@link DeserializationFeature#WRAP_EXCEPTIONS}
+     *   that this is one case where {@link DeserializationFeatures#WRAP_EXCEPTIONS}
      *   does NOT result in wrapping of exception even if enabled)
      * @throws JsonParseException if underlying input contains invalid content
      *    of type {@link JsonParser} supports (JSON for default case)
@@ -2952,7 +2952,7 @@ public class ObjectMapper
      * 
      * @throws IOException if a low-level I/O problem (unexpected end-of-input,
      *   network error) occurs (passed through as-is without additional wrapping -- note
-     *   that this is one case where {@link DeserializationFeature#WRAP_EXCEPTIONS}
+     *   that this is one case where {@link DeserializationFeatures#WRAP_EXCEPTIONS}
      *   does NOT result in wrapping of exception even if enabled)
      * @throws JsonParseException if underlying input contains invalid content
      *    of type {@link JsonParser} supports (JSON for default case)
@@ -2978,7 +2978,7 @@ public class ObjectMapper
      * 
      * @throws IOException if a low-level I/O problem (unexpected end-of-input,
      *   network error) occurs (passed through as-is without additional wrapping -- note
-     *   that this is one case where {@link DeserializationFeature#WRAP_EXCEPTIONS}
+     *   that this is one case where {@link DeserializationFeatures#WRAP_EXCEPTIONS}
      *   does NOT result in wrapping of exception even if enabled)
      * @throws JsonParseException if underlying input contains invalid content
      *    of type {@link JsonParser} supports (JSON for default case)
@@ -2997,7 +2997,7 @@ public class ObjectMapper
      * 
      * @throws IOException if a low-level I/O problem (unexpected end-of-input,
      *   network error) occurs (passed through as-is without additional wrapping -- note
-     *   that this is one case where {@link DeserializationFeature#WRAP_EXCEPTIONS}
+     *   that this is one case where {@link DeserializationFeatures#WRAP_EXCEPTIONS}
      *   does NOT result in wrapping of exception even if enabled)
      * @throws JsonParseException if underlying input contains invalid content
      *    of type {@link JsonParser} supports (JSON for default case)
@@ -3016,7 +3016,7 @@ public class ObjectMapper
      * 
      * @throws IOException if a low-level I/O problem (unexpected end-of-input,
      *   network error) occurs (passed through as-is without additional wrapping -- note
-     *   that this is one case where {@link DeserializationFeature#WRAP_EXCEPTIONS}
+     *   that this is one case where {@link DeserializationFeatures#WRAP_EXCEPTIONS}
      *   does NOT result in wrapping of exception even if enabled)
      * @throws JsonParseException if underlying input contains invalid content
      *    of type {@link JsonParser} supports (JSON for default case)
@@ -3464,7 +3464,7 @@ public class ObjectMapper
      * Note that the resulting instance is NOT usable as is,
      * without defining expected value type.
      */
-    public ObjectReader reader(DeserializationFeature feature) {
+    public ObjectReader reader(DeserializationFeatures feature) {
         return _newReader(getDeserializationConfig().with(feature));
     }
 
@@ -3475,8 +3475,8 @@ public class ObjectMapper
      * Note that the resulting instance is NOT usable as is,
      * without defining expected value type.
      */
-    public ObjectReader reader(DeserializationFeature first,
-            DeserializationFeature... other) {
+    public ObjectReader reader(DeserializationFeatures first,
+                               DeserializationFeatures... other) {
         return _newReader(getDeserializationConfig().with(first, other));
     }
     
@@ -3705,7 +3705,7 @@ public class ObjectMapper
         
         // Then use TokenBuffer, which is a JsonGenerator:
         TokenBuffer buf = new TokenBuffer(this, false);
-        if (isEnabled(DeserializationFeature.USE_BIG_DECIMAL_FOR_FLOATS)) {
+        if (isEnabled(DeserializationFeatures.USE_BIG_DECIMAL_FOR_FLOATS)) {
             buf = buf.forceUseOfBigDecimal(true);
         }
         try {
@@ -3781,7 +3781,7 @@ public class ObjectMapper
         T result = valueToUpdate;
         if ((valueToUpdate != null) && (overrides != null)) {
             TokenBuffer buf = new TokenBuffer(this, false);
-            if (isEnabled(DeserializationFeature.USE_BIG_DECIMAL_FOR_FLOATS)) {
+            if (isEnabled(DeserializationFeatures.USE_BIG_DECIMAL_FOR_FLOATS)) {
                 buf = buf.forceUseOfBigDecimal(true);
             }
             try {
@@ -3974,7 +3974,7 @@ public class ObjectMapper
         }
         // Need to consume the token too
         p.clearCurrentToken();
-        if (cfg.isEnabled(DeserializationFeature.FAIL_ON_TRAILING_TOKENS)) {
+        if (cfg.isEnabled(DeserializationFeatures.FAIL_ON_TRAILING_TOKENS)) {
             _verifyNoTrailingTokens(p, ctxt, valueType);
         }
         return result;
@@ -4002,7 +4002,7 @@ public class ObjectMapper
                 }
                 ctxt.checkUnresolvedObjectId();
             }
-            if (cfg.isEnabled(DeserializationFeature.FAIL_ON_TRAILING_TOKENS)) {
+            if (cfg.isEnabled(DeserializationFeatures.FAIL_ON_TRAILING_TOKENS)) {
                 _verifyNoTrailingTokens(p, ctxt, valueType);
             }
             return result;
@@ -4042,7 +4042,7 @@ public class ObjectMapper
                 result = _unwrapAndDeserialize(p, ctxt, cfg, valueType, deser);
             } else {
                 result = deser.deserialize(p, ctxt);
-                if (cfg.isEnabled(DeserializationFeature.FAIL_ON_TRAILING_TOKENS)) {
+                if (cfg.isEnabled(DeserializationFeatures.FAIL_ON_TRAILING_TOKENS)) {
                     _verifyNoTrailingTokens(p, ctxt, valueType);
                 }
             }
@@ -4085,7 +4085,7 @@ public class ObjectMapper
                     "Current token not END_OBJECT (to match wrapper object with root name '%s'), but %s",
                     expSimpleName, p.getCurrentToken());
         }
-        if (config.isEnabled(DeserializationFeature.FAIL_ON_TRAILING_TOKENS)) {
+        if (config.isEnabled(DeserializationFeatures.FAIL_ON_TRAILING_TOKENS)) {
             _verifyNoTrailingTokens(p, ctxt, rootType);
         }
         return result;
diff --git a/src/main/java/com/fasterxml/jackson/databind/ObjectReader.java b/src/main/java/com/fasterxml/jackson/databind/ObjectReader.java
index d313c4207..3ddb51066 100644
--- a/src/main/java/com/fasterxml/jackson/databind/ObjectReader.java
+++ b/src/main/java/com/fasterxml/jackson/databind/ObjectReader.java
@@ -390,7 +390,7 @@ public class ObjectReader
      * Method for constructing a new reader instance that is configured
      * with specified feature enabled.
      */
-    public ObjectReader with(DeserializationFeature feature) {
+    public ObjectReader with(DeserializationFeatures feature) {
         return _with(_config.with(feature));
     }
 
@@ -398,8 +398,8 @@ public class ObjectReader
      * Method for constructing a new reader instance that is configured
      * with specified features enabled.
      */
-    public ObjectReader with(DeserializationFeature first,
-            DeserializationFeature... other)
+    public ObjectReader with(DeserializationFeatures first,
+                             DeserializationFeatures... other)
     {
         return _with(_config.with(first, other));
     }    
@@ -408,7 +408,7 @@ public class ObjectReader
      * Method for constructing a new reader instance that is configured
      * with specified features enabled.
      */
-    public ObjectReader withFeatures(DeserializationFeature... features) {
+    public ObjectReader withFeatures(DeserializationFeatures... features) {
         return _with(_config.withFeatures(features));
     }    
 
@@ -416,7 +416,7 @@ public class ObjectReader
      * Method for constructing a new reader instance that is configured
      * with specified feature disabled.
      */
-    public ObjectReader without(DeserializationFeature feature) {
+    public ObjectReader without(DeserializationFeatures feature) {
         return _with(_config.without(feature)); 
     }
 
@@ -424,8 +424,8 @@ public class ObjectReader
      * Method for constructing a new reader instance that is configured
      * with specified features disabled.
      */
-    public ObjectReader without(DeserializationFeature first,
-            DeserializationFeature... other) {
+    public ObjectReader without(DeserializationFeatures first,
+                                DeserializationFeatures... other) {
         return _with(_config.without(first, other));
     }    
 
@@ -433,7 +433,7 @@ public class ObjectReader
      * Method for constructing a new reader instance that is configured
      * with specified features disabled.
      */
-    public ObjectReader withoutFeatures(DeserializationFeature... features) {
+    public ObjectReader withoutFeatures(DeserializationFeatures... features) {
         return _with(_config.withoutFeatures(features));
     }    
 
@@ -898,7 +898,7 @@ public class ObjectReader
     /**********************************************************
      */
     
-    public boolean isEnabled(DeserializationFeature f) {
+    public boolean isEnabled(DeserializationFeatures f) {
         return _config.isEnabled(f);
     }
 
@@ -1581,7 +1581,7 @@ public class ObjectReader
         }
         // Need to consume the token too
         p.clearCurrentToken();
-        if (_config.isEnabled(DeserializationFeature.FAIL_ON_TRAILING_TOKENS)) {
+        if (_config.isEnabled(DeserializationFeatures.FAIL_ON_TRAILING_TOKENS)) {
             _verifyNoTrailingTokens(p, ctxt, _valueType);
         }
         return result;
@@ -1615,7 +1615,7 @@ public class ObjectReader
                     }
                 }
             }
-            if (_config.isEnabled(DeserializationFeature.FAIL_ON_TRAILING_TOKENS)) {
+            if (_config.isEnabled(DeserializationFeatures.FAIL_ON_TRAILING_TOKENS)) {
                 _verifyNoTrailingTokens(p, ctxt, _valueType);
             }
             return result;
@@ -1655,7 +1655,7 @@ public class ObjectReader
             result = _unwrapAndDeserialize(p, ctxt, JSON_NODE_TYPE, deser);
         } else {
             result = deser.deserialize(p, ctxt);
-            if (_config.isEnabled(DeserializationFeature.FAIL_ON_TRAILING_TOKENS)) {
+            if (_config.isEnabled(DeserializationFeatures.FAIL_ON_TRAILING_TOKENS)) {
                 _verifyNoTrailingTokens(p, ctxt, JSON_NODE_TYPE);
             }
         }
@@ -1711,7 +1711,7 @@ public class ObjectReader
                     "Current token not END_OBJECT (to match wrapper object with root name '%s'), but %s",
                     expSimpleName, p.getCurrentToken());
         }
-        if (_config.isEnabled(DeserializationFeature.FAIL_ON_TRAILING_TOKENS)) {
+        if (_config.isEnabled(DeserializationFeatures.FAIL_ON_TRAILING_TOKENS)) {
             _verifyNoTrailingTokens(p, ctxt, _valueType);
         }
         return result;
@@ -1926,7 +1926,7 @@ public class ObjectReader
      */
     protected JsonDeserializer<Object> _prefetchRootDeserializer(JavaType valueType)
     {
-        if ((valueType == null) || !_config.isEnabled(DeserializationFeature.EAGER_DESERIALIZER_FETCH)) {
+        if ((valueType == null) || !_config.isEnabled(DeserializationFeatures.EAGER_DESERIALIZER_FETCH)) {
             return null;
         }
         // already cached?
diff --git a/src/main/java/com/fasterxml/jackson/databind/SerializationFeature.java b/src/main/java/com/fasterxml/jackson/databind/SerializationFeature.java
index 1b46dc073..155e0ce1e 100644
--- a/src/main/java/com/fasterxml/jackson/databind/SerializationFeature.java
+++ b/src/main/java/com/fasterxml/jackson/databind/SerializationFeature.java
@@ -250,7 +250,7 @@ public enum SerializationFeature implements ConfigFeature
      * is used; if disabled, return value of <code>Enum.name()</code> is used.
      *<p>
      * Note: this feature should usually have same value
-     * as {@link DeserializationFeature#READ_ENUMS_USING_TO_STRING}.
+     * as {@link DeserializationFeatures#READ_ENUMS_USING_TO_STRING}.
      *<p>
      * Feature is disabled by default.
      */
@@ -325,7 +325,7 @@ public enum SerializationFeature implements ConfigFeature
      *  { "arrayProperty" : 1 }
      *</pre>
      *<p>
-     * Note that this feature is counterpart to {@link DeserializationFeature#ACCEPT_SINGLE_VALUE_AS_ARRAY}
+     * Note that this feature is counterpart to {@link DeserializationFeatures#ACCEPT_SINGLE_VALUE_AS_ARRAY}
      * (that is, usually both are enabled, or neither is).
      *<p>
      * Feature is disabled by default, so that no special handling is done.
diff --git a/src/main/java/com/fasterxml/jackson/databind/deser/BeanDeserializerBase.java b/src/main/java/com/fasterxml/jackson/databind/deser/BeanDeserializerBase.java
index 6ce41f783..7d58eea0d 100644
--- a/src/main/java/com/fasterxml/jackson/databind/deser/BeanDeserializerBase.java
+++ b/src/main/java/com/fasterxml/jackson/databind/deser/BeanDeserializerBase.java
@@ -1439,9 +1439,9 @@ public abstract class BeanDeserializerBase
             }
             return bean;
         }
-        if (ctxt.isEnabled(DeserializationFeature.UNWRAP_SINGLE_VALUE_ARRAYS)) {
+        if (ctxt.isEnabled(DeserializationFeatures.UNWRAP_SINGLE_VALUE_ARRAYS)) {
             JsonToken t = p.nextToken();
-            if (t == JsonToken.END_ARRAY && ctxt.isEnabled(DeserializationFeature.ACCEPT_EMPTY_ARRAY_AS_NULL_OBJECT)) {
+            if (t == JsonToken.END_ARRAY && ctxt.isEnabled(DeserializationFeatures.ACCEPT_EMPTY_ARRAY_AS_NULL_OBJECT)) {
                 return null;
             }
             final Object value = deserialize(p, ctxt);
@@ -1450,7 +1450,7 @@ public abstract class BeanDeserializerBase
             }
             return value;
         }
-        if (ctxt.isEnabled(DeserializationFeature.ACCEPT_EMPTY_ARRAY_AS_NULL_OBJECT)) {
+        if (ctxt.isEnabled(DeserializationFeatures.ACCEPT_EMPTY_ARRAY_AS_NULL_OBJECT)) {
             JsonToken t = p.nextToken();
             if (t == JsonToken.END_ARRAY) {
                 return null;
@@ -1599,7 +1599,7 @@ public abstract class BeanDeserializerBase
             Object beanOrClass, String propName)
         throws IOException
     {
-        if (ctxt.isEnabled(DeserializationFeature.FAIL_ON_IGNORED_PROPERTIES)) {
+        if (ctxt.isEnabled(DeserializationFeatures.FAIL_ON_IGNORED_PROPERTIES)) {
             throw IgnoredPropertyException.from(p, beanOrClass, propName, getKnownPropertyNames());
         }
         p.skipChildren();
@@ -1723,7 +1723,7 @@ public abstract class BeanDeserializerBase
         }
         // Errors to be passed as is
         ClassUtil.throwIfError(t);
-        boolean wrap = (ctxt == null) || ctxt.isEnabled(DeserializationFeature.WRAP_EXCEPTIONS);
+        boolean wrap = (ctxt == null) || ctxt.isEnabled(DeserializationFeatures.WRAP_EXCEPTIONS);
         // Ditto for IOExceptions; except we may want to wrap JSON exceptions
         if (t instanceof IOException) {
             if (!wrap || !(t instanceof JsonProcessingException)) {
@@ -1747,7 +1747,7 @@ public abstract class BeanDeserializerBase
             // Since we have no more information to add, let's not actually wrap..
             throw (IOException) t;
         }
-        boolean wrap = (ctxt == null) || ctxt.isEnabled(DeserializationFeature.WRAP_EXCEPTIONS);
+        boolean wrap = (ctxt == null) || ctxt.isEnabled(DeserializationFeatures.WRAP_EXCEPTIONS);
         if (!wrap) { // [JACKSON-407] -- allow disabling wrapping for unchecked exceptions
             ClassUtil.throwIfRTE(t);
         }
diff --git a/src/main/java/com/fasterxml/jackson/databind/deser/DefaultDeserializationContext.java b/src/main/java/com/fasterxml/jackson/databind/deser/DefaultDeserializationContext.java
index cdc90ed2e..2ffeca316 100644
--- a/src/main/java/com/fasterxml/jackson/databind/deser/DefaultDeserializationContext.java
+++ b/src/main/java/com/fasterxml/jackson/databind/deser/DefaultDeserializationContext.java
@@ -148,7 +148,7 @@ public abstract class DefaultDeserializationContext
             return;
         }
         // 29-Dec-2014, tatu: As per [databind#299], may also just let unresolved refs be...
-        if (!isEnabled(DeserializationFeature.FAIL_ON_UNRESOLVED_OBJECT_IDS)) {
+        if (!isEnabled(DeserializationFeatures.FAIL_ON_UNRESOLVED_OBJECT_IDS)) {
             return;
         }
         UnresolvedForwardReference exception = null;
diff --git a/src/main/java/com/fasterxml/jackson/databind/deser/DeserializationProblemHandler.java b/src/main/java/com/fasterxml/jackson/databind/deser/DeserializationProblemHandler.java
index 38b87051b..accb3b935 100644
--- a/src/main/java/com/fasterxml/jackson/databind/deser/DeserializationProblemHandler.java
+++ b/src/main/java/com/fasterxml/jackson/databind/deser/DeserializationProblemHandler.java
@@ -6,6 +6,7 @@ import com.fasterxml.jackson.core.JsonParser;
 import com.fasterxml.jackson.core.JsonToken;
 import com.fasterxml.jackson.databind.DeserializationConfig;
 import com.fasterxml.jackson.databind.DeserializationContext;
+import com.fasterxml.jackson.databind.DeserializationFeatures;
 import com.fasterxml.jackson.databind.JavaType;
 import com.fasterxml.jackson.databind.JsonDeserializer;
 import com.fasterxml.jackson.databind.ObjectMapper;
@@ -52,7 +53,7 @@ public abstract class DeserializationProblemHandler
      *  parser.skipChildren();
      *</pre>
      *<p>
-     * Note: {@link com.fasterxml.jackson.databind.DeserializationFeature#FAIL_ON_UNKNOWN_PROPERTIES})
+     * Note: {@link DeserializationFeatures#FAIL_ON_UNKNOWN_PROPERTIES})
      * takes effect only <b>after</b> handler is called, and only
      * if handler did <b>not</b> handle the problem.
      *
diff --git a/src/main/java/com/fasterxml/jackson/databind/deser/ValueInstantiator.java b/src/main/java/com/fasterxml/jackson/databind/deser/ValueInstantiator.java
index a7a695168..2cfc8c79c 100644
--- a/src/main/java/com/fasterxml/jackson/databind/deser/ValueInstantiator.java
+++ b/src/main/java/com/fasterxml/jackson/databind/deser/ValueInstantiator.java
@@ -364,7 +364,7 @@ public abstract class ValueInstantiator
         }
         // also, empty Strings might be accepted as null Object...
         if (value.length() == 0) {
-            if (ctxt.isEnabled(DeserializationFeature.ACCEPT_EMPTY_STRING_AS_NULL_OBJECT)) {
+            if (ctxt.isEnabled(DeserializationFeatures.ACCEPT_EMPTY_STRING_AS_NULL_OBJECT)) {
                 return null;
             }
         }
diff --git a/src/main/java/com/fasterxml/jackson/databind/deser/impl/BeanAsArrayBuilderDeserializer.java b/src/main/java/com/fasterxml/jackson/databind/deser/impl/BeanAsArrayBuilderDeserializer.java
index 0dbc50da3..0bef92e0c 100644
--- a/src/main/java/com/fasterxml/jackson/databind/deser/impl/BeanAsArrayBuilderDeserializer.java
+++ b/src/main/java/com/fasterxml/jackson/databind/deser/impl/BeanAsArrayBuilderDeserializer.java
@@ -156,7 +156,7 @@ public class BeanAsArrayBuilderDeserializer
         }
         // 09-Nov-2016, tatu: Should call `handleUnknownProperty()` in Context, but it'd give
         //   non-optimal exception message so...
-        if (!_ignoreAllUnknown && ctxt.isEnabled(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES)) {
+        if (!_ignoreAllUnknown && ctxt.isEnabled(DeserializationFeatures.FAIL_ON_UNKNOWN_PROPERTIES)) {
             ctxt.reportInputMismatch(handledType(),
                     "Unexpected JSON values; expected at most %d properties (in JSON Array)",
                     propCount);
@@ -234,7 +234,7 @@ public class BeanAsArrayBuilderDeserializer
             p.skipChildren();
         }
         // Ok; extra fields? Let's fail, unless ignoring extra props is fine
-        if (!_ignoreAllUnknown && ctxt.isEnabled(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES)) {
+        if (!_ignoreAllUnknown && ctxt.isEnabled(DeserializationFeatures.FAIL_ON_UNKNOWN_PROPERTIES)) {
             ctxt.reportWrongTokenException(this, JsonToken.END_ARRAY,
                     "Unexpected JSON value(s); expected at most %d properties (in JSON Array)",
                     propCount);
diff --git a/src/main/java/com/fasterxml/jackson/databind/deser/impl/BeanAsArrayDeserializer.java b/src/main/java/com/fasterxml/jackson/databind/deser/impl/BeanAsArrayDeserializer.java
index 2b39004b6..40e14dafb 100644
--- a/src/main/java/com/fasterxml/jackson/databind/deser/impl/BeanAsArrayDeserializer.java
+++ b/src/main/java/com/fasterxml/jackson/databind/deser/impl/BeanAsArrayDeserializer.java
@@ -126,7 +126,7 @@ public class BeanAsArrayDeserializer
             ++i;
         }
         // Ok; extra fields? Let's fail, unless ignoring extra props is fine
-        if (!_ignoreAllUnknown && ctxt.isEnabled(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES)) {
+        if (!_ignoreAllUnknown && ctxt.isEnabled(DeserializationFeatures.FAIL_ON_UNKNOWN_PROPERTIES)) {
             ctxt.reportWrongTokenException(this, JsonToken.END_ARRAY,
                     "Unexpected JSON values; expected at most %d properties (in JSON Array)",
                     propCount);
@@ -180,7 +180,7 @@ public class BeanAsArrayDeserializer
         }
         
         // Ok; extra fields? Let's fail, unless ignoring extra props is fine
-        if (!_ignoreAllUnknown && ctxt.isEnabled(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES)) {
+        if (!_ignoreAllUnknown && ctxt.isEnabled(DeserializationFeatures.FAIL_ON_UNKNOWN_PROPERTIES)) {
             ctxt.reportWrongTokenException(this, JsonToken.END_ARRAY,
                     "Unexpected JSON values; expected at most %d properties (in JSON Array)",
                     propCount);
diff --git a/src/main/java/com/fasterxml/jackson/databind/deser/impl/BeanPropertyMap.java b/src/main/java/com/fasterxml/jackson/databind/deser/impl/BeanPropertyMap.java
index b015bb5a2..2f764759f 100644
--- a/src/main/java/com/fasterxml/jackson/databind/deser/impl/BeanPropertyMap.java
+++ b/src/main/java/com/fasterxml/jackson/databind/deser/impl/BeanPropertyMap.java
@@ -7,7 +7,7 @@ import java.util.*;
 import com.fasterxml.jackson.core.JsonParser;
 import com.fasterxml.jackson.core.JsonProcessingException;
 import com.fasterxml.jackson.databind.DeserializationContext;
-import com.fasterxml.jackson.databind.DeserializationFeature;
+import com.fasterxml.jackson.databind.DeserializationFeatures;
 import com.fasterxml.jackson.databind.JsonDeserializer;
 import com.fasterxml.jackson.databind.JsonMappingException;
 import com.fasterxml.jackson.databind.PropertyName;
@@ -701,7 +701,7 @@ public class BeanPropertyMap
         // Errors to be passed as is
         ClassUtil.throwIfError(t);
         // StackOverflowErrors are tricky ones; need to be careful...
-        boolean wrap = (ctxt == null) || ctxt.isEnabled(DeserializationFeature.WRAP_EXCEPTIONS);
+        boolean wrap = (ctxt == null) || ctxt.isEnabled(DeserializationFeatures.WRAP_EXCEPTIONS);
         // Ditto for IOExceptions; except we may want to wrap JSON exceptions
         if (t instanceof IOException) {
             if (!wrap || !(t instanceof JsonProcessingException)) {
diff --git a/src/main/java/com/fasterxml/jackson/databind/deser/impl/ExternalTypeHandler.java b/src/main/java/com/fasterxml/jackson/databind/deser/impl/ExternalTypeHandler.java
index 1be53a2fe..33116001a 100644
--- a/src/main/java/com/fasterxml/jackson/databind/deser/impl/ExternalTypeHandler.java
+++ b/src/main/java/com/fasterxml/jackson/databind/deser/impl/ExternalTypeHandler.java
@@ -236,7 +236,7 @@ public class ExternalTypeHandler
                 SettableBeanProperty prop = _properties[i].getProperty();
 
                 if(prop.isRequired() ||
-                        ctxt.isEnabled(DeserializationFeature.FAIL_ON_MISSING_EXTERNAL_TYPE_ID_PROPERTY)) {
+                        ctxt.isEnabled(DeserializationFeatures.FAIL_ON_MISSING_EXTERNAL_TYPE_ID_PROPERTY)) {
                     ctxt.reportInputMismatch(bean.getClass(),
                             "Missing property '%s' for external type id '%s'",
                             prop.getName(), _properties[i].getTypePropertyName());
diff --git a/src/main/java/com/fasterxml/jackson/databind/deser/impl/PropertyValueBuffer.java b/src/main/java/com/fasterxml/jackson/databind/deser/impl/PropertyValueBuffer.java
index 76e0b2b1b..5c7e4f020 100644
--- a/src/main/java/com/fasterxml/jackson/databind/deser/impl/PropertyValueBuffer.java
+++ b/src/main/java/com/fasterxml/jackson/databind/deser/impl/PropertyValueBuffer.java
@@ -5,7 +5,7 @@ import java.util.BitSet;
 
 import com.fasterxml.jackson.core.JsonParser;
 import com.fasterxml.jackson.databind.DeserializationContext;
-import com.fasterxml.jackson.databind.DeserializationFeature;
+import com.fasterxml.jackson.databind.DeserializationFeatures;
 import com.fasterxml.jackson.databind.JsonDeserializer;
 import com.fasterxml.jackson.databind.JsonMappingException;
 import com.fasterxml.jackson.databind.deser.SettableAnyProperty;
@@ -130,7 +130,7 @@ public class PropertyValueBuffer
         } else {
             value = _creatorParameters[prop.getCreatorIndex()] = _findMissing(prop);
         }
-        if (value == null && _context.isEnabled(DeserializationFeature.FAIL_ON_NULL_CREATOR_PROPERTIES)) {
+        if (value == null && _context.isEnabled(DeserializationFeatures.FAIL_ON_NULL_CREATOR_PROPERTIES)) {
             return _context.reportInputMismatch(prop,
                 "Null value for creator property '%s' (index %d); `DeserializationFeature.FAIL_ON_NULL_FOR_CREATOR_PARAMETERS` enabled",
                 prop.getName(), prop.getCreatorIndex());
@@ -167,7 +167,7 @@ public class PropertyValueBuffer
             }
         }
 
-        if (_context.isEnabled(DeserializationFeature.FAIL_ON_NULL_CREATOR_PROPERTIES)) {
+        if (_context.isEnabled(DeserializationFeatures.FAIL_ON_NULL_CREATOR_PROPERTIES)) {
             for (int ix = 0; ix < props.length; ++ix) {
                 if (_creatorParameters[ix] == null) {
                     SettableBeanProperty prop = props[ix];
@@ -194,7 +194,7 @@ public class PropertyValueBuffer
             _context.reportInputMismatch(prop, "Missing required creator property '%s' (index %d)",
                     prop.getName(), prop.getCreatorIndex());
         }
-        if (_context.isEnabled(DeserializationFeature.FAIL_ON_MISSING_CREATOR_PROPERTIES)) {
+        if (_context.isEnabled(DeserializationFeatures.FAIL_ON_MISSING_CREATOR_PROPERTIES)) {
             _context.reportInputMismatch(prop,
                     "Missing creator property '%s' (index %d); `DeserializationFeature.FAIL_ON_MISSING_CREATOR_PROPERTIES` enabled",
                     prop.getName(), prop.getCreatorIndex());
diff --git a/src/main/java/com/fasterxml/jackson/databind/deser/std/CollectionDeserializer.java b/src/main/java/com/fasterxml/jackson/databind/deser/std/CollectionDeserializer.java
index c255d896f..84934e917 100644
--- a/src/main/java/com/fasterxml/jackson/databind/deser/std/CollectionDeserializer.java
+++ b/src/main/java/com/fasterxml/jackson/databind/deser/std/CollectionDeserializer.java
@@ -11,7 +11,6 @@ import com.fasterxml.jackson.databind.*;
 import com.fasterxml.jackson.databind.annotation.JacksonStdImpl;
 import com.fasterxml.jackson.databind.deser.*;
 import com.fasterxml.jackson.databind.deser.impl.ReadableObjectId.Referring;
-import com.fasterxml.jackson.databind.deser.std.ContainerDeserializerBase;
 import com.fasterxml.jackson.databind.jsontype.TypeDeserializer;
 import com.fasterxml.jackson.databind.util.ClassUtil;
 
@@ -295,7 +294,7 @@ _containerType,
                     .from(p, "Unresolved forward reference but no identity info", reference);
                 */
             } catch (Exception e) {
-                boolean wrap = (ctxt == null) || ctxt.isEnabled(DeserializationFeature.WRAP_EXCEPTIONS);
+                boolean wrap = (ctxt == null) || ctxt.isEnabled(DeserializationFeatures.WRAP_EXCEPTIONS);
                 if (!wrap) {
                     ClassUtil.throwIfRTE(e);
                 }
@@ -327,7 +326,7 @@ _containerType,
         // Implicit arrays from single values?
         boolean canWrap = (_unwrapSingle == Boolean.TRUE) ||
                 ((_unwrapSingle == null) &&
-                        ctxt.isEnabled(DeserializationFeature.ACCEPT_SINGLE_VALUE_AS_ARRAY));
+                        ctxt.isEnabled(DeserializationFeatures.ACCEPT_SINGLE_VALUE_AS_ARRAY));
         if (!canWrap) {
             return (Collection<Object>) ctxt.handleUnexpectedToken(_containerType.getRawClass(), p);
         }
@@ -392,7 +391,7 @@ _containerType,
                 Referring ref = referringAccumulator.handleUnresolvedReference(reference);
                 reference.getRoid().appendReferring(ref);
             } catch (Exception e) {
-                boolean wrap = (ctxt == null) || ctxt.isEnabled(DeserializationFeature.WRAP_EXCEPTIONS);
+                boolean wrap = (ctxt == null) || ctxt.isEnabled(DeserializationFeatures.WRAP_EXCEPTIONS);
                 if (!wrap) {
                     ClassUtil.throwIfRTE(e);
                 }
diff --git a/src/main/java/com/fasterxml/jackson/databind/deser/std/EnumDeserializer.java b/src/main/java/com/fasterxml/jackson/databind/deser/std/EnumDeserializer.java
index c697e1ce8..9b824b6fc 100644
--- a/src/main/java/com/fasterxml/jackson/databind/deser/std/EnumDeserializer.java
+++ b/src/main/java/com/fasterxml/jackson/databind/deser/std/EnumDeserializer.java
@@ -171,7 +171,7 @@ public class EnumDeserializer
         
         // Usually should just get string value:
         if (curr == JsonToken.VALUE_STRING || curr == JsonToken.FIELD_NAME) {
-            CompactStringObjectMap lookup = ctxt.isEnabled(DeserializationFeature.READ_ENUMS_USING_TO_STRING)
+            CompactStringObjectMap lookup = ctxt.isEnabled(DeserializationFeatures.READ_ENUMS_USING_TO_STRING)
                     ? _getToStringLookup(ctxt) : _lookupByName;
             final String name = p.getText();
             Object result = lookup.find(name);
@@ -184,7 +184,7 @@ public class EnumDeserializer
         if (curr == JsonToken.VALUE_NUMBER_INT) {
             // ... unless told not to do that
             int index = p.getIntValue();
-            if (ctxt.isEnabled(DeserializationFeature.FAIL_ON_NUMBERS_FOR_ENUMS)) {
+            if (ctxt.isEnabled(DeserializationFeatures.FAIL_ON_NUMBERS_FOR_ENUMS)) {
                 return ctxt.handleWeirdNumberValue(_enumClass(), index,
                         "not allowed to deserialize Enum value out of number: disable DeserializationConfig.DeserializationFeature.FAIL_ON_NUMBERS_FOR_ENUMS to allow"
                         );
@@ -193,10 +193,10 @@ public class EnumDeserializer
                 return _enumsByIndex[index];
             }
             if ((_enumDefaultValue != null)
-                    && ctxt.isEnabled(DeserializationFeature.READ_UNKNOWN_ENUM_VALUES_USING_DEFAULT_VALUE)) {
+                    && ctxt.isEnabled(DeserializationFeatures.READ_UNKNOWN_ENUM_VALUES_USING_DEFAULT_VALUE)) {
                 return _enumDefaultValue;
             }
-            if (!ctxt.isEnabled(DeserializationFeature.READ_UNKNOWN_ENUM_VALUES_AS_NULL)) {
+            if (!ctxt.isEnabled(DeserializationFeatures.READ_UNKNOWN_ENUM_VALUES_AS_NULL)) {
                 return ctxt.handleWeirdNumberValue(_enumClass(), index,
                         "index value outside legal index range [0..%s]",
                         _enumsByIndex.length-1);
@@ -217,7 +217,7 @@ public class EnumDeserializer
     {
         name = name.trim();
         if (name.length() == 0) {
-            if (ctxt.isEnabled(DeserializationFeature.ACCEPT_EMPTY_STRING_AS_NULL_OBJECT)) {
+            if (ctxt.isEnabled(DeserializationFeatures.ACCEPT_EMPTY_STRING_AS_NULL_OBJECT)) {
                 return getEmptyValue(ctxt);
             }
         } else {
@@ -227,7 +227,7 @@ public class EnumDeserializer
                 if (match != null) {
                     return match;
                 }
-            } else if (!ctxt.isEnabled(DeserializationFeature.FAIL_ON_NUMBERS_FOR_ENUMS)) {
+            } else if (!ctxt.isEnabled(DeserializationFeatures.FAIL_ON_NUMBERS_FOR_ENUMS)) {
                 // [databind#149]: Allow use of 'String' indexes as well -- unless prohibited (as per above)
                 char c = name.charAt(0);
                 if (c >= '0' && c <= '9') {
@@ -248,10 +248,10 @@ public class EnumDeserializer
             }
         }
         if ((_enumDefaultValue != null)
-                && ctxt.isEnabled(DeserializationFeature.READ_UNKNOWN_ENUM_VALUES_USING_DEFAULT_VALUE)) {
+                && ctxt.isEnabled(DeserializationFeatures.READ_UNKNOWN_ENUM_VALUES_USING_DEFAULT_VALUE)) {
             return _enumDefaultValue;
         }
-        if (!ctxt.isEnabled(DeserializationFeature.READ_UNKNOWN_ENUM_VALUES_AS_NULL)) {
+        if (!ctxt.isEnabled(DeserializationFeatures.READ_UNKNOWN_ENUM_VALUES_AS_NULL)) {
             return ctxt.handleWeirdStringValue(_enumClass(), name,
                     "value not one of declared Enum instance names: %s", lookup.keys());
         }
diff --git a/src/main/java/com/fasterxml/jackson/databind/deser/std/EnumMapDeserializer.java b/src/main/java/com/fasterxml/jackson/databind/deser/std/EnumMapDeserializer.java
index f61b17c1c..a3b660bc9 100644
--- a/src/main/java/com/fasterxml/jackson/databind/deser/std/EnumMapDeserializer.java
+++ b/src/main/java/com/fasterxml/jackson/databind/deser/std/EnumMapDeserializer.java
@@ -278,7 +278,7 @@ public class EnumMapDeserializer
             Enum<?> key = (Enum<?>) _keyDeserializer.deserializeKey(keyStr, ctxt);
             JsonToken t = p.nextToken();
             if (key == null) {
-                if (!ctxt.isEnabled(DeserializationFeature.READ_UNKNOWN_ENUM_VALUES_AS_NULL)) {
+                if (!ctxt.isEnabled(DeserializationFeatures.READ_UNKNOWN_ENUM_VALUES_AS_NULL)) {
                     return (EnumMap<?,?>) ctxt.handleWeirdStringValue(_enumClass, keyStr,
                             "value not one of declared Enum instance names for %s",
                             _containerType.getKeyType());
@@ -374,7 +374,7 @@ public class EnumMapDeserializer
             // but we need to let key deserializer handle it separately, nonetheless
             Enum<?> key = (Enum<?>) _keyDeserializer.deserializeKey(keyName, ctxt);
             if (key == null) {
-                if (!ctxt.isEnabled(DeserializationFeature.READ_UNKNOWN_ENUM_VALUES_AS_NULL)) {
+                if (!ctxt.isEnabled(DeserializationFeatures.READ_UNKNOWN_ENUM_VALUES_AS_NULL)) {
                     return (EnumMap<?,?>) ctxt.handleWeirdStringValue(_enumClass, keyName,
                             "value not one of declared Enum instance names for %s",
                             _containerType.getKeyType());
diff --git a/src/main/java/com/fasterxml/jackson/databind/deser/std/EnumSetDeserializer.java b/src/main/java/com/fasterxml/jackson/databind/deser/std/EnumSetDeserializer.java
index 08ceee8c1..c71927904 100644
--- a/src/main/java/com/fasterxml/jackson/databind/deser/std/EnumSetDeserializer.java
+++ b/src/main/java/com/fasterxml/jackson/databind/deser/std/EnumSetDeserializer.java
@@ -196,7 +196,7 @@ public class EnumSetDeserializer
     {
         boolean canWrap = (_unwrapSingle == Boolean.TRUE) ||
                 ((_unwrapSingle == null) &&
-                        ctxt.isEnabled(DeserializationFeature.ACCEPT_SINGLE_VALUE_AS_ARRAY));
+                        ctxt.isEnabled(DeserializationFeatures.ACCEPT_SINGLE_VALUE_AS_ARRAY));
 
         if (!canWrap) {
             return (EnumSet<?>) ctxt.handleUnexpectedToken(EnumSet.class, p);
diff --git a/src/main/java/com/fasterxml/jackson/databind/deser/std/FactoryBasedEnumDeserializer.java b/src/main/java/com/fasterxml/jackson/databind/deser/std/FactoryBasedEnumDeserializer.java
index 8802f5a70..98bdb44e4 100644
--- a/src/main/java/com/fasterxml/jackson/databind/deser/std/FactoryBasedEnumDeserializer.java
+++ b/src/main/java/com/fasterxml/jackson/databind/deser/std/FactoryBasedEnumDeserializer.java
@@ -135,7 +135,7 @@ class FactoryBasedEnumDeserializer
         } catch (Exception e) {
             Throwable t = ClassUtil.throwRootCauseIfIOE(e);
             // [databind#1642]:
-            if (ctxt.isEnabled(DeserializationFeature.READ_UNKNOWN_ENUM_VALUES_AS_NULL) &&
+            if (ctxt.isEnabled(DeserializationFeatures.READ_UNKNOWN_ENUM_VALUES_AS_NULL) &&
                     t instanceof IllegalArgumentException) {
                 return null;
             }
@@ -197,7 +197,7 @@ class FactoryBasedEnumDeserializer
         t = ClassUtil.getRootCause(t);
         // Errors to be passed as is
         ClassUtil.throwIfError(t);
-        boolean wrap = (ctxt == null) || ctxt.isEnabled(DeserializationFeature.WRAP_EXCEPTIONS);
+        boolean wrap = (ctxt == null) || ctxt.isEnabled(DeserializationFeatures.WRAP_EXCEPTIONS);
         // Ditto for IOExceptions; except we may want to wrap JSON exceptions
         if (t instanceof IOException) {
             if (!wrap || !(t instanceof JsonProcessingException)) {
diff --git a/src/main/java/com/fasterxml/jackson/databind/deser/std/FromStringDeserializer.java b/src/main/java/com/fasterxml/jackson/databind/deser/std/FromStringDeserializer.java
index 68187c130..2d5921f7c 100644
--- a/src/main/java/com/fasterxml/jackson/databind/deser/std/FromStringDeserializer.java
+++ b/src/main/java/com/fasterxml/jackson/databind/deser/std/FromStringDeserializer.java
@@ -32,7 +32,7 @@ import com.fasterxml.jackson.databind.util.ClassUtil;
  * <li>Embedded values ({@link JsonToken#VALUE_EMBEDDED_OBJECT}) are returned as-is
  *    if they are of compatible type
  *  </li>
- * <li>Arrays may be "unwrapped" if (and only if) {@link DeserializationFeature#UNWRAP_SINGLE_VALUE_ARRAYS}
+ * <li>Arrays may be "unwrapped" if (and only if) {@link DeserializationFeatures#UNWRAP_SINGLE_VALUE_ARRAYS}
  *    is enabled, and array contains just a single scalar value that can be deserialized
  *    (for example, JSON Array with single JSON String element).
  *  </li>
diff --git a/src/main/java/com/fasterxml/jackson/databind/deser/std/JsonNodeDeserializer.java b/src/main/java/com/fasterxml/jackson/databind/deser/std/JsonNodeDeserializer.java
index 01937fe8b..87121ab15 100644
--- a/src/main/java/com/fasterxml/jackson/databind/deser/std/JsonNodeDeserializer.java
+++ b/src/main/java/com/fasterxml/jackson/databind/deser/std/JsonNodeDeserializer.java
@@ -222,7 +222,7 @@ abstract class BaseNodeDeserializer<T extends JsonNode>
         throws JsonProcessingException
     {
         // [databind#237]: Report an error if asked to do so:
-        if (ctxt.isEnabled(DeserializationFeature.FAIL_ON_READING_DUP_TREE_KEY)) {
+        if (ctxt.isEnabled(DeserializationFeatures.FAIL_ON_READING_DUP_TREE_KEY)) {
             ctxt.reportInputMismatch(JsonNode.class,
                     "Duplicate field '%s' for ObjectNode: not allowed when FAIL_ON_READING_DUP_TREE_KEY enabled",
                     fieldName);
@@ -556,9 +556,9 @@ abstract class BaseNodeDeserializer<T extends JsonNode>
         JsonParser.NumberType nt;
         int feats = ctxt.getDeserializationFeatures();
         if ((feats & F_MASK_INT_COERCIONS) != 0) {
-            if (DeserializationFeature.USE_BIG_INTEGER_FOR_INTS.enabledIn(feats)) {
+            if (DeserializationFeatures.USE_BIG_INTEGER_FOR_INTS.enabledIn(feats)) {
                 nt = JsonParser.NumberType.BIG_INTEGER;
-            } else if (DeserializationFeature.USE_LONG_FOR_INTS.enabledIn(feats)) {
+            } else if (DeserializationFeatures.USE_LONG_FOR_INTS.enabledIn(feats)) {
                 nt = JsonParser.NumberType.LONG;
             } else {
                 nt = p.getNumberType();
@@ -582,7 +582,7 @@ abstract class BaseNodeDeserializer<T extends JsonNode>
         if (nt == JsonParser.NumberType.BIG_DECIMAL) {
             return nodeFactory.numberNode(p.getDecimalValue());
         }
-        if (ctxt.isEnabled(DeserializationFeature.USE_BIG_DECIMAL_FOR_FLOATS)) {
+        if (ctxt.isEnabled(DeserializationFeatures.USE_BIG_DECIMAL_FOR_FLOATS)) {
             // 20-May-2016, tatu: As per [databind#1028], need to be careful
             //   (note: JDK 1.8 would have `Double.isFinite()`)
             if (p.isNaN()) {
diff --git a/src/main/java/com/fasterxml/jackson/databind/deser/std/NumberDeserializers.java b/src/main/java/com/fasterxml/jackson/databind/deser/std/NumberDeserializers.java
index 35ec9d4da..f7dbe584d 100644
--- a/src/main/java/com/fasterxml/jackson/databind/deser/std/NumberDeserializers.java
+++ b/src/main/java/com/fasterxml/jackson/databind/deser/std/NumberDeserializers.java
@@ -152,7 +152,7 @@ public class NumberDeserializers
         public final T getNullValue(DeserializationContext ctxt) throws JsonMappingException {
             // 01-Mar-2017, tatu: Alas, not all paths lead to `_coerceNull()`, as `SettableBeanProperty`
             //    short-circuits `null` handling. Hence need this check as well.
-            if (_primitive && ctxt.isEnabled(DeserializationFeature.FAIL_ON_NULL_FOR_PRIMITIVES)) {
+            if (_primitive && ctxt.isEnabled(DeserializationFeatures.FAIL_ON_NULL_FOR_PRIMITIVES)) {
                 ctxt.reportInputMismatch(this,
                         "Cannot map `null` into type %s (set DeserializationConfig.DeserializationFeature.FAIL_ON_NULL_FOR_PRIMITIVES to 'false' to allow)",
                         handledType().toString());
@@ -316,7 +316,7 @@ public class NumberDeserializers
                 return Byte.valueOf((byte) value);
             }
             if (t == JsonToken.VALUE_NUMBER_FLOAT) {
-                if (!ctxt.isEnabled(DeserializationFeature.ACCEPT_FLOAT_AS_INT)) {
+                if (!ctxt.isEnabled(DeserializationFeatures.ACCEPT_FLOAT_AS_INT)) {
                     _failDoubleToIntCoercion(p, ctxt, "Byte");
                 }
                 return p.getByteValue();
@@ -387,7 +387,7 @@ public class NumberDeserializers
                 return Short.valueOf((short) value);
             }
             if (t == JsonToken.VALUE_NUMBER_FLOAT) {
-                if (!ctxt.isEnabled(DeserializationFeature.ACCEPT_FLOAT_AS_INT)) {
+                if (!ctxt.isEnabled(DeserializationFeatures.ACCEPT_FLOAT_AS_INT)) {
                     _failDoubleToIntCoercion(p, ctxt, "Short");
                 }
                 return p.getShortValue();
@@ -493,7 +493,7 @@ public class NumberDeserializers
             case JsonTokenId.ID_NUMBER_INT:
                 return Integer.valueOf(p.getIntValue());
             case JsonTokenId.ID_NUMBER_FLOAT: // coercing may work too
-                if (!ctxt.isEnabled(DeserializationFeature.ACCEPT_FLOAT_AS_INT)) {
+                if (!ctxt.isEnabled(DeserializationFeatures.ACCEPT_FLOAT_AS_INT)) {
                     _failDoubleToIntCoercion(p, ctxt, "Integer");
                 }
                 return Integer.valueOf(p.getValueAsInt());
@@ -564,7 +564,7 @@ public class NumberDeserializers
             case JsonTokenId.ID_NUMBER_INT:
                 return p.getLongValue();
             case JsonTokenId.ID_NUMBER_FLOAT:
-                if (!ctxt.isEnabled(DeserializationFeature.ACCEPT_FLOAT_AS_INT)) {
+                if (!ctxt.isEnabled(DeserializationFeatures.ACCEPT_FLOAT_AS_INT)) {
                     _failDoubleToIntCoercion(p, ctxt, "Long");
                 }
                 return p.getValueAsLong();
@@ -774,7 +774,7 @@ public class NumberDeserializers
                 return p.getNumberValue();
 
             case JsonTokenId.ID_NUMBER_FLOAT:
-                if (ctxt.isEnabled(DeserializationFeature.USE_BIG_DECIMAL_FOR_FLOATS)) {
+                if (ctxt.isEnabled(DeserializationFeatures.USE_BIG_DECIMAL_FOR_FLOATS)) {
                     // 10-Mar-2017, tatu: NaN and BigDecimal won't mix...
                     if (!p.isNaN()) {
                         return p.getDecimalValue();
@@ -807,16 +807,16 @@ public class NumberDeserializers
                 _verifyStringForScalarCoercion(ctxt, text);
                 try {
                     if (!_isIntNumber(text)) {
-                        if (ctxt.isEnabled(DeserializationFeature.USE_BIG_DECIMAL_FOR_FLOATS)) {
+                        if (ctxt.isEnabled(DeserializationFeatures.USE_BIG_DECIMAL_FOR_FLOATS)) {
                             return new BigDecimal(text);
                         }
                         return Double.valueOf(text);
                     }
-                    if (ctxt.isEnabled(DeserializationFeature.USE_BIG_INTEGER_FOR_INTS)) {
+                    if (ctxt.isEnabled(DeserializationFeatures.USE_BIG_INTEGER_FOR_INTS)) {
                         return new BigInteger(text);
                     }
                     long value = Long.parseLong(text);
-                    if (!ctxt.isEnabled(DeserializationFeature.USE_LONG_FOR_INTS)) {
+                    if (!ctxt.isEnabled(DeserializationFeatures.USE_LONG_FOR_INTS)) {
                         if (value <= Integer.MAX_VALUE && value >= Integer.MIN_VALUE) {
                             return Integer.valueOf((int) value);
                         }
@@ -894,7 +894,7 @@ public class NumberDeserializers
                 }
                 break;
             case JsonTokenId.ID_NUMBER_FLOAT:
-                if (!ctxt.isEnabled(DeserializationFeature.ACCEPT_FLOAT_AS_INT)) {
+                if (!ctxt.isEnabled(DeserializationFeatures.ACCEPT_FLOAT_AS_INT)) {
                     _failDoubleToIntCoercion(p, ctxt, "java.math.BigInteger");
                 }
                 return p.getDecimalValue().toBigInteger();
diff --git a/src/main/java/com/fasterxml/jackson/databind/deser/std/ObjectArrayDeserializer.java b/src/main/java/com/fasterxml/jackson/databind/deser/std/ObjectArrayDeserializer.java
index 017317d5d..0cc14214c 100644
--- a/src/main/java/com/fasterxml/jackson/databind/deser/std/ObjectArrayDeserializer.java
+++ b/src/main/java/com/fasterxml/jackson/databind/deser/std/ObjectArrayDeserializer.java
@@ -308,7 +308,7 @@ public class ObjectArrayDeserializer
     {
         // Empty String can become null...
         if (p.hasToken(JsonToken.VALUE_STRING)
-                && ctxt.isEnabled(DeserializationFeature.ACCEPT_EMPTY_STRING_AS_NULL_OBJECT)) {
+                && ctxt.isEnabled(DeserializationFeatures.ACCEPT_EMPTY_STRING_AS_NULL_OBJECT)) {
             String str = p.getText();
             if (str.length() == 0) {
                 return null;
@@ -318,7 +318,7 @@ public class ObjectArrayDeserializer
         // Can we do implicit coercion to a single-element array still?
         boolean canWrap = (_unwrapSingle == Boolean.TRUE) ||
                 ((_unwrapSingle == null) &&
-                        ctxt.isEnabled(DeserializationFeature.ACCEPT_SINGLE_VALUE_AS_ARRAY));
+                        ctxt.isEnabled(DeserializationFeatures.ACCEPT_SINGLE_VALUE_AS_ARRAY));
         if (!canWrap) {
             // One exception; byte arrays are generally serialized as base64, so that should be handled
             JsonToken t = p.getCurrentToken();
diff --git a/src/main/java/com/fasterxml/jackson/databind/deser/std/PrimitiveArrayDeserializers.java b/src/main/java/com/fasterxml/jackson/databind/deser/std/PrimitiveArrayDeserializers.java
index 175db71e0..e6ec13ae2 100644
--- a/src/main/java/com/fasterxml/jackson/databind/deser/std/PrimitiveArrayDeserializers.java
+++ b/src/main/java/com/fasterxml/jackson/databind/deser/std/PrimitiveArrayDeserializers.java
@@ -226,14 +226,14 @@ public abstract class PrimitiveArrayDeserializers<T> extends StdDeserializer<T>
     {
         // Empty String can become null...
         if (p.hasToken(JsonToken.VALUE_STRING)
-                && ctxt.isEnabled(DeserializationFeature.ACCEPT_EMPTY_STRING_AS_NULL_OBJECT)) {
+                && ctxt.isEnabled(DeserializationFeatures.ACCEPT_EMPTY_STRING_AS_NULL_OBJECT)) {
             if (p.getText().length() == 0) {
                 return null;
             }
         }
         boolean canWrap = (_unwrapSingle == Boolean.TRUE) ||
                 ((_unwrapSingle == null) &&
-                        ctxt.isEnabled(DeserializationFeature.ACCEPT_SINGLE_VALUE_AS_ARRAY));
+                        ctxt.isEnabled(DeserializationFeatures.ACCEPT_SINGLE_VALUE_AS_ARRAY));
         if (canWrap) {
             return handleSingleElementUnwrapped(p, ctxt);
         }
diff --git a/src/main/java/com/fasterxml/jackson/databind/deser/std/StackTraceElementDeserializer.java b/src/main/java/com/fasterxml/jackson/databind/deser/std/StackTraceElementDeserializer.java
index fcfba1029..22ce3662a 100644
--- a/src/main/java/com/fasterxml/jackson/databind/deser/std/StackTraceElementDeserializer.java
+++ b/src/main/java/com/fasterxml/jackson/databind/deser/std/StackTraceElementDeserializer.java
@@ -6,7 +6,7 @@ import com.fasterxml.jackson.core.JsonParser;
 import com.fasterxml.jackson.core.JsonToken;
 
 import com.fasterxml.jackson.databind.DeserializationContext;
-import com.fasterxml.jackson.databind.DeserializationFeature;
+import com.fasterxml.jackson.databind.DeserializationFeatures;
 
 public class StackTraceElementDeserializer
     extends StdScalarDeserializer<StackTraceElement>
@@ -61,7 +61,7 @@ public class StackTraceElementDeserializer
             }
             return constructValue(ctxt, className, methodName, fileName, lineNumber,
                     moduleName, moduleVersion, classLoaderName);
-        } else if (t == JsonToken.START_ARRAY && ctxt.isEnabled(DeserializationFeature.UNWRAP_SINGLE_VALUE_ARRAYS)) {
+        } else if (t == JsonToken.START_ARRAY && ctxt.isEnabled(DeserializationFeatures.UNWRAP_SINGLE_VALUE_ARRAYS)) {
             p.nextToken();
             final StackTraceElement value = deserialize(p, ctxt);
             if (p.nextToken() != JsonToken.END_ARRAY) {
diff --git a/src/main/java/com/fasterxml/jackson/databind/deser/std/StdDeserializer.java b/src/main/java/com/fasterxml/jackson/databind/deser/std/StdDeserializer.java
index 5d0133fe0..a62721284 100644
--- a/src/main/java/com/fasterxml/jackson/databind/deser/std/StdDeserializer.java
+++ b/src/main/java/com/fasterxml/jackson/databind/deser/std/StdDeserializer.java
@@ -34,20 +34,20 @@ public abstract class StdDeserializer<T>
     private static final long serialVersionUID = 1L;
 
     /**
-     * Bitmask that covers {@link DeserializationFeature#USE_BIG_INTEGER_FOR_INTS}
-     * and {@link DeserializationFeature#USE_LONG_FOR_INTS}, used for more efficient
+     * Bitmask that covers {@link DeserializationFeatures#USE_BIG_INTEGER_FOR_INTS}
+     * and {@link DeserializationFeatures#USE_LONG_FOR_INTS}, used for more efficient
      * cheks when coercing integral values for untyped deserialization.
      *
      * @since 2.6
      */
     protected final static int F_MASK_INT_COERCIONS = 
-            DeserializationFeature.USE_BIG_INTEGER_FOR_INTS.getMask()
-            | DeserializationFeature.USE_LONG_FOR_INTS.getMask();
+            DeserializationFeatures.USE_BIG_INTEGER_FOR_INTS.getMask()
+            | DeserializationFeatures.USE_LONG_FOR_INTS.getMask();
 
     // @since 2.9
     protected final static int F_MASK_ACCEPT_ARRAYS =
-            DeserializationFeature.UNWRAP_SINGLE_VALUE_ARRAYS.getMask() |
-            DeserializationFeature.ACCEPT_EMPTY_ARRAY_AS_NULL_OBJECT.getMask();
+            DeserializationFeatures.UNWRAP_SINGLE_VALUE_ARRAYS.getMask() |
+            DeserializationFeatures.ACCEPT_EMPTY_ARRAY_AS_NULL_OBJECT.getMask();
 
     
     /**
@@ -177,7 +177,7 @@ public abstract class StdDeserializer<T>
             return Boolean.TRUE.equals(b);
         }
         // [databind#381]
-        if (t == JsonToken.START_ARRAY && ctxt.isEnabled(DeserializationFeature.UNWRAP_SINGLE_VALUE_ARRAYS)) {
+        if (t == JsonToken.START_ARRAY && ctxt.isEnabled(DeserializationFeatures.UNWRAP_SINGLE_VALUE_ARRAYS)) {
             p.nextToken();
             final boolean parsed = _parseBooleanPrimitive(p, ctxt);
             _verifyEndArrayForSingle(p, ctxt);
@@ -241,7 +241,7 @@ public abstract class StdDeserializer<T>
             }
             return _parseIntPrimitive(ctxt, text);
         case JsonTokenId.ID_NUMBER_FLOAT:
-            if (!ctxt.isEnabled(DeserializationFeature.ACCEPT_FLOAT_AS_INT)) {
+            if (!ctxt.isEnabled(DeserializationFeatures.ACCEPT_FLOAT_AS_INT)) {
                 _failDoubleToIntCoercion(p, ctxt, "int");
             }
             return p.getValueAsInt();
@@ -249,7 +249,7 @@ public abstract class StdDeserializer<T>
             _verifyNullForPrimitive(ctxt);
             return 0;
         case JsonTokenId.ID_START_ARRAY:
-            if (ctxt.isEnabled(DeserializationFeature.UNWRAP_SINGLE_VALUE_ARRAYS)) {
+            if (ctxt.isEnabled(DeserializationFeatures.UNWRAP_SINGLE_VALUE_ARRAYS)) {
                 p.nextToken();
                 final int parsed = _parseIntPrimitive(p, ctxt);
                 _verifyEndArrayForSingle(p, ctxt);
@@ -301,7 +301,7 @@ public abstract class StdDeserializer<T>
             }
             return _parseLongPrimitive(ctxt, text);
         case JsonTokenId.ID_NUMBER_FLOAT:
-            if (!ctxt.isEnabled(DeserializationFeature.ACCEPT_FLOAT_AS_INT)) {
+            if (!ctxt.isEnabled(DeserializationFeatures.ACCEPT_FLOAT_AS_INT)) {
                 _failDoubleToIntCoercion(p, ctxt, "long");
             }
             return p.getValueAsLong();
@@ -309,7 +309,7 @@ public abstract class StdDeserializer<T>
             _verifyNullForPrimitive(ctxt);
             return 0L;
         case JsonTokenId.ID_START_ARRAY:
-            if (ctxt.isEnabled(DeserializationFeature.UNWRAP_SINGLE_VALUE_ARRAYS)) {
+            if (ctxt.isEnabled(DeserializationFeatures.UNWRAP_SINGLE_VALUE_ARRAYS)) {
                 p.nextToken();
                 final long parsed = _parseLongPrimitive(p, ctxt);
                 _verifyEndArrayForSingle(p, ctxt);
@@ -355,7 +355,7 @@ public abstract class StdDeserializer<T>
             _verifyNullForPrimitive(ctxt);
             return 0.0f;
         case JsonTokenId.ID_START_ARRAY:
-            if (ctxt.isEnabled(DeserializationFeature.UNWRAP_SINGLE_VALUE_ARRAYS)) {
+            if (ctxt.isEnabled(DeserializationFeatures.UNWRAP_SINGLE_VALUE_ARRAYS)) {
                 p.nextToken();
                 final float parsed = _parseFloatPrimitive(p, ctxt);
                 _verifyEndArrayForSingle(p, ctxt);
@@ -416,7 +416,7 @@ public abstract class StdDeserializer<T>
             _verifyNullForPrimitive(ctxt);
             return 0.0;
         case JsonTokenId.ID_START_ARRAY:
-            if (ctxt.isEnabled(DeserializationFeature.UNWRAP_SINGLE_VALUE_ARRAYS)) {
+            if (ctxt.isEnabled(DeserializationFeatures.UNWRAP_SINGLE_VALUE_ARRAYS)) {
                 p.nextToken();
                 final double parsed = _parseDoublePrimitive(p, ctxt);
                 _verifyEndArrayForSingle(p, ctxt);
@@ -493,11 +493,11 @@ public abstract class StdDeserializer<T>
         if (ctxt.hasSomeOfFeatures(F_MASK_ACCEPT_ARRAYS)) {
             t = p.nextToken();
             if (t == JsonToken.END_ARRAY) {
-                if (ctxt.isEnabled(DeserializationFeature.ACCEPT_EMPTY_ARRAY_AS_NULL_OBJECT)) {
+                if (ctxt.isEnabled(DeserializationFeatures.ACCEPT_EMPTY_ARRAY_AS_NULL_OBJECT)) {
                     return (java.util.Date) getNullValue(ctxt);
                 }
             }
-            if (ctxt.isEnabled(DeserializationFeature.UNWRAP_SINGLE_VALUE_ARRAYS)) {
+            if (ctxt.isEnabled(DeserializationFeatures.UNWRAP_SINGLE_VALUE_ARRAYS)) {
                 final Date parsed = _parseDate(p, ctxt);
                 _verifyEndArrayForSingle(p, ctxt);
                 return parsed;            
@@ -581,7 +581,7 @@ public abstract class StdDeserializer<T>
     {
         JsonToken t = p.getCurrentToken();
         if (t == JsonToken.START_ARRAY) {
-            if (ctxt.isEnabled(DeserializationFeature.ACCEPT_EMPTY_ARRAY_AS_NULL_OBJECT)) {
+            if (ctxt.isEnabled(DeserializationFeatures.ACCEPT_EMPTY_ARRAY_AS_NULL_OBJECT)) {
                 t = p.nextToken();
                 if (t == JsonToken.END_ARRAY) {
                     return null;
@@ -589,7 +589,7 @@ public abstract class StdDeserializer<T>
                 return (T) ctxt.handleUnexpectedToken(handledType(), p);
             }
         } else if (t == JsonToken.VALUE_STRING) {
-            if (ctxt.isEnabled(DeserializationFeature.ACCEPT_EMPTY_STRING_AS_NULL_OBJECT)) {
+            if (ctxt.isEnabled(DeserializationFeatures.ACCEPT_EMPTY_STRING_AS_NULL_OBJECT)) {
                 String str = p.getText().trim();
                 if (str.isEmpty()) {
                     return null;
@@ -635,7 +635,7 @@ public abstract class StdDeserializer<T>
      */
 
     /**
-     * Helper method that allows easy support for array-related {@link DeserializationFeature}s
+     * Helper method that allows easy support for array-related {@link DeserializationFeatures}s
      * `ACCEPT_EMPTY_ARRAY_AS_NULL_OBJECT` and `UNWRAP_SINGLE_VALUE_ARRAYS`: checks for either
      * empty array, or single-value array-wrapped value (respectively), and either reports
      * an exception (if no match, or feature(s) not enabled), or returns appropriate
@@ -656,11 +656,11 @@ public abstract class StdDeserializer<T>
         if (ctxt.hasSomeOfFeatures(F_MASK_ACCEPT_ARRAYS)) {
             t = p.nextToken();
             if (t == JsonToken.END_ARRAY) {
-                if (ctxt.isEnabled(DeserializationFeature.ACCEPT_EMPTY_ARRAY_AS_NULL_OBJECT)) {
+                if (ctxt.isEnabled(DeserializationFeatures.ACCEPT_EMPTY_ARRAY_AS_NULL_OBJECT)) {
                     return getNullValue(ctxt);
                 }
             }
-            if (ctxt.isEnabled(DeserializationFeature.UNWRAP_SINGLE_VALUE_ARRAYS)) {
+            if (ctxt.isEnabled(DeserializationFeatures.UNWRAP_SINGLE_VALUE_ARRAYS)) {
                 final T parsed = deserialize(p, ctxt);
                 if (p.nextToken() != JsonToken.END_ARRAY) {
                     handleMissingEndArrayForSingle(p, ctxt);
@@ -676,7 +676,7 @@ public abstract class StdDeserializer<T>
     }
 
     /**
-     * Helper called to support {@link DeserializationFeature#UNWRAP_SINGLE_VALUE_ARRAYS}:
+     * Helper called to support {@link DeserializationFeatures#UNWRAP_SINGLE_VALUE_ARRAYS}:
      * default implementation simply calls
      * {@link #deserialize(JsonParser, DeserializationContext)},
      * but handling may be overridden.
@@ -719,18 +719,18 @@ public abstract class StdDeserializer<T>
      * {@link java.lang.Number} into "bigger" type like {@link java.lang.Long} or
      * {@link java.math.BigInteger}
      * 
-     * @see DeserializationFeature#USE_BIG_INTEGER_FOR_INTS
-     * @see DeserializationFeature#USE_LONG_FOR_INTS
+     * @see DeserializationFeatures#USE_BIG_INTEGER_FOR_INTS
+     * @see DeserializationFeatures#USE_LONG_FOR_INTS
      *
      * @since 2.6
      */
     protected Object _coerceIntegral(JsonParser p, DeserializationContext ctxt) throws IOException
     {
         int feats = ctxt.getDeserializationFeatures();
-        if (DeserializationFeature.USE_BIG_INTEGER_FOR_INTS.enabledIn(feats)) {
+        if (DeserializationFeatures.USE_BIG_INTEGER_FOR_INTS.enabledIn(feats)) {
             return p.getBigIntegerValue();
         }
-        if (DeserializationFeature.USE_LONG_FOR_INTS.enabledIn(feats)) {
+        if (DeserializationFeatures.USE_LONG_FOR_INTS.enabledIn(feats)) {
             return p.getLongValue();
         }
         return p.getBigIntegerValue(); // should be optimal, whatever it is
@@ -763,8 +763,8 @@ public abstract class StdDeserializer<T>
         if (!ctxt.isEnabled(MapperFeature.ALLOW_COERCION_OF_SCALARS)) {
             feat = MapperFeature.ALLOW_COERCION_OF_SCALARS;
             enable = true;
-        } else if (isPrimitive && ctxt.isEnabled(DeserializationFeature.FAIL_ON_NULL_FOR_PRIMITIVES)) {
-            feat = DeserializationFeature.FAIL_ON_NULL_FOR_PRIMITIVES;
+        } else if (isPrimitive && ctxt.isEnabled(DeserializationFeatures.FAIL_ON_NULL_FOR_PRIMITIVES)) {
+            feat = DeserializationFeatures.FAIL_ON_NULL_FOR_PRIMITIVES;
             enable = false;
         } else {
             return getNullValue(ctxt);
@@ -786,8 +786,8 @@ public abstract class StdDeserializer<T>
         if (!ctxt.isEnabled(MapperFeature.ALLOW_COERCION_OF_SCALARS)) {
             feat = MapperFeature.ALLOW_COERCION_OF_SCALARS;
             enable = true;
-        } else if (isPrimitive && ctxt.isEnabled(DeserializationFeature.FAIL_ON_NULL_FOR_PRIMITIVES)) {
-            feat = DeserializationFeature.FAIL_ON_NULL_FOR_PRIMITIVES;
+        } else if (isPrimitive && ctxt.isEnabled(DeserializationFeatures.FAIL_ON_NULL_FOR_PRIMITIVES)) {
+            feat = DeserializationFeatures.FAIL_ON_NULL_FOR_PRIMITIVES;
             enable = false;
         } else {
             return getNullValue(ctxt);
@@ -799,7 +799,7 @@ public abstract class StdDeserializer<T>
     // @since 2.9
     protected final void _verifyNullForPrimitive(DeserializationContext ctxt) throws JsonMappingException
     {
-        if (ctxt.isEnabled(DeserializationFeature.FAIL_ON_NULL_FOR_PRIMITIVES)) {
+        if (ctxt.isEnabled(DeserializationFeatures.FAIL_ON_NULL_FOR_PRIMITIVES)) {
             ctxt.reportInputMismatch(this,
 "Cannot coerce `null` %s (disable `DeserializationFeature.FAIL_ON_NULL_FOR_PRIMITIVES` to allow)",
                     _coercedTypeDesc());
@@ -816,8 +816,8 @@ public abstract class StdDeserializer<T>
         if (!ctxt.isEnabled(MapperFeature.ALLOW_COERCION_OF_SCALARS)) {
             feat = MapperFeature.ALLOW_COERCION_OF_SCALARS;
             enable = true;
-        } else if (ctxt.isEnabled(DeserializationFeature.FAIL_ON_NULL_FOR_PRIMITIVES)) {
-            feat = DeserializationFeature.FAIL_ON_NULL_FOR_PRIMITIVES;
+        } else if (ctxt.isEnabled(DeserializationFeatures.FAIL_ON_NULL_FOR_PRIMITIVES)) {
+            feat = DeserializationFeatures.FAIL_ON_NULL_FOR_PRIMITIVES;
             enable = false;
         } else {
             return;
diff --git a/src/main/java/com/fasterxml/jackson/databind/deser/std/StdKeyDeserializer.java b/src/main/java/com/fasterxml/jackson/databind/deser/std/StdKeyDeserializer.java
index 29a944bc0..a3f2c1bb9 100644
--- a/src/main/java/com/fasterxml/jackson/databind/deser/std/StdKeyDeserializer.java
+++ b/src/main/java/com/fasterxml/jackson/databind/deser/std/StdKeyDeserializer.java
@@ -133,7 +133,7 @@ public class StdKeyDeserializer extends KeyDeserializer
             return ctxt.handleWeirdKey(_keyClass, key, "not a valid representation, problem: (%s) %s",
                     re.getClass().getName(), re.getMessage());
         }
-        if (_keyClass.isEnum() && ctxt.getConfig().isEnabled(DeserializationFeature.READ_UNKNOWN_ENUM_VALUES_AS_NULL)) {
+        if (_keyClass.isEnum() && ctxt.getConfig().isEnabled(DeserializationFeatures.READ_UNKNOWN_ENUM_VALUES_AS_NULL)) {
             return null;
         }
         return ctxt.handleWeirdKey(_keyClass, key, "not a valid representation");
@@ -381,14 +381,14 @@ public class StdKeyDeserializer extends KeyDeserializer
                     ClassUtil.unwrapAndThrowAsIAE(e);
                 }
             }
-            EnumResolver res = ctxt.isEnabled(DeserializationFeature.READ_ENUMS_USING_TO_STRING)
+            EnumResolver res = ctxt.isEnabled(DeserializationFeatures.READ_ENUMS_USING_TO_STRING)
                     ? _getToStringResolver(ctxt) : _byNameResolver;
             Enum<?> e = res.findEnum(key);
             if (e == null) {
                 if ((_enumDefaultValue != null)
-                        && ctxt.isEnabled(DeserializationFeature.READ_UNKNOWN_ENUM_VALUES_USING_DEFAULT_VALUE)) {
+                        && ctxt.isEnabled(DeserializationFeatures.READ_UNKNOWN_ENUM_VALUES_USING_DEFAULT_VALUE)) {
                     e = _enumDefaultValue;
-                } else if (!ctxt.isEnabled(DeserializationFeature.READ_UNKNOWN_ENUM_VALUES_AS_NULL)) {
+                } else if (!ctxt.isEnabled(DeserializationFeatures.READ_UNKNOWN_ENUM_VALUES_AS_NULL)) {
                     return ctxt.handleWeirdKey(_keyClass, key, "not one of values excepted for Enum class: %s",
                         res.getEnumIds());
                 }
diff --git a/src/main/java/com/fasterxml/jackson/databind/deser/std/StringArrayDeserializer.java b/src/main/java/com/fasterxml/jackson/databind/deser/std/StringArrayDeserializer.java
index a348a4019..a9937059b 100644
--- a/src/main/java/com/fasterxml/jackson/databind/deser/std/StringArrayDeserializer.java
+++ b/src/main/java/com/fasterxml/jackson/databind/deser/std/StringArrayDeserializer.java
@@ -297,7 +297,7 @@ public final class StringArrayDeserializer
         // implicit arrays from single values?
         boolean canWrap = (_unwrapSingle == Boolean.TRUE) ||
                 ((_unwrapSingle == null) &&
-                        ctxt.isEnabled(DeserializationFeature.ACCEPT_SINGLE_VALUE_AS_ARRAY));
+                        ctxt.isEnabled(DeserializationFeatures.ACCEPT_SINGLE_VALUE_AS_ARRAY));
         if (canWrap) {
             String value = p.hasToken(JsonToken.VALUE_NULL)
                     ? (String) _nullProvider.getNullValue(ctxt)
@@ -305,7 +305,7 @@ public final class StringArrayDeserializer
             return new String[] { value };
         }
         if (p.hasToken(JsonToken.VALUE_STRING)
-                    && ctxt.isEnabled(DeserializationFeature.ACCEPT_EMPTY_STRING_AS_NULL_OBJECT)) {
+                    && ctxt.isEnabled(DeserializationFeatures.ACCEPT_EMPTY_STRING_AS_NULL_OBJECT)) {
             String str = p.getText();
             if (str.length() == 0) {
                 return null;
diff --git a/src/main/java/com/fasterxml/jackson/databind/deser/std/StringCollectionDeserializer.java b/src/main/java/com/fasterxml/jackson/databind/deser/std/StringCollectionDeserializer.java
index 321df6f29..29c6080ec 100644
--- a/src/main/java/com/fasterxml/jackson/databind/deser/std/StringCollectionDeserializer.java
+++ b/src/main/java/com/fasterxml/jackson/databind/deser/std/StringCollectionDeserializer.java
@@ -261,7 +261,7 @@ public final class StringCollectionDeserializer
         // implicit arrays from single values?
         boolean canWrap = (_unwrapSingle == Boolean.TRUE) ||
                 ((_unwrapSingle == null) &&
-                        ctxt.isEnabled(DeserializationFeature.ACCEPT_SINGLE_VALUE_AS_ARRAY));
+                        ctxt.isEnabled(DeserializationFeatures.ACCEPT_SINGLE_VALUE_AS_ARRAY));
         if (!canWrap) {
             return (Collection<String>) ctxt.handleUnexpectedToken(_containerType.getRawClass(), p);
         }
diff --git a/src/main/java/com/fasterxml/jackson/databind/deser/std/UntypedObjectDeserializer.java b/src/main/java/com/fasterxml/jackson/databind/deser/std/UntypedObjectDeserializer.java
index 67be23847..ba22a4432 100644
--- a/src/main/java/com/fasterxml/jackson/databind/deser/std/UntypedObjectDeserializer.java
+++ b/src/main/java/com/fasterxml/jackson/databind/deser/std/UntypedObjectDeserializer.java
@@ -7,7 +7,7 @@ import com.fasterxml.jackson.core.*;
 import com.fasterxml.jackson.databind.BeanProperty;
 import com.fasterxml.jackson.databind.DeserializationConfig;
 import com.fasterxml.jackson.databind.DeserializationContext;
-import com.fasterxml.jackson.databind.DeserializationFeature;
+import com.fasterxml.jackson.databind.DeserializationFeatures;
 import com.fasterxml.jackson.databind.JavaType;
 import com.fasterxml.jackson.databind.JsonDeserializer;
 import com.fasterxml.jackson.databind.JsonMappingException;
@@ -247,7 +247,7 @@ public class UntypedObjectDeserializer
             }
             return mapObject(p, ctxt);
         case JsonTokenId.ID_START_ARRAY:
-            if (ctxt.isEnabled(DeserializationFeature.USE_JAVA_ARRAY_FOR_JSON_ARRAY)) {
+            if (ctxt.isEnabled(DeserializationFeatures.USE_JAVA_ARRAY_FOR_JSON_ARRAY)) {
                 return mapArrayToArray(p, ctxt);
             }
             if (_listDeserializer != null) {
@@ -279,7 +279,7 @@ public class UntypedObjectDeserializer
                 return _numberDeserializer.deserialize(p, ctxt);
             }
             // Need to allow overriding the behavior regarding which type to use
-            if (ctxt.isEnabled(DeserializationFeature.USE_BIG_DECIMAL_FOR_FLOATS)) {
+            if (ctxt.isEnabled(DeserializationFeatures.USE_BIG_DECIMAL_FOR_FLOATS)) {
                 return p.getDecimalValue();
             }
             // as per [databind#1453] should not assume Double but:
@@ -337,7 +337,7 @@ public class UntypedObjectDeserializer
             if (_numberDeserializer != null) {
                 return _numberDeserializer.deserialize(p, ctxt);
             }
-            if (ctxt.isEnabled(DeserializationFeature.USE_BIG_DECIMAL_FOR_FLOATS)) {
+            if (ctxt.isEnabled(DeserializationFeatures.USE_BIG_DECIMAL_FOR_FLOATS)) {
                 return p.getDecimalValue();
             }
             return p.getNumberValue();
@@ -383,7 +383,7 @@ public class UntypedObjectDeserializer
             if (intoValue instanceof Collection<?>) {
                 return mapArray(p, ctxt, (Collection<Object>) intoValue);
             }
-            if (ctxt.isEnabled(DeserializationFeature.USE_JAVA_ARRAY_FOR_JSON_ARRAY)) {
+            if (ctxt.isEnabled(DeserializationFeatures.USE_JAVA_ARRAY_FOR_JSON_ARRAY)) {
                 return mapArrayToArray(p, ctxt);
             }
             return mapArray(p, ctxt);
@@ -408,7 +408,7 @@ public class UntypedObjectDeserializer
             if (_numberDeserializer != null) {
                 return _numberDeserializer.deserialize(p, ctxt, intoValue);
             }
-            if (ctxt.isEnabled(DeserializationFeature.USE_BIG_DECIMAL_FOR_FLOATS)) {
+            if (ctxt.isEnabled(DeserializationFeatures.USE_BIG_DECIMAL_FOR_FLOATS)) {
                 return p.getDecimalValue();
             }
             return p.getNumberValue();
@@ -656,13 +656,13 @@ public class UntypedObjectDeserializer
                 {
                     JsonToken t = p.nextToken();
                     if (t == JsonToken.END_ARRAY) { // and empty one too
-                        if (ctxt.isEnabled(DeserializationFeature.USE_JAVA_ARRAY_FOR_JSON_ARRAY)) {
+                        if (ctxt.isEnabled(DeserializationFeatures.USE_JAVA_ARRAY_FOR_JSON_ARRAY)) {
                             return NO_OBJECTS;
                         }
                         return new ArrayList<Object>(2);
                     }
                 }
-                if (ctxt.isEnabled(DeserializationFeature.USE_JAVA_ARRAY_FOR_JSON_ARRAY)) {
+                if (ctxt.isEnabled(DeserializationFeatures.USE_JAVA_ARRAY_FOR_JSON_ARRAY)) {
                     return mapArrayToArray(p, ctxt);
                 }
                 return mapArray(p, ctxt);
@@ -678,7 +678,7 @@ public class UntypedObjectDeserializer
                 return p.getNumberValue(); // should be optimal, whatever it is
 
             case JsonTokenId.ID_NUMBER_FLOAT:
-                if (ctxt.isEnabled(DeserializationFeature.USE_BIG_DECIMAL_FOR_FLOATS)) {
+                if (ctxt.isEnabled(DeserializationFeatures.USE_BIG_DECIMAL_FOR_FLOATS)) {
                     return p.getDecimalValue();
                 }
                 return p.getNumberValue();
@@ -715,13 +715,13 @@ public class UntypedObjectDeserializer
                 return p.getText();
 
             case JsonTokenId.ID_NUMBER_INT:
-                if (ctxt.isEnabled(DeserializationFeature.USE_BIG_INTEGER_FOR_INTS)) {
+                if (ctxt.isEnabled(DeserializationFeatures.USE_BIG_INTEGER_FOR_INTS)) {
                     return p.getBigIntegerValue();
                 }
                 return p.getNumberValue();
 
             case JsonTokenId.ID_NUMBER_FLOAT:
-                if (ctxt.isEnabled(DeserializationFeature.USE_BIG_DECIMAL_FOR_FLOATS)) {
+                if (ctxt.isEnabled(DeserializationFeatures.USE_BIG_DECIMAL_FOR_FLOATS)) {
                     return p.getDecimalValue();
                 }
                 return p.getNumberValue();
diff --git a/src/main/java/com/fasterxml/jackson/databind/introspect/JacksonAnnotationIntrospector.java b/src/main/java/com/fasterxml/jackson/databind/introspect/JacksonAnnotationIntrospector.java
index 823deb622..75e260a6f 100644
--- a/src/main/java/com/fasterxml/jackson/databind/introspect/JacksonAnnotationIntrospector.java
+++ b/src/main/java/com/fasterxml/jackson/databind/introspect/JacksonAnnotationIntrospector.java
@@ -14,7 +14,7 @@ import com.fasterxml.jackson.databind.ext.Java7Support;
 import com.fasterxml.jackson.databind.jsontype.NamedType;
 import com.fasterxml.jackson.databind.jsontype.TypeIdResolver;
 import com.fasterxml.jackson.databind.jsontype.TypeResolverBuilder;
-import com.fasterxml.jackson.databind.jsontype.impl.StdTypeResolverBuilder;
+import com.fasterxml.jackson.databind.jsontype.impl.StandardTypeResolverBuilder;
 import com.fasterxml.jackson.databind.ser.BeanPropertyWriter;
 import com.fasterxml.jackson.databind.ser.VirtualBeanPropertyWriter;
 import com.fasterxml.jackson.databind.ser.impl.AttributePropertyWriter;
@@ -1463,16 +1463,16 @@ public class JacksonAnnotationIntrospector
      * Helper method for constructing standard {@link TypeResolverBuilder}
      * implementation.
      */
-    protected StdTypeResolverBuilder _constructStdTypeResolverBuilder() {
-        return new StdTypeResolverBuilder();
+    protected StandardTypeResolverBuilder _constructStdTypeResolverBuilder() {
+        return new StandardTypeResolverBuilder();
     }
 
     /**
      * Helper method for dealing with "no type info" marker; can't be null
      * (as it'd be replaced by default typing)
      */
-    protected StdTypeResolverBuilder _constructNoTypeResolverBuilder() {
-        return StdTypeResolverBuilder.noTypeInfoBuilder();
+    protected StandardTypeResolverBuilder _constructNoTypeResolverBuilder() {
+        return StandardTypeResolverBuilder.noTypeInfoResolverBuilder();
     }
 
     private boolean _primitiveAndWrapper(Class<?> baseType, Class<?> refinement)
diff --git a/src/main/java/com/fasterxml/jackson/databind/jsontype/impl/AsPropertyTypeDeserializer.java b/src/main/java/com/fasterxml/jackson/databind/jsontype/impl/AsPropertyTypeDeserializer.java
index 9bfab808b..ef21e39e7 100644
--- a/src/main/java/com/fasterxml/jackson/databind/jsontype/impl/AsPropertyTypeDeserializer.java
+++ b/src/main/java/com/fasterxml/jackson/databind/jsontype/impl/AsPropertyTypeDeserializer.java
@@ -148,7 +148,7 @@ public class AsPropertyTypeDeserializer extends AsArrayTypeDeserializer
                 return super.deserializeTypedFromAny(p, ctxt);
             }
             if (p.hasToken(JsonToken.VALUE_STRING)) {
-                if (ctxt.isEnabled(DeserializationFeature.ACCEPT_EMPTY_STRING_AS_NULL_OBJECT)) {
+                if (ctxt.isEnabled(DeserializationFeatures.ACCEPT_EMPTY_STRING_AS_NULL_OBJECT)) {
                     String str = p.getText().trim();
                     if (str.isEmpty()) {
                         return null;
diff --git a/src/main/java/com/fasterxml/jackson/databind/jsontype/impl/StdTypeResolverBuilder.java b/src/main/java/com/fasterxml/jackson/databind/jsontype/impl/StandardTypeResolverBuilder.java
similarity index 59%
rename from src/main/java/com/fasterxml/jackson/databind/jsontype/impl/StdTypeResolverBuilder.java
rename to src/main/java/com/fasterxml/jackson/databind/jsontype/impl/StandardTypeResolverBuilder.java
index 17d5ec72f..ab64eca15 100644
--- a/src/main/java/com/fasterxml/jackson/databind/jsontype/impl/StdTypeResolverBuilder.java
+++ b/src/main/java/com/fasterxml/jackson/databind/jsontype/impl/StandardTypeResolverBuilder.java
@@ -12,8 +12,8 @@ import com.fasterxml.jackson.databind.jsontype.*;
 /**
  * Default {@link TypeResolverBuilder} implementation.
  */
-public class StdTypeResolverBuilder
-    implements TypeResolverBuilder<StdTypeResolverBuilder>
+public class StandardTypeResolverBuilder
+    implements TypeResolverBuilder<StandardTypeResolverBuilder>
 {
     // Configuration settings:
 
@@ -44,59 +44,59 @@ public class StdTypeResolverBuilder
     /**********************************************************
      */
 
-    public StdTypeResolverBuilder() { }
+    public StandardTypeResolverBuilder() { }
 
     /**
      * @since 2.9
      */
-    protected StdTypeResolverBuilder(JsonTypeInfo.Id idType,
-            JsonTypeInfo.As idAs, String propName) {
-        _idType = idType;
-        _includeAs = idAs;
-        _typeProperty = propName;
+    protected StandardTypeResolverBuilder(JsonTypeInfo.Id identifierStrategy,
+                                          JsonTypeInfo.As inclusionMethod, String propertyName) {
+        _idType = identifierStrategy;
+        _includeAs = inclusionMethod;
+        _typeProperty = propertyName;
     }
 
-    public static StdTypeResolverBuilder noTypeInfoBuilder() {
-        return new StdTypeResolverBuilder().init(JsonTypeInfo.Id.NONE, null);
+    public static StandardTypeResolverBuilder noTypeInfoResolverBuilder() {
+        return new StandardTypeResolverBuilder().init(JsonTypeInfo.Id.NONE, null);
     }
 
     @Override
-    public StdTypeResolverBuilder init(JsonTypeInfo.Id idType, TypeIdResolver idRes)
+    public StandardTypeResolverBuilder init(JsonTypeInfo.Id identifierStrategy, TypeIdResolver typeIdResolver)
     {
         // sanity checks
-        if (idType == null) {
+        if (identifierStrategy == null) {
             throw new IllegalArgumentException("idType cannot be null");
         }
-        _idType = idType;
-        _customIdResolver = idRes;
+        _idType = identifierStrategy;
+        _customIdResolver = typeIdResolver;
         // Let's also initialize property name as per idType default
-        _typeProperty = idType.getDefaultPropertyName();
+        _typeProperty = identifierStrategy.getDefaultPropertyName();
         return this;
     }
 
     @Override
-    public TypeSerializer buildTypeSerializer(SerializationConfig config,
-            JavaType baseType, Collection<NamedType> subtypes)
+    public TypeSerializer buildTypeSerializer(SerializationConfig serializationSettings,
+                                              JavaType rootType, Collection<NamedType> knownVariants)
     {
         if (_idType == JsonTypeInfo.Id.NONE) { return null; }
         // 03-Oct-2016, tatu: As per [databind#1395] better prevent use for primitives,
         //    regardless of setting
-        if (baseType.isPrimitive()) {
+        if (rootType.isPrimitive()) {
             return null;
         }
-        TypeIdResolver idRes = idResolver(config, baseType, subtypes, true, false);
+        TypeIdResolver typeIdResolver = buildIdResolver(serializationSettings, rootType, knownVariants, true, false);
         switch (_includeAs) {
         case WRAPPER_ARRAY:
-            return new AsArrayTypeSerializer(idRes, null);
+            return new AsArrayTypeSerializer(typeIdResolver, null);
         case PROPERTY:
-            return new AsPropertyTypeSerializer(idRes, null, _typeProperty);
+            return new AsPropertyTypeSerializer(typeIdResolver, null, _typeProperty);
         case WRAPPER_OBJECT:
-            return new AsWrapperTypeSerializer(idRes, null);
+            return new AsWrapperTypeSerializer(typeIdResolver, null);
         case EXTERNAL_PROPERTY:
-            return new AsExternalTypeSerializer(idRes, null, _typeProperty);
+            return new AsExternalTypeSerializer(typeIdResolver, null, _typeProperty);
         case EXISTING_PROPERTY:
         	// as per [#528]
-        	return new AsExistingPropertyTypeSerializer(idRes, null, _typeProperty);
+        	return new AsExistingPropertyTypeSerializer(typeIdResolver, null, _typeProperty);
         }
         throw new IllegalStateException("Do not know how to construct standard type serializer for inclusion type: "+_includeAs);
     }
@@ -108,22 +108,22 @@ public class StdTypeResolverBuilder
     //}
 
     @Override
-    public TypeDeserializer buildTypeDeserializer(DeserializationConfig config,
-            JavaType baseType, Collection<NamedType> subtypes)
+    public TypeDeserializer buildTypeDeserializer(DeserializationConfig serializationSettings,
+                                                  JavaType rootType, Collection<NamedType> knownVariants)
     {
         if (_idType == JsonTypeInfo.Id.NONE) { return null; }
         // 03-Oct-2016, tatu: As per [databind#1395] better prevent use for primitives,
         //    regardless of setting
-        if (baseType.isPrimitive()) {
+        if (rootType.isPrimitive()) {
             return null;
         }
 
-        TypeIdResolver idRes = idResolver(config, baseType, subtypes, false, true);
+        TypeIdResolver typeIdResolver = buildIdResolver(serializationSettings, rootType, knownVariants, false, true);
 
-        JavaType defaultImpl;
+        JavaType fallbackImplementation;
 
         if (_defaultImpl == null) {
-            defaultImpl = null;
+            fallbackImplementation = null;
         } else {
             // 20-Mar-2016, tatu: It is important to do specialization go through
             //   TypeFactory to ensure proper resolution; with 2.7 and before, direct
@@ -133,14 +133,14 @@ public class StdTypeResolverBuilder
             //   seems like a reasonable compromise.
             if ((_defaultImpl == Void.class)
                      || (_defaultImpl == NoClass.class)) {
-                defaultImpl = config.getTypeFactory().constructType(_defaultImpl);
+                fallbackImplementation = serializationSettings.getTypeFactory().constructType(_defaultImpl);
             } else {
-                if (baseType.hasRawClass(_defaultImpl)) { // common enough to check
-                    defaultImpl = baseType;
-                } else if (baseType.isTypeOrSuperTypeOf(_defaultImpl)) {
+                if (rootType.hasRawClass(_defaultImpl)) { // common enough to check
+                    fallbackImplementation = rootType;
+                } else if (rootType.isTypeOrSuperTypeOf(_defaultImpl)) {
                     // most common case with proper base type...
-                    defaultImpl = config.getTypeFactory()
-                            .constructSpecializedType(baseType, _defaultImpl);
+                    fallbackImplementation = serializationSettings.getTypeFactory()
+                            .constructSpecializedType(rootType, _defaultImpl);
                 } else {
                     // 05-Apr-2018, tatu: As [databind#1565] and [databind#1861] need to allow
                     //    some cases of seemingly incompatible `defaultImpl`. Easiest to just clear
@@ -152,7 +152,7 @@ public class StdTypeResolverBuilder
                                     ClassUtil.nameOf(_defaultImpl), ClassUtil.nameOf(baseType.getRawClass()))
                             );
                             */
-                    defaultImpl = null;
+                    fallbackImplementation = null;
                 }
             }
         }
@@ -160,18 +160,18 @@ public class StdTypeResolverBuilder
         // First, method for converting type info to type id:
         switch (_includeAs) {
         case WRAPPER_ARRAY:
-            return new AsArrayTypeDeserializer(baseType, idRes,
-                    _typeProperty, _typeIdVisible, defaultImpl);
+            return new AsArrayTypeDeserializer(rootType, typeIdResolver,
+                    _typeProperty, _typeIdVisible, fallbackImplementation);
         case PROPERTY:
         case EXISTING_PROPERTY: // as per [#528] same class as PROPERTY
-            return new AsPropertyTypeDeserializer(baseType, idRes,
-                    _typeProperty, _typeIdVisible, defaultImpl, _includeAs);
+            return new AsPropertyTypeDeserializer(rootType, typeIdResolver,
+                    _typeProperty, _typeIdVisible, fallbackImplementation, _includeAs);
         case WRAPPER_OBJECT:
-            return new AsWrapperTypeDeserializer(baseType, idRes,
-                    _typeProperty, _typeIdVisible, defaultImpl);
+            return new AsWrapperTypeDeserializer(rootType, typeIdResolver,
+                    _typeProperty, _typeIdVisible, fallbackImplementation);
         case EXTERNAL_PROPERTY:
-            return new AsExternalTypeDeserializer(baseType, idRes,
-                    _typeProperty, _typeIdVisible, defaultImpl);
+            return new AsExternalTypeDeserializer(rootType, typeIdResolver,
+                    _typeProperty, _typeIdVisible, fallbackImplementation);
         }
         throw new IllegalStateException("Do not know how to construct standard type serializer for inclusion type: "+_includeAs);
     }
@@ -183,11 +183,11 @@ public class StdTypeResolverBuilder
      */
 
     @Override
-    public StdTypeResolverBuilder inclusion(JsonTypeInfo.As includeAs) {
-        if (includeAs == null) {
+    public StandardTypeResolverBuilder inclusion(JsonTypeInfo.As inclusionMethod) {
+        if (inclusionMethod == null) {
             throw new IllegalArgumentException("includeAs cannot be null");
         }
-        _includeAs = includeAs;
+        _includeAs = inclusionMethod;
         return this;
     }
 
@@ -196,24 +196,24 @@ public class StdTypeResolverBuilder
      * (property name to use for type id when using "as-property" inclusion).
      */
     @Override
-    public StdTypeResolverBuilder typeProperty(String typeIdPropName) {
+    public StandardTypeResolverBuilder typeProperty(String typePropertyName) {
         // ok to have null/empty; will restore to use defaults
-        if (typeIdPropName == null || typeIdPropName.length() == 0) {
-            typeIdPropName = _idType.getDefaultPropertyName();
+        if (typePropertyName == null || typePropertyName.length() == 0) {
+            typePropertyName = _idType.getDefaultPropertyName();
         }
-        _typeProperty = typeIdPropName;
+        _typeProperty = typePropertyName;
         return this;
     }
 
     @Override
-    public StdTypeResolverBuilder defaultImpl(Class<?> defaultImpl) {
-        _defaultImpl = defaultImpl;
+    public StandardTypeResolverBuilder defaultImpl(Class<?> fallbackImplementation) {
+        _defaultImpl = fallbackImplementation;
         return this;
     }
 
     @Override
-    public StdTypeResolverBuilder typeIdVisibility(boolean isVisible) {
-        _typeIdVisible = isVisible;
+    public StandardTypeResolverBuilder typeIdVisibility(boolean visibleFlag) {
+        _typeIdVisible = visibleFlag;
         return this;
     }
     
@@ -239,19 +239,19 @@ public class StdTypeResolverBuilder
      * type id resolver, or construct a standard resolver
      * given configuration.
      */
-    protected TypeIdResolver idResolver(MapperConfig<?> config,
-            JavaType baseType, Collection<NamedType> subtypes, boolean forSer, boolean forDeser)
+    protected TypeIdResolver buildIdResolver(MapperConfig<?> serializationSettings,
+                                             JavaType rootType, Collection<NamedType> knownVariants, boolean forSerialization, boolean forDeserialization)
     {
         // Custom id resolver?
         if (_customIdResolver != null) { return _customIdResolver; }
         if (_idType == null) throw new IllegalStateException("Cannot build, 'init()' not yet called");
         switch (_idType) {
         case CLASS:
-            return new ClassNameIdResolver(baseType, config.getTypeFactory());
+            return new ClassNameIdResolver(rootType, serializationSettings.getTypeFactory());
         case MINIMAL_CLASS:
-            return new MinimalClassNameIdResolver(baseType, config.getTypeFactory());
+            return new MinimalClassNameIdResolver(rootType, serializationSettings.getTypeFactory());
         case NAME:
-            return TypeNameIdResolver.construct(config, baseType, subtypes, forSer, forDeser);
+            return TypeNameIdResolver.construct(serializationSettings, rootType, knownVariants, forSerialization, forDeserialization);
         case NONE: // hmmh. should never get this far with 'none'
             return null;
         case CUSTOM: // need custom resolver...
diff --git a/src/main/java/com/fasterxml/jackson/databind/jsontype/impl/TypeDeserializerBase.java b/src/main/java/com/fasterxml/jackson/databind/jsontype/impl/TypeDeserializerBase.java
index 2b8e79fdf..9ea23d8ed 100644
--- a/src/main/java/com/fasterxml/jackson/databind/jsontype/impl/TypeDeserializerBase.java
+++ b/src/main/java/com/fasterxml/jackson/databind/jsontype/impl/TypeDeserializerBase.java
@@ -8,7 +8,7 @@ import com.fasterxml.jackson.annotation.JsonTypeInfo;
 import com.fasterxml.jackson.core.*;
 import com.fasterxml.jackson.databind.BeanProperty;
 import com.fasterxml.jackson.databind.DeserializationContext;
-import com.fasterxml.jackson.databind.DeserializationFeature;
+import com.fasterxml.jackson.databind.DeserializationFeatures;
 import com.fasterxml.jackson.databind.JavaType;
 import com.fasterxml.jackson.databind.JsonDeserializer;
 import com.fasterxml.jackson.databind.deser.std.NullifyingDeserializer;
@@ -205,7 +205,7 @@ public abstract class TypeDeserializerBase
          *   to do swift mapping to null
          */
         if (_defaultImpl == null) {
-            if (!ctxt.isEnabled(DeserializationFeature.FAIL_ON_INVALID_SUBTYPE)) {
+            if (!ctxt.isEnabled(DeserializationFeatures.FAIL_ON_INVALID_SUBTYPE)) {
                 return NullifyingDeserializer.instance;
             }
             return null;
diff --git a/src/main/java/com/fasterxml/jackson/databind/util/TokenBuffer.java b/src/main/java/com/fasterxml/jackson/databind/util/TokenBuffer.java
index f31334e77..3edf905dd 100644
--- a/src/main/java/com/fasterxml/jackson/databind/util/TokenBuffer.java
+++ b/src/main/java/com/fasterxml/jackson/databind/util/TokenBuffer.java
@@ -183,7 +183,7 @@ public class TokenBuffer
         _hasNativeObjectIds = p.canReadObjectId();
         _mayHaveNativeIds = _hasNativeTypeIds | _hasNativeObjectIds;
         _forceBigDecimal = (ctxt == null) ? false
-                : ctxt.isEnabled(DeserializationFeature.USE_BIG_DECIMAL_FOR_FLOATS);
+                : ctxt.isEnabled(DeserializationFeatures.USE_BIG_DECIMAL_FOR_FLOATS);
     }
 
     /**
diff --git a/src/test/java/com/fasterxml/jackson/databind/FullStreamReadTest.java b/src/test/java/com/fasterxml/jackson/databind/FullStreamReadTest.java
index 6bfa5cc94..00a5f7463 100644
--- a/src/test/java/com/fasterxml/jackson/databind/FullStreamReadTest.java
+++ b/src/test/java/com/fasterxml/jackson/databind/FullStreamReadTest.java
@@ -23,7 +23,7 @@ public class FullStreamReadTest extends BaseMapTest
 
     public void testMapperAcceptTrailing() throws Exception
     {
-        assertFalse(MAPPER.isEnabled(DeserializationFeature.FAIL_ON_TRAILING_TOKENS));
+        assertFalse(MAPPER.isEnabled(DeserializationFeatures.FAIL_ON_TRAILING_TOKENS));
 
         // by default, should be ok to read, all
         _verifyArray(MAPPER.readTree(JSON_OK_ARRAY));
@@ -40,8 +40,8 @@ public class FullStreamReadTest extends BaseMapTest
     {
         // but things change if we enforce checks
         ObjectMapper strict = newObjectMapper()
-                .enable(DeserializationFeature.FAIL_ON_TRAILING_TOKENS);
-        assertTrue(strict.isEnabled(DeserializationFeature.FAIL_ON_TRAILING_TOKENS));
+                .enable(DeserializationFeatures.FAIL_ON_TRAILING_TOKENS);
+        assertTrue(strict.isEnabled(DeserializationFeatures.FAIL_ON_TRAILING_TOKENS));
 
         // some still ok
         _verifyArray(strict.readTree(JSON_OK_ARRAY));
@@ -90,7 +90,7 @@ public class FullStreamReadTest extends BaseMapTest
     public void testReaderAcceptTrailing() throws Exception
     {
         ObjectReader R = MAPPER.reader();
-        assertFalse(R.isEnabled(DeserializationFeature.FAIL_ON_TRAILING_TOKENS));
+        assertFalse(R.isEnabled(DeserializationFeatures.FAIL_ON_TRAILING_TOKENS));
 
         _verifyArray(R.readTree(JSON_OK_ARRAY));
         _verifyArray(R.readTree(JSON_OK_ARRAY_WITH_COMMENT));
@@ -103,7 +103,7 @@ public class FullStreamReadTest extends BaseMapTest
 
     public void testReaderFailOnTrailing() throws Exception
     {
-        ObjectReader strictR = MAPPER.reader().with(DeserializationFeature.FAIL_ON_TRAILING_TOKENS);
+        ObjectReader strictR = MAPPER.reader().with(DeserializationFeatures.FAIL_ON_TRAILING_TOKENS);
         ObjectReader strictRForList = strictR.forType(List.class);
         _verifyArray(strictR.readTree(JSON_OK_ARRAY));
         _verifyCollection((List<?>)strictRForList.readValue(JSON_OK_ARRAY));
diff --git a/src/test/java/com/fasterxml/jackson/databind/ObjectMapperTest.java b/src/test/java/com/fasterxml/jackson/databind/ObjectMapperTest.java
index f59eabce6..344b08645 100644
--- a/src/test/java/com/fasterxml/jackson/databind/ObjectMapperTest.java
+++ b/src/test/java/com/fasterxml/jackson/databind/ObjectMapperTest.java
@@ -94,9 +94,9 @@ public class ObjectMapperTest extends BaseMapTest
     public void testCopy() throws Exception
     {
         ObjectMapper m = new ObjectMapper();
-        assertTrue(m.isEnabled(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES));
-        m.disable(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES);
-        assertFalse(m.isEnabled(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES));
+        assertTrue(m.isEnabled(DeserializationFeatures.FAIL_ON_UNKNOWN_PROPERTIES));
+        m.disable(DeserializationFeatures.FAIL_ON_UNKNOWN_PROPERTIES);
+        assertFalse(m.isEnabled(DeserializationFeatures.FAIL_ON_UNKNOWN_PROPERTIES));
         InjectableValues inj = new InjectableValues.Std();
         m.setInjectableValues(inj);
         assertFalse(m.isEnabled(JsonParser.Feature.ALLOW_COMMENTS));
@@ -106,20 +106,20 @@ public class ObjectMapperTest extends BaseMapTest
         // // First: verify that handling of features is decoupled:
         
         ObjectMapper m2 = m.copy();
-        assertFalse(m2.isEnabled(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES));
-        m2.enable(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES);
-        assertTrue(m2.isEnabled(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES));
+        assertFalse(m2.isEnabled(DeserializationFeatures.FAIL_ON_UNKNOWN_PROPERTIES));
+        m2.enable(DeserializationFeatures.FAIL_ON_UNKNOWN_PROPERTIES);
+        assertTrue(m2.isEnabled(DeserializationFeatures.FAIL_ON_UNKNOWN_PROPERTIES));
         assertSame(inj, m2.getInjectableValues());
 
         // but should NOT change the original
-        assertFalse(m.isEnabled(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES));
+        assertFalse(m.isEnabled(DeserializationFeatures.FAIL_ON_UNKNOWN_PROPERTIES));
 
         // nor vice versa:
-        assertFalse(m.isEnabled(DeserializationFeature.UNWRAP_ROOT_VALUE));
-        assertFalse(m2.isEnabled(DeserializationFeature.UNWRAP_ROOT_VALUE));
-        m.enable(DeserializationFeature.UNWRAP_ROOT_VALUE);
-        assertTrue(m.isEnabled(DeserializationFeature.UNWRAP_ROOT_VALUE));
-        assertFalse(m2.isEnabled(DeserializationFeature.UNWRAP_ROOT_VALUE));
+        assertFalse(m.isEnabled(DeserializationFeatures.UNWRAP_ROOT_VALUE));
+        assertFalse(m2.isEnabled(DeserializationFeatures.UNWRAP_ROOT_VALUE));
+        m.enable(DeserializationFeatures.UNWRAP_ROOT_VALUE);
+        assertTrue(m.isEnabled(DeserializationFeatures.UNWRAP_ROOT_VALUE));
+        assertFalse(m2.isEnabled(DeserializationFeatures.UNWRAP_ROOT_VALUE));
 
         // // Also, underlying JsonFactory instances should be distinct
         
diff --git a/src/test/java/com/fasterxml/jackson/databind/ObjectReaderTest.java b/src/test/java/com/fasterxml/jackson/databind/ObjectReaderTest.java
index 1d67d5578..7dc73e2b4 100644
--- a/src/test/java/com/fasterxml/jackson/databind/ObjectReaderTest.java
+++ b/src/test/java/com/fasterxml/jackson/databind/ObjectReaderTest.java
@@ -83,18 +83,18 @@ public class ObjectReaderTest extends BaseMapTest
         assertFalse(r.isEnabled(MapperFeature.ACCEPT_CASE_INSENSITIVE_PROPERTIES));
         assertFalse(r.isEnabled(JsonParser.Feature.ALLOW_COMMENTS));
         
-        r = r.withoutFeatures(DeserializationFeature.FAIL_ON_IGNORED_PROPERTIES,
-                DeserializationFeature.FAIL_ON_INVALID_SUBTYPE);
-        assertFalse(r.isEnabled(DeserializationFeature.FAIL_ON_IGNORED_PROPERTIES));
-        assertFalse(r.isEnabled(DeserializationFeature.FAIL_ON_INVALID_SUBTYPE));
-        r = r.withFeatures(DeserializationFeature.FAIL_ON_IGNORED_PROPERTIES,
-                DeserializationFeature.FAIL_ON_INVALID_SUBTYPE);
-        assertTrue(r.isEnabled(DeserializationFeature.FAIL_ON_IGNORED_PROPERTIES));
-        assertTrue(r.isEnabled(DeserializationFeature.FAIL_ON_INVALID_SUBTYPE));
+        r = r.withoutFeatures(DeserializationFeatures.FAIL_ON_IGNORED_PROPERTIES,
+                DeserializationFeatures.FAIL_ON_INVALID_SUBTYPE);
+        assertFalse(r.isEnabled(DeserializationFeatures.FAIL_ON_IGNORED_PROPERTIES));
+        assertFalse(r.isEnabled(DeserializationFeatures.FAIL_ON_INVALID_SUBTYPE));
+        r = r.withFeatures(DeserializationFeatures.FAIL_ON_IGNORED_PROPERTIES,
+                DeserializationFeatures.FAIL_ON_INVALID_SUBTYPE);
+        assertTrue(r.isEnabled(DeserializationFeatures.FAIL_ON_IGNORED_PROPERTIES));
+        assertTrue(r.isEnabled(DeserializationFeatures.FAIL_ON_INVALID_SUBTYPE));
 
         // alternative method too... can't recall why two
-        assertSame(r, r.with(DeserializationFeature.FAIL_ON_IGNORED_PROPERTIES,
-                DeserializationFeature.FAIL_ON_INVALID_SUBTYPE));
+        assertSame(r, r.with(DeserializationFeatures.FAIL_ON_IGNORED_PROPERTIES,
+                DeserializationFeatures.FAIL_ON_INVALID_SUBTYPE));
     }
 
     public void testMiscSettings() throws Exception
@@ -146,7 +146,7 @@ public class ObjectReaderTest extends BaseMapTest
     public void testNoPrefetch() throws Exception
     {
         ObjectReader r = MAPPER.reader()
-                .without(DeserializationFeature.EAGER_DESERIALIZER_FETCH);
+                .without(DeserializationFeatures.EAGER_DESERIALIZER_FETCH);
         Number n = r.forType(Integer.class).readValue("123 ");
         assertEquals(Integer.valueOf(123), n);
     }
diff --git a/src/test/java/com/fasterxml/jackson/databind/TestRootName.java b/src/test/java/com/fasterxml/jackson/databind/TestRootName.java
index 02837dac5..9d91b6d6a 100644
--- a/src/test/java/com/fasterxml/jackson/databind/TestRootName.java
+++ b/src/test/java/com/fasterxml/jackson/databind/TestRootName.java
@@ -2,8 +2,6 @@ package com.fasterxml.jackson.databind;
 
 import com.fasterxml.jackson.annotation.*;
 
-import com.fasterxml.jackson.databind.ObjectMapper;
-
 /**
  * Unit tests dealing with handling of "root element wrapping",
  * including configuration of root name to use.
@@ -67,14 +65,14 @@ public class TestRootName extends BaseMapTest
         Bean result = mapper.readValue(jsonUnwrapped, Bean.class);
         assertNotNull(result);
         try { // must not have extra wrapping
-            result = mapper.readerFor(Bean.class).with(DeserializationFeature.UNWRAP_ROOT_VALUE)
+            result = mapper.readerFor(Bean.class).with(DeserializationFeatures.UNWRAP_ROOT_VALUE)
                 .readValue(jsonUnwrapped);
             fail("Should have failed");
         } catch (JsonMappingException e) {
             verifyException(e, "Root name 'a'");
         }
         // except wrapping may be expected:
-        result = mapper.readerFor(Bean.class).with(DeserializationFeature.UNWRAP_ROOT_VALUE)
+        result = mapper.readerFor(Bean.class).with(DeserializationFeatures.UNWRAP_ROOT_VALUE)
             .readValue(jsonWrapped);
         assertNotNull(result);
     }
@@ -126,7 +124,7 @@ public class TestRootName extends BaseMapTest
     {
         ObjectMapper mapper = new ObjectMapper();
         mapper.configure(SerializationFeature.WRAP_ROOT_VALUE, true);
-        mapper.configure(DeserializationFeature.UNWRAP_ROOT_VALUE, true);
+        mapper.configure(DeserializationFeatures.UNWRAP_ROOT_VALUE, true);
         return mapper;
     }
 }
diff --git a/src/test/java/com/fasterxml/jackson/databind/cfg/DeserializationConfigTest.java b/src/test/java/com/fasterxml/jackson/databind/cfg/DeserializationConfigTest.java
index 5a78e8972..f454776c5 100644
--- a/src/test/java/com/fasterxml/jackson/databind/cfg/DeserializationConfigTest.java
+++ b/src/test/java/com/fasterxml/jackson/databind/cfg/DeserializationConfigTest.java
@@ -23,20 +23,20 @@ public class DeserializationConfigTest extends BaseMapTest
         assertTrue(cfg.isEnabled(MapperFeature.USE_GETTERS_AS_SETTERS));
         assertTrue(cfg.isEnabled(MapperFeature.CAN_OVERRIDE_ACCESS_MODIFIERS));
 
-        assertFalse(cfg.isEnabled(DeserializationFeature.USE_BIG_DECIMAL_FOR_FLOATS));
-        assertFalse(cfg.isEnabled(DeserializationFeature.USE_BIG_INTEGER_FOR_INTS));
+        assertFalse(cfg.isEnabled(DeserializationFeatures.USE_BIG_DECIMAL_FOR_FLOATS));
+        assertFalse(cfg.isEnabled(DeserializationFeatures.USE_BIG_INTEGER_FOR_INTS));
 
-        assertTrue(cfg.isEnabled(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES));
+        assertTrue(cfg.isEnabled(DeserializationFeatures.FAIL_ON_UNKNOWN_PROPERTIES));
     }
 
     public void testBasicFeatures() throws Exception
     {
         DeserializationConfig config = MAPPER.getDeserializationConfig();
-        assertTrue(config.hasDeserializationFeatures(DeserializationFeature.EAGER_DESERIALIZER_FETCH.getMask()));
-        assertFalse(config.hasDeserializationFeatures(DeserializationFeature.ACCEPT_SINGLE_VALUE_AS_ARRAY.getMask()));
-        assertTrue(config.hasSomeOfFeatures(DeserializationFeature.EAGER_DESERIALIZER_FETCH.getMask()
-                + DeserializationFeature.ACCEPT_SINGLE_VALUE_AS_ARRAY.getMask()));
-        assertFalse(config.hasSomeOfFeatures(DeserializationFeature.ACCEPT_SINGLE_VALUE_AS_ARRAY.getMask()));
+        assertTrue(config.hasDeserializationFeatures(DeserializationFeatures.EAGER_DESERIALIZER_FETCH.getMask()));
+        assertFalse(config.hasDeserializationFeatures(DeserializationFeatures.ACCEPT_SINGLE_VALUE_AS_ARRAY.getMask()));
+        assertTrue(config.hasSomeOfFeatures(DeserializationFeatures.EAGER_DESERIALIZER_FETCH.getMask()
+                + DeserializationFeatures.ACCEPT_SINGLE_VALUE_AS_ARRAY.getMask()));
+        assertFalse(config.hasSomeOfFeatures(DeserializationFeatures.ACCEPT_SINGLE_VALUE_AS_ARRAY.getMask()));
 
         // if no changes then same config object
         assertSame(config, config.without());
@@ -52,8 +52,8 @@ public class DeserializationConfigTest extends BaseMapTest
         assertSame(config, config.with(MapperFeature.ACCEPT_CASE_INSENSITIVE_PROPERTIES));
         assertNotSame(config, config.with(MapperFeature.ACCEPT_CASE_INSENSITIVE_PROPERTIES, false));
 
-        assertNotSame(config, config.with(DeserializationFeature.ACCEPT_EMPTY_ARRAY_AS_NULL_OBJECT,
-                DeserializationFeature.FAIL_ON_MISSING_CREATOR_PROPERTIES));
+        assertNotSame(config, config.with(DeserializationFeatures.ACCEPT_EMPTY_ARRAY_AS_NULL_OBJECT,
+                DeserializationFeatures.FAIL_ON_MISSING_CREATOR_PROPERTIES));
     }
 
     public void testParserFeatures() throws Exception
@@ -87,7 +87,7 @@ public class DeserializationConfigTest extends BaseMapTest
     {
         int max = 0;
         
-        for (DeserializationFeature f : DeserializationFeature.values()) {
+        for (DeserializationFeatures f : DeserializationFeatures.values()) {
             max = Math.max(max, f.ordinal());
         }
         if (max >= 31) { // 31 is actually ok; 32 not
diff --git a/src/test/java/com/fasterxml/jackson/databind/convert/NumericConversionTest.java b/src/test/java/com/fasterxml/jackson/databind/convert/NumericConversionTest.java
index 287ad4bb1..33a85e0de 100644
--- a/src/test/java/com/fasterxml/jackson/databind/convert/NumericConversionTest.java
+++ b/src/test/java/com/fasterxml/jackson/databind/convert/NumericConversionTest.java
@@ -6,7 +6,7 @@ import com.fasterxml.jackson.databind.exc.MismatchedInputException;
 public class NumericConversionTest extends BaseMapTest
 {
     private final ObjectMapper MAPPER = objectMapper();
-    private final ObjectReader R = MAPPER.reader().without(DeserializationFeature.ACCEPT_FLOAT_AS_INT);
+    private final ObjectReader R = MAPPER.reader().without(DeserializationFeatures.ACCEPT_FLOAT_AS_INT);
 
     public void testDoubleToInt() throws Exception
     {
diff --git a/src/test/java/com/fasterxml/jackson/databind/convert/TestBeanConversions.java b/src/test/java/com/fasterxml/jackson/databind/convert/TestBeanConversions.java
index ac08d94e3..c188ed578 100644
--- a/src/test/java/com/fasterxml/jackson/databind/convert/TestBeanConversions.java
+++ b/src/test/java/com/fasterxml/jackson/databind/convert/TestBeanConversions.java
@@ -164,7 +164,7 @@ public class TestBeanConversions
     public void testWrapping() throws Exception
     {
         ObjectMapper wrappingMapper = new ObjectMapper();
-        wrappingMapper.enable(DeserializationFeature.UNWRAP_ROOT_VALUE);
+        wrappingMapper.enable(DeserializationFeatures.UNWRAP_ROOT_VALUE);
         wrappingMapper.enable(SerializationFeature.WRAP_ROOT_VALUE);
 
         // conversion is ok, even if it's bogus one
@@ -173,12 +173,12 @@ public class TestBeanConversions
         // also: ok to have mismatched settings, since as per [JACKSON-710], should
         // not actually use wrapping internally in these cases
         wrappingMapper = new ObjectMapper();
-        wrappingMapper.enable(DeserializationFeature.UNWRAP_ROOT_VALUE);
+        wrappingMapper.enable(DeserializationFeatures.UNWRAP_ROOT_VALUE);
         wrappingMapper.disable(SerializationFeature.WRAP_ROOT_VALUE);
         _convertAndVerifyPoint(wrappingMapper);
 
         wrappingMapper = new ObjectMapper();
-        wrappingMapper.disable(DeserializationFeature.UNWRAP_ROOT_VALUE);
+        wrappingMapper.disable(DeserializationFeatures.UNWRAP_ROOT_VALUE);
         wrappingMapper.enable(SerializationFeature.WRAP_ROOT_VALUE);
         _convertAndVerifyPoint(wrappingMapper);
     }
diff --git a/src/test/java/com/fasterxml/jackson/databind/deser/AnySetterTest.java b/src/test/java/com/fasterxml/jackson/databind/deser/AnySetterTest.java
index 7e5dc85a9..665570ea9 100644
--- a/src/test/java/com/fasterxml/jackson/databind/deser/AnySetterTest.java
+++ b/src/test/java/com/fasterxml/jackson/databind/deser/AnySetterTest.java
@@ -274,14 +274,14 @@ public class AnySetterTest
     public void testIgnored() throws Exception
     {
         ObjectMapper mapper = new ObjectMapper();
-        mapper.enable(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES);
+        mapper.enable(DeserializationFeatures.FAIL_ON_UNKNOWN_PROPERTIES);
         _testIgnorals(mapper);
     }
 
     public void testIgnoredPart2() throws Exception
     {
         ObjectMapper mapper = new ObjectMapper();
-        mapper.disable(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES);
+        mapper.disable(DeserializationFeatures.FAIL_ON_UNKNOWN_PROPERTIES);
         _testIgnorals(mapper);
     }
 
diff --git a/src/test/java/com/fasterxml/jackson/databind/deser/IgnoreWithDeserTest.java b/src/test/java/com/fasterxml/jackson/databind/deser/IgnoreWithDeserTest.java
index e1dfa5b3d..597ed7d4b 100644
--- a/src/test/java/com/fasterxml/jackson/databind/deser/IgnoreWithDeserTest.java
+++ b/src/test/java/com/fasterxml/jackson/databind/deser/IgnoreWithDeserTest.java
@@ -64,7 +64,7 @@ public class IgnoreWithDeserTest
         assertEquals(1, result.y);
 
         // but not 'y'
-        r = r.with(DeserializationFeature.FAIL_ON_IGNORED_PROPERTIES);
+        r = r.with(DeserializationFeatures.FAIL_ON_IGNORED_PROPERTIES);
         try {
             result = r.readValue(aposToQuotes("{'x':3, 'y':4}"));
             fail("Should fail");
diff --git a/src/test/java/com/fasterxml/jackson/databind/deser/TestArrayDeserialization.java b/src/test/java/com/fasterxml/jackson/databind/deser/TestArrayDeserialization.java
index 6b506d8b6..ccc46da5c 100644
--- a/src/test/java/com/fasterxml/jackson/databind/deser/TestArrayDeserialization.java
+++ b/src/test/java/com/fasterxml/jackson/databind/deser/TestArrayDeserialization.java
@@ -189,7 +189,7 @@ public class TestArrayDeserialization
     public void testFromEmptyString() throws Exception
     {
         ObjectMapper m = new ObjectMapper();
-        m.configure(DeserializationFeature.ACCEPT_EMPTY_STRING_AS_NULL_OBJECT, true);
+        m.configure(DeserializationFeatures.ACCEPT_EMPTY_STRING_AS_NULL_OBJECT, true);
         assertNull(m.readValue(quote(""), Object[].class));
         assertNull( m.readValue(quote(""), String[].class));
         assertNull( m.readValue(quote(""), int[].class));
@@ -199,8 +199,8 @@ public class TestArrayDeserialization
     public void testFromEmptyString2() throws Exception
     {
         ObjectMapper m = new ObjectMapper();
-        m.configure(DeserializationFeature.ACCEPT_EMPTY_STRING_AS_NULL_OBJECT, true);
-        m.configure(DeserializationFeature.ACCEPT_SINGLE_VALUE_AS_ARRAY, true);
+        m.configure(DeserializationFeatures.ACCEPT_EMPTY_STRING_AS_NULL_OBJECT, true);
+        m.configure(DeserializationFeatures.ACCEPT_SINGLE_VALUE_AS_ARRAY, true);
         Product p = m.readValue("{\"thelist\":\"\"}", Product.class);
         assertNotNull(p);
         assertNull(p.thelist);
diff --git a/src/test/java/com/fasterxml/jackson/databind/deser/TestBeanDeserializer.java b/src/test/java/com/fasterxml/jackson/databind/deser/TestBeanDeserializer.java
index 988ece38d..5f44abcb5 100644
--- a/src/test/java/com/fasterxml/jackson/databind/deser/TestBeanDeserializer.java
+++ b/src/test/java/com/fasterxml/jackson/databind/deser/TestBeanDeserializer.java
@@ -373,7 +373,7 @@ public class TestBeanDeserializer extends BaseMapTest
     public void testPOJOFromEmptyString() throws Exception
     {
         // first, verify default settings which do not accept empty String:
-        assertFalse(MAPPER.isEnabled(DeserializationFeature.ACCEPT_EMPTY_STRING_AS_NULL_OBJECT));
+        assertFalse(MAPPER.isEnabled(DeserializationFeatures.ACCEPT_EMPTY_STRING_AS_NULL_OBJECT));
         try {
             MAPPER.readValue(quote(""), Bean.class);
             fail("Should not accept Empty String for POJO");
@@ -383,7 +383,7 @@ public class TestBeanDeserializer extends BaseMapTest
         }
         // should be ok to enable dynamically
         ObjectReader r = MAPPER.readerFor(Bean.class)
-                .with(DeserializationFeature.ACCEPT_EMPTY_STRING_AS_NULL_OBJECT);
+                .with(DeserializationFeatures.ACCEPT_EMPTY_STRING_AS_NULL_OBJECT);
         Bean result = r.readValue(quote(""));
         assertNull(result);
     }
diff --git a/src/test/java/com/fasterxml/jackson/databind/deser/TestGenerics.java b/src/test/java/com/fasterxml/jackson/databind/deser/TestGenerics.java
index 967a6e7ef..ee26e0976 100644
--- a/src/test/java/com/fasterxml/jackson/databind/deser/TestGenerics.java
+++ b/src/test/java/com/fasterxml/jackson/databind/deser/TestGenerics.java
@@ -80,7 +80,7 @@ public class TestGenerics
     public void testGenericWrapperWithSingleElementArray() throws Exception
     {
         ObjectMapper mapper = new ObjectMapper();
-        mapper.enable(DeserializationFeature.UNWRAP_SINGLE_VALUE_ARRAYS);
+        mapper.enable(DeserializationFeatures.UNWRAP_SINGLE_VALUE_ARRAYS);
         
         Wrapper<SimpleBean> result = mapper.readValue
             ("[{\"value\": [{ \"x\" : 13 }] }]",
@@ -123,7 +123,7 @@ public class TestGenerics
     public void testMultipleWrappersSingleValueArray() throws Exception
     {
         ObjectMapper mapper = new ObjectMapper();
-        mapper.enable(DeserializationFeature.UNWRAP_SINGLE_VALUE_ARRAYS);
+        mapper.enable(DeserializationFeatures.UNWRAP_SINGLE_VALUE_ARRAYS);
 
         // First, numeric wrapper
         Wrapper<Boolean> result = mapper.readValue
@@ -165,7 +165,7 @@ public class TestGenerics
     public void testArrayOfGenericWrappersSingleValueArray() throws Exception
     {
         ObjectMapper mapper = new ObjectMapper();
-        mapper.enable(DeserializationFeature.UNWRAP_SINGLE_VALUE_ARRAYS);
+        mapper.enable(DeserializationFeatures.UNWRAP_SINGLE_VALUE_ARRAYS);
         
         Wrapper<SimpleBean>[] result = mapper.readValue
             ("[ {\"value\": [ { \"x\" : [ 9 ] } ] } ]",
diff --git a/src/test/java/com/fasterxml/jackson/databind/deser/TestTimestampDeserialization.java b/src/test/java/com/fasterxml/jackson/databind/deser/TestTimestampDeserialization.java
index 295cdad80..607cf83e9 100644
--- a/src/test/java/com/fasterxml/jackson/databind/deser/TestTimestampDeserialization.java
+++ b/src/test/java/com/fasterxml/jackson/databind/deser/TestTimestampDeserialization.java
@@ -29,7 +29,7 @@ public class TestTimestampDeserialization
     public void testTimestampUtilSingleElementArray() throws Exception
     {
         final ObjectMapper mapper = new ObjectMapper();
-        mapper.enable(DeserializationFeature.UNWRAP_SINGLE_VALUE_ARRAYS);
+        mapper.enable(DeserializationFeatures.UNWRAP_SINGLE_VALUE_ARRAYS);
         
         long now = System.currentTimeMillis();
         java.sql.Timestamp value = new java.sql.Timestamp(now);
diff --git a/src/test/java/com/fasterxml/jackson/databind/deser/builder/BuilderErrorHandling.java b/src/test/java/com/fasterxml/jackson/databind/deser/builder/BuilderErrorHandling.java
index f7f67b0c5..db57ed981 100644
--- a/src/test/java/com/fasterxml/jackson/databind/deser/builder/BuilderErrorHandling.java
+++ b/src/test/java/com/fasterxml/jackson/databind/deser/builder/BuilderErrorHandling.java
@@ -1,7 +1,7 @@
 package com.fasterxml.jackson.databind.deser.builder;
 
 import com.fasterxml.jackson.databind.BaseMapTest;
-import com.fasterxml.jackson.databind.DeserializationFeature;
+import com.fasterxml.jackson.databind.DeserializationFeatures;
 import com.fasterxml.jackson.databind.ObjectMapper;
 import com.fasterxml.jackson.databind.annotation.JsonDeserialize;
 import com.fasterxml.jackson.databind.exc.MismatchedInputException;
@@ -58,7 +58,7 @@ public class BuilderErrorHandling extends BaseMapTest
         }
         // but pass if ok to ignore
         ValueClassXY result = MAPPER.readerFor(ValueClassXY.class)
-                .without(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES)
+                .without(DeserializationFeatures.FAIL_ON_UNKNOWN_PROPERTIES)
                 .readValue(json);
         assertEquals(2, result._x);
         assertEquals(5, result._y);
diff --git a/src/test/java/com/fasterxml/jackson/databind/deser/creators/FailOnNullCreatorTest.java b/src/test/java/com/fasterxml/jackson/databind/deser/creators/FailOnNullCreatorTest.java
index a767bdadb..cf638d3a5 100644
--- a/src/test/java/com/fasterxml/jackson/databind/deser/creators/FailOnNullCreatorTest.java
+++ b/src/test/java/com/fasterxml/jackson/databind/deser/creators/FailOnNullCreatorTest.java
@@ -34,7 +34,7 @@ public class FailOnNullCreatorTest extends BaseMapTest
         assertEquals(Integer.valueOf(0), p.age);
 
         // Second: fine if feature is enabled but default value is not null
-        ObjectReader r = POINT_READER.with(DeserializationFeature.FAIL_ON_NULL_CREATOR_PROPERTIES);
+        ObjectReader r = POINT_READER.with(DeserializationFeatures.FAIL_ON_NULL_CREATOR_PROPERTIES);
         p = POINT_READER.readValue(aposToQuotes("{'name':'John', 'age': null}"));
         assertEquals("John", p.name);
         assertEquals(Integer.valueOf(0), p.age);
diff --git a/src/test/java/com/fasterxml/jackson/databind/deser/creators/RequiredCreatorTest.java b/src/test/java/com/fasterxml/jackson/databind/deser/creators/RequiredCreatorTest.java
index 66bd9675c..b35daa363 100644
--- a/src/test/java/com/fasterxml/jackson/databind/deser/creators/RequiredCreatorTest.java
+++ b/src/test/java/com/fasterxml/jackson/databind/deser/creators/RequiredCreatorTest.java
@@ -56,7 +56,7 @@ public class RequiredCreatorTest extends BaseMapTest
         assertEquals(0, p.y);
 
         // but not if global checks desired
-        ObjectReader r = POINT_READER.with(DeserializationFeature.FAIL_ON_MISSING_CREATOR_PROPERTIES);
+        ObjectReader r = POINT_READER.with(DeserializationFeatures.FAIL_ON_MISSING_CREATOR_PROPERTIES);
         try {
             r.readValue(aposToQuotes("{'x':6}"));
             fail("Should not pass");
diff --git a/src/test/java/com/fasterxml/jackson/databind/deser/creators/TestCreators3.java b/src/test/java/com/fasterxml/jackson/databind/deser/creators/TestCreators3.java
index d00030cb9..3ce93614a 100644
--- a/src/test/java/com/fasterxml/jackson/databind/deser/creators/TestCreators3.java
+++ b/src/test/java/com/fasterxml/jackson/databind/deser/creators/TestCreators3.java
@@ -144,7 +144,7 @@ public class TestCreators3 extends BaseMapTest
                 MapperFeature.AUTO_DETECT_SETTERS,
                 MapperFeature.USE_GETTERS_AS_SETTERS
         );
-        mapper.disable(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES);
+        mapper.disable(DeserializationFeatures.FAIL_ON_UNKNOWN_PROPERTIES);
         mapper.disable(SerializationFeature.FAIL_ON_EMPTY_BEANS);
         mapper.setSerializationInclusion(JsonInclude.Include.NON_NULL);  
 
diff --git a/src/test/java/com/fasterxml/jackson/databind/deser/filter/NullConversionsGenericTest.java b/src/test/java/com/fasterxml/jackson/databind/deser/filter/NullConversionsGenericTest.java
index 87df5f910..1630aaf64 100644
--- a/src/test/java/com/fasterxml/jackson/databind/deser/filter/NullConversionsGenericTest.java
+++ b/src/test/java/com/fasterxml/jackson/databind/deser/filter/NullConversionsGenericTest.java
@@ -64,7 +64,7 @@ public class NullConversionsGenericTest extends BaseMapTest
     public void testEmptyStringToNullToEmptyPojo() throws Exception
     {
         GeneralEmpty<Point> result = MAPPER.readerFor(new TypeReference<GeneralEmpty<Point>>() { })
-                .with(DeserializationFeature.ACCEPT_EMPTY_STRING_AS_NULL_OBJECT)
+                .with(DeserializationFeatures.ACCEPT_EMPTY_STRING_AS_NULL_OBJECT)
                 .readValue(aposToQuotes("{'value':''}"));
         assertNotNull(result.value);
         Point p = result.value;
diff --git a/src/test/java/com/fasterxml/jackson/databind/deser/filter/NullConversionsSkipTest.java b/src/test/java/com/fasterxml/jackson/databind/deser/filter/NullConversionsSkipTest.java
index 9fe93a340..be3beb7f4 100644
--- a/src/test/java/com/fasterxml/jackson/databind/deser/filter/NullConversionsSkipTest.java
+++ b/src/test/java/com/fasterxml/jackson/databind/deser/filter/NullConversionsSkipTest.java
@@ -86,7 +86,7 @@ public class NullConversionsSkipTest extends BaseMapTest
     public void testEnumAsNullThenSkip() throws Exception
     {    
         Pojo2015 p = MAPPER.readerFor(Pojo2015.class)
-                .with(DeserializationFeature.READ_UNKNOWN_ENUM_VALUES_AS_NULL)
+                .with(DeserializationFeatures.READ_UNKNOWN_ENUM_VALUES_AS_NULL)
                 .readValue("{\"number\":\"THREE\"}"); 
         assertEquals(NUMS2015.TWO, p.number);
     }
diff --git a/src/test/java/com/fasterxml/jackson/databind/deser/filter/ProblemHandlerLocation1440Test.java b/src/test/java/com/fasterxml/jackson/databind/deser/filter/ProblemHandlerLocation1440Test.java
index 14464e7b4..db2dad605 100644
--- a/src/test/java/com/fasterxml/jackson/databind/deser/filter/ProblemHandlerLocation1440Test.java
+++ b/src/test/java/com/fasterxml/jackson/databind/deser/filter/ProblemHandlerLocation1440Test.java
@@ -126,7 +126,7 @@ public class ProblemHandlerLocation1440Test extends BaseMapTest
 );
 
         ObjectMapper mapper = newObjectMapper();
-        mapper.configure(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES, false);
+        mapper.configure(DeserializationFeatures.FAIL_ON_UNKNOWN_PROPERTIES, false);
         final DeserializationProblemLogger logger = new DeserializationProblemLogger();
         mapper.addHandler(logger);
         mapper.readValue(invalidInput, Activity.class);
diff --git a/src/test/java/com/fasterxml/jackson/databind/deser/filter/TestUnknownPropertyDeserialization.java b/src/test/java/com/fasterxml/jackson/databind/deser/filter/TestUnknownPropertyDeserialization.java
index dacf4231e..fdbcac7e7 100644
--- a/src/test/java/com/fasterxml/jackson/databind/deser/filter/TestUnknownPropertyDeserialization.java
+++ b/src/test/java/com/fasterxml/jackson/databind/deser/filter/TestUnknownPropertyDeserialization.java
@@ -178,7 +178,7 @@ public class TestUnknownPropertyDeserialization
     public void testUnknownHandlingIgnoreWithFeature() throws Exception
     {
         ObjectMapper mapper = newObjectMapper();
-        mapper.configure(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES, false);
+        mapper.configure(DeserializationFeatures.FAIL_ON_UNKNOWN_PROPERTIES, false);
         TestBean result = null;
         try {
             result = mapper.readValue(new StringReader(JSON_UNKNOWN_FIELD), TestBean.class);
diff --git a/src/test/java/com/fasterxml/jackson/databind/deser/jdk/CollectionDeserTest.java b/src/test/java/com/fasterxml/jackson/databind/deser/jdk/CollectionDeserTest.java
index 92e461330..719ba53b9 100644
--- a/src/test/java/com/fasterxml/jackson/databind/deser/jdk/CollectionDeserTest.java
+++ b/src/test/java/com/fasterxml/jackson/databind/deser/jdk/CollectionDeserTest.java
@@ -140,7 +140,7 @@ public class CollectionDeserTest
     {
         // can't share mapper, custom configs (could create ObjectWriter tho)
         ObjectMapper mapper = new ObjectMapper();
-        mapper.configure(DeserializationFeature.ACCEPT_SINGLE_VALUE_AS_ARRAY, true);
+        mapper.configure(DeserializationFeatures.ACCEPT_SINGLE_VALUE_AS_ARRAY, true);
 
         // first with simple scalar types (numbers), with collections
         List<Integer> ints = mapper.readValue("4", List.class);
@@ -171,7 +171,7 @@ public class CollectionDeserTest
     // [JACKSON-620]: allow "" to mean 'null' for Maps
     public void testFromEmptyString() throws Exception
     {
-        ObjectReader r = MAPPER.reader(DeserializationFeature.ACCEPT_EMPTY_STRING_AS_NULL_OBJECT);
+        ObjectReader r = MAPPER.reader(DeserializationFeatures.ACCEPT_EMPTY_STRING_AS_NULL_OBJECT);
         List<?> result = r.forType(List.class).readValue(quote(""));
         assertNull(result);
     }
@@ -263,7 +263,7 @@ public class CollectionDeserTest
     public void testWrapExceptions() throws Exception
     {
         ObjectMapper mapper = new ObjectMapper();
-        mapper.enable(DeserializationFeature.WRAP_EXCEPTIONS);
+        mapper.enable(DeserializationFeatures.WRAP_EXCEPTIONS);
 
         try {
             mapper.readValue("[{}]", new TypeReference<List<SomeObject>>() {});
@@ -274,7 +274,7 @@ public class CollectionDeserTest
         }
 
         ObjectMapper mapperNoWrap = new ObjectMapper();
-        mapperNoWrap.disable(DeserializationFeature.WRAP_EXCEPTIONS);
+        mapperNoWrap.disable(DeserializationFeatures.WRAP_EXCEPTIONS);
 
         try {
             mapperNoWrap.readValue("[{}]", new TypeReference<List<SomeObject>>() {});
diff --git a/src/test/java/com/fasterxml/jackson/databind/deser/jdk/DateDeserializationTest.java b/src/test/java/com/fasterxml/jackson/databind/deser/jdk/DateDeserializationTest.java
index 5ec830eb2..8dbcb18bd 100644
--- a/src/test/java/com/fasterxml/jackson/databind/deser/jdk/DateDeserializationTest.java
+++ b/src/test/java/com/fasterxml/jackson/databind/deser/jdk/DateDeserializationTest.java
@@ -649,7 +649,7 @@ public class DateDeserializationTest
         final String tzId = "PST";
 
         // this is enabled by default:
-        assertTrue(MAPPER.isEnabled(DeserializationFeature.ADJUST_DATES_TO_CONTEXT_TIME_ZONE));
+        assertTrue(MAPPER.isEnabled(DeserializationFeatures.ADJUST_DATES_TO_CONTEXT_TIME_ZONE));
         final ObjectReader r = MAPPER
                 .readerFor(Calendar.class)
                 .with(TimeZone.getTimeZone(tzId));
@@ -669,7 +669,7 @@ public class DateDeserializationTest
         assertEquals(11, cal.get(Calendar.HOUR_OF_DAY));
 
         // but if disabled, should use what's been sent in:
-        cal = r.without(DeserializationFeature.ADJUST_DATES_TO_CONTEXT_TIME_ZONE)
+        cal = r.without(DeserializationFeatures.ADJUST_DATES_TO_CONTEXT_TIME_ZONE)
                 .readValue(quote(inputStr));
 
         // 23-Jun-2017, tatu: Actually turns out to be hard if not impossible to do ...
@@ -694,7 +694,7 @@ public class DateDeserializationTest
     {
         ObjectReader reader = new ObjectMapper()
                 .readerFor(CalendarBean.class)
-                .without(DeserializationFeature.UNWRAP_SINGLE_VALUE_ARRAYS);
+                .without(DeserializationFeatures.UNWRAP_SINGLE_VALUE_ARRAYS);
         final String inputDate = "1972-12-28T00:00:00.000+0000";
         final String input = aposToQuotes("{'v':['"+inputDate+"']}");
         try {
@@ -705,7 +705,7 @@ public class DateDeserializationTest
             verifyException(exp, "out of START_ARRAY");
         }
 
-        reader = reader.with(DeserializationFeature.UNWRAP_SINGLE_VALUE_ARRAYS);
+        reader = reader.with(DeserializationFeatures.UNWRAP_SINGLE_VALUE_ARRAYS);
         CalendarBean bean = reader.readValue(input);
         assertNotNull(bean._v);
         assertEquals(1972, bean._v.get(Calendar.YEAR));
diff --git a/src/test/java/com/fasterxml/jackson/databind/deser/jdk/EnumAltIdTest.java b/src/test/java/com/fasterxml/jackson/databind/deser/jdk/EnumAltIdTest.java
index 76f188243..97fd90a81 100644
--- a/src/test/java/com/fasterxml/jackson/databind/deser/jdk/EnumAltIdTest.java
+++ b/src/test/java/com/fasterxml/jackson/databind/deser/jdk/EnumAltIdTest.java
@@ -6,7 +6,7 @@ import java.util.EnumSet;
 import com.fasterxml.jackson.annotation.JsonFormat;
 import com.fasterxml.jackson.core.type.TypeReference;
 import com.fasterxml.jackson.databind.BaseMapTest;
-import com.fasterxml.jackson.databind.DeserializationFeature;
+import com.fasterxml.jackson.databind.DeserializationFeatures;
 import com.fasterxml.jackson.databind.MapperFeature;
 import com.fasterxml.jackson.databind.ObjectMapper;
 import com.fasterxml.jackson.databind.ObjectReader;
@@ -63,7 +63,7 @@ public class EnumAltIdTest extends BaseMapTest
     
     public void testFailWhenCaseSensitiveAndToStringIsUpperCase() throws IOException {
         ObjectReader r = READER_DEFAULT.forType(LowerCaseEnum.class)
-                .with(DeserializationFeature.READ_ENUMS_USING_TO_STRING);
+                .with(DeserializationFeatures.READ_ENUMS_USING_TO_STRING);
         try {
             r.readValue("\"A\"");
             fail("InvalidFormatException expected");
@@ -79,7 +79,7 @@ public class EnumAltIdTest extends BaseMapTest
 
     public void testEnumDesIgnoringCaseWithUpperCaseToString() throws IOException {
         ObjectReader r = MAPPER_IGNORE_CASE.readerFor(LowerCaseEnum.class)
-                .with(DeserializationFeature.READ_ENUMS_USING_TO_STRING);
+                .with(DeserializationFeatures.READ_ENUMS_USING_TO_STRING);
         assertEquals(LowerCaseEnum.A, r.readValue("\"A\""));
     }
 
diff --git a/src/test/java/com/fasterxml/jackson/databind/deser/jdk/EnumDefaultReadTest.java b/src/test/java/com/fasterxml/jackson/databind/deser/jdk/EnumDefaultReadTest.java
index 58392e824..4e4489157 100644
--- a/src/test/java/com/fasterxml/jackson/databind/deser/jdk/EnumDefaultReadTest.java
+++ b/src/test/java/com/fasterxml/jackson/databind/deser/jdk/EnumDefaultReadTest.java
@@ -96,7 +96,7 @@ public class EnumDefaultReadTest extends BaseMapTest
     public void testWithFailOnNumbers() throws Exception
     {
         ObjectReader r = MAPPER.reader()
-                .with(DeserializationFeature.FAIL_ON_NUMBERS_FOR_ENUMS);
+                .with(DeserializationFeatures.FAIL_ON_NUMBERS_FOR_ENUMS);
 
         _verifyOkDeserialization(r, "ZERO", SimpleEnum.class, SimpleEnum.ZERO);
         _verifyOkDeserialization(r, "ONE", SimpleEnum.class, SimpleEnum.ONE);
@@ -130,7 +130,7 @@ public class EnumDefaultReadTest extends BaseMapTest
     public void testWithReadUnknownAsDefault() throws Exception
     {
         ObjectReader r = MAPPER.reader()
-                .with(DeserializationFeature.READ_UNKNOWN_ENUM_VALUES_USING_DEFAULT_VALUE);
+                .with(DeserializationFeatures.READ_UNKNOWN_ENUM_VALUES_USING_DEFAULT_VALUE);
 
         _verifyOkDeserialization(r, "ZERO", SimpleEnum.class, SimpleEnum.ZERO);
         _verifyOkDeserialization(r, "ONE", SimpleEnum.class, SimpleEnum.ONE);
@@ -165,8 +165,8 @@ public class EnumDefaultReadTest extends BaseMapTest
         throws Exception
     {
         ObjectReader r = MAPPER.reader()
-                .with(DeserializationFeature.FAIL_ON_NUMBERS_FOR_ENUMS)
-                .with(DeserializationFeature.READ_UNKNOWN_ENUM_VALUES_USING_DEFAULT_VALUE);
+                .with(DeserializationFeatures.FAIL_ON_NUMBERS_FOR_ENUMS)
+                .with(DeserializationFeatures.READ_UNKNOWN_ENUM_VALUES_USING_DEFAULT_VALUE);
 
         _verifyOkDeserialization(r, "ZERO", SimpleEnum.class, SimpleEnum.ZERO);
         _verifyOkDeserialization(r, "ONE", SimpleEnum.class, SimpleEnum.ONE);
diff --git a/src/test/java/com/fasterxml/jackson/databind/deser/jdk/EnumDeserializationTest.java b/src/test/java/com/fasterxml/jackson/databind/deser/jdk/EnumDeserializationTest.java
index ff0a29cd1..648f212ea 100644
--- a/src/test/java/com/fasterxml/jackson/databind/deser/jdk/EnumDeserializationTest.java
+++ b/src/test/java/com/fasterxml/jackson/databind/deser/jdk/EnumDeserializationTest.java
@@ -254,7 +254,7 @@ public class EnumDeserializationTest
     {
         // can't reuse global one due to reconfig
         ObjectMapper m = new ObjectMapper();
-        m.configure(DeserializationFeature.READ_ENUMS_USING_TO_STRING, true);
+        m.configure(DeserializationFeatures.READ_ENUMS_USING_TO_STRING, true);
         LowerCaseEnum value = m.readValue("\"c\"", LowerCaseEnum.class);
         assertEquals(LowerCaseEnum.C, value);
     }
@@ -262,13 +262,13 @@ public class EnumDeserializationTest
     public void testNumbersToEnums() throws Exception
     {
         // by default numbers are fine:
-        assertFalse(MAPPER.getDeserializationConfig().isEnabled(DeserializationFeature.FAIL_ON_NUMBERS_FOR_ENUMS));
+        assertFalse(MAPPER.getDeserializationConfig().isEnabled(DeserializationFeatures.FAIL_ON_NUMBERS_FOR_ENUMS));
         TestEnum value = MAPPER.readValue("1", TestEnum.class);
         assertSame(TestEnum.RULES, value);
 
         // but can also be changed to errors:
         ObjectReader r = MAPPER.readerFor(TestEnum.class)
-                .with(DeserializationFeature.FAIL_ON_NUMBERS_FOR_ENUMS);
+                .with(DeserializationFeatures.FAIL_ON_NUMBERS_FOR_ENUMS);
         try {
             value = r.readValue("1");
             fail("Expected an error");
@@ -327,7 +327,7 @@ public class EnumDeserializationTest
     public void testAllowUnknownEnumValuesReadAsNull() throws Exception
     {
         // cannot use shared mapper when changing configs...
-        ObjectReader reader = MAPPER.reader(DeserializationFeature.READ_UNKNOWN_ENUM_VALUES_AS_NULL);
+        ObjectReader reader = MAPPER.reader(DeserializationFeatures.READ_UNKNOWN_ENUM_VALUES_AS_NULL);
         assertNull(reader.forType(TestEnum.class).readValue("\"NO-SUCH-VALUE\""));
         assertNull(reader.forType(TestEnum.class).readValue(" 4343 "));
     }
@@ -338,14 +338,14 @@ public class EnumDeserializationTest
     public void testAllowUnknownEnumValuesReadAsNullWithCreatorMethod() throws Exception
     {
         // cannot use shared mapper when changing configs...
-        ObjectReader reader = MAPPER.reader(DeserializationFeature.READ_UNKNOWN_ENUM_VALUES_AS_NULL);
+        ObjectReader reader = MAPPER.reader(DeserializationFeatures.READ_UNKNOWN_ENUM_VALUES_AS_NULL);
         assertNull(reader.forType(StrictEnumCreator.class).readValue("\"NO-SUCH-VALUE\""));
         assertNull(reader.forType(StrictEnumCreator.class).readValue(" 4343 "));
     }
 
     public void testAllowUnknownEnumValuesForEnumSets() throws Exception
     {
-        ObjectReader reader = MAPPER.reader(DeserializationFeature.READ_UNKNOWN_ENUM_VALUES_AS_NULL);
+        ObjectReader reader = MAPPER.reader(DeserializationFeatures.READ_UNKNOWN_ENUM_VALUES_AS_NULL);
         EnumSet<TestEnum> result = reader.forType(new TypeReference<EnumSet<TestEnum>>() { })
                 .readValue("[\"NO-SUCH-VALUE\"]");
         assertEquals(0, result.size());
@@ -353,7 +353,7 @@ public class EnumDeserializationTest
     
     public void testAllowUnknownEnumValuesAsMapKeysReadAsNull() throws Exception
     {
-        ObjectReader reader = MAPPER.reader(DeserializationFeature.READ_UNKNOWN_ENUM_VALUES_AS_NULL);
+        ObjectReader reader = MAPPER.reader(DeserializationFeatures.READ_UNKNOWN_ENUM_VALUES_AS_NULL);
         ClassWithEnumMapKey result = reader.forType(ClassWithEnumMapKey.class)
                 .readValue("{\"map\":{\"NO-SUCH-VALUE\":\"val\"}}");
         assertTrue(result.map.containsKey(null));
@@ -361,7 +361,7 @@ public class EnumDeserializationTest
     
     public void testDoNotAllowUnknownEnumValuesAsMapKeysWhenReadAsNullDisabled() throws Exception
     {
-        assertFalse(MAPPER.isEnabled(DeserializationFeature.READ_UNKNOWN_ENUM_VALUES_AS_NULL));
+        assertFalse(MAPPER.isEnabled(DeserializationFeatures.READ_UNKNOWN_ENUM_VALUES_AS_NULL));
          try {
              MAPPER.readValue("{\"map\":{\"NO-SUCH-VALUE\":\"val\"}}", ClassWithEnumMapKey.class);
              fail("Expected an exception for bogus enum value...");
@@ -374,7 +374,7 @@ public class EnumDeserializationTest
     public void testEnumsWithEmpty() throws Exception
     {
        final ObjectMapper mapper = new ObjectMapper();
-       mapper.configure(DeserializationFeature.ACCEPT_EMPTY_STRING_AS_NULL_OBJECT, true);
+       mapper.configure(DeserializationFeatures.ACCEPT_EMPTY_STRING_AS_NULL_OBJECT, true);
        TestEnum result = mapper.readValue("\"\"", TestEnum.class);
        assertNull(result);
     }
@@ -392,14 +392,14 @@ public class EnumDeserializationTest
     // [databind#381]
     public void testUnwrappedEnum() throws Exception {
         final ObjectMapper mapper = newObjectMapper();
-        mapper.enable(DeserializationFeature.UNWRAP_SINGLE_VALUE_ARRAYS);
+        mapper.enable(DeserializationFeatures.UNWRAP_SINGLE_VALUE_ARRAYS);
         
         assertEquals(TestEnum.JACKSON, mapper.readValue("[" + quote("JACKSON") + "]", TestEnum.class));
     }
     
     public void testUnwrappedEnumException() throws Exception {
         final ObjectMapper mapper = newObjectMapper();
-        mapper.disable(DeserializationFeature.UNWRAP_SINGLE_VALUE_ARRAYS);
+        mapper.disable(DeserializationFeatures.UNWRAP_SINGLE_VALUE_ARRAYS);
         try {
             Object v = mapper.readValue("[" + quote("JACKSON") + "]",
                     TestEnum.class);
@@ -457,20 +457,20 @@ public class EnumDeserializationTest
         assertSame(Enum1161.A, result);
 
         result = MAPPER.readerFor(Enum1161.class)
-                .with(DeserializationFeature.READ_ENUMS_USING_TO_STRING)
+                .with(DeserializationFeatures.READ_ENUMS_USING_TO_STRING)
                 .readValue(quote("a"));
         assertSame(Enum1161.A, result);
 
         // and once again, going back to defaults
         result = MAPPER.readerFor(Enum1161.class)
-                .without(DeserializationFeature.READ_ENUMS_USING_TO_STRING)
+                .without(DeserializationFeatures.READ_ENUMS_USING_TO_STRING)
                 .readValue(quote("A"));
         assertSame(Enum1161.A, result);
     }
     
     public void testEnumWithDefaultAnnotation() throws Exception {
         final ObjectMapper mapper = new ObjectMapper();
-        mapper.enable(DeserializationFeature.READ_UNKNOWN_ENUM_VALUES_USING_DEFAULT_VALUE);
+        mapper.enable(DeserializationFeatures.READ_UNKNOWN_ENUM_VALUES_USING_DEFAULT_VALUE);
 
         EnumWithDefaultAnno myEnum = mapper.readValue("\"foo\"", EnumWithDefaultAnno.class);
         assertSame(EnumWithDefaultAnno.OTHER, myEnum);
@@ -478,7 +478,7 @@ public class EnumDeserializationTest
 
     public void testEnumWithDefaultAnnotationUsingIndexInBound1() throws Exception {
         final ObjectMapper mapper = new ObjectMapper();
-        mapper.enable(DeserializationFeature.READ_UNKNOWN_ENUM_VALUES_USING_DEFAULT_VALUE);
+        mapper.enable(DeserializationFeatures.READ_UNKNOWN_ENUM_VALUES_USING_DEFAULT_VALUE);
 
         EnumWithDefaultAnno myEnum = mapper.readValue("1", EnumWithDefaultAnno.class);
         assertSame(EnumWithDefaultAnno.B, myEnum);
@@ -486,7 +486,7 @@ public class EnumDeserializationTest
 
     public void testEnumWithDefaultAnnotationUsingIndexInBound2() throws Exception {
         final ObjectMapper mapper = new ObjectMapper();
-        mapper.enable(DeserializationFeature.READ_UNKNOWN_ENUM_VALUES_USING_DEFAULT_VALUE);
+        mapper.enable(DeserializationFeatures.READ_UNKNOWN_ENUM_VALUES_USING_DEFAULT_VALUE);
 
         EnumWithDefaultAnno myEnum = mapper.readValue("2", EnumWithDefaultAnno.class);
         assertSame(EnumWithDefaultAnno.OTHER, myEnum);
@@ -494,7 +494,7 @@ public class EnumDeserializationTest
 
     public void testEnumWithDefaultAnnotationUsingIndexSameAsLength() throws Exception {
         final ObjectMapper mapper = new ObjectMapper();
-        mapper.enable(DeserializationFeature.READ_UNKNOWN_ENUM_VALUES_USING_DEFAULT_VALUE);
+        mapper.enable(DeserializationFeatures.READ_UNKNOWN_ENUM_VALUES_USING_DEFAULT_VALUE);
 
         EnumWithDefaultAnno myEnum = mapper.readValue("3", EnumWithDefaultAnno.class);
         assertSame(EnumWithDefaultAnno.OTHER, myEnum);
@@ -502,7 +502,7 @@ public class EnumDeserializationTest
 
     public void testEnumWithDefaultAnnotationUsingIndexOutOfBound() throws Exception {
         final ObjectMapper mapper = new ObjectMapper();
-        mapper.enable(DeserializationFeature.READ_UNKNOWN_ENUM_VALUES_USING_DEFAULT_VALUE);
+        mapper.enable(DeserializationFeatures.READ_UNKNOWN_ENUM_VALUES_USING_DEFAULT_VALUE);
 
         EnumWithDefaultAnno myEnum = mapper.readValue("4", EnumWithDefaultAnno.class);
         assertSame(EnumWithDefaultAnno.OTHER, myEnum);
@@ -510,7 +510,7 @@ public class EnumDeserializationTest
 
     public void testEnumWithDefaultAnnotationWithConstructor() throws Exception {
         final ObjectMapper mapper = new ObjectMapper();
-        mapper.enable(DeserializationFeature.READ_UNKNOWN_ENUM_VALUES_USING_DEFAULT_VALUE);
+        mapper.enable(DeserializationFeatures.READ_UNKNOWN_ENUM_VALUES_USING_DEFAULT_VALUE);
 
         EnumWithDefaultAnnoAndConstructor myEnum = mapper.readValue("\"foo\"", EnumWithDefaultAnnoAndConstructor.class);
         assertNull("When using a constructor, the default value annotation shouldn't be used.", myEnum);
diff --git a/src/test/java/com/fasterxml/jackson/databind/deser/jdk/EnumMapDeserializationTest.java b/src/test/java/com/fasterxml/jackson/databind/deser/jdk/EnumMapDeserializationTest.java
index bf30d14e3..e06275278 100644
--- a/src/test/java/com/fasterxml/jackson/databind/deser/jdk/EnumMapDeserializationTest.java
+++ b/src/test/java/com/fasterxml/jackson/databind/deser/jdk/EnumMapDeserializationTest.java
@@ -94,7 +94,7 @@ public class EnumMapDeserializationTest extends BaseMapTest
     {
         // can't reuse global one due to reconfig
         ObjectReader r = MAPPER.reader()
-                .with(DeserializationFeature.READ_ENUMS_USING_TO_STRING);
+                .with(DeserializationFeatures.READ_ENUMS_USING_TO_STRING);
         EnumMap<LowerCaseEnum,String> value = r.forType(
             new TypeReference<EnumMap<LowerCaseEnum,String>>() { })
                 .readValue("{\"a\":\"value\"}");
@@ -187,14 +187,14 @@ public class EnumMapDeserializationTest extends BaseMapTest
         // first, via EnumMap
         EnumMap<TestEnumWithDefault,String> value = MAPPER
                 .readerFor(new TypeReference<EnumMap<TestEnumWithDefault,String>>() { })
-                .with(DeserializationFeature.READ_UNKNOWN_ENUM_VALUES_USING_DEFAULT_VALUE)
+                .with(DeserializationFeatures.READ_UNKNOWN_ENUM_VALUES_USING_DEFAULT_VALUE)
                 .readValue("{\"unknown\":\"value\"}");
         assertEquals(1, value.size());
         assertEquals("value", value.get(TestEnumWithDefault.OK));
 
         Map<TestEnumWithDefault,String> value2 = MAPPER
                 .readerFor(new TypeReference<Map<TestEnumWithDefault,String>>() { })
-                .with(DeserializationFeature.READ_UNKNOWN_ENUM_VALUES_USING_DEFAULT_VALUE)
+                .with(DeserializationFeatures.READ_UNKNOWN_ENUM_VALUES_USING_DEFAULT_VALUE)
                 .readValue("{\"unknown\":\"value\"}");
         assertEquals(1, value2.size());
         assertEquals("value", value2.get(TestEnumWithDefault.OK));
@@ -206,14 +206,14 @@ public class EnumMapDeserializationTest extends BaseMapTest
         // first, via EnumMap
         EnumMap<TestEnumWithDefault,String> value = MAPPER
                 .readerFor(new TypeReference<EnumMap<TestEnumWithDefault,String>>() { })
-                .with(DeserializationFeature.READ_UNKNOWN_ENUM_VALUES_AS_NULL)
+                .with(DeserializationFeatures.READ_UNKNOWN_ENUM_VALUES_AS_NULL)
                 .readValue("{\"unknown\":\"value\"}");
         assertEquals(0, value.size());
 
         // then regular Map
         Map<TestEnumWithDefault,String> value2 = MAPPER
                 .readerFor(new TypeReference<Map<TestEnumWithDefault,String>>() { })
-                .with(DeserializationFeature.READ_UNKNOWN_ENUM_VALUES_AS_NULL)
+                .with(DeserializationFeatures.READ_UNKNOWN_ENUM_VALUES_AS_NULL)
                 .readValue("{\"unknown\":\"value\"}");
         // 04-Jan-2017, tatu: Not sure if this is weird or not, but since `null`s are typically
         //    ok for "regular" JDK Maps...
diff --git a/src/test/java/com/fasterxml/jackson/databind/deser/jdk/JDKNumberDeserTest.java b/src/test/java/com/fasterxml/jackson/databind/deser/jdk/JDKNumberDeserTest.java
index 2fc0b1c43..22439356b 100644
--- a/src/test/java/com/fasterxml/jackson/databind/deser/jdk/JDKNumberDeserTest.java
+++ b/src/test/java/com/fasterxml/jackson/databind/deser/jdk/JDKNumberDeserTest.java
@@ -124,7 +124,7 @@ public class JDKNumberDeserTest extends BaseMapTest
 
         // Also: verify failure for at least some
         try {
-            MAPPER.readerFor(Integer.TYPE).with(DeserializationFeature.FAIL_ON_NULL_FOR_PRIMITIVES)
+            MAPPER.readerFor(Integer.TYPE).with(DeserializationFeatures.FAIL_ON_NULL_FOR_PRIMITIVES)
                 .readValue(NULL_JSON);
             fail("Should not have passed");
         } catch (MismatchedInputException e) {
@@ -211,7 +211,7 @@ public class JDKNumberDeserTest extends BaseMapTest
         /* Slight twist; as per [JACKSON-100], can also request binding
          * to BigInteger even if value would fit in Integer
          */
-        ObjectReader r = MAPPER.reader(DeserializationFeature.USE_BIG_INTEGER_FOR_INTS);
+        ObjectReader r = MAPPER.reader(DeserializationFeatures.USE_BIG_INTEGER_FOR_INTS);
 
         BigInteger exp = BigInteger.valueOf(123L);
 
@@ -239,7 +239,7 @@ public class JDKNumberDeserTest extends BaseMapTest
 
     public void testFpTypeOverrideSimple() throws Exception
     {
-        ObjectReader r = MAPPER.reader(DeserializationFeature.USE_BIG_DECIMAL_FOR_FLOATS);
+        ObjectReader r = MAPPER.reader(DeserializationFeatures.USE_BIG_DECIMAL_FOR_FLOATS);
         BigDecimal dec = new BigDecimal("0.1");
 
         // First test generic stand-alone Number
@@ -259,7 +259,7 @@ public class JDKNumberDeserTest extends BaseMapTest
 
     public void testFpTypeOverrideStructured() throws Exception
     {
-        ObjectReader r = MAPPER.reader(DeserializationFeature.USE_BIG_DECIMAL_FOR_FLOATS);
+        ObjectReader r = MAPPER.reader(DeserializationFeatures.USE_BIG_DECIMAL_FOR_FLOATS);
 
         BigDecimal dec = new BigDecimal("-19.37");
         // List element types
@@ -281,7 +281,7 @@ public class JDKNumberDeserTest extends BaseMapTest
     // [databind#504]
     public void testForceIntsToLongs() throws Exception
     {
-        ObjectReader r = MAPPER.reader(DeserializationFeature.USE_LONG_FOR_INTS);
+        ObjectReader r = MAPPER.reader(DeserializationFeatures.USE_LONG_FOR_INTS);
 
         Object ob = r.forType(Object.class).readValue("42");
         assertEquals(Long.class, ob.getClass());
diff --git a/src/test/java/com/fasterxml/jackson/databind/deser/jdk/JDKScalarsTest.java b/src/test/java/com/fasterxml/jackson/databind/deser/jdk/JDKScalarsTest.java
index 66d9951d6..0dea9c708 100644
--- a/src/test/java/com/fasterxml/jackson/databind/deser/jdk/JDKScalarsTest.java
+++ b/src/test/java/com/fasterxml/jackson/databind/deser/jdk/JDKScalarsTest.java
@@ -222,7 +222,7 @@ public class JDKScalarsTest
         assertNull(wrapper.getV());
         
         final ObjectMapper mapper = new ObjectMapper();
-        mapper.enable(DeserializationFeature.FAIL_ON_NULL_FOR_PRIMITIVES);
+        mapper.enable(DeserializationFeatures.FAIL_ON_NULL_FOR_PRIMITIVES);
         try {
             mapper.readValue("{\"v\":null}", CharacterBean.class);
             fail("Attempting to deserialize a 'null' JSON reference into a 'char' property did not throw an exception");
@@ -231,7 +231,7 @@ public class JDKScalarsTest
             //Exception thrown as required
         }
 
-        mapper.disable(DeserializationFeature.FAIL_ON_NULL_FOR_PRIMITIVES);  
+        mapper.disable(DeserializationFeatures.FAIL_ON_NULL_FOR_PRIMITIVES);
         final CharacterBean charBean = MAPPER.readValue("{\"v\":null}", CharacterBean.class);
         assertNotNull(wrapper);
         assertEquals('\u0000', charBean.getV());
@@ -268,7 +268,7 @@ public class JDKScalarsTest
         
         // [databind#381]
         final ObjectMapper mapper = new ObjectMapper();
-        mapper.disable(DeserializationFeature.UNWRAP_SINGLE_VALUE_ARRAYS);
+        mapper.disable(DeserializationFeatures.UNWRAP_SINGLE_VALUE_ARRAYS);
         try {
             mapper.readValue("{\"v\":[3]}", IntBean.class);
             fail("Did not throw exception when reading a value from a single value array with the UNWRAP_SINGLE_VALUE_ARRAYS feature disabled");
@@ -276,7 +276,7 @@ public class JDKScalarsTest
             //Correctly threw exception
         }
         
-        mapper.enable(DeserializationFeature.UNWRAP_SINGLE_VALUE_ARRAYS);
+        mapper.enable(DeserializationFeatures.UNWRAP_SINGLE_VALUE_ARRAYS);
         
         result = mapper.readValue("{\"v\":[3]}", IntBean.class);
         assertEquals(3, result._v);
@@ -331,7 +331,7 @@ public class JDKScalarsTest
         
         // [databind#381]
         final ObjectMapper mapper = new ObjectMapper();
-        mapper.disable(DeserializationFeature.UNWRAP_SINGLE_VALUE_ARRAYS);
+        mapper.disable(DeserializationFeatures.UNWRAP_SINGLE_VALUE_ARRAYS);
         try {
             mapper.readValue("{\"v\":[3]}", LongBean.class);
             fail("Did not throw exception when reading a value from a single value array with the UNWRAP_SINGLE_VALUE_ARRAYS feature disabled");
@@ -339,7 +339,7 @@ public class JDKScalarsTest
             //Correctly threw exception
         }
         
-        mapper.enable(DeserializationFeature.UNWRAP_SINGLE_VALUE_ARRAYS);
+        mapper.enable(DeserializationFeatures.UNWRAP_SINGLE_VALUE_ARRAYS);
         
         result = mapper.readValue("{\"v\":[3]}", LongBean.class);
         assertEquals(3, result._v);
@@ -452,7 +452,7 @@ public class JDKScalarsTest
     public void testDoubleAsArray() throws Exception
     {
         final ObjectMapper mapper = new ObjectMapper();
-        mapper.disable(DeserializationFeature.UNWRAP_SINGLE_VALUE_ARRAYS);
+        mapper.disable(DeserializationFeatures.UNWRAP_SINGLE_VALUE_ARRAYS);
         final double value = 0.016;
         try {
             mapper.readValue("{\"v\":[" + value + "]}", DoubleBean.class);
@@ -461,7 +461,7 @@ public class JDKScalarsTest
             //Correctly threw exception
         }
         
-        mapper.enable(DeserializationFeature.UNWRAP_SINGLE_VALUE_ARRAYS);
+        mapper.enable(DeserializationFeatures.UNWRAP_SINGLE_VALUE_ARRAYS);
         
         DoubleBean result = mapper.readValue("{\"v\":[" + value + "]}",
                 DoubleBean.class);
@@ -538,7 +538,7 @@ public class JDKScalarsTest
         ObjectReader intR = MAPPER.readerFor(primType);
         assertEquals(emptyValue, intR.readValue(EMPTY));
         try {
-            intR.with(DeserializationFeature.FAIL_ON_NULL_FOR_PRIMITIVES)
+            intR.with(DeserializationFeatures.FAIL_ON_NULL_FOR_PRIMITIVES)
                 .readValue("\"\"");
             fail("Should not have passed");
         } catch (JsonMappingException e) {
@@ -657,7 +657,7 @@ public class JDKScalarsTest
     {
         final ObjectReader reader = MAPPER
                 .readerFor(PrimitivesBean.class)
-                .with(DeserializationFeature.FAIL_ON_NULL_FOR_PRIMITIVES);
+                .with(DeserializationFeatures.FAIL_ON_NULL_FOR_PRIMITIVES);
         try {
             reader.readValue(aposToQuotes("{'"+propName+"':''}"));
             fail("Expected failure for boolean + empty String");
@@ -707,7 +707,7 @@ public class JDKScalarsTest
         // but not when enabled
         final ObjectReader reader = MAPPER
                 .readerFor(PrimitivesBean.class)
-                .with(DeserializationFeature.FAIL_ON_NULL_FOR_PRIMITIVES);
+                .with(DeserializationFeatures.FAIL_ON_NULL_FOR_PRIMITIVES);
         // boolean
         try {
             reader.readValue("{\"booleanValue\":null}");
@@ -786,7 +786,7 @@ public class JDKScalarsTest
         final String SIMPLE_NAME = "`"+cls.getSimpleName()+"`";
         final ObjectReader readerCoerceOk = MAPPER.readerFor(cls);
         final ObjectReader readerNoCoerce = readerCoerceOk
-                .with(DeserializationFeature.FAIL_ON_NULL_FOR_PRIMITIVES);
+                .with(DeserializationFeatures.FAIL_ON_NULL_FOR_PRIMITIVES);
 
         Object ob = readerCoerceOk.forType(cls).readValue(JSON_WITH_NULL);
         assertEquals(1, Array.getLength(ob));
diff --git a/src/test/java/com/fasterxml/jackson/databind/deser/jdk/JDKStringLikeTypesTest.java b/src/test/java/com/fasterxml/jackson/databind/deser/jdk/JDKStringLikeTypesTest.java
index 7f65dd35e..2334c0807 100644
--- a/src/test/java/com/fasterxml/jackson/databind/deser/jdk/JDKStringLikeTypesTest.java
+++ b/src/test/java/com/fasterxml/jackson/databind/deser/jdk/JDKStringLikeTypesTest.java
@@ -316,7 +316,7 @@ public class JDKStringLikeTypesTest extends BaseMapTest
                 "00000007-0000-0000-0000-000000000000"
         }) {
             
-            mapper.disable(DeserializationFeature.UNWRAP_SINGLE_VALUE_ARRAYS);
+            mapper.disable(DeserializationFeatures.UNWRAP_SINGLE_VALUE_ARRAYS);
             
             UUID uuid = UUID.fromString(value);
             assertEquals(uuid,
diff --git a/src/test/java/com/fasterxml/jackson/databind/deser/jdk/MapDeserializationTest.java b/src/test/java/com/fasterxml/jackson/databind/deser/jdk/MapDeserializationTest.java
index 852f3898e..022ba50d8 100644
--- a/src/test/java/com/fasterxml/jackson/databind/deser/jdk/MapDeserializationTest.java
+++ b/src/test/java/com/fasterxml/jackson/databind/deser/jdk/MapDeserializationTest.java
@@ -186,7 +186,7 @@ public class MapDeserializationTest
     public void testFromEmptyString() throws Exception
     {
         ObjectMapper m = new ObjectMapper();
-        m.configure(DeserializationFeature.ACCEPT_EMPTY_STRING_AS_NULL_OBJECT, true);
+        m.configure(DeserializationFeatures.ACCEPT_EMPTY_STRING_AS_NULL_OBJECT, true);
         Map<?,?> result = m.readValue(quote(""), Map.class);
         assertNull(result);
     }
diff --git a/src/test/java/com/fasterxml/jackson/databind/deser/jdk/UntypedDeserializationTest.java b/src/test/java/com/fasterxml/jackson/databind/deser/jdk/UntypedDeserializationTest.java
index 3b28b9d0c..b319edb2b 100644
--- a/src/test/java/com/fasterxml/jackson/databind/deser/jdk/UntypedDeserializationTest.java
+++ b/src/test/java/com/fasterxml/jackson/databind/deser/jdk/UntypedDeserializationTest.java
@@ -279,8 +279,8 @@ public class UntypedDeserializationTest
 
         ObjectReader rDefault = mapper.readerFor(WrappedPolymorphicUntyped.class);
         ObjectReader rAlt = rDefault
-                .with(DeserializationFeature.USE_BIG_DECIMAL_FOR_FLOATS,
-                        DeserializationFeature.USE_BIG_INTEGER_FOR_INTS);
+                .with(DeserializationFeatures.USE_BIG_DECIMAL_FOR_FLOATS,
+                        DeserializationFeatures.USE_BIG_INTEGER_FOR_INTS);
         WrappedPolymorphicUntyped w;
 
         w = rDefault.readValue(aposToQuotes("{'value':10}"));
@@ -302,7 +302,7 @@ public class UntypedDeserializationTest
 
         // First read as-is, no type wrapping
         Object ob = mapper.readerFor(Object.class)
-                .with(DeserializationFeature.USE_JAVA_ARRAY_FOR_JSON_ARRAY)
+                .with(DeserializationFeatures.USE_JAVA_ARRAY_FOR_JSON_ARRAY)
                 .readValue(INT_ARRAY_JSON);
         assertTrue(ob instanceof Object[]);
         Object[] obs = (Object[]) ob;
@@ -366,7 +366,7 @@ public class UntypedDeserializationTest
         assertTrue(ob instanceof List<?>);
 
         // but can change to produce Object[]:
-        MAPPER.configure(DeserializationFeature.USE_JAVA_ARRAY_FOR_JSON_ARRAY, true);
+        MAPPER.configure(DeserializationFeatures.USE_JAVA_ARRAY_FOR_JSON_ARRAY, true);
         ob = MAPPER.readValue("[1]", Object.class);
         assertEquals(Object[].class, ob.getClass());
     }
@@ -379,7 +379,7 @@ public class UntypedDeserializationTest
         assertEquals(Integer.valueOf(3), w.value);
 
         w = MAPPER.readerFor(WrappedUntyped1460.class)
-                .with(DeserializationFeature.USE_LONG_FOR_INTS)
+                .with(DeserializationFeatures.USE_LONG_FOR_INTS)
                 .readValue(JSON);
         assertEquals(Long.valueOf(3), w.value);
     }
diff --git a/src/test/java/com/fasterxml/jackson/databind/deser/merge/ArrayMergeTest.java b/src/test/java/com/fasterxml/jackson/databind/deser/merge/ArrayMergeTest.java
index 908ddc5f8..7eab71298 100644
--- a/src/test/java/com/fasterxml/jackson/databind/deser/merge/ArrayMergeTest.java
+++ b/src/test/java/com/fasterxml/jackson/databind/deser/merge/ArrayMergeTest.java
@@ -47,7 +47,7 @@ public class ArrayMergeTest extends BaseMapTest
 
         // and with one trick
         result = MAPPER.readerFor(type)
-                .with(DeserializationFeature.ACCEPT_SINGLE_VALUE_AS_ARRAY)
+                .with(DeserializationFeatures.ACCEPT_SINGLE_VALUE_AS_ARRAY)
                 .withValueToUpdate(input)
                 .readValue(aposToQuotes("{'value':'zap'}"));
         assertSame(input, result);
diff --git a/src/test/java/com/fasterxml/jackson/databind/exc/ExceptionDeserializationTest.java b/src/test/java/com/fasterxml/jackson/databind/exc/ExceptionDeserializationTest.java
index 536a5b428..a51a674bf 100644
--- a/src/test/java/com/fasterxml/jackson/databind/exc/ExceptionDeserializationTest.java
+++ b/src/test/java/com/fasterxml/jackson/databind/exc/ExceptionDeserializationTest.java
@@ -99,7 +99,7 @@ public class ExceptionDeserializationTest
     // [databind#381]
     public void testSingleValueArrayDeserialization() throws Exception {
         final ObjectMapper mapper = new ObjectMapper();
-        mapper.enable(DeserializationFeature.UNWRAP_SINGLE_VALUE_ARRAYS);
+        mapper.enable(DeserializationFeatures.UNWRAP_SINGLE_VALUE_ARRAYS);
         final IOException exp;
         try {
             throw new IOException("testing");
@@ -143,7 +143,7 @@ public class ExceptionDeserializationTest
 
     public void testSingleValueArrayDeserializationException() throws Exception {
         final ObjectMapper mapper = new ObjectMapper();
-        mapper.disable(DeserializationFeature.UNWRAP_SINGLE_VALUE_ARRAYS);
+        mapper.disable(DeserializationFeatures.UNWRAP_SINGLE_VALUE_ARRAYS);
         
         final IOException exp;
         try {
diff --git a/src/test/java/com/fasterxml/jackson/databind/introspect/TestJacksonAnnotationIntrospector.java b/src/test/java/com/fasterxml/jackson/databind/introspect/TestJacksonAnnotationIntrospector.java
index ef9adde13..668919d83 100644
--- a/src/test/java/com/fasterxml/jackson/databind/introspect/TestJacksonAnnotationIntrospector.java
+++ b/src/test/java/com/fasterxml/jackson/databind/introspect/TestJacksonAnnotationIntrospector.java
@@ -13,10 +13,8 @@ import com.fasterxml.jackson.core.JsonProcessingException;
 import com.fasterxml.jackson.databind.*;
 import com.fasterxml.jackson.databind.annotation.*;
 import com.fasterxml.jackson.databind.deser.std.StdDeserializer;
-import com.fasterxml.jackson.databind.introspect.AnnotatedClass;
-import com.fasterxml.jackson.databind.introspect.JacksonAnnotationIntrospector;
 import com.fasterxml.jackson.databind.jsontype.TypeResolverBuilder;
-import com.fasterxml.jackson.databind.jsontype.impl.StdTypeResolverBuilder;
+import com.fasterxml.jackson.databind.jsontype.impl.StandardTypeResolverBuilder;
 import com.fasterxml.jackson.databind.type.TypeFactory;
 
 @SuppressWarnings("serial")
@@ -116,7 +114,7 @@ public class TestJacksonAnnotationIntrospector
         }
     }
 
-    public static class DummyBuilder extends StdTypeResolverBuilder
+    public static class DummyBuilder extends StandardTypeResolverBuilder
     //<DummyBuilder>
     {
     }
diff --git a/src/test/java/com/fasterxml/jackson/databind/jsontype/TestPolymorphicWithDefaultImpl.java b/src/test/java/com/fasterxml/jackson/databind/jsontype/TestPolymorphicWithDefaultImpl.java
index 7d260c785..dea7b5524 100644
--- a/src/test/java/com/fasterxml/jackson/databind/jsontype/TestPolymorphicWithDefaultImpl.java
+++ b/src/test/java/com/fasterxml/jackson/databind/jsontype/TestPolymorphicWithDefaultImpl.java
@@ -199,7 +199,7 @@ public class TestPolymorphicWithDefaultImpl extends BaseMapTest
     public void testBadTypeAsNull() throws Exception
     {
         ObjectMapper mapper = new ObjectMapper();
-        mapper.disable(DeserializationFeature.FAIL_ON_INVALID_SUBTYPE);
+        mapper.disable(DeserializationFeatures.FAIL_ON_INVALID_SUBTYPE);
         Object ob = mapper.readValue("{}", MysteryPolymorphic.class);
         assertNull(ob);
         ob = mapper.readValue("{ \"whatever\":13}", MysteryPolymorphic.class);
@@ -209,9 +209,9 @@ public class TestPolymorphicWithDefaultImpl extends BaseMapTest
     // [databind#511]
     public void testInvalidTypeId511() throws Exception {
         ObjectReader reader = MAPPER.reader().without(
-                DeserializationFeature.FAIL_ON_INVALID_SUBTYPE,
-                DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES,
-                DeserializationFeature.FAIL_ON_IGNORED_PROPERTIES
+                DeserializationFeatures.FAIL_ON_INVALID_SUBTYPE,
+                DeserializationFeatures.FAIL_ON_UNKNOWN_PROPERTIES,
+                DeserializationFeatures.FAIL_ON_IGNORED_PROPERTIES
         );
         String json = "{\"many\":[{\"sub1\":{\"a\":\"foo\"}},{\"sub2\":{\"b\":\"bar\"}}]}" ;
         Good goodResult = reader.forType(Good.class).readValue(json) ;
@@ -232,7 +232,7 @@ public class TestPolymorphicWithDefaultImpl extends BaseMapTest
     public void testUnknownTypeIDRecovery() throws Exception
     {
         ObjectReader reader = MAPPER.readerFor(CallRecord.class).without(
-                DeserializationFeature.FAIL_ON_INVALID_SUBTYPE);
+                DeserializationFeatures.FAIL_ON_INVALID_SUBTYPE);
         String json = aposToQuotes("{'version':0.0,'application':'123',"
                 +"'item':{'type':'xevent','location':'location1'},"
                 +"'item2':{'type':'event','location':'location1'}}");
@@ -250,7 +250,7 @@ public class TestPolymorphicWithDefaultImpl extends BaseMapTest
     public void testUnknownClassAsSubtype() throws Exception
     {
         ObjectMapper mapper = new ObjectMapper();
-        mapper.configure(DeserializationFeature.FAIL_ON_INVALID_SUBTYPE, false);
+        mapper.configure(DeserializationFeatures.FAIL_ON_INVALID_SUBTYPE, false);
         BaseWrapper w = mapper.readValue(aposToQuotes
                 ("{'value':{'clazz':'com.foobar.Nothing'}}'"),
                 BaseWrapper.class);
@@ -261,7 +261,7 @@ public class TestPolymorphicWithDefaultImpl extends BaseMapTest
     public void testWithoutEmptyStringAsNullObject1533() throws Exception
     {
         ObjectReader r = MAPPER.readerFor(AsPropertyWrapper.class)
-                .without(DeserializationFeature.ACCEPT_EMPTY_STRING_AS_NULL_OBJECT);
+                .without(DeserializationFeatures.ACCEPT_EMPTY_STRING_AS_NULL_OBJECT);
         try {
             r.readValue("{ \"value\": \"\" }");
             fail("Expected " + JsonMappingException.class);
@@ -274,7 +274,7 @@ public class TestPolymorphicWithDefaultImpl extends BaseMapTest
     public void testWithEmptyStringAsNullObject1533() throws Exception
     {
         ObjectReader r = MAPPER.readerFor(AsPropertyWrapper.class)
-                .with(DeserializationFeature.ACCEPT_EMPTY_STRING_AS_NULL_OBJECT);
+                .with(DeserializationFeatures.ACCEPT_EMPTY_STRING_AS_NULL_OBJECT);
         AsPropertyWrapper wrapper = r.readValue("{ \"value\": \"\" }");
         assertNull(wrapper.value);
     }
diff --git a/src/test/java/com/fasterxml/jackson/databind/jsontype/UnknownSubClassTest.java b/src/test/java/com/fasterxml/jackson/databind/jsontype/UnknownSubClassTest.java
index ba670983d..03e40adea 100644
--- a/src/test/java/com/fasterxml/jackson/databind/jsontype/UnknownSubClassTest.java
+++ b/src/test/java/com/fasterxml/jackson/databind/jsontype/UnknownSubClassTest.java
@@ -18,7 +18,7 @@ public class UnknownSubClassTest extends BaseMapTest
     public void testUnknownClassAsSubtype() throws Exception
     {
         ObjectMapper mapper = new ObjectMapper();
-        mapper.configure(DeserializationFeature.FAIL_ON_INVALID_SUBTYPE, false);
+        mapper.configure(DeserializationFeatures.FAIL_ON_INVALID_SUBTYPE, false);
         BaseWrapper w = mapper.readValue(aposToQuotes
                 ("{'value':{'clazz':'com.foobar.Nothing'}}'"),
                 BaseWrapper.class);
diff --git a/src/test/java/com/fasterxml/jackson/databind/jsontype/deftyping/TestDefaultForScalars.java b/src/test/java/com/fasterxml/jackson/databind/jsontype/deftyping/TestDefaultForScalars.java
index 7bb7b5c43..b514f33f2 100644
--- a/src/test/java/com/fasterxml/jackson/databind/jsontype/deftyping/TestDefaultForScalars.java
+++ b/src/test/java/com/fasterxml/jackson/databind/jsontype/deftyping/TestDefaultForScalars.java
@@ -6,7 +6,7 @@ import static org.junit.Assert.*;
 
 import com.fasterxml.jackson.annotation.JsonTypeInfo;
 import com.fasterxml.jackson.databind.*;
-import com.fasterxml.jackson.databind.jsontype.impl.StdTypeResolverBuilder;
+import com.fasterxml.jackson.databind.jsontype.impl.StandardTypeResolverBuilder;
 
 /**
  * Unit tests to verify that Java/JSON scalar values (non-structured values)
@@ -121,7 +121,7 @@ public class TestDefaultForScalars
 
         // Configure Jackson to preserve types
         ObjectMapper mapper = new ObjectMapper();
-        StdTypeResolverBuilder resolver = new StdTypeResolverBuilder();
+        StandardTypeResolverBuilder resolver = new StandardTypeResolverBuilder();
         resolver.init(JsonTypeInfo.Id.CLASS, null);
         resolver.inclusion(JsonTypeInfo.As.PROPERTY);
         resolver.typeProperty("__t");
diff --git a/src/test/java/com/fasterxml/jackson/databind/jsontype/ext/ExternalTypeIdTest.java b/src/test/java/com/fasterxml/jackson/databind/jsontype/ext/ExternalTypeIdTest.java
index 753712992..634daab01 100644
--- a/src/test/java/com/fasterxml/jackson/databind/jsontype/ext/ExternalTypeIdTest.java
+++ b/src/test/java/com/fasterxml/jackson/databind/jsontype/ext/ExternalTypeIdTest.java
@@ -7,7 +7,7 @@ import com.fasterxml.jackson.annotation.*;
 import com.fasterxml.jackson.annotation.JsonTypeInfo.As;
 import com.fasterxml.jackson.annotation.JsonTypeInfo.Id;
 import com.fasterxml.jackson.databind.BaseMapTest;
-import com.fasterxml.jackson.databind.DeserializationFeature;
+import com.fasterxml.jackson.databind.DeserializationFeatures;
 import com.fasterxml.jackson.databind.ObjectMapper;
 
 // Tests for External type id, one that exists at same level as typed Object,
@@ -528,7 +528,7 @@ public class ExternalTypeIdTest extends BaseMapTest
         }
         
         Wrapper965 w2 = MAPPER.readerFor(Wrapper965.class)
-                .with(DeserializationFeature.USE_BIG_DECIMAL_FOR_FLOATS)
+                .with(DeserializationFeatures.USE_BIG_DECIMAL_FOR_FLOATS)
                 .readValue(json);
 
         assertEquals(w.typeEnum, w2.typeEnum);
diff --git a/src/test/java/com/fasterxml/jackson/databind/jsontype/ext/TestSubtypesExternalPropertyMissingProperty.java b/src/test/java/com/fasterxml/jackson/databind/jsontype/ext/TestSubtypesExternalPropertyMissingProperty.java
index ac414b3ac..94c2a7ca7 100644
--- a/src/test/java/com/fasterxml/jackson/databind/jsontype/ext/TestSubtypesExternalPropertyMissingProperty.java
+++ b/src/test/java/com/fasterxml/jackson/databind/jsontype/ext/TestSubtypesExternalPropertyMissingProperty.java
@@ -128,11 +128,11 @@ public class TestSubtypesExternalPropertyMissingProperty
      */
     @Test
     public void testDeserializationPresent() throws Exception {
-        MAPPER.disable(DeserializationFeature.FAIL_ON_MISSING_EXTERNAL_TYPE_ID_PROPERTY);
+        MAPPER.disable(DeserializationFeatures.FAIL_ON_MISSING_EXTERNAL_TYPE_ID_PROPERTY);
         checkOrangeBox();
         checkAppleBox();
 
-        MAPPER.enable(DeserializationFeature.FAIL_ON_MISSING_EXTERNAL_TYPE_ID_PROPERTY);
+        MAPPER.enable(DeserializationFeatures.FAIL_ON_MISSING_EXTERNAL_TYPE_ID_PROPERTY);
         checkOrangeBox();
         checkAppleBox();
     }
@@ -142,11 +142,11 @@ public class TestSubtypesExternalPropertyMissingProperty
      */
     @Test
     public void testDeserializationNull() throws Exception {
-        MAPPER.disable(DeserializationFeature.FAIL_ON_MISSING_EXTERNAL_TYPE_ID_PROPERTY);
+        MAPPER.disable(DeserializationFeatures.FAIL_ON_MISSING_EXTERNAL_TYPE_ID_PROPERTY);
         checkOrangeBoxNull(orangeBoxNullJson);
         checkAppleBoxNull(appleBoxNullJson);
 
-        MAPPER.enable(DeserializationFeature.FAIL_ON_MISSING_EXTERNAL_TYPE_ID_PROPERTY);
+        MAPPER.enable(DeserializationFeatures.FAIL_ON_MISSING_EXTERNAL_TYPE_ID_PROPERTY);
         checkOrangeBoxNull(orangeBoxNullJson);
         checkAppleBoxNull(appleBoxNullJson);
     }
@@ -156,11 +156,11 @@ public class TestSubtypesExternalPropertyMissingProperty
      */
     @Test
     public void testDeserializationEmpty() throws Exception {
-        MAPPER.disable(DeserializationFeature.FAIL_ON_MISSING_EXTERNAL_TYPE_ID_PROPERTY);
+        MAPPER.disable(DeserializationFeatures.FAIL_ON_MISSING_EXTERNAL_TYPE_ID_PROPERTY);
         checkOrangeBoxEmpty(orangeBoxEmptyJson);
         checkAppleBoxEmpty(appleBoxEmptyJson);
 
-        MAPPER.enable(DeserializationFeature.FAIL_ON_MISSING_EXTERNAL_TYPE_ID_PROPERTY);
+        MAPPER.enable(DeserializationFeatures.FAIL_ON_MISSING_EXTERNAL_TYPE_ID_PROPERTY);
         checkOrangeBoxEmpty(orangeBoxEmptyJson);
         checkAppleBoxEmpty(appleBoxEmptyJson);
     }
@@ -170,11 +170,11 @@ public class TestSubtypesExternalPropertyMissingProperty
      */
     @Test
     public void testDeserializationMissing() throws Exception {
-        MAPPER.disable(DeserializationFeature.FAIL_ON_MISSING_EXTERNAL_TYPE_ID_PROPERTY);
+        MAPPER.disable(DeserializationFeatures.FAIL_ON_MISSING_EXTERNAL_TYPE_ID_PROPERTY);
         checkOrangeBoxNull(orangeBoxMissingJson);
         checkAppleBoxNull(appleBoxMissingJson);
 
-        MAPPER.enable(DeserializationFeature.FAIL_ON_MISSING_EXTERNAL_TYPE_ID_PROPERTY);
+        MAPPER.enable(DeserializationFeatures.FAIL_ON_MISSING_EXTERNAL_TYPE_ID_PROPERTY);
         checkBoxJsonMappingException(orangeBoxMissingJson);
         checkBoxJsonMappingException(appleBoxMissingJson);
     }
@@ -184,11 +184,11 @@ public class TestSubtypesExternalPropertyMissingProperty
      */
     @Test
     public void testDeserializationMissingRequired() throws Exception {
-        MAPPER.disable(DeserializationFeature.FAIL_ON_MISSING_EXTERNAL_TYPE_ID_PROPERTY);
+        MAPPER.disable(DeserializationFeatures.FAIL_ON_MISSING_EXTERNAL_TYPE_ID_PROPERTY);
         checkReqBoxJsonMappingException(orangeBoxMissingJson);
         checkReqBoxJsonMappingException(appleBoxMissingJson);
 
-        MAPPER.enable(DeserializationFeature.FAIL_ON_MISSING_EXTERNAL_TYPE_ID_PROPERTY);
+        MAPPER.enable(DeserializationFeatures.FAIL_ON_MISSING_EXTERNAL_TYPE_ID_PROPERTY);
         checkReqBoxJsonMappingException(orangeBoxMissingJson);
         checkReqBoxJsonMappingException(appleBoxMissingJson);
     }
diff --git a/src/test/java/com/fasterxml/jackson/databind/mixins/MapperMixinsCopy1998Test.java b/src/test/java/com/fasterxml/jackson/databind/mixins/MapperMixinsCopy1998Test.java
index 32897e659..d6eb35962 100644
--- a/src/test/java/com/fasterxml/jackson/databind/mixins/MapperMixinsCopy1998Test.java
+++ b/src/test/java/com/fasterxml/jackson/databind/mixins/MapperMixinsCopy1998Test.java
@@ -121,7 +121,7 @@ public class MapperMixinsCopy1998Test extends BaseMapTest
         return new ObjectMapper().setSerializationInclusion(JsonInclude.Include.NON_EMPTY)
                 .configure(SerializationFeature.WRITE_DATES_AS_TIMESTAMPS, false)
                 .configure(MapperFeature.ALLOW_COERCION_OF_SCALARS, false)
-                .configure(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES, true)
+                .configure(DeserializationFeatures.FAIL_ON_UNKNOWN_PROPERTIES, true)
             ;
     }
 }
diff --git a/src/test/java/com/fasterxml/jackson/databind/node/NotANumberConversionTest.java b/src/test/java/com/fasterxml/jackson/databind/node/NotANumberConversionTest.java
index 3fcb71dba..d0ae24bc0 100644
--- a/src/test/java/com/fasterxml/jackson/databind/node/NotANumberConversionTest.java
+++ b/src/test/java/com/fasterxml/jackson/databind/node/NotANumberConversionTest.java
@@ -8,7 +8,7 @@ public class NotANumberConversionTest extends BaseMapTest
 {
     private final ObjectMapper m = new ObjectMapper();
     {
-        m.enable(DeserializationFeature.USE_BIG_DECIMAL_FOR_FLOATS);
+        m.enable(DeserializationFeatures.USE_BIG_DECIMAL_FOR_FLOATS);
     }
 
     public void testBigDecimalWithNaN() throws Exception
diff --git a/src/test/java/com/fasterxml/jackson/databind/node/NumberNodesTest.java b/src/test/java/com/fasterxml/jackson/databind/node/NumberNodesTest.java
index f12cb9484..422db8e93 100644
--- a/src/test/java/com/fasterxml/jackson/databind/node/NumberNodesTest.java
+++ b/src/test/java/com/fasterxml/jackson/databind/node/NumberNodesTest.java
@@ -364,7 +364,7 @@ public class NumberNodesTest extends NodeTestBase
     public void testBigDecimalAsPlain() throws Exception
     {
         ObjectMapper mapper = new ObjectMapper()
-                .enable(DeserializationFeature.USE_BIG_DECIMAL_FOR_FLOATS)
+                .enable(DeserializationFeatures.USE_BIG_DECIMAL_FOR_FLOATS)
                 .enable(JsonGenerator.Feature.WRITE_BIGDECIMAL_AS_PLAIN);
         final String INPUT = "{\"x\":1e2}";
         final JsonNode node = mapper.readTree(INPUT);
diff --git a/src/test/java/com/fasterxml/jackson/databind/node/ObjectNodeTest.java b/src/test/java/com/fasterxml/jackson/databind/node/ObjectNodeTest.java
index b617d68b0..b78ebe203 100644
--- a/src/test/java/com/fasterxml/jackson/databind/node/ObjectNodeTest.java
+++ b/src/test/java/com/fasterxml/jackson/databind/node/ObjectNodeTest.java
@@ -373,13 +373,13 @@ public class ObjectNodeTest
         
         // first: verify defaults:
         ObjectMapper mapper = new ObjectMapper();
-        assertFalse(mapper.isEnabled(DeserializationFeature.FAIL_ON_READING_DUP_TREE_KEY));
+        assertFalse(mapper.isEnabled(DeserializationFeatures.FAIL_ON_READING_DUP_TREE_KEY));
         ObjectNode root = (ObjectNode) mapper.readTree(DUP_JSON);
         assertEquals(2, root.path("a").asInt());
         
         // and then enable checks:
         try {
-            mapper.reader(DeserializationFeature.FAIL_ON_READING_DUP_TREE_KEY).readTree(DUP_JSON);
+            mapper.reader(DeserializationFeatures.FAIL_ON_READING_DUP_TREE_KEY).readTree(DUP_JSON);
             fail("Should have thrown exception!");
         } catch (JsonMappingException e) {
             verifyException(e, "duplicate field 'a'");
diff --git a/src/test/java/com/fasterxml/jackson/databind/objectid/ObjectId825BTest.java b/src/test/java/com/fasterxml/jackson/databind/objectid/ObjectId825BTest.java
index 8c36f278a..c05862a7a 100644
--- a/src/test/java/com/fasterxml/jackson/databind/objectid/ObjectId825BTest.java
+++ b/src/test/java/com/fasterxml/jackson/databind/objectid/ObjectId825BTest.java
@@ -139,7 +139,7 @@ public class ObjectId825BTest extends BaseMapTest
     {
         final ObjectMapper mapper = new ObjectMapper();
         mapper.enableDefaultTyping(ObjectMapper.DefaultTyping.OBJECT_AND_NON_CONCRETE);
-        mapper.enable(DeserializationFeature.ACCEPT_EMPTY_STRING_AS_NULL_OBJECT);
+        mapper.enable(DeserializationFeatures.ACCEPT_EMPTY_STRING_AS_NULL_OBJECT);
 
         String INPUT = aposToQuotes(
 "{\n"+
diff --git a/src/test/java/com/fasterxml/jackson/databind/objectid/TestObjectIdDeserialization.java b/src/test/java/com/fasterxml/jackson/databind/objectid/TestObjectIdDeserialization.java
index 2db9bdc61..0ecc2cd49 100644
--- a/src/test/java/com/fasterxml/jackson/databind/objectid/TestObjectIdDeserialization.java
+++ b/src/test/java/com/fasterxml/jackson/databind/objectid/TestObjectIdDeserialization.java
@@ -14,7 +14,7 @@ import com.fasterxml.jackson.annotation.ObjectIdGenerators;
 import com.fasterxml.jackson.annotation.ObjectIdResolver;
 import com.fasterxml.jackson.databind.BaseMapTest;
 import com.fasterxml.jackson.databind.DeserializationContext;
-import com.fasterxml.jackson.databind.DeserializationFeature;
+import com.fasterxml.jackson.databind.DeserializationFeatures;
 import com.fasterxml.jackson.databind.ObjectMapper;
 import com.fasterxml.jackson.databind.cfg.ContextAttributes;
 import com.fasterxml.jackson.databind.deser.UnresolvedForwardReference;
@@ -346,7 +346,7 @@ public class TestObjectIdDeserialization extends BaseMapTest
     public void testUnresolvableAsNull() throws Exception
     {
         IdWrapper w = MAPPER.readerFor(IdWrapper.class)
-                .without(DeserializationFeature.FAIL_ON_UNRESOLVED_OBJECT_IDS)
+                .without(DeserializationFeatures.FAIL_ON_UNRESOLVED_OBJECT_IDS)
                 .readValue(aposToQuotes("{'node':123}"));
         assertNotNull(w);
         assertNull(w.node);
diff --git a/src/test/java/com/fasterxml/jackson/databind/ser/TestKeySerializers.java b/src/test/java/com/fasterxml/jackson/databind/ser/TestKeySerializers.java
index dd9739223..c4928435d 100644
--- a/src/test/java/com/fasterxml/jackson/databind/ser/TestKeySerializers.java
+++ b/src/test/java/com/fasterxml/jackson/databind/ser/TestKeySerializers.java
@@ -229,7 +229,7 @@ public class TestKeySerializers extends BaseMapTest
         mod.addKeySerializer(ABC.class, new ABCKeySerializer());
         final ObjectMapper mapper = new ObjectMapper()
             .registerModule(mod)
-            .enable(DeserializationFeature.ACCEPT_EMPTY_STRING_AS_NULL_OBJECT)
+            .enable(DeserializationFeatures.ACCEPT_EMPTY_STRING_AS_NULL_OBJECT)
             .disable(SerializationFeature.WRITE_DATES_AS_TIMESTAMPS)
             .disable(SerializationFeature.WRITE_NULL_MAP_VALUES)
             .setSerializationInclusion(JsonInclude.Include.NON_EMPTY)
diff --git a/src/test/java/com/fasterxml/jackson/databind/struct/EmptyArrayAsNullTest.java b/src/test/java/com/fasterxml/jackson/databind/struct/EmptyArrayAsNullTest.java
index 71aba3253..6317653f2 100644
--- a/src/test/java/com/fasterxml/jackson/databind/struct/EmptyArrayAsNullTest.java
+++ b/src/test/java/com/fasterxml/jackson/databind/struct/EmptyArrayAsNullTest.java
@@ -19,7 +19,7 @@ public class EmptyArrayAsNullTest extends BaseMapTest
     private final ObjectMapper MAPPER = new ObjectMapper();
     private final ObjectReader DEFAULT_READER = MAPPER.reader();
     private final ObjectReader READER_WITH_ARRAYS = DEFAULT_READER
-            .with(DeserializationFeature.ACCEPT_EMPTY_ARRAY_AS_NULL_OBJECT);
+            .with(DeserializationFeatures.ACCEPT_EMPTY_ARRAY_AS_NULL_OBJECT);
 
     static class Bean {
         public String a = "foo";
@@ -34,9 +34,9 @@ public class EmptyArrayAsNullTest extends BaseMapTest
      */
 
     public void testSettings() {
-        assertFalse(MAPPER.isEnabled(DeserializationFeature.ACCEPT_EMPTY_ARRAY_AS_NULL_OBJECT));
-        assertFalse(DEFAULT_READER.isEnabled(DeserializationFeature.ACCEPT_EMPTY_ARRAY_AS_NULL_OBJECT));
-        assertTrue(READER_WITH_ARRAYS.isEnabled(DeserializationFeature.ACCEPT_EMPTY_ARRAY_AS_NULL_OBJECT));
+        assertFalse(MAPPER.isEnabled(DeserializationFeatures.ACCEPT_EMPTY_ARRAY_AS_NULL_OBJECT));
+        assertFalse(DEFAULT_READER.isEnabled(DeserializationFeatures.ACCEPT_EMPTY_ARRAY_AS_NULL_OBJECT));
+        assertTrue(READER_WITH_ARRAYS.isEnabled(DeserializationFeatures.ACCEPT_EMPTY_ARRAY_AS_NULL_OBJECT));
     }
 
     /*
diff --git a/src/test/java/com/fasterxml/jackson/databind/struct/ScalarCoercionTest.java b/src/test/java/com/fasterxml/jackson/databind/struct/ScalarCoercionTest.java
index e524d7203..8ac623e18 100644
--- a/src/test/java/com/fasterxml/jackson/databind/struct/ScalarCoercionTest.java
+++ b/src/test/java/com/fasterxml/jackson/databind/struct/ScalarCoercionTest.java
@@ -53,7 +53,7 @@ public class ScalarCoercionTest extends BaseMapTest
     private void _verifyNullOkFromEmpty(Class<?> type, Object exp) throws IOException
     {
         Object result = COERCING_MAPPER.readerFor(type)
-                .with(DeserializationFeature.ACCEPT_EMPTY_STRING_AS_NULL_OBJECT)
+                .with(DeserializationFeatures.ACCEPT_EMPTY_STRING_AS_NULL_OBJECT)
                 .readValue("\"\"");
         if (exp == null) {
             assertNull(result);
diff --git a/src/test/java/com/fasterxml/jackson/databind/struct/SingleValueAsArrayTest.java b/src/test/java/com/fasterxml/jackson/databind/struct/SingleValueAsArrayTest.java
index f0f93546e..1c48e8778 100644
--- a/src/test/java/com/fasterxml/jackson/databind/struct/SingleValueAsArrayTest.java
+++ b/src/test/java/com/fasterxml/jackson/databind/struct/SingleValueAsArrayTest.java
@@ -66,7 +66,7 @@ public class SingleValueAsArrayTest extends BaseMapTest
     
     private final ObjectMapper MAPPER = new ObjectMapper();
     {
-        MAPPER.enable(DeserializationFeature.ACCEPT_SINGLE_VALUE_AS_ARRAY);
+        MAPPER.enable(DeserializationFeatures.ACCEPT_SINGLE_VALUE_AS_ARRAY);
     }
 
     public void testSuccessfulDeserializationOfObjectWithChainedArrayCreators() throws IOException
diff --git a/src/test/java/com/fasterxml/jackson/databind/struct/TestForwardReference.java b/src/test/java/com/fasterxml/jackson/databind/struct/TestForwardReference.java
index 87a5ce1e0..8eefe2605 100644
--- a/src/test/java/com/fasterxml/jackson/databind/struct/TestForwardReference.java
+++ b/src/test/java/com/fasterxml/jackson/databind/struct/TestForwardReference.java
@@ -5,7 +5,7 @@ import java.io.IOException;
 import com.fasterxml.jackson.annotation.*;
 
 import com.fasterxml.jackson.databind.BaseMapTest;
-import com.fasterxml.jackson.databind.DeserializationFeature;
+import com.fasterxml.jackson.databind.DeserializationFeatures;
 import com.fasterxml.jackson.databind.ObjectMapper;
 import com.fasterxml.jackson.databind.SerializationFeature;
 
@@ -15,7 +15,7 @@ import com.fasterxml.jackson.databind.SerializationFeature;
 public class TestForwardReference extends BaseMapTest {
 
 	private final ObjectMapper MAPPER = new ObjectMapper()
-			.configure(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES, false)
+			.configure(DeserializationFeatures.FAIL_ON_UNKNOWN_PROPERTIES, false)
 			.enable(SerializationFeature.INDENT_OUTPUT)
 			.setSerializationInclusion(JsonInclude.Include.NON_NULL);
 
diff --git a/src/test/java/com/fasterxml/jackson/databind/struct/TestPOJOAsArray.java b/src/test/java/com/fasterxml/jackson/databind/struct/TestPOJOAsArray.java
index 391cd3cb8..94767f9bb 100644
--- a/src/test/java/com/fasterxml/jackson/databind/struct/TestPOJOAsArray.java
+++ b/src/test/java/com/fasterxml/jackson/databind/struct/TestPOJOAsArray.java
@@ -203,7 +203,7 @@ public class TestPOJOAsArray extends BaseMapTest
     public void testBeanAsArrayUnwrapped() throws Exception
     {
         ObjectMapper mapper = new ObjectMapper();
-        mapper.enable(DeserializationFeature.ACCEPT_SINGLE_VALUE_AS_ARRAY);
+        mapper.enable(DeserializationFeatures.ACCEPT_SINGLE_VALUE_AS_ARRAY);
         SingleBean result = mapper.readValue("[\"foobar\"]", SingleBean.class);
         assertNotNull(result);
         assertEquals("foobar", result.name);
@@ -281,7 +281,7 @@ public class TestPOJOAsArray extends BaseMapTest
 
         // but actually fine if skip-unknown set
         PojoAsArrayWrapper v = MAPPER.readerFor(PojoAsArrayWrapper.class)
-                .without(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES)
+                .without(DeserializationFeatures.FAIL_ON_UNKNOWN_PROPERTIES)
                 .readValue(json);
         assertNotNull(v);
         // note: +1 for both so
diff --git a/src/test/java/com/fasterxml/jackson/databind/struct/TestPOJOAsArrayWithBuilder.java b/src/test/java/com/fasterxml/jackson/databind/struct/TestPOJOAsArrayWithBuilder.java
index 321c86c6a..0c0080e22 100644
--- a/src/test/java/com/fasterxml/jackson/databind/struct/TestPOJOAsArrayWithBuilder.java
+++ b/src/test/java/com/fasterxml/jackson/databind/struct/TestPOJOAsArrayWithBuilder.java
@@ -3,7 +3,7 @@ package com.fasterxml.jackson.databind.struct;
 import com.fasterxml.jackson.annotation.*;
 
 import com.fasterxml.jackson.databind.BaseMapTest;
-import com.fasterxml.jackson.databind.DeserializationFeature;
+import com.fasterxml.jackson.databind.DeserializationFeatures;
 import com.fasterxml.jackson.databind.ObjectMapper;
 import com.fasterxml.jackson.databind.ObjectReader;
 import com.fasterxml.jackson.databind.annotation.JsonDeserialize;
@@ -195,7 +195,7 @@ public class TestPOJOAsArrayWithBuilder extends BaseMapTest
 
         // but actually fine if skip-unknown set
         ValueClassXY v = MAPPER.readerFor(ValueClassXY.class)
-                .without(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES)
+                .without(DeserializationFeatures.FAIL_ON_UNKNOWN_PROPERTIES)
                 .readValue(json);
         assertNotNull(v);
         // note: +1 for both so
diff --git a/src/test/java/com/fasterxml/jackson/databind/struct/UnwrapSingleArrayScalarsTest.java b/src/test/java/com/fasterxml/jackson/databind/struct/UnwrapSingleArrayScalarsTest.java
index 4352835ab..0e4c70063 100644
--- a/src/test/java/com/fasterxml/jackson/databind/struct/UnwrapSingleArrayScalarsTest.java
+++ b/src/test/java/com/fasterxml/jackson/databind/struct/UnwrapSingleArrayScalarsTest.java
@@ -8,7 +8,7 @@ import java.net.URI;
 import java.util.UUID;
 
 import com.fasterxml.jackson.databind.BaseMapTest;
-import com.fasterxml.jackson.databind.DeserializationFeature;
+import com.fasterxml.jackson.databind.DeserializationFeatures;
 import com.fasterxml.jackson.databind.ObjectMapper;
 import com.fasterxml.jackson.databind.ObjectReader;
 import com.fasterxml.jackson.databind.exc.MismatchedInputException;
@@ -24,7 +24,7 @@ public class UnwrapSingleArrayScalarsTest extends BaseMapTest
 
     private final ObjectReader NO_UNWRAPPING_READER = MAPPER.reader();
     private final ObjectReader UNWRAPPING_READER = MAPPER.reader()
-            .with(DeserializationFeature.UNWRAP_SINGLE_VALUE_ARRAYS);
+            .with(DeserializationFeatures.UNWRAP_SINGLE_VALUE_ARRAYS);
 
     /*
     /**********************************************************
@@ -36,7 +36,7 @@ public class UnwrapSingleArrayScalarsTest extends BaseMapTest
     {
         // [databind#381]
         final ObjectMapper mapper = new ObjectMapper();
-        mapper.enable(DeserializationFeature.UNWRAP_SINGLE_VALUE_ARRAYS);
+        mapper.enable(DeserializationFeatures.UNWRAP_SINGLE_VALUE_ARRAYS);
         BooleanBean result = mapper.readValue(new StringReader("{\"v\":[true]}"), BooleanBean.class);
         assertTrue(result._v);
 
@@ -73,7 +73,7 @@ public class UnwrapSingleArrayScalarsTest extends BaseMapTest
         final char charTest = 'c';
 
         final ObjectMapper mapper = new ObjectMapper();
-        mapper.enable(DeserializationFeature.UNWRAP_SINGLE_VALUE_ARRAYS);
+        mapper.enable(DeserializationFeatures.UNWRAP_SINGLE_VALUE_ARRAYS);
 
         final int intValue = mapper.readValue(asArray(intTest), Integer.TYPE);
         assertEquals(intTest, intValue);
@@ -122,7 +122,7 @@ public class UnwrapSingleArrayScalarsTest extends BaseMapTest
 
     public void testSingleElementArrayDisabled() throws Exception {
         final ObjectMapper mapper = new ObjectMapper();
-        mapper.disable(DeserializationFeature.UNWRAP_SINGLE_VALUE_ARRAYS);
+        mapper.disable(DeserializationFeatures.UNWRAP_SINGLE_VALUE_ARRAYS);
         try {
             mapper.readValue("[42]", Integer.class);
             fail("Single value array didn't throw an exception when DeserializationFeature.UNWRAP_SINGLE_VALUE_ARRAYS is disabled");
@@ -249,7 +249,7 @@ public class UnwrapSingleArrayScalarsTest extends BaseMapTest
     public void testSingleStringWrapped() throws Exception
     {
         final ObjectMapper mapper = new ObjectMapper();
-        mapper.disable(DeserializationFeature.UNWRAP_SINGLE_VALUE_ARRAYS);
+        mapper.disable(DeserializationFeatures.UNWRAP_SINGLE_VALUE_ARRAYS);
         
         String value = "FOO!";
         try {
@@ -260,7 +260,7 @@ public class UnwrapSingleArrayScalarsTest extends BaseMapTest
             verifyException(exp, "out of START_ARRAY");
         }
         
-        mapper.enable(DeserializationFeature.UNWRAP_SINGLE_VALUE_ARRAYS);
+        mapper.enable(DeserializationFeatures.UNWRAP_SINGLE_VALUE_ARRAYS);
         
         try {
             mapper.readValue("[\""+value+"\",\""+value+"\"]", String.class);
@@ -275,7 +275,7 @@ public class UnwrapSingleArrayScalarsTest extends BaseMapTest
     public void testBigDecimal() throws Exception
     {
         final ObjectMapper mapper = objectMapper();
-        mapper.disable(DeserializationFeature.UNWRAP_SINGLE_VALUE_ARRAYS);
+        mapper.disable(DeserializationFeatures.UNWRAP_SINGLE_VALUE_ARRAYS);
         
         BigDecimal value = new BigDecimal("0.001");
         BigDecimal result = mapper.readValue(value.toString(), BigDecimal.class);
@@ -288,7 +288,7 @@ public class UnwrapSingleArrayScalarsTest extends BaseMapTest
             verifyException(exp, "out of START_ARRAY");
         }
         
-        mapper.enable(DeserializationFeature.UNWRAP_SINGLE_VALUE_ARRAYS);
+        mapper.enable(DeserializationFeatures.UNWRAP_SINGLE_VALUE_ARRAYS);
         result = mapper.readValue("[" + value.toString() + "]", BigDecimal.class);
         assertEquals(value, result);
         
@@ -303,7 +303,7 @@ public class UnwrapSingleArrayScalarsTest extends BaseMapTest
     public void testBigInteger() throws Exception
     {
         final ObjectMapper mapper = objectMapper();
-        mapper.disable(DeserializationFeature.UNWRAP_SINGLE_VALUE_ARRAYS);
+        mapper.disable(DeserializationFeatures.UNWRAP_SINGLE_VALUE_ARRAYS);
         
         BigInteger value = new BigInteger("-1234567890123456789012345567809");
         BigInteger result = mapper.readValue(value.toString(), BigInteger.class);
@@ -317,7 +317,7 @@ public class UnwrapSingleArrayScalarsTest extends BaseMapTest
             verifyException(exp, "out of START_ARRAY");
         }
         
-        mapper.enable(DeserializationFeature.UNWRAP_SINGLE_VALUE_ARRAYS);
+        mapper.enable(DeserializationFeatures.UNWRAP_SINGLE_VALUE_ARRAYS);
         result = mapper.readValue("[" + value.toString() + "]", BigInteger.class);
         assertEquals(value, result);
         
@@ -333,13 +333,13 @@ public class UnwrapSingleArrayScalarsTest extends BaseMapTest
     {
         Class<?> result = MAPPER
                     .readerFor(Class.class)
-                    .with(DeserializationFeature.UNWRAP_SINGLE_VALUE_ARRAYS)
+                    .with(DeserializationFeatures.UNWRAP_SINGLE_VALUE_ARRAYS)
                     .readValue(quote(String.class.getName()));
         assertEquals(String.class, result);
 
         try {
             MAPPER.readerFor(Class.class)
-                .without(DeserializationFeature.UNWRAP_SINGLE_VALUE_ARRAYS)
+                .without(DeserializationFeatures.UNWRAP_SINGLE_VALUE_ARRAYS)
                 .readValue("[" + quote(String.class.getName()) + "]");
             fail("Did not throw exception when UNWRAP_SINGLE_VALUE_ARRAYS feature was disabled and attempted to read a Class array containing one element");
         } catch (MismatchedInputException e) {
@@ -349,7 +349,7 @@ public class UnwrapSingleArrayScalarsTest extends BaseMapTest
         _verifyMultiValueArrayFail("[" + quote(Object.class.getName()) + "," + quote(Object.class.getName()) +"]",
                 Class.class);
         result = MAPPER.readerFor(Class.class)
-                .with(DeserializationFeature.UNWRAP_SINGLE_VALUE_ARRAYS)
+                .with(DeserializationFeatures.UNWRAP_SINGLE_VALUE_ARRAYS)
                 .readValue("[" + quote(String.class.getName()) + "]");
         assertEquals(String.class, result);
     }
@@ -359,7 +359,7 @@ public class UnwrapSingleArrayScalarsTest extends BaseMapTest
         final ObjectReader reader = MAPPER.readerFor(URI.class);
         final URI value = new URI("http://foo.com");
         try {
-            reader.without(DeserializationFeature.UNWRAP_SINGLE_VALUE_ARRAYS)
+            reader.without(DeserializationFeatures.UNWRAP_SINGLE_VALUE_ARRAYS)
                 .readValue("[\""+value.toString()+"\"]");
             fail("Did not throw exception for single value array when UNWRAP_SINGLE_VALUE_ARRAYS is disabled");
         } catch (MismatchedInputException e) {
@@ -382,7 +382,7 @@ public class UnwrapSingleArrayScalarsTest extends BaseMapTest
             verifyException(e, "out of START_ARRAY token");
         }
         assertEquals(uuid,
-                reader.with(DeserializationFeature.UNWRAP_SINGLE_VALUE_ARRAYS)
+                reader.with(DeserializationFeatures.UNWRAP_SINGLE_VALUE_ARRAYS)
                     .readValue("[" + quote(uuidStr) + "]"));
         _verifyMultiValueArrayFail("[" + quote(uuidStr) + "," + quote(uuidStr) + "]", UUID.class);
     }
diff --git a/src/test/java/com/fasterxml/jackson/databind/type/RecursiveType1658Test.java b/src/test/java/com/fasterxml/jackson/databind/type/RecursiveType1658Test.java
index c211cd969..459f2d322 100644
--- a/src/test/java/com/fasterxml/jackson/databind/type/RecursiveType1658Test.java
+++ b/src/test/java/com/fasterxml/jackson/databind/type/RecursiveType1658Test.java
@@ -5,7 +5,7 @@ import java.util.*;
 import com.fasterxml.jackson.annotation.JsonTypeInfo;
 import com.fasterxml.jackson.databind.*;
 import com.fasterxml.jackson.databind.jsontype.TypeResolverBuilder;
-import com.fasterxml.jackson.databind.jsontype.impl.StdTypeResolverBuilder;
+import com.fasterxml.jackson.databind.jsontype.impl.StandardTypeResolverBuilder;
 
 public class RecursiveType1658Test extends BaseMapTest
 {
@@ -31,7 +31,7 @@ public class RecursiveType1658Test extends BaseMapTest
         Tree<String> t = new Tree<String>(Arrays.asList("hello", "world"));
         ObjectMapper mapper = new ObjectMapper();
 
-        final TypeResolverBuilder<?> typer = new StdTypeResolverBuilder()
+        final TypeResolverBuilder<?> typer = new StandardTypeResolverBuilder()
                 .init(JsonTypeInfo.Id.CLASS, null)
                 .inclusion(JsonTypeInfo.As.PROPERTY);
         mapper.setDefaultTyping(typer);
diff --git a/src/test/java/com/fasterxml/jackson/failing/NumberNodes1770Test.java b/src/test/java/com/fasterxml/jackson/failing/NumberNodes1770Test.java
index 93e3602a9..11dd8a399 100644
--- a/src/test/java/com/fasterxml/jackson/failing/NumberNodes1770Test.java
+++ b/src/test/java/com/fasterxml/jackson/failing/NumberNodes1770Test.java
@@ -14,7 +14,7 @@ public class NumberNodes1770Test extends BaseMapTest
     public void testBigDecimalCoercion() throws Exception
     {
         final JsonNode jsonNode = MAPPER.reader()
-            .with(DeserializationFeature.USE_BIG_DECIMAL_FOR_FLOATS)
+            .with(DeserializationFeatures.USE_BIG_DECIMAL_FOR_FLOATS)
             .readTree("7976931348623157e309");
         assertTrue(jsonNode.isBigDecimal());
         // the following fails with NumberFormatException, because jsonNode is a DoubleNode with a value of POSITIVE_INFINITY
diff --git a/src/test/java/com/fasterxml/jackson/failing/TestUnwrappedWithUnknown650.java b/src/test/java/com/fasterxml/jackson/failing/TestUnwrappedWithUnknown650.java
index 6229491bd..524edd69b 100644
--- a/src/test/java/com/fasterxml/jackson/failing/TestUnwrappedWithUnknown650.java
+++ b/src/test/java/com/fasterxml/jackson/failing/TestUnwrappedWithUnknown650.java
@@ -18,7 +18,7 @@ public class TestUnwrappedWithUnknown650 extends BaseMapTest
 
     public void testFailOnUnknownPropertyUnwrapped() throws Exception
     {
-        assertTrue(MAPPER.isEnabled(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES));
+        assertTrue(MAPPER.isEnabled(DeserializationFeatures.FAIL_ON_UNKNOWN_PROPERTIES));
 
         final String JSON = "{'field': 'value', 'bad':'bad value'}";
         try {
diff --git a/src/test/java/perf/ObjectReaderTestBase.java b/src/test/java/perf/ObjectReaderTestBase.java
index d973b2e89..02181da8b 100644
--- a/src/test/java/perf/ObjectReaderTestBase.java
+++ b/src/test/java/perf/ObjectReaderTestBase.java
@@ -111,10 +111,10 @@ abstract class ObjectReaderTestBase
         System.out.print("Warming up");
 
         final ObjectReader jsonReader = mapper1.reader()
-                .with(DeserializationFeature.EAGER_DESERIALIZER_FETCH)
+                .with(DeserializationFeatures.EAGER_DESERIALIZER_FETCH)
                 .forType(inputClass1);
         final ObjectReader arrayReader = mapper2.reader()
-                .with(DeserializationFeature.EAGER_DESERIALIZER_FETCH)
+                .with(DeserializationFeatures.EAGER_DESERIALIZER_FETCH)
                 .forType(inputClass2);
         
         int i = 0;

EOF_METAMORPHIC_PATCH
git apply /home/metamorphic_base.patch
git add -A && git -c user.email='mswe-agent@metamorphic.py' -c user.name='metamorphic-transformation-patch' commit -m 'Apply `metamorphic_base_patch` transformation to base commit'


bash /home/check_git_changes.sh

file="/home/jackson-databind/pom.xml"
old_version="2.15.0-rc2-SNAPSHOT"
new_version="2.15.5-SNAPSHOT"
sed -i "s/$old_version/$new_version/g" "$file"

mvn clean test -Dmaven.test.skip=false -DfailIfNoTests=false || true
