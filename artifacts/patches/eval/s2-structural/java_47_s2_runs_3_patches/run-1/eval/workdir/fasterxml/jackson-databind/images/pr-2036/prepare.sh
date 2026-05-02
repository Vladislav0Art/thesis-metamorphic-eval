#!/bin/bash
set -e

cd /home/jackson-databind
git reset --hard
bash /home/check_git_changes.sh
git checkout bfeb1fa9dc4c889f8027b80abb2f77996efd9b70

# apply metamorphic patch (if present)
cat > /home/metamorphic_base.patch << 'EOF_METAMORPHIC_PATCH'
diff --git a/src/main/java/com/fasterxml/jackson/databind/DeserializationContext.java b/src/main/java/com/fasterxml/jackson/databind/DeserializationContext.java
index 53f44a5f9..d39ce6600 100644
--- a/src/main/java/com/fasterxml/jackson/databind/DeserializationContext.java
+++ b/src/main/java/com/fasterxml/jackson/databind/DeserializationContext.java
@@ -13,6 +13,7 @@ import com.fasterxml.jackson.annotation.ObjectIdResolver;
 import com.fasterxml.jackson.core.*;
 
 import com.fasterxml.jackson.databind.cfg.ContextAttributes;
+import com.fasterxml.jackson.databind.cfg.DeserializationFeature;
 import com.fasterxml.jackson.databind.deser.*;
 import com.fasterxml.jackson.databind.deser.impl.ObjectIdReader;
 import com.fasterxml.jackson.databind.deser.impl.ReadableObjectId;
diff --git a/src/main/java/com/fasterxml/jackson/databind/Module.java b/src/main/java/com/fasterxml/jackson/databind/Module.java
index 1fe60963e..d20c1a8c2 100644
--- a/src/main/java/com/fasterxml/jackson/databind/Module.java
+++ b/src/main/java/com/fasterxml/jackson/databind/Module.java
@@ -3,6 +3,7 @@ package com.fasterxml.jackson.databind;
 import java.util.Collection;
 
 import com.fasterxml.jackson.core.*;
+import com.fasterxml.jackson.databind.cfg.DeserializationFeature;
 import com.fasterxml.jackson.databind.cfg.MutableConfigOverride;
 import com.fasterxml.jackson.databind.deser.BeanDeserializerModifier;
 import com.fasterxml.jackson.databind.deser.DeserializationProblemHandler;
diff --git a/src/main/java/com/fasterxml/jackson/databind/ObjectMapper.java b/src/main/java/com/fasterxml/jackson/databind/ObjectMapper.java
index a049ae4b1..1db953a09 100644
--- a/src/main/java/com/fasterxml/jackson/databind/ObjectMapper.java
+++ b/src/main/java/com/fasterxml/jackson/databind/ObjectMapper.java
@@ -24,7 +24,7 @@ import com.fasterxml.jackson.databind.introspect.*;
 import com.fasterxml.jackson.databind.jsonFormatVisitors.JsonFormatVisitorWrapper;
 import com.fasterxml.jackson.databind.jsontype.*;
 import com.fasterxml.jackson.databind.jsontype.impl.StdSubtypeResolver;
-import com.fasterxml.jackson.databind.jsontype.impl.StdTypeResolverBuilder;
+import com.fasterxml.jackson.databind.jsontype.StdTypeResolverBuilder;
 import com.fasterxml.jackson.databind.node.*;
 import com.fasterxml.jackson.databind.ser.*;
 import com.fasterxml.jackson.databind.type.*;
diff --git a/src/main/java/com/fasterxml/jackson/databind/ObjectReader.java b/src/main/java/com/fasterxml/jackson/databind/ObjectReader.java
index d313c4207..a67e18fce 100644
--- a/src/main/java/com/fasterxml/jackson/databind/ObjectReader.java
+++ b/src/main/java/com/fasterxml/jackson/databind/ObjectReader.java
@@ -13,6 +13,7 @@ import com.fasterxml.jackson.core.type.ResolvedType;
 import com.fasterxml.jackson.core.type.TypeReference;
 
 import com.fasterxml.jackson.databind.cfg.ContextAttributes;
+import com.fasterxml.jackson.databind.cfg.DeserializationFeature;
 import com.fasterxml.jackson.databind.deser.DataFormatReaders;
 import com.fasterxml.jackson.databind.deser.DefaultDeserializationContext;
 import com.fasterxml.jackson.databind.deser.DeserializationProblemHandler;
diff --git a/src/main/java/com/fasterxml/jackson/databind/SerializationFeature.java b/src/main/java/com/fasterxml/jackson/databind/SerializationFeature.java
index 1b46dc073..9686b408a 100644
--- a/src/main/java/com/fasterxml/jackson/databind/SerializationFeature.java
+++ b/src/main/java/com/fasterxml/jackson/databind/SerializationFeature.java
@@ -1,6 +1,7 @@
 package com.fasterxml.jackson.databind;
 
 import com.fasterxml.jackson.databind.cfg.ConfigFeature;
+import com.fasterxml.jackson.databind.cfg.DeserializationFeature;
 
 /**
  * Enumeration that defines simple on/off features that affect
diff --git a/src/main/java/com/fasterxml/jackson/databind/DeserializationFeature.java b/src/main/java/com/fasterxml/jackson/databind/cfg/DeserializationFeature.java
similarity index 97%
rename from src/main/java/com/fasterxml/jackson/databind/DeserializationFeature.java
rename to src/main/java/com/fasterxml/jackson/databind/cfg/DeserializationFeature.java
index 5fd5ca48e..2c5b48c8c 100644
--- a/src/main/java/com/fasterxml/jackson/databind/DeserializationFeature.java
+++ b/src/main/java/com/fasterxml/jackson/databind/cfg/DeserializationFeature.java
@@ -1,6 +1,12 @@
-package com.fasterxml.jackson.databind;
+package com.fasterxml.jackson.databind.cfg;
 
-import com.fasterxml.jackson.databind.cfg.ConfigFeature;
+import com.fasterxml.jackson.databind.DeserializationContext;
+import com.fasterxml.jackson.databind.JsonDeserializer;
+import com.fasterxml.jackson.databind.JsonMappingException;
+import com.fasterxml.jackson.databind.MapperFeature;
+import com.fasterxml.jackson.databind.ObjectMapper;
+import com.fasterxml.jackson.databind.ObjectReader;
+import com.fasterxml.jackson.databind.SerializationFeature;
 
 /**
  * Enumeration that defines simple on/off features that affect
@@ -485,18 +491,18 @@ public enum DeserializationFeature implements ConfigFeature
 
     private final boolean _defaultState;
     private final int _mask;
-    
-    private DeserializationFeature(boolean defaultState) {
-        _defaultState = defaultState;
-        _mask = (1 << ordinal());
-    }
-
-    @Override
-    public boolean enabledByDefault() { return _defaultState; }
 
     @Override
     public int getMask() { return _mask; }
 
     @Override
     public boolean enabledIn(int flags) { return (flags & _mask) != 0; }
+
+    @Override
+    public boolean enabledByDefault() { return _defaultState; }
+
+    private DeserializationFeature(boolean defaultState) {
+        _defaultState = defaultState;
+        _mask = (1 << ordinal());
+    }
 }
diff --git a/src/main/java/com/fasterxml/jackson/databind/deser/BeanDeserializerBase.java b/src/main/java/com/fasterxml/jackson/databind/deser/BeanDeserializerBase.java
index 6ce41f783..766b872eb 100644
--- a/src/main/java/com/fasterxml/jackson/databind/deser/BeanDeserializerBase.java
+++ b/src/main/java/com/fasterxml/jackson/databind/deser/BeanDeserializerBase.java
@@ -11,6 +11,7 @@ import com.fasterxml.jackson.core.*;
 import com.fasterxml.jackson.core.JsonParser.NumberType;
 
 import com.fasterxml.jackson.databind.*;
+import com.fasterxml.jackson.databind.cfg.DeserializationFeature;
 import com.fasterxml.jackson.databind.deser.impl.*;
 import com.fasterxml.jackson.databind.deser.std.StdDelegatingDeserializer;
 import com.fasterxml.jackson.databind.deser.std.StdDeserializer;
diff --git a/src/main/java/com/fasterxml/jackson/databind/deser/DefaultDeserializationContext.java b/src/main/java/com/fasterxml/jackson/databind/deser/DefaultDeserializationContext.java
index cdc90ed2e..9190dcb1a 100644
--- a/src/main/java/com/fasterxml/jackson/databind/deser/DefaultDeserializationContext.java
+++ b/src/main/java/com/fasterxml/jackson/databind/deser/DefaultDeserializationContext.java
@@ -10,6 +10,7 @@ import com.fasterxml.jackson.annotation.ObjectIdGenerator.IdKey;
 import com.fasterxml.jackson.core.JsonParser;
 
 import com.fasterxml.jackson.databind.*;
+import com.fasterxml.jackson.databind.cfg.DeserializationFeature;
 import com.fasterxml.jackson.databind.cfg.HandlerInstantiator;
 import com.fasterxml.jackson.databind.deser.impl.ReadableObjectId;
 import com.fasterxml.jackson.databind.deser.impl.ReadableObjectId.Referring;
diff --git a/src/main/java/com/fasterxml/jackson/databind/deser/DeserializationProblemHandler.java b/src/main/java/com/fasterxml/jackson/databind/deser/DeserializationProblemHandler.java
index 38b87051b..2bbc7e094 100644
--- a/src/main/java/com/fasterxml/jackson/databind/deser/DeserializationProblemHandler.java
+++ b/src/main/java/com/fasterxml/jackson/databind/deser/DeserializationProblemHandler.java
@@ -9,6 +9,7 @@ import com.fasterxml.jackson.databind.DeserializationContext;
 import com.fasterxml.jackson.databind.JavaType;
 import com.fasterxml.jackson.databind.JsonDeserializer;
 import com.fasterxml.jackson.databind.ObjectMapper;
+import com.fasterxml.jackson.databind.cfg.DeserializationFeature;
 import com.fasterxml.jackson.databind.jsontype.TypeIdResolver;
 
 /**
@@ -52,7 +53,7 @@ public abstract class DeserializationProblemHandler
      *  parser.skipChildren();
      *</pre>
      *<p>
-     * Note: {@link com.fasterxml.jackson.databind.DeserializationFeature#FAIL_ON_UNKNOWN_PROPERTIES})
+     * Note: {@link DeserializationFeature#FAIL_ON_UNKNOWN_PROPERTIES})
      * takes effect only <b>after</b> handler is called, and only
      * if handler did <b>not</b> handle the problem.
      *
diff --git a/src/main/java/com/fasterxml/jackson/databind/deser/ValueInstantiator.java b/src/main/java/com/fasterxml/jackson/databind/deser/ValueInstantiator.java
index a7a695168..683788cfb 100644
--- a/src/main/java/com/fasterxml/jackson/databind/deser/ValueInstantiator.java
+++ b/src/main/java/com/fasterxml/jackson/databind/deser/ValueInstantiator.java
@@ -3,6 +3,7 @@ package com.fasterxml.jackson.databind.deser;
 import java.io.IOException;
 
 import com.fasterxml.jackson.databind.*;
+import com.fasterxml.jackson.databind.cfg.DeserializationFeature;
 import com.fasterxml.jackson.databind.deser.impl.PropertyValueBuffer;
 import com.fasterxml.jackson.databind.introspect.AnnotatedParameter;
 import com.fasterxml.jackson.databind.introspect.AnnotatedWithParams;
diff --git a/src/main/java/com/fasterxml/jackson/databind/deser/impl/BeanAsArrayBuilderDeserializer.java b/src/main/java/com/fasterxml/jackson/databind/deser/impl/BeanAsArrayBuilderDeserializer.java
index 0dbc50da3..f921467e8 100644
--- a/src/main/java/com/fasterxml/jackson/databind/deser/impl/BeanAsArrayBuilderDeserializer.java
+++ b/src/main/java/com/fasterxml/jackson/databind/deser/impl/BeanAsArrayBuilderDeserializer.java
@@ -5,6 +5,7 @@ import java.util.Set;
 
 import com.fasterxml.jackson.core.*;
 import com.fasterxml.jackson.databind.*;
+import com.fasterxml.jackson.databind.cfg.DeserializationFeature;
 import com.fasterxml.jackson.databind.deser.*;
 import com.fasterxml.jackson.databind.introspect.AnnotatedMethod;
 import com.fasterxml.jackson.databind.util.NameTransformer;
diff --git a/src/main/java/com/fasterxml/jackson/databind/deser/impl/BeanAsArrayDeserializer.java b/src/main/java/com/fasterxml/jackson/databind/deser/impl/BeanAsArrayDeserializer.java
index 2b39004b6..f6b1f4ef3 100644
--- a/src/main/java/com/fasterxml/jackson/databind/deser/impl/BeanAsArrayDeserializer.java
+++ b/src/main/java/com/fasterxml/jackson/databind/deser/impl/BeanAsArrayDeserializer.java
@@ -6,6 +6,7 @@ import java.util.Set;
 import com.fasterxml.jackson.core.JsonParser;
 import com.fasterxml.jackson.core.JsonToken;
 import com.fasterxml.jackson.databind.*;
+import com.fasterxml.jackson.databind.cfg.DeserializationFeature;
 import com.fasterxml.jackson.databind.deser.*;
 import com.fasterxml.jackson.databind.util.NameTransformer;
 
diff --git a/src/main/java/com/fasterxml/jackson/databind/deser/impl/BeanPropertyMap.java b/src/main/java/com/fasterxml/jackson/databind/deser/impl/BeanPropertyMap.java
index b015bb5a2..f53fa2ece 100644
--- a/src/main/java/com/fasterxml/jackson/databind/deser/impl/BeanPropertyMap.java
+++ b/src/main/java/com/fasterxml/jackson/databind/deser/impl/BeanPropertyMap.java
@@ -7,7 +7,7 @@ import java.util.*;
 import com.fasterxml.jackson.core.JsonParser;
 import com.fasterxml.jackson.core.JsonProcessingException;
 import com.fasterxml.jackson.databind.DeserializationContext;
-import com.fasterxml.jackson.databind.DeserializationFeature;
+import com.fasterxml.jackson.databind.cfg.DeserializationFeature;
 import com.fasterxml.jackson.databind.JsonDeserializer;
 import com.fasterxml.jackson.databind.JsonMappingException;
 import com.fasterxml.jackson.databind.PropertyName;
diff --git a/src/main/java/com/fasterxml/jackson/databind/deser/impl/ExternalTypeHandler.java b/src/main/java/com/fasterxml/jackson/databind/deser/impl/ExternalTypeHandler.java
index 1be53a2fe..5d6c76105 100644
--- a/src/main/java/com/fasterxml/jackson/databind/deser/impl/ExternalTypeHandler.java
+++ b/src/main/java/com/fasterxml/jackson/databind/deser/impl/ExternalTypeHandler.java
@@ -5,6 +5,7 @@ import java.util.*;
 
 import com.fasterxml.jackson.core.*;
 import com.fasterxml.jackson.databind.*;
+import com.fasterxml.jackson.databind.cfg.DeserializationFeature;
 import com.fasterxml.jackson.databind.deser.SettableBeanProperty;
 import com.fasterxml.jackson.databind.jsontype.TypeDeserializer;
 import com.fasterxml.jackson.databind.util.TokenBuffer;
diff --git a/src/main/java/com/fasterxml/jackson/databind/deser/impl/PropertyValueBuffer.java b/src/main/java/com/fasterxml/jackson/databind/deser/impl/PropertyValueBuffer.java
index 76e0b2b1b..bb22ec261 100644
--- a/src/main/java/com/fasterxml/jackson/databind/deser/impl/PropertyValueBuffer.java
+++ b/src/main/java/com/fasterxml/jackson/databind/deser/impl/PropertyValueBuffer.java
@@ -5,7 +5,7 @@ import java.util.BitSet;
 
 import com.fasterxml.jackson.core.JsonParser;
 import com.fasterxml.jackson.databind.DeserializationContext;
-import com.fasterxml.jackson.databind.DeserializationFeature;
+import com.fasterxml.jackson.databind.cfg.DeserializationFeature;
 import com.fasterxml.jackson.databind.JsonDeserializer;
 import com.fasterxml.jackson.databind.JsonMappingException;
 import com.fasterxml.jackson.databind.deser.SettableAnyProperty;
diff --git a/src/main/java/com/fasterxml/jackson/databind/deser/std/CollectionDeserializer.java b/src/main/java/com/fasterxml/jackson/databind/deser/std/CollectionDeserializer.java
index c255d896f..eab042dfb 100644
--- a/src/main/java/com/fasterxml/jackson/databind/deser/std/CollectionDeserializer.java
+++ b/src/main/java/com/fasterxml/jackson/databind/deser/std/CollectionDeserializer.java
@@ -9,9 +9,9 @@ import com.fasterxml.jackson.core.*;
 
 import com.fasterxml.jackson.databind.*;
 import com.fasterxml.jackson.databind.annotation.JacksonStdImpl;
+import com.fasterxml.jackson.databind.cfg.DeserializationFeature;
 import com.fasterxml.jackson.databind.deser.*;
 import com.fasterxml.jackson.databind.deser.impl.ReadableObjectId.Referring;
-import com.fasterxml.jackson.databind.deser.std.ContainerDeserializerBase;
 import com.fasterxml.jackson.databind.jsontype.TypeDeserializer;
 import com.fasterxml.jackson.databind.util.ClassUtil;
 
diff --git a/src/main/java/com/fasterxml/jackson/databind/deser/std/EnumDeserializer.java b/src/main/java/com/fasterxml/jackson/databind/deser/std/EnumDeserializer.java
index c697e1ce8..724b6268d 100644
--- a/src/main/java/com/fasterxml/jackson/databind/deser/std/EnumDeserializer.java
+++ b/src/main/java/com/fasterxml/jackson/databind/deser/std/EnumDeserializer.java
@@ -8,6 +8,7 @@ import com.fasterxml.jackson.core.*;
 
 import com.fasterxml.jackson.databind.*;
 import com.fasterxml.jackson.databind.annotation.JacksonStdImpl;
+import com.fasterxml.jackson.databind.cfg.DeserializationFeature;
 import com.fasterxml.jackson.databind.deser.ContextualDeserializer;
 import com.fasterxml.jackson.databind.deser.SettableBeanProperty;
 import com.fasterxml.jackson.databind.deser.ValueInstantiator;
diff --git a/src/main/java/com/fasterxml/jackson/databind/deser/std/EnumMapDeserializer.java b/src/main/java/com/fasterxml/jackson/databind/deser/std/EnumMapDeserializer.java
index f61b17c1c..6117cabb5 100644
--- a/src/main/java/com/fasterxml/jackson/databind/deser/std/EnumMapDeserializer.java
+++ b/src/main/java/com/fasterxml/jackson/databind/deser/std/EnumMapDeserializer.java
@@ -5,6 +5,7 @@ import java.util.*;
 
 import com.fasterxml.jackson.core.*;
 import com.fasterxml.jackson.databind.*;
+import com.fasterxml.jackson.databind.cfg.DeserializationFeature;
 import com.fasterxml.jackson.databind.deser.ContextualDeserializer;
 import com.fasterxml.jackson.databind.deser.NullValueProvider;
 import com.fasterxml.jackson.databind.deser.ResolvableDeserializer;
diff --git a/src/main/java/com/fasterxml/jackson/databind/deser/std/EnumSetDeserializer.java b/src/main/java/com/fasterxml/jackson/databind/deser/std/EnumSetDeserializer.java
index 08ceee8c1..e33680468 100644
--- a/src/main/java/com/fasterxml/jackson/databind/deser/std/EnumSetDeserializer.java
+++ b/src/main/java/com/fasterxml/jackson/databind/deser/std/EnumSetDeserializer.java
@@ -6,6 +6,7 @@ import java.util.*;
 import com.fasterxml.jackson.annotation.JsonFormat;
 import com.fasterxml.jackson.core.*;
 import com.fasterxml.jackson.databind.*;
+import com.fasterxml.jackson.databind.cfg.DeserializationFeature;
 import com.fasterxml.jackson.databind.deser.ContextualDeserializer;
 import com.fasterxml.jackson.databind.jsontype.TypeDeserializer;
 
diff --git a/src/main/java/com/fasterxml/jackson/databind/deser/std/FactoryBasedEnumDeserializer.java b/src/main/java/com/fasterxml/jackson/databind/deser/std/FactoryBasedEnumDeserializer.java
index 8802f5a70..7d3fcba86 100644
--- a/src/main/java/com/fasterxml/jackson/databind/deser/std/FactoryBasedEnumDeserializer.java
+++ b/src/main/java/com/fasterxml/jackson/databind/deser/std/FactoryBasedEnumDeserializer.java
@@ -7,6 +7,7 @@ import com.fasterxml.jackson.core.JsonProcessingException;
 import com.fasterxml.jackson.core.JsonToken;
 
 import com.fasterxml.jackson.databind.*;
+import com.fasterxml.jackson.databind.cfg.DeserializationFeature;
 import com.fasterxml.jackson.databind.deser.ContextualDeserializer;
 import com.fasterxml.jackson.databind.deser.SettableBeanProperty;
 import com.fasterxml.jackson.databind.deser.ValueInstantiator;
diff --git a/src/main/java/com/fasterxml/jackson/databind/deser/std/FromStringDeserializer.java b/src/main/java/com/fasterxml/jackson/databind/deser/std/FromStringDeserializer.java
index 68187c130..62cdb8116 100644
--- a/src/main/java/com/fasterxml/jackson/databind/deser/std/FromStringDeserializer.java
+++ b/src/main/java/com/fasterxml/jackson/databind/deser/std/FromStringDeserializer.java
@@ -15,6 +15,7 @@ import java.util.regex.Pattern;
 import com.fasterxml.jackson.core.*;
 import com.fasterxml.jackson.core.util.VersionUtil;
 import com.fasterxml.jackson.databind.*;
+import com.fasterxml.jackson.databind.cfg.DeserializationFeature;
 import com.fasterxml.jackson.databind.exc.InvalidFormatException;
 import com.fasterxml.jackson.databind.util.ClassUtil;
 
diff --git a/src/main/java/com/fasterxml/jackson/databind/deser/std/JsonNodeDeserializer.java b/src/main/java/com/fasterxml/jackson/databind/deser/std/JsonNodeDeserializer.java
index 01937fe8b..d1b7c8bea 100644
--- a/src/main/java/com/fasterxml/jackson/databind/deser/std/JsonNodeDeserializer.java
+++ b/src/main/java/com/fasterxml/jackson/databind/deser/std/JsonNodeDeserializer.java
@@ -4,6 +4,7 @@ import java.io.IOException;
 
 import com.fasterxml.jackson.core.*;
 import com.fasterxml.jackson.databind.*;
+import com.fasterxml.jackson.databind.cfg.DeserializationFeature;
 import com.fasterxml.jackson.databind.jsontype.TypeDeserializer;
 import com.fasterxml.jackson.databind.node.*;
 import com.fasterxml.jackson.databind.util.RawValue;
diff --git a/src/main/java/com/fasterxml/jackson/databind/deser/std/NumberDeserializers.java b/src/main/java/com/fasterxml/jackson/databind/deser/std/NumberDeserializers.java
index 35ec9d4da..1eb4cc6ca 100644
--- a/src/main/java/com/fasterxml/jackson/databind/deser/std/NumberDeserializers.java
+++ b/src/main/java/com/fasterxml/jackson/databind/deser/std/NumberDeserializers.java
@@ -9,6 +9,7 @@ import com.fasterxml.jackson.core.*;
 import com.fasterxml.jackson.core.io.NumberInput;
 import com.fasterxml.jackson.databind.*;
 import com.fasterxml.jackson.databind.annotation.JacksonStdImpl;
+import com.fasterxml.jackson.databind.cfg.DeserializationFeature;
 import com.fasterxml.jackson.databind.jsontype.TypeDeserializer;
 import com.fasterxml.jackson.databind.util.AccessPattern;
 
diff --git a/src/main/java/com/fasterxml/jackson/databind/deser/std/ObjectArrayDeserializer.java b/src/main/java/com/fasterxml/jackson/databind/deser/std/ObjectArrayDeserializer.java
index 017317d5d..d25adcaee 100644
--- a/src/main/java/com/fasterxml/jackson/databind/deser/std/ObjectArrayDeserializer.java
+++ b/src/main/java/com/fasterxml/jackson/databind/deser/std/ObjectArrayDeserializer.java
@@ -9,6 +9,7 @@ import com.fasterxml.jackson.core.*;
 
 import com.fasterxml.jackson.databind.*;
 import com.fasterxml.jackson.databind.annotation.JacksonStdImpl;
+import com.fasterxml.jackson.databind.cfg.DeserializationFeature;
 import com.fasterxml.jackson.databind.deser.ContextualDeserializer;
 import com.fasterxml.jackson.databind.deser.NullValueProvider;
 import com.fasterxml.jackson.databind.jsontype.TypeDeserializer;
diff --git a/src/main/java/com/fasterxml/jackson/databind/deser/std/PrimitiveArrayDeserializers.java b/src/main/java/com/fasterxml/jackson/databind/deser/std/PrimitiveArrayDeserializers.java
index 175db71e0..5e4f4683c 100644
--- a/src/main/java/com/fasterxml/jackson/databind/deser/std/PrimitiveArrayDeserializers.java
+++ b/src/main/java/com/fasterxml/jackson/databind/deser/std/PrimitiveArrayDeserializers.java
@@ -9,6 +9,7 @@ import com.fasterxml.jackson.annotation.Nulls;
 import com.fasterxml.jackson.core.*;
 import com.fasterxml.jackson.databind.*;
 import com.fasterxml.jackson.databind.annotation.JacksonStdImpl;
+import com.fasterxml.jackson.databind.cfg.DeserializationFeature;
 import com.fasterxml.jackson.databind.deser.ContextualDeserializer;
 import com.fasterxml.jackson.databind.deser.NullValueProvider;
 import com.fasterxml.jackson.databind.deser.impl.NullsConstantProvider;
diff --git a/src/main/java/com/fasterxml/jackson/databind/deser/std/StackTraceElementDeserializer.java b/src/main/java/com/fasterxml/jackson/databind/deser/std/StackTraceElementDeserializer.java
index fcfba1029..af44ab9be 100644
--- a/src/main/java/com/fasterxml/jackson/databind/deser/std/StackTraceElementDeserializer.java
+++ b/src/main/java/com/fasterxml/jackson/databind/deser/std/StackTraceElementDeserializer.java
@@ -6,7 +6,7 @@ import com.fasterxml.jackson.core.JsonParser;
 import com.fasterxml.jackson.core.JsonToken;
 
 import com.fasterxml.jackson.databind.DeserializationContext;
-import com.fasterxml.jackson.databind.DeserializationFeature;
+import com.fasterxml.jackson.databind.cfg.DeserializationFeature;
 
 public class StackTraceElementDeserializer
     extends StdScalarDeserializer<StackTraceElement>
diff --git a/src/main/java/com/fasterxml/jackson/databind/deser/std/StdDeserializer.java b/src/main/java/com/fasterxml/jackson/databind/deser/std/StdDeserializer.java
index 5d0133fe0..1a955c1db 100644
--- a/src/main/java/com/fasterxml/jackson/databind/deser/std/StdDeserializer.java
+++ b/src/main/java/com/fasterxml/jackson/databind/deser/std/StdDeserializer.java
@@ -9,6 +9,7 @@ import com.fasterxml.jackson.core.*;
 import com.fasterxml.jackson.core.io.NumberInput;
 import com.fasterxml.jackson.databind.*;
 import com.fasterxml.jackson.databind.annotation.JacksonStdImpl;
+import com.fasterxml.jackson.databind.cfg.DeserializationFeature;
 import com.fasterxml.jackson.databind.deser.BeanDeserializerBase;
 import com.fasterxml.jackson.databind.deser.NullValueProvider;
 import com.fasterxml.jackson.databind.deser.SettableBeanProperty;
diff --git a/src/main/java/com/fasterxml/jackson/databind/deser/std/StdKeyDeserializer.java b/src/main/java/com/fasterxml/jackson/databind/deser/std/StdKeyDeserializer.java
index 29a944bc0..9a890415e 100644
--- a/src/main/java/com/fasterxml/jackson/databind/deser/std/StdKeyDeserializer.java
+++ b/src/main/java/com/fasterxml/jackson/databind/deser/std/StdKeyDeserializer.java
@@ -13,6 +13,7 @@ import com.fasterxml.jackson.core.JsonProcessingException;
 import com.fasterxml.jackson.core.io.NumberInput;
 import com.fasterxml.jackson.databind.*;
 import com.fasterxml.jackson.databind.annotation.JacksonStdImpl;
+import com.fasterxml.jackson.databind.cfg.DeserializationFeature;
 import com.fasterxml.jackson.databind.introspect.AnnotatedMethod;
 import com.fasterxml.jackson.databind.util.ClassUtil;
 import com.fasterxml.jackson.databind.util.EnumResolver;
diff --git a/src/main/java/com/fasterxml/jackson/databind/deser/std/StringArrayDeserializer.java b/src/main/java/com/fasterxml/jackson/databind/deser/std/StringArrayDeserializer.java
index a348a4019..254f69827 100644
--- a/src/main/java/com/fasterxml/jackson/databind/deser/std/StringArrayDeserializer.java
+++ b/src/main/java/com/fasterxml/jackson/databind/deser/std/StringArrayDeserializer.java
@@ -6,6 +6,7 @@ import com.fasterxml.jackson.annotation.JsonFormat;
 import com.fasterxml.jackson.core.*;
 import com.fasterxml.jackson.databind.*;
 import com.fasterxml.jackson.databind.annotation.JacksonStdImpl;
+import com.fasterxml.jackson.databind.cfg.DeserializationFeature;
 import com.fasterxml.jackson.databind.deser.ContextualDeserializer;
 import com.fasterxml.jackson.databind.deser.NullValueProvider;
 import com.fasterxml.jackson.databind.deser.impl.NullsConstantProvider;
diff --git a/src/main/java/com/fasterxml/jackson/databind/deser/std/StringCollectionDeserializer.java b/src/main/java/com/fasterxml/jackson/databind/deser/std/StringCollectionDeserializer.java
index 321df6f29..71bbfec46 100644
--- a/src/main/java/com/fasterxml/jackson/databind/deser/std/StringCollectionDeserializer.java
+++ b/src/main/java/com/fasterxml/jackson/databind/deser/std/StringCollectionDeserializer.java
@@ -7,6 +7,7 @@ import com.fasterxml.jackson.annotation.JsonFormat;
 import com.fasterxml.jackson.core.*;
 import com.fasterxml.jackson.databind.*;
 import com.fasterxml.jackson.databind.annotation.JacksonStdImpl;
+import com.fasterxml.jackson.databind.cfg.DeserializationFeature;
 import com.fasterxml.jackson.databind.deser.ContextualDeserializer;
 import com.fasterxml.jackson.databind.deser.NullValueProvider;
 import com.fasterxml.jackson.databind.deser.ValueInstantiator;
diff --git a/src/main/java/com/fasterxml/jackson/databind/deser/std/UntypedObjectDeserializer.java b/src/main/java/com/fasterxml/jackson/databind/deser/std/UntypedObjectDeserializer.java
index 67be23847..796e3e235 100644
--- a/src/main/java/com/fasterxml/jackson/databind/deser/std/UntypedObjectDeserializer.java
+++ b/src/main/java/com/fasterxml/jackson/databind/deser/std/UntypedObjectDeserializer.java
@@ -7,7 +7,7 @@ import com.fasterxml.jackson.core.*;
 import com.fasterxml.jackson.databind.BeanProperty;
 import com.fasterxml.jackson.databind.DeserializationConfig;
 import com.fasterxml.jackson.databind.DeserializationContext;
-import com.fasterxml.jackson.databind.DeserializationFeature;
+import com.fasterxml.jackson.databind.cfg.DeserializationFeature;
 import com.fasterxml.jackson.databind.JavaType;
 import com.fasterxml.jackson.databind.JsonDeserializer;
 import com.fasterxml.jackson.databind.JsonMappingException;
diff --git a/src/main/java/com/fasterxml/jackson/databind/introspect/JacksonAnnotationIntrospector.java b/src/main/java/com/fasterxml/jackson/databind/introspect/JacksonAnnotationIntrospector.java
index 823deb622..b58ea92c9 100644
--- a/src/main/java/com/fasterxml/jackson/databind/introspect/JacksonAnnotationIntrospector.java
+++ b/src/main/java/com/fasterxml/jackson/databind/introspect/JacksonAnnotationIntrospector.java
@@ -14,7 +14,7 @@ import com.fasterxml.jackson.databind.ext.Java7Support;
 import com.fasterxml.jackson.databind.jsontype.NamedType;
 import com.fasterxml.jackson.databind.jsontype.TypeIdResolver;
 import com.fasterxml.jackson.databind.jsontype.TypeResolverBuilder;
-import com.fasterxml.jackson.databind.jsontype.impl.StdTypeResolverBuilder;
+import com.fasterxml.jackson.databind.jsontype.StdTypeResolverBuilder;
 import com.fasterxml.jackson.databind.ser.BeanPropertyWriter;
 import com.fasterxml.jackson.databind.ser.VirtualBeanPropertyWriter;
 import com.fasterxml.jackson.databind.ser.impl.AttributePropertyWriter;
diff --git a/src/main/java/com/fasterxml/jackson/databind/jsontype/impl/StdTypeResolverBuilder.java b/src/main/java/com/fasterxml/jackson/databind/jsontype/StdTypeResolverBuilder.java
similarity index 90%
rename from src/main/java/com/fasterxml/jackson/databind/jsontype/impl/StdTypeResolverBuilder.java
rename to src/main/java/com/fasterxml/jackson/databind/jsontype/StdTypeResolverBuilder.java
index 17d5ec72f..cbdafbd2b 100644
--- a/src/main/java/com/fasterxml/jackson/databind/jsontype/impl/StdTypeResolverBuilder.java
+++ b/src/main/java/com/fasterxml/jackson/databind/jsontype/StdTypeResolverBuilder.java
@@ -1,4 +1,4 @@
-package com.fasterxml.jackson.databind.jsontype.impl;
+package com.fasterxml.jackson.databind.jsontype;
 
 import java.util.Collection;
 
@@ -7,7 +7,18 @@ import com.fasterxml.jackson.annotation.JsonTypeInfo;
 import com.fasterxml.jackson.databind.*;
 import com.fasterxml.jackson.databind.annotation.NoClass;
 import com.fasterxml.jackson.databind.cfg.MapperConfig;
-import com.fasterxml.jackson.databind.jsontype.*;
+import com.fasterxml.jackson.databind.jsontype.impl.AsArrayTypeDeserializer;
+import com.fasterxml.jackson.databind.jsontype.impl.AsArrayTypeSerializer;
+import com.fasterxml.jackson.databind.jsontype.impl.AsExistingPropertyTypeSerializer;
+import com.fasterxml.jackson.databind.jsontype.impl.AsExternalTypeDeserializer;
+import com.fasterxml.jackson.databind.jsontype.impl.AsExternalTypeSerializer;
+import com.fasterxml.jackson.databind.jsontype.impl.AsPropertyTypeDeserializer;
+import com.fasterxml.jackson.databind.jsontype.impl.AsPropertyTypeSerializer;
+import com.fasterxml.jackson.databind.jsontype.impl.AsWrapperTypeDeserializer;
+import com.fasterxml.jackson.databind.jsontype.impl.AsWrapperTypeSerializer;
+import com.fasterxml.jackson.databind.jsontype.impl.ClassNameIdResolver;
+import com.fasterxml.jackson.databind.jsontype.impl.MinimalClassNameIdResolver;
+import com.fasterxml.jackson.databind.jsontype.impl.TypeNameIdResolver;
 
 /**
  * Default {@link TypeResolverBuilder} implementation.
@@ -44,22 +55,56 @@ public class StdTypeResolverBuilder
     /**********************************************************
      */
 
-    public StdTypeResolverBuilder() { }
+    // as per [#368]
+    // removed when fix [#528]
+    //private IllegalArgumentException _noExisting() {
+    //    return new IllegalArgumentException("Inclusion type "+_includeAs+" not yet supported");
+    //}
+
+    /*
+    /**********************************************************
+    /* Construction, configuration
+    /**********************************************************
+     */
+
+    /*
+    /**********************************************************
+    /* Accessors
+    /**********************************************************
+     */
+
+    /*
+    /**********************************************************
+    /* Internal methods
+    /**********************************************************
+     */
 
     /**
-     * @since 2.9
+     * Method for constructing an instance with specified type property name
+     * (property name to use for type id when using "as-property" inclusion).
      */
-    protected StdTypeResolverBuilder(JsonTypeInfo.Id idType,
-            JsonTypeInfo.As idAs, String propName) {
-        _idType = idType;
-        _includeAs = idAs;
-        _typeProperty = propName;
+    @Override
+    public StdTypeResolverBuilder typeProperty(String typeIdPropName) {
+        // ok to have null/empty; will restore to use defaults
+        if (typeIdPropName == null || typeIdPropName.length() == 0) {
+            typeIdPropName = _idType.getDefaultPropertyName();
+        }
+        _typeProperty = typeIdPropName;
+        return this;
+    }
+
+    @Override
+    public StdTypeResolverBuilder typeIdVisibility(boolean isVisible) {
+        _typeIdVisible = isVisible;
+        return this;
     }
 
     public static StdTypeResolverBuilder noTypeInfoBuilder() {
         return new StdTypeResolverBuilder().init(JsonTypeInfo.Id.NONE, null);
     }
 
+    public boolean isTypeIdVisible() { return _typeIdVisible; }
+
     @Override
     public StdTypeResolverBuilder init(JsonTypeInfo.Id idType, TypeIdResolver idRes)
     {
@@ -74,6 +119,50 @@ public class StdTypeResolverBuilder
         return this;
     }
 
+    @Override
+    public StdTypeResolverBuilder inclusion(JsonTypeInfo.As includeAs) {
+        if (includeAs == null) {
+            throw new IllegalArgumentException("includeAs cannot be null");
+        }
+        _includeAs = includeAs;
+        return this;
+    }
+
+    /**
+     * Helper method that will either return configured custom
+     * type id resolver, or construct a standard resolver
+     * given configuration.
+     */
+    protected TypeIdResolver idResolver(MapperConfig<?> config,
+            JavaType baseType, Collection<NamedType> subtypes, boolean forSer, boolean forDeser)
+    {
+        // Custom id resolver?
+        if (_customIdResolver != null) { return _customIdResolver; }
+        if (_idType == null) throw new IllegalStateException("Cannot build, 'init()' not yet called");
+        switch (_idType) {
+        case CLASS:
+            return new ClassNameIdResolver(baseType, config.getTypeFactory());
+        case MINIMAL_CLASS:
+            return new MinimalClassNameIdResolver(baseType, config.getTypeFactory());
+        case NAME:
+            return TypeNameIdResolver.construct(config, baseType, subtypes, forSer, forDeser);
+        case NONE: // hmmh. should never get this far with 'none'
+            return null;
+        case CUSTOM: // need custom resolver...
+        }
+        throw new IllegalStateException("Do not know how to construct standard type id resolver for idType: "+_idType);
+    }
+
+    public String getTypeProperty() { return _typeProperty; }
+
+    @Override public Class<?> getDefaultImpl() { return _defaultImpl; }
+
+    @Override
+    public StdTypeResolverBuilder defaultImpl(Class<?> defaultImpl) {
+        _defaultImpl = defaultImpl;
+        return this;
+    }
+
     @Override
     public TypeSerializer buildTypeSerializer(SerializationConfig config,
             JavaType baseType, Collection<NamedType> subtypes)
@@ -101,12 +190,6 @@ public class StdTypeResolverBuilder
         throw new IllegalStateException("Do not know how to construct standard type serializer for inclusion type: "+_includeAs);
     }
 
-    // as per [#368]
-    // removed when fix [#528]
-    //private IllegalArgumentException _noExisting() {
-    //    return new IllegalArgumentException("Inclusion type "+_includeAs+" not yet supported");
-    //}
-
     @Override
     public TypeDeserializer buildTypeDeserializer(DeserializationConfig config,
             JavaType baseType, Collection<NamedType> subtypes)
@@ -176,86 +259,15 @@ public class StdTypeResolverBuilder
         throw new IllegalStateException("Do not know how to construct standard type serializer for inclusion type: "+_includeAs);
     }
 
-    /*
-    /**********************************************************
-    /* Construction, configuration
-    /**********************************************************
-     */
-
-    @Override
-    public StdTypeResolverBuilder inclusion(JsonTypeInfo.As includeAs) {
-        if (includeAs == null) {
-            throw new IllegalArgumentException("includeAs cannot be null");
-        }
-        _includeAs = includeAs;
-        return this;
-    }
-
-    /**
-     * Method for constructing an instance with specified type property name
-     * (property name to use for type id when using "as-property" inclusion).
-     */
-    @Override
-    public StdTypeResolverBuilder typeProperty(String typeIdPropName) {
-        // ok to have null/empty; will restore to use defaults
-        if (typeIdPropName == null || typeIdPropName.length() == 0) {
-            typeIdPropName = _idType.getDefaultPropertyName();
-        }
-        _typeProperty = typeIdPropName;
-        return this;
-    }
-
-    @Override
-    public StdTypeResolverBuilder defaultImpl(Class<?> defaultImpl) {
-        _defaultImpl = defaultImpl;
-        return this;
-    }
-
-    @Override
-    public StdTypeResolverBuilder typeIdVisibility(boolean isVisible) {
-        _typeIdVisible = isVisible;
-        return this;
-    }
-    
-    /*
-    /**********************************************************
-    /* Accessors
-    /**********************************************************
-     */
-
-    @Override public Class<?> getDefaultImpl() { return _defaultImpl; }
+    public StdTypeResolverBuilder() { }
 
-    public String getTypeProperty() { return _typeProperty; }
-    public boolean isTypeIdVisible() { return _typeIdVisible; }
-    
-    /*
-    /**********************************************************
-    /* Internal methods
-    /**********************************************************
-     */
-    
     /**
-     * Helper method that will either return configured custom
-     * type id resolver, or construct a standard resolver
-     * given configuration.
+     * @since 2.9
      */
-    protected TypeIdResolver idResolver(MapperConfig<?> config,
-            JavaType baseType, Collection<NamedType> subtypes, boolean forSer, boolean forDeser)
-    {
-        // Custom id resolver?
-        if (_customIdResolver != null) { return _customIdResolver; }
-        if (_idType == null) throw new IllegalStateException("Cannot build, 'init()' not yet called");
-        switch (_idType) {
-        case CLASS:
-            return new ClassNameIdResolver(baseType, config.getTypeFactory());
-        case MINIMAL_CLASS:
-            return new MinimalClassNameIdResolver(baseType, config.getTypeFactory());
-        case NAME:
-            return TypeNameIdResolver.construct(config, baseType, subtypes, forSer, forDeser);
-        case NONE: // hmmh. should never get this far with 'none'
-            return null;
-        case CUSTOM: // need custom resolver...
-        }
-        throw new IllegalStateException("Do not know how to construct standard type id resolver for idType: "+_idType);
+    protected StdTypeResolverBuilder(JsonTypeInfo.Id idType,
+            JsonTypeInfo.As idAs, String propName) {
+        _idType = idType;
+        _includeAs = idAs;
+        _typeProperty = propName;
     }
 }
diff --git a/src/main/java/com/fasterxml/jackson/databind/jsontype/impl/AsPropertyTypeDeserializer.java b/src/main/java/com/fasterxml/jackson/databind/jsontype/impl/AsPropertyTypeDeserializer.java
index 9bfab808b..9d4adbdb4 100644
--- a/src/main/java/com/fasterxml/jackson/databind/jsontype/impl/AsPropertyTypeDeserializer.java
+++ b/src/main/java/com/fasterxml/jackson/databind/jsontype/impl/AsPropertyTypeDeserializer.java
@@ -6,6 +6,7 @@ import com.fasterxml.jackson.annotation.JsonTypeInfo.As;
 import com.fasterxml.jackson.core.*;
 import com.fasterxml.jackson.core.util.JsonParserSequence;
 import com.fasterxml.jackson.databind.*;
+import com.fasterxml.jackson.databind.cfg.DeserializationFeature;
 import com.fasterxml.jackson.databind.jsontype.TypeDeserializer;
 import com.fasterxml.jackson.databind.jsontype.TypeIdResolver;
 import com.fasterxml.jackson.databind.util.TokenBuffer;
diff --git a/src/main/java/com/fasterxml/jackson/databind/jsontype/impl/TypeDeserializerBase.java b/src/main/java/com/fasterxml/jackson/databind/jsontype/impl/TypeDeserializerBase.java
index 2b8e79fdf..f3533fc2e 100644
--- a/src/main/java/com/fasterxml/jackson/databind/jsontype/impl/TypeDeserializerBase.java
+++ b/src/main/java/com/fasterxml/jackson/databind/jsontype/impl/TypeDeserializerBase.java
@@ -8,7 +8,7 @@ import com.fasterxml.jackson.annotation.JsonTypeInfo;
 import com.fasterxml.jackson.core.*;
 import com.fasterxml.jackson.databind.BeanProperty;
 import com.fasterxml.jackson.databind.DeserializationContext;
-import com.fasterxml.jackson.databind.DeserializationFeature;
+import com.fasterxml.jackson.databind.cfg.DeserializationFeature;
 import com.fasterxml.jackson.databind.JavaType;
 import com.fasterxml.jackson.databind.JsonDeserializer;
 import com.fasterxml.jackson.databind.deser.std.NullifyingDeserializer;
diff --git a/src/main/java/com/fasterxml/jackson/databind/util/TokenBuffer.java b/src/main/java/com/fasterxml/jackson/databind/util/TokenBuffer.java
index f31334e77..123342ac8 100644
--- a/src/main/java/com/fasterxml/jackson/databind/util/TokenBuffer.java
+++ b/src/main/java/com/fasterxml/jackson/databind/util/TokenBuffer.java
@@ -10,6 +10,7 @@ import com.fasterxml.jackson.core.base.ParserMinimalBase;
 import com.fasterxml.jackson.core.json.JsonWriteContext;
 import com.fasterxml.jackson.core.util.ByteArrayBuilder;
 import com.fasterxml.jackson.databind.*;
+import com.fasterxml.jackson.databind.cfg.DeserializationFeature;
 
 /**
  * Utility class used for efficient storage of {@link JsonToken}
diff --git a/src/test/java/com/fasterxml/jackson/databind/FullStreamReadTest.java b/src/test/java/com/fasterxml/jackson/databind/FullStreamReadTest.java
index 6bfa5cc94..157e70dc4 100644
--- a/src/test/java/com/fasterxml/jackson/databind/FullStreamReadTest.java
+++ b/src/test/java/com/fasterxml/jackson/databind/FullStreamReadTest.java
@@ -4,6 +4,7 @@ import java.util.*;
 
 import com.fasterxml.jackson.core.JsonParseException;
 import com.fasterxml.jackson.core.JsonParser;
+import com.fasterxml.jackson.databind.cfg.DeserializationFeature;
 import com.fasterxml.jackson.databind.exc.MismatchedInputException;
 
 public class FullStreamReadTest extends BaseMapTest
diff --git a/src/test/java/com/fasterxml/jackson/databind/ObjectMapperTest.java b/src/test/java/com/fasterxml/jackson/databind/ObjectMapperTest.java
index f59eabce6..04bbe7c87 100644
--- a/src/test/java/com/fasterxml/jackson/databind/ObjectMapperTest.java
+++ b/src/test/java/com/fasterxml/jackson/databind/ObjectMapperTest.java
@@ -10,6 +10,7 @@ import com.fasterxml.jackson.annotation.Nulls;
 import com.fasterxml.jackson.core.*;
 import com.fasterxml.jackson.core.util.MinimalPrettyPrinter;
 
+import com.fasterxml.jackson.databind.cfg.DeserializationFeature;
 import com.fasterxml.jackson.databind.introspect.JacksonAnnotationIntrospector;
 import com.fasterxml.jackson.databind.introspect.VisibilityChecker;
 import com.fasterxml.jackson.databind.node.*;
diff --git a/src/test/java/com/fasterxml/jackson/databind/ObjectReaderTest.java b/src/test/java/com/fasterxml/jackson/databind/ObjectReaderTest.java
index 1d67d5578..0f57e302b 100644
--- a/src/test/java/com/fasterxml/jackson/databind/ObjectReaderTest.java
+++ b/src/test/java/com/fasterxml/jackson/databind/ObjectReaderTest.java
@@ -9,6 +9,7 @@ import java.util.Set;
 import com.fasterxml.jackson.core.*;
 
 import com.fasterxml.jackson.databind.cfg.ContextAttributes;
+import com.fasterxml.jackson.databind.cfg.DeserializationFeature;
 import com.fasterxml.jackson.databind.deser.DeserializationProblemHandler;
 import com.fasterxml.jackson.databind.node.ArrayNode;
 import com.fasterxml.jackson.databind.node.JsonNodeFactory;
diff --git a/src/test/java/com/fasterxml/jackson/databind/TestRootName.java b/src/test/java/com/fasterxml/jackson/databind/TestRootName.java
index 02837dac5..ed27b1cf0 100644
--- a/src/test/java/com/fasterxml/jackson/databind/TestRootName.java
+++ b/src/test/java/com/fasterxml/jackson/databind/TestRootName.java
@@ -2,7 +2,7 @@ package com.fasterxml.jackson.databind;
 
 import com.fasterxml.jackson.annotation.*;
 
-import com.fasterxml.jackson.databind.ObjectMapper;
+import com.fasterxml.jackson.databind.cfg.DeserializationFeature;
 
 /**
  * Unit tests dealing with handling of "root element wrapping",
diff --git a/src/test/java/com/fasterxml/jackson/databind/convert/NumericConversionTest.java b/src/test/java/com/fasterxml/jackson/databind/convert/NumericConversionTest.java
index 287ad4bb1..bd2e7205b 100644
--- a/src/test/java/com/fasterxml/jackson/databind/convert/NumericConversionTest.java
+++ b/src/test/java/com/fasterxml/jackson/databind/convert/NumericConversionTest.java
@@ -1,6 +1,7 @@
 package com.fasterxml.jackson.databind.convert;
 
 import com.fasterxml.jackson.databind.*;
+import com.fasterxml.jackson.databind.cfg.DeserializationFeature;
 import com.fasterxml.jackson.databind.exc.MismatchedInputException;
 
 public class NumericConversionTest extends BaseMapTest
diff --git a/src/test/java/com/fasterxml/jackson/databind/convert/TestBeanConversions.java b/src/test/java/com/fasterxml/jackson/databind/convert/TestBeanConversions.java
index ac08d94e3..52c02e513 100644
--- a/src/test/java/com/fasterxml/jackson/databind/convert/TestBeanConversions.java
+++ b/src/test/java/com/fasterxml/jackson/databind/convert/TestBeanConversions.java
@@ -9,6 +9,7 @@ import com.fasterxml.jackson.core.TreeNode;
 import com.fasterxml.jackson.databind.*;
 import com.fasterxml.jackson.databind.annotation.JsonDeserialize;
 import com.fasterxml.jackson.databind.annotation.JsonSerialize;
+import com.fasterxml.jackson.databind.cfg.DeserializationFeature;
 import com.fasterxml.jackson.databind.node.ObjectNode;
 import com.fasterxml.jackson.databind.util.StdConverter;
 
diff --git a/src/test/java/com/fasterxml/jackson/databind/deser/AnySetterTest.java b/src/test/java/com/fasterxml/jackson/databind/deser/AnySetterTest.java
index 7e5dc85a9..e3711801f 100644
--- a/src/test/java/com/fasterxml/jackson/databind/deser/AnySetterTest.java
+++ b/src/test/java/com/fasterxml/jackson/databind/deser/AnySetterTest.java
@@ -5,6 +5,7 @@ import java.util.*;
 import com.fasterxml.jackson.annotation.*;
 
 import com.fasterxml.jackson.databind.*;
+import com.fasterxml.jackson.databind.cfg.DeserializationFeature;
 
 /**
  * Unit tests for verifying that {@link JsonAnySetter} annotation
diff --git a/src/test/java/com/fasterxml/jackson/databind/deser/IgnoreWithDeserTest.java b/src/test/java/com/fasterxml/jackson/databind/deser/IgnoreWithDeserTest.java
index e1dfa5b3d..e7e70b219 100644
--- a/src/test/java/com/fasterxml/jackson/databind/deser/IgnoreWithDeserTest.java
+++ b/src/test/java/com/fasterxml/jackson/databind/deser/IgnoreWithDeserTest.java
@@ -3,6 +3,7 @@ package com.fasterxml.jackson.databind.deser;
 import com.fasterxml.jackson.annotation.*;
 
 import com.fasterxml.jackson.databind.*;
+import com.fasterxml.jackson.databind.cfg.DeserializationFeature;
 
 /**
  * This unit test suite that tests use of {@link JsonIgnore}
diff --git a/src/test/java/com/fasterxml/jackson/databind/deser/TestArrayDeserialization.java b/src/test/java/com/fasterxml/jackson/databind/deser/TestArrayDeserialization.java
index 6b506d8b6..3e3ad5e64 100644
--- a/src/test/java/com/fasterxml/jackson/databind/deser/TestArrayDeserialization.java
+++ b/src/test/java/com/fasterxml/jackson/databind/deser/TestArrayDeserialization.java
@@ -9,6 +9,7 @@ import com.fasterxml.jackson.core.*;
 import com.fasterxml.jackson.core.type.TypeReference;
 import com.fasterxml.jackson.databind.*;
 import com.fasterxml.jackson.databind.annotation.JsonDeserialize;
+import com.fasterxml.jackson.databind.cfg.DeserializationFeature;
 import com.fasterxml.jackson.databind.jsontype.TypeSerializer;
 import com.fasterxml.jackson.databind.module.SimpleModule;
 
diff --git a/src/test/java/com/fasterxml/jackson/databind/deser/TestBeanDeserializer.java b/src/test/java/com/fasterxml/jackson/databind/deser/TestBeanDeserializer.java
index 988ece38d..340c5f6a6 100644
--- a/src/test/java/com/fasterxml/jackson/databind/deser/TestBeanDeserializer.java
+++ b/src/test/java/com/fasterxml/jackson/databind/deser/TestBeanDeserializer.java
@@ -7,6 +7,7 @@ import com.fasterxml.jackson.annotation.JsonCreator;
 import com.fasterxml.jackson.annotation.JsonProperty;
 import com.fasterxml.jackson.core.*;
 import com.fasterxml.jackson.databind.*;
+import com.fasterxml.jackson.databind.cfg.DeserializationFeature;
 import com.fasterxml.jackson.databind.deser.std.StdDeserializer;
 import com.fasterxml.jackson.databind.deser.std.StdScalarDeserializer;
 import com.fasterxml.jackson.databind.module.SimpleModule;
diff --git a/src/test/java/com/fasterxml/jackson/databind/deser/TestGenerics.java b/src/test/java/com/fasterxml/jackson/databind/deser/TestGenerics.java
index 967a6e7ef..a69352b9f 100644
--- a/src/test/java/com/fasterxml/jackson/databind/deser/TestGenerics.java
+++ b/src/test/java/com/fasterxml/jackson/databind/deser/TestGenerics.java
@@ -3,6 +3,7 @@ package com.fasterxml.jackson.databind.deser;
 
 import com.fasterxml.jackson.core.type.TypeReference;
 import com.fasterxml.jackson.databind.*;
+import com.fasterxml.jackson.databind.cfg.DeserializationFeature;
 
 public class TestGenerics
     extends BaseMapTest
diff --git a/src/test/java/com/fasterxml/jackson/databind/deser/TestTimestampDeserialization.java b/src/test/java/com/fasterxml/jackson/databind/deser/TestTimestampDeserialization.java
index 295cdad80..e70c8ea4c 100644
--- a/src/test/java/com/fasterxml/jackson/databind/deser/TestTimestampDeserialization.java
+++ b/src/test/java/com/fasterxml/jackson/databind/deser/TestTimestampDeserialization.java
@@ -5,6 +5,7 @@ import java.text.SimpleDateFormat;
 
 
 import com.fasterxml.jackson.databind.*;
+import com.fasterxml.jackson.databind.cfg.DeserializationFeature;
 
 public class TestTimestampDeserialization
     extends BaseMapTest
diff --git a/src/test/java/com/fasterxml/jackson/databind/deser/builder/BuilderErrorHandling.java b/src/test/java/com/fasterxml/jackson/databind/deser/builder/BuilderErrorHandling.java
index f7f67b0c5..018ac94b0 100644
--- a/src/test/java/com/fasterxml/jackson/databind/deser/builder/BuilderErrorHandling.java
+++ b/src/test/java/com/fasterxml/jackson/databind/deser/builder/BuilderErrorHandling.java
@@ -1,7 +1,7 @@
 package com.fasterxml.jackson.databind.deser.builder;
 
 import com.fasterxml.jackson.databind.BaseMapTest;
-import com.fasterxml.jackson.databind.DeserializationFeature;
+import com.fasterxml.jackson.databind.cfg.DeserializationFeature;
 import com.fasterxml.jackson.databind.ObjectMapper;
 import com.fasterxml.jackson.databind.annotation.JsonDeserialize;
 import com.fasterxml.jackson.databind.exc.MismatchedInputException;
diff --git a/src/test/java/com/fasterxml/jackson/databind/deser/creators/FailOnNullCreatorTest.java b/src/test/java/com/fasterxml/jackson/databind/deser/creators/FailOnNullCreatorTest.java
index a767bdadb..b8c02d405 100644
--- a/src/test/java/com/fasterxml/jackson/databind/deser/creators/FailOnNullCreatorTest.java
+++ b/src/test/java/com/fasterxml/jackson/databind/deser/creators/FailOnNullCreatorTest.java
@@ -3,6 +3,7 @@ package com.fasterxml.jackson.databind.deser.creators;
 import com.fasterxml.jackson.annotation.JsonCreator;
 import com.fasterxml.jackson.annotation.JsonProperty;
 import com.fasterxml.jackson.databind.*;
+import com.fasterxml.jackson.databind.cfg.DeserializationFeature;
 
 /**
  * Tests to ensure that deserialization fails when a bean property has a null value
diff --git a/src/test/java/com/fasterxml/jackson/databind/deser/creators/RequiredCreatorTest.java b/src/test/java/com/fasterxml/jackson/databind/deser/creators/RequiredCreatorTest.java
index 66bd9675c..d479cbc72 100644
--- a/src/test/java/com/fasterxml/jackson/databind/deser/creators/RequiredCreatorTest.java
+++ b/src/test/java/com/fasterxml/jackson/databind/deser/creators/RequiredCreatorTest.java
@@ -3,6 +3,7 @@ package com.fasterxml.jackson.databind.deser.creators;
 import com.fasterxml.jackson.annotation.*;
 
 import com.fasterxml.jackson.databind.*;
+import com.fasterxml.jackson.databind.cfg.DeserializationFeature;
 
 public class RequiredCreatorTest extends BaseMapTest
 {
diff --git a/src/test/java/com/fasterxml/jackson/databind/deser/creators/TestCreators3.java b/src/test/java/com/fasterxml/jackson/databind/deser/creators/TestCreators3.java
index d00030cb9..6d0b2b9c0 100644
--- a/src/test/java/com/fasterxml/jackson/databind/deser/creators/TestCreators3.java
+++ b/src/test/java/com/fasterxml/jackson/databind/deser/creators/TestCreators3.java
@@ -6,6 +6,7 @@ import java.util.Map;
 import com.fasterxml.jackson.annotation.*;
 
 import com.fasterxml.jackson.databind.*;
+import com.fasterxml.jackson.databind.cfg.DeserializationFeature;
 import com.fasterxml.jackson.databind.introspect.AnnotatedMember;
 import com.fasterxml.jackson.databind.introspect.AnnotatedParameter;
 import com.fasterxml.jackson.databind.introspect.JacksonAnnotationIntrospector;
diff --git a/src/test/java/com/fasterxml/jackson/databind/deser/filter/NullConversionsGenericTest.java b/src/test/java/com/fasterxml/jackson/databind/deser/filter/NullConversionsGenericTest.java
index 87df5f910..faffbd350 100644
--- a/src/test/java/com/fasterxml/jackson/databind/deser/filter/NullConversionsGenericTest.java
+++ b/src/test/java/com/fasterxml/jackson/databind/deser/filter/NullConversionsGenericTest.java
@@ -8,6 +8,7 @@ import com.fasterxml.jackson.annotation.Nulls;
 import com.fasterxml.jackson.core.type.TypeReference;
 
 import com.fasterxml.jackson.databind.*;
+import com.fasterxml.jackson.databind.cfg.DeserializationFeature;
 
 // for [databind#1402]; configurable null handling, for values themselves,
 // using generic types
diff --git a/src/test/java/com/fasterxml/jackson/databind/deser/filter/NullConversionsSkipTest.java b/src/test/java/com/fasterxml/jackson/databind/deser/filter/NullConversionsSkipTest.java
index 9fe93a340..421042d5b 100644
--- a/src/test/java/com/fasterxml/jackson/databind/deser/filter/NullConversionsSkipTest.java
+++ b/src/test/java/com/fasterxml/jackson/databind/deser/filter/NullConversionsSkipTest.java
@@ -3,6 +3,7 @@ package com.fasterxml.jackson.databind.deser.filter;
 import com.fasterxml.jackson.annotation.JsonSetter;
 import com.fasterxml.jackson.annotation.Nulls;
 import com.fasterxml.jackson.databind.*;
+import com.fasterxml.jackson.databind.cfg.DeserializationFeature;
 
 // for [databind#1402]; configurable null handling, specifically with SKIP
 public class NullConversionsSkipTest extends BaseMapTest
diff --git a/src/test/java/com/fasterxml/jackson/databind/deser/filter/ProblemHandlerLocation1440Test.java b/src/test/java/com/fasterxml/jackson/databind/deser/filter/ProblemHandlerLocation1440Test.java
index 14464e7b4..37d519440 100644
--- a/src/test/java/com/fasterxml/jackson/databind/deser/filter/ProblemHandlerLocation1440Test.java
+++ b/src/test/java/com/fasterxml/jackson/databind/deser/filter/ProblemHandlerLocation1440Test.java
@@ -8,6 +8,7 @@ import com.fasterxml.jackson.annotation.*;
 import com.fasterxml.jackson.core.*;
 
 import com.fasterxml.jackson.databind.*;
+import com.fasterxml.jackson.databind.cfg.DeserializationFeature;
 import com.fasterxml.jackson.databind.deser.DeserializationProblemHandler;
 
 // Test(s) to verify [databind#1440]
diff --git a/src/test/java/com/fasterxml/jackson/databind/deser/filter/TestUnknownPropertyDeserialization.java b/src/test/java/com/fasterxml/jackson/databind/deser/filter/TestUnknownPropertyDeserialization.java
index dacf4231e..91202a09a 100644
--- a/src/test/java/com/fasterxml/jackson/databind/deser/filter/TestUnknownPropertyDeserialization.java
+++ b/src/test/java/com/fasterxml/jackson/databind/deser/filter/TestUnknownPropertyDeserialization.java
@@ -7,6 +7,7 @@ import com.fasterxml.jackson.annotation.*;
 import com.fasterxml.jackson.core.*;
 import com.fasterxml.jackson.core.type.TypeReference;
 import com.fasterxml.jackson.databind.*;
+import com.fasterxml.jackson.databind.cfg.DeserializationFeature;
 import com.fasterxml.jackson.databind.deser.DeserializationProblemHandler;
 
 /**
diff --git a/src/test/java/com/fasterxml/jackson/databind/deser/jdk/CollectionDeserTest.java b/src/test/java/com/fasterxml/jackson/databind/deser/jdk/CollectionDeserTest.java
index 92e461330..01fc6c574 100644
--- a/src/test/java/com/fasterxml/jackson/databind/deser/jdk/CollectionDeserTest.java
+++ b/src/test/java/com/fasterxml/jackson/databind/deser/jdk/CollectionDeserTest.java
@@ -8,6 +8,7 @@ import com.fasterxml.jackson.core.*;
 import com.fasterxml.jackson.core.type.TypeReference;
 import com.fasterxml.jackson.databind.*;
 import com.fasterxml.jackson.databind.annotation.JsonDeserialize;
+import com.fasterxml.jackson.databind.cfg.DeserializationFeature;
 import com.fasterxml.jackson.databind.deser.std.StdDeserializer;
 
 @SuppressWarnings("serial")
diff --git a/src/test/java/com/fasterxml/jackson/databind/deser/jdk/DateDeserializationTest.java b/src/test/java/com/fasterxml/jackson/databind/deser/jdk/DateDeserializationTest.java
index 5ec830eb2..b74a5612d 100644
--- a/src/test/java/com/fasterxml/jackson/databind/deser/jdk/DateDeserializationTest.java
+++ b/src/test/java/com/fasterxml/jackson/databind/deser/jdk/DateDeserializationTest.java
@@ -9,6 +9,7 @@ import com.fasterxml.jackson.annotation.JsonFormat;
 import com.fasterxml.jackson.annotation.JsonIgnore;
 import com.fasterxml.jackson.annotation.OptBoolean;
 import com.fasterxml.jackson.databind.*;
+import com.fasterxml.jackson.databind.cfg.DeserializationFeature;
 import com.fasterxml.jackson.databind.exc.MismatchedInputException;
 import com.fasterxml.jackson.databind.exc.InvalidFormatException;
 
diff --git a/src/test/java/com/fasterxml/jackson/databind/deser/jdk/EnumAltIdTest.java b/src/test/java/com/fasterxml/jackson/databind/deser/jdk/EnumAltIdTest.java
index 76f188243..04bacca27 100644
--- a/src/test/java/com/fasterxml/jackson/databind/deser/jdk/EnumAltIdTest.java
+++ b/src/test/java/com/fasterxml/jackson/databind/deser/jdk/EnumAltIdTest.java
@@ -6,7 +6,7 @@ import java.util.EnumSet;
 import com.fasterxml.jackson.annotation.JsonFormat;
 import com.fasterxml.jackson.core.type.TypeReference;
 import com.fasterxml.jackson.databind.BaseMapTest;
-import com.fasterxml.jackson.databind.DeserializationFeature;
+import com.fasterxml.jackson.databind.cfg.DeserializationFeature;
 import com.fasterxml.jackson.databind.MapperFeature;
 import com.fasterxml.jackson.databind.ObjectMapper;
 import com.fasterxml.jackson.databind.ObjectReader;
diff --git a/src/test/java/com/fasterxml/jackson/databind/deser/jdk/EnumDefaultReadTest.java b/src/test/java/com/fasterxml/jackson/databind/deser/jdk/EnumDefaultReadTest.java
index 58392e824..32099275c 100644
--- a/src/test/java/com/fasterxml/jackson/databind/deser/jdk/EnumDefaultReadTest.java
+++ b/src/test/java/com/fasterxml/jackson/databind/deser/jdk/EnumDefaultReadTest.java
@@ -5,6 +5,7 @@ import java.io.IOException;
 import com.fasterxml.jackson.annotation.*;
 
 import com.fasterxml.jackson.databind.*;
+import com.fasterxml.jackson.databind.cfg.DeserializationFeature;
 import com.fasterxml.jackson.databind.exc.InvalidFormatException;
 
 public class EnumDefaultReadTest extends BaseMapTest
diff --git a/src/test/java/com/fasterxml/jackson/databind/deser/jdk/EnumDeserializationTest.java b/src/test/java/com/fasterxml/jackson/databind/deser/jdk/EnumDeserializationTest.java
index ff0a29cd1..e6daf0417 100644
--- a/src/test/java/com/fasterxml/jackson/databind/deser/jdk/EnumDeserializationTest.java
+++ b/src/test/java/com/fasterxml/jackson/databind/deser/jdk/EnumDeserializationTest.java
@@ -9,6 +9,7 @@ import com.fasterxml.jackson.core.*;
 import com.fasterxml.jackson.core.type.TypeReference;
 import com.fasterxml.jackson.databind.*;
 import com.fasterxml.jackson.databind.annotation.JsonDeserialize;
+import com.fasterxml.jackson.databind.cfg.DeserializationFeature;
 import com.fasterxml.jackson.databind.deser.std.FromStringDeserializer;
 import com.fasterxml.jackson.databind.deser.std.StdDeserializer;
 import com.fasterxml.jackson.databind.exc.InvalidFormatException;
diff --git a/src/test/java/com/fasterxml/jackson/databind/deser/jdk/EnumMapDeserializationTest.java b/src/test/java/com/fasterxml/jackson/databind/deser/jdk/EnumMapDeserializationTest.java
index bf30d14e3..c0f1b1a1b 100644
--- a/src/test/java/com/fasterxml/jackson/databind/deser/jdk/EnumMapDeserializationTest.java
+++ b/src/test/java/com/fasterxml/jackson/databind/deser/jdk/EnumMapDeserializationTest.java
@@ -7,6 +7,7 @@ import com.fasterxml.jackson.annotation.*;
 
 import com.fasterxml.jackson.core.type.TypeReference;
 import com.fasterxml.jackson.databind.*;
+import com.fasterxml.jackson.databind.cfg.DeserializationFeature;
 
 @SuppressWarnings("serial")
 public class EnumMapDeserializationTest extends BaseMapTest
diff --git a/src/test/java/com/fasterxml/jackson/databind/deser/jdk/JDKNumberDeserTest.java b/src/test/java/com/fasterxml/jackson/databind/deser/jdk/JDKNumberDeserTest.java
index 2fc0b1c43..ec0677683 100644
--- a/src/test/java/com/fasterxml/jackson/databind/deser/jdk/JDKNumberDeserTest.java
+++ b/src/test/java/com/fasterxml/jackson/databind/deser/jdk/JDKNumberDeserTest.java
@@ -10,6 +10,7 @@ import java.util.Map;
 import com.fasterxml.jackson.core.*;
 import com.fasterxml.jackson.databind.*;
 import com.fasterxml.jackson.databind.annotation.JsonDeserialize;
+import com.fasterxml.jackson.databind.cfg.DeserializationFeature;
 import com.fasterxml.jackson.databind.exc.MismatchedInputException;
 
 public class JDKNumberDeserTest extends BaseMapTest
diff --git a/src/test/java/com/fasterxml/jackson/databind/deser/jdk/JDKScalarsTest.java b/src/test/java/com/fasterxml/jackson/databind/deser/jdk/JDKScalarsTest.java
index 66d9951d6..297c77a48 100644
--- a/src/test/java/com/fasterxml/jackson/databind/deser/jdk/JDKScalarsTest.java
+++ b/src/test/java/com/fasterxml/jackson/databind/deser/jdk/JDKScalarsTest.java
@@ -3,6 +3,7 @@ package com.fasterxml.jackson.databind.deser.jdk;
 import java.io.*;
 import java.lang.reflect.Array;
 
+import com.fasterxml.jackson.databind.cfg.DeserializationFeature;
 import org.junit.Assert;
 
 import com.fasterxml.jackson.annotation.JsonCreator;
diff --git a/src/test/java/com/fasterxml/jackson/databind/deser/jdk/JDKStringLikeTypesTest.java b/src/test/java/com/fasterxml/jackson/databind/deser/jdk/JDKStringLikeTypesTest.java
index 7f65dd35e..d1be2befb 100644
--- a/src/test/java/com/fasterxml/jackson/databind/deser/jdk/JDKStringLikeTypesTest.java
+++ b/src/test/java/com/fasterxml/jackson/databind/deser/jdk/JDKStringLikeTypesTest.java
@@ -17,6 +17,7 @@ import com.fasterxml.jackson.core.JsonProcessingException;
 
 import com.fasterxml.jackson.databind.*;
 import com.fasterxml.jackson.databind.annotation.JsonDeserialize;
+import com.fasterxml.jackson.databind.cfg.DeserializationFeature;
 import com.fasterxml.jackson.databind.deser.std.StdDeserializer;
 import com.fasterxml.jackson.databind.exc.InvalidFormatException;
 import com.fasterxml.jackson.databind.module.SimpleModule;
diff --git a/src/test/java/com/fasterxml/jackson/databind/deser/jdk/MapDeserializationTest.java b/src/test/java/com/fasterxml/jackson/databind/deser/jdk/MapDeserializationTest.java
index 852f3898e..8c11ac3f1 100644
--- a/src/test/java/com/fasterxml/jackson/databind/deser/jdk/MapDeserializationTest.java
+++ b/src/test/java/com/fasterxml/jackson/databind/deser/jdk/MapDeserializationTest.java
@@ -11,6 +11,7 @@ import com.fasterxml.jackson.core.*;
 import com.fasterxml.jackson.core.type.TypeReference;
 import com.fasterxml.jackson.databind.*;
 import com.fasterxml.jackson.databind.annotation.JsonDeserialize;
+import com.fasterxml.jackson.databind.cfg.DeserializationFeature;
 import com.fasterxml.jackson.databind.deser.std.StdDeserializer;
 
 @SuppressWarnings("serial")
diff --git a/src/test/java/com/fasterxml/jackson/databind/deser/jdk/UntypedDeserializationTest.java b/src/test/java/com/fasterxml/jackson/databind/deser/jdk/UntypedDeserializationTest.java
index 3b28b9d0c..4ed41388e 100644
--- a/src/test/java/com/fasterxml/jackson/databind/deser/jdk/UntypedDeserializationTest.java
+++ b/src/test/java/com/fasterxml/jackson/databind/deser/jdk/UntypedDeserializationTest.java
@@ -11,6 +11,7 @@ import com.fasterxml.jackson.annotation.JsonTypeInfo.As;
 import com.fasterxml.jackson.core.*;
 import com.fasterxml.jackson.databind.*;
 import com.fasterxml.jackson.databind.ObjectMapper.DefaultTyping;
+import com.fasterxml.jackson.databind.cfg.DeserializationFeature;
 import com.fasterxml.jackson.databind.deser.ContextualDeserializer;
 import com.fasterxml.jackson.databind.deser.std.StdDeserializer;
 import com.fasterxml.jackson.databind.deser.std.StdScalarDeserializer;
diff --git a/src/test/java/com/fasterxml/jackson/databind/deser/merge/ArrayMergeTest.java b/src/test/java/com/fasterxml/jackson/databind/deser/merge/ArrayMergeTest.java
index 908ddc5f8..deab35ca1 100644
--- a/src/test/java/com/fasterxml/jackson/databind/deser/merge/ArrayMergeTest.java
+++ b/src/test/java/com/fasterxml/jackson/databind/deser/merge/ArrayMergeTest.java
@@ -1,5 +1,6 @@
 package com.fasterxml.jackson.databind.deser.merge;
 
+import com.fasterxml.jackson.databind.cfg.DeserializationFeature;
 import org.junit.Assert;
 
 import com.fasterxml.jackson.annotation.JsonMerge;
diff --git a/src/test/java/com/fasterxml/jackson/databind/exc/ExceptionDeserializationTest.java b/src/test/java/com/fasterxml/jackson/databind/exc/ExceptionDeserializationTest.java
index 536a5b428..2360c0c54 100644
--- a/src/test/java/com/fasterxml/jackson/databind/exc/ExceptionDeserializationTest.java
+++ b/src/test/java/com/fasterxml/jackson/databind/exc/ExceptionDeserializationTest.java
@@ -6,6 +6,7 @@ import java.util.*;
 import com.fasterxml.jackson.annotation.*;
 
 import com.fasterxml.jackson.databind.*;
+import com.fasterxml.jackson.databind.cfg.DeserializationFeature;
 
 /**
  * Unit tests for verifying that simple exceptions can be deserialized.
diff --git a/src/test/java/com/fasterxml/jackson/databind/introspect/TestJacksonAnnotationIntrospector.java b/src/test/java/com/fasterxml/jackson/databind/introspect/TestJacksonAnnotationIntrospector.java
index ef9adde13..cdd19b5ae 100644
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
+import com.fasterxml.jackson.databind.jsontype.StdTypeResolverBuilder;
 import com.fasterxml.jackson.databind.type.TypeFactory;
 
 @SuppressWarnings("serial")
diff --git a/src/test/java/com/fasterxml/jackson/databind/jsontype/TestPolymorphicWithDefaultImpl.java b/src/test/java/com/fasterxml/jackson/databind/jsontype/TestPolymorphicWithDefaultImpl.java
index 7d260c785..008dc373a 100644
--- a/src/test/java/com/fasterxml/jackson/databind/jsontype/TestPolymorphicWithDefaultImpl.java
+++ b/src/test/java/com/fasterxml/jackson/databind/jsontype/TestPolymorphicWithDefaultImpl.java
@@ -6,6 +6,7 @@ import com.fasterxml.jackson.annotation.*;
 
 import com.fasterxml.jackson.databind.*;
 import com.fasterxml.jackson.databind.annotation.NoClass;
+import com.fasterxml.jackson.databind.cfg.DeserializationFeature;
 import com.fasterxml.jackson.databind.exc.InvalidTypeIdException;
 
 /**
diff --git a/src/test/java/com/fasterxml/jackson/databind/jsontype/UnknownSubClassTest.java b/src/test/java/com/fasterxml/jackson/databind/jsontype/UnknownSubClassTest.java
index ba670983d..1f7127af3 100644
--- a/src/test/java/com/fasterxml/jackson/databind/jsontype/UnknownSubClassTest.java
+++ b/src/test/java/com/fasterxml/jackson/databind/jsontype/UnknownSubClassTest.java
@@ -3,6 +3,7 @@ package com.fasterxml.jackson.databind.jsontype;
 import com.fasterxml.jackson.annotation.JsonTypeInfo;
 
 import com.fasterxml.jackson.databind.*;
+import com.fasterxml.jackson.databind.cfg.DeserializationFeature;
 
 public class UnknownSubClassTest extends BaseMapTest
 {
diff --git a/src/test/java/com/fasterxml/jackson/databind/jsontype/deftyping/TestDefaultForScalars.java b/src/test/java/com/fasterxml/jackson/databind/jsontype/deftyping/TestDefaultForScalars.java
index 7bb7b5c43..84cb83a39 100644
--- a/src/test/java/com/fasterxml/jackson/databind/jsontype/deftyping/TestDefaultForScalars.java
+++ b/src/test/java/com/fasterxml/jackson/databind/jsontype/deftyping/TestDefaultForScalars.java
@@ -6,7 +6,7 @@ import static org.junit.Assert.*;
 
 import com.fasterxml.jackson.annotation.JsonTypeInfo;
 import com.fasterxml.jackson.databind.*;
-import com.fasterxml.jackson.databind.jsontype.impl.StdTypeResolverBuilder;
+import com.fasterxml.jackson.databind.jsontype.StdTypeResolverBuilder;
 
 /**
  * Unit tests to verify that Java/JSON scalar values (non-structured values)
diff --git a/src/test/java/com/fasterxml/jackson/databind/jsontype/ext/ExternalTypeIdTest.java b/src/test/java/com/fasterxml/jackson/databind/jsontype/ext/ExternalTypeIdTest.java
index 753712992..4a1d8e5cc 100644
--- a/src/test/java/com/fasterxml/jackson/databind/jsontype/ext/ExternalTypeIdTest.java
+++ b/src/test/java/com/fasterxml/jackson/databind/jsontype/ext/ExternalTypeIdTest.java
@@ -7,7 +7,7 @@ import com.fasterxml.jackson.annotation.*;
 import com.fasterxml.jackson.annotation.JsonTypeInfo.As;
 import com.fasterxml.jackson.annotation.JsonTypeInfo.Id;
 import com.fasterxml.jackson.databind.BaseMapTest;
-import com.fasterxml.jackson.databind.DeserializationFeature;
+import com.fasterxml.jackson.databind.cfg.DeserializationFeature;
 import com.fasterxml.jackson.databind.ObjectMapper;
 
 // Tests for External type id, one that exists at same level as typed Object,
diff --git a/src/test/java/com/fasterxml/jackson/databind/jsontype/ext/TestSubtypesExternalPropertyMissingProperty.java b/src/test/java/com/fasterxml/jackson/databind/jsontype/ext/TestSubtypesExternalPropertyMissingProperty.java
index ac414b3ac..d635ca71f 100644
--- a/src/test/java/com/fasterxml/jackson/databind/jsontype/ext/TestSubtypesExternalPropertyMissingProperty.java
+++ b/src/test/java/com/fasterxml/jackson/databind/jsontype/ext/TestSubtypesExternalPropertyMissingProperty.java
@@ -7,6 +7,7 @@ import com.fasterxml.jackson.annotation.JsonTypeInfo.Id;
 
 import com.fasterxml.jackson.databind.*;
 
+import com.fasterxml.jackson.databind.cfg.DeserializationFeature;
 import org.junit.Rule;
 import org.junit.Test;
 import org.junit.rules.ExpectedException;
diff --git a/src/test/java/com/fasterxml/jackson/databind/mixins/MapperMixinsCopy1998Test.java b/src/test/java/com/fasterxml/jackson/databind/mixins/MapperMixinsCopy1998Test.java
index 32897e659..878947f79 100644
--- a/src/test/java/com/fasterxml/jackson/databind/mixins/MapperMixinsCopy1998Test.java
+++ b/src/test/java/com/fasterxml/jackson/databind/mixins/MapperMixinsCopy1998Test.java
@@ -5,6 +5,7 @@ import java.io.IOException;
 import com.fasterxml.jackson.annotation.*;
 
 import com.fasterxml.jackson.databind.*;
+import com.fasterxml.jackson.databind.cfg.DeserializationFeature;
 
 public class MapperMixinsCopy1998Test extends BaseMapTest
 {
diff --git a/src/test/java/com/fasterxml/jackson/databind/node/NotANumberConversionTest.java b/src/test/java/com/fasterxml/jackson/databind/node/NotANumberConversionTest.java
index 3fcb71dba..b3f830d76 100644
--- a/src/test/java/com/fasterxml/jackson/databind/node/NotANumberConversionTest.java
+++ b/src/test/java/com/fasterxml/jackson/databind/node/NotANumberConversionTest.java
@@ -3,6 +3,7 @@ package com.fasterxml.jackson.databind.node;
 import java.math.BigDecimal;
 
 import com.fasterxml.jackson.databind.*;
+import com.fasterxml.jackson.databind.cfg.DeserializationFeature;
 
 public class NotANumberConversionTest extends BaseMapTest
 {
diff --git a/src/test/java/com/fasterxml/jackson/databind/node/NumberNodesTest.java b/src/test/java/com/fasterxml/jackson/databind/node/NumberNodesTest.java
index f12cb9484..e58ffcbde 100644
--- a/src/test/java/com/fasterxml/jackson/databind/node/NumberNodesTest.java
+++ b/src/test/java/com/fasterxml/jackson/databind/node/NumberNodesTest.java
@@ -7,6 +7,7 @@ import com.fasterxml.jackson.core.JsonGenerator;
 import com.fasterxml.jackson.core.JsonParser;
 import com.fasterxml.jackson.core.JsonToken;
 import com.fasterxml.jackson.databind.*;
+import com.fasterxml.jackson.databind.cfg.DeserializationFeature;
 
 /**
  * Basic tests for {@link JsonNode} implementations that
diff --git a/src/test/java/com/fasterxml/jackson/databind/node/ObjectNodeTest.java b/src/test/java/com/fasterxml/jackson/databind/node/ObjectNodeTest.java
index b617d68b0..3437e9846 100644
--- a/src/test/java/com/fasterxml/jackson/databind/node/ObjectNodeTest.java
+++ b/src/test/java/com/fasterxml/jackson/databind/node/ObjectNodeTest.java
@@ -9,6 +9,7 @@ import com.fasterxml.jackson.annotation.JsonInclude;
 import com.fasterxml.jackson.annotation.JsonValue;
 import com.fasterxml.jackson.databind.*;
 import com.fasterxml.jackson.databind.annotation.JsonDeserialize;
+import com.fasterxml.jackson.databind.cfg.DeserializationFeature;
 import com.fasterxml.jackson.databind.exc.MismatchedInputException;
 
 /**
diff --git a/src/test/java/com/fasterxml/jackson/databind/objectid/ObjectId825BTest.java b/src/test/java/com/fasterxml/jackson/databind/objectid/ObjectId825BTest.java
index 8c36f278a..6cfe94d32 100644
--- a/src/test/java/com/fasterxml/jackson/databind/objectid/ObjectId825BTest.java
+++ b/src/test/java/com/fasterxml/jackson/databind/objectid/ObjectId825BTest.java
@@ -4,6 +4,7 @@ import java.util.ArrayList;
 
 import com.fasterxml.jackson.annotation.*;
 import com.fasterxml.jackson.databind.*;
+import com.fasterxml.jackson.databind.cfg.DeserializationFeature;
 
 @SuppressWarnings("serial")
 public class ObjectId825BTest extends BaseMapTest
diff --git a/src/test/java/com/fasterxml/jackson/databind/objectid/TestObjectIdDeserialization.java b/src/test/java/com/fasterxml/jackson/databind/objectid/TestObjectIdDeserialization.java
index 2db9bdc61..50520bc7b 100644
--- a/src/test/java/com/fasterxml/jackson/databind/objectid/TestObjectIdDeserialization.java
+++ b/src/test/java/com/fasterxml/jackson/databind/objectid/TestObjectIdDeserialization.java
@@ -14,7 +14,7 @@ import com.fasterxml.jackson.annotation.ObjectIdGenerators;
 import com.fasterxml.jackson.annotation.ObjectIdResolver;
 import com.fasterxml.jackson.databind.BaseMapTest;
 import com.fasterxml.jackson.databind.DeserializationContext;
-import com.fasterxml.jackson.databind.DeserializationFeature;
+import com.fasterxml.jackson.databind.cfg.DeserializationFeature;
 import com.fasterxml.jackson.databind.ObjectMapper;
 import com.fasterxml.jackson.databind.cfg.ContextAttributes;
 import com.fasterxml.jackson.databind.deser.UnresolvedForwardReference;
diff --git a/src/test/java/com/fasterxml/jackson/databind/ser/TestKeySerializers.java b/src/test/java/com/fasterxml/jackson/databind/ser/TestKeySerializers.java
index dd9739223..a2fc08773 100644
--- a/src/test/java/com/fasterxml/jackson/databind/ser/TestKeySerializers.java
+++ b/src/test/java/com/fasterxml/jackson/databind/ser/TestKeySerializers.java
@@ -8,6 +8,7 @@ import com.fasterxml.jackson.core.JsonGenerator;
 import com.fasterxml.jackson.core.type.TypeReference;
 import com.fasterxml.jackson.databind.*;
 import com.fasterxml.jackson.databind.annotation.JsonSerialize;
+import com.fasterxml.jackson.databind.cfg.DeserializationFeature;
 import com.fasterxml.jackson.databind.jsontype.TypeResolverBuilder;
 import com.fasterxml.jackson.databind.module.SimpleModule;
 
diff --git a/src/test/java/com/fasterxml/jackson/databind/struct/EmptyArrayAsNullTest.java b/src/test/java/com/fasterxml/jackson/databind/struct/EmptyArrayAsNullTest.java
index 71aba3253..c2c6beb69 100644
--- a/src/test/java/com/fasterxml/jackson/databind/struct/EmptyArrayAsNullTest.java
+++ b/src/test/java/com/fasterxml/jackson/databind/struct/EmptyArrayAsNullTest.java
@@ -7,6 +7,7 @@ import java.util.*;
 
 import com.fasterxml.jackson.core.type.TypeReference;
 import com.fasterxml.jackson.databind.*;
+import com.fasterxml.jackson.databind.cfg.DeserializationFeature;
 
 /**
  * Tests to verify implementation of [databind#540]; also for
diff --git a/src/test/java/com/fasterxml/jackson/databind/struct/ScalarCoercionTest.java b/src/test/java/com/fasterxml/jackson/databind/struct/ScalarCoercionTest.java
index e524d7203..50c5782ff 100644
--- a/src/test/java/com/fasterxml/jackson/databind/struct/ScalarCoercionTest.java
+++ b/src/test/java/com/fasterxml/jackson/databind/struct/ScalarCoercionTest.java
@@ -5,6 +5,7 @@ import java.math.BigDecimal;
 import java.math.BigInteger;
 
 import com.fasterxml.jackson.databind.*;
+import com.fasterxml.jackson.databind.cfg.DeserializationFeature;
 import com.fasterxml.jackson.databind.exc.MismatchedInputException;
 
 // for [databind#1106]
diff --git a/src/test/java/com/fasterxml/jackson/databind/struct/SingleValueAsArrayTest.java b/src/test/java/com/fasterxml/jackson/databind/struct/SingleValueAsArrayTest.java
index f0f93546e..14600b54e 100644
--- a/src/test/java/com/fasterxml/jackson/databind/struct/SingleValueAsArrayTest.java
+++ b/src/test/java/com/fasterxml/jackson/databind/struct/SingleValueAsArrayTest.java
@@ -11,6 +11,7 @@ import com.fasterxml.jackson.annotation.JsonProperty;
 import com.fasterxml.jackson.core.type.TypeReference;
 
 import com.fasterxml.jackson.databind.*;
+import com.fasterxml.jackson.databind.cfg.DeserializationFeature;
 
 public class SingleValueAsArrayTest extends BaseMapTest
 {
diff --git a/src/test/java/com/fasterxml/jackson/databind/struct/TestForwardReference.java b/src/test/java/com/fasterxml/jackson/databind/struct/TestForwardReference.java
index 87a5ce1e0..dca536a98 100644
--- a/src/test/java/com/fasterxml/jackson/databind/struct/TestForwardReference.java
+++ b/src/test/java/com/fasterxml/jackson/databind/struct/TestForwardReference.java
@@ -5,7 +5,7 @@ import java.io.IOException;
 import com.fasterxml.jackson.annotation.*;
 
 import com.fasterxml.jackson.databind.BaseMapTest;
-import com.fasterxml.jackson.databind.DeserializationFeature;
+import com.fasterxml.jackson.databind.cfg.DeserializationFeature;
 import com.fasterxml.jackson.databind.ObjectMapper;
 import com.fasterxml.jackson.databind.SerializationFeature;
 
diff --git a/src/test/java/com/fasterxml/jackson/databind/struct/TestPOJOAsArray.java b/src/test/java/com/fasterxml/jackson/databind/struct/TestPOJOAsArray.java
index 391cd3cb8..1137357b4 100644
--- a/src/test/java/com/fasterxml/jackson/databind/struct/TestPOJOAsArray.java
+++ b/src/test/java/com/fasterxml/jackson/databind/struct/TestPOJOAsArray.java
@@ -7,6 +7,7 @@ import com.fasterxml.jackson.annotation.*;
 import com.fasterxml.jackson.annotation.JsonFormat.Shape;
 
 import com.fasterxml.jackson.databind.*;
+import com.fasterxml.jackson.databind.cfg.DeserializationFeature;
 import com.fasterxml.jackson.databind.exc.MismatchedInputException;
 import com.fasterxml.jackson.databind.introspect.Annotated;
 import com.fasterxml.jackson.databind.introspect.JacksonAnnotationIntrospector;
diff --git a/src/test/java/com/fasterxml/jackson/databind/struct/TestPOJOAsArrayWithBuilder.java b/src/test/java/com/fasterxml/jackson/databind/struct/TestPOJOAsArrayWithBuilder.java
index 321c86c6a..8031962b6 100644
--- a/src/test/java/com/fasterxml/jackson/databind/struct/TestPOJOAsArrayWithBuilder.java
+++ b/src/test/java/com/fasterxml/jackson/databind/struct/TestPOJOAsArrayWithBuilder.java
@@ -3,7 +3,7 @@ package com.fasterxml.jackson.databind.struct;
 import com.fasterxml.jackson.annotation.*;
 
 import com.fasterxml.jackson.databind.BaseMapTest;
-import com.fasterxml.jackson.databind.DeserializationFeature;
+import com.fasterxml.jackson.databind.cfg.DeserializationFeature;
 import com.fasterxml.jackson.databind.ObjectMapper;
 import com.fasterxml.jackson.databind.ObjectReader;
 import com.fasterxml.jackson.databind.annotation.JsonDeserialize;
diff --git a/src/test/java/com/fasterxml/jackson/databind/struct/UnwrapSingleArrayScalarsTest.java b/src/test/java/com/fasterxml/jackson/databind/struct/UnwrapSingleArrayScalarsTest.java
index 4352835ab..55f8d79bf 100644
--- a/src/test/java/com/fasterxml/jackson/databind/struct/UnwrapSingleArrayScalarsTest.java
+++ b/src/test/java/com/fasterxml/jackson/databind/struct/UnwrapSingleArrayScalarsTest.java
@@ -8,7 +8,7 @@ import java.net.URI;
 import java.util.UUID;
 
 import com.fasterxml.jackson.databind.BaseMapTest;
-import com.fasterxml.jackson.databind.DeserializationFeature;
+import com.fasterxml.jackson.databind.cfg.DeserializationFeature;
 import com.fasterxml.jackson.databind.ObjectMapper;
 import com.fasterxml.jackson.databind.ObjectReader;
 import com.fasterxml.jackson.databind.exc.MismatchedInputException;
diff --git a/src/test/java/com/fasterxml/jackson/databind/type/RecursiveType1658Test.java b/src/test/java/com/fasterxml/jackson/databind/type/RecursiveType1658Test.java
index c211cd969..cbf865800 100644
--- a/src/test/java/com/fasterxml/jackson/databind/type/RecursiveType1658Test.java
+++ b/src/test/java/com/fasterxml/jackson/databind/type/RecursiveType1658Test.java
@@ -5,7 +5,7 @@ import java.util.*;
 import com.fasterxml.jackson.annotation.JsonTypeInfo;
 import com.fasterxml.jackson.databind.*;
 import com.fasterxml.jackson.databind.jsontype.TypeResolverBuilder;
-import com.fasterxml.jackson.databind.jsontype.impl.StdTypeResolverBuilder;
+import com.fasterxml.jackson.databind.jsontype.StdTypeResolverBuilder;
 
 public class RecursiveType1658Test extends BaseMapTest
 {
diff --git a/src/test/java/com/fasterxml/jackson/failing/NumberNodes1770Test.java b/src/test/java/com/fasterxml/jackson/failing/NumberNodes1770Test.java
index 93e3602a9..3be58bb92 100644
--- a/src/test/java/com/fasterxml/jackson/failing/NumberNodes1770Test.java
+++ b/src/test/java/com/fasterxml/jackson/failing/NumberNodes1770Test.java
@@ -1,6 +1,7 @@
 package com.fasterxml.jackson.failing;
 
 import com.fasterxml.jackson.databind.*;
+import com.fasterxml.jackson.databind.cfg.DeserializationFeature;
 
 /**
  * Basic tests for {@link JsonNode} implementations that
diff --git a/src/test/java/com/fasterxml/jackson/failing/TestUnwrappedWithUnknown650.java b/src/test/java/com/fasterxml/jackson/failing/TestUnwrappedWithUnknown650.java
index 6229491bd..ed280faab 100644
--- a/src/test/java/com/fasterxml/jackson/failing/TestUnwrappedWithUnknown650.java
+++ b/src/test/java/com/fasterxml/jackson/failing/TestUnwrappedWithUnknown650.java
@@ -2,6 +2,7 @@ package com.fasterxml.jackson.failing;
 
 import com.fasterxml.jackson.annotation.JsonUnwrapped;
 import com.fasterxml.jackson.databind.*;
+import com.fasterxml.jackson.databind.cfg.DeserializationFeature;
 
 public class TestUnwrappedWithUnknown650 extends BaseMapTest
 {
diff --git a/src/test/java/perf/ObjectReaderTestBase.java b/src/test/java/perf/ObjectReaderTestBase.java
index d973b2e89..08a5cd3c3 100644
--- a/src/test/java/perf/ObjectReaderTestBase.java
+++ b/src/test/java/perf/ObjectReaderTestBase.java
@@ -3,6 +3,7 @@ package perf;
 import java.io.*;
 
 import com.fasterxml.jackson.databind.*;
+import com.fasterxml.jackson.databind.cfg.DeserializationFeature;
 
 abstract class ObjectReaderTestBase
 {

EOF_METAMORPHIC_PATCH
git apply /home/metamorphic_base.patch
git add -A && git -c user.email='mswe-agent@metamorphic.py' -c user.name='metamorphic-transformation-patch' commit -m 'Apply `metamorphic_base_patch` transformation to base commit'


bash /home/check_git_changes.sh

file="/home/jackson-databind/pom.xml"
old_version="2.15.0-rc2-SNAPSHOT"
new_version="2.15.5-SNAPSHOT"
sed -i "s/$old_version/$new_version/g" "$file"

mvn clean test -Dmaven.test.skip=false -DfailIfNoTests=false || true
