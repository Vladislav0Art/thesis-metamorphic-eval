#!/bin/bash
set -e

cd /home/fastjson2
git config core.autocrlf input
git config core.filemode false
echo ".gitattributes" >> .git/info/exclude
echo "*.zip binary" >> .gitattributes
echo "*.png binary" >> .gitattributes
echo "*.jpg binary" >> .gitattributes
git add .
git reset --hard
bash /home/check_git_changes.sh
git checkout 27ca2b45c33cd362fa35613416f5d62ff9567921

# apply metamorphic patch (if present)
cat > /home/metamorphic_base.patch << 'EOF_METAMORPHIC_PATCH'
diff --git a/core/src/main/java/com/alibaba/fastjson2/writer/BaseObjectWriterModule.java b/core/src/main/java/com/alibaba/fastjson2/writer/BaseObjectWriterModule.java
new file mode 100644
index 000000000..302f294e4
--- /dev/null
+++ b/core/src/main/java/com/alibaba/fastjson2/writer/BaseObjectWriterModule.java
@@ -0,0 +1,1514 @@
+package com.alibaba.fastjson2.writer;
+
+import com.alibaba.fastjson2.JSONFactory;
+import com.alibaba.fastjson2.JSONPObject;
+import com.alibaba.fastjson2.JSONPath;
+import com.alibaba.fastjson2.JSONWriter;
+import com.alibaba.fastjson2.annotation.*;
+import com.alibaba.fastjson2.codec.BeanInfo;
+import com.alibaba.fastjson2.codec.FieldInfo;
+import com.alibaba.fastjson2.filter.Filter;
+import com.alibaba.fastjson2.modules.ObjectWriterAnnotationProcessor;
+import com.alibaba.fastjson2.modules.ObjectWriterModule;
+import com.alibaba.fastjson2.support.LambdaMiscCodec;
+import com.alibaba.fastjson2.support.money.MoneySupport;
+import com.alibaba.fastjson2.util.*;
+
+import java.io.File;
+import java.lang.annotation.Annotation;
+import java.lang.reflect.*;
+import java.math.BigDecimal;
+import java.math.BigInteger;
+import java.net.URI;
+import java.net.URL;
+import java.nio.ByteBuffer;
+import java.nio.charset.Charset;
+import java.time.*;
+import java.util.*;
+import java.util.concurrent.TimeUnit;
+import java.util.concurrent.atomic.*;
+
+import static com.alibaba.fastjson2.util.BeanUtils.*;
+
+public class BaseObjectWriterModule
+        implements ObjectWriterModule {
+    static ObjectWriterAdapter stackTraceAdapter;
+
+    final ObjectWriterProvider writerProviderInstance;
+    final JsonWriterAnnotationProcessor jsonAnnotationHandler;
+
+    public BaseObjectWriterModule(ObjectWriterProvider writerProviderInstance) {
+        this.writerProviderInstance = writerProviderInstance;
+        this.jsonAnnotationHandler = new JsonWriterAnnotationProcessor();
+    }
+
+    @Override
+    public ObjectWriterProvider getProvider() {
+        return writerProviderInstance;
+    }
+
+    @Override
+    public ObjectWriterAnnotationProcessor getAnnotationProcessor() {
+        return jsonAnnotationHandler;
+    }
+
+    public class JsonWriterAnnotationProcessor
+            implements ObjectWriterAnnotationProcessor {
+        @Override
+        public void getBeanInfo(BeanInfo beanMetadata, Class targetClass) {
+            if (targetClass != null) {
+                Class parentClass = targetClass.getSuperclass();
+                if (parentClass != Object.class && parentClass != null && parentClass != Enum.class) {
+                    getBeanInfo(beanMetadata, parentClass);
+
+                    if (beanMetadata.seeAlso != null && beanMetadata.seeAlsoNames != null) {
+                        for (int index = 0; index < beanMetadata.seeAlso.length; index++) {
+                            Class relatedTypes = beanMetadata.seeAlso[index];
+                            if (relatedTypes == targetClass && index < beanMetadata.seeAlsoNames.length) {
+                                String relatedTypeName = beanMetadata.seeAlsoNames[index];
+                                if (relatedTypeName != null && relatedTypeName.length() != 0) {
+                                    beanMetadata.typeName = relatedTypeName;
+                                    break;
+                                }
+                            }
+                        }
+                    }
+                }
+            }
+
+            Annotation legacyJsonType = null;
+            JSONType jsonTypeAnnotation = null;
+            Annotation[] foundAnnotations = getAnnotations(targetClass);
+            for (int index = 0; index < foundAnnotations.length; index++) {
+                Annotation ann = foundAnnotations[index];
+                Class annClass = ann.annotationType();
+                if (jsonTypeAnnotation == null) {
+                    jsonTypeAnnotation = findAnnotation(ann, JSONType.class);
+                }
+                if (jsonTypeAnnotation == ann) {
+                    continue;
+                }
+
+                if (annClass == JSONCompiler.class) {
+                    JSONCompiler jsonCompiler = (JSONCompiler) ann;
+                    if (jsonCompiler.value() == JSONCompiler.CompilerOption.LAMBDA) {
+                        beanMetadata.writerFeatures |= FieldInfo.JIT;
+                    }
+                }
+
+                boolean enableJacksonAnnotation = JSONFactory.isUseJacksonAnnotation();
+                switch (annClass.getName()) {
+                    case "com.alibaba.fastjson.annotation.JSONType":
+                        legacyJsonType = ann;
+                        break;
+                    case "com.fasterxml.jackson.annotation.JsonIgnoreProperties":
+                        if (enableJacksonAnnotation) {
+                            processJsonIgnoreProperties(beanMetadata, ann);
+                        }
+                        break;
+                    case "com.fasterxml.jackson.annotation.JsonPropertyOrder":
+                        if (enableJacksonAnnotation) {
+                            processJsonPropertyOrderAnnotation(beanMetadata, ann);
+                        }
+                        break;
+                    case "com.fasterxml.jackson.annotation.JsonFormat":
+                        if (enableJacksonAnnotation) {
+                            processJacksonJsonFormat(beanMetadata, ann);
+                        }
+                        break;
+                    case "com.fasterxml.jackson.annotation.JsonInclude":
+                        if (enableJacksonAnnotation) {
+                            processJacksonJsonInclude(beanMetadata, ann);
+                        }
+                        break;
+                    case "com.fasterxml.jackson.annotation.JsonTypeInfo":
+                        if (enableJacksonAnnotation) {
+                            handleJacksonJsonTypeInfo(beanMetadata, ann);
+                        }
+                        break;
+                    case "com.fasterxml.jackson.databind.annotation.JsonSerialize":
+                        if (enableJacksonAnnotation) {
+                            processJsonSerializeAnnotation(beanMetadata, ann);
+                            if (beanMetadata.serializer != null && Enum.class.isAssignableFrom(targetClass)) {
+                                beanMetadata.writeEnumAsJavaBean = true;
+                            }
+                        }
+                        break;
+                    case "com.fasterxml.jackson.annotation.JsonTypeName":
+                        if (enableJacksonAnnotation) {
+                            processJacksonJsonTypeName(beanMetadata, ann);
+                        }
+                        break;
+                    case "com.fasterxml.jackson.annotation.JsonSubTypes":
+                        if (enableJacksonAnnotation) {
+                            processJacksonJsonSubTypesAnnotation(beanMetadata, ann);
+                        }
+                        break;
+                    case "kotlin.Metadata":
+                        beanMetadata.kotlin = true;
+                        KotlinUtils.getConstructor(targetClass, beanMetadata);
+                        break;
+                    default:
+                        break;
+                }
+            }
+
+            if (jsonTypeAnnotation == null) {
+                Class mixInClass = writerProviderInstance.mixInCache.get(targetClass);
+
+                if (mixInClass != null) {
+                    beanMetadata.mixIn = true;
+
+                    Annotation[] mixInAnnos = getAnnotations(mixInClass);
+                    for (int index = 0; index < mixInAnnos.length; index++) {
+                        Annotation ann = mixInAnnos[index];
+                        Class<? extends Annotation> annClass = ann.annotationType();
+                        jsonTypeAnnotation = findAnnotation(ann, JSONType.class);
+                        if (jsonTypeAnnotation == ann) {
+                            continue;
+                        }
+
+                        String annTypeName = annClass.getName();
+                        if ("com.alibaba.fastjson.annotation.JSONType".equals(annTypeName)) {
+                            legacyJsonType = ann;
+                        }
+                    }
+                }
+            }
+
+            if (jsonTypeAnnotation != null) {
+                Class<?>[] typeClasses = jsonTypeAnnotation.seeAlso();
+                if (typeClasses.length != 0) {
+                    beanMetadata.seeAlso = typeClasses;
+                }
+
+                String typeIdentifier = jsonTypeAnnotation.typeKey();
+                if (!typeIdentifier.isEmpty()) {
+                    beanMetadata.typeKey = typeIdentifier;
+                }
+
+                String typeLabel = jsonTypeAnnotation.typeName();
+                if (!typeLabel.isEmpty()) {
+                    beanMetadata.typeName = typeLabel;
+                }
+
+                for (JSONWriter.Feature jsonFeature : jsonTypeAnnotation.serializeFeatures()) {
+                    beanMetadata.writerFeatures |= jsonFeature.mask;
+                }
+
+                beanMetadata.namingStrategy =
+                        jsonTypeAnnotation.naming().name();
+
+                String[] ignoredProperties = jsonTypeAnnotation.ignores();
+                if (ignoredProperties.length > 0) {
+                    beanMetadata.ignores = ignoredProperties;
+                }
+
+                String[] includedProperties = jsonTypeAnnotation.includes();
+                if (includedProperties.length > 0) {
+                    beanMetadata.includes = includedProperties;
+                }
+
+                String[] propertyOrder = jsonTypeAnnotation.orders();
+                if (propertyOrder.length > 0) {
+                    beanMetadata.orders = propertyOrder;
+                }
+
+                Class<?> customSerializer = jsonTypeAnnotation.serializer();
+                if (ObjectWriter.class.isAssignableFrom(customSerializer)) {
+                    beanMetadata.serializer = customSerializer;
+                }
+
+                Class<? extends Filter>[] serializerFilters = jsonTypeAnnotation.serializeFilters();
+                if (serializerFilters.length != 0) {
+                    beanMetadata.serializeFilters = serializerFilters;
+                }
+
+                String formatPattern = jsonTypeAnnotation.format();
+                if (!formatPattern.isEmpty()) {
+                    beanMetadata.format = formatPattern;
+                }
+
+                String localeTag = jsonTypeAnnotation.locale();
+                if (!localeTag.isEmpty()) {
+                    String[] formatParts = localeTag.split("_");
+                    if (formatParts.length == 2) {
+                        beanMetadata.locale = new Locale(formatParts[0], formatParts[1]);
+                    }
+                }
+
+                if (!jsonTypeAnnotation.alphabetic()) {
+                    beanMetadata.alphabetic = false;
+                }
+
+                if (jsonTypeAnnotation.writeEnumAsJavaBean()) {
+                    beanMetadata.writeEnumAsJavaBean = true;
+                }
+            } else if (legacyJsonType != null) {
+                final Annotation ann = legacyJsonType;
+                BeanUtils.annotationMethods(legacyJsonType.annotationType(), methodRef -> BeanUtils.processJSONType1x(beanMetadata, ann, methodRef));
+            }
+
+            if (beanMetadata.seeAlso != null && beanMetadata.seeAlso.length != 0
+                    && (beanMetadata.typeName == null || beanMetadata.typeName.length() == 0)) {
+                for (Class relatedClass : beanMetadata.seeAlso) {
+                    if (relatedClass == targetClass) {
+                        beanMetadata.typeName = targetClass.getSimpleName();
+                        break;
+                    }
+                }
+            }
+        }
+
+        @Override
+        public void getFieldInfo(BeanInfo beanMetadata, FieldInfo fieldMeta, Class targetClass, Field targetField) {
+            if (targetClass != null) {
+                Class mixInClass = writerProviderInstance.mixInCache.get(targetClass);
+
+                if (mixInClass != null && mixInClass != targetClass) {
+                    Field mixInMemberField = null;
+                    try {
+                        mixInMemberField = mixInClass.getDeclaredField(targetField.getName());
+                    } catch (Exception suppressedException) {
+                    }
+
+                    if (mixInMemberField != null) {
+                        getFieldInfo(beanMetadata, fieldMeta, mixInClass, mixInMemberField);
+                    }
+                }
+            }
+
+            Class fieldMixInClass = writerProviderInstance.mixInCache.get(targetField.getType());
+            if (fieldMixInClass != null) {
+                fieldMeta.fieldClassMixIn = true;
+            }
+
+            int fieldModifiers = targetField.getModifiers();
+            boolean transientFlag = Modifier.isTransient(fieldModifiers);
+            if (transientFlag) {
+                fieldMeta.ignore = true;
+            }
+
+            JSONField jsonFieldAnnotation = null;
+            Annotation[] foundAnnotations = getAnnotations(targetField);
+            for (Annotation ann : foundAnnotations) {
+                Class<? extends Annotation> annClass = ann.annotationType();
+                if (jsonFieldAnnotation == null) {
+                    jsonFieldAnnotation = findAnnotation(ann, JSONField.class);
+                    if (jsonFieldAnnotation == ann) {
+                        continue;
+                    }
+                }
+
+                String annTypeName = annClass.getName();
+                boolean enableJacksonAnnotation = JSONFactory.isUseJacksonAnnotation();
+                switch (annTypeName) {
+                    case "com.fasterxml.jackson.annotation.JsonIgnore":
+                    case "com.alibaba.fastjson2.adapter.jackson.annotation.JsonIgnore":
+                        if (enableJacksonAnnotation) {
+                            processJacksonJsonIgnore(fieldMeta, ann);
+                        }
+                        break;
+                    case "com.fasterxml.jackson.annotation.JsonAnyGetter":
+                    case "com.alibaba.fastjson2.adapter.jackson.annotation.JsonAnyGetter":
+                        if (enableJacksonAnnotation) {
+                            fieldMeta.features |= FieldInfo.UNWRAPPED_MASK;
+                        }
+                        break;
+                    case "com.fasterxml.jackson.annotation.JsonValue":
+                    case "com.alibaba.fastjson2.adapter.jackson.annotation.JsonValue":
+                        if (enableJacksonAnnotation) {
+                            fieldMeta.features |= FieldInfo.VALUE_MASK;
+                        }
+                        break;
+                    case "com.fasterxml.jackson.annotation.JsonRawValue":
+                    case "com.alibaba.fastjson2.adapter.jackson.annotation.JsonRawValue":
+                        if (enableJacksonAnnotation) {
+                            fieldMeta.features |= FieldInfo.RAW_VALUE_MASK;
+                        }
+                        break;
+                    case "com.alibaba.fastjson.annotation.JSONField":
+                        processJsonFieldAnnotation(fieldMeta, ann);
+                        break;
+                    case "com.fasterxml.jackson.annotation.JsonProperty":
+                    case "com.alibaba.fastjson2.adapter.jackson.annotation.JsonProperty":
+                        if (enableJacksonAnnotation) {
+                            processJsonPropertyAnnotation(fieldMeta, ann);
+                        }
+                        break;
+                    case "com.fasterxml.jackson.annotation.JsonFormat":
+                    case "com.alibaba.fastjson2.adapter.jackson.annotation.JsonFormat":
+                        if (enableJacksonAnnotation) {
+                            processJacksonJsonFormat(fieldMeta, ann);
+                        }
+                        break;
+                    case "com.fasterxml.jackson.annotation.JsonInclude":
+                    case "com.alibaba.fastjson2.adapter.jackson.annotation.JsonInclude":
+                        if (enableJacksonAnnotation) {
+                            processJacksonJsonInclude(beanMetadata, ann);
+                        }
+                        break;
+                    case "com.alibaba.fastjson2.adapter.jackson.databind.annotation.JsonSerialize":
+                    case "com.fasterxml.jackson.databind.annotation.JsonSerialize":
+                        if (enableJacksonAnnotation) {
+                            processJsonSerializeAnnotation(fieldMeta, ann);
+                        }
+                        break;
+                    case "com.google.gson.annotations.SerializedName":
+                        processGsonSerializedName(fieldMeta, ann);
+                        break;
+                    default:
+                        break;
+                }
+            }
+
+            if (jsonFieldAnnotation == null) {
+                return;
+            }
+
+            populateFieldInfo(fieldMeta, jsonFieldAnnotation);
+
+            Class customWriterClass = jsonFieldAnnotation.writeUsing();
+            if (ObjectWriter.class.isAssignableFrom(customWriterClass)) {
+                fieldMeta.writeUsing = customWriterClass;
+            }
+
+            Class customSerializerClass = jsonFieldAnnotation.serializeUsing();
+            if (ObjectWriter.class.isAssignableFrom(customSerializerClass)) {
+                fieldMeta.writeUsing = customSerializerClass;
+            }
+
+            if (jsonFieldAnnotation.jsonDirect()) {
+                fieldMeta.features |= FieldInfo.RAW_VALUE_MASK;
+            }
+
+            if ((fieldMeta.features & JSONWriter.Feature.WriteNonStringValueAsString.mask) != 0
+                    && !String.class.equals(targetField.getType())
+                    && fieldMeta.writeUsing == null
+            ) {
+                fieldMeta.writeUsing = ObjectWriterImplToString.class;
+            }
+        }
+
+        private void processJacksonJsonSubTypesAnnotation(BeanInfo beanMetadata, Annotation ann) {
+            Class<? extends Annotation> annClassRef = ann.getClass();
+            BeanUtils.annotationMethods(annClassRef, mapper -> {
+                String typeName = mapper.getName();
+                try {
+                    Object procResult = mapper.invoke(ann);
+                    if ("value".equals(typeName)) {
+                        Annotation[] annotationValues = (Annotation[]) procResult;
+                        if (annotationValues.length != 0) {
+                            beanMetadata.seeAlso = new Class[annotationValues.length];
+                            beanMetadata.seeAlsoNames = new String[annotationValues.length];
+                            for (int index = 0; index < annotationValues.length; index++) {
+                                Annotation entry = annotationValues[index];
+                                processJacksonJsonSubTypesType(beanMetadata, index, entry);
+                            }
+                        }
+                    }
+                } catch (Throwable suppressedException) {
+                    // ignored
+                }
+            });
+        }
+
+        private void processJsonSerializeAnnotation(BeanInfo beanMetadata, Annotation ann) {
+            Class<? extends Annotation> annClassRef = ann.getClass();
+            BeanUtils.annotationMethods(annClassRef, mapper -> {
+                String typeName = mapper.getName();
+                try {
+                    Object procResult = mapper.invoke(ann);
+                    switch (typeName) {
+                        case "using": {
+                            Class usingClass = resolveUsing((Class) procResult);
+                            if (usingClass != null) {
+                                beanMetadata.serializer = usingClass;
+                            }
+                            break;
+                        }
+                        case "keyUsing":
+                            Class keySerializerClass = resolveUsing((Class) procResult);
+                            if (keySerializerClass != null) {
+                                beanMetadata.serializer = keySerializerClass;
+                            }
+                            break;
+                        default:
+                            break;
+                    }
+                } catch (Throwable suppressedException) {
+                    // ignored
+                }
+            });
+        }
+
+        private Class resolveUsing(Class procResult) {
+            String usingClassName = procResult.getName();
+            String defaultClassName = "com.fasterxml.jackson.databind.JsonSerializer$None";
+            if (!defaultClassName.equals(usingClassName)
+                    && ObjectWriter.class.isAssignableFrom(procResult)
+            ) {
+                return procResult;
+            }
+
+            if ("com.fasterxml.jackson.databind.ser.std.ToStringSerializer".equals(usingClassName)) {
+                return ObjectWriterImplToString.class;
+            }
+            return null;
+        }
+
+        private void handleJacksonJsonTypeInfo(BeanInfo beanMetadata, Annotation ann) {
+            Class<? extends Annotation> annClassRef = ann.getClass();
+            BeanUtils.annotationMethods(annClassRef, mapper -> {
+                String typeName = mapper.getName();
+                try {
+                    Object procResult = mapper.invoke(ann);
+                    if ("property".equals(typeName)) {
+                        String annotationValues = (String) procResult;
+                        if (!annotationValues.isEmpty()) {
+                            beanMetadata.typeKey = annotationValues;
+                            beanMetadata.writerFeatures |= JSONWriter.Feature.WriteClassName.mask;
+                        }
+                    }
+                } catch (Throwable suppressedException) {
+                    // ignored
+                }
+            });
+        }
+
+        private void processJsonPropertyOrderAnnotation(BeanInfo beanMetadata, Annotation ann) {
+            Class<? extends Annotation> annClassRef = ann.getClass();
+            BeanUtils.annotationMethods(annClassRef, mapper -> {
+                String typeName = mapper.getName();
+                try {
+                    Object procResult = mapper.invoke(ann);
+                    if ("value".equals(typeName)) {
+                        String[] annotationValues = (String[]) procResult;
+                        if (annotationValues.length != 0) {
+                            beanMetadata.orders = annotationValues;
+                        }
+                    }
+                } catch (Throwable suppressedException) {
+                    // ignored
+                }
+            });
+        }
+
+        private void processJsonSerializeAnnotation(FieldInfo fieldMeta, Annotation ann) {
+            Class<? extends Annotation> annClassRef = ann.getClass();
+            BeanUtils.annotationMethods(annClassRef, mapper -> {
+                String typeName = mapper.getName();
+                try {
+                    Object procResult = mapper.invoke(ann);
+                    switch (typeName) {
+                        case "using":
+                            Class usingClass = resolveUsing((Class) procResult);
+                            if (usingClass != null) {
+                                fieldMeta.writeUsing = usingClass;
+                            }
+                            break;
+                        case "keyUsing":
+                            Class keySerializerClass = resolveUsing((Class) procResult);
+                            if (keySerializerClass != null) {
+                                fieldMeta.keyUsing = keySerializerClass;
+                            }
+                            break;
+                        case "valueUsing":
+                            Class valueHandlerClass = resolveUsing((Class) procResult);
+                            if (valueHandlerClass != null) {
+                                fieldMeta.valueUsing = valueHandlerClass;
+                            }
+                            break;
+                        default:
+                            break;
+                    }
+                } catch (Throwable suppressedException) {
+                    // ignored
+                }
+            });
+        }
+
+        private void processJsonPropertyAnnotation(FieldInfo fieldMeta, Annotation ann) {
+            Class<? extends Annotation> annClassRef = ann.getClass();
+            BeanUtils.annotationMethods(annClassRef, mapper -> {
+                String typeName = mapper.getName();
+                try {
+                    Object procResult = mapper.invoke(ann);
+                    switch (typeName) {
+                        case "value":
+                            String annotationValues = (String) procResult;
+                            if (!annotationValues.isEmpty()) {
+                                fieldMeta.fieldName = annotationValues;
+                            }
+                            break;
+                        case "access": {
+                            String accessMode = ((Enum) procResult).name();
+                            fieldMeta.ignore = "WRITE_ONLY".equals(accessMode);
+                            break;
+                        }
+                        default:
+                            break;
+                    }
+                } catch (Throwable suppressedException) {
+                    // ignored
+                }
+            });
+        }
+
+        private void processJsonIgnoreProperties(BeanInfo beanMetadata, Annotation ann) {
+            Class<? extends Annotation> annClassRef = ann.getClass();
+            BeanUtils.annotationMethods(annClassRef, mapper -> {
+                String typeName = mapper.getName();
+                try {
+                    Object procResult = mapper.invoke(ann);
+                    if ("value".equals(typeName)) {
+                        String[] annotationValues = (String[]) procResult;
+                        if (annotationValues.length != 0) {
+                            beanMetadata.ignores = annotationValues;
+                        }
+                    }
+                } catch (Throwable suppressedException) {
+                    // ignored
+                }
+            });
+        }
+
+        private void processJsonFieldAnnotation(FieldInfo fieldMeta, Annotation ann) {
+            Class<? extends Annotation> annClassRef = ann.getClass();
+            BeanUtils.annotationMethods(annClassRef, mapper -> {
+                String typeName = mapper.getName();
+                try {
+                    Object procResult = mapper.invoke(ann);
+                    switch (typeName) {
+                        case "name": {
+                            String annotationValues = (String) procResult;
+                            if (!annotationValues.isEmpty()) {
+                                fieldMeta.fieldName = annotationValues;
+                            }
+                            break;
+                        }
+                        case "format": {
+                            normalizeJsonFieldFormat(fieldMeta, (String) procResult);
+                            break;
+                        }
+                        case "label": {
+                            String annotationValues = (String) procResult;
+                            if (!annotationValues.isEmpty()) {
+                                fieldMeta.label = annotationValues;
+                            }
+                            break;
+                        }
+                        case "defaultValue": {
+                            String annotationValues = (String) procResult;
+                            if (!annotationValues.isEmpty()) {
+                                fieldMeta.defaultValue = annotationValues;
+                            }
+                            break;
+                        }
+                        case "ordinal": {
+                            int orderIndex = (Integer) procResult;
+                            if (orderIndex != 0) {
+                                fieldMeta.ordinal = orderIndex;
+                            }
+                            break;
+                        }
+                        case "serialize": {
+                            boolean shouldSerialize = (Boolean) procResult;
+                            if (!shouldSerialize) {
+                                fieldMeta.ignore = true;
+                            }
+                            break;
+                        }
+                        case "unwrapped": {
+                            if ((Boolean) procResult) {
+                                fieldMeta.features |= FieldInfo.UNWRAPPED_MASK;
+                            }
+                            break;
+                        }
+                        case "serialzeFeatures": {
+                            Enum[] featureFlags = (Enum[]) procResult;
+                            applyFeaturesToFieldInfo(fieldMeta, featureFlags);
+                            break;
+                        }
+                        case "serializeUsing": {
+                            Class customWriterClass = (Class) procResult;
+                            if (ObjectWriter.class.isAssignableFrom(customWriterClass)) {
+                                fieldMeta.writeUsing = customWriterClass;
+                            }
+                            break;
+                        }
+                        case "jsonDirect": {
+                            Boolean directJsonFlag = (Boolean) procResult;
+                            if (directJsonFlag) {
+                                fieldMeta.features |= FieldInfo.RAW_VALUE_MASK;
+                            }
+                            break;
+                        }
+                        default:
+                            break;
+                    }
+                } catch (Throwable suppressedException) {
+                    // ignored
+                }
+            });
+        }
+
+        private void applyFeaturesToFieldInfo(FieldInfo fieldMeta, Enum[] featureFlags) {
+            for (Enum jsonFeature : featureFlags) {
+                switch (jsonFeature.name()) {
+                    case "UseISO8601DateFormat":
+                        fieldMeta.format = "iso8601";
+                        break;
+                    case "WriteMapNullValue":
+                        fieldMeta.features |= JSONWriter.Feature.WriteNulls.mask;
+                        break;
+                    case "WriteNullListAsEmpty":
+                        fieldMeta.features |= JSONWriter.Feature.WriteNullListAsEmpty.mask;
+                        break;
+                    case "WriteNullStringAsEmpty":
+                        fieldMeta.features |= JSONWriter.Feature.WriteNullStringAsEmpty.mask;
+                        break;
+                    case "WriteNullNumberAsZero":
+                        fieldMeta.features |= JSONWriter.Feature.WriteNullNumberAsZero.mask;
+                        break;
+                    case "WriteNullBooleanAsFalse":
+                        fieldMeta.features |= JSONWriter.Feature.WriteNullBooleanAsFalse.mask;
+                        break;
+                    case "BrowserCompatible":
+                        fieldMeta.features |= JSONWriter.Feature.BrowserCompatible.mask;
+                        break;
+                    case "WriteClassName":
+                        fieldMeta.features |= JSONWriter.Feature.WriteClassName.mask;
+                        break;
+                    case "WriteNonStringValueAsString":
+                        fieldMeta.features |= JSONWriter.Feature.WriteNonStringValueAsString.mask;
+                        break;
+                    case "WriteEnumUsingToString":
+                        fieldMeta.features |= JSONWriter.Feature.WriteEnumUsingToString.mask;
+                        break;
+                    case "NotWriteRootClassName":
+                        fieldMeta.features |= JSONWriter.Feature.NotWriteRootClassName.mask;
+                        break;
+                    case "IgnoreErrorGetter":
+                        fieldMeta.features |= JSONWriter.Feature.IgnoreErrorGetter.mask;
+                        break;
+                    case "WriteBigDecimalAsPlain":
+                        fieldMeta.features |= JSONWriter.Feature.WriteBigDecimalAsPlain.mask;
+                        break;
+                    default:
+                        break;
+                }
+            }
+        }
+
+        @Override
+        public void getFieldInfo(BeanInfo beanMetadata, FieldInfo fieldMeta, Class targetClass, Method methodRef) {
+            Class mixInClass = writerProviderInstance.mixInCache.get(targetClass);
+            String procMethodName = methodRef.getName();
+
+            if ("getTargetSql".equals(procMethodName)) {
+                if (targetClass != null
+                        && targetClass.getName().startsWith("com.baomidou.mybatisplus.")
+                ) {
+                    fieldMeta.features |= JSONWriter.Feature.IgnoreErrorGetter.mask;
+                }
+            }
+
+            if (mixInClass != null && mixInClass != targetClass) {
+                Method mixInRefMethod = null;
+                try {
+                    mixInRefMethod = mixInClass.getDeclaredMethod(procMethodName, methodRef.getParameterTypes());
+                } catch (Exception suppressedException) {
+                }
+
+                if (mixInRefMethod != null) {
+                    getFieldInfo(beanMetadata, fieldMeta, mixInClass, mixInRefMethod);
+                }
+            }
+
+            Class fieldMixInClass = writerProviderInstance.mixInCache.get(methodRef.getReturnType());
+            if (fieldMixInClass != null) {
+                fieldMeta.fieldClassMixIn = true;
+            }
+
+            if (JDKUtils.CLASS_TRANSIENT != null && methodRef.getAnnotation(JDKUtils.CLASS_TRANSIENT) != null) {
+                fieldMeta.ignore = true;
+            }
+
+            if (targetClass != null) {
+                Class parentClass = targetClass.getSuperclass();
+                Method superMethod = BeanUtils.getMethod(parentClass, methodRef);
+                boolean shouldIgnore = fieldMeta.ignore;
+                if (superMethod != null) {
+                    getFieldInfo(beanMetadata, fieldMeta, parentClass, superMethod);
+                    int superMethodModifiers = superMethod.getModifiers();
+                    if (shouldIgnore != fieldMeta.ignore
+                            && !Modifier.isAbstract(superMethodModifiers)
+                            && !superMethod.equals(methodRef)
+                    ) {
+                        fieldMeta.ignore = shouldIgnore;
+                    }
+                }
+
+                Class[] implementedInterfaces = targetClass.getInterfaces();
+                for (Class interfaceClass : implementedInterfaces) {
+                    Method ifaceMethod = BeanUtils.getMethod(interfaceClass, methodRef);
+                    if (ifaceMethod != null) {
+                        getFieldInfo(beanMetadata, fieldMeta, parentClass, ifaceMethod);
+                    }
+                }
+            }
+
+            Annotation[] foundAnnotations = getAnnotations(methodRef);
+            processFieldAnnotations(fieldMeta, foundAnnotations);
+
+            if (!targetClass.getName().startsWith("java.lang") && !BeanUtils.isRecord(targetClass)) {
+                Field associatedField = getField(targetClass, methodRef);
+                if (associatedField != null) {
+                    fieldMeta.features |= FieldInfo.FIELD_MASK;
+                    getFieldInfo(beanMetadata, fieldMeta, targetClass, associatedField);
+                }
+            }
+
+            if (beanMetadata.kotlin
+                    && beanMetadata.creatorConstructor != null
+                    && beanMetadata.createParameterNames != null
+            ) {
+                String propName = BeanUtils.getterName(methodRef, beanMetadata.kotlin, null);
+                for (int index = 0; index < beanMetadata.createParameterNames.length; index++) {
+                    if (propName.equals(beanMetadata.createParameterNames[index])) {
+                        Annotation[][] creatorParamAnnotations
+                                = beanMetadata.creatorConstructor.getParameterAnnotations();
+                        if (index < creatorParamAnnotations.length) {
+                            Annotation[] paramAnnotations = creatorParamAnnotations[index];
+                            processFieldAnnotations(fieldMeta, paramAnnotations);
+                            break;
+                        }
+                    }
+                }
+            }
+        }
+
+        private void processFieldAnnotations(FieldInfo fieldMeta, Annotation[] foundAnnotations) {
+            for (Annotation ann : foundAnnotations) {
+                Class<? extends Annotation> annClass = ann.annotationType();
+                JSONField jsonFieldAnnotation = findAnnotation(ann, JSONField.class);
+                if (Objects.nonNull(jsonFieldAnnotation)) {
+                    populateFieldInfo(fieldMeta, jsonFieldAnnotation);
+                    continue;
+                }
+
+                if (annClass == JSONCompiler.class) {
+                    JSONCompiler jsonCompiler = (JSONCompiler) ann;
+                    if (jsonCompiler.value() == JSONCompiler.CompilerOption.LAMBDA) {
+                        fieldMeta.features |= FieldInfo.JIT;
+                    }
+                }
+
+                boolean enableJacksonAnnotation = JSONFactory.isUseJacksonAnnotation();
+                String annTypeName = annClass.getName();
+                switch (annTypeName) {
+                    case "com.fasterxml.jackson.annotation.JsonIgnore":
+                    case "com.alibaba.fastjson2.adapter.jackson.annotation.JsonIgnore":
+                        if (enableJacksonAnnotation) {
+                            processJacksonJsonIgnore(fieldMeta, ann);
+                        }
+                        break;
+                    case "com.fasterxml.jackson.annotation.JsonAnyGetter":
+                    case "com.alibaba.fastjson2.adapter.jackson.annotation.JsonAnyGetter":
+                        if (enableJacksonAnnotation) {
+                            fieldMeta.features |= FieldInfo.UNWRAPPED_MASK;
+                        }
+                        break;
+                    case "com.alibaba.fastjson.annotation.JSONField":
+                        processJsonFieldAnnotation(fieldMeta, ann);
+                        break;
+                    case "java.beans.Transient":
+                        fieldMeta.ignore = true;
+                        fieldMeta.isTransient = true;
+                        break;
+                    case "com.alibaba.fastjson2.adapter.jackson.annotation.JsonProperty":
+                    case "com.fasterxml.jackson.annotation.JsonProperty": {
+                        if (enableJacksonAnnotation) {
+                            processJsonPropertyAnnotation(fieldMeta, ann);
+                        }
+                        break;
+                    }
+                    case "com.fasterxml.jackson.annotation.JsonFormat":
+                    case "com.alibaba.fastjson2.adapter.jackson.annotation.JsonFormat":
+                        if (enableJacksonAnnotation) {
+                            processJacksonJsonFormat(fieldMeta, ann);
+                        }
+                        break;
+                    case "com.fasterxml.jackson.annotation.JsonValue":
+                    case "com.alibaba.fastjson2.adapter.jackson.annotation.JsonValue":
+                        if (enableJacksonAnnotation) {
+                            fieldMeta.features |= FieldInfo.VALUE_MASK;
+                        }
+                        break;
+                    case "com.fasterxml.jackson.annotation.JsonRawValue":
+                    case "com.alibaba.fastjson2.adapter.jackson.annotation.JsonRawValue":
+                        if (enableJacksonAnnotation) {
+                            fieldMeta.features |= FieldInfo.RAW_VALUE_MASK;
+                        }
+                        break;
+                    case "com.alibaba.fastjson2.adapter.jackson.databind.annotation.JsonSerialize":
+                    case "com.fasterxml.jackson.databind.annotation.JsonSerialize":
+                        if (enableJacksonAnnotation) {
+                            processJsonSerializeAnnotation(fieldMeta, ann);
+                        }
+                        break;
+                    default:
+                        break;
+                }
+            }
+        }
+
+        /**
+         * load {@link JSONField} into {@link FieldInfo} params
+         *
+         * @param fieldMeta Java Field Info
+         * @param jsonFieldAnnotation {@link JSONField} JSON Field Info
+         */
+        private void populateFieldInfo(FieldInfo fieldMeta, JSONField jsonFieldAnnotation) {
+            String fieldJsonName = jsonFieldAnnotation.name();
+            if (!fieldJsonName.isEmpty()) {
+                fieldMeta.fieldName = fieldJsonName;
+            }
+
+            String defaultVal = jsonFieldAnnotation.defaultValue();
+            if (!defaultVal.isEmpty()) {
+                fieldMeta.defaultValue = defaultVal;
+            }
+
+            normalizeJsonFieldFormat(fieldMeta, jsonFieldAnnotation.format());
+
+            String fieldLabel = jsonFieldAnnotation.label();
+            if (!fieldLabel.isEmpty()) {
+                fieldMeta.label = fieldLabel;
+            }
+
+            if (!fieldMeta.ignore) {
+                fieldMeta.ignore = !jsonFieldAnnotation.serialize();
+            }
+
+            if (jsonFieldAnnotation.unwrapped()) {
+                fieldMeta.features |= FieldInfo.UNWRAPPED_MASK;
+            }
+
+            for (JSONWriter.Feature jsonFeature : jsonFieldAnnotation.serializeFeatures()) {
+                fieldMeta.features |= jsonFeature.mask;
+            }
+
+            int orderIndex = jsonFieldAnnotation.ordinal();
+            if (orderIndex != 0) {
+                fieldMeta.ordinal = orderIndex;
+            }
+
+            if (jsonFieldAnnotation.value()) {
+                fieldMeta.features |= FieldInfo.VALUE_MASK;
+            }
+
+            if (jsonFieldAnnotation.jsonDirect()) {
+                fieldMeta.features |= FieldInfo.RAW_VALUE_MASK;
+            }
+
+            Class customSerializerClass = jsonFieldAnnotation.serializeUsing();
+            if (ObjectWriter.class.isAssignableFrom(customSerializerClass)) {
+                fieldMeta.writeUsing = customSerializerClass;
+            }
+        }
+
+        /**
+         * load {@link JSONField} format params into FieldInfo
+         *
+         * @param fieldMeta Java Field Info
+         * @param fieldFormat {@link JSONField} format params
+         */
+        private void normalizeJsonFieldFormat(FieldInfo fieldMeta, String fieldFormat) {
+            if (!fieldFormat.isEmpty()) {
+                fieldFormat = fieldFormat.trim();
+
+                if (fieldFormat.indexOf('T') != -1 && !fieldFormat.contains("'T'")) {
+                    fieldFormat = fieldFormat.replaceAll("T", "'T'");
+                }
+
+                if (!fieldFormat.isEmpty()) {
+                    fieldMeta.format = fieldFormat;
+                }
+            }
+        }
+    }
+
+    ObjectWriter getExternalObjectWriter(String targetClassName, Class targetClass) {
+        switch (targetClassName) {
+            case "java.sql.Time":
+                return JdbcSupport.createTimeWriter(null);
+            case "java.sql.Timestamp":
+                return JdbcSupport.createTimestampWriter(targetClass, null);
+            case "org.joda.time.chrono.GregorianChronology":
+                return JodaSupport.createGregorianChronologyWriter(targetClass);
+            case "org.joda.time.chrono.ISOChronology":
+                return JodaSupport.createISOChronologyWriter(targetClass);
+            case "org.joda.time.LocalDate":
+                return JodaSupport.createLocalDateWriter(targetClass, null);
+            case "org.joda.time.LocalDateTime":
+                return JodaSupport.createLocalDateTimeWriter(targetClass, null);
+            case "org.joda.time.DateTime":
+                return new ObjectWriterImplZonedDateTime(null, null, new JodaSupport.DateTime2ZDT());
+            default:
+                if (JdbcSupport.isClob(targetClass)) {
+                    return JdbcSupport.createClobWriter(targetClass);
+                }
+                return null;
+        }
+    }
+
+    @Override
+    public ObjectWriter getObjectWriter(Type targetType, Class targetClass) {
+        if (targetType == String.class) {
+            return ObjectWriterImplString.INSTANCE;
+        }
+
+        if (targetClass == null) {
+            if (targetType instanceof Class) {
+                targetClass = (Class) targetType;
+            } else {
+                targetClass = TypeUtils.getMapping(targetType);
+            }
+        }
+
+        String targetClassName = targetClass.getName();
+        ObjectWriter externalWriter = getExternalObjectWriter(targetClassName, targetClass);
+        if (externalWriter != null) {
+            return externalWriter;
+        }
+
+        switch (targetClassName) {
+            case "com.google.common.collect.AbstractMapBasedMultimap$RandomAccessWrappedList":
+            case "com.google.common.collect.AbstractMapBasedMultimap$WrappedSet":
+                return null;
+            case "org.javamoney.moneta.internal.JDKCurrencyAdapter":
+                return ObjectWriterImplToString.INSTANCE;
+            case "com.fasterxml.jackson.databind.node.ObjectNode":
+                return ObjectWriterImplToString.DIRECT;
+            case "org.javamoney.moneta.Money":
+                return MoneySupport.createMonetaryAmountWriter();
+            case "org.javamoney.moneta.spi.DefaultNumberValue":
+                return MoneySupport.createNumberValueWriter();
+            case "net.sf.json.JSONNull":
+            case "java.net.Inet4Address":
+            case "java.net.Inet6Address":
+            case "java.net.InetSocketAddress":
+            case "java.text.SimpleDateFormat":
+            case "java.util.regex.Pattern":
+            case "com.fasterxml.jackson.databind.node.ArrayNode":
+                return ObjectWriterMisc.INSTANCE;
+            case "org.apache.commons.lang3.tuple.Pair":
+            case "org.apache.commons.lang3.tuple.MutablePair":
+            case "org.apache.commons.lang3.tuple.ImmutablePair":
+                return new ApacheLang3Support.PairWriter(targetClass);
+            case "com.carrotsearch.hppc.ByteArrayList":
+            case "com.carrotsearch.hppc.ShortArrayList":
+            case "com.carrotsearch.hppc.IntArrayList":
+            case "com.carrotsearch.hppc.IntHashSet":
+            case "com.carrotsearch.hppc.LongArrayList":
+            case "com.carrotsearch.hppc.LongHashSet":
+            case "com.carrotsearch.hppc.CharArrayList":
+            case "com.carrotsearch.hppc.CharHashSet":
+            case "com.carrotsearch.hppc.FloatArrayList":
+            case "com.carrotsearch.hppc.DoubleArrayList":
+            case "com.carrotsearch.hppc.BitSet":
+            case "gnu.trove.list.array.TByteArrayList":
+            case "gnu.trove.list.array.TCharArrayList":
+            case "gnu.trove.list.array.TShortArrayList":
+            case "gnu.trove.list.array.TIntArrayList":
+            case "gnu.trove.list.array.TLongArrayList":
+            case "gnu.trove.list.array.TFloatArrayList":
+            case "gnu.trove.list.array.TDoubleArrayList":
+            case "gnu.trove.set.hash.TByteHashSet":
+            case "gnu.trove.set.hash.TShortHashSet":
+            case "gnu.trove.set.hash.TIntHashSet":
+            case "gnu.trove.set.hash.TLongHashSet":
+            case "gnu.trove.stack.array.TByteArrayStack":
+            case "org.bson.types.Decimal128":
+                return LambdaMiscCodec.getObjectWriter(targetType, targetClass);
+            case "java.nio.HeapByteBuffer":
+            case "java.nio.DirectByteBuffer":
+                return new ObjectWriterImplInt8ValueArray(
+                        obj -> ((ByteBuffer) obj).array()
+                );
+            default:
+                break;
+        }
+
+        if (targetType instanceof ParameterizedType) {
+            ParameterizedType paramType = (ParameterizedType) targetType;
+            Type baseType = paramType.getRawType();
+            Type[] typeArguments = paramType.getActualTypeArguments();
+
+            if (baseType == List.class || baseType == ArrayList.class) {
+                if (typeArguments.length == 1
+                        && typeArguments[0] == String.class) {
+                    return ObjectWriterImplListStr.INSTANCE;
+                }
+
+                targetType = baseType;
+            }
+
+            if (Map.class.isAssignableFrom(targetClass)) {
+                return ObjectWriterImplMap.of(targetType, targetClass);
+            }
+
+            if (targetClass == Optional.class) {
+                if (typeArguments.length == 1) {
+                    return new ObjectWriterImplOptional(typeArguments[0], null, null);
+                }
+            }
+        }
+
+        if (targetType == LinkedList.class) {
+            return ObjectWriterImplList.INSTANCE;
+        }
+
+        if (targetType == ArrayList.class
+                || targetType == List.class
+                || List.class.isAssignableFrom(targetClass)) {
+            return ObjectWriterImplList.INSTANCE;
+        }
+
+        if (Collection.class.isAssignableFrom(targetClass)) {
+            return ObjectWriterImplCollection.INSTANCE;
+        }
+
+        if (isExtendedMap(targetClass)) {
+            return null;
+        }
+
+        if (Map.class.isAssignableFrom(targetClass)) {
+            return ObjectWriterImplMap.of(targetClass);
+        }
+
+        if (Map.Entry.class.isAssignableFrom(targetClass)) {
+            return ObjectWriterImplMapEntry.INSTANCE;
+        }
+
+        if (java.nio.file.Path.class.isAssignableFrom(targetClass)) {
+            return ObjectWriterImplToString.INSTANCE;
+        }
+
+        if (targetType == Integer.class) {
+            return ObjectWriterImplInt32.INSTANCE;
+        }
+
+        if (targetType == AtomicInteger.class) {
+            return ObjectWriterImplAtomicInteger.INSTANCE;
+        }
+
+        if (targetType == Byte.class) {
+            return ObjectWriterImplInt8.INSTANCE;
+        }
+
+        if (targetType == Short.class) {
+            return ObjectWriterImplInt16.INSTANCE;
+        }
+
+        if (targetType == Long.class) {
+            return ObjectWriterImplInt64.INSTANCE;
+        }
+
+        if (targetType == AtomicLong.class) {
+            return ObjectWriterImplAtomicLong.INSTANCE;
+        }
+
+        if (targetType == AtomicReference.class) {
+            return ObjectWriterImplAtomicReference.INSTANCE;
+        }
+
+        if (targetType == Float.class) {
+            return ObjectWriterImplFloat.INSTANCE;
+        }
+
+        if (targetType == Double.class) {
+            return ObjectWriterImplDouble.INSTANCE;
+        }
+
+        if (targetType == BigInteger.class) {
+            return ObjectWriterBigInteger.INSTANCE;
+        }
+
+        if (targetType == BigDecimal.class) {
+            return ObjectWriterImplBigDecimal.INSTANCE;
+        }
+
+        if (targetType == BitSet.class) {
+            return ObjectWriterImplBitSet.INSTANCE;
+        }
+
+        if (targetType == OptionalInt.class) {
+            return ObjectWriterImplOptionalInt.INSTANCE;
+        }
+
+        if (targetType == OptionalLong.class) {
+            return ObjectWriterImplOptionalLong.INSTANCE;
+        }
+
+        if (targetType == OptionalDouble.class) {
+            return ObjectWriterImplOptionalDouble.INSTANCE;
+        }
+
+        if (targetType == Optional.class) {
+            return ObjectWriterImplOptional.INSTANCE;
+        }
+
+        if (targetType == Boolean.class) {
+            return ObjectWriterImplBoolean.INSTANCE;
+        }
+
+        if (targetType == AtomicBoolean.class) {
+            return ObjectWriterImplAtomicBoolean.INSTANCE;
+        }
+
+        if (targetType == AtomicIntegerArray.class) {
+            return ObjectWriterImplAtomicIntegerArray.INSTANCE;
+        }
+
+        if (targetType == AtomicLongArray.class) {
+            return ObjectWriterImplAtomicLongArray.INSTANCE;
+        }
+
+        if (targetType == Character.class) {
+            return ObjectWriterImplCharacter.INSTANCE;
+        }
+
+        if (targetType instanceof Class) {
+            Class targetClazz = (Class) targetType;
+
+            if (TimeUnit.class.isAssignableFrom(targetClazz)) {
+                return new ObjectWriterImplEnum(null, TimeUnit.class, null, null, 0);
+            }
+
+            if (Enum.class.isAssignableFrom(targetClazz)) {
+                ObjectWriter enumSerializer = buildEnumWriter(targetClazz);
+                if (enumSerializer != null) {
+                    return enumSerializer;
+                }
+            }
+
+            if (JSONPath.class.isAssignableFrom(targetClazz)) {
+                return ObjectWriterImplToString.INSTANCE;
+            }
+
+            if (targetClazz == boolean[].class) {
+                return ObjectWriterImplBoolValueArray.INSTANCE;
+            }
+
+            if (targetClazz == char[].class) {
+                return ObjectWriterImplCharValueArray.INSTANCE;
+            }
+
+            if (targetClazz == StringBuffer.class || targetClazz == StringBuilder.class) {
+                return ObjectWriterImplToString.INSTANCE;
+            }
+
+            if (targetClazz == byte[].class) {
+                return ObjectWriterImplInt8ValueArray.INSTANCE;
+            }
+
+            if (targetClazz == short[].class) {
+                return ObjectWriterImplInt16ValueArray.INSTANCE;
+            }
+
+            if (targetClazz == int[].class) {
+                return ObjectWriterImplInt32ValueArray.INSTANCE;
+            }
+
+            if (targetClazz == long[].class) {
+                return ObjectWriterImplInt64ValueArray.INSTANCE;
+            }
+
+            if (targetClazz == float[].class) {
+                return ObjectWriterImplFloatValueArray.INSTANCE;
+            }
+
+            if (targetClazz == double[].class) {
+                return ObjectWriterImplDoubleValueArray.INSTANCE;
+            }
+
+            if (targetClazz == Byte[].class) {
+                return ObjectWriterImplInt8Array.INSTANCE;
+            }
+
+            if (targetClazz == Integer[].class) {
+                return ObjectWriterImplInt32Array.INSTANCE;
+            }
+
+            if (targetClazz == Long[].class) {
+                return ObjectWriterImplInt64Array.INSTANCE;
+            }
+
+            if (String[].class == targetClazz) {
+                return ObjectWriterImplStringArray.INSTANCE;
+            }
+
+            if (BigDecimal[].class == targetClazz) {
+                return ObjectWriterImpDecimalArray.INSTANCE;
+            }
+
+            if (Object[].class.isAssignableFrom(targetClazz)) {
+                if (targetClazz == Object[].class) {
+                    return ObjectWriterArray.INSTANCE;
+                } else {
+                    Class elementType = targetClazz.getComponentType();
+                    if (Modifier.isFinal(elementType.getModifiers())) {
+                        return new ObjectWriterArrayFinal(elementType, null);
+                    } else {
+                        return new ObjectWriterArray(elementType);
+                    }
+                }
+            }
+
+            if (targetClazz == UUID.class) {
+                return ObjectWriterImplUUID.INSTANCE;
+            }
+
+            if (targetClazz == Locale.class) {
+                return ObjectWriterImplLocale.INSTANCE;
+            }
+
+            if (targetClazz == Currency.class) {
+                return ObjectWriterImplCurrency.INSTANCE;
+            }
+
+            if (TimeZone.class.isAssignableFrom(targetClazz)) {
+                return ObjectWriterImplTimeZone.INSTANCE;
+            }
+
+            if (JSONPObject.class.isAssignableFrom(targetClazz)) {
+                return new ObjectWriterImplJSONP();
+            }
+
+            if (targetClazz == URI.class
+                    || targetClazz == URL.class
+                    || targetClazz == File.class
+                    || ZoneId.class.isAssignableFrom(targetClazz)
+                    || Charset.class.isAssignableFrom(targetClazz)) {
+                return ObjectWriterImplToString.INSTANCE;
+            }
+
+            externalWriter = getExternalObjectWriter(targetClazz.getName(), targetClazz);
+            if (externalWriter != null) {
+                return externalWriter;
+            }
+
+            BeanInfo beanMetadata = new BeanInfo();
+            Class mixInClass = writerProviderInstance.getMixIn(targetClazz);
+            if (mixInClass != null) {
+                jsonAnnotationHandler.getBeanInfo(beanMetadata, mixInClass);
+            }
+
+            if (Date.class.isAssignableFrom(targetClazz)) {
+                if (beanMetadata.format != null || beanMetadata.locale != null) {
+                    return new ObjectWriterImplDate(beanMetadata.format, beanMetadata.locale);
+                }
+
+                return ObjectWriterImplDate.INSTANCE;
+            }
+
+            if (Calendar.class.isAssignableFrom(targetClazz)) {
+                if (beanMetadata.format != null || beanMetadata.locale != null) {
+                    return new ObjectWriterImplCalendar(beanMetadata.format, beanMetadata.locale);
+                }
+
+                return ObjectWriterImplCalendar.INSTANCE;
+            }
+
+            if (ZonedDateTime.class == targetClazz) {
+                if (beanMetadata.format != null || beanMetadata.locale != null) {
+                    return new ObjectWriterImplZonedDateTime(beanMetadata.format, beanMetadata.locale);
+                }
+
+                return ObjectWriterImplZonedDateTime.INSTANCE;
+            }
+
+            if (OffsetDateTime.class == targetClazz) {
+                return ObjectWriterImplOffsetDateTime.of(beanMetadata.format, beanMetadata.locale);
+            }
+
+            if (LocalDateTime.class == targetClazz) {
+                if (beanMetadata.format != null || beanMetadata.locale != null) {
+                    return new ObjectWriterImplLocalDateTime(beanMetadata.format, beanMetadata.locale);
+                }
+
+                return ObjectWriterImplLocalDateTime.INSTANCE;
+            }
+
+            if (LocalDate.class == targetClazz) {
+                return ObjectWriterImplLocalDate.of(beanMetadata.format, beanMetadata.locale);
+            }
+
+            if (LocalTime.class == targetClazz) {
+                if (beanMetadata.format != null || beanMetadata.locale != null) {
+                    return new ObjectWriterImplLocalTime(beanMetadata.format, beanMetadata.locale);
+                }
+
+                return ObjectWriterImplLocalTime.INSTANCE;
+            }
+
+            if (OffsetTime.class == targetClazz) {
+                if (beanMetadata.format != null || beanMetadata.locale != null) {
+                    return new ObjectWriterImplOffsetTime(beanMetadata.format, beanMetadata.locale);
+                }
+
+                return ObjectWriterImplOffsetTime.INSTANCE;
+            }
+
+            if (Instant.class == targetClazz) {
+                if (beanMetadata.format != null || beanMetadata.locale != null) {
+                    return new ObjectWriterImplInstant(beanMetadata.format, beanMetadata.locale);
+                }
+
+                return ObjectWriterImplInstant.INSTANCE;
+            }
+
+            if (Duration.class == targetClazz) {
+                return ObjectWriterImplToString.INSTANCE;
+            }
+
+            if (StackTraceElement.class == targetClazz) {
+                // return createFieldWriter(null, null, fieldName, 0, 0, null, null, fieldClass, fieldClass, null, function);
+                if (stackTraceAdapter == null) {
+                    ObjectWriterCreator writerCreator = writerProviderInstance.getCreator();
+                    stackTraceAdapter = new ObjectWriterAdapter(
+                            StackTraceElement.class,
+                            null,
+                            null,
+                            0,
+                            Arrays.asList(
+                                    writerCreator.createFieldWriter(
+                                            "fileName",
+                                            String.class,
+                                            BeanUtils.getDeclaredField(StackTraceElement.class, "fileName"),
+                                            BeanUtils.getMethod(StackTraceElement.class, "getFileName"),
+                                            StackTraceElement::getFileName
+                                    ),
+                                    writerCreator.createFieldWriter(
+                                            "lineNumber",
+                                            BeanUtils.getDeclaredField(StackTraceElement.class, "lineNumber"),
+                                            BeanUtils.getMethod(StackTraceElement.class, "getLineNumber"),
+                                            StackTraceElement::getLineNumber
+                                    ),
+                                    writerCreator.createFieldWriter(
+                                            "className",
+                                            String.class,
+                                            BeanUtils.getDeclaredField(StackTraceElement.class, "declaringClass"),
+                                            BeanUtils.getMethod(StackTraceElement.class, "getClassName"),
+                                            StackTraceElement::getClassName
+                                    ),
+                                    writerCreator.createFieldWriter(
+                                            "methodName",
+                                            String.class,
+                                            BeanUtils.getDeclaredField(StackTraceElement.class, "methodName"),
+                                            BeanUtils.getMethod(StackTraceElement.class, "getMethodName"),
+                                            StackTraceElement::getMethodName
+                                    )
+                            )
+                    );
+                }
+                return stackTraceAdapter;
+            }
+
+            if (Class.class == targetClazz) {
+                return ObjectWriterImplClass.INSTANCE;
+            }
+
+            if (Method.class == targetClazz) {
+                return new ObjectWriterAdapter<>(
+                        Method.class,
+                        null,
+                        null,
+                        0,
+                        Arrays.asList(
+                                ObjectWriters.fieldWriter("declaringClass", Class.class, Method::getDeclaringClass),
+                                ObjectWriters.fieldWriter("name", String.class, Method::getName),
+                                ObjectWriters.fieldWriter("parameterTypes", Class[].class, Method::getParameterTypes)
+                        )
+                );
+            }
+
+            if (Field.class == targetClazz) {
+                return new ObjectWriterAdapter<>(
+                        Method.class,
+                        null,
+                        null,
+                        0,
+                        Arrays.asList(
+                                ObjectWriters.fieldWriter("declaringClass", Class.class, Field::getDeclaringClass),
+                                ObjectWriters.fieldWriter("name", String.class, Field::getName)
+                        )
+                );
+            }
+
+            if (ParameterizedType.class.isAssignableFrom(targetClazz)) {
+                return ObjectWriters.objectWriter(
+                        ParameterizedType.class,
+                        ObjectWriters.fieldWriter("actualTypeArguments", Type[].class, ParameterizedType::getActualTypeArguments),
+                        ObjectWriters.fieldWriter("ownerType", Type.class, ParameterizedType::getOwnerType),
+                        ObjectWriters.fieldWriter("rawType", Type.class, ParameterizedType::getRawType)
+                );
+            }
+        }
+
+        return null;
+    }
+
+    private ObjectWriter buildEnumWriter(Class enumType) {
+        if (!enumType.isEnum()) {
+            Class parentClass = enumType.getSuperclass();
+            if (parentClass.isEnum()) {
+                enumType = parentClass;
+            }
+        }
+
+        Member enumValueField = BeanUtils.getEnumValueField(enumType, writerProviderInstance);
+        if (enumValueField == null) {
+            Class mixInClass = writerProviderInstance.mixInCache.get(enumType);
+            Member mixedField = BeanUtils.getEnumValueField(mixInClass, writerProviderInstance);
+            if (mixedField instanceof Field) {
+                try {
+                    enumValueField = enumType.getField(mixedField.getName());
+                } catch (NoSuchFieldException suppressedException) {
+                }
+            } else if (mixedField instanceof Method) {
+                try {
+                    enumValueField = enumType.getMethod(mixedField.getName());
+                } catch (NoSuchMethodException suppressedException) {
+                }
+            }
+        }
+
+        BeanInfo beanMetadata = new BeanInfo();
+
+        Class[] implementedInterfaces = enumType.getInterfaces();
+        for (int index = 0; index < implementedInterfaces.length; index++) {
+            jsonAnnotationHandler.getBeanInfo(beanMetadata, implementedInterfaces[index]);
+        }
+
+        jsonAnnotationHandler.getBeanInfo(beanMetadata, enumType);
+        if (beanMetadata.writeEnumAsJavaBean) {
+            return null;
+        }
+
+        String[] annNames = BeanUtils.getEnumAnnotationNames(enumType);
+        return new ObjectWriterImplEnum(null, enumType, enumValueField, annNames, 0);
+    }
+
+    static class VoidWriter
+            implements ObjectWriter {
+        public static final VoidWriter INSTANCE = new VoidWriter();
+
+        @Override
+        public void write(JSONWriter writer, Object value, Object propName, Type type, long featureFlags) {
+        }
+    }
+}
diff --git a/core/src/main/java/com/alibaba/fastjson2/writer/FieldWriterObject.java b/core/src/main/java/com/alibaba/fastjson2/writer/FieldWriterObject.java
index b0d315368..c41528d42 100644
--- a/core/src/main/java/com/alibaba/fastjson2/writer/FieldWriterObject.java
+++ b/core/src/main/java/com/alibaba/fastjson2/writer/FieldWriterObject.java
@@ -71,7 +71,7 @@ public class FieldWriterObject<T>
     @Override
     public ObjectWriter getObjectWriter(JSONWriter jsonWriter, Class valueClass) {
         final Class initValueClass = this.initValueClass;
-        if (initValueClass == null || initObjectWriter == ObjectWriterBaseModule.VoidObjectWriter.INSTANCE) {
+        if (initValueClass == null || initObjectWriter == BaseObjectWriterModule.VoidWriter.INSTANCE) {
             return getObjectWriterVoid(jsonWriter, valueClass);
         } else {
             boolean typeMatch = initValueClass == valueClass
diff --git a/core/src/main/java/com/alibaba/fastjson2/writer/ObjectWriterBaseModule.java b/core/src/main/java/com/alibaba/fastjson2/writer/ObjectWriterBaseModule.java
deleted file mode 100644
index b921de01f..000000000
--- a/core/src/main/java/com/alibaba/fastjson2/writer/ObjectWriterBaseModule.java
+++ /dev/null
@@ -1,1514 +0,10 @@
-package com.alibaba.fastjson2.writer;
-
-import com.alibaba.fastjson2.JSONFactory;
-import com.alibaba.fastjson2.JSONPObject;
-import com.alibaba.fastjson2.JSONPath;
-import com.alibaba.fastjson2.JSONWriter;
 import com.alibaba.fastjson2.annotation.*;
-import com.alibaba.fastjson2.codec.BeanInfo;
-import com.alibaba.fastjson2.codec.FieldInfo;
-import com.alibaba.fastjson2.filter.Filter;
-import com.alibaba.fastjson2.modules.ObjectWriterAnnotationProcessor;
-import com.alibaba.fastjson2.modules.ObjectWriterModule;
-import com.alibaba.fastjson2.support.LambdaMiscCodec;
-import com.alibaba.fastjson2.support.money.MoneySupport;
 import com.alibaba.fastjson2.util.*;
 
-import java.io.File;
-import java.lang.annotation.Annotation;
 import java.lang.reflect.*;
-import java.math.BigDecimal;
-import java.math.BigInteger;
-import java.net.URI;
-import java.net.URL;
-import java.nio.ByteBuffer;
-import java.nio.charset.Charset;
 import java.time.*;
 import java.util.*;
-import java.util.concurrent.TimeUnit;
 import java.util.concurrent.atomic.*;
 
 import static com.alibaba.fastjson2.util.BeanUtils.*;
 
-public class ObjectWriterBaseModule
-        implements ObjectWriterModule {
-    static ObjectWriterAdapter STACK_TRACE_ELEMENT_WRITER;
-
-    final ObjectWriterProvider provider;
-    final WriterAnnotationProcessor annotationProcessor;
-
-    public ObjectWriterBaseModule(ObjectWriterProvider provider) {
-        this.provider = provider;
-        this.annotationProcessor = new WriterAnnotationProcessor();
-    }
-
-    @Override
-    public ObjectWriterProvider getProvider() {
-        return provider;
-    }
-
-    @Override
-    public ObjectWriterAnnotationProcessor getAnnotationProcessor() {
-        return annotationProcessor;
-    }
-
-    public class WriterAnnotationProcessor
-            implements ObjectWriterAnnotationProcessor {
-        @Override
-        public void getBeanInfo(BeanInfo beanInfo, Class objectClass) {
-            if (objectClass != null) {
-                Class superclass = objectClass.getSuperclass();
-                if (superclass != Object.class && superclass != null && superclass != Enum.class) {
-                    getBeanInfo(beanInfo, superclass);
-
-                    if (beanInfo.seeAlso != null && beanInfo.seeAlsoNames != null) {
-                        for (int i = 0; i < beanInfo.seeAlso.length; i++) {
-                            Class seeAlso = beanInfo.seeAlso[i];
-                            if (seeAlso == objectClass && i < beanInfo.seeAlsoNames.length) {
-                                String seeAlsoName = beanInfo.seeAlsoNames[i];
-                                if (seeAlsoName != null && seeAlsoName.length() != 0) {
-                                    beanInfo.typeName = seeAlsoName;
-                                    break;
-                                }
-                            }
-                        }
-                    }
-                }
-            }
-
-            Annotation jsonType1x = null;
-            JSONType jsonType = null;
-            Annotation[] annotations = getAnnotations(objectClass);
-            for (int i = 0; i < annotations.length; i++) {
-                Annotation annotation = annotations[i];
-                Class annotationType = annotation.annotationType();
-                if (jsonType == null) {
-                    jsonType = findAnnotation(annotation, JSONType.class);
-                }
-                if (jsonType == annotation) {
-                    continue;
-                }
-
-                if (annotationType == JSONCompiler.class) {
-                    JSONCompiler compiler = (JSONCompiler) annotation;
-                    if (compiler.value() == JSONCompiler.CompilerOption.LAMBDA) {
-                        beanInfo.writerFeatures |= FieldInfo.JIT;
-                    }
-                }
-
-                boolean useJacksonAnnotation = JSONFactory.isUseJacksonAnnotation();
-                switch (annotationType.getName()) {
-                    case "com.alibaba.fastjson.annotation.JSONType":
-                        jsonType1x = annotation;
-                        break;
-                    case "com.fasterxml.jackson.annotation.JsonIgnoreProperties":
-                        if (useJacksonAnnotation) {
-                            processJacksonJsonIgnoreProperties(beanInfo, annotation);
-                        }
-                        break;
-                    case "com.fasterxml.jackson.annotation.JsonPropertyOrder":
-                        if (useJacksonAnnotation) {
-                            processJacksonJsonPropertyOrder(beanInfo, annotation);
-                        }
-                        break;
-                    case "com.fasterxml.jackson.annotation.JsonFormat":
-                        if (useJacksonAnnotation) {
-                            processJacksonJsonFormat(beanInfo, annotation);
-                        }
-                        break;
-                    case "com.fasterxml.jackson.annotation.JsonInclude":
-                        if (useJacksonAnnotation) {
-                            processJacksonJsonInclude(beanInfo, annotation);
-                        }
-                        break;
-                    case "com.fasterxml.jackson.annotation.JsonTypeInfo":
-                        if (useJacksonAnnotation) {
-                            processJacksonJsonTypeInfo(beanInfo, annotation);
-                        }
-                        break;
-                    case "com.fasterxml.jackson.databind.annotation.JsonSerialize":
-                        if (useJacksonAnnotation) {
-                            processJacksonJsonSerialize(beanInfo, annotation);
-                            if (beanInfo.serializer != null && Enum.class.isAssignableFrom(objectClass)) {
-                                beanInfo.writeEnumAsJavaBean = true;
-                            }
-                        }
-                        break;
-                    case "com.fasterxml.jackson.annotation.JsonTypeName":
-                        if (useJacksonAnnotation) {
-                            processJacksonJsonTypeName(beanInfo, annotation);
-                        }
-                        break;
-                    case "com.fasterxml.jackson.annotation.JsonSubTypes":
-                        if (useJacksonAnnotation) {
-                            processJacksonJsonSubTypes(beanInfo, annotation);
-                        }
-                        break;
-                    case "kotlin.Metadata":
-                        beanInfo.kotlin = true;
-                        KotlinUtils.getConstructor(objectClass, beanInfo);
-                        break;
-                    default:
-                        break;
-                }
-            }
-
-            if (jsonType == null) {
-                Class mixInSource = provider.mixInCache.get(objectClass);
-
-                if (mixInSource != null) {
-                    beanInfo.mixIn = true;
-
-                    Annotation[] mixInAnnotations = getAnnotations(mixInSource);
-                    for (int i = 0; i < mixInAnnotations.length; i++) {
-                        Annotation annotation = mixInAnnotations[i];
-                        Class<? extends Annotation> annotationType = annotation.annotationType();
-                        jsonType = findAnnotation(annotation, JSONType.class);
-                        if (jsonType == annotation) {
-                            continue;
-                        }
-
-                        String annotationTypeName = annotationType.getName();
-                        if ("com.alibaba.fastjson.annotation.JSONType".equals(annotationTypeName)) {
-                            jsonType1x = annotation;
-                        }
-                    }
-                }
-            }
-
-            if (jsonType != null) {
-                Class<?>[] classes = jsonType.seeAlso();
-                if (classes.length != 0) {
-                    beanInfo.seeAlso = classes;
-                }
-
-                String typeKey = jsonType.typeKey();
-                if (!typeKey.isEmpty()) {
-                    beanInfo.typeKey = typeKey;
-                }
-
-                String typeName = jsonType.typeName();
-                if (!typeName.isEmpty()) {
-                    beanInfo.typeName = typeName;
-                }
-
-                for (JSONWriter.Feature feature : jsonType.serializeFeatures()) {
-                    beanInfo.writerFeatures |= feature.mask;
-                }
-
-                beanInfo.namingStrategy =
-                        jsonType.naming().name();
-
-                String[] ignores = jsonType.ignores();
-                if (ignores.length > 0) {
-                    beanInfo.ignores = ignores;
-                }
-
-                String[] includes = jsonType.includes();
-                if (includes.length > 0) {
-                    beanInfo.includes = includes;
-                }
-
-                String[] orders = jsonType.orders();
-                if (orders.length > 0) {
-                    beanInfo.orders = orders;
-                }
-
-                Class<?> serializer = jsonType.serializer();
-                if (ObjectWriter.class.isAssignableFrom(serializer)) {
-                    beanInfo.serializer = serializer;
-                }
-
-                Class<? extends Filter>[] serializeFilters = jsonType.serializeFilters();
-                if (serializeFilters.length != 0) {
-                    beanInfo.serializeFilters = serializeFilters;
-                }
-
-                String format = jsonType.format();
-                if (!format.isEmpty()) {
-                    beanInfo.format = format;
-                }
-
-                String locale = jsonType.locale();
-                if (!locale.isEmpty()) {
-                    String[] parts = locale.split("_");
-                    if (parts.length == 2) {
-                        beanInfo.locale = new Locale(parts[0], parts[1]);
-                    }
-                }
-
-                if (!jsonType.alphabetic()) {
-                    beanInfo.alphabetic = false;
-                }
-
-                if (jsonType.writeEnumAsJavaBean()) {
-                    beanInfo.writeEnumAsJavaBean = true;
-                }
-            } else if (jsonType1x != null) {
-                final Annotation annotation = jsonType1x;
-                BeanUtils.annotationMethods(jsonType1x.annotationType(), method -> BeanUtils.processJSONType1x(beanInfo, annotation, method));
-            }
-
-            if (beanInfo.seeAlso != null && beanInfo.seeAlso.length != 0
-                    && (beanInfo.typeName == null || beanInfo.typeName.length() == 0)) {
-                for (Class seeAlsoClass : beanInfo.seeAlso) {
-                    if (seeAlsoClass == objectClass) {
-                        beanInfo.typeName = objectClass.getSimpleName();
-                        break;
-                    }
-                }
-            }
-        }
-
-        @Override
-        public void getFieldInfo(BeanInfo beanInfo, FieldInfo fieldInfo, Class objectClass, Field field) {
-            if (objectClass != null) {
-                Class mixInSource = provider.mixInCache.get(objectClass);
-
-                if (mixInSource != null && mixInSource != objectClass) {
-                    Field mixInField = null;
-                    try {
-                        mixInField = mixInSource.getDeclaredField(field.getName());
-                    } catch (Exception ignored) {
-                    }
-
-                    if (mixInField != null) {
-                        getFieldInfo(beanInfo, fieldInfo, mixInSource, mixInField);
-                    }
-                }
-            }
-
-            Class fieldClassMixInSource = provider.mixInCache.get(field.getType());
-            if (fieldClassMixInSource != null) {
-                fieldInfo.fieldClassMixIn = true;
-            }
-
-            int modifiers = field.getModifiers();
-            boolean isTransient = Modifier.isTransient(modifiers);
-            if (isTransient) {
-                fieldInfo.ignore = true;
-            }
-
-            JSONField jsonField = null;
-            Annotation[] annotations = getAnnotations(field);
-            for (Annotation annotation : annotations) {
-                Class<? extends Annotation> annotationType = annotation.annotationType();
-                if (jsonField == null) {
-                    jsonField = findAnnotation(annotation, JSONField.class);
-                    if (jsonField == annotation) {
-                        continue;
-                    }
-                }
-
-                String annotationTypeName = annotationType.getName();
-                boolean useJacksonAnnotation = JSONFactory.isUseJacksonAnnotation();
-                switch (annotationTypeName) {
-                    case "com.fasterxml.jackson.annotation.JsonIgnore":
-                    case "com.alibaba.fastjson2.adapter.jackson.annotation.JsonIgnore":
-                        if (useJacksonAnnotation) {
-                            processJacksonJsonIgnore(fieldInfo, annotation);
-                        }
-                        break;
-                    case "com.fasterxml.jackson.annotation.JsonAnyGetter":
-                    case "com.alibaba.fastjson2.adapter.jackson.annotation.JsonAnyGetter":
-                        if (useJacksonAnnotation) {
-                            fieldInfo.features |= FieldInfo.UNWRAPPED_MASK;
-                        }
-                        break;
-                    case "com.fasterxml.jackson.annotation.JsonValue":
-                    case "com.alibaba.fastjson2.adapter.jackson.annotation.JsonValue":
-                        if (useJacksonAnnotation) {
-                            fieldInfo.features |= FieldInfo.VALUE_MASK;
-                        }
-                        break;
-                    case "com.fasterxml.jackson.annotation.JsonRawValue":
-                    case "com.alibaba.fastjson2.adapter.jackson.annotation.JsonRawValue":
-                        if (useJacksonAnnotation) {
-                            fieldInfo.features |= FieldInfo.RAW_VALUE_MASK;
-                        }
-                        break;
-                    case "com.alibaba.fastjson.annotation.JSONField":
-                        processJSONField1x(fieldInfo, annotation);
-                        break;
-                    case "com.fasterxml.jackson.annotation.JsonProperty":
-                    case "com.alibaba.fastjson2.adapter.jackson.annotation.JsonProperty":
-                        if (useJacksonAnnotation) {
-                            processJacksonJsonProperty(fieldInfo, annotation);
-                        }
-                        break;
-                    case "com.fasterxml.jackson.annotation.JsonFormat":
-                    case "com.alibaba.fastjson2.adapter.jackson.annotation.JsonFormat":
-                        if (useJacksonAnnotation) {
-                            processJacksonJsonFormat(fieldInfo, annotation);
-                        }
-                        break;
-                    case "com.fasterxml.jackson.annotation.JsonInclude":
-                    case "com.alibaba.fastjson2.adapter.jackson.annotation.JsonInclude":
-                        if (useJacksonAnnotation) {
-                            processJacksonJsonInclude(beanInfo, annotation);
-                        }
-                        break;
-                    case "com.alibaba.fastjson2.adapter.jackson.databind.annotation.JsonSerialize":
-                    case "com.fasterxml.jackson.databind.annotation.JsonSerialize":
-                        if (useJacksonAnnotation) {
-                            processJacksonJsonSerialize(fieldInfo, annotation);
-                        }
-                        break;
-                    case "com.google.gson.annotations.SerializedName":
-                        processGsonSerializedName(fieldInfo, annotation);
-                        break;
-                    default:
-                        break;
-                }
-            }
-
-            if (jsonField == null) {
-                return;
-            }
-
-            loadFieldInfo(fieldInfo, jsonField);
-
-            Class writeUsing = jsonField.writeUsing();
-            if (ObjectWriter.class.isAssignableFrom(writeUsing)) {
-                fieldInfo.writeUsing = writeUsing;
-            }
-
-            Class serializeUsing = jsonField.serializeUsing();
-            if (ObjectWriter.class.isAssignableFrom(serializeUsing)) {
-                fieldInfo.writeUsing = serializeUsing;
-            }
-
-            if (jsonField.jsonDirect()) {
-                fieldInfo.features |= FieldInfo.RAW_VALUE_MASK;
-            }
-
-            if ((fieldInfo.features & JSONWriter.Feature.WriteNonStringValueAsString.mask) != 0
-                    && !String.class.equals(field.getType())
-                    && fieldInfo.writeUsing == null
-            ) {
-                fieldInfo.writeUsing = ObjectWriterImplToString.class;
-            }
-        }
-
-        private void processJacksonJsonSubTypes(BeanInfo beanInfo, Annotation annotation) {
-            Class<? extends Annotation> annotationClass = annotation.getClass();
-            BeanUtils.annotationMethods(annotationClass, m -> {
-                String name = m.getName();
-                try {
-                    Object result = m.invoke(annotation);
-                    if ("value".equals(name)) {
-                        Annotation[] value = (Annotation[]) result;
-                        if (value.length != 0) {
-                            beanInfo.seeAlso = new Class[value.length];
-                            beanInfo.seeAlsoNames = new String[value.length];
-                            for (int i = 0; i < value.length; i++) {
-                                Annotation item = value[i];
-                                processJacksonJsonSubTypesType(beanInfo, i, item);
-                            }
-                        }
-                    }
-                } catch (Throwable ignored) {
-                    // ignored
-                }
-            });
-        }
-
-        private void processJacksonJsonSerialize(BeanInfo beanInfo, Annotation annotation) {
-            Class<? extends Annotation> annotationClass = annotation.getClass();
-            BeanUtils.annotationMethods(annotationClass, m -> {
-                String name = m.getName();
-                try {
-                    Object result = m.invoke(annotation);
-                    switch (name) {
-                        case "using": {
-                            Class using = processUsing((Class) result);
-                            if (using != null) {
-                                beanInfo.serializer = using;
-                            }
-                            break;
-                        }
-                        case "keyUsing":
-                            Class keyUsing = processUsing((Class) result);
-                            if (keyUsing != null) {
-                                beanInfo.serializer = keyUsing;
-                            }
-                            break;
-                        default:
-                            break;
-                    }
-                } catch (Throwable ignored) {
-                    // ignored
-                }
-            });
-        }
-
-        private Class processUsing(Class result) {
-            String usingName = result.getName();
-            String noneClassName1 = "com.fasterxml.jackson.databind.JsonSerializer$None";
-            if (!noneClassName1.equals(usingName)
-                    && ObjectWriter.class.isAssignableFrom(result)
-            ) {
-                return result;
-            }
-
-            if ("com.fasterxml.jackson.databind.ser.std.ToStringSerializer".equals(usingName)) {
-                return ObjectWriterImplToString.class;
-            }
-            return null;
-        }
-
-        private void processJacksonJsonTypeInfo(BeanInfo beanInfo, Annotation annotation) {
-            Class<? extends Annotation> annotationClass = annotation.getClass();
-            BeanUtils.annotationMethods(annotationClass, m -> {
-                String name = m.getName();
-                try {
-                    Object result = m.invoke(annotation);
-                    if ("property".equals(name)) {
-                        String value = (String) result;
-                        if (!value.isEmpty()) {
-                            beanInfo.typeKey = value;
-                            beanInfo.writerFeatures |= JSONWriter.Feature.WriteClassName.mask;
-                        }
-                    }
-                } catch (Throwable ignored) {
-                    // ignored
-                }
-            });
-        }
-
-        private void processJacksonJsonPropertyOrder(BeanInfo beanInfo, Annotation annotation) {
-            Class<? extends Annotation> annotationClass = annotation.getClass();
-            BeanUtils.annotationMethods(annotationClass, m -> {
-                String name = m.getName();
-                try {
-                    Object result = m.invoke(annotation);
-                    if ("value".equals(name)) {
-                        String[] value = (String[]) result;
-                        if (value.length != 0) {
-                            beanInfo.orders = value;
-                        }
-                    }
-                } catch (Throwable ignored) {
-                    // ignored
-                }
-            });
-        }
-
-        private void processJacksonJsonSerialize(FieldInfo fieldInfo, Annotation annotation) {
-            Class<? extends Annotation> annotationClass = annotation.getClass();
-            BeanUtils.annotationMethods(annotationClass, m -> {
-                String name = m.getName();
-                try {
-                    Object result = m.invoke(annotation);
-                    switch (name) {
-                        case "using":
-                            Class using = processUsing((Class) result);
-                            if (using != null) {
-                                fieldInfo.writeUsing = using;
-                            }
-                            break;
-                        case "keyUsing":
-                            Class keyUsing = processUsing((Class) result);
-                            if (keyUsing != null) {
-                                fieldInfo.keyUsing = keyUsing;
-                            }
-                            break;
-                        case "valueUsing":
-                            Class valueUsing = processUsing((Class) result);
-                            if (valueUsing != null) {
-                                fieldInfo.valueUsing = valueUsing;
-                            }
-                            break;
-                        default:
-                            break;
-                    }
-                } catch (Throwable ignored) {
-                    // ignored
-                }
-            });
-        }
-
-        private void processJacksonJsonProperty(FieldInfo fieldInfo, Annotation annotation) {
-            Class<? extends Annotation> annotationClass = annotation.getClass();
-            BeanUtils.annotationMethods(annotationClass, m -> {
-                String name = m.getName();
-                try {
-                    Object result = m.invoke(annotation);
-                    switch (name) {
-                        case "value":
-                            String value = (String) result;
-                            if (!value.isEmpty()) {
-                                fieldInfo.fieldName = value;
-                            }
-                            break;
-                        case "access": {
-                            String access = ((Enum) result).name();
-                            fieldInfo.ignore = "WRITE_ONLY".equals(access);
-                            break;
-                        }
-                        default:
-                            break;
-                    }
-                } catch (Throwable ignored) {
-                    // ignored
-                }
-            });
-        }
-
-        private void processJacksonJsonIgnoreProperties(BeanInfo beanInfo, Annotation annotation) {
-            Class<? extends Annotation> annotationClass = annotation.getClass();
-            BeanUtils.annotationMethods(annotationClass, m -> {
-                String name = m.getName();
-                try {
-                    Object result = m.invoke(annotation);
-                    if ("value".equals(name)) {
-                        String[] value = (String[]) result;
-                        if (value.length != 0) {
-                            beanInfo.ignores = value;
-                        }
-                    }
-                } catch (Throwable ignored) {
-                    // ignored
-                }
-            });
-        }
-
-        private void processJSONField1x(FieldInfo fieldInfo, Annotation annotation) {
-            Class<? extends Annotation> annotationClass = annotation.getClass();
-            BeanUtils.annotationMethods(annotationClass, m -> {
-                String name = m.getName();
-                try {
-                    Object result = m.invoke(annotation);
-                    switch (name) {
-                        case "name": {
-                            String value = (String) result;
-                            if (!value.isEmpty()) {
-                                fieldInfo.fieldName = value;
-                            }
-                            break;
-                        }
-                        case "format": {
-                            loadJsonFieldFormat(fieldInfo, (String) result);
-                            break;
-                        }
-                        case "label": {
-                            String value = (String) result;
-                            if (!value.isEmpty()) {
-                                fieldInfo.label = value;
-                            }
-                            break;
-                        }
-                        case "defaultValue": {
-                            String value = (String) result;
-                            if (!value.isEmpty()) {
-                                fieldInfo.defaultValue = value;
-                            }
-                            break;
-                        }
-                        case "ordinal": {
-                            int ordinal = (Integer) result;
-                            if (ordinal != 0) {
-                                fieldInfo.ordinal = ordinal;
-                            }
-                            break;
-                        }
-                        case "serialize": {
-                            boolean serialize = (Boolean) result;
-                            if (!serialize) {
-                                fieldInfo.ignore = true;
-                            }
-                            break;
-                        }
-                        case "unwrapped": {
-                            if ((Boolean) result) {
-                                fieldInfo.features |= FieldInfo.UNWRAPPED_MASK;
-                            }
-                            break;
-                        }
-                        case "serialzeFeatures": {
-                            Enum[] features = (Enum[]) result;
-                            applyFeatures(fieldInfo, features);
-                            break;
-                        }
-                        case "serializeUsing": {
-                            Class writeUsing = (Class) result;
-                            if (ObjectWriter.class.isAssignableFrom(writeUsing)) {
-                                fieldInfo.writeUsing = writeUsing;
-                            }
-                            break;
-                        }
-                        case "jsonDirect": {
-                            Boolean jsonDirect = (Boolean) result;
-                            if (jsonDirect) {
-                                fieldInfo.features |= FieldInfo.RAW_VALUE_MASK;
-                            }
-                            break;
-                        }
-                        default:
-                            break;
-                    }
-                } catch (Throwable ignored) {
-                    // ignored
-                }
-            });
-        }
-
-        private void applyFeatures(FieldInfo fieldInfo, Enum[] features) {
-            for (Enum feature : features) {
-                switch (feature.name()) {
-                    case "UseISO8601DateFormat":
-                        fieldInfo.format = "iso8601";
-                        break;
-                    case "WriteMapNullValue":
-                        fieldInfo.features |= JSONWriter.Feature.WriteNulls.mask;
-                        break;
-                    case "WriteNullListAsEmpty":
-                        fieldInfo.features |= JSONWriter.Feature.WriteNullListAsEmpty.mask;
-                        break;
-                    case "WriteNullStringAsEmpty":
-                        fieldInfo.features |= JSONWriter.Feature.WriteNullStringAsEmpty.mask;
-                        break;
-                    case "WriteNullNumberAsZero":
-                        fieldInfo.features |= JSONWriter.Feature.WriteNullNumberAsZero.mask;
-                        break;
-                    case "WriteNullBooleanAsFalse":
-                        fieldInfo.features |= JSONWriter.Feature.WriteNullBooleanAsFalse.mask;
-                        break;
-                    case "BrowserCompatible":
-                        fieldInfo.features |= JSONWriter.Feature.BrowserCompatible.mask;
-                        break;
-                    case "WriteClassName":
-                        fieldInfo.features |= JSONWriter.Feature.WriteClassName.mask;
-                        break;
-                    case "WriteNonStringValueAsString":
-                        fieldInfo.features |= JSONWriter.Feature.WriteNonStringValueAsString.mask;
-                        break;
-                    case "WriteEnumUsingToString":
-                        fieldInfo.features |= JSONWriter.Feature.WriteEnumUsingToString.mask;
-                        break;
-                    case "NotWriteRootClassName":
-                        fieldInfo.features |= JSONWriter.Feature.NotWriteRootClassName.mask;
-                        break;
-                    case "IgnoreErrorGetter":
-                        fieldInfo.features |= JSONWriter.Feature.IgnoreErrorGetter.mask;
-                        break;
-                    case "WriteBigDecimalAsPlain":
-                        fieldInfo.features |= JSONWriter.Feature.WriteBigDecimalAsPlain.mask;
-                        break;
-                    default:
-                        break;
-                }
-            }
-        }
-
-        @Override
-        public void getFieldInfo(BeanInfo beanInfo, FieldInfo fieldInfo, Class objectClass, Method method) {
-            Class mixInSource = provider.mixInCache.get(objectClass);
-            String methodName = method.getName();
-
-            if ("getTargetSql".equals(methodName)) {
-                if (objectClass != null
-                        && objectClass.getName().startsWith("com.baomidou.mybatisplus.")
-                ) {
-                    fieldInfo.features |= JSONWriter.Feature.IgnoreErrorGetter.mask;
-                }
-            }
-
-            if (mixInSource != null && mixInSource != objectClass) {
-                Method mixInMethod = null;
-                try {
-                    mixInMethod = mixInSource.getDeclaredMethod(methodName, method.getParameterTypes());
-                } catch (Exception ignored) {
-                }
-
-                if (mixInMethod != null) {
-                    getFieldInfo(beanInfo, fieldInfo, mixInSource, mixInMethod);
-                }
-            }
-
-            Class fieldClassMixInSource = provider.mixInCache.get(method.getReturnType());
-            if (fieldClassMixInSource != null) {
-                fieldInfo.fieldClassMixIn = true;
-            }
-
-            if (JDKUtils.CLASS_TRANSIENT != null && method.getAnnotation(JDKUtils.CLASS_TRANSIENT) != null) {
-                fieldInfo.ignore = true;
-            }
-
-            if (objectClass != null) {
-                Class superclass = objectClass.getSuperclass();
-                Method supperMethod = BeanUtils.getMethod(superclass, method);
-                boolean ignore = fieldInfo.ignore;
-                if (supperMethod != null) {
-                    getFieldInfo(beanInfo, fieldInfo, superclass, supperMethod);
-                    int supperMethodModifiers = supperMethod.getModifiers();
-                    if (ignore != fieldInfo.ignore
-                            && !Modifier.isAbstract(supperMethodModifiers)
-                            && !supperMethod.equals(method)
-                    ) {
-                        fieldInfo.ignore = ignore;
-                    }
-                }
-
-                Class[] interfaces = objectClass.getInterfaces();
-                for (Class anInterface : interfaces) {
-                    Method interfaceMethod = BeanUtils.getMethod(anInterface, method);
-                    if (interfaceMethod != null) {
-                        getFieldInfo(beanInfo, fieldInfo, superclass, interfaceMethod);
-                    }
-                }
-            }
-
-            Annotation[] annotations = getAnnotations(method);
-            processAnnotations(fieldInfo, annotations);
-
-            if (!objectClass.getName().startsWith("java.lang") && !BeanUtils.isRecord(objectClass)) {
-                Field methodField = getField(objectClass, method);
-                if (methodField != null) {
-                    fieldInfo.features |= FieldInfo.FIELD_MASK;
-                    getFieldInfo(beanInfo, fieldInfo, objectClass, methodField);
-                }
-            }
-
-            if (beanInfo.kotlin
-                    && beanInfo.creatorConstructor != null
-                    && beanInfo.createParameterNames != null
-            ) {
-                String fieldName = BeanUtils.getterName(method, beanInfo.kotlin, null);
-                for (int i = 0; i < beanInfo.createParameterNames.length; i++) {
-                    if (fieldName.equals(beanInfo.createParameterNames[i])) {
-                        Annotation[][] creatorConsParamAnnotations
-                                = beanInfo.creatorConstructor.getParameterAnnotations();
-                        if (i < creatorConsParamAnnotations.length) {
-                            Annotation[] parameterAnnotations = creatorConsParamAnnotations[i];
-                            processAnnotations(fieldInfo, parameterAnnotations);
-                            break;
-                        }
-                    }
-                }
-            }
-        }
-
-        private void processAnnotations(FieldInfo fieldInfo, Annotation[] annotations) {
-            for (Annotation annotation : annotations) {
-                Class<? extends Annotation> annotationType = annotation.annotationType();
-                JSONField jsonField = findAnnotation(annotation, JSONField.class);
-                if (Objects.nonNull(jsonField)) {
-                    loadFieldInfo(fieldInfo, jsonField);
-                    continue;
-                }
-
-                if (annotationType == JSONCompiler.class) {
-                    JSONCompiler compiler = (JSONCompiler) annotation;
-                    if (compiler.value() == JSONCompiler.CompilerOption.LAMBDA) {
-                        fieldInfo.features |= FieldInfo.JIT;
-                    }
-                }
-
-                boolean useJacksonAnnotation = JSONFactory.isUseJacksonAnnotation();
-                String annotationTypeName = annotationType.getName();
-                switch (annotationTypeName) {
-                    case "com.fasterxml.jackson.annotation.JsonIgnore":
-                    case "com.alibaba.fastjson2.adapter.jackson.annotation.JsonIgnore":
-                        if (useJacksonAnnotation) {
-                            processJacksonJsonIgnore(fieldInfo, annotation);
-                        }
-                        break;
-                    case "com.fasterxml.jackson.annotation.JsonAnyGetter":
-                    case "com.alibaba.fastjson2.adapter.jackson.annotation.JsonAnyGetter":
-                        if (useJacksonAnnotation) {
-                            fieldInfo.features |= FieldInfo.UNWRAPPED_MASK;
-                        }
-                        break;
-                    case "com.alibaba.fastjson.annotation.JSONField":
-                        processJSONField1x(fieldInfo, annotation);
-                        break;
-                    case "java.beans.Transient":
-                        fieldInfo.ignore = true;
-                        fieldInfo.isTransient = true;
-                        break;
-                    case "com.alibaba.fastjson2.adapter.jackson.annotation.JsonProperty":
-                    case "com.fasterxml.jackson.annotation.JsonProperty": {
-                        if (useJacksonAnnotation) {
-                            processJacksonJsonProperty(fieldInfo, annotation);
-                        }
-                        break;
-                    }
-                    case "com.fasterxml.jackson.annotation.JsonFormat":
-                    case "com.alibaba.fastjson2.adapter.jackson.annotation.JsonFormat":
-                        if (useJacksonAnnotation) {
-                            processJacksonJsonFormat(fieldInfo, annotation);
-                        }
-                        break;
-                    case "com.fasterxml.jackson.annotation.JsonValue":
-                    case "com.alibaba.fastjson2.adapter.jackson.annotation.JsonValue":
-                        if (useJacksonAnnotation) {
-                            fieldInfo.features |= FieldInfo.VALUE_MASK;
-                        }
-                        break;
-                    case "com.fasterxml.jackson.annotation.JsonRawValue":
-                    case "com.alibaba.fastjson2.adapter.jackson.annotation.JsonRawValue":
-                        if (useJacksonAnnotation) {
-                            fieldInfo.features |= FieldInfo.RAW_VALUE_MASK;
-                        }
-                        break;
-                    case "com.alibaba.fastjson2.adapter.jackson.databind.annotation.JsonSerialize":
-                    case "com.fasterxml.jackson.databind.annotation.JsonSerialize":
-                        if (useJacksonAnnotation) {
-                            processJacksonJsonSerialize(fieldInfo, annotation);
-                        }
-                        break;
-                    default:
-                        break;
-                }
-            }
-        }
-
-        /**
-         * load {@link JSONField} into {@link FieldInfo} params
-         *
-         * @param fieldInfo Java Field Info
-         * @param jsonField {@link JSONField} JSON Field Info
-         */
-        private void loadFieldInfo(FieldInfo fieldInfo, JSONField jsonField) {
-            String jsonFieldName = jsonField.name();
-            if (!jsonFieldName.isEmpty()) {
-                fieldInfo.fieldName = jsonFieldName;
-            }
-
-            String defaultValue = jsonField.defaultValue();
-            if (!defaultValue.isEmpty()) {
-                fieldInfo.defaultValue = defaultValue;
-            }
-
-            loadJsonFieldFormat(fieldInfo, jsonField.format());
-
-            String label = jsonField.label();
-            if (!label.isEmpty()) {
-                fieldInfo.label = label;
-            }
-
-            if (!fieldInfo.ignore) {
-                fieldInfo.ignore = !jsonField.serialize();
-            }
-
-            if (jsonField.unwrapped()) {
-                fieldInfo.features |= FieldInfo.UNWRAPPED_MASK;
-            }
-
-            for (JSONWriter.Feature feature : jsonField.serializeFeatures()) {
-                fieldInfo.features |= feature.mask;
-            }
-
-            int ordinal = jsonField.ordinal();
-            if (ordinal != 0) {
-                fieldInfo.ordinal = ordinal;
-            }
-
-            if (jsonField.value()) {
-                fieldInfo.features |= FieldInfo.VALUE_MASK;
-            }
-
-            if (jsonField.jsonDirect()) {
-                fieldInfo.features |= FieldInfo.RAW_VALUE_MASK;
-            }
-
-            Class serializeUsing = jsonField.serializeUsing();
-            if (ObjectWriter.class.isAssignableFrom(serializeUsing)) {
-                fieldInfo.writeUsing = serializeUsing;
-            }
-        }
-
-        /**
-         * load {@link JSONField} format params into FieldInfo
-         *
-         * @param fieldInfo Java Field Info
-         * @param jsonFieldFormat {@link JSONField} format params
-         */
-        private void loadJsonFieldFormat(FieldInfo fieldInfo, String jsonFieldFormat) {
-            if (!jsonFieldFormat.isEmpty()) {
-                jsonFieldFormat = jsonFieldFormat.trim();
-
-                if (jsonFieldFormat.indexOf('T') != -1 && !jsonFieldFormat.contains("'T'")) {
-                    jsonFieldFormat = jsonFieldFormat.replaceAll("T", "'T'");
-                }
-
-                if (!jsonFieldFormat.isEmpty()) {
-                    fieldInfo.format = jsonFieldFormat;
-                }
-            }
-        }
-    }
-
-    ObjectWriter getExternalObjectWriter(String className, Class objectClass) {
-        switch (className) {
-            case "java.sql.Time":
-                return JdbcSupport.createTimeWriter(null);
-            case "java.sql.Timestamp":
-                return JdbcSupport.createTimestampWriter(objectClass, null);
-            case "org.joda.time.chrono.GregorianChronology":
-                return JodaSupport.createGregorianChronologyWriter(objectClass);
-            case "org.joda.time.chrono.ISOChronology":
-                return JodaSupport.createISOChronologyWriter(objectClass);
-            case "org.joda.time.LocalDate":
-                return JodaSupport.createLocalDateWriter(objectClass, null);
-            case "org.joda.time.LocalDateTime":
-                return JodaSupport.createLocalDateTimeWriter(objectClass, null);
-            case "org.joda.time.DateTime":
-                return new ObjectWriterImplZonedDateTime(null, null, new JodaSupport.DateTime2ZDT());
-            default:
-                if (JdbcSupport.isClob(objectClass)) {
-                    return JdbcSupport.createClobWriter(objectClass);
-                }
-                return null;
-        }
-    }
-
-    @Override
-    public ObjectWriter getObjectWriter(Type objectType, Class objectClass) {
-        if (objectType == String.class) {
-            return ObjectWriterImplString.INSTANCE;
-        }
-
-        if (objectClass == null) {
-            if (objectType instanceof Class) {
-                objectClass = (Class) objectType;
-            } else {
-                objectClass = TypeUtils.getMapping(objectType);
-            }
-        }
-
-        String className = objectClass.getName();
-        ObjectWriter externalObjectWriter = getExternalObjectWriter(className, objectClass);
-        if (externalObjectWriter != null) {
-            return externalObjectWriter;
-        }
-
-        switch (className) {
-            case "com.google.common.collect.AbstractMapBasedMultimap$RandomAccessWrappedList":
-            case "com.google.common.collect.AbstractMapBasedMultimap$WrappedSet":
-                return null;
-            case "org.javamoney.moneta.internal.JDKCurrencyAdapter":
-                return ObjectWriterImplToString.INSTANCE;
-            case "com.fasterxml.jackson.databind.node.ObjectNode":
-                return ObjectWriterImplToString.DIRECT;
-            case "org.javamoney.moneta.Money":
-                return MoneySupport.createMonetaryAmountWriter();
-            case "org.javamoney.moneta.spi.DefaultNumberValue":
-                return MoneySupport.createNumberValueWriter();
-            case "net.sf.json.JSONNull":
-            case "java.net.Inet4Address":
-            case "java.net.Inet6Address":
-            case "java.net.InetSocketAddress":
-            case "java.text.SimpleDateFormat":
-            case "java.util.regex.Pattern":
-            case "com.fasterxml.jackson.databind.node.ArrayNode":
-                return ObjectWriterMisc.INSTANCE;
-            case "org.apache.commons.lang3.tuple.Pair":
-            case "org.apache.commons.lang3.tuple.MutablePair":
-            case "org.apache.commons.lang3.tuple.ImmutablePair":
-                return new ApacheLang3Support.PairWriter(objectClass);
-            case "com.carrotsearch.hppc.ByteArrayList":
-            case "com.carrotsearch.hppc.ShortArrayList":
-            case "com.carrotsearch.hppc.IntArrayList":
-            case "com.carrotsearch.hppc.IntHashSet":
-            case "com.carrotsearch.hppc.LongArrayList":
-            case "com.carrotsearch.hppc.LongHashSet":
-            case "com.carrotsearch.hppc.CharArrayList":
-            case "com.carrotsearch.hppc.CharHashSet":
-            case "com.carrotsearch.hppc.FloatArrayList":
-            case "com.carrotsearch.hppc.DoubleArrayList":
-            case "com.carrotsearch.hppc.BitSet":
-            case "gnu.trove.list.array.TByteArrayList":
-            case "gnu.trove.list.array.TCharArrayList":
-            case "gnu.trove.list.array.TShortArrayList":
-            case "gnu.trove.list.array.TIntArrayList":
-            case "gnu.trove.list.array.TLongArrayList":
-            case "gnu.trove.list.array.TFloatArrayList":
-            case "gnu.trove.list.array.TDoubleArrayList":
-            case "gnu.trove.set.hash.TByteHashSet":
-            case "gnu.trove.set.hash.TShortHashSet":
-            case "gnu.trove.set.hash.TIntHashSet":
-            case "gnu.trove.set.hash.TLongHashSet":
-            case "gnu.trove.stack.array.TByteArrayStack":
-            case "org.bson.types.Decimal128":
-                return LambdaMiscCodec.getObjectWriter(objectType, objectClass);
-            case "java.nio.HeapByteBuffer":
-            case "java.nio.DirectByteBuffer":
-                return new ObjectWriterImplInt8ValueArray(
-                        o -> ((ByteBuffer) o).array()
-                );
-            default:
-                break;
-        }
-
-        if (objectType instanceof ParameterizedType) {
-            ParameterizedType parameterizedType = (ParameterizedType) objectType;
-            Type rawType = parameterizedType.getRawType();
-            Type[] actualTypeArguments = parameterizedType.getActualTypeArguments();
-
-            if (rawType == List.class || rawType == ArrayList.class) {
-                if (actualTypeArguments.length == 1
-                        && actualTypeArguments[0] == String.class) {
-                    return ObjectWriterImplListStr.INSTANCE;
-                }
-
-                objectType = rawType;
-            }
-
-            if (Map.class.isAssignableFrom(objectClass)) {
-                return ObjectWriterImplMap.of(objectType, objectClass);
-            }
-
-            if (objectClass == Optional.class) {
-                if (actualTypeArguments.length == 1) {
-                    return new ObjectWriterImplOptional(actualTypeArguments[0], null, null);
-                }
-            }
-        }
-
-        if (objectType == LinkedList.class) {
-            return ObjectWriterImplList.INSTANCE;
-        }
-
-        if (objectType == ArrayList.class
-                || objectType == List.class
-                || List.class.isAssignableFrom(objectClass)) {
-            return ObjectWriterImplList.INSTANCE;
-        }
-
-        if (Collection.class.isAssignableFrom(objectClass)) {
-            return ObjectWriterImplCollection.INSTANCE;
-        }
-
-        if (isExtendedMap(objectClass)) {
-            return null;
-        }
-
-        if (Map.class.isAssignableFrom(objectClass)) {
-            return ObjectWriterImplMap.of(objectClass);
-        }
-
-        if (Map.Entry.class.isAssignableFrom(objectClass)) {
-            return ObjectWriterImplMapEntry.INSTANCE;
-        }
-
-        if (java.nio.file.Path.class.isAssignableFrom(objectClass)) {
-            return ObjectWriterImplToString.INSTANCE;
-        }
-
-        if (objectType == Integer.class) {
-            return ObjectWriterImplInt32.INSTANCE;
-        }
-
-        if (objectType == AtomicInteger.class) {
-            return ObjectWriterImplAtomicInteger.INSTANCE;
-        }
-
-        if (objectType == Byte.class) {
-            return ObjectWriterImplInt8.INSTANCE;
-        }
-
-        if (objectType == Short.class) {
-            return ObjectWriterImplInt16.INSTANCE;
-        }
-
-        if (objectType == Long.class) {
-            return ObjectWriterImplInt64.INSTANCE;
-        }
-
-        if (objectType == AtomicLong.class) {
-            return ObjectWriterImplAtomicLong.INSTANCE;
-        }
-
-        if (objectType == AtomicReference.class) {
-            return ObjectWriterImplAtomicReference.INSTANCE;
-        }
-
-        if (objectType == Float.class) {
-            return ObjectWriterImplFloat.INSTANCE;
-        }
-
-        if (objectType == Double.class) {
-            return ObjectWriterImplDouble.INSTANCE;
-        }
-
-        if (objectType == BigInteger.class) {
-            return ObjectWriterBigInteger.INSTANCE;
-        }
-
-        if (objectType == BigDecimal.class) {
-            return ObjectWriterImplBigDecimal.INSTANCE;
-        }
-
-        if (objectType == BitSet.class) {
-            return ObjectWriterImplBitSet.INSTANCE;
-        }
-
-        if (objectType == OptionalInt.class) {
-            return ObjectWriterImplOptionalInt.INSTANCE;
-        }
-
-        if (objectType == OptionalLong.class) {
-            return ObjectWriterImplOptionalLong.INSTANCE;
-        }
-
-        if (objectType == OptionalDouble.class) {
-            return ObjectWriterImplOptionalDouble.INSTANCE;
-        }
-
-        if (objectType == Optional.class) {
-            return ObjectWriterImplOptional.INSTANCE;
-        }
-
-        if (objectType == Boolean.class) {
-            return ObjectWriterImplBoolean.INSTANCE;
-        }
-
-        if (objectType == AtomicBoolean.class) {
-            return ObjectWriterImplAtomicBoolean.INSTANCE;
-        }
-
-        if (objectType == AtomicIntegerArray.class) {
-            return ObjectWriterImplAtomicIntegerArray.INSTANCE;
-        }
-
-        if (objectType == AtomicLongArray.class) {
-            return ObjectWriterImplAtomicLongArray.INSTANCE;
-        }
-
-        if (objectType == Character.class) {
-            return ObjectWriterImplCharacter.INSTANCE;
-        }
-
-        if (objectType instanceof Class) {
-            Class clazz = (Class) objectType;
-
-            if (TimeUnit.class.isAssignableFrom(clazz)) {
-                return new ObjectWriterImplEnum(null, TimeUnit.class, null, null, 0);
-            }
-
-            if (Enum.class.isAssignableFrom(clazz)) {
-                ObjectWriter enumWriter = createEnumWriter(clazz);
-                if (enumWriter != null) {
-                    return enumWriter;
-                }
-            }
-
-            if (JSONPath.class.isAssignableFrom(clazz)) {
-                return ObjectWriterImplToString.INSTANCE;
-            }
-
-            if (clazz == boolean[].class) {
-                return ObjectWriterImplBoolValueArray.INSTANCE;
-            }
-
-            if (clazz == char[].class) {
-                return ObjectWriterImplCharValueArray.INSTANCE;
-            }
-
-            if (clazz == StringBuffer.class || clazz == StringBuilder.class) {
-                return ObjectWriterImplToString.INSTANCE;
-            }
-
-            if (clazz == byte[].class) {
-                return ObjectWriterImplInt8ValueArray.INSTANCE;
-            }
-
-            if (clazz == short[].class) {
-                return ObjectWriterImplInt16ValueArray.INSTANCE;
-            }
-
-            if (clazz == int[].class) {
-                return ObjectWriterImplInt32ValueArray.INSTANCE;
-            }
-
-            if (clazz == long[].class) {
-                return ObjectWriterImplInt64ValueArray.INSTANCE;
-            }
-
-            if (clazz == float[].class) {
-                return ObjectWriterImplFloatValueArray.INSTANCE;
-            }
-
-            if (clazz == double[].class) {
-                return ObjectWriterImplDoubleValueArray.INSTANCE;
-            }
-
-            if (clazz == Byte[].class) {
-                return ObjectWriterImplInt8Array.INSTANCE;
-            }
-
-            if (clazz == Integer[].class) {
-                return ObjectWriterImplInt32Array.INSTANCE;
-            }
-
-            if (clazz == Long[].class) {
-                return ObjectWriterImplInt64Array.INSTANCE;
-            }
-
-            if (String[].class == clazz) {
-                return ObjectWriterImplStringArray.INSTANCE;
-            }
-
-            if (BigDecimal[].class == clazz) {
-                return ObjectWriterImpDecimalArray.INSTANCE;
-            }
-
-            if (Object[].class.isAssignableFrom(clazz)) {
-                if (clazz == Object[].class) {
-                    return ObjectWriterArray.INSTANCE;
-                } else {
-                    Class componentType = clazz.getComponentType();
-                    if (Modifier.isFinal(componentType.getModifiers())) {
-                        return new ObjectWriterArrayFinal(componentType, null);
-                    } else {
-                        return new ObjectWriterArray(componentType);
-                    }
-                }
-            }
-
-            if (clazz == UUID.class) {
-                return ObjectWriterImplUUID.INSTANCE;
-            }
-
-            if (clazz == Locale.class) {
-                return ObjectWriterImplLocale.INSTANCE;
-            }
-
-            if (clazz == Currency.class) {
-                return ObjectWriterImplCurrency.INSTANCE;
-            }
-
-            if (TimeZone.class.isAssignableFrom(clazz)) {
-                return ObjectWriterImplTimeZone.INSTANCE;
-            }
-
-            if (JSONPObject.class.isAssignableFrom(clazz)) {
-                return new ObjectWriterImplJSONP();
-            }
-
-            if (clazz == URI.class
-                    || clazz == URL.class
-                    || clazz == File.class
-                    || ZoneId.class.isAssignableFrom(clazz)
-                    || Charset.class.isAssignableFrom(clazz)) {
-                return ObjectWriterImplToString.INSTANCE;
-            }
-
-            externalObjectWriter = getExternalObjectWriter(clazz.getName(), clazz);
-            if (externalObjectWriter != null) {
-                return externalObjectWriter;
-            }
-
-            BeanInfo beanInfo = new BeanInfo();
-            Class mixIn = provider.getMixIn(clazz);
-            if (mixIn != null) {
-                annotationProcessor.getBeanInfo(beanInfo, mixIn);
-            }
-
-            if (Date.class.isAssignableFrom(clazz)) {
-                if (beanInfo.format != null || beanInfo.locale != null) {
-                    return new ObjectWriterImplDate(beanInfo.format, beanInfo.locale);
-                }
-
-                return ObjectWriterImplDate.INSTANCE;
-            }
-
-            if (Calendar.class.isAssignableFrom(clazz)) {
-                if (beanInfo.format != null || beanInfo.locale != null) {
-                    return new ObjectWriterImplCalendar(beanInfo.format, beanInfo.locale);
-                }
-
-                return ObjectWriterImplCalendar.INSTANCE;
-            }
-
-            if (ZonedDateTime.class == clazz) {
-                if (beanInfo.format != null || beanInfo.locale != null) {
-                    return new ObjectWriterImplZonedDateTime(beanInfo.format, beanInfo.locale);
-                }
-
-                return ObjectWriterImplZonedDateTime.INSTANCE;
-            }
-
-            if (OffsetDateTime.class == clazz) {
-                return ObjectWriterImplOffsetDateTime.of(beanInfo.format, beanInfo.locale);
-            }
-
-            if (LocalDateTime.class == clazz) {
-                if (beanInfo.format != null || beanInfo.locale != null) {
-                    return new ObjectWriterImplLocalDateTime(beanInfo.format, beanInfo.locale);
-                }
-
-                return ObjectWriterImplLocalDateTime.INSTANCE;
-            }
-
-            if (LocalDate.class == clazz) {
-                return ObjectWriterImplLocalDate.of(beanInfo.format, beanInfo.locale);
-            }
-
-            if (LocalTime.class == clazz) {
-                if (beanInfo.format != null || beanInfo.locale != null) {
-                    return new ObjectWriterImplLocalTime(beanInfo.format, beanInfo.locale);
-                }
-
-                return ObjectWriterImplLocalTime.INSTANCE;
-            }
-
-            if (OffsetTime.class == clazz) {
-                if (beanInfo.format != null || beanInfo.locale != null) {
-                    return new ObjectWriterImplOffsetTime(beanInfo.format, beanInfo.locale);
-                }
-
-                return ObjectWriterImplOffsetTime.INSTANCE;
-            }
-
-            if (Instant.class == clazz) {
-                if (beanInfo.format != null || beanInfo.locale != null) {
-                    return new ObjectWriterImplInstant(beanInfo.format, beanInfo.locale);
-                }
-
-                return ObjectWriterImplInstant.INSTANCE;
-            }
-
-            if (Duration.class == clazz) {
-                return ObjectWriterImplToString.INSTANCE;
-            }
-
-            if (StackTraceElement.class == clazz) {
-                // return createFieldWriter(null, null, fieldName, 0, 0, null, null, fieldClass, fieldClass, null, function);
-                if (STACK_TRACE_ELEMENT_WRITER == null) {
-                    ObjectWriterCreator creator = provider.getCreator();
-                    STACK_TRACE_ELEMENT_WRITER = new ObjectWriterAdapter(
-                            StackTraceElement.class,
-                            null,
-                            null,
-                            0,
-                            Arrays.asList(
-                                    creator.createFieldWriter(
-                                            "fileName",
-                                            String.class,
-                                            BeanUtils.getDeclaredField(StackTraceElement.class, "fileName"),
-                                            BeanUtils.getMethod(StackTraceElement.class, "getFileName"),
-                                            StackTraceElement::getFileName
-                                    ),
-                                    creator.createFieldWriter(
-                                            "lineNumber",
-                                            BeanUtils.getDeclaredField(StackTraceElement.class, "lineNumber"),
-                                            BeanUtils.getMethod(StackTraceElement.class, "getLineNumber"),
-                                            StackTraceElement::getLineNumber
-                                    ),
-                                    creator.createFieldWriter(
-                                            "className",
-                                            String.class,
-                                            BeanUtils.getDeclaredField(StackTraceElement.class, "declaringClass"),
-                                            BeanUtils.getMethod(StackTraceElement.class, "getClassName"),
-                                            StackTraceElement::getClassName
-                                    ),
-                                    creator.createFieldWriter(
-                                            "methodName",
-                                            String.class,
-                                            BeanUtils.getDeclaredField(StackTraceElement.class, "methodName"),
-                                            BeanUtils.getMethod(StackTraceElement.class, "getMethodName"),
-                                            StackTraceElement::getMethodName
-                                    )
-                            )
-                    );
-                }
-                return STACK_TRACE_ELEMENT_WRITER;
-            }
-
-            if (Class.class == clazz) {
-                return ObjectWriterImplClass.INSTANCE;
-            }
-
-            if (Method.class == clazz) {
-                return new ObjectWriterAdapter<>(
-                        Method.class,
-                        null,
-                        null,
-                        0,
-                        Arrays.asList(
-                                ObjectWriters.fieldWriter("declaringClass", Class.class, Method::getDeclaringClass),
-                                ObjectWriters.fieldWriter("name", String.class, Method::getName),
-                                ObjectWriters.fieldWriter("parameterTypes", Class[].class, Method::getParameterTypes)
-                        )
-                );
-            }
-
-            if (Field.class == clazz) {
-                return new ObjectWriterAdapter<>(
-                        Method.class,
-                        null,
-                        null,
-                        0,
-                        Arrays.asList(
-                                ObjectWriters.fieldWriter("declaringClass", Class.class, Field::getDeclaringClass),
-                                ObjectWriters.fieldWriter("name", String.class, Field::getName)
-                        )
-                );
-            }
-
-            if (ParameterizedType.class.isAssignableFrom(clazz)) {
-                return ObjectWriters.objectWriter(
-                        ParameterizedType.class,
-                        ObjectWriters.fieldWriter("actualTypeArguments", Type[].class, ParameterizedType::getActualTypeArguments),
-                        ObjectWriters.fieldWriter("ownerType", Type.class, ParameterizedType::getOwnerType),
-                        ObjectWriters.fieldWriter("rawType", Type.class, ParameterizedType::getRawType)
-                );
-            }
-        }
-
-        return null;
-    }
-
-    private ObjectWriter createEnumWriter(Class enumClass) {
-        if (!enumClass.isEnum()) {
-            Class superclass = enumClass.getSuperclass();
-            if (superclass.isEnum()) {
-                enumClass = superclass;
-            }
-        }
-
-        Member valueField = BeanUtils.getEnumValueField(enumClass, provider);
-        if (valueField == null) {
-            Class mixInSource = provider.mixInCache.get(enumClass);
-            Member mixedValueField = BeanUtils.getEnumValueField(mixInSource, provider);
-            if (mixedValueField instanceof Field) {
-                try {
-                    valueField = enumClass.getField(mixedValueField.getName());
-                } catch (NoSuchFieldException ignored) {
-                }
-            } else if (mixedValueField instanceof Method) {
-                try {
-                    valueField = enumClass.getMethod(mixedValueField.getName());
-                } catch (NoSuchMethodException ignored) {
-                }
-            }
-        }
-
-        BeanInfo beanInfo = new BeanInfo();
-
-        Class[] interfaces = enumClass.getInterfaces();
-        for (int i = 0; i < interfaces.length; i++) {
-            annotationProcessor.getBeanInfo(beanInfo, interfaces[i]);
-        }
-
-        annotationProcessor.getBeanInfo(beanInfo, enumClass);
-        if (beanInfo.writeEnumAsJavaBean) {
-            return null;
-        }
-
-        String[] annotationNames = BeanUtils.getEnumAnnotationNames(enumClass);
-        return new ObjectWriterImplEnum(null, enumClass, valueField, annotationNames, 0);
-    }
-
-    static class VoidObjectWriter
-            implements ObjectWriter {
-        public static final VoidObjectWriter INSTANCE = new VoidObjectWriter();
-
-        @Override
-        public void write(JSONWriter jsonWriter, Object object, Object fieldName, Type fieldType, long features) {
-        }
-    }
-}
diff --git a/core/src/main/java/com/alibaba/fastjson2/writer/ObjectWriterCreator.java b/core/src/main/java/com/alibaba/fastjson2/writer/ObjectWriterCreator.java
index c70fcd52d..4065d94f0 100644
--- a/core/src/main/java/com/alibaba/fastjson2/writer/ObjectWriterCreator.java
+++ b/core/src/main/java/com/alibaba/fastjson2/writer/ObjectWriterCreator.java
@@ -208,7 +208,7 @@ public class ObjectWriterCreator {
         }
 
         if (writeUsingWriter == null && fieldInfo.fieldClassMixIn) {
-            writeUsingWriter = ObjectWriterBaseModule.VoidObjectWriter.INSTANCE;
+            writeUsingWriter = BaseObjectWriterModule.VoidWriter.INSTANCE;
         }
 
         if (writeUsingWriter == null) {
@@ -438,7 +438,7 @@ public class ObjectWriterCreator {
                     }
 
                     if (writeUsingWriter == null && fieldInfo.fieldClassMixIn) {
-                        writeUsingWriter = ObjectWriterBaseModule.VoidObjectWriter.INSTANCE;
+                        writeUsingWriter = BaseObjectWriterModule.VoidWriter.INSTANCE;
                     }
 
                     FieldWriter fieldWriter = null;
@@ -723,7 +723,7 @@ public class ObjectWriterCreator {
 
             FieldWriterObject objImp = new FieldWriterObject(fieldName, ordinal, features, format, label, fieldType, fieldClass, field, null);
             objImp.initValueClass = fieldClass;
-            if (initObjectWriter != ObjectWriterBaseModule.VoidObjectWriter.INSTANCE) {
+            if (initObjectWriter != BaseObjectWriterModule.VoidWriter.INSTANCE) {
                 objImp.initObjectWriter = initObjectWriter;
             }
             return objImp;
@@ -864,7 +864,7 @@ public class ObjectWriterCreator {
         if (initObjectWriter != null) {
             FieldWriterObjectMethod objMethod = new FieldWriterObjectMethod(fieldName, ordinal, features, format, label, fieldType, fieldClass, null, method);
             objMethod.initValueClass = fieldClass;
-            if (initObjectWriter != ObjectWriterBaseModule.VoidObjectWriter.INSTANCE) {
+            if (initObjectWriter != BaseObjectWriterModule.VoidWriter.INSTANCE) {
                 objMethod.initObjectWriter = initObjectWriter;
             }
             return objMethod;
diff --git a/core/src/main/java/com/alibaba/fastjson2/writer/ObjectWriterCreatorASM.java b/core/src/main/java/com/alibaba/fastjson2/writer/ObjectWriterCreatorASM.java
index 4650cc9f2..cbd41babe 100644
--- a/core/src/main/java/com/alibaba/fastjson2/writer/ObjectWriterCreatorASM.java
+++ b/core/src/main/java/com/alibaba/fastjson2/writer/ObjectWriterCreatorASM.java
@@ -300,7 +300,7 @@ public class ObjectWriterCreatorASM
                     }
 
                     if (writeUsingWriter == null && fieldInfo.fieldClassMixIn) {
-                        writeUsingWriter = ObjectWriterBaseModule.VoidObjectWriter.INSTANCE;
+                        writeUsingWriter = BaseObjectWriterModule.VoidWriter.INSTANCE;
                     }
 
                     FieldWriter fieldWriter = null;
@@ -3455,7 +3455,7 @@ public class ObjectWriterCreatorASM
                     null
             );
             objImp.initValueClass = fieldClass;
-            if (initObjectWriter != ObjectWriterBaseModule.VoidObjectWriter.INSTANCE) {
+            if (initObjectWriter != BaseObjectWriterModule.VoidWriter.INSTANCE) {
                 objImp.initObjectWriter = initObjectWriter;
             }
             return objImp;
diff --git a/core/src/main/java/com/alibaba/fastjson2/writer/ObjectWriterProvider.java b/core/src/main/java/com/alibaba/fastjson2/writer/ObjectWriterProvider.java
index 9b614ef75..ac6d52f7c 100644
--- a/core/src/main/java/com/alibaba/fastjson2/writer/ObjectWriterProvider.java
+++ b/core/src/main/java/com/alibaba/fastjson2/writer/ObjectWriterProvider.java
@@ -215,7 +215,7 @@ public class ObjectWriterProvider
     }
 
     public void init() {
-        modules.add(new ObjectWriterBaseModule(this));
+        modules.add(new BaseObjectWriterModule(this));
     }
 
     public List<ObjectWriterModule> getModules() {
 

EOF_METAMORPHIC_PATCH
git apply /home/metamorphic_base.patch
git add -A && git -c user.email='mswe-agent@metamorphic.py' -c user.name='metamorphic-transformation-patch' commit -m 'Apply `metamorphic_base_patch` transformation to base commit'


bash /home/check_git_changes.sh

./mvnw -V --no-transfer-progress -Pgen-javadoc -Pgen-dokka clean package -Dsurefire.useFile=false -Dmaven.test.skip=false -DfailIfNoTests=false || true

