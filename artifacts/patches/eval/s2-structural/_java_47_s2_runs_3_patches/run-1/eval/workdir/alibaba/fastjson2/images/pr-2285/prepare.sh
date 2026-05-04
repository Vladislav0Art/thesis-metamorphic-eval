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
diff --git a/core/src/main/java/com/alibaba/fastjson2/writer/ObjectWriterBaseModule.java b/core/src/main/java/com/alibaba/fastjson2/writer/ObjectWriterBaseModule.java
index b921de01f..c1acde992 100644
--- a/core/src/main/java/com/alibaba/fastjson2/writer/ObjectWriterBaseModule.java
+++ b/core/src/main/java/com/alibaba/fastjson2/writer/ObjectWriterBaseModule.java
@@ -37,410 +37,8 @@ public class ObjectWriterBaseModule
     final ObjectWriterProvider provider;
     final WriterAnnotationProcessor annotationProcessor;
 
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
     public class WriterAnnotationProcessor
             implements ObjectWriterAnnotationProcessor {
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
 
         private Class processUsing(Class result) {
             String usingName = result.getName();
@@ -476,17 +74,51 @@ public class ObjectWriterBaseModule
             });
         }
 
-        private void processJacksonJsonPropertyOrder(BeanInfo beanInfo, Annotation annotation) {
+        private void processJacksonJsonSubTypes(BeanInfo beanInfo, Annotation annotation) {
+            Class<? extends Annotation> annotationClass = annotation.getClass();
+            BeanUtils.annotationMethods(annotationClass, m -> {
+                String name = m.getName();
+                try {
+                    Object result = m.invoke(annotation);
+                    if ("value".equals(name)) {
+                        Annotation[] value = (Annotation[]) result;
+                        if (value.length != 0) {
+                            beanInfo.seeAlso = new Class[value.length];
+                            beanInfo.seeAlsoNames = new String[value.length];
+                            for (int i = 0; i < value.length; i++) {
+                                Annotation item = value[i];
+                                processJacksonJsonSubTypesType(beanInfo, i, item);
+                            }
+                        }
+                    }
+                } catch (Throwable ignored) {
+                    // ignored
+                }
+            });
+        }
+
+        private void processJacksonJsonSerialize(BeanInfo beanInfo, Annotation annotation) {
             Class<? extends Annotation> annotationClass = annotation.getClass();
             BeanUtils.annotationMethods(annotationClass, m -> {
                 String name = m.getName();
                 try {
                     Object result = m.invoke(annotation);
-                    if ("value".equals(name)) {
-                        String[] value = (String[]) result;
-                        if (value.length != 0) {
-                            beanInfo.orders = value;
+                    switch (name) {
+                        case "using": {
+                            Class using = processUsing((Class) result);
+                            if (using != null) {
+                                beanInfo.serializer = using;
+                            }
+                            break;
                         }
+                        case "keyUsing":
+                            Class keyUsing = processUsing((Class) result);
+                            if (keyUsing != null) {
+                                beanInfo.serializer = keyUsing;
+                            }
+                            break;
+                        default:
+                            break;
                     }
                 } catch (Throwable ignored) {
                     // ignored
@@ -528,6 +160,24 @@ public class ObjectWriterBaseModule
             });
         }
 
+        private void processJacksonJsonPropertyOrder(BeanInfo beanInfo, Annotation annotation) {
+            Class<? extends Annotation> annotationClass = annotation.getClass();
+            BeanUtils.annotationMethods(annotationClass, m -> {
+                String name = m.getName();
+                try {
+                    Object result = m.invoke(annotation);
+                    if ("value".equals(name)) {
+                        String[] value = (String[]) result;
+                        if (value.length != 0) {
+                            beanInfo.orders = value;
+                        }
+                    }
+                } catch (Throwable ignored) {
+                    // ignored
+                }
+            });
+        }
+
         private void processJacksonJsonProperty(FieldInfo fieldInfo, Annotation annotation) {
             Class<? extends Annotation> annotationClass = annotation.getClass();
             BeanUtils.annotationMethods(annotationClass, m -> {
@@ -653,52 +303,284 @@ public class ObjectWriterBaseModule
             });
         }
 
-        private void applyFeatures(FieldInfo fieldInfo, Enum[] features) {
-            for (Enum feature : features) {
-                switch (feature.name()) {
-                    case "UseISO8601DateFormat":
-                        fieldInfo.format = "iso8601";
+        private void processAnnotations(FieldInfo fieldInfo, Annotation[] annotations) {
+            for (Annotation annotation : annotations) {
+                Class<? extends Annotation> annotationType = annotation.annotationType();
+                JSONField jsonField = findAnnotation(annotation, JSONField.class);
+                if (Objects.nonNull(jsonField)) {
+                    loadFieldInfo(fieldInfo, jsonField);
+                    continue;
+                }
+
+                if (annotationType == JSONCompiler.class) {
+                    JSONCompiler compiler = (JSONCompiler) annotation;
+                    if (compiler.value() == JSONCompiler.CompilerOption.LAMBDA) {
+                        fieldInfo.features |= FieldInfo.JIT;
+                    }
+                }
+
+                boolean useJacksonAnnotation = JSONFactory.isUseJacksonAnnotation();
+                String annotationTypeName = annotationType.getName();
+                switch (annotationTypeName) {
+                    case "com.fasterxml.jackson.annotation.JsonIgnore":
+                    case "com.alibaba.fastjson2.adapter.jackson.annotation.JsonIgnore":
+                        if (useJacksonAnnotation) {
+                            processJacksonJsonIgnore(fieldInfo, annotation);
+                        }
                         break;
-                    case "WriteMapNullValue":
-                        fieldInfo.features |= JSONWriter.Feature.WriteNulls.mask;
+                    case "com.fasterxml.jackson.annotation.JsonAnyGetter":
+                    case "com.alibaba.fastjson2.adapter.jackson.annotation.JsonAnyGetter":
+                        if (useJacksonAnnotation) {
+                            fieldInfo.features |= FieldInfo.UNWRAPPED_MASK;
+                        }
                         break;
-                    case "WriteNullListAsEmpty":
-                        fieldInfo.features |= JSONWriter.Feature.WriteNullListAsEmpty.mask;
+                    case "com.alibaba.fastjson.annotation.JSONField":
+                        processJSONField1x(fieldInfo, annotation);
                         break;
-                    case "WriteNullStringAsEmpty":
-                        fieldInfo.features |= JSONWriter.Feature.WriteNullStringAsEmpty.mask;
+                    case "java.beans.Transient":
+                        fieldInfo.ignore = true;
+                        fieldInfo.isTransient = true;
                         break;
-                    case "WriteNullNumberAsZero":
-                        fieldInfo.features |= JSONWriter.Feature.WriteNullNumberAsZero.mask;
+                    case "com.alibaba.fastjson2.adapter.jackson.annotation.JsonProperty":
+                    case "com.fasterxml.jackson.annotation.JsonProperty": {
+                        if (useJacksonAnnotation) {
+                            processJacksonJsonProperty(fieldInfo, annotation);
+                        }
+                        break;
+                    }
+                    case "com.fasterxml.jackson.annotation.JsonFormat":
+                    case "com.alibaba.fastjson2.adapter.jackson.annotation.JsonFormat":
+                        if (useJacksonAnnotation) {
+                            processJacksonJsonFormat(fieldInfo, annotation);
+                        }
+                        break;
+                    case "com.fasterxml.jackson.annotation.JsonValue":
+                    case "com.alibaba.fastjson2.adapter.jackson.annotation.JsonValue":
+                        if (useJacksonAnnotation) {
+                            fieldInfo.features |= FieldInfo.VALUE_MASK;
+                        }
+                        break;
+                    case "com.fasterxml.jackson.annotation.JsonRawValue":
+                    case "com.alibaba.fastjson2.adapter.jackson.annotation.JsonRawValue":
+                        if (useJacksonAnnotation) {
+                            fieldInfo.features |= FieldInfo.RAW_VALUE_MASK;
+                        }
+                        break;
+                    case "com.alibaba.fastjson2.adapter.jackson.databind.annotation.JsonSerialize":
+                    case "com.fasterxml.jackson.databind.annotation.JsonSerialize":
+                        if (useJacksonAnnotation) {
+                            processJacksonJsonSerialize(fieldInfo, annotation);
+                        }
+                        break;
+                    default:
+                        break;
+                }
+            }
+        }
+
+        /**
+         * load {@link JSONField} format params into FieldInfo
+         *
+         * @param fieldInfo Java Field Info
+         * @param jsonFieldFormat {@link JSONField} format params
+         */
+        private void loadJsonFieldFormat(FieldInfo fieldInfo, String jsonFieldFormat) {
+            if (!jsonFieldFormat.isEmpty()) {
+                jsonFieldFormat = jsonFieldFormat.trim();
+
+                if (jsonFieldFormat.indexOf('T') != -1 && !jsonFieldFormat.contains("'T'")) {
+                    jsonFieldFormat = jsonFieldFormat.replaceAll("T", "'T'");
+                }
+
+                if (!jsonFieldFormat.isEmpty()) {
+                    fieldInfo.format = jsonFieldFormat;
+                }
+            }
+        }
+
+        /**
+         * load {@link JSONField} into {@link FieldInfo} params
+         *
+         * @param fieldInfo Java Field Info
+         * @param jsonField {@link JSONField} JSON Field Info
+         */
+        private void loadFieldInfo(FieldInfo fieldInfo, JSONField jsonField) {
+            String jsonFieldName = jsonField.name();
+            if (!jsonFieldName.isEmpty()) {
+                fieldInfo.fieldName = jsonFieldName;
+            }
+
+            String defaultValue = jsonField.defaultValue();
+            if (!defaultValue.isEmpty()) {
+                fieldInfo.defaultValue = defaultValue;
+            }
+
+            loadJsonFieldFormat(fieldInfo, jsonField.format());
+
+            String label = jsonField.label();
+            if (!label.isEmpty()) {
+                fieldInfo.label = label;
+            }
+
+            if (!fieldInfo.ignore) {
+                fieldInfo.ignore = !jsonField.serialize();
+            }
+
+            if (jsonField.unwrapped()) {
+                fieldInfo.features |= FieldInfo.UNWRAPPED_MASK;
+            }
+
+            for (JSONWriter.Feature feature : jsonField.serializeFeatures()) {
+                fieldInfo.features |= feature.mask;
+            }
+
+            int ordinal = jsonField.ordinal();
+            if (ordinal != 0) {
+                fieldInfo.ordinal = ordinal;
+            }
+
+            if (jsonField.value()) {
+                fieldInfo.features |= FieldInfo.VALUE_MASK;
+            }
+
+            if (jsonField.jsonDirect()) {
+                fieldInfo.features |= FieldInfo.RAW_VALUE_MASK;
+            }
+
+            Class serializeUsing = jsonField.serializeUsing();
+            if (ObjectWriter.class.isAssignableFrom(serializeUsing)) {
+                fieldInfo.writeUsing = serializeUsing;
+            }
+        }
+
+        @Override
+        public void getFieldInfo(BeanInfo beanInfo, FieldInfo fieldInfo, Class objectClass, Field field) {
+            if (objectClass != null) {
+                Class mixInSource = provider.mixInCache.get(objectClass);
+
+                if (mixInSource != null && mixInSource != objectClass) {
+                    Field mixInField = null;
+                    try {
+                        mixInField = mixInSource.getDeclaredField(field.getName());
+                    } catch (Exception ignored) {
+                    }
+
+                    if (mixInField != null) {
+                        getFieldInfo(beanInfo, fieldInfo, mixInSource, mixInField);
+                    }
+                }
+            }
+
+            Class fieldClassMixInSource = provider.mixInCache.get(field.getType());
+            if (fieldClassMixInSource != null) {
+                fieldInfo.fieldClassMixIn = true;
+            }
+
+            int modifiers = field.getModifiers();
+            boolean isTransient = Modifier.isTransient(modifiers);
+            if (isTransient) {
+                fieldInfo.ignore = true;
+            }
+
+            JSONField jsonField = null;
+            Annotation[] annotations = getAnnotations(field);
+            for (Annotation annotation : annotations) {
+                Class<? extends Annotation> annotationType = annotation.annotationType();
+                if (jsonField == null) {
+                    jsonField = findAnnotation(annotation, JSONField.class);
+                    if (jsonField == annotation) {
+                        continue;
+                    }
+                }
+
+                String annotationTypeName = annotationType.getName();
+                boolean useJacksonAnnotation = JSONFactory.isUseJacksonAnnotation();
+                switch (annotationTypeName) {
+                    case "com.fasterxml.jackson.annotation.JsonIgnore":
+                    case "com.alibaba.fastjson2.adapter.jackson.annotation.JsonIgnore":
+                        if (useJacksonAnnotation) {
+                            processJacksonJsonIgnore(fieldInfo, annotation);
+                        }
+                        break;
+                    case "com.fasterxml.jackson.annotation.JsonAnyGetter":
+                    case "com.alibaba.fastjson2.adapter.jackson.annotation.JsonAnyGetter":
+                        if (useJacksonAnnotation) {
+                            fieldInfo.features |= FieldInfo.UNWRAPPED_MASK;
+                        }
                         break;
-                    case "WriteNullBooleanAsFalse":
-                        fieldInfo.features |= JSONWriter.Feature.WriteNullBooleanAsFalse.mask;
+                    case "com.fasterxml.jackson.annotation.JsonValue":
+                    case "com.alibaba.fastjson2.adapter.jackson.annotation.JsonValue":
+                        if (useJacksonAnnotation) {
+                            fieldInfo.features |= FieldInfo.VALUE_MASK;
+                        }
                         break;
-                    case "BrowserCompatible":
-                        fieldInfo.features |= JSONWriter.Feature.BrowserCompatible.mask;
+                    case "com.fasterxml.jackson.annotation.JsonRawValue":
+                    case "com.alibaba.fastjson2.adapter.jackson.annotation.JsonRawValue":
+                        if (useJacksonAnnotation) {
+                            fieldInfo.features |= FieldInfo.RAW_VALUE_MASK;
+                        }
                         break;
-                    case "WriteClassName":
-                        fieldInfo.features |= JSONWriter.Feature.WriteClassName.mask;
+                    case "com.alibaba.fastjson.annotation.JSONField":
+                        processJSONField1x(fieldInfo, annotation);
                         break;
-                    case "WriteNonStringValueAsString":
-                        fieldInfo.features |= JSONWriter.Feature.WriteNonStringValueAsString.mask;
+                    case "com.fasterxml.jackson.annotation.JsonProperty":
+                    case "com.alibaba.fastjson2.adapter.jackson.annotation.JsonProperty":
+                        if (useJacksonAnnotation) {
+                            processJacksonJsonProperty(fieldInfo, annotation);
+                        }
                         break;
-                    case "WriteEnumUsingToString":
-                        fieldInfo.features |= JSONWriter.Feature.WriteEnumUsingToString.mask;
+                    case "com.fasterxml.jackson.annotation.JsonFormat":
+                    case "com.alibaba.fastjson2.adapter.jackson.annotation.JsonFormat":
+                        if (useJacksonAnnotation) {
+                            processJacksonJsonFormat(fieldInfo, annotation);
+                        }
                         break;
-                    case "NotWriteRootClassName":
-                        fieldInfo.features |= JSONWriter.Feature.NotWriteRootClassName.mask;
+                    case "com.fasterxml.jackson.annotation.JsonInclude":
+                    case "com.alibaba.fastjson2.adapter.jackson.annotation.JsonInclude":
+                        if (useJacksonAnnotation) {
+                            processJacksonJsonInclude(beanInfo, annotation);
+                        }
                         break;
-                    case "IgnoreErrorGetter":
-                        fieldInfo.features |= JSONWriter.Feature.IgnoreErrorGetter.mask;
+                    case "com.alibaba.fastjson2.adapter.jackson.databind.annotation.JsonSerialize":
+                    case "com.fasterxml.jackson.databind.annotation.JsonSerialize":
+                        if (useJacksonAnnotation) {
+                            processJacksonJsonSerialize(fieldInfo, annotation);
+                        }
                         break;
-                    case "WriteBigDecimalAsPlain":
-                        fieldInfo.features |= JSONWriter.Feature.WriteBigDecimalAsPlain.mask;
+                    case "com.google.gson.annotations.SerializedName":
+                        processGsonSerializedName(fieldInfo, annotation);
                         break;
                     default:
                         break;
                 }
             }
+
+            if (jsonField == null) {
+                return;
+            }
+
+            loadFieldInfo(fieldInfo, jsonField);
+
+            Class writeUsing = jsonField.writeUsing();
+            if (ObjectWriter.class.isAssignableFrom(writeUsing)) {
+                fieldInfo.writeUsing = writeUsing;
+            }
+
+            Class serializeUsing = jsonField.serializeUsing();
+            if (ObjectWriter.class.isAssignableFrom(serializeUsing)) {
+                fieldInfo.writeUsing = serializeUsing;
+            }
+
+            if (jsonField.jsonDirect()) {
+                fieldInfo.features |= FieldInfo.RAW_VALUE_MASK;
+            }
+
+            if ((fieldInfo.features & JSONWriter.Feature.WriteNonStringValueAsString.mask) != 0
+                    && !String.class.equals(field.getType())
+                    && fieldInfo.writeUsing == null
+            ) {
+                fieldInfo.writeUsing = ObjectWriterImplToString.class;
+            }
         }
 
         @Override
@@ -786,182 +668,276 @@ public class ObjectWriterBaseModule
                         }
                     }
                 }
-            }
-        }
+            }
+        }
+
+        @Override
+        public void getBeanInfo(BeanInfo beanInfo, Class objectClass) {
+            if (objectClass != null) {
+                Class superclass = objectClass.getSuperclass();
+                if (superclass != Object.class && superclass != null && superclass != Enum.class) {
+                    getBeanInfo(beanInfo, superclass);
+
+                    if (beanInfo.seeAlso != null && beanInfo.seeAlsoNames != null) {
+                        for (int i = 0; i < beanInfo.seeAlso.length; i++) {
+                            Class seeAlso = beanInfo.seeAlso[i];
+                            if (seeAlso == objectClass && i < beanInfo.seeAlsoNames.length) {
+                                String seeAlsoName = beanInfo.seeAlsoNames[i];
+                                if (seeAlsoName != null && seeAlsoName.length() != 0) {
+                                    beanInfo.typeName = seeAlsoName;
+                                    break;
+                                }
+                            }
+                        }
+                    }
+                }
+            }
+
+            Annotation jsonType1x = null;
+            JSONType jsonType = null;
+            Annotation[] annotations = getAnnotations(objectClass);
+            for (int i = 0; i < annotations.length; i++) {
+                Annotation annotation = annotations[i];
+                Class annotationType = annotation.annotationType();
+                if (jsonType == null) {
+                    jsonType = findAnnotation(annotation, JSONType.class);
+                }
+                if (jsonType == annotation) {
+                    continue;
+                }
+
+                if (annotationType == JSONCompiler.class) {
+                    JSONCompiler compiler = (JSONCompiler) annotation;
+                    if (compiler.value() == JSONCompiler.CompilerOption.LAMBDA) {
+                        beanInfo.writerFeatures |= FieldInfo.JIT;
+                    }
+                }
+
+                boolean useJacksonAnnotation = JSONFactory.isUseJacksonAnnotation();
+                switch (annotationType.getName()) {
+                    case "com.alibaba.fastjson.annotation.JSONType":
+                        jsonType1x = annotation;
+                        break;
+                    case "com.fasterxml.jackson.annotation.JsonIgnoreProperties":
+                        if (useJacksonAnnotation) {
+                            processJacksonJsonIgnoreProperties(beanInfo, annotation);
+                        }
+                        break;
+                    case "com.fasterxml.jackson.annotation.JsonPropertyOrder":
+                        if (useJacksonAnnotation) {
+                            processJacksonJsonPropertyOrder(beanInfo, annotation);
+                        }
+                        break;
+                    case "com.fasterxml.jackson.annotation.JsonFormat":
+                        if (useJacksonAnnotation) {
+                            processJacksonJsonFormat(beanInfo, annotation);
+                        }
+                        break;
+                    case "com.fasterxml.jackson.annotation.JsonInclude":
+                        if (useJacksonAnnotation) {
+                            processJacksonJsonInclude(beanInfo, annotation);
+                        }
+                        break;
+                    case "com.fasterxml.jackson.annotation.JsonTypeInfo":
+                        if (useJacksonAnnotation) {
+                            processJacksonJsonTypeInfo(beanInfo, annotation);
+                        }
+                        break;
+                    case "com.fasterxml.jackson.databind.annotation.JsonSerialize":
+                        if (useJacksonAnnotation) {
+                            processJacksonJsonSerialize(beanInfo, annotation);
+                            if (beanInfo.serializer != null && Enum.class.isAssignableFrom(objectClass)) {
+                                beanInfo.writeEnumAsJavaBean = true;
+                            }
+                        }
+                        break;
+                    case "com.fasterxml.jackson.annotation.JsonTypeName":
+                        if (useJacksonAnnotation) {
+                            processJacksonJsonTypeName(beanInfo, annotation);
+                        }
+                        break;
+                    case "com.fasterxml.jackson.annotation.JsonSubTypes":
+                        if (useJacksonAnnotation) {
+                            processJacksonJsonSubTypes(beanInfo, annotation);
+                        }
+                        break;
+                    case "kotlin.Metadata":
+                        beanInfo.kotlin = true;
+                        KotlinUtils.getConstructor(objectClass, beanInfo);
+                        break;
+                    default:
+                        break;
+                }
+            }
+
+            if (jsonType == null) {
+                Class mixInSource = provider.mixInCache.get(objectClass);
+
+                if (mixInSource != null) {
+                    beanInfo.mixIn = true;
+
+                    Annotation[] mixInAnnotations = getAnnotations(mixInSource);
+                    for (int i = 0; i < mixInAnnotations.length; i++) {
+                        Annotation annotation = mixInAnnotations[i];
+                        Class<? extends Annotation> annotationType = annotation.annotationType();
+                        jsonType = findAnnotation(annotation, JSONType.class);
+                        if (jsonType == annotation) {
+                            continue;
+                        }
+
+                        String annotationTypeName = annotationType.getName();
+                        if ("com.alibaba.fastjson.annotation.JSONType".equals(annotationTypeName)) {
+                            jsonType1x = annotation;
+                        }
+                    }
+                }
+            }
+
+            if (jsonType != null) {
+                Class<?>[] classes = jsonType.seeAlso();
+                if (classes.length != 0) {
+                    beanInfo.seeAlso = classes;
+                }
+
+                String typeKey = jsonType.typeKey();
+                if (!typeKey.isEmpty()) {
+                    beanInfo.typeKey = typeKey;
+                }
+
+                String typeName = jsonType.typeName();
+                if (!typeName.isEmpty()) {
+                    beanInfo.typeName = typeName;
+                }
+
+                for (JSONWriter.Feature feature : jsonType.serializeFeatures()) {
+                    beanInfo.writerFeatures |= feature.mask;
+                }
+
+                beanInfo.namingStrategy =
+                        jsonType.naming().name();
+
+                String[] ignores = jsonType.ignores();
+                if (ignores.length > 0) {
+                    beanInfo.ignores = ignores;
+                }
+
+                String[] includes = jsonType.includes();
+                if (includes.length > 0) {
+                    beanInfo.includes = includes;
+                }
+
+                String[] orders = jsonType.orders();
+                if (orders.length > 0) {
+                    beanInfo.orders = orders;
+                }
+
+                Class<?> serializer = jsonType.serializer();
+                if (ObjectWriter.class.isAssignableFrom(serializer)) {
+                    beanInfo.serializer = serializer;
+                }
+
+                Class<? extends Filter>[] serializeFilters = jsonType.serializeFilters();
+                if (serializeFilters.length != 0) {
+                    beanInfo.serializeFilters = serializeFilters;
+                }
+
+                String format = jsonType.format();
+                if (!format.isEmpty()) {
+                    beanInfo.format = format;
+                }
+
+                String locale = jsonType.locale();
+                if (!locale.isEmpty()) {
+                    String[] parts = locale.split("_");
+                    if (parts.length == 2) {
+                        beanInfo.locale = new Locale(parts[0], parts[1]);
+                    }
+                }
 
-        private void processAnnotations(FieldInfo fieldInfo, Annotation[] annotations) {
-            for (Annotation annotation : annotations) {
-                Class<? extends Annotation> annotationType = annotation.annotationType();
-                JSONField jsonField = findAnnotation(annotation, JSONField.class);
-                if (Objects.nonNull(jsonField)) {
-                    loadFieldInfo(fieldInfo, jsonField);
-                    continue;
+                if (!jsonType.alphabetic()) {
+                    beanInfo.alphabetic = false;
                 }
 
-                if (annotationType == JSONCompiler.class) {
-                    JSONCompiler compiler = (JSONCompiler) annotation;
-                    if (compiler.value() == JSONCompiler.CompilerOption.LAMBDA) {
-                        fieldInfo.features |= FieldInfo.JIT;
+                if (jsonType.writeEnumAsJavaBean()) {
+                    beanInfo.writeEnumAsJavaBean = true;
+                }
+            } else if (jsonType1x != null) {
+                final Annotation annotation = jsonType1x;
+                BeanUtils.annotationMethods(jsonType1x.annotationType(), method -> BeanUtils.processJSONType1x(beanInfo, annotation, method));
+            }
+
+            if (beanInfo.seeAlso != null && beanInfo.seeAlso.length != 0
+                    && (beanInfo.typeName == null || beanInfo.typeName.length() == 0)) {
+                for (Class seeAlsoClass : beanInfo.seeAlso) {
+                    if (seeAlsoClass == objectClass) {
+                        beanInfo.typeName = objectClass.getSimpleName();
+                        break;
                     }
                 }
+            }
+        }
 
-                boolean useJacksonAnnotation = JSONFactory.isUseJacksonAnnotation();
-                String annotationTypeName = annotationType.getName();
-                switch (annotationTypeName) {
-                    case "com.fasterxml.jackson.annotation.JsonIgnore":
-                    case "com.alibaba.fastjson2.adapter.jackson.annotation.JsonIgnore":
-                        if (useJacksonAnnotation) {
-                            processJacksonJsonIgnore(fieldInfo, annotation);
-                        }
+        private void applyFeatures(FieldInfo fieldInfo, Enum[] features) {
+            for (Enum feature : features) {
+                switch (feature.name()) {
+                    case "UseISO8601DateFormat":
+                        fieldInfo.format = "iso8601";
                         break;
-                    case "com.fasterxml.jackson.annotation.JsonAnyGetter":
-                    case "com.alibaba.fastjson2.adapter.jackson.annotation.JsonAnyGetter":
-                        if (useJacksonAnnotation) {
-                            fieldInfo.features |= FieldInfo.UNWRAPPED_MASK;
-                        }
+                    case "WriteMapNullValue":
+                        fieldInfo.features |= JSONWriter.Feature.WriteNulls.mask;
                         break;
-                    case "com.alibaba.fastjson.annotation.JSONField":
-                        processJSONField1x(fieldInfo, annotation);
+                    case "WriteNullListAsEmpty":
+                        fieldInfo.features |= JSONWriter.Feature.WriteNullListAsEmpty.mask;
                         break;
-                    case "java.beans.Transient":
-                        fieldInfo.ignore = true;
-                        fieldInfo.isTransient = true;
+                    case "WriteNullStringAsEmpty":
+                        fieldInfo.features |= JSONWriter.Feature.WriteNullStringAsEmpty.mask;
                         break;
-                    case "com.alibaba.fastjson2.adapter.jackson.annotation.JsonProperty":
-                    case "com.fasterxml.jackson.annotation.JsonProperty": {
-                        if (useJacksonAnnotation) {
-                            processJacksonJsonProperty(fieldInfo, annotation);
-                        }
+                    case "WriteNullNumberAsZero":
+                        fieldInfo.features |= JSONWriter.Feature.WriteNullNumberAsZero.mask;
                         break;
-                    }
-                    case "com.fasterxml.jackson.annotation.JsonFormat":
-                    case "com.alibaba.fastjson2.adapter.jackson.annotation.JsonFormat":
-                        if (useJacksonAnnotation) {
-                            processJacksonJsonFormat(fieldInfo, annotation);
-                        }
+                    case "WriteNullBooleanAsFalse":
+                        fieldInfo.features |= JSONWriter.Feature.WriteNullBooleanAsFalse.mask;
                         break;
-                    case "com.fasterxml.jackson.annotation.JsonValue":
-                    case "com.alibaba.fastjson2.adapter.jackson.annotation.JsonValue":
-                        if (useJacksonAnnotation) {
-                            fieldInfo.features |= FieldInfo.VALUE_MASK;
-                        }
+                    case "BrowserCompatible":
+                        fieldInfo.features |= JSONWriter.Feature.BrowserCompatible.mask;
                         break;
-                    case "com.fasterxml.jackson.annotation.JsonRawValue":
-                    case "com.alibaba.fastjson2.adapter.jackson.annotation.JsonRawValue":
-                        if (useJacksonAnnotation) {
-                            fieldInfo.features |= FieldInfo.RAW_VALUE_MASK;
-                        }
+                    case "WriteClassName":
+                        fieldInfo.features |= JSONWriter.Feature.WriteClassName.mask;
                         break;
-                    case "com.alibaba.fastjson2.adapter.jackson.databind.annotation.JsonSerialize":
-                    case "com.fasterxml.jackson.databind.annotation.JsonSerialize":
-                        if (useJacksonAnnotation) {
-                            processJacksonJsonSerialize(fieldInfo, annotation);
-                        }
+                    case "WriteNonStringValueAsString":
+                        fieldInfo.features |= JSONWriter.Feature.WriteNonStringValueAsString.mask;
+                        break;
+                    case "WriteEnumUsingToString":
+                        fieldInfo.features |= JSONWriter.Feature.WriteEnumUsingToString.mask;
+                        break;
+                    case "NotWriteRootClassName":
+                        fieldInfo.features |= JSONWriter.Feature.NotWriteRootClassName.mask;
+                        break;
+                    case "IgnoreErrorGetter":
+                        fieldInfo.features |= JSONWriter.Feature.IgnoreErrorGetter.mask;
+                        break;
+                    case "WriteBigDecimalAsPlain":
+                        fieldInfo.features |= JSONWriter.Feature.WriteBigDecimalAsPlain.mask;
                         break;
                     default:
                         break;
                 }
             }
         }
+    }
 
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
+    static class VoidObjectWriter
+            implements ObjectWriter {
+        public static final VoidObjectWriter INSTANCE = new VoidObjectWriter();
 
-                if (!jsonFieldFormat.isEmpty()) {
-                    fieldInfo.format = jsonFieldFormat;
-                }
-            }
+        @Override
+        public void write(JSONWriter jsonWriter, Object object, Object fieldName, Type fieldType, long features) {
         }
     }
 
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
+    @Override
+    public ObjectWriterProvider getProvider() {
+        return provider;
     }
 
     @Override
@@ -1462,6 +1438,35 @@ public class ObjectWriterBaseModule
         return null;
     }
 
+    ObjectWriter getExternalObjectWriter(String className, Class objectClass) {
+        switch (className) {
+            case "java.sql.Time":
+                return JdbcSupport.createTimeWriter(null);
+            case "java.sql.Timestamp":
+                return JdbcSupport.createTimestampWriter(objectClass, null);
+            case "org.joda.time.chrono.GregorianChronology":
+                return JodaSupport.createGregorianChronologyWriter(objectClass);
+            case "org.joda.time.chrono.ISOChronology":
+                return JodaSupport.createISOChronologyWriter(objectClass);
+            case "org.joda.time.LocalDate":
+                return JodaSupport.createLocalDateWriter(objectClass, null);
+            case "org.joda.time.LocalDateTime":
+                return JodaSupport.createLocalDateTimeWriter(objectClass, null);
+            case "org.joda.time.DateTime":
+                return new ObjectWriterImplZonedDateTime(null, null, new JodaSupport.DateTime2ZDT());
+            default:
+                if (JdbcSupport.isClob(objectClass)) {
+                    return JdbcSupport.createClobWriter(objectClass);
+                }
+                return null;
+        }
+    }
+
+    @Override
+    public ObjectWriterAnnotationProcessor getAnnotationProcessor() {
+        return annotationProcessor;
+    }
+
     private ObjectWriter createEnumWriter(Class enumClass) {
         if (!enumClass.isEnum()) {
             Class superclass = enumClass.getSuperclass();
@@ -1503,12 +1508,8 @@ public class ObjectWriterBaseModule
         return new ObjectWriterImplEnum(null, enumClass, valueField, annotationNames, 0);
     }
 
-    static class VoidObjectWriter
-            implements ObjectWriter {
-        public static final VoidObjectWriter INSTANCE = new VoidObjectWriter();
-
-        @Override
-        public void write(JSONWriter jsonWriter, Object object, Object fieldName, Type fieldType, long features) {
-        }
+    public ObjectWriterBaseModule(ObjectWriterProvider provider) {
+        this.provider = provider;
+        this.annotationProcessor = new WriterAnnotationProcessor();
     }
 }

EOF_METAMORPHIC_PATCH
git apply /home/metamorphic_base.patch
git add -A && git -c user.email='mswe-agent@metamorphic.py' -c user.name='metamorphic-transformation-patch' commit -m 'Apply `metamorphic_base_patch` transformation to base commit'


bash /home/check_git_changes.sh

./mvnw -V --no-transfer-progress -Pgen-javadoc -Pgen-dokka clean package -Dsurefire.useFile=false -Dmaven.test.skip=false -DfailIfNoTests=false || true

